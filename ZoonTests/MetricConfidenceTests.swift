import XCTest

/// `LearnedSleepNeed.Confidence` and `SleepIntelligenceScore.Confidence` used
/// to be two independently-declared enums with the same four cases and
/// near-duplicate label text. They're now both aliases of `MetricConfidence`
/// -- this locks that in so a future edit can't silently reintroduce a
/// second, drifted copy.
final class MetricConfidenceTests: XCTestCase {

    func testLearnedSleepNeedConfidenceIsMetricConfidence() {
        let value: LearnedSleepNeed.Confidence = .moderate
        XCTAssertTrue(value == MetricConfidence.moderate)
    }

    func testSleepIntelligenceScoreConfidenceIsMetricConfidence() {
        let value: SleepIntelligenceScore.Confidence = .moderate
        XCTAssertTrue(value == MetricConfidence.moderate)
    }

    func testAllFourBandsHaveDistinctLabels() {
        let labels = Set(
            [MetricConfidence.insufficient, .low, .moderate, .high].map(\.label)
        )
        XCTAssertEqual(labels.count, 4)
    }
}
