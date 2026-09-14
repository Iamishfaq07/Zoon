import XCTest

/// A streak is a claim about consecutive local days. Travel and daylight
/// saving must not create or break one by arithmetic accident.
///
/// The engine used to key days by `startOfDay` in each night's own timezone
/// and then look those keys up with the device's current calendar. Local
/// midnight in Delhi and in London are five and a half hours apart, so on the
/// day after flying home every lookup missed and a genuine streak collapsed.
final class SleepStreakTravelTests: XCTestCase {

    private let goal: Double = 480

    private func day(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    /// One night per listed (wake day, zone), each comfortably at goal.
    private func nights(_ entries: [(String, String)]) -> [SleepNightFeatures] {
        entries.map { iso, zone in
            Fixture.night(
                timeAsleepMinutes: 500,
                timeInBedMinutes: 520,
                timeZoneIdentifier: zone,
                wakeDay: day(iso)
            )
        }
    }

    private func streak(_ entries: [(String, String)]) -> SleepStreakEngine.Result {
        SleepStreakEngine.evaluate(nights: nights(entries), goalMinutes: goal)
    }

    // MARK: - Eastbound and westbound

    func testIndiaToDubaiKeepsTheStreak() {
        let result = streak([
            ("2026-03-08T02:00:00Z", "Asia/Kolkata"),
            ("2026-03-09T02:00:00Z", "Asia/Kolkata"),
            ("2026-03-10T03:00:00Z", "Asia/Dubai"),
            ("2026-03-11T03:00:00Z", "Asia/Dubai"),
        ])
        XCTAssertEqual(result.current, 4)
    }

    func testDubaiToLondonKeepsTheStreak() {
        let result = streak([
            ("2026-03-08T03:00:00Z", "Asia/Dubai"),
            ("2026-03-09T03:00:00Z", "Asia/Dubai"),
            ("2026-03-10T07:00:00Z", "Europe/London"),
            ("2026-03-11T07:00:00Z", "Europe/London"),
        ])
        XCTAssertEqual(result.current, 4)
    }

    /// Westbound: the local clock goes backwards, so two consecutive wakes
    /// can be more than 24 hours apart in elapsed time. Elapsed-time
    /// arithmetic gets this wrong; civil dates do not.
    func testLondonToNewYorkKeepsTheStreak() {
        let result = streak([
            ("2026-03-09T07:00:00Z", "Europe/London"),
            ("2026-03-10T07:00:00Z", "Europe/London"),
            ("2026-03-11T12:00:00Z", "America/New_York"),
            ("2026-03-12T12:00:00Z", "America/New_York"),
        ])
        XCTAssertEqual(result.current, 4)
    }

    /// Eastbound the other way: less than 24 hours can separate two wakes on
    /// consecutive local dates.
    func testNewYorkToLondonKeepsTheStreak() {
        let result = streak([
            ("2026-03-09T12:00:00Z", "America/New_York"),
            ("2026-03-10T12:00:00Z", "America/New_York"),
            ("2026-03-11T07:00:00Z", "Europe/London"),
            ("2026-03-12T07:00:00Z", "Europe/London"),
        ])
        XCTAssertEqual(result.current, 4)
    }

    // MARK: - Daylight saving

    func testSpringForwardDoesNotBreakAStreak() {
        // 2026-03-08 is a 23-hour day in New York.
        let result = streak([
            ("2026-03-06T12:00:00Z", "America/New_York"),
            ("2026-03-07T12:00:00Z", "America/New_York"),
            ("2026-03-08T12:00:00Z", "America/New_York"),
            ("2026-03-09T12:00:00Z", "America/New_York"),
        ])
        XCTAssertEqual(result.current, 4)
    }

    func testFallBackDoesNotDoubleCountADay() {
        // 2026-11-01 is a 25-hour day in New York.
        let result = streak([
            ("2026-10-30T12:00:00Z", "America/New_York"),
            ("2026-10-31T12:00:00Z", "America/New_York"),
            ("2026-11-01T12:00:00Z", "America/New_York"),
            ("2026-11-02T12:00:00Z", "America/New_York"),
        ])
        XCTAssertEqual(result.current, 4)
        XCTAssertEqual(result.best, 4, "a 25-hour day is still one day")
    }

    // MARK: - The rule that still bites

    /// A day with no record at all breaks the run, travel or not. This is the
    /// product rule, and it is what makes the Date Line case below honest
    /// rather than clever.
    func testAMissingLocalDayStillBreaksTheStreak() {
        let result = streak([
            ("2026-03-08T12:00:00Z", "America/New_York"),
            ("2026-03-09T12:00:00Z", "America/New_York"),
            // 10th missing
            ("2026-03-11T12:00:00Z", "America/New_York"),
        ])
        XCTAssertEqual(result.current, 1, "the run restarts at the most recent night")
        XCTAssertEqual(result.best, 2)
    }

    /// Crossing the Date Line westward skips a civil date the traveller never
    /// lived. Zoon has no record for it, so it reads as missing and breaks the
    /// run — documented in the engine as a deliberate limitation rather than
    /// papered over by inferring a zone for a day with no data.
    func testDateLineSkipIsTreatedAsAMissingDay() {
        let result = streak([
            ("2026-03-08T18:00:00Z", "Pacific/Auckland"),
            ("2026-03-09T18:00:00Z", "Pacific/Auckland"),
            // The 11th does not exist for this traveller.
            ("2026-03-11T18:00:00Z", "Pacific/Auckland"),
        ])
        XCTAssertEqual(result.current, 1)
    }

    // MARK: - Duplicates

    /// Two records for one local day are one day, not two — and the longer
    /// one wins, which is what a duplicate import should resolve to.
    func testDuplicateRecordsForOneDayCountOnce() {
        var entries = nights([
            ("2026-03-08T12:00:00Z", "America/New_York"),
            ("2026-03-09T12:00:00Z", "America/New_York"),
        ])
        entries.append(
            Fixture.night(
                timeAsleepMinutes: 300,
                timeZoneIdentifier: "America/New_York",
                wakeDay: day("2026-03-09T12:00:00Z")
            )
        )
        let result = SleepStreakEngine.evaluate(nights: entries, goalMinutes: goal)
        XCTAssertEqual(result.current, 2, "the shorter duplicate must not replace the qualifying night")
    }

    // MARK: - One engine

    /// Badges and the streak card read the same history, so they must not
    /// disagree about it. Achievements used to count runs with its own
    /// elapsed-time arithmetic.
    func testAchievementsAgreeWithTheStreakEngine() {
        let history = nights([
            ("2026-03-06T12:00:00Z", "America/New_York"),
            ("2026-03-07T12:00:00Z", "America/New_York"),
            ("2026-03-08T12:00:00Z", "America/New_York"),
            ("2026-03-10T07:00:00Z", "Europe/London"),
            ("2026-03-11T07:00:00Z", "Europe/London"),
        ])
        XCTAssertEqual(
            AchievementEngine.longestRun(history, goalMinutes: goal),
            SleepStreakEngine.evaluate(nights: history, goalMinutes: goal).best
        )
    }
}
