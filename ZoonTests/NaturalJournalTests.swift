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
}

@MainActor
final class AlertnessCheckStoreTests: XCTestCase {
    func testResultUsesMedianAndCountsLapses() {
        let suite = "AlertnessCheckStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertnessCheckStore(defaults: defaults)

        store.save(reactions: [0.2, 0.3, 0.4, 0.7], subjectiveAlertness: 4)

        XCTAssertEqual(store.results.first?.medianReactionMilliseconds, 400)
        XCTAssertEqual(store.results.first?.lapses, 1)
        XCTAssertEqual(store.results.first?.subjectiveAlertness, 4)
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
