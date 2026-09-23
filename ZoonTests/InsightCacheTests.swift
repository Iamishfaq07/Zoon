import XCTest

/// Generated text is served only for the inputs it was generated from.
final class InsightCacheTests: XCTestCase {

    private let night = Date(timeIntervalSince1970: 1_700_000_000)

    private func insight(_ summary: String) -> SleepInsight {
        SleepInsight(summary: summary, likelyCause: nil, actionableTip: "Keep going.",
                     confidence: .medium, source: .appleIntelligence)
    }

    /// The night was corrected, so the prompt changed. The text written for
    /// the old numbers must not be found under the new ones.
    func testAChangedNightDoesNotFindTheOldText() {
        let cache = InsightCache()
        let before = InsightCache.key(prompt: "Time asleep: 420", instructions: "i")
        let after = InsightCache.key(prompt: "Time asleep: 360", instructions: "i")
        cache.store(insight("You slept seven hours."), for: before, night: night)
        XCTAssertNotNil(cache.value(for: before))
        XCTAssertNil(cache.value(for: after))
    }

    /// Change the night, then the model is unavailable: no old text.
    func testAnAttemptInvalidatesTheNightEvenIfItFails() {
        let cache = InsightCache()
        let key = InsightCache.key(prompt: "Time asleep: 420", instructions: "i")
        cache.store(insight("Old."), for: key, night: night)
        cache.invalidate(night: night)
        XCTAssertNil(cache.value(for: key))
    }

    func testOtherNightsSurviveAnInvalidation() {
        let cache = InsightCache()
        let other = night.addingTimeInterval(-86_400)
        let key = InsightCache.key(prompt: "b", instructions: "i")
        cache.store(insight("Other."), for: key, night: other)
        cache.invalidate(night: night)
        XCTAssertNotNil(cache.value(for: key))
    }

    // MARK: - Grounding

    func testANumberThePromptGaveIsGrounded() {
        XCTAssertTrue(GeneratedTextGrounding.isGrounded(
            "You slept 7 hours, about 420 minutes.", in: "Time asleep: 420 minutes"
        ))
    }

    func testAnInventedPercentageIsNot() {
        XCTAssertFalse(GeneratedTextGrounding.isGrounded(
            "Deep sleep was 18% lower than usual.", in: "Deep: 64 minutes. Time asleep: 420"
        ))
    }

    func testSmallCountsAreLanguageNotClaims() {
        XCTAssertTrue(GeneratedTextGrounding.isGrounded("Try 2 things tonight.", in: "nothing"))
    }

    func testDecimalsAreRead() {
        XCTAssertEqual(GeneratedTextGrounding.numbers(in: "HRV 52.5 ms, then 7."), [52.5, 7])
    }
}
