import XCTest

/// Streaks are a claim about *consecutive calendar days*, so every case here
/// is about what breaks adjacency rather than about arithmetic.
final class SleepStreakEngineTests: XCTestCase {

    private let goal: Double = 420

    /// The bug this engine exists to fix: Mon, Tue, [nothing recorded
    /// Wednesday], Thu, Fri is not a five- or four-night streak. The old
    /// implementation walked the array and broke only on a night under goal,
    /// so a night that was never recorded was invisible to it.
    func testMissingCalendarDayBreaksTheStreak() {
        let nights = [5, 4, 2, 1].map { Fixture.night(daysAgo: $0, timeAsleepMinutes: 460) }
        let result = SleepStreakEngine.evaluate(nights: nights, goalMinutes: goal)

        XCTAssertEqual(result.current, 2, "Only the two nights after the gap are consecutive")
        XCTAssertEqual(result.best, 2)
    }

    func testConsecutiveNightsCount() {
        let nights = (0..<4).map { Fixture.night(daysAgo: $0, timeAsleepMinutes: 460) }
        XCTAssertEqual(SleepStreakEngine.evaluate(nights: nights, goalMinutes: goal).current, 4)
    }

    func testNightUnderGoalBreaksTheStreak() {
        var nights = (0..<4).map { Fixture.night(daysAgo: $0, timeAsleepMinutes: 460) }
        nights[2] = Fixture.night(daysAgo: 2, timeAsleepMinutes: 300)
        let result = SleepStreakEngine.evaluate(nights: nights, goalMinutes: goal)
        XCTAssertEqual(result.current, 2, "Today and yesterday only")
    }

    /// The most recent night failing means there is no current streak at all,
    /// however long the run behind it was.
    func testStreakIsZeroWhenTheLatestNightMissesGoal() {
        var nights = (0..<5).map { Fixture.night(daysAgo: $0, timeAsleepMinutes: 460) }
        nights[0] = Fixture.night(daysAgo: 0, timeAsleepMinutes: 280)
        let result = SleepStreakEngine.evaluate(nights: nights, goalMinutes: goal)
        XCTAssertEqual(result.current, 0)
        XCTAssertEqual(result.best, 4, "The earlier run is still the personal best")
    }

    /// Goal is measured against the 24-hour total, so a short main sleep
    /// topped up by a nap counts — the same basis the shortfall and need use.
    func testNapCountsTowardGoalLikeEverywhereElse() {
        let night = Fixture.night(daysAgo: 0, timeAsleepMinutes: 380, secondaryAsleepMinutes: 60)
        let result = SleepStreakEngine.evaluate(nights: [night], goalMinutes: goal)
        XCTAssertEqual(result.current, 1, "380 + 60 clears a 420 goal")
    }

    /// A duplicate import must not lengthen a streak or double a day.
    func testDuplicateRecordsForOneDayCountOnce() {
        let nights = [
            Fixture.night(daysAgo: 1, timeAsleepMinutes: 460),
            Fixture.night(daysAgo: 1, timeAsleepMinutes: 455),
            Fixture.night(daysAgo: 0, timeAsleepMinutes: 460)
        ]
        let result = SleepStreakEngine.evaluate(nights: nights, goalMinutes: goal)
        XCTAssertEqual(result.current, 2)
    }

    func testEmptyHistoryIsNotAStreak() {
        let result = SleepStreakEngine.evaluate(nights: [], goalMinutes: goal)
        XCTAssertEqual(result.current, 0)
        XCTAssertEqual(result.best, 0)
        XCTAssertEqual(result.metInWindow, 0)
    }
}
