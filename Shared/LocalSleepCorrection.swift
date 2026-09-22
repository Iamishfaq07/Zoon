import Foundation

/// How a night's session bounds were obtained.
///
/// Distinct from `SensorTruth.Provenance`, which grades a *kind* of number
/// (a wrist temperature is measured; a REM minute is inferred). This grades
/// the clock times themselves: HealthKit samples, an inferred in-bed window,
/// or a reversible overlay the person applied in Zoon. HealthKit is never
/// written either way.
enum SleepTimingProvenance: String, Codable, Hashable, Sendable {
    case measured
    case estimated
    case locallyCorrected

    var label: String {
        switch self {
        case .measured: "Measured"
        case .estimated: "Estimated"
        case .locallyCorrected: "Locally corrected"
        }
    }

    var explanation: String {
        switch self {
        case .measured:
            "Session bounds came from HealthKit samples."
        case .estimated:
            "Time in bed was inferred because the source wrote no in-bed samples."
        case .locallyCorrected:
            "You moved the bounds in Zoon. Apple Health was not changed."
        }
    }
}

/// A reversible local overlay on a HealthKit night.
///
/// HealthKit is never written. The original samples stay where they are.
/// Zoon's own engines read the overlay so a watch that started the session
/// twenty minutes too early does not keep teaching Autopilot, Need and
/// Recovery the wrong bounds. Exclusion (already on `PersonalSetup.Repair`)
/// drops a night from comparisons entirely; a boundary edit keeps the night
/// and moves only the clock times the person named.
enum LocalSleepCorrection {

    /// Largest shift a person can apply in either direction.
    ///
    /// Ninety minutes. Larger than Autopilot's nightly 20-minute cap on
    /// purpose: this is a one-off correction of a mis-detected edge, not a
    /// schedule change. Past an hour and a half the honest move is to
    /// exclude the night and wait for a better recording.
    static let maximumShiftMinutes = 90.0

    static func apply(
        _ night: SleepNightFeatures,
        repairs: [PersonalSetup.Repair]
    ) -> SleepNightFeatures {
        guard let repair = repairs.first(where: {
            $0.nightKey == night.nightKey && $0.hasBoundaryEdit && !$0.excluded
        }) else { return night }
        return night.shiftingBounds(
            bedtimeShiftMinutes: repair.bedtimeShiftMinutes,
            wakeShiftMinutes: repair.wakeShiftMinutes
        )
    }

    static func apply(
        _ nights: [SleepNightFeatures],
        repairs: [PersonalSetup.Repair]
    ) -> [SleepNightFeatures] {
        nights.map { apply($0, repairs: repairs) }
    }
}

extension SleepNightFeatures {

