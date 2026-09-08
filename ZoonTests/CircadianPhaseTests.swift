import XCTest

final class CircadianPhaseTests: XCTestCase {

    func testPeakFocusIsAFewHoursAfterWake() {
        let calendar = Calendar(identifier: .gregorian)
        let wake = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 7))!
        let lateMorning = wake.addingTimeInterval(3 * 3600)
        XCTAssertEqual(
            CircadianPhase.at(now: lateMorning, wakeTime: wake, onsetHour: -0.5, calendar: calendar),
            .peakFocus
        )
    }

    func testSleepWindowNearHabitualOnset() {
        let calendar = Calendar(identifier: .gregorian)
        let wake = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 7))!
        let bedtime = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 23, minute: 30))!
        XCTAssertEqual(
            CircadianPhase.at(now: bedtime, wakeTime: wake, onsetHour: -0.5, calendar: calendar),
            .sleepWindow
        )
    }

    func testCircularDistanceWrapsMidnight() {
        XCTAssertEqual(CircadianPhase.circularDistance(-0.5, 0.5), -1.0, accuracy: 0.001)
        XCTAssertEqual(abs(CircadianPhase.circularDistance(11, -11)), 2.0, accuracy: 0.001)
    }
}
