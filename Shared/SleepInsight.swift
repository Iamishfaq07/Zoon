import Foundation

/// The structured output every insight engine must produce.
///
/// Deliberately small and fully constrained: this is also the JSON schema the
/// local LLM is held to in `LocalLLMInsightEngine`. A three-field struct is easy
/// to validate, easy to repair on a malformed generation, and impossible to turn
/// into a wall of text.
struct SleepInsight: Codable, Hashable, Sendable {

    /// One line, plain language, no jargon. Shown in the dashboard hero card.
    /// e.g. "Solid night — 7h 20m with good deep sleep."
    let summary: String

    /// Best-guess driver, only when the signal is strong enough to name one.
    /// `nil` is a valid and common answer — inventing a cause from noise is the
    /// fastest way to lose a user's trust.
    let likelyCause: String?

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
