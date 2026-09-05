import Foundation

/// The extension point for reasoning about a night.
///
/// Everything upstream — HealthKit, session building, persistence — exists to
/// produce the two inputs to this call. Everything downstream just renders the
/// output. Adding a new way to explain a night means adding a conformance here
/// and nothing else.
///
/// **The contract is deliberately narrow:** given features and comparative
/// context, return one `SleepInsight`, synchronously, with no failure case. An
/// engine that can't say anything useful returns a low-confidence insight — it
/// never throws and never returns nil, because there is no sensible UI for
/// "the explanation subsystem is unavailable".
///
/// Implementations:
/// - `RuleBasedInsightEngine` — complete, deterministic, always available.
/// - `LocalLLMInsightEngine` — stub; wraps a fallback engine.
protocol SleepInsightEngine {

    /// Human-readable name, shown in Settings.
    var displayName: String { get }

    /// - Parameters:
    ///   - features: the night being explained.
    ///   - baseline: rolling context. May be `.empty` on the first nights —
    ///     implementations must degrade to non-comparative statements rather
    ///     than claiming a change they can't substantiate.
    ///   - goalMinutes: the user's own sleep target.
    ///   - band: the night's Sleep Intelligence band -- the flagship score's
    ///     own grade. Supplied because the summary opens with a word for the
    ///     whole night ("Strong night", "Rough night"), and that word has to
    ///     come from the same score every other surface shows. It was derived
    ///     from `SleepScore` here, which meant the most-read sentence in the
    ///     app could call a night "Mixed" while the hero orb two lines above
    ///     it graded the same night Good.
    ///
    ///     `nil` when no flagship score could be computed for the night --
    ///     implementations fall back rather than inventing a grade. Defaulted
    ///     so preview and test call sites that only want a sentence stay
    ///     unchanged.
    func generate(
        for features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double,
        band: SleepIntelligenceScore.Band?
    ) -> SleepInsight
}

extension SleepInsightEngine {

    /// Convenience for callers with no flagship score to hand -- previews,
    /// tests, and the engines' own fallbacks.
    func generate(
        for features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) -> SleepInsight {
        generate(for: features, baseline: baseline, goalMinutes: goalMinutes, band: nil)
    }
}
