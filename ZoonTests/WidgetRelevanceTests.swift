import XCTest

final class WidgetRelevanceTests: XCTestCase {

    func testPlaceholderAlwaysScoresLow() {
        let now = Date.now
        XCTAssertEqual(WidgetRelevance.score(isPlaceholder: true, now: now, generatedAt: now), 10)
        // Even a snapshot generated a minute ago -- placeholder overrides everything.
        XCTAssertEqual(
            WidgetRelevance.score(isPlaceholder: true, now: now, generatedAt: now.addingTimeInterval(-60)),
            10
        )
    }

    func testScoresHighWithinFourHoursOfGeneration() {
        let generatedAt = Date.now
        let threeHoursLater = generatedAt.addingTimeInterval(3 * 3600)
        XCTAssertEqual(WidgetRelevance.score(isPlaceholder: false, now: threeHoursLater, generatedAt: generatedAt), 80)
    }

    func testScoresHighAtExactlyGenerationTime() {
        let generatedAt = Date.now
        XCTAssertEqual(WidgetRelevance.score(isPlaceholder: false, now: generatedAt, generatedAt: generatedAt), 80)
    }

    func testScoresLowPastFourHours() {
        let generatedAt = Date.now
        let fiveHoursLater = generatedAt.addingTimeInterval(5 * 3600)
        XCTAssertEqual(WidgetRelevance.score(isPlaceholder: false, now: fiveHoursLater, generatedAt: generatedAt), 20)
    }

    func testScoresLowAtExactlyTheFourHourBoundary() {
        // hoursSinceGenerated < 4 is strict, so exactly 4 hours should not
        // still read as "recently refreshed".
        let generatedAt = Date.now
        let fourHoursLater = generatedAt.addingTimeInterval(4 * 3600)
        XCTAssertEqual(WidgetRelevance.score(isPlaceholder: false, now: fourHoursLater, generatedAt: generatedAt), 20)
    }

    func testScoresLowWhenGeneratedAtIsInTheFuture() {
        // A snapshot generatedAt after `now` (clock skew, or a stale/corrupt
        // timestamp) shouldn't be treated as "just refreshed" -- the
        // negative-hours guard exists precisely for this.
        let now = Date.now
        let generatedInFuture = now.addingTimeInterval(3600)
        XCTAssertEqual(WidgetRelevance.score(isPlaceholder: false, now: now, generatedAt: generatedInFuture), 20)
    }
}
