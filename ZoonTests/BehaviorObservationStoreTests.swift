import XCTest
import SwiftData

/// `BehaviorObservationStore` against a real, in-memory SwiftData store.
///
/// Follows `JournalStoreIntegrationTests` exactly, including the retained
/// `container` property -- a container that dies with the factory call takes
/// the in-memory store with it, and the next fetch traps inside SwiftData and
/// kills the whole test process with no XCTest failure message. See that
/// file's header for how that was tracked down.
@MainActor
final class BehaviorObservationStoreTests: XCTestCase {

    /// Held for the lifetime of the test. See the type doc.
    private var container: ModelContainer?
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // A per-test suite, so the one-shot migration flag cannot leak from
        // one test into another and silently turn a migration into a no-op.
        suiteName = "zoon.tests.behaviors.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        container = nil
        super.tearDown()
    }

    private func makeStore() throws -> BehaviorObservationStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BehaviorObservationRecord.self, JournalEntry.self,
            configurations: config
        )
        self.container = container
        return BehaviorObservationStore(context: container.mainContext)
    }

    private func makeStoreAndJournal() throws -> (BehaviorObservationStore, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: BehaviorObservationRecord.self, JournalEntry.self,
            configurations: config
        )
        self.container = container
        return (BehaviorObservationStore(context: container.mainContext), container.mainContext)
    }

    private let night = "2024-06-01@UTC"

    // MARK: - Reading and writing

    func testAnUnwrittenBehaviourIsUnknown() throws {
        let store = try makeStore()
        XCTAssertEqual(store.answers(forNightKey: night).state(for: .alcohol), .unknown)
        XCTAssertFalse(store.answers(forNightKey: night).hasAnyAnswer)
    }

    func testRecordingYesAndNo() throws {
        let store = try makeStore()
        store.set(.yes, for: .alcohol, nightKey: night)
        store.set(.no, for: .caffeineLate, nightKey: night)

        let answers = store.answers(forNightKey: night)
        XCTAssertEqual(answers.state(for: .alcohol), .yes)
        XCTAssertEqual(answers.state(for: .caffeineLate), .no)
        XCTAssertEqual(answers.state(for: .sauna), .unknown,
                       "answering two behaviours says nothing about a third")
    }

    func testChangingAnAnswerUpdatesRatherThanDuplicates() throws {
        let store = try makeStore()
        store.set(.yes, for: .alcohol, nightKey: night)
        store.set(.no, for: .alcohol, nightKey: night)

        XCTAssertEqual(store.answers(forNightKey: night).state(for: .alcohol), .no)
        XCTAssertEqual(store.allRecords().count, 1, "one row per night and behaviour")
    }

    /// Clearing deletes the row rather than storing `.unknown`, so an absent
    /// row is the single representation of "never answered".
    func testClearingRemovesTheRow() throws {
        let store = try makeStore()
        store.set(.yes, for: .alcohol, nightKey: night)
        store.set(.unknown, for: .alcohol, nightKey: night)

        XCTAssertEqual(store.answers(forNightKey: night).state(for: .alcohol), .unknown)
        XCTAssertTrue(store.allRecords().isEmpty)
    }

    func testCycleWalksThroughAllThreeStates() throws {
        let store = try makeStore()
        XCTAssertEqual(store.cycle(.alcohol, nightKey: night), .yes)
        XCTAssertEqual(store.cycle(.alcohol, nightKey: night), .no)
        XCTAssertEqual(store.cycle(.alcohol, nightKey: night), .unknown)
        XCTAssertEqual(store.cycle(.alcohol, nightKey: night), .yes)
    }

    func testAnswersAreScopedToTheirNight() throws {
        let store = try makeStore()
        let other = "2024-06-02@UTC"
        store.set(.yes, for: .alcohol, nightKey: night)

        XCTAssertEqual(store.answers(forNightKey: other).state(for: .alcohol), .unknown)
        let grouped = store.allAnswersByNightKey()
        XCTAssertEqual(grouped[night]?.state(for: .alcohol), .yes)
        XCTAssertNil(grouped[other])
    }

    // MARK: - Bulk negatives

    func testAnswerRemainingNoFillsOnlyTheUnanswered() throws {
        let store = try makeStore()
        store.set(.yes, for: .alcohol, nightKey: night)

        let candidates: [BehaviorTag] = [.alcohol, .caffeineLate, .sauna]
        let recorded = store.answerRemainingNo(nightKey: night, candidates: candidates)

        XCTAssertEqual(recorded, 2, "alcohol was already answered")
        let answers = store.answers(forNightKey: night)
        XCTAssertEqual(answers.state(for: .alcohol), .yes, "an existing yes is not overwritten")
        XCTAssertEqual(answers.state(for: .caffeineLate), .no)
        XCTAssertEqual(answers.state(for: .sauna), .no)
    }

    /// The bulk action is scoped to the candidates it was handed, so a
    /// behaviour the user has untracked in Settings does not silently acquire
    /// a negative it was never asked about.
    func testAnswerRemainingNoIgnoresBehavioursOutsideTheCandidateList() throws {
        let store = try makeStore()
        store.answerRemainingNo(nightKey: night, candidates: [.alcohol])
        XCTAssertEqual(store.answers(forNightKey: night).state(for: .caffeineLate), .unknown)
    }

    // MARK: - Legacy migration

    private func insertEntry(
        into context: ModelContext,
        daysAgo: Int,
        tags: [BehaviorTag],
        nightKey: String?
    ) -> JournalEntry {
        let date = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        )
        let entry = JournalEntry(date: date, tags: tags, nightKey: nightKey)
        context.insert(entry)
        return entry
    }

    func testMigrationTurnsLegacyPositiveTagsIntoYes() throws {
        let (store, context) = try makeStoreAndJournal()
        _ = insertEntry(into: context, daysAgo: 1, tags: [.alcohol, .sauna], nightKey: night)

        let created = store.migrateLegacyTags(
            from: try context.fetch(FetchDescriptor<JournalEntry>()), defaults: defaults
        )

        XCTAssertEqual(created, 2)
        let answers = store.answers(forNightKey: night)
        XCTAssertEqual(answers.state(for: .alcohol), .yes)
        XCTAssertEqual(answers.state(for: .sauna), .yes)
    }

    /// The load-bearing assertion of the whole migration. Back-filling `.no`
    /// for absent tags would bake the fabricated control arm permanently into
    /// the store, where no later fix could find it.
    func testMigrationNeverWritesANegative() throws {
        let (store, context) = try makeStoreAndJournal()
        _ = insertEntry(into: context, daysAgo: 1, tags: [.alcohol], nightKey: night)

        store.migrateLegacyTags(
            from: try context.fetch(FetchDescriptor<JournalEntry>()), defaults: defaults
        )

        XCTAssertTrue(store.allRecords().allSatisfy { $0.state == .yes },
                      "migration produces yes rows and nothing else")
        XCTAssertEqual(store.answers(forNightKey: night).state(for: .caffeineLate), .unknown)
    }

    /// An entry predating `JournalEntry.nightKey` has no night identity to
    /// attach an observation to. It is skipped rather than guessed at -- the
    /// legacy tag still reaches the engines through
    /// `Observation.exposureState(for:)`, which treats a positive tag as yes.
    func testMigrationSkipsEntriesWithNoNightKey() throws {
        let (store, context) = try makeStoreAndJournal()
        _ = insertEntry(into: context, daysAgo: 1, tags: [.alcohol], nightKey: nil)

        let created = store.migrateLegacyTags(
            from: try context.fetch(FetchDescriptor<JournalEntry>()), defaults: defaults
        )

        XCTAssertEqual(created, 0)
        XCTAssertTrue(store.allRecords().isEmpty)
    }

    func testMigrationRunsOnceThenBecomesANoOp() throws {
        let (store, context) = try makeStoreAndJournal()
        _ = insertEntry(into: context, daysAgo: 1, tags: [.alcohol], nightKey: night)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())

        XCTAssertEqual(store.migrateLegacyTags(from: entries, defaults: defaults), 1)
        XCTAssertEqual(store.migrateLegacyTags(from: entries, defaults: defaults), 0,
                       "the flag stops a second pass")
    }

    /// Re-running with `force` must not clobber an answer the user has since
    /// changed. A migrated yes that the user corrected to no stays no.
    func testAForcedRerunDoesNotOverwriteAChangedAnswer() throws {
        let (store, context) = try makeStoreAndJournal()
        _ = insertEntry(into: context, daysAgo: 1, tags: [.alcohol], nightKey: night)
        let entries = try context.fetch(FetchDescriptor<JournalEntry>())

        store.migrateLegacyTags(from: entries, defaults: defaults)
        store.set(.no, for: .alcohol, nightKey: night)

        let created = store.migrateLegacyTags(from: entries, force: true, defaults: defaults)
        XCTAssertEqual(created, 0)
        XCTAssertEqual(store.answers(forNightKey: night).state(for: .alcohol), .no)
    }

    /// A tag identifier this build does not recognise is carried through as a
    /// row rather than dropped or crashed on, and reads as unknown for every
    /// known behaviour.
    func testMigrationToleratesAnUnrecognisedIdentifier() throws {
        let (store, context) = try makeStoreAndJournal()
        let entry = insertEntry(into: context, daysAgo: 1, tags: [], nightKey: night)
        entry.tagIdentifiers = ["behaviourFromAFutureBuild"]

        let created = store.migrateLegacyTags(
            from: try context.fetch(FetchDescriptor<JournalEntry>()), defaults: defaults
        )

        XCTAssertEqual(created, 1)
        XCTAssertNil(store.allRecords().first?.tag)
        for tag in BehaviorTag.allCases {
            XCTAssertEqual(store.answers(forNightKey: night).state(for: tag), .unknown, tag.rawValue)
        }
    }

    // MARK: - Deletion

    func testDeleteAllRemovesEverything() throws {
        let store = try makeStore()
        store.set(.yes, for: .alcohol, nightKey: night)
        store.set(.no, for: .sauna, nightKey: "2024-06-02@UTC")

        XCTAssertTrue(store.deleteAll())
        XCTAssertTrue(store.allRecords().isEmpty)
    }

    // MARK: - Provisional identity

    /// A provisional key cannot collide with a real `nightKey`, which always
    /// carries an `@<timezone>` suffix.
    func testProvisionalKeyCannotLookLikeARealNightKey() {
        let key = BehaviorObservationRecord.provisionalNightKey(for: .now)
        XCTAssertTrue(key.hasPrefix("pending:"))
        XCTAssertFalse(key.contains("@"))
    }

    func testProvisionalKeyIsStableForTheSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 7))!
        let evening = calendar.date(from: DateComponents(year: 2024, month: 6, day: 1, hour: 23))!

        XCTAssertEqual(
            BehaviorObservationRecord.provisionalNightKey(for: morning, calendar: calendar),
            BehaviorObservationRecord.provisionalNightKey(for: evening, calendar: calendar)
        )
    }
}
