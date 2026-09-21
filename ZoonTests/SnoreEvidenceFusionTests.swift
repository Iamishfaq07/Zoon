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

    func testHeuristicOnlyIntervalsCarryLowerConfidenceThanClassifier() {
        let fused = SnoreEvidenceFusion.fuse(
            classifier: [(start: 0, end: 10, confidence: 0.94)],
            heuristic: [(start: 40, end: 50)]
        )
        let classified = fused.first { $0.source == .classifier }
        let heuristic = fused.first { $0.source == .heuristic }
        XCTAssertEqual(classified?.confidence ?? 0, 0.94, accuracy: 0.001)
        XCTAssertLessThan(heuristic?.confidence ?? 1, classified?.confidence ?? 0)
    }
}
