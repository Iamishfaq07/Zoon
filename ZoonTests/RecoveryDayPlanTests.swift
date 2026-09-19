import XCTest

/// §15. The plan is a composition, so most of what can go wrong is in what it
/// adds on top: a gate that fires on an ordinary night, a step invented for an
/// engine that said nothing, or a sentence that promises the day undoes the
/// night.
final class RecoveryDayPlanTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var bedtime: Date { Date(timeIntervalSinceReferenceDate: 800_000_000) }

    private func plan(
        light: LightCoach.Guidance? = LightCoach.Guidance(
            headline: "Get outside if you can", detail: "…", symbol: "sun.max"
        ),
        nap: NapCoach.Recommendation? = NapCoach.Recommendation(
            advice: .recommended(durationMinutes: 25), reason: "…"
        ),
        caffeineCutoff: Date? = Date(timeIntervalSinceReferenceDate: 800_000_000),
        movement: MovementContext.Snapshot? = nil,
        plannedBedtime: Date? = Date(timeIntervalSinceReferenceDate: 800_000_000)
    ) -> RecoveryDayPlan.Plan? {
        RecoveryDayPlan.build(
            reason: "About 120 minutes under what you usually need",
            light: light,
            nap: nap,
            caffeineCutoff: caffeineCutoff,
            movement: movement,
            plannedBedtime: plannedBedtime,
            calendar: calendar
        )
    }

    // MARK: - The gate

    /// A night, with everything the gate reads.
    private func night(
        asleep: Double = 450,
        inBed: Double = 480,
        wakeCount: Int = 2,
        awake: Double = 20,
        inBedIsEstimated: Bool = false,
        daysAgo: Int = 0
    ) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: daysAgo,
            timeAsleepMinutes: asleep,
            timeInBedMinutes: inBed,
            wakeCount: wakeCount,
            timeInBedIsEstimated: inBedIsEstimated,
            awakeMinutes: awake
        )
    }

    /// Ordinary recent nights, for the personal comparison.
    private func history(awake: Double = 20, count: Int = 14) -> [SleepNightFeatures] {
        (1...count).map { night(awake: awake + Double($0 % 3), daysAgo: $0) }
    }

    private func reason(
        _ subject: SleepNightFeatures,
        need: Double = 480,
        history: [SleepNightFeatures] = []
    ) -> String? {
        RecoveryDayPlan.qualifyingReason(night: subject, needMinutes: need, history: history)
    }

    func testAnOrdinaryNightGetsNoRescuePlan() {
        XCTAssertNil(reason(night(), history: history()))
    }

    func testAShortNightQualifiesAndTheReasonSaysBySoMuch() throws {
        let short = try XCTUnwrap(reason(night(asleep: 330), history: history()))
        XCTAssertTrue(short.contains("150"), short)
        XCTAssertTrue(short.contains("aiming for"), short)
    }

    // MARK: - Wake count is no longer enough on its own

    /// The audit's point, and it is right: consumer wake detection is not
    /// precise enough to hang a whole rescue day on a count. Six brief
    /// awakenings with an ordinary amount of time actually awake is a normal
    /// night that a wearable noticed a lot of.
    func testManyBriefAwakeningsAloneDoNotTriggerARecoveryDay() {
        XCTAssertNil(
            reason(night(asleep: 450, wakeCount: 8, awake: 18), history: history(awake: 20))
        )
    }

    /// Corroborated by time genuinely awake for this person, it does.
    func testManyAwakeningsWithElevatedTimeAwakeDoTrigger() throws {
        let broken = try XCTUnwrap(
            reason(night(asleep: 450, wakeCount: 8, awake: 75), history: history(awake: 20))
        )
        XCTAssertTrue(broken.contains("awakenings"), broken)
        XCTAssertTrue(broken.contains("more than your usual"), broken)
    }

    /// Personal, not absolute. Somebody who habitually spends fifty minutes
    /// awake has not had a bad night when they spend fifty-five.
    func testAHabituallyRestlessSleeperIsComparedWithThemselves() {
        XCTAssertNil(
            reason(night(asleep: 450, wakeCount: 8, awake: 55), history: history(awake: 50))
        )
    }

    /// And the same absolute number is a bad night for somebody who is
    /// usually settled.
    func testTheSameTimeAwakeTriggersForSomebodyUsuallySettled() {
        XCTAssertNotNil(
            reason(night(asleep: 450, wakeCount: 8, awake: 55), history: history(awake: 8))
        )
    }

    /// With no baseline to compare against, an absolute floor applies —
    /// never in preference to a baseline that exists.
    func testWithNoHistoryAnAbsoluteFloorApplies() {
        XCTAssertNil(reason(night(asleep: 450, wakeCount: 8, awake: 30)))
        XCTAssertNotNil(reason(night(asleep: 450, wakeCount: 8, awake: 75)))
    }

    // MARK: - Efficiency needs a measured window

    func testALowEfficiencyNightOnAMeasuredWindowQualifies() throws {
        let reason = try XCTUnwrap(
            reason(night(asleep: 460, inBed: 700, wakeCount: 3), history: history())
        )
        XCTAssertTrue(reason.contains("%"), reason)
    }

    /// Apple Watch alone never writes an in-bed sample, so the window is
    /// inferred from the sleep period and efficiency is an artefact of that
    /// inference. Firing on it would put this feature in front of exactly the
    /// users whose data is thinnest.
    func testALowEfficiencyNightOnAnInferredWindowDoesNotQualify() {
        XCTAssertNil(
            reason(
                night(asleep: 460, inBed: 700, wakeCount: 3, inBedIsEstimated: true),
                history: history()
            )
        )
    }

    /// Missing is not short.
    func testAnUnmeasuredNightDoesNotQualify() {
        XCTAssertNil(reason(night(asleep: 0, inBed: 0, wakeCount: 0, awake: 0)))
    }

    // MARK: - Composition, and only composition

    func testTheDayIsOrderedMorningAfternoonTonight() throws {
        let plan = try XCTUnwrap(plan())
        XCTAssertEqual(plan.parts, [.morning, .afternoon, .tonight])
    }

    /// An engine that said nothing contributes nothing. The alternative --
    /// filling the gap with generic advice -- is how a plan stops being this
    /// person's.
    func testAnEngineThatSaidNothingAddsNoStep() throws {
        let plan = try XCTUnwrap(plan(light: nil, caffeineCutoff: nil))
        XCTAssertTrue(plan.steps(in: .morning).isEmpty)
        XCTAssertFalse(plan.parts.contains(.morning))
        XCTAssertFalse(plan.steps.isEmpty, "the rest of the day still has steps")
    }

    func testAPlanWithNothingToSayIsNoPlan() {
        XCTAssertNil(
            plan(light: nil, nap: nil, caffeineCutoff: nil, movement: nil, plannedBedtime: nil)
        )
    }

    /// "Not this afternoon" is advice. A plan that only ever printed a nap
    /// when one was recommended would be silent on the days it matters most.
    func testAvoidingANapIsItselfAStep() throws {
        let plan = try XCTUnwrap(
            plan(nap: NapCoach.Recommendation(advice: .avoid, reason: "…"))
        )
        let afternoon = try XCTUnwrap(plan.steps(in: .afternoon).first)
        XCTAssertTrue(afternoon.text.lowercased().contains("skip"), afternoon.text)
    }

    func testARecommendedNapCarriesItsLength() throws {
        let plan = try XCTUnwrap(
            plan(nap: NapCoach.Recommendation(advice: .recommended(durationMinutes: 25), reason: "…"))
        )
        XCTAssertTrue(
            plan.steps(in: .afternoon).contains { $0.text.contains("25") },
            plan.steps(in: .afternoon).map(\.text).description
        )
    }

    /// Every step names the engine it came from, so nothing in the plan is
    /// this file's own opinion presented as a finding.
    func testEveryStepNamesItsEngine() throws {
        let plan = try XCTUnwrap(plan())
        for step in plan.steps {
            XCTAssertFalse(step.source.isEmpty, step.text)
        }
    }

    // MARK: - What it may not say

    /// The claim the brief singles out. One day does not erase sleep loss, and
    /// there is no state here called "recovered".
    func testNothingClaimsTheDayUndoesTheNight() throws {
        let plan = try XCTUnwrap(plan())
        var lines = plan.steps.map(\.text)
        lines.append(plan.reason)
        for line in lines {
            for banned in ["erase", "undo", "make up for", "fully recovered", "back to normal",
                           "cancels", "reverses"] {
                XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
            }
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
        }
        // Asserted rather than swept: the caveat is the one line that names
        // the claim in order to deny it.
        XCTAssertTrue(plan.caveat.contains("does not undo"), plan.caveat)
        XCTAssertTrue(plan.caveat.contains("not a treatment for anything"), plan.caveat)
    }

    /// No new score. The brief asks for the existing engines composed, not a
    /// rescue number summarising a day that has not happened.
    func testThePlanCarriesNoScoreOfItsOwn() throws {
        let plan = try XCTUnwrap(plan())
        let mirror = Mirror(reflecting: plan)
        for child in mirror.children {
            XCTAssertFalse(
                (child.label ?? "").lowercased().contains("score"),
                "a score appeared on the plan: \(child.label ?? "")"
            )
        }
    }
}
