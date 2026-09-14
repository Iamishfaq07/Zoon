import XCTest

/// Coverage and zone boundaries fail independently. A day watched
/// second-by-second can still be sorted by a maximum heart rate nobody has
/// ever measured, and nothing in the old display hinted at that.
final class LoadProvenanceTests: XCTestCase {

    private func score(
        coverage: Bool,
        provenance: HRZoneProvenance
    ) -> StrainScore {
        StrainScore.compute(
            zoneMinutes: [.moderate: 30],
            activeEnergyKcal: 400,
            hasHeartRateCoverage: coverage,
            zoneProvenance: provenance
        )
    }

    func testPersonalZonesNeedNoCaveat() {
        for provenance: HRZoneProvenance in [.userConfigured, .observedPersonalized] {
            XCTAssertNil(score(coverage: true, provenance: provenance).confidenceNote)
            XCTAssertNil(score(coverage: true, provenance: provenance).confidenceTag)
        }
    }

    func testGuessedZonesAreNamedEvenWithFullCoverage() throws {
        let aged = score(coverage: true, provenance: .ageEstimated)
        let note = try XCTUnwrap(aged.confidenceNote, "a guessed ceiling must not read as a measured one")
        XCTAssertTrue(note.lowercased().contains("age"))
        XCTAssertEqual(aged.confidenceTag, "estimated zones")

        let generic = score(coverage: true, provenance: .genericFallback)
        XCTAssertNotNil(generic.confidenceNote)
        XCTAssertNotEqual(generic.confidenceNote, aged.confidenceNote, "a default is not the same as an age estimate")
    }

    /// Thin coverage is the larger caveat and wins the one line available.
    func testMissingCoverageOutranksZoneProvenance() throws {
        let thin = score(coverage: false, provenance: .observedPersonalized)
        XCTAssertEqual(thin.confidenceTag, "estimated")
        XCTAssertTrue(try XCTUnwrap(thin.confidenceNote).lowercased().contains("coverage"))
    }

    /// The active-energy fallback sorts nothing into zones, so it has no zone
    /// provenance to report -- and a score decoded from an older payload has
    /// none either. Unknown must not be presented as generic.
    func testEstimateAndLegacyCarryNoZoneProvenance() throws {
        XCTAssertNil(StrainScore.estimate(activeEnergyKcal: 400, exerciseMinutes: 30).zoneProvenance)

        let legacy = """
        {"value":8.2,"zoneMinutes":{},"isEstimate":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StrainScore.self, from: legacy)
        XCTAssertNil(decoded.zoneProvenance)
        XCTAssertNil(decoded.confidenceNote, "an unknown ceiling must not be reported as a known-bad one")
    }

    func testProvenanceSurvivesARoundTrip() throws {
        let original = score(coverage: true, provenance: .ageEstimated)
        let decoded = try JSONDecoder().decode(
            StrainScore.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded.zoneProvenance, .ageEstimated)
        XCTAssertEqual(decoded, original)
    }

    func testMaximumHeartRateReportsHowItWasDerived() {
        let withAge = HeartRateZoneIntegrator.maximumHeartRate(age: 40)
        XCTAssertEqual(withAge.provenance, .ageEstimated)
        XCTAssertEqual(withAge.bpm, 208 - 0.7 * 40, accuracy: 0.001)
        XCTAssertFalse(withAge.provenance.isPersonalized, "a formula is not a measurement of this person")

        XCTAssertEqual(HeartRateZoneIntegrator.maximumHeartRate(age: nil).provenance, .genericFallback)
        XCTAssertEqual(HeartRateZoneIntegrator.maximumHeartRate(age: 0).provenance, .genericFallback)
        XCTAssertEqual(HeartRateZoneIntegrator.maximumHeartRate(age: 130).provenance, .genericFallback)
    }

    /// Tanaka, not 220 - age. The older rule underestimates for over-40s,
    /// and every zone boundary sits below whichever is used.
    func testTanakaRatherThanTwoTwentyMinusAge() {
        for age in [nil, 25, 40, 65] as [Int?] {
            XCTAssertEqual(
                HeartRateZoneIntegrator.maximumHeartRate(age: age).bpm,
                age.map { Double(208) - 0.7 * Double($0) } ?? 190
            )
        }
    }
}
