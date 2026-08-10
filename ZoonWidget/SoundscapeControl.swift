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
