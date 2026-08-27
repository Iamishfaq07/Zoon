import XCTest

final class AdaptiveJournalTests: XCTestCase {

    private func observation(
        daysAgo: Int,
        tags: Set<BehaviorTag> = [],
        isJournaled: Bool = true,
        sleepPerformance: Double? = 80,
        recoveryPercent: Double? = 70
    ) -> JournalCorrelator.Observation {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return JournalCorrelator.Observation(
            date: date,
            tags: tags,
            isJournaled: isJournaled,
            recoveryPercent: recoveryPercent,
            sleepPerformance: sleepPerformance,
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

    /// 30 nights, the last six never reviewed. Of the 24 journaled nights:
    /// `alcohol` on 6 (thinner arm 6 -- a few short of the matched-pair
    /// floor), `coolRoom` on 12 (thinner arm 12 -- already answerable),
    /// `travelled` on 2 (thinner arm 2 -- barely seen), and `sauna` and
    /// `nicotine` never.
    private func history(
        sleepPerformance: @escaping (Int) -> Double = { _ in 80 }
    ) -> [JournalCorrelator.Observation] {
        (0..<30).map { index in
            guard index < 24 else {
                return observation(daysAgo: 30 - index, isJournaled: false,
                                   sleepPerformance: sleepPerformance(index))
            }
            var tags: Set<BehaviorTag> = []
            if index < 6 { tags.insert(.alcohol) }
            if index % 2 == 0 { tags.insert(.coolRoom) }
            if index == 10 || index == 11 { tags.insert(.travelled) }
            return observation(daysAgo: 30 - index, tags: tags,
                               sleepPerformance: sleepPerformance(index))
        }
    }

    private func prompt(for tag: BehaviorTag, in prompts: [AdaptiveJournal.Prompt])
        throws -> AdaptiveJournal.Prompt {
        try XCTUnwrap(prompts.first { $0.tag == tag },
                      "no prompt for \(tag.rawValue) in \(prompts.map(\.id))")
    }

    // MARK: - The rule that shapes the whole type

    /// The safeguard this engine exists around. If Zoon asked about a
    /// behaviour more often after bad nights, the journal would fill with
    /// tags disproportionately attached to bad nights, and the correlator
    /// would then "discover" an association Zoon manufactured by choosing
    /// when to ask. That bias is indistinguishable from a real effect once
    /// it is in the data.
    func testTheListIsIdenticalRegardlessOfHowTheyActuallySlept() {
        let terrible = AdaptiveJournal.prompts(observations: history { _ in 20 })
        let excellent = AdaptiveJournal.prompts(observations: history { _ in 99 })
        let mixed = AdaptiveJournal.prompts(
            observations: history { $0.isMultiple(of: 2) ? 20 : 99 }
        )

        XCTAssertFalse(terrible.isEmpty)
        XCTAssertEqual(terrible, excellent)
        XCTAssertEqual(terrible, mixed)
    }

    /// No note may reference sleep quality, since no reason depends on it.
    func testNoReasonMentionsHowTheySlept() {
        for reason in [AdaptiveJournal.Reason.underExperiment, .pinnedByUser,
                       .nearlyAnswerable, .barelySeen, .routine] {
            let note = reason.note.lowercased()
            for banned in ["slept", "sleep", "recovery", "bad night", "poor"] {
                XCTAssertFalse(note.contains(banned), "\(reason.note) mentions \(banned)")
            }
        }
    }

    // MARK: - Priority

    /// Adherence data *is* the trial: a missed night is a hole in the result,
    /// so a behaviour under test outranks everything, even one never logged.
    func testABehaviourUnderExperimentComesFirstEvenWithNoHistory() throws {
        let prompts = AdaptiveJournal.prompts(
            observations: history(), activeExperimentTag: BehaviorTag.sauna.rawValue
        )
        let first = try XCTUnwrap(prompts.first)

        XCTAssertEqual(first.tag, .sauna)
        XCTAssertEqual(first.reason, .underExperiment)
    }

    /// Stated intent outranks anything inferred.
    func testAPinnedBehaviourOutranksEveryInferredReason() throws {
        let prompts = AdaptiveJournal.prompts(
            observations: history(), pinnedTags: [.nicotine]
        )
        let first = try XCTUnwrap(prompts.first)

        XCTAssertEqual(first.tag, .nicotine, "never logged, but the person asked for it")
        XCTAssertEqual(first.reason, .pinnedByUser)
    }

    func testAnExperimentOutranksAPin() throws {
        let prompts = AdaptiveJournal.prompts(
            observations: history(),
            activeExperimentTag: BehaviorTag.sauna.rawValue,
            pinnedTags: [.nicotine]
        )
        XCTAssertEqual(prompts.first?.tag, .sauna)
        XCTAssertEqual(prompts.dropFirst().first?.tag, .nicotine)
    }

    func testABehaviourAFewNightsShortIsCalledNearlyAnswerable() throws {
        let prompts = AdaptiveJournal.prompts(observations: history())
        let alcohol = try prompt(for: .alcohol, in: prompts)

        XCTAssertEqual(alcohol.thinnerArmNights, 6)
        XCTAssertLessThan(alcohol.thinnerArmNights, JournalCorrelator.minimumMatchedPairs)
        XCTAssertEqual(alcohol.reason, .nearlyAnswerable)
    }

    func testABehaviourFarFromAComparisonIsCalledBarelySeen() throws {
        let prompts = AdaptiveJournal.prompts(observations: history())
        let travelled = try prompt(for: .travelled, in: prompts)

        XCTAssertEqual(travelled.thinnerArmNights, 2)
        XCTAssertEqual(travelled.reason, .barelySeen)
    }

    /// Observation can already answer this one, so it is only there to fill
    /// out the list.
    func testAnAlreadyAnswerableBehaviourIsRoutine() throws {
        let prompts = AdaptiveJournal.prompts(observations: history())
        let coolRoom = try prompt(for: .coolRoom, in: prompts)

        XCTAssertGreaterThanOrEqual(coolRoom.thinnerArmNights,
                                    JournalCorrelator.minimumMatchedPairs)
        XCTAssertEqual(coolRoom.reason, .routine)
    }

    func testReasonsOrderWeakestToStrongest() {
        XCTAssertLessThan(AdaptiveJournal.Reason.routine, .barelySeen)
        XCTAssertLessThan(AdaptiveJournal.Reason.barelySeen, .nearlyAnswerable)
        XCTAssertLessThan(AdaptiveJournal.Reason.nearlyAnswerable, .pinnedByUser)
        XCTAssertLessThan(AdaptiveJournal.Reason.pinnedByUser, .underExperiment)
    }

    func testPromptsComeBackStrongestReasonFirst() {
        let reasons = AdaptiveJournal.prompts(observations: history()).map(\.reason)
        XCTAssertEqual(reasons, reasons.sorted(by: >))
    }

    /// Tonight's answer is worth most where the thinner arm is emptiest.
    func testWithinAReasonTheEmptiestArmComesFirst() {
        let prompts = AdaptiveJournal.prompts(
            observations: history(), pinnedTags: [.alcohol, .travelled]
        )
        let pinned = prompts.filter { $0.reason == .pinnedByUser }

        XCTAssertEqual(pinned.count, 2)
        XCTAssertEqual(pinned.map(\.tag), [.travelled, .alcohol],
                       "travelled's thinner arm is 2 against alcohol's 6")
    }

    // MARK: - Unknown nights

    /// The reason unknown nights cannot rank anything: a night the person
    /// never reviewed is unknown for every tag alike, so the number is
    /// identical across the whole list.
    func testUnknownNightsAreTheSameForEveryPromptAndSoOrderNothing() {
        let prompts = AdaptiveJournal.prompts(observations: history())
        XCTAssertFalse(prompts.isEmpty)
        XCTAssertEqual(Set(prompts.map(\.unknownNights)), [6])
    }

    // MARK: - Exclusions and limits

    /// A behaviour with no history is noise on the nightly list.
    func testANeverLoggedBehaviourIsLeftOffUnlessAskedFor() {
        let ids = AdaptiveJournal.prompts(observations: history()).map(\.id)
        XCTAssertFalse(ids.contains(BehaviorTag.nicotine.rawValue))
        XCTAssertFalse(ids.contains(BehaviorTag.sauna.rawValue))
    }

    /// The point is to shorten the list, not to reorder twenty-three of them.
    func testTheListIsCappedAtTheLimit() {
        XCTAssertEqual(AdaptiveJournal.prompts(observations: history(), limit: 2).count, 2)
        XCTAssertTrue(AdaptiveJournal.prompts(observations: history(), limit: 0).isEmpty)
        XCTAssertLessThanOrEqual(
            AdaptiveJournal.prompts(observations: history()).count,
            AdaptiveJournal.promptSize
        )
    }

    func testNoHistoryProducesNoPrompts() {
        XCTAssertTrue(AdaptiveJournal.prompts(observations: []).isEmpty)
    }

    /// An experiment must still be asked about on someone's very first night.
    func testAnExperimentIsAskedAboutEvenWithNoHistoryAtAll() throws {
        let prompts = AdaptiveJournal.prompts(
            observations: [], activeExperimentTag: BehaviorTag.alcohol.rawValue
        )
        XCTAssertEqual(prompts.map(\.tag), [.alcohol])
        XCTAssertEqual(try XCTUnwrap(prompts.first).unknownNights, 0)
    }

    func testOrderingIsStable() {
        let first = AdaptiveJournal.prompts(observations: history()).map(\.id)
        let second = AdaptiveJournal.prompts(observations: history()).map(\.id)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }
}
