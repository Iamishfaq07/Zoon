import XCTest

/// Tonight is one episode, and a bedtime that has passed stays tonight's.
final class ResolvedSleepEpisodeTests: XCTestCase {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func autopilot(bed: Double, sleep: Double = 480) -> SleepAutopilot.Plan {
        SleepAutopilot.Plan(
            targetBedtimeMinutes: bed, targetSleepMinutes: sleep, shiftMinutes: 0,
            debtRepaymentMinutes: 0, isHolding: true, confidence: .moderate
        )
    }

    // MARK: - The 23:01 defect

    /// At 23:01 for a 23:00 bedtime the next *occurrence* of 23:00 is
    /// tomorrow, and Today read "Bed in 23h 59m". The bedtime is still
    /// tonight's, overdue.
    func testOneMinutePastBedtimeIsStillTonight() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 22, 23, 1)
        let episode = ResolvedSleepEpisode.resolve(
            autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: now, calendar: cal
        )
        XCTAssertEqual(episode?.bed, date(cal, 2026, 9, 22, 23, 0))
        XCTAssertEqual(episode?.wake, date(cal, 2026, 9, 23, 7, 0))
        XCTAssertEqual(episode?.phase(at: now), .overdue)

        // And the old resolver really did say tomorrow, which is why the
        // new one exists.
        XCTAssertEqual(
            PlannedBedtimeResolver.nextOccurrence(ofMinutesFromMidnight: 23 * 60, after: now, calendar: cal),
            date(cal, 2026, 9, 23, 23, 0)
        )
        XCTAssertEqual(
            PlannedBedtimeResolver.tonightsOccurrence(
                ofMinutesFromMidnight: 23 * 60, sleepMinutes: 480, after: now, calendar: cal
            ),
            date(cal, 2026, 9, 22, 23, 0)
        )
    }

    /// After midnight, the night in progress is still tonight's. The alarm
    /// target used to be `BodyClock.window(for: .now)`, which at 02:00 is
    /// tomorrow morning.
    func testAfterMidnightTheWakeIsThisMorning() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 23, 2, 0)
        let episode = ResolvedSleepEpisode.resolve(
            autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: now, calendar: cal
        )
        XCTAssertEqual(episode?.wake, date(cal, 2026, 9, 23, 7, 0))
        XCTAssertEqual(episode?.bed, date(cal, 2026, 9, 22, 23, 0))
    }

    /// Once the wake has passed, the episode is over and the next is tonight.
    func testTheEpisodeExpiresAtItsWake() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 23, 7, 1)
        let episode = ResolvedSleepEpisode.resolve(
            autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: now, calendar: cal
        )
        XCTAssertEqual(episode?.bed, date(cal, 2026, 9, 23, 23, 0))
        XCTAssertEqual(episode?.phase(at: now), .upcoming)
    }

    func testPhasesInOrder() {
        let cal = calendar("Europe/London")
        let episode = ResolvedSleepEpisode.resolve(
            autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: date(cal, 2026, 9, 22, 12, 0), calendar: cal
        )!
        XCTAssertEqual(episode.phase(at: date(cal, 2026, 9, 22, 22, 0)), .upcoming)
        XCTAssertEqual(episode.phase(at: date(cal, 2026, 9, 22, 22, 40)), .windingDown)
        XCTAssertEqual(episode.phase(at: date(cal, 2026, 9, 23, 3, 0)), .overdue)
        XCTAssertEqual(episode.phase(at: date(cal, 2026, 9, 23, 7, 0)), .completed)
    }

    // MARK: - Clock changes and zones

    /// Spring forward in Los Angeles: the night is an hour shorter in
    /// elapsed time, and the wake is still 07:00 on the wall.
    func testLosAngelesSpringForward() {
        let cal = calendar("America/Los_Angeles")
        let now = date(cal, 2026, 3, 7, 23, 30)
        let window = ResolvedSleepEpisode.window(
            bedMinute: 23 * 60, wakeMinute: 7 * 60, containingOrAfter: now, calendar: cal
        )
        XCTAssertEqual(window?.start, date(cal, 2026, 3, 7, 23, 0))
        XCTAssertEqual(window?.end, date(cal, 2026, 3, 8, 7, 0))
        XCTAssertEqual(window?.duration, 7 * 3600, "the lost hour is lost from the night")
    }

    func testLosAngelesFallBack() {
        let cal = calendar("America/Los_Angeles")
        let now = date(cal, 2026, 10, 31, 20, 0)
        let window = ResolvedSleepEpisode.window(
            bedMinute: 23 * 60, wakeMinute: 7 * 60, containingOrAfter: now, calendar: cal
        )
        XCTAssertEqual(window?.end, date(cal, 2026, 11, 1, 7, 0))
        XCTAssertEqual(window?.duration, 9 * 3600)
        XCTAssertLessThan(window!.start, window!.end)
    }

    /// No DST, a half-hour offset: the times are the wall clock's, not
    /// UTC's with a whole-hour guess.
    func testKolkataCrossMidnight() {
        let cal = calendar("Asia/Kolkata")
        let now = date(cal, 2026, 9, 22, 23, 45)
        let window = ResolvedSleepEpisode.window(
            bedMinute: 23 * 60 + 30, wakeMinute: 6 * 60 + 30, containingOrAfter: now, calendar: cal
        )
        XCTAssertEqual(window?.start, date(cal, 2026, 9, 22, 23, 30))
        XCTAssertEqual(window?.end, date(cal, 2026, 9, 23, 6, 30))
    }

    /// A night-shift day sleep: bed 08:30, wake 16:00. Chronological, same day.
    func testDaySleepAfterANightShift() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 22, 9, 0)
        let window = ResolvedSleepEpisode.window(
            bedMinute: 8 * 60 + 30, wakeMinute: 16 * 60, containingOrAfter: now, calendar: cal
        )
        XCTAssertEqual(window?.start, date(cal, 2026, 9, 22, 8, 30))
        XCTAssertEqual(window?.end, date(cal, 2026, 9, 22, 16, 0))
    }

    // MARK: - Manual plans

    /// A manual 22:30–06:30 plan is what every surface gets: the Tonight
    /// section, the bedtime reminder and the alarm all read this value.
    func testAManualPlanWinsForTheNightItCovers() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 22, 12, 0)
        let plan = PersonalSetup.SleepPlan(
            name: "Weeknights", timeZoneIdentifier: "Europe/London",
            bedtimeMinute: 22 * 60 + 30, wakeMinute: 6 * 60 + 30,
            weekdays: [1, 2, 3, 4, 5, 6, 7], firstDate: date(cal, 2026, 9, 1, 0, 0)
        )
        let episode = ResolvedSleepEpisode.resolve(
            plans: [plan], autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: now, calendar: cal
        )
        XCTAssertEqual(episode?.source, .manualPlan)
        XCTAssertEqual(episode?.bed, date(cal, 2026, 9, 22, 22, 30))
        XCTAssertEqual(episode?.wake, date(cal, 2026, 9, 23, 6, 30))
        XCTAssertEqual(episode?.windDown, date(cal, 2026, 9, 22, 22, 0))
        XCTAssertEqual(episode?.planName, "Weeknights")
    }

    /// A Tuesday-only plan does not reach forward from Wednesday and claim
    /// next Tuesday as tonight; Wednesday is the derived night.
    func testATuesdayPlanDoesNotClaimWednesday() {
        let cal = calendar("Europe/London")
        // 2026-09-22 is a Tuesday (weekday 3).
        let tuesday = PersonalSetup.SleepPlan(
            name: "Early Tuesdays", timeZoneIdentifier: "Europe/London",
            bedtimeMinute: 21 * 60 + 30, wakeMinute: 5 * 60,
            weekdays: [3], firstDate: date(cal, 2026, 9, 1, 0, 0)
        )
        let wednesdayNoon = date(cal, 2026, 9, 23, 12, 0)
        let episode = ResolvedSleepEpisode.resolve(
            plans: [tuesday], autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: wednesdayNoon, calendar: cal
        )
        XCTAssertEqual(episode?.source, .autopilot)
        XCTAssertEqual(episode?.bed, date(cal, 2026, 9, 23, 23, 0))
    }

    /// A one-night plan applies once. The horizon holds it on its night only.
    func testAOneNightOverrideAppliesOnce() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 22, 12, 0)
        let once = PersonalSetup.SleepPlan(
            name: "Flight", timeZoneIdentifier: "Europe/London",
            bedtimeMinute: 21 * 60, wakeMinute: 4 * 60,
            weekdays: [], firstDate: date(cal, 2026, 9, 24, 0, 0)
        )
        let horizon = ResolvedSleepEpisode.horizon(
            nights: 7, plans: [once], autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60,
            needMinutes: 480, windDownLeadMinutes: 30, now: now, calendar: cal
        )
        XCTAssertEqual(horizon.count, 7)
        XCTAssertEqual(horizon.filter { $0.source == .manualPlan }.count, 1)
        XCTAssertEqual(horizon.first { $0.source == .manualPlan }?.bed, date(cal, 2026, 9, 24, 21, 0))
        // Chronological and non-overlapping.
        for (a, b) in zip(horizon, horizon.dropFirst()) {
            XCTAssertLessThanOrEqual(a.wake, b.bed)
        }
    }

    // MARK: - Feasibility

    /// A hard 06:00 wake with a 23:30 habit cannot give eight hours. The
    /// wake stays at the commitment and the shortfall is stated.
    func testAnImpossibleWakeIsCalledOutNotMoved() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 9, 22, 12, 0)
        let episode = ResolvedSleepEpisode.resolve(
            autopilot: autopilot(bed: -30, sleep: 480), usualWakeMinute: 7 * 60, needMinutes: 480,
            hardWakeMinute: 6 * 60, windDownLeadMinutes: 30, now: now, calendar: cal
        )!
        XCTAssertEqual(episode.wake, date(cal, 2026, 9, 23, 6, 0))
        XCTAssertEqual(episode.obligationWake, episode.wake)
        XCTAssertFalse(episode.isFeasible)
        XCTAssertEqual(episode.shortfallMinutes, 90, accuracy: 0.5)
    }

    /// The watch's label is the episode's own times, in the episode's zone.
    func testTheRangeLabelIsTheEpisodesTimes() throws {
        let cal = calendar("Asia/Kolkata")
        let episode = try XCTUnwrap(ResolvedSleepEpisode.resolve(
            autopilot: autopilot(bed: -60), usualWakeMinute: 7 * 60, needMinutes: 480,
            windDownLeadMinutes: 30, now: date(cal, 2026, 9, 22, 12, 0), calendar: cal
        ))
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = cal.timeZone
        XCTAssertEqual(
            episode.rangeLabel,
            "\(date(cal, 2026, 9, 22, 23, 0).formatted(style)) - \(date(cal, 2026, 9, 23, 7, 0).formatted(style))"
        )
    }

    func testNoHistoryAndNoPlanResolvesNothing() {
        let cal = calendar("Europe/London")
        XCTAssertNil(ResolvedSleepEpisode.resolve(
            autopilot: nil, usualWakeMinute: nil, needMinutes: 480,
            windDownLeadMinutes: 30, now: date(cal, 2026, 9, 22, 12, 0), calendar: cal
        ))
    }
}

