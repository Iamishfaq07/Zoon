import Foundation

/// Cardiovascular load for a day, on a 0–21 scale.
///
/// Whoop's Strain scale, reimplemented from the published concept. The scale is
/// **logarithmic**, which is the part that matters and the part people get
/// wrong: going from 8 to 10 is an ordinary harder day, going from 16 to 18 is
/// brutal. A linear 0–100 "activity score" flatters easy days and compresses the
/// hard ones into indistinguishable mush at the top.
///
/// Built from time spent in heart-rate zones, weighted by zone, because that's
/// what's actually derivable from HealthKit without a proprietary model.
struct StrainScore: Codable, Hashable, Sendable {

    /// 0...21
    let value: Double
    let zoneMinutes: [Zone: Double]
    let activeEnergyKcal: Double?
    /// False when there wasn't enough heart-rate coverage to trust it.
    let isEstimate: Bool

    enum Zone: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
        case light      // 50–60% HRR
        case moderate   // 60–70%
        case vigorous   // 70–80%
        case hard       // 80–90%
        case maximum    // 90%+

        var id: String { rawValue }

        var label: String {
            switch self {
            case .light: "Light"
            case .moderate: "Moderate"
            case .vigorous: "Vigorous"
            case .hard: "Hard"
            case .maximum: "Max"
            }
        }

        /// Contribution multiplier. Steeply weighted — a minute at threshold
        /// costs far more than a minute walking, which is the whole premise.
        var weight: Double {
            switch self {
            case .light: 0.2
            case .moderate: 0.6
            case .vigorous: 1.5
            case .hard: 3.0
            case .maximum: 5.0
            }
        }

        /// Lower bound as a fraction of heart-rate reserve.
        var lowerBoundHRR: Double {
            switch self {
            case .light: 0.50
            case .moderate: 0.60
            case .vigorous: 0.70
            case .hard: 0.80
            case .maximum: 0.90
            }
        }
    }

    /// Scale ceiling. Whoop's 21 is `ln`-derived; we match the shape so the
    /// numbers mean roughly what a user coming from that world expects.
    static let maxValue = 21.0

    /// Raw weighted load at which the scale saturates.
    private static let saturationLoad = 420.0

    static func compute(
        zoneMinutes: [Zone: Double],
        activeEnergyKcal: Double?,
        hasHeartRateCoverage: Bool
    ) -> StrainScore {

        let load = zoneMinutes.reduce(0.0) { $0 + $1.value * $1.key.weight }

        // Logarithmic compression: rapid early gains, heavily damped at the top.
        // log1p keeps load 0 mapping to exactly 0 rather than to −∞.
        let normalized = log1p(load) / log1p(saturationLoad)
        let value = min(maxValue, normalized * maxValue)

        return StrainScore(
            value: value,
            zoneMinutes: zoneMinutes,
            activeEnergyKcal: activeEnergyKcal,
            isEstimate: !hasHeartRateCoverage
        )
    }

    /// Fallback when heart-rate coverage is too sparse to build zones —
    /// common if the watch came off during the day.
    ///
    /// Active energy is a much blunter instrument (it can't tell a long walk
    /// from a short sprint), so anything derived this way is flagged as an
    /// estimate and the UI says so.
    static func estimate(activeEnergyKcal: Double, exerciseMinutes: Double) -> StrainScore {
        let pseudoLoad = activeEnergyKcal * 0.35 + exerciseMinutes * 1.2
        let normalized = log1p(pseudoLoad) / log1p(saturationLoad)
        return StrainScore(
            value: min(maxValue, normalized * maxValue),
            zoneMinutes: [:],
            activeEnergyKcal: activeEnergyKcal,
            isEstimate: true
        )
    }

    static let zero = StrainScore(value: 0, zoneMinutes: [:], activeEnergyKcal: 0, isEstimate: true)
}

extension StrainScore {

    var band: String {
        switch value {
        case ..<6: "Light"
        case 6..<10: "Moderate"
        case 10..<14: "Strenuous"
        case 14..<18: "High"
        default: "All-out"
        }
    }

    var displayValue: String { String(format: "%.1f", value) }

    /// Whether today's exertion matched what recovery said the body could take.
    ///
    /// The pairing is the actual product: strain alone is a vanity metric, and
    /// recovery alone doesn't tell you what to do with it.
    static func balanceVerdict(strain: Double, recoveryPercent: Int) -> String {
        // The strain a given recovery reasonably supports.
        let supported = 4 + Double(recoveryPercent) / 100 * 12
        let delta = strain - supported

        switch delta {
        case ..<(-4): return "Well under what your body could handle today."
        case -4..<2: return "Well matched to your recovery."
        case 2..<5: return "Above what your recovery supported. Expect to feel it."
        default: return "Far beyond today's recovery. Prioritise sleep tonight."
        }
    }
}
