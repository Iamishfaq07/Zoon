import XCTest
@testable import Zoon

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
}
