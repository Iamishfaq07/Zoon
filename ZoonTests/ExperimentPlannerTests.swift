import XCTest

final class ExperimentPlannerTests: XCTestCase {

    private func observation(
        daysAgo: Int,
        tags: Set<BehaviorTag> = [],
        isJournaled: Bool = true
    ) -> JournalCorrelator.Observation {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return JournalCorrelator.Observation(
            date: date,
            tags: tags,
            isJournaled: isJournaled,
            recoveryPercent: 70,
            sleepPerformance: 80,
            deepMinutes: 80,
            remMinutes: 90,
            efficiency: 90,
            wakeCount: 2,
            isWeekend: false,
            sleepDebtMinutes: 30,
            bedtimeHour: -1,
            alcoholicBeverages: nil,
            lateCaffeineMg: nil,
            measuredTimeZoneShift: false
        )
    }

    /// 30 journaled nights. `alcohol` on every third (10 nights, so it varies
    /// naturally and clears the matched-pair floor), `travelled` on four
    /// (enough to be a candidate, too few for matched pairs), `coolRoom` on
    /// all but one (so one arm has to be manufactured), `sauna` on two (below
    /// the candidate floor).
    private func history(journaledNights: Int = 30, ofTotal total: Int? = nil)
        -> [JournalCorrelator.Observation] {
        let total = total ?? journaledNights
        return (0..<total).map { index in
            guard index < journaledNights else {
                return observation(daysAgo: total - index, isJournaled: false)
            }
            var tags: Set<BehaviorTag> = []
            if index % 3 == 0 { tags.insert(.alcohol) }
            if index < 4 { tags.insert(.travelled) }
            if index != 7 { tags.insert(.coolRoom) }
            if index < 2 { tags.insert(.sauna) }
            return observation(daysAgo: total - index, tags: tags)
        }
    }

    private func proposal(
        for tag: BehaviorTag,
        associatedTags: Set<BehaviorTag> = [],
        settledTags: Set<String> = []
    ) throws -> ExperimentPlanner.Proposal {
        let proposals = ExperimentPlanner.plan(
            observations: history(),
            associatedTags: associatedTags,
            settledTags: settledTags
        )
        return try XCTUnwrap(proposals.first { $0.tag == tag },
                             "no proposal for \(tag.rawValue) in \(proposals.map(\.id))")
    }

    // MARK: - Value ranking

    /// The whole point of the ordering: an association observation already
    /// flagged is the one thing only a planned trial can settle.
    func testAFlaggedAssociationOutranksEverythingElse() throws {
        let proposals = ExperimentPlanner.plan(
            observations: history(), associatedTags: [.coolRoom]
        )
        let first = try XCTUnwrap(proposals.first)

        XCTAssertEqual(first.tag, .coolRoom)
        XCTAssertEqual(first.value, .settlesAnAssociation)
    }

    /// A behaviour logged too rarely for matched pairs is where a deliberate
    /// trial adds contrast that observation cannot.
    func testARarelyLoggedBehaviourCreatesMissingContrast() throws {
        let travelled = try proposal(for: .travelled)
        XCTAssertLessThan(travelled.exposedNights, JournalCorrelator.minimumMatchedPairs,
                          "precondition: too few nights for the matched-pair engine")
        XCTAssertEqual(travelled.value, .createsMissingContrast)
    }

    /// Observation had its chance on a heavily logged behaviour with no
    /// signal, so this is the weakest reason to spend weeks on a trial.
    func testAHeavilyLoggedBehaviourWithNoSignalIsTheWeakestReason() throws {
        let alcohol = try proposal(for: .alcohol)
        XCTAssertGreaterThanOrEqual(alcohol.exposedNights, JournalCorrelator.minimumMatchedPairs,
                                    "precondition: enough nights for matched pairs")
        XCTAssertEqual(alcohol.value, .confirmsAQuietResult)
    }

    func testValueOrdersWeakestToStrongest() {
        XCTAssertLessThan(ExperimentPlanner.Value.confirmsAQuietResult, .createsMissingContrast)
        XCTAssertLessThan(ExperimentPlanner.Value.createsMissingContrast, .settlesAnAssociation)
    }

    func testProposalsComeBackStrongestFirst() {
        let values = ExperimentPlanner.plan(
            observations: history(), associatedTags: [.coolRoom]
        ).map(\.value)
        XCTAssertEqual(values, values.sorted(by: >))
    }

