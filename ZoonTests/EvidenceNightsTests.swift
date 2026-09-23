import XCTest

final class EvidenceNightsTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func testEmptyReadsNone() {
        XCTAssertEqual(EvidenceNights.list([], calendar: calendar), "none")
    }

    func testSortedAndOneEntryPerDay() {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 6))!
        let later = calendar.date(byAdding: .day, value: 1, to: base)!
        let sameDayAsBase = calendar.date(byAdding: .hour, value: 10, to: base)!
        let text = EvidenceNights.list([later, base, sameDayAsBase], calendar: calendar, locale: Locale(identifier: "en_US_POSIX"))
        let parts = text.components(separatedBy: ", ")
        XCTAssertEqual(parts.count, 2, text)
        XCTAssertTrue(parts[0].contains("14"), text)
        XCTAssertTrue(parts[1].contains("15"), text)
    }
}
