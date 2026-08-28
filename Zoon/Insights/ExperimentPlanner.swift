import Foundation

/// Decides which experiment is worth running *next*, rather than leaving the
/// person to guess which of twenty-three behaviours to test first.
///
/// `GuidedExperiment` runs a trial once someone has chosen what to test.
/// `JournalCorrelator` finds associations in nights that already happened.
/// Neither answers the question that actually blocks people: given
/// everything already known about this person, which single question would
/// learn the most, and can they even produce the two arms it needs?
///
/// The ranking follows the same epistemic ladder as `EvidenceNotebook`. The
/// most valuable experiment is the one that promotes an existing association
/// to a tested result -- observation has already flagged something, and a
/// pre-specified trial is the only thing that can settle it. The next most
/// valuable is a behaviour logged often enough to be interesting but too
/// rarely for matched pairs to say anything, where a deliberate trial
/// creates the contrast that observation cannot. A behaviour already logged
/// heavily with nothing showing up is the least valuable: observation had
/// its chance.
///
/// **A proposal is a question, not a prediction.** Nothing here estimates
/// what the trial would find, and the copy never implies a direction. Two of
/// the three reasons a behaviour ranks highly are reasons the answer is
/// *unknown*.
enum ExperimentPlanner {

    /// Nights with at least one answered behaviour, required before any
    /// proposal is made. Below this the exposure counts are too thin to tell
    /// "they never do this" from "they have not been answering".
    static let minimumJournaledNights = 14

    /// How far back exposure is counted. Long enough to see a habit, short
    /// enough that a behaviour someone gave up months ago stops being
    /// proposed.
    static let window = 60

    /// Nights of a behaviour needed before it is a candidate at all.
    ///
    /// Proposing a trial of something someone has never once logged would be
    /// proposing they take it up -- this suggests testing what they already
    /// do, never that they start doing something.
    static let minimumExposedNights = 3

    // MARK: - Value and feasibility

    /// Why this behaviour is worth a trial. Ordered by how much a trial
    /// would add, strongest first.
    enum Value: Int, Comparable, Hashable, Sendable {
        /// Observation already flagged an association; only a pre-specified
        /// trial can settle it.
        case settlesAnAssociation = 3
        /// Logged enough to be interesting, too rarely for matched pairs.
        case createsMissingContrast = 2
        /// Logged heavily with nothing showing up. Observation had its
        /// chance; a trial is still cleaner, but it is the weakest reason.
        case confirmsAQuietResult = 1

        static func < (a: Value, b: Value) -> Bool { a.rawValue < b.rawValue }

        var reason: String {
            switch self {
            case .settlesAnAssociation:
                "Your nights already hint at something here. A planned test is the only way to know."
            case .createsMissingContrast:
                "You do this too rarely for your history to answer it. A planned test would create the comparison."
            case .confirmsAQuietResult:
                "Your history shows nothing so far. A planned test would say so more cleanly."
            }
        }
    }

    /// Whether the person's own habits already supply both arms of the
    /// trial, or whether running it means deliberately changing something.
    enum Effort: Hashable, Sendable {
        /// They already do this on some nights and not others.
        case alreadyVaries
        /// Nearly always, or nearly never. One arm has to be manufactured.
        case requiresDeliberateChange

        var note: String {
            switch self {
            case .alreadyVaries:
                "You already vary on this, so both halves should happen naturally."
            case .requiresDeliberateChange:
                "You do this on almost every night you log, so the test needs you to change it on purpose for a stretch."
            }
        }
    }

    struct Proposal: Identifiable, Hashable, Sendable {
        let tag: BehaviorTag
        let value: Value
        let effort: Effort
        let exposedNights: Int
        let unexposedNights: Int
        /// Calendar nights the trial is likely to take, inflated for how
        /// often this person actually logs.
        let estimatedNights: Int

        var id: String { tag.rawValue }

        var headline: String { "Worth testing next: \(tag.label)" }

        var sentence: String {
            "\(value.reason) \(effort.note)"
                + " Expect around \(estimatedNights) nights."
        }

        /// Travels with every proposal. Naming a question is not answering
        /// it, and the ranking is about what is *unknown*.
        var caveat: String {
            "This is a question worth asking, not a guess at the answer."
                + " Zoon has no idea yet which way this one goes."
        }
    }

    // MARK: - Planning

