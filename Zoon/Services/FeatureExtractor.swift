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
        let interval = DateInterval(start: session.start, end: session.end)

        // Vitals are queried concurrently — six sequential round trips to the
        // health store is a visible pause on a cold refresh. Each returns nil on
        // failure: one missing signal should degrade the record, not fail it.
        async let avgHRTask = measuredAverage(.heartRate, unit: .beatsPerMinute, in: interval)
        async let minHRTask = measuredMinimum(.heartRate, unit: .beatsPerMinute, in: interval)
        // Allowing up to 24h after wake, not just up to `session.end`: Apple
        // computes this once for the calendar day, sometimes later in the day
        // than the moment someone wakes up, so a strict "before wake" cutoff
        // would frequently miss that day's own RHR and silently fall back to
        // the previous day's.
        async let restingHRTask = measuredMostRecent(
            .restingHeartRate, unit: .beatsPerMinute, onOrBefore: session.end.addingTimeInterval(86_400)
        )
        async let hrvTask = measuredAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: interval)
        async let respiratoryTask = measuredAverage(.respiratoryRate, unit: .breathsPerMinute, in: interval)
        async let spo2Task = measuredAverage(.oxygenSaturation, unit: .percent(), in: interval)
        async let wristTempTask = measuredAverage(.appleSleepingWristTemperature, unit: .degreeCelsius(), in: interval)
        async let breathingTask = measuredAverage(.appleSleepingBreathingDisturbances, unit: .percent(), in: interval)

        let avgHROutcome = await avgHRTask
        let minHROutcome = await minHRTask
        let restingHROutcome = await restingHRTask
        let hrvOutcome = await hrvTask
        let respiratoryOutcome = await respiratoryTask
        // HKUnit.percent() yields a 0–1 fraction, NOT 0–100. Forgetting this is
        // how you end up displaying "0.97% blood oxygen".
        let spo2Outcome = await spo2Task.map { $0 * 100 }
        let wristTempOutcome = await wristTempTask
        // Breathing disturbances also arrive as a 0-1 fraction under
        // HKUnit.percent(), same trap as SpO2.
        let breathingOutcome = await breathingTask.map { $0 * 100 }

        let workoutHours = await lastWorkoutContext(before: session.start)
        let exercisePrevious = await exerciseMinutes(onDayOf: session.start)

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
            date: Calendar.current.startOfDay(for: session.end),
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
            hrv7DayAvg: baseline?.hrv7DayAvg,
            sleepDebtMinutes: baseline?.sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: workoutHours,
            exerciseMinutesPreviousDay: exercisePrevious,
            sourceName: session.sourceName,
            isMock: false,
            stageSegments: session.segments
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
        in interval: DateInterval
    ) async -> MeasurementOutcome {
        do {
            guard let value = try await healthKit.average(identifier, unit: unit, in: interval) else {
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
        in interval: DateInterval
    ) async -> MeasurementOutcome {
        do {
            guard let value = try await healthKit.minimum(identifier, unit: unit, in: interval) else {
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
        onOrBefore cutoff: Date
    ) async -> MeasurementOutcome {
        do {
            guard let value = try await healthKit.mostRecentSample(identifier, unit: unit, onOrBefore: cutoff) else {
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
    /// up to bedtime.
    private func exerciseMinutes(onDayOf bedtime: Date) async -> Double? {
        let dayStart = Calendar.current.startOfDay(for: bedtime)
        guard dayStart < bedtime else { return nil }
        let interval = DateInterval(start: dayStart, end: bedtime)
        return try? await healthKit.sum(.appleExerciseTime, unit: .minute(), in: interval)
    }
}

// MARK: - Units

extension HKUnit {
    static var beatsPerMinute: HKUnit { .count().unitDivided(by: .minute()) }
    static var breathsPerMinute: HKUnit { .count().unitDivided(by: .minute()) }
}

// MARK: - Rolling baseline

/// Comparative context computed from stored history.
///
/// Every field is optional because history accrues over time: a user on night
/// three legitimately has no 7-day average, and the insight engine must degrade
/// gracefully rather than pretend.
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
        wristTempBaselineC: nil,
        bedtimeConsistencyMinutes: nil,
        sampleCount: 0
    )
}
