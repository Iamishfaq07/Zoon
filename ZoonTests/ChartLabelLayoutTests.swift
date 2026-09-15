import XCTest

final class ChartLabelLayoutTests: XCTestCase {

    /// The screenshot: Peak focus at 10:24 and Afternoon dip at 11:54, ~24 pt
    /// apart on a 22-hour axis, both wanting to sit above the curve. They
    /// must not share a side.
    func testCloseLabelsAlternateSides() {
        let items = [
            ChartLabelLayout.Request(x: 100, y: 40, width: 72, height: 28, prefersAbove: true),
            ChartLabelLayout.Request(x: 124, y: 76, width: 80, height: 28, prefersAbove: true),
        ]
        let placed = ChartLabelLayout.place(items, canvasWidth: 360, canvasHeight: 148)
        XCTAssertEqual(placed.count, 2)
        XCTAssertTrue(placed[0].showCaption)
        XCTAssertTrue(placed[1].showCaption)
        XCTAssertNotEqual(placed[0].side, placed[1].side)
    }

    func testIsolatedLabelKeepsItsPreferredSide() {
        let items = [
            ChartLabelLayout.Request(x: 180, y: 50, width: 72, height: 28, prefersAbove: true),
        ]
        let placed = ChartLabelLayout.place(items, canvasWidth: 360, canvasHeight: 148)
        XCTAssertEqual(placed.first?.side, .above)
        XCTAssertEqual(placed.first?.showCaption, true)
    }

    func testALabelTooHighFlipsBelow() {
        let items = [
            ChartLabelLayout.Request(x: 180, y: 8, width: 72, height: 28, prefersAbove: true),
        ]
        let placed = ChartLabelLayout.place(items, canvasWidth: 360, canvasHeight: 148)
        XCTAssertEqual(placed.first?.side, .below)
        XCTAssertEqual(placed.first?.showCaption, true)
    }

    /// Three marks in one cluster: two captions on opposite sides, the third
    /// drops its words rather than drawing through the others.
    func testAThirdClusteredLabelDropsItsCaption() {
        let items = [
            ChartLabelLayout.Request(x: 100, y: 50, width: 80, height: 28, prefersAbove: true),
            ChartLabelLayout.Request(x: 110, y: 60, width: 80, height: 28, prefersAbove: true),
            ChartLabelLayout.Request(x: 120, y: 55, width: 80, height: 28, prefersAbove: true),
        ]
        let placed = ChartLabelLayout.place(items, canvasWidth: 360, canvasHeight: 148)
        let visible = placed.filter(\.showCaption)
        XCTAssertEqual(visible.count, 2)
        XCTAssertNotEqual(visible[0].side, visible[1].side)
        XCTAssertEqual(placed.filter { !$0.showCaption }.count, 1)
    }

    func testCaptionsStayInsideTheCanvas() {
        let items = [
            ChartLabelLayout.Request(x: 10, y: 40, width: 80, height: 28, prefersAbove: true),
            ChartLabelLayout.Request(x: 350, y: 40, width: 80, height: 28, prefersAbove: true),
        ]
        let placed = ChartLabelLayout.place(items, canvasWidth: 360, canvasHeight: 148)
        for (item, place) in zip(items, placed) where place.showCaption {
            XCTAssertGreaterThanOrEqual(place.x - item.width / 2, 2)
            XCTAssertLessThanOrEqual(place.x + item.width / 2, 358)
            XCTAssertGreaterThanOrEqual(place.y - item.height / 2, 2)
            XCTAssertLessThanOrEqual(place.y + item.height / 2, 146)
        }
    }

    func testEmptyInputIsEmpty() {
        XCTAssertTrue(ChartLabelLayout.place([], canvasWidth: 360, canvasHeight: 148).isEmpty)
    }

    func testOriginalOrderIsPreserved() {
        let items = [
            ChartLabelLayout.Request(x: 300, y: 40, width: 40, height: 20, prefersAbove: true),
            ChartLabelLayout.Request(x: 40, y: 40, width: 40, height: 20, prefersAbove: true),
        ]
        let placed = ChartLabelLayout.place(items, canvasWidth: 360, canvasHeight: 148)
        XCTAssertEqual(placed[0].x, 300, accuracy: 0.5)
        XCTAssertEqual(placed[1].x, 40, accuracy: 0.5)
    }
}
