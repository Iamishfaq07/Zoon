import XCTest

/// Physiological Load compared waking readings against overnight resting
/// ones. A desk-bound heart rate of 70 is perfectly normal and sits 30% above
/// a perfectly normal sleeping 54, which the ±20% band reads as "High" — a
/// relaxed afternoon reported as elevated load purely because the two numbers
/// were never on the same scale.
final class DaytimeBaselineTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 3, day: day, hour: hour, minute: minute
        ))!
    }

    /// `days` days of readings at `hour`, `perDay` per day.
    private func samples(
        hour: Int, value: Double, days: Int, perDay: Int = 2, startDay: Int = 1
    ) -> [DaytimeBaseline.Sample] {
        (0..<days).flatMap { day in
            (0..<perDay).map { n in
                DaytimeBaseline.Sample(
                    date: date(day: startDay + day, hour: hour, minute: n * 10),
                    value: value
                )
            }
        }
    }

    // MARK: - Binning

    func testBlocksAreThreeHoursFromMidnight() {
        XCTAssertEqual(DaytimeBaseline.binIndex(for: date(day: 1, hour: 0), calendar: calendar), 0)
        XCTAssertEqual(DaytimeBaseline.binIndex(for: date(day: 1, hour: 2), calendar: calendar), 0)
        XCTAssertEqual(DaytimeBaseline.binIndex(for: date(day: 1, hour: 3), calendar: calendar), 1)
        XCTAssertEqual(DaytimeBaseline.binIndex(for: date(day: 1, hour: 14), calendar: calendar), 4)
        XCTAssertEqual(DaytimeBaseline.binIndex(for: date(day: 1, hour: 23), calendar: calendar), 7)
    }

    /// Morning and afternoon are different physiological states, and one
    /// all-day average would make every morning look calm and every afternoon
    /// look stressed.
    func testEachBlockKeepsItsOwnCentre() throws {
        let baseline = DaytimeBaseline.build(
            samples: samples(hour: 7, value: 62, days: 10)
                + samples(hour: 16, value: 78, days: 10),
            calendar: calendar
        )

        XCTAssertEqual(try XCTUnwrap(baseline.bin(for: date(day: 20, hour: 7), calendar: calendar)).median, 62)
        XCTAssertEqual(try XCTUnwrap(baseline.bin(for: date(day: 20, hour: 16), calendar: calendar)).median, 78)
    }

    func testAnHourWithNoHistoryHasNoBin() {
        let baseline = DaytimeBaseline.build(
            samples: samples(hour: 7, value: 62, days: 10), calendar: calendar
        )
        XCTAssertNil(baseline.bin(for: date(day: 20, hour: 16), calendar: calendar))
    }

    // MARK: - Thresholds

    /// Twelve readings from two days is not a week's worth of evidence, and
    /// only the day count can tell the two apart.
    func testManySamplesFromFewDaysDoesNotQualify() {
        let baseline = DaytimeBaseline.build(
            samples: samples(hour: 7, value: 62, days: 2, perDay: 20), calendar: calendar
        )
        XCTAssertTrue(baseline.isEmpty, "20 readings a day for two days is two days of evidence")
    }

    func testEnoughDaysButTooFewReadingsDoesNotQualify() {
        let baseline = DaytimeBaseline.build(
            samples: samples(hour: 7, value: 62, days: 8, perDay: 1), calendar: calendar
        )
        XCTAssertTrue(baseline.isEmpty, "eight readings is under the sample floor")
    }

    func testClearingBothThresholdsQualifies() throws {
        let baseline = DaytimeBaseline.build(
            samples: samples(hour: 7, value: 62, days: 7, perDay: 2), calendar: calendar
        )
        let bin = try XCTUnwrap(baseline.bin(for: date(day: 20, hour: 8), calendar: calendar))
        XCTAssertEqual(bin.dayCount, 7)
        XCTAssertEqual(bin.sampleCount, 14)
    }

    // MARK: - Robustness

    /// A median, not a mean: the readings that survive the quiet filter are
    /// still skewed by activity, and a mean follows that tail.
    func testOneHecticAfternoonDoesNotMoveTheCentre() throws {
        var values = samples(hour: 15, value: 70, days: 10)
        values.append(DaytimeBaseline.Sample(date: date(day: 11, hour: 15), value: 190))
        values.append(DaytimeBaseline.Sample(date: date(day: 11, hour: 15, minute: 20), value: 185))

        let bin = try XCTUnwrap(
            DaytimeBaseline.build(samples: values, calendar: calendar)
                .bin(for: date(day: 20, hour: 15), calendar: calendar)
        )
        XCTAssertEqual(bin.median, 70, "two extreme readings must not redefine usual")
    }

    func testSpreadIsReportedForABandedCaller() throws {
        let mixed = (0..<14).map { n in
            DaytimeBaseline.Sample(
                date: date(day: 1 + n % 7, hour: 10, minute: n * 3),
                value: n.isMultiple(of: 2) ? 66 : 74
            )
        }
        let bin = try XCTUnwrap(
            DaytimeBaseline.build(samples: mixed, calendar: calendar)
                .bin(for: date(day: 20, hour: 10), calendar: calendar)
        )
        XCTAssertGreaterThan(bin.spread, 0)
    }
}
