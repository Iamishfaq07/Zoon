import XCTest

final class ZoonTomorrowTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func nights(count: Int = 14) -> [SleepNightFeatures] {
        (0..<count).map { index in
            Fixture.night(daysAgo: count - index, timeAsleepMinutes: 420, timeInBedMinutes: 450)
        }
    }

    func testEarlyMorningEventMovesWakeAndKeepsTheShiftCapped() throws {
        let now = date(2026, 9, 14, 18, 0)
        let event = ZoonTomorrow.Event(start: date(2026, 9, 15, 8, 30), isAllDay: false, source: .manual)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: event,
            nights: nights(),
            sleepNeedMinutes: 480,
            sleepDebtMinutes: 40,
            calendar: calendar
        ))

        XCTAssertEqual(calendar.component(.hour, from: plan.wake), 7)
        XCTAssertEqual(calendar.component(.minute, from: plan.wake), 40)
        XCTAssertLessThanOrEqual(abs(plan.shiftMinutes), SleepAutopilot.maximumNightlyShift)
        XCTAssertTrue(plan.nodes.contains(where: { $0.kind == .event }))
        XCTAssertTrue(plan.caveat.lowercased().contains("not a medical"))
        XCTAssertFalse(plan.sentence.lowercased().contains("will feel"))
    }

    func testLateAfternoonEventIsNotAMorningCommitment() throws {
        let now = date(2026, 9, 14, 18, 0)
        let event = ZoonTomorrow.Event(start: date(2026, 9, 15, 16, 0), isAllDay: false, source: .manual)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: event,
            nights: nights(),
            sleepNeedMinutes: 480,
            calendar: calendar
        ))
        XCTAssertNil(plan.event)
        XCTAssertFalse(plan.nodes.contains(where: { $0.kind == .event }))
    }

    func testAllDayEventIsIgnored() throws {
        let now = date(2026, 9, 14, 18, 0)
        let event = ZoonTomorrow.Event(start: date(2026, 9, 15, 0, 0), isAllDay: true, source: .calendar)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: event,
            nights: nights(),
            sleepNeedMinutes: 480,
            calendar: calendar
        ))
        XCTAssertNil(plan.event)
    }

    func testShortfallIsCappedInsideTheTarget() throws {
        let now = date(2026, 9, 14, 18, 0)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: nil,
            nights: nights(),
            sleepNeedMinutes: 480,
            sleepDebtMinutes: 240,
            calendar: calendar
        ))
        XCTAssertLessThanOrEqual(plan.targetSleepMinutes, 480 + SleepAutopilot.maximumDebtRepayment + 0.01)
    }

    func testCaffeineAndWindDownSitBeforeTheSleepWindow() throws {
        let now = date(2026, 9, 14, 12, 0)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: ZoonTomorrow.Event(start: date(2026, 9, 15, 8, 30), isAllDay: false, source: .manual),
            nights: nights(),
            sleepNeedMinutes: 480,
            calendar: calendar
        ))
        if let caffeine = plan.caffeineCutoff {
            XCTAssertLessThan(caffeine, plan.sleepWindowStart)
        }
        XCTAssertLessThan(plan.windDown, plan.sleepWindowStart)
        XCTAssertLessThan(plan.sleepWindowEnd, plan.wake)
        XCTAssertEqual(plan.confidence, .high)
    }

    func testInsufficientHistoryStillPlansWhenAnEventExists() throws {
        let now = date(2026, 9, 14, 18, 0)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: ZoonTomorrow.Event(start: date(2026, 9, 15, 9, 0), isAllDay: false, source: .manual),
            nights: nights(count: 3),
            sleepNeedMinutes: 450,
            calendar: calendar
        ))
        XCTAssertEqual(plan.confidence, .low)
        XCTAssertEqual(calendar.component(.hour, from: plan.wake), 8)
        XCTAssertEqual(calendar.component(.minute, from: plan.wake), 10)
    }

    func testZeroNeedProducesNothing() {
        let now = date(2026, 9, 14, 18, 0)
        XCTAssertNil(ZoonTomorrow.plan(
            now: now,
            event: nil,
            nights: nights(),
            sleepNeedMinutes: 0,
            calendar: calendar
        ))
    }
}
