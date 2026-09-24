import XCTest

/// Mood and sleep (Apple Health State of Mind) and measured morning daylight.
final class MoodAndDaylightTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func day(_ n: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: n))!
    }

    private func at(_ n: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: n, hour: hour, minute: minute))!
    }

    // MARK: - Morning daylight

    func testTheWindowIsFiveToElevenAndGrowsWithTheMorning() throws {
        let full = try XCTUnwrap(MorningDaylight.window(on: day(10), now: at(15, 0), calendar: calendar))
        XCTAssertEqual(full.start, at(10, 5))
        XCTAssertEqual(full.end, at(10, 11))
        let partial = try XCTUnwrap(MorningDaylight.window(on: day(10), now: at(10, 8, 30), calendar: calendar))
        XCTAssertEqual(partial.end, at(10, 8, 30))
        XCTAssertNil(MorningDaylight.window(on: day(10), now: at(10, 4), calendar: calendar), "not open yet")
    }

    func testOnlyEnoughMeasuredDaylightCounts() {
        XCTAssertTrue(MorningDaylight.counts(10))
        XCTAssertTrue(MorningDaylight.counts(42))
        XCTAssertFalse(MorningDaylight.counts(9.9))
        XCTAssertFalse(MorningDaylight.counts(nil), "unmeasured is not no, and not yes")
        XCTAssertFalse(MorningDaylight.counts(.nan))
    }

    func testTheMorningBelongsToTheNightThatFollowsIt() {
        XCTAssertEqual(MorningDaylight.nightDate(for: at(10, 9), calendar: calendar), day(11))
    }

    // MARK: - Mood and sleep

    /// A night that ended on the morning of day `n`.
    private func night(_ n: Int, asleep: Double, need: Double? = 480) -> SleepNightFeatures {
        var night = Fixture.night(daysAgo: 0, timeAsleepMinutes: asleep, timeZoneIdentifier: "UTC", wakeDay: day(n))
        night.sleepNeedBaselineMinutes = need
        return night
    }

    private func mood(_ n: Int, _ valence: Double) -> MoodSleepLink.DailyMood {
        MoodSleepLink.DailyMood(day: day(n), valence: valence)
    }

    func testNothingIsSaidUntilBothSidesHaveEnoughDays() {
        let nights = (1...8).map { night($0, asleep: $0 <= 4 ? 480 : 360) }
        let moods = (1...8).map { mood($0, 0.3) }
        let result = MoodSleepLink.compute(moods: moods, nights: nights, calendar: calendar)
        XCTAssertEqual(result.daysAfterFullNights, 4)
        XCTAssertEqual(result.daysAfterShortNights, 4)
        XCTAssertFalse(result.isReady)
        XCTAssertNil(result.difference)
        XCTAssertTrue(result.sentence.contains("1 more after a full night"), result.sentence)
    }

    func testBetterMoodAfterFullNightsIsDescribedAsAnAssociation() throws {
        let nights = (1...12).map { night($0, asleep: $0 <= 6 ? 490 : 360) }
        let moods = (1...12).map { mood($0, $0 <= 6 ? 0.5 : 0.1) }
        let result = MoodSleepLink.compute(moods: moods, nights: nights, calendar: calendar)
        XCTAssertTrue(result.isReady)
        XCTAssertEqual(try XCTUnwrap(result.difference), 0.4, accuracy: 0.0001)
        XCTAssertTrue(result.sentence.contains("more pleasant"), result.sentence)
        XCTAssertTrue(result.sentence.contains("does not show which came first"), result.sentence)
        XCTAssertFalse(DiagnosticLanguageGuard.rejects(result.sentence), result.sentence)
    }

    func testASmallDifferenceIsReportedAsNone() {
        let nights = (1...12).map { night($0, asleep: $0 <= 6 ? 490 : 360) }
        let moods = (1...12).map { mood($0, $0 <= 6 ? 0.25 : 0.2) }
        let result = MoodSleepLink.compute(moods: moods, nights: nights, calendar: calendar)
        XCTAssertTrue(result.sentence.contains("about the same"), result.sentence)
    }

    /// In-between nights and nights with no recorded need prove nothing.
    func testAmbiguousNightsAndUnknownNeedAreLeftOut() {
        let nights = [
            night(1, asleep: 440),             // 40 min short: neither
            night(2, asleep: 300, need: nil),  // need unknown
            night(3, asleep: 475)              // within tolerance: full
        ]
        let result = MoodSleepLink.compute(moods: [mood(1, 0.1), mood(2, 0.1), mood(3, 0.1), mood(4, 0.9)], nights: nights, calendar: calendar)
        XCTAssertEqual(result.daysAfterFullNights, 1)
        XCTAssertEqual(result.daysAfterShortNights, 0)
    }

    func testSeveralLogsOnADayBecomeOneMean() {
        let means = MoodSleepLink.dailyMeans([
            (date: at(5, 8), valence: 0.2),
            (date: at(5, 20), valence: 0.6),
            (date: at(6, 9), valence: -0.4),
            (date: at(6, 10), valence: .nan)
        ], calendar: calendar)
        XCTAssertEqual(means.count, 2)
        XCTAssertEqual(means[0].day, day(5))
        XCTAssertEqual(means[0].valence, 0.4, accuracy: 0.0001)
        XCTAssertEqual(means[1].valence, -0.4, accuracy: 0.0001)
    }

    func testOutOfRangeValenceIsClamped() {
        let nights = (1...10).map { night($0, asleep: $0 <= 5 ? 490 : 360) }
        let moods = (1...10).map { mood($0, $0 <= 5 ? 3 : -3) }
        let result = MoodSleepLink.compute(moods: moods, nights: nights, calendar: calendar)
        XCTAssertEqual(result.moodAfterFull, 1)
        XCTAssertEqual(result.moodAfterShort, -1)
    }
}
