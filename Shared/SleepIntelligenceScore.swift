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
/// | Architecture | 5% | Deep/REM minutes vs. your own history |
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
    static let currentVersion = 1

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
        var id: String { label }

        /// Signed points this component contributed relative to a neutral
        /// (0.5-normalized) baseline -- the number the "why" UI sums to.
        var pointContribution: Double {
            (normalized - 0.5) * weightUsed * 100
        }
    }

    enum Confidence: String, Codable, Sendable {
        case insufficient, low, moderate, high

        var label: String {
            switch self {
            case .insufficient: "Insufficient data"
            case .low: "Low confidence"
            case .moderate: "Moderate confidence"
            case .high: "High confidence"
            }
        }
    }

    /// Nominal weights. `compute` renormalizes among whatever subset is
    /// actually available for a given night. Exposed (not just `private`) so
    /// the algorithm-transparency screen can show the real table rather than
    /// a hand-copied duplicate that could drift out of sync with it.
    static let nominalWeights: [(component: String, weight: Double)] = [
        ("Duration", 0.25), ("Continuity", 0.20), ("Regularity", 0.15),
        ("Recovery", 0.15), ("Circadian", 0.10), ("Breathing", 0.10), ("Architecture", 0.05)
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
        /// Already-computed Sleep Regularity Index (0–100) -- reused rather
        /// than reimplementing the same circular bedtime/wake statistics a
        /// second time.
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
            weightUsed: 0
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
                weightUsed: 0
            ), nominalWeightsByName["Continuity"]!))
        }

        // --- Regularity ------------------------------------------------------
        if let index = inputs.regularityIndex {
            raw.append((Component(
                label: "Regularity",
                detail: "\(Int(index.rounded())) SRI",
                normalized: index / 100,
                weightUsed: 0
            ), nominalWeightsByName["Regularity"]!))
        }

        // --- Recovery (HRV, resting HR, temperature) -----------------------
        if let recoveryNormalized = recoveryComponent(night: night, history: history) {
            raw.append((Component(
                label: "Recovery",
                detail: recoveryDetail(night: night, history: history),
                normalized: recoveryNormalized,
                weightUsed: 0
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
                weightUsed: 0
            ), nominalWeightsByName["Circadian"]!))
        }

        // --- Breathing -------------------------------------------------------
        if let breathingNormalized = breathingComponent(night: night, history: history) {
            raw.append((Component(
                label: "Breathing",
                detail: night.avgRespiratoryRate.map { String(format: "%.1f br/min", $0) } ?? "—",
                normalized: breathingNormalized,
                weightUsed: 0
            ), nominalWeightsByName["Breathing"]!))
        }

        // --- Architecture ------------------------------------------------------
        if let architectureNormalized = architectureComponent(night: night, history: history) {
            raw.append((Component(
                label: "Architecture",
                detail: "\(Int(night.deepMinutes))m deep, \(Int(night.remMinutes))m REM",
                normalized: architectureNormalized,
                weightUsed: 0
            ), nominalWeightsByName["Architecture"]!))
        }

        // --- Renormalize -----------------------------------------------------
        let totalNominal = raw.reduce(0) { $0 + $1.nominalWeight }
        let components: [Component] = totalNominal > 0
            ? raw.map { entry in
                var component = entry.component
                component = Component(
                    label: component.label, detail: component.detail,
                    normalized: component.normalized,
                    weightUsed: entry.nominalWeight / totalNominal
                )
                return component
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

    private static func recoveryComponent(night: SleepNightFeatures, history: [SleepNightFeatures]) -> Double? {
        var scores: [(value: Double, weight: Double)] = []

        if let hrv = night.avgHRV {
            let history30 = Array(history.suffix(30)).compactMap(\.avgHRV)
            if let z = Statistics.robustZ(hrv, in: history30) {
                // HRV: higher than usual is good, so direction is not symmetric.
                scores.append((interpolate(z, anchors: [
                    (-3, 5), (-2, 20), (-1, 45), (0, 65), (1, 90), (2, 100), (3, 100)
                ]), 0.5))
            }
        }
        if let rhr = night.restingHeartRate {
            let history30 = Array(history.suffix(30)).compactMap(\.restingHeartRate)
            if let z = Statistics.robustZ(rhr, in: history30) {
                // Elevated resting HR relative to baseline is unfavorable.
                scores.append((interpolate(z, anchors: [
                    (-2, 100), (-1, 90), (0, 65), (1, 40), (2, 15), (3, 5)
                ]), 0.3))
            }
        }
        if let temp = night.wristTempDeltaC {
            let history30 = Array(history.suffix(30)).compactMap(\.wristTempDeltaC)
            if let z = Statistics.robustZ(temp, in: history30) {
                // Either direction away from baseline is unusual for temperature.
                scores.append((interpolate(abs(z), anchors: [
                    (0, 100), (1, 75), (1.5, 50), (2, 25), (3, 5)
                ]), 0.2))
            }
        }

        guard !scores.isEmpty else { return nil }
        let totalWeight = scores.reduce(0) { $0 + $1.weight }
        return scores.reduce(0) { $0 + $1.value / 100 * $1.weight } / totalWeight
    }

    private static func recoveryDetail(night: SleepNightFeatures, history: [SleepNightFeatures]) -> String {
        if let hrv = night.avgHRV { return "HRV \(Int(hrv)) ms" }
        if let rhr = night.restingHeartRate { return "Resting HR \(Int(rhr)) bpm" }
        return "—"
    }

    private static func breathingComponent(night: SleepNightFeatures, history: [SleepNightFeatures]) -> Double? {
        var scores: [(value: Double, weight: Double)] = []

        if let rate = night.avgRespiratoryRate {
            let history30 = Array(history.suffix(30)).compactMap(\.avgRespiratoryRate)
            if let z = Statistics.robustZ(rate, in: history30) {
                scores.append((interpolate(abs(z), anchors: [
                    (0, 100), (1, 80), (1.5, 55), (2, 30), (3, 5)
                ]), 0.6))
            }
        }
        if let disturbances = night.breathingDisturbances {
            scores.append((interpolate(disturbances, anchors: [
                (0, 100), (5, 85), (15, 55), (30, 25), (50, 5)
            ]), 0.4))
        }

        guard !scores.isEmpty else { return nil }
        let totalWeight = scores.reduce(0) { $0 + $1.weight }
        return scores.reduce(0) { $0 + $1.value / 100 * $1.weight } / totalWeight
    }

    private static func architectureComponent(night: SleepNightFeatures, history: [SleepNightFeatures]) -> Double? {
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
        // Deliberately gentle -- this is 5% of the score, and a single
        // unusual staged night shouldn't read as a real architecture problem.
        return interpolate(avgDeviation, anchors: [(0, 100), (1, 90), (2, 70), (3, 50), (4, 30)]) / 100
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
        let onset = Statistics.circularMinutesFromMidnight(night.bedtime) / 60
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
    }

    var band: Band {
        switch percent {
        case ..<50: .poor
        case 50..<70: .fair
        case 70..<85: .good
        default: .excellent
        }
    }

    /// Components that helped, strongest first.
    var positiveContributors: [Component] {
        components.filter { $0.pointContribution > 0.5 }
            .sorted { $0.pointContribution > $1.pointContribution }
    }

    /// Components that cost points, largest cost first.
    var negativeContributors: [Component] {
        components.filter { $0.pointContribution < -0.5 }
            .sorted { $0.pointContribution < $1.pointContribution }
    }
}
