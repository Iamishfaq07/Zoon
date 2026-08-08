import SwiftUI
import SwiftData

/// Zoon Sleep — local-first sleep insights.
///
/// The whole object graph is assembled here and injected through the
/// environment. There are no singletons and no global mutable state: every
/// dependency is constructible in a test or a preview with different arguments,
/// which is what makes `PreviewSupport` possible.
@main
struct ZoonApp: App {

    /// Persistent store. Created once for the process lifetime.
    private let modelContainer: ModelContainer

    @State private var coordinator: SleepDataCoordinator
    @State private var preferences: UserPreferences
    @State private var naps: NapStore
    @State private var soundscape: SoundscapeEngine
    @State private var reminders: BedtimeReminder

    init() {
        let preferences = UserPreferences()

        // If an App Group is configured, the store lives in the shared container
        // so future features (and any diagnostics) can reach it from the
        // extension. Without one it falls back to the app's own container —
        // fully functional, just not shared. See `AppGroup` and SETUP.md.
        let configuration: ModelConfiguration
        if let groupURL = AppGroup.containerURL {
            configuration = ModelConfiguration(url: groupURL.appendingPathComponent("Zoon.store"))
        } else {
            configuration = ModelConfiguration()
        }

        let container: ModelContainer
        do {
            container = try ModelContainer(
                for: SleepNightRecord.self, JournalEntry.self,
                configurations: configuration
            )
        } catch {
            // An unopenable store means a schema the app can't read. There is no
            // safe partial mode here, and silently falling back to in-memory
            // would quietly discard the user's history on every launch — a worse
            // outcome than a crash that surfaces the bug.
            fatalError("Could not open the Zoon data store: \(error)")
        }

        self.modelContainer = container

        // @State properties must be seeded through their storage in init, not
        // assigned directly.
        // Built as locals first: the coordinator needs the same NapStore
        // instance the views get, and reading a @State's wrapped value during
        // init isn't valid.
        let naps = NapStore()

        _preferences = State(initialValue: preferences)
        _naps = State(initialValue: naps)
        _soundscape = State(initialValue: SoundscapeEngine())
        _reminders = State(initialValue: BedtimeReminder())
        _coordinator = State(
            initialValue: SleepDataCoordinator(
                healthKit: HealthKitManager(),
                store: SleepHistoryStore(context: container.mainContext),
                journal: JournalStore(context: container.mainContext),
                naps: naps,
                preferences: preferences
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(preferences)
                .environment(naps)
                .environment(soundscape)
                .environment(reminders)
        }
        .modelContainer(modelContainer)
    }
}
