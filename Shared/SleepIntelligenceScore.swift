import Foundation

/// A proprietary, fully explainable nightly score — the thing Apple's Sleep
/// Score, Oura's Sleep Score, and Whoop's Sleep Performance all are, but with
/// every point traceable to a cause instead of handed down from a black box.
///
/// Five sleep-period components, each scored 0–1 against **this person's own recent
/// history** using robust statistics (median/MAD, not mean/SD — see
/// `Statistics`), then weighted and summed:
///
/// | Component | Weight | What it measures |
/// |---|---|---|
/// | Duration | 40% | Tonight's sleep vs. tonight's estimated need |
/// | Continuity | 30% | Efficiency, WASO, and awakening rate |
/// | Regularity | 20% | Bedtime/wake consistency (reuses `SleepRegularity`) |
/// | Timing | 5% | Tonight's midpoint vs. your habitual `BodyClock` |
/// | Stage Pattern | 5% | How close tonight's deep/REM split is to your own |
///
/// A missing component (no HRV sensor, no `BodyClock` yet, a source with no
/// stage data) is excluded and the remaining weights renormalize to 100 —
/// the score never silently penalizes someone for data their device or
/// history doesn't have yet. `dataCompletenessPercent` reports how much of
/// the full model actually ran.
struct SleepIntelligenceScore: Codable, Hashable, Sendable {

    /// Bumped whenever the anchor tables or weights change, so a score
    /// computed under an old version stays interpretable as such rather than
    /// silently meaning something different after an app update.
    static let currentVersion = 3

    let percent: Int
    let scoringVersion: Int
    let components: [Component]
    let confidence: Confidence
    /// What fraction of the full five-component model actually had enough
    /// data to run tonight, as a percent 0–100.
    let dataCompletenessPercent: Int

    struct Component: Codable, Hashable, Sendable, Identifiable {
        let label: String
        let detail: String
        /// 0...1, this component alone.
        let normalized: Double
        /// The weight actually used tonight, after renormalizing around any
        /// missing components -- not the nominal table weight above.
        let weightUsed: Double

        /// The normalized value a *typical* night produces for this
        /// component -- its own curve evaluated at its own expected input,
        /// not 0.5.
        ///
        /// This was 0.5 for every component, and 0.5 is not the middle of
        /// anything here. `stagePatternComponent` scores a night at a typical
        /// distance from its median stage split near 0.93 because it measures
        /// distance from the person's pattern. Measured against 0.5, that
        /// ordinary stage pattern would incorrectly read as helping.
        ///
        /// Each component derives this from the same anchor table it scores
        /// with, at a documented expected input, so a curve and its neutral
        /// cannot drift apart.
        let expectedNeutral: Double

        var id: String { label }

        /// Signed points this component contributed relative to a typical
        /// night -- the number the "why" UI sums to.
        var pointContribution: Double {
            (normalized - expectedNeutral) * weightUsed * 100
        }

        /// Whether this component helped, was ordinary, or held the night
        /// back. The three words the UI should use, decided here so every
        /// surface says the same one.
        var role: Role {
            let delta = normalized - expectedNeutral
            if delta > SleepIntelligenceScore.typicalBand { return .helpful }
            if delta < -SleepIntelligenceScore.typicalBand { return .limiting }
            return .typical
        }
    }

    /// What a component did to the night.
    enum Role: String, Codable, Hashable, Sendable {
        /// Better than this person's own expected state.
        case helpful
        /// Within it. Most components on most nights.
        case typical
        /// Below it.
        case limiting

        var label: String {
            switch self {
            case .helpful: "Helpful"
            case .typical: "Typical"
            case .limiting: "Limiting"
            }
        }
    }

    /// How far from `expectedNeutral` still counts as an ordinary night.
    ///
    /// Without a band, every component is helpful or limiting and none is
    /// ever typical, which is the same failure as a 0.5 neutral wearing
    /// different clothes: it manufactures a story out of noise.
    static let typicalBand = 0.05

    /// The expected size of a robust z-score, in the units `Statistics.robustZ`
    /// returns.
    ///
    /// Components that score `abs(z)` are measuring distance from your own
    /// median, and a typical night is not at zero distance -- half of all
    /// nights are further away than the median absolute deviation. For a
    /// normal distribution that is 0.6745 standard deviations, which is the
    /// same constant `robustZ` scales the MAD by, so this is the value a
    /// median night actually produces rather than an assumption about one.
    static let expectedAbsoluteZ = 0.6745

