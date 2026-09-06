import XCTest

final class TravelPlanTests: XCTestCase {

    private let london = TimeZone(identifier: "Europe/London")!
    private let newYork = TimeZone(identifier: "America/New_York")!
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private let paris = TimeZone(identifier: "Europe/Paris")!
    private let delhi = TimeZone(identifier: "Asia/Kolkata")!
    private let auckland = TimeZone(identifier: "Pacific/Auckland")!

    /// A fixed midsummer day, so no test depends on when it is run and none
    /// straddles a daylight-saving boundary by accident.
    private func date(day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = day
        components.hour = hour
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private func trip(
        to destination: TimeZone,
        from origin: TimeZone? = nil,
        departureDay: Int = 10,
        arrivalHourUTC: Int = 18
    ) -> TravelPlan.Trip {
        TravelPlan.Trip(
            origin: origin ?? london,
            destination: destination,
            departure: date(day: departureDay, hour: 10),
            arrival: date(day: departureDay, hour: arrivalHourUTC)
        )
    }

    private func clock(
        midpoint: Double = 3.0,
        durationMinutes: Double = 480,
        nightCount: Int = 40
    ) -> BodyClock {
        BodyClock(
            midpoint: midpoint,
            spreadHours: 0.5,
            nightCount: nightCount,
            typicalDurationMinutes: durationMinutes
        )
    }

    // MARK: - The arithmetic

    func testShiftIsMeasuredAtArrivalNotNow() {
        // London is UTC+1 in July, New York UTC-4: five hours behind.
        XCTAssertEqual(TravelPlan.shiftHours(for: trip(to: newYork)), -5, accuracy: 0.01)
        // Tokyo is UTC+9: eight hours ahead of British Summer Time.
        XCTAssertEqual(TravelPlan.shiftHours(for: trip(to: tokyo)), 8, accuracy: 0.01)
    }

    /// A destination thirteen hours ahead is eleven hours behind by the
    /// clock, and a schedule should be built from the shorter description.
    func testAVeryLargeShiftWrapsToTheShorterDirection() {
        let shift = TravelPlan.shiftHours(for: trip(to: auckland))
        XCTAssertLessThanOrEqual(abs(shift), 12)
    }

    func testHalfHourZonesAreNotRounded() {
        // India is UTC+5:30 — four and a half hours ahead of London in July.
        XCTAssertEqual(TravelPlan.shiftHours(for: trip(to: delhi)), 4.5, accuracy: 0.01)
    }

    // MARK: - When there is nothing to plan

    func testAOneHourHopIsNotATimeZoneProblem() {
        XCTAssertEqual(TravelPlan.direction(for: trip(to: paris)), .negligible)
        XCTAssertNil(TravelPlan.plan(for: trip(to: paris), bodyClock: clock(), now: date(day: 1)))
    }

    /// `plan` returning nil does not on its own say *why*, so the direction
    /// is available separately for the caller to render a sentence.
    func testTheNegligibleCaseIsReportableWithoutAPlan() {
        XCTAssertEqual(TravelPlan.direction(for: trip(to: newYork)), .westward)
        XCTAssertEqual(TravelPlan.direction(for: trip(to: tokyo)), .eastward)
    }

    // MARK: - Preparation

    func testEastwardShiftsBedtimeEarlierAndWestwardLater() throws {
        let west = try XCTUnwrap(
            TravelPlan.plan(for: trip(to: newYork), bodyClock: clock(), now: date(day: 1))
        )
        let east = try XCTUnwrap(
            TravelPlan.plan(for: trip(to: tokyo), bodyClock: clock(), now: date(day: 1))
        )

        XCTAssertTrue(west.steps.contains { $0.action.contains("later") })
        XCTAssertFalse(west.steps.contains { $0.action.contains("minutes earlier") })
        XCTAssertTrue(east.steps.contains { $0.action.contains("earlier") })
        XCTAssertFalse(east.steps.contains { $0.action.contains("minutes later") })
    }

    /// The bug this cap exists for. Four days westward at an hour a day is
    /// four hours of accumulated shift, which asks someone to go to bed at
    /// three in the morning the night before their flight.
    func testPreparationNeverAsksForMoreShiftThanTheCap() throws {
        for destination in [newYork, tokyo, auckland, delhi] {
            let plan = try XCTUnwrap(TravelPlan.plan(
                for: trip(to: destination), bodyClock: clock(), now: date(day: 1)
            ))
            let total = Double(plan.preparationDays)
                * (plan.direction == .eastward
                   ? TravelPlan.advanceMinutesPerDay : TravelPlan.delayMinutesPerDay)
            XCTAssertLessThanOrEqual(
                total, TravelPlan.maximumTotalShiftMinutes,
                "\(destination.identifier) asked for \(total) minutes of pre-trip shift"
            )
        }
    }

    func testPreparationIsLimitedByHowLongThereIsBeforeTakeoff() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo, departureDay: 3), bodyClock: clock(), now: date(day: 2)
        ))
        XCTAssertEqual(plan.preparationDays, 1)
    }

    func testATripLeavingTodayGetsNoPreparationSteps() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo, departureDay: 10), bodyClock: clock(), now: date(day: 10)
        ))
        XCTAssertEqual(plan.preparationDays, 0)
        XCTAssertFalse(plan.steps.contains {
            if case .before = $0.phase { return true }
            return false
        })
        // The flight and destination steps still apply — the trip is still
        // happening.
        XCTAssertEqual(plan.steps.count, 2)
    }

    /// A small shift should not be handed a four-day preparation schedule.
    func testASmallShiftAsksForFewerDaysThanALargeOne() throws {
        let small = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: delhi), bodyClock: clock(), now: date(day: 1)
        ))
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(), now: date(day: 1)
        ))
        XCTAssertLessThanOrEqual(small.preparationDays, plan.preparationDays)
    }

    // MARK: - What it refuses to claim

    func testLightGuidanceIsWithheldNearTheAntipode() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: auckland), bodyClock: clock(), now: date(day: 1)
        ))
        XCTAssertTrue(plan.lightGuidanceWithheld)
        XCTAssertNotNil(plan.lightCaveat)

        let destination = try XCTUnwrap(plan.steps.last)
        XCTAssertFalse(destination.action.lowercased().contains("light"),
                       "gave light advice it said it was withholding")
    }

    /// Withholding light advice must not withhold the schedule: the sleep
    /// steps are arithmetic, not biology, and they still stand.
    func testTheSleepScheduleSurvivesWhenLightGuidanceDoesNot() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: auckland), bodyClock: clock(), now: date(day: 1)
        ))
        XCTAssertTrue(plan.lightGuidanceWithheld)
        XCTAssertGreaterThan(plan.preparationDays, 0)
    }

    func testAModerateShiftDoesGetLightGuidance() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: newYork), bodyClock: clock(), now: date(day: 1)
        ))
        XCTAssertFalse(plan.lightGuidanceWithheld)
        XCTAssertNil(plan.lightCaveat)
        XCTAssertTrue(try XCTUnwrap(plan.steps.last).action.lowercased().contains("light"))
    }

    func testEveryPlanCarriesTheRuleOfThumbCaveat() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(), now: date(day: 1)
        ))
        XCTAssertTrue(plan.rateCaveat.contains("not a measurement"))
    }

    func testAPlanBuiltOnAnEstimatedBodyClockSaysSo() throws {
        let learning = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo),
            bodyClock: clock(nightCount: BodyClock.minimumNights - 1),
            now: date(day: 1)
        ))
        let settled = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(nightCount: 90), now: date(day: 1)
        ))

        XCTAssertTrue(learning.anchoredToEstimate)
        XCTAssertNotNil(learning.estimateCaveat)
        XCTAssertFalse(settled.anchoredToEstimate)
        XCTAssertNil(settled.estimateCaveat)
    }

    // MARK: - The flight

    func testLandingInTheMorningMeansSleepingOnTheFlight() throws {
        // 22:00 UTC into Tokyo is 07:00 the next morning, local.
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo, arrivalHourUTC: 22), bodyClock: clock(), now: date(day: 1)
        ))
        let flight = try XCTUnwrap(plan.steps.first { $0.phase == .flight })
        XCTAssertTrue(flight.action.contains("Sleep as much of the flight"))
    }

    func testLandingInTheAfternoonMeansStayingAwake() throws {
        // 12:00 UTC into New York is 08:00 local — but 18:00 UTC is 14:00.
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: newYork, arrivalHourUTC: 18), bodyClock: clock(), now: date(day: 1)
        ))
        let flight = try XCTUnwrap(plan.steps.first { $0.phase == .flight })
        XCTAssertTrue(flight.action.contains("Stay awake"))
    }

    // MARK: - Simple and detailed

    func testTheSimplePlanSummarisesRatherThanTruncates() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(), now: date(day: 1)
        ))

        XCTAssertGreaterThan(plan.preparationDays, 1)
        XCTAssertEqual(plan.simpleSteps.count, 3, "before, flight, destination")
        XCTAssertLessThan(plan.simpleSteps.count, plan.steps.count)

        // The collapsed line must say how many days, or it has thrown the
        // schedule away rather than summarised it.
        let before = try XCTUnwrap(plan.simpleSteps.first)
        XCTAssertTrue(before.action.contains("\(plan.preparationDays) days"))
    }

    func testTheSimplePlanKeepsTheFlightAndDestinationStepsVerbatim() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(), now: date(day: 1)
        ))
        XCTAssertEqual(
            plan.simpleSteps.filter { $0.phase != .flight && $0.phase != .destination }.count, 1
        )
        XCTAssertEqual(plan.steps.last, plan.simpleSteps.last)
    }

    func testWithNoPreparationTheSimplePlanIsJustTheFlightAndDestination() throws {
        let plan = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo, departureDay: 10), bodyClock: clock(), now: date(day: 10)
        ))
        XCTAssertEqual(plan.simpleSteps.count, 2)
    }

    // MARK: - Anchoring

    /// The plan must be expressed relative to the person's own bedtime, not
    /// a generic one, or Body Clock and Travel Mode show different times for
    /// the same night.
    func testStepsAreAnchoredToTheMeasuredBedtime() throws {
        let early = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(midpoint: 1.0), now: date(day: 1)
        ))
        let late = try XCTUnwrap(TravelPlan.plan(
            for: trip(to: tokyo), bodyClock: clock(midpoint: 5.0), now: date(day: 1)
        ))
        XCTAssertNotEqual(early.steps.first?.action, late.steps.first?.action)
    }
}
