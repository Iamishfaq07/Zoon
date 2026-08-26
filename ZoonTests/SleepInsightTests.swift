import XCTest

final class SleepInsightTests: XCTestCase {

    // MARK: - Confidence ordering

    func testConfidenceOrdersLowBelowMediumBelowHigh() {
        XCTAssertLessThan(SleepInsight.Confidence.low, .medium)
        XCTAssertLessThan(SleepInsight.Confidence.medium, .high)
        XCTAssertLessThan(SleepInsight.Confidence.low, .high)
    }

    func testConfidenceIsNotLessThanItself() {
        XCTAssertFalse(SleepInsight.Confidence.medium < .medium)
    }

    func testConfidenceSortDescendingPutsHighFirst() {
        let sorted = [SleepInsight.Confidence.medium, .low, .high].sorted(by: >)
        XCTAssertEqual(sorted, [.high, .medium, .low])
    }

    // MARK: - Defaults

    func testDefaultConfidenceIsMediumWhenUnspecified() {
        let insight = SleepInsight(summary: "x", likelyCause: nil, actionableTip: "y")
        XCTAssertEqual(insight.confidence, .medium)
    }

    func testDefaultSourceIsRuleBasedWhenUnspecified() {
        let insight = SleepInsight(summary: "x", likelyCause: nil, actionableTip: "y")
        XCTAssertEqual(insight.source, .ruleBased)
    }

    // MARK: - placeholder

    func testPlaceholderCarriesLowConfidence() {
        XCTAssertEqual(SleepInsight.placeholder.confidence, .low)
    }

    func testPlaceholderHasNoLikelyCause() {
        // A guessed cause with no real data behind it would be exactly the
        // kind of invented-from-noise claim this type's own doc comment
        // warns against.
        XCTAssertNil(SleepInsight.placeholder.likelyCause)
    }

    // MARK: - Source display names

    func testEverySourceHasANonEmptyDisplayName() {
        for source in [SleepInsight.Source.ruleBased, .appleIntelligence, .localLLM] {
            XCTAssertFalse(source.displayName.isEmpty)
        }
    }
}
