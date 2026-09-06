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

/// What one source contributed to one measurement, and who else contributed.
///
/// Deliberately not a Bool. "Did my Garmin write the HRV" and "did only my
/// Garmin write the HRV" are different questions, and a Bool answers the
/// first while every user-facing sentence needs the second.
struct SourceContribution: Hashable, Sendable {
    /// The source being asked about wrote at least one of this night's
    /// samples for this quantity.
    let targetPresent: Bool
    /// Every *other* writer of the same quantity on the same night. Empty
    /// when the target was the only one -- which is the only case where
    /// naming a single device is honest.
    let otherSources: [MeasurementSource]

    /// Both the target and somebody else wrote it. Real on a wrist wearing
    /// two devices, and the case that used to be reported as the target's
    /// alone.
    var isShared: Bool { targetPresent && !otherSources.isEmpty }

    /// Somebody wrote it and it was not the target.
    var isExclusivelyOther: Bool { !targetPresent && !otherSources.isEmpty }

    var otherSourceNames: [String] {
        Set(otherSources.map(\.name)).sorted()
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

    /// What one source contributed to one quantity, *and who else did*.
    ///
    /// The distinction `wasWritten` cannot make. A Bool answers "did this
    /// watch write it", which silently discards the fact that another device
    /// wrote it on the same night -- and a caller counting only that Bool
    /// therefore reports a co-written metric as exclusively this source's.
    /// That is the whole over-claim this file exists to prevent, rebuilt one
    /// layer up.
    ///
    /// The four states a caller needs to tell apart are all recoverable here:
    ///
    /// | `targetPresent` | `otherSources` | means |
    /// |---|---|---|
    /// | true | empty | only this source |
    /// | true | non-empty | this source and others |
    /// | false | non-empty | only other sources |
    /// | — | — | `nil`: nothing recorded, say nothing |
    ///
    /// - Returns: `nil` when provenance was never recorded for this quantity,
    ///   which is not the same as "nobody wrote it".
    func contribution(
        of bundleIdentifier: String?,
        orNamed name: String?,
        for quantity: SensorTruth.Quantity
    ) -> SourceContribution? {
        guard let sources = byQuantity[quantity.rawValue] else { return nil }

        // Bundle identifier first, name only as a fallback -- a renamed watch
        // must not read as a different device. Whichever key matched decides
        // which entries are "the target", so the remainder are the others.
        func isTarget(_ source: MeasurementSource) -> Bool {
            if let bundleIdentifier, !bundleIdentifier.isEmpty,
               !source.bundleIdentifier.isEmpty {
                return source.bundleIdentifier == bundleIdentifier
            }
            guard let name, !name.isEmpty else { return false }
            return source.name == name
        }

        let target = sources.filter(isTarget)
        let others = sources.filter { !isTarget($0) }
        return SourceContribution(targetPresent: !target.isEmpty, otherSources: others)
    }

    /// Whether the named source contributed to this quantity. `nil` when
    /// provenance was never recorded for it, so the caller can decline to
    /// answer rather than guess.
    ///
    /// Kept for callers that genuinely only need the yes/no. Anything that
    /// reports *attribution* to a person wants `contribution(of:orNamed:for:)`
    /// instead -- see its doc comment.
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
