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

/// Unlike the two above, this one starts what it names: tapped at bedtime,
/// "Wind Down" that only opened a settings screen would be the do-nothing
/// control the note at the top warns about. The app still does the work
/// (`RootView.consumeDeepLink`); this only asks for it.
@available(iOS 18.0, *)
struct WindDownControl: ControlWidget {

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.zoon.sleep.control.windDown") {
            ControlWidgetButton(action: OpenWindDownIntent()) {
                Label("Wind Down", systemImage: "moon.stars")
            }
        }
        .displayName("Wind Down")
        .description("Open Zoon and begin the Tonight routine.")
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
// So the controls above are inspectable only by building to a device or
// simulator and opening Control Center's gallery. If a future SDK adds a
// control-shaped preview, this comment is the thing to delete.

// MARK: - Intents

// The intents these controls and the widget buttons run live in
// `Shared/LaunchIntents.swift`, so the app target compiles them too: an
// `openAppWhenRun` intent only in the extension ran there, left its link,
// and never opened Zoon.
