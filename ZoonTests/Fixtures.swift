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
        /// `SleepNightFeatures.sleepDebtMinutes` is a `let`, so a test that
        /// needs a night carrying debt has to say so when the night is
        /// built rather than assigning afterwards.
        sleepDebtMinutes: Double? = 0,
        avgHRV: Double? = 55,
        restingHeartRate: Double? = 54,
        minHeartRate: Double? = 48,
        avgRespiratoryRate: Double? = 14.5,
        wristTempDeltaC: Double? = 0.0,
        avgSpO2: Double? = 97,
        wakeCount: Int = 2,
        breathingDisturbances: Double? = 1.0,
        breathingDisturbancesClassification: BreathingDisturbanceClassification? = nil,
        lastWorkoutHoursBeforeBed: Double? = nil,
        /// Which app or device wrote the night. Defaulted so every existing
        /// caller is unchanged; `SourceCoverage` needs it because coverage is
        /// measured per source.
        sourceName: String = "Fixture",
        /// The stable identity `SourceCoverage` prefers when matching. `nil`
        /// by default so existing callers keep exercising the name fallback,
        /// which is what every night stored before the extractor started
        /// passing one through looks like.
        sourceBundleIdentifier: String? = nil,
        /// `false` writes the night as one undifferentiated asleep block, the
        /// way a source that reports no stages does. Not the same as a short
        /// night: the sleep is all there, the structure is not.
        /// Naps or split-sleep credited to this night. `total24hAsleepMinutes`
        /// is main sleep plus this, and that total is the basis the shortfall,
        /// the need and the streak engine all measure against — so a test
        /// about goal-met behaviour needs to be able to set it.
        secondaryAsleepMinutes: Double = 0,
        /// Bedtime hour in local time. `nil` keeps the default anchoring
        /// (wake at 07:00, bedtime derived from `timeInBedMinutes`), which is
        /// what every existing caller relies on. Supplied, the night is
        /// anchored on bedtime instead and wake follows -- needed by anything
        /// testing *when* someone slept rather than how long.
        bedtimeHour: Int? = nil,
        /// Minutes added to `bedtimeHour`, for drift cases. Negative is
        /// earlier.
        bedtimeMinuteOffset: Int = 0,
        staged: Bool = true,
        /// Overrides the default 18/22 split when a test needs a specific
        /// stage mix (demographic-prior scoring, for example).
        deepMinutes: Double? = nil,
        remMinutes: Double? = nil,
        /// Whether a raw wrist-temperature reading arrived. Defaults to
        /// following `wristTempDeltaC`, which is what a night with enough
        /// history behind it looks like -- pass `true` with a nil delta to
        /// build the first week of an install, where the sensor works and the
        /// baseline does not exist yet.
        wristTempMeasured: Bool? = nil,
        /// Who wrote each measurement. Empty by default, which is the honest
        /// shape of every night recorded before provenance was captured.
        measurementSources: NightMeasurementSources = .empty,
        /// The zone the night was recorded in. Travel tests need this: day
        /// identity is a civil date reckoned where the sleeper was, and the
        /// whole point of `SleepDayKey` is that it survives the sleeper
        /// moving between zones.
        timeZoneIdentifier: String = TimeZone.current.identifier,
        /// Anchors the night on a specific wake day instead of counting back
        /// from now, so a test can sit a run of nights across a known DST
        /// boundary or a known flight.
        wakeDay: Date? = nil,
        /// Whether the source reported a time in bed of its own. `false` --
        /// measured -- keeps every existing caller unchanged. Apple Watch
        /// alone never reports one, and a night whose window was inferred
        /// from the sleep period has an efficiency that is an artefact of
        /// that inference rather than a measurement of anything, which is
        /// the distinction `SleepOpportunity` refuses to attribute across.
        timeInBedIsEstimated: Bool = false,
        /// Time awake inside the sleep window. Defaults to in-bed minus
        /// asleep, which is what a night with no separate awake reading looks
        /// like -- supplied, it decouples WASO from efficiency, which
        /// anything testing fragmentation against duration needs.
        awakeMinutes: Double? = nil
    ) -> SleepNightFeatures {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let wake = wakeDay ?? calendar.date(byAdding: .day, value: -daysAgo, to: .now)!
        let bedtime: Date
        let wakeTime: Date
        if let bedtimeHour {
            // Anchored on bedtime. The hour is set on the day *before* the
            // wake day whenever it falls in the evening, so a 23:00 bedtime
            // belongs to the night that ends on `wake`, not the one starting
            // that evening.
            let anchorDay = bedtimeHour >= 12
                ? calendar.date(byAdding: .day, value: -1, to: wake) ?? wake
                : wake
            let anchored = calendar.date(
                bySettingHour: bedtimeHour, minute: 0, second: 0, of: anchorDay
            ) ?? wake
            bedtime = anchored.addingTimeInterval(Double(bedtimeMinuteOffset) * 60)
            wakeTime = bedtime.addingTimeInterval(timeInBedMinutes * 60)
        } else {
            wakeTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: wake) ?? wake
            bedtime = wakeTime.addingTimeInterval(-timeInBedMinutes * 60)
        }

        return SleepNightFeatures(
            date: calendar.startOfDay(for: wakeTime),
            bedtime: bedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBedMinutes,
            timeInBedIsEstimated: timeInBedIsEstimated,
            timeAsleepMinutes: timeAsleepMinutes,
            sleepEfficiencyPercent: timeInBedMinutes > 0
                ? min(100, timeAsleepMinutes / timeInBedMinutes * 100) : 0,
            coreMinutes: staged ? max(0, timeAsleepMinutes - (deepMinutes ?? timeAsleepMinutes * 0.18) - (remMinutes ?? timeAsleepMinutes * 0.22)) : 0,
            deepMinutes: staged ? (deepMinutes ?? timeAsleepMinutes * 0.18) : 0,
            remMinutes: staged ? (remMinutes ?? timeAsleepMinutes * 0.22) : 0,
            unspecifiedAsleepMinutes: staged ? 0 : timeAsleepMinutes,
            awakeMinutes: awakeMinutes ?? max(0, timeInBedMinutes - timeAsleepMinutes),
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
            sleepDebtMinutes: sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: nil,
            secondaryAsleepMinutes: secondaryAsleepMinutes,
            sourceName: sourceName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            isMock: true,
            timeZoneIdentifier: timeZoneIdentifier,
            measurementSources: measurementSources,
            wristTempMeasured: wristTempMeasured ?? (wristTempDeltaC != nil)
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
