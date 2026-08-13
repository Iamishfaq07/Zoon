import XCTest

final class SleepDebtCalculatorTests: XCTestCase {

    func testNoNightsReturnsNil() {
        XCTAssertNil(SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: [], goalMinutes: 480))
    }

    func testSingleShortNightContributesItsShortfall() {
        guard let debt = SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: [420], goalMinutes: 480) else {
            return XCTFail("expected a debt value")
        }
        XCTAssertEqual(debt, 60, accuracy: 0.01)
    }

    /// Nights at or above goal contribute nothing new, but -- per the
    /// "surplus does not cancel debt" rule -- also don't reduce what's
    /// already there beyond the ordinary night-over-night decay.
    func testSurplusNightDoesNotDirectlyCancelExistingDebt() {
        // One short night, then one long night.
        let withOnlyShort = SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: [420], goalMinutes: 480)!
        let withSurplusAfter = SleepDebtCalculator.debt(
            timeAsleepMinutesNewestFirst: [600, 420], // newest first: long night, then the earlier short one
            goalMinutes: 480
        )!
        // The long night adds zero of its own, so the total is exactly the
        // short night's contribution decayed by one more night -- never less
        // than what straight decay alone would produce, and never negative.
        XCTAssertEqual(withSurplusAfter, withOnlyShort * SleepDebtCalculator.decayPerNight, accuracy: 0.01)
    }

    /// The specific bug this model replaces: a large shortfall many nights
    /// ago must fade out gradually, not vanish in a single step when it
    /// crosses some fixed window edge.
    func testOldShortfallFadesGraduallyRatherThanCliffDropping() {
        // A single very short night 20 nights ago, goal nights every night since.
        var history = [Double](repeating: 480, count: 19) // nights 19...1 nights ago, newest-first order built below
        history.append(180) // the oldest night: a big shortfall, 20 nights ago
        let debt = SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: history, goalMinutes: 480)!

        // It should still be a small but non-zero fraction of the original
        // 300-minute shortfall -- not exactly zero (a hard cutoff) and not
        // still the full 300 (no decay at all).
        XCTAssertGreaterThan(debt, 0)
        XCTAssertLessThan(debt, 300)
    }

    func testConsistentShortfallConvergesRatherThanGrowingForever() {
        let history = [Double](repeating: 420, count: 200) // 60 min short, every night, for a long time
        let debt = SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: history, goalMinutes: 480)!

        // Steady state of a geometric series: shortfall / (1 - decay).
        let expectedSteadyState = 60 / (1 - SleepDebtCalculator.decayPerNight)
        XCTAssertEqual(debt, expectedSteadyState, accuracy: 1)
    }

    func testMissingNightsAreSimplyAbsentNotZeroSleep() {
        // Two consecutive on-goal nights (missing nights are never passed in
        // at all by the caller -- this just confirms on-goal nights add nothing).
        guard let debt = SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: [480, 480], goalMinutes: 480) else {
            return XCTFail("expected a debt value")
        }
        XCTAssertEqual(debt, 0, accuracy: 0.01)
    }

    /// The whole point of `debtSeries`: it and `debt` must be the same
    /// recurrence, not two implementations that happen to agree today. This
    /// is what stops a chart (which needs the series) and a detail screen
    /// (which needs the scalar) from ever showing different numbers for the
    /// same night again -- the bug this type replaced (TrendsView's
    /// independently reimplemented, non-decaying running total) was exactly
    /// that: two call sites, two answers.
    func testSeriesLastElementMatchesScalarDebt() {
        let oldestFirst: [Double] = [480, 420, 390, 500, 460, 300, 480]
        let series = SleepDebtCalculator.debtSeries(timeAsleepMinutesOldestFirst: oldestFirst, goalMinutes: 480)
        let scalar = SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: oldestFirst.reversed(), goalMinutes: 480)

        XCTAssertEqual(series.count, oldestFirst.count)
        XCTAssertEqual(series.last, scalar)
    }

    /// Every prefix of the series must also equal what `debt` would report
    /// for that prefix alone -- the series isn't just right at the end, it's
    /// right at every point a chart might plot.
    func testEachSeriesElementMatchesDebtOfThatPrefix() throws {
        let oldestFirst: [Double] = [420, 480, 350, 480, 480, 300]
        let series = SleepDebtCalculator.debtSeries(timeAsleepMinutesOldestFirst: oldestFirst, goalMinutes: 480)

        for prefixLength in 1...oldestFirst.count {
            let prefix = Array(oldestFirst.prefix(prefixLength))
            let expected = try XCTUnwrap(SleepDebtCalculator.debt(
                timeAsleepMinutesNewestFirst: prefix.reversed(), goalMinutes: 480
            ))
            XCTAssertEqual(series[prefixLength - 1], expected, accuracy: 0.0001)
        }
    }

    func testEmptySeriesForEmptyInput() {
        XCTAssertEqual(
            SleepDebtCalculator.debtSeries(timeAsleepMinutesOldestFirst: [], goalMinutes: 480),
            []
        )
    }

    // MARK: - Per-night goals (ZOON V4 Release 1, finding #17)

    /// A uniform goal array must reproduce the exact scalar-goal series --
    /// the per-night-goal overload is the core recurrence everything else is
    /// defined in terms of, so this is the seam where a regression would show.
    func testUniformPerNightGoalsMatchScalarGoal() {
        let oldestFirst: [Double] = [480, 420, 390, 500, 460, 300, 480]
        let uniform = SleepDebtCalculator.debtSeries(timeAsleepMinutesOldestFirst: oldestFirst, goalMinutes: 480)
        let perNight = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: oldestFirst,
            goalMinutesOldestFirst: Array(repeating: 480, count: oldestFirst.count)
        )
        XCTAssertEqual(uniform, perNight)
    }

    /// The actual point of the per-night overload: a night judged against a
    /// *lower* personal goal than a later night's shows less debt for the
    /// same shortfall, and that earlier judgment never changes even though
    /// later nights use a different goal.
    func testEachNightIsJudgedAgainstItsOwnGoal() {
        // Night 1: slept 400 against a learned goal of 420 (shortfall 20).
        // Night 2: slept 400 against the Settings goal of 480 (shortfall 80).
        let series = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: [400, 400],
            goalMinutesOldestFirst: [420, 480]
        )
        XCTAssertEqual(series[0], 20, accuracy: 0.01)
        XCTAssertEqual(series[1], 20 * SleepDebtCalculator.decayPerNight + 80, accuracy: 0.01)
    }

    func testDebtWithPerNightGoalsMatchesSeriesLastElement() {
        let newestFirst: [Double] = [480, 300, 460, 500, 390, 420, 480]
        let goalsNewestFirst: [Double] = [480, 450, 450, 500, 500, 480, 480]

        let scalar = SleepDebtCalculator.debt(
            timeAsleepMinutesNewestFirst: newestFirst,
            goalMinutesNewestFirst: goalsNewestFirst
        )
        let series = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: Array(newestFirst.reversed()),
            goalMinutesOldestFirst: Array(goalsNewestFirst.reversed())
        )
        XCTAssertEqual(scalar, series.last)
    }

    func testDebtWithMismatchedCountsReturnsNil() {
        XCTAssertNil(SleepDebtCalculator.debt(timeAsleepMinutesNewestFirst: [480, 420], goalMinutesNewestFirst: [480]))
    }
}
