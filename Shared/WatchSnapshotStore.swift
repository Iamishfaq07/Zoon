import Foundation
import os

/// Where the watch app parks the snapshot for its complications to read.
///
/// The complication extension and the watch app are separate processes, and
/// only the app can hold a `WCSession`. So the app receives, this stores, and
/// the extension reads.
///
/// ## Why UserDefaults rather than a file
///
/// On watchOS the app and its widget extension share a container by default —
/// they are one bundle, unlike the iOS app and its widget, which need an
/// explicit App Group. `UserDefaults.standard` is therefore genuinely shared
/// here, with none of the entitlement setup the phone side needs (and none of
/// the paid-account requirement that comes with it).
///
/// The payload is one JSON blob under one key for the same reason it is on the
/// wire: `SleepSnapshot` stays the only definition of the format.
enum WatchSnapshotStore {

    private static let key = "zoon.watch.snapshot"
    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "WatchStore")

    static func save(_ snapshot: SleepSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            logger.error("Could not store snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `nil` when nothing has arrived from the phone yet — which is the normal
    /// state on a freshly installed watch app, not an error.
    static func load() -> SleepSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SleepSnapshot.self, from: data)
    }
}