    /// See `MetricConfidence`.
    typealias Confidence = MetricConfidence

    /// Nominal weights. `compute` renormalizes among whatever subset is
    /// actually available for a given night. Exposed (not just `private`) so
    /// the algorithm-transparency screen can show the real table rather than
    /// a hand-copied duplicate that could drift out of sync with it.
    static let nominalWeights: [(component: String, weight: Double)] = [
        ("Duration", 0.40), ("Continuity", 0.30), ("Regularity", 0.20),
        ("Timing", 0.05), ("Stage Pattern", 0.05)
    ]
    private static let nominalWeightsByName = Dictionary(
        uniqueKeysWithValues: nominalWeights.map { ($0.component, $0.weight) }
    )

    // MARK: - Compute

    struct Inputs {
        let night: SleepNightFeatures
        /// Prior nights, oldest first, excluding tonight. Used as the robust
        /// baseline for every history-relative component.
        let history: [SleepNightFeatures]
        let sleepNeedMinutes: Double
        /// Already-computed `SleepRegularity.index` (0–100, see that type for
        /// what it does and doesn't measure) -- reused rather than
        /// reimplementing the same circular bedtime/wake statistics a second
        /// time.
        let regularityIndex: Double?
        /// Habitual sleep midpoint from `BodyClock`, hours from midnight,
        /// evening negative. `nil` until there's enough history for one.
        let habitualMidpointHours: Double?
    }

