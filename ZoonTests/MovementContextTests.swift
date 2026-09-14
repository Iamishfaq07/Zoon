import XCTest

final class MovementContextTests: XCTestCase {

    func testMissingStepsAreUnknownNotZero() {
        let snapshot = MovementContext.snapshot(stepsSoFar: nil, typicalStepsByNow: 6_000, weekday: 2)
        XCTAssertNil(snapshot.stepsSoFar)
        XCTAssertNil(snapshot.percentVsTypical)
        XCTAssertEqual(snapshot.confidence, .insufficient)
        XCTAssertTrue(snapshot.sentence.lowercased().contains("unknown"))
        XCTAssertFalse(snapshot.sentence.contains("0"))
    }

    func testSparseDayWithoutABaselineStaysLowConfidence() {
        let snapshot = MovementContext.snapshot(stepsSoFar: 4_240, typicalStepsByNow: nil, weekday: 2)
        XCTAssertEqual(snapshot.stepsSoFar, 4_240)
        XCTAssertEqual(snapshot.confidence, .low)
        XCTAssertTrue(snapshot.sentence.contains("4"))
    }

    func testBelowTypicalMonday() {
        let snapshot = MovementContext.snapshot(stepsSoFar: 4_240, typicalStepsByNow: 5_900, weekday: 2)
        XCTAssertEqual(snapshot.percentVsTypical!, -0.28, accuracy: 0.02)
        XCTAssertTrue(snapshot.sentence.contains("below"))
        XCTAssertEqual(snapshot.confidence, .moderate)
    }
}
