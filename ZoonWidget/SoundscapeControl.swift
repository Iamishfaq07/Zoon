import SwiftUI
import WidgetKit
import AppIntents

/// Control Center buttons for Zoon's sleep tools.
///
/// ## Why these open the app rather than acting in place
///
/// A `ControlWidget` runs in the widget extension, which cannot start audio —
/// `AVAudioEngine` there has no audio session to speak of, and even if it
/// somehow started, the sound would die with the extension moments later.
/// Playing a soundscape has to happen in the app process.
///
/// So these are launchers, and the copy says so. A control that appears to
/// start something and silently doesn't would be worse than no control: it's
/// the kind of thing you tap in a dark bedroom and then spend a minute working
/// out why nothing happened.
///
/// The value is still real — one tap from a locked phone to the sleep sounds,
/// without hunting for an icon.
@available(iOS 18.0, *)
struct SoundscapeControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zoon.sleep.control.soundscape") {
            ControlWidgetButton(action: OpenSoundscapesIntent()) {
                Label("Sleep Sounds", systemImage: "waveform")
            }
        }
        .displayName("Sleep Sounds")
        .description("Open Zoon's generated soundscapes.")
    }
}

@available(iOS 18.0, *)
struct NapControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zoon.sleep.control.nap") {
            ControlWidgetButton(action: OpenNapIntent()) {
                Label("Nap", systemImage: "powersleep")
            }
        }
        .displayName("Nap")
        .description("Open Zoon's nap timer.")
    }
}

// MARK: - Previews

// There are none, and that is a verified fact rather than an oversight.
//
// Every other file in this target carries #Preview blocks; a reader is
// entitled to wonder why this one does not. `#Preview(as:)` is a Widget-only
// macro, so a ControlWidget cannot go through it. Tried on this SDK, all
// three errors from one build:
//
//     macro 'Preview(_:as:widget:timeline:)' requires that
//       'SoundscapeControl' conform to 'Widget'
//     type 'WidgetFamily' has no member 'controlCenter'
//     cannot find 'ControlWidgetPreviewValue' in scope
//
// So the two controls above are inspectable only by building to a device or
// simulator and opening Control Center's gallery. If a future SDK adds a
// control-shaped preview, this comment is the thing to delete.

// MARK: - Intents

/// Opens the app on the soundscapes screen.
///
/// `openAppWhenRun` is what makes this a launcher; `ZoonApp` reads the pending
/// destination on activation.
@available(iOS 18.0, *)
struct OpenSoundscapesIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sleep Sounds"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.pending = .soundscapes
        return .result()
    }
}

@available(iOS 18.0, *)
struct OpenNapIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Nap Timer"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.pending = .nap
        return .result()
    }
}

/// Backs the Tonight widget's tap-through.
///
/// Patterns rather than Today: the widget shows tonight's target and
/// tomorrow's range, and Patterns is where the forecast those come from is
/// actually explained. Sending someone to the Today screen would land them
/// on the same card they just tapped.
///
/// Not gated on iOS 18 like the two Control Center intents above -- those are
/// `ControlWidget` buttons, which is what needs the newer floor. An
/// `AppIntent` behind a widget `Button` is the same mechanism
/// `OpenJournalIntent` already uses on the Sleep Score widget.
struct OpenPatternsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Your Patterns"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.pending = .patterns
        return .result()
    }
}

/// Backs the interactive "Log a habit" button on the medium Sleep Score
/// widget, in addition to the Control Center buttons above.
struct OpenJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Journal"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DeepLink.pending = .journal
        return .result()
    }
}
