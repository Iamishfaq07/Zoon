import Foundation

/// A personal sleep-need baseline, learned from history rather than taken
/// purely from the goal set in Settings.
///
/// Whoop, Oura, and Garmin all present some version of "how much sleep you
/// actually need" as a personalized figure rather than a flat 8 hours. Before
/// this existed, `SleepNeed.baselineMinutes` was literally just the user's
/// configured goal -- a real target, but not a *learned* one, despite the
/// rest of the app's language implying otherwise.
///
/// ## Why not just average historical sleep
///
/// A straight mean or median of every stored night would teach the system
/// that a chronic under-sleeper's usual shortfall is their "need" -- the
/// exact failure mode the spec this was built against calls out by name.
/// Instead:
///
/// 1. Filter to nights that look like genuinely restful, well-measured sleep
///    (decent efficiency, not badly fragmented, real stage data) -- not "the
///    nights closest to what we expect," which would be circular, but a
///    data-quality and continuity floor applied uniformly regardless of
///    duration.
/// 2. Take the 60th percentile of *those* nights' duration, not the median --
///    biasing toward the more-rested end of someone's own good nights,
///    rather than splitting the difference with their merely-adequate ones.
/// 3. Blend that learned figure with the goal progressively as qualifying
///    nights accumulate, rather than switching over abruptly at some
///    threshold.
struct LearnedSleepNeed: Codable, Hashable, Sendable {

    /// See `MetricConfidence`. `.low` isn't currently reachable here --
    /// `compute` only ever produces `.insufficient`, `.moderate`, or `.high`
    /// -- but the shared type carries it for consistency with the other
    /// metrics that do use it.
    typealias Confidence = MetricConfidence

    /// The baseline to actually use -- the goal alone below
    /// `minimumQualifyingNights`, a progressive blend of goal and learned
    /// estimate above it.
    let minutes: Double
    /// The pure learned estimate, `nil` until there's enough qualifying
    /// history to compute one at all.
    let learnedMinutes: Double?
    /// How many stored nights cleared the quality filter -- not the same as
    /// total nights of history, which may include plenty of fragmented or
    /// sparsely-measured ones that don't qualify.
    let qualifyingNightCount: Int
    let confidence: Confidence

    /// Nights needed before a learned estimate starts blending in at all.
    static let minimumQualifyingNights = 30
    /// Nights at which the blend is fully the learned estimate.
    static let fullConfidenceNights = 60

    static func compute(goalMinutes: Double, history: [SleepNightFeatures]) -> LearnedSleepNeed {
        let qualifying = history.filter(isHighQuality)
        let count = qualifying.count

        guard count >= minimumQualifyingNights,
              let learned = Statistics.percentile(qualifying.map(\.timeAsleepMinutes), 60) else {
            return LearnedSleepNeed(
                minutes: goalMinutes, learnedMinutes: nil,
                qualifyingNightCount: count, confidence: .insufficient
            )
        }

        // Linear ramp from 0% learned at the minimum to 100% learned at
        // fullConfidenceNights, rather than a hard cutover -- the 31st
        // qualifying night is barely more trustworthy than the 29th, and a
        // step-change in someone's displayed sleep need for no reason they
        // can see would read as the number being unstable, not personalized.
        let weight = min(1.0, Double(count - minimumQualifyingNights) / Double(fullConfidenceNights - minimumQualifyingNights))
        let blended = goalMinutes * (1 - weight) + learned * weight

        return LearnedSleepNeed(
            minutes: blended,
            learnedMinutes: learned,
            qualifyingNightCount: count,
            confidence: count >= fullConfidenceNights ? .high : .moderate
        )
    }

    /// A night is a fair data point for "how much sleep this person needs"
    /// when it was efficient, not badly fragmented, and actually measured.
    /// The duration bound here is a sanity floor/ceiling against fragments
    /// and clearly-erroneous outliers (4-12h), not a narrow "expected"
    /// window -- narrowing it further would just reproduce whatever
    /// assumption seeded the filter, defeating the point of learning it.
    ///
    /// Deliberately does **not** require `hasStageBreakdown`. This used to,
    /// which meant an iPhone-only or third-party-tracker user -- anyone
    /// whose source writes only `asleepUnspecified`, never a
    /// core/deep/REM split -- could never accumulate a single qualifying
    /// night, no matter how many efficient, unfragmented, well-measured
    /// nights they had: `learnedMinutes` stayed permanently `nil` and the
    /// baseline stayed the raw Settings goal forever. Staging granularity
    /// has nothing to do with whether a night's *total duration* is
    /// trustworthy -- `unspecifiedAsleepMinutes` is a first-class, measured
    /// asleep total in its own right (see `SleepNightFeatures`'s doc
    /// comment on that field), not a placeholder. The efficiency, wake-count
    /// and duration bounds below are the real quality floor; they apply
    /// identically regardless of source.
    private static func isHighQuality(_ night: SleepNightFeatures) -> Bool {
        night.sleepEfficiencyPercent >= 85
            && night.wakeCount <= 4
            && night.timeAsleepMinutes >= 240
            && night.timeAsleepMinutes <= 720
    }
}
