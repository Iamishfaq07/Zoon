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
            for: SleepNightRecord.self, JournalEntry.self, SleepEpisodeRecord.self,
            BehaviorObservationRecord.self,
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
        // Observations are counted too. A destination holding only
        // behaviour answers -- possible once those can arrive from an
        // archive import before any night syncs -- would otherwise read
        // as empty and be treated as a fresh install to copy over.
        let destinationObservationCount = try destinationContext.fetchCount(
            FetchDescriptor<BehaviorObservationRecord>()
        )
        let destinationHasData = destinationNightCount > 0
            || destinationJournalCount > 0
            || destinationObservationCount > 0
        guard !destinationHasData else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        guard let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) else {
            defaults.set(true, forKey: migrationKey)
            return
        }

        let legacy = try ModelContainer(
            for: SleepNightRecord.self, JournalEntry.self, SleepEpisodeRecord.self,
            BehaviorObservationRecord.self,
            configurations: ModelConfiguration()
        )
        // If this throws, it propagates out of this function before reaching
        // the migrationKey/eraseLegacyStoreFiles() calls below, so a failed
        // copy never marks the migration done or deletes the source -- the
        // next launch retries from scratch instead of losing data.
        try copy(from: legacy.mainContext, into: destinationContext)

        defaults.set(true, forKey: migrationKey)
        _ = eraseLegacyStoreFiles()
    }

    /// The actual record copy, factored out of `migrateLegacyStoreIfNeeded`
    /// so the file-system/App-Group-entitlement plumbing above stays
    /// separate from the migration logic itself. Not covered by an
    /// automated test: prior attempts to exercise SwiftData `ModelContainer`
    /// operations directly in `ZoonTests` crashed the whole test process
    /// rather than failing an assertion (see `Tools/generate-pbxproj.py`'s
    /// `TESTS_EXTRA_APP_FILES` comment for the earlier, still-unexplained
    /// case). Verified by direct code reading instead.
    ///
    /// Copies `SleepEpisodeRecord` (naps and secondary-sleep blocks)
    /// alongside `SleepNightRecord`/`JournalEntry`. An earlier version of
    /// this migration only copied the latter two, which meant enabling an
    /// App Group after already accumulating nap history silently dropped
    /// every nap: `eraseLegacyStoreFiles()` deletes the legacy store right
    /// after migration, so the omission was permanent data loss.
    static func copy(from source: ModelContext, into destination: ModelContext) throws {
        let nights = try source.fetch(FetchDescriptor<SleepNightRecord>())
        let entries = try source.fetch(FetchDescriptor<JournalEntry>())
        let episodes = try source.fetch(FetchDescriptor<SleepEpisodeRecord>())
        let observations = try source.fetch(FetchDescriptor<BehaviorObservationRecord>())

        for night in nights {
            let copy = SleepNightRecord(
                features: night.features(),
                absoluteWristTempC: night.wristTempAbsoluteC,
                insight: night.cachedInsight,
                nightKey: night.nightKey
            )
            copy.createdAt = night.createdAt
            destination.insert(copy)
        }
        for entry in entries {
            // `nightKey` is passed through rather than dropped. Omitting
            // it silently downgraded every migrated entry to `date`-only
            // matching, which disagrees with a night's own key exactly on
            // travel days -- and `eraseLegacyStoreFiles()` deletes the
            // source right afterwards, so the loss was permanent. It also
            // now decides which observations a legacy tag can be
            // forward-filled into (see `BehaviorObservationStore`).
            let copy = JournalEntry(date: entry.date, nightKey: entry.nightKey)
            copy.tagIdentifiers = entry.tagIdentifiers
            copy.note = entry.note
            copy.feelingRaw = entry.feelingRaw
            copy.restedRaw = entry.restedRaw
            copy.energyRaw = entry.energyRaw
            copy.sleepinessRaw = entry.sleepinessRaw
            copy.moodRaw = entry.moodRaw
            copy.updatedAt = entry.updatedAt
            destination.insert(copy)
        }
        for episode in episodes {
            let copy = SleepEpisodeRecord(
                id: episode.id,
                nightKey: episode.nightKey,
                startDate: episode.startDate,
                endDate: episode.endDate,
                timezoneIdentifier: episode.timezoneIdentifier,
                episodeType: episode.episodeType,
                asleepMinutes: episode.asleepMinutes,
                timeInBedMinutes: episode.timeInBedMinutes,
                sourceName: episode.sourceName
            )
            copy.createdAt = episode.createdAt
            destination.insert(copy)
        }
        for observation in observations {
            destination.insert(BehaviorObservationRecord(
                nightKey: observation.nightKey,
                behaviorIdentifier: observation.behaviorIdentifier,
                state: observation.state,
                source: observation.source,
                observedAt: observation.observedAt
            ))
        }
        try destination.save()
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
