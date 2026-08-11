import Foundation
import SwiftData

/// SwiftData row for one night.
///
/// This is a flat mirror of `SleepNightFeatures` rather than a wrapper around it,
/// for two reasons:
///
/// - SwiftData stores stored properties; it cannot persist a struct with
///   optionals as a single opaque blob without losing queryability. Flat columns
///   mean `#Predicate` and `SortDescriptor` work on any field.
/// - The persisted schema and the in-memory feature struct can then evolve
///   independently. Adding a computed convenience to `SleepNightFeatures` never
///   forces a store migration.
///
/// `date` is unique: one row per night, so a re-sync updates rather than
/// duplicates.
@Model
final class SleepNightRecord {

    /// Start-of-day for the morning the user woke up. Unique key.
    @Attribute(.unique) var date: Date

    var bedtime: Date
    var wakeTime: Date

    var timeInBedMinutes: Double
    var timeAsleepMinutes: Double
    var sleepEfficiencyPercent: Double

    var coreMinutes: Double
    var deepMinutes: Double
    var remMinutes: Double
    var unspecifiedAsleepMinutes: Double
    var awakeMinutes: Double
    var wakeCount: Int
    var sleepLatencyMinutes: Double?

    var avgHeartRate: Double?
    var minHeartRate: Double?
    /// True resting heart rate from HealthKit's daily `.restingHeartRate`
    /// sample. See `SleepNightFeatures.restingHeartRate` -- `minHeartRate`
    /// above is a different concept and must not be read as this one.
    var restingHeartRate: Double?
    var avgHRV: Double?
    var avgRespiratoryRate: Double?
    var avgSpO2: Double?
    /// Stored as the **absolute** overnight wrist temperature in °C, not the
    /// delta. The delta is relative to a baseline that keeps moving as history
    /// grows, so persisting it would freeze a comparison that should be live.
    var wristTempAbsoluteC: Double?
    /// Overnight breathing disturbances, percent of night. iOS 18+, newer watches only.
    var breathingDisturbances: Double?

    var lastWorkoutHoursBeforeBed: Double?
    var exerciseMinutesPreviousDay: Double?

    var sourceName: String?

    /// The night's stage timeline, JSON-encoded.
    ///
    /// A blob rather than a to-many relationship: it's only ever read whole to
    /// draw the hypnogram, never queried into, and 30–80 child rows per night
    /// would multiply the store for nothing.
    var stageSegmentsData: Data?

    /// Cached insight so the dashboard and widget don't re-derive it on every
    /// launch. Regenerated whenever the night is re-processed.
    var insightSummary: String?
    var insightLikelyCause: String?
    var insightTip: String?

    var createdAt: Date

    init(features: SleepNightFeatures, absoluteWristTempC: Double? = nil, insight: SleepInsight? = nil) {
        self.date = features.date
        self.bedtime = features.bedtime
        self.wakeTime = features.wakeTime
        self.timeInBedMinutes = features.timeInBedMinutes
        self.timeAsleepMinutes = features.timeAsleepMinutes
        self.sleepEfficiencyPercent = features.sleepEfficiencyPercent
        self.coreMinutes = features.coreMinutes
        self.deepMinutes = features.deepMinutes
        self.remMinutes = features.remMinutes
        self.unspecifiedAsleepMinutes = features.unspecifiedAsleepMinutes
        self.awakeMinutes = features.awakeMinutes
        self.wakeCount = features.wakeCount
        self.sleepLatencyMinutes = features.sleepLatencyMinutes
        self.avgHeartRate = features.avgHeartRate
        self.minHeartRate = features.minHeartRate
        self.restingHeartRate = features.restingHeartRate
        self.avgHRV = features.avgHRV
        self.avgRespiratoryRate = features.avgRespiratoryRate
        self.avgSpO2 = features.avgSpO2
        self.wristTempAbsoluteC = absoluteWristTempC
        self.breathingDisturbances = features.breathingDisturbances
        self.lastWorkoutHoursBeforeBed = features.lastWorkoutHoursBeforeBed
        self.exerciseMinutesPreviousDay = features.exerciseMinutesPreviousDay
        self.sourceName = features.sourceName
        self.stageSegmentsData = features.stageSegments.encoded
        self.insightSummary = insight?.summary
        self.insightLikelyCause = insight?.likelyCause
        self.insightTip = insight?.actionableTip
        self.createdAt = .now
    }

