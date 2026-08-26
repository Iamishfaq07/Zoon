import XCTest

final class SleepScoreTests: XCTestCase {

    func testDurationGetsFullCreditAtOrAboveGoal() {
        let atGoal = SleepScore.compute(
            for: Fixture.night(timeAsleepMinutes: 480, timeInBedMinutes: 480),
            goalMinutes: 480
        )
        let duration = atGoal.components.first { $0.label == "Duration" }
        XCTAssertEqual(duration?.normalized, 1.0, accuracy: 0.001)
    }

    func testDurationScalesLinearlyBelowGoal() {
        let score = SleepScore.compute(
            for: Fixture.night(timeAsleepMinutes: 240, timeInBedMinutes: 480),
            goalMinutes: 480
        )
        let duration = score.components.first { $0.label == "Duration" }
        XCTAssertEqual(duration?.normalized, 0.5, accuracy: 0.001)
    }

    func testEfficiencyThresholdBoundaries() {
        // 60% efficiency -> normalized 0; 95% -> normalized 1, per the
        // documented 60-95 scaling window.
        let low = SleepScore.compute(
            for: Fixture.night(timeAsleepMinutes: 288, timeInBedMinutes: 480), // 60%
            goalMinutes: 480
        )
        XCTAssertEqual(low.components.first { $0.label == "Efficiency" }?.normalized, 0, accuracy: 0.01)

        let high = SleepScore.compute(
            for: Fixture.night(timeAsleepMinutes: 456, timeInBedMinutes: 480), // 95%
            goalMinutes: 480
        )
        XCTAssertEqual(high.components.first { $0.label == "Efficiency" }?.normalized, 1, accuracy: 0.01)
    }

    func testContinuityDecaysWithWakeCount() {
        let noWakes = SleepScore.compute(for: Fixture.night(wakeCount: 0), goalMinutes: 480)
        let eightWakes = SleepScore.compute(for: Fixture.night(wakeCount: 8), goalMinutes: 480)
        XCTAssertEqual(noWakes.components.first { $0.label == "Continuity" }?.normalized, 1.0, accuracy: 0.001)
        XCTAssertEqual(eightWakes.components.first { $0.label == "Continuity" }?.normalized, 0.0, accuracy: 0.001)
    }

    func testContinuityNeverGoesNegativePastEightWakes() {
        let manyWakes = SleepScore.compute(for: Fixture.night(wakeCount: 20), goalMinutes: 480)
        XCTAssertEqual(manyWakes.components.first { $0.label == "Continuity" }?.normalized, 0.0, accuracy: 0.001)
    }

    func testComponentWeightsSumToOne() {
        let score = SleepScore.compute(for: Fixture.night(), goalMinutes: 480)
        let totalWeight = score.components.reduce(0) { $0 + $1.weight }
        XCTAssertEqual(totalWeight, 1.0, accuracy: 0.001)
    }

    func testValueIsWithinZeroToOneHundred() {
        let perfect = SleepScore.compute(
            for: Fixture.night(timeAsleepMinutes: 480, timeInBedMinutes: 480, wakeCount: 0),
            goalMinutes: 480
        )
        XCTAssertEqual(perfect.value, 100)

        let terrible = SleepScore.compute(
            for: Fixture.night(timeAsleepMinutes: 0, timeInBedMinutes: 480, wakeCount: 20),
            goalMinutes: 480
        )
        XCTAssertGreaterThanOrEqual(terrible.value, 0)
        XCTAssertLessThanOrEqual(terrible.value, 100)
    }

    func testBandBoundaries() {
        XCTAssertEqual(SleepScore(value: 0, components: []).band, .poor)
        XCTAssertEqual(SleepScore(value: 49, components: []).band, .poor)
        XCTAssertEqual(SleepScore(value: 50, components: []).band, .fair)
        XCTAssertEqual(SleepScore(value: 69, components: []).band, .fair)
        XCTAssertEqual(SleepScore(value: 70, components: []).band, .good)
        XCTAssertEqual(SleepScore(value: 84, components: []).band, .good)
        XCTAssertEqual(SleepScore(value: 85, components: []).band, .excellent)
        XCTAssertEqual(SleepScore(value: 100, components: []).band, .excellent)
    }
}
