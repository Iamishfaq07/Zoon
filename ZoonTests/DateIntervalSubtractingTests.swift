import XCTest

final class DateIntervalSubtractingTests: XCTestCase {

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testNoExclusionsReturnsBaseUnchanged() {
        let base = DateInterval(start: date(6), end: date(18))
        let result = DateInterval.subtracting([], from: base)
        XCTAssertEqual(result, [base])
    }

    func testSingleExclusionInTheMiddleSplitsIntoTwo() {
        let base = DateInterval(start: date(6), end: date(18))
        let workout = DateInterval(start: date(10), end: date(11))
        let result = DateInterval.subtracting([workout], from: base)
        XCTAssertEqual(result, [
            DateInterval(start: date(6), end: date(10)),
            DateInterval(start: date(11), end: date(18)),
        ])
    }

    func testExclusionAtTheStartLeavesOnlyTheRemainder() {
        let base = DateInterval(start: date(6), end: date(18))
        let workout = DateInterval(start: date(6), end: date(7))
        let result = DateInterval.subtracting([workout], from: base)
        XCTAssertEqual(result, [DateInterval(start: date(7), end: date(18))])
    }

    func testOverlappingExclusionsAreMergedNotDoubleCounted() {
        let base = DateInterval(start: date(6), end: date(18))
        let workoutA = DateInterval(start: date(10), end: date(12))
        let workoutB = DateInterval(start: date(11), end: date(13))
        let result = DateInterval.subtracting([workoutA, workoutB], from: base)
        XCTAssertEqual(result, [
            DateInterval(start: date(6), end: date(10)),
            DateInterval(start: date(13), end: date(18)),
        ])
    }

    func testExclusionExtendingBeyondBaseIsClipped() {
        let base = DateInterval(start: date(6), end: date(18))
        let workout = DateInterval(start: date(16), end: date(20))
        let result = DateInterval.subtracting([workout], from: base)
        XCTAssertEqual(result, [DateInterval(start: date(6), end: date(16))])
    }

    func testExclusionCoveringTheWholeBaseLeavesNothing() {
        let base = DateInterval(start: date(6), end: date(18))
        let workout = DateInterval(start: date(0), end: date(23, 59))
        let result = DateInterval.subtracting([workout], from: base)
        XCTAssertTrue(result.isEmpty)
    }
}
