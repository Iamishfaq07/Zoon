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
}
