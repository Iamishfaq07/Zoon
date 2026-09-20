import Foundation

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
    /// they slept minutes the watch never saw. Efficiency is recomputed
    /// from the new window. Workout-to-bed hours move with bedtime so a
    /// late-workout finding cannot silently keep the uncorrected clock.
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
        let newAsleep = min(timeAsleepMinutes, newInBed)
        let newEfficiency = min(100, max(0, newAsleep / newInBed * 100))
        let workoutHours = lastWorkoutHoursBeforeBed.map { $0 - bedShift / 60 }

        return SleepNightFeatures(
            date: date,
            bedtime: newBed,
            wakeTime: newWake,
            timeInBedMinutes: newInBed,
            timeInBedIsEstimated: timeInBedIsEstimated,
            timeAsleepMinutes: newAsleep,
            sleepEfficiencyPercent: newEfficiency,
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
            stageSegments: stageSegments,
            timeZoneIdentifier: timeZoneIdentifier,
            measurementSources: measurementSources,
            wristTempMeasured: wristTempMeasured,
            sleepApneaEventCount: sleepApneaEventCount,
            stageSourcePriority: stageSourcePriority
        )
    }
}

private func clampShift(_ minutes: Double) -> Double {
    min(LocalSleepCorrection.maximumShiftMinutes,
        max(-LocalSleepCorrection.maximumShiftMinutes, minutes))
}
