import SwiftData

/// Opens the same `ModelContainer` configuration the app uses, so anything
/// running outside `ZoonApp`'s own process lifetime -- an App Intent invoked
/// by Siri or Shortcuts, most notably -- reads and writes the identical store
/// rather than a second, silently diverging one.
enum PersistentStore {
    static func open() throws -> ModelContainer {
        // Same App Group reasoning as `SnapshotStore`: shared container when
        // configured, so an intent process (which may be a fresh launch, not
        // the running app) still finds the real data. See `AppGroup`.
        let configuration: ModelConfiguration
        if let groupURL = AppGroup.containerURL {
            configuration = ModelConfiguration(url: groupURL.appendingPathComponent("Zoon.store"))
        } else {
            configuration = ModelConfiguration()
        }
        return try ModelContainer(
            for: SleepNightRecord.self, JournalEntry.self,
            configurations: configuration
        )
    }
}
