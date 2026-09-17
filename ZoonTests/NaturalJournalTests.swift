import XCTest

final class NaturalJournalTests: XCTestCase {
    func testExampleSentenceBecomesReviewableProposals() {
        let proposals = NaturalJournalParser.proposals(
            from: "I had two coffees, went to the gym at 7 and ate late."
        )
        XCTAssertEqual(Set(proposals.compactMap(\.tag)), [.caffeine, .hardTraining, .lateMeal])
    }

    func testParserDoesNotInventAnObservation() {
        XCTAssertTrue(NaturalJournalParser.proposals(from: "It was a normal day.").isEmpty)
    }

    func testMultiplePhrasesProduceOneProposalPerTag() {
        let proposals = NaturalJournalParser.proposals(from: "Coffee and espresso, then a late dinner and ate late.")
        XCTAssertEqual(proposals.filter { $0.tag == .caffeine }.count, 1)
        XCTAssertEqual(proposals.filter { $0.tag == .lateMeal }.count, 1)
    }

    func testMorningDaylightIsAvailableToPersonalLearning() {
        XCTAssertEqual(
            NaturalJournalParser.proposals(from: "I took a morning walk outside this morning").compactMap(\.tag),
            [.morningDaylight]
        )
    }

    func testTimeBelongsToEntityInsteadOfCreatingCaffeineFalsePositive() {
        let gym = NaturalJournalParser.proposals(from: "I went to the gym after 3 PM")
        XCTAssertEqual(Set(gym.compactMap(\.tag)), [.hardTraining])
        XCTAssertFalse(gym.contains { $0.tag == .caffeineLate })
    }

    func testNegationsBecomeExplicitNoObservations() {
        let proposals = NaturalJournalParser.proposals(from: "I had no coffee, didn't drink alcohol, and was not stressed today")
        XCTAssertEqual(proposals.first(where: { $0.tag == .caffeine })?.state, .no)
        XCTAssertEqual(proposals.first(where: { $0.tag == .alcohol })?.state, .no)
        XCTAssertEqual(proposals.first(where: { $0.tag == .stressfulDay })?.state, .no)
        XCTAssertEqual(NaturalJournalParser.proposals(from: "I had tea but no coffee").first?.state, .yes)
        XCTAssertEqual(NaturalJournalParser.proposals(from: "I didn't eat late").first?.state, .no)
    }

    func testExplicitLateCaffeineKeepsEntityAndTime() {
        let proposals = NaturalJournalParser.proposals(from: "I had two coffees, last one at 4:30 PM")
        XCTAssertEqual(proposals.first?.behavior, BehaviorTag.caffeineLate.behaviorID)
        XCTAssertEqual(proposals.first?.state, .yes)
        XCTAssertEqual(proposals.first?.confidence, .high)
        XCTAssertTrue(proposals.first?.matchedText.contains("4pm") == true)
    }

    /// "4pm" with no space before the meridiem used to fail to parse at all,
    /// and "steak" used to propose caffeine by way of "tea".
    func testATimeWithNoSpaceBeforeTheMeridiemStillParses() {
        let proposals = NaturalJournalParser.proposals(from: "Had steak, then two coffees at 4pm")
        XCTAssertEqual(proposals.compactMap(\.tag), [.caffeineLate])
        XCTAssertEqual(proposals.first?.state, .yes)
        XCTAssertEqual(proposals.first?.confidence, .high)
        XCTAssertEqual(proposals.first?.matchedText, "coffees at 4pm")
    }

    func testTwelveIsHandledOnBothSidesOfNoon() {
        XCTAssertEqual(NaturalJournalParser.proposals(from: "coffee at 12pm").first?.behavior, BehaviorTag.caffeine.behaviorID)
        XCTAssertEqual(NaturalJournalParser.proposals(from: "coffee at 12am").first?.behavior, BehaviorTag.caffeine.behaviorID)
        XCTAssertEqual(NaturalJournalParser.proposals(from: "coffee at 3pm").first?.behavior, BehaviorTag.caffeineLate.behaviorID)
    }

    /// Keywords match whole words. A steady day contains "tea" and is not a
    /// caffeine observation.
    func testKeywordsInsideOtherWordsProposeNothing() {
        XCTAssertTrue(NaturalJournalParser.proposals(from: "It was a steady day").isEmpty)
        XCTAssertTrue(NaturalJournalParser.proposals(from: "Had steak for dinner").isEmpty)
    }

