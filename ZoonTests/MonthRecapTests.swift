import XCTest

/// The month recap describes stored nights and nothing else.
final class MonthRecapTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// September 2026, and its nights by day of the month.
    private var september: DateInterval {
        calendar.dateInterval(of: .month, for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!)!
    }

    private func night(day: Int, month: Int = 9, asleep: Double, bedtimeHour: Int = 23) -> SleepNightFeatures {
        let wake = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 7))!
        return Fixture.night(
            timeAsleepMinutes: asleep, timeInBedMinutes: asleep + 30,
            bedtimeHour: bedtimeHour, wakeDay: wake
        )
    }

    func testTooFewNightsGiveNoRecap() {
        let nights = (1...4).map { night(day: $0, asleep: 480) }
        XCTAssertNil(MonthRecap.make(nights: nights, goalMinutes: 480, month: september, calendar: calendar))
    }

    func testCountsAverageAndGoalNights() throws {
        let nights = [night(day: 1, asleep: 420), night(day: 2, asleep: 480), night(day: 3, asleep: 500),
                      night(day: 4, asleep: 400), night(day: 5, asleep: 480)]
        let recap = try XCTUnwrap(MonthRecap.make(nights: nights, goalMinutes: 480, month: september, calendar: calendar))
        XCTAssertEqual(recap.nightCount, 5)
        XCTAssertEqual(recap.averageAsleepMinutes, 456, accuracy: 0.01)
        XCTAssertEqual(recap.goalNights, 3)
        XCTAssertEqual(recap.days.count, 30)
    }

    /// A missing night breaks a run: unrecorded is not met.
    func testTheLongestRunNeedsConsecutiveDays() throws {
        let nights = [1, 2, 3, 5, 6].map { night(day: $0, asleep: 500) } + [night(day: 7, asleep: 300)]
        let recap = try XCTUnwrap(MonthRecap.make(nights: nights, goalMinutes: 480, month: september, calendar: calendar))
        XCTAssertEqual(recap.longestGoalStreak, 3)
    }

    /// 23:30 and 00:30 are an hour apart, not a day.
    func testBedtimesAcrossMidnightAverageSensibly() throws {
        let nights = [night(day: 1, asleep: 450, bedtimeHour: 23), night(day: 2, asleep: 450, bedtimeHour: 0),
                      night(day: 3, asleep: 450, bedtimeHour: 23), night(day: 4, asleep: 450, bedtimeHour: 0),
                      night(day: 5, asleep: 450, bedtimeHour: 0)]
        let recap = try XCTUnwrap(MonthRecap.make(nights: nights, goalMinutes: 480, month: september, calendar: calendar))
        XCTAssertEqual(try XCTUnwrap(recap.typicalBedtimeMinutes), 0, accuracy: 0.5)
    }

    func testTheChangeFromTheMonthBeforeNeedsEnoughNightsThere() throws {
        let august = calendar.dateInterval(of: .month, for: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!)!
        let now = (1...5).map { night(day: $0, asleep: 480) }
        let before = (10...14).map { night(day: $0, month: 8, asleep: 420) }
        let recap = try XCTUnwrap(MonthRecap.make(
            nights: before + now, goalMinutes: 480, month: september, previousMonth: august, calendar: calendar
        ))
        XCTAssertEqual(try XCTUnwrap(recap.changeFromPreviousMinutes), 60, accuracy: 0.01)
        XCTAssertTrue(recap.headline.contains("5 of 5"), recap.headline)

        let thin = try XCTUnwrap(MonthRecap.make(
            nights: Array(before.prefix(2)) + now, goalMinutes: 480, month: september,
            previousMonth: august, calendar: calendar
        ))
        XCTAssertNil(thin.changeFromPreviousMinutes)
    }
}
