import XCTest

final class CalendarCommitmentTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ h: Int, day: Int = 15, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: h, minute: minute))!
    }

    func testPicksTheEarliestMorningEventTomorrow() {
        let now = date(18, day: 14)
        let events = [
            CalendarCommitment(start: date(9, day: 15), durationMinutes: 60, isAllDay: false, source: .calendar),
            CalendarCommitment(start: date(8, day: 15, minute: 30), durationMinutes: 30, isAllDay: false, source: .calendar)
        ]
        let first = CalendarCommitmentPicker.firstMeaningful(in: events, after: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(first).start), 8)
    }

    func testIgnoresAllDayAndLateEvents() {
        let now = date(18, day: 14)
        let events = [
            CalendarCommitment(start: date(0, day: 15), durationMinutes: nil, isAllDay: true, source: .calendar),
            CalendarCommitment(start: date(16, day: 15), durationMinutes: 60, isAllDay: false, source: .calendar)
        ]
        XCTAssertNil(CalendarCommitmentPicker.firstMeaningful(in: events, after: now, calendar: calendar))
    }

    func testNoPermissionOrEmptyListIsUnknownNotAGuess() {
        let now = date(18, day: 14)
        XCTAssertNil(CalendarCommitmentPicker.firstMeaningful(in: [], after: now, calendar: calendar))
    }

    func testDuplicatesAtTheSameInstantCollapse() {
        let now = date(18, day: 14)
        let start = date(8, day: 15, minute: 30)
        let events = [
            CalendarCommitment(start: start, durationMinutes: 30, isAllDay: false, source: .calendar),
            CalendarCommitment(start: start, durationMinutes: 30, isAllDay: false, source: .calendar)
        ]
        let first = CalendarCommitmentPicker.firstMeaningful(in: events, after: now, calendar: calendar)
        XCTAssertEqual(first?.start, start)
    }
}
