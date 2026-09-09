import XCTest

/// Academic full-24h SRI. The user-facing metric remains `SleepRegularity`.
final class SleepRegularityIndexTests: XCTestCase {

    func testPerfectlyConsistentScheduleScoresAtTheTop() {
        let nights = Fixture.consecutiveNights(14)
        let sri = SleepRegularityIndex.compute(nights: nights)
        XCTAssertTrue(sri.hasEnoughData)
        XCTAssertGreaterThan(sri.index, 95)
    }

    func testBelowMinimumDaysIsFlaggedNotScored() {
        let nights = Fixture.consecutiveNights(5)
        let sri = SleepRegularityIndex.compute(nights: nights)
        XCTAssertFalse(sri.hasEnoughData)
        XCTAssertEqual(sri.dayCount, 5)
    }

    func testANapOnOnlyOneDayLowersTheIndex() {
        let calendar = Calendar.current
        var nights = Fixture.consecutiveNights(8)
        let target = nights[3]
        let napStart = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: target.date)!
        let napEnd = napStart.addingTimeInterval(90 * 60)
        nights[3] = SleepNightFeatures(
            date: target.date,
            bedtime: target.bedtime,
            wakeTime: target.wakeTime,
            timeInBedMinutes: target.timeInBedMinutes,
            timeAsleepMinutes: target.timeAsleepMinutes,
            sleepEfficiencyPercent: target.sleepEfficiencyPercent,
            coreMinutes: target.coreMinutes,
            deepMinutes: target.deepMinutes,
            remMinutes: target.remMinutes,
            unspecifiedAsleepMinutes: target.unspecifiedAsleepMinutes,
            awakeMinutes: target.awakeMinutes,
            wakeCount: target.wakeCount,
            sleepLatencyMinutes: target.sleepLatencyMinutes,
            avgHeartRate: target.avgHeartRate,
            minHeartRate: target.minHeartRate,
            avgHRV: target.avgHRV,
            avgRespiratoryRate: target.avgRespiratoryRate,
            avgSpO2: target.avgSpO2,
            wristTempDeltaC: target.wristTempDeltaC,
            hrv7DayAvg: target.hrv7DayAvg,
            sleepDebtMinutes: target.sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: target.lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: target.exerciseMinutesPreviousDay,
            sourceName: target.sourceName,
            stageSegments: [
                StageSegment(stage: .core, start: target.bedtime, end: target.wakeTime),
                StageSegment(stage: .unspecified, start: napStart, end: napEnd)
            ]
        )

        let withNap = SleepRegularityIndex.compute(nights: nights)
        let without = SleepRegularityIndex.compute(nights: Fixture.consecutiveNights(8))
        XCTAssertLessThan(withNap.index, without.index)
    }

    func testGapInRecordIsSkippedNotScoredAsIrregularity() {
        let calendar = Calendar.current
        var nights = Fixture.consecutiveNights(7)
        let farFuture = calendar.date(byAdding: .day, value: 10, to: nights.last!.date)!
        nights.append(nights[0].withDate(farFuture))
        let sri = SleepRegularityIndex.compute(nights: nights)
        XCTAssertEqual(sri.validPairCount, 6, "The 10-day gap must not become a seventh pair")
        XCTAssertGreaterThan(sri.index, 90)
    }

    func testDaytimeAwakeAgreementIsCounted() {
        // Two identical nights. Full-day SRI includes ~16h of daytime
        // awake-awake agreement the windowed metric ignores, so it must
        // score at least as high as `SleepRegularity` on the same input.
        let nights = Fixture.consecutiveNights(8)
        let full = SleepRegularityIndex.compute(nights: nights)
        let windowed = SleepRegularity.compute(nights: nights)
        XCTAssertGreaterThanOrEqual(full.index, windowed.index - 1)
    }
}

private extension SleepNightFeatures {
    func withDate(_ newDate: Date) -> SleepNightFeatures {
        let calendar = Calendar.current
        let dayDelta = calendar.dateComponents([.day], from: date, to: newDate).day ?? 0
        return SleepNightFeatures(
            date: newDate,
            bedtime: calendar.date(byAdding: .day, value: dayDelta, to: bedtime) ?? bedtime,
            wakeTime: calendar.date(byAdding: .day, value: dayDelta, to: wakeTime) ?? wakeTime,
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
            wristTempDeltaC: wristTempDeltaC,
            breathingDisturbances: breathingDisturbances,
            hrv7DayAvg: hrv7DayAvg,
            sleepDebtMinutes: sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            sourceName: sourceName,
            isMock: isMock
        )
    }
}
