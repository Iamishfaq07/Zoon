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
///    duration. That floor also excludes nights whose length was decided by
///    something other than the sleeper: a short night at very high
///    efficiency (the opportunity ran out) and a night slept deep in debt
///    (a repayment, not a baseline). See `isRestrictionShaped`, which is
///    where the "efficient short night" trap is dealt with -- a
///    quality filter that selects for efficiency will otherwise select
///    hardest for exactly the nights that mislead it.
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
        let qualifying = history.filter { isHighQuality($0, goalMinutes: goalMinutes) }
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
    private static func isHighQuality(
        _ night: SleepNightFeatures,
        goalMinutes: Double
    ) -> Bool {
        night.sleepEfficiencyPercent >= 85
            && night.wakeCount <= 4
            && night.timeAsleepMinutes >= 240
            && night.timeAsleepMinutes <= 720
            && !isRestrictionShaped(night, goalMinutes: goalMinutes)
            && !isRepayingDebt(night)
    }

    /// Efficiency above which a *short* night stops being evidence of need.
    static let restrictionEfficiencyPercent = 95.0

    /// Debt above which a night is a repayment rather than a baseline.
    static let repaymentDebtMinutes = 60.0

    /// A night that ended because the opportunity ran out, not because the
    /// sleeper was done.
    ///
    /// This is the V9 spec's named failure: "a chronic short sleeper may
    /// repeatedly have 6h15, high efficiency, without that necessarily being
    /// sufficient." The filter above selects *for* efficiency, and high
    /// efficiency on a short night is at least as consistent with sleep
    /// pressure as with sufficiency -- someone carrying a deficit falls
    /// asleep fast and sleeps solidly *because* they are short. So the
    /// original filter was selecting precisely the nights that mislead it,
    /// and the more disciplined the short sleeper, the more confidently it
    /// learned the wrong number.
    ///
    /// Only applied when time in bed was really measured. When it is
    /// estimated from the session span (Apple Watch alone never writes
    /// `inBed`), efficiency is known to read high -- see
    /// `timeInBedIsEstimated` -- and applying a 95% ceiling to an inflated
    /// figure would disqualify exactly the users whose data is thinnest.
    /// That is the same bug this file already records for
    /// `hasStageBreakdown`, and it is not being reintroduced under a new
    /// name.
    static func isRestrictionShaped(
        _ night: SleepNightFeatures,
        goalMinutes: Double
    ) -> Bool {
        guard !night.timeInBedIsEstimated else { return false }
        return night.timeAsleepMinutes < goalMinutes
            && night.sleepEfficiencyPercent >= restrictionEfficiencyPercent
    }

    /// A night slept while meaningfully in debt runs long by design, so it
    /// describes the deficit rather than the baseline.
    ///
    /// Excluded in the opposite direction to `isRestrictionShaped`, and
    /// deliberately so: one drops nights that bias the estimate down, the
    /// other drops nights that bias it up. Removing only the first would
    /// trade one lopsided estimate for another.
    static func isRepayingDebt(_ night: SleepNightFeatures) -> Bool {
        (night.sleepDebtMinutes ?? 0) >= repaymentDebtMinutes
    }
}
