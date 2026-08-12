import Foundation

/// Deterministic causal insights from thresholds and comparisons against the
/// user's own rolling baseline.
///
/// ## How it works
///
/// Each rule is a self-contained check that either fires or doesn't. A rule that
/// fires produces a `Finding` carrying a priority, a plain-language cause, and a
/// tip. The engine evaluates every rule, sorts by priority, and builds the final
/// insight from the strongest one — with the summary always describing the night
/// factually, and the causal line only attached when a rule actually fired.
///
/// ## Two rules the rules themselves follow
///
/// 1. **Never invent a cause.** `likelyCause` stays `nil` unless a rule fired
///    with real evidence behind it. A confident wrong explanation costs more
///    trust than an honest "solid night, nothing notable".
/// 2. **Never compare without a baseline.** Every comparative rule checks
///    `baseline.hasComparativeContext` first. On night two, "your deep sleep is
///    down 20%" is not a finding, it's noise.
struct RuleBasedInsightEngine: SleepInsightEngine {

    let displayName = "Rules"

    // MARK: - Thresholds
    //
    // Gathered here rather than scattered through the rules so the engine's
    // opinions are auditable in one place. These are consumer-wellness
    // heuristics drawn from commonly cited ranges — not clinical cutoffs.

    private enum T {
        /// Relative drop vs baseline that counts as meaningful.
        static let deepDropFraction = 0.20
        static let hrvDropFraction = 0.15
        /// Absolute thresholds.
        static let poorEfficiency = 80.0
        static let goodEfficiency = 88.0
        static let highLatencyMinutes = 30.0
        static let highWakeCount = 5
        static let elevatedRestingHRDelta = 5.0
        static let feverishTempDeltaC = 0.5
        static let lowSpO2Percent = 90.0
        static let lateWorkoutHours = 2.0
        /// Sleep debt worth mentioning, minutes.
        static let notableDebtMinutes = 180.0
        /// Bedtime SD worth mentioning, minutes.
        static let irregularBedtimeSD = 60.0
    }

    /// One rule's output. Priority orders competing explanations; the highest
    /// wins the causal slot.
    private struct Finding {
        let priority: Int
        let cause: String
        let tip: String
        let confidence: SleepInsight.Confidence
        /// True when the finding leans on SpO2 / respiratory / temperature, which
        /// require the non-diagnostic framing.
        var isPhysiological: Bool = false
    }

    // MARK: - Entry point

    func generate(
        for features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) -> SleepInsight {

        let findings = allRules.compactMap { $0(features, baseline, goalMinutes) }
        let strongest = findings.max { $0.priority < $1.priority }

        let summary = makeSummary(features: features, goalMinutes: goalMinutes, baseline: baseline)

        guard let strongest else {
            // Nothing fired. Say so plainly and give a maintenance tip rather
            // than manufacturing a problem.
            return SleepInsight(
                summary: summary,
                likelyCause: nil,
                actionableTip: maintenanceTip(features: features, baseline: baseline, goalMinutes: goalMinutes),
                confidence: baseline.hasComparativeContext ? .high : .medium,
                source: .ruleBased
            )
        }

        // Findings that lean on SpO2, respiratory rate, or temperature carry the
        // non-diagnostic reminder inline. Those are the ones a user is most
        // likely to read as a medical claim, and the disclaimer buried in
        // Settings is not where it needs to be at that moment.
        let tip = strongest.isPhysiological
            ? "\(strongest.tip)\n\nZoon can't diagnose anything — this is an observation, not a finding."
            : strongest.tip

        return SleepInsight(
            summary: summary,
            likelyCause: strongest.cause,
            actionableTip: tip,
            confidence: strongest.confidence,
            source: .ruleBased
        )
    }

    // MARK: - Rule registry

    private typealias Rule = (SleepNightFeatures, RollingBaseline, Double) -> Finding?

