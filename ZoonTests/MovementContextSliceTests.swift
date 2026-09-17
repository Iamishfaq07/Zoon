import XCTest

/// §8. "How much had I walked by now, compared with the last four Tuesdays"
/// only means anything if all five are measured to the same point in the day.
///
/// The coordinator used to take today's seconds since midnight and add them to
/// each comparison day's midnight. Four weeks is long enough to contain a
/// clock change, and a day containing one is twenty-three or twenty-five hours
/// long — so the comparison silently slid an hour, in the direction that
/// flatters or alarms depending on the season.
final class MovementContextSliceTests: XCTestCase {

    /// London, because it changes its clocks and its transitions land at a
    /// time that is easy to reason about: 01:00 UTC, in the small hours.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        return calendar.date(from: components)!
    }

    private func clockTime(_ date: Date) -> DateComponents {
        calendar.dateComponents([.hour, .minute], from: date)
    }

    // MARK: - The ordinary case

    func testAnOrdinaryWeekEndsAtTheSameClockTime() throws {
        let now = date(2026, 6, 16, 15, 20)
        let slice = try XCTUnwrap(
            MovementContext.comparableSlice(of: date(2026, 6, 9, 12), matching: now, calendar: calendar)
        )
        XCTAssertEqual(clockTime(slice.end).hour, 15)
        XCTAssertEqual(clockTime(slice.end).minute, 20)
        XCTAssertEqual(slice.start, calendar.startOfDay(for: date(2026, 6, 9, 12)))
    }

    /// The slice starts at that day's own midnight, not today's, whichever
    /// hour of the day it is asked about.
    func testTheSliceStartsAtTheComparisonDaysOwnMidnight() throws {
        let now = date(2026, 6, 16, 6, 5)
        let day = date(2026, 6, 2, 19)
        let slice = try XCTUnwrap(
            MovementContext.comparableSlice(of: day, matching: now, calendar: calendar)
        )
        XCTAssertEqual(slice.start, calendar.startOfDay(for: day))
        XCTAssertEqual(clockTime(slice.end).hour, 6)
    }

    // MARK: - The clock changes

    /// 29 March 2026 is a twenty-three-hour day in London. Elapsed-seconds
    /// arithmetic measured it to 14:00 while today was measured to 15:00.
    func testASpringForwardDayIsStillMeasuredToTheSameClockTime() throws {
        let now = date(2026, 4, 5, 15)
        let springForward = date(2026, 3, 29, 12)
        let slice = try XCTUnwrap(
            MovementContext.comparableSlice(of: springForward, matching: now, calendar: calendar)
        )
        XCTAssertEqual(clockTime(slice.end).hour, 15, "the slice slid off 15:00")

        // And it really was a short day: the old arithmetic would have landed
        // an hour early, which is what this is worth testing for.
        let elapsed = now.timeIntervalSince(calendar.startOfDay(for: now))
        let old = calendar.startOfDay(for: springForward).addingTimeInterval(elapsed)
        XCTAssertEqual(calendar.component(.hour, from: old), 16)
        XCTAssertNotEqual(old, slice.end)
    }

    /// 25 October 2026 is a twenty-five-hour day. The error goes the other
    /// way: the baseline gained an hour of walking nobody had done by then.
    func testAFallBackDayIsStillMeasuredToTheSameClockTime() throws {
        let now = date(2026, 11, 1, 15)
        let fallBack = date(2026, 10, 25, 12)
        let slice = try XCTUnwrap(
            MovementContext.comparableSlice(of: fallBack, matching: now, calendar: calendar)
        )
        XCTAssertEqual(clockTime(slice.end).hour, 15)

        let elapsed = now.timeIntervalSince(calendar.startOfDay(for: now))
        let old = calendar.startOfDay(for: fallBack).addingTimeInterval(elapsed)
        XCTAssertEqual(calendar.component(.hour, from: old), 14)
    }

    /// A slice measured to a real clock time is the same length as the day it
    /// sits in, not the same length as today's.
    func testTheSliceLengthFollowsTheComparisonDayNotToday() throws {
        let now = date(2026, 4, 5, 15)
        let short = try XCTUnwrap(
            MovementContext.comparableSlice(of: date(2026, 3, 29, 12), matching: now, calendar: calendar)
        )
        XCTAssertEqual(short.duration / 3600, 14, accuracy: 0.001, "a 23-hour day's 15:00 is 14 hours in")
    }

    // MARK: - Refusing an hour that did not happen

    /// Clocks go forward at 01:00 on 29 March 2026, so 01:30 has no instant on
    /// that day. There is no honest slice to that point, and inventing one
    /// (02:30, say) would compare thirty minutes against ninety.
    func testAnHourThatNeverHappenedHasNoSlice() {
        XCTAssertNil(
            MovementContext.comparableSlice(
                of: date(2026, 3, 29, 12), matching: date(2026, 4, 5, 1, 30), calendar: calendar
            )
        )
    }

    /// Midnight itself is not a slice: there is nothing in it to compare.
    func testMidnightHasNoSlice() {
        XCTAssertNil(
            MovementContext.comparableSlice(
                of: date(2026, 6, 9, 12), matching: date(2026, 6, 16, 0), calendar: calendar
            )
        )
    }
}
