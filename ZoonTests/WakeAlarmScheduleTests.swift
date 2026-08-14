import XCTest

/// Covers the "dynamic wake time replaces the old schedule" requirement: the
/// wake alarm is one-time at an absolute instant, so the instant it resolves
/// to has to be right, and it has to be right across a DST boundary.
final class WakeAlarmScheduleTests: XCTestCase {

    // MARK: Fixtures

    /// New York, because it observes DST on dates that are easy to name.
    private var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(
        _ calendar: Calendar,
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: Ordinary case

    /// The normal path: the body clock hands back an upcoming window end, and
    /// it is passed through untouched. Nothing should be "corrected" here.
    func testFutureWakeTimeIsReturnedUnchanged() {
        let calendar = newYork
        let now = date(calendar, 2026, 6, 1, 23, 0)
        let wake = date(calendar, 2026, 6, 2, 7, 30)

        let resolved = WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: now, calendar: calendar)

        XCTAssertEqual(resolved, wake)
    }

    /// A one-time alarm at a past instant would simply never fire, so a wake
    /// time that has already gone by rolls to the same wall-clock time
    /// tomorrow rather than being scheduled into the past.
    func testPastWakeTimeRollsForwardToTomorrow() {
        let calendar = newYork
        let now = date(calendar, 2026, 6, 2, 9, 0)
        let wake = date(calendar, 2026, 6, 2, 7, 30)

        let resolved = WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: now, calendar: calendar)

        XCTAssertEqual(resolved, date(calendar, 2026, 6, 3, 7, 30))
    }

    /// Exactly-now counts as past. An alarm scheduled for this very instant is
    /// a coin flip on whether it fires at all.
    func testWakeTimeEqualToNowRollsForward() {
        let calendar = newYork
        let wake = date(calendar, 2026, 6, 2, 7, 30)

        let resolved = WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: wake, calendar: calendar)

        XCTAssertEqual(resolved, date(calendar, 2026, 6, 3, 7, 30))
    }

    // MARK: DST

    /// Spring forward: 2 AM → 3 AM on 8 March 2026 in New York, so that night
    /// is 23 hours long. Rolling a 07:30 wake forward must land on 07:30 the
    /// next morning, not 08:30 — which is exactly what `addingTimeInterval(86_400)`
    /// would produce, and the reason this steps by calendar day instead.
    func testRollForwardAcrossSpringForwardKeepsWallClockTime() {
        let calendar = newYork
        let now = date(calendar, 2026, 3, 7, 9, 0)
        let wake = date(calendar, 2026, 3, 7, 7, 30)

        let resolved = WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: now, calendar: calendar)

        XCTAssertEqual(resolved, date(calendar, 2026, 3, 8, 7, 30))

        // The interval really is 23 hours, confirming the day crossed the
        // boundary rather than the fixture quietly avoiding it.
        XCTAssertEqual(resolved!.timeIntervalSince(wake), 23 * 3600, accuracy: 1)
    }

    /// Fall back: 2 AM → 1 AM on 1 November 2026, a 25-hour night. Same
    /// requirement in the other direction.
    func testRollForwardAcrossFallBackKeepsWallClockTime() {
        let calendar = newYork
        let now = date(calendar, 2026, 10, 31, 9, 0)
        let wake = date(calendar, 2026, 10, 31, 7, 30)

        let resolved = WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: now, calendar: calendar)

        XCTAssertEqual(resolved, date(calendar, 2026, 11, 1, 7, 30))
        XCTAssertEqual(resolved!.timeIntervalSince(wake), 25 * 3600, accuracy: 1)
    }

    // MARK: Bounds

    /// A wake time stale by more than the roll-forward bound means something
    /// upstream is broken. Declining is correct: `WakeAlarm.schedule(at:)`
    /// returns `false` and the caller keeps the notification backstop, rather
    /// than an alarm being invented at an unjustifiable time.
    func testWakeTimeStalerThanTheBoundReturnsNil() {
        let calendar = newYork
        let wake = date(calendar, 2026, 6, 1, 7, 30)
        let now = calendar.date(
            byAdding: .day,
            value: WakeAlarmSchedule.maximumRollForwardDays + 2,
            to: wake
        )!

        XCTAssertNil(WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: now, calendar: calendar))
    }

    /// The boundary itself resolves rather than falling off the end.
    func testWakeTimeAtTheEdgeOfTheBoundStillResolves() {
        let calendar = newYork
        let wake = date(calendar, 2026, 6, 1, 7, 30)
        // Just under the bound: the last day that can still roll forward.
        let now = calendar.date(
            byAdding: .day,
            value: WakeAlarmSchedule.maximumRollForwardDays - 1,
            to: wake
        )!

        let resolved = WakeAlarmSchedule.nextFutureOccurrence(of: wake, now: now, calendar: calendar)

        XCTAssertNotNil(resolved)
        XCTAssertGreaterThan(resolved!, now)
    }
}
