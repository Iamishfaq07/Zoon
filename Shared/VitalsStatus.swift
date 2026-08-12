import Foundation

/// Overnight vitals checked against personal typical ranges.
///
/// Modelled on the Vitals feature Apple shipped in iOS 18: rather than showing
/// six numbers and leaving you to work out whether any of them matter, it
/// establishes what's normal *for you* and tells you when something sits
/// outside it. One outlier is noise; several at once is a pattern worth
/// noticing.
///
/// The framing is deliberately non-clinical throughout. "Outside your typical
/// range" is an observation. "Abnormal" would be a claim this app has no
/// business making.
struct VitalsStatus: Codable, Hashable, Sendable {

    let metrics: [Metric]
    /// True once enough history exists for "typical" to mean anything.
    let hasBaseline: Bool

    struct Metric: Codable, Hashable, Sendable, Identifiable {
        let kind: Kind
        let value: Double?
        /// Personal mean.
        let baseline: Double?
        /// Half-width of the typical band (one standard deviation).
        let tolerance: Double?
        let state: State

        var id: String { kind.rawValue }

        var formattedValue: String {
            guard let value else { return "—" }
            return kind.format(value)
        }

        var formattedRange: String? {
            guard let baseline, let tolerance else { return nil }
            return "\(kind.format(baseline - tolerance))–\(kind.format(baseline + tolerance))"
        }
    }

    enum State: String, Codable, Hashable, Sendable {
        case typical
        case aboveTypical
        case belowTypical
        case unavailable

        var isOutlier: Bool { self == .aboveTypical || self == .belowTypical }

        var label: String {
            switch self {
            case .typical: "Typical"
            case .aboveTypical: "Above typical"
            case .belowTypical: "Below typical"
            case .unavailable: "No data"
            }
        }

        var symbol: String {
            switch self {
            case .typical: "checkmark.circle.fill"
            case .aboveTypical: "arrow.up.circle.fill"
            case .belowTypical: "arrow.down.circle.fill"
            case .unavailable: "minus.circle"
            }
        }
    }

    enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case restingHeartRate
        case hrv
        case respiratoryRate
        case oxygenSaturation
        case wristTemperature
        case sleepDuration
        case breathingDisturbances

        var label: String {
            switch self {
            case .restingHeartRate: "Resting Heart Rate"
            case .hrv: "Heart Rate Variability"
            case .respiratoryRate: "Respiratory Rate"
            case .oxygenSaturation: "Blood Oxygen"
            case .wristTemperature: "Wrist Temperature"
            case .sleepDuration: "Sleep Duration"
            case .breathingDisturbances: "Breathing Disturbances"
            }
        }

