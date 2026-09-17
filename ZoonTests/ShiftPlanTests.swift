import XCTest

/// The planner's job is to place windows around a shift and to refuse to say
/// anything about whether somebody should be working it. Both halves are
/// tested here: the arithmetic of the windows, and the positioning the brief
/// rules out.
final class ShiftPlanTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday 14 September 2026, midnight UTC.
    private var monday: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 14
        return calendar.date(from: components)!
    }

    private func at(_ hours: Double, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: monday)!
            .addingTimeInterval(hours * 3600)
    }

    private func shift(from startHour: Double, hours: Double, dayOffset: Int = 0) -> ShiftRoster.Occurrence {
        let start = at(startHour, dayOffset: dayOffset)
        return ShiftRoster.Occurrence(
            shiftID: UUID(),
            start: start,
            end: start.addingTimeInterval(hours * 3600),
            label: "Nights"
        )
    }

    /// A habit built through `Fixture.night`, so the planner is exercised
    /// against the same type the runway uses rather than a stub of it. Only
    /// the overall medians matter here, so the nights' own dates do not.
    private func habit(bedHour: Int, wakeHour: Int) -> SleepRunway.Habit {
        let inBedMinutes = Double((wakeHour - bedHour + 24) % 24) * 60
        let nights = (1...14).map {
            Fixture.night(
                daysAgo: $0,
                timeInBedMinutes: inBedMinutes,
                bedtimeHour: bedHour,
                timeZoneIdentifier: "UTC"
            )
        }
        return SleepRunway.Habit(nights: nights, calendar: calendar)
    }

    /// The default schedule the app already uses: 50 minutes getting ready,
    /// 30 each way.
    private func plan(
        _ occurrence: ShiftRoster.Occurrence,
        next: ShiftRoster.Occurrence? = nil,
        now: Date,
        bedHour: Int = 23,
        wakeHour: Int = 7,
        need: Double = 480
    ) -> ShiftPlan.Plan? {
        ShiftPlan.make(
            shift: occurrence,
            nextShift: next,
            sleepNeedMinutes: need,
            habit: habit(bedHour: bedHour, wakeHour: wakeHour),
            now: now,
            calendar: calendar
        )
    }

    private func window(_ plan: ShiftPlan.Plan, _ role: ShiftPlan.Window.Role) -> ShiftPlan.Window? {
        plan.windows.first { $0.role == role }
    }

    // MARK: - Classifying against this person's own sleep

    func testAShiftThatCoversMostOfTheUsualSleepWindowDisplacesIt() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(9)))
        XCTAssertEqual(plan.kind, .displacesSleep)
    }

    func testAShiftInsideTheWakingDayIsOrdinary() throws {
        let plan = try XCTUnwrap(plan(shift(from: 9, hours: 8), now: at(7)))
        XCTAssertEqual(plan.kind, .ordinary)
    }

    /// The same two clock times, two different schedules. This is the case a
    /// fixed "night shift starts after 20:00" rule gets wrong, and it is
    /// exactly the population this feature exists for.
    func testTheSameEveningShiftDisplacesOneSleeperAndNotAnother() throws {
        let evening = shift(from: 18, hours: 8)
        let earlySleeper = try XCTUnwrap(plan(evening, now: at(9), bedHour: 23, wakeHour: 7))
        let lateSleeper = try XCTUnwrap(plan(evening, now: at(9), bedHour: 3, wakeHour: 11))
        XCTAssertEqual(earlySleeper.kind, .displacesSleep)
        XCTAssertEqual(lateSleeper.kind, .ordinary)
    }

    /// An hour off the end of a night is a moved wake time, which the runway
    /// and the single-night plan already handle. Two plans for one night is
    /// two answers to one question.
    func testAnEarlyStartThatClipsOneHourIsStillOrdinary() throws {
        let plan = try XCTUnwrap(plan(shift(from: 6, hours: 8), now: at(-4)))
        XCTAssertEqual(plan.kind, .ordinary)
    }

    func testAnOrdinaryShiftPlacesNoSleepWindowsAndNoCaffeineTime() throws {
        let plan = try XCTUnwrap(plan(shift(from: 9, hours: 8), now: at(7)))
        XCTAssertEqual(plan.windows.map(\.role), [.shift])
        XCTAssertNil(plan.caffeineCutoff)
        XCTAssertEqual(plan.shortfallMinutes, 0)
    }

    // MARK: - Where the sleep goes

    func testWithAWholeDayAheadTheSleepFitsBeforeTheShift() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(9)))
        let before = try XCTUnwrap(window(plan, .preShiftSleep))
        // 22:00 less 50 minutes getting ready and a 30-minute commute.
        XCTAssertEqual(before.end, at(20.0 + 40.0 / 60.0))
        XCTAssertEqual(before.minutes, 480, accuracy: 0.001)
        XCTAssertEqual(plan.shortfallMinutes, 0)
    }

    /// The shape this schedule actually has. Half the need before the shift
    /// and the rest after is a split night, not a failure.
    func testAnAfternoonStartSplitsTheSleepEitherSideOfTheShift() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(16)))
        let before = try XCTUnwrap(window(plan, .preShiftSleep))
        let after = try XCTUnwrap(window(plan, .postShiftSleep))
        XCTAssertEqual(before.minutes, 280, accuracy: 0.001)
        XCTAssertEqual(after.minutes, 200, accuracy: 0.001)
        XCTAssertEqual(plan.sleepOpportunityMinutes, 480, accuracy: 0.001)
        XCTAssertEqual(plan.shortfallMinutes, 0)
        // Home at 06:00 plus the commute plus winding down.
        XCTAssertEqual(after.start, at(6.0 + 70.0 / 60.0, dayOffset: 1))
    }

    /// Forty minutes on a sofa is not "sleep before your shift", and labelling
    /// it as such is the kind of thing somebody would act on.
    func testAWindowShorterThanOneSleepCycleIsNotCalledSleep() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(20)))
        XCTAssertNil(window(plan, .preShiftSleep))
        XCTAssertNotNil(window(plan, .postShiftSleep))
    }

    func testTheWakeTargetIsTheEndOfTheLastSleepWindow() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(16)))
        XCTAssertEqual(plan.wakeTarget, window(plan, .postShiftSleep)?.end)
    }

    func testNoWindowIsEverDrawnInThePast() throws {
        let now = at(16)
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: now))
        for window in plan.windows where window.role != .shift {
            XCTAssertGreaterThanOrEqual(window.start, now, window.title)
        }
    }

    // MARK: - The nap

    /// A nap is what is left when the shift starts too soon to sleep properly
    /// first — never an extra window alongside one that already runs up to
    /// leaving, which would propose the same minutes twice.
    func testTheNapIsNotOfferedAlongsideASleepWindowBefore() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(16)))
        XCTAssertNotNil(window(plan, .preShiftSleep))
        XCTAssertNil(plan.napWindow)
    }

    /// What is left before a shift, when it is less than a sleep cycle, is a
    /// nap and is named one. Forty minutes is available at 20:00; the window
    /// is capped at thirty and runs up to leaving.
    func testWhatIsLeftBeforeAShiftIsCalledANapRatherThanSleep() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(20)))
        let nap = try XCTUnwrap(plan.napWindow)
        XCTAssertNil(window(plan, .preShiftSleep))
        XCTAssertEqual(nap.minutes, ShiftPlan.maximumNapMinutes, accuracy: 0.001)
        XCTAssertEqual(nap.end, at(20.0 + 40.0 / 60.0))
    }

    /// Ten minutes is not a nap either. Below the threshold the plan says
    /// nothing about the time before the shift rather than proposing it.
    func testTooLittleTimeForEvenANapProposesNothingBeforeTheShift() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(20.5)))
        XCTAssertNil(plan.napWindow)
        XCTAssertNil(window(plan, .preShiftSleep))
    }

    func testANapCountsTowardsTheOpportunityItActuallyIs() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(20)))
        let after = try XCTUnwrap(window(plan, .postShiftSleep))
        XCTAssertEqual(after.minutes, 450, accuracy: 0.001)
        XCTAssertEqual(plan.sleepOpportunityMinutes, 480, accuracy: 0.001)
    }

    // MARK: - Caffeine

    /// The point of the whole feature in one figure: for a night shift the
    /// cutoff falls in the middle of the shift, which is not a time anyone
    /// would arrive at on their own.
    func testTheCaffeineCutoffIsMeasuredAgainstTheSleepThatFollowsTheShift() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(16)))
        let after = try XCTUnwrap(window(plan, .postShiftSleep))
        XCTAssertEqual(plan.caffeineCutoff, after.start.addingTimeInterval(-8 * 3600))
        // 07:10 the next morning, less eight hours: 23:10, mid-shift.
        XCTAssertEqual(plan.caffeineCutoff, at(23.0 + 10.0 / 60.0))
    }

    /// `CaffeineCutoff` already refuses to show a time long past. A plan built
    /// in the morning for a window tomorrow afternoon must not print a cutoff
    /// that was this morning.
    func testACutoffWellInThePastIsNotShown() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(9)))
        XCTAssertNil(plan.caffeineCutoff)
    }

    // MARK: - Refusals

    func testNoHabitMeansNoPlanRatherThanAClockGuess() {
        XCTAssertNil(
            ShiftPlan.make(
                shift: shift(from: 22, hours: 8),
                sleepNeedMinutes: 480,
                habit: SleepRunway.Habit(nights: [], calendar: calendar),
                now: at(9),
                calendar: calendar
            )
        )
    }

    func testNoSleepNeedMeansNoPlan() {
        XCTAssertNil(plan(shift(from: 22, hours: 8), now: at(9), need: 0))
    }

    // MARK: - Positioning

    /// The single thing the brief rules out: this must not read as a judgement
    /// about whether somebody should be working the shift.
    func testNothingThePlanSaysIsAnOccupationalHealthJudgement() throws {
        let cases: [(Double, Double, Date)] = [
            (22, 8, at(9)), (22, 8, at(16)), (22, 8, at(20)),
            (9, 8, at(7)), (18, 8, at(9)), (0, 8, at(12))
        ]
        for (start, hours, now) in cases {
            let plan = try XCTUnwrap(plan(shift(from: start, hours: hours), now: now))
            for line in [plan.sentence, plan.caveat, plan.kind.label] {
                XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
                XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
                for banned in ShiftPlan.bannedPositioning {
                    XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
                }
            }
        }
    }

    func testTheCaveatSaysItIsScheduleSupport() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(16)))
        XCTAssertTrue(plan.caveat.contains("Schedule support"), plan.caveat)
        XCTAssertTrue(plan.caveat.contains("not a forecast"), plan.caveat)
    }

    /// Opportunity is a ceiling. The sentence must not promise the sleep will
    /// happen, only that the schedule leaves room for it.
    func testTheSentenceTalksAboutRoomRatherThanSleepAchieved() throws {
        let plan = try XCTUnwrap(plan(shift(from: 22, hours: 8), now: at(16)))
        XCTAssertTrue(plan.sentence.contains("leaves room for"), plan.sentence)
    }

    /// A single shift leaves an unbounded window behind it, so its shortfall
    /// is genuinely zero. Back-to-back nights are what squeeze it, and that is
    /// the case a roster exists to show.
    func testOneShiftOnItsOwnLeavesNoShortfall() throws {
        let plan = try XCTUnwrap(plan(shift(from: 19, hours: 12), now: at(18), need: 600))
        XCTAssertFalse(plan.isShort)
        XCTAssertEqual(plan.shortfallMinutes, 0)
    }

    func testBackToBackNightsSqueezeTheWindowBetweenThem() throws {
        // 19:00–07:00 tonight and again tomorrow. Home at 08:10, and leaving
        // again at 17:40: nine and a half hours for a ten-hour need.
        let tonight = shift(from: 19, hours: 12)
        let tomorrow = shift(from: 19, hours: 12, dayOffset: 1)
        let plan = try XCTUnwrap(plan(tonight, next: tomorrow, now: at(18), need: 600))
        let after = try XCTUnwrap(window(plan, .postShiftSleep))
        XCTAssertEqual(after.start, at(8.0 + 10.0 / 60.0, dayOffset: 1))
        XCTAssertEqual(after.end, at(17.0 + 40.0 / 60.0, dayOffset: 1))
        XCTAssertEqual(plan.shortfallMinutes, 30, accuracy: 0.001)
        XCTAssertTrue(plan.isShort)
        XCTAssertTrue(plan.sentence.contains("short of"), plan.sentence)
    }
}
