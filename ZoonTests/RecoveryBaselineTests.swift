import XCTest

/// A window of nights is never uniformly populated: wrist temperature needs a
/// Series 8+, respiratory rate needs the feature on and the watch worn, and
/// true resting heart rate only lands once HealthKit computes it for the day.
/// `RecoveryBaseline.from(nights:)` must therefore qualify each metric on its
/// own sample count -- averaging the one or two nights that happen to carry a
/// metric, and presenting that with the same authority as a well-sampled
/// baseline, is the bug these lock down.
final class RecoveryBaselineTests: XCTestCase {

    /// Nights where only `withTemperature` of them carry a wrist-temp reading;
    /// everything else is present on every night.
    private func nights(count: Int, withTemperature: Int) -> [SleepNightFeatures] {
        (0..<count).map { index in
            Fixture.night(
                daysAgo: count - index,
                wristTempDeltaC: index < withTemperature ? 0.2 : nil
            )
        }
    }

    func testMetricBelowSampleFloorIsExcludedEvenInALongWindow() {
        // The spec's example: a long window whose temperature coverage is one night.
        let history = nights(count: 30, withTemperature: 1)
        let baseline = RecoveryBaseline.from(nights: history)

        XCTAssertNil(baseline.wristTemperature, "one sample must not become a 30-night baseline")
        // Everything else was present on all 30 nights and should survive.
        XCTAssertNotNil(baseline.hrv)
        XCTAssertNotNil(baseline.restingHeartRate)
        XCTAssertNotNil(baseline.respiratoryRate)
    }

    func testMetricAtTheSampleFloorIsIncluded() {
        let history = nights(count: 30, withTemperature: RecoveryBaseline.minimumSamplesPerMetric)
        let baseline = RecoveryBaseline.from(nights: history)

        XCTAssertNotNil(baseline.wristTemperature)
    }

    func testMetricOneBelowTheSampleFloorIsExcluded() {
        let history = nights(count: 30, withTemperature: RecoveryBaseline.minimumSamplesPerMetric - 1)
        let baseline = RecoveryBaseline.from(nights: history)

        XCTAssertNil(baseline.wristTemperature)
    }

    /// nightCount describes the window, not any single metric's coverage --
    /// it only drives the overall "still building a baseline" flag.
    func testNightCountReflectsTheWindowNotMetricCoverage() {
        let history = nights(count: 30, withTemperature: 1)
        XCTAssertEqual(RecoveryBaseline.from(nights: history).nightCount, 30)
    }

    func testEmptyHistoryProducesNoBaselines() {
        let baseline = RecoveryBaseline.from(nights: [])

        XCTAssertNil(baseline.hrv)
        XCTAssertNil(baseline.restingHeartRate)
        XCTAssertNil(baseline.respiratoryRate)
        XCTAssertNil(baseline.wristTemperature)
        XCTAssertEqual(baseline.nightCount, 0)
    }

    /// The end-to-end consequence: an under-sampled metric must reach
    /// RecoveryScore as unavailable, so it's excluded and renormalized around
    /// rather than scored against a mean of one or two readings.
    func testUnderSampledMetricIsExcludedFromTheScore() {
        let history = (0..<30).map { index in
            Fixture.night(daysAgo: 30 - index, avgHRV: index < 1 ? 55 : nil)
        }
        let baseline = RecoveryBaseline.from(nights: history)
        let score = RecoveryScore.compute(
            features: Fixture.night(), baseline: baseline, sleepPerformance: 100
        )

        let hrv = score.components.first { $0.label == "HRV" }
        XCTAssertEqual(hrv?.isAvailable, false)
        XCTAssertEqual(hrv?.effectiveWeight, 0)
    }
}
