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
    /// Stable local-date identity captured from the HealthKit sample timezone.
    /// Optional so existing stores migrate without assigning every historical
    /// row the same default key; rows are backfilled as HealthKit re-syncs.
    var nightKey: String?

    /// Timezone the night was actually recorded in -- see
    /// `SleepNightFeatures.timeZoneIdentifier`. Optional for the same reason
    /// as `nightKey`: existing rows predate this column and are backfilled on
    /// the next re-sync rather than migrated to a guessed value.
    var timeZoneIdentifier: String?

    /// The sleep-need baseline (see `LearnedSleepNeed`) that was
    /// authoritative *at the moment this night was processed*, frozen
    /// forever after -- never recomputed against a later, more-informed
    /// learned figure. See `SleepDebtCalculator.debtSeries(timeAsleepMinutesOldestFirst:goalMinutesOldestFirst:)`'s
    /// doc comment for why: without this, sleep debt would either use a
    /// single value across all of history (unable to reflect a personal
    /// learned need at all, only ever the raw Settings goal) or recompute
    /// every past night against today's latest learned figure, silently
    /// rewriting historical debt every time the model updates. Optional for
    /// the same reason as `nightKey`/`timeZoneIdentifier`: existing rows
    /// predate this column and fall back to the current Settings goal at
    /// read time rather than being migrated to a guessed value.
    var sleepNeedBaselineMinutesAtProcessing: Double?

    var bedtime: Date
    var wakeTime: Date

    var timeInBedMinutes: Double
    /// See `SleepNightFeatures.timeInBedIsEstimated`.
    var timeInBedIsEstimated: Bool = false
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

    init(
        features: SleepNightFeatures,
        absoluteWristTempC: Double? = nil,
        insight: SleepInsight? = nil,
        nightKey: String? = nil
    ) {
        self.date = features.date
        self.nightKey = nightKey
        self.timeZoneIdentifier = features.timeZoneIdentifier
        // Stamped once, here, on first insert only -- update(from:) below
        // deliberately never touches this, so a re-sync of the same night
        // (HealthKit revising it hours later) can never shift it.
        self.sleepNeedBaselineMinutesAtProcessing = features.sleepNeedBaselineMinutes
        self.bedtime = features.bedtime
        self.wakeTime = features.wakeTime
        self.timeInBedMinutes = features.timeInBedMinutes
        self.timeInBedIsEstimated = features.timeInBedIsEstimated
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
    /// - Parameter confirmedAbsent: metrics HealthKit definitively reported
    ///   nothing for this night. A metric arriving as `nil` means one of two
    ///   very different things -- HealthKit answered "nothing recorded", or
    ///   the query failed -- and only the first justifies clearing a value
    ///   already on disk. Previously this couldn't be told apart, so each
    ///   optional field picked one behaviour and lived with the other being
    ///   wrong: HRV, respiratory rate and SpO2 cleared unconditionally (a
    ///   transient query failure destroyed a good night's readings), while
    ///   resting HR, temperature and breathing disturbances preserved
    ///   unconditionally (a reading deleted in Health lived on in Zoon
    ///   forever). Both are now correct. See `MeasurementOutcome`.
    ///
    /// Deliberately does **not** touch `sleepNeedBaselineMinutesAtProcessing`
    /// -- unlike `timeZoneIdentifier` and everything else here, that field
    /// is meant to freeze at first insert and never move again, even across
    /// a same-night re-sync. See its own doc comment.
    func update(
        from features: SleepNightFeatures,
        absoluteWristTempC: Double?,
        confirmedAbsent: Set<VitalMetric> = []
    ) {
        /// Writes a new value, clears on confirmed absence, and otherwise
        /// leaves whatever is already stored alone.
        func apply(
            _ new: Double?,
            _ metric: VitalMetric,
            to keyPath: ReferenceWritableKeyPath<SleepNightRecord, Double?>
        ) {
            if let new {
                self[keyPath: keyPath] = new
            } else if confirmedAbsent.contains(metric) {
                self[keyPath: keyPath] = nil
            }
        }

        timeZoneIdentifier = features.timeZoneIdentifier
        bedtime = features.bedtime
        wakeTime = features.wakeTime
        timeInBedMinutes = features.timeInBedMinutes
        timeInBedIsEstimated = features.timeInBedIsEstimated
        timeAsleepMinutes = features.timeAsleepMinutes
        sleepEfficiencyPercent = features.sleepEfficiencyPercent
        coreMinutes = features.coreMinutes
        deepMinutes = features.deepMinutes
        remMinutes = features.remMinutes
        unspecifiedAsleepMinutes = features.unspecifiedAsleepMinutes
        awakeMinutes = features.awakeMinutes
        wakeCount = features.wakeCount
        sleepLatencyMinutes = features.sleepLatencyMinutes
        apply(features.avgHeartRate, .averageHeartRate, to: \.avgHeartRate)
        apply(features.minHeartRate, .minimumHeartRate, to: \.minHeartRate)
        apply(features.restingHeartRate, .restingHeartRate, to: \.restingHeartRate)
        apply(features.avgHRV, .hrv, to: \.avgHRV)
        apply(features.avgRespiratoryRate, .respiratoryRate, to: \.avgRespiratoryRate)
        apply(features.avgSpO2, .oxygenSaturation, to: \.avgSpO2)
        apply(absoluteWristTempC, .wristTemperature, to: \.wristTempAbsoluteC)
        apply(features.breathingDisturbances, .breathingDisturbances, to: \.breathingDisturbances)
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
    /// - Parameter secondaryAsleepMinutes: naps/split-sleep tied to this
    ///   night's `nightKey`, looked up by the caller (`SleepHistoryStore`
    ///   owns the query since it needs the model context). Defaults to 0 for
    ///   callers that don't have or need that lookup, e.g. the store-migration
    ///   copy path.
    func features(baseline: RollingBaseline? = nil, secondaryAsleepMinutes: Double = 0) -> SleepNightFeatures {
        SleepNightFeatures(
            date: date,
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBedMinutes,
            timeInBedIsEstimated: timeInBedIsEstimated,
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
            sleepDebtMinutes: baseline?.sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            secondaryAsleepMinutes: secondaryAsleepMinutes,
            sleepNeedBaselineMinutes: sleepNeedBaselineMinutesAtProcessing,
            sourceName: sourceName,
            isMock: false,
            stageSegments: [StageSegment].decode(stageSegmentsData),
            timeZoneIdentifier: timeZoneIdentifier ?? TimeZone.current.identifier
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
