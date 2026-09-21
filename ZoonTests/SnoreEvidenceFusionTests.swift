import XCTest

final class SnoreEvidenceFusionTests: XCTestCase {

    func testOverlappingSourcesAreNotDoubleCounted() {
        let fused = SnoreEvidenceFusion.fuse(
            classifier: [(start: 10, end: 20)],
            heuristic: [(start: 12, end: 25)]
        )
        XCTAssertEqual(SnoreEvidenceFusion.snoreSeconds(from: fused), 15, accuracy: 0.01)
        XCTAssertTrue(fused.contains { $0.source == .both })
        XCTAssertTrue(fused.contains { $0.source == .heuristic })
    }

    func testDisjointIntervalsAreUnioned() {
        let fused = SnoreEvidenceFusion.fuse(
            classifier: [(start: 0, end: 10)],
            heuristic: [(start: 40, end: 50)]
        )
        XCTAssertEqual(SnoreEvidenceFusion.snoreSeconds(from: fused), 20, accuracy: 0.01)
    }

    func testMaxWouldUndercountDisjointTrueIntervals() {
        let classifier = 10.0
        let heuristic = 10.0
        XCTAssertEqual(max(classifier, heuristic), 10)
        let fused = SnoreEvidenceFusion.fuse(
            classifier: [(start: 0, end: 10)],
            heuristic: [(start: 40, end: 50)]
        )
        XCTAssertEqual(SnoreEvidenceFusion.snoreSeconds(from: fused), 20, accuracy: 0.01)
    }
}
