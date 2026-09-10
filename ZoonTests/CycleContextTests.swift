import XCTest

final class CycleContextTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func date(_ day: Int) -> Date {
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return calendar.date(byAdding: .day, value: day - 1, to: start)!
    }

    func testTypicalLengthUsesRecordedHistory() {
        let starts = [date(1), date(29), date(57)]
        XCTAssertEqual(CycleContext.typicalCycleLength(starts: starts, calendar: calendar), 28)
    }

    func testIrregularHistoryDoesNotReceiveEstimatedBands() {
        let starts = [date(1), date(22), date(60)]
        XCTAssertNil(CycleContext.typicalCycleLength(starts: starts, calendar: calendar))
    }

    func testTimingBandsNeverClaimOvulation() {
        XCTAssertEqual(CyclePhase.phase(forCycleDay: 4, typicalCycleLength: 32), .periodDays)
        XCTAssertEqual(CyclePhase.phase(forCycleDay: 10, typicalCycleLength: 32), .earlier)
        XCTAssertEqual(CyclePhase.phase(forCycleDay: 17, typicalCycleLength: 32), .middle)
        XCTAssertEqual(CyclePhase.phase(forCycleDay: 27, typicalCycleLength: 32), .later)
    }

    /// A start logged at 14:00 on day X is day 1 for the night dated X 00:00.
    /// Compared on raw instants the start sat after the night and was
    /// skipped, so that night read as the previous cycle's tail.
    func testAStartLoggedLaterTheSameDayStillCountsAsDayOne() {
        let start = calendar.date(byAdding: .hour, value: 14, to: date(10))!
        XCTAssertEqual(CycleContext.compute(date: date(10), starts: [start], calendar: calendar).cycleDay, 1)
        XCTAssertEqual(CycleContext.compute(date: date(11), starts: [start], calendar: calendar).cycleDay, 2)
        XCTAssertNil(CycleContext.compute(date: date(9), starts: [start], calendar: calendar).cycleDay)
    }

    /// Intervals of 27 and 29 days: the true median is 28. Picking the
    /// upper-middle element said 29.
    func testTypicalLengthIsTheTrueMedianOfAnEvenHistory() {
        let starts = [date(1), date(28), date(57)]
        XCTAssertEqual(CycleContext.typicalCycleLength(starts: starts, calendar: calendar), 28)
    }
}
