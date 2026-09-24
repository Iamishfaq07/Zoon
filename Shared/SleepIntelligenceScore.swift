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
/// | Stage Pattern | 5% | How close tonight's deep/REM *percentages* are to your own (trusted stages only) |
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
    ///
    /// **v4** (this version) changed what two things mean, so it is a new
    /// version rather than a fix to v3:
    /// - Stage Pattern compares stage *composition* (Deep and REM as a share
    ///   of staged sleep), not absolute minutes. v3 compared minutes, so a
    ///   short night with an ordinary split lost points here as well as in
    ///   Duration -- the same shortfall counted twice.
    /// - Stage Pattern runs only on stages `StageTrust` accepts, against a
    ///   history from the same kind of source. v3 let inferred or
    ///   unattributed stages move the headline.
    /// - A severe shortfall caps the headline (`durationCeilings`). v3 could
    ///   call a night 90 minutes short "Excellent" when everything else was
    ///   perfect.
    /// - Continuity no longer treats an inferred time in bed as a measured
    ///   efficiency.
    /// Scores stored under v3 keep `scoringVersion == 3` and are not
    /// rewritten.
    static let currentVersion = 4

    let percent: Int
    let scoringVersion: Int
    let components: [Component]
    let confidence: Confidence
    /// What fraction of the full five-component model actually had enough
    /// data to run tonight, as a percent 0–100.
    let dataCompletenessPercent: Int
    /// Set when a severe shortfall held the headline below what the weighted
    /// sum gave. `nil` when no ceiling applied, and on every score stored
    /// before v4.
    let durationCap: DurationCap?

    /// A transparent limit, not a hidden adjustment: the number it replaced
    /// and the rule that replaced it are both kept, so the UI can say why.
    struct DurationCap: Codable, Hashable, Sendable {
        /// Minutes short of tonight's need.
        let shortfallMinutes: Int
        /// The highest percent a night this short may show.
        let ceiling: Int
        /// What the weighted components summed to before the ceiling.
        let uncappedPercent: Int

        var explanation: String {
            "Capped at \(ceiling) because the night was \(shortfallMinutes)m short of your need. "
                + "The other components summed to \(uncappedPercent)."
        }
    }

    /// The most a night may score for how far short of need it fell.
    ///
    /// An engineering guardrail, stated here rather than tuned silently: with
    /// every other component perfect, v3 scored a 90-minute shortfall 86
    /// ("Excellent") and a 120-minute shortfall 78 ("Good"). Each ceiling
    /// sits one point under a band boundary (`Band.forPercent`), so a night
    /// this short cannot be *labelled* better than the band named here:
    /// 60+ minutes short at most Good, 120+ at most Fair, 180+ Poor.
    static let durationCeilings: [(shortfallMinutes: Double, ceiling: Int)] = [
        (180, 49), (120, 69), (60, 84)
    ]

    /// Trusted, same-source nights a stage composition needs before it is
    /// compared with anything.
    static let minimumStageBaselineNights = 5

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
            // An efficiency is asleep over *time in bed*. When the source gave
            // no time in bed (Apple Watch alone never does) the window was
            // inferred from the sleep itself, and "efficiency" is then just
            // the awake share restated -- WASO counted twice under a name
            // that claims a measurement. So an estimated window scores what
            // was genuinely measured: time awake inside sleep, and how often
            // it broke.
            let estimated = night.timeInBedIsEstimated
            let continuityNormalized = estimated
                ? (wasoScore * Self.estimatedWindowWeights.waso + rateScore * Self.estimatedWindowWeights.rate) / 100
                : (efficiencyScore * 0.50 + wasoScore * 0.30 + rateScore * 0.20) / 100
            let wakes = night.wakeCount == 1 ? "1 awakening" : "\(night.wakeCount) awakenings"
            raw.append((Component(
                label: "Continuity",
                detail: estimated
                    ? "\(Int(waso))m awake within sleep, \(wakes) (time in bed estimated)"
                    : "\(Int(night.sleepEfficiencyPercent))% efficient, \(Int(waso))m awake",
                normalized: continuityNormalized,
                weightUsed: 0,
                expectedNeutral: estimated ? Self.estimatedWindowContinuityNeutral : Self.continuityNeutral
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

        let weighted = Int((components.reduce(0.0) { $0 + $1.normalized * $1.weightUsed } * 100).rounded())
        let uncapped = max(0, min(100, weighted))
        let completeness = Int((totalNominal * 100).rounded())

        let shortfall = max(0, -deltaMinutes)
        var cap: DurationCap?
        if let ceiling = durationCeilings.first(where: { shortfall >= $0.shortfallMinutes })?.ceiling,
           uncapped > ceiling {
            cap = DurationCap(
                shortfallMinutes: Int(shortfall.rounded()),
                ceiling: ceiling,
                uncappedPercent: uncapped
            )
        }

        return SleepIntelligenceScore(
            percent: cap?.ceiling ?? uncapped,
            scoringVersion: currentVersion,
            components: components,
            confidence: confidenceLevel(nightCount: history.count, completeness: completeness),
            dataCompletenessPercent: completeness,
            durationCap: cap
        )
    }

    // MARK: - Component helpers

    /// How close tonight's Deep/REM *composition* is to this person's own.
    ///
    /// Named "Architecture" once, and still scored as distance in either
    /// direction: an unusually deep night moves as far from the pattern as an
    /// unusually light one. That is "distance from my usual stage pattern",
    /// not "stage quality" -- more deep sleep is not better here.
    ///
    /// **v4: composition, not minutes.** v3 z-scored Deep and REM *minutes*,
    /// so a 360-minute night at the usual 18% Deep / 22% REM scored as an
    /// unusual stage pattern against 450-minute history -- a shortfall
    /// Duration had already charged, charged again. This compares each
    /// stage's share of staged sleep, so a night's length cannot move it.
    ///
    /// **v4: trusted stages only.** The night and every baseline night must
    /// pass `StageTrust.supportsStageFigures`, and the baseline comes from the
    /// same kind of source (`stageSourcePriority`): two vendors' classifiers
    /// produce different distributions, and a change of watch is not a change
    /// in someone's sleep. Too little trusted, same-source history and the
    /// component is omitted; completeness and confidence say so.
    ///
    /// Weight stays at 5%.
    private static func stagePatternComponent(
        night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> (normalized: Double, expectedNeutral: Double)? {
        guard let tonight = StageComposition(night) else { return nil }
        let baseline = stageBaseline(for: night, history: history)
        guard baseline.count >= minimumStageBaselineNights else { return nil }

        var deviations: [Double] = []
        if let z = Statistics.robustZ(tonight.deepShare, in: baseline.map(\.deepShare)) {
            deviations.append(abs(z))
        }
        if let z = Statistics.robustZ(tonight.remShare, in: baseline.map(\.remShare)) {
            deviations.append(abs(z))
        }
        guard !deviations.isEmpty else { return nil }
        let avgDeviation = deviations.reduce(0, +) / Double(deviations.count)
        let anchors: [(Double, Double)] = [(0, 100), (1, 90), (2, 70), (3, 50), (4, 30)]
        return (
            interpolate(avgDeviation, anchors: anchors) / 100,
            // Zero distance from your own median is the best case, not the
            // typical one -- half of all nights sit further out than this.
            interpolate(expectedAbsoluteZ, anchors: anchors) / 100
        )
    }

    /// Deep and REM as shares of *staged* sleep (core + deep + REM).
    ///
    /// Staged sleep, not all sleep: minutes a source marked only "asleep"
    /// carry no stage, and counting them in the denominator would make a
    /// partly staged night look light on every stage at once.
    struct StageComposition: Hashable, Sendable {
        let deepShare: Double
        let remShare: Double

        /// A trusted night with enough staged sleep to have a composition.
        init?(_ night: SleepNightFeatures) {
            guard night.stageTrust.supportsStageFigures else { return nil }
            let staged = night.coreMinutes + night.deepMinutes + night.remMinutes
            guard staged >= 60 else { return nil }
            deepShare = night.deepMinutes / staged
            remShare = night.remMinutes / staged
        }
    }

    /// The last 30 trusted nights from the same kind of source as `night`.
    static func stageBaseline(
        for night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> [StageComposition] {
        history.suffix(30)
            .filter { $0.stageSourcePriority == night.stageSourcePriority }
            .compactMap(StageComposition.init)
    }

    /// "Deep 18% (usually 15-21%), REM 22%" -- tonight's composition, and
    /// the range it is judged against.
    private static func stagePatternDetail(
        night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> String {
        guard let tonight = StageComposition(night) else { return "Stages not scored" }
        func pct(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }
        let deepHistory = stageBaseline(for: night, history: history).map(\.deepShare)
        guard let low = Statistics.percentile(deepHistory, 25),
              let high = Statistics.percentile(deepHistory, 75) else {
            return "Deep \(pct(tonight.deepShare)), REM \(pct(tonight.remShare))"
        }
        return "Deep \(pct(tonight.deepShare)) (usually \(pct(low))-\(pct(high))), REM \(pct(tonight.remShare))"
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

    /// Continuity's subweights when the time in bed was estimated: WASO and
    /// awakening rate carry efficiency's share in the ratio they already
    /// had (30:20).
    static let estimatedWindowWeights = (waso: 0.60, rate: 0.40)

    /// The neutral for an estimated window, through the same two curves at
    /// the same ordinary-night inputs as `continuityNeutral`.
    static var estimatedWindowContinuityNeutral: Double {
        let waso = interpolate(
            5,
            anchors: [(0, 100), (3, 100), (5, 90), (10, 70), (15, 45), (25, 10), (40, 0)]
        )
        let rate = interpolate(
            0.6,
            anchors: [(0, 100), (0.25, 100), (0.5, 90), (1.0, 70), (1.5, 45), (2.5, 10), (4, 0)]
        )
        return (waso * estimatedWindowWeights.waso + rate * estimatedWindowWeights.rate) / 100
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

    /// Components the model could not run tonight, in table order.
    ///
    /// Read off `nominalWeights` rather than a second list of names, so a
    /// sixth component cannot be added without every surface that explains
    /// an incomplete score knowing about it.
    var missingComponentLabels: [String] {
        SleepIntelligenceScore.nominalWeights
            .map(\.component)
            .filter { label in !components.contains { $0.label == label } }
    }

    /// Why the score carries the confidence it does, as a sentence -- which
    /// part of the model could not run, rather than a restatement of the
    /// band. `nil` when the whole model ran, because there is then nothing
    /// to caveat and a reassuring sentence is still a sentence to read.
    ///
    /// Lives here rather than in the card because the score is what knows
    /// which components ran; a view deriving it a second time is a second
    /// thing to keep in step.
    var confidenceReason: String? {
        guard dataCompletenessPercent < 100 else { return nil }
        let missing = missingComponentLabels
        guard !missing.isEmpty else {
            // Completeness is below 100 with every component present: a
            // component ran on partial inputs rather than being dropped.
            return "\(dataCompletenessPercent)% of the model ran tonight."
        }
        let named = missing.count == 1
            ? missing[0]
            : missing.dropLast().joined(separator: ", ") + " and " + missing[missing.count - 1]
        let pronoun = missing.count == 1 ? "it" : "them"
        return "Scored without \(named) — there wasn't enough data for \(pronoun) tonight."
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
