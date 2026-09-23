import XCTest

final class ChartZoomTests: XCTestCase {
    private let full = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 8 * 3600)

    func testPinchingOutNarrowsAroundTheFingers() throws {
        let window = try XCTUnwrap(ChartZoom.window(current: full, full: full, magnification: 2, anchorFraction: 0.5))
        XCTAssertEqual(window.duration, 4 * 3600, accuracy: 1)
        XCTAssertEqual(window.start.timeIntervalSince1970, 2 * 3600, accuracy: 1)
    }

    func testTheMomentUnderTheFingersStaysPut() throws {
        let window = try XCTUnwrap(ChartZoom.window(current: full, full: full, magnification: 4, anchorFraction: 0.25))
        // 25% into the night is 2h; it should still sit 25% into the window.
        let anchorTime = window.start.addingTimeInterval(window.duration * 0.25)
        XCTAssertEqual(anchorTime.timeIntervalSince1970, 2 * 3600, accuracy: 1)
    }

    func testTheWindowNeverLeavesTheNight() throws {
        let window = try XCTUnwrap(ChartZoom.window(current: full, full: full, magnification: 4, anchorFraction: 1))
        XCTAssertEqual(window.end, full.end)
        let early = try XCTUnwrap(ChartZoom.window(current: full, full: full, magnification: 4, anchorFraction: 0))
        XCTAssertEqual(early.start, full.start)
    }

    func testThereIsAFloor() throws {
        let window = try XCTUnwrap(ChartZoom.window(current: full, full: full, magnification: 1000, anchorFraction: 0.5))
        XCTAssertEqual(window.duration, ChartZoom.minimumDuration, accuracy: 1)
    }

    func testPinchingBackOutToTheWholeNightClearsTheZoom() {
        let half = DateInterval(start: full.start, duration: 4 * 3600)
        XCTAssertNil(ChartZoom.window(current: half, full: full, magnification: 0.5, anchorFraction: 0.5))
        XCTAssertNil(ChartZoom.window(current: half, full: full, magnification: 0.1, anchorFraction: 0.5))
    }

    func testANonsenseMagnificationLeavesTheWindowAlone() {
        let half = DateInterval(start: full.start, duration: 4 * 3600)
        XCTAssertEqual(ChartZoom.window(current: half, full: full, magnification: 0, anchorFraction: 0.5), half)
        XCTAssertEqual(ChartZoom.window(current: half, full: full, magnification: .nan, anchorFraction: 0.5), half)
    }
}
