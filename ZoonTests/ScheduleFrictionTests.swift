import XCTest

/// Why a runway night is short, not only that it is.
final class ScheduleFrictionTests: XCTestCase {

    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: hour, minute: minute))!
    }

    private func day(
        wakeSource: SleepRunway.WakeSource,
        needMinutes: Double = 480,
        opportunityMinutes: Double = 415,
        wake: Date? = nil
    ) -> SleepRunway.Day {
        SleepRunway.Day(
            date: calendar.startOfDay(for: at(7)),
            needMinutes: needMinutes,
            opportunityMinutes: opportunityMinutes,
            bedtime: at(0),
            wake: wake ?? at(7),
            wakeSource: wakeSource,
            projectedShortfallMinutes: 0
        )
    }

    // MARK: - Naming the cause

    /// The gap alone is not actionable: a meeting, a wake time the person set,
    /// and a habit that drifted late call for completely different responses,
    /// and two of the three can be changed tonight.
    func testACalendarMorningIsNamedAsTheConstraint() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar),
            firstCommitment: at(7, 30),
            calendar: calendar
        )
        XCTAssertEqual(reading.mainConstraint, .calendarEvent)
        // Not matched against a full formatted string: the time is rendered
        // in the runner's locale, and pinning "7:30 AM" would fail on a
        // 24-hour runner for a reason that has nothing to do with the code.
        let explanation = reading.explanation ?? ""
        XCTAssertTrue(explanation.hasPrefix("Early event at"), explanation)
        XCTAssertTrue(explanation.contains("7"), explanation)
    }

    /// The commitment, not the wake. Telling somebody their constraint is 6:45
    /// when the meeting is at 7:30 names the wrong thing -- the wake is the
    /// commitment minus getting-ready time.
    func testTheConstraintTimeIsTheCommitmentNotTheWake() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar, wake: at(6, 45)),
            firstCommitment: at(7, 30),
            calendar: calendar
        )
        XCTAssertEqual(reading.constraintTime, at(7, 30))
    }

    /// A shift is not "an early event". The app knows the difference and the
    /// wake source alone does not.
    func testAShiftIsNotDescribedAsAMeeting() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar),
            firstCommitment: at(5),
            isShiftWork: true,
            calendar: calendar
        )
        XCTAssertEqual(reading.mainConstraint, .shift)
        XCTAssertTrue(reading.explanation?.contains("Shift") == true, reading.explanation ?? "")
    }

    func testAWakeTimeThePersonSetIsNamedAsTheirs() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .manual, wake: at(6, 30)),
            calendar: calendar
        )
        XCTAssertEqual(reading.mainConstraint, .protectedWakeTime)
        XCTAssertTrue(reading.explanation?.contains("you set") == true, reading.explanation ?? "")
    }

    /// Nothing outside the person pinned this morning, so the shortfall comes
    /// from the other end of the night.
    func testAnUnpinnedMorningBlamesTheBedtimeNotTheMorning() {
        let reading = ScheduleFriction.read(day: day(wakeSource: .habit), calendar: calendar)
        XCTAssertEqual(reading.mainConstraint, .lateBedtimeHabit)
    }

    // MARK: - Which cause gets named

    /// The binding constraint is the one that cannot move, not whichever was
    /// computed first.
    func testTheImmovableCauseIsTheOneNamed() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar),
            firstCommitment: at(7, 30),
            readyBufferMinutes: 45,
            calendar: calendar
        )
        XCTAssertEqual(reading.mainConstraint, .calendarEvent)
        XCTAssertTrue(reading.contributors.contains(.readyBuffer))
        XCTAssertTrue(reading.contributors.contains(.lateBedtimeHabit))
    }

    /// Both ends can be wrong at once, and the bedtime is the end the reader
    /// can act on tonight. Hiding it behind the meeting would drop the only
    /// actionable contributor.
    func testAPinnedMorningStillListsTheMovableEnd() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar),
            firstCommitment: at(7, 30),
            calendar: calendar
        )
        XCTAssertTrue(reading.contributors.contains(.lateBedtimeHabit))
        XCTAssertEqual(reading.contributors.first, .calendarEvent, "ordered hardest-to-move first")
    }

    /// A buffer of zero constrains nothing, and naming it would pad the
    /// explanation with something nobody can act on.
    func testAZeroBufferIsNotAContributor() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar),
            readyBufferMinutes: 0,
            calendar: calendar
        )
        XCTAssertFalse(reading.contributors.contains(.readyBuffer))
    }

    // MARK: - Not every night is a problem

    /// A constraint on a night with no gap is a fact about the schedule, not
    /// a problem to solve, and the screen should say nothing.
    func testAnUnconstrainedNightNamesNothing() {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar, opportunityMinutes: 500),
            firstCommitment: at(7, 30),
            calendar: calendar
        )
        XCTAssertFalse(reading.isConstrained)
        XCTAssertNil(reading.mainConstraint)
        XCTAssertNil(reading.explanation)
    }

    /// The threshold is the runway's own, so the map and the bar it sits
    /// under cannot disagree about which nights are short.
    func testShortnessMatchesTheRunwaysOwnThreshold() {
        let justUnder = ScheduleFriction.read(
            day: day(wakeSource: .habit,
                     opportunityMinutes: 480 - SleepRunway.warningGapMinutes + 1),
            calendar: calendar
        )
        let justOver = ScheduleFriction.read(
            day: day(wakeSource: .habit,
                     opportunityMinutes: 480 - SleepRunway.warningGapMinutes),
            calendar: calendar
        )
        XCTAssertFalse(justUnder.isConstrained)
        XCTAssertTrue(justOver.isConstrained)
    }

    /// Times never break across a line, the same guarantee the watch needed.
    func testTheConstraintTimeCannotBreakAcrossALine() throws {
        let reading = ScheduleFriction.read(
            day: day(wakeSource: .calendar),
            firstCommitment: at(7, 30),
            calendar: calendar
        )
        // Asserted as "no ASCII space in the time", not "contains U+00A0".
        //
        // The first version demanded the non-breaking space `ClockText`
        // inserts, and failed -- because iOS's short-time formatter already
        // emits U+202F, a *narrow* no-break space, between the time and the
        // meridiem. There was no ordinary space to replace, so nothing was
        // replaced, and the string was unbreakable all along.
        //
        // The property that matters is that the time cannot break, not which
        // of the two characters achieves it. Testing for the implementation's
        // preferred character would fail on a platform that got there another
        // way, which is what happened here.
        let explanation = try XCTUnwrap(reading.explanation)
        let time = try XCTUnwrap(explanation.components(separatedBy: "at ").last)
        XCTAssertFalse(
            time.contains(" "),
            "the time can break: \(time.unicodeScalars.map { "U+\(String($0.value, radix: 16))" })"
        )
    }
}
