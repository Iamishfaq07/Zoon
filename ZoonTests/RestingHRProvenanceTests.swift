import XCTest

/// Covers the resting-heart-rate half of the Load zone model.
///
/// Zones are Karvonen: `(bpm − resting) / (max − resting)`. The resting rate
/// therefore sits in both the numerator and the denominator, and Zoon used to
/// end its lookup chain with a bare `?? 60` — a population constant that
/// arrived unlabelled and made the whole model generic in both terms while
/// the UI went on describing it as personal.
final class RestingHRProvenanceTests: XCTestCase {

    private func interval(minutes: Double) -> DateInterval {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        return DateInterval(start: start, end: start.addingTimeInterval(minutes * 60))
    }

    // MARK: - Which source was used

    func testTodaysMeasuredRestingRateWins() {
        let input = HeartRateZoneIntegrator.restingHeartRate(
            measuredToday: 52, measuredEarlier: 55, sleepDerived: 48
        )
        XCTAssertEqual(input.bpm, 52)
        XCTAssertEqual(input.provenance, .measuredDailyRestingHR)
    }

    /// The chain used to reach for the previous night's measured value ahead
    /// of the current night's, so a fresh reading lost to a day-old one.
    func testAnEarlierMeasurementIsUsedOnlyWhenTodayHasNone() {
        let input = HeartRateZoneIntegrator.restingHeartRate(
            measuredToday: nil, measuredEarlier: 55, sleepDerived: 48
        )
        XCTAssertEqual(input.bpm, 55)
        XCTAssertEqual(input.provenance, .historicalPersonalRestingHR)
    }

    func testSleepDerivedIsPersonalButNotMeasured() {
        let input = HeartRateZoneIntegrator.restingHeartRate(
            measuredToday: nil, measuredEarlier: nil, sleepDerived: 48
        )
        XCTAssertEqual(input.bpm, 48)
        XCTAssertEqual(input.provenance, .sleepDerivedPersonalEstimate)
        XCTAssertTrue(input.provenance.isPersonalized)
    }

    func testNothingPersonalFallsBackAndSaysSo() {
        let input = HeartRateZoneIntegrator.restingHeartRate(
            measuredToday: nil, measuredEarlier: nil, sleepDerived: nil
        )
        XCTAssertEqual(input.bpm, HeartRateZoneIntegrator.genericRestingHeartRate)
        XCTAssertEqual(input.provenance, .genericFallback)
        XCTAssertFalse(input.provenance.isPersonalized)
    }

    /// A corrupt sample in the reserve denominator does not produce a
    /// slightly wrong Load, it produces a nonsensical one.
    func testImplausibleValuesAreRejectedAtEveryTier() {
        XCTAssertEqual(
            HeartRateZoneIntegrator.restingHeartRate(
                measuredToday: 0, measuredEarlier: 260, sleepDerived: 51
            ).provenance,
            .sleepDerivedPersonalEstimate
        )
        XCTAssertEqual(
            HeartRateZoneIntegrator.restingHeartRate(
                measuredToday: -5, measuredEarlier: nil, sleepDerived: 900
            ).provenance,
            .genericFallback
        )
    }

    // MARK: - What it does to confidence

    private func score(
        zones: HRZoneProvenance,
        resting: RestingHRProvenance,
        covered: Bool = true
    ) -> StrainScore {
        StrainScore.compute(
            zoneMinutes: [.moderate: 30],
            activeEnergyKcal: 400,
            hasHeartRateCoverage: covered,
            zoneProvenance: zones,
            restingProvenance: resting
        )
    }

    func testAPerfectlySampledDayOnAGenericRestingRateIsNotHighConfidence() {
        XCTAssertEqual(score(zones: .observedPersonalized, resting: .genericFallback).confidence, .low)
    }

    func testAllThreeStrongGivesHighConfidence() {
        XCTAssertEqual(
            score(zones: .observedPersonalized, resting: .measuredDailyRestingHR).confidence,
            .high
        )
    }

    /// The weakest link decides, whichever of the three it is.
    func testConfidenceTakesTheWeakestOfCoverageZonesAndResting() {
        XCTAssertEqual(
            score(zones: .ageEstimated, resting: .measuredDailyRestingHR).confidence,
            .moderate
        )
        XCTAssertEqual(
            score(zones: .observedPersonalized, resting: .sleepDerivedPersonalEstimate).confidence,
            .moderate
        )
        XCTAssertEqual(
            score(zones: .observedPersonalized, resting: .measuredDailyRestingHR, covered: false).confidence,
            .low
        )
    }

    /// An age-estimated ceiling over a default floor is a population model
    /// wearing a personal label.
    func testIsFullyPersonalizedRequiresBothBoundaries() {
        XCTAssertFalse(score(zones: .ageEstimated, resting: .measuredDailyRestingHR).isFullyPersonalized)
        XCTAssertFalse(score(zones: .observedPersonalized, resting: .genericFallback).isFullyPersonalized)
        XCTAssertTrue(
            score(zones: .userConfigured, resting: .historicalPersonalRestingHR).isFullyPersonalized
        )
    }

    /// Unknown is not generic. A score decoded from a payload written before
    /// provenance existed must not be marked down for it.
    func testUnrecordedProvenanceDoesNotConstrainConfidence() {
        let legacy = StrainScore(
            value: 9, zoneMinutes: [.moderate: 30], activeEnergyKcal: 400, isEstimate: false
        )
        XCTAssertEqual(legacy.confidence, .high)
        XCTAssertNil(legacy.confidenceNote)
        XCTAssertFalse(legacy.isFullyPersonalized)
    }