    /// Moves bedtime and/or wake without inventing extra sleep.
    ///
    /// Time asleep stays the HealthKit measurement unless the new in-bed
    /// window is shorter than that measurement, in which case it is clamped
    /// — the person is saying the session did not last that long, not that
    /// they slept minutes the watch never saw. Stage minutes and segments
    /// are intersected with the corrected window so they cannot outrun
    /// asleep time. Efficiency is recomputed from the new window.
    ///
    /// Workout-to-bed hours move *with* bedtime. A later bedtime widens the
    /// gap to yesterday's session; an earlier bedtime narrows it. A gap that
    /// would go negative means the workout now ends after the corrected
    /// bedtime, so the field is cleared rather than stored as a late-workout
    /// signal with the wrong sign.
    func shiftingBounds(
        bedtimeShiftMinutes: Double,
        wakeShiftMinutes: Double
    ) -> SleepNightFeatures {
        let bedShift = clampShift(bedtimeShiftMinutes)
        let wakeShift = clampShift(wakeShiftMinutes)
        guard abs(bedShift) >= 1 || abs(wakeShift) >= 1 else { return self }

        let newBed = bedtime.addingTimeInterval(bedShift * 60)
        var newWake = wakeTime.addingTimeInterval(wakeShift * 60)
        if newWake <= newBed {
            newWake = newBed.addingTimeInterval(60)
        }
        let newInBed = max(1, newWake.timeIntervalSince(newBed) / 60)

        let stages = LocalSleepCorrectionMath.recomputeStages(
            original: self,
            newBed: newBed,
            newWake: newWake,
            newInBed: newInBed,
            bedtimeShiftMinutes: bedShift
        )
        let workoutHours = LocalSleepCorrectionMath.workoutHoursBeforeBed(
            originalHours: lastWorkoutHoursBeforeBed,
            bedtimeShiftMinutes: bedShift
        )
        let newEfficiency = LocalSleepCorrectionMath.efficiency(
            asleep: stages.asleep,
            inBed: newInBed
        )

        return SleepNightFeatures(
            date: date,
            bedtime: newBed,
            wakeTime: newWake,
            timeInBedMinutes: newInBed,
            timeInBedIsEstimated: timeInBedIsEstimated,
            timeAsleepMinutes: stages.asleep,
            sleepEfficiencyPercent: newEfficiency,
            coreMinutes: stages.core,
            deepMinutes: stages.deep,
            remMinutes: stages.rem,
            unspecifiedAsleepMinutes: stages.unspecified,
            awakeMinutes: stages.awake,
            wakeCount: stages.wakeCount,
            sleepLatencyMinutes: stages.latency,
            avgHeartRate: avgHeartRate,
            minHeartRate: minHeartRate,
            restingHeartRate: restingHeartRate,
            avgHRV: avgHRV,
            avgRespiratoryRate: avgRespiratoryRate,
            avgSpO2: avgSpO2,
            wristTempDeltaC: wristTempDeltaC,
            breathingDisturbances: breathingDisturbances,
            breathingDisturbancesClassification: breathingDisturbancesClassification,
            hrv7DayAvg: hrv7DayAvg,
            sleepDebtMinutes: sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: workoutHours,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            secondaryAsleepMinutes: secondaryAsleepMinutes,
            sleepNeedBaselineMinutes: sleepNeedBaselineMinutes,
            alcoholicBeverages: alcoholicBeverages,
            lateCaffeineMg: lateCaffeineMg,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            isMock: isMock,
            stageSegments: stages.segments,
            timeZoneIdentifier: timeZoneIdentifier,
            measurementSources: measurementSources,
            wristTempMeasured: wristTempMeasured,
            sleepApneaEventCount: sleepApneaEventCount,
            stageSourcePriority: stageSourcePriority,
            timingProvenance: .locallyCorrected
        )
    }
}

/// Pure arithmetic for the overlay. Kept off the night type so the sign
/// of workout timing and the stage-clip invariants can be tested without
/// constructing a full `SleepNightFeatures`.
enum LocalSleepCorrectionMath {

    struct Stages: Equatable, Sendable {
        var asleep: Double
        var core: Double
        var deep: Double
        var rem: Double
        var unspecified: Double
        var awake: Double
        var wakeCount: Int
        var latency: Double?
        var segments: [StageSegment]
    }

    /// Hours between workout end and bedtime move with the bedtime shift.
    ///
    /// `new = old + bedtimeShiftHours`. Later bedtime (positive shift)
    /// widens the gap. A negative result means the session now ends after
    /// the corrected bedtime — not a late workout, just a workout that is
    /// no longer "before bed" — so the value is cleared.
    static func workoutHoursBeforeBed(
        originalHours: Double?,
        bedtimeShiftMinutes: Double
    ) -> Double? {
        guard let originalHours, originalHours.isFinite else { return nil }
        let hours = originalHours + bedtimeShiftMinutes / 60
        guard hours.isFinite, hours >= 0 else { return nil }
        return hours
    }

    static func efficiency(asleep: Double, inBed: Double) -> Double {
        guard inBed > 0, asleep.isFinite, inBed.isFinite else { return 0 }
        return min(100, max(0, asleep / inBed * 100))
    }

    static func recomputeStages(
        original: SleepNightFeatures,
        newBed: Date,
        newWake: Date,
        newInBed: Double,
        bedtimeShiftMinutes: Double
    ) -> Stages {
        if !original.stageSegments.isEmpty {
            return fromSegments(
                original: original,
                newBed: newBed,
                newWake: newWake,
                newInBed: newInBed
            )
        }
        return withoutSegments(
            original: original,
            newInBed: newInBed,
            bedtimeShiftMinutes: bedtimeShiftMinutes
        )
    }

