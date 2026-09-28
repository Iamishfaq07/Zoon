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

    // MARK: - No wake known (the watch complication, always)

    private func at(_ hour: Int, _ minute: Int = 0, wake: Date? = nil) -> CircadianPhase {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: hour, minute: minute))!
        return CircadianPhase.at(now: now, wakeTime: wake, onsetHour: nil, calendar: calendar)
    }

    /// The fallback took the clock hour as hours awake: "Peak focus" at 3 am
    /// and "Sleep window" at 4 pm.
    func testWithoutAWakeTheNightIsTheSleepWindow() {
        XCTAssertEqual(at(3), .sleepWindow)
        XCTAssertEqual(at(23, 30), .sleepWindow)
    }

    func testWithoutAWakeTheDayFollowsANominalMorning() {
        XCTAssertEqual(at(7, 30), .morningRise)
        XCTAssertEqual(at(10), .peakFocus)
        XCTAssertEqual(at(16), .afternoonDip)
        XCTAssertEqual(at(19), .secondWind)
        XCTAssertEqual(at(21), .windDown)
    }

    /// A day-old wake, or one in the future, is no wake at all.
    func testAStaleOrFutureWakeFallsBackToTheNominalOne() {
        let calendar = Calendar(identifier: .gregorian)
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 7))!
        let later = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        XCTAssertEqual(at(16, wake: yesterday), .afternoonDip)
        XCTAssertEqual(at(10, wake: later), .peakFocus)
    }
}
