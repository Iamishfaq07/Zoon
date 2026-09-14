import XCTest

final class LongTermResilienceTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testInsufficientHistoryDoesNotInventABaseline() {
        let points = [LongTermResilience.Point(date: Date(), value: 54)]
        let signal = LongTermResilience.measure(
            name: "resting heart rate",
            points: points,
            window: .days90,
            calendar: calendar,
            unit: "bpm",
            lowerIsFavourable: true
        )
        XCTAssertNil(signal.baseline)
        XCTAssertEqual(signal.confidence, .insufficient)
        XCTAssertFalse(signal.sentence.lowercased().contains("years"))
    }

    func testRestingHRBelowBaselineReportsDaysHeld() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        var points: [LongTermResilience.Point] = []
        for day in 0..<90 {
            let date = calendar.date(byAdding: .day, value: -day, to: now)!
            let value: Double = day < 18 ? 50 : 54
            points.append(.init(date: date, value: value))
        }
        let signal = LongTermResilience.measure(
            name: "resting heart rate",
            points: points,
            window: .days90,
            now: now,
            calendar: calendar,
            unit: "bpm",
            lowerIsFavourable: true
        )
        XCTAssertEqual(signal.confidence, .high)
        XCTAssertEqual(signal.favourable, true)
        XCTAssertEqual(signal.daysHeld, 18)
        XCTAssertTrue(signal.sentence.contains("below"))
        XCTAssertFalse(signal.sentence.lowercased().contains("younger"))
    }

    /// The mirror of the test above, and the case that was broken.
    ///
    /// The run was counted on the *favourable* side whatever side the value
    /// was on, so an eighteen-day drift the wrong way started its count at
    /// zero and lost the "for 18 days" from the sentence that most needed it.
    func testRestingHRAboveBaselineAlsoReportsDaysHeld() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        var points: [LongTermResilience.Point] = []
        for day in 0..<90 {
            let date = calendar.date(byAdding: .day, value: -day, to: now)!
            // Eighteen recent days *above* a 50 bpm baseline.
            let value: Double = day < 18 ? 58 : 50
            points.append(.init(date: date, value: value))
        }
        let signal = LongTermResilience.measure(
            name: "resting heart rate",
            points: points,
            window: .days90,
            now: now,
            calendar: calendar,
            unit: "bpm",
            lowerIsFavourable: true
        )

        XCTAssertEqual(signal.favourable, false, "above baseline is the unfavourable side for RHR")
        XCTAssertEqual(signal.daysHeld, 18, "the run on the unfavourable side was not counted")
        XCTAssertTrue(signal.sentence.contains("above"))
        XCTAssertTrue(
            signal.sentence.contains("18 days"),
            "the sentence dropped the duration: \(signal.sentence)"
        )
    }

    /// A metric where higher is better exercises the other polarity, so the
    /// fix cannot be a hard-coded side.
    func testHigherIsBetterMetricCountsItsUnfavourableRunToo() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        var points: [LongTermResilience.Point] = []
        for day in 0..<90 {
            let date = calendar.date(byAdding: .day, value: -day, to: now)!
            // Twelve recent days of *lower* HRV, which is unfavourable.
            let value: Double = day < 12 ? 40 : 60
            points.append(.init(date: date, value: value))
        }
        let signal = LongTermResilience.measure(
            name: "HRV",
            points: points,
            window: .days90,
            now: now,
            calendar: calendar,
            unit: "ms",
            lowerIsFavourable: false
        )

        XCTAssertEqual(signal.favourable, false)
        XCTAssertEqual(signal.daysHeld, 12)
        XCTAssertTrue(signal.sentence.contains("below"))
    }
}
