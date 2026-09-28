import Foundation

/// The overnight physiological signals Zoon queries per night.
///
/// Exists to name *which* query failed, so a night's record can tell the
/// difference between "the watch genuinely recorded no blood oxygen" and
/// "the blood-oxygen query threw". Both arrive as `nil`, and treating them
/// identically is safe only as long as nothing acts on the absence -- which
/// stopped being true once `SleepNightRecord.update` began clearing stale
/// values. See `MeasurementOutcome`.
enum VitalMetric: String, Codable, Hashable, Sendable, CaseIterable {
    case averageHeartRate
    case minimumHeartRate
    case restingHeartRate
    case hrv
    case respiratoryRate
    case oxygenSaturation
    case wristTemperature
    case breathingDisturbances
}

/// One metric's query result, keeping "no data" and "query failed" distinct.
///
/// A plain `Double?` can't express the difference, and the difference decides
/// whether a previously-stored value should be cleared or kept:
///
/// - `.measured` — write it.
/// - `.noData` — HealthKit answered, and the answer is that nothing was
///   recorded. A stored value from an earlier sync is now stale and must be
///   cleared, or a reading the user deleted in Health lives on in Zoon
///   forever.
/// - `.queryFailed` — HealthKit didn't answer. This says nothing about
///   whether data exists, so a stored value must be left alone; clearing it
///   would mean one transient failure silently destroys a good night's
///   record.
enum MeasurementOutcome: Hashable, Sendable {
    case measured(Double)
    case noData
    case queryFailed

    var value: Double? {
        if case .measured(let value) = self { return value }
        return nil
    }

    /// True when HealthKit gave a definitive answer of "nothing recorded" --
    /// the only case where clearing a stored value is correct.
    var confirmsAbsence: Bool { self == .noData }

    /// Applies a transform to a measured value, preserving the distinction
    /// for the other two cases. Used for the reading-to-stored conversions
    /// in `VitalMetric.storedValue(fromReading:)`.
    func map(_ transform: (Double) -> Double) -> MeasurementOutcome {
        if case .measured(let value) = self { return .measured(transform(value)) }
        return self
    }
}

extension VitalMetric {

    /// The number Zoon stores for a reading taken in the unit
    /// `FeatureExtractor` queries this metric in.
    ///
    /// Only blood oxygen changes scale: HealthKit's `percent()` unit is a
    /// 0–1 fraction, and the app stores and shows 0–100. Everything else is
    /// stored exactly as read -- including breathing disturbances, which
    /// HealthKit declares as a `count` quantity (events per hour). That one
    /// used to be read as a percent and multiplied by 100 on the belief that
    /// it was a fraction of the night, which turned 3.2 events an hour into
    /// "320%" on every surface and on the clinician PDF. Kept here, in
    /// `Shared/`, so the mapping is pinned by tests rather than living as an
    /// inline multiplication nobody can exercise without a health store.
    func storedValue(fromReading reading: Double) -> Double {
        switch self {
        case .oxygenSaturation:
            reading * 100
        case .averageHeartRate, .minimumHeartRate, .restingHeartRate, .hrv,
             .respiratoryRate, .wristTemperature, .breathingDisturbances:
            reading
        }
    }
}
