import Foundation
import os

/// Where the watch app parks the snapshot for its complications to read.
///
/// The complication extension and the watch app are separate processes, and
/// only the app can hold a `WCSession`. The app receives, this stores, and the
/// extension reads from their shared App Group defaults suite.
///
/// The App Group container is local to each physical device. WatchConnectivity
/// remains the direct transport between the phone and Watch; this store is only
/// the hand-off between processes on the Watch.
enum WatchSnapshotStore {

    private static let key = "zoon.watch.snapshot"
    private static let logger = Logger(subsystem: "com.zoon.sleep", category: "WatchStore")
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    static func save(_ snapshot: SleepSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: key)
        } catch {
            logger.error("Could not store snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `nil` when nothing has arrived from the phone yet, which is the normal
    /// state on a freshly installed watch app, not an error.
    static func load() -> SleepSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SleepSnapshot.self, from: data)
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
