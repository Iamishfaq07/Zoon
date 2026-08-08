import WidgetKit
import SwiftUI

/// Widget extension entry point.
///
/// The extension deliberately depends on very little: the `Shared/` folder only.
/// It never opens SwiftData and never touches HealthKit — a widget process has a
/// small memory ceiling and gets killed without ceremony when it exceeds it, and
/// running the extraction pipeline there would be a good way to find that out in
/// production. It reads one small JSON snapshot the app writes.
@main
struct ZoonWidgetBundle: WidgetBundle {
    var body: some Widget {
        SleepDebtWidget()
        SleepScoreWidget()

        // Live Activities and Control Center controls are both newer than the
        // app's iOS 18 floor in places, so each is gated rather than assumed.
        #if canImport(ActivityKit)
        NapLiveActivity()
        #endif

        if #available(iOS 18.0, *) {
            SoundscapeControl()
            NapControl()
        }
    }
}
