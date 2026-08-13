import XCTest

final class DateIntervalMergingTests: XCTestCase {

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testSingleIntervalIsUnchanged() {
        let interval = DateInterval(start: date(14), end: date(14, 30))
        XCTAssertEqual(DateInterval.merging([interval]), [interval])
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(DateInterval.merging([]), [])
    }

    /// The core case for nap dedup: a manual log and an auto-detected
    /// episode that overlap even slightly must merge into one interval, not
    /// be counted as two separate naps.
    func testOverlappingIntervalsMergeIntoOne() {
        let manual = DateInterval(start: date(14), end: date(14, 30))
        let auto = DateInterval(start: date(14, 15), end: date(14, 45))
        let merged = DateInterval.merging([manual, auto])
        XCTAssertEqual(merged, [DateInterval(start: date(14), end: date(14, 45))])
    }

    func testAdjacentTouchingIntervalsMerge() {
        let first = DateInterval(start: date(14), end: date(14, 30))
        let second = DateInterval(start: date(14, 30), end: date(15))
        let merged = DateInterval.merging([first, second])
        XCTAssertEqual(merged, [DateInterval(start: date(14), end: date(15))])
    }

    func testNonOverlappingIntervalsStaySeparate() {
        let first = DateInterval(start: date(14), end: date(14, 20))
        let second = DateInterval(start: date(16), end: date(16, 30))
        let merged = DateInterval.merging([first, second])
        XCTAssertEqual(merged, [first, second])
    }

    /// An interval fully containing another must not double the duration --
    /// the union is just the larger interval.
    func testFullyContainedIntervalDoesNotExtendTheUnion() {
        let outer = DateInterval(start: date(14), end: date(15))
        let inner = DateInterval(start: date(14, 10), end: date(14, 20))
        let merged = DateInterval.merging([outer, inner])
        XCTAssertEqual(merged, [outer])
    }

    func testUnsortedInputIsHandledCorrectly() {
        let a = DateInterval(start: date(16), end: date(16, 30))
        let b = DateInterval(start: date(14), end: date(14, 30))
        let merged = DateInterval.merging([a, b])
        XCTAssertEqual(merged, [b, a])
    }
}
