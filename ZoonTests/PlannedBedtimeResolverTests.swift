import XCTest

/// A day is not always 86,400 seconds, and a planned bedtime is a wall-clock
/// time, not an elapsed-seconds offset from midnight.
///
/// All fixed to America/New_York so the transitions are the familiar ones:
/// 2026-03-08 springs forward (23-hour day) and 2026-11-01 falls back
/// (25-hour day).
final class PlannedBedtimeResolverTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private func assertResolves(
        _ minutes: Double,
        from now: Date,
        to expected: Date,
        _ message: String,
        line: UInt = #line
    ) {
        let resolved = PlannedBedtimeResolver.nextOccurrence(
            ofMinutesFromMidnight: minutes, after: now, calendar: calendar
        )
        XCTAssertEqual(resolved, expected, message, line: line)
    }

    // MARK: - The ordinary case still works

    func testEveningBedtimeLaterTodayResolvesToday() {
        assertResolves(
            23 * 60 + 10,
            from: date(2026, 3, 10, 12, 0),
            to: date(2026, 3, 10, 23, 10),
            "a bedtime still ahead today is tonight"
        )
    }

    func testAfterMidnightBedtimeBelongsToTomorrow() {
        // 00:40 has already gone by when someone is deciding at noon. Resolved
        // against today alone it sits in the past, and every evening nap then
        // looks safe to a coach asking "how long until bed".
        assertResolves(
            40,
            from: date(2026, 3, 10, 12, 0),
            to: date(2026, 3, 11, 0, 40),
            "an after-midnight bedtime is tomorrow's, not today's past"
        )
    }

    func testMinutesPastADayWrap() {
        assertResolves(
            1440 + 40,
            from: date(2026, 3, 10, 12, 0),
            to: date(2026, 3, 11, 0, 40),
            "a wrapped target names the same clock time as its unwrapped twin"
        )
    }

    // MARK: - Daylight saving

    /// Midnight plus 23h10m of elapsed seconds lands at 00:10 on the 9th --
    /// an hour late and on the wrong calendar day.
    func testSpringForwardDayKeepsTheWallClockTime() {
        assertResolves(
            23 * 60 + 10,
            from: date(2026, 3, 8, 12, 0),
            to: date(2026, 3, 8, 23, 10),
            "bedtime on a 23-hour day is still 23:10 that evening"
        )
    }

    /// The same arithmetic on a 25-hour day lands an hour early, at 22:10.
    func testFallBackDayKeepsTheWallClockTime() {
        assertResolves(
            23 * 60 + 10,
            from: date(2026, 11, 1, 12, 0),
            to: date(2026, 11, 1, 23, 10),
            "bedtime on a 25-hour day is still 23:10 that evening"
        )
    }

    /// Rolling forward has the same hazard: +86,400 seconds from 23:10 on the
    /// evening before a transition is 00:10 or 22:10, never 23:10.
    func testRollingForwardAcrossSpringForward() {
        assertResolves(
            23 * 60 + 10,
            from: date(2026, 3, 7, 23, 30),
            to: date(2026, 3, 8, 23, 10),
            "tomorrow's bedtime is tomorrow's clock time, not 24 hours later"
        )
    }

    func testRollingForwardAcrossFallBack() {
        assertResolves(
            23 * 60 + 10,
            from: date(2026, 10, 31, 23, 30),
            to: date(2026, 11, 1, 23, 10),
            "tomorrow's bedtime is tomorrow's clock time, not 24 hours later"
        )
    }

    // MARK: - Degenerate input

    func testNegativeMinutesWrapRatherThanReachingIntoYesterday() {
        assertResolves(
            -20,                                   // 23:40
            from: date(2026, 3, 10, 12, 0),
            to: date(2026, 3, 10, 23, 40),
            "a negative offset wraps to the end of the day"
        )
    }

    func testMidnightExactly() {
        assertResolves(
            0,
            from: date(2026, 3, 10, 12, 0),
            to: date(2026, 3, 11, 0, 0),
            "midnight today is already past at noon"
        )
    }
}
