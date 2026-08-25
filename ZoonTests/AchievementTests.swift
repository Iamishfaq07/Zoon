import XCTest

final class AchievementTests: XCTestCase {

    /// A night whose main sleep alone falls short of the goal, but whose
    /// naps push the 24h total over it, must count toward "hit your sleep
    /// goal" -- the same total24hAsleepMinutes convention "achieved vs.
    /// need" uses everywhere else in the app. Naps already earn their own
    /// separate badge category (`napCount`); this is about not silently
    /// denying credit here too.
    func testNapCompensatedNightCountsTowardGoal() {
        var night = Fixture.night(timeAsleepMinutes: 300) // 5h main sleep
        night.secondaryAsleepMinutes = 200 // +3h20m of naps -> 500 total

        let achievements = AchievementEngine.evaluate(nights: [night], goalMinutes: 480)

        let bronzeGoal = achievements.first { $0.id == "goal-7" }
        XCTAssertEqual(bronzeGoal?.value, 1, "the nap-compensated night should count toward the goal badges")
    }

    /// The same total should decide streaks, not just the cumulative count.
    func testNapCompensatedNightExtendsAStreak() {
        var night = Fixture.night(timeAsleepMinutes: 300)
        night.secondaryAsleepMinutes = 200

        let run = AchievementEngine.longestRun([night], goalMinutes: 480)
        XCTAssertEqual(run, 1)
    }

    /// A night that falls short even with naps included must not count --
    /// this isn't just "always pass", the threshold still applies to the
    /// total.
    func testShortNightStillMissesGoalDespiteASmallNap() {
        var night = Fixture.night(timeAsleepMinutes: 300)
        night.secondaryAsleepMinutes = 30 // 330 total, still under 480

        let achievements = AchievementEngine.evaluate(nights: [night], goalMinutes: 480)
        let bronzeGoal = achievements.first { $0.id == "goal-7" }
        XCTAssertEqual(bronzeGoal?.value, 0)

        let run = AchievementEngine.longestRun([night], goalMinutes: 480)
        XCTAssertEqual(run, 0)
    }
}
