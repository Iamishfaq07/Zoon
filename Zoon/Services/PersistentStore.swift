import Foundation
import SwiftData

/// Opens the same `ModelContainer` configuration the app uses, so anything
/// running outside `ZoonApp`'s own process lifetime -- an App Intent invoked
/// by Siri or Shortcuts, most notably -- reads and writes the identical store
/// rather than a second, silently diverging one.
enum PersistentStore {
    private static let migrationKey = "zoon.store.didMigrateToAppGroup"

    @MainActor
    static func open() throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let groupURL = AppGroup.containerURL {
            configuration = ModelConfiguration(
                url: groupURL.appendingPathComponent("Zoon.store")
            )
        } else {
            configuration = ModelConfiguration()
        }

        let container = try ModelContainer(
            for: SleepNightRecord.self, JournalEntry.self,
            configurations: configuration
        )
        if AppGroup.isConfigured {
            try migrateLegacyStoreIfNeeded(into: container)
        }
        return container
    }

    /// Migrates records when App Groups are enabled after the app has already
    /// accumulated history in SwiftData's default Application Support store.
    /// Without this, switching containers looks exactly like data loss.
    @MainActor
    private static func migrateLegacyStoreIfNeeded(
        into destination: ModelContainer
    ) throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let destinationContext = destination.mainContext
        let destinationNightCount = try destinationContext.fetchCount(
            FetchDescriptor<SleepNightRecord>()
        )
        let destinationJournalCount = try destinationContext.fetchCount(
            FetchDescriptor<JournalEntry>()
        )
        let destinationHasData = destinationNightCount > 0 || destinationJournalCount > 0
        guard !destinationHasData else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        guard let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        do {
            let legacy = try ModelContainer(
                for: SleepNightRecord.self, JournalEntry.self,
                configurations: ModelConfiguration()
            )
            let source = legacy.mainContext
            let nights = try source.fetch(FetchDescriptor<SleepNightRecord>())
            let entries = try source.fetch(FetchDescriptor<JournalEntry>())

            for night in nights {
                let copy = SleepNightRecord(
                    features: night.features(),
                    absoluteWristTempC: night.wristTempAbsoluteC,
                    insight: night.cachedInsight,
                    nightKey: night.nightKey
                )
                copy.createdAt = night.createdAt
                destinationContext.insert(copy)
            }
            for entry in entries {
                let copy = JournalEntry(date: entry.date)
                copy.tagIdentifiers = entry.tagIdentifiers
                copy.note = entry.note
                copy.updatedAt = entry.updatedAt
                destinationContext.insert(copy)
            }
            try destinationContext.save()
        }

        defaults.set(true, forKey: migrationKey)
        _ = eraseLegacyStoreFiles()
    }

    private static var legacyURL: URL? {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("default.store")
    }

    /// Removes a migrated default store and its SQLite sidecars. Never runs
    /// unless the App Group container is active, so it cannot delete the live
    /// fallback store used by an unconfigured build.
    @discardableResult
    static func eraseLegacyStoreFiles() -> Bool {
        guard AppGroup.isConfigured, let legacyURL else { return true }
        let urls = [
            legacyURL,
            URL(fileURLWithPath: legacyURL.path + "-shm"),
            URL(fileURLWithPath: legacyURL.path + "-wal"),
        ]
        var succeeded = true
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }
}
