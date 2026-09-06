import Foundation

/// The structured output every insight engine must produce.
///
/// Deliberately small and fully constrained: the first three fields are also
/// the JSON schema the local LLM is held to in `LocalLLMInsightEngine`. A
/// three-field struct is easy to validate, easy to repair on a malformed
/// generation, and impossible to turn into a wall of text.
///
/// `generalContext` is deliberately outside that schema -- it is a *separation*
/// the deterministic engine performs, not a fourth thing for a model to write.
struct SleepInsight: Codable, Hashable, Sendable {

    /// One line, plain language, no jargon. Shown in the dashboard hero card.
    /// e.g. "Solid night — 7h 20m with good deep sleep."
    let summary: String

    /// What was actually measured about this night, when a rule found
    /// something worth naming.
    ///
    /// `nil` is a valid and common answer — inventing a cause from noise is the
    /// fastest way to lose a user's trust.
    ///
    /// Named `likelyCause` from the first version and kept, because every
    /// stored night and every snapshot on disk uses that key. What changed is
    /// what it is allowed to hold: this person's own numbers, and nothing
    /// else. See `generalContext`.
    let likelyCause: String?

    /// What is generally known about the pattern above — across people, not
    /// about this person.
    ///
    /// ## Why this is a separate field
    ///
    /// The rule engine works from one night against a rolling baseline. It can
    /// see that deep sleep came in 30% below usual. It cannot see why, and it
    /// never will from one night. What it *can* offer is the general finding:
    /// most deep sleep happens early, so a disturbed first few hours costs it.
    ///
    /// Both sentences used to be concatenated into `likelyCause`, and a reader
    /// got them as one paragraph in one voice. That is the whole failure: a
    /// measurement about them and a fact about people in general read
    /// identically, so the general fact silently borrows the measurement's
    /// standing and becomes the reason for last night. Keeping them in two
    /// fields is what lets a screen render them as two different kinds of
    /// thing, which is the only presentation that is not quietly misleading.
    ///
    /// The third tier the app deals in -- what *this person's* own history
    /// says, from matched pairs or a pre-specified experiment -- is not here
    /// and cannot be. One night has no such evidence in it. It comes from
    /// `JournalCorrelator`, `GuidedExperiment` and the evidence ledger, and
    /// lives on the screens that own them.
    ///
    /// `nil` for engines that do not distinguish the two. The local model is
    /// held to a three-field schema on purpose (see `LocalLLMInsightEngine`),
    /// and a model asked to sort its own output into evidence tiers would
    /// answer confidently and wrongly.
    var generalContext: String? = nil

    /// One concrete, actionable thing to try tonight.
    let actionableTip: String

    /// How much the engine trusts this reading. Drives UI treatment: low
    /// confidence renders without the causal line.
    var confidence: Confidence = .medium

    /// Which engine produced this, for debugging and for the Settings screen.
    var source: Source = .ruleBased

    enum Confidence: String, Codable, Hashable, Sendable, Comparable {
        case low, medium, high

        private var rank: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
    }

    enum Source: String, Codable, Hashable, Sendable {
        case ruleBased = "rule_based"
        case appleIntelligence = "apple_intelligence"
        case localLLM = "local_llm"

        var displayName: String {
            switch self {
            case .ruleBased: "On-device rules"
            case .appleIntelligence: "Apple Intelligence"
            case .localLLM: "On-device model"
            }
        }
    }
}

extension SleepInsight {

    /// Shown before any night has been processed, and in the Simulator when
    /// HealthKit has nothing to give us.
    static let placeholder = SleepInsight(
        summary: "No sleep data yet.",
        likelyCause: nil,
        actionableTip: "Wear your Apple Watch to bed tonight and check back in the morning.",
        confidence: .low
    )

    /// Standard non-diagnostic disclaimer.
    ///
    /// Zoon reads the same physiological signals a clinician would, but it is a
    /// consumer app making correlational guesses — it must never read as
    /// diagnosis. Surfaced in Settings and beneath any insight that references
    /// SpO2, respiratory rate, or wrist temperature.
    static let disclaimer = """
        Zoon offers general wellness observations, not medical advice. \
        It cannot diagnose any condition, including sleep apnea. \
        If something here worries you, talk to a clinician.
        """
}
