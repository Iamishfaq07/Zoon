import Foundation
import HealthKit

/// Joins a `SleepSession` to the vitals recorded during it, producing one
/// `SleepNightFeatures`.
///
/// Kept separate from `HealthKitManager` so the join logic — which is where the
/// unit conversions and the "which window do I query?" decisions live — can be
/// reasoned about without a health store in the picture.
///
/// `@MainActor` because it does nothing CPU-bound: every call is I/O against the
/// health store and immediately suspends. The expensive part (session building)
/// happens in `SleepSessionBuilder`, off this actor.
@MainActor
struct FeatureExtractor {

    let healthKit: HealthKitManager

    /// What one extraction produces.
    ///
    /// Carries the *absolute* overnight wrist temperature alongside the feature
    /// struct, which only holds the delta. The store needs the absolute value:
    /// the delta is measured against a baseline built from past absolute
    /// readings, so if only deltas were persisted the baseline could never
    /// bootstrap — night one has no baseline, so it would have no delta, so it
    /// would contribute nothing to the baseline, forever.
    struct Result {
        let features: SleepNightFeatures
        let absoluteWristTempC: Double?
        /// Metrics HealthKit definitively reported nothing for, as opposed to
        /// ones whose query failed. Only these may clear a previously-stored
        /// value on re-sync -- see `MeasurementOutcome`.
        let confirmedAbsent: Set<VitalMetric>
    }

