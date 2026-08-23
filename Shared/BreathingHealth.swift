import Foundation

/// Apple's own night-level classification of the `appleSleepingBreathingDisturbances`
/// quantity, via `HKAppleSleepingBreathingDisturbancesClassification(for:)` (iOS
/// 18+). Preferred over `BreathingHealth`'s own percent-of-night threshold
/// wherever available -- Apple's own cutoff is the one its Sleep Apnea
/// Notifications feature is actually calibrated against, not a guess this
/// app invented. Stored per-night on `SleepNightFeatures` so historical
/// nights extracted before this classification existed, or nights from a
/// watch/OS combination too old to report it, simply have `nil` here and
/// fall back to the in-app threshold -- see `BreathingHealth.isElevated`.
enum BreathingDisturbanceClassification: String, Codable, Sendable {
    case notElevated
    case elevated
}

/// A dedicated breathing-signal summary: respiratory rate vs. baseline, a
/// breathing-disturbances trend, SpO2 trend, and a repeated-pattern check --
/// never a diagnosis, never the word "apnea".
///
/// The repeated-pattern check exists specifically because a single elevated
/// night proves nothing (see `spec §89`): breathing disturbances are noisy,
/// and alerting from one night trains people to distrust or ignore the
/// signal by the time it might matter. This only flags when a real multi-
/// night pattern shows up.
struct BreathingHealth: Codable, Hashable, Sendable {

    let tonightRespiratoryRate: Double?
    let baselineRespiratoryRate: Double?
    let respiratoryDeviationPercent: Double?

    /// Last 14 nights with a breathing-disturbances reading, oldest first.
    let disturbanceTrend: [TrendPoint]
    /// Last 14 nights with an SpO2 reading, oldest first.
    let oxygenTrend: [TrendPoint]

    let pattern: Pattern

    struct TrendPoint: Codable, Hashable, Sendable, Identifiable {
        let date: Date
        let value: Double
        /// Whether this specific night was classified elevated -- see
        /// `BreathingHealth.isElevated`, computed once here rather than
        /// callers (chart coloring, etc.) re-deriving their own cutoff from
        /// `value` alone and disagreeing with the real classification.
        /// Meaningful only for `disturbanceTrend` points; `oxygenTrend`
        /// reuses this same struct shape for SpO2 and always leaves this
        /// at its default, unread.
        let isElevated: Bool
        var id: Date { date }

        init(date: Date, value: Double, isElevated: Bool = false) {
            self.date = date
            self.value = value
            self.isElevated = isElevated
        }
    }

    enum Pattern: Codable, Hashable, Sendable {
        /// Not enough nights with disturbance data to say anything.
        case insufficientData
        case normal
        /// `nightsElevated` of the last `windowNights` were above the
        /// elevated threshold -- language stays at "repeated pattern",
        /// never a named condition.
        case repeatedPattern(nightsElevated: Int, windowNights: Int)

        var label: String {
            switch self {
            case .insufficientData: "Not enough data"
            case .normal: "Not elevated"
            case .repeatedPattern: "Repeated pattern"
            }
        }
    }

    /// Nights considered for the pattern check.
    private static let patternWindow = 14
    /// Fallback threshold for a night with no Apple classification at all
    /// (an older watch/OS, or a night extracted before this classification
    /// existed) -- a conservative, in-app-only heuristic, used only when
    /// `isElevated` has nothing better to go on.
    private static let elevatedThresholdPercent = 5.0
    /// This many elevated nights out of the window before it's called a
    /// pattern rather than noise.
    private static let patternMinimumNights = 5

    /// Whether a night counts as "elevated" -- Apple's own classification
    /// when HealthKit provided one, the in-app percent threshold otherwise.
    static func isElevated(_ night: SleepNightFeatures) -> Bool {
        if let classification = night.breathingDisturbancesClassification {
            return classification == .elevated
        }
        guard let value = night.breathingDisturbances else { return false }
        return value >= elevatedThresholdPercent
    }

    static func compute(nights: [SleepNightFeatures]) -> BreathingHealth {
        let sorted = nights.sorted { $0.date < $1.date }
        let recentWindow = Array(sorted.suffix(30))
        let latest = sorted.last

        var respiratoryDeviation: Double?
        var baseline: Double?
        if let rate = latest?.avgRespiratoryRate {
            let history = recentWindow.dropLast().compactMap(\.avgRespiratoryRate)
            baseline = Statistics.median(history)
            if let base = baseline, base > 0 {
                respiratoryDeviation = (rate - base) / base * 100
            }
        }

        let disturbanceWindow = Array(sorted.suffix(patternWindow))
        let disturbanceNights = disturbanceWindow.filter { $0.breathingDisturbances != nil }
        let disturbanceTrend = disturbanceNights.map {
            TrendPoint(date: $0.date, value: $0.breathingDisturbances!, isElevated: isElevated($0))
        }

        let oxygenTrend = disturbanceWindow.compactMap { night -> TrendPoint? in
            guard let value = night.avgSpO2 else { return nil }
            return TrendPoint(date: night.date, value: value)
        }

        let pattern: Pattern
        if disturbanceTrend.count < patternMinimumNights {
            pattern = .insufficientData
        } else {
            let elevatedCount = disturbanceNights.filter(isElevated).count
            pattern = elevatedCount >= patternMinimumNights
                ? .repeatedPattern(nightsElevated: elevatedCount, windowNights: disturbanceTrend.count)
                : .normal
        }

        return BreathingHealth(
            tonightRespiratoryRate: latest?.avgRespiratoryRate,
            baselineRespiratoryRate: baseline,
            respiratoryDeviationPercent: respiratoryDeviation,
            disturbanceTrend: disturbanceTrend,
            oxygenTrend: oxygenTrend,
            pattern: pattern
        )
    }
}
