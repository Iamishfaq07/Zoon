import XCTest

/// Coverage and the zone model weaken a Load score independently, and it is
/// only as good as the weaker of the two.
///
/// Phase 4's own rule: a full day of heart-rate samples sorted into zones
/// drawn from a generic maximum is still estimated. `isEstimate` answered only
/// the coverage half, so that day reported as if nothing were wrong with it.
final class LoadConfidenceTests: XCTestCase {

    private func score(
        coverage: Bool,
        provenance: HRZoneProvenance?
    ) -> StrainScore {
        guard let provenance else {
            // The active-energy fallback and legacy payloads both record none.
            return StrainScore(
                value: 9, zoneMinutes: [:], activeEnergyKcal: 400, isEstimate: !coverage
            )
        }
        return StrainScore.compute(
            zoneMinutes: [.moderate: 40],
            activeEnergyKcal: 400,
            hasHeartRateCoverage: coverage,
            zoneProvenance: provenance
        )
    }

    /// The case the rule names.
    func testAFullyWatchedDayOnGuessedZonesIsNotHighConfidence() {
        XCTAssertEqual(score(coverage: true, provenance: .genericFallback).confidence, .low)
        XCTAssertEqual(score(coverage: true, provenance: .ageEstimated).confidence, .moderate)
    }

    func testPersonalZonesWithFullCoverageAreHighConfidence() {
        for provenance: HRZoneProvenance in [.userConfigured, .observedPersonalized] {
            XCTAssertEqual(score(coverage: true, provenance: provenance).confidence, .high)
        }
    }

    /// The weaker half decides, whichever half it is.
    func testThinCoverageCapsEvenPerfectZones() {
        XCTAssertEqual(score(coverage: false, provenance: .userConfigured).confidence, .low)
    }

    /// "We did not record it" is not evidence that it was bad. A legacy
    /// payload with good coverage keeps its confidence rather than being
    /// retroactively downgraded.
    func testUnknownProvenanceDoesNotConstrain() {
        XCTAssertEqual(score(coverage: true, provenance: nil).confidence, .high)
        XCTAssertEqual(score(coverage: false, provenance: nil).confidence, .low)
    }

    /// Confidence and the short tag answer different questions and must not
    /// drift apart: whenever the tag names a weakness, confidence is below
    /// high.
    func testTheTagAndTheConfidenceAgree() {
        let cases: [(Bool, HRZoneProvenance)] = [
            (true, .genericFallback), (true, .ageEstimated),
            (false, .userConfigured), (false, .genericFallback),
        ]
        for (coverage, provenance) in cases {
            let strain = score(coverage: coverage, provenance: provenance)
            XCTAssertNotNil(strain.confidenceTag, "a weakened score should carry a tag")
            XCTAssertLessThan(strain.confidence, .high)
        }
        let clean = score(coverage: true, provenance: .observedPersonalized)
        XCTAssertNil(clean.confidenceTag)
        XCTAssertEqual(clean.confidence, .high)
    }
}