    private static func fromSegments(
        original: SleepNightFeatures,
        newBed: Date,
        newWake: Date,
        newInBed: Double
    ) -> Stages {
        let clipped = original.stageSegments
            .compactMap { $0.intersecting(start: newBed, end: newWake) }
            .mergingAdjacent()
        let core = finite(clipped.minutes(of: .core))
        let deep = finite(clipped.minutes(of: .deep))
        let rem = finite(clipped.minutes(of: .rem))
        let unspecified = finite(clipped.minutes(of: .unspecified))
        let awakeFromStages = finite(clipped.minutes(of: .awake))
        let stagedAsleep = core + deep + rem + unspecified
        let asleepStages: (core: Double, deep: Double, rem: Double, unspecified: Double)
        let asleep: Double
        var outputSegments = clipped
        if stagedAsleep > newInBed {
            // Overlapping stages can sum past the window after a clip.
            // Keep consistent totals; do not leave a hypnogram that
            // disagrees with those totals.
            asleepStages = scaleAsleepStages(
                core: core, deep: deep, rem: rem, unspecified: unspecified, to: newInBed
            )
            asleep = newInBed
            outputSegments = []
        } else {
            asleepStages = (core, deep, rem, unspecified)
            asleep = max(0, stagedAsleep)
        }
        let awake = min(awakeFromStages, max(0, newInBed - asleep))
        let latency: Double?
        if let onset = clipped.first(where: { SleepStage.asleepStages.contains($0.stage) }) {
            latency = max(0, onset.start.timeIntervalSince(newBed) / 60)
        } else {
            latency = nil
        }
        return Stages(
            asleep: asleep,
            core: asleepStages.core,
            deep: asleepStages.deep,
            rem: asleepStages.rem,
            unspecified: asleepStages.unspecified,
            awake: awake,
            wakeCount: wakeCount(from: clipped),
            latency: latency,
            segments: outputSegments
        )
    }

    private static func withoutSegments(
        original: SleepNightFeatures,
        newInBed: Double,
        bedtimeShiftMinutes: Double
    ) -> Stages {
        let newAsleep = min(max(0, original.timeAsleepMinutes), newInBed)
        let scaled = scaleAsleepStages(
            core: original.coreMinutes,
            deep: original.deepMinutes,
            rem: original.remMinutes,
            unspecified: original.unspecifiedAsleepMinutes,
            to: newAsleep
        )
        let awake = min(max(0, original.awakeMinutes), max(0, newInBed - newAsleep))
        let latency: Double?
        if bedtimeShiftMinutes > 0.5 {
            if let old = original.sleepLatencyMinutes {
                let remaining = old - bedtimeShiftMinutes
                latency = remaining >= 0 ? remaining : nil
            } else {
                latency = nil
            }
        } else if bedtimeShiftMinutes < -0.5 {
            // Expanding bedtime earlier invents a prefix with no samples.
            latency = nil
        } else {
            latency = original.sleepLatencyMinutes
        }
        return Stages(
            asleep: newAsleep,
            core: scaled.core,
            deep: scaled.deep,
            rem: scaled.rem,
            unspecified: scaled.unspecified,
            awake: awake,
            wakeCount: newAsleep <= 0 ? 0 : original.wakeCount,
            latency: latency,
            segments: []
        )
    }

    static func scaleAsleepStages(
        core: Double,
        deep: Double,
        rem: Double,
        unspecified: Double,
        to newAsleep: Double
    ) -> (core: Double, deep: Double, rem: Double, unspecified: Double) {
        let total = finite(core) + finite(deep) + finite(rem) + finite(unspecified)
        let target = max(0, finite(newAsleep))
        guard total > 0, target >= 0 else { return (0, 0, 0, 0) }
        if total <= target + 0.01 {
            return (finite(core), finite(deep), finite(rem), finite(unspecified))
        }
        let scale = target / total
        return (core * scale, deep * scale, rem * scale, unspecified * scale)
    }

    static func wakeCount(from segments: [StageSegment]) -> Int {
        guard let onset = segments.first(where: { SleepStage.asleepStages.contains($0.stage) }) else {
            return 0
        }
        return segments.filter { $0.stage == .awake && $0.start >= onset.start }.count
    }

    private static func finite(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

private func clampShift(_ minutes: Double) -> Double {
    guard minutes.isFinite else { return 0 }
    return min(LocalSleepCorrection.maximumShiftMinutes,
               max(-LocalSleepCorrection.maximumShiftMinutes, minutes))
}
