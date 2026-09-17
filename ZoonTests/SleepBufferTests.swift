import XCTest

/// §14. The buffer's whole value is in what it refuses to say. The arithmetic
/// is small — a night with slack has room, and thirty minutes of it is thirty
/// minutes — and the risk is entirely in the sentence wrapped around it.
final class SleepBufferTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var monday: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 9; components.day = 14
        return calendar.date(from: components)!
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: monday)!
    }

    /// One runway morning. `opportunity` is what makes a night roomy or
    /// constrained; the need is a flat eight hours throughout.
    private func runwayDay(_ offset: Int, opportunityMinutes: Double) -> SleepRunway.Day {
        let wake = day(offset).addingTimeInterval(7 * 3600)
        return SleepRunway.Day(
            date: day(offset),
            needMinutes: 480,
            opportunityMinutes: opportunityMinutes,
            bedtime: wake.addingTimeInterval(-opportunityMinutes * 60),
            wake: wake,
            wakeSource: .habit,
            projectedShortfallMinutes: 0
        )
    }

    /// A week with one short night, at `shortOffset`, and room everywhere else.
    private func runway(
        shortOffset: Int,
        shortOpportunity: Double = 400,
        roomyOpportunity: Double = 540
    ) -> SleepRunway.Plan {
        let days = (0..<7).map {
            runwayDay($0, opportunityMinutes: $0 == shortOffset ? shortOpportunity : roomyOpportunity)
        }
        return SleepRunway.Plan(
            days: days,
            firstShortDay: days.first(where: \.isShort),
            sentence: "",
            caveat: "",
            confidence: .moderate,
            usedCalendar: false
        )
    }

    // MARK: - Finding the room

    func testTheNightsOfferedAreTheOnesBeforeTheConstraint() throws {
        let plan = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 4), calendar: calendar))
        XCTAssertEqual(plan.constrainedDate, day(4))
        XCTAssertEqual(plan.suggestions.map(\.date), [day(1), day(2), day(3)])
    }

    func testAtMostThreeNightsAreOfferedHoweverFarAheadTheConstraintIs() throws {
        let plan = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 6), calendar: calendar))
        XCTAssertEqual(plan.suggestions.count, SleepBuffer.maximumNights)
        XCTAssertEqual(plan.suggestions.last?.date, day(5), "the nights nearest the constraint")
    }

    /// Tomorrow is not something to prepare for; it is tonight, and Zoon
    /// Tomorrow already owns it.
    func testAConstraintOneNightAwayIsNotABufferOpportunity() {
        XCTAssertNil(SleepBuffer.build(runway: runway(shortOffset: 1), calendar: calendar))
    }

    func testAWeekWithNoConstraintProducesNothing() {
        let days = (0..<7).map { runwayDay($0, opportunityMinutes: 540) }
        let plan = SleepRunway.Plan(
            days: days, firstShortDay: nil, sentence: "", caveat: "",
            confidence: .moderate, usedCalendar: false
        )
        XCTAssertNil(SleepBuffer.build(runway: plan, calendar: calendar))
    }

    /// Every earlier night already tight. There is no room to find, and
    /// suggesting one of them anyway would just move the shortfall.
    func testAWeekWithNoSlackAnywhereProducesNothingRatherThanMovingTheProblem() {
        let days = (0..<7).map { runwayDay($0, opportunityMinutes: $0 == 4 ? 400 : 480) }
        let plan = SleepRunway.Plan(
            days: days, firstShortDay: days.first(where: \.isShort), sentence: "",
            caveat: "", confidence: .moderate, usedCalendar: false
        )
        XCTAssertNil(SleepBuffer.build(runway: plan, calendar: calendar))
    }

    // MARK: - Conservative limits

    func testNoNightIsAskedToMoveMoreThanHalfAnHour() throws {
        // Ten hours of room on every earlier night: far more slack than the
        // cap, which is the point.
        let plan = try XCTUnwrap(
            SleepBuffer.build(
                runway: runway(shortOffset: 4, roomyOpportunity: 600), calendar: calendar
            )
        )
        for suggestion in plan.suggestions {
            XCTAssertLessThanOrEqual(
                suggestion.extensionMinutes, SleepBuffer.maximumNightlyExtensionMinutes,
                "a large abrupt bedtime shift"
            )
        }
    }

    /// A night with fifteen minutes of room is offered fifteen — not the cap.
    /// The suggestion is bounded by what is actually there.
    func testANightIsNeverOfferedMoreRoomThanItHas() throws {
        let days = (0..<7).map {
            runwayDay($0, opportunityMinutes: $0 == 4 ? 400 : ($0 == 3 ? 495 : 540))
        }
        let plan = try XCTUnwrap(
            SleepBuffer.build(
                runway: SleepRunway.Plan(
                    days: days, firstShortDay: days.first(where: \.isShort), sentence: "",
                    caveat: "", confidence: .moderate, usedCalendar: false
                ),
                calendar: calendar
            )
        )
        let wednesday = try XCTUnwrap(plan.suggestions.first { $0.date == day(3) })
        XCTAssertEqual(wednesday.extensionMinutes, 15, accuracy: 0.001)
    }

    /// Below the deadband, a suggestion is a suggestion to do nothing.
    func testANightWithFiveMinutesOfRoomIsNotOffered() throws {
        let days = (0..<7).map {
            runwayDay($0, opportunityMinutes: $0 == 4 ? 400 : ($0 == 3 ? 485 : 540))
        }
        let plan = try XCTUnwrap(
            SleepBuffer.build(
                runway: SleepRunway.Plan(
                    days: days, firstShortDay: days.first(where: \.isShort), sentence: "",
                    caveat: "", confidence: .moderate, usedCalendar: false
                ),
                calendar: calendar
            )
        )
        XCTAssertFalse(plan.suggestions.contains { $0.date == day(3) })
    }

    func testTheSuggestedBedtimeIsTheExtensionEarlier() throws {
        let plan = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 4), calendar: calendar))
        let suggestion = try XCTUnwrap(plan.suggestions.first)
        XCTAssertEqual(
            suggestion.plannedBedtime.timeIntervalSince(suggestion.suggestedBedtime) / 60,
            suggestion.extensionMinutes,
            accuracy: 0.001
        )
    }

    // MARK: - The roster

    /// A night the roster has already spoken for has no room, whatever a
    /// habitual bedtime implies.
    func testANightCoveredByAShiftIsNotOfferedAsANightWithRoom() throws {
        let plain = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 4), calendar: calendar))
        XCTAssertTrue(plain.suggestions.contains { $0.date == day(3) })

        // A shift running across Tuesday night into Wednesday morning.
        let shift = ShiftRoster.Occurrence(
            shiftID: UUID(),
            start: day(2).addingTimeInterval(22 * 3600),
            end: day(3).addingTimeInterval(6 * 3600),
            label: "Nights"
        )
        let withShift = try XCTUnwrap(
            SleepBuffer.build(
                runway: runway(shortOffset: 4), shiftOccurrences: [shift], calendar: calendar
            )
        )
        XCTAssertFalse(withShift.suggestions.contains { $0.date == day(3) })
    }

    // MARK: - What it may not say

    /// The line the whole feature turns on. "Bank", "store", "offset" and
    /// "protect" are each a physiological claim Zoon cannot support.
    func testNothingInAPlanPromisesSleepCanBeBanked() throws {
        let plan = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 4), calendar: calendar))

        // The reading sentence is swept. It is the line somebody skims, and it
        // must not contain the promise anywhere, in any form.
        for banned in ["bank", "stored", "store up", "saves you", "offset",
                       "protects you", "makes up for", "cancels"] {
            XCTAssertFalse(
                plan.sentence.lowercased().contains(banned), "\(banned) in: \(plan.sentence)"
            )
        }
        XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(plan.sentence), plan.sentence)
        XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(plan.sentence), plan.sentence)

        // The caveat is asserted rather than swept, and deliberately so: it is
        // the one line that names the claim, in order to deny it. A blanket
        // "must not contain 'protects you'" would fail on exactly the sentence
        // that makes the feature safe -- the same exemption the Awakening
        // Inspector's and the sensitivity curve's caveats carry.
        XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(plan.caveat), plan.caveat)
        XCTAssertTrue(plan.caveat.contains("not sleep saved up"), plan.caveat)
        XCTAssertTrue(plan.caveat.contains("does not claim"), plan.caveat)
    }

    func testThePlanSaysItIsExperimentalRatherThanLeavingItToTheSurface() throws {
        let plan = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 4), calendar: calendar))
        XCTAssertTrue(plan.isExperimental)
    }

    /// The sentence has to carry the constraint itself, or the suggestion
    /// arrives without the reason for it.
    func testTheSentenceNamesTheConstrainedNightAndItsOpportunity() throws {
        let plan = try XCTUnwrap(SleepBuffer.build(runway: runway(shortOffset: 4), calendar: calendar))
        XCTAssertTrue(plan.sentence.contains("Friday"), plan.sentence)
        XCTAssertTrue(plan.sentence.contains("6h 40m"), plan.sentence)
        XCTAssertTrue(plan.sentence.contains("opportunity"), plan.sentence)
    }
}