        var symbol: String {
            switch self {
            case .restingHeartRate: "heart.fill"
            case .hrv: "waveform.path.ecg"
            case .respiratoryRate: "lungs.fill"
            case .oxygenSaturation: "drop.fill"
            case .wristTemperature: "thermometer.medium"
            case .sleepDuration: "bed.double.fill"
            case .breathingDisturbances: "wind"
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .restingHeartRate: "\(Int(value.rounded())) bpm"
            case .hrv: "\(Int(value.rounded())) ms"
            case .respiratoryRate: String(format: "%.1f", value)
            case .oxygenSaturation: String(format: "%.0f%%", value)
            case .wristTemperature: String(format: "%+.1f°", value)
            case .sleepDuration: SleepNightFeatures.formatMinutes(value)
            case .breathingDisturbances: String(format: "%.1f%%", value)
            }
        }
    }

    /// Nights needed before a typical range is claimed.
    static let minimumNights = 7

    /// How many standard deviations counts as outside typical.
    ///
    /// 1.0 rather than the more statistically conventional 2.0, on purpose: at
    /// 2σ almost nothing ever fires and the panel becomes decoration. At 1σ
    /// roughly a third of readings land outside, which is about right for a
    /// "worth a glance" signal — and the copy is careful never to imply that
    /// outside-typical means wrong.
    static let outlierSigma = 1.0

    static func evaluate(features: SleepNightFeatures, history: [VitalsSample]) -> VitalsStatus {
        let hasBaseline = history.count >= minimumNights

        let metrics = Kind.allCases.map { kind -> Metric in
            let value = currentValue(kind, features: features)
            guard hasBaseline else {
                return Metric(kind: kind, value: value, baseline: nil, tolerance: nil,
                              state: value == nil ? .unavailable : .typical)
            }

            let series = history.compactMap { historicValue(kind, sample: $0) }
            guard series.count >= minimumNights, let value else {
                return Metric(kind: kind, value: value, baseline: nil, tolerance: nil, state: .unavailable)
            }

            let mean = series.reduce(0, +) / Double(series.count)
            let variance = series.reduce(0) { $0 + pow($1 - mean, 2) } / Double(series.count)
            let sd = variance.squareRoot()

            // A degenerate spread (identical readings) would make every tiny
            // wobble an outlier, so floor the tolerance per metric.
            let tolerance = max(sd * outlierSigma, kind.minimumTolerance)

            let state: State
            if value > mean + tolerance {
                state = .aboveTypical
            } else if value < mean - tolerance {
                state = .belowTypical
            } else {
                state = .typical
            }

            return Metric(kind: kind, value: value, baseline: mean, tolerance: tolerance, state: state)
        }

        return VitalsStatus(metrics: metrics, hasBaseline: hasBaseline)
    }

    private static func currentValue(_ kind: Kind, features: SleepNightFeatures) -> Double? {
        switch kind {
        case .restingHeartRate: features.restingHeartRate
        case .hrv: features.avgHRV
        case .respiratoryRate: features.avgRespiratoryRate
        case .oxygenSaturation: features.avgSpO2
        case .wristTemperature: features.wristTempDeltaC
        case .sleepDuration: features.timeAsleepMinutes
        case .breathingDisturbances: features.breathingDisturbances
        }
    }

    private static func historicValue(_ kind: Kind, sample: VitalsSample) -> Double? {
        switch kind {
        case .restingHeartRate: sample.restingHeartRate
        case .hrv: sample.hrv
        case .respiratoryRate: sample.respiratoryRate
        case .oxygenSaturation: sample.oxygenSaturation
        case .wristTemperature: sample.wristTemperatureDelta
        case .sleepDuration: sample.sleepMinutes
        case .breathingDisturbances: sample.breathingDisturbances
        }
    }
}

extension VitalsStatus.Kind {
    /// Floor on the typical-range half-width, in each metric's own units.
    var minimumTolerance: Double {
        switch self {
        case .restingHeartRate: 2.0
        case .hrv: 4.0
        case .respiratoryRate: 0.4
        case .oxygenSaturation: 0.8
        case .wristTemperature: 0.15
        case .sleepDuration: 25.0
        case .breathingDisturbances: 0.6
        }
    }
}

extension VitalsStatus {

    var outliers: [Metric] { metrics.filter { $0.state.isOutlier } }

    var headline: String {
        guard hasBaseline else {
            return "Building your typical ranges"
        }
        switch outliers.count {
        case 0: return "All vitals typical"
        case 1: return "1 vital outside your typical range"
        default: return "\(outliers.count) vitals outside your typical range"
        }
    }

    var detail: String {
        guard hasBaseline else {
            return "Zoon needs about a week of nights to learn what's normal for you."
        }
        if outliers.isEmpty {
            return "Everything measured last night sits inside your personal range."
        }
        let names = outliers.map(\.kind.label).joined(separator: ", ")
        return "\(names). Multiple vitals moving together can accompany illness, alcohol, or a hard training block."
    }
}

/// One night's vitals, flattened for baseline maths.
struct VitalsSample: Codable, Hashable, Sendable {
    let date: Date
    let restingHeartRate: Double?
    let hrv: Double?
    let respiratoryRate: Double?
    let oxygenSaturation: Double?
    let wristTemperatureDelta: Double?
    let sleepMinutes: Double?
    var breathingDisturbances: Double? = nil
}
