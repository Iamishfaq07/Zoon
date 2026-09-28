import SwiftUI

/// Zoon on the wrist.
///
/// Deliberately a *reader*, not a second copy of the app. The watch records the
/// sleep; the phone does the work; this shows the answer. Everything here is
/// three numbers and a glance, because that is the entire useful interaction
/// budget of a watch screen at 7am.
///
/// It holds no HealthKit code and no SwiftData store. The snapshot arrives over
/// WatchConnectivity — see `WatchLink` — which keeps this target small enough
/// to launch instantly and impossible to disagree with the phone.
@main
struct ZoonWatchApp: App {

    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(link)
                .task {
                    link.activate()
                }
                // No extended-runtime "keep-alive". A self-care session was
                // started on every launch so Double Tap could fire after the
                // screen blanked; self-care sessions last minutes, not a night,
                // and exist for guided self-care, so it neither did the job nor
                // matched its declared purpose (an App Review risk).
        }
    }
}