    /// Overwrites measured fields from a fresh extraction, leaving identity and
    /// `createdAt` alone. Used when HealthKit revises a night — which it does,
    /// often, as the watch finishes syncing through the morning.
    func update(from features: SleepNightFeatures, absoluteWristTempC: Double?) {
        bedtime = features.bedtime
        wakeTime = features.wakeTime
        timeInBedMinutes = features.timeInBedMinutes
        timeAsleepMinutes = features.timeAsleepMinutes
        sleepEfficiencyPercent = features.sleepEfficiencyPercent
        coreMinutes = features.coreMinutes
        deepMinutes = features.deepMinutes
        remMinutes = features.remMinutes
        unspecifiedAsleepMinutes = features.unspecifiedAsleepMinutes
        awakeMinutes = features.awakeMinutes
        wakeCount = features.wakeCount
        sleepLatencyMinutes = features.sleepLatencyMinutes
        avgHeartRate = features.avgHeartRate
        minHeartRate = features.minHeartRate
        // Preserve a previously-fetched RHR rather than clearing it: HealthKit
        // posts the day's RHR sample on its own schedule, which may not have
        // happened yet the moment a re-sync re-extracts this night.
        if let value = features.restingHeartRate { restingHeartRate = value }
        avgHRV = features.avgHRV
        avgRespiratoryRate = features.avgRespiratoryRate
        avgSpO2 = features.avgSpO2
        if let absoluteWristTempC { wristTempAbsoluteC = absoluteWristTempC }
        if let value = features.breathingDisturbances { breathingDisturbances = value }
        lastWorkoutHoursBeforeBed = features.lastWorkoutHoursBeforeBed
        exerciseMinutesPreviousDay = features.exerciseMinutesPreviousDay
        sourceName = features.sourceName
        // Only overwrite when the fresh extraction actually has a timeline —
        // a re-sync that lost staging shouldn't erase a good hypnogram.
        if !features.stageSegments.isEmpty {
            stageSegmentsData = features.stageSegments.encoded
        }
    }

    func apply(_ insight: SleepInsight) {
        insightSummary = insight.summary
        insightLikelyCause = insight.likelyCause
        insightTip = insight.actionableTip
    }
}

// MARK: - Conversion back to the feature struct

extension SleepNightRecord {

    /// Rebuilds a `SleepNightFeatures` from the row.
    ///
    /// - Parameter baseline: supplies the comparative fields, which are *not*
    ///   persisted because they change as history grows. A night from three
    ///   weeks ago should show today's 7-day-average context, not the context
    ///   that existed when it was recorded.
    func features(baseline: RollingBaseline? = nil) -> SleepNightFeatures {
        SleepNightFeatures(
            date: date,
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBedMinutes,
            timeAsleepMinutes: timeAsleepMinutes,
            sleepEfficiencyPercent: sleepEfficiencyPercent,
            coreMinutes: coreMinutes,
            deepMinutes: deepMinutes,
            remMinutes: remMinutes,
            unspecifiedAsleepMinutes: unspecifiedAsleepMinutes,
            awakeMinutes: awakeMinutes,
            wakeCount: wakeCount,
            sleepLatencyMinutes: sleepLatencyMinutes,
            avgHeartRate: avgHeartRate,
            minHeartRate: minHeartRate,
            restingHeartRate: restingHeartRate,
            avgHRV: avgHRV,
            avgRespiratoryRate: avgRespiratoryRate,
            avgSpO2: avgSpO2,
            wristTempDeltaC: wristTempDelta(against: baseline),
            breathingDisturbances: breathingDisturbances,
            hrv7DayAvg: baseline?.hrv7DayAvg,
            sleepDebtMinutes14Day: baseline?.sleepDebtMinutes14Day,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            sourceName: sourceName,
            isMock: false,
            stageSegments: [StageSegment].decode(stageSegmentsData)
        )
    }

    private func wristTempDelta(against baseline: RollingBaseline?) -> Double? {
        guard let absolute = wristTempAbsoluteC, let base = baseline?.wristTempBaselineC else { return nil }
        return absolute - base
    }

    var cachedInsight: SleepInsight? {
        guard let insightSummary, let insightTip else { return nil }
        return SleepInsight(
            summary: insightSummary,
            likelyCause: insightLikelyCause,
            actionableTip: insightTip
        )
    }
}