    func testTheNoteNamesTheRestingRateWhenItIsTheWeakestLink() throws {
        let note = try XCTUnwrap(
            score(zones: .observedPersonalized, resting: .genericFallback).confidenceNote
        )
        XCTAssertTrue(note.lowercased().contains("resting heart rate"), note)
        XCTAssertEqual(
            score(zones: .observedPersonalized, resting: .genericFallback).confidenceTag,
            "default resting rate"
        )
    }

    func testTheNoteStillNamesTheCeilingWhenTheFloorIsSound() throws {
        let note = try XCTUnwrap(
            score(zones: .ageEstimated, resting: .measuredDailyRestingHR).confidenceNote
        )
        XCTAssertTrue(note.contains("age-estimated"), note)
    }

    func testAFullyPersonalScoreHasNothingToQualify() {
        XCTAssertNil(score(zones: .userConfigured, resting: .measuredDailyRestingHR).confidenceNote)
        XCTAssertNil(score(zones: .userConfigured, resting: .measuredDailyRestingHR).confidenceTag)
    }

    // MARK: - Round trip

    func testProvenanceSurvivesEncoding() throws {
        let original = score(zones: .ageEstimated, resting: .sleepDerivedPersonalEstimate)
        let decoded = try JSONDecoder().decode(
            StrainScore.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded.restingProvenance, .sleepDerivedPersonalEstimate)
        XCTAssertEqual(decoded.zoneProvenance, .ageEstimated)
        XCTAssertEqual(decoded.confidence, original.confidence)
    }

    /// A payload written before `restingProvenance` existed must still
    /// decode. Built by encoding a score that has no resting provenance,
    /// which is byte-for-byte what an older build wrote: the synthesized
    /// encoder omits absent optionals entirely.
    func testLegacyPayloadWithoutRestingProvenanceDecodes() throws {
        let legacy = StrainScore(
            value: 9, zoneMinutes: [.moderate: 30], activeEnergyKcal: 400,
            isEstimate: false, zoneProvenance: .ageEstimated
        )
        let data = try JSONEncoder().encode(legacy)
        XCTAssertFalse(
            String(decoding: data, as: UTF8.self).contains("restingProvenance"),
            "an absent optional must not be written, or this is not a legacy payload"
        )
        let decoded = try JSONDecoder().decode(StrainScore.self, from: data)
        XCTAssertNil(decoded.restingProvenance)
        XCTAssertEqual(decoded.zoneProvenance, .ageEstimated)
        XCTAssertEqual(decoded.confidence, .moderate)
    }

    // MARK: - Dense and sparse sampling, workout and passive days

    /// Dense sampling through a workout still integrates to real minutes.
    func testDenseWorkoutSamplingProducesZoneMinutes() {
        let window = interval(minutes: 30)
        let samples = stride(from: 0.0, to: 30.0 * 60, by: 10).map {
            HeartRateZoneIntegrator.Sample(
                date: window.start.addingTimeInterval($0), bpm: 155
            )
        }
        let result = HeartRateZoneIntegrator.integrate(
            samples: samples, restingHeartRate: 50, maxHeartRate: 190, interval: window
        )
        XCTAssertEqual(result.coverage, 1, accuracy: 0.02)
        XCTAssertGreaterThan(result.zoneMinutes.values.reduce(0, +), 29)
    }

    /// A passive day sampled every five minutes is fully *observed* and
    /// carries no zone minutes, because none of it is above 50% reserve.
    func testPassiveDayIsObservedButCarriesNoLoad() {
        let window = interval(minutes: 120)
        let samples = stride(from: 0.0, to: 120.0 * 60, by: 300).map {
            HeartRateZoneIntegrator.Sample(
                date: window.start.addingTimeInterval($0), bpm: 62
            )
        }
        let result = HeartRateZoneIntegrator.integrate(
            samples: samples, restingHeartRate: 55, maxHeartRate: 190, interval: window
        )
        XCTAssertTrue(result.zoneMinutes.isEmpty)
        XCTAssertGreaterThan(result.coverage, 0)
    }

    /// The same beats read as harder work against a generic floor that sits
    /// above the person's real one — or easier, when it sits below. Either
    /// way the score is not about them, which is the whole point of
    /// labelling it.
    func testAGenericRestingRateMovesTheZonesItSortsInto() {
        let window = interval(minutes: 20)
        let samples = stride(from: 0.0, to: 20.0 * 60, by: 15).map {
            HeartRateZoneIntegrator.Sample(
                date: window.start.addingTimeInterval($0), bpm: 140
            )
        }
        func minutes(restingHeartRate: Double) -> [StrainScore.Zone: Double] {
            HeartRateZoneIntegrator.integrate(
                samples: samples,
                restingHeartRate: restingHeartRate,
                maxHeartRate: 190,
                interval: window
            ).zoneMinutes
        }
        // True resting 45: (140−45)/145 = 0.655 → moderate.
        XCTAssertNotNil(minutes(restingHeartRate: 45)[.moderate])
        // Generic 60: (140−60)/130 = 0.615 → still moderate here, but the
        // reserve fraction moved by four points on one substitution.
        XCTAssertNotNil(minutes(restingHeartRate: 60)[.moderate])
        // Push the floor lower against a lower ceiling and the same beats
        // land in a different zone entirely: (140−40)/130 = 0.769, vigorous.
        // Nothing about the day changed; only the boundaries did.
        let harder = HeartRateZoneIntegrator.integrate(
            samples: samples, restingHeartRate: 40, maxHeartRate: 170, interval: window
        )
        XCTAssertNotNil(harder.zoneMinutes[.vigorous])
        XCTAssertNil(harder.zoneMinutes[.moderate])
    }
}
