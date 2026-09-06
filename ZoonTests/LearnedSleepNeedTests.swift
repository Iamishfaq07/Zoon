import XCTest

final class LearnedSleepNeedTests: XCTestCase {

    private func qualifyingNights(_ count: Int, minutes: Double = 450) -> [SleepNightFeatures] {
        Fixture.consecutiveNights(count) { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: minutes, timeInBedMinutes: minutes + 30)
        }
    }

    func testBelowMinimumQualifyingNightsUsesGoalAlone() {
        let history = qualifyingNights(20)
        let result = LearnedSleepNeed.compute(goalMinutes: 480, history: history)

        XCTAssertEqual(result.minutes, 480)
        XCTAssertNil(result.learnedMinutes)
        XCTAssertEqual(result.confidence, .insufficient)
    }

    /// At exactly the minimum, a learned figure exists but the blend weight
    /// is still 0 -- the ramp hasn't started yet, so the baseline used is
    /// still the goal, even though a learned estimate is now available to
    /// display.
    func testAtMinimumNightsLearnedExistsButBlendIsStillZero() {
        let history = qualifyingNights(LearnedSleepNeed.minimumQualifyingNights, minutes: 450)
        let result = LearnedSleepNeed.compute(goalMinutes: 480, history: history)

        XCTAssertNotNil(result.learnedMinutes)
        XCTAssertEqual(result.minutes, 480, accuracy: 0.01)
    }

    func testHalfwayToFullConfidenceBlendsEvenly() {
        let halfway = (LearnedSleepNeed.minimumQualifyingNights + LearnedSleepNeed.fullConfidenceNights) / 2
        let history = qualifyingNights(halfway, minutes: 450)
        let result = LearnedSleepNeed.compute(goalMinutes: 480, history: history)

        // Goal 480, learned 450, half-blended -> 465.
        XCTAssertEqual(result.minutes, 465, accuracy: 1)
        XCTAssertEqual(result.confidence, .moderate)
    }

    func testAtFullConfidenceNightsBlendIsFullyLearned() {
        let history = qualifyingNights(LearnedSleepNeed.fullConfidenceNights, minutes: 450)
        let result = LearnedSleepNeed.compute(goalMinutes: 480, history: history)

        XCTAssertEqual(result.minutes, 450, accuracy: 0.5)
        XCTAssertEqual(result.confidence, .high)
    }

    /// The exact failure mode the spec warns about: a chronic under-sleeper's
    /// short, fragmented nights must not count toward "their learned need."
    func testLowQualityNightsDoNotCountAsQualifying() {
        let fragmented = Fixture.consecutiveNights(40) { daysAgo in
            Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: 300, timeInBedMinutes: 450) // ~67% efficiency
        }
        let result = LearnedSleepNeed.compute(goalMinutes: 480, history: fragmented)

        XCTAssertEqual(result.qualifyingNightCount, 0)
        XCTAssertEqual(result.confidence, .insufficient)
    }

    /// Builds a night with no stage breakdown at all -- everything asleep is
    /// `unspecifiedAsleepMinutes`, the shape an iPhone-only or third-party
    /// source produces. `Fixture.night` always stages its minutes, so this
    /// constructs one directly.
    private func unstagedNight(daysAgo: Int, timeAsleepMinutes: Double) -> SleepNightFeatures {
        let staged = Fixture.night(daysAgo: daysAgo, timeAsleepMinutes: timeAsleepMinutes)
        return SleepNightFeatures(
            date: staged.date,
            bedtime: staged.bedtime,
            wakeTime: staged.wakeTime,
            timeInBedMinutes: staged.timeInBedMinutes,
            timeAsleepMinutes: staged.timeAsleepMinutes,
            sleepEfficiencyPercent: staged.sleepEfficiencyPercent,
            coreMinutes: 0,
            deepMinutes: 0,
            remMinutes: 0,
            unspecifiedAsleepMinutes: timeAsleepMinutes,
            awakeMinutes: staged.awakeMinutes,
            wakeCount: staged.wakeCount,
            sleepLatencyMinutes: nil,
            avgHeartRate: nil,
            minHeartRate: nil,
            avgHRV: nil,
            avgRespiratoryRate: nil,
            avgSpO2: nil,
            wristTempDeltaC: nil,
            hrv7DayAvg: nil,
            sleepDebtMinutes: nil,
            lastWorkoutHoursBeforeBed: nil,
            exerciseMinutesPreviousDay: nil,
            sourceName: "iPhone"
        )
    }

    /// The bug finding #22 (ZOON V4 Release 1) describes: an iPhone-only or
    /// third-party-tracker user, whose source never writes a core/deep/REM
    /// split, used to be permanently excluded from ever earning a learned
    /// baseline -- no matter how many efficient, well-measured nights they
    /// had -- because `isHighQuality` required `hasStageBreakdown`. Staging
    /// granularity has nothing to do with whether total duration is
    /// trustworthy, so it's no longer part of the quality gate.
    func testUnstagedButOtherwiseHighQualityNightsCanQualify() {
        let history = (0..<LearnedSleepNeed.minimumQualifyingNights).map {
            unstagedNight(daysAgo: $0, timeAsleepMinutes: 450)
        }
        let result = LearnedSleepNeed.compute(goalMinutes: 480, history: history)

        XCTAssertEqual(result.qualifyingNightCount, LearnedSleepNeed.minimumQualifyingNights)
        XCTAssertNotNil(result.learnedMinutes)
    }
}

