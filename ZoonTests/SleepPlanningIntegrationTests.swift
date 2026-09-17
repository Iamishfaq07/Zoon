import XCTest

/// §6. The planners are tested in isolation elsewhere; this file tests them
/// **with the values the screens actually pass**, which is where the double
/// count lived.
///
/// Each engine was correct on its own. `ZoonTomorrowView` handed every one of
/// them `SleepNeed.totalNeedMinutes` — a figure that already contains 33% of
/// the outstanding debt — *and* the full debt beside it, and each engine then
/// added a repayment of its own. No unit test could see that, because no unit
/// test built its input the way the view did.
final class SleepPlanningIntegrationTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Fourteen ordinary nights, 23:00–07:00, so every planner has a habit.
    private func history() -> [SleepNightFeatures] {
        (1...14).map {
            Fixture.night(daysAgo: $0, timeInBedMinutes: 480, bedtimeHour: 23,
                          timeZoneIdentifier: "UTC")
        }
    }

    /// What the screens build, through the one conversion they all use.
    private func planning(
        baseline: Double = 480,
        outstandingShortfall: Double = 0,
        yesterdayStrain: Double = 0,
        napMinutes: Double = 0
    ) -> SleepPlanningInputs {
        SleepNeed.compute(
            goalMinutes: baseline,
            outstandingDebtMinutes: outstandingShortfall,
            yesterdayStrain: yesterdayStrain,
            napMinutes: napMinutes,
            achievedMinutes: 400
        )
        .planningInputs(outstandingShortfallMinutes: outstandingShortfall)
    }

    // MARK: - The invariant

    /// The one that would have caught the bug.
    ///
    /// Tonight's target must exceed the baseline by exactly one repayment —
    /// not by `SleepNeed`'s 33% share *plus* a planner's 25% share.
    func testDebtIsRepaidExactlyOnce() {
        for shortfall in [0.0, 60, 180, 600] {
            let inputs = planning(outstandingShortfall: shortfall)
            let expected = min(shortfall * SleepAutopilot.debtRepaymentRate,
                               SleepAutopilot.maximumDebtRepayment)
            XCTAssertEqual(
                inputs.tonightNeedMinutes - inputs.baselineNeedMinutes,
                expected,
                accuracy: 0.001,
                "shortfall \(shortfall) was not repaid exactly once"
            )
        }
    }

    /// The composed total is *not* what a planner may be handed, and the two
    /// figures genuinely differ once there is any debt — so a caller that
    /// reaches for the wrong one changes the answer.
    func testTheComposedTotalAndThePlanningTargetAreNotInterchangeable() {
        let need = SleepNeed.compute(
            goalMinutes: 480, outstandingDebtMinutes: 180,
            yesterdayStrain: 0, napMinutes: 0, achievedMinutes: 400
        )
        let inputs = need.planningInputs(outstandingShortfallMinutes: 180)

        // SleepNeed repays 33% (59.4); the planners repay 25% capped at 30.
        XCTAssertEqual(need.totalNeedMinutes, 480 + 59.4, accuracy: 0.1)
        XCTAssertEqual(inputs.tonightNeedMinutes, 510, accuracy: 0.001)
        XCTAssertNotEqual(need.totalNeedMinutes, inputs.tonightNeedMinutes, accuracy: 1)
    }

    func testTheRepaymentIsCappedRatherThanScalingWithADeepDebt() {
        let deep = planning(outstandingShortfall: 900)
        XCTAssertEqual(
            deep.tonightNeedMinutes - deep.baselineNeedMinutes,
            SleepAutopilot.maximumDebtRepayment,
            accuracy: 0.001
        )
    }

    // MARK: - Tonight-only modifiers

    func testStrainAndNapMoveTonightOnly() {
        let inputs = planning(yesterdayStrain: 18, napMinutes: 40)
        XCTAssertGreaterThan(inputs.tonightStrainAdjustmentMinutes, 0)
        XCTAssertEqual(inputs.tonightNapCreditMinutes, 40, accuracy: 0.001)
        // The horizon sees none of it.
        XCTAssertEqual(inputs.futureNightNeedMinutes, inputs.baselineNeedMinutes, accuracy: 0.001)
    }

    func testANapReducesTonightsTargetWithoutTouchingTheBaseline() {
        let rested = planning()
        let napped = planning(napMinutes: 45)
        XCTAssertLessThan(napped.tonightNeedMinutes, rested.tonightNeedMinutes)
        XCTAssertEqual(napped.baselineNeedMinutes, rested.baselineNeedMinutes, accuracy: 0.001)
    }

    /// A nap cannot drive the night's target through the floor.
    func testAVeryLongNapStopsAtTheNightFloor() {
        let inputs = planning(napMinutes: 240)
        XCTAssertGreaterThanOrEqual(inputs.tonightNeedMinutes, 480 * 0.75)
    }

    // MARK: - The horizon

    /// The defect that only appears over several days: today's strain and nap
    /// credit used to be the base for every night of the week.
    func testTheRunwayPlansFutureNightsFromTheBaselineNotFromTonight() throws {
        let strained = try XCTUnwrap(
            SleepRunway.build(
                nights: history(),
                planning: planning(yesterdayStrain: 20, napMinutes: 60),
                calendar: calendar
            )
        )
        let ordinary = try XCTUnwrap(
            SleepRunway.build(nights: history(), planning: planning(), calendar: calendar)
        )
        XCTAssertEqual(strained.days.map(\.needMinutes),
                       ordinary.days.map(\.needMinutes),
                       "today's strain and nap reached future nights")
    }

    /// The ledger has to be payable. Advancing it by the *repaid* target would
    /// mean a window that covers the need still grows the debt.
    func testAGenerousWeekPaysTheShortfallDownRatherThanHoldingItOpen() throws {
        let plan = try XCTUnwrap(
            SleepRunway.build(
                nights: history(),
                planning: planning(outstandingShortfall: 120),
                calendar: calendar
            )
        )
        let projected = plan.days.map(\.projectedShortfallMinutes)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(projected.last), try XCTUnwrap(projected.first),
            "the shortfall never came down across the horizon"
        )
    }

    func testTheFirstRunwayNightAsksForOneRepaymentAboveBaseline() throws {
        let plan = try XCTUnwrap(
            SleepRunway.build(
                nights: history(),
                planning: planning(outstandingShortfall: 120),
                calendar: calendar
            )
        )
        let first = try XCTUnwrap(plan.days.first)
        XCTAssertEqual(
            first.needMinutes - 480,
            min(120 * SleepAutopilot.debtRepaymentRate, SleepAutopilot.maximumDebtRepayment),
            accuracy: 0.001
        )
    }

    // MARK: - What-If

    /// What-If's projection advances the ledger by the base need, so a window
    /// long enough to cover it reduces the shortfall rather than growing it.
    func testWhatIfProjectsAgainstTheBaseNeedNotTheRepaidTarget() {
        let inputs = planning(outstandingShortfall: 120)
        let bedtime = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let model = WhatIfTonight(
            bedtime: bedtime,
            wake: bedtime.addingTimeInterval(9 * 3600),
            needMinutes: inputs.tonightNeedMinutes,
            shortfallMinutes: inputs.currentShortfallMinutes,
            baseNeedMinutes: inputs.tonightNeedBeforeRepaymentMinutes,
            reference: nil
        )
        // Nine hours against an eight-hour base need and two hours of debt:
        // the projection must fall below the 120 it started at.
        XCTAssertLessThan(model.projectedShortfallMinutes, 120)
    }

    // MARK: - Zero is still zero

    /// With no debt, strain or naps, every planning figure collapses to the
    /// baseline — the case that must not have changed.
    func testAnUnremarkableNightIsJustTheBaseline() {
        let inputs = planning()
        XCTAssertEqual(inputs.tonightNeedMinutes, 480, accuracy: 0.001)
        XCTAssertEqual(inputs.tonightNeedBeforeRepaymentMinutes, 480, accuracy: 0.001)
        XCTAssertEqual(inputs.futureNightNeedMinutes, 480, accuracy: 0.001)
        XCTAssertEqual(inputs.tonightRepaymentMinutes, 0, accuracy: 0.001)
    }

    func testNegativeInputsAreClampedRatherThanSubtracting() {
        let inputs = SleepPlanningInputs(
            baselineNeedMinutes: 480,
            currentShortfallMinutes: -60,
            tonightStrainAdjustmentMinutes: -10,
            tonightNapCreditMinutes: -30
        )
        XCTAssertEqual(inputs.currentShortfallMinutes, 0)
        XCTAssertEqual(inputs.tonightNeedMinutes, 480, accuracy: 0.001)
    }
}
