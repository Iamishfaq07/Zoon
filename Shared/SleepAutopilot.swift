import Foundation

/// Works out what tonight's bed and wake times should be, and -- more
/// importantly -- how far it is willing to move them.
///
/// The naive version of this feature computes an ideal schedule and shows
/// it: "your target bedtime is 22:40". Someone currently going to bed at
/// midnight reads that, fails to do it, and the number sits there being
/// wrong every night. The schedule was not the hard part; the distance was.
///
/// So this is written as a controller rather than a calculator. It measures
/// where the person actually is, works out where they should be, and moves
/// the target a bounded step in that direction -- the same shape as any
/// closed-loop system that has to be stable rather than merely correct.
/// Three properties make it behave:
///
/// 1. **A rate limit.** Circadian phase shifts by roughly twenty minutes a
///    day under ordinary light exposure. A plan that asks for ninety is not
///    a plan, it is a wish, and asking for it every night teaches the person
///    that the number is decorative.
/// 2. **A deadband.** Below a threshold the target holds exactly where they
///    already are. Without this, ordinary night-to-night variation would
///    produce a new "target" every evening, chasing noise and never letting
///    a habit form -- which is the one thing regularity actually needs.
/// 3. **A capped correction on sleep debt.** Debt is repaid a slice at a
///    time. Nobody sleeps off four hours of debt in one night, and telling
///    them to go to bed four hours early is worse than saying nothing.
///
/// **A plan, not a prescription.** This arranges the person's own numbers
/// into a schedule. It makes no claim that following it will improve
/// anything, and the copy never implies one.
enum SleepAutopilot {

    /// Nights of history before a habit is known well enough to move it.
    static let minimumNights = 7

    /// How far back the current habit is measured.
    static let window = 14

    /// The largest shift asked for in one night, in minutes.
    ///
    /// Circadian phase moves roughly this much per day under ordinary light
    /// exposure. The rate limit is what makes a multi-week correction
    /// arrive as a sequence of achievable nights.
    static let maximumNightlyShift = 20.0

    /// Below this, the target holds exactly where the person already is.
    /// Ordinary variation is larger than this, and a target that moves with
    /// it is noise wearing a recommendation's clothes.
    static let deadband = 10.0

    /// The most extra sleep asked for in one night to repay debt.
    static let maximumDebtRepayment = 30.0

    /// The share of outstanding debt attempted in any one night.
    static let debtRepaymentRate = 0.25

    struct Plan: Hashable, Sendable {
        /// Minutes from midnight, on the same wrapped scale as
        /// `Statistics.circularMinutesFromMidnight` -- negative before
        /// midnight, positive after.
        let targetBedtimeMinutes: Double
        let targetSleepMinutes: Double
        /// Signed shift from the person's current habit. Negative is
        /// earlier.
        let shiftMinutes: Double
        /// Extra sleep included tonight to repay debt, already capped.
        let debtRepaymentMinutes: Double
        /// True when the correction fell inside the deadband and the target
        /// is simply where they already are.
        let isHolding: Bool
        let confidence: MetricConfidence

        var targetWakeMinutes: Double { targetBedtimeMinutes + targetSleepMinutes }

        var sentence: String {
            guard !isHolding else {
                return "Tonight looks like your usual night. No change worth making."
            }
            let direction = shiftMinutes < 0 ? "earlier" : "later"
            let magnitude = SleepNightFeatures.formatMinutes(abs(shiftMinutes))
            var text = "Aim for \(magnitude) \(direction) than usual tonight"
            if debtRepaymentMinutes > 0 {
                text += ", which includes "
                    + "\(SleepNightFeatures.formatMinutes(debtRepaymentMinutes)) toward what you're owed"
            }
            return text + "."
        }

        /// Travels with every plan. Arranging someone's own numbers into a
        /// schedule is not evidence that following it helps them.
        var caveat: String {
            "This is built from your own nights and your own sleep need."
                + " It is a plan, not a promise about how you'll feel."
        }
    }

    // MARK: - Planning

    /// Builds tonight's plan.
    ///
    /// - Parameters:
    ///   - nights: recent history, in any order.
    ///   - sleepNeedMinutes: the person's own learned need, not a guideline
    ///     figure. Passed in rather than computed here so the autopilot
    ///     cannot quietly disagree with the number shown elsewhere.
    ///   - obligationWakeMinutes: a wake time tonight is anchored to (an
    ///     alarm, a shift), on the same wrapped scale. When present the
    ///     bedtime is derived from it, because the wake time is the half
    ///     that is not negotiable.
    ///   - sleepDebtMinutes: outstanding debt, if any. Negative or zero
    ///     means nothing to repay.
    /// - Returns: `nil` when there is too little history to know the habit
    ///   being adjusted.
    static func plan(
        nights: [SleepNightFeatures],
        sleepNeedMinutes: Double,
        obligationWakeMinutes: Double? = nil,
        sleepDebtMinutes: Double = 0,
        minimumNights: Int = minimumNights
    ) -> Plan? {
        guard sleepNeedMinutes > 0 else { return nil }

        let recent = nights.sorted { $0.date < $1.date }.suffix(window)
        let bedtimes = recent.compactMap { TrendEngine.Metric.bedtime.value(from: $0) }
        let durations = recent.compactMap { TrendEngine.Metric.duration.value(from: $0) }
        guard bedtimes.count >= minimumNights, durations.count >= minimumNights,
              let habitualBedtime = Statistics.median(bedtimes),
              let habitualSleep = Statistics.median(durations) else { return nil }

        // Repay a slice of the debt, capped twice: once as a share of what
        // is outstanding, once in absolute minutes. Someone four hours down
        // is not going to bed four hours early tonight, and saying so would
        // cost the plan its credibility on every other night too.
        let repayment = min(
            max(sleepDebtMinutes, 0) * debtRepaymentRate,
            maximumDebtRepayment
        )
        let targetSleep = sleepNeedMinutes + repayment

        // With a fixed wake time, the bedtime is what has to give: the alarm
        // is the half of the night nobody can negotiate with.
        //
        // Without one, the correction comes from the duration shortfall
        // instead. An earlier bedtime is the actionable half there too --
        // sleeping later is not something anyone can reliably decide to do,
        // whereas starting earlier is -- so the shortfall is applied to the
        // bedtime and the wake time is left where it falls.
        let rawShift: Double = if let wake = obligationWakeMinutes {
            (wake - targetSleep) - habitualBedtime
        } else {
            habitualSleep - targetSleep
        }

        let isHolding = abs(rawShift) < deadband
        let shift = isHolding
            ? 0
            : max(-maximumNightlyShift, min(maximumNightlyShift, rawShift))

        return Plan(
            targetBedtimeMinutes: habitualBedtime + shift,
            targetSleepMinutes: targetSleep,
            shiftMinutes: shift,
            debtRepaymentMinutes: repayment,
            isHolding: isHolding,
            confidence: confidence(nights: bedtimes.count)
        )
    }

    private static func confidence(nights: Int) -> MetricConfidence {
        switch nights {
        case ..<minimumNights: .insufficient
        case minimumNights..<10: .low
        case 10..<14: .moderate
        default: .high
        }
    }
}