    /// Order here is irrelevant — priority decides. Grouped by theme for reading.
    private var allRules: [Rule] {
        [
            possibleIllnessRule,       // 100 — physiological, most important to surface
            lowSpO2Rule,               //  95
            lateWorkoutRule,           //  80
            strainRule,                //  75
            fragmentationRule,         //  70
            highLatencyRule,           //  65
            shortSleepRule,            //  60
            irregularScheduleRule,     //  55
            sleepDebtRule,             //  50
            lowDeepRule,               //  45
            lowREMRule                 //  40
        ]
    }

    // MARK: - Rules

    /// Elevated wrist temperature *and* suppressed HRV together — the classic
    /// "something is brewing" pattern.
    ///
    /// Requires both signals on purpose. Wrist temp alone moves with room
    /// temperature, bedding, and alcohol; HRV alone moves with training load.
    /// Together they're worth mentioning. Even then it's framed as an
    /// observation, never a diagnosis.
    private let possibleIllnessRule: Rule = { features, baseline, _ in
        guard baseline.hasComparativeContext,
              let tempDelta = features.wristTempDeltaC, tempDelta >= T.feverishTempDeltaC,
              let hrv = features.avgHRV, let hrvBase = baseline.hrv7DayAvg,
              hrv < hrvBase * (1 - T.hrvDropFraction) else { return nil }

        return Finding(
            priority: 100,
            cause: String(
                format: "Your wrist temperature ran %.1f°C above your baseline while HRV dropped to %.0f ms (usually %.0f). That combination often shows up when your body is fighting something off, or after a heavy drinking night.",
                tempDelta, hrv, hrvBase
            ),
            tip: "Treat today as a recovery day — go easy on training, hydrate, and get to bed early.",
            confidence: .medium,
            isPhysiological: true
        )
    }

    /// Sustained low blood oxygen. Surfaced because it matters, worded carefully
    /// because Zoon cannot and must not diagnose sleep apnea.
    private let lowSpO2Rule: Rule = { features, _, _ in
        guard let spo2 = features.avgSpO2, spo2 < T.lowSpO2Percent else { return nil }

        return Finding(
            priority: 95,
            cause: String(
                format: "Your average overnight blood oxygen was %.0f%%, below the typical range. Readings can be thrown off by a loose watch band or sleeping on your arm.",
                spo2
            ),
            tip: "Check your watch fits snugly. If this repeats across several nights, it's worth raising with a doctor.",
            confidence: .low,
            isPhysiological: true
        )
    }

    /// Hard training close to bedtime suppressing deep sleep.
    ///
    /// The strongest genuinely *causal* rule in the set: a mechanism (elevated
    /// core temperature and sympathetic tone), a measurable trigger (workout
    /// within 2h), and a measurable effect (deep sleep below baseline). Fires
    /// only when both halves are present.
    private let lateWorkoutRule: Rule = { features, baseline, _ in
        guard baseline.hasComparativeContext,
              let hours = features.lastWorkoutHoursBeforeBed, hours <= T.lateWorkoutHours,
              let deepBase = baseline.deep7DayAvg, deepBase > 0,
              features.hasStageBreakdown,
              features.deepMinutes < deepBase * (1 - T.deepDropFraction) else { return nil }

        let dropPercent = (1 - features.deepMinutes / deepBase) * 100

        return Finding(
            priority: 80,
            cause: String(
                format: "Deep sleep was down %.0f%% (%.0f min vs your usual %.0f). Your last workout ended about %.1fh before bed — hard training that close keeps core body temperature and adrenaline up, and deep sleep is the first thing to suffer.",
                dropPercent, features.deepMinutes, deepBase, hours
            ),
            tip: "Aim to finish hard sessions at least 3h before bed. Easy movement that late is fine.",
            confidence: .high
        )
    }