    /// The same history must not reshuffle between visits to the screen.
    func testOrderingIsStable() {
        let first = ExperimentPlanner.plan(observations: history()).map(\.id)
        let second = ExperimentPlanner.plan(observations: history()).map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    // MARK: - Effort

    func testABehaviourOnAlmostEveryNightNeedsADeliberateChange() throws {
        let coolRoom = try proposal(for: .coolRoom)
        XCTAssertEqual(coolRoom.effort, .requiresDeliberateChange)
        XCTAssertTrue(coolRoom.sentence.contains("change it on purpose"), coolRoom.sentence)
    }

    func testABehaviourThatAlreadyVariesNeedsNoChange() throws {
        let alcohol = try proposal(for: .alcohol)
        XCTAssertEqual(alcohol.effort, .alreadyVaries)
        XCTAssertTrue(alcohol.sentence.contains("naturally"), alcohol.sentence)
    }

    // MARK: - Refusals

    func testTooLittleJournalingProducesNoProposals() {
        XCTAssertTrue(ExperimentPlanner.plan(observations: history(journaledNights: 10)).isEmpty)
    }

    /// Un-journaled nights are not history. Thirty nights of which only ten
    /// were reviewed must be treated as ten.
    func testUnjournaledNightsDoNotCountTowardTheFloor() {
        XCTAssertTrue(
            ExperimentPlanner.plan(
                observations: history(journaledNights: 10, ofTotal: 40)
            ).isEmpty,
            "thirty un-reviewed nights must not unlock proposals"
        )
    }

    /// Proposing a trial of something never logged would be proposing the
    /// person take it up. This suggests testing what they already do.
    func testABehaviourBelowTheExposureFloorIsNeverProposed() {
        let ids = ExperimentPlanner.plan(observations: history()).map(\.id)
        XCTAssertFalse(ids.contains(BehaviorTag.sauna.rawValue),
                       "two nights is below the candidate floor")
        XCTAssertFalse(ids.contains(BehaviorTag.nicotine.rawValue),
                       "never logged at all")
    }

    /// Re-proposing a question the person already answered wastes the one
    /// thing an experiment costs, which is weeks.
    func testASettledBehaviourIsNotProposedAgain() {
        let ids = ExperimentPlanner.plan(
            observations: history(),
            associatedTags: [.coolRoom],
            settledTags: [BehaviorTag.coolRoom.rawValue]
        ).map(\.id)

        XCTAssertFalse(ids.contains(BehaviorTag.coolRoom.rawValue))
        XCTAssertFalse(ids.isEmpty, "settling one question must not silence the rest")
    }

    func testNoObservationsProducesNoProposals() {
        XCTAssertTrue(ExperimentPlanner.plan(observations: []).isEmpty)
        XCTAssertNil(ExperimentPlanner.next(observations: []))
    }

    // MARK: - Estimated length

    /// Quoting the raw two-week minimum to someone who logs every third night
    /// quotes a number they cannot hit: the trial needs known nights, and
    /// unknown ones count toward neither arm.
    func testTheEstimateStretchesForPatchyJournaling() throws {
        let dense = try XCTUnwrap(ExperimentPlanner.next(observations: history(journaledNights: 30)))
        let patchy = try XCTUnwrap(
            ExperimentPlanner.next(observations: history(journaledNights: 20, ofTotal: 40))
        )

        XCTAssertEqual(dense.estimatedNights, GuidedExperiment.minimumPeriodNights * 2)
        XCTAssertEqual(patchy.estimatedNights, GuidedExperiment.minimumPeriodNights * 4,
                       "logging half the nights doubles the calendar time")
    }

    // MARK: - Copy

    func testTheHeadlineNamesTheBehaviour() throws {
        let alcohol = try proposal(for: .alcohol)
        XCTAssertTrue(alcohol.headline.contains(BehaviorTag.alcohol.label), alcohol.headline)
    }

    /// A proposal is a question. The copy must not hint at an answer, and two
    /// of the three reasons a behaviour ranks highly are reasons the answer
    /// is unknown.
    func testNoCopyPredictsTheOutcome() {
        for value in [ExperimentPlanner.Value.settlesAnAssociation,
                      .createsMissingContrast, .confirmsAQuietResult] {
            let reason = value.reason.lowercased()
            XCTAssertFalse(reason.contains("will improve"), value.reason)
            XCTAssertFalse(reason.contains("because"), value.reason)
        }
    }

    func testTheCaveatSaysZoonDoesNotKnowTheAnswer() throws {
        let caveat = try proposal(for: .alcohol).caveat.lowercased()
        XCTAssertTrue(caveat.contains("not a guess at the answer"), caveat)
        XCTAssertTrue(caveat.contains("no idea yet"), caveat)
    }
}
