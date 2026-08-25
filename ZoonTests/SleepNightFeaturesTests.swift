import XCTest

final class SleepNightFeaturesTests: XCTestCase {

    func testTotal24hAsleepMinutesAddsSecondaryToMain() {
        var night = Fixture.night(timeAsleepMinutes: 400)
        night.secondaryAsleepMinutes = 45
        XCTAssertEqual(night.total24hAsleepMinutes, 445, accuracy: 0.01)
    }

    func testTotal24hAsleepMinutesDefaultsToMainSleepAlone() {
        let night = Fixture.night(timeAsleepMinutes: 400)
        XCTAssertEqual(night.total24hAsleepMinutes, 400, accuracy: 0.01)
    }

    // MARK: - nightKey

    /// The exact format `SleepSession.nightKey` uses ("YYYY-MM-DD@tzId"),
    /// derived independently here from the same `date` to pin the formula
    /// down rather than just re-deriving it.
    func testNightKeyMatchesDateComponentsInItsOwnTimeZone() {
        var night = Fixture.night()
        night.timeZoneIdentifier = "America/New_York"

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let components = calendar.dateComponents([.year, .month, .day], from: night.date)
        let expected = String(
            format: "%04d-%02d-%02d@America/New_York",
            components.year ?? 0, components.month ?? 0, components.day ?? 0
        )

        XCTAssertEqual(night.nightKey, expected)
    }

    /// The whole point of `nightKey` over comparing `Date`s directly: the
    /// same absolute instant can fall on different calendar days depending
    /// on which timezone reads it -- 2024-01-15 07:30 UTC is already the
    /// 15th in New York but still the 14th in Los Angeles. A plain
    /// `Date`/`Calendar.current` join can't tell these apart once the
    /// device's current timezone differs from the one a night actually
    /// happened in; `nightKey`, keyed off each night's own recorded
    /// timezone, gets it right regardless of where the comparison runs.
    func testNightKeyCrossesADayBoundaryDifferentlyPerTimeZone() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let instant = utcCalendar.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 7, minute: 30))!

        let eastCoast = night(date: instant, timeZoneIdentifier: "America/New_York")
        let westCoast = night(date: instant, timeZoneIdentifier: "America/Los_Angeles")

        XCTAssertEqual(eastCoast.nightKey, "2024-01-15@America/New_York")
        XCTAssertEqual(westCoast.nightKey, "2024-01-14@America/Los_Angeles")
    }

    /// Minimal night at a specific instant/timezone -- `Fixture.night`
    /// always anchors to a 7am local wake time, which can't land on a UTC
    /// instant that crosses midnight differently per timezone the way this
    /// test needs.
    private func night(date: Date, timeZoneIdentifier: String) -> SleepNightFeatures {
        SleepNightFeatures(
            date: date, bedtime: date.addingTimeInterval(-8 * 3600), wakeTime: date,
            timeInBedMinutes: 480, timeAsleepMinutes: 450, sleepEfficiencyPercent: 94,
            coreMinutes: 250, deepMinutes: 100, remMinutes: 100, unspecifiedAsleepMinutes: 0,
            awakeMinutes: 30, wakeCount: 2, sleepLatencyMinutes: nil, avgHeartRate: nil,
            minHeartRate: nil, avgHRV: nil, avgRespiratoryRate: nil, avgSpO2: nil,
            wristTempDeltaC: nil, hrv7DayAvg: nil, sleepDebtMinutes: nil,
            lastWorkoutHoursBeforeBed: nil, exerciseMinutesPreviousDay: nil, sourceName: nil,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}
