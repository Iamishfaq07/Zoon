import XCTest

/// The ledger grades Zoon's own forecasts. These grade the ledger.
///
/// Two properties matter more than the rest: that the backtest cannot see the
/// night it is scoring, and that "calibrated" is measured against what the
/// estimator can actually achieve rather than what its label implies.
final class CalibrationLedgerTests: XCTestCase {

    private func nights(
        _ count: Int, centre: Double = 450, spread: Double = 60, seed: UInt64 = 31
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let asleep = centre + generator.nextDouble(in: -spread...spread)
            return Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - What "calibrated" means

    /// The correction the whole feature rests on.
    ///
    /// A 10th-to-90th interval sounds like 80%. Read off empirical
    /// percentiles of a 21-night window it is not: the bounds land on the 3rd
    /// and 19th order statistics, and a fresh draw falls between the k-th and
    /// m-th of n samples with probability (m - k)/(n + 1) = 16/22.
    ///
    /// Scored against 80%, a perfectly ordinary sleeper reads as
    /// overconfident. Simulation puts that misfire at about a third of
    /// calibrated users, so this is not a rounding quibble.
    func testExpectedCoverageIsNotTheNominalEightyPercent() {
        XCTAssertEqual(CalibrationLedger.expectedCoverage(windowSize: 21), 16.0 / 22.0, accuracy: 0.0005)
        XCTAssertLessThan(CalibrationLedger.expectedCoverage(windowSize: 21), 0.8)
        XCTAssertEqual(CalibrationLedger.expectedCoverage(windowSize: 14), 0.8 * 13 / 15, accuracy: 0.0005)
    }

    /// Longer windows earn more of the label back, and never exceed it.
    func testExpectedCoverageRisesWithWindowAndStaysUnderTheLabel() {
        let short = CalibrationLedger.expectedCoverage(windowSize: 14)
        let long = CalibrationLedger.expectedCoverage(windowSize: 60)
        XCTAssertLessThan(short, long)
        XCTAssertLessThan(long, 0.8)
        XCTAssertEqual(CalibrationLedger.expectedCoverage(windowSize: 1), 0)
    }

    // MARK: - Wilson

    func testWilsonIntervalMatchesKnownValues() {
        let (lower, upper) = CalibrationLedger.wilsonInterval(hits: 11, attempts: 15)
        XCTAssertEqual(lower, 0.480, accuracy: 0.005)
        XCTAssertEqual(upper, 0.891, accuracy: 0.005)
    }

    /// The normal approximation runs off the end of the scale at the extremes,
    /// which is exactly where a badly miscalibrated forecast would sit.
    func testWilsonIntervalStaysInsideZeroToOne() {
        for (hits, attempts) in [(0, 15), (15, 15), (1, 40), (39, 40)] {
            let (lower, upper) = CalibrationLedger.wilsonInterval(hits: hits, attempts: attempts)
            XCTAssertGreaterThanOrEqual(lower, 0)
            XCTAssertLessThanOrEqual(upper, 1)
            XCTAssertLessThanOrEqual(lower, upper)
        }
    }

    // MARK: - No lookahead

    /// The property that makes this a backtest rather than a flattering
    /// restatement of history.
    ///
    /// Every night is identical except the last, which is wildly outside
    /// anything seen before. A forecast built only from the past cannot
    /// contain it, so exactly one attempt must miss. A backtest that let the
    /// scored night into its own window would stretch the interval over it
    /// and score a perfect record -- silently, and in the direction that
    /// makes the app look good.
    func testTheScoredNightIsNotInItsOwnForecast() throws {
        var history = (0..<21).map {
            Fixture.night(daysAgo: 22 - $0, timeAsleepMinutes: 450, timeInBedMinutes: 500)
        }
        history.append(Fixture.night(daysAgo: 1, timeAsleepMinutes: 900, timeInBedMinutes: 950))

        let result = try XCTUnwrap(
            CalibrationLedger.backtest(metric: .duration, nights: history, minimumAttempts: 1)
        )
        XCTAssertEqual(
            result.hits, result.attempts - 1,
            "the outlier night must miss; if it hit, the backtest saw it"
        )
    }

    // MARK: - Verdicts

    func testTooFewScoredNightsSaysSoRatherThanGuessing() throws {
        let result = try XCTUnwrap(
            CalibrationLedger.backtest(metric: .duration, nights: nights(18))
        )
        XCTAssertLessThan(result.attempts, CalibrationLedger.minimumAttempts)
        XCTAssertEqual(result.verdict, .notEnoughYet)
    }

    func testNoHistoryScoresNothing() {
        XCTAssertNil(CalibrationLedger.backtest(metric: .duration, nights: nights(5)))
    }

    /// A steady sleeper's observed coverage should sit near what the
    /// estimator can achieve.
    ///
    /// Asserted as a band rather than as `.matchesExpectation`, deliberately.
    /// The verdict is a hypothesis test at 95%, so a correctly built ledger
    /// still returns a non-matching verdict for a small share of calibrated
    /// samples -- simulation puts it near the 2.5% a one-sided test should
    /// have. Pinning the categorical answer to one seed would be asserting
    /// that this seed is not in that tail, which is luck, not correctness.
    /// What must always hold is that it is nowhere near the false alarm.
    func testASteadySleeperLandsNearTheAchievableCoverage() throws {
        let result = try XCTUnwrap(
            CalibrationLedger.backtest(metric: .duration, nights: nights(300))
        )
        XCTAssertGreaterThan(result.attempts, 250)
        XCTAssertEqual(result.observedCoverage, result.expectedCoverage, accuracy: 0.12)
        XCTAssertNotEqual(result.verdict, .tooConfident)
    }

    /// A sleeper whose nights are marching in one direction really is being
    /// forecast too confidently: an interval built from the past cannot keep
    /// up with a trend, and the ledger should say so.
    func testADriftingSleeperIsReportedAsTooConfident() throws {
        var generator = SeededGenerator(seed: 77)
        let drifting = (0..<120).map { index -> SleepNightFeatures in
            let asleep = 380 + Double(index) * 3 + generator.nextDouble(in: -10...10)
            return Fixture.night(
                daysAgo: 120 - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep / 0.9
            )
        }.sorted { $0.date < $1.date }

        let result = try XCTUnwrap(
            CalibrationLedger.backtest(metric: .duration, nights: drifting)
        )
        XCTAssertLessThan(result.observedCoverage, result.expectedCoverage)
        XCTAssertEqual(result.verdict, .tooConfident)
    }

    func testBacktestAllRanksByHowMuchItCouldScore() {
        let results = CalibrationLedger.backtestAll(nights: nights(120))
        XCTAssertFalse(results.isEmpty)
        let counts = results.map(\.attempts)
        XCTAssertEqual(counts, counts.sorted(by: >))
    }

    // MARK: - Correlated attempts (V10 item 8)

    /// Neighbouring attempts are not independent: a 21-night window advanced
    /// by one night shares twenty of its nights with the previous one, and
    /// sleep is serially correlated in its own right. Wilson assumes they
    /// are, so it reports a precision the data does not contain.
    func testDependenceWidensTheIntervalOnARunnyPattern() {
        // Long runs of hits and misses -- what overlapping windows produce.
        let outcomes = Array(repeating: true, count: 30) + Array(repeating: false, count: 10)
        let hits = outcomes.filter { $0 }.count

        let wilson = CalibrationLedger.wilsonInterval(hits: hits, attempts: outcomes.count)
        let combined = CalibrationLedger.Dependence.combined(
            hits: hits, attempts: outcomes.count, outcomes: outcomes
        )
        XCTAssertGreaterThan(
            combined.upper - combined.lower, wilson.upper - wilson.lower,
            "correlated attempts reported the same certainty as independent ones"
        )
    }

    /// The failure a naive bootstrap has here, and the reason the reported
    /// interval is the wider of the two methods. Thirty hits from thirty
    /// attempts makes every resample all-hits, collapsing the bootstrap to a
    /// single point -- a *stronger* claim than independence, and a false one.
    func testAPerfectRecordDoesNotCollapseToCertainty() {
        let outcomes = Array(repeating: true, count: 30)
        let combined = CalibrationLedger.Dependence.combined(
            hits: 30, attempts: 30, outcomes: outcomes
        )
        XCTAssertLessThan(combined.lower, 1.0, "thirty for thirty was reported as certainty")
        XCTAssertGreaterThan(combined.upper - combined.lower, 0)
    }

    /// Dependence may only ever widen. Whatever the resampling finds, the
    /// reported interval is never narrower than the independence assumption.
    func testTheReportedIntervalIsNeverNarrowerThanWilson() {
        let patterns: [[Bool]] = [
            Array(repeating: true, count: 30),
            (0..<30).map { $0.isMultiple(of: 2) },
            Array(repeating: true, count: 20) + Array(repeating: false, count: 10),
            (0..<40).map { $0 % 7 != 0 }
        ]
        for outcomes in patterns {
            let hits = outcomes.filter { $0 }.count
            let wilson = CalibrationLedger.wilsonInterval(hits: hits, attempts: outcomes.count)
            let combined = CalibrationLedger.Dependence.combined(
                hits: hits, attempts: outcomes.count, outcomes: outcomes
            )
            XCTAssertLessThanOrEqual(combined.lower, wilson.lower + 1e-9)
            XCTAssertGreaterThanOrEqual(combined.upper, wilson.upper - 1e-9)
        }
    }

    /// Same history, same interval. A bootstrap seeded from the clock would
    /// move these numbers on every redraw, which reads as instability in the
    /// estimate rather than in the random number generator.
    func testTheIntervalIsDeterministic() {
        let outcomes = (0..<45).map { $0 % 5 != 0 }
        let first = CalibrationLedger.Dependence.interval(outcomes: outcomes)
        let second = CalibrationLedger.Dependence.interval(outcomes: outcomes)
        XCTAssertEqual(first.lower, second.lower, accuracy: 1e-12)
        XCTAssertEqual(first.upper, second.upper, accuracy: 1e-12)
    }

    /// Order carries the dependence. Two records with the same hit count but
    /// different run structure are not equally certain, and shuffling one
    /// into the other would erase exactly what is being measured.
    func testOrderMatters() {
        let clustered = Array(repeating: true, count: 20) + Array(repeating: false, count: 20)
        let alternating = (0..<40).map { $0.isMultiple(of: 2) }
        XCTAssertEqual(clustered.filter { $0 }.count, alternating.filter { $0 }.count)

        let clusteredWidth = { () -> Double in
            let i = CalibrationLedger.Dependence.interval(outcomes: clustered)
            return i.upper - i.lower
        }()
        let alternatingWidth = { () -> Double in
            let i = CalibrationLedger.Dependence.interval(outcomes: alternating)
            return i.upper - i.lower
        }()
        XCTAssertGreaterThan(clusteredWidth, alternatingWidth,
                             "a run-structured record was treated like an alternating one")
    }

    func testBlockLengthGrowsWithAttemptsAndStaysClamped() {
        XCTAssertEqual(CalibrationLedger.Dependence.blockLength(attempts: 15), 3)
        XCTAssertEqual(CalibrationLedger.Dependence.blockLength(attempts: 61), 4)
        XCTAssertEqual(CalibrationLedger.Dependence.blockLength(attempts: 120), 5)
        // Clamped at both ends: too short carries no dependence, too long
        // leaves too few distinct blocks to resample.
        XCTAssertEqual(CalibrationLedger.Dependence.blockLength(attempts: 1),
                       CalibrationLedger.Dependence.minimumBlockLength)
        XCTAssertEqual(CalibrationLedger.Dependence.blockLength(attempts: 100_000),
                       CalibrationLedger.Dependence.maximumBlockLength)
    }

    /// A single attempt has no run structure to resample, so the bootstrap
    /// has nothing to say and the interval falls back to Wilson alone.
    func testASingleAttemptFallsBackToWilson() {
        let combined = CalibrationLedger.Dependence.combined(hits: 1, attempts: 1, outcomes: [true])
        let wilson = CalibrationLedger.wilsonInterval(hits: 1, attempts: 1)
        XCTAssertEqual(combined.lower, wilson.lower, accuracy: 1e-12)
        XCTAssertEqual(combined.upper, wilson.upper, accuracy: 1e-12)
    }
}
