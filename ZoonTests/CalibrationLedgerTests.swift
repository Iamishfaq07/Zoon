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
}
