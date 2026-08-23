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

    // MARK: - obligationWeekdays

    /// The actual fix: which nights count as "work" vs. "free" for the
    /// weekday/weekend midpoint split (and social jetlag) used to hardcode
    /// the calendar weekend with no way to correct it. Two weeks of nights
    /// with a clearly later bedtime on Saturday/Sunday than every other
    /// day -- with the default Mon-Fri obligation set that split reads as a
    /// real social-jetlag pattern; reconfigured so Saturday/Sunday count as
    /// obligation days instead, the same two days move into the "work"
    /// bucket and the split should read the other way.
    func testObligationWeekdaysControlsWorkFreeMidpointSplit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2024-01-01 was a Monday.
        let mondayJan1 = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!

        func night(dayOffset: Int) -> SleepNightFeatures {
            let wakeDate = calendar.date(byAdding: .day, value: dayOffset, to: mondayJan1)!
            let weekday = calendar.component(.weekday, from: wakeDate)
            let isSaturdayOrSunday = weekday == 1 || weekday == 7
            let wakeTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: wakeDate)!
            // Saturday/Sunday nights run two hours later at both ends --
            // a clear, unambiguous midpoint shift versus every other day.
            let bedtime = wakeTime.addingTimeInterval(-(isSaturdayOrSunday ? 6 : 8) * 3600)
            return SleepNightFeatures(
                date: wakeDate, bedtime: bedtime, wakeTime: wakeTime,
                timeInBedMinutes: wakeTime.timeIntervalSince(bedtime) / 60,
                timeAsleepMinutes: wakeTime.timeIntervalSince(bedtime) / 60 - 10,
                sleepEfficiencyPercent: 95,
                coreMinutes: 200, deepMinutes: 80, remMinutes: 90,
                unspecifiedAsleepMinutes: 0, awakeMinutes: 10, wakeCount: 1,
                sleepLatencyMinutes: 10,
                avgHeartRate: 60, minHeartRate: 50, restingHeartRate: 52,
                avgHRV: 50, avgRespiratoryRate: 14, avgSpO2: 97,
                wristTempDeltaC: 0, breathingDisturbances: 1,
                hrv7DayAvg: 50, sleepDebtMinutes: 0,
                lastWorkoutHoursBeforeBed: nil, exerciseMinutesPreviousDay: nil,
                sourceName: "Fixture", isMock: true
            )
        }

        let nights = (0..<14).map(night)

        let defaultSplit = SleepRegularity.compute(nights: nights, calendar: calendar)
        guard let defaultWeekday = defaultSplit.weekdayMidpoint, let defaultWeekend = defaultSplit.weekendMidpoint else {
            return XCTFail("expected both midpoints with two full weeks of nights")
        }
        // Saturday/Sunday's later bedtime means a later (more positive, or
        // less negative) midpoint than the rest of the week.
        XCTAssertGreaterThan(defaultWeekend, defaultWeekday)

        let invertedSplit = SleepRegularity.compute(
            nights: nights, obligationWeekdays: [1, 7], calendar: calendar
        )
        guard let invertedWeekday = invertedSplit.weekdayMidpoint, let invertedWeekend = invertedSplit.weekendMidpoint else {
            return XCTFail("expected both midpoints with two full weeks of nights")
        }
        // With Saturday/Sunday reconfigured as the obligation days, the
        // later-bedtime nights are now in the "weekday" (obligation)
        // bucket, so the relationship flips.
        XCTAssertGreaterThan(invertedWeekday, invertedWeekend)
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
            sleepDebtMinutes: sleepDebtMinutes,
            lastWorkoutHoursBeforeBed: lastWorkoutHoursBeforeBed,
            exerciseMinutesPreviousDay: exerciseMinutesPreviousDay,
            sourceName: sourceName,
            isMock: isMock
        )
    }
}
