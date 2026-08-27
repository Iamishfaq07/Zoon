import XCTest

final class SleepAutopilotTests: XCTestCase {

    /// Nights with a chosen bedtime and duration. `Fixture.night` derives
    /// bedtime from a 07:00 wake minus time in bed, so time in bed is the
    /// lever for bedtime here and `timeAsleepMinutes` is set independently.
    private func nights(
        count: Int = 14,
        bedtimeMinutes: Double = 0,
        sleepMinutes: Double = 420
    ) -> [SleepNightFeatures] {
        // 07:00 is 420 minutes past midnight; bedtime 0 means midnight, so
        // time in bed is the gap between them.
        let timeInBed = 420 - bedtimeMinutes
        return (0..<count).map { index in
            Fixture.night(
                daysAgo: count - index,
                timeAsleepMinutes: sleepMinutes,
                timeInBedMinutes: timeInBed
            )
        }
    }

    private func plan(
        bedtimeMinutes: Double = 0,
        sleepMinutes: Double = 420,
        count: Int = 14,
        needMinutes: Double = 480,
        obligationWakeMinutes: Double? = 420,
        debtMinutes: Double = 0
    ) throws -> SleepAutopilot.Plan {
        try XCTUnwrap(SleepAutopilot.plan(
            nights: nights(count: count, bedtimeMinutes: bedtimeMinutes, sleepMinutes: sleepMinutes),
            sleepNeedMinutes: needMinutes,
            obligationWakeMinutes: obligationWakeMinutes,
            sleepDebtMinutes: debtMinutes
        ))
    }

    // MARK: - The rate limit

    /// The property that makes this a controller rather than a calculator.
    /// Someone at midnight who needs to be asleep by 23:00 is an hour out;
    /// asking for the whole hour tonight teaches them the number is
    /// decorative.
    func testALargeCorrectionIsCappedAtOneNightsWorth() throws {
        // Habit midnight, need 480 against a 07:00 alarm -> ideal 23:00,
        // a full hour earlier.
        let plan = try plan(bedtimeMinutes: 0, needMinutes: 480)

        XCTAssertEqual(plan.shiftMinutes, -SleepAutopilot.maximumNightlyShift)
        XCTAssertEqual(plan.targetBedtimeMinutes, -SleepAutopilot.maximumNightlyShift)
        XCTAssertFalse(plan.isHolding)
    }

    func testTheCapAppliesInBothDirections() throws {
        // Habit far earlier than needed -> the correction is later, and
        // capped by the same amount.
        let plan = try plan(bedtimeMinutes: -180, needMinutes: 480)
        XCTAssertEqual(plan.shiftMinutes, SleepAutopilot.maximumNightlyShift)
    }

    /// A correction smaller than the cap is passed through unchanged --
    /// the limit is a ceiling, not a step size.
    func testASmallCorrectionIsNotInflatedToTheCap() throws {
        // Ideal is -60; habit at -48 leaves a 12-minute gap.
        let plan = try plan(bedtimeMinutes: -48, needMinutes: 480)
        XCTAssertEqual(plan.shiftMinutes, -12, accuracy: 0.001)
    }

    /// Applied night after night, the bounded steps have to actually get
    /// there -- a rate limit that never converges is just a cap on being
    /// wrong.
    func testRepeatedNightsConvergeOnTheTarget() throws {
        var history = nights(count: 14, bedtimeMinutes: 0, sleepMinutes: 420)
        var lastTarget: Double = 0

        for night in 1...20 {
            let plan = try XCTUnwrap(SleepAutopilot.plan(
                nights: history, sleepNeedMinutes: 480, obligationWakeMinutes: 420
            ))
            lastTarget = plan.targetBedtimeMinutes
            // The person goes to bed where they were asked to. All these
            // nights share a date, which is harmless: the window holds
            // exactly fourteen and the habit is their median, so the order
            // among equal dates cannot change the result.
            history.append(Fixture.night(
                daysAgo: 0,
                timeAsleepMinutes: 420,
                timeInBedMinutes: 420 - plan.targetBedtimeMinutes
            ))
            history = Array(history.suffix(14))
            XCTAssertGreaterThanOrEqual(plan.targetBedtimeMinutes, -60.001,
                                        "must never overshoot the ideal on night \(night)")
        }

        XCTAssertEqual(lastTarget, -60, accuracy: 1,
                       "twenty bounded nights should arrive at the hour-earlier target")
    }

