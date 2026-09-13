import XCTest

/// A score the wrist refuses to state must not appear as a number on the
/// phone, and Energy must not spend it either.
final class RecoveryPresentationTests: XCTestCase {

    private func score(
        percent: Int,
        completeness: Int,
        baselineNights: Int,
        components: [RecoveryScore.Component] = []
    ) -> RecoveryScore {
        RecoveryScore(
            percent: percent,
            components: components,
            isEstimate: false,
            dataCompletenessPercent: completeness,
            availableComponentCount: components.count,
            baselineNightCount: baselineNights
        )
    }

    /// The scenario from the audit: sleep recorded, HRV and resting HR and
    /// respiration all absent. The weighted engine renormalises and can
    /// legitimately return 92 — from sleep duration alone.
    func testSleepOnlyNightIsNotShownAsAScore() {
        let recovery = score(percent: 92, completeness: 20, baselineNights: 30)

        guard case .limited(let reason) = recovery.presentation else {
            return XCTFail("Expected .limited, got \(recovery.presentation)")
        }
        XCTAssertFalse(recovery.presentation.isShowable)
        XCTAssertNil(recovery.presentation.score, "92 must not reach a surface")
        XCTAssertTrue(reason.contains("physiological"))
    }

    /// A thin baseline is a different problem with a different remedy, so it
    /// is named separately rather than collapsed into "limited".
    func testThinBaselineReportsBuildingNotLimited() {
        let recovery = score(percent: 74, completeness: 100, baselineNights: 3)

        guard case .buildingBaseline(let nights, let required) = recovery.presentation else {
            return XCTFail("Expected .buildingBaseline, got \(recovery.presentation)")
        }
        XCTAssertEqual(nights, 3)
        XCTAssertEqual(required, RecoveryScore.minimumBaselineNights)
        XCTAssertFalse(recovery.presentation.isShowable)
    }

    /// A well-covered night on a real baseline still shows its number.
    func testWellCoveredNightIsShown() {
        let recovery = score(percent: 74, completeness: 100, baselineNights: 30)
        XCTAssertEqual(recovery.presentation.score, 74)
        XCTAssertTrue(recovery.presentation.isShowable)
        XCTAssertEqual(recovery.presentation.placeholder, "74")
    }

    /// Partial coverage is showable but qualified, not silently confident.
    func testPartialCoverageIsShownWithLowerConfidence() {
        let recovery = score(percent: 66, completeness: 55, baselineNights: 30)
        guard case .available(let value, let confidence) = recovery.presentation else {
            return XCTFail("Expected .available, got \(recovery.presentation)")
        }
        XCTAssertEqual(value, 66)
        XCTAssertLessThan(confidence, .high)
        XCTAssertNotNil(recovery.presentation.explanation)
    }

    // MARK: - Energy inherits the verdict

    /// The compounding failure: weak provenance produced a high Recovery
    /// number, which charged the battery, which produced a precise Energy
    /// figure the user could read as measured.
    func testUnstatableRecoveryDoesNotChargeTheBattery() {
        let blended = BodyBattery.overnightCharge(recoveryPercent: 92, sleepPerformance: 40)
        let sleepOnly = BodyBattery.overnightCharge(recoveryPercent: nil, sleepPerformance: 40)

        XCTAssertNotEqual(blended, sleepOnly, accuracy: 0.001,
                          "An unstatable 92 must not charge as a measured 92")
        XCTAssertLessThan(sleepOnly, blended)
    }

    func testEnergyProvenanceFollowsRecoveryState() {
        XCTAssertEqual(
            BodyBattery.provenance(for: .available(score: 74, confidence: .high)),
            .fullPhysiologicalRecovery
        )
        XCTAssertEqual(
            BodyBattery.provenance(for: .available(score: 66, confidence: .low)),
            .partialRecovery
        )
        XCTAssertEqual(
            BodyBattery.provenance(for: .limited(reason: "x")),
            .sleepDerivedEstimate
        )
        XCTAssertEqual(
            BodyBattery.provenance(for: .buildingBaseline(nights: 3, required: 7)),
            .sleepDerivedEstimate
        )
        XCTAssertEqual(BodyBattery.provenance(for: .unavailable), .insufficient)
    }

    /// Energy can never outrank the recovery it was charged from.
    func testEnergyConfidenceNeverExceedsItsInput() {
        var battery = BodyBattery.empty
        battery.restingBaselineSource = .personalBaseline
        battery.provenance = .sleepDerivedEstimate
        XCTAssertLessThanOrEqual(battery.confidence, .low,
                                 "A perfect resting baseline cannot rescue a sleep-only charge")
    }
}
