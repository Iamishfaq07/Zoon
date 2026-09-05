import XCTest

/// The word the app's most-read sentence opens with.
///
/// `makeSummary` graded the night with `SleepScore` -- "Strong night", "Solid
/// night", "Mixed night", "Rough night" -- while every surface around it shows
/// Sleep Intelligence. The two scores measure differently, so the same night
/// could be introduced as "Mixed night" directly under a hero orb grading it
/// Good, with nothing to say the two words were about different things.
final class InsightSummaryBandTests: XCTestCase {

    private let engine = RuleBasedInsightEngine()

    private func summary(
        band: SleepIntelligenceScore.Band?,
        night: SleepNightFeatures = Fixture.night()
    ) -> String {
        engine.generate(
            for: night,
            baseline: .empty,
            goalMinutes: 480,
            band: band
        ).summary
    }

    func testTheSummaryOpensWithTheFlagshipBand() {
        XCTAssertTrue(summary(band: .excellent).hasPrefix("Strong night"))
        XCTAssertTrue(summary(band: .good).hasPrefix("Solid night"))
        XCTAssertTrue(summary(band: .fair).hasPrefix("Mixed night"))
        XCTAssertTrue(summary(band: .poor).hasPrefix("Rough night"))
    }

    /// The point of the change: the grade must follow the score that was
    /// handed in, not one the engine computes for itself.
    func testTheFlagshipBandOverridesWhatSleepScoreWouldSay() {
        // A long, efficient, well-staged night -- SleepScore grades this well.
        let goodNight = Fixture.night(timeAsleepMinutes: 470, timeInBedMinutes: 480, wakeCount: 0)
        let ownGrade = SleepScore.compute(for: goodNight, goalMinutes: 480).band
        XCTAssertTrue(
            ownGrade == .good || ownGrade == .excellent,
            "fixture no longer scores well under SleepScore; the test needs a new one"
        )

        // Sleep Intelligence disagrees -- it weighs regularity, circadian
        // timing and recovery, none of which this night's duration can speak
        // for. The sentence has to follow it.
        XCTAssertTrue(summary(band: .poor, night: goodNight).hasPrefix("Rough night"))
    }

    /// Nights with no flagship score still get a sentence rather than a blank
    /// or an invented grade.
    func testAMissingBandFallsBackRatherThanSayingNothing() {
        let text = summary(band: nil)
        let openings = ["Strong night", "Solid night", "Mixed night", "Rough night"]
        XCTAssertTrue(
            openings.contains { text.hasPrefix($0) },
            "fallback produced no recognised qualifier: \(text)"
        )
    }

    /// One vocabulary. The fallback maps a `SleepScore` value through the
    /// flagship's own band table, so a night can never be graded with a word
    /// the flagship would not have used at that number.
    func testTheFallbackUsesTheFlagshipVocabulary() {
        for percent in 0...100 {
            XCTAssertEqual(
                SleepIntelligenceScore.Band.forPercent(percent).label,
                SleepScore.Band.forValue(percent).label,
                "band tables disagree at \(percent), so the fallback would rename nights"
            )
        }
    }

    /// The convenience overload exists for previews and tests; it must be the
    /// same call, not a second path.
    func testTheConvenienceOverloadMatchesPassingNoBand() {
        let night = Fixture.night()
        XCTAssertEqual(
            engine.generate(for: night, baseline: .empty, goalMinutes: 480).summary,
            engine.generate(for: night, baseline: .empty, goalMinutes: 480, band: nil).summary
        )
    }
}
