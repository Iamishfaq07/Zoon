import XCTest

/// "Is there a number" and "may a number be printed" are different questions.
/// The watch and the widgets already ask the second; the phone's Energy
/// Reserve card asked neither and printed a level, three stats and a sentence
/// of advice regardless of what charged it.
final class EnergyPresentabilityTests: XCTestCase {

    func testOnlyInsufficientWithholdsTheNumber() {
        XCTAssertFalse(BodyBattery.Provenance.insufficient.isPresentable)
        for provenance: BodyBattery.Provenance in [
            .fullPhysiologicalRecovery, .partialRecovery, .sleepDerivedEstimate
        ] {
            XCTAssertTrue(
                provenance.isPresentable,
                "\(provenance) is a weaker charge, not an absent one"
            )
        }
    }

    /// A weak charge still prints — with its caveat. Only an absent one is
    /// withheld, which keeps "we don't know" distinct from "we know roughly".
    func testAWeakChargeStillPrintsAndStillWarns() throws {
        var battery = BodyBattery(
            points: [BodyBattery.Point(date: .now, level: 64, delta: 0)],
            current: 64, morningPeak: 80, dayLow: 55
        )
        battery.provenance = .sleepDerivedEstimate
        battery.restingBaselineSource = .personalBaseline

        XCTAssertTrue(battery.provenance.isPresentable)
        XCTAssertNotNil(battery.confidenceNote)
    }

    func testAnAbsentChargeIsNotPresentableAndSaysWhy() throws {
        var battery = BodyBattery(
            points: [BodyBattery.Point(date: .now, level: 64, delta: 0)],
            current: 64, morningPeak: 80, dayLow: 55
        )
        battery.provenance = .insufficient

        XCTAssertFalse(battery.provenance.isPresentable)
        XCTAssertNotNil(battery.confidenceNote, "withholding without explaining is worse than either")
    }

    /// Recovery's verdict is what sets the charge, so an unavailable Recovery
    /// must not leave a presentable Energy behind it.
    func testAnUnavailableRecoveryProducesAnUnpresentableCharge() {
        XCTAssertFalse(
            BodyBattery.provenance(for: .unavailable).isPresentable,
            "Energy cannot be more certain than the recovery that charged it"
        )
    }

    /// Still building a baseline is not the same as having nothing: the
    /// charge falls back to sleep, which is a real if weaker basis. It prints,
    /// with its caveat. Only `.unavailable` -- no recovery at all -- is
    /// withheld, which is what keeps "we know roughly" apart from "we don't
    /// know".
    func testStillBuildingABaselineStillCharges() {
        let provenance = BodyBattery.provenance(for: .buildingBaseline(nights: 2, required: 14))
        XCTAssertEqual(provenance, .sleepDerivedEstimate)
        XCTAssertTrue(provenance.isPresentable)
    }

    func testAFullRecoveryProducesAPresentableCharge() {
        XCTAssertTrue(
            BodyBattery.provenance(for: .available(score: 71, confidence: .high)).isPresentable
        )
    }
}