    /// Builds features for one session.
    ///
    /// - Parameter baseline: rolling context from stored history. Passing `nil`
    ///   yields a record with no comparative fields — valid, just less useful,
    ///   which is exactly what the first few nights look like.
    func extract(from session: SleepSession, baseline: RollingBaseline?) async -> Result {
        // Scoped to the night's actual asleep intervals, not the in-bed
        // envelope (session.start...session.end): a session with 20 minutes
        // awake at the start would otherwise fold pre-sleep HR into "average
        // overnight heart rate", which is a different, less useful number.
        // `asleepIntervals` is never empty here — the builder only keeps
        // sessions with totalAsleepMinutes > 0.
        let intervals = session.asleepIntervals

        // Vitals are queried concurrently — six sequential round trips to the
        // health store is a visible pause on a cold refresh. Each returns nil on
        // failure: one missing signal should degrade the record, not fail it.
        async let avgHRTask = measuredAverage(.heartRate, unit: .beatsPerMinute, in: intervals)
        async let minHRTask = measuredMinimum(.heartRate, unit: .beatsPerMinute, in: intervals)
        // Resting HR is a once-daily value that can arrive after wake. Bound the
        // query to the wake date so a missing reading cannot silently reuse an
        // arbitrarily old sample or reach into the following day. Uses the
        // session's own recorded timezone (`wakeDate`), not the device's
        // current one -- a traveler re-syncing a historical night from a new
        // timezone must still get that night's own wake day, not today's.
        var wakeCalendar = Calendar(identifier: .gregorian)
        wakeCalendar.timeZone = TimeZone(identifier: session.timeZoneIdentifier) ?? .current
        let wakeDayStart = session.wakeDate
        let wakeDayEnd = wakeCalendar.date(
            byAdding: .day,
            value: 1,
            to: wakeDayStart
        ) ?? session.end.addingTimeInterval(86_400)
        async let restingHRTask = measuredMostRecent(
            .restingHeartRate,
            unit: .beatsPerMinute,
            in: DateInterval(start: wakeDayStart, end: wakeDayEnd)
        )
        async let hrvTask = measuredAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: intervals)
        async let respiratoryTask = measuredAverage(.respiratoryRate, unit: .breathsPerMinute, in: intervals)
        async let spo2Task = measuredAverage(.oxygenSaturation, unit: .percent(), in: intervals)
        async let wristTempTask = measuredAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), in: intervals)
        async let breathingTask = measuredAverage(.appleSleepingBreathingDisturbances, unit: .percent(), in: intervals)

        let avgHROutcome = await avgHRTask
        let minHROutcome = await minHRTask
        let restingHROutcome = await restingHRTask
        let hrvOutcome = await hrvTask
        let respiratoryOutcome = await respiratoryTask
        // HKUnit.percent() yields a 0–1 fraction, NOT 0–100. Forgetting this is
        // how you end up displaying "0.97% blood oxygen".
        let spo2Outcome = await spo2Task.map { $0 * 100 }
        let wristTempOutcome = await wristTempTask
        let breathingRaw = await breathingTask
        // Breathing disturbances also arrive as a 0-1 fraction under
        // HKUnit.percent(), same trap as SpO2.
        let breathingOutcome = breathingRaw.map { $0 * 100 }
        // Apple's own elevated/not-elevated call on the same measured
        // fraction (pre-percent-conversion -- the classifier expects the
        // same 0-1 HKQuantity HealthKit itself reports), rather than this
        // app inventing its own cutoff. `nil` when there was no measured
        // value, or when HealthKit's own classifier declines to classify
        // it -- `BreathingHealth.isElevated` falls back to an in-app
        // threshold either way, so this never blocks the feature. The
        // Swift-refined label is `classifying:`, not `for:` -- confirmed
        // against the real SDK by CI after an initial guess was wrong.
        let breathingClassification: BreathingDisturbanceClassification? = breathingRaw.value.flatMap { fraction in
            let quantity = HKQuantity(unit: .percent(), doubleValue: fraction)
            guard let raw = HKAppleSleepingBreathingDisturbancesClassification(classifying: quantity) else { return nil }
            switch raw {
            case .notElevated: return .notElevated
            case .elevated: return .elevated
            @unknown default: return nil
            }
        }

        let workoutHours = await lastWorkoutContext(before: session.start)
        let exercisePrevious = await exerciseMinutes(onDayOf: session.start, timeZoneIdentifier: session.timeZoneIdentifier)
        let measuredAlcoholicBeverages = await alcoholicBeverages(onDayOf: session.start, timeZoneIdentifier: session.timeZoneIdentifier)
        let measuredLateCaffeineMg = await lateCaffeineMg(onDayOf: session.start, timeZoneIdentifier: session.timeZoneIdentifier)

        let wristTemp = wristTempOutcome.value

        // Wrist temperature is only meaningful as a delta from the user's own
        // baseline — the absolute number varies too much between people and
        // wrists to mean anything alone. Stays nil until history exists.
        let tempDelta: Double? = {
            guard let absolute = wristTemp, let base = baseline?.wristTempBaselineC else { return nil }
            return absolute - base
        }()

        // Only a definitive "nothing recorded" clears a stored value on
        // re-sync. A query that threw leaves the existing record alone --
        // see MeasurementOutcome and SleepNightRecord.update.
        var confirmedAbsent: Set<VitalMetric> = []
        let outcomes: [(VitalMetric, MeasurementOutcome)] = [
            (.averageHeartRate, avgHROutcome),
            (.minimumHeartRate, minHROutcome),
            (.restingHeartRate, restingHROutcome),
            (.hrv, hrvOutcome),
            (.respiratoryRate, respiratoryOutcome),
            (.oxygenSaturation, spo2Outcome),
            (.wristTemperature, wristTempOutcome),
            (.breathingDisturbances, breathingOutcome)
        ]
        for (metric, outcome) in outcomes where outcome.confirmsAbsence {
            confirmedAbsent.insert(metric)
        }

        let stageMinutes = session.stageMinutes
        let asleep = session.totalAsleepMinutes
        let inBed = session.timeInBed / 60
        // Clamped: with duplicate sources merged this shouldn't exceed 100, but a
        // misbehaving source can still hand us overlapping in-bed data.
        let efficiency = inBed > 0 ? min(100, max(0, asleep / inBed * 100)) : 0

        let features = SleepNightFeatures(
            // Filed under the wake-up day, matching Health app convention.
            date: session.wakeDate,
            bedtime: session.start,
            wakeTime: session.end,
            timeInBedMinutes: inBed,
            timeInBedIsEstimated: !session.hasExplicitInBedData,
            timeAsleepMinutes: asleep,
            sleepEfficiencyPercent: efficiency,
            coreMinutes: stageMinutes[.core] ?? 0,
            deepMinutes: stageMinutes[.deep] ?? 0,
            remMinutes: stageMinutes[.rem] ?? 0,
            unspecifiedAsleepMinutes: stageMinutes[.unspecified] ?? 0,
            awakeMinutes: stageMinutes[.awake] ?? 0,
            wakeCount: session.wakeCountAfterOnset,
            sleepLatencyMinutes: session.latencyMinutes,
            avgHeartRate: avgHROutcome.value,
            minHeartRate: minHROutcome.value,
            restingHeartRate: restingHROutcome.value,
            avgHRV: hrvOutcome.value,
            avgRespiratoryRate: respiratoryOutcome.value,
            avgSpO2: spo2Outcome.value,
            wristTempDeltaC: tempDelta,
            breathingDisturbances: breathingOutcome.value,
            breathingDisturbancesClassification: breathingClassification,
            hrv7DayAvg: baseline?.hrv7DayAvg,
            sleepDebtMinutes: baseline?.sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: workoutHours,
            exerciseMinutesPreviousDay: exercisePrevious,
            alcoholicBeverages: measuredAlcoholicBeverages,
            lateCaffeineMg: measuredLateCaffeineMg,
            sourceName: session.sourceName,
            isMock: false,
            stageSegments: session.segments,
            timeZoneIdentifier: session.timeZoneIdentifier
        )

        return Result(
            features: features,
            absoluteWristTempC: wristTemp,
            confirmedAbsent: confirmedAbsent
        )
    }

    // MARK: - Query wrappers
    //
    // These used to collapse `throws` + `Double?` into a plain `Double?`, on
    // the reasoning that a night with no SpO2 readings and a night where the
    // SpO2 query errored are the same thing to the feature record. That held
    // only while nothing acted on the absence. Now that a re-sync can clear a
    // stale stored value, the two must stay distinguishable: a confirmed
    // absence should clear, a failed query must not. See `MeasurementOutcome`.

    private func measuredAverage(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in intervals: [DateInterval]
    ) async -> MeasurementOutcome {
        do {
            guard let value = try await healthKit.average(identifier, unit: unit, in: intervals) else {
                return .noData
            }
            return .measured(value)
        } catch {
            return .queryFailed
        }
    }

    private func measuredMinimum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in intervals: [DateInterval]
    ) async -> MeasurementOutcome {
        do {
            guard let value = try await healthKit.minimum(identifier, unit: unit, in: intervals) else {
                return .noData
            }
            return .measured(value)
        } catch {
            return .queryFailed
        }
    }

    private func measuredMostRecent(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        in interval: DateInterval
    ) async -> MeasurementOutcome {
        do {
            guard let value = try await healthKit.mostRecentSample(
                identifier,
                unit: unit,
                in: interval
            ) else {
                return .noData
            }
            return .measured(value)
        } catch {
            return .queryFailed
        }
    }

    // MARK: - Context helpers

    /// Hours between the end of the last workout and bedtime.
    ///
    /// Bounded to the 24h before bed by the underlying query — a workout three
    /// days ago says nothing about tonight, and "72.4 hours since last workout"
    /// is noise the insight engine would have to defend against.
    private func lastWorkoutContext(before bedtime: Date) async -> Double? {
        guard let workout = try? await healthKit.lastWorkout(before: bedtime) else { return nil }
        let hours = bedtime.timeIntervalSince(workout.endDate) / 3600
        return hours >= 0 ? hours : nil
    }

    /// Apple Exercise minutes accumulated on the day the user went to bed,
    /// up to bedtime. Uses the session's own recorded timezone rather than
    /// the device's current one, so re-syncing a historical night after
    /// traveling still resolves "the day of" against that night's own zone.
    private func exerciseMinutes(onDayOf bedtime: Date, timeZoneIdentifier: String) async -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let dayStart = calendar.startOfDay(for: bedtime)
        guard dayStart < bedtime else { return nil }
        let interval = DateInterval(start: dayStart, end: bedtime)
        return try? await healthKit.sum(.appleExerciseTime, unit: .minute(), in: interval)
    }

    /// Alcoholic beverages logged on the day of bedtime, up to bedtime --
    /// same day-boundary convention as `exerciseMinutes`. Nil whether
    /// nothing was logged or the Lifestyle Insights type was never
    /// authorized; both look identical to a query, by HealthKit's design
    /// (see `HealthKitManager`'s own doc comment on read-permission
    /// opacity), so this can't and doesn't try to tell them apart.
    private func alcoholicBeverages(onDayOf bedtime: Date, timeZoneIdentifier: String) async -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let dayStart = calendar.startOfDay(for: bedtime)
        guard dayStart < bedtime else { return nil }
        let interval = DateInterval(start: dayStart, end: bedtime)
        return try? await healthKit.sum(.numberOfAlcoholicBeverages, unit: .count(), in: interval)
    }

    /// Caffeine logged after 4pm on the day of bedtime, up to bedtime --
    /// "late" is the behaviourally relevant window for sleep (matches
    /// `BehaviorTag.caffeineLate`'s own framing), not the day's total intake.
    private func lateCaffeineMg(onDayOf bedtime: Date, timeZoneIdentifier: String) async -> Double? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        guard let afternoon = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: bedtime),
              afternoon < bedtime else { return nil }
        let interval = DateInterval(start: afternoon, end: bedtime)
        return try? await healthKit.sum(.dietaryCaffeine, unit: .gramUnit(with: .milli), in: interval)
    }
}

// MARK: - Units

extension HKUnit {
    static var beatsPerMinute: HKUnit { .count().unitDivided(by: .minute()) }
    static var breathsPerMinute: HKUnit { .count().unitDivided(by: .minute()) }
}

// `RollingBaseline` moved to its own file (RollingBaseline.swift) -- it's
// pure Foundation with no HealthKit dependency, and living here forced
// anything that needs it (SleepNightRecord.features(baseline:)) to compile
// this file's HealthKit import along with it.
