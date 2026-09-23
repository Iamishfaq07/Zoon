import Foundation

/// The one tonight every surface is allowed to show.
///
/// **Why this exists.** `DayContext.targetBedtime()` used to be
/// `wake-tomorrow − SleepNeed.totalNeedMinutes`. That total already contains
/// a 33% repayment. `SleepAutopilot` then applied its own 25% repayment to
/// whatever "debt" it was handed — and Today handed it `SleepNeed.debtMinutes`,
/// which is the repayment slice, not the outstanding shortfall. Meanwhile
/// Tomorrow, What-If and the Runway went through `SleepPlanningInputs`.
/// Four answers, one night.
///
/// This type is the only composer. It builds `SleepPlanningInputs` from the
/// outstanding shortfall, hands Autopilot the need *before* repayment plus
/// the full shortfall, and resolves a bedtime. Every consumer reads this.
/// A Calendar commitment is a documented reason for Tomorrow to differ;
/// without one, Tonight, reminders, Nap Coach, Energy and the Watch snapshot
/// must agree.
struct TonightPlan: Hashable, Sendable {

    enum ObligationSource: String, Sendable, Hashable {
        case none
        case bodyClock
        case calendar
        case manual
    }

    struct Driver: Hashable, Sendable, Identifiable {
        var id: String { label }
        let label: String
        let minutes: Double
        let detail: String
    }

    let planning: SleepPlanningInputs
    let autopilot: SleepAutopilot.Plan?
    let obligationSource: ObligationSource
    /// Wall-clock minutes of wind-down before bed, baked so reminders and
    /// the timeline cannot pick different leads.
    let windDownLeadMinutes: Double
    /// Last night's wake, used only when Autopilot has no habit to move.
    let fallbackWake: Date

    var suggestedSleepTargetMinutes: Double {
        autopilot?.targetSleepMinutes ?? planning.tonightNeedMinutes
    }

    var planningConfidence: MetricConfidence {
        autopilot?.confidence ?? .low
    }

    var drivers: [Driver] {
        var rows: [Driver] = [
            Driver(
                label: "Personal baseline",
                minutes: planning.baselineNeedMinutes,
                detail: "Learned from unconstrained nights, not a measurement of physiological need."
            )
        ]
        if planning.tonightRepaymentMinutes >= 1 {
            rows.append(Driver(
                label: "Shortfall repayment",
                minutes: planning.tonightRepaymentMinutes,
                detail: "One slice of the outstanding shortfall. Not the whole debt."
            ))
        }
        if planning.tonightStrainAdjustmentMinutes >= 1 {
            rows.append(Driver(
                label: "Yesterday's strain",
                minutes: planning.tonightStrainAdjustmentMinutes,
                detail: "Tonight only. Future nights do not inherit this."
            ))
        }
        if planning.tonightNapCreditMinutes >= 1 {
            rows.append(Driver(
                label: "Nap credit",
                minutes: -planning.tonightNapCreditMinutes,
                detail: "Already slept today, so the night target comes down."
            ))
        }
        return rows
    }

    /// The bedtime every surface must show.
    ///
    /// Resolved through `ResolvedSleepEpisode.window`, like the reminders,
    /// the alarm and Tonight: a bedtime that has passed stays tonight's until
    /// the wake it was planning for. The next occurrence after `now` jumped
    /// to tomorrow the minute bedtime passed, and the fallback's "wake
    /// tomorrow" was the morning after next once past midnight.
    func bedtime(now: Date = .now, calendar: Calendar = .current) -> Date? {
        if let autopilot,
           let window = ResolvedSleepEpisode.window(
            bedMinute: autopilot.targetBedtimeMinutes,
            wakeMinute: autopilot.targetWakeMinutes,
            containingOrAfter: now,
            calendar: calendar
           ) {
            return window.start
        }
        return fallbackBedtime(now: now, calendar: calendar)
    }

    func wakeTime(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let bed = bedtime(now: now, calendar: calendar) else { return nil }
        return calendar.date(
            byAdding: .minute,
            value: Int(suggestedSleepTargetMinutes.rounded()),
            to: bed
        )
    }

    func windDownStart(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let bed = bedtime(now: now, calendar: calendar) else { return nil }
        return calendar.date(
            byAdding: .minute,
            value: -Int(windDownLeadMinutes.rounded()),
            to: bed
        )
    }

    /// Same naive geometry `DayContext.targetBedtime` used, but the minutes
    /// subtracted are tonight's planning target (one repayment), not the
    /// composed `SleepNeed.totalNeedMinutes` (a different repayment).
    private func fallbackBedtime(now: Date, calendar: Calendar) -> Date? {
        let wake = calendar.dateComponents([.hour, .minute], from: fallbackWake)
        let wakeMinute = Double((wake.hour ?? 7) * 60 + (wake.minute ?? 0))
        return ResolvedSleepEpisode.window(
            bedMinute: wakeMinute - suggestedSleepTargetMinutes,
            wakeMinute: wakeMinute,
            containingOrAfter: now,
            calendar: calendar
        )?.start
    }
}

enum TonightPlanner {

    /// The single construction every Tonight consumer must go through.
    static func build(
        nights: [SleepNightFeatures],
        sleepNeed: SleepNeed,
        outstandingShortfallMinutes: Double,
        lastWake: Date,
        now: Date = .now,
        obligationWake: Date? = nil,
        obligationSource: TonightPlan.ObligationSource = .none,
        windDownLeadMinutes: Double = ZoonTomorrow.windDownLeadMinutes,
        planning explicitPlanning: SleepPlanningInputs? = nil,
        calendar: Calendar = .current
    ) -> TonightPlan {
        // `explicitPlanning` is the as-of-now figure `DayContextBuilder`
        // composes: the shortfall through the night just slept plus today's
        // naps and strain (`SleepPlanningInputs.asOfNow`). Without one, the
        // plan is composed from `sleepNeed` as before.
        let planning = explicitPlanning ?? sleepNeed.planningInputs(
            outstandingShortfallMinutes: outstandingShortfallMinutes
        )
        let obligationMinutes = obligationWake.map {
            Statistics.circularMinutesFromMidnight($0, calendar: calendar)
        }
        let autopilot = SleepAutopilot.plan(
            nights: nights,
            planning: planning,
            obligationWakeMinutes: obligationMinutes
        )
        return TonightPlan(
            planning: planning,
            autopilot: autopilot,
            obligationSource: obligationWake == nil ? .none : obligationSource,
            windDownLeadMinutes: windDownLeadMinutes,
            fallbackWake: lastWake
        )
    }
}

extension SleepAutopilot {

    /// The correct wiring: need *before* repayment, outstanding shortfall
    /// in full. Callers that still pass `SleepNeed.debtMinutes` as debt are
    /// applying the repayment twice.
    static func plan(
        nights: [SleepNightFeatures],
        planning: SleepPlanningInputs,
        obligationWakeMinutes: Double? = nil,
        minimumNights: Int = minimumNights
    ) -> Plan? {
        plan(
            nights: nights,
            sleepNeedMinutes: planning.tonightNeedBeforeRepaymentMinutes,
            obligationWakeMinutes: obligationWakeMinutes,
            sleepDebtMinutes: planning.currentShortfallMinutes,
            minimumNights: minimumNights
        )
    }
}
