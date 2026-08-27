import Foundation

/// Whether a behaviour happened on a given night, didn't happen, or was
/// simply never answered.
///
/// The third case is the whole point of this type. The model this replaced
/// carried a `Set<BehaviorTag>` per night and inferred the rest: a tag in the
/// set meant yes, a tag absent from the set on a night that had *any* journal
/// row meant no. That inference is invalid, and invalid in the direction that
/// does the most damage.
///
/// `JournalStore.entryOrCreate` persists a row the moment the journal screen
/// renders a day, whether or not the user taps anything. So opening the
/// screen once manufactured a confident "did not happen" for all twenty-three
/// behaviours -- and those fabricated negatives became the control arm of
/// every matched-pair comparison in `JournalCorrelator`. Someone who tags
/// alcohol on the nights they drink and never touches the other checkboxes
/// was, under the old model, asserting that they had no caffeine, no late
/// meal, no screens and no stressful day on every single one of those nights.
/// The correlator then compared real exposed nights against a control group
/// built substantially out of nothing.
///
/// A missing answer is missing data. It is not a "no".
enum BehaviorObservationState: String, Codable, Sendable, CaseIterable {
    case yes
    case no
    case unknown
}

/// Where a behaviour answer came from.
///
/// Recorded rather than inferred because the three sources carry genuinely
/// different authority, and a later reader cannot recover which one produced
/// an answer from the answer alone. `manual` is the only source that can
/// assert `.no`: see `BehaviorObservationState`'s own doc comment, and
/// `JournalCorrelator.Observation.exposureState(for:)` for the measured-data
/// rule.
enum BehaviorObservationSource: String, Codable, Sendable, CaseIterable {

    /// The user explicitly answered the question. The only source permitted
    /// to record a `.no`.
    case manual

    /// Read directly from a HealthKit sample (a logged drink, a caffeine
    /// entry). Can upgrade an unanswered behaviour to `.yes` and nothing
    /// else -- an absent sample means "nothing was logged *or* the type was
    /// never authorized", which HealthKit deliberately makes
    /// indistinguishable, so it can never prove absence.
    case healthKit

    /// Inferred from other measured data rather than from a sample of the
    /// behaviour itself -- a night whose recorded timezone differs from the
    /// previous night's is evidence of travel. Same upgrade-only rule as
    /// `healthKit`: a same-timezone trip is real travel this cannot see, so
    /// its absence is evidence of nothing.
    case derived
}

/// One night's explicit per-behaviour answers.
///
/// Keyed by `BehaviorTag.rawValue` rather than by `BehaviorTag` for the same
/// reason `JournalEntry.tagIdentifiers` is a `[String]`: an identifier
/// written by a future build decays to "never answered" instead of failing to
/// load, and the enum can be reordered or extended without a migration.
///
/// `.unknown` is never stored. It is the absence of an entry, so writing it
/// explicitly would make `answeredCount` count non-answers and would let a
/// cleared answer masquerade as a recorded one.
struct BehaviorAnswers: Equatable, Sendable {

    private var states: [String: BehaviorObservationState]

    init(_ states: [String: BehaviorObservationState] = [:]) {
        self.states = states.filter { $0.value != .unknown }
    }

    /// A night with nothing answered. The default, and what every night
    /// starts as -- including a night whose journal screen has been opened.
    static let none = BehaviorAnswers()

    func state(for tag: BehaviorTag) -> BehaviorObservationState {
        states[tag.rawValue] ?? .unknown
    }

    func state(forIdentifier identifier: String) -> BehaviorObservationState {
        states[identifier] ?? .unknown
    }

    /// Whether the user has answered anything at all about this night.
    ///
    /// Replaces the old `isJournaled` flag as the night-level "did we learn
    /// something here" gate (see `ExperimentPlanner.plan`). The distinction
    /// matters: a journal row exists for every day the screen was opened,
    /// but only an answered behaviour is data.
    var hasAnyAnswer: Bool { !states.isEmpty }

    var answeredCount: Int { states.count }

    var answeredIdentifiers: Set<String> { Set(states.keys) }

    /// Identifiers answered `.yes`. Used for the legacy-tag bridge and for
    /// display; never for building a control arm.
    var yesIdentifiers: Set<String> {
        Set(states.filter { $0.value == .yes }.keys)
    }

    mutating func set(_ state: BehaviorObservationState, for tag: BehaviorTag) {
        if state == .unknown {
            states.removeValue(forKey: tag.rawValue)
        } else {
            states[tag.rawValue] = state
        }
    }

    func setting(_ state: BehaviorObservationState, for tag: BehaviorTag) -> BehaviorAnswers {
        var copy = self
        copy.set(state, for: tag)
        return copy
    }

    // MARK: - Construction

    /// Answers for a night the user worked all the way through: the listed
    /// behaviours `.yes`, every other candidate an explicit `.no`.
    ///
    /// This is now the only way to obtain a full control arm, and it exists
    /// so that intent has to be stated. Under the old model this shape was
    /// the *default* for any night with a journal row, which is precisely
    /// the bug -- a test or a caller that wants a complete night now has to
    /// say so, and a night nobody answered stays unknown.
    static func fullyAnswered(
        tags: Set<BehaviorTag>,
        candidates: [BehaviorTag] = BehaviorTag.allCases
    ) -> BehaviorAnswers {
        var states: [String: BehaviorObservationState] = [:]
        for candidate in candidates {
            states[candidate.rawValue] = tags.contains(candidate) ? .yes : .no
        }
        // A tag outside `candidates` that the user did record is still a
        // recorded yes; dropping it would lose real data.
        for tag in tags {
            states[tag.rawValue] = .yes
        }
        return BehaviorAnswers(states)
    }

    /// Answers derived from the legacy `JournalEntry.tagIdentifiers` model.
    ///
    /// A tag that was present is a `.yes` the user really did record, so it
    /// migrates. A tag that was absent migrates to `.unknown` and **must
    /// never become `.no`**: the old model could not tell "the user reviewed
    /// this night and it didn't apply" from "the user never saw the
    /// question", and back-filling `.no` would bake the fabricated control
    /// arm permanently into the store, where no later fix could find it.
    ///
    /// The migration is therefore lossy on purpose, and lossy in the safe
    /// direction: it under-claims what is known rather than over-claiming.
    static func migrating(fromTagIdentifiers identifiers: [String]) -> BehaviorAnswers {
        var states: [String: BehaviorObservationState] = [:]
        for identifier in identifiers {
            states[identifier] = .yes
        }
        return BehaviorAnswers(states)
    }
}
