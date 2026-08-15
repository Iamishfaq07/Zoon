import XCTest

/// Guards the user-facing strings that shipped wrong.
///
/// Three copy defects reached a build in one working session, all of the same
/// shape: a count interpolated next to a hardcoded plural, or a word appended
/// to a label that already contained it. None was caught by the compiler,
/// because all three are perfectly valid Swift; they were caught by looking at
/// rendered screenshots, which is a slow and lucky way to find them.
///
/// These are cheap assertions on the exact branches that were broken. They
/// don't attempt to cover every string in the app -- that would be a
/// maintenance tax with little return. They cover the ones with a known
/// history of going wrong.
final class CopyCorrectnessTests: XCTestCase {

    // MARK: - Int.pluralized

    func testPluralizedUsesSingularForExactlyOne() {
        XCTAssertEqual(1.pluralized("night"), "1 night")
    }

    func testPluralizedUsesPluralForZero() {
        // Zero takes the plural in English -- "0 nights", not "0 night".
        XCTAssertEqual(0.pluralized("night"), "0 nights")
    }

    func testPluralizedUsesPluralForMany() {
        XCTAssertEqual(7.pluralized("night"), "7 nights")
    }

    func testPluralizedHonoursIrregularPlural() {
        XCTAssertEqual(1.pluralized("journal entry", "journal entries"), "1 journal entry")
        XCTAssertEqual(3.pluralized("journal entry", "journal entries"), "3 journal entries")
    }

    // MARK: - MetricConfidence

    func testConfidenceLabelsAlreadyContainTheWordConfidence() {
        // TodayView appended " confidence" to these and rendered "Moderate
        // confidence confidence". Any call site that appends the word again is
        // wrong, so the labels must keep carrying it themselves.
        XCTAssertTrue(MetricConfidence.low.label.contains("confidence"))
        XCTAssertTrue(MetricConfidence.moderate.label.contains("confidence"))
        XCTAssertTrue(MetricConfidence.high.label.contains("confidence"))
    }

    func testNoConfidenceLabelDoublesTheWord() {
        for confidence in [MetricConfidence.insufficient, .low, .moderate, .high] {
            XCTAssertFalse(
                confidence.label.lowercased().contains("confidence confidence"),
                "\(confidence.label) doubles the word"
            )
        }
    }

    // MARK: - Weekly report goal highlight

    /// A week where the goal was never met. Read "Goal met only 0 of 7
    /// nights" before the fix.
    func testGoalHighlightReadsNaturallyWhenGoalNeverMet() {
        let report = weeklyReport(nightCount: 7, timeAsleepMinutes: 300)
        let title = goalHighlightTitle(in: report)

        XCTAssertNotNil(title, "A week with zero goal hits should produce a caution highlight")
        XCTAssertFalse(title?.contains("only 0") ?? false, "\"only 0 of 7\" is not English")
        XCTAssertEqual(title, "Goal missed every night")
    }

    /// One night, goal met. Read "Hit your goal 1 of 1 nights" before the fix.
    func testGoalHighlightIsSingularForAOneNightWeek() {
        let report = weeklyReport(nightCount: 1, timeAsleepMinutes: 500)
        let title = goalHighlightTitle(in: report)

        XCTAssertNotNil(title)
        XCTAssertFalse(title?.contains("1 nights") ?? false, "\"1 of 1 nights\" is not English")
        XCTAssertEqual(title, "Hit your goal 1 of 1 night")
    }

    /// Some nights met, most missed -- the branch that keeps the "only N of M"
    /// phrasing, which reads fine once N is not zero.
    func testGoalHighlightKeepsOnlyPhrasingAboveZero() {
        // `consecutiveNights` hands the template `count - offset`, so these
        // run 7 days ago through 1. Exactly one clears the 480-minute goal.
        let nights = Fixtures.consecutiveNights(7) { daysAgo in
            Fixtures.night(daysAgo: daysAgo, timeAsleepMinutes: daysAgo == 1 ? 500 : 300)
        }

        let title = goalHighlightTitle(in: weeklyReport(from: nights))
        XCTAssertEqual(title, "Goal met only 1 of 7 nights")
    }

    // MARK: - Helpers

    private func weeklyReport(nightCount: Int, timeAsleepMinutes: Double) -> WeeklyReport {
        weeklyReport(
            from: Fixtures.consecutiveNights(nightCount) { index in
                Fixtures.night(daysAgo: index, timeAsleepMinutes: timeAsleepMinutes)
            }
        )
    }

    private func weeklyReport(from nights: [SleepNightFeatures]) -> WeeklyReport {
        WeeklyReport.build(
            nights: nights,
            recoveries: [:],
            previousNights: [],
            previousRecoveries: [:],
            goalMinutes: 480,
            consistencyMinutes: nil
        )
    }

    /// The goal highlight is the one whose title mentions the goal; matching on
    /// that rather than an index keeps the test working as other highlights are
    /// added or reordered.
    private func goalHighlightTitle(in report: WeeklyReport) -> String? {
        report.highlights
            .first { $0.title.contains("goal") || $0.title.contains("Goal") }?
            .title
    }
}
