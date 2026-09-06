import XCTest

final class AdaptiveJournalTests: XCTestCase {

    private func observation(
        daysAgo: Int,
        tags: Set<BehaviorTag> = [],
        // Replaced an `isJournaled` flag that meant only "a JournalEntry
        // row exists" -- which the old model read as a confident no for
        // every untagged behaviour, though a row is created merely by
        // opening the journal screen. `true` now states what these fixtures
        // actually mean: the whole list was worked through, so tagged
        // behaviours are yes and every other one is an explicit no. `false`
        // means nothing was answered, so every behaviour is unknown.
        fullyAnswered: Bool = true,
        sleepPerformance: Double? = 80,
        recoveryPercent: Double? = 70
    ) -> JournalCorrelator.Observation {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return JournalCorrelator.Observation(
            date: date,
            tags: tags,
            answers: fullyAnswered ? .fullyAnswered(tags: tags) : .none,
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
                return observation(daysAgo: 30 - index, fullyAnswered: false,
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
            AdaptiveJournal.rankedListSize
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

// MARK: - Why Zoon is asking

/// V9 item 39. The spec's example: "Why Zoon is asking: We have 15 YES
/// nights but only 3 NO nights."
///
/// Both arm counts were already being computed and then discarded in favour
/// of their minimum, so the prompt knew exactly how short the comparison was
/// and declined to say.
extension AdaptiveJournalTests {

    private func prompt(
        reason: AdaptiveJournal.Reason,
        yes: Int,
        no: Int
    ) -> AdaptiveJournal.Prompt {
        AdaptiveJournal.Prompt(
            tag: .caffeineLate, reason: reason,
            unknownNights: 0, yesNights: yes, noNights: no
        )
    }

    func testAShortComparisonSaysHowShortItIs() {
        let note = prompt(reason: .nearlyAnswerable, yes: 15, no: 3).note
        XCTAssertTrue(note.contains("15 nights with it"), note)
        XCTAssertTrue(note.contains("3 without"), note)
    }

    func testTheBarelySeenCaseAlsoGivesCounts() {
        let note = prompt(reason: .barelySeen, yes: 4, no: 0).note
        XCTAssertTrue(note.contains("4 nights with it"), note)
        XCTAssertTrue(note.contains("0 without"), note)
    }

    func testASingleNightReadsAsSingular() {
        let note = prompt(reason: .barelySeen, yes: 1, no: 9).note
        XCTAssertTrue(note.contains("1 night with it"), note)
        XCTAssertFalse(note.contains("1 nights"), note)
    }

    /// The reasons that are already complete sentences do not get numbers
    /// bolted on. "You're testing this right now" is the whole reason, and
    /// appending counts would be numbers for their own sake.
    func testTheOtherReasonsAreLeftAlone() {
        for reason in [AdaptiveJournal.Reason.underExperiment, .pinnedByUser, .routine] {
            let note = prompt(reason: reason, yes: 15, no: 3).note
            XCTAssertEqual(note, reason.note, "\(reason) should keep its own wording")
            XCTAssertFalse(note.contains("15"), note)
        }
    }

    /// `thinnerArmNights` is derived from the two arms now rather than
    /// stored beside them, so the three can never disagree.
    func testTheThinnerArmIsTheSmallerOfTheTwo() {
        XCTAssertEqual(prompt(reason: .routine, yes: 15, no: 3).thinnerArmNights, 3)
        XCTAssertEqual(prompt(reason: .routine, yes: 2, no: 20).thinnerArmNights, 2)
    }

    // MARK: - The one question (V9 item 39)

    /// Everything routine: the top-ranked prompt is one whose answer Zoon can
    /// already predict, so the right number of questions is none.
    private func allRoutineHistory() -> [JournalCorrelator.Observation] {
        (0..<24).map { index in
            observation(daysAgo: 24 - index, tags: index.isMultiple(of: 2) ? [.coolRoom] : [])
        }
    }

    func testTheAskIsASingleQuestion() throws {
        let prompt = try XCTUnwrap(AdaptiveJournal.question(observations: history()))
        // The thinnest genuinely-short comparison wins over the barely-seen
        // one, and both win over anything routine.
        XCTAssertEqual(prompt.tag, .alcohol)
        XCTAssertEqual(prompt.reason, .nearlyAnswerable)
    }

    func testNothingIsAskedWhenEveryAnswerIsAlreadyPredictable() {
        // `prompts` still returns the routine behaviour -- it fills a list.
        XCTAssertFalse(AdaptiveJournal.prompts(observations: allRoutineHistory()).isEmpty)
        // The question does not, because there is no list to fill.
        XCTAssertNil(AdaptiveJournal.question(observations: allRoutineHistory()))
    }

    func testNothingIsAskedWithNoHistoryAtAll() {
        XCTAssertNil(AdaptiveJournal.question(observations: []))
    }

    /// A trial's adherence *is* the trial, so a missed night is a hole in the
    /// result -- that outranks the quiet.
    func testAnExperimentIsStillAskedAboutWhenEverythingElseIsRoutine() throws {
        let prompt = try XCTUnwrap(AdaptiveJournal.question(
            observations: allRoutineHistory(),
            activeExperimentTag: BehaviorTag.magnesium.rawValue
        ))
        XCTAssertEqual(prompt.tag, .magnesium)
        XCTAssertEqual(prompt.reason, .underExperiment)
    }

    /// Someone who pinned a behaviour has said it matters, and that settles
    /// it -- their stated intent outranks anything inferred about them.
    func testAPinnedBehaviourIsStillAskedAboutWhenEverythingElseIsRoutine() throws {
        let prompt = try XCTUnwrap(AdaptiveJournal.question(
            observations: allRoutineHistory(),
            pinnedTags: [.sauna]
        ))
        XCTAssertEqual(prompt.tag, .sauna)
        XCTAssertEqual(prompt.reason, .pinnedByUser)
    }

    func testABehaviourAlreadyAnsweredTonightIsNotAskedAgain() throws {
        let first = try XCTUnwrap(AdaptiveJournal.question(observations: history()))
        XCTAssertEqual(first.tag, .alcohol)

        let second = try XCTUnwrap(AdaptiveJournal.question(
            observations: history(), alreadyAnswered: [.alcohol]
        ))
        XCTAssertNotEqual(second.tag, .alcohol)
    }

    func testAnsweringEverythingWorthAskingEndsTheAsking() {
        XCTAssertNil(AdaptiveJournal.question(
            observations: history(),
            alreadyAnswered: Set(BehaviorTag.allCases)
        ))
    }

    /// The same safeguard the list has, on the single question: what gets
    /// asked cannot depend on how the person slept.
    func testTheQuestionIsIdenticalRegardlessOfHowTheyActuallySlept() {
        let terrible = AdaptiveJournal.question(observations: history { _ in 20 })
        let excellent = AdaptiveJournal.question(observations: history { _ in 99 })
        XCTAssertEqual(terrible?.tag, excellent?.tag)
        XCTAssertEqual(terrible?.reason, excellent?.reason)
    }

    /// The "why Zoon is asking" line has to carry both arms, not a verdict.
    func testTheReasonGivenNamesBothSidesOfTheComparison() throws {
        let prompt = try XCTUnwrap(AdaptiveJournal.question(observations: history()))
        XCTAssertTrue(prompt.note.contains("\(prompt.yesNights)"))
        XCTAssertTrue(prompt.note.contains("\(prompt.noNights)"))
        for word in ["worse", "better", "bad night", "poor"] {
            XCTAssertFalse(prompt.note.lowercased().contains(word), "note judged the night: \(prompt.note)")
        }
    }

    // MARK: - The question text

    func testEveryBehaviourHasAnAnswerableQuestion() {
        for tag in BehaviorTag.allCases {
            XCTAssertTrue(tag.question.hasSuffix("?"), "\(tag.rawValue) is not phrased as a question")
            XCTAssertNotEqual(tag.question, tag.label)
            XCTAssertGreaterThan(tag.question.count, tag.label.count)
        }
    }

    func testQuestionsAreDistinct() {
        let questions = Set(BehaviorTag.allCases.map(\.question))
        XCTAssertEqual(questions.count, BehaviorTag.allCases.count)
    }
}
