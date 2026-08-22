import XCTest

final class SleepDaySummaryTests: XCTestCase {

    private func interval(startMinutesFromNow: Double, durationMinutes: Double) -> DateInterval {
        let start = Date.now.addingTimeInterval(startMinutesFromNow * 60)
        return DateInterval(start: start, duration: durationMinutes * 60)
    }

    func testNoNapsIsJustMainSleep() {
        let summary = SleepDaySummary.compute(mainSleepMinutes: 420, autoEpisodes: [], manualNaps: [])
        XCTAssertEqual(summary.total24HourSleepMinutes, 420)
        XCTAssertEqual(summary.episodeCount, 0)
    }

    func testNonOverlappingNapsAreBothCredited() {
        let auto = SleepDaySummary.AutoEpisode(
            isNap: true, interval: interval(startMinutesFromNow: 0, durationMinutes: 20), asleepMinutes: 18
        )
        let manual = SleepDaySummary.ManualNap(
            interval: interval(startMinutesFromNow: 200, durationMinutes: 30), minutes: 30
        )
        let summary = SleepDaySummary.compute(mainSleepMinutes: 400, autoEpisodes: [auto], manualNaps: [manual])

        XCTAssertEqual(summary.automaticNapAsleepMinutes, 18)
        XCTAssertEqual(summary.manualNapMinutes, 30)
        XCTAssertEqual(summary.total24HourSleepMinutes, 400 + 18 + 30)
        XCTAssertEqual(summary.episodeCount, 2)
    }

    /// The actual bug this type fixes: a nap caught by both a Zoon timer
    /// and a Watch detection must be credited once, not summed -- and the
    /// credited amount is the larger source's own asleep-time estimate,
    /// not the union of both raw intervals (which would count in-bed-but-
    /// awake padding as sleep).
    func testOverlappingNapsAreCreditedOnceUsingTheLargerEstimate() {
        // Manual timer: 08:00-08:32 (32 minutes). Watch detected the same
        // nap but only credits 24 minutes of it as actually asleep.
        let auto = SleepDaySummary.AutoEpisode(
            isNap: true, interval: interval(startMinutesFromNow: 0, durationMinutes: 32), asleepMinutes: 24
        )
        let manual = SleepDaySummary.ManualNap(
            interval: interval(startMinutesFromNow: 0, durationMinutes: 32), minutes: 32
        )
        let summary = SleepDaySummary.compute(mainSleepMinutes: 400, autoEpisodes: [auto], manualNaps: [manual])

        // Credited once (32, the larger of the two estimates), not summed
        // (24 + 32 = 56).
        XCTAssertEqual(summary.total24HourSleepMinutes, 400 + 32)
        XCTAssertEqual(summary.manualNapMinutes, 32)
        XCTAssertEqual(summary.automaticNapAsleepMinutes, 0)
        // Both sources are still visible in the count, even though only
        // one contributed minutes -- provenance isn't discarded.
        XCTAssertEqual(summary.episodeCount, 2)
    }

    func testSecondarySleepIsNotDedupedAgainstNaps() {
        let secondary = SleepDaySummary.AutoEpisode(
            isNap: false, interval: interval(startMinutesFromNow: -600, durationMinutes: 90), asleepMinutes: 80
        )
        let summary = SleepDaySummary.compute(mainSleepMinutes: 400, autoEpisodes: [secondary], manualNaps: [])

        XCTAssertEqual(summary.secondarySleepMinutes, 80)
        XCTAssertEqual(summary.total24HourSleepMinutes, 480)
    }

    func testThreeWayOverlapCreditsOnlyTheLargestOnce() {
        // Two auto fragments plus a manual log, all overlapping the same
        // nap window.
        let autoA = SleepDaySummary.AutoEpisode(
            isNap: true, interval: interval(startMinutesFromNow: 0, durationMinutes: 15), asleepMinutes: 14
        )
        let autoB = SleepDaySummary.AutoEpisode(
            isNap: true, interval: interval(startMinutesFromNow: 10, durationMinutes: 15), asleepMinutes: 12
        )
        let manual = SleepDaySummary.ManualNap(
            interval: interval(startMinutesFromNow: 0, durationMinutes: 25), minutes: 25
        )
        let summary = SleepDaySummary.compute(
            mainSleepMinutes: 400, autoEpisodes: [autoA, autoB], manualNaps: [manual]
        )

        XCTAssertEqual(summary.total24HourSleepMinutes, 400 + 25)
        XCTAssertEqual(summary.episodeCount, 3)
    }
}
