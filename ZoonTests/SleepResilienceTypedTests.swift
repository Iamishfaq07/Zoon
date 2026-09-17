import XCTest

/// Covers personal tolerance and bounce-back by disruption type.
///
/// The card that consumed this engine passed a flat 25 minutes for everyone,
/// which is a claim that all sleepers vary by the same amount. For someone
/// whose nights sit within ten minutes of each other almost nothing was a
/// disruption; for someone genuinely erratic the band swallowed real ones.
/// Both failures were silent — the card reported the wrong thing confidently.
final class SleepResilienceTypedTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func wakeDay(_ daysAgo: Int) -> Date {
        calendar.date(
            byAdding: .day,
            value: -daysAgo,
            to: calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12))!
        )!
    }

    /// `durations[i]` is the oldest night first.
    private func nights(
        durations: [Double],
        bedtimeHours: [Int]? = nil,
        timeZones: [String]? = nil
    ) -> [SleepNightFeatures] {
        durations.enumerated().map { index, asleep in
            Fixture.night(
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep + 25,
                bedtimeHour: bedtimeHours?[index] ?? 23,
                timeZoneIdentifier: timeZones?[index] ?? "UTC",
                wakeDay: wakeDay(durations.count - index)
            )
        }
    }

    // MARK: - Personal tolerance

    /// A band this narrow would make nearly every night a disruption, so the
    /// floor holds it open.
    func testAVeryRegularSleeperGetsTheFloorNotAThreeMinuteBand() throws {
        let values = [450.0, 452, 448, 451, 449, 450, 453]
        let tolerance = try XCTUnwrap(
            SleepResilience.personalTolerance(
                values,
                floor: SleepResilience.durationToleranceFloor,
                ceiling: SleepResilience.durationToleranceCeiling
            )
        )
        XCTAssertEqual(tolerance, SleepResilience.durationToleranceFloor)
    }

    /// And a band this wide would swallow a genuinely terrible night.
    func testAVeryErraticSleeperGetsTheCeiling() throws {
        let values = [240.0, 600, 300, 540, 260, 580, 320]
        let tolerance = try XCTUnwrap(
            SleepResilience.personalTolerance(
                values,
                floor: SleepResilience.durationToleranceFloor,
                ceiling: SleepResilience.durationToleranceCeiling
            )
        )
        XCTAssertEqual(tolerance, SleepResilience.durationToleranceCeiling)
    }

    /// In between, the band is the person's own spread.
    func testAnOrdinarySpreadProducesAnIntermediateBand() throws {
        // MAD of 30 → 30 × 1.4826 ≈ 44.5, inside the bounds.
        let values = [390.0, 420, 450, 480, 510, 450, 420]
        let tolerance = try XCTUnwrap(
            SleepResilience.personalTolerance(
                values,
                floor: SleepResilience.durationToleranceFloor,
                ceiling: SleepResilience.durationToleranceCeiling
            )
        )
        XCTAssertGreaterThan(tolerance, SleepResilience.durationToleranceFloor)
        XCTAssertLessThan(tolerance, SleepResilience.durationToleranceCeiling)
    }

    func testTooFewValuesProduceNoBand() {
        XCTAssertNil(
            SleepResilience.personalTolerance([450, 460], floor: 30, ceiling: 90)
        )
    }

    // MARK: - Typed bounce-back

    /// Three short nights, each followed by a normal one, across enough
    /// history to qualify.
    func testShortSleepBounceBackIsMeasuredWhenThereAreEnoughEpisodes() throws {
        var durations = Array(repeating: 450.0, count: 28)
        for index in [5, 12, 20] { durations[index] = 300 }

        let typed = SleepResilience.byDisruptionType(nights: nights(durations: durations), calendar: calendar)
        let short = try XCTUnwrap(typed.first { $0.kind == .shortSleep })
        XCTAssertEqual(short.result.state.medianNights, 1)
        XCTAssertEqual(short.result.eventCount, 3)
        XCTAssertTrue(short.sentence.contains("bounce-back"), short.sentence)
    }

    /// Two is an anecdote. The engine waits.
    func testTwoEpisodesIsNotYetAPattern() throws {
        var durations = Array(repeating: 450.0, count: 28)
        for index in [5, 12] { durations[index] = 300 }

        let typed = SleepResilience.byDisruptionType(nights: nights(durations: durations), calendar: calendar)
        let short = try XCTUnwrap(typed.first { $0.kind == .shortSleep })
        XCTAssertNil(short.result.state.medianNights)
        XCTAssertTrue(short.sentence.contains("of 3 episodes"), short.sentence)
    }

    /// A run of short nights is one disruption, not three, and the return
    /// time is counted from where it started.
    func testAConsecutiveRunIsOneEpisode() throws {
        var durations = Array(repeating: 450.0, count: 28)
        for index in [5, 6, 7, 14, 21] { durations[index] = 300 }

        let typed = SleepResilience.byDisruptionType(nights: nights(durations: durations), calendar: calendar)
        let short = try XCTUnwrap(typed.first { $0.kind == .shortSleep })
        XCTAssertEqual(short.result.eventCount, 3, "a three-night run is one disruption")
        XCTAssertEqual(short.result.state.medianNights, 1)
    }

    /// Travel is a different trigger with the same outcome: sleep length
    /// coming back. A trip that costs two nights reads as two, not one.
    func testTravelIsMeasuredByWhenSleepComesBackNotWhenTheTripEnds() throws {
        var durations = Array(repeating: 450.0, count: 28)
        var zones = Array(repeating: "UTC", count: 28)
        // Three trips. Each: one night in another zone, and the night after
        // it is still short, so recovery is two nights from the start.
        for start in [5, 13, 21] {
            zones[start] = "Asia/Tokyo"
            durations[start] = 300
            durations[start + 1] = 300
        }

        let typed = SleepResilience.byDisruptionType(
            nights: nights(durations: durations, timeZones: zones), calendar: calendar
        )
        let travel = try XCTUnwrap(typed.first { $0.kind == .travel })
        XCTAssertEqual(travel.result.eventCount, 3)
        XCTAssertEqual(travel.result.state.medianNights, 2)
    }

    /// A late bedtime is its own trigger, separate from a short one.
    func testALateScheduleIsItsOwnDisruptionType() throws {
        var durations = Array(repeating: 450.0, count: 28)
        var bedtimes = Array(repeating: 23, count: 28)
        for index in [5, 13, 21] {
            bedtimes[index] = 3
            durations[index] = 300
        }

        let typed = SleepResilience.byDisruptionType(
            nights: nights(durations: durations, bedtimeHours: bedtimes), calendar: calendar
        )
        let late = try XCTUnwrap(typed.first { $0.kind == .lateSchedule })
        XCTAssertEqual(late.result.eventCount, 3)
        XCTAssertNotNil(late.result.state.medianNights)
    }

    /// A steady sleeper who never leaves their band has nothing to bounce
    /// back from, which is a good answer rather than a gap.
    func testASteadySleeperHasNothingToRecoverFrom() throws {
        let typed = SleepResilience.byDisruptionType(
            nights: nights(durations: Array(repeating: 450.0, count: 28)), calendar: calendar
        )
        let short = try XCTUnwrap(typed.first { $0.kind == .shortSleep })
        XCTAssertEqual(short.result.state, .steady)
        XCTAssertTrue(short.sentence.contains("hasn't happened"), short.sentence)
    }

    /// Below the history floor, nothing is claimed at all.
    func testTooLittleHistoryClaimsNothing() throws {
        var durations = Array(repeating: 450.0, count: 12)
        for index in [2, 5, 8] { durations[index] = 300 }

        let typed = SleepResilience.byDisruptionType(nights: nights(durations: durations), calendar: calendar)
        for result in typed {
            XCTAssertNil(result.result.state.medianNights, result.kind.rawValue)
        }
    }

    /// The episode count travels with every answer. A bounce-back across
    /// three disruptions and one across twenty are not the same claim.
    func testEveryTypedResultCarriesItsEpisodeCount() throws {
        var durations = Array(repeating: 450.0, count: 28)
        for index in [5, 12, 20] { durations[index] = 300 }

        let typed = SleepResilience.byDisruptionType(nights: nights(durations: durations), calendar: calendar)
        for result in typed where result.result.state.medianNights != nil {
            XCTAssertGreaterThanOrEqual(result.result.eventCount, SleepResilience.minimumEvents)
        }
    }
}
