import XCTest

/// Holds this session's new copy to the same standard as the engines that
/// already had a language guard.
///
/// `DiagnosticLanguageGuard` exists because a prompt instruction is a request
/// a model may or may not honour. The same argument applies to hand-written
/// copy for a different reason: a sentence that reads naturally is exactly the
/// kind that slides from "went with" to "led to" without anyone noticing, and
/// four words is all it takes to throw away the epistemic position the
/// matched-pair machinery is built to defend.
///
/// Every new planning and decomposition surface is run through it here.
final class NewSurfaceLanguageTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute)
        )!
    }

    private func check(_ text: String, _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertFalse(
            DiagnosticLanguageGuard.containsBannedLanguage(text),
            "diagnostic language: \(text)", file: file, line: line
        )
        XCTAssertFalse(
            DiagnosticLanguageGuard.overclaimsCausation(text),
            "causal overclaim: \(text)", file: file, line: line
        )
    }

    // MARK: - Opportunity and execution

    func testEveryOpportunitySentenceIsSafe() throws {
        let cases: [(inBed: Double, asleep: Double, estimated: Bool)] = [
            (415, 391, false),   // opportunity-dominant
            (485, 400, false),   // execution-dominant
            (425, 380, false),   // both
            (415, 391, true),    // refused
            (500, 470, false)    // met
        ]
        for scenario in cases {
            let night = Fixture.night(
                timeAsleepMinutes: scenario.asleep,
                timeInBedMinutes: scenario.inBed,
                timeInBedIsEstimated: scenario.estimated
            )
            let opportunity = try XCTUnwrap(
                SleepOpportunity.make(night: night, needMinutes: 465)
            )
            if let sentence = opportunity.sentence { check(sentence) }
            for row in opportunity.rows { check(row.label) }
        }
    }

    // MARK: - The runway

    func testEveryRunwaySentenceIsSafe() throws {
        let nights = (1...20).map { index in
            Fixture.night(
                timeAsleepMinutes: 450,
                timeInBedMinutes: 480,
                bedtimeHour: 23,
                wakeDay: calendar.date(byAdding: .day, value: -index, to: date(14, 12))!
            )
        }
        for commitments in [[:], [date(17, 0): date(17, 6, 30)]] as [[Date: Date]] {
            let plan = try XCTUnwrap(SleepRunway.build(
                now: date(14, 21),
                nights: nights,
                planning: SleepPlanningInputs(baselineNeedMinutes: 465),
                commitments: commitments,
                calendar: calendar
            ))
            check(plan.sentence)
            check(plan.caveat)
            for day in plan.days { check(day.wakeSource.label) }
        }
    }

    // MARK: - What if tonight

    func testEveryWhatIfSentenceIsSafe() {
        let reference = WhatIfTonight.Reference(bedtime: date(14, 23, 15), wake: date(15, 7))
        for bedtime in [date(14, 22, 15), date(14, 23, 15), date(15, 0, 30)] {
            let model = WhatIfTonight(
                bedtime: bedtime,
                wake: date(15, 7),
                needMinutes: 465,
                shortfallMinutes: 90,
                reference: reference
            )
            check(model.sentence(calendar: calendar))
            for row in model.rows(now: date(14, 20), calendar: calendar) {
                check(row.label)
                check(row.value)
            }
        }
    }

    // MARK: - Resilience by disruption type

    func testEveryResilienceSentenceIsSafe() {
        var durations = Array(repeating: 450.0, count: 28)
        for index in [5, 12, 20] { durations[index] = 300 }
        let nights = durations.enumerated().map { index, asleep in
            Fixture.night(
                timeAsleepMinutes: asleep,
                timeInBedMinutes: asleep + 25,
                bedtimeHour: 23,
                wakeDay: calendar.date(byAdding: .day, value: index - durations.count, to: date(14, 12))!
            )
        }
        for typed in SleepResilience.byDisruptionType(nights: nights, calendar: calendar) {
            check(typed.kind.label)
            check(typed.sentence)
        }
    }

    // MARK: - Long-term resilience

    func testEveryLongTermSentenceIsSafe() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        func series(_ value: (Int) -> Double) -> [LongTermResilience.Point] {
            (0..<90).map {
                LongTermResilience.Point(
                    date: calendar.date(byAdding: .day, value: -$0, to: now)!,
                    value: value($0)
                )
            }
        }
        let specs: [(LongTermResilience.Spec, (Int) -> Double)] = [
            (.restingHeartRate, { $0 < 21 ? 50 : 56 }),
            (.restingHeartRate, { $0 < 21 ? 58 : 50 }),
            (.heartRateVariability, { $0 < 14 ? 40 : 62 }),
            (.respiratoryRate, { _ in 14.4 })
        ]
        for (spec, value) in specs {
            let signal = LongTermResilience.measure(
                spec: spec, points: series(value), window: .days90, now: now, calendar: calendar
            )
            check(signal.sentence)
        }
    }

    // MARK: - The Coach's proposals

    /// A confirmation prompt is copy too, and it is the copy a person acts
    /// on rather than reads past.
    func testEveryCoachProposalIsSafe() throws {
        let utterances = [
            "Log coffee at 5.", "Start a 25 minute nap",
            "Prepare me for my 9 AM meeting tomorrow", "Set my alarm",
            "What's my recovery", "How did I sleep last night?"
        ]
        for utterance in utterances {
            let call = try XCTUnwrap(CoachToolCatalog.interpret(utterance), utterance)
            check(call.kind.summary)
            if let prompt = call.confirmationPrompt { check(prompt) }
        }
    }
}
