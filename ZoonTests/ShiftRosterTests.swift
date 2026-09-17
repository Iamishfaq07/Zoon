import XCTest

/// The roster is a rule, not a list of dates, so most of what can go wrong is
/// in expanding it: the day a repeating shift lands on, the shift that crosses
/// midnight, the one that was cancelled, and the entry that is a typo rather
/// than a shift.
final class ShiftRosterTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Monday 14 September 2026.
    private var monday: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 14
        return calendar.date(from: components)!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    private func week(from offset: Int = 0, days: Int = 7) -> DateInterval {
        DateInterval(start: day(offset), end: day(offset + days))
    }

    private func nights(weekdays: Set<Int>, startMinutes: Int = 22 * 60, hours: Int = 8) -> ShiftRoster.Shift {
        ShiftRoster.Shift(
            startMinutes: startMinutes,
            durationMinutes: hours * 60,
            weekdays: weekdays,
            label: "Nights"
        )
    }

    // MARK: - Expanding the rule

    func testARepeatingShiftProducesOneOccurrencePerMatchingWeekday() {
        // Monday through Thursday. Gregorian weekday numbers: Sunday is 1.
        let roster = ShiftRoster(shifts: [nights(weekdays: [2, 3, 4, 5])])
        let occurrences = roster.occurrences(in: week(), calendar: calendar)
        XCTAssertEqual(occurrences.count, 4)
        XCTAssertEqual(
            occurrences.map { calendar.component(.weekday, from: $0.start) },
            [2, 3, 4, 5]
        )
    }

    func testAOneOffShiftHappensOnceAndOnlyOnItsOwnDay() {
        let shift = ShiftRoster.Shift(
            startMinutes: 9 * 60, durationMinutes: 8 * 60, date: day(2)
        )
        let occurrences = ShiftRoster(shifts: [shift]).occurrences(in: week(), calendar: calendar)
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.start, day(2).addingTimeInterval(9 * 3600))
    }

    /// A start plus a duration, never a start and an end that run backwards.
    func testAShiftCrossingMidnightEndsOnTheFollowingDay() throws {
        let roster = ShiftRoster(shifts: [nights(weekdays: [2])])
        let shift = try XCTUnwrap(roster.occurrences(in: week(), calendar: calendar).first)
        XCTAssertEqual(shift.start, day(0).addingTimeInterval(22 * 3600))
        XCTAssertEqual(shift.end, day(1).addingTimeInterval(6 * 3600))
        XCTAssertEqual(shift.durationMinutes, 480)
    }

    /// Keyed on the start: a night shift that began yesterday belongs to
    /// yesterday, which is how the person who worked it thinks of it, and
    /// counting it under both days would build two plans around one shift.
    func testAnOccurrenceBelongsToTheDayItStartsOn() {
        let roster = ShiftRoster(shifts: [nights(weekdays: [2])])
        // A window opening on Tuesday, while Monday night's shift is still
        // running.
        let tuesdayOnly = DateInterval(start: day(1), end: day(2))
        XCTAssertTrue(roster.occurrences(in: tuesdayOnly, calendar: calendar).isEmpty)
    }

    /// The expansion walks back a day before the window opens, so a shift
    /// starting at 22:00 is still found when the window itself opens at 20:00.
    func testAWindowOpeningMidEveningStillFindsThatEveningsShift() {
        let roster = ShiftRoster(shifts: [nights(weekdays: [2])])
        let evening = DateInterval(
            start: day(0).addingTimeInterval(20 * 3600),
            end: day(1)
        )
        XCTAssertEqual(roster.occurrences(in: evening, calendar: calendar).count, 1)
    }

    // MARK: - Cancelling

    func testSkippingOneNightLeavesTheRestOfThePatternAlone() {
        let shift = nights(weekdays: [2, 3, 4, 5])
        let roster = ShiftRoster(shifts: [shift], skipped: [shift.id: [day(1)]])
        let occurrences = roster.occurrences(in: week(), calendar: calendar)
        XCTAssertEqual(occurrences.count, 3)
        XCTAssertFalse(occurrences.contains { calendar.isDate($0.start, inSameDayAs: day(1)) })
    }

    func testASkipOnOneShiftDoesNotCancelAnother() {
        let a = nights(weekdays: [2])
        let b = nights(weekdays: [2], startMinutes: 8 * 60)
        let roster = ShiftRoster(shifts: [a, b], skipped: [a.id: [day(0)]])
        let occurrences = roster.occurrences(in: week(), calendar: calendar)
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences.first?.shiftID, b.id)
    }

    // MARK: - Refusing an entry that is not a shift

    func testAShiftLongerThanSixteenHoursIsNotExpanded() {
        let roster = ShiftRoster(shifts: [nights(weekdays: [2], hours: 20)])
        XCTAssertTrue(roster.occurrences(in: week(), calendar: calendar).isEmpty)
    }

    func testATwoMinuteShiftIsNotExpanded() {
        let shift = ShiftRoster.Shift(startMinutes: 9 * 60, durationMinutes: 2, weekdays: [2])
        XCTAssertTrue(ShiftRoster(shifts: [shift]).occurrences(in: week(), calendar: calendar).isEmpty)
    }

    /// Neither repeating nor dated is not a shift, and silently treating it as
    /// "every day" would fill the horizon with something nobody entered.
    func testAShiftWithNoWeekdaysAndNoDateNeverHappens() {
        let shift = ShiftRoster.Shift(startMinutes: 9 * 60, durationMinutes: 8 * 60)
        XCTAssertTrue(ShiftRoster(shifts: [shift]).occurrences(in: week(), calendar: calendar).isEmpty)
    }

    // MARK: - Finding the next one

    func testNextReturnsTheSoonestUpcomingShift() throws {
        let roster = ShiftRoster(shifts: [nights(weekdays: [2, 5])])
        let next = try XCTUnwrap(
            roster.next(after: day(0).addingTimeInterval(9 * 3600), calendar: calendar)
        )
        XCTAssertEqual(next.start, day(0).addingTimeInterval(22 * 3600))
    }

    func testNextSkipsAShiftThatHasAlreadyStarted() throws {
        let roster = ShiftRoster(shifts: [nights(weekdays: [2, 5])])
        let next = try XCTUnwrap(
            roster.next(after: day(0).addingTimeInterval(23 * 3600), calendar: calendar)
        )
        XCTAssertEqual(next.start, day(3).addingTimeInterval(22 * 3600))
    }

    func testAnEmptyRosterHasNoNextShift() {
        XCTAssertNil(ShiftRoster().next(after: monday, calendar: calendar))
    }

    // MARK: - The horizon is days, not seconds (§11)

    /// London's clocks go forward at 01:00 on 29 March 2026, so the week
    /// containing it is 167 hours long, not 168. Seven times 86,400 seconds
    /// stops an hour short of the seventh day's end.
    func testAWeekAcrossASpringForwardIsStillSevenCalendarDays() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var components = DateComponents()
        components.year = 2026; components.month = 3; components.day = 26
        components.hour = 20
        let start = london.date(from: components)!

        let horizon = ShiftRoster.horizon(days: 7, from: start, calendar: london)
        XCTAssertEqual(horizon.duration / 3600, 167, accuracy: 0.001)
        XCTAssertEqual(london.component(.hour, from: horizon.end), 20,
                       "the horizon ended at a different time of day than it began")
        XCTAssertNotEqual(horizon.end, start.addingTimeInterval(7 * 86_400))
    }

    /// And the other way: the week containing 25 October 2026 is 169 hours.
    func testAWeekAcrossAFallBackIsStillSevenCalendarDays() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 22
        components.hour = 20
        let start = london.date(from: components)!

        let horizon = ShiftRoster.horizon(days: 7, from: start, calendar: london)
        XCTAssertEqual(horizon.duration / 3600, 169, accuracy: 0.001)
        XCTAssertEqual(london.component(.hour, from: horizon.end), 20)
    }

    /// The hour is not an abstraction: it is a shift the planner either shows
    /// or does not.
    ///
    /// Seven calendar days from Thursday evening reaches the following
    /// Thursday evening, and a nightly 22:00 shift occurs seven times in it.
    /// A 604,800-second window spans *more* than seven local days when one of
    /// them is short, so it reaches into an eighth evening and the "next 7
    /// days" plan quietly contains eight shifts.
    func testTheSecondsFormReachesPastTheSeventhDayAcrossASpringForward() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 26
        components.hour = 21
        components.minute = 30
        let start = london.date(from: components)!

        let roster = ShiftRoster(shifts: [nights(weekdays: [1, 2, 3, 4, 5, 6, 7])])
        let honest = roster.occurrences(
            in: ShiftRoster.horizon(days: 7, from: start, calendar: london), calendar: london
        )
        let seconds = roster.occurrences(
            in: DateInterval(start: start, duration: 7 * 86_400), calendar: london
        )
        XCTAssertEqual(honest.count, 7, "seven calendar days hold seven nightly shifts")
        XCTAssertEqual(seconds.count, 8, "the seconds form reached into an eighth evening")
    }

    /// In autumn it runs the other way: 604,800 seconds stop an hour short of
    /// the seventh evening, and that night's shift disappears from the plan.
    func testTheSecondsFormLosesTheSeventhDayAcrossAFallBack() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 22
        components.hour = 22
        components.minute = 30
        let start = london.date(from: components)!

        let roster = ShiftRoster(shifts: [nights(weekdays: [1, 2, 3, 4, 5, 6, 7])])
        let honest = roster.occurrences(
            in: ShiftRoster.horizon(days: 7, from: start, calendar: london), calendar: london
        )
        let seconds = roster.occurrences(
            in: DateInterval(start: start, duration: 7 * 86_400), calendar: london
        )
        XCTAssertEqual(honest.count, 7)
        XCTAssertEqual(seconds.count, 6, "the seconds form stopped short of the seventh evening")
    }

    func testAZeroDayHorizonIsEmptyRatherThanBackwards() {
        let horizon = ShiftRoster.horizon(days: 0, from: monday, calendar: calendar)
        XCTAssertEqual(horizon.duration, 0)
        XCTAssertTrue(ShiftRoster(shifts: [nights(weekdays: [2])])
            .occurrences(in: horizon, calendar: calendar).isEmpty)
    }

    // MARK: - Storage

    func testARosterSurvivesARoundTripThroughJSON() throws {
        let shift = nights(weekdays: [2, 4])
        let roster = ShiftRoster(shifts: [shift], skipped: [shift.id: [day(1)]])
        let data = try JSONEncoder().encode(roster)
        XCTAssertEqual(try JSONDecoder().decode(ShiftRoster.self, from: data), roster)
    }
}
