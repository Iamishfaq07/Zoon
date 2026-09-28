#if os(iOS)
import AppIntents
import Foundation

// The intents behind Zoon's Control Center buttons and interactive widget
// buttons. Each one opens the app on a screen.
//
// Here in Shared, so they compile into the app as well as the widget
// extension. Apple requires an `openAppWhenRun` intent to be a member of
// both: compiled only into the extension (where they used to live, beside
// the controls), `perform()` ran there, wrote its link, and Zoon never
// opened -- the tap did nothing, and the link fired the next time the app
// was opened, starting Wind Down in the morning.
//
// iOS only: Shared also builds the watch targets, which have neither
// Control Center controls nor these widgets.

/// Leaves `destination` for `RootView` and, in the app process, tells it
/// straight away.
@MainActor
private func openApp(on destination: DeepLink.Destination, startingWindDown: Bool = false) {
    DeepLink.pending = destination
    if startingWindDown { DeepLink.pendingStartsWindDown = true }
    NotificationCenter.default.post(name: DeepLink.postedNotification, object: nil)
}

/// Opens the app on the soundscapes screen.
@available(iOS 18.0, *)
struct OpenSoundscapesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sleep Sounds"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openApp(on: .soundscapes)
        return .result()
    }
}

@available(iOS 18.0, *)
struct OpenNapIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Nap Timer"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openApp(on: .nap)
        return .result()
    }
}

/// Starts what it names: tapped at bedtime, a "Wind Down" that only opened a
/// settings screen would be a control that does nothing. The app does the
/// work (`RootView.consumeDeepLink`).
@available(iOS 18.0, *)
struct OpenWindDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Begin Wind Down"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openApp(on: .windDown, startingWindDown: true)
        return .result()
    }
}

/// Backs the Tonight widget's tap-through.
///
/// Patterns rather than Today: the widget shows tonight's target and
/// tomorrow's range, and Patterns is where the forecast those come from is
/// explained. Not gated on iOS 18 like the Control Center intents above: an
/// `AppIntent` behind a widget `Button` needs only the deployment target.
struct OpenPatternsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Your Patterns"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openApp(on: .patterns)
        return .result()
    }
}

/// Backs the interactive "Log a habit" button on the medium Sleep Score
/// widget.
struct OpenJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Journal"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        openApp(on: .journal)
        return .result()
    }
}
#endif
