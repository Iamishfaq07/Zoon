import Foundation

/// Breathing Disturbances are a rate -- events per hour of sleep -- and this is
/// the one rule for turning values written under the old, wrong reading back
/// into that rate.
///
/// **The defect behind it.** HealthKit declares
/// `appleSleepingBreathingDisturbances` as a `count` quantity: Apple's
/// algorithm reports how many breathing disturbances it saw per hour of
/// sleep. `FeatureExtractor` read it with `HKUnit.percent()` -- which
/// HealthKit converts from a count one-for-one, so nothing ever failed -- and
/// then multiplied by 100, believing it had a 0–1 fraction of the night. A
/// night Apple recorded at 3.2 events an hour was stored as 320 and shown as
/// "320%" on the Breathing screen, in Body Signals and on the clinician PDF.
///
/// Extraction now stores the rate as read. What is left is everything written
/// before that: rows already in the store, and backups exported from it. Both
/// the store migration (`BreathingDisturbanceUnitMigration`) and the backup
/// importer go through this type, so they cannot disagree about the factor or
/// about which backups need it.
///
/// Foundation-only and in `Shared/` so the rule is unit-tested; the SwiftData
/// half lives with the app.
enum BreathingDisturbanceUnits {

    /// The factor the old extraction multiplied the rate by.
    static let legacyScale = 100.0

    /// The newest backup format whose nights carry the old values.
    ///
    /// A backup records no unit, only its format number, so the number is the
    /// only way an importer can tell an old file from a new one. The importer
    /// may therefore convert only once exports are stamped with a *later*
    /// format: `DataExporter.formatVersion` must be at least 7 wherever
    /// `nightsFromArchive(_:formatVersion:)` is applied, or a fresh export
    /// would be divided again on the way back in.
    static let lastLegacyArchiveFormat = 6

    /// A stored value from before the fix, as events per hour.
    static func eventsPerHour(fromLegacy value: Double) -> Double {
        value / legacyScale
    }

    /// A backup's nights with breathing disturbances in events per hour.
    ///
    /// Archives from format 6 and earlier were exported from a store holding
    /// the old values, so theirs are converted; anything newer is returned
    /// untouched. Nights with no reading are untouched either way.
    static func nightsFromArchive(
        _ nights: [SleepNightFeatures],
        formatVersion: Int
    ) -> [SleepNightFeatures] {
        guard formatVersion <= lastLegacyArchiveFormat else { return nights }
        return nights.map { night in
            guard let legacy = night.breathingDisturbances else { return night }
            var converted = night
            converted.breathingDisturbances = eventsPerHour(fromLegacy: legacy)
            return converted
        }
    }

    // MARK: - Store migration plan

    /// The key a stored night is tracked under while the store migration is
    /// pending. The row's `date` is its unique identity in the store, and
    /// `String(Double)` round-trips exactly.
    static func rowKey(for date: Date) -> String {
        String(date.timeIntervalSinceReferenceDate)
    }

    /// Which stored rows still hold an old value and must be converted.
    ///
    /// On a first attempt (`pendingSnapshot` nil) every stored value is old:
    /// the migration runs before anything new is extracted. On a retry --
    /// an earlier attempt that recorded its snapshot and then failed to save,
    /// or saved and was killed before it could record that it was done --
    /// only rows still holding exactly the value they held at that first
    /// attempt are converted. A row written since then (a re-extracted night,
    /// already in events per hour) or converted already (a hundredth of its
    /// snapshot) no longer matches and is left alone. That is what makes a
    /// retry safe: no value is ever divided twice.
    ///
    /// - Parameters:
    ///   - stored: every stored breathing value now, keyed by `rowKey(for:)`.
    ///   - pendingSnapshot: the values recorded when the migration first
    ///     started, or `nil` if it never has.
    static func rowsNeedingConversion(
        stored: [String: Double],
        pendingSnapshot: [String: Double]?
    ) -> Set<String> {
        guard let pendingSnapshot else { return Set(stored.keys) }
        var keys = Set<String>()
        for entry in stored {
            guard let legacy = pendingSnapshot[entry.key], isSameValue(entry.value, legacy) else { continue }
            keys.insert(entry.key)
        }
        return keys
    }

    /// Equality with room for nothing but representation noise. A converted
    /// row holds a hundredth of its snapshot, and a re-extracted one holds the
    /// true rate -- also a hundredth of the old figure -- so neither can match
    /// unless the value is zero, where converting again changes nothing.
    private static func isSameValue(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(abs(lhs), abs(rhs)) * 1e-9
    }
}
