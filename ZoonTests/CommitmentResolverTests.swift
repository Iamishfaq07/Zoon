import XCTest

/// Covers the separation of manual and Calendar commitments.
///
/// The bug these exist for: Zoon used to store a Calendar event as an hour
/// and a minute, and reconstruct it as "tomorrow at that time" forever. A
/// Tuesday 8:30 meeting therefore became a Wednesday 8:30 commitment, then a
/// Thursday one, long after the meeting was over. Every case below is a way
/// that record stops being true.
@MainActor
final class CommitmentResolverTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, day: Int, minute: Int = 0, calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(
            from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
        )!
    }

    private func stored(
        _ start: Date,
        fetchedAt: Date,
        isAllDay: Bool = false,
        identifier: String? = "event-1"
    ) -> StoredCommitment {
        StoredCommitment(
            start: start,
            isAllDay: isAllDay,
            eventIdentifier: identifier,
            fetchedAt: fetchedAt,
            timeZoneIdentifier: "UTC"
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.zoon.sleep.tests.commitment.\(UUID().uuidString)")!
    }

    // MARK: - Which morning is being planned for

    func testEveningPlansForTheNextCalendarDay() throws {
        let window = try XCTUnwrap(PlanningDay.morning(after: date(21, day: 14), calendar: calendar))
        XCTAssertEqual(window.start, date(0, day: 15))
        XCTAssertEqual(window.end, date(0, day: 16))
    }

    /// At 1 AM the person has not slept yet. The commitment they are planning
    /// around is the one seven hours away, not thirty-one.
    func testAfterMidnightStillPlansForTheComingMorning() throws {
        let window = try XCTUnwrap(PlanningDay.morning(after: date(1, day: 15), calendar: calendar))
        XCTAssertEqual(window.start, date(0, day: 15))
        XCTAssertEqual(window.end, date(0, day: 16))
    }

    func testAfterTheLateNightCutoffTheMorningHasPassed() throws {
        let window = try XCTUnwrap(PlanningDay.morning(after: date(9, day: 15), calendar: calendar))
        XCTAssertEqual(window.start, date(0, day: 16))
    }

    // MARK: - Calendar record validity

    func testEventExistsTomorrowIsUsed() {
        let now = date(21, day: 14)
        let record = stored(date(8, day: 15, minute: 30), fetchedAt: now)
        let outcome = CommitmentResolver.resolve(
            calendarRecord: record, manual: nil, now: now, calendar: calendar
        )
        guard case let .calendar(event) = outcome else { return XCTFail("expected a calendar commitment") }
        XCTAssertEqual(event.start, date(8, day: 15, minute: 30))
        XCTAssertEqual(event.source, .calendar)
    }

    /// The original failure, written out. Tuesday's meeting must not become
    /// Wednesday's simply because 8:30 still exists on Wednesday.
    func testYesterdaysEventDoesNotSurviveIntoTheNextDay() {
        let record = stored(date(8, day: 15, minute: 30), fetchedAt: date(21, day: 14))
        let tuesdayEvening = date(21, day: 15)
        XCTAssertFalse(
            CommitmentResolver.isStillValid(record, now: tuesdayEvening, calendar: calendar)
        )
        XCTAssertEqual(
            CommitmentResolver.resolve(
                calendarRecord: record, manual: nil, now: tuesdayEvening, calendar: calendar
            ),
            .noCommitment
        )
    }

    /// An event deleted from Calendar produces a read that finds nothing.
    /// Recording that read is what clears the record.
    func testRemovedEventClearsTheRecord() {
        let defaults = makeDefaults()
        let preferences = UserPreferences(defaults: defaults)
        let monday = date(21, day: 14)

        preferences.recordCalendarRead(
            CalendarCommitment(
                start: date(8, day: 15, minute: 30),
                durationMinutes: 30,
                isAllDay: false,
                source: .calendar,
                eventIdentifier: "event-1"
            ),
            at: monday
        )
        XCTAssertNotNil(preferences.calendarCommitmentRecord)

        preferences.recordCalendarRead(nil, at: monday)
        XCTAssertNil(preferences.calendarCommitmentRecord)
    }

    /// Moving the meeting later must move the plan, not leave the old instant
    /// in place next to a new one.
    func testMovedEventReplacesTheRecordRatherThanAccumulating() {
        let preferences = UserPreferences(defaults: makeDefaults())
        let now = date(21, day: 14)
        func read(_ start: Date) {
            preferences.recordCalendarRead(
                CalendarCommitment(
                    start: start, durationMinutes: 30, isAllDay: false,
                    source: .calendar, eventIdentifier: "event-1"
                ),
                at: now
            )
        }
        read(date(8, day: 15, minute: 30))
        read(date(10, day: 15))
        XCTAssertEqual(preferences.calendarCommitmentRecord?.start, date(10, day: 15))
    }

    /// Moved out of the morning entirely: a 4 PM meeting is not a wake anchor.
    func testEventMovedPastTheMorningCutoffIsDropped() {
        let now = date(21, day: 14)
        let record = stored(date(16, day: 15), fetchedAt: now)
        XCTAssertFalse(CommitmentResolver.isStillValid(record, now: now, calendar: calendar))
    }

    func testAllDayEventIsNeverAWakeAnchor() {
        let now = date(21, day: 14)
        let record = stored(date(0, day: 15), fetchedAt: now, isAllDay: true)
        XCTAssertFalse(CommitmentResolver.isStillValid(record, now: now, calendar: calendar))
    }

    /// No read has landed in over half a day. Zoon has not looked, so it may
    /// not go on asserting what it last saw.
    func testAStaleReadExpires() {
        let record = stored(date(8, day: 16, minute: 30), fetchedAt: date(6, day: 14))
        let now = date(21, day: 15)
        XCTAssertGreaterThan(
            now.timeIntervalSince(record.fetchedAt), CommitmentResolver.maximumCalendarAge
        )
        XCTAssertFalse(CommitmentResolver.isStillValid(record, now: now, calendar: calendar))
    }

    func testAFetchStampedInTheFutureIsNotTrusted() {
        let now = date(21, day: 14)
        let record = stored(date(8, day: 15, minute: 30), fetchedAt: date(23, day: 14))
        XCTAssertFalse(CommitmentResolver.isStillValid(record, now: now, calendar: calendar))
    }

    /// A fresh, future record that simply belongs to a different day. This is
    /// the clause that kills the original bug: nothing about the record is
    /// wrong except that it is not about the morning being planned.
    func testAnEventOnTheWrongDayIsNotUsedForThisMorning() {
        let now = date(21, day: 14)
        let record = stored(date(8, day: 16, minute: 30), fetchedAt: date(20, day: 14))
        XCTAssertFalse(CommitmentResolver.isStillValid(record, now: now, calendar: calendar))
        XCTAssertEqual(
            CommitmentResolver.resolve(
                calendarRecord: record, manual: nil, now: now, calendar: calendar
            ),
            .noCommitment
        )
    }

    /// Flying east far enough changes what the stored instant means locally.
    /// The event did not move; the wall clock under it did.
    func testTravelCanTakeAnEventOutOfTheMorningEntirely() {
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        // Read in London as an 08:30 morning meeting on the 15th.
        let record = stored(date(8, day: 15, minute: 30), fetchedAt: date(6, day: 14))
        // Now in Tokyo: the same instant reads 17:30 local, which is not a
        // morning start and must not move wake.
        let nowInTokyo = date(12, day: 14)
        XCTAssertEqual(tokyo.component(.hour, from: record.start), 17)
        XCTAssertFalse(CommitmentResolver.isStillValid(record, now: nowInTokyo, calendar: tokyo))
        // Same record, same instant, still a morning in the timezone it was
        // read in — so the rejection above is about the timezone, not about
        // the record being malformed.
        XCTAssertTrue(CommitmentResolver.isStillValid(record, now: date(12, day: 14), calendar: calendar))
    }

    /// Permission withdrawn: the reader reports `.unavailable`, the app
    /// forgets, and the manual intent is what remains.
    func testPermissionRevokedForgetsCalendarButKeepsTheManualTime() {
        let preferences = UserPreferences(defaults: makeDefaults())
        let now = date(21, day: 14)
        preferences.recordCalendarRead(
            CalendarCommitment(
                start: date(8, day: 15), durationMinutes: 30, isAllDay: false,
                source: .calendar, eventIdentifier: "event-1"
            ),
            at: now
        )
        preferences.setTomorrowEvent(date: date(9, day: 15), calendar: calendar)

        preferences.forgetCalendarCommitment()

        XCTAssertNil(preferences.calendarCommitmentRecord)
        guard case let .manual(event) = preferences.commitment(now: now, calendar: calendar) else {
            return XCTFail("expected the manual commitment to survive")
        }
        XCTAssertEqual(calendar.component(.hour, from: event.start), 9)
    }

    // MARK: - Manual and Calendar together

    /// Both are obligations. The binding one is whichever comes first.
    func testTheEarlierOfManualAndCalendarWins() {
        let now = date(21, day: 14)
        let record = stored(date(9, day: 15), fetchedAt: now)
        let outcome = CommitmentResolver.resolve(
            calendarRecord: record,
            manual: ManualCommitment(hour: 7, minute: 0),
            now: now,
            calendar: calendar
        )
        guard case let .manual(event) = outcome else { return XCTFail("expected the manual time") }
        XCTAssertEqual(calendar.component(.hour, from: event.start), 7)
    }

    func testCalendarWinsWhenItIsTheEarlierOne() {
        let now = date(21, day: 14)
        let record = stored(date(7, day: 15), fetchedAt: now)
        let outcome = CommitmentResolver.resolve(
            calendarRecord: record,
            manual: ManualCommitment(hour: 9, minute: 0),
            now: now,
            calendar: calendar
        )
        guard case let .calendar(event) = outcome else { return XCTFail("expected the calendar event") }
        XCTAssertEqual(calendar.component(.hour, from: event.start), 7)
    }

    func testNoCalendarAndNoManualIsNoCommitment() {
        XCTAssertEqual(
            CommitmentResolver.resolve(
                calendarRecord: nil, manual: nil, now: date(21, day: 14), calendar: calendar
            ),
            .noCommitment
        )
    }

    // MARK: - Persistence

    func testTheRecordSurvivesRelaunch() {
        let defaults = makeDefaults()
        let now = date(21, day: 14)
        let first = UserPreferences(defaults: defaults)
        first.recordCalendarRead(
            CalendarCommitment(
                start: date(8, day: 15, minute: 30), durationMinutes: 30, isAllDay: false,
                source: .calendar, eventIdentifier: "event-1"
            ),
            at: now
        )

        let relaunched = UserPreferences(defaults: defaults)
        XCTAssertEqual(relaunched.calendarCommitmentRecord?.start, date(8, day: 15, minute: 30))
        XCTAssertEqual(relaunched.calendarCommitmentRecord?.eventIdentifier, "event-1")
    }

    /// The Calendar record is not part of the manual settings, and erasing
    /// data must take it with everything else.
    func testDataErasureForgetsTheCalendarRecord() {
        let preferences = UserPreferences(defaults: makeDefaults())
        preferences.recordCalendarRead(
            CalendarCommitment(
                start: date(8, day: 15), durationMinutes: 30, isAllDay: false,
                source: .calendar, eventIdentifier: "event-1"
            ),
            at: date(21, day: 14)
        )
        preferences.resetForDataErasure()
        XCTAssertNil(preferences.calendarCommitmentRecord)
    }

    // MARK: - Getting-ready buffer

    func testTheReadyBufferIsAPreferenceNotAConstant() {
        let preferences = UserPreferences(defaults: makeDefaults())
        XCTAssertEqual(preferences.morningReadyBufferMinutes, ZoonTomorrow.readyBufferMinutes)
        preferences.morningReadyBufferMinutes = 25
        XCTAssertEqual(preferences.morningReadyBufferMinutes, 25)
    }

    func testWakeMovesWithTheReadyBuffer() throws {
        let now = date(21, day: 14)
        let event = ZoonTomorrow.Event(start: date(8, day: 15, minute: 30), isAllDay: false, source: .calendar)
        // No history on purpose: with an event and no autopilot plan, wake is
        // the event wake and nothing else, so this measures the buffer rather
        // than the rate limiter.
        func wakeHourMinute(buffer: Double) throws -> Int {
            let plan = try XCTUnwrap(ZoonTomorrow.plan(
                now: now,
                event: event,
                nights: [],
                planning: SleepPlanningInputs(baselineNeedMinutes: 450),
                readyBufferMinutes: buffer,
                calendar: calendar
            ))
            return calendar.component(.hour, from: plan.wake) * 60
                + calendar.component(.minute, from: plan.wake)
        }
        XCTAssertEqual(try wakeHourMinute(buffer: 50), 7 * 60 + 40)
        XCTAssertEqual(try wakeHourMinute(buffer: 20), 8 * 60 + 10)
        XCTAssertEqual(try wakeHourMinute(buffer: 0), 8 * 60 + 30)
    }

    /// An out-of-range buffer is clamped rather than producing a wake time on
    /// the wrong day.
    func testTheReadyBufferIsClamped() throws {
        let now = date(21, day: 14)
        let event = ZoonTomorrow.Event(start: date(8, day: 15, minute: 30), isAllDay: false, source: .calendar)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: event,
            nights: [],
            planning: SleepPlanningInputs(baselineNeedMinutes: 450),
            readyBufferMinutes: 10_000,
            calendar: calendar
        ))
        XCTAssertGreaterThanOrEqual(
            plan.wake,
            calendar.date(byAdding: .minute, value: -Int(ZoonTomorrow.readyBufferRange.upperBound), to: event.start)!
        )
    }

    /// The `why` line has to name where the commitment came from. It used to
    /// say "the time you asked Zoon to protect" for events Zoon had read out
    /// of someone's calendar.
    func testTheWhyLineNamesTheCalendarAsTheSource() throws {
        let now = date(21, day: 14)
        let plan = try XCTUnwrap(ZoonTomorrow.plan(
            now: now,
            event: ZoonTomorrow.Event(start: date(8, day: 15, minute: 30), isAllDay: false, source: .calendar),
            nights: [],
            planning: SleepPlanningInputs(baselineNeedMinutes: 450),
            calendar: calendar
        ))
        XCTAssertTrue(
            plan.why.contains { $0.contains("Calendar commitment") },
            "why lines were: \(plan.why)"
        )
    }
}
