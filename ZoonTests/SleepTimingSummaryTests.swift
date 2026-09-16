import XCTest

/// Covers the clinician report's timing statistics.
///
/// Bedtime and wake time are angles. Read as plain numbers, 23:50 / 00:00 /
/// 00:10 — a person going to bed at almost exactly the same moment three
/// nights running — has a mean of 07:56 and a standard deviation of thirteen
/// and a half hours. The rows these replace dodged that by shifting
/// everything at or after 18:00 back a day, which works for an ordinary night
/// sleeper and puts the seam exactly where a shift worker's bedtimes live.
final class SleepTimingSummaryTests: XCTestCase {

    /// Noon on a given September day, in a given zone — a seed for
    /// `Fixture.night`, which derives the real bedtime and wake from it.
    private func noon(_ day: Int, in zone: String = "UTC") -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: day, hour: 12)
        )!
    }

    /// One night, built through `Fixture.night` rather than by hand.
    ///
    /// The hand-rolled `SleepNightFeatures(...)` this replaced listed twenty
    /// arguments and missed two of them, which is the whole argument for the
    /// fixture: an initializer that wide is not something a test should be
    /// restating.
    ///
    /// `bedtimeHour` at or after noon anchors the night on the *previous*
    /// day, so a 23:00 bedtime belongs to the night ending on `wakeDay`.
    private func night(
        bedtimeHour: Int,
        bedtimeMinute: Int = 0,
        inBedMinutes: Double = 450,
        wakeDay: Int,
        zone: String = "UTC"
    ) -> SleepNightFeatures {
        Fixture.night(
            timeAsleepMinutes: inBedMinutes - 25,
            timeInBedMinutes: inBedMinutes,
            bedtimeHour: bedtimeHour,
            bedtimeMinuteOffset: bedtimeMinute,
            timeZoneIdentifier: zone,
            wakeDay: noon(wakeDay, in: zone)
        )
    }

    // MARK: - The case the old arithmetic got wrong

    /// Three nights that are nearly identical must read as nearly identical.
    func testBedtimesStraddlingMidnightClusterRatherThanScatter() throws {
        let summary = SleepTimingSummary.make(nights: [
            night(bedtimeHour: 23, bedtimeMinute: 50, wakeDay: 15),
            night(bedtimeHour: 0, wakeDay: 16),
            night(bedtimeHour: 0, bedtimeMinute: 10, wakeDay: 17)
        ])

        XCTAssertEqual(
            SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "00:00"
        )
        // Ten minutes, not thirteen and a half hours.
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 10, accuracy: 0.5)
    }

    /// The seam the shifted representation left behind: two bedtimes twenty
    /// minutes apart either side of 18:00 came out twenty-four hours apart,
    /// which is exactly where a shift worker's bedtimes live.
    func testBedtimesStraddlingSixPMAlsoCluster() throws {
        let summary = SleepTimingSummary.make(nights: [
            night(bedtimeHour: 17, bedtimeMinute: 50, wakeDay: 15),
            night(bedtimeHour: 18, wakeDay: 16),
            night(bedtimeHour: 18, bedtimeMinute: 10, wakeDay: 17)
        ])
        XCTAssertEqual(
            SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "18:00"
        )
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 10, accuracy: 0.5)
    }

    /// A day sleeper is an ordinary schedule, not an edge case, and nothing
    /// about it should go through a midnight branch at all.
    func testADaySleeperReportsAnAfternoonMidSleep() throws {
        let summary = SleepTimingSummary.make(
            nights: (15...21).map { night(bedtimeHour: 9, wakeDay: $0) }
        )
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "09:00")
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.wakeMinutes)), "16:30")
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.midSleepMinutes)), "12:45")
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 0, accuracy: 0.001)
    }

    /// Mid-sleep for a night that crosses midnight is in the small hours, not
    /// at noon — which is what averaging the two clock readings would give.
    func testMidSleepCrossesMidnightCorrectly() throws {
        let summary = SleepTimingSummary.make(
            nights: (15...21).map { night(bedtimeHour: 23, bedtimeMinute: 40, wakeDay: $0) }
        )
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.midSleepMinutes)), "03:25")
    }

    // MARK: - Robustness

    /// One 04:00 night in a fortnight of 23:00 bedtimes must not drag the
    /// reported median across an hour. A vector mean would.
    func testASingleLateNightDoesNotMoveTheMedian() throws {
        var nights = (2...14).map { night(bedtimeHour: 23, wakeDay: $0) }
        nights.append(night(bedtimeHour: 4, wakeDay: 15))

        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "23:00")
    }

    /// A genuinely irregular schedule must report a large spread rather than
    /// being smoothed into a tidy one.
    func testAnIrregularScheduleReportsALargeSpread() throws {
        let hours = [21, 23, 1, 3, 22, 0, 2]
        let summary = SleepTimingSummary.make(
            nights: hours.enumerated().map { index, hour in
                night(bedtimeHour: hour, wakeDay: 15 + index)
            }
        )
        XCTAssertGreaterThan(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 60)
    }

    // MARK: - Provenance the document has to carry

    func testTravelAcrossTimezonesIsDeclared() {
        let summary = SleepTimingSummary.make(nights: [
            night(bedtimeHour: 23, wakeDay: 15),
            night(bedtimeHour: 23, wakeDay: 16, zone: "Asia/Tokyo")
        ])
        XCTAssertEqual(summary.timeZoneIdentifiers.count, 2)
        XCTAssertTrue(
            summary.rows.contains { $0.label == "Timezones in this range" },
            "a report spanning a travel period has to say so"
        )
    }

    /// Each night is read in its own timezone: a report drawn after
    /// travelling must not recompute historical bedtimes in the zone the
    /// phone is in now.
    func testEachNightIsReadInItsOwnTimezone() throws {
        let summary = SleepTimingSummary.make(
            nights: (15...21).map { night(bedtimeHour: 23, wakeDay: $0, zone: "Asia/Tokyo") }
        )
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "23:00")
    }

    func testTheSampleCountIsReported() {
        let summary = SleepTimingSummary.make(
            nights: (15...21).map { night(bedtimeHour: 23, wakeDay: $0) }
        )
        XCTAssertEqual(summary.nightCount, 7)
        XCTAssertEqual(
            summary.rows.first(where: { $0.label == "Nights with timing data" })?.value, "7"
        )
    }

    /// No nights is "Not available", not `00:00`. A plausible-looking zero on
    /// a clinician document is indistinguishable from a measurement.
    func testAnEmptyRangeReportsNotAvailableRatherThanMidnight() {
        let summary = SleepTimingSummary.make(nights: [])
        XCTAssertNil(summary.bedtimeMinutes)
        for row in summary.rows where row.label.hasPrefix("Median") {
            XCTAssertEqual(row.value, "Not available", row.label)
        }
    }

    // MARK: - The circular primitives underneath

    func testCircularMedianOfTimesAroundMidnight() throws {
        let values = [23.0 * 60 + 50, 0, 10]
        XCTAssertEqual(try XCTUnwrap(Statistics.circularMedian(values)), 0, accuracy: 0.001)
    }

    func testCircularDifferenceKeepsDirectionAcrossMidnight() {
        // 00:10 is forty minutes *after* 23:30, not 1400 minutes before it.
        XCTAssertEqual(Statistics.circularDifference(10, 23 * 60 + 30), 40, accuracy: 0.001)
        XCTAssertEqual(Statistics.circularDifference(23 * 60 + 30, 10), -40, accuracy: 0.001)
        XCTAssertEqual(Statistics.circularDifference(120, 60), 60, accuracy: 0.001)
    }

    func testCircularMadIsMeasuredAboutTheCentreThatIsReported() throws {
        let values = [23.0 * 60 + 50, 0, 10]
        let centre = try XCTUnwrap(Statistics.circularMedian(values))
        let spread = try XCTUnwrap(
            Statistics.circularMedianAbsoluteDeviation(values, around: centre)
        )
        XCTAssertEqual(spread, 10, accuracy: 0.001)
    }

    /// DST: the same 23:00 local bedtime either side of a transition is the
    /// same bedtime, because it is read as a wall clock in its own zone.
    /// 25 October 2026 is the UK clock change.
    func testDaylightSavingTransitionDoesNotMoveTheClockReading() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        // Bedtimes on the 23rd through the 27th, so wake days are the 24th
        // through the 28th.
        let nights = (24...28).map { day -> SleepNightFeatures in
            Fixture.night(
                timeAsleepMinutes: 425,
                timeInBedMinutes: 450,
                bedtimeHour: 23,
                timeZoneIdentifier: "Europe/London",
                wakeDay: calendar.date(
                    from: DateComponents(year: 2026, month: 10, day: day, hour: 12)
                )!
            )
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "23:00")
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 0, accuracy: 0.001)
    }
}
