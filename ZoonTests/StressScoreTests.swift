import XCTest

final class StressScoreTests: XCTestCase {

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
}
