import XCTest

/// `WeeklyReport.averageRecovery` is a mean over whichever nights carried a
/// Recovery score; `nightCount` counts every night in the window. They are
/// different numbers, and the report header used to name the second while
/// showing the first.
///
/// `CyclePhaseCorrelation` already drew this distinction with its own
/// `recoveryNightCount`, and its card only claims the full count when the two
/// agree. These tests hold `WeeklyReport` to the same rule.
final class WeeklyReportBasisTests: XCTestCase {

    /// The ordinary case: every night scored, so the two counts agree and the
    /// header has nothing to qualify.
    func testFullyScoredWeekCountsEveryNight() {
        let nights = Fixture.consecutiveNights(7)
        let report = build(nights: nights, scoring: nights)

        XCTAssertEqual(report.nightCount, 7)
        XCTAssertEqual(report.recoveryNightCount, 7)
    }

    /// The case that motivated this: a week where most nights have no
    /// Recovery score. The mean must be reported as resting on the nights
    /// that produced it.
    func testPartiallyScoredWeekCountsOnlyTheScoredNights() {
        let nights = Fixture.consecutiveNights(7)
        let report = build(nights: nights, scoring: Array(nights.prefix(3)))

        XCTAssertEqual(report.nightCount, 7, "the window still holds seven nights")
        XCTAssertEqual(
            report.recoveryNightCount, 3,
            "the mean rests on three nights and must say so"
        )
    }

    /// No scores at all: there is no average, and the basis is zero rather
    /// than the window's size. A header that said "across 7 nights" beside no
    /// number would be claiming an observation that does not exist.
    func testUnscoredWeekHasNoAverageAndNoBasis() {
        let nights = Fixture.consecutiveNights(7)
        let report = build(nights: nights, scoring: [])

        XCTAssertNil(report.averageRecovery)
        XCTAssertEqual(report.recoveryNightCount, 0)
    }

    /// The basis can never exceed the window, whichever nights carry scores —
    /// including scores keyed to dates that are not in the window at all,
    /// which is what a stale recovery store looks like.
    func testBasisNeverExceedsTheWindow() {
        let nights = Fixture.consecutiveNights(5)
        var recoveries: [Date: Int] = [:]
        for night in Fixture.consecutiveNights(20) { recoveries[night.date] = 70 }

        let report = WeeklyReport.build(
            nights: nights,
            recoveries: recoveries,
            previousNights: [],
            previousRecoveries: [:],
            goalMinutes: 480,
            consistencyMinutes: nil
        )

        XCTAssertLessThanOrEqual(report.recoveryNightCount, report.nightCount)
    }

    /// The average is genuinely over the scored nights only, not over the
    /// window with the gaps treated as zero. Missing is not zero.
    func testGapsAreNotAveragedInAsZero() {
        let nights = Fixture.consecutiveNights(7)
        let report = build(nights: nights, scoring: Array(nights.prefix(2)), score: 80)

        XCTAssertEqual(report.averageRecovery ?? 0, 80, accuracy: 0.001)
    }

    private func build(
        nights: [SleepNightFeatures],
        scoring scored: [SleepNightFeatures],
        score: Int = 70
    ) -> WeeklyReport {
        var recoveries: [Date: Int] = [:]
        for night in scored { recoveries[night.date] = score }
        return WeeklyReport.build(
            nights: nights,
            recoveries: recoveries,
            previousNights: [],
            previousRecoveries: [:],
            goalMinutes: 480,
            consistencyMinutes: nil
        )
    }
}
