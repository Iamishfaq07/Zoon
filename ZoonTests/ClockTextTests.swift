import XCTest

/// The line break that split a clock time in half.
final class ClockTextTests: XCTestCase {

    private func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2026, month: 1, day: 5, hour: hour, minute: minute
        ))!
    }

    /// The defect itself: an ordinary space is a break opportunity, and a
    /// column too narrow for "10:22 PM" took it -- the AX5 capture of
    /// Tomorrow rendered "10:22 P" above a lone "M".
    func testNoOrdinarySpaceSurvivesToBeBrokenOn() {
        for date in [at(22, 22), at(10, 47), at(7, 40), at(0, 5), at(12, 0)] {
            let atomic = ClockText.atomic(date)
            XCTAssertFalse(
                atomic.contains(" "),
                "an ordinary space is a place to break: \(atomic)"
            )
        }
    }

    /// Nothing but the spaces changes. A time that reads differently is a
    /// worse bug than one that wraps badly.
    func testOnlyTheSpacesChange() {
        for date in [at(22, 22), at(10, 47), at(7, 40)] {
            let plain = date.formatted(date: .omitted, time: .shortened)
            let atomic = ClockText.atomic(date)
            XCTAssertEqual(
                atomic.replacingOccurrences(of: "\u{00A0}", with: " "), plain,
                "the time itself changed"
            )
            XCTAssertEqual(atomic.count, plain.count, "characters were added or lost")
        }
    }

    /// A locale whose short time has no space is left exactly as it was,
    /// rather than being given a separator it never had.
    func testAFormatWithNoSpaceIsUntouched() {
        XCTAssertEqual(ClockText.atomic("22:22"), "22:22")
        XCTAssertEqual(ClockText.atomic("07:40"), "07:40")
    }

    /// Every space goes, not just the first. A format with a thin space
    /// before the meridiem and another elsewhere must not keep one.
    func testEverySpaceGoes() {
        XCTAssertFalse(ClockText.atomic("10 : 22 PM").contains(" "))
    }
}
