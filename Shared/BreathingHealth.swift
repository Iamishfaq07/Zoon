import Foundation

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
        var id: Date { date }
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
    /// A night counts as "elevated" above this percent-of-night threshold.
    /// Deliberately not tied to Apple's own sleep-apnea notification
    /// threshold, which this app has no access to and no basis to guess at
    /// -- this is a separate, conservative, in-app-only heuristic.
    private static let elevatedThresholdPercent = 5.0
    /// This many elevated nights out of the window before it's called a
    /// pattern rather than noise.
    private static let patternMinimumNights = 5

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
        let disturbanceTrend = disturbanceWindow.compactMap { night -> TrendPoint? in
            guard let value = night.breathingDisturbances else { return nil }
            return TrendPoint(date: night.date, value: value)
        }

        let oxygenTrend = disturbanceWindow.compactMap { night -> TrendPoint? in
            guard let value = night.avgSpO2 else { return nil }
            return TrendPoint(date: night.date, value: value)
        }

        let pattern: Pattern
        if disturbanceTrend.count < patternMinimumNights {
            pattern = .insufficientData
        } else {
            let elevatedCount = disturbanceTrend.filter { $0.value >= elevatedThresholdPercent }.count
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
