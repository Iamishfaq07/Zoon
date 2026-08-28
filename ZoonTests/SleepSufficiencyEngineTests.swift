import XCTest

/// Pins the two rules `SleepSufficiencyEngine` exists to enforce: sufficiency
/// is measured against *total 24-hour* sleep, and the comparison basis is
/// never implicit.
final class SleepSufficiencyEngineTests: XCTestCase {

    private func night(
        mainMinutes: Double,
        napMinutes: Double = 0,
        need: Double? = nil
    ) -> SleepNightFeatures {
        var night = Fixture.night(timeAsleepMinutes: mainMinutes)
        night.secondaryAsleepMinutes = napMinutes
        night.sleepNeedBaselineMinutes = need
        return night
    }

    // MARK: - Total 24h, not main sleep

    /// The mistake the type exists to prevent. A 45-minute nap is real sleep;
    /// excluding it reports a shortfall the person does not have.
    func testANapCountsTowardSufficiency() {
        let withoutNap = SleepSufficiencyEngine.evaluate(
            night: night(mainMinutes: 400, need: 480), goalMinutes: 480
        )
        let withNap = SleepSufficiencyEngine.evaluate(
            night: night(mainMinutes: 400, napMinutes: 45, need: 480), goalMinutes: 480
        )

        XCTAssertGreaterThan(withNap.percent, withoutNap.percent)
        XCTAssertEqual(withNap.sleptMinutes, 445)
    }

    /// A short main sleep fully compensated by naps is sufficient, and must
    /// not read as a deficit.
    func testMainSleepShortfallFullyCompensatedByNapsIsMet() {
        let result = SleepSufficiencyEngine.evaluate(
            night: night(mainMinutes: 300, napMinutes: 200, need: 480), goalMinutes: 480
        )

        XCTAssertTrue(result.isMet)
        XCTAssertEqual(result.shortfallMinutes, 0)
    }

    // MARK: - Capping and shortfall

    /// Sleeping well past the target is not a deficiency in the other
    /// direction; the measure simply has nothing more to say.
    func testSufficiencyIsCappedAtOneHundred() {
        let result = SleepSufficiencyEngine.evaluate(
            total24hAsleepMinutes: 900, target: 480, basis: .personalNeed
        )

        XCTAssertEqual(result.percent, 100)
        XCTAssertEqual(result.shortfallMinutes, 0)
    }

    func testShortfallReportsTheMissingMinutes() {
        let result = SleepSufficiencyEngine.evaluate(
            total24hAsleepMinutes: 400, target: 480, basis: .personalNeed
        )

        XCTAssertEqual(result.shortfallMinutes, 80)
        XCTAssertFalse(result.isMet)
    }

    /// A zero or nonsense target must not divide by zero and produce a
    /// non-finite percentage that then poisons every average downstream.
    func testAZeroTargetDoesNotProduceANonFiniteResult() {
        let result = SleepSufficiencyEngine.evaluate(
            total24hAsleepMinutes: 400, target: 0, basis: .userGoal
        )

        XCTAssertTrue(result.percent.isFinite)
        XCTAssertEqual(result.percent, 100)
    }

    // MARK: - Basis is explicit

    /// A night with a learned baseline is answering the physiological
    /// question, and must say so.
    func testANightWithALearnedNeedReportsPersonalNeedBasis() {
        let result = SleepSufficiencyEngine.evaluate(
            night: night(mainMinutes: 450, need: 470), goalMinutes: 480
        )

        XCTAssertEqual(result.basis, .personalNeed)
        XCTAssertEqual(result.targetMinutes, 470)
    }

    /// A night predating learned need falls back to the goal — and reports
    /// that it did, rather than passing a goal comparison off as a need one.
    func testANightWithoutALearnedNeedFallsBackToTheGoalAndSaysSo() {
        let result = SleepSufficiencyEngine.evaluate(
            night: night(mainMinutes: 450, need: nil), goalMinutes: 480
        )

        XCTAssertEqual(result.basis, .userGoal)
        XCTAssertEqual(result.targetMinutes, 480)
    }

    /// The copy distinction that keeps Zoon from overstating what it knows.
    func testBasisLabelsDistinguishAChoiceFromAnEstimate() {
        XCTAssertEqual(SleepSufficiencyEngine.Basis.userGoal.label, "goal")
        XCTAssertEqual(SleepSufficiencyEngine.Basis.personalNeed.label, "estimated need")
    }

    // MARK: - Windows

    /// Each night is scored against its *own* recorded need. Applying today's
    /// target retroactively rescores history under a baseline that was never
    /// in effect — the bug canonical Sleep Debt already avoids.
    func testEachNightIsScoredAgainstItsOwnRecordedNeed() throws {
        let nights = [
            night(mainMinutes: 480, need: 480),  // 100%
            night(mainMinutes: 240, need: 480)   // 50%
        ]

        let average = SleepSufficiencyEngine.averagePercent(nights: nights, goalMinutes: 600)

        XCTAssertEqual(try XCTUnwrap(average), 75, accuracy: 0.001,
                       "Should use each night's own 480 need, not the 600 goal.")
    }

    /// An empty window has no answer. Returning zero would render as "you got
    /// no sleep" rather than "there is nothing here yet".
    func testAnEmptyWindowHasNoAnswerRatherThanZero() {
        XCTAssertNil(SleepSufficiencyEngine.averagePercent(nights: [], goalMinutes: 480))
    }

    // MARK: - Goal streaks

    /// A streak is about a commitment being kept, so it is measured against
    /// the goal even when a learned need exists — but still over total 24h
    /// sleep, so a nap still counts toward it.
    func testGoalStreakUsesTheGoalNotTheLearnedNeed() {
        let generousNeed = night(mainMinutes: 400, need: 300)

        XCTAssertFalse(
            SleepSufficiencyEngine.meetsGoal(night: generousNeed, goalMinutes: 480),
            "400 minutes does not meet a 480 goal, whatever the learned need says."
        )
    }

    func testGoalStreakCountsNaps() {
        let compensated = night(mainMinutes: 400, napMinutes: 90, need: 480)

        XCTAssertTrue(SleepSufficiencyEngine.meetsGoal(night: compensated, goalMinutes: 480))
    }
}
