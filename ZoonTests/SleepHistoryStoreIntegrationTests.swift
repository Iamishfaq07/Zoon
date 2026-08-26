import XCTest
import SwiftData

/// Restores the coverage dropped in "Drop SleepHistoryStorePruneTests -- crashes
/// the test process, cause unknown".
///
/// The cause turned out to be TWO independent bugs, which is why every
/// single-fix attempt looked wrong while the other bug was still present:
///
/// 1. Adding `SleepHistoryStore` to this target used to drag in
///    `FeatureExtractor.swift` (for `RollingBaseline`) and
///    `HealthKitManager.swift` (for `AnchorStore`), both `import HealthKit`.
///    Fixed by extracting those two types into HealthKit-free files.
/// 2. A synchronous `throws` test method on a `@MainActor` XCTestCase is
///    invoked through XCTest's non-async path, which never actually enters
///    the main actor -- the compiler emits no hop (it trusts the annotation),
///    and the first `@MainActor`-isolated call into the store trips the
///    runtime's executor assertion: EXC_BREAKPOINT (SIGTRAP), captured in
///    this repo's CI crash reports with `JournalEntry` metadata in the
///    faulting frame. That kills the process with no XCTest failure message.
///    Fixed by making every test method `async throws`, which uses the
///    concurrency-aware invocation path that does hop -- `SwiftDataProbeTests`
///    (async all along) passing in the same run these crashed as sync was
///    the isolating evidence.
///
/// So every test here must stay `async throws` even though nothing awaits.
///
/// `prune` is worth this trouble: it is the only thing that removes a stored
/// night whose HealthKit sample was later deleted or corrected away, and
/// getting its window scoping wrong would either strand stale rows forever or
/// erase real history outside the re-verified window.
@MainActor
final class SleepHistoryStoreIntegrationTests: XCTestCase {

    private func makeStore() throws -> SleepHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self,
            configurations: config
        )
        return SleepHistoryStore(context: container.mainContext)
    }

    @discardableResult
    private func insert(_ store: SleepHistoryStore, daysAgo: Int) -> Date {
        let features = Fixture.night(daysAgo: daysAgo)
        store.upsert(features)
        return features.date
    }

    // MARK: - Prune

    func testNightMissingFromAFreshFetchIsRemoved() async throws {
        let store = try makeStore()
        let staleDate = insert(store, daysAgo: 3)
        XCTAssertNotNil(store.night(on: staleDate))

        let window = DateInterval(start: staleDate.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNil(store.night(on: staleDate))
    }

    func testNightStillPresentInAFreshFetchSurvives() async throws {
        let store = try makeStore()
        let date = insert(store, daysAgo: 2)

        let window = DateInterval(start: date.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [date])

        XCTAssertNotNil(store.night(on: date))
    }

    /// The scoping guarantee: a night outside the re-verified window was never
    /// re-checked against HealthKit, so it must survive even though it isn't in
    /// `keeping` -- otherwise every sync would eventually erase all history
    /// older than the rolling window.
    func testNightOutsideTheWindowIsNeverTouched() async throws {
        let store = try makeStore()
        let oldDate = insert(store, daysAgo: 400)

        let window = DateInterval(start: .now.addingTimeInterval(-7 * 86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNotNil(store.night(on: oldDate))
    }

    func testPruneWithNothingKeptClearsEveryNightInTheWindow() async throws {
        let store = try makeStore()
        let recent = insert(store, daysAgo: 1)
        let older = insert(store, daysAgo: 2)

        let window = DateInterval(start: older.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNil(store.night(on: recent))
        XCTAssertNil(store.night(on: older))
    }

    // MARK: - Upsert

    /// Upsert, not insert: HealthKit revises nights, and a re-sync of the same
    /// night must update the existing row rather than duplicate it.
    func testUpsertingTheSameNightTwiceKeepsOneRow() async throws {
        let store = try makeStore()
        let date = insert(store, daysAgo: 1)

        store.upsert(Fixture.night(daysAgo: 1, timeAsleepMinutes: 400))

        XCTAssertEqual(store.allNights().filter { $0.date == date }.count, 1)
        XCTAssertEqual(store.night(on: date)?.timeAsleepMinutes ?? -1, 400, accuracy: 0.001)
    }

    func testUpsertStampsNightKeyWhenOneIsSupplied() async throws {
        let store = try makeStore()
        let features = Fixture.night(daysAgo: 1)

        store.upsert(features, nightKey: "night-key-1")

        XCTAssertEqual(store.night(on: features.date)?.nightKey, "night-key-1")
    }

    // MARK: - Import

    /// Restoring a backup merges into whatever the device has kept recording,
    /// rather than discarding it.
    func testImportNightsMergesRatherThanReplacing() async throws {
        let store = try makeStore()
        insert(store, daysAgo: 1)

        let written = store.importNights([Fixture.night(daysAgo: 5)])

        XCTAssertEqual(written, 1)
        XCTAssertEqual(store.allNights().count, 2)
    }
}
