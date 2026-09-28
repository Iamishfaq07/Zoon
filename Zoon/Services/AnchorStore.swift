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

/// Nights restored from a backup that HealthKit on this device has not shown
/// Zoon itself.
///
/// A full sync prunes every stored night in its window that HealthKit no
/// longer returns, which is right for a night deleted in the Health app and
/// wrong for a night that only ever came from a backup -- a new iPhone
/// without Health history, a restored archive. Those were deleted by the
/// next full sync: "Restored 212 nights", then three months gone. A night is
/// listed here when a restore writes it, skipped by prune while it is, and
/// dropped from the list as soon as HealthKit returns that night itself, so
/// from then on a deletion in Health removes it as usual.
///
/// Keyed on the night's `date`, its unique identity in the store. Foundation
/// only, beside `AnchorStore`, so `SleepHistoryStore` still compiles into the
/// test target.
enum RestoredNightLedger {

    static let key = "zoon.sleep.restoredNights.v1"

    static func dates(in defaults: UserDefaults) -> Set<Date> {
        let raw = defaults.array(forKey: key) as? [Double] ?? []
        return Set(raw.map(Date.init(timeIntervalSinceReferenceDate:)))
    }

    static func record(_ dates: [Date], in defaults: UserDefaults) {
        guard !dates.isEmpty else { return }
        write(Self.dates(in: defaults).union(dates), to: defaults)
    }

    static func forget(_ dates: Set<Date>, in defaults: UserDefaults) {
        let current = Self.dates(in: defaults)
        let remaining = current.subtracting(dates)
        guard remaining.count != current.count else { return }
        write(remaining, to: defaults)
    }

    static func clear(in defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }

    private static func write(_ dates: Set<Date>, to defaults: UserDefaults) {
        if dates.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(dates.map(\.timeIntervalSinceReferenceDate).sorted(), forKey: key)
        }
    }
}
