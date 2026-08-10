import Foundation

/// How much sleep you actually needed last night, and how much of it you got.
///
/// Modelled on Whoop's sleep need: a personal baseline plus the three things
/// that legitimately raise the requirement on a given night. A fixed 8-hour
/// target treats every night the same, which is wrong in the direction that
/// matters most — the night after a hard session or a short night is exactly
/// when you need more, and a static goal tells you nothing.
///
/// ```
/// need = baseline + sleepDebt×payback + strainBonus − napCredit
/// performance = timeAsleep / need × 100
/// ```
struct SleepNeed: Codable, Hashable, Sendable {

    /// The user's habitual requirement, minutes.
    let baselineMinutes: Double
    /// Extra needed to service accumulated debt, minutes.
    let debtMinutes: Double
    /// Extra earned by yesterday's exertion, minutes.
    let strainMinutes: Double
    /// Offset by daytime naps, minutes.
    let napCreditMinutes: Double

    /// What was actually slept, minutes.
    let achievedMinutes: Double

    var totalNeedMinutes: Double {
        max(baselineMinutes, baselineMinutes + debtMinutes + strainMinutes - napCreditMinutes)
    }

    /// 0–100+, capped at 100 for display. Whoop calls this Sleep Performance.
    var performancePercent: Double {
        guard totalNeedMinutes > 0 else { return 0 }
        return min(100, achievedMinutes / totalNeedMinutes * 100)
    }

    /// Shortfall in minutes, floored at zero.
    var shortfallMinutes: Double {
        max(0, totalNeedMinutes - achievedMinutes)
    }

    /// Breakdown rows for the stacked "need" bar in the UI.
    var contributions: [Contribution] {
        var rows = [
            Contribution(label: "Baseline need", minutes: baselineMinutes, kind: .baseline)
        ]
        if debtMinutes >= 1 {
            rows.append(Contribution(label: "Sleep debt", minutes: debtMinutes, kind: .debt))
        }
        if strainMinutes >= 1 {
            rows.append(Contribution(label: "Yesterday's strain", minutes: strainMinutes, kind: .strain))
        }
        if napCreditMinutes >= 1 {
            rows.append(Contribution(label: "Naps", minutes: -napCreditMinutes, kind: .nap))
        }
        return rows
    }

    struct Contribution: Hashable, Sendable, Identifiable {
        let label: String
        let minutes: Double
        let kind: Kind
        var id: String { label }

        enum Kind: String, Hashable, Sendable {
            case baseline, debt, strain, nap
        }
    }

    // MARK: - Computation

    /// Fraction of outstanding debt to try to repay in a single night.
    ///
    /// Deliberately partial. Telling someone carrying six hours of debt that
    /// they need fourteen hours tonight is useless advice they will ignore,
    /// and it makes every subsequent score look like failure. A third at a
    /// time is repayable.
    private static let debtPaybackFraction = 0.33
    /// Cap on debt-driven extra, minutes.
    private static let maxDebtBonus = 90.0
    /// Cap on strain-driven extra, minutes.
    private static let maxStrainBonus = 55.0

    static func compute(
        goalMinutes: Double,
        outstandingDebtMinutes: Double,
        yesterdayStrain: Double,
        napMinutes: Double,
        achievedMinutes: Double
    ) -> SleepNeed {

        let debt = min(maxDebtBonus, max(0, outstandingDebtMinutes) * debtPaybackFraction)

        // Strain bonus ramps in above a moderate day: an ordinary day doesn't
        // change what you need. Strain runs 0–21, so 8 is roughly "a normal
        // active day" and 21 is a race.
        let strainExcess = max(0, yesterdayStrain - 8) / 13
        let strain = min(maxStrainBonus, strainExcess * maxStrainBonus)

        return SleepNeed(
            baselineMinutes: goalMinutes,
            debtMinutes: debt,
            strainMinutes: strain,
            napCreditMinutes: max(0, napMinutes),
            achievedMinutes: achievedMinutes
        )
    }
}

extension SleepNeed {

    var performanceBand: String {
        switch performancePercent {
        case ..<70: "Insufficient"
        case 70..<85: "Adequate"
        case 85..<95: "Sufficient"
        default: "Optimal"
        }
    }

    /// Plain-language summary for the sleep card.
    var summary: String {
        let need = SleepNightFeatures.formatMinutes(totalNeedMinutes)
        let got = SleepNightFeatures.formatMinutes(achievedMinutes)
        if shortfallMinutes < 10 {
            return "You needed \(need) and got \(got)."
        }
        return "You needed \(need) and got \(got) — \(SleepNightFeatures.formatMinutes(shortfallMinutes)) short."
    }
}
