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

    /// The exact numbers a device produced: 3,173 steps against a typical of
    /// 119 gave "2566% above your typical Tuesday", which is arithmetically
    /// right and useless. 119 steps is a Tuesday the phone spent on a desk.
    func testAThinBaselineWithholdsThePercentage() {
        let snapshot = MovementContext.snapshot(
            stepsSoFar: 3173,
            typicalStepsByNow: 119,
            weekday: 3
        )

        XCTAssertFalse(
            snapshot.sentence.contains("%"),
            "a percentage against 119 steps is not context: \(snapshot.sentence)"
        )
        XCTAssertTrue(snapshot.sentence.contains("3,173"), "the steps themselves are still reported")
        XCTAssertEqual(snapshot.confidence, .low)
    }

    /// The comparison returns as soon as the baseline can carry it, and the
    /// percentage is the ordinary one.
    func testASubstantialBaselineStillComparesNormally() {
        let snapshot = MovementContext.snapshot(
            stepsSoFar: 6000,
            typicalStepsByNow: 4000,
            weekday: 3
        )

        XCTAssertTrue(
            snapshot.sentence.contains("50%"),
            "expected a plain 50% above: \(snapshot.sentence)"
        )
        XCTAssertEqual(snapshot.confidence, .moderate)
    }

    /// No sentence in this type may ever state a percentage in the thousands,
    /// whatever the inputs. This is the guard the device screenshot needed.
    func testNoInputProducesAnAbsurdPercentage() {
        for typical in [1, 50, 119, 399, 400, 1000, 5000] {
            for steps in [0, 500, 3173, 25000] {
                let snapshot = MovementContext.snapshot(
                    stepsSoFar: steps, typicalStepsByNow: typical, weekday: 3
                )
                if let range = snapshot.sentence.range(of: #"(\d[\d,]*)%"#, options: .regularExpression) {
                    let digits = snapshot.sentence[range]
                        .dropLast()
                        .replacingOccurrences(of: ",", with: "")
                    let value = Int(digits) ?? 0
                    XCTAssertLessThan(
                        value, 1000,
                        "steps \(steps) vs typical \(typical) produced \(snapshot.sentence)"
                    )
                }
            }
        }
    }
}