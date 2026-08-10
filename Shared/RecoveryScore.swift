import Foundation

/// How ready the body is today, 0–100%.
///
/// The headline number, in the tradition of Whoop's Recovery and Garmin's
/// Training Readiness. It answers one question: *given last night and the state
/// of your autonomic nervous system, how hard can you go today?*
///
/// ## What it's built from
///
/// Four inputs, each scored against **your own rolling baseline** rather than a
/// population norm. HRV in particular is meaningless between people — a 30ms
/// SDNN can be excellent or alarming depending on whose wrist it came from — so
/// every comparison here is personal.
///
/// | Input | Weight | Why |
/// |---|---|---|
/// | HRV vs baseline | 45% | Strongest single autonomic signal |
/// | Resting HR vs baseline | 25% | Slower-moving, catches strain HRV misses |
/// | Sleep performance | 20% | Recovery you actually banked |
/// | Respiratory stability | 10% | Elevated rate flags illness/alcohol early |
///
/// ## What it is not
///
/// This is not Whoop's algorithm, or Garmin's, or anyone else's — those are
/// proprietary and trained on data we don't have. It's a transparent
/// reimplementation of the same *idea*, with the weights written down so you can
/// argue with them. Every component is exposed in `components` so the UI can
/// show its working rather than handing down a number from nowhere.
struct RecoveryScore: Codable, Hashable, Sendable {

    let percent: Int
    let components: [Component]
    /// False when there wasn't enough baseline history to score honestly.
    /// The UI shows a "building baseline" state instead of a fake number.
    let isEstimate: Bool

    struct Component: Codable, Hashable, Sendable, Identifiable {
        let label: String
        let detail: String
        /// 0...1
        let normalized: Double
        let weight: Double
        /// Deviation from baseline as a signed percentage, when meaningful.
        let deviationPercent: Double?

        var id: String { label }
    }

    // Weights sum to 1.0.
    private static let hrvWeight = 0.45
    private static let rhrWeight = 0.25
    private static let sleepWeight = 0.20
    private static let respiratoryWeight = 0.10

    /// Nights of history before the score stops being flagged as an estimate.
    static let minimumBaselineNights = 4

    static func compute(
        features: SleepNightFeatures,
        baseline: RecoveryBaseline,
        sleepPerformance: Double
    ) -> RecoveryScore {

        var components: [Component] = []

        // --- HRV ---------------------------------------------------------
        // Scored on relative deviation, not absolute value. ±25% from baseline
        // maps across the full range: at baseline you sit mid-scale, well above
        // is a green light, well below means the nervous system is still working.
        var hrvNormalized = 0.5
        var hrvDeviation: Double?
        if let hrv = features.avgHRV, let base = baseline.hrv, base > 0 {
            let deviation = (hrv - base) / base
            hrvDeviation = deviation * 100
            hrvNormalized = clamp01(0.5 + deviation / 0.5)
        }
        components.append(Component(
            label: "HRV",
            detail: features.avgHRV.map { "\(Int($0)) ms" } ?? "—",
            normalized: hrvNormalized,
            weight: hrvWeight,
            deviationPercent: hrvDeviation
        ))

        // --- Resting heart rate ------------------------------------------
        // Inverted: higher than baseline is worse. RHR moves less than HRV but
        // it's less noisy, so it acts as a check on a single odd HRV reading.
        var rhrNormalized = 0.5
        var rhrDeviation: Double?
        if let rhr = features.minHeartRate, let base = baseline.restingHeartRate, base > 0 {
            let deviation = (rhr - base) / base
            rhrDeviation = deviation * 100
            // ±12% spans the scale — RHR is a tighter distribution than HRV.
            rhrNormalized = clamp01(0.5 - deviation / 0.24)
        }
        components.append(Component(
            label: "Resting HR",
            detail: features.minHeartRate.map { "\(Int($0)) bpm" } ?? "—",
            normalized: rhrNormalized,
            weight: rhrWeight,
            deviationPercent: rhrDeviation
        ))

        // --- Sleep performance -------------------------------------------
        components.append(Component(
            label: "Sleep",
            detail: "\(Int(sleepPerformance))% of need",
            normalized: clamp01(sleepPerformance / 100),
            weight: sleepWeight,
            deviationPercent: nil
        ))

        // --- Respiratory rate ---------------------------------------------
        // Very stable night to night in a healthy adult, so a small absolute
        // rise is a real signal. A full breath per minute above baseline is a
        // meaningful departure — hence the tight ±1.5 br/min scale.
        var respiratoryNormalized = 0.75
        var respiratoryDeviation: Double?
        if let rate = features.avgRespiratoryRate, let base = baseline.respiratoryRate, base > 0 {
            let delta = rate - base
            respiratoryDeviation = (delta / base) * 100
            respiratoryNormalized = clamp01(1 - abs(delta) / 1.5)
        }
        components.append(Component(
            label: "Respiratory",
            detail: features.avgRespiratoryRate.map { String(format: "%.1f br/min", $0) } ?? "—",
            normalized: respiratoryNormalized,
            weight: respiratoryWeight,
            deviationPercent: respiratoryDeviation
        ))

        let total = components.reduce(0.0) { $0 + $1.normalized * $1.weight } * 100

        return RecoveryScore(
            percent: Int(total.rounded()),
            components: components,
            isEstimate: baseline.nightCount < minimumBaselineNights
        )
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}

// MARK: - Presentation

extension RecoveryScore {

    enum Band: String, Sendable {
        case low, moderate, high

        var label: String {
            switch self {
            case .low: "Low"
            case .moderate: "Moderate"
            case .high: "High"
            }
        }

        /// The one-line prescription. This is the whole point of the number —
        /// a percentage with no instruction attached is trivia.
        var guidance: String {
            switch self {
            case .low:
                "Your body is still working. Keep today easy — walking, mobility, or full rest."
            case .moderate:
                "Ready for moderate work. Train, but leave something in the tank."
            case .high:
                "Primed. This is the day to go hard if you're going to."
            }
        }
    }

    var band: Band {
        switch percent {
        case ..<34: .low
        case 34..<67: .moderate
        default: .high
        }
    }

    /// The single strongest driver, for the "why" line under the ring.
    var primaryDriver: Component? {
        components.min { $0.normalized < $1.normalized }
    }
}

/// Personal baselines the recovery score compares against.
///
/// Separate from `RollingBaseline` because recovery wants a longer, slower
/// window than the insight rules do: a 7-day window tracks a training block so
/// closely that a hard week quietly redefines "normal" and the score stops
/// noticing you're buried.
struct RecoveryBaseline: Codable, Hashable, Sendable {
    let hrv: Double?
    let restingHeartRate: Double?
    let respiratoryRate: Double?
    let wristTemperature: Double?
    let nightCount: Int

    static let empty = RecoveryBaseline(
        hrv: nil, restingHeartRate: nil, respiratoryRate: nil,
        wristTemperature: nil, nightCount: 0
    )
}
