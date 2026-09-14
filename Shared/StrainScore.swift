import Foundation

/// Cardiovascular load for a day, on a 0–21 scale.
///
/// The scale is **logarithmic**, which is the part that matters and the part
/// people get wrong: going from 8 to 10 is an ordinary harder day, going from
/// 16 to 18 is brutal. A linear 0–100 "activity score" flatters easy days and
/// compresses the hard ones into indistinguishable mush at the top.
///
/// Built from time spent in heart-rate zones, weighted by zone, because that's
/// what's actually derivable from HealthKit without a proprietary model.
///
/// A 0–21 range is a convention several load metrics share; sharing a range
/// is not sharing a definition. A day scored here is not interchangeable with
/// the same day scored by another product, and nothing in the app should
/// suggest it is.
struct StrainScore: Codable, Hashable, Sendable {

    /// 0...21
    let value: Double
    let zoneMinutes: [Zone: Double]
    let activeEnergyKcal: Double?
    /// False when there wasn't enough heart-rate coverage to trust it.
    let isEstimate: Bool
    /// Where the zone boundaries these minutes were sorted into came from.
    ///
    /// Optional because it is genuinely unknown for a score decoded from a
    /// payload written before this existed, and for the active-energy
    /// fallback, which sorts nothing into zones at all. Unknown is not the
    /// same as generic, and the UI must be able to tell them apart.
    let zoneProvenance: HRZoneProvenance?

    init(
        value: Double,
        zoneMinutes: [Zone: Double],
        activeEnergyKcal: Double?,
        isEstimate: Bool,
        zoneProvenance: HRZoneProvenance? = nil
    ) {
        self.value = value
        self.zoneMinutes = zoneMinutes
        self.activeEnergyKcal = activeEnergyKcal
        self.isEstimate = isEstimate
        self.zoneProvenance = zoneProvenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(Double.self, forKey: .value)
        zoneMinutes = try container.decode([Zone: Double].self, forKey: .zoneMinutes)
        activeEnergyKcal = try container.decodeIfPresent(Double.self, forKey: .activeEnergyKcal)
        isEstimate = try container.decode(Bool.self, forKey: .isEstimate)
        zoneProvenance = try container.decodeIfPresent(HRZoneProvenance.self, forKey: .zoneProvenance)
    }

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

    /// Scale ceiling. `ln`-derived, so the top of the range compresses rather
    /// than clipping: the hardest days someone actually has stay
    /// distinguishable from one another instead of all reading "max".
    static let maxValue = 21.0

    /// Raw weighted load at which the scale saturates.
    private static let saturationLoad = 420.0

    static func compute(
        zoneMinutes: [Zone: Double],
        activeEnergyKcal: Double?,
        hasHeartRateCoverage: Bool,
        zoneProvenance: HRZoneProvenance = .genericFallback
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
            isEstimate: !hasHeartRateCoverage,
            zoneProvenance: zoneProvenance
        )
    }

    /// Active energy an ordinary day logs without any workout -- standing,
    /// walking around, fidgeting. The zone path scores all of that as zero
    /// because none of it lifts heart rate above 50% HRR, so the estimate
    /// has to discount it too or a sedentary day reads as a training day.
    private static let sedentaryActiveEnergyKcal = 250.0

    /// Fallback when heart-rate coverage is too sparse to build zones —
    /// common if the watch came off during the day.
    ///
    /// Active energy is a much blunter instrument (it can't tell a long walk
    /// from a short sprint), so anything derived this way is flagged as an
    /// estimate and the UI says so.
    ///
    /// Calibrated so the pseudo-load lands where the zone path's
    /// `Σ minutes × weight` would for a comparable day (30 min moderate ≈
    /// 10.2, 60 min vigorous ≈ 15.7), through the same `log1p` curve:
    ///
    ///    150 kcal /   0 min → load   0.0 → 0.0  (Light; was 13.8, "Strenuous")
    ///    400 kcal /  30 min → load  15.0 → 9.6  (Moderate; was 18.0)
    ///    800 kcal /  60 min → load  47.5 → 13.5 (Strenuous; was 20.4)
    ///   1200 kcal /  90 min → load  80.0 → 15.3 (High)
    ///   2000 kcal / 150 min → load 145.0 → 17.3 (High)
    static func estimate(activeEnergyKcal: Double, exerciseMinutes: Double) -> StrainScore {
        let surplusKcal = max(0, activeEnergyKcal - sedentaryActiveEnergyKcal)
        let pseudoLoad = surplusKcal * 0.07 + exerciseMinutes * 0.15
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

    /// One line naming the weakest thing this number rests on, or `nil` when
    /// there is nothing worth qualifying.
    ///
    /// Coverage and zone boundaries fail independently. A day can be watched
    /// continuously and still be sorted by a guessed maximum heart rate, and
    /// the second is the quieter problem: nothing about the display hints at
    /// it, so a number built on 208 − 0.7 × age looks exactly as solid as one
    /// built on a max the person actually hit. Coverage is named first when
    /// both are weak, because a score with no heart rate behind it is the
    /// larger caveat.
    var confidenceNote: String? {
        if isEstimate {
            return "Estimated from active energy — not enough heart-rate coverage to build zones."
        }
        switch zoneProvenance {
        case .some(let provenance) where provenance.isPersonalized:
            return nil
        case .some(.ageEstimated):
            return "Zones from an age-estimated maximum heart rate, not one you've hit."
        case .some(.genericFallback):
            return "Zones from a default maximum heart rate. Add your age in Settings to sharpen this."
        case .none:
            return nil
        }
    }

    /// Short enough for a row beside the band.
    var confidenceTag: String? {
        if isEstimate { return "estimated" }
        guard let zoneProvenance, !zoneProvenance.isPersonalized else { return nil }
        return "estimated zones"
    }

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
