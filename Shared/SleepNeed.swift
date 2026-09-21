import Foundation

/// A planning target for a night's sleep, and how much of it was slept.
///
/// **This is a plan, not a measurement.** The header on this file used to say
/// "how much sleep you actually needed last night", and that is a claim Zoon
/// cannot make. Nothing here measures a physiological requirement. It takes a
/// learned baseline and adjusts it for three things that reasonably raise how
/// much sleep is worth aiming for on a given night, using coefficients that
/// are defensible heuristics rather than findings:
///
/// ```
/// target = baseline + shortfall×payback + strainBonus − napCredit
/// performance = timeAsleep / target × 100
/// ```
///
/// A fixed eight-hour goal treats every night the same, which is wrong in the
/// direction that matters most — the night after a hard session or a short one
/// is exactly when aiming higher is worth doing. But "the model suggests
/// aiming for 8h35" and "your body needed 8h35" are different statements, and
/// only the first is supported.
///
/// **Two figures, not one.** `baselineMinutes` is the learned estimate of
/// where this person's unconstrained nights sit — see `LearnedSleepNeed`,
/// which carries its own spread. `totalNeedMinutes` is tonight's planning
/// target, which is that baseline plus today's adjustments. The separation
/// matters because they answer different questions and only one of them moves
/// day to day; `SleepPlanningInputs` exists so the planners cannot confuse
/// them.
///
/// The shape of the model is a common one in the category. The coefficients
/// here are Zoon's own and are stated in the open, in `SleepNeed.compute`,
/// rather than reproduced from anybody's published product.
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
        // A nap is part of the day's sleep, so it must be able to reduce the
        // nocturnal target below the full daily baseline. Keep a substantial
        // night floor, though: a long afternoon nap should not turn into advice
        // to sleep only a few hours overnight.
        let nightFloor = max(baselineMinutes * 0.75, baselineMinutes - 120)
        return max(
            nightFloor,
            baselineMinutes + debtMinutes + strainMinutes - napCreditMinutes
        )
    }

    /// How much of the target was slept, 0–100, capped for display.
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
            Contribution(label: "Personal baseline", minutes: baselineMinutes, kind: .baseline)
        ]
        if debtMinutes >= 1 {
            rows.append(Contribution(label: "Shortfall repayment", minutes: debtMinutes, kind: .debt))
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
    /// A nap can offset at most two hours of the nocturnal target. Longer naps
    /// still appear in history, but should not produce an unsafe bedtime plan.
    private static let maxNapCredit = 120.0

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
            napCreditMinutes: min(maxNapCredit, max(0, napMinutes)),
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

    /// Plain-language summary for the sleep card. A planning target, not a
    /// measured physiological requirement — "you needed" is a claim the
    /// model cannot make.
    var summary: String {
        let need = SleepNightFeatures.formatMinutes(totalNeedMinutes)
        let got = SleepNightFeatures.formatMinutes(achievedMinutes)
        if shortfallMinutes < 10 {
            return "Last night's target was \(need). You slept \(got)."
        }
        return "Last night's target was \(need). You slept \(got) — \(SleepNightFeatures.formatMinutes(shortfallMinutes)) short."
    }
}