    func testConsecutiveDisruptionDaysBecomeOneEpisode() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let dates = Set((0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            + [calendar.date(byAdding: .day, value: 12, to: start)!])
        let episodes = PersonalLearning.disruptionEpisodes(from: dates, calendar: calendar)
        XCTAssertEqual(episodes.count, 2)
        XCTAssertEqual(episodes.first?.dayCount, 5)
    }
}

@MainActor
final class AlertnessCheckStoreTests: XCTestCase {
    func testResultUsesMedianAndCountsLapses() {
        let suite = "AlertnessCheckStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertnessCheckStore(defaults: defaults)

        store.save(reactions: [0.2, 0.3, 0.4, 0.45, 0.7], subjectiveAlertness: 4)

        XCTAssertEqual(store.sessions.first?.medianMilliseconds, 400)
        XCTAssertEqual(store.sessions.first?.lapses, 1)
        XCTAssertEqual(store.sessions.first?.subjectiveAlertness, 4)
    }

    func testEvenMedianUsesBothCenterTrials() {
        let suite = "AlertnessCheckStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertnessCheckStore(defaults: defaults)
        store.save(reactions: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6], subjectiveAlertness: 3)
        XCTAssertEqual(store.sessions.first?.medianMilliseconds, 350)
    }

    func testIncompleteCheckIsNotSaved() {
        let suite = "AlertnessCheckStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertnessCheckStore(defaults: defaults)
        // The store now says so rather than returning quietly, because the
        // screen used to show "Saved on this device" over a run it had
        // dropped.
        XCTAssertNil(store.save(reactions: [0.2, 0.3, 0.4], subjectiveAlertness: 3))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    // MARK: - Custom signals

    private func catalog(_ names: [String], active: Bool = true) -> BehaviorCatalog {
        BehaviorCatalog(custom: names.map { CustomBehavior(name: $0, isActive: active) })
    }

    /// The parameter this restores used to end in `_ = customNames`: it
    /// accepted the list and dropped it, so the box appeared to support
    /// custom signals and silently ignored every one of them.
    func testACustomSignalIsProposedByName() throws {
        let catalog = catalog(["magnesium glycinate", "prayer"])
        let proposals = NaturalJournalParser.proposals(
            from: "Took magnesium glycinate before bed", catalog: catalog
        )
        let proposal = try XCTUnwrap(proposals.first { $0.behavior.isCustom })
        XCTAssertEqual(proposal.label, "magnesium glycinate")
        XCTAssertEqual(proposal.state, .yes)
    }

    func testACustomSignalCanBeNegated() throws {
        let proposals = NaturalJournalParser.proposals(
            from: "No prayer today", catalog: catalog(["prayer"])
        )
        let proposal = try XCTUnwrap(proposals.first { $0.behavior.isCustom })
        XCTAssertEqual(proposal.state, .no)
    }

    /// Whole-word, the same rule the built-in phrases use.
    func testACustomSignalDoesNotMatchInsideAnotherWord() {
        let proposals = NaturalJournalParser.proposals(
            from: "It was a steady day", catalog: catalog(["tea"])
        )
        XCTAssertTrue(proposals.filter { $0.behavior.isCustom }.isEmpty)
    }

    func testAnInactiveCustomSignalIsNotProposed() {
        let proposals = NaturalJournalParser.proposals(
            from: "Took magnesium glycinate", catalog: catalog(["magnesium glycinate"], active: false)
        )
        XCTAssertTrue(proposals.filter { $0.behavior.isCustom }.isEmpty)
    }

    /// A name alone is weaker evidence than a matched phrase with a time on
    /// it. Zoon chose none of these words.
    func testACustomSignalIsNeverHighConfidenceFromANameAlone() throws {
        let proposals = NaturalJournalParser.proposals(
            from: "Did my breathing practice", catalog: catalog(["breathing practice"])
        )
        let proposal = try XCTUnwrap(proposals.first { $0.behavior.isCustom })
        XCTAssertNotEqual(proposal.confidence, .high)
    }

    /// Built-ins and custom signals coexist in one sentence.
    func testBuiltInAndCustomProposalsCoexist() {
        let proposals = NaturalJournalParser.proposals(
            from: "Two coffees and my evening medication", catalog: catalog(["evening medication"])
        )
        XCTAssertTrue(proposals.contains { $0.tag == .caffeine })
        XCTAssertTrue(proposals.contains { $0.behavior.isCustom })
    }
}
