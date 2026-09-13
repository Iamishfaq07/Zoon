import XCTest

/// Time-in-zone is a duration claim. These pin what one sample is allowed to
/// say about the time around it.
final class HeartRateZoneIntegratorTests: XCTestCase {

    private let resting: Double = 55
    private let maximum: Double = 190

    private func interval(minutes: Double) -> DateInterval {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return DateInterval(start: start, duration: minutes * 60)
    }

    private func samples(_ offsetsSeconds: [Double], bpm: Double) -> [HeartRateZoneIntegrator.Sample] {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        return offsetsSeconds.map {
            .init(date: start.addingTimeInterval($0), bpm: bpm)
        }
    }

    private func totalMinutes(_ result: HeartRateZoneIntegrator.Result) -> Double {
        result.zoneMinutes.values.reduce(0, +)
    }

    /// The reported bug: one passive reading inside a ten-minute window used
    /// to be credited as ten full minutes in that zone.
    func testOneSampleCannotClaimTenMinutes() {
        let result = HeartRateZoneIntegrator.integrate(
            samples: samples([0], bpm: 142),
            restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 10)
        )
        XCTAssertEqual(totalMinutes(result), 2.5, accuracy: 0.01,
                       "Capped at the interpolation window, not the bin width")
        XCTAssertLessThan(totalMinutes(result), 10)
    }

    /// Dense workout sampling must still be credited in full — the fix must
    /// not undercount real exercise.
    func testDenseWorkoutSamplingIsCreditedInFull() {
        let offsets = stride(from: 0.0, to: 600.0, by: 5.0).map { $0 }
        let result = HeartRateZoneIntegrator.integrate(
            samples: samples(offsets, bpm: 150),
            restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 10)
        )
        XCTAssertEqual(totalMinutes(result), 10.0, accuracy: 0.05)
        XCTAssertEqual(result.coverage, 1.0, accuracy: 0.01)
    }

    /// Sparse older-Watch resting sampling is deliberately under-credited:
    /// the gaps are genuinely unobserved, and low zones carry no weight.
    func testSparseRestingSamplingIsNotExtrapolated() {
        let offsets = stride(from: 0.0, to: 3600.0, by: 300.0).map { $0 }
        let result = HeartRateZoneIntegrator.integrate(
            samples: samples(offsets, bpm: 70),
            restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 60)
        )
        XCTAssertEqual(totalMinutes(result), 30.0, accuracy: 0.1,
                       "12 samples × 2.5 min cap")
        XCTAssertLessThan(result.coverage, 0.75)
    }

    /// A giant gap after one sample must not be inferred at all.
    func testGiantGapIsNotInferred() {
        let result = HeartRateZoneIntegrator.integrate(
            samples: samples([0], bpm: 140),
            restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 180)
        )
        XCTAssertEqual(totalMinutes(result), 2.5, accuracy: 0.01)
        XCTAssertLessThan(result.coverage, 0.02)
    }

    func testNoSamplesProducesNothing() {
        let result = HeartRateZoneIntegrator.integrate(
            samples: [], restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 10)
        )
        XCTAssertTrue(result.zoneMinutes.isEmpty)
        XCTAssertEqual(result.coverage, 0)
    }

    /// Invariants that must hold for any input.
    func testInvariants() {
        let mixed = samples([0, 30, 90, 200, 700, 1800], bpm: 120)
        let result = HeartRateZoneIntegrator.integrate(
            samples: mixed, restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 60)
        )
        XCTAssertGreaterThanOrEqual(result.coverage, 0)
        XCTAssertLessThanOrEqual(result.coverage, 1)
        XCTAssertFalse(result.coverage.isNaN)
        for (zone, minutes) in result.zoneMinutes {
            XCTAssertGreaterThanOrEqual(minutes, 0, "\(zone) negative")
            XCTAssertFalse(minutes.isNaN)
            XCTAssertLessThanOrEqual(minutes, 60, "\(zone) exceeds the window")
        }
    }

    /// Samples outside the window are ignored rather than extending it.
    func testSamplesOutsideTheIntervalAreIgnored() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let outside = [
            HeartRateZoneIntegrator.Sample(date: start.addingTimeInterval(-600), bpm: 170),
            HeartRateZoneIntegrator.Sample(date: start.addingTimeInterval(60), bpm: 100)
        ]
        let result = HeartRateZoneIntegrator.integrate(
            samples: outside, restingHeartRate: resting, maxHeartRate: maximum,
            interval: interval(minutes: 10)
        )
        XCTAssertEqual(totalMinutes(result), 2.5, accuracy: 0.01,
                       "Only the in-window sample counts")
    }

    /// Zone provenance is independent of coverage: perfect sampling against
    /// a guessed maximum is still an estimated model.
    func testProvenancePersonalizationIsSeparateFromCoverage() {
        XCTAssertTrue(HRZoneProvenance.userConfigured.isPersonalized)
        XCTAssertTrue(HRZoneProvenance.observedPersonalized.isPersonalized)
        XCTAssertFalse(HRZoneProvenance.ageEstimated.isPersonalized)
        XCTAssertFalse(HRZoneProvenance.genericFallback.isPersonalized)
    }
}