    // MARK: - The deadband

    /// Without this, ordinary night-to-night variation produces a new
    /// "target" every evening -- noise wearing a recommendation's clothes,
    /// and the one thing that stops a habit forming.
    func testASmallGapHoldsInsteadOfNudging() throws {
        // Ideal -60, habit -52: an eight-minute gap, inside the deadband.
        let plan = try plan(bedtimeMinutes: -52, needMinutes: 480)

        XCTAssertTrue(plan.isHolding)
        XCTAssertEqual(plan.shiftMinutes, 0)
        XCTAssertEqual(plan.targetBedtimeMinutes, -52, accuracy: 0.001,
                       "the target is exactly where they already are")
    }

    func testHoldingSaysSoPlainlyRatherThanInventingAChange() throws {
        let sentence = try plan(bedtimeMinutes: -52, needMinutes: 480).sentence
        XCTAssertTrue(sentence.contains("No change worth making"), sentence)
    }

    func testAGapJustOutsideTheDeadbandMoves() throws {
        let plan = try plan(bedtimeMinutes: -48, needMinutes: 480)
        XCTAssertFalse(plan.isHolding)
        XCTAssertNotEqual(plan.shiftMinutes, 0)
    }

    // MARK: - Sleep debt

    /// Nobody sleeps off four hours of debt in one night, and telling them
    /// to go to bed four hours early costs the plan its credibility on
    /// every other night too.
    func testDebtRepaymentIsCappedInAbsoluteMinutes() throws {
        let plan = try plan(debtMinutes: 600)
        XCTAssertEqual(plan.debtRepaymentMinutes, SleepAutopilot.maximumDebtRepayment)
    }

    /// A small debt gets a proportionate slice, not the cap.
    func testASmallDebtIsRepaidAsAShare() throws {
        let plan = try plan(debtMinutes: 40)
        XCTAssertEqual(plan.debtRepaymentMinutes, 10, accuracy: 0.001)
    }

    func testNoDebtAddsNothing() throws {
        XCTAssertEqual(try plan(debtMinutes: 0).debtRepaymentMinutes, 0)
        XCTAssertEqual(try plan(debtMinutes: -120).debtRepaymentMinutes, 0,
                       "being ahead is not a reason to sleep less")
    }

    func testRepaymentIsAddedToTheNightsTargetSleep() throws {
        let withDebt = try plan(debtMinutes: 40)
        let without = try plan(debtMinutes: 0)
        XCTAssertEqual(withDebt.targetSleepMinutes - without.targetSleepMinutes, 10, accuracy: 0.001)
    }

    // MARK: - Which half gives

    /// The alarm is the half of the night nobody can negotiate with, so the
    /// bedtime is what moves.
    func testWithAFixedWakeTimeTheBedtimeMoves() throws {
        let plan = try plan(bedtimeMinutes: 0, needMinutes: 480, obligationWakeMinutes: 420)
        XCTAssertLessThan(plan.shiftMinutes, 0, "an earlier bedtime, not a later alarm")
        XCTAssertEqual(plan.targetWakeMinutes,
                       plan.targetBedtimeMinutes + plan.targetSleepMinutes, accuracy: 0.001)
    }

    /// Without an alarm the correction comes from the duration shortfall
    /// instead. This path used to be inert: with no obligation the ideal
    /// bedtime was simply the habitual one, so the plan always held no
    /// matter how far under their need the person was sleeping.
    func testWithNoFixedWakeTimeAShortfallStillMovesTheBedtime() throws {
        // Sleeping 435 against a need of 480: 45 minutes short.
        let plan = try plan(
            bedtimeMinutes: -60, sleepMinutes: 435,
            needMinutes: 480, obligationWakeMinutes: nil
        )

        XCTAssertFalse(plan.isHolding, "a 45-minute shortfall is not nothing")
        XCTAssertEqual(plan.shiftMinutes, -SleepAutopilot.maximumNightlyShift)
    }

