import SwiftUI
import SwiftData

/// Preview scaffolding.
///
/// Every `#Preview` in the app calls `zoonPreviewEnvironment()`, which builds a
/// fully-wired object graph backed by an **in-memory** SwiftData container and
/// mock data. Nothing here touches HealthKit or the on-disk store, so previews
/// render instantly in the Simulator and never mutate real history.
@MainActor
enum PreviewSupport {

    /// In-memory container — created once and reused. Building a fresh
    /// `ModelContainer` per preview is slow enough to be noticeable.
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(
                for: SleepNightRecord.self, JournalEntry.self, SleepEpisodeRecord.self,
                configurations: configuration
            )
        } catch {
            // A preview container that can't be built is a programmer error in
            // the schema, and there's no graceful degradation worth having here.
            fatalError("Preview container failed: \(error)")
        }
    }()

    static let preferences = UserPreferences(
        // A dedicated defaults suite so previews can't stomp on real settings.
        defaults: UserDefaults(suiteName: "com.zoon.sleep.previews") ?? .standard
    )
    static let naps = NapStore.preview
    static let reminders = BedtimeReminder()

    /// Coordinator pre-loaded with mock data.
    static var coordinator: SleepDataCoordinator {
        let coordinator = SleepDataCoordinator(
            healthKit: HealthKitManager(),
            store: SleepHistoryStore(context: container.mainContext),
            journal: JournalStore(context: container.mainContext),
            naps: naps,
            preferences: preferences,
            reminders: reminders
        )
        coordinator.loadMockData()
        return coordinator
    }
}

extension View {
    /// Injects everything a Zoon view needs to render in a preview.
    @MainActor
    func zoonPreviewEnvironment() -> some View {
        self
            .environment(PreviewSupport.coordinator)
            .environment(PreviewSupport.preferences)
            .environment(PreviewSupport.naps)
            .environment(SoundscapeEngine())
            .environment(PreviewSupport.reminders)
            .environment(GlobalPresentation())
            .modelContainer(PreviewSupport.container)
            .preferredColorScheme(.dark)
    }
}
