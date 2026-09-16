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

    private var utc: TimeZone { TimeZone(secondsFromGMT: 0)! }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, in zone: TimeZone? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? utc
        return calendar.date(
            from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
        )!
    }

    /// One night with a given bedtime and wake time.
    private func night(
        bedtime: Date,
        wake: Date,
        zone: TimeZone? = nil
    ) -> SleepNightFeatures {
        // Every stage split is bound to an explicitly typed local rather than
        // written inline. `SleepNightFeatures.init` takes twenty-odd
        // arguments, and a handful of `asleep * 0.15` literals among them is
        // enough to blow the type-checker's budget for the whole call --
        // which it reports as "unable to type-check this expression in
        // reasonable time" on the opening line, not on the arithmetic.
        let asleep: Double = wake.timeIntervalSince(bedtime) / 60
        let core: Double = asleep * 0.55
        let deep: Double = asleep * 0.15
        let rem: Double = asleep * 0.2
        let awake: Double = asleep * 0.1
        return SleepNightFeatures(
            date: wake,
            bedtime: bedtime,
            wakeTime: wake,
            timeInBedMinutes: asleep,
            timeAsleepMinutes: asleep,
            sleepEfficiencyPercent: 95,
            coreMinutes: core,
            deepMinutes: deep,
            remMinutes: rem,
            unspecifiedAsleepMinutes: 0,
            awakeMinutes: awake,
            wakeCount: 2,
            sleepLatencyMinutes: 12,
            avgHeartRate: 56,
            minHeartRate: 49,
            avgHRV: 55,
            avgRespiratoryRate: 14.5,
            avgSpO2: 97,
            wristTempDeltaC: 0,
            hrv7DayAvg: 55,
            sleepDebtMinutes: 0,
            lastWorkoutHoursBeforeBed: nil,
            timeZone: zone ?? utc
        )
    }

    // MARK: - The case the old arithmetic got wrong

    /// Three nights that are nearly identical must read as nearly identical.
    func testBedtimesStraddlingMidnightClusterRatherThanScatter() throws {
        let nights = [
            night(bedtime: date(14, 23, 50), wake: date(15, 7, 0)),
            night(bedtime: date(16, 0, 0), wake: date(16, 7, 10)),
            night(bedtime: date(17, 0, 10), wake: date(17, 7, 20))
        ]
        let summary = SleepTimingSummary.make(nights: nights)

        let bedtime = try XCTUnwrap(summary.bedtimeMinutes)
        XCTAssertEqual(SleepTimingSummary.clockLabel(bedtime), "00:00")
        // Ten minutes, not thirteen and a half hours.
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 10, accuracy: 0.5)
    }

    /// The seam the shifted representation left behind: two bedtimes twenty
    /// minutes apart either side of 18:00 came out twenty-four hours apart.
    func testBedtimesStraddlingSixPMAlsoCluster() throws {
        let nights = [
            night(bedtime: date(14, 17, 50), wake: date(15, 1, 0)),
            night(bedtime: date(15, 18, 0), wake: date(16, 1, 10)),
            night(bedtime: date(16, 18, 10), wake: date(17, 1, 20))
        ]
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "18:00")
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 10, accuracy: 0.5)
    }

    /// A day sleeper is an ordinary schedule, not an edge case, and nothing
    /// about it should go through a midnight branch at all.
    func testADaySleeperReportsAnAfternoonMidSleep() throws {
        let nights = (14...20).map { day in
            night(bedtime: date(day, 9, 0), wake: date(day, 16, 30))
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "09:00")
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.wakeMinutes)), "16:30")
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.midSleepMinutes)), "12:45")
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 0, accuracy: 0.001)
    }

    /// Mid-sleep for a night that crosses midnight is in the small hours, not
    /// at noon — which is what averaging the two clock readings would give.
    func testMidSleepCrossesMidnightCorrectly() throws {
        let nights = (14...20).map { day in
            night(bedtime: date(day, 23, 40), wake: date(day + 1, 7, 10))
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.midSleepMinutes)), "03:25")
    }

    // MARK: - Robustness

    /// One 04:00 night in a fortnight of 23:00 bedtimes must not drag the
    /// reported median across an hour. A vector mean would.
    func testASingleLateNightDoesNotMoveTheMedian() throws {
        var nights = (1...13).map { day in
            night(bedtime: date(day, 23, 0), wake: date(day + 1, 6, 30))
        }
        nights.append(night(bedtime: date(15, 4, 0), wake: date(15, 9, 0)))

        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "23:00")
    }

    /// A genuinely irregular schedule must report a large spread rather than
    /// being smoothed into a tidy one.
    func testAnIrregularScheduleReportsALargeSpread() throws {
        let bedtimes = [21, 23, 1, 3, 22, 0, 2]
        let nights = bedtimes.enumerated().map { index, hour in
            let day = 14 + index
            let bedtime = date(day, hour)
            return night(bedtime: bedtime, wake: bedtime.addingTimeInterval(7 * 3600))
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertGreaterThan(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 60)
    }

    // MARK: - Provenance the document has to carry

    func testTravelAcrossTimezonesIsDeclared() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let nights = [
            night(bedtime: date(14, 23, 0), wake: date(15, 7, 0)),
            night(bedtime: date(15, 23, 0, in: tokyo), wake: date(16, 7, 0, in: tokyo), zone: tokyo)
        ]
        let summary = SleepTimingSummary.make(nights: nights)
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
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        // 23:00 local in Tokyo every night.
        let nights = (14...20).map { day in
            night(bedtime: date(day, 23, 0, in: tokyo), wake: date(day + 1, 7, 0, in: tokyo), zone: tokyo)
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "23:00")
    }

    func testTheSampleCountIsReported() {
        let nights = (14...20).map { day in
            night(bedtime: date(day, 23, 0), wake: date(day + 1, 7, 0))
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(summary.nightCount, 7)
        XCTAssertEqual(
            summary.rows.first(where: { $0.label == "Nights with timing data" })?.value,
            "7"
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
    func testDaylightSavingTransitionDoesNotMoveTheClockReading() throws {
        let london = TimeZone(identifier: "Europe/London")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        // 25 October 2026 is the UK clock change.
        let nights = (23...27).map { day -> SleepNightFeatures in
            let bedtime = calendar.date(
                from: DateComponents(year: 2026, month: 10, day: day, hour: 23, minute: 0)
            )!
            return night(bedtime: bedtime, wake: bedtime.addingTimeInterval(8 * 3600), zone: london)
        }
        let summary = SleepTimingSummary.make(nights: nights)
        XCTAssertEqual(SleepTimingSummary.clockLabel(try XCTUnwrap(summary.bedtimeMinutes)), "23:00")
        XCTAssertEqual(try XCTUnwrap(summary.bedtimeVariabilityMinutes), 0, accuracy: 0.001)
    }
}
