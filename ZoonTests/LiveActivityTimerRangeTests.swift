import XCTest

/// The Lock Screen timers build a `ClosedRange<Date>` from the activity's
/// start and its stored end. A range whose end is before its start traps, so
/// the end must never be taken as-is.
final class LiveActivityTimerRangeTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testNapRangeRunsFromStartToEnd() {
        let attributes = NapActivityAttributes(targetMinutes: 20, startedAt: start)
        let state = NapActivityAttributes.ContentState(endsAt: attributes.endDate, progress: 0)
        XCTAssertEqual(attributes.timerRange(state), start...start.addingTimeInterval(1200))
    }

    func testNapRangeWithEndBeforeStartCollapsesToStart() {
        let attributes = NapActivityAttributes(targetMinutes: 20, startedAt: start)
        let state = NapActivityAttributes.ContentState(endsAt: start.addingTimeInterval(-60), progress: 1)
        XCTAssertEqual(attributes.timerRange(state), start...start)
    }

    func testWindDownRangeWithEndBeforeStartCollapsesToStart() {
        // A routine resumed with nothing left, or a clock moved back mid-routine.
        let attributes = WindDownActivityAttributes(startedAt: start)
        let state = WindDownActivityAttributes.ContentState(endsAt: start.addingTimeInterval(-300), stageLabel: "Quiet")
        XCTAssertEqual(attributes.timerRange(state), start...start)
        let later = WindDownActivityAttributes.ContentState(endsAt: start.addingTimeInterval(1800), stageLabel: "Arrive")
        XCTAssertEqual(attributes.timerRange(later).upperBound, start.addingTimeInterval(1800))
    }
}
