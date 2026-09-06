import Foundation

/// Chooses which behaviours to put in front of someone tonight, instead of
/// showing the same twenty-three checkboxes every evening.
///
/// A fixed vocabulary is what makes the journal analysable at all -- free
/// text produces data nobody can correlate. But a fixed *display* is what
/// makes it tiring, and a tiring journal stops being filled in, which is the
/// only failure mode that actually breaks every engine downstream. The
/// vocabulary stays fixed; the nightly ask gets short.
///
/// ## The rule that shapes everything here
///
/// **The ranking must never depend on how the person slept.**
///
/// This is not a stylistic preference. If Zoon asked about alcohol more
/// often after bad nights, the journal would accumulate alcohol tags that
/// are disproportionately attached to bad nights, and `JournalCorrelator`
/// would then discover an "association" that Zoon itself manufactured by
/// choosing when to ask. Differential measurement of that kind is
/// indistinguishable from a real effect once it is in the data, and no
/// amount of downstream statistics can undo it.
///
/// So this takes exposure history, an active experiment and the person's own
/// pinned selection -- and deliberately takes no sleep outcome at all. There
/// is no `SleepNightFeatures` parameter, no recovery score, no sleep
/// performance. The absence is the safeguard: the bias cannot be introduced
/// later by someone wiring up one more input, because there is nowhere to
/// wire it.
enum AdaptiveJournal {

    /// Default length of the *ranked list* `prompts` returns.
    ///
    /// Not how many questions get asked. The nightly ask is one question --
    /// see `question(observations:...)`, which takes the top of this ranking
    /// and may decide the honest number tonight is zero. This constant only
    /// bounds the ranking itself, which stays useful at length for testing
    /// the ordering and for any surface that wants to see more than the
    /// single winner.
    static let rankedListSize = 6

    /// How far back exposure is counted.
    static let window = 60

    /// How close to `JournalCorrelator.minimumMatchedPairs` a behaviour's
    /// thinner arm must be for one more night to plausibly unlock a finding.
    static let nearlyAnswerableGap = 3

    // MARK: - Reasons

    /// Why this behaviour made tonight's list. Ordered by priority.
    enum Reason: Int, Comparable, Hashable, Sendable {
        /// A trial is running on it. Adherence data *is* the trial, so this
        /// outranks everything -- a missed night is a hole in the result.
        case underExperiment = 4
        /// The person explicitly chose to track it. Their stated intent
        /// outranks anything inferred about them.
        case pinnedByUser = 3
        /// The thinner arm is a few nights short of what the matched-pair
        /// engine needs. Tonight's answer might be the one that unlocks it.
        case nearlyAnswerable = 2
        /// Seen, but nowhere near often enough to compare. More nights of
        /// it -- not a subtler analysis -- are what this one needs.
        case barelySeen = 1
        /// Logged enough to be routine. Included only to fill the list.
        case routine = 0

        static func < (a: Reason, b: Reason) -> Bool { a.rawValue < b.rawValue }

        /// Shown to the person so the list never looks arbitrary. None of
        /// these mention sleep quality, because none of them depend on it.
        var note: String {
            switch self {
            case .underExperiment: "You're testing this right now."
            case .pinnedByUser: "You chose to track this."
            case .nearlyAnswerable: "A few more nights and Zoon can answer this one."
            case .barelySeen: "Zoon has barely seen this one."
            case .routine: "Part of your usual picture."
            }
        }
    }

    struct Prompt: Identifiable, Hashable, Sendable {
        let tag: BehaviorTag
        let reason: Reason
        /// Nights in the window the person never reviewed. Carried for
        /// display, never for ranking: an unreviewed night is unknown for
        /// every tag alike, so this number is the same across the whole
        /// list and can order nothing.
        let unknownNights: Int
        /// Nights the behaviour did happen, and nights it did not.
        ///
        /// Both arms, not just the smaller one. The V9 spec asks the prompt
        /// to say *why* it is being asked in concrete terms -- "we have 15
        /// YES nights but only 3 NO nights" -- and the shape of that
        /// sentence is the point: it shows the reader that a comparison
        /// needs two sides, and which of theirs is short. A count was
        /// already being computed for each arm here and then thrown away in
        /// favour of the minimum.
        let yesNights: Int
        let noNights: Int

        /// The smaller of the yes and no counts -- what actually limits a
        /// matched-pair comparison, since the larger arm cannot make up for
        /// a missing smaller one.
        var thinnerArmNights: Int { min(yesNights, noNights) }

        var id: String { tag.rawValue }

        /// Why this is on tonight's list.
        ///
        /// The two reasons that exist *because a comparison is short* say
        /// how short, in nights. The others do not: "you're testing this
        /// right now" is already the whole reason, and appending counts to
        /// it would be numbers for their own sake.
        var note: String {
            switch reason {
            case .nearlyAnswerable, .barelySeen:
                return "\(yesNights) \(yesNights == 1 ? "night" : "nights") with it, "
                    + "\(noNights) without. Zoon compares the two, so the smaller side is what it needs."
            case .underExperiment, .pinnedByUser, .routine:
                return reason.note
            }
        }
    }

