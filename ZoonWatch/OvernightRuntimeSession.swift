import Foundation
import WatchKit

/// Keep-alive for the watch app overnight, so Double Tap can still log a
/// midnight awakening after the screen blanks.
///
/// Deliberately **not** a second HealthKit pipeline. The watch remains a
/// reader: Apple's own sleep mode already writes stages and vitals to
/// Health, and the phone is the only process that reads them. This session
/// exists so the watch process is not jetsam'd while someone is asleep with
/// the app still the frontmost self-care session -- a `WKExtendedRuntimeSession`
/// of type `self-care` (declared in Info.plist `WKBackgroundModes`).
///
/// Self-care sessions are time-bounded by the system (typically around an
/// hour). That is enough to cover a wind-down and the first stretch of the
/// night; it is not a promise of dusk-to-dawn capture, and nothing here
/// pretends otherwise.
@MainActor
final class OvernightRuntimeSession: NSObject, WKExtendedRuntimeSessionDelegate {

    static let shared = OvernightRuntimeSession()

    private var session: WKExtendedRuntimeSession?
    private(set) var isRunning = false

    func start() {
        guard session == nil else { return }
        let next = WKExtendedRuntimeSession()
        next.delegate = self
        next.start()
        session = next
    }

    func invalidate() {
        session?.invalidate()
        session = nil
        isRunning = false
    }

    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.isRunning = true
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        // No extra work. The system is about to stop us; logging from here
        // would be a write during teardown.
    }

    nonisolated func extendedRuntimeSession(
        _ session: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            self.session = nil
            self.isRunning = false
        }
    }
}
