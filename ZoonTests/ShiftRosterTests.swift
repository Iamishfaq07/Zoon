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

    // MARK: - Storage

    func testARosterSurvivesARoundTripThroughJSON() throws {
        let shift = nights(weekdays: [2, 4])
        let roster = ShiftRoster(shifts: [shift], skipped: [shift.id: [day(1)]])
        let data = try JSONEncoder().encode(roster)
        XCTAssertEqual(try JSONDecoder().decode(ShiftRoster.self, from: data), roster)
    }
}