    // MARK: - Building tonight's list

    /// Ranks the behaviours worth asking about tonight.
    ///
    /// - Parameters:
    ///   - observations: journaled and un-journaled nights alike. Only the
    ///     journaled ones can contribute to an arm; the rest are counted
    ///     and reported, but cannot rank anything (see `Prompt.unknownNights`).
    ///   - activeExperimentTag: raw identifier of a behaviour under trial,
    ///     if any. Always asked, always first.
    ///   - pinnedTags: the person's own tracked-behaviour selection.
    ///   - limit: how many to return.
    ///
    /// Note the absence of any sleep-outcome parameter; see the type doc.
    static func prompts(
        observations: [JournalCorrelator.Observation],
        activeExperimentTag: String? = nil,
        pinnedTags: Set<BehaviorTag> = [],
        candidates: [BehaviorTag] = BehaviorTag.allCases,
        limit: Int = rankedListSize
    ) -> [Prompt] {
        guard limit > 0 else { return [] }
        let recent = Array(observations.sorted { $0.date < $1.date }.suffix(window))

        var prompts: [Prompt] = []
        for tag in candidates {
            var yes = 0, no = 0, unknown = 0
            for observation in recent {
                switch observation.exposureState(for: tag) {
                case .yes: yes += 1
                case .no: no += 1
                case .unknown: unknown += 1
                }
            }

            let isUnderExperiment = activeExperimentTag == tag.rawValue
            let isPinned = pinnedTags.contains(tag)

            // A behaviour with no history at all is noise on the nightly
            // list -- unless the person pinned it or is testing it, in which
            // case they have said it matters and that settles it.
            guard isUnderExperiment || isPinned || yes > 0 else { continue }

            let thinner = min(yes, no)
            let reason: Reason = if isUnderExperiment {
                .underExperiment
            } else if isPinned {
                .pinnedByUser
            } else if thinner < JournalCorrelator.minimumMatchedPairs
                && thinner >= JournalCorrelator.minimumMatchedPairs - nearlyAnswerableGap {
                .nearlyAnswerable
            } else if thinner < JournalCorrelator.minimumMatchedPairs {
                .barelySeen
            } else {
                .routine
            }

            prompts.append(Prompt(
                tag: tag, reason: reason,
                unknownNights: unknown, yesNights: yes, noNights: no
            ))
        }

        // Within a reason, the behaviour furthest from a usable comparison
        // comes first: tonight's answer is worth most where the thinner arm
        // is emptiest.
        //
        // Note this cannot sort on `unknownNights`, tempting as that looks.
        // A night the person never reviewed is unknown for *every* tag
        // equally, so that count is a property of the night rather than of
        // the behaviour, and ranking by it would order twenty-three
        // behaviours by a number identical for all of them. The identifier
        // breaks remaining ties, so the list cannot reshuffle between one
        // evening and the next.
        return prompts
            .sorted { a, b in
                if a.reason != b.reason { return a.reason > b.reason }
                if a.thinnerArmNights != b.thinnerArmNights {
                    return a.thinnerArmNights < b.thinnerArmNights
                }
                return a.tag.rawValue < b.tag.rawValue
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - The one question

    /// The single question worth asking tonight, or nothing at all.
    ///
    /// ## Why this can return nil
    ///
    /// `prompts` will always hand back something as long as any behaviour
    /// has ever been logged, because its lowest-priority reason -- `.routine`
    /// -- exists purely to fill a list of six. With a list of one there is
    /// nothing to fill, and a routine question is one whose answer Zoon can
    /// already predict from the fifty nights behind it. Asking it anyway
    /// spends the person's willingness to answer on a night that teaches
    /// nothing, and that willingness is the scarce resource here.
    ///
    /// So: ask when a trial needs tonight's adherence, when the person
    /// pinned the behaviour themselves, or when one arm of a comparison is
    /// genuinely short. Otherwise ask nothing.
    ///
    /// This is not a permanent silence. Exposure is counted over a rolling
    /// window, so a behaviour that stops being asked about stops accumulating
    /// answers, its arms thin out as older nights fall off the end, and it
    /// becomes worth asking again on its own. The quiet is self-correcting.
    ///
    /// - Parameter alreadyAnswered: behaviours the person has already
    ///   answered for tonight. Excluded outright -- re-asking something just
    ///   answered is the exact fatigue this is meant to avoid.
    static func question(
        observations: [JournalCorrelator.Observation],
        activeExperimentTag: String? = nil,
        pinnedTags: Set<BehaviorTag> = [],
        alreadyAnswered: Set<BehaviorTag> = [],
        candidates: [BehaviorTag] = BehaviorTag.allCases
    ) -> Prompt? {
        let unanswered = candidates.filter { !alreadyAnswered.contains($0) }
        let top = prompts(
            observations: observations,
            activeExperimentTag: activeExperimentTag,
            pinnedTags: pinnedTags,
            candidates: unanswered,
            limit: 1
        ).first
        guard let top, top.reason != .routine else { return nil }
        return top
    }
}