/// Reminders are dated, one-off and bounded.
final class ReminderScheduleTests: XCTestCase {

    private var cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// Every request names a year, month and day. A trigger built from only
    /// hour and minute repeats daily, which is the defect.
    func testRequestsAreDated() {
        let requests = ReminderSchedule.requests(
            kind: .bedtime, fireDates: [date(22, 23, 0), date(23, 23, 0)], now: date(22, 12, 0), calendar: cal
        )
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertNotNil(request.components.year)
            XCTAssertNotNil(request.components.month)
            XCTAssertNotNil(request.components.day)
        }
        XCTAssertEqual(requests[0].components.day, 22)
        XCTAssertEqual(requests[1].components.day, 23)
    }

    /// A date already passed is not scheduled, and so is never recorded as armed.
    func testPastDatesAreDropped() {
        let requests = ReminderSchedule.requests(
            kind: .bedtime, fireDates: [date(22, 11, 0), date(22, 23, 0)], now: date(22, 12, 0), calendar: cal
        )
        XCTAssertEqual(requests.map(\.fireDate), [date(22, 23, 0)])
    }

    /// Two episodes on the same minute do not become two alerts.
    func testDuplicatesCollapse() {
        let requests = ReminderSchedule.requests(
            kind: .bedtime, fireDates: [date(22, 23, 0), date(22, 23, 0)], now: date(22, 12, 0), calendar: cal
        )
        XCTAssertEqual(requests.count, 1)
    }

    /// Bounded, and every identifier it can use is one cancel knows about --
    /// including the fixed one the repeating implementation left behind.
    func testIdentifiersAreBoundedAndCancellable() {
        let dates = (0..<20).map { date(22, 23, 0).addingTimeInterval(Double($0) * 86_400) }
        let requests = ReminderSchedule.requests(kind: .windDown, fireDates: dates, now: date(22, 12, 0), calendar: cal)
        XCTAssertEqual(requests.count, ReminderSchedule.horizonNights)
        let known = Set(ReminderSchedule.Kind.windDown.allIdentifiers)
        XCTAssertTrue(requests.allSatisfy { known.contains($0.identifier) })
        XCTAssertTrue(known.contains("zoon.reminder.winddown"), "the legacy repeating request must be cleared")
        XCTAssertTrue(ReminderSchedule.Kind.bedtime.allIdentifiers.contains("zoon.reminder.bedtime"))
        XCTAssertTrue(ReminderSchedule.Kind.wakeWindow.allIdentifiers.contains("zoon.reminder.wakewindow"))
        XCTAssertTrue(ReminderSchedule.Kind.morningBrief.allIdentifiers.contains("zoon.reminder.morningbrief"))
    }

    /// Tuesday-only: a horizon from Tuesday noon puts the plan's 21:30 on
    /// Tuesday only. No other night fires at 21:30.
    func testATuesdayPlanFiresOnTuesdayOnly() {
        let tuesday = PersonalSetup.SleepPlan(
            name: "Early Tuesdays", timeZoneIdentifier: "Europe/London",
            bedtimeMinute: 21 * 60 + 30, wakeMinute: 5 * 60,
            weekdays: [3], firstDate: date(1, 0, 0)
        )
        let episodes = ResolvedSleepEpisode.horizon(
            nights: 7, plans: [tuesday], autopilot: nil, usualWakeMinute: 7 * 60,
            needMinutes: 480, windDownLeadMinutes: 30, now: date(22, 12, 0), calendar: cal
        )
        let requests = ReminderSchedule.requests(
            kind: .bedtime, fireDates: episodes.map(\.bed), now: date(22, 12, 0), calendar: cal
        )
        let atPlanTime = requests.filter {
            $0.components.hour == 21 && $0.components.minute == 30
        }
        XCTAssertEqual(atPlanTime.map(\.components.day), [22])
    }
}
