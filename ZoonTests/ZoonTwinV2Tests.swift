import XCTest

final class ZoonTwinV2Tests: XCTestCase {

    /// Nights whose duration varies while time in bed does not.
    ///
    /// Deliberate: `Fixture.night` derives bedtime from time in bed, so a
    /// fixture that varies time in bed varies bedtime with it -- and bedtime
    /// is one of the covariates the matcher balances on. Holding the bed
    /// window fixed and moving only the sleep inside it isolates the lever,
    /// which is what these tests are about.
    private func nights(
        _ count: Int = 80,
        coupling: Double = 0,
        seed: UInt64 = 77
    ) -> [SleepNightFeatures] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let asleep = 430 + generator.nextDouble(in: -70...70)
            let hrv = 55 + (asleep - 430) * coupling + generator.nextDouble(in: -4...4)
            return Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: asleep,
                timeInBedMinutes: 480,
                avgHRV: hrv
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Estimating

    /// A real dependence in the fixture must survive matching and come out
    /// with an interval that excludes no change.
    func testARealDependenceComesOutDecisiveAndInTheRightDirection() throws {
        let result = ZoonTwinV2.estimate(nights: nights(coupling: 0.09), lever: .duration, direction: .more)
        let estimate = try XCTUnwrap(result.estimate, "fixture must produce an estimate, not \(result)")

        XCTAssertTrue(estimate.isDecisive, "interval \(estimate.lower)...\(estimate.upper) should exclude zero")
        XCTAssertEqual(estimate.isImprovement, true, "more HRV is the better direction")
        XCTAssertGreaterThan(estimate.difference, 0)
        XCTAssertGreaterThanOrEqual(estimate.pairs, ZoonTwinV2.minimumPairs)
    }

    /// The whole reason for the interval. With no dependence in the fixture,
    /// the estimate must report that it cannot tell -- and `isImprovement`
    /// must be nil rather than false, so no caller can print "worse" for
    /// "cannot tell".
    ///
    /// The outcome is held flat rather than made noisy on purpose. A noisy
    /// null fixture is decisive about one time in twenty by construction,
    /// and pinning that coin flip to a seed makes a test that passes today
    /// and fails the first time anything upstream changes the draw order.
    /// Flat is the same property without the roulette: every paired
    /// difference is zero, so the interval is exactly [0, 0].
    func testNoDependenceProducesAnIntervalThatSpansNoChange() throws {
        var generator = SeededGenerator(seed: 91)
        let flatOutcome = (0..<80).map { index in
            Fixture.night(
                daysAgo: 80 - index,
                timeAsleepMinutes: 430 + generator.nextDouble(in: -70...70),
                timeInBedMinutes: 480,
                avgHRV: 55
            )
        }.sorted { $0.date < $1.date }

        let result = ZoonTwinV2.estimate(nights: flatOutcome, lever: .duration, direction: .more)
        let estimate = try XCTUnwrap(result.estimate, "fixture must reach the estimate branch, got \(result)")

        XCTAssertFalse(estimate.isDecisive)
        XCTAssertNil(estimate.isImprovement)
        XCTAssertLessThanOrEqual(estimate.lower, 0)
        XCTAssertGreaterThanOrEqual(estimate.upper, 0)
        XCTAssertTrue(estimate.sentence.contains("cannot say which way"))
    }

    /// Matching without replacement can only make as many pairs as it has
    /// controls to spare, and what it could not pair is part of the answer.
    func testTheEstimateSaysHowManyNightsItCouldNotPair() throws {
        let estimate = try XCTUnwrap(
            ZoonTwinV2.estimate(nights: nights(), lever: .duration, direction: .more).estimate
        )
        XCTAssertEqual(estimate.nightsDropped, estimate.candidateNights - estimate.pairs)
        XCTAssertLessThanOrEqual(estimate.pairs, estimate.candidateNights)
    }

    /// Every covariate must actually be checked, and the reported balance
    /// must be the balance that let the estimate through.
    func testAnEstimateReportsBalanceOnEveryCovariateItMatchedOn() throws {
        let estimate = try XCTUnwrap(
            ZoonTwinV2.estimate(nights: nights(), lever: .duration, direction: .more).estimate
        )
        XCTAssertEqual(
            Set(estimate.balance.map(\.metric)),
            Set(ZoonTwinV2.covariates(lever: .duration))
        )
        XCTAssertTrue(estimate.balance.allSatisfy(\.isBalanced),
                      "an estimate is only returned when every covariate balanced")
    }

    // MARK: - Refusing

