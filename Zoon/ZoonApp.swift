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
        let openedDisk: Bool

        do {
            container = try PersistentStore.open()
            storeOpeningError = nil
            openedDisk = true
        } catch {
            // Preserve the unreadable store. Do not replace it with an
            // in-memory one the rest of the app could mistake for empty
            // history. Recovery is a screen, not a second database.
            let openingError = error.localizedDescription
            // Probe the schema in memory so the recovery screen can say
            // whether the file is the problem or the models themselves are.
            // Used to be `fatalError` when this threw -- build 65 hit that
            // on a real device (EXC_BREAKPOINT inside App.main(), before any
            // window existed). #300 already stopped killing the process;
            // this path still must not construct the coordinator against
            // a throwaway container, because `start()` fetches models.
            do {
                _ = try PersistentStore.makeRecoveryContainer()
                storeOpeningError = openingError
            } catch {
                storeOpeningError = openingError
                    + "\n\nThe in-memory recovery store also failed: "
                    + error.localizedDescription
            }
            container = nil
            openedDisk = false
        }

        self.modelContainer = container
        self.storeOpeningError = storeOpeningError

        let naps = NapStore(wake: NapWake())
        let reminders = BedtimeReminder()

        _preferences = State(initialValue: preferences)
        _naps = State(initialValue: naps)
        _soundscape = State(initialValue: SoundscapeEngine())
        _reminders = State(initialValue: reminders)
        // Coordinator reads the store on `start()`. Build it only against a
        // container `open()` actually mounted. Build 65 constructed it against
        // the recovery container (and, when that container's schema had
        // drifted, against a fetch for a model that wasn't in it) -- `try?`
        // does not catch a SwiftData trap, so an unopenable store became a
        // silent repeating launch crash. #300 skipped the coordinator when
        // *both* containers failed; this also skips it for the in-memory
        // recovery container, which exists only as a diagnostic.
        if openedDisk, let container {
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
        } else {
            _coordinator = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer, let coordinator, storeOpeningError == nil {
                Group {
                    if preferences.hasCompletedOnboarding || LaunchOptions.skipsOnboarding {
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
                // Deliberately carries no .modelContainer and no coordinator:
                // this is the scene for when there is no store to give it.
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
