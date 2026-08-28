import Foundation

/// Synthetic `SleepNightFeatures` builder for tests.
///
/// A logic-only test bundle has no HealthKit, no simulator sleep data, and no
/// device -- every fixture here is built entirely by hand so the pure
/// algorithms in `Shared/` can be exercised deterministically, the same
/// reasoning `MockData` uses for previews.
///
/// No `import` for `Shared`'s types: this target compiles `Shared/`'s source
/// files directly, the same way the app, widget, and watch targets do (see
/// `Tools/generate-pbxproj.py`) rather than linking a framework, so
/// `SleepNightFeatures` and friends are simply in-module here.
enum Fixture {

    /// A fully-populated, unremarkable night: every physiological signal
    /// present, nothing missing. The baseline every "what happens when X is
    /// missing" test starts from and removes one field at a time.
    static func night(
        daysAgo: Int = 0,
        timeAsleepMinutes: Double = 450,
        timeInBedMinutes: Double = 480,
        avgHRV: Double? = 55,
        restingHeartRate: Double? = 54,
        minHeartRate: Double? = 48,
        avgRespiratoryRate: Double? = 14.5,
        wristTempDeltaC: Double? = 0.0,
        avgSpO2: Double? = 97,
        wakeCount: Int = 2,
        breathingDisturbances: Double? = 1.0,
        breathingDisturbancesClassification: BreathingDisturbanceClassification? = nil,
        lastWorkoutHoursBeforeBed: Double? = nil
    ) -> SleepNightFeatures {
        let calendar = Calendar.current
        let wake = calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
        let wakeTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: wake) ?? wake
        let bedtime = wakeTime.addingTimeInterval(-timeInBedMinutes * 60)

        return SleepNightFeatures(
            date: calendar.startOfDay(for: wakeTime),
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBedMinutes,
            timeAsleepMinutes: timeAsleepMinutes,
            sleepEfficiencyPercent: timeInBedMinutes > 0
                ? min(100, timeAsleepMinutes / timeInBedMinutes * 100) : 0,
            coreMinutes: timeAsleepMinutes * 0.55,
            deepMinutes: timeAsleepMinutes * 0.18,
            remMinutes: timeAsleepMinutes * 0.22,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: max(0, timeInBedMinutes - timeAsleepMinutes),
            wakeCount: wakeCount,
            sleepLatencyMinutes: 12,
            avgHeartRate: minHeartRate.map { $0 + 8 },
            minHeartRate: minHeartRate,
            restingHeartRate: restingHeartRate,
            avgHRV: avgHRV,
            avgRespiratoryRate: avgRespiratoryRate,
            avgSpO2: avgSpO2,
            wristTempDeltaC: wristTempDeltaC,
            breathingDisturbances: breathingDisturbances,
            breathingDisturbancesClassification: breathingDisturbancesClassification,
            hrv7DayAvg: avgHRV,
            sleepDebtMinutes: 0,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: nil,
            sourceName: "Fixture",
            isMock: true
        )
    }

    /// `count` consecutive nights, oldest first, each one calendar day apart
    /// and otherwise identical to `night(daysAgo:)`'s defaults -- the shape
    /// `SleepRegularity` and every rolling-baseline calculation expects.
    static func consecutiveNights(_ count: Int, template: (Int) -> SleepNightFeatures = { night(daysAgo: $0) }) -> [SleepNightFeatures] {
        (0..<count).map { template(count - $0) }.sorted { $0.date < $1.date }
    }

    /// Maps a built `SleepSession` onto the sleep half of
    /// `SleepNightFeatures`, so a test can carry real builder output through
    /// persistence and analytics instead of hand-writing a night that never
    /// came out of the pipeline.
    ///
    /// Deliberately covers only what `SleepSessionBuilder` itself produces.
    /// The vitals half is `FeatureExtractor.extract(from:baseline:)`, which is
    /// async and reads HealthKit directly with no protocol to substitute, so
    /// it cannot be exercised from a test bundle. Every vital here is `nil`
    /// for that reason, not because a real night would have none.
    static func night(
        from session: SleepSession,
        need: Double? = nil,
        secondaryAsleepMinutes: Double = 0
    ) -> SleepNightFeatures {
        let asleep = session.totalAsleepMinutes
        let inBed = session.timeInBed / 60
        return SleepNightFeatures(
            date: session.wakeDate,
            bedtime: session.start,
            wakeTime: session.end,
            timeInBedMinutes: inBed,
            timeAsleepMinutes: asleep,
            sleepEfficiencyPercent: inBed > 0 ? min(100, asleep / inBed * 100) : 0,
            coreMinutes: session.stageMinutes[.core] ?? 0,
            deepMinutes: session.stageMinutes[.deep] ?? 0,
            remMinutes: session.stageMinutes[.rem] ?? 0,
            unspecifiedAsleepMinutes: session.stageMinutes[.unspecified] ?? 0,
            awakeMinutes: session.stageMinutes[.awake] ?? 0,
            wakeCount: 0,
            sleepLatencyMinutes: nil,
            avgHeartRate: nil,
            minHeartRate: nil,
            avgHRV: nil,
            avgRespiratoryRate: nil,
            avgSpO2: nil,
            wristTempDeltaC: nil,
            hrv7DayAvg: nil,
            sleepDebtMinutes: nil,
            lastWorkoutHoursBeforeBed: nil,
            exerciseMinutesPreviousDay: nil,
            secondaryAsleepMinutes: secondaryAsleepMinutes,
            sleepNeedBaselineMinutes: need,
            sourceName: session.sourceName,
            sourceBundleIdentifier: session.sourceBundleIdentifier,
            stageSegments: session.segments,
            timeZoneIdentifier: session.timeZoneIdentifier
        )
    }
}
