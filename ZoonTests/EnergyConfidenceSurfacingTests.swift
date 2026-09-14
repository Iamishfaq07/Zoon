import XCTest

/// Energy has two independent weaknesses. The charge sets the level the day
/// starts from and comes from Recovery; the drawdown needs a resting rate to
/// measure effort against. `confidenceNote` used to report only the second.
final class EnergyConfidenceSurfacingTests: XCTestCase {

    private func battery(
        provenance: BodyBattery.Provenance,
        resting: BodyBattery.RestingBaselineSource
    ) -> BodyBattery {
        var battery = BodyBattery(
            points: [BodyBattery.Point(date: .now, level: 70, delta: 0)],
            current: 70,
            morningPeak: 80,
            dayLow: 55
        )
        battery.provenance = provenance
        battery.restingBaselineSource = resting
        return battery
    }

    func testAFullyGroundedCurveNeedsNoCaveat() {
        let note = battery(provenance: .fullPhysiologicalRecovery, resting: .personalBaseline)
            .confidenceNote
        XCTAssertNil(note)
    }

    /// The case that used to go unmentioned: a sleep-derived charge sitting
    /// behind a perfectly good personal resting baseline.
    func testASleepDerivedChargeIsNamedEvenWithAPersonalRestingBaseline() throws {
        let note = try XCTUnwrap(
            battery(provenance: .sleepDerivedEstimate, resting: .personalBaseline).confidenceNote,
            "a charge with no recovery behind it must say so"
        )
        XCTAssertTrue(note.lowercased().contains("sleep alone"))
    }

    /// The charge is named first when both are weak: a wrong starting level
    /// is wrong all day, while a rough drawdown only drifts.
    func testTheChargeOutranksTheDrawdown() throws {
        let note = try XCTUnwrap(
            battery(provenance: .insufficient, resting: .unavailable).confidenceNote
        )
        XCTAssertFalse(
            note.lowercased().contains("overnight reserve only"),
            "the drawdown note must not displace the larger caveat"
        )
    }

    func testTheDrawdownIsStillReportedWhenTheChargeIsSound() throws {
        let note = try XCTUnwrap(
            battery(provenance: .fullPhysiologicalRecovery, resting: .unavailable).confidenceNote
        )
        XCTAssertTrue(note.lowercased().contains("resting heart-rate baseline"))
    }

    // MARK: - The glance surfaces

    private func payload(energy: Int?, confidence: MetricConfidence?) -> SleepSnapshot {
        var snapshot = SleepSnapshot(
            features: Fixture.night(daysAgo: 1),
            score: SleepScore(value: 70, components: []),
            insight: SleepInsight(
                summary: "summary", likelyCause: "cause", actionableTip: "tip", confidence: .medium
            ),
            goalMinutes: 480,
            bodyBattery: energy
        )
        snapshot.energyConfidence = confidence?.rawValue ?? ""
        return snapshot
    }

    /// "Is there a number" and "is it a number to state" are different
    /// questions, and the wrist was only asking the first.
    func testPresenceIsNotTheSameQuestionAsConfidence() {
        let snapshot = payload(energy: 64, confidence: .insufficient)
        XCTAssertTrue(snapshot.hasEnergy, "the number is present")
        XCTAssertFalse(snapshot.canStateEnergy, "but it is not one to state")
    }

    func testAbsentEnergyIsStillAbsent() {
        let snapshot = payload(energy: nil, confidence: .high)
        XCTAssertFalse(snapshot.hasEnergy)
        XCTAssertFalse(snapshot.canStateEnergy, "confidence in nothing is still nothing")
    }

    func testWeakButRealConfidenceIsStated() {
        for confidence: MetricConfidence in [.low, .moderate, .high] {
            XCTAssertTrue(payload(energy: 64, confidence: confidence).canStateEnergy)
        }
    }

    func testLegacyPayloadWithNoConfidenceStillStatesEnergy() {
        XCTAssertTrue(payload(energy: 64, confidence: nil).canStateEnergy)
    }

    func testConfidenceSurvivesTheWire() throws {
        let decoded = try JSONDecoder().decode(
            SleepSnapshot.self,
            from: JSONEncoder().encode(payload(energy: 64, confidence: .insufficient))
        )
        XCTAssertFalse(decoded.canStateEnergy)
    }
}
