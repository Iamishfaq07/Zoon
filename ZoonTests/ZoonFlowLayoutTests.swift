import XCTest
import SwiftUI

/// Rows of pills were `HStack`s, which never wrap — they compress. At the
/// largest accessibility size that turned a "Sample" pill into a column of
/// single letters and broke "93 score" into "93 / scor / e".
///
/// Wrapping is the layout answer. `minimumScaleFactor` would have solved it by
/// making accessibility text small again, which is the one thing the reader
/// asked it not to be.
final class ZoonFlowLayoutTests: XCTestCase {

    private let layout = ZoonFlowLayout(spacing: 8, lineSpacing: 8)

    private func sizes(_ widths: [CGFloat], height: CGFloat = 24) -> [CGSize] {
        widths.map { CGSize(width: $0, height: height) }
    }

    /// At ordinary sizes the pills fit, and this must behave exactly like the
    /// HStack it replaces — otherwise every screen changes for the majority of
    /// readers to fix a problem only some of them have.
    func testItemsThatFitStayOnOneLine() {
        let lines = layout.lines(sizes: sizes([90, 80, 70]), proposedWidth: 360)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.indices, [0, 1, 2])
        XCTAssertEqual(lines.first?.width, 90 + 8 + 80 + 8 + 70)
    }

    func testItemsWrapWhenTheyRunOut() {
        let lines = layout.lines(sizes: sizes([200, 200, 200]), proposedWidth: 360)
        XCTAssertEqual(lines.count, 3, "each pill needs its own line at this width")
        XCTAssertEqual(lines.map(\.indices), [[0], [1], [2]])
    }

    func testTwoFitThenTheThirdWraps() {
        let lines = layout.lines(sizes: sizes([150, 150, 150]), proposedWidth: 360)
        XCTAssertEqual(lines.map(\.indices), [[0, 1], [2]])
    }

    /// Spacing counts toward the width, or a row fits "just barely" and then
    /// overflows once drawn.
    func testSpacingIsCountedWhenDecidingToWrap() {
        // 176 + 176 = 352 fits in 360, but 176 + 8 + 176 = 360 does not exceed
        // it either; one more point each does.
        XCTAssertEqual(layout.lines(sizes: sizes([176, 176]), proposedWidth: 360).count, 1)
        XCTAssertEqual(layout.lines(sizes: sizes([177, 177]), proposedWidth: 360).count, 2)
    }

    /// An accessibility-sized pill can be wider than the phone. It gets a line
    /// to itself rather than being dropped or forced to share.
    func testAnItemWiderThanTheContainerGetsItsOwnLine() {
        let lines = layout.lines(sizes: sizes([500, 60]), proposedWidth: 360)
        XCTAssertEqual(lines.map(\.indices), [[0], [1]])
    }

    func testAnUnboundedProposalDoesNotWrap() {
        // "Size to fit" is one line; wrapping against an infinite width would
        // report a height nothing asked for.
        let lines = layout.lines(sizes: sizes([200, 200, 200]), proposedWidth: .greatestFiniteMagnitude)
        XCTAssertEqual(lines.count, 1)
    }

    func testNoItemsIsNoLines() {
        XCTAssertTrue(layout.lines(sizes: [], proposedWidth: 360).isEmpty)
    }

    /// Line height follows the tallest item on that line, so a pill with an
    /// icon does not clip its neighbours.
    func testLineHeightFollowsTheTallestItem() throws {
        let mixed = [
            CGSize(width: 80, height: 24),
            CGSize(width: 80, height: 44),
        ]
        let line = try XCTUnwrap(layout.lines(sizes: mixed, proposedWidth: 360).first)
        XCTAssertEqual(line.height, 44)
    }
}
