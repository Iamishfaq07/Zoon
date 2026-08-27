import XCTest

/// The semantics of the three-state behaviour evidence model.
///
/// This file exists because the model it replaced inferred a confident "did
/// not happen" from the existence of a `JournalEntry` row --- and
/// `JournalStore.entryOrCreate` writes one the moment the journal screen
/// renders a day. Opening the screen therefore manufactured negative
/// evidence for all twenty-three behaviours, and those fabricated negatives
/// became the control arm of every matched-pair comparison in
/// `JournalCorrelator`.
///
/// Two tests in `JournalCorrelatorTests` used to assert exactly that
/// behaviour (`testJournaledNightWithoutTagIsNo`,
/// `testJournaledNightWithNoTagsIsNoNotUnknown`). They have been replaced by
/// their inverses below, because they were pinning down the defect.
final class BehaviorEvidenceTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var anchor: Date {
        calendar.date(from: DateComponents(year: 2024, month: 6, day: 1))!
    }

    private func observation(
        daysAgo: Int,
        tags: Set<BehaviorTag> = [],
        answers: BehaviorAnswers = .none,
        sleepPerformance: Double? = 80,
        isWeekend: Bool = false,
        sleepDebtMinutes: Double? = 30,
        bedtimeHour: Double? = -1,
        alcoholicBeverages: Double? = nil,
        lateCaffeineMg: Double? = nil,
        measuredTimeZoneShift: Bool = false
    ) -> JournalCorrelator.Observation {
        JournalCorrelator.Observation(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: anchor)!,
            tags: tags,
            answers: answers,
            recoveryPercent: 70,
            sleepPerformance: sleepPerformance,
            deepMinutes: 80,
            remMinutes: 90,
            efficiency: 90,
            wakeCount: 2,
            isWeekend: isWeekend,
            sleepDebtMinutes: sleepDebtMinutes,
            bedtimeHour: bedtimeHour,
            alcoholicBeverages: alcoholicBeverages,
            lateCaffeineMg: lateCaffeineMg,
            measuredTimeZoneShift: measuredTimeZoneShift
        )
    }

    // MARK: - The core inversion

    /// The defect, stated as a test. A night the user answered *something*
    /// on says nothing about the behaviours they didn't answer.
    func testAnsweringOneBehaviourLeavesTheOthersUnknown() {
        let obs = observation(
            daysAgo: 0,
            answers: BehaviorAnswers([BehaviorTag.hardTraining.rawValue: .yes])
        )
        XCTAssertEqual(obs.exposureState(for: .hardTraining), .yes)
        XCTAssertEqual(obs.exposureState(for: .caffeineLate), .unknown,
                       "an unanswered behaviour is missing data, not a no")
        XCTAssertEqual(obs.exposureState(for: .alcohol), .unknown,
                       "training yes must not imply alcohol no")
    }

    /// A night with a journal row but no answers at all. Under the old model
    /// this resolved to `.no` for every behaviour.
    func testAJournalRowWithNoAnswersIsUnknownThroughout() {
        let obs = observation(daysAgo: 0)
        for tag in BehaviorTag.allCases {
            XCTAssertEqual(obs.exposureState(for: tag), .unknown, tag.rawValue)
        }
        XCTAssertFalse(obs.hasAnyExplicitAnswer)
    }

    func testExplicitNoIsNo() {
        let obs = observation(
            daysAgo: 0,
            answers: BehaviorAnswers([BehaviorTag.caffeineLate.rawValue: .no])
        )
        XCTAssertEqual(obs.exposureState(for: .caffeineLate), .no)
        XCTAssertTrue(obs.hasAnyExplicitAnswer)
    }

    func testExplicitYesIsYes() {
        let obs = observation(
            daysAgo: 0,
            answers: BehaviorAnswers([BehaviorTag.caffeineLate.rawValue: .yes])
        )
        XCTAssertEqual(obs.exposureState(for: .caffeineLate), .yes)
    }

    /// An explicit answer outranks a stale legacy tag, or changing your mind
    /// would be impossible for any behaviour recorded before the migration.
    func testAnExplicitNoOverridesALegacyPositiveTag() {
        let obs = observation(
            daysAgo: 0,
            tags: [.alcohol],
            answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .no])
        )
        XCTAssertEqual(obs.exposureState(for: .alcohol), .no)
    }

    // MARK: - Measured data is upgrade-only

    func testMeasuredAlcoholUpgradesAnUnansweredNightToYes() {
        let obs = observation(daysAgo: 0, alcoholicBeverages: 2)
        XCTAssertEqual(obs.exposureState(for: .alcohol), .yes)
    }

    /// The rule the previous implementation stated in its own doc comment and
    /// then broke: it read a measured zero as a confident `.no`. But
    /// `FeatureExtractor.alcoholicBeverages` cannot distinguish "nothing
    /// logged" from "Lifestyle Insights never authorized", so an absent
    /// sample proves nothing.
    func testAMeasuredZeroIsNotANo() {
        XCTAssertEqual(observation(daysAgo: 0, alcoholicBeverages: 0)
            .exposureState(for: .alcohol), .unknown)
        XCTAssertEqual(observation(daysAgo: 0, lateCaffeineMg: 0)
            .exposureState(for: .caffeineLate), .unknown)
    }

    func testATimezoneShiftUpgradesTravelToYesButItsAbsenceProvesNothing() {
        XCTAssertEqual(observation(daysAgo: 0, measuredTimeZoneShift: true)
            .exposureState(for: .travelled), .yes)
        XCTAssertEqual(observation(daysAgo: 0, measuredTimeZoneShift: false)
            .exposureState(for: .travelled), .unknown)
    }

    // MARK: - Migration

    func testALegacyPositiveTagMigratesToYes() {
        let answers = BehaviorAnswers.migrating(
            fromTagIdentifiers: [BehaviorTag.alcohol.rawValue, BehaviorTag.sauna.rawValue]
        )
        XCTAssertEqual(answers.state(for: .alcohol), .yes)
        XCTAssertEqual(answers.state(for: .sauna), .yes)
    }

    /// The migration must be lossy in the safe direction. Back-filling `.no`
    /// would bake the fabricated control arm permanently into the store,
    /// where no later fix could find it.
    func testALegacyMissingTagMigratesToUnknownNeverNo() {
        let answers = BehaviorAnswers.migrating(
            fromTagIdentifiers: [BehaviorTag.alcohol.rawValue]
        )
        XCTAssertEqual(answers.state(for: .caffeineLate), .unknown)
        for tag in BehaviorTag.allCases where tag != .alcohol {
            XCTAssertNotEqual(answers.state(for: tag), .no, tag.rawValue)
        }
    }

    /// A legacy tag still reaches the engines even with no observation row,
    /// which is what makes the forward-fill safe to skip for entries that
    /// predate `JournalEntry.nightKey`.
    func testALegacyTagIsHonouredWithoutAnyObservation() {
        let obs = observation(daysAgo: 0, tags: [.alcohol], answers: .none)
        XCTAssertEqual(obs.exposureState(for: .alcohol), .yes)
        XCTAssertTrue(obs.hasAnyExplicitAnswer)
    }

    func testAnUnknownIdentifierIsIgnoredRatherThanFatal() {
        let answers = BehaviorAnswers.migrating(
            fromTagIdentifiers: ["someBehaviourFromAFutureBuild"]
        )
        XCTAssertEqual(answers.answeredCount, 1)
        for tag in BehaviorTag.allCases {
            XCTAssertEqual(answers.state(for: tag), .unknown, tag.rawValue)
        }
    }

    // MARK: - BehaviorAnswers itself

    func testUnknownIsNotStored() {
        var answers = BehaviorAnswers([BehaviorTag.alcohol.rawValue: .yes])
        XCTAssertEqual(answers.answeredCount, 1)
        answers.set(.unknown, for: .alcohol)
        XCTAssertEqual(answers.answeredCount, 0, "clearing removes the answer")
        XCTAssertFalse(answers.hasAnyAnswer)
    }

    func testExplicitUnknownInTheInitialiserIsDiscarded() {
        let answers = BehaviorAnswers([
            BehaviorTag.alcohol.rawValue: .unknown,
            BehaviorTag.sauna.rawValue: .no,
        ])
        XCTAssertEqual(answers.answeredCount, 1)
        XCTAssertEqual(answers.state(for: .alcohol), .unknown)
        XCTAssertEqual(answers.state(for: .sauna), .no)
    }

    func testFullyAnsweredIsYesForTaggedAndNoForEverythingElse() {
        let answers = BehaviorAnswers.fullyAnswered(tags: [.alcohol])
        XCTAssertEqual(answers.state(for: .alcohol), .yes)
        XCTAssertEqual(answers.state(for: .caffeineLate), .no)
        XCTAssertEqual(answers.answeredCount, BehaviorTag.allCases.count)
    }

    func testChangingAnAnswerReplacesIt() {
        let answers = BehaviorAnswers([BehaviorTag.alcohol.rawValue: .yes])
            .setting(.no, for: .alcohol)
        XCTAssertEqual(answers.state(for: .alcohol), .no)
        XCTAssertEqual(answers.answeredCount, 1)
    }

    // MARK: - Cause Finder needs a stated contrast

    /// Eight exposed nights and thirty-two unanswered ones must not produce a
    /// finding. Under the old model those thirty-two carried journal rows and
    /// so became a thirty-two-night control arm nobody ever described.
    func testUnansweredNightsCannotFormAControlArm() {
        var observations: [JournalCorrelator.Observation] = []
        for i in 0..<8 {
            observations.append(observation(
                daysAgo: i,
                answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .yes]),
                sleepPerformance: 55, isWeekend: i % 2 == 0
            ))
        }
        for i in 8..<40 {
            observations.append(observation(
                daysAgo: i, sleepPerformance: 95, isWeekend: i % 2 == 0
            ))
        }
        let findings = JournalCorrelator().findings(from: observations)
        XCTAssertFalse(findings.contains { $0.tag == .alcohol },
                       "no stated negatives means no comparison is possible")
    }

    /// The same history, with the control nights actually answered, does
    /// produce a finding -- so the refusal above is about missing evidence
    /// rather than the engine being broken.
    func testStatedNegativesDoFormAControlArm() {
        var observations: [JournalCorrelator.Observation] = []
        for i in 0..<12 {
            observations.append(observation(
                daysAgo: i,
                answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .yes]),
                sleepPerformance: 55, isWeekend: i % 2 == 0
            ))
        }
        for i in 12..<44 {
            observations.append(observation(
                daysAgo: i,
                answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .no]),
                sleepPerformance: 95, isWeekend: i % 2 == 0
            ))
        }
        let findings = JournalCorrelator().findings(from: observations)
        XCTAssertTrue(findings.contains { $0.tag == .alcohol },
                      "twelve stated yes nights against thirty-two stated no nights is a real contrast")
    }

    // MARK: - Matching prefers what it knows

    /// A candidate missing a confounder used to score zero distance, which is
    /// the best possible score, so the matcher preferentially chose the
    /// nights it knew least about. `sleepDebtMinutes` is nil until fourteen
    /// nights of history exist, so the bias was strongest exactly when the
    /// engine first starts producing findings.
    func testAKnownCloseConfounderBeatsAMissingOne() {
        var observations: [JournalCorrelator.Observation] = []
        for i in 0..<10 {
            observations.append(observation(
                daysAgo: i,
                answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .yes]),
                sleepPerformance: 60, isWeekend: false, sleepDebtMinutes: 30
            ))
        }
        // Controls whose debt is known and identical to the exposed nights.
        for i in 10..<20 {
            observations.append(observation(
                daysAgo: i,
                answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .no]),
                sleepPerformance: 90, isWeekend: false, sleepDebtMinutes: 30
            ))
        }
        // Controls with no debt recorded at all, and a wildly different
        // outcome. If these win the match, the reported effect moves.
        for i in 20..<40 {
            observations.append(observation(
                daysAgo: i,
                answers: BehaviorAnswers([BehaviorTag.alcohol.rawValue: .no]),
                sleepPerformance: 20, isWeekend: false, sleepDebtMinutes: nil
            ))
        }

        let findings = JournalCorrelator().findings(from: observations)
        guard let finding = findings.first(where: {
            $0.tag == .alcohol && $0.metric == .sleepPerformance
        }) else {
            return XCTFail("expected an alcohol/sleepPerformance finding")
        }
        XCTAssertLessThan(finding.pairDeltaMedian, 0,
                          "matched against the known-debt controls, alcohol nights are worse")
    }
}
