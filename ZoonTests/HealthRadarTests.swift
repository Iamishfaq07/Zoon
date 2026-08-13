import XCTest

final class HealthRadarTests: XCTestCase {

    /// The bug this replaces: mean/SD let a single outlier baseline night
    /// (e.g. one bad-data night, or a real one-off illness blip) inflate the
    /// tolerance band enough to mask a real, smaller sustained drift in the
    /// recent window. Median/MAD barely notices the same outlier.
    func testSingleBaselineOutlierDoesNotMaskASustainedDrift() {
        // 29 baseline nights with ordinary night-to-night jitter (52-56),
        // one wild outlier night (90), then 3 recent nights modestly but
        // consistently elevated (59) -- a real, if small, sustained drift.
        var nights: [SleepNightFeatures] = []
        for i in 0..<29 {
            let rhr = Double(52 + (i % 5))
            nights.append(Fixture.night(daysAgo: 32 - i, restingHeartRate: rhr))
        }
        nights.append(Fixture.night(daysAgo: 32 - 29, restingHeartRate: 90)) // the outlier
        for daysAgo in [2, 1, 0] {
            nights.append(Fixture.night(daysAgo: daysAgo, restingHeartRate: 59))
        }

        let radar = HealthRadar.detect(nights: nights)

        let rhrSignal = radar.signals.first { $0.kind == .restingHeartRate }
        XCTAssertNotNil(rhrSignal, "a sustained elevated-RHR drift should be detected despite one outlier baseline night")
        XCTAssertEqual(rhrSignal?.direction, .elevated)
    }

    func testNoDriftWhenRecentNightsMatchBaseline() {
        var nights: [SleepNightFeatures] = []
        for i in 0..<33 {
            nights.append(Fixture.night(daysAgo: 32 - i, restingHeartRate: 54))
        }

        let radar = HealthRadar.detect(nights: nights)

        XCTAssertTrue(radar.signals.isEmpty)
    }

    func testInsufficientHistoryProducesNoSignals() {
        let nights = (0..<5).map { Fixture.night(daysAgo: $0) }
        let radar = HealthRadar.detect(nights: nights)
        XCTAssertTrue(radar.signals.isEmpty)
        XCTAssertEqual(radar.nightCount, 5)
    }
}