    /// Ranks the behaviours worth testing next, most valuable first.
    ///
    /// - Parameters:
    ///   - observations: journaled nights, most recent last.
    ///   - associatedTags: behaviours `JournalCorrelator` already flagged,
    ///     i.e. `Set(findings.map(\.tag))`. A tag appearing here is the
    ///     strongest reason to test it. Taken as a tag set rather than as
    ///     `[Finding]` because the direction and size of an association are
    ///     deliberately *not* inputs here -- a proposal ranks a question by
    ///     how open it is, never by what the answer might be.
    ///   - settledTags: raw identifiers of behaviours with a finished
    ///     experiment. Re-proposing a question the person already answered
    ///     wastes the one thing an experiment costs, which is weeks.
    static func plan(
        observations: [JournalCorrelator.Observation],
        associatedTags: Set<BehaviorTag> = [],
        settledTags: Set<String> = [],
        candidates: [BehaviorTag] = BehaviorTag.allCases,
        minimumJournaledNights: Int = minimumJournaledNights
    ) -> [Proposal] {
        let recent = observations
            .sorted { $0.date < $1.date }
            .suffix(window)
        // Nights something is actually known about, not nights with a
        // journal row. `entryOrCreate` writes a row for every day whose
        // screen was opened, so the old `isJournaled` gate counted screens
        // rather than data -- see `Observation.hasAnyExplicitAnswer`.
        let journaled = recent.filter(\.hasAnyExplicitAnswer)
        guard journaled.count >= minimumJournaledNights else { return [] }

        var proposals: [Proposal] = []
        for tag in candidates where !settledTags.contains(tag.rawValue) {
            // Counted through `exposureState` rather than `tags.contains`
            // so the planner inherits the yes/no/unknown semantics instead
            // of keeping a second copy of them that could drift.
            let exposed = journaled.filter { $0.exposureState(for: tag) == .yes }.count
            let unexposed = journaled.filter { $0.exposureState(for: tag) == .no }.count
            guard exposed >= minimumExposedNights else { continue }

            let value: Value = if associatedTags.contains(tag) {
                .settlesAnAssociation
            } else if exposed < JournalCorrelator.minimumMatchedPairs {
                .createsMissingContrast
            } else {
                .confirmsAQuietResult
            }

            proposals.append(Proposal(
                tag: tag,
                value: value,
                effort: effort(exposed: exposed, unexposed: unexposed),
                exposedNights: exposed,
                unexposedNights: unexposed,
                estimatedNights: estimatedNights(
                    journaled: journaled.count, ofRecent: recent.count
                )
            ))
        }

        // Ties break on the rarer arm -- the behaviour further from a usable
        // contrast benefits most from a deliberate trial -- and then on the
        // identifier, so the same history always produces the same order
        // rather than reshuffling between visits to the screen.
        return proposals.sorted { a, b in
            if a.value != b.value { return a.value > b.value }
            let aThin = min(a.exposedNights, a.unexposedNights)
            let bThin = min(b.exposedNights, b.unexposedNights)
            if aThin != bThin { return aThin < bThin }
            return a.tag.rawValue < b.tag.rawValue
        }
    }

    /// The single best next experiment, or `nil` when nothing qualifies.
    static func next(
        observations: [JournalCorrelator.Observation],
        associatedTags: Set<BehaviorTag> = [],
        settledTags: Set<String> = []
    ) -> Proposal? {
        plan(
            observations: observations,
            associatedTags: associatedTags,
            settledTags: settledTags
        ).first
    }

    // MARK: - Internals

    /// A behaviour on four fifths or more of logged nights (or a fifth or
    /// fewer) has one arm that will not fill itself.
    private static func effort(exposed: Int, unexposed: Int) -> Effort {
        let total = exposed + unexposed
        guard total > 0 else { return .requiresDeliberateChange }
        let share = Double(exposed) / Double(total)
        return (0.2...0.8).contains(share) ? .alreadyVaries : .requiresDeliberateChange
    }

    /// Two periods of `GuidedExperiment.minimumPeriodNights`, stretched by
    /// how often this person actually journals.
    ///
    /// Quoting the raw 14 to someone who logs every third night would be
    /// quoting a number they cannot hit: the trial needs 14 *known* nights,
    /// and unknown ones do not count toward either arm. Better to say six
    /// weeks up front than to have the trial quietly overrun.
    private static func estimatedNights(journaled: Int, ofRecent recent: Int) -> Int {
        let minimum = GuidedExperiment.minimumPeriodNights * 2
        guard recent > 0, journaled > 0 else { return minimum }
        let rate = Double(journaled) / Double(recent)
        return Int((Double(minimum) / rate).rounded())
    }
}
