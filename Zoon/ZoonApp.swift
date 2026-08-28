import SwiftUI
import SwiftData

/// Zoon Sleep — local-first sleep insights.
///
/// The whole object graph is assembled here and injected through the
/// environment. Every dependency is constructible in a test or preview.
@main
@MainActor
struct ZoonApp: App {

    private let modelContainer: ModelContainer
    private let storeOpeningError: String?

    @State private var coordinator: SleepDataCoordinator
    @State private var preferences: UserPreferences
    @State private var naps: NapStore
    @State private var soundscape: SoundscapeEngine
    @State private var reminders: BedtimeReminder
    @State private var presentation = GlobalPresentation()

    init() {
        let preferences = UserPreferences()
        let container: ModelContainer
        let storeOpeningError: String?

        do {
            container = try PersistentStore.open()
            storeOpeningError = nil
        } catch {
            // Preserve the unreadable store and mount only a recovery screen.
            // The normal app never sees this in-memory container, so it cannot
            // mistake the failure for empty history or overwrite the disk.
            storeOpeningError = error.localizedDescription
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                container = try ModelContainer(
                    for: SleepNightRecord.self, JournalEntry.self, SleepEpisodeRecord.self,
                    configurations: fallback
                )
            } catch {
                fatalError("Could not create recovery container: \(error)")
            }
        }

        self.modelContainer = container
        self.storeOpeningError = storeOpeningError

        let naps = NapStore()
        let reminders = BedtimeReminder()

        _preferences = State(initialValue: preferences)
        _naps = State(initialValue: naps)
        _soundscape = State(initialValue: SoundscapeEngine())
        _reminders = State(initialValue: reminders)
        _coordinator = State(
            initialValue: SleepDataCoordinator(
                healthKit: HealthKitManager(),
                store: SleepHistoryStore(context: container.mainContext),
                journal: JournalStore(context: container.mainContext),
                behaviors: BehaviorObservationStore(context: container.mainContext),
                naps: naps,
                preferences: preferences,
                reminders: reminders
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let storeOpeningError {
                    StoreRecoveryView(message: storeOpeningError)
                } else if preferences.hasCompletedOnboarding || LaunchOptions.skipsOnboarding {
                    RootView()
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.4), value: preferences.hasCompletedOnboarding)
            .environment(coordinator)
            .environment(preferences)
            .environment(naps)
            .environment(soundscape)
            .environment(reminders)
            .environment(presentation)
        }
        .modelContainer(modelContainer)
    }
}

private struct StoreRecoveryView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 46))
                .foregroundStyle(Theme.Metric.recoveryMid)
            Text("Zoon couldn't open your data")
                .font(Theme.label(22, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Your existing store has not been deleted or replaced. Quit and reopen Zoon after installing the latest update. If the problem continues, report the diagnostic below before resetting anything.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Link(
                "Report this problem",
                destination: URL(string: "https://github.com/Iamishfaq07/Zoon/issues")!
            )
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nightBackground()
    }
}