    /// Elevated resting heart rate plus depressed HRV, with no temperature
    /// signal — reads as accumulated strain rather than illness.
    private let strainRule: Rule = { features, baseline, _ in
        guard baseline.hasComparativeContext,
              let minHR = features.minHeartRate, let hrBase = baseline.minHeartRate7DayAvg,
              minHR >= hrBase + T.elevatedRestingHRDelta,
              let hrv = features.avgHRV, let hrvBase = baseline.hrv7DayAvg,
              hrv < hrvBase * (1 - T.hrvDropFraction) else { return nil }

        return Finding(
            priority: 75,
            cause: String(
                format: "Your lowest overnight heart rate was %.0f bpm against a usual %.0f, and HRV fell to %.0f ms. Your nervous system stayed in gear overnight — typically late eating, alcohol, stress, or a hard training block.",
                minHR, hrBase, hrv
            ),
            tip: "Keep tonight's dinner earlier and lighter, and skip alcohol.",
            confidence: .medium
        )
    }

    /// Fragmented sleep: lots of awakenings, poor efficiency.
    private let fragmentationRule: Rule = { features, _, _ in
        guard features.wakeCount >= T.highWakeCount,
              features.sleepEfficiencyPercent < T.poorEfficiency else { return nil }

        return Finding(
            priority: 70,
            // Int is interpolated rather than passed through %d: Swift's Int is
            // 64-bit and %d expects a 32-bit value.
            cause: "You woke \(features.wakeCount) times and spent "
                + "\(SleepNightFeatures.formatMinutes(features.awakeMinutes)) awake in bed — "
                + String(format: "efficiency came out at %.0f%%. ", features.sleepEfficiencyPercent)
                + "Fragmentation like this usually traces to room temperature, light, noise, or a late drink.",
            tip: "Try the room a couple of degrees cooler tonight, and cut liquids an hour before bed.",
            confidence: .medium
        )
    }

    /// Long time to fall asleep. Only fires when the source actually gives us
    /// in-bed data, so it stays silent for Apple-Watch-only users.
    private let highLatencyRule: Rule = { features, _, _ in
        guard let latency = features.sleepLatencyMinutes, latency >= T.highLatencyMinutes else { return nil }

        var cause = String(format: "It took you about %.0f minutes to fall asleep.", latency)
        if let exercise = features.exerciseMinutesPreviousDay, exercise < 15 {
            cause += " You also logged very little movement yesterday — low daytime activity makes sleep pressure build more slowly."
        } else {
            cause += " Long onset usually points to caffeine too late, screens in bed, or an unwinding mind."
        }

        return Finding(
            priority: 65,
            cause: cause,
            tip: "Set a caffeine cutoff 8h before bed, and give yourself 30 screen-free minutes beforehand.",
            confidence: .medium
        )
    }

    /// Well short of the user's own goal.
    private let shortSleepRule: Rule = { features, _, goalMinutes in
        let shortfall = goalMinutes - features.timeAsleepMinutes
        guard shortfall >= 60 else { return nil }

        return Finding(
            priority: 60,
            cause: String(
                format: "You slept %@, which is %@ short of your %@ goal. Most of the shortfall is simply time — you were only in bed %@.",
                features.formattedTimeAsleep,
                SleepNightFeatures.formatMinutes(shortfall),
                SleepNightFeatures.formatMinutes(goalMinutes),
                SleepNightFeatures.formatMinutes(features.timeInBedMinutes)
            ),
            tip: String(
                format: "Go to bed %@ earlier tonight — that alone closes most of the gap.",
                SleepNightFeatures.formatMinutes(min(shortfall, 60))
            ),
            confidence: .high
        )
    }

    /// Irregular bedtimes. Consistency is the single most actionable lever most
    /// people have, so it earns its own rule even when the night looks fine.
    private let irregularScheduleRule: Rule = { _, baseline, _ in
        guard let sd = baseline.bedtimeConsistencyMinutes, sd >= T.irregularBedtimeSD else { return nil }

        return Finding(
            priority: 55,
            cause: String(
                format: "Your bedtime has swung by roughly ±%.0f minutes over the past week. An irregular schedule shifts your body clock around and costs you deep sleep even on nights you get enough hours.",
                sd
            ),
            tip: "Pick one bedtime and hold it within 30 minutes for the next week, weekends included.",
            confidence: .high
        )
    }

