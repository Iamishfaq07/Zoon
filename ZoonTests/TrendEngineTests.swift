import XCTest

final class TrendEngineTests: XCTestCase {

    /// `windowNights` nights at `recent` duration (most recent), followed by
    /// `windowNights` nights at `older` duration further back -- exactly the
    /// two non-overlapping windows `detect` compares.
    private func twoWindowNights(windowNights: Int, recentMinutes: Double, olderMinutes: Double) -> [SleepNightFeatures] {
        let recentWindow = (0..<windowNights).map { offset in
            Fixture.night(daysAgo: offset + 1, timeAsleepMinutes: recentMinutes)
        }
        let olderWindow = (0..<windowNights).map { offset in
            Fixture.night(daysAgo: windowNights + offset + 1, timeAsleepMinutes: olderMinutes)
        }
        return recentWindow + olderWindow
    }

    func testDetectReturnsNothingWithFewerThanTwoFullWindows() {
        let nights = (0..<10).map { Fixture.night(daysAgo: $0 + 1) }
        XCTAssertTrue(TrendEngine.detect(nights: nights, windowNights: 14).isEmpty)
    }

    func testDetectFindsADurationShiftPastThreshold() {
        // 60-minute swing, well past the 15-minute duration threshold.
        let nights = twoWindowNights(windowNights: 14, recentMinutes: 480, olderMinutes: 420)
        let results = TrendEngine.detect(nights: nights, windowNights: 14)
        let duration = results.first { $0.metric == .duration }
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration?.delta ?? .nan, 60, accuracy: 0.001)
    }

    func testDetectSuppressesADurationShiftUnderThreshold() {
        // 5-minute swing is under the 15-minute duration threshold.
        let nights = twoWindowNights(windowNights: 14, recentMinutes: 485, olderMinutes: 480)
        let results = TrendEngine.detect(nights: nights, windowNights: 14)
        XCTAssertNil(results.first { $0.metric == .duration })
    }

    func testDetectComparesTheCurrentWindowAgainstThePriorOneNotItself() {
        // Identical nights in both windows must never report a change.
        let nights = twoWindowNights(windowNights: 14, recentMinutes: 450, olderMinutes: 450)
        let results = TrendEngine.detect(nights: nights, windowNights: 14)
        XCTAssertNil(results.first { $0.metric == .duration })
    }

    func testIsImprovementForHigherIsBetterMetric() {
        // Duration: higherIsBetter, delta > 0 -> improvement.
        let nights = twoWindowNights(windowNights: 14, recentMinutes: 480, olderMinutes: 420)
        let results = TrendEngine.detect(nights: nights, windowNights: 14)
        let duration = results.first { $0.metric == .duration }
        XCTAssertEqual(duration?.isImprovement, true)
    }

    func testIsImprovementForLowerIsBetterMetric() {
        // sleepDebt: higherIsBetter == false, so a *decrease* (negative
        // delta) is what should read as an improvement.
        XCTAssertFalse(TrendEngine.Metric.sleepDebt.higherIsBetter)
        let improvingDebt = TrendEngine.Result(metric: .sleepDebt, currentMedian: 20, previousMedian: 60, windowNights: 14)
        XCTAssertTrue(improvingDebt.isImprovement)
        let worseningDebt = TrendEngine.Result(metric: .sleepDebt, currentMedian: 60, previousMedian: 20, windowNights: 14)
        XCTAssertFalse(worseningDebt.isImprovement)
    }

    func testResultsSortedByRelativeMagnitudeDescending() {
        // A metric with a large relative move should sort before one with a
        // smaller relative move, even if the smaller one has a bigger raw delta.
        let nights = twoWindowNights(windowNights: 14, recentMinutes: 480, olderMinutes: 420)
        let results = TrendEngine.detect(nights: nights, windowNights: 14)
        guard results.count > 1 else { return }
        let magnitudes = results.map { abs($0.delta / max(abs($0.previousMedian), 1)) }
        XCTAssertEqual(magnitudes, magnitudes.sorted(by: >))
    }
}