    static func compute(_ inputs: Inputs) -> SleepIntelligenceScore {
        let night = inputs.night
        let history = inputs.history

        var raw: [(component: Component, nominalWeight: Double)] = []

        // --- Duration ------------------------------------------------------
        let deltaMinutes = night.timeAsleepMinutes - inputs.sleepNeedMinutes
        let durationNormalized = durationScore(deltaMinutes: deltaMinutes) / 100
        raw.append((Component(
            label: "Duration",
            detail: signedMinutes(deltaMinutes) + " vs need",
            normalized: durationNormalized,
            weightUsed: 0,
            // Meeting your need exactly. The curve is flat at 100 from 0 to
            // +60 minutes, so duration can be typical or limiting and never
            // helpful -- which is what the curve has always said. Sleeping
            // past your need does not buy anything back.
            expectedNeutral: durationScore(deltaMinutes: 0) / 100
        ), nominalWeightsByName["Duration"] ?? 0))

        // --- Continuity ------------------------------------------------------
        if night.timeAsleepMinutes > 0 {
            let waso = wasoMinutes(night)
            let hours = max(night.timeAsleepMinutes / 60, 0.1)
            let awakeningRate = Double(night.wakeCount) / hours
            let opportunityMinutes = max(night.timeInBedMinutes, night.timeAsleepMinutes, 1)

            let efficiencyScore = interpolate(
                night.sleepEfficiencyPercent,
                anchors: [(60, 0), (70, 20), (80, 55), (85, 75), (90, 90), (95, 100), (100, 100)]
            )
            let wasoScore = interpolate(
                (waso / opportunityMinutes) * 100,
                anchors: [(0, 100), (3, 100), (5, 90), (10, 70), (15, 45), (25, 10), (40, 0)]
            )
            let rateScore = interpolate(
                awakeningRate,
                anchors: [(0, 100), (0.25, 100), (0.5, 90), (1.0, 70), (1.5, 45), (2.5, 10), (4, 0)]
            )
            let continuityNormalized = (efficiencyScore * 0.50 + wasoScore * 0.30 + rateScore * 0.20) / 100
            raw.append((Component(
                label: "Continuity",
                detail: "\(Int(night.sleepEfficiencyPercent))% efficient, \(Int(waso))m awake",
                normalized: continuityNormalized,
                weightUsed: 0,
                expectedNeutral: Self.continuityNeutral
            ), nominalWeightsByName["Continuity"] ?? 0))
        }

        // --- Regularity ------------------------------------------------------
        if let index = inputs.regularityIndex {
            raw.append((Component(
                label: "Regularity",
                detail: "\(Int(index.rounded())) timing score",
                normalized: index / 100,
                weightUsed: 0,
                // SRI is already a 0-100 scale where 100 means an identical
                // schedule every day, which nobody has. This is the index a
                // reasonably regular sleeper runs at -- see
                // `typicalRegularityIndex`.
                expectedNeutral: Self.typicalRegularityIndex / 100
            ), nominalWeightsByName["Regularity"] ?? 0))
        }

        // --- Timing ----------------------------------------------------------
        //
        // "Circadian" until now. The V9 audit's own list of the six
        // components calls this one Timing, and it is right to: the number
        // measures how far last night's midpoint sat from where this person
        // usually sleeps, which is a thing anyone can picture. "Circadian" is
        // the word for the system underneath, kept as the technical alias in
        // `SleepVocabulary.circadianAlignment`.
        //
        // A label change only -- the score is bit-for-bit identical, so
        // `currentVersion` does not move. Versions track what the number
        // means, not what it is called.
        if let habitual = inputs.habitualMidpointHours {
            let tonightMidpoint = midpointHours(night)
            // Both values are hours on a 24-hour clock, but they fold at
            // different points: `midpointHours` folds the onset at 18:00 and
            // adds half the span unfolded, `BodyClock.midpoint` folds at
            // 12:00. A 20:30 midpoint against a 20:30 habit is +20.5 vs
            // -3.5, which a plain subtraction reads as a full day of drift.
            // Measure the drift on the circle instead; the signed wrap is
            // only for the label.
            let rawDeltaMinutes = (tonightMidpoint - habitual) * 60
            let signedDeltaMinutes = rawDeltaMinutes - (rawDeltaMinutes / 1440).rounded() * 1440
            let diffMinutes = Statistics.circularDistance(tonightMidpoint * 60, habitual * 60)
            let circadianNormalized = interpolate(
                diffMinutes,
                anchors: [(0, 100), (15, 100), (30, 90), (60, 75), (90, 55), (120, 35), (180, 10), (240, 0)]
            ) / 100
            raw.append((Component(
                label: "Timing",
                detail: String(format: "%+.0fm vs usual timing", signedDeltaMinutes),
                normalized: circadianNormalized,
                weightUsed: 0,
                expectedNeutral: Self.circadianNeutral
            ), nominalWeightsByName["Timing"] ?? 0))
        }

        // --- Stage Pattern -----------------------------------------------------
        if let stagePattern = stagePatternComponent(night: night, history: history) {
            raw.append((Component(
                label: "Stage Pattern",
                detail: stagePatternDetail(night: night, history: history),
                normalized: stagePattern.normalized,
                weightUsed: 0,
                expectedNeutral: stagePattern.expectedNeutral
            ), nominalWeightsByName["Stage Pattern"] ?? 0))
        }

        // --- Renormalize -----------------------------------------------------
        let totalNominal = raw.reduce(0) { $0 + $1.nominalWeight }
        let components: [Component] = totalNominal > 0
            ? raw.map { entry in
                Component(
                    label: entry.component.label,
                    detail: entry.component.detail,
                    normalized: entry.component.normalized,
                    weightUsed: entry.nominalWeight / totalNominal,
                    expectedNeutral: entry.component.expectedNeutral
                )
            }
            : []

        let percent = Int((components.reduce(0.0) { $0 + $1.normalized * $1.weightUsed } * 100).rounded())
        let completeness = Int((totalNominal * 100).rounded())

        return SleepIntelligenceScore(
            percent: max(0, min(100, percent)),
            scoringVersion: currentVersion,
            components: components,
            confidence: confidenceLevel(nightCount: history.count, completeness: completeness),
            dataCompletenessPercent: completeness
        )
    }

    // MARK: - Component helpers

