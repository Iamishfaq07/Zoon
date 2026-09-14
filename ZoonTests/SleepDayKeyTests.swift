import XCTest

/// Day identity as a civil date rather than an instant.
///
/// The streak engine stored day keys as `startOfDay` computed in each night's
/// own timezone, then looked them up with the device's current calendar.
/// Local midnight in Delhi and in London are five and a half hours apart, so
/// the day after flying home every stored key missed its lookup.
final class SleepDayKeyTests: XCTestCase {

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }

    // MARK: - Identity

    /// The same instant is a different day depending on where you were, which
    /// is the entire reason the zone has to be supplied rather than assumed.
    func testTheSameInstantIsADifferentDayInDifferentZones() {
        let instant = date("2026-03-10T19:00:00Z")
        XCTAssertEqual(SleepDayKey(instant, timeZone: zone("America/New_York")).description, "2026-03-10")
        XCTAssertEqual(SleepDayKey(instant, timeZone: zone("Asia/Kolkata")).description, "2026-03-11")
    }

    /// Two nights recorded either side of a flight are still consecutive
    /// days. A key carrying the zone would say otherwise — which is why this
    /// deliberately does not carry one.
    func testConsecutiveDaysSurviveAChangeOfZone() {
        let delhi = SleepDayKey(date("2026-03-10T01:30:00Z"), timeZone: zone("Asia/Kolkata"))   // 07:00 local
        let london = SleepDayKey(date("2026-03-11T07:00:00Z"), timeZone: zone("Europe/London")) // 07:00 local
        XCTAssertEqual(delhi.description, "2026-03-10")
        XCTAssertEqual(london.description, "2026-03-11")
        XCTAssertTrue(london.isDayAfter(delhi), "a flight does not make two mornings non-consecutive")
    }

    // MARK: - Arithmetic

    /// A 23-hour day and a 25-hour day both still have exactly one date, so
    /// civil-date arithmetic cannot gain or lose a night across a transition.
    func testDaylightSavingCannotAddOrDropADay() {
        let springForward = SleepDayKey(date("2026-03-08T12:00:00Z"), timeZone: zone("America/New_York"))
        XCTAssertEqual(springForward.description, "2026-03-08")
        XCTAssertEqual(springForward.previous.description, "2026-03-07")
        XCTAssertEqual(springForward.next.description, "2026-03-09")

        let fallBack = SleepDayKey(date("2026-11-01T12:00:00Z"), timeZone: zone("America/New_York"))
        XCTAssertEqual(fallBack.previous.description, "2026-10-31")
        XCTAssertEqual(fallBack.next.description, "2026-11-02")
    }

    func testMonthAndYearBoundaries() {
        let firstOfMarch = SleepDayKey(date("2026-03-01T12:00:00Z"), timeZone: .gmt)
        XCTAssertEqual(firstOfMarch.previous.description, "2026-02-28")

        let newYear = SleepDayKey(date("2026-01-01T12:00:00Z"), timeZone: .gmt)
        XCTAssertEqual(newYear.previous.description, "2025-12-31")

        let leapDay = SleepDayKey(date("2028-03-01T12:00:00Z"), timeZone: .gmt)
        XCTAssertEqual(leapDay.previous.description, "2028-02-29", "2028 is a leap year")
    }

    func testOrderingIsChronological() {
        let earlier = SleepDayKey(date("2026-03-09T12:00:00Z"), timeZone: .gmt)
        let later = SleepDayKey(date("2026-04-01T12:00:00Z"), timeZone: .gmt)
        XCTAssertLessThan(earlier, later)
        XCTAssertFalse(later < earlier)
        XCTAssertEqual([later, earlier].sorted(), [earlier, later])
    }

    func testAdjacencyIsStrictlyOneDay() {
        let day = SleepDayKey(date("2026-03-10T12:00:00Z"), timeZone: .gmt)
        XCTAssertTrue(day.next.isDayAfter(day))
        XCTAssertFalse(day.advanced(by: 2).isDayAfter(day))
        XCTAssertFalse(day.isDayAfter(day), "a day does not follow itself")
        XCTAssertFalse(day.previous.isDayAfter(day))
    }

    /// The zone the arithmetic runs in must never escape into the result.
    func testArithmeticDoesNotDependOnTheDeviceZone() {
        let key = SleepDayKey(date("2026-06-15T23:30:00Z"), timeZone: zone("Pacific/Kiritimati")) // UTC+14
        XCTAssertEqual(key.description, "2026-06-16")
        XCTAssertEqual(key.previous.description, "2026-06-15")
    }
}
