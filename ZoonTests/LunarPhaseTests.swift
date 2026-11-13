import XCTest

final class LunarPhaseTests: XCTestCase {

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = hour
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// The total solar eclipse of 8 April 2024 was, necessarily, a new moon.
    func testKnownNewMoon() {
        let phase = LunarPhase(date: date(2024, 4, 8, 18))
        XCTAssertLessThan(phase.illumination, 0.03)
        XCTAssertEqual(phase.name, "New moon")
    }

    /// The total lunar eclipse of 14 March 2025 was a full moon.
    func testKnownFullMoon() {
        let phase = LunarPhase(date: date(2025, 3, 14, 7))
        XCTAssertGreaterThan(phase.illumination, 0.97)
        XCTAssertEqual(phase.name, "Full moon")
    }

    func testWaxingBeforeFullAndWaningAfter() {
        XCTAssertTrue(LunarPhase(date: date(2025, 3, 9)).isWaxing)
        XCTAssertFalse(LunarPhase(date: date(2025, 3, 19)).isWaxing)
    }

    func testQuartersAreHalfLit() {
        XCTAssertEqual(LunarPhase(cycle: 0.25).illumination, 0.5, accuracy: 0.0001)
        XCTAssertEqual(LunarPhase(cycle: 0.75).illumination, 0.5, accuracy: 0.0001)
        XCTAssertEqual(LunarPhase(cycle: 0.25).name, "First quarter")
        XCTAssertEqual(LunarPhase(cycle: 0.75).name, "Last quarter")
    }

    func testCycleWraps() {
        XCTAssertEqual(LunarPhase(cycle: 1.25).cycle, 0.25, accuracy: 0.0001)
        XCTAssertEqual(LunarPhase(cycle: -0.25).cycle, 0.75, accuracy: 0.0001)
        // A date before the reference new moon still lands inside 0..<1.
        let early = LunarPhase(date: date(1999, 6, 1))
        XCTAssertTrue((0..<1).contains(early.cycle))
    }

    func testSummaryReadsNameAndPercent() {
        XCTAssertEqual(LunarPhase(cycle: 0.5).summary, "Full moon, 100% lit")
    }

    // MARK: - Dawn

    func testDawnIsDarkUntilTheLead() {
        let wake = date(2025, 1, 1, 7)
        XCTAssertEqual(DawnRamp.progress(now: wake.addingTimeInterval(-60 * 60), wake: wake), 0)
        XCTAssertEqual(DawnRamp.progress(now: wake.addingTimeInterval(-DawnRamp.leadMinutes * 60), wake: wake), 0)
        XCTAssertEqual(DawnRamp.progress(now: .now, wake: nil), 0)
    }

    func testDawnRisesToFullAtTheWake() {
        let wake = date(2025, 1, 1, 7)
        let early = DawnRamp.progress(now: wake.addingTimeInterval(-15 * 60), wake: wake)
        let late = DawnRamp.progress(now: wake.addingTimeInterval(-5 * 60), wake: wake)
        XCTAssertGreaterThan(early, 0)
        XCTAssertGreaterThan(late, early)
        XCTAssertLessThan(late, 1)
        XCTAssertEqual(DawnRamp.progress(now: wake, wake: wake), 1)
    }

    func testDawnHoldsThenGoesDark() {
        let wake = date(2025, 1, 1, 7)
        XCTAssertEqual(DawnRamp.progress(now: wake.addingTimeInterval(10 * 60), wake: wake), 1)
        XCTAssertEqual(DawnRamp.progress(now: wake.addingTimeInterval(45 * 60), wake: wake), 0)
    }
}
