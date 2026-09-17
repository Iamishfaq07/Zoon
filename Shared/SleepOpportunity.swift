import Foundation

/// Where a night's shortfall actually came from: not enough time allowed, or
/// not enough of the allowed time spent asleep.
///
/// The arithmetic is an identity, which is what makes it worth showing:
///
///     need − asleep  =  (need − opportunity)  +  (opportunity − asleep)
///                        ────────────────────     ──────────────────────
///                          opportunity gap            execution gap
///
/// Two people can both be forty minutes short and need opposite advice. One
/// went to bed too late; a longer wind-down is the whole answer. The other
/// was in bed for nine hours and awake for two of them; more time in bed is
/// the wrong instruction and might make it worse. Every metric Zoon already
/// has says "you were short". None of them says which.
///
/// **What opportunity is here.** Time in bed, which is the measurable proxy
/// for the window someone allowed themselves. It is not always measured:
/// Apple Watch alone does not record it, and `timeInBedIsEstimated` says
/// when it has been inferred from the sleep period instead. An estimated
/// time in bed is close to asleep time by construction, so it understates
/// the execution gap — which is exactly the direction that would make a
/// fragmentation problem look like a scheduling one. When it is estimated,
/// this refuses to attribute at all rather than attributing wrongly.
struct SleepOpportunity: Hashable, Sendable {

    enum Cause: String, Hashable, Sendable {
        /// Not enough time was allowed for sleep.
        case opportunity
        /// Enough time was allowed; less of it was spent asleep.
        case execution
        /// Both contributed, neither dominates.
        case both
    }

    let needMinutes: Double
    /// Time in bed — the window allowed.
    let opportunityMinutes: Double
    let actualMinutes: Double
    /// Whether `opportunityMinutes` was measured or inferred.
    let opportunityIsEstimated: Bool
    /// This person's own usual efficiency, when enough nights exist for one.
    /// Only used to decide whether "lower than usual" may be said at all.
    let typicalEfficiencyPercent: Double?

    /// How far short of need the night finished. Zero when it met it.
    var shortfallMinutes: Double { max(0, needMinutes - actualMinutes) }

    /// Need minus the window allowed. Negative means more time was allowed
    /// than needed, which is a real and good answer, so it is not clamped.
    var opportunityGapMinutes: Double { needMinutes - opportunityMinutes }

    /// The window allowed minus time asleep: awake-in-bed time, latency
    /// included.
    var executionGapMinutes: Double { max(0, opportunityMinutes - actualMinutes) }

    /// Achieved sleep as a percentage of the window allowed.
    var efficiencyPercent: Double {
        guard opportunityMinutes > 0 else { return 0 }
        return min(100, actualMinutes / opportunityMinutes * 100)
    }

    /// Shortfall below which the night is treated as having met its need.
    ///
    /// Sleep need is itself an estimate to within tens of minutes, so a
    /// fifteen-minute miss is not a finding.
    static let metTolerance = 15.0

    /// How much larger one gap must be than the other before it is named as
    /// the cause rather than both.
    static let dominanceMargin = 20.0

    /// Which side the shortfall came from, or `nil` when there is no
    /// shortfall to explain — or no honest way to explain it.
    var cause: Cause? {
        guard shortfallMinutes > Self.metTolerance else { return nil }
        // An inferred time in bed sits close to asleep time by construction,
        // so the execution gap it produces is not a measurement of anything.
        // Refusing is the honest outcome; the numbers are still shown.
        guard !opportunityIsEstimated else { return nil }
        let opportunityGap = max(0, opportunityGapMinutes)
        let executionGap = executionGapMinutes
        if opportunityGap - executionGap > Self.dominanceMargin { return .opportunity }
        if executionGap - opportunityGap > Self.dominanceMargin { return .execution }
        return .both
    }

    /// Whether this night's efficiency is genuinely below the person's own.
    ///
    /// Gates the phrase "lower than usual", which is a comparative claim and
    /// may not be made without something to compare against.
    var isBelowUsualEfficiency: Bool {
        guard let typicalEfficiencyPercent else { return false }
        return efficiencyPercent < typicalEfficiencyPercent - 3
    }

    /// The decomposition in one sentence, or `nil` when there is nothing to
    /// explain.
    var sentence: String? {
        guard let cause else {
            if shortfallMinutes <= Self.metTolerance { return nil }
            return "You were \(SleepNightFeatures.formatMinutes(shortfallMinutes)) short of your sleep need. Your time in bed was estimated rather than measured, so Zoon cannot say how much of that was the window and how much was the sleep itself."
        }
        switch cause {
        case .opportunity:
            return "Most of this shortfall came from the time available rather than from broken sleep — you allowed \(SleepNightFeatures.formatMinutes(opportunityMinutes)) against a need of \(SleepNightFeatures.formatMinutes(needMinutes))."
        case .execution:
            let usual = isBelowUsualEfficiency
                ? " That is lower than your usual."
                : ""
            return "You allowed enough time — \(SleepNightFeatures.formatMinutes(opportunityMinutes)) — but were asleep for \(SleepNightFeatures.formatMinutes(actualMinutes)) of it.\(usual)"
        case .both:
            return "This shortfall came from both sides: the window was \(SleepNightFeatures.formatMinutes(max(0, opportunityGapMinutes))) short of your need, and \(SleepNightFeatures.formatMinutes(executionGapMinutes)) of the window was spent awake."
        }
    }

    /// The three rows, in the order they are read.
    var rows: [(label: String, minutes: Double)] {
        [
            ("Sleep need", needMinutes),
            ("Opportunity", opportunityMinutes),
            ("Actual sleep", actualMinutes)
        ]
    }

    /// Builds the decomposition for one night.
    ///
    /// - Parameters:
    ///   - needMinutes: the person's own need, never a guideline.
    ///   - history: nights before this one, for the usual-efficiency
    ///     comparison. Fewer than `minimumBaselineNights` means no
    ///     comparative claim is made rather than one made against a thin
    ///     baseline.
    static func make(
        night: SleepNightFeatures,
        needMinutes: Double,
        history: [SleepNightFeatures] = []
    ) -> SleepOpportunity? {
        guard needMinutes > 0, night.timeInBedMinutes > 0 else { return nil }
        let measured = history.filter { !$0.timeInBedIsEstimated }.map(\.sleepEfficiencyPercent)
        return SleepOpportunity(
            needMinutes: needMinutes,
            opportunityMinutes: night.timeInBedMinutes,
            // Main sleep only, matched to `timeInBedMinutes`, which is also
            // main sleep. Using the 24-hour total against a single night's
            // window would let an afternoon nap close a gap the window never
            // opened.
            actualMinutes: night.timeAsleepMinutes,
            opportunityIsEstimated: night.timeInBedIsEstimated,
            typicalEfficiencyPercent: measured.count >= minimumBaselineNights
                ? Statistics.median(measured)
                : nil
        )
    }

    /// Nights of measured time in bed needed before "lower than usual" may
    /// be said.
    static let minimumBaselineNights = 7
}
