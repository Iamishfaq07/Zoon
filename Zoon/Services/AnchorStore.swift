import Foundation

/// Persists the `HKQueryAnchor` between launches so incremental sync survives
/// process death. `UserDefaults` is fine here — it's an opaque cursor, not
/// health data.
///
/// Deliberately split across two files. The anchor-typed `load()`/`save()`
/// pair genuinely needs `HKQueryAnchor` and lives in `HealthKitManager.swift`;
/// the key and `clear()` are plain `UserDefaults` and live here, importing
/// only Foundation. `SleepHistoryStore.importNights` calls `clear()` and
/// nothing else, so keeping that reachable without HealthKit is what lets
/// `SleepHistoryStore` compile into `ZoonTests` -- a target that links no
/// HealthKit and has no Health entitlements or usage descriptions. Pulling
/// HealthKit in there is what crashed the test process outright when
/// `SleepHistoryStorePruneTests` was first attempted (see
/// `SwiftDataProbeTests` for how that was finally isolated).
enum AnchorStore {

    static let key = "zoon.sleep.anchor"

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
