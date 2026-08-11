import XCTest

/// `SleepRegularity.compute` returns a hardcoded index of 0 -- not nil --
/// below its own 7-night minimum. These tests exist because that 0 was, for
/// a while, read as a real "zero regularity" measurement by both
/// `DayContextBuilder` (feeding Sleep Intelligence) and `AchievementsView`
/// (feeding badge progress) instead of being excluded. The fix lives in
/// those two call sites; these tests pin down the contract they both now
/// depend on: `hasEnoughData` is the only correct gate.
final class SleepRegularityTests: XCTestCase {

    func testBelowMinimumNightsReturnsZeroIndexButFlagsInsufficientData() {
        let nights = Fixture.consecutiveNights(5)
        let regularity = SleepRegularity.compute(nights: nights)

        XCTAssertEqual(regularity.index, 0)
        XCTAssertFalse(regularity.hasEnoughData, "5 nights is below SleepRegularity.minimumNights (7)")
        XCTAssertEqual(regularity.nightCount, 5)
    }

    func testAtMinimumNightsHasEnoughData() {
        let nights = Fixture.consecutiveNights(SleepRegularity.minimumNights)
        let regularity = SleepRegularity.compute(nights: nights)

        XCTAssertTrue(regularity.hasEnoughData)
    }

    /// Identical bed/wake times every night should score very close to
    /// perfectly regular once there's enough history to measure it.
    func testPerfectlyConsistentScheduleScoresHigh() {
        let nights = Fixture.consecutiveNights(14)
        let regularity = SleepRegularity.compute(nights: nights)

        XCTAssertTrue(regularity.hasEnoughData)
        XCTAssertGreaterThan(regularity.index, 90)
    }

    /// A gap in the record (watch not worn for a stretch) must not be scored
    /// as irregularity -- nights that aren't a day apart are skipped as
    /// comparisons, not counted as a broken pattern.
    func testGapInRecordDoesNotTankScore() {
        let calendar = Calendar.current
        var nights = Fixture.consecutiveNights(7)
        // Splice a night 10 days later than the record's end, rather than 1.
        let farFuture = calendar.date(byAdding: .day, value: 10, to: nights.last!.date)!
        nights.append(Fixture.night(daysAgo: 0).withDate(farFuture))

        let regularity = SleepRegularity.compute(nights: nights)
        XCTAssertGreaterThan(regularity.index, 80, "A single gap shouldn't collapse an otherwise consistent record")
    }
}

private extension SleepNightFeatures {
    /// Test-only: rebuilds this night at a different date, keeping bedtime's
    /// and wake time's clock components but moving the calendar day, so
    /// `SleepRegularity`'s consecutive-night pairing has something to skip
    /// over.
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
            sleepDebtMinutes14Day: sleepDebtMinutes14Day,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            sourceName: sourceName,
            isMock: isMock
        )
    }
}
