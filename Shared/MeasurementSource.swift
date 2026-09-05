import Foundation

/// Which HealthKit source wrote one particular measurement.
///
/// Distinct from `SensorTruth.Provenance`, which asks a different question:
/// that one grades *what kind of claim* a number is (measured, derived,
/// inferred). This one records *who produced it*, and the two are
/// independent -- an HRV reading is `.measured` whether it came from an
/// Apple Watch or a Garmin.
struct MeasurementSource: Codable, Hashable, Sendable {
    /// As HealthKit named it, e.g. "Ishfaq's Apple Watch". Display only.
    let name: String
    /// `HKSource.bundleIdentifier`. Stable across a device rename or a
    /// display-language change, which the name is not.
    let bundleIdentifier: String

    init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Who wrote each of a night's measurements.
///
/// ## Why this has to be stored per metric
///
/// `SleepNightFeatures.sourceName` names the source of the *sleep* samples,
/// and until now everything else on the night was silently attributed to it.
/// That is wrong on any device pairing that is at all common: a Garmin can
/// write the sleep session while a simultaneously-worn Apple Watch writes the
/// HRV, and Zoon would report "your Garmin provides HRV". The physiology is
/// queried over the night's asleep intervals with no source predicate at all,
/// so whoever wrote a sample in that window contributes to the average --
/// which is the right behaviour for the *number*, and exactly why the number
/// cannot be attributed to the sleep source.
///
/// ## Absent is not the same as "nobody"
///
/// Every night stored before this existed carries no entries, and nothing may
/// read that as "no source wrote it". `attribution(for:)` returns `nil` for an
/// unrecorded quantity rather than an empty list, and callers are expected to
/// treat `nil` as *unknown* and say nothing.
struct NightMeasurementSources: Codable, Hashable, Sendable {

    /// Keyed by `SensorTruth.Quantity.rawValue` -- a raw string rather than
    /// the enum, so a quantity renamed or removed in a later release
    /// degrades to an unreadable key instead of failing the whole night's
    /// decode.
    private var byQuantity: [String: [MeasurementSource]]

    static let empty = NightMeasurementSources(byQuantity: [:])

    init(byQuantity: [String: [MeasurementSource]] = [:]) {
        self.byQuantity = byQuantity
    }

    init(_ recorded: [SensorTruth.Quantity: [MeasurementSource]]) {
        var mapped: [String: [MeasurementSource]] = [:]
        for (quantity, sources) in recorded where !sources.isEmpty {
            mapped[quantity.rawValue] = sources
        }
        byQuantity = mapped
    }

    var isEmpty: Bool { byQuantity.isEmpty }

    /// Every source that contributed to this quantity on this night, or `nil`
    /// when nothing was recorded -- see the type's doc comment for why those
    /// must not collapse into each other.
    func sources(for quantity: SensorTruth.Quantity) -> [MeasurementSource]? {
        byQuantity[quantity.rawValue]
    }

    /// Whether the named source contributed to this quantity. `nil` when
    /// provenance was never recorded for it, so the caller can decline to
    /// answer rather than guess.
    func wasWritten(
        by bundleIdentifier: String?,
        orNamed name: String?,
        for quantity: SensorTruth.Quantity
    ) -> Bool? {
        guard let sources = byQuantity[quantity.rawValue] else { return nil }
        // Bundle identifier first, name only as a fallback -- the same
        // ordering `SleepHistoryStore.knownSleepSources` established for the
        // preferred-source picker, and for the same reason: a renamed watch
        // must not read as a different device.
        if let bundleIdentifier, !bundleIdentifier.isEmpty,
           sources.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return true
        }
        if let name, !name.isEmpty, sources.contains(where: { $0.name == name }) {
            return true
        }
        return false
    }
}

// MARK: - Persistence

extension NightMeasurementSources {

    /// JSON blob for the SwiftData column. A blob rather than a table for the
    /// same reason `stageSegmentsData` is one: it is only ever read whole,
    /// never queried into.
    var encoded: Data? {
        isEmpty ? nil : try? JSONEncoder().encode(self)
    }

    /// Decodes leniently: a row written by an older or newer build that this
    /// one cannot read comes back empty, which every caller already has to
    /// handle as "unknown".
    static func decode(_ data: Data?) -> NightMeasurementSources {
        guard let data,
              let decoded = try? JSONDecoder().decode(NightMeasurementSources.self, from: data)
        else { return .empty }
        return decoded
    }
}