    /// How close tonight's deep/REM split is to this person's own.
    ///
    /// Named "Architecture" until now, and shown to people under that word,
    /// which was wrong in a way the maths makes unavoidable: this scores
    /// `abs(z)`, so a night with unusually *high* deep sleep is marked down
    /// exactly as far as one with unusually low deep sleep. Under the label
    /// "Architecture Quality" that reads as a bug -- more deep sleep is
    /// supposed to be good, and a user seeing a great deep-sleep night
    /// docked for it would be right to distrust the whole score.
    ///
    /// The measurement is not the problem. Distance from your own pattern is
    /// a real and useful thing to track, and an abrupt change in either
    /// direction is worth noticing. Only the name promised something else.
    /// So the maths is unchanged and the concept is now called what it is.
    ///
    /// Weights stay at 5%: a single unusual staged night is not an
    /// architecture problem, and wearable stage estimates do not deserve to
    /// look clinically precise.
    private static func stagePatternComponent(
        night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> (normalized: Double, expectedNeutral: Double)? {
        guard night.hasStageBreakdown else { return nil }
        let history30 = Array(history.suffix(30)).filter(\.hasStageBreakdown)
        guard history30.count >= 5 else { return nil }

        var deviations: [Double] = []
        if let z = Statistics.robustZ(night.deepMinutes, in: history30.map(\.deepMinutes)) {
            deviations.append(abs(z))
        }
        if let z = Statistics.robustZ(night.remMinutes, in: history30.map(\.remMinutes)) {
            deviations.append(abs(z))
        }
        guard !deviations.isEmpty else { return nil }
        let avgDeviation = deviations.reduce(0, +) / Double(deviations.count)
        let anchors: [(Double, Double)] = [(0, 100), (1, 90), (2, 70), (3, 50), (4, 30)]
        return (
            interpolate(avgDeviation, anchors: anchors) / 100,
            // Zero distance from your own median is the best case, not the
            // typical one -- half of all nights sit further out than this.
            // Scored against 0.5 the typical night looked like a night your
            // sleep stages actively helped.
            interpolate(expectedAbsoluteZ, anchors: anchors) / 100
        )
    }

    /// "Deep 1h14 (usually 1h02-1h25)" -- the number, and the range it is
    /// being judged against.
    ///
    /// The old detail read "81m deep, 99m REM", which states two numbers and
    /// leaves the reader to guess whether either is unusual for them. The
    /// range is what makes the component legible, and it is the same history
    /// the score itself is computed from.
    private static func stagePatternDetail(
        night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> String {
        let deep = SleepNightFeatures.formatMinutes(night.deepMinutes)
        let history30 = Array(history.suffix(30)).filter(\.hasStageBreakdown).map(\.deepMinutes)
        guard let low = Statistics.percentile(history30, 25),
              let high = Statistics.percentile(history30, 75) else {
            return "Deep \(deep)"
        }
        return "Deep \(deep) (usually \(SleepNightFeatures.formatMinutes(low))-\(SleepNightFeatures.formatMinutes(high)))"
    }

    // MARK: - Expected states
    //
    // Each of these is the input a typical night presents to the component's
    // own curve. They live here rather than inline so the reasoning is in one
    // place and so a test can assert an ordinary night scores as typical
    // across the board.

    /// A reasonably regular sleeper's SRI.
    ///
    /// Not 100: an SRI of 100 means an identical schedule every single day,
    /// which nobody has and nothing should be graded against. Published SRI
    /// distributions put a typical adult in the mid-seventies, which is also
    /// where this app's own `SleepRegularity` lands for consistent-looking
    /// history.
    static let typicalRegularityIndex = 75.0

    /// Minutes a typical night's midpoint drifts from the habitual one.
    ///
    /// Half an hour either way is an ordinary week: weekends move, and the
    /// `Circadian` curve is already flat out to 15 minutes precisely because
    /// small drift is not a finding.
    static let typicalMidpointDriftMinutes = 30.0

    static var circadianNeutral: Double {
        interpolate(
            typicalMidpointDriftMinutes,
            anchors: [(0, 100), (15, 100), (30, 90), (60, 75), (90, 55), (120, 35), (180, 10), (240, 0)]
        ) / 100
    }

    /// What the continuity curves give for an ordinary night: 88% efficient,
    /// 5% of the opportunity spent awake after onset, and a little over one
    /// awakening every two hours.
    ///
    /// Derived through the same three curves the component scores with,
    /// rather than written down as a number, so moving an anchor moves the
    /// neutral with it instead of silently regrading every night.
    static var continuityNeutral: Double {
        let efficiency = interpolate(
            88,
            anchors: [(60, 0), (70, 20), (80, 55), (85, 75), (90, 90), (95, 100), (100, 100)]
        )
        let waso = interpolate(
            5,
            anchors: [(0, 100), (3, 100), (5, 90), (10, 70), (15, 45), (25, 10), (40, 0)]
        )
        let rate = interpolate(
            0.6,
            anchors: [(0, 100), (0.25, 100), (0.5, 90), (1.0, 70), (1.5, 45), (2.5, 10), (4, 0)]
        )
        return (efficiency * 0.50 + waso * 0.30 + rate * 0.20) / 100
    }

    private static func confidenceLevel(nightCount: Int, completeness: Int) -> Confidence {
        // Duration (0.40) is always present, so a 40 threshold could never
        // fail. 70 is Duration plus Continuity: a night that produced
        // nothing but a sleep-minutes figure is not a night this score can
        // say anything about.
        guard completeness >= 70 else { return .insufficient }
        switch nightCount {
        case ..<14: return .low
        case 14..<30: return .moderate
        default: return .high
        }
    }

    // MARK: - Small helpers

    private static func wasoMinutes(_ night: SleepNightFeatures) -> Double {
        // True WASO -- awake time strictly between sleep onset and the final
        // sustained sleep segment -- when staged data exists; otherwise
        // `awakeMinutes` (the whole session's awake time) is the closest
        // available proxy, since non-staged sources give nothing finer.
        let asleep = night.stageSegments.filter { SleepStage.asleepStages.contains($0.stage) }
        guard let firstAsleep = asleep.map(\.start).min(),
              let lastAsleep = asleep.map(\.end).max() else {
            return night.awakeMinutes
        }
        return night.stageSegments
            .filter { $0.stage == .awake && $0.start >= firstAsleep && $0.end <= lastAsleep }
            .reduce(0) { $0 + $1.minutes }
    }

    private static func midpointHours(_ night: SleepNightFeatures) -> Double {
        var calendar = Calendar.current
        calendar.timeZone = night.timeZone
        let onset = Statistics.circularMinutesFromMidnight(night.bedtime, calendar: calendar) / 60
        let span = night.wakeTime.timeIntervalSince(night.bedtime) / 3600
        return onset + span / 2
    }

    private static func durationScore(deltaMinutes: Double) -> Double {
        if deltaMinutes >= 0 {
            return interpolate(deltaMinutes, anchors: [
                (0, 100), (60, 100), (90, 95), (120, 85), (180, 65), (240, 40)
            ])
        }
        return interpolate(-deltaMinutes, anchors: [
            (0, 100), (30, 92), (60, 80), (90, 65), (120, 45), (180, 10), (240, 0)
        ])
    }

    private static func interpolate(_ x: Double, anchors: [(Double, Double)]) -> Double {
        Statistics.interpolate(x, anchors: anchors.map { (x: $0.0, y: $0.1) })
    }

    private static func signedMinutes(_ minutes: Double) -> String {
        let sign = minutes >= 0 ? "+" : "−"
        return "\(sign)\(Int(abs(minutes)))m"
    }
}

// MARK: - Presentation

extension SleepIntelligenceScore {

    enum Band: String, Sendable {
        case poor, fair, good, excellent

        var label: String {
            switch self {
            case .poor: "Poor"
            case .fair: "Fair"
            case .good: "Good"
            case .excellent: "Excellent"
            }
        }

        /// Callable from a bare `Int`, for the same reason
        /// `SleepScore.Band.forValue` is: the widget and watch targets hold a
        /// `SleepSnapshot`, not a full score, and a surface that re-derives
        /// these cutoffs is how two tables drift apart while both look right.
        ///
        /// The thresholds are currently identical to `SleepScore.Band`'s.
        /// That is a coincidence of two independent tables, not a shared
        /// definition -- `SleepIntelligenceBandTests` pins the agreement so a
        /// change to either one is a failing test rather than a widget whose
        /// colour stops matching its label.
        static func forPercent(_ percent: Int) -> Band {
            switch percent {
            case ..<50: .poor
            case 50..<70: .fair
            case 70..<85: .good
            default: .excellent
            }
        }
    }

    var band: Band { Band.forPercent(percent) }

    /// Components that helped, strongest first.
    var positiveContributors: [Component] {
        components.filter { $0.role == .helpful }
            .sorted { $0.pointContribution > $1.pointContribution }
    }

    /// Components that cost points, largest cost first.
    var negativeContributors: [Component] {
        components.filter { $0.role == .limiting }
            .sorted { $0.pointContribution < $1.pointContribution }
    }

    /// Neither helped nor held the night back. Most components, most nights.
    ///
    /// Split out because it used to be invisible: the two lists above
    /// filtered on a +/-0.5 *point* threshold of their own, unrelated to what
    /// counts as an ordinary night, so a component could be absent from both
    /// lists for one reason and graded `typical` for another. They now
    /// partition `components` exactly.
    var typicalContributors: [Component] {
        components.filter { $0.role == .typical }
    }
}
