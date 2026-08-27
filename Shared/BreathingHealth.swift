import Foundation

/// Apple's own night-level classification of the `appleSleepingBreathingDisturbances`
/// quantity, via `HKAppleSleepingBreathingDisturbancesClassification(for:)` (iOS
/// 18+). This is the only source Zoon will call a night "elevated" from: it is
/// the cutoff Apple's Sleep Apnea Notifications feature is actually calibrated
/// against. Nights from a watch/OS combination too old to report it, or
/// extracted before it existed, are `nil` here and resolve to
/// `BreathingElevation.unclassified` -- see `BreathingHealth.elevation`.
enum BreathingDisturbanceClassification: String, Codable, Sendable {
    case notElevated
    case elevated
}

/// Whether a night was classified elevated, was classified not elevated, or
/// was never classified at all.
///
/// The third case is the point. `BreathingHealth.isElevated` used to return a
/// plain `Bool` and, when Apple's classification was absent, substituted an
/// in-app cutoff of `value >= 5.0` percent of the night. That number was
/// Zoon's own invention. It read as a clinical threshold, it was surfaced to
/// users and printed on the clinician report as "nights classified elevated",
/// and nothing in this app ever calibrated it against anything.
///
/// The same `Bool` also conflated two different unknowns: a night with no
/// breathing data at all returned `false`, which is indistinguishable from a
/// night Apple's own classifier examined and called not elevated.
///
/// Zoon can honestly show the raw trend and the deviation from someone's own
/// baseline without either of those. So it does, and says "not classified"
/// where that is the truth.
enum BreathingElevation: String, Codable, Sendable, CaseIterable {
    case elevated
    case notElevated
    /// No Apple classification for this night. Zoon does not substitute a
    /// threshold of its own.
    case unclassified

    var label: String {
        switch self {
        case .elevated: "Elevated"
        case .notElevated: "Not elevated"
        case .unclassified: "Not classified"
        }
    }
}

/// A dedicated breathing-signal summary: respiratory rate vs. baseline, a
/// breathing-disturbances trend, SpO2 trend, and a repeated-pattern check --
/// never a diagnosis, never the word "apnea".
///
/// The repeated-pattern check exists specifically because a single elevated
/// night proves nothing: breathing disturbances are noisy, and alerting from
/// one night trains people to distrust or ignore the signal by the time it
/// might matter. This only flags when a real multi-night pattern shows up,
/// and only from nights Apple actually classified.
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
        /// How this specific night was classified -- computed once here
        /// rather than callers (chart colouring, and so on) re-deriving a
        /// cutoff from `value` alone and disagreeing with the real answer.
        /// Meaningful only for `disturbanceTrend` points; `oxygenTrend`
        /// reuses this struct shape for SpO2 and leaves this `.unclassified`,
        /// unread.
        let elevation: BreathingElevation
        var id: Date { date }

        /// Convenience for surfaces that only need the positive case. Note
        /// that `false` here means "not known to be elevated", which
        /// includes never having been classified -- use `elevation` wherever
        /// that difference should be visible.
        var isElevated: Bool { elevation == .elevated }

        init(date: Date, value: Double, elevation: BreathingElevation = .unclassified) {
            self.date = date
            self.value = value
            self.elevation = elevation
        }
    }

    enum Pattern: Codable, Hashable, Sendable {
        /// Not enough nights with disturbance data to say anything.
        case insufficientData
        /// There are readings, but too few of them carry Apple's
        /// classification to draw a conclusion. Distinct from
        /// `insufficientData` because the user does have data -- the trend is
        /// worth showing -- and distinct from `normal` because Zoon has not
        /// established that anything is normal.
        case unclassified(windowNights: Int)
        case normal
        /// `nightsElevated` of the last `windowNights` were classified
        /// elevated by Apple -- language stays at "repeated pattern", never a
        /// named condition.
        case repeatedPattern(nightsElevated: Int, windowNights: Int)

        var label: String {
            switch self {
            case .insufficientData: "Not enough data"
            case .unclassified: "Not classified"
            case .normal: "Not elevated"
            case .repeatedPattern: "Repeated pattern"
            }
        }
    }

    /// Nights considered for the pattern check.
    private static let patternWindow = 14
    /// This many elevated nights out of the window before it's called a
    /// pattern rather than noise. Also the minimum number of *classified*
    /// nights before the check runs at all.
    private static let patternMinimumNights = 5

    /// How a night was classified. Apple's classification, or nothing.
    static func elevation(_ night: SleepNightFeatures) -> BreathingElevation {
        guard let classification = night.breathingDisturbancesClassification else {
            return .unclassified
        }
        return classification == .elevated ? .elevated : .notElevated
    }

    /// Whether a night is *known* to be elevated.
    ///
    /// `false` covers both "classified not elevated" and "never classified".
    /// Callers that count elevated nights against a denominator must filter
    /// with `classified(_:)` first, or an unclassified night silently reads
    /// as a clean one.
    static func isElevated(_ night: SleepNightFeatures) -> Bool {
        elevation(night) == .elevated
    }

    /// The nights Apple actually classified. The correct denominator for any
    /// "N of M nights elevated" statement.
    static func classified(_ nights: [SleepNightFeatures]) -> [SleepNightFeatures] {
        nights.filter { elevation($0) != .unclassified }
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
            TrendPoint(date: $0.date, value: $0.breathingDisturbances!, elevation: elevation($0))
        }

        let oxygenTrend = disturbanceWindow.compactMap { night -> TrendPoint? in
            guard let value = night.avgSpO2 else { return nil }
            return TrendPoint(date: night.date, value: value)
        }

        // Only classified nights can support a claim about elevation. A
        // window full of readings from a watch that does not classify them is
        // `unclassified`, not `normal` -- the old code called it normal,
        // because its invented 5% cutoff answered for every night.
        let classifiedNights = classified(disturbanceNights)
        let pattern: Pattern
        if disturbanceTrend.count < patternMinimumNights {
            pattern = .insufficientData
        } else if classifiedNights.count < patternMinimumNights {
            pattern = .unclassified(windowNights: disturbanceTrend.count)
        } else {
            let elevatedCount = classifiedNights.filter(isElevated).count
            pattern = elevatedCount >= patternMinimumNights
                ? .repeatedPattern(nightsElevated: elevatedCount, windowNights: classifiedNights.count)
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
