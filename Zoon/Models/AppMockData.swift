import Foundation

/// Mock data that depends on app-target types.
///
/// Split from `Shared/MockData.swift` because that file is compiled into the
/// widget extension too, and the widget has no `RollingBaseline`, no
/// `BehaviorTag`, and no correlation engine. Keeping the app-only mocks here is
/// what stops a preview convenience from breaking the extension build.
enum AppMockData {

    /// Rolling baseline matching `MockData.goodNight`.
    static let baseline = RollingBaseline(
        hrv7DayAvg: 61, sleepDebtMinutes14Day: 95, deep7DayAvg: 74,
        duration7DayAvg: 421, efficiency7DayAvg: 89, minHeartRate7DayAvg: 52,
        wristTempBaselineC: 35.1, bedtimeConsistencyMinutes: 38, sampleCount: 7
    )

    /// A fully-populated `DayContext` built by the *real* builder.
    ///
    /// Running the production pipeline over synthetic inputs means a bug in a
    /// scoring formula shows up in a preview on a laptop, not three weeks later
    /// on someone's wrist.
    static func dayContext(goalMinutes: Double = 480) -> DayContext {
        let night = MockData.goodNight
        return DayContextBuilder().build(.init(
            night: night,
            insight: MockData.goodInsight,
            history: MockData.history.filter { $0.date < night.date },
            goalMinutes: goalMinutes,
            yesterdayStrain: MockData.yesterdayStrain,
            todayStrain: MockData.todayStrain,
            hourlyHeartRate: MockData.hourlyHeartRate(wakeTime: night.wakeTime),
            maxHeartRate: 185,
            napMinutes: 0,
            bedtimeConsistencyMinutes: 38
        ))
    }

    /// A rough night, for previewing the low-recovery treatment.
    static func poorDayContext(goalMinutes: Double = 480) -> DayContext {
        let night = MockData.poorNight
        return DayContextBuilder().build(.init(
            night: night,
            insight: MockData.poorInsight,
            history: MockData.history.filter { $0.date < night.date },
            goalMinutes: goalMinutes,
            yesterdayStrain: MockData.yesterdayStrain,
            todayStrain: MockData.todayStrain,
            hourlyHeartRate: MockData.hourlyHeartRate(wakeTime: night.wakeTime),
            maxHeartRate: 185,
            napMinutes: 0,
            bedtimeConsistencyMinutes: 96
        ))
    }

    /// Journal observations with a deliberately visible alcohol signal, so the
    /// correlation screen has something real to render in previews.
    static var journalObservations: [JournalCorrelator.Observation] {
        MockData.history.enumerated().map { index, night in
            let drank = index % 5 == 0
            var tags: Set<BehaviorTag> = []
            if drank { tags.insert(.alcohol) }
            if index % 3 == 0 { tags.insert(.caffeineLate) }
            if index % 4 == 0 { tags.insert(.hardTraining) }
            if index % 2 == 0 { tags.insert(.readBeforeBed) }

            let penalty = drank ? 0.78 : 1.0
            return JournalCorrelator.Observation(
                date: night.date,
                tags: tags,
                recoveryPercent: (night.avgHRV ?? 55) * penalty,
                sleepPerformance: min(100, night.timeAsleepMinutes / 480 * 100) * penalty,
                deepMinutes: night.deepMinutes * penalty,
                remMinutes: night.remMinutes * penalty,
                efficiency: night.sleepEfficiencyPercent * (drank ? 0.94 : 1.0),
                wakeCount: Double(night.wakeCount) * (drank ? 1.6 : 1.0)
            )
        }
    }

    static var correlationFindings: [JournalCorrelator.Finding] {
        JournalCorrelator().topFindingPerTag(from: journalObservations)
    }

    /// A synthetic hypnogram: descending into deep early, more REM toward
    /// morning, a couple of brief awakenings. The shape a real night has.
    static func stageSegments(for night: SleepNightFeatures) -> [StageSegment] {
        let pattern: [(SleepStage, Double)] = [
            (.core, 22), (.deep, 48), (.core, 26), (.rem, 18),
            (.core, 34), (.deep, 30), (.awake, 6), (.core, 28),
            (.rem, 32), (.core, 24), (.deep, 14), (.rem, 26),
            (.core, 20), (.awake, 4), (.rem, 34), (.core, 18)
        ]
        var cursor = night.bedtime.addingTimeInterval(
            (night.sleepLatencyMinutes ?? 10) * 60
        )
        return pattern.map { stage, minutes in
            let start = cursor
            cursor = cursor.addingTimeInterval(minutes * 60)
            return StageSegment(stage: stage, start: start, end: cursor)
        }
    }
}