// MARK: - The efficient-short-night trap

/// V9 item 37. "A chronic short sleeper may repeatedly have 6h15, high
/// efficiency, without that necessarily being sufficient."
///
/// The trap is that the quality filter selects *for* efficiency, and high
/// efficiency on a short night is at least as consistent with sleep pressure
/// as with sufficiency -- so the more disciplined the short sleeper, the
/// more confidently the old model learned the wrong number.
extension LearnedSleepNeedTests {

    private func restrictedNight(daysAgo: Int) -> SleepNightFeatures {
        // 6h15 asleep, 96% efficiency, measured time in bed.
        Fixture.night(
            daysAgo: daysAgo,
            timeAsleepMinutes: 375,
            timeInBedMinutes: 375 / 0.96
        )
    }

    func testAShortNightAtVeryHighEfficiencyIsNotEvidenceOfNeed() {
        let night = restrictedNight(daysAgo: 1)
        XCTAssertTrue(
            LearnedSleepNeed.isRestrictionShaped(night, goalMinutes: 480),
            "6h15 at 96% under an 8h goal is the spec's own example"
        )
    }

    /// The same night measured by a watch that never writes `inBed`. Its
    /// efficiency reads high because the span omits time lying awake, so
    /// applying the ceiling here would disqualify the users whose data is
    /// already thinnest -- the same bug this file records for
    /// `hasStageBreakdown`.
    func testAnEstimatedInBedNightIsNotJudgedByTheEfficiencyCeiling() {
        var night = restrictedNight(daysAgo: 1)
        night.timeInBedIsEstimated = true
        XCTAssertFalse(LearnedSleepNeed.isRestrictionShaped(night, goalMinutes: 480))
    }

    /// A long night at high efficiency is exactly what need looks like. The
    /// rule is about *short* nights; applied to long ones it would throw
    /// away the best evidence there is.
    func testALongNightAtHighEfficiencyStillCounts() {
        let night = Fixture.night(
            daysAgo: 1, timeAsleepMinutes: 500, timeInBedMinutes: 500 / 0.96
        )
        XCTAssertFalse(LearnedSleepNeed.isRestrictionShaped(night, goalMinutes: 480))
    }

    /// Excluded in the opposite direction, and deliberately so: one rule
    /// drops nights biasing the estimate down, the other drops nights
    /// biasing it up.
    func testANightSleptDeepInDebtIsARepaymentNotABaseline() {
        let repaying = Fixture.night(
            daysAgo: 1, timeAsleepMinutes: 540,
            sleepDebtMinutes: LearnedSleepNeed.repaymentDebtMinutes + 30
        )
        XCTAssertTrue(LearnedSleepNeed.isRepayingDebt(repaying))

        let settled = Fixture.night(daysAgo: 1, timeAsleepMinutes: 540, sleepDebtMinutes: 10)
        XCTAssertFalse(LearnedSleepNeed.isRepayingDebt(settled))
    }

    func testANightWithNoDebtFigureIsNotTreatedAsRepaying() {
        let night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 480, sleepDebtMinutes: nil)
        XCTAssertFalse(LearnedSleepNeed.isRepayingDebt(night))
    }

    // MARK: - What the model now says

    /// The whole point. Forty restricted nights used to produce a confident
    /// 6h15 "need"; they now produce too little qualifying evidence to claim
    /// anything, which is what the spec means by "keep conservative
    /// confidence" and "do not drastically change current Need until enough
    /// evidence exists".
    func testAChronicShortSleeperNoLongerLearnsTheirRestriction() {
        let nights = (1...40).map { restrictedNight(daysAgo: $0) }
        let need = LearnedSleepNeed.compute(goalMinutes: 480, history: nights)

        XCTAssertNil(need.learnedMinutes, "a restriction must not be learned as a need")
        XCTAssertEqual(need.confidence, .insufficient)
        XCTAssertEqual(need.minutes, 480, "falls back to the stated goal, not to 6h15")
    }

    /// No regression for someone who actually sleeps well: 7h45 at 90% is
    /// neither restriction-shaped nor a repayment, so nothing changes.
    func testAWellSleptPersonIsUnaffected() throws {
        let nights = (1...40).map {
            Fixture.night(daysAgo: $0, timeAsleepMinutes: 465, timeInBedMinutes: 465 / 0.90)
        }
        let need = LearnedSleepNeed.compute(goalMinutes: 480, history: nights)

        XCTAssertEqual(need.qualifyingNightCount, 40)
        XCTAssertEqual(try XCTUnwrap(need.learnedMinutes), 465, accuracy: 1)
    }
}
