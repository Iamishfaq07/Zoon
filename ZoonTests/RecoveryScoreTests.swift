import XCTest

/// Regression tests for the missing-data bug fixed in RecoveryScore: a
/// component with no underlying signal must be excluded and its weight
/// redistributed among what's available, never filled in with a neutral or
/// favorable default at full weight.
final class RecoveryScoreTests: XCTestCase {

    private let fullBaseline = RecoveryBaseline(
        hrv: 55, restingHeartRate: 54, respiratoryRate: 14.5, wristTemperature: 0, nightCount: 30
    )

    // MARK: - Band boundaries

    func testBandBoundaries() {
        XCTAssertEqual(RecoveryScore.Band.forPercent(0), .low)
        XCTAssertEqual(RecoveryScore.Band.forPercent(33), .low)
        XCTAssertEqual(RecoveryScore.Band.forPercent(34), .moderate)
        XCTAssertEqual(RecoveryScore.Band.forPercent(66), .moderate)
        XCTAssertEqual(RecoveryScore.Band.forPercent(67), .high)
        XCTAssertEqual(RecoveryScore.Band.forPercent(100), .high)
    }

    func testAllComponentsAvailableSumsToFullWeight() {
        let night = Fixture.night()
        let score = RecoveryScore.compute(features: night, baseline: fullBaseline, sleepPerformance: 100)

        XCTAssertEqual(score.availableComponentCount, 4)
        XCTAssertEqual(score.dataCompletenessPercent, 100)
        for component in score.components {
            XCTAssertTrue(component.isAvailable)
            XCTAssertEqual(component.effectiveWeight, component.weight, accuracy: 0.0001)
        }
    }

    /// The exact bug: HRV missing used to score 0.5 (neutral) at full 45%
    /// weight. It must now be excluded entirely, and the remaining three
    /// components' weights must renormalize to fill the gap.
    func testMissingHRVIsExcludedNotDefaulted() {
        let night = Fixture.night(avgHRV: nil)
        let score = RecoveryScore.compute(features: night, baseline: fullBaseline, sleepPerformance: 100)

        let hrv = score.components.first { $0.label == "HRV" }!
        XCTAssertFalse(hrv.isAvailable)
        XCTAssertEqual(hrv.effectiveWeight, 0)

        XCTAssertEqual(score.availableComponentCount, 3)
        XCTAssertLessThan(score.dataCompletenessPercent, 100)

        // Remaining components' effective weights must sum to 1 -- the
        // excluded component's share was fully redistributed, not dropped.
        let remainingWeight = score.components.filter(\.isAvailable).reduce(0.0) { $0 + $1.effectiveWeight }
        XCTAssertEqual(remainingWeight, 1.0, accuracy: 0.0001)
    }

    /// Respiration briefly defaulted to a *favorable* 0.75 when missing --
    /// actively rewarding absent data instead of excluding the component.
    /// Confirms that specific regression directly: missing respiration must
    /// carry zero weight, not some nonzero "assume it's fine" value.
    func testMissingRespirationIsExcludedNotFavorablyDefaulted() {
        let night = Fixture.night(avgRespiratoryRate: nil)
        let score = RecoveryScore.compute(features: night, baseline: fullBaseline, sleepPerformance: 100)

        let respiratory = score.components.first { $0.label == "Respiratory" }!
        XCTAssertFalse(respiratory.isAvailable)
        XCTAssertEqual(respiratory.effectiveWeight, 0)

        // With respiration excluded, a genuinely elevated respiratory rate
        // (a real bad signal) must still be able to pull the score down --
        // it must not be masked by the missing-data path defaulting to
        // something better than a real bad reading would score.
        let badRespirationNight = Fixture.night(avgRespiratoryRate: 17.5) // +3 br/min over baseline
        let badScore = RecoveryScore.compute(features: badRespirationNight, baseline: fullBaseline, sleepPerformance: 100)
        XCTAssertLessThan(badScore.percent, score.percent)
    }

    func testAllComponentsMissingExceptSleepStillScores() {
        let night = Fixture.night(avgHRV: nil, restingHeartRate: nil, avgRespiratoryRate: nil)
        let score = RecoveryScore.compute(features: night, baseline: fullBaseline, sleepPerformance: 80)

        // Sleep performance has no missing-data path, so it alone should
        // carry the full weight and the score should equal its own
        // normalized value.
        XCTAssertEqual(score.availableComponentCount, 1)
        XCTAssertEqual(score.percent, 80)
    }

    func testBaselineMissingAlsoExcludesComponent() {
        // Night has an HRV reading, but there's no baseline yet to compare
        // it against -- must still be excluded, not scored against nothing.
        let night = Fixture.night(avgHRV: 55)
        let noBaseline = RecoveryBaseline.empty
        let score = RecoveryScore.compute(features: night, baseline: noBaseline, sleepPerformance: 100)

        let hrv = score.components.first { $0.label == "HRV" }!
        XCTAssertFalse(hrv.isAvailable)
    }

    /// `primaryDriver` defaults an unavailable component's `normalized` to 0
    /// internally (harmless for scoring, since `effectiveWeight` is also 0 --
    /// but `primaryDriver` picks the *lowest* `normalized`, so an unfiltered
    /// version would always pick the unavailable component over a real,
    /// merely-low one).
    func testPrimaryDriverNeverPicksAnUnavailableComponent() {
        // Sleep performance is mediocre (a real, measured low point) but
        // every physiological signal is missing outright.
        let night = Fixture.night(avgHRV: nil, restingHeartRate: nil, avgRespiratoryRate: nil)
        let score = RecoveryScore.compute(features: night, baseline: fullBaseline, sleepPerformance: 60)

        XCTAssertEqual(score.primaryDriver?.label, "Sleep")
    }
}
