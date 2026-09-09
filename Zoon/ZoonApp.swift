import SwiftUI
import SwiftData

/// Zoon Sleep — local-first sleep insights.
///
/// The whole object graph is assembled here and injected through the
/// environment. Every dependency is constructible in a test or preview.
@main
@MainActor
struct ZoonApp: App {

    private let modelContainer: ModelContainer?
    private let storeOpeningError: String?

    @State private var coordinator: SleepDataCoordinator?
    @State private var preferences: UserPreferences
    @State private var naps: NapStore
    @State private var soundscape: SoundscapeEngine
    @State private var reminders: BedtimeReminder
    @State private var presentation = GlobalPresentation()

    init() {
        let preferences = UserPreferences()
        let container: ModelContainer?
        let storeOpeningError: String?

        do {
            container = try PersistentStore.open()
            storeOpeningError = nil
        } catch {
            // Preserve the unreadable store and mount only a recovery screen.
            // The normal app never sees this in-memory container, so it cannot
            // mistake the failure for empty history or overwrite the disk.
            let openingError = error.localizedDescription
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                // PersistentStore.schema, never a hand-repeated list: the two
                // had drifted, and a recovery container missing a model the
                // app immediately fetches traps instead of recovering.
                container = try ModelContainer(
                    for: PersistentStore.schema, configurations: fallback
                )
                storeOpeningError = openingError
            } catch {
                // Both containers failed. This used to be `fatalError`, and on
                // 2026-09-09 build 65 hit it on a real device: EXC_BREAKPOINT
                // on the main thread inside App.main(), before any window
                // existed. That is the worst shape a bug can take -- the app
                // dies instantly, every launch, showing nothing and saying
                // nothing, and the only way anyone learned why was reading a
                // .ips off the phone by hand.
                //
                // Nothing here is worth killing the process for. A scene that
                // needs no ModelContainer at all can still put both errors on
                // screen, where the person holding the phone can read them.
                container = nil
                storeOpeningError = openingError
                    + "\n\nThe in-memory recovery store also failed: "
                    + error.localizedDescription
            }
        }

        self.modelContainer = container
        self.storeOpeningError = storeOpeningError

        let naps = NapStore(wake: NapWake())
        let reminders = BedtimeReminder()

        _preferences = State(initialValue: preferences)
        _naps = State(initialValue: naps)
        _soundscape = State(initialValue: SoundscapeEngine())
        _reminders = State(initialValue: reminders)
        // No container means no stores to build -- and nothing that needs
        // them, because the only scene mounted in that case is the recovery
        // one. Building them anyway is what turned an unopenable store into
        // a crash.
        _coordinator = State(initialValue: container.map { container in
            SleepDataCoordinator(
                healthKit: HealthKitManager(),
                store: SleepHistoryStore(context: container.mainContext),
                journal: JournalStore(context: container.mainContext),
                behaviors: BehaviorObservationStore(context: container.mainContext),
                naps: naps,
                preferences: preferences,
                reminders: reminders
            )
        })
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer, let coordinator {
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
                .modelContainer(modelContainer)
            } else {
                // Deliberately carries no .modelContainer and no environment:
                // this is the scene for when there is no container to give it.
                StoreRecoveryView(
                    message: storeOpeningError ?? "The data store could not be opened."
                )
            }
        }
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
