import XCTest

final class StressScoreTests: XCTestCase {

    func testBaselineContextIsDisclosedOnEveryScore() {
        let score = StressScore.compute(
            avgHeartRate: 78, avgHRV: 34, hrBaseline: 64, hrvBaseline: 52,
            sampledMinutes: 240, baselineNightCount: 10
        )
        XCTAssertTrue(score?.baselineContextNote.contains("overnight") == true)
        XCTAssertEqual(StressScore.minimumBaselineNights, 7)
    }

    /// `StressDetailView` shows today's reading against its own baseline for
    /// each signal -- that only works if `compute` actually carries the
    /// baselines it was given onto the returned score, not just the blended
    /// percent.
    func testComputeCarriesBothBaselinesOntoTheScore() {
        let score = StressScore.compute(
            avgHeartRate: 78,
            avgHRV: 34,
            hrBaseline: 64,
            hrvBaseline: 52,
            sampledMinutes: 240,
            baselineNightCount: 10
        )

        XCTAssertEqual(score?.hrBaseline, 64)
        XCTAssertEqual(score?.hrvBaseline, 52)
    }

    /// When only one signal has a baseline, the other's `nil` baseline must
    /// still come through untouched -- a detail view showing "Not available"
    /// for the missing one depends on this staying `nil`, not falling back to
    /// some other value.
    func testComputeCarriesANilBaselineWhenOnlyOneSignalHasOne() {
        let score = StressScore.compute(
            avgHeartRate: 78,
            avgHRV: 34,
            hrBaseline: 64,
            hrvBaseline: nil,
            sampledMinutes: 240,
            baselineNightCount: 10
        )

        XCTAssertEqual(score?.hrBaseline, 64)
        XCTAssertNil(score?.hrvBaseline)
    }

    /// The spec maps HR deviation across ±20% and HRV deviation across ±35%
    /// of baseline. A previous version divided by the half-width instead,
    /// which silently narrowed both bands to ±10% and ±17.5%.
    func testNormalizationMatchesTheDocumentedBands() {
        let hrTenPercentOver = StressScore.compute(
            avgHeartRate: 66, avgHRV: nil, hrBaseline: 60, hrvBaseline: nil,
            sampledMinutes: 240, baselineNightCount: 10
        )
        XCTAssertEqual(Double(hrTenPercentOver?.percent ?? 0), 75, accuracy: 1)

        let hrTwentyPercentOver = StressScore.compute(
            avgHeartRate: 72, avgHRV: nil, hrBaseline: 60, hrvBaseline: nil,
            sampledMinutes: 240, baselineNightCount: 10
        )
        XCTAssertEqual(hrTwentyPercentOver?.percent, 100)

        let hrvThirtyFivePercentUnder = StressScore.compute(
            avgHeartRate: nil, avgHRV: 32.5, hrBaseline: nil, hrvBaseline: 50,
            sampledMinutes: 240, baselineNightCount: 10
        )
        XCTAssertEqual(hrvThirtyFivePercentUnder?.percent, 100)

        let atBaseline = StressScore.compute(
            avgHeartRate: 60, avgHRV: 50, hrBaseline: 60, hrvBaseline: 50,
            sampledMinutes: 240, baselineNightCount: 10
        )
        XCTAssertEqual(atBaseline?.percent, 50)
    }
}
