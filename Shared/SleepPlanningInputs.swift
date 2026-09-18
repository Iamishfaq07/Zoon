import Foundation

/// The inputs every sleep planner takes, with each minute's meaning stated
/// once so no two planners can disagree about what they were handed.
///
/// **The bug this exists for.** `SleepNeed.totalNeedMinutes` is a *composed*
/// figure: `baseline + debtRepayment + strain − napCredit`, where the debt
/// term is already 33% of what is outstanding. Every planner was handed that
/// total **and** the full outstanding debt beside it, and then added a
/// repayment of its own:
///
/// ```swift
/// // SleepRunway, before:
/// let repayment = min(shortfall * SleepAutopilot.debtRepaymentRate, …)
/// let need = sleepNeedMinutes + repayment   // ← already had a repayment in it
/// ```
///
/// So a night carrying two hours of debt asked for roughly forty minutes of
/// repayment where one rule would have asked for thirty — and the error grew
/// with the debt, which is exactly when a plan most needs to be credible.
///
/// **Baseline is what a planner gets.** Not a total. The composition happens
/// in one place — `tonightNeedMinutes` below — and the planners read that
/// rather than adding terms of their own.
///
/// **Today's modifiers are today's.** Strain from yesterday's session and
/// credit from this afternoon's nap change *tonight*. Carrying them across a
/// seven-day horizon would plan every night of the week around one hard
/// Tuesday, so `futureNightNeedMinutes` drops them by construction and the
/// type makes that visible rather than leaving it to each caller's discipline.
struct SleepPlanningInputs: Hashable, Sendable {

    /// The learned personal requirement, with nothing folded in.
    let baselineNeedMinutes: Double

    /// Outstanding accumulated shortfall, in full. A planner decides how much
    /// of it to ask for tonight; it is never pre-repaid on the way in.
    let currentShortfallMinutes: Double

    /// Extra earned by yesterday's exertion. Tonight only.
    let tonightStrainAdjustmentMinutes: Double

    /// Offset by naps already taken today. Tonight only.
    let tonightNapCreditMinutes: Double

    init(
        baselineNeedMinutes: Double,
        currentShortfallMinutes: Double = 0,
        tonightStrainAdjustmentMinutes: Double = 0,
        tonightNapCreditMinutes: Double = 0
    ) {
        self.baselineNeedMinutes = max(0, baselineNeedMinutes)
        self.currentShortfallMinutes = max(0, currentShortfallMinutes)
        self.tonightStrainAdjustmentMinutes = max(0, tonightStrainAdjustmentMinutes)
        self.tonightNapCreditMinutes = max(0, tonightNapCreditMinutes)
    }

    /// How much of the outstanding shortfall to ask for in one night.
    ///
    /// One rule, one place. `SleepAutopilot` owns the numbers — a share of
    /// what is outstanding, capped in absolute minutes — because it is the
    /// engine that has to live with the bedtime they produce, and a second
    /// copy of a repayment rule is how this went wrong in the first place.
    static func repayment(for shortfallMinutes: Double) -> Double {
        min(
            max(0, shortfallMinutes) * SleepAutopilot.debtRepaymentRate,
            SleepAutopilot.maximumDebtRepayment
        )
    }

    /// Tonight's target: baseline, one repayment, today's modifiers.
    ///
    /// The night floor is the same rule `SleepNeed` applies for display, kept
    /// here so a long nap cannot turn into advice to sleep four hours.
    var tonightNeedMinutes: Double {
        let floor = max(baselineNeedMinutes * 0.75, baselineNeedMinutes - 120)
        let composed = baselineNeedMinutes
            + Self.repayment(for: currentShortfallMinutes)
            + tonightStrainAdjustmentMinutes
            - tonightNapCreditMinutes
        return max(floor, composed)
    }

    /// Tonight's need *before* any repayment: baseline plus today's modifiers.
    ///
    /// For an engine that applies the repayment itself — `SleepAutopilot` owns
    /// that rule and has to live with the bedtime it produces — this is the
    /// value to hand it. Passing `tonightNeedMinutes` there would repay the
    /// shortfall twice, which is precisely the defect this type was added for.
    var tonightNeedBeforeRepaymentMinutes: Double {
        let floor = max(baselineNeedMinutes * 0.75, baselineNeedMinutes - 120)
        return max(
            floor,
            baselineNeedMinutes + tonightStrainAdjustmentMinutes - tonightNapCreditMinutes
        )
    }

    /// What a night further out needs, before its own ledger is applied.
    ///
    /// Deliberately just the baseline. A planner walking a horizon carries the
    /// shortfall forward itself, night by night, and applies `repayment` to
    /// the ledger *as it stands going into that night* — not to today's.
    var futureNightNeedMinutes: Double { baselineNeedMinutes }

    /// The repayment tonight's target contains, for a caller that wants to
    /// show the composition rather than only the total.
    var tonightRepaymentMinutes: Double {
        Self.repayment(for: currentShortfallMinutes)
    }
}

extension SleepNeed {

    /// The planning view of this night's need.
    ///
    /// **Why the debt term is not carried over.** `SleepNeed.debtMinutes` is
    /// already a repayment — 33% of what was outstanding, capped at 90 — and
    /// handing it to a planner that computes its own would be the double count
    /// this type exists to end. The planner gets the *outstanding* shortfall
    /// and applies one rule to it.
    ///
    /// - Parameter outstandingShortfallMinutes: the full accumulated
    ///   shortfall, as `SleepNightFeatures.sleepDebtMinutes` reports it. Pass
    ///   the same value that was used to build this `SleepNeed`, not the
    ///   repayment inside it.
    func planningInputs(outstandingShortfallMinutes: Double) -> SleepPlanningInputs {
        SleepPlanningInputs(
            baselineNeedMinutes: baselineMinutes,
            currentShortfallMinutes: outstandingShortfallMinutes,
            tonightStrainAdjustmentMinutes: strainMinutes,
            tonightNapCreditMinutes: napCreditMinutes
        )
    }
}
