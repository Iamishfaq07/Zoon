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
        // Replaced an `isJournaled` flag that meant only "a JournalEntry
        // row exists" -- which the old model read as a confident no for
        // every untagged behaviour, though a row is created merely by
        // opening the journal screen. `true` now states what these fixtures
        // actually mean: the whole list was worked through, so tagged
        // behaviours are yes and every other one is an explicit no. `false`
        // means nothing was answered, so every behaviour is unknown.
        fullyAnswered: Bool = true,
        sleepPerformance: Double? = 80,
        wakeCount: Double = 2
    ) -> JournalCorrelator.Observation {
        JournalCorrelator.Observation(
            date: date, tags: tags, answers: fullyAnswered ? .fullyAnswered(tags: tags) : .none, recoveryPercent: 70,
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
        // 7 known and compliant (journaled, no alcohol tag -- default
        // .avoid direction), 4 unknown (never journaled). Compliant count
        // must clear the same minimumPeriodNights floor the primary
        // analysis now requires (see testTooFewAdherentNightsReturnsNil),
        // or summarize returns nil before this test's own assertions run.
        var trialNights: [JournalCorrelator.Observation] = []
        for i in 0..<7 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], fullyAnswered: true))
        }
        for i in 7..<11 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], fullyAnswered: false))
        }
        let endDate = dateOffset(10, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )

        guard let outcome else { return XCTFail("expected an outcome") }
        XCTAssertEqual(outcome.trialNightCount, 11)
        XCTAssertEqual(outcome.trialKnownNightCount, 7)
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
        // 8 compliant (journaled, no alcohol tag), 6 known but noncompliant
        // (alcohol tagged) -- 8 clears the primary-analysis adherent-night
        // floor (see testTooFewAdherentNightsReturnsNil) while still
        // demonstrating adherence (8/14) reads differently from "100% known".
        for i in 0..<8 {
            // Compliant: journaled, no alcohol tag -- exposureState resolves to `.no`.
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], fullyAnswered: true))
        }
        for i in 8..<14 {
            // Known, but noncompliant: alcohol tagged.
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.alcohol], fullyAnswered: true))
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
        XCTAssertEqual(outcome.trialCompliantNightCount, 8)
        XCTAssertEqual(outcome.adherenceRate ?? 0, 8.0 / 14.0, accuracy: 0.001)
    }

    /// For a `.pursue` direction ("do more of this"), compliance flips: a
    /// night the tag was tagged "yes" is the compliant one.
    func testPursueDirectionCountsYesNightsAsCompliant() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        var trialNights: [JournalCorrelator.Observation] = []
        for i in 0..<8 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.hardTraining], fullyAnswered: true))
        }
        for i in 8..<10 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], fullyAnswered: true))
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

    // MARK: - Primary analysis uses only adherent nights

    /// The actual bug this fix addresses: `trialMedian` used to average
    /// every night in the trial window, compliant or not. A trial testing
    /// "avoid late caffeine" where most nights still had late caffeine
    /// would report a "trial" outcome dominated by the nights nothing was
    /// actually being tried. Here the compliant nights all score 90 and
    /// the noncompliant ones all score 40 -- if trialMedian included the
    /// noncompliant nights it would land far below 90.
    func testTrialMedianUsesOnlyAdherentNightsNotAllTrialNights() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate), sleepPerformance: 80)
        }
        var trialNights: [JournalCorrelator.Observation] = []
        for i in 0..<8 {
            // Compliant: no alcohol tag.
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], fullyAnswered: true, sleepPerformance: 90))
        }
        for i in 8..<14 {
            // Noncompliant: alcohol tagged.
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.alcohol], fullyAnswered: true, sleepPerformance: 40))
        }
        let endDate = dateOffset(13, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance, direction: .avoid,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )

        guard let outcome else { return XCTFail("expected an outcome") }
        XCTAssertEqual(outcome.trialMedian, 90, accuracy: 0.001)
    }

    /// A trial can have plenty of total nights logged and still not have
    /// enough *compliant* ones to say anything -- the primary analysis
    /// must require its own minimum on adherent nights, not just on the
    /// trial window's raw night count.
    func testTooFewAdherentNightsReturnsNilEvenWithEnoughTotalTrialNights() {
        let baselineNights = (1...14).map { i in
            observation(date: dateOffset(-i, from: startDate))
        }
        var trialNights: [JournalCorrelator.Observation] = []
        // 14 total trial nights, but only 3 compliant -- below the
        // minimumPeriodNights floor the primary analysis now enforces.
        for i in 0..<3 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [], fullyAnswered: true))
        }
        for i in 3..<14 {
            trialNights.append(observation(date: dateOffset(i, from: startDate), tags: [.alcohol], fullyAnswered: true))
        }
        let endDate = dateOffset(13, from: startDate)

        let outcome = GuidedExperiment.summarize(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance, direction: .avoid,
            startDate: startDate, endDate: endDate,
            observations: baselineNights + trialNights
        )
        XCTAssertNil(outcome)
    }

    // MARK: - Controlled designs

    /// The arm that does what the experiment asks is the trial; the other
    /// arm is its baseline. Nights without alcohol score 88, nights with it
    /// 80, and every assigned night followed the plan -- so the outcome
    /// reads without (trial) against with (baseline), and never against the
    /// fortnight before the schedule, which has no nights here at all.
    func testACrossoverIsReadAgainstItsScheduleNotTheFortnightBefore() throws {
        let schedule = ExperimentDesign.abba.schedule(
            startingOn: startDate, blockNights: 7, seed: 1, calendar: calendar
        )
        let observations = schedule.map { assignment in
            observation(
                date: assignment.date,
                tags: assignment.arm == .with ? [.alcohol] : [],
                sleepPerformance: assignment.arm == .with ? 80 : 88
            )
        }

        let outcome = try XCTUnwrap(GuidedExperiment.summarizeCrossover(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance, direction: .avoid,
            schedule: schedule, endDate: dateOffset(28, from: startDate),
            observations: observations, calendar: calendar
        ))

        XCTAssertEqual(outcome.baselineMedian, 80, accuracy: 0.001)
        XCTAssertEqual(outcome.trialMedian, 88, accuracy: 0.001)
        XCTAssertTrue(outcome.isImprovement)
        XCTAssertEqual(outcome.trialNightCount, 28, "every assigned night, both arms")
        XCTAssertEqual(outcome.trialCompliantNightCount, 28)
        XCTAssertEqual(outcome.trialKnownNightCount, 28)
        XCTAssertEqual(outcome.baselineNightCount, 14, "the with arm's followed nights")
        XCTAssertEqual(outcome.startDate, schedule.first?.date)
        XCTAssertEqual(outcome.direction, .avoid)
    }

    /// A stretch nobody followed is refused, the same way `analyse` refuses
    /// it, rather than summarised from the nights around it.
    func testACrossoverWithAnUnfollowedStretchProducesNoOutcome() {
        let schedule = ExperimentDesign.ab.schedule(
            startingOn: startDate, blockNights: 7, seed: 1, calendar: calendar
        )
        // Every night alcohol-free: the "with" stretch has no adherent nights.
        let observations = schedule.map { assignment in
            observation(date: assignment.date, tags: [], sleepPerformance: 85)
        }

        XCTAssertNil(GuidedExperiment.summarizeCrossover(
            tag: .alcohol, hypothesis: nil, primaryMetric: .sleepPerformance, direction: .avoid,
            schedule: schedule, endDate: dateOffset(14, from: startDate),
            observations: observations, calendar: calendar
        ))
    }

    // MARK: - Interval on the median difference

    /// A ten-point shift between two tight samples excludes zero; the same
    /// baseline against noise around its own median does not.
    func testAClearShiftExcludesZeroAndNoiseDoesNot() throws {
        let baseline: [Double] = [78, 80, 79, 81, 80, 82, 78, 80, 79, 81]

        let clear = try XCTUnwrap(GuidedExperiment.medianDifferenceInterval(
            baseline: baseline, trial: baseline.map { $0 + 10 }
        ))
        XCTAssertGreaterThan(clear.lower, 0)
        XCTAssertLessThan(clear.lower, clear.upper)

        let wobble = try XCTUnwrap(GuidedExperiment.medianDifferenceInterval(
            baseline: baseline, trial: [79, 81, 80, 80, 82, 78, 81, 79, 80, 80]
        ))
        XCTAssertLessThanOrEqual(wobble.lower, 0)
        XCTAssertGreaterThanOrEqual(wobble.upper, 0)
    }

    func testTheIntervalIsDeterministicAndNeedsTheSummaryMinimumNights() {
        let baseline: [Double] = [78, 80, 79, 81, 80, 82, 78]
        let trial: [Double] = [84, 86, 85, 87, 86, 88, 84]
        let first = GuidedExperiment.medianDifferenceInterval(baseline: baseline, trial: trial)
        let second = GuidedExperiment.medianDifferenceInterval(baseline: baseline, trial: trial)
        XCTAssertEqual(first?.lower, second?.lower)
        XCTAssertEqual(first?.upper, second?.upper)

        XCTAssertNil(GuidedExperiment.medianDifferenceInterval(
            baseline: Array(baseline.dropLast()), trial: trial
        ))
    }
}
