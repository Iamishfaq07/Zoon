import XCTest

final class GuidedExperimentTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var startDate: Date {
        calendar.date(from: DateComponents(year: 2024, month: 1, day: 15))!
    }

    private func observation(
        date: Date,
        tags: Set<BehaviorTag> = [],
        isJournaled: Bool = true,
        sleepPerformance: Double? = 80,
        wakeCount: Double = 2
    ) -> JournalCorrelator.Observation {
        JournalCorrelator.Observation(
            date: date, tags: tags, isJournaled: isJournaled, recoveryPercent: 70,
            sleepPerformance: sleepPerformance, deepMinutes: 80, remMinutes: 90, efficiency: 90,
            wakeCount: wakeCount, isWeekend: false, sleepDebtMinutes: 30, bedtimeHour: -1,
            alcoholicBeverages: nil, lateCaffeineMg: nil, measuredTimeZoneShift: false
        )
    }

    private func dateOffset(_ days: Int, from base: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: base)!
    }

    // MARK: - Pre-specified metric, not post-hoc "biggest mover"

    /// The actual bug: `summarize` used to scan every metric and report
    /// whichever moved the most, which is a multiple-comparisons trap. Here
    /// wakeCount swings enormously while sleepPerformance barely moves --
    /// the old code would have reported wakeCount as the finding even
    /// though the experiment was never about awakenings.
    func testSummarizeUsesPreSpecifiedMetricNotStrongestMover() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate), sleepPerformance: 80, wakeCount: 2)
        }
        let trialNights = (0..<10).map { i in
            observation(date: dateOffset(i, from: startDate), sleepPerformance: 82, wakeCount: 8)
        }
        let endDate = dateOffset(9, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )

        guard let outcome else { return XCTFail("expected an outcome") }
        XCTAssertEqual(outcome.metricLabel, JournalCorrelator.Metric.sleepPerformance.shortLabel)
        XCTAssertEqual(outcome.baselineMedian, 80, accuracy: 0.001)
        XCTAssertEqual(outcome.trialMedian, 82, accuracy: 0.001)
    }

    func testMissingPrimaryMetricDataReturnsNilRatherThanSubstitutingAnother() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate), sleepPerformance: nil, wakeCount: 2)
        }
        let trialNights = (0..<10).map { i in
            observation(date: dateOffset(i, from: startDate), sleepPerformance: nil, wakeCount: 8)
        }
        let endDate = dateOffset(9, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )
        XCTAssertNil(outcome)
    }

    // MARK: - Minimum nights

    func testTooFewBaselineNightsReturnsNil() {
        let baselineNights = (1...5).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        let trialNights = (0..<10).map { i in
            observation(date: dateOffset(i, from: startDate))
        }
        let endDate = dateOffset(9, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )
        XCTAssertNil(outcome)
    }

    func testTooFewTrialNightsReturnsNil() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        let trialNights = (0..<5).map { i in
            observation(date: dateOffset(i, from: startDate))
        }
        let endDate = dateOffset(4, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )
        XCTAssertNil(outcome)
    }

    // MARK: - Known vs. compliant trial nights

    /// `trialKnownNightCount` should count only trial nights with a known
    /// yes/no for the tracked tag -- an unjournaled night is neither, and
    /// shouldn't be silently folded into either bucket. This is a measure of
    /// logging completeness, not adherence -- see the tests below for that.
    func testKnownNightCountCountsOnlyLoggedTrialNights() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        // 6 known (tagged "yes"), 4 unknown (never journaled).
        var trialNights: [JournalCorrelator.Observation] = []
        for i in 0..<6 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.alcohol], isJournaled: true))
        }
        for i in 6..<10 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], isJournaled: false))
        }
        let endDate = dateOffset(9, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )

        guard let outcome else { return XCTFail("expected an outcome") }
        XCTAssertEqual(outcome.trialNightCount, 10)
        XCTAssertEqual(outcome.trialKnownNightCount, 6)
    }

    /// The actual bug this fix addresses: adherence used to be
    /// `trialKnownNightCount / trialNightCount` -- nights logged either way,
    /// not nights of actual compliance. The spec's worked example: 14 trial
    /// nights testing "cut back on alcohol", 5 of them genuinely alcohol-free
    /// (compliant), 9 with alcohol tagged (noncompliant, but still known).
    /// All 14 nights are known, so the old formula reported 100% adherence
    /// for a trial that was 9/14 broken. True adherence is 5/14 ≈ 36%.
    func testAdherenceCountsCompliantNightsNotJustKnownNights() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        var trialNights: [JournalCorrelator.Observation] = []
        for i in 0..<5 {
            // Compliant: journaled, no alcohol tag -- exposureState resolves to `.no`.
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], isJournaled: true))
        }
        for i in 5..<14 {
            // Known, but noncompliant: alcohol tagged.
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.alcohol], isJournaled: true))
        }
        let endDate = dateOffset(13, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance, direction: .avoid,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )

        guard let outcome else { return XCTFail("expected an outcome") }
        XCTAssertEqual(outcome.trialNightCount, 14)
        XCTAssertEqual(outcome.trialKnownNightCount, 14)
        XCTAssertEqual(outcome.trialCompliantNightCount, 5)
        XCTAssertEqual(outcome.adherenceRate ?? 0, 5.0 / 14.0, accuracy: 0.001)
    }

    /// For a `.pursue` direction ("do more of this"), compliance flips: a
    /// night the tag was tagged "yes" is the compliant one.
    func testPursueDirectionCountsYesNightsAsCompliant() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        var trialNights: [JournalCorrelator.Observation] = []
        for i in 0..<8 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.hardTraining], isJournaled: true))
        }
        for i in 8..<10 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], isJournaled: true))
        }
        let endDate = dateOffset(9, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .hardTraining, hypothesis: nil, primaryMetric: .sleepPerformance, direction: .pursue,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )

        guard let outcome else { return XCTFail("expected an outcome") }
        XCTAssertEqual(outcome.trialCompliantNightCount, 8)
        XCTAssertEqual(outcome.adherenceRate ?? 0, 0.8, accuracy: 0.001)
    }
}
