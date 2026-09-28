import XCTest

/// Everything drawn beside the headline shortfall decays as the ledger does:
/// per calendar night, not per record.
///
/// The Trends chart, What Changed, Today's week-ago line and Sleep Health
/// used the undated series. A 300-minute night, ten unworn nights, then a
/// full night: the ledger has 300 x 0.933^11, about 2h 20m; the chart said
/// 300 x 0.933, 4h 40m.
final class DatedShortfallSeriesTests: XCTestCase {

    func testAGapDecaysByTheNightsThatPassed() throws {
        let nights = [
            Fixture.night(daysAgo: 12, timeAsleepMinutes: 180, timeInBedMinutes: 200, sleepDebtMinutes: nil),
            Fixture.night(daysAgo: 1, timeAsleepMinutes: 480, timeInBedMinutes: 500, sleepDebtMinutes: nil)
        ]
        let series = RecentSleepShortfall.debtSeries(nightsOldestFirst: nights, fallbackGoalMinutes: 480)
        let last = try XCTUnwrap(series.last)
        let expected = 300 * pow(RecentSleepShortfall.decayPerNight, 11)
        XCTAssertEqual(last, expected, accuracy: 0.5)
        XCTAssertLessThan(last, 150)
    }

    /// Consecutive nights are unchanged: the dated series is the undated one
    /// when nothing is missing.
    func testConsecutiveNightsMatchTheUndatedSeries() {
        let nights = (1...10).reversed().map {
            Fixture.night(daysAgo: $0, timeAsleepMinutes: 420, timeInBedMinutes: 450, sleepDebtMinutes: nil)
        }
        let dated = RecentSleepShortfall.debtSeries(nightsOldestFirst: nights, fallbackGoalMinutes: 480)
        let undated = RecentSleepShortfall.debtSeries(
            timeAsleepMinutesOldestFirst: nights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: nights.map { _ in 480.0 }
        )
        XCTAssertEqual(dated.count, undated.count)
        for (a, b) in zip(dated, undated) { XCTAssertEqual(a, b, accuracy: 0.001) }
    }

    /// Each night's own frozen need is used, the fallback only without one.
    func testFrozenNeedIsPreferredOverTheFallback() throws {
        var night = Fixture.night(daysAgo: 1, timeAsleepMinutes: 420, timeInBedMinutes: 450, sleepDebtMinutes: nil)
        night.sleepNeedBaselineMinutes = 450
        let series = RecentSleepShortfall.debtSeries(nightsOldestFirst: [night], fallbackGoalMinutes: 480)
        XCTAssertEqual(try XCTUnwrap(series.last), 30, accuracy: 0.001)
    }
}
