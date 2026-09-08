import XCTest

final class NaturalJournalTests: XCTestCase {
    func testExampleSentenceBecomesReviewableProposals() {
        let proposals = NaturalJournalParser.proposals(
            from: "I had two coffees, went to the gym at 7 and ate late."
        )
        XCTAssertEqual(Set(proposals.map(\.tag)), [.caffeine, .hardTraining, .lateMeal])
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
            NaturalJournalParser.proposals(from: "I took a morning walk outside this morning").map(\.tag),
            [.morningDaylight]
        )
    }

    func testTimeBelongsToEntityInsteadOfCreatingCaffeineFalsePositive() {
        let gym = NaturalJournalParser.proposals(from: "I went to the gym after 3 PM")
        XCTAssertEqual(Set(gym.map(\.tag)), [.hardTraining])
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
        XCTAssertEqual(proposals.first?.tag, .caffeineLate)
        XCTAssertEqual(proposals.first?.state, .yes)
        XCTAssertEqual(proposals.first?.confidence, .high)
        XCTAssertTrue(proposals.first?.matchedText.contains("4pm") == true)
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

        store.save(reactions: [0.2, 0.3, 0.4, 0.7], subjectiveAlertness: 4)

        XCTAssertEqual(store.results.first?.medianReactionMilliseconds, 350)
        XCTAssertEqual(store.results.first?.lapses, 1)
        XCTAssertEqual(store.results.first?.subjectiveAlertness, 4)
    }

    func testEvenMedianUsesBothCenterTrials() {
        let suite = "AlertnessCheckStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertnessCheckStore(defaults: defaults)
        store.save(reactions: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6], subjectiveAlertness: 3)
        XCTAssertEqual(store.results.first?.medianReactionMilliseconds, 350)
    }

    func testIncompleteCheckIsNotSaved() {
        let suite = "AlertnessCheckStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertnessCheckStore(defaults: defaults)
        store.save(reactions: [0.2, 0.3, 0.4], subjectiveAlertness: 3)
        XCTAssertTrue(store.results.isEmpty)
    }
}