    func testWithNoFixedWakeTimeAndNoShortfallItHolds() throws {
        let plan = try plan(
            bedtimeMinutes: -90, sleepMinutes: 480,
            needMinutes: 480, obligationWakeMinutes: nil
        )
        XCTAssertTrue(plan.isHolding)
    }

    // MARK: - Refusals

    func testTooFewNightsReturnsNil() {
        XCTAssertNil(SleepAutopilot.plan(
            nights: nights(count: 4), sleepNeedMinutes: 480, obligationWakeMinutes: 420
        ))
    }

    func testNoNightsReturnsNil() {
        XCTAssertNil(SleepAutopilot.plan(nights: [], sleepNeedMinutes: 480))
    }

    /// A need of zero is not a schedule, it is a missing input.
    func testAnAbsentSleepNeedReturnsNil() {
        XCTAssertNil(SleepAutopilot.plan(nights: nights(), sleepNeedMinutes: 0))
        XCTAssertNil(SleepAutopilot.plan(nights: nights(), sleepNeedMinutes: -10))
    }

    // MARK: - Confidence

    func testConfidenceRisesWithHistory() throws {
        let thin = try plan(count: 8)
        let full = try plan(count: 14)
        XCTAssertLessThan(thin.confidence, full.confidence)
        XCTAssertEqual(full.confidence, .high)
    }

    // MARK: - Clock formatting

    /// Shared by the card, the watch and the widget, so the fold is worth
    /// pinning: values are negative before midnight, and a target sleep
    /// length can push a wake time past 1440.
    func testClockLabelFoldsBothEndsOntoARealClockFace() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // 23:40 arrives as -20, not as a negative clock time.
        XCTAssertEqual(SleepAutopilot.clockLabel(-20, calendar: calendar),
                       SleepAutopilot.clockLabel(1420, calendar: calendar))
        // A 1:00 wake arrives as 1500 once a sleep length is added past
        // midnight, and must not render as hour 25.
        XCTAssertEqual(SleepAutopilot.clockLabel(1500, calendar: calendar),
                       SleepAutopilot.clockLabel(60, calendar: calendar))
        // Midnight itself round-trips rather than folding to 1440.
        XCTAssertEqual(SleepAutopilot.clockLabel(0, calendar: calendar),
                       SleepAutopilot.clockLabel(1440, calendar: calendar))
    }

    func testClockLabelNeverRendersANegativeOrOutOfRangeHour() {
        for minutes in stride(from: -720.0, through: 2160.0, by: 37) {
            let label = SleepAutopilot.clockLabel(minutes)
            XCTAssertFalse(label.contains("-"), "\(minutes) -> \(label)")
            XCTAssertFalse(label.hasPrefix("25"), "\(minutes) -> \(label)")
            XCTAssertFalse(label.isEmpty, "\(minutes)")
        }
    }

    // MARK: - Copy

    func testTheSentenceNamesTheDirectionAndAmount() throws {
        let sentence = try plan(bedtimeMinutes: 0, needMinutes: 480).sentence
        XCTAssertTrue(sentence.contains("earlier"), sentence)
        XCTAssertFalse(sentence.contains("later"), sentence)
    }

    func testTheSentenceMentionsRepaymentOnlyWhenThereIsSome() throws {
        let withDebt = try plan(bedtimeMinutes: 0, debtMinutes: 120).sentence
        let without = try plan(bedtimeMinutes: 0, debtMinutes: 0).sentence

        XCTAssertTrue(withDebt.contains("what you're owed"), withDebt)
        XCTAssertFalse(without.contains("owed"), without)
    }

    /// Arranging someone's own numbers into a schedule is not evidence that
    /// following it helps them, and the copy must not imply otherwise.
    func testTheCaveatPromisesNothingAboutHowTheyWillFeel() throws {
        let caveat = try plan().caveat.lowercased()

        XCTAssertTrue(caveat.contains("plan, not a promise"), caveat)
        XCTAssertFalse(caveat.contains("will improve"), caveat)
        XCTAssertFalse(caveat.contains("better sleep"), caveat)
    }
}
