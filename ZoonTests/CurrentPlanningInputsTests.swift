import XCTest

/// Tonight is planned as of now: last night on the ledger, today's naps and
/// today's strain as the modifiers. Last night's assessment is untouched.
final class CurrentPlanningInputsTests: XCTestCase {

    /// A 480-minute goal, nothing owed before, then a 180-minute night.
    ///
    /// Assessed, last night carried in no debt: its own `SleepNeed` is right
    /// to say so. Planned, tonight owes 300 minutes, and the plan asks for a
    /// bounded slice of it rather than nothing.
    func testAShortLatestNightReachesTonight() throws {
        let throughLatest = try XCTUnwrap(SleepDebtCalculator.debt(
            timeAsleepMinutesNewestFirst: [180], goalMinutes: 480
        ))
        XCTAssertEqual(throughLatest, 300, accuracy: 0.01)

        // What the planners used to be handed: the debt carried *into* the
        // night, which was zero.
        let assessed = SleepNeed.compute(
            goalMinutes: 480, outstandingDebtMinutes: 0, yesterdayStrain: 0,
            napMinutes: 0, achievedMinutes: 180
        )
        let before = assessed.planningInputs(outstandingShortfallMinutes: 0)
        XCTAssertEqual(before.tonightNeedMinutes, 480, accuracy: 0.01, "the defect: tonight saw no shortfall")

        let now = SleepPlanningInputs.asOfNow(
            baselineNeedMinutes: 480,
            shortfallThroughLatestNightMinutes: throughLatest,
            todayStrain: 0,
            napMinutesToday: 0
        )
        XCTAssertEqual(now.currentShortfallMinutes, 300, accuracy: 0.01)
        XCTAssertEqual(now.tonightRepaymentMinutes, SleepAutopilot.maximumDebtRepayment, accuracy: 0.01,
                       "bounded: five hours owed is not five hours asked for")
        XCTAssertEqual(now.tonightNeedMinutes, 480 + SleepAutopilot.maximumDebtRepayment, accuracy: 0.01)

        // And the assessment of last night is unchanged by any of this.
        XCTAssertEqual(assessed.debtMinutes, 0)
    }

    /// A 60-minute nap this afternoon changes tonight, once.
    func testANapTodayChangesTonightOnce() {
        let without = SleepPlanningInputs.asOfNow(
            baselineNeedMinutes: 480, shortfallThroughLatestNightMinutes: 0,
            todayStrain: 0, napMinutesToday: 0
        )
        let with = SleepPlanningInputs.asOfNow(
            baselineNeedMinutes: 480, shortfallThroughLatestNightMinutes: 0,
            todayStrain: 0, napMinutesToday: 60
        )
        XCTAssertEqual(without.tonightNeedMinutes - with.tonightNeedMinutes, 60, accuracy: 0.01)
        // The autopilot's input moves by the same amount: the credit is in
        // the need-before-repayment, not applied a second time on top.
        XCTAssertEqual(
            without.tonightNeedBeforeRepaymentMinutes - with.tonightNeedBeforeRepaymentMinutes,
            60, accuracy: 0.01
        )
    }

    /// Today's exertion, not yesterday's, is tonight's strain term.
    func testTodaysStrainIsTonights() {
        let easy = SleepPlanningInputs.asOfNow(
            baselineNeedMinutes: 480, shortfallThroughLatestNightMinutes: 0,
            todayStrain: 5, napMinutesToday: 0
        )
        let hard = SleepPlanningInputs.asOfNow(
            baselineNeedMinutes: 480, shortfallThroughLatestNightMinutes: 0,
            todayStrain: 21, napMinutesToday: 0
        )
        XCTAssertEqual(easy.tonightStrainAdjustmentMinutes, 0)
        XCTAssertEqual(hard.tonightStrainAdjustmentMinutes, SleepNeed.strainAdjustment(forStrain: 21))
        XCTAssertGreaterThan(hard.tonightNeedMinutes, easy.tonightNeedMinutes)
    }

    /// The assessment and the plan share one strain and one nap rule.
    func testOneRuleForStrainAndNaps() {
        let need = SleepNeed.compute(
            goalMinutes: 480, outstandingDebtMinutes: 0, yesterdayStrain: 15,
            napMinutes: 200, achievedMinutes: 480
        )
        XCTAssertEqual(need.strainMinutes, SleepNeed.strainAdjustment(forStrain: 15))
        XCTAssertEqual(need.napCreditMinutes, SleepNeed.napCredit(forNapMinutes: 200))
    }

    func testNonFiniteInputsDoNotPoisonThePlan() {
        let inputs = SleepPlanningInputs.asOfNow(
            baselineNeedMinutes: 480, shortfallThroughLatestNightMinutes: .nan,
            todayStrain: .infinity, napMinutesToday: .nan
        )
        XCTAssertTrue(inputs.tonightNeedMinutes.isFinite)
        XCTAssertEqual(inputs.tonightNeedMinutes, 480, accuracy: 0.01)
    }
}
