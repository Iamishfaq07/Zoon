import Foundation

/// A proprietary, fully explainable nightly score — the thing Apple's Sleep
/// Score, Oura's Sleep Score, and Whoop's Sleep Performance all are, but with
/// every point traceable to a cause instead of handed down from a black box.
///
/// Seven components, each scored 0–1 against **this person's own recent
/// history** using robust statistics (median/MAD, not mean/SD — see
/// `Statistics`), then weighted and summed:
///
/// | Component | Weight | What it measures |
/// |---|---|---|
/// | Duration | 25% | Tonight's sleep vs. tonight's estimated need |
/// | Continuity | 20% | Efficiency, WASO, and awakening rate |
/// | Regularity | 15% | Bedtime/wake consistency (reuses `SleepRegularity`) |
/// | Recovery | 15% | HRV, resting HR, and temperature vs. baseline |
/// | Circadian | 10% | Tonight's midpoint vs. your habitual `BodyClock` |
/// | Breathing | 10% | Respiratory rate deviation + disturbances |
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
    static let currentVersion = 2

    let percent: Int
    let scoringVersion: Int
    let components: [Component]
    let confidence: Confidence
    /// What fraction of the full seven-component model actually had enough
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
        /// anything here. `recoveryComponent` scores an HRV exactly at your
        /// own median as 0.65, because HRV has more room to fall than to
        /// rise; `stagePatternComponent` scores a night at your own median
        /// stage split as 0.93, because it measures distance from your
        /// pattern and zero distance is the best possible. Measured against
        /// 0.5, both of those read as *helping* the score -- so a perfectly
        /// ordinary night was reported as a night where your HRV and your
        /// sleep stages were doing you favours.
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
        ("Duration", 0.25), ("Continuity", 0.20), ("Regularity", 0.15),
        ("Recovery", 0.15), ("Circadian", 0.10), ("Breathing", 0.10), ("Stage Pattern", 0.05)
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
        ), nominalWeightsByName["Duration"]!))

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
            ), nominalWeightsByName["Continuity"]!))
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
            ), nominalWeightsByName["Regularity"]!))
        }

        // --- Recovery (HRV, resting HR, temperature) -----------------------
        if let recovery = recoveryComponent(night: night, history: history) {
            raw.append((Component(
                label: "Recovery",
                detail: recoveryDetail(night: night, history: history),
                normalized: recovery.normalized,
                weightUsed: 0,
                expectedNeutral: recovery.expectedNeutral
            ), nominalWeightsByName["Recovery"]!))
        }

        // --- Circadian -------------------------------------------------------
        if let habitual = inputs.habitualMidpointHours {
            let tonightMidpoint = midpointHours(night)
            let diffMinutes = abs(tonightMidpoint - habitual) * 60
            let circadianNormalized = interpolate(
                diffMinutes,
                anchors: [(0, 100), (15, 100), (30, 90), (60, 75), (90, 55), (120, 35), (180, 10), (240, 0)]
            ) / 100
            raw.append((Component(
                label: "Circadian",
                detail: String(format: "%+.0fm vs usual timing", (tonightMidpoint - habitual) * 60),
                normalized: circadianNormalized,
                weightUsed: 0,
                expectedNeutral: Self.circadianNeutral
            ), nominalWeightsByName["Circadian"]!))
        }

        // --- Breathing -------------------------------------------------------
        if let breathing = breathingComponent(night: night, history: history) {
            raw.append((Component(
                label: "Breathing",
                detail: breathingDetail(night: night),
                normalized: breathing.normalized,
                weightUsed: 0,
                expectedNeutral: breathing.expectedNeutral
            ), nominalWeightsByName["Breathing"]!))
        }

        // --- Stage Pattern -----------------------------------------------------
        if let stagePattern = stagePatternComponent(night: night, history: history) {
            raw.append((Component(
                label: "Stage Pattern",
                detail: stagePatternDetail(night: night, history: history),
                normalized: stagePattern.normalized,
                weightUsed: 0,
                expectedNeutral: stagePattern.expectedNeutral
            ), nominalWeightsByName["Stage Pattern"]!))
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

    private static func recoveryComponent(
        night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> (normalized: Double, expectedNeutral: Double)? {
        var scores: [(value: Double, neutral: Double, weight: Double)] = []

        if let hrv = night.avgHRV {
            let history30 = Array(history.suffix(30)).compactMap(\.avgHRV)
            if let z = Statistics.robustZ(hrv, in: history30) {
                // HRV: higher than usual is good, so direction is not symmetric.
                let anchors: [(Double, Double)] = [
                    (-3, 5), (-2, 20), (-1, 45), (0, 65), (1, 90), (2, 100), (3, 100)
                ]
                // An HRV sitting exactly on your own median scores 65, not
                // 100 -- the curve is asymmetric because HRV has further to
                // fall than to rise. Graded against 0.5 that read as a night
                // your HRV helped. It is the definition of an ordinary one.
                scores.append((interpolate(z, anchors: anchors), interpolate(0, anchors: anchors), 0.5))
            }
        }
        if let rhr = night.restingHeartRate {
            let history30 = Array(history.suffix(30)).compactMap(\.restingHeartRate)
            if let z = Statistics.robustZ(rhr, in: history30) {
                // Elevated resting HR relative to baseline is unfavorable.
                let anchors: [(Double, Double)] = [
                    (-2, 100), (-1, 90), (0, 65), (1, 40), (2, 15), (3, 5)
                ]
                scores.append((interpolate(z, anchors: anchors), interpolate(0, anchors: anchors), 0.3))
            }
        }
        if let temp = night.wristTempDeltaC {
            let history30 = Array(history.suffix(30)).compactMap(\.wristTempDeltaC)
            if let z = Statistics.robustZ(temp, in: history30) {
                // Either direction away from baseline is unusual for temperature.
                let anchors: [(Double, Double)] = [
                    (0, 100), (1, 75), (1.5, 50), (2, 25), (3, 5)
                ]
                // Distance from baseline, so the expected input is the
                // expected distance -- half your nights are further from
                // your own median than this -- not zero.
                scores.append((
                    interpolate(abs(z), anchors: anchors),
                    interpolate(expectedAbsoluteZ, anchors: anchors),
                    0.2
                ))
            }
        }

        guard !scores.isEmpty else { return nil }
        return blend(scores)
    }

    /// Weighted mean of whichever sub-signals were available, carrying each
    /// one's own neutral through the same renormalization as its value.
    ///
    /// The neutral has to be blended with the value, not chosen for the
    /// component as a whole: a night with HRV and no temperature reading is
    /// scored against a different mix than one with both, so its expected
    /// state is a different number too. Hard-coding one neutral per component
    /// would quietly mis-grade every night where a sensor was missing.
    private static func blend(
        _ scores: [(value: Double, neutral: Double, weight: Double)]
    ) -> (normalized: Double, expectedNeutral: Double) {
        let totalWeight = scores.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return (0, 0) }
        return (
            scores.reduce(0) { $0 + $1.value / 100 * $1.weight } / totalWeight,
            scores.reduce(0) { $0 + $1.neutral / 100 * $1.weight } / totalWeight
        )
    }

    private static func recoveryDetail(night: SleepNightFeatures, history: [SleepNightFeatures]) -> String {
        if let hrv = night.avgHRV { return "HRV \(Int(hrv)) ms" }
        if let rhr = night.restingHeartRate { return "Resting HR \(Int(rhr)) bpm" }
        return "—"
    }

    /// Breathing, graded against Apple's own call and against this person's
    /// own nights -- never against an invented severity scale.
    ///
    /// The disturbance half used to interpolate an absolute table:
    ///
    ///     0% -> 100, 5% -> 85, 15% -> 55, 30% -> 25, 50% -> 5
    ///
    /// Those five points are a clinical-looking severity curve that nothing
    /// in this app, or in Apple's documentation, supports. They give the
    /// impression that Zoon knows what a 15% disturbance rate means for a
    /// person's health. It does not, and `BreathingHealth`'s own doc comment
    /// says as much about the same measurement.
    ///
    /// What does exist is `HKAppleSleepingBreathingDisturbancesClassification`,
    /// which Apple computes and `FeatureExtractor` already stores on every
    /// night. It has two states and Apple stands behind both. Where it is
    /// present it is used and nothing is invented on top of it. Where it is
    /// absent -- older hardware, the feature switched off -- the fallback is
    /// this person's own distribution, one-sided: a night with unusually few
    /// disturbances for them is not a bonus, it is a normal night.
    private static func breathingComponent(
        night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> (normalized: Double, expectedNeutral: Double)? {
        var scores: [(value: Double, neutral: Double, weight: Double)] = []

        if let rate = night.avgRespiratoryRate {
            let history30 = Array(history.suffix(30)).compactMap(\.avgRespiratoryRate)
            if let z = Statistics.robustZ(rate, in: history30) {
                let anchors: [(Double, Double)] = [
                    (0, 100), (1, 80), (1.5, 55), (2, 30), (3, 5)
                ]
                scores.append((
                    interpolate(abs(z), anchors: anchors),
                    interpolate(expectedAbsoluteZ, anchors: anchors),
                    0.6
                ))
            }
        }

        if let classification = night.breathingDisturbancesClassification {
            // Two states, both Apple's. `notElevated` is the expected state
            // and carries no penalty; `elevated` is Apple's own flag that
            // this is worth a person's attention, and it costs the component
            // real ground without pretending to grade how severe it is.
            let value = classification == .elevated
                ? elevatedBreathingScore
                : notElevatedBreathingScore
            scores.append((value, notElevatedBreathingScore, 0.4))
        } else if let disturbances = night.breathingDisturbances {
            let history30 = Array(history.suffix(30)).compactMap(\.breathingDisturbances)
            if let z = Statistics.robustZ(disturbances, in: history30) {
                let anchors: [(Double, Double)] = [
                    (0, 100), (1, 85), (2, 60), (3, 35)
                ]
                // One-sided on purpose: only *more* disturbance than usual
                // counts against the night. Fewer than usual is a normal
                // night, not an achievement, and scoring it as one would
                // reward noise.
                scores.append((
                    interpolate(max(0, z), anchors: anchors),
                    interpolate(0, anchors: anchors),
                    0.4
                ))
            }
        }

        guard !scores.isEmpty else { return nil }
        return blend(scores)
    }

    /// The two values the Apple classification maps to.
    ///
    /// Named constants rather than literals because they are a judgement --
    /// the classification says elevated or not, it does not say by how much,
    /// and any number here is Zoon's choice about how much weight to give
    /// Apple's flag. `notElevated` is the neutral, so an unflagged night is
    /// reported as ordinary rather than as a night your breathing helped.
    /// Together they move at most 4 points of the whole score.
    static let notElevatedBreathingScore = 100.0
    static let elevatedBreathingScore = 30.0

    private static func breathingDetail(night: SleepNightFeatures) -> String {
        if night.breathingDisturbancesClassification == .elevated {
            return "Elevated disturbances (Apple)"
        }
        if let rate = night.avgRespiratoryRate {
            return String(format: "%.1f br/min", rate)
        }
        return "—"
    }

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
        guard completeness >= 40 else { return .insufficient }
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
