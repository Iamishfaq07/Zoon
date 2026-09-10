import XCTest

final class AmbientBackgroundTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: hour))!
    }

    func testDayBandsDriveDistinctTodayStates() {
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 7), calendar: calendar), .morning)
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 13), calendar: calendar), .day)
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 19), calendar: calendar), .evening)
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 23), calendar: calendar), .night)
    }

    func testBandBoundariesAreDeterministic() {
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 5), calendar: calendar), .morning)
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 9), calendar: calendar), .day)
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 17), calendar: calendar), .evening)
        XCTAssertEqual(ZoonAmbientBackground.Band.current(now: date(hour: 21), calendar: calendar), .night)
    }
}
