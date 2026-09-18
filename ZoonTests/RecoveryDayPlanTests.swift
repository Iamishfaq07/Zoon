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

    func testAnOrdinaryNightGetsNoRescuePlan() {
        XCTAssertNil(
            RecoveryDayPlan.qualifyingReason(
                asleepMinutes: 450, needMinutes: 480, wakeCount: 2, efficiencyPercent: 94
            )
        )
    }

    func testAShortNightQualifiesAndTheReasonSaysBySoMuch() throws {
        let reason = try XCTUnwrap(
            RecoveryDayPlan.qualifyingReason(
                asleepMinutes: 330, needMinutes: 480, wakeCount: 2, efficiencyPercent: 94
            )
        )
        XCTAssertTrue(reason.contains("150"), reason)
    }

    /// The other way a night goes wrong. Seven hours in six pieces is not
    /// seven hours, and a gate keyed only on duration would have nothing to
    /// say to somebody who slept the whole night badly.
    func testALongButBrokenNightQualifiesOnItsAwakenings() throws {
        let reason = try XCTUnwrap(
            RecoveryDayPlan.qualifyingReason(
                asleepMinutes: 470, needMinutes: 480, wakeCount: 8, efficiencyPercent: 88
            )
        )
        XCTAssertTrue(reason.contains("awakenings"), reason)
        XCTAssertTrue(reason.contains("continuity"), reason)
    }

    func testAnEfficientlySpentNightThatWasMostlyAwakeQualifies() throws {
        let reason = try XCTUnwrap(
            RecoveryDayPlan.qualifyingReason(
                asleepMinutes: 460, needMinutes: 480, wakeCount: 3, efficiencyPercent: 62
            )
        )
        XCTAssertTrue(reason.contains("62%"), reason)
    }

    /// Missing is not short. A night Zoon did not measure is not a night to
    /// put a rescue plan in front of somebody for.
    func testAnUnmeasuredNightDoesNotQualify() {
        XCTAssertNil(
            RecoveryDayPlan.qualifyingReason(
                asleepMinutes: nil, needMinutes: 480, wakeCount: nil, efficiencyPercent: nil
            )
        )
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
