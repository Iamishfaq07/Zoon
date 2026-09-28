import SwiftData
import XCTest

/// Breathing disturbances are events per hour of sleep, a HealthKit `count`
/// quantity. They used to be read as a percent and multiplied by 100, so 3.2
/// events an hour reached the screens and the clinician PDF as "320%". These
/// pin the unit rule, the one-time store conversion, and backup imports.
@MainActor
final class BreathingDisturbanceUnitsTests: XCTestCase {

    // MARK: - Reading

    func testBreathingDisturbancesAreStoredAsRead() {
        XCTAssertEqual(VitalMetric.breathingDisturbances.storedValue(fromReading: 3.2), 3.2)
    }

    func testBloodOxygenIsTheOnlyReadingThatChangesScale() {
        XCTAssertEqual(VitalMetric.oxygenSaturation.storedValue(fromReading: 0.97), 97, accuracy: 1e-9)
        for metric in VitalMetric.allCases where metric != .oxygenSaturation {
            XCTAssertEqual(metric.storedValue(fromReading: 42), 42, "\(metric) should be stored as read")
        }
    }

    func testVitalsShowEventsPerHourNotPercent() {
        XCTAssertEqual(VitalsStatus.Kind.breathingDisturbances.format(3.2), "3.2/h")
        XCTAssertEqual(VitalsStatus.Kind.breathingDisturbances.spokenFormat(3.2), "3.2 events per hour")
    }

    // MARK: - Retry-safe conversion plan

    func testAFirstAttemptConvertsEveryStoredValue() {
        let stored = ["a": 320.0, "b": 150.0]
        XCTAssertEqual(BreathingDisturbanceUnits.rowsNeedingConversion(stored: stored, pendingSnapshot: nil), ["a", "b"])
    }

    /// Killed after saving but before recording that it was done: every row
    /// now holds a hundredth of its snapshot, so nothing is divided again.
    func testARetryAfterASaveConvertsNothing() {
        let snapshot = ["a": 320.0, "b": 150.0]
        let stored = ["a": 3.2, "b": 1.5]
        XCTAssertTrue(BreathingDisturbanceUnits.rowsNeedingConversion(stored: stored, pendingSnapshot: snapshot).isEmpty)
    }

    /// Killed before the save: the rows still hold their old values.
    func testARetryBeforeASaveConvertsWhatIsStillOld() {
        let snapshot = ["a": 320.0, "b": 150.0]
        let stored = ["a": 320.0, "b": 150.0, "c": 2.0]
        XCTAssertEqual(BreathingDisturbanceUnits.rowsNeedingConversion(stored: stored, pendingSnapshot: snapshot), ["a", "b"])
    }

    // MARK: - Backups

    func testOldBackupsAreConvertedAndNewOnesAreNot() {
        var night = Fixture.night(daysAgo: 1)
        night.breathingDisturbances = 320
        let old = BreathingDisturbanceUnits.nightsFromArchive([night], formatVersion: 6)
        XCTAssertEqual(old.first?.breathingDisturbances ?? -1, 3.2, accuracy: 1e-9)
        let current = BreathingDisturbanceUnits.nightsFromArchive([night], formatVersion: DataExporter.formatVersion)
        XCTAssertEqual(current.first?.breathingDisturbances, 320)
        XCTAssertGreaterThan(DataExporter.formatVersion, BreathingDisturbanceUnits.lastLegacyArchiveFormat,
                             "exports must be stamped after the legacy format, or a fresh backup would be divided again on import")
    }

    func testNightsWithoutAReadingAreUntouched() {
        // The fixture carries a reading by default; this night has none.
        var night = Fixture.night(daysAgo: 1)
        night.breathingDisturbances = nil
        XCTAssertNil(BreathingDisturbanceUnits.nightsFromArchive([night], formatVersion: 6).first?.breathingDisturbances)
    }

    // MARK: - Store migration

    private var container: ModelContainer?

    private func makeStore() throws -> SleepHistoryStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SleepNightRecord.self, SleepEpisodeRecord.self, EvidenceRevisionRecord.self,
            configurations: config
        )
        // Retained: the in-memory store goes with its container.
        self.container = container
        return SleepHistoryStore(context: container.mainContext)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "BreathingDisturbanceUnitsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testTheStoreMigrationConvertsOnceAndOnlyOnce() throws {
        let store = try makeStore()
        var night = Fixture.night(daysAgo: 3)
        night.breathingDisturbances = 320
        store.upsert(night)
        let defaults = makeDefaults()

        store.migrateBreathingDisturbanceUnitsIfNeeded(defaults: defaults)
        XCTAssertEqual(store.night(on: night.date)?.breathingDisturbances ?? -1, 3.2, accuracy: 1e-9)
        XCTAssertTrue(defaults.bool(forKey: SleepHistoryStore.breathingUnitsMigratedKey))

        store.migrateBreathingDisturbanceUnitsIfNeeded(defaults: defaults)
        XCTAssertEqual(store.night(on: night.date)?.breathingDisturbances ?? -1, 3.2, accuracy: 1e-9,
                       "a second run must not divide again")
    }

    func testAMigrationInterruptedAfterItsSaveDoesNotDivideAgain() throws {
        let store = try makeStore()
        var night = Fixture.night(daysAgo: 3)
        night.breathingDisturbances = 3.2
        store.upsert(night)
        let defaults = makeDefaults()
        // As if an earlier run recorded its snapshot, saved, and was killed
        // before it could mark itself done.
        defaults.set([BreathingDisturbanceUnits.rowKey(for: night.date): 320.0],
                     forKey: SleepHistoryStore.breathingUnitsSnapshotKey)

        store.migrateBreathingDisturbanceUnitsIfNeeded(defaults: defaults)
        XCTAssertEqual(store.night(on: night.date)?.breathingDisturbances ?? -1, 3.2, accuracy: 1e-9)
        XCTAssertTrue(defaults.bool(forKey: SleepHistoryStore.breathingUnitsMigratedKey))
    }
}