    /// The spec is explicit that this is a feature. Nights with no close
    /// comparison are not compared to distant ones.
    func testNightsWithNoCloseComparisonAreRefusedRatherThanPaired() {
        // Long nights only in the distant past, short nights only recently:
        // every possible pair sits months apart, well beyond the caliper.
        var generator = SeededGenerator(seed: 5)
        let old = (0..<15).map { index in
            Fixture.night(
                daysAgo: 200 - index, timeAsleepMinutes: 500 + generator.nextDouble(in: -5...5),
                timeInBedMinutes: 480, avgHRV: 55
            )
        }
        let recent = (0..<15).map { index in
            Fixture.night(
                daysAgo: 15 - index, timeAsleepMinutes: 360 + generator.nextDouble(in: -5...5),
                timeInBedMinutes: 480, avgHRV: 55
            )
        }

        let result = ZoonTwinV2.estimate(nights: old + recent, lever: .duration, direction: .more)
        guard case let .unsupported(reason) = result else {
            return XCTFail("months-apart nights must not be paired; got \(result)")
        }
        guard case let .notEnoughComparableNights(matched, need) = reason else {
            return XCTFail("expected the caliper to refuse, got \(reason)")
        }
        XCTAssertLessThan(matched, need)
        XCTAssertTrue(reason.improvesWithMoreNights)
    }

    /// A lever compared against itself reports only that these nights are
    /// these nights.
    func testALeverComparedAgainstItselfIsRefused() {
        let result = ZoonTwinV2.estimate(nights: nights(), lever: .hrv, direction: .more, outcome: .hrv)
        XCTAssertEqual(result.refusal, .sameMetric)
        XCTAssertFalse(ZoonTwinV2.Unsupported.sameMetric.improvesWithMoreNights,
                       "no number of nights fixes this one")
    }

    func testTooFewNightsIsRefusedBeforeAnythingElseIsAttempted() {
        let result = ZoonTwinV2.estimate(nights: nights(8), lever: .duration, direction: .more)
        guard case let .unsupported(.notEnoughNights(have, need)) = result else {
            return XCTFail("expected a night-count refusal, got \(result)")
        }
        XCTAssertLessThan(have, need)
    }

    /// Nights that never varied on the lever cannot be split, and saying so
    /// is different from saying the split found nothing.
    func testAHistoryWithNoSpreadOnTheLeverIsRefusedForThatReason() {
        let flat = (0..<40).map { index in
            Fixture.night(daysAgo: 40 - index, timeAsleepMinutes: 430, timeInBedMinutes: 480, avgHRV: 55)
        }
        XCTAssertEqual(
            ZoonTwinV2.estimate(nights: flat, lever: .duration, direction: .more).refusal,
            .noContrast
        )
    }

    /// Every refusal has to read as a statement about the evidence. An empty
    /// or error-shaped message would turn "not yet" into "something broke".
    func testEveryRefusalReasonHasSomethingToSay() {
        let reasons: [ZoonTwinV2.Unsupported] = [
            .sameMetric,
            .notEnoughNights(have: 4, need: 20),
            .noContrast,
            .notEnoughComparableNights(matched: 3, need: 10),
            .unbalanced(.sleepDebt),
            .differentEras(daysApart: 90)
        ]
        for reason in reasons {
            XCTAssertFalse(reason.message.isEmpty, "\(reason) has no message")
            XCTAssertFalse(reason.message.lowercased().contains("error"), "\(reason) reads as a failure")
        }
    }

    // MARK: - Preselection

    /// The defect V2 exists to fix. The outcome is fixed in the source, once,
    /// and is not one of the things a person can pull.
    func testTheOutcomeIsPreselectedAndIsNotItselfALever() {
        XCTAssertFalse(ZoonTwin.levers.contains(ZoonTwinV2.preselectedOutcome))
        let defaulted = ZoonTwinV2.estimate(nights: nights(), lever: .duration, direction: .more)
        XCTAssertEqual(defaulted.estimate?.outcome, ZoonTwinV2.preselectedOutcome)
    }

    // MARK: - Determinism

    /// A finding that reshuffles between one visit to the screen and the next
    /// is not one anybody can act on. Greedy matching in a fixed order and a
    /// seeded bootstrap must give the same answer twice.
    func testTheSameNightsGiveTheSameEstimateTwice() throws {
        let window = nights(coupling: 0.07)
        let first = try XCTUnwrap(ZoonTwinV2.estimate(nights: window, lever: .duration, direction: .more).estimate)
        let second = try XCTUnwrap(ZoonTwinV2.estimate(nights: window, lever: .duration, direction: .more).estimate)
        XCTAssertEqual(first, second)
    }

    /// Balance on a covariate that never moved is perfect, not a division by
    /// zero.
    func testAConstantCovariateIsPerfectlyBalancedRatherThanUndefined() {
        let value = ZoonTwinV2.standardisedDifference([5, 5, 5], [5, 5, 5])
        XCTAssertEqual(value, 0, accuracy: 1e-12)
        XCTAssertTrue(value.isFinite)
    }
}
