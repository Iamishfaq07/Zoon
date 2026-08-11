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
    /// Share of the nominal weight actually backed by real data, 0...100.
    /// 100 when every component was available; lower when some were excluded
    /// and the rest had to be reweighted to fill the gap.
    let dataCompletenessPercent: Int
    /// How many of the (up to 4) components had real data behind them.
    let availableComponentCount: Int

    struct Component: Codable, Hashable, Sendable, Identifiable {
        let label: String
        let detail: String
        /// 0...1. Meaningless when `isAvailable` is false -- present only so
        /// existing callers that read `normalized` unconditionally don't crash;
        /// always check `isAvailable` first.
        let normalized: Double
        /// The nominal weight from the table in this file's doc comment.
        let weight: Double
        /// The weight this component actually carried in the final score,
        /// after excluded components' weight was redistributed. Equal to
        /// `weight` when every component was available; 0 when this one
        /// wasn't. `effectiveWeight * normalized * 100`, summed across
        /// components, reconstructs `percent`.
        let effectiveWeight: Double
        /// False when the underlying signal (HRV, RHR, respiration) simply
        /// wasn't there -- no Watch that night, hardware that doesn't measure
        /// it, or not enough baseline history yet. An unavailable component
        /// contributes nothing, never a neutral or favorable stand-in.
        let isAvailable: Bool
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

    /// True resting heart rate, from HealthKit's daily `.restingHeartRate`
    /// sample -- not the lowest heart-rate reading during sleep, which is a
    /// noisier, different concept. See `SleepNightFeatures.restingHeartRate`.
    static func compute(
        features: SleepNightFeatures,
        baseline: RecoveryBaseline,
        sleepPerformance: Double
    ) -> RecoveryScore {

        // Each entry only enters the weighted sum if `isAvailable` -- a
        // missing signal is excluded and renormalized among what's left, never
        // filled in with a neutral 0.5 or (worse) a favorable default. That was
        // the bug this replaced: a night with no HRV or RHR reading used to
        // silently score those components at "average," which floors recovery
        // at a comfortable-looking number regardless of how little data backed
        // it, and briefly rewarded missing respiration outright.

        // --- HRV ---------------------------------------------------------
        // Scored on relative deviation, not absolute value. ±25% from baseline
        // maps across the full range: at baseline you sit mid-scale, well above
        // is a green light, well below means the nervous system is still working.
        var hrvNormalized = 0.0
        var hrvDeviation: Double?
        var hrvAvailable = false
        if let hrv = features.avgHRV, let base = baseline.hrv, base > 0 {
            let deviation = (hrv - base) / base
            hrvDeviation = deviation * 100
            hrvNormalized = clamp01(0.5 + deviation / 0.5)
            hrvAvailable = true
        }

        // --- Resting heart rate ------------------------------------------
        // Inverted: higher than baseline is worse. RHR moves less than HRV but
        // it's less noisy, so it acts as a check on a single odd HRV reading.
        var rhrNormalized = 0.0
        var rhrDeviation: Double?
        var rhrAvailable = false
        if let rhr = features.restingHeartRate, let base = baseline.restingHeartRate, base > 0 {
            let deviation = (rhr - base) / base
            rhrDeviation = deviation * 100
            // ±12% spans the scale — RHR is a tighter distribution than HRV.
            rhrNormalized = clamp01(0.5 - deviation / 0.24)
            rhrAvailable = true
        }

        // --- Respiratory rate ---------------------------------------------
        // Very stable night to night in a healthy adult, so a small absolute
        // rise is a real signal. A full breath per minute above baseline is a
        // meaningful departure — hence the tight ±1.5 br/min scale.
        var respiratoryNormalized = 0.0
        var respiratoryDeviation: Double?
        var respiratoryAvailable = false
        if let rate = features.avgRespiratoryRate, let base = baseline.respiratoryRate, base > 0 {
            let delta = rate - base
            respiratoryDeviation = (delta / base) * 100
            respiratoryNormalized = clamp01(1 - abs(delta) / 1.5)
            respiratoryAvailable = true
        }

        // Sleep performance has no missing-data path — it's always derived
        // from the night's own duration and the caller's sleep-need estimate,
        // both of which exist whenever there's a night to score at all.
        let raw: [(label: String, detail: String, normalized: Double, weight: Double, available: Bool, deviation: Double?)] = [
            ("HRV", features.avgHRV.map { "\(Int($0)) ms" } ?? "—", hrvNormalized, hrvWeight, hrvAvailable, hrvDeviation),
            ("Resting HR", features.restingHeartRate.map { "\(Int($0)) bpm" } ?? "—", rhrNormalized, rhrWeight, rhrAvailable, rhrDeviation),
            ("Sleep", "\(Int(sleepPerformance))% of need", clamp01(sleepPerformance / 100), sleepWeight, true, nil),
            ("Respiratory", features.avgRespiratoryRate.map { String(format: "%.1f br/min", $0) } ?? "—", respiratoryNormalized, respiratoryWeight, respiratoryAvailable, respiratoryDeviation)
        ]

        let availableWeight = raw.filter(\.available).reduce(0.0) { $0 + $1.weight }
        // Sleep performance is always available, so this can't be zero in
        // practice, but guard the division regardless.
        let renormalize = availableWeight > 0 ? 1.0 / availableWeight : 0

        let components = raw.map { entry in
            Component(
                label: entry.label,
                detail: entry.detail,
                normalized: entry.normalized,
                weight: entry.weight,
                effectiveWeight: entry.available ? entry.weight * renormalize : 0,
                isAvailable: entry.available,
                deviationPercent: entry.deviation
            )
        }

        let total = components.reduce(0.0) { $0 + $1.normalized * $1.effectiveWeight } * 100
        let availableCount = components.filter(\.isAvailable).count

        return RecoveryScore(
            percent: Int(total.rounded()),
            components: components,
            isEstimate: baseline.nightCount < minimumBaselineNights,
            dataCompletenessPercent: Int((availableWeight * 100).rounded()),
            availableComponentCount: availableCount
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
