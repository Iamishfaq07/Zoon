import XCTest
import SwiftData

/// Restores the coverage dropped in "Drop SleepHistoryStorePruneTests -- crashes
/// the test process, cause unknown".
///
/// The cause, finally read off a symbolicated CI crash report rather than
/// guessed at: the `ModelContainer` was a local inside the `makeStore()`
/// factory, so it was released the moment that function returned, while the
/// store it returned went on holding that container's `mainContext`. The
/// first fetch afterwards traps inside SwiftData -- EXC_BREAKPOINT/SIGTRAP,
/// three SwiftData frames sitting directly under `JournalStore.entry(for:)`
/// -- and takes the process with it, with no XCTest failure message.
/// Retaining the container on the test case is the fix. The August attempt
/// used this same factory shape, so this was its bug too.
///
/// Worth recording what it was NOT, since each was tested and disproven
/// across five CI runs: SwiftData in an unhosted test bundle (a bare probe
/// passes), `#Predicate` evaluation (a predicate probe passes), and
/// sync-vs-async invocation on a `@MainActor` XCTestCase (the crash stack
/// shows the async thunks, so isolation was never involved). The
/// HealthKit-free extraction of `RollingBaseline` and `AnchorStore.clear()`
/// was still needed -- without it these files do not compile into this
/// target at all -- but it was never what caused the crash.
///
/// Tests stay `async throws`: harmless, and right for a `@MainActor` case.
///
/// `prune` is worth this trouble: it is the only thing that removes a stored
/// night whose HealthKit sample was later deleted or corrected away, and
/// getting its window scoping wrong would either strand stale rows forever or
/// erase real history outside the re-verified window.
@MainActor
final class SleepHistoryStoreIntegrationTests: XCTestCase {

    /// Held for the lifetime of the test -- see the note in `makeStore()`.
    private var container: ModelContainer?

    private func makeStore() throws -> SleepHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self,
            configurations: config
        )
        // Retained above. A container that goes out of scope here takes the
        // in-memory store with it while the returned SleepHistoryStore still
        // holds its mainContext, and the next fetch traps inside SwiftData.
        self.container = container
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
