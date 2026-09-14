import XCTest

/// The band has to change on its own when a screen is left open across a
/// boundary, and it must do so without polling.
final class PhaseBoundaryTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: minute
        ))!
    }

    /// The boundary list and the band switch must agree. Two lists of the
    /// same four numbers is how a screen refreshes into the wrong band.
    func testEveryBoundaryActuallyChangesTheBand() {
        for hour in ZoonAmbientBackground.Band.boundaryHours {
            let before = ZoonAmbientBackground.Band.current(
                now: date(hour - 1, 59), calendar: calendar
            )
            let after = ZoonAmbientBackground.Band.current(
                now: date(hour, 0), calendar: calendar
            )
            XCTAssertNotEqual(before, after, "Nothing changes at \(hour):00")
        }
    }

    func testNextBoundaryIsTheUpcomingOne() throws {
        let cases: [(now: Date, expectedHour: Int)] = [
            (date(4, 59), 5),
            (date(5, 0), 9),
            (date(8, 59), 9),
            (date(16, 59), 17),
            (date(17, 1), 21),
            (date(20, 59), 21)
        ]
        for (now, expectedHour) in cases {
            let next = try XCTUnwrap(
                ZoonAmbientBackground.Band.nextBoundary(after: now, calendar: calendar)
            )
            XCTAssertEqual(
                calendar.component(.hour, from: next), expectedHour,
                "from \(calendar.component(.hour, from: now)):xx"
            )
            XCTAssertGreaterThan(next, now, "A boundary in the past schedules nothing")
        }
    }

    /// Late at night the next boundary is tomorrow's first one, not today's.
    func testAfterTheLastBoundaryItRollsToTomorrow() throws {
        let next = try XCTUnwrap(
            ZoonAmbientBackground.Band.nextBoundary(after: date(23, 30), calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.hour, from: next), 5)
        XCTAssertEqual(calendar.component(.day, from: next), 15)
    }

    /// Just after midnight is still the same night: the next boundary is
    /// this morning's 05:00, a few hours away, not tomorrow's.
    func testJustAfterMidnightWaitsHoursNotADay() throws {
        let now = date(0, 10)
        let next = try XCTUnwrap(
            ZoonAmbientBackground.Band.nextBoundary(after: now, calendar: calendar)
        )
        XCTAssertEqual(calendar.component(.day, from: next), 14)
        XCTAssertLessThan(next.timeIntervalSince(now), 6 * 3600)
    }

    /// At most four wakeups a day — the whole point of scheduling to the
    /// boundary rather than polling.
    func testAtMostFourBoundariesInADay() throws {
        var cursor = date(0, 1)
        let endOfDay = date(23, 59)
        var count = 0
        while cursor < endOfDay, count < 20 {
            let next = try XCTUnwrap(
                ZoonAmbientBackground.Band.nextBoundary(after: cursor, calendar: calendar)
            )
            if next > endOfDay { break }
            count += 1
            cursor = next
        }
        XCTAssertLessThanOrEqual(count, 4)
        XCTAssertEqual(count, 4, "05, 09, 17 and 21")
    }

    /// Boundaries are wall-clock, so they survive a DST transition rather
    /// than sliding by an hour.
    func testBoundariesHoldAcrossSpringForward() throws {
        // Europe/London springs forward at 01:00 on 29 March 2026.
        let beforeDST = calendar.date(from: DateComponents(
            year: 2026, month: 3, day: 29, hour: 0, minute: 30
        ))!
        let next = try XCTUnwrap(
            ZoonAmbientBackground.Band.nextBoundary(after: beforeDST, calendar: calendar)
        )
        XCTAssertEqual(
            calendar.component(.hour, from: next), 5,
            "Still 05:00 local, whatever the elapsed seconds were"
        )
    }
}
