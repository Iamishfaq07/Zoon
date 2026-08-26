import XCTest

final class DataQualityTests: XCTestCase {

    /// `.sleep`'s own coverage measures nights *present* against the full
    /// window, not against itself (which would trivially always be 100%
    /// for any night that exists) -- a history shorter than the window
    /// should read as partial sleep coverage, not perfect.
    func testSleepCoverageCountsMissingNightsAgainstTheFullWindow() {
        let nights = Fixture.consecutiveNights(10)
        let quality = DataQuality.compute(nights: nights, windowDays: 30)

        let sleep = quality.coverage.first { $0.metric == .sleep }
        XCTAssertEqual(sleep?.presentNightCount, 10)
        XCTAssertEqual(sleep?.expectedNightCount, 30)
        XCTAssertEqual(sleep?.fraction ?? 0, 10.0 / 30.0, accuracy: 0.001)
    }

    /// A secondary metric missing from every night in an otherwise-full
    /// window should read as fully insufficient, not silently pass.
    func testMissingSecondaryMetricReadsAsInsufficientCoverage() {
        let nights = Fixture.consecutiveNights(30, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, avgHRV: nil)
        })
        let quality = DataQuality.compute(nights: nights, windowDays: 30)

        let hrv = quality.coverage.first { $0.metric == .hrv }
        XCTAssertEqual(hrv?.presentNightCount, 0)
        XCTAssertEqual(hrv?.confidence, .insufficient)
    }

    /// Full coverage of a metric across a full window should read as
    /// strong confidence, not merely "not insufficient."
    func testFullCoverageReadsAsStrongConfidence() {
        let nights = Fixture.consecutiveNights(30, template: { daysAgo in
            Fixture.night(daysAgo: daysAgo, avgHRV: 55)
        })
        let quality = DataQuality.compute(nights: nights, windowDays: 30)

        let hrv = quality.coverage.first { $0.metric == .hrv }
        XCTAssertEqual(hrv?.percent, 100)
        XCTAssertEqual(hrv?.confidence, .strong)
    }

    /// Nights outside the trailing window shouldn't count toward coverage
    /// at all, in either direction.
    func testNightsOutsideTheWindowAreExcluded() {
        let recent = Fixture.consecutiveNights(10)
        let old = (40...50).map { daysAgo in
            Fixture.night(daysAgo: daysAgo)
        }
        let quality = DataQuality.compute(nights: recent + old, windowDays: 30)

        let sleep = quality.coverage.first { $0.metric == .sleep }
        XCTAssertEqual(sleep?.presentNightCount, 10)
        XCTAssertEqual(sleep?.totalNightCount, 10)
    }
}
