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
