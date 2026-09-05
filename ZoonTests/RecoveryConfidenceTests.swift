import XCTest

/// How much to believe the headline number.
///
/// Recovery already knew both halves of this and said neither. It computed
/// `dataCompletenessPercent` -- so a score assembled from 55% of its usual
/// inputs was already distinguishable from a full one, in a field nothing
/// rendered -- and `isEstimate`, one boolean that flips at four nights and
/// then says the same thing forever after.
final class RecoveryConfidenceTests: XCTestCase {

    private func baseline(nights: Int) -> RecoveryBaseline {
        RecoveryBaseline(
            hrv: 55, restingHeartRate: 54, respiratoryRate: 14.5,
            wristTemperature: 0, nightCount: nights
        )
    }

    private func score(
        nights: Int = 30,
        hrv: Double? = 55,
        restingHeartRate: Double? = 54,
        respiratoryRate: Double? = 14.5
    ) -> RecoveryScore {
        RecoveryScore.compute(
            features: Fixture.night(
                avgHRV: hrv,
                restingHeartRate: restingHeartRate,
                avgRespiratoryRate: respiratoryRate
            ),
            baseline: baseline(nights: nights),
            sleepPerformance: 92
        )
    }

    // MARK: - The weaker of the two, never the average

    func testAFullNightOnAThinBaselineIsNotConfident() {
        let result = score(nights: 3)
        XCTAssertEqual(result.dataCompletenessPercent, 100)
        XCTAssertEqual(result.confidence, .insufficient)
    }

    func testALongBaselineCannotRescueAMissingHRV() {
        let result = score(nights: 60, hrv: nil)
        // HRV alone is 45% of the model.
        XCTAssertEqual(result.dataCompletenessPercent, 55)
        XCTAssertEqual(RecoveryScore.baselineConfidence(nightCount: 60), .high)
        XCTAssertEqual(result.confidence, .low, "the weaker judgment has to win")
    }

    func testEverythingPresentOnALongBaselineIsHigh() {
        let result = score(nights: 60)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertNil(result.confidenceReason, "nothing is holding it back")
    }

    /// Three of four components is 90% or 55% depending on which one is
    /// missing. Counting components would call those the same night.
    func testCoverageIsWeightedNotCounted() {
        let noRespiratory = score(respiratoryRate: nil)
        let noHRV = score(hrv: nil)

        XCTAssertEqual(noRespiratory.availableComponentCount, 3)
        XCTAssertEqual(noHRV.availableComponentCount, 3)

        XCTAssertEqual(noRespiratory.dataCompletenessPercent, 90)
        XCTAssertEqual(noHRV.dataCompletenessPercent, 55)
        XCTAssertEqual(noRespiratory.confidence, .moderate)
        XCTAssertEqual(noHRV.confidence, .low)
    }

    /// Sleep performance is the only always-available component. A night
    /// with nothing else is a restatement of how long you slept.
    func testSleepAloneIsNotARecoveryScore() {
        let result = score(hrv: nil, restingHeartRate: nil, respiratoryRate: nil)
        XCTAssertEqual(result.dataCompletenessPercent, 20)
        XCTAssertEqual(result.confidence, .insufficient)
    }

    // MARK: - Thresholds

    func testBaselineThresholds() {
        XCTAssertEqual(RecoveryScore.baselineConfidence(nightCount: 0), .insufficient)
        XCTAssertEqual(
            RecoveryScore.baselineConfidence(
                nightCount: RecoveryScore.minimumBaselineNights - 1
            ),
            .insufficient
        )
        XCTAssertEqual(
            RecoveryScore.baselineConfidence(nightCount: RecoveryScore.minimumBaselineNights),
            .low
        )
        XCTAssertEqual(RecoveryScore.baselineConfidence(nightCount: 6), .low)
        XCTAssertEqual(RecoveryScore.baselineConfidence(nightCount: 7), .moderate)
        XCTAssertEqual(RecoveryScore.baselineConfidence(nightCount: 13), .moderate)
        XCTAssertEqual(RecoveryScore.baselineConfidence(nightCount: 14), .high)
    }

    func testCoverageThresholds() {
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 20), .insufficient)
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 49), .insufficient)
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 50), .low)
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 74), .low)
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 75), .moderate)
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 99), .moderate)
        XCTAssertEqual(RecoveryScore.coverageConfidence(percent: 100), .high)
    }

    /// `isEstimate` and `confidence` must not contradict each other: the
    /// boolean is still read by the "building baseline" UI.
    func testIsEstimateAgreesWithAnInsufficientBaseline() {
        for nights in 0...20 {
            let result = score(nights: nights)
            XCTAssertEqual(
                result.isEstimate,
                RecoveryScore.baselineConfidence(nightCount: nights) == .insufficient,
                "disagreement at \(nights) nights"
            )
        }
    }

    // MARK: - Saying which half is the limit

    func testTheReasonNamesTheMissingSignal() throws {
        let result = score(nights: 60, hrv: nil)
        let reason = try XCTUnwrap(result.confidenceReason)
        XCTAssertTrue(reason.lowercased().contains("hrv"), reason)
    }

    func testTheReasonNamesTheHistoryWhenThatIsTheLimit() throws {
        let result = score(nights: 5)
        let reason = try XCTUnwrap(result.confidenceReason)
        XCTAssertTrue(reason.contains("5 nights"), reason)
    }

    func testTheReasonPluralisesOneNight() throws {
        let result = score(nights: 1)
        let reason = try XCTUnwrap(result.confidenceReason)
        XCTAssertTrue(reason.contains("1 night of"), reason)
        XCTAssertFalse(reason.contains("1 nights"), reason)
    }
}
