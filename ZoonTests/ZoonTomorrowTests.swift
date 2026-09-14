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

    /// The bug the test below this one could not see.
    ///
    /// `shiftMinutes` was read straight off `SleepAutopilot`, so asserting it
    /// was capped asserted the cap on a value the event path had *discarded*.
    /// The bedtime actually shown was `wake - targetSleep`, which can move by
    /// hours — while the `why` line underneath still read "Bedtime only moves
    /// 20 minutes earlier because larger jumps are hard to keep."
    ///
    /// So this measures the bedtime itself against the habitual one, and
    /// checks the sentence against the movement it is describing.
    func testEventBedtimeIsTheOneTheCapProduced() throws {
        // Habitually 23:30-06:30. A 05:00 event demands a wake ~2h earlier
        // than usual, which is far more than one night may move.
        let now = date(2026, 9, 14, 18, 0)
        let history = (0..<14).map { index in
            Fixture.night(
                daysAgo: 14 - index,
                timeAsleepMinutes: 420,
                timeInBedMinutes: 420,
                bedtimeHour: 23,
                bedtimeMinuteOffset: 30
            )
        }
        let event = ZoonTomorrow.Event(start: date(2026, 9, 15, 5, 0), isAllDay: false, source: .manual)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: event,
            nights: history,
            sleepNeedMinutes: 480,
            calendar: calendar
        ))

        let bedtimeMinutes = Double(calendar.component(.hour, from: plan.bedtime) * 60
            + calendar.component(.minute, from: plan.bedtime))
        // Habitual bedtime is 23:30 = 1410 minutes from midnight; an earlier
        // bedtime that same evening is a smaller number on the same day.
        let movedBy = abs(bedtimeMinutes - (23 * 60 + 30))

        XCTAssertLessThanOrEqual(
            movedBy, SleepAutopilot.maximumNightlyShift + 1,
            "the shown bedtime moved \(Int(movedBy))m, past the nightly cap"
        )

        // And the explanation must not describe a cap the bedtime did not go
        // through, in either direction.
        if let capLine = plan.why.first(where: { $0.contains("only moves") }) {
            XCTAssertGreaterThan(
                abs(plan.shiftMinutes), 0,
                "the plan claims a capped move while reporting no shift: \(capLine)"
            )
        }
    }

    /// A late-evening open must not hand back a wind-down that already passed.
    func testLateEveningPlanIsNotEntirelyInThePast() throws {
        let now = date(2026, 9, 14, 23, 50)
        let event = ZoonTomorrow.Event(start: date(2026, 9, 15, 9, 0), isAllDay: false, source: .manual)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: event,
            nights: nights(),
            sleepNeedMinutes: 480,
            calendar: calendar
        ))

        XCTAssertGreaterThan(
            plan.wake, now,
            "wake is in the past"
        )
        XCTAssertGreaterThan(
            plan.bedtime, now.addingTimeInterval(-60 * 60),
            "bedtime sits more than an hour before the moment the plan was asked for"
        )
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
