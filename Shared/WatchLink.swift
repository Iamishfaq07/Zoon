import Foundation
import os
#if os(watchOS)
import WidgetKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#else
#warning("WatchConnectivity unavailable: the watch app will show no data in this build.")
#endif

/// Carries the snapshot between the phone and the watch.
///
/// ## Why not an App Group
///
/// The widget extension reads a shared container. The watch cannot: it is a
/// separate device with a separate filesystem. WatchConnectivity is the only
/// route, and it happens to be the right one here anyway — it is a direct
/// encrypted link between two devices the same person owns, with no server in
/// the middle. The no-network promise survives intact.
///
/// ## Why `updateApplicationContext`
///
/// Three transports exist and only one fits:
///
/// - `sendMessage` needs both apps running and reachable. The watch app is
///   usually not running.
/// - `transferUserInfo` queues every message and delivers all of them, in
///   order. For a value that is only ever "the latest state", that queue is
///   pure waste — and it would replay a week of stale nights on reconnect.
/// - `updateApplicationContext` keeps exactly one payload, overwriting any
///   undelivered one, and delivers it when the counterpart next wakes. That is
///   precisely the semantics of "last night's numbers".
///
/// Not `public`: every target compiles these sources directly rather than
/// importing a module, so `public` here buys nothing and drags every type in
/// the signatures — `SleepSnapshot` among them — into needing it too.
@MainActor
@Observable
final class WatchLink: NSObject {

    /// Latest snapshot from the phone. `nil` until one arrives.
    private(set) var snapshot: SleepSnapshot?
    /// True once the session has activated, whether or not data has arrived.
    private(set) var isActivated = false

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "WatchLink")

    /// Single key in the context dictionary — the payload is one JSON blob
    /// rather than a spread of primitives, so `SleepSnapshot` stays the single
    /// definition of the wire format on both sides.
    private static let payloadKey = "snapshot"
    /// A tombstone is sent instead of an empty/invalid snapshot so an offline
    /// watch can erase its last value the next time WatchConnectivity delivers
    /// application context.
    private static let deletionKey = "snapshotDeleted"
    private static let pendingDeletionKey = "zoon.watch.pendingSnapshotDeletion"
    /// A refresh can finish before WCSession activation on a cold launch. Keep
    /// that value in memory and publish it from the activation callback rather
    /// than silently losing the night's only phone-to-watch hand-off.
    private var pendingSnapshot: SleepSnapshot?

    override init() {
        super.init()
    }

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            logger.notice("WCSession unsupported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        // A context may already be waiting from before this launch.
        apply(session.receivedApplicationContext)
        #endif
    }

    /// Phone side: publish the latest snapshot.
    ///
    /// Cheap enough to call on every refresh — the framework coalesces, and a
    /// context identical to the last one is dropped by the system rather than
    /// waking the watch for nothing.
    func send(_ snapshot: SleepSnapshot) {
        pendingSnapshot = snapshot
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try session.updateApplicationContext([Self.payloadKey: data])
            pendingSnapshot = nil
            UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
        } catch {
            logger.error("Could not send snapshot: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Phone side: replace the latest application context with an erasure
    /// tombstone. Watch side: `apply` removes both its in-memory value and the
    /// complication store before asking timelines to redraw.
    func clearSnapshot() {
        snapshot = nil
        pendingSnapshot = nil
        UserDefaults.standard.set(true, forKey: Self.pendingDeletionKey)
        sendPendingDeletionIfPossible()
    }

    private func sendPendingDeletionIfPossible() {
        #if canImport(WatchConnectivity)
        guard UserDefaults.standard.bool(forKey: Self.pendingDeletionKey) else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        do {
            try session.updateApplicationContext([Self.deletionKey: true])
            UserDefaults.standard.removeObject(forKey: Self.pendingDeletionKey)
        } catch {
            logger.error("Could not send snapshot deletion: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    private func apply(_ context: [String: Any]) {
        if context[Self.deletionKey] as? Bool == true {
            snapshot = nil
            #if os(watchOS)
            WatchSnapshotStore.clear()
            WidgetCenter.shared.reloadAllTimelines()
            #endif
            return
        }

        guard let data = context[Self.payloadKey] as? Data else { return }
        do {
            let decoded = try JSONDecoder().decode(SleepSnapshot.self, from: data)
            snapshot = decoded
            #if os(watchOS)
            // Park it where the complication extension can read it, and ask the
            // faces to redraw. The extension cannot hold a WCSession, so this
            // hand-off is the only route to a watch face.
            WatchSnapshotStore.save(decoded)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            // A decode failure here means the two sides are on different app
            // versions. Logged rather than surfaced: the watch showing slightly
            // stale numbers beats an error message about serialisation.
            logger.error("Could not decode snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if canImport(WatchConnectivity)
extension WatchLink: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isActivated = state == .activated
            if state == .activated {
                apply(session.receivedApplicationContext)
                if UserDefaults.standard.bool(forKey: Self.pendingDeletionKey) {
                    sendPendingDeletionIfPossible()
                } else if let pendingSnapshot {
                    send(pendingSnapshot)
                }
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext context: [String: Any]
    ) {
        Task { @MainActor in
            apply(context)
        }
    }

    // Required on iOS only, and both are no-ops here: the session is
    // reactivated on the next launch anyway.
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate so a second paired watch keeps working.
        WCSession.default.activate()
    }
    #endif
}
#endif
