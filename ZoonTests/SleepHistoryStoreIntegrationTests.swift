import XCTest
import SwiftData

/// Restores the coverage dropped in "Drop SleepHistoryStorePruneTests -- crashes
/// the test process, cause unknown".
///
/// The cause is now known and fixed. It was never SwiftData: adding
/// `SleepHistoryStore` to this target used to drag in `FeatureExtractor.swift`
/// (for `RollingBaseline`) and `HealthKitManager.swift` (for `AnchorStore`),
/// both of which `import HealthKit` -- and linking HealthKit into `ZoonTests`,
/// an unhosted bundle with no Health entitlements or usage descriptions, is
/// what killed the process before any assertion could run. `SwiftDataProbeTests`
/// isolated that by proving a bare `ModelContainer` runs here fine; splitting
/// `RollingBaseline` and `AnchorStore.clear()` into HealthKit-free files
/// removed the dependency entirely.
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

    func testNightMissingFromAFreshFetchIsRemoved() throws {
        let store = try makeStore()
        let staleDate = insert(store, daysAgo: 3)
        XCTAssertNotNil(store.night(on: staleDate))

        let window = DateInterval(start: staleDate.addingTimeInterval(-86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNil(store.night(on: staleDate))
    }

    func testNightStillPresentInAFreshFetchSurvives() throws {
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
    func testNightOutsideTheWindowIsNeverTouched() throws {
        let store = try makeStore()
        let oldDate = insert(store, daysAgo: 400)

        let window = DateInterval(start: .now.addingTimeInterval(-7 * 86_400), end: .now)
        store.prune(window: window, keeping: [])

        XCTAssertNotNil(store.night(on: oldDate))
    }

    func testPruneWithNothingKeptClearsEveryNightInTheWindow() throws {
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
    func testUpsertingTheSameNightTwiceKeepsOneRow() throws {
        let store = try makeStore()
        let date = insert(store, daysAgo: 1)

        store.upsert(Fixture.night(daysAgo: 1, timeAsleepMinutes: 400))

        XCTAssertEqual(store.allNights().filter { $0.date == date }.count, 1)
        XCTAssertEqual(store.night(on: date)?.timeAsleepMinutes ?? -1, 400, accuracy: 0.001)
    }

    func testUpsertStampsNightKeyWhenOneIsSupplied() throws {
        let store = try makeStore()
        let features = Fixture.night(daysAgo: 1)

        store.upsert(features, nightKey: "night-key-1")

        XCTAssertEqual(store.night(on: features.date)?.nightKey, "night-key-1")
    }

    // MARK: - Import

    /// Restoring a backup merges into whatever the device has kept recording,
    /// rather than discarding it.
    func testImportNightsMergesRatherThanReplacing() throws {
        let store = try makeStore()
        insert(store, daysAgo: 1)

        let written = store.importNights([Fixture.night(daysAgo: 5)])

        XCTAssertEqual(written, 1)
        XCTAssertEqual(store.allNights().count, 2)
    }
}
