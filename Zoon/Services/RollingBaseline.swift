import Foundation

/// Comparative context computed from stored history.
///
/// Every field is optional because history accrues over time: a user on night
/// three legitimately has no 7-day average, and the insight engine must degrade
/// gracefully rather than pretend.
///
/// Split out of `FeatureExtractor.swift` (which imports HealthKit) so this
/// pure Foundation type -- referenced by `SleepNightRecord.features(baseline:)`
/// -- can compile into `ZoonTests` without pulling HealthKit/HealthKitManager
/// along with it.
struct RollingBaseline: Sendable {
    /// Mean overnight HRV, previous 7 nights, excluding tonight.
    let hrv7DayAvg: Double?
    /// Cumulative shortfall vs the sleep goal over 14 days, minutes. Never < 0.
    let sleepDebtMinutes: Double?
    /// Mean deep-sleep minutes over the previous 7 nights.
    let deep7DayAvg: Double?
    /// Mean sleep duration over the previous 7 nights.
    let duration7DayAvg: Double?
    /// Mean sleep efficiency over the previous 7 nights.
    let efficiency7DayAvg: Double?
    /// Mean resting (minimum) overnight heart rate over the previous 7 nights.
    let minHeartRate7DayAvg: Double?
    /// Mean HealthKit resting-heart-rate sample over the previous 7 nights.
    let restingHeartRate7DayAvg: Double?
    /// Personal wrist-temperature baseline in °C — the mean of available
    /// overnight readings. `nil` until enough nights exist to be meaningful.
    let wristTempBaselineC: Double?
    /// Standard deviation of bedtime, in minutes, over the previous 7 nights.
    /// High values indicate an irregular schedule ("social jetlag").
    let bedtimeConsistencyMinutes: Double?
    /// How many nights of history the above is drawn from.
    let sampleCount: Int

    /// True once there is enough history for comparative claims to be honest.
    /// The rule engine checks this before saying "below your usual".
    var hasComparativeContext: Bool { sampleCount >= 3 }

    static let empty = RollingBaseline(
        hrv7DayAvg: nil,
        sleepDebtMinutes: nil,
        deep7DayAvg: nil,
        duration7DayAvg: nil,
        efficiency7DayAvg: nil,
        minHeartRate7DayAvg: nil,
        restingHeartRate7DayAvg: nil,
        wristTempBaselineC: nil,
        bedtimeConsistencyMinutes: nil,
        sampleCount: 0
    )
}