    /// Accumulated debt worth flagging.
    private let sleepDebtRule: Rule = { features, _, _ in
        guard let debt = features.sleepDebtMinutes, debt >= T.notableDebtMinutes else { return nil }

        return Finding(
            priority: 50,
            cause: String(
                format: "You're carrying about %@ of sleep debt over the last two weeks. It builds quietly — 40 minutes short a night adds up faster than one bad night does.",
                SleepNightFeatures.formatMinutes(debt)
            ),
            tip: "Add 30–45 minutes to the front of your night for the next week. Sleeping in doesn't repay it as well as going to bed earlier.",
            confidence: .high
        )
    }

    /// Deep sleep below baseline with no better explanation available.
    private let lowDeepRule: Rule = { features, baseline, _ in
        guard baseline.hasComparativeContext,
              features.hasStageBreakdown,
              let deepBase = baseline.deep7DayAvg, deepBase > 0,
              features.deepMinutes < deepBase * (1 - T.deepDropFraction) else { return nil }

        let dropPercent = (1 - features.deepMinutes / deepBase) * 100

        return Finding(
            priority: 45,
            cause: String(
                format: "Deep sleep came in %.0f%% below your usual (%.0f min vs %.0f). Deep sleep is front-loaded into the first half of the night, so a late bedtime or a disturbed first few hours hits it hardest.",
                dropPercent, features.deepMinutes, deepBase
            ),
            tip: "Protect the first three hours tonight — dark, cool, quiet, and get to bed at your usual time.",
            confidence: .medium
        )
    }

    /// REM below the typical share. REM is concentrated toward morning, so a
    /// truncated night takes REM first.
    private let lowREMRule: Rule = { features, baseline, goalMinutes in
        guard baseline.hasComparativeContext,
              features.hasStageBreakdown,
              let remPercent = features.remPercentOfAsleep, remPercent < 15 else { return nil }

        var cause = String(
            format: "REM made up only %.0f%% of your sleep, below the usual 20–25%%.",
            remPercent
        )
        if features.timeAsleepMinutes < goalMinutes {
            cause += " REM is concentrated in the last few hours, so a short night cuts it disproportionately."
        } else {
            cause += " Alcohol and some medications suppress REM even when total sleep looks fine."
        }

        return Finding(
            priority: 40,
            cause: cause,
            tip: "Give yourself a full night's runway — the last 90 minutes of sleep are where most REM lives.",
            confidence: .medium
        )
    }

    // MARK: - Summary

    /// The factual one-liner. Always present, never speculative — it describes
    /// what happened, and the causal line (if any) explains why.
    private func makeSummary(
        features: SleepNightFeatures,
        goalMinutes: Double,
        baseline: RollingBaseline
    ) -> String {
        let score = SleepScore.compute(for: features, goalMinutes: goalMinutes)
        let duration = features.formattedTimeAsleep

        let qualifier: String
        switch score.band {
        case .excellent: qualifier = "Strong night"
        case .good: qualifier = "Solid night"
        case .fair: qualifier = "Mixed night"
        case .poor: qualifier = "Rough night"
        }

        // Add the most notable single detail, when there is one worth adding.
        if features.hasStageBreakdown, let deepPct = features.deepPercentOfAsleep, deepPct >= 20 {
            return "\(qualifier) — \(duration) with unusually strong deep sleep."
        }
        if features.wakeCount >= T.highWakeCount {
            return "\(qualifier) — \(duration), broken up by \(features.wakeCount) awakenings."
        }
        if features.sleepEfficiencyPercent >= T.goodEfficiency {
            return "\(qualifier) — \(duration) at \(Int(features.sleepEfficiencyPercent))% efficiency."
        }
        return "\(qualifier) — \(duration) asleep."
    }

    /// Used when no rule fires: a good night still deserves a useful sentence.
    private func maintenanceTip(
        features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) -> String {
        if features.timeAsleepMinutes >= goalMinutes {
            return "You hit your goal. Keep tonight's bedtime the same — consistency is what makes this repeatable."
        }
        if let sd = baseline.bedtimeConsistencyMinutes, sd < 30 {
            return "Your schedule is impressively steady. Hold that line."
        }
        return "Nothing stands out tonight. Keep your bedtime steady and check back tomorrow."
    }
}
