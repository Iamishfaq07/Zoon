import XCTest

final class StrainScoreTests: XCTestCase {

    // MARK: - compute

    func testComputeWithNoZonesIsZero() {
        let score = StrainScore.compute(zoneMinutes: [:], activeEnergyKcal: nil, hasHeartRateCoverage: true)
        XCTAssertEqual(score.value, 0, accuracy: 0.001)
    }

    func testComputeNeverExceedsMaxValue() {
        // Absurdly high load should saturate at maxValue, not overshoot it.
        let score = StrainScore.compute(
            zoneMinutes: [.maximum: 600],
            activeEnergyKcal: nil,
            hasHeartRateCoverage: true
        )
        XCTAssertLessThanOrEqual(score.value, StrainScore.maxValue)
    }

    func testComputeWeighsHarderZonesMoreThanEasierOnesForEqualMinutes() {
        let easy = StrainScore.compute(zoneMinutes: [.light: 60], activeEnergyKcal: nil, hasHeartRateCoverage: true)
        let hard = StrainScore.compute(zoneMinutes: [.maximum: 60], activeEnergyKcal: nil, hasHeartRateCoverage: true)
        XCTAssertGreaterThan(hard.value, easy.value)
    }

    func testComputeMarksEstimateWhenHeartRateCoverageIsMissing() {
        let score = StrainScore.compute(zoneMinutes: [.moderate: 30], activeEnergyKcal: nil, hasHeartRateCoverage: false)
        XCTAssertTrue(score.isEstimate)
    }

    func testComputeMarksNonEstimateWithCoverage() {
        let score = StrainScore.compute(zoneMinutes: [.moderate: 30], activeEnergyKcal: nil, hasHeartRateCoverage: true)
        XCTAssertFalse(score.isEstimate)
    }

    // MARK: - estimate

    func testEstimateIsAlwaysFlaggedAsEstimate() {
        let score = StrainScore.estimate(activeEnergyKcal: 400, exerciseMinutes: 45)
        XCTAssertTrue(score.isEstimate)
    }

    func testEstimateNeverExceedsMaxValue() {
        let score = StrainScore.estimate(activeEnergyKcal: 5000, exerciseMinutes: 400)
        XCTAssertLessThanOrEqual(score.value, StrainScore.maxValue)
    }

    func testEstimateWithNoActivityIsZero() {
        let score = StrainScore.estimate(activeEnergyKcal: 0, exerciseMinutes: 0)
        XCTAssertEqual(score.value, 0, accuracy: 0.001)
    }

    // MARK: - band boundaries

    func testBandBoundaries() {
        XCTAssertEqual(StrainScore(value: 0, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "Light")
        XCTAssertEqual(StrainScore(value: 5.9, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "Light")
        XCTAssertEqual(StrainScore(value: 6, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "Moderate")
        XCTAssertEqual(StrainScore(value: 9.9, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "Moderate")
        XCTAssertEqual(StrainScore(value: 10, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "Strenuous")
        XCTAssertEqual(StrainScore(value: 13.9, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "Strenuous")
        XCTAssertEqual(StrainScore(value: 14, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "High")
        XCTAssertEqual(StrainScore(value: 17.9, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "High")
        XCTAssertEqual(StrainScore(value: 18, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "All-out")
        XCTAssertEqual(StrainScore(value: 21, zoneMinutes: [:], activeEnergyKcal: nil, isEstimate: false).band, "All-out")
    }

    // MARK: - balanceVerdict

    func testBalanceVerdictWellUnderCapacity() {
        // supported at 100% recovery = 16; strain of 8 is far under it.
        let verdict = StrainScore.balanceVerdict(strain: 8, recoveryPercent: 100)
        XCTAssertEqual(verdict, "Well under what your body could handle today.")
    }

    func testBalanceVerdictWellMatched() {
        // supported at 50% recovery = 10; strain of 9 is within -4..<2 of it.
        let verdict = StrainScore.balanceVerdict(strain: 9, recoveryPercent: 50)
        XCTAssertEqual(verdict, "Well matched to your recovery.")
    }

    func testBalanceVerdictAboveSupported() {
        // supported at 0% recovery = 4; strain of 7 is 3 above it.
        let verdict = StrainScore.balanceVerdict(strain: 7, recoveryPercent: 0)
        XCTAssertEqual(verdict, "Above what your recovery supported. Expect to feel it.")
    }

    func testBalanceVerdictFarBeyondSupported() {
        let verdict = StrainScore.balanceVerdict(strain: 20, recoveryPercent: 0)
        XCTAssertEqual(verdict, "Far beyond today's recovery. Prioritise sleep tonight.")
    }
}
