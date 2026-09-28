import SwiftData
import XCTest

/// Nights restored from a backup survive a full sync that HealthKit on this
/// device knows nothing about, and stop being special once HealthKit returns
/// them. They used to be pruned by the next full sync: a new iPhone without
/// Health history, "Restored 212 nights", then three months gone.
@MainActor
final class RestoredNightProtectionTests: XCTestCase {

    private var container: ModelContainer?

    private func makeStore() throws -> SleepHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self, EvidenceRevisionRecord.self,
            configurations: config
        )
        // Retained: the in-memory store goes with its container.
        self.container = container
        let store = SleepHistoryStore(context: container.mainContext)
        store.restoredNightDefaults = UserDefaults(suiteName: "zoon.tests.restored.\(UUID().uuidString)")!
        return store
    }

    private func window(around date: Date) -> DateInterval {
        DateInterval(start: date.addingTimeInterval(-30 * 86_400), end: .now)
    }

    func testARestoredNightSurvivesAFullSyncThatDoesNotHaveIt() throws {
        let store = try makeStore()
        let night = Fixture.night(daysAgo: 10)
        XCTAssertEqual(store.importNights([night]), 1)

        store.prune(window: window(around: night.date), keeping: [])

        XCTAssertNotNil(store.night(on: night.date), "a restored night must not be deleted for being absent from HealthKit")
    }

    /// Once HealthKit has returned the night, it is an ordinary night again:
    /// deleting it in the Health app removes it here too.
    func testARestoredNightThatHealthKitLaterReturnsIsPrunedLikeAnyOther() throws {
        let store = try makeStore()
        let night = Fixture.night(daysAgo: 10)
        XCTAssertEqual(store.importNights([night]), 1)

        store.prune(window: window(around: night.date), keeping: [night.date])
        XCTAssertFalse(RestoredNightLedger.dates(in: store.restoredNightDefaults).contains(night.date))

        store.prune(window: window(around: night.date), keeping: [])
        XCTAssertNil(store.night(on: night.date))
    }

    func testANightThatWasNeverRestoredIsStillPruned() throws {
        let store = try makeStore()
        let night = Fixture.night(daysAgo: 4)
        store.upsert(night)

        store.prune(window: window(around: night.date), keeping: [])

        XCTAssertNil(store.night(on: night.date))
    }

    func testDeletingEverythingForgetsWhatWasRestored() throws {
        let store = try makeStore()
        XCTAssertEqual(store.importNights([Fixture.night(daysAgo: 6)]), 1)
        XCTAssertTrue(store.deleteAll())
        XCTAssertTrue(RestoredNightLedger.dates(in: store.restoredNightDefaults).isEmpty)
    }
}
