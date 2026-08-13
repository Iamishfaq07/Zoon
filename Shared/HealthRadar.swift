import Foundation

/// Sustained drift across several signals at once.
///
/// Oura's Health Radar, reimplemented. The distinction from `VitalsStatus`
/// matters and is the whole reason this exists separately: that panel asks
/// *"was last night unusual?"*, which any single bad night triggers. This asks
/// *"have several signals been moving together for several days?"* — which is a
/// much rarer and much more meaningful event.
///
/// One elevated reading is noise. Three nights of elevated temperature *and*
/// suppressed HRV *and* raised resting heart rate is the pattern that precedes
/// a cold, follows a hard training block, or accompanies a drinking spell. It is
/// worth surfacing, and it is invisible in any single-night view.
struct HealthRadar: Codable, Hashable, Sendable {

    let signals: [Signal]
    /// Nights the detection ran across.
    let nightCount: Int

    struct Signal: Codable, Hashable, Sendable, Identifiable {
        let kind: VitalsStatus.Kind
        let direction: Direction
        /// Consecutive nights this signal has been drifting.
        let consecutiveNights: Int
        /// Median over the drift window -- see `detect`'s doc comment for why
        /// median/MAD replaced mean/SD here.
        let recentMean: Double
        /// Long-run personal baseline, also a median.
        let baseline: Double

        var id: String { kind.rawValue }

        var percentChange: Double {
            guard baseline != 0 else { return 0 }
            return (recentMean - baseline) / abs(baseline) * 100
        }
    }

    enum Direction: String, Codable, Hashable, Sendable {
        case elevated, suppressed

        var symbol: String {
            self == .elevated ? "arrow.up.right" : "arrow.down.right"
        }
    }

    /// Consecutive nights of drift before a signal counts.
    ///
    /// Three, not two: two consecutive nights happens by chance often enough
    /// that a two-night threshold would fire most weeks and the feature would
    /// become wallpaper.
    static let minimumConsecutiveNights = 3

    /// Baseline nights needed before any of this is trustworthy.
    static let minimumBaselineNights = 14

    /// Signals must move by at least this many standard deviations to count.
    static let driftSigma = 0.8

    // MARK: - Detection

    /// Median/MAD, not mean/SD, for the baseline center and tolerance band.
    ///
    /// A single bad night sitting in the 30-night baseline window (the same
    /// stomach bug or red-eye flight `Statistics`'s own doc comment warns
    /// about) used to be able to drag `baseMean` toward itself and inflate
    /// `sd`, which does two things wrong at once: it quietly redefines
    /// "normal" to include the outlier, and it widens the tolerance band so
    /// a real drift has to be even larger before it's noticed. A median
    /// barely moves for one outlier night, and MAD-derived tolerance doesn't
    /// balloon from it either.
    static func detect(nights: [SleepNightFeatures]) -> HealthRadar {
        let sorted = nights.sorted { $0.date < $1.date }
        guard sorted.count >= minimumBaselineNights else {
            return HealthRadar(signals: [], nightCount: sorted.count)
        }

        // Baseline excludes the recent window, so a drift that's already
        // underway can't quietly redefine "normal" and hide itself.
        let recentWindow = Array(sorted.suffix(minimumConsecutiveNights))
        let baselineWindow = Array(sorted.dropLast(minimumConsecutiveNights).suffix(30))
        guard baselineWindow.count >= minimumBaselineNights - minimumConsecutiveNights else {
            return HealthRadar(signals: [], nightCount: sorted.count)
        }

        var detected: [Signal] = []

        for kind in VitalsStatus.Kind.allCases {
            let baselineValues = baselineWindow.compactMap { value(kind, in: $0) }
            let recentValues = recentWindow.compactMap { value(kind, in: $0) }

            guard baselineValues.count >= 8,
                  recentValues.count == recentWindow.count else { continue }

            let baseMedian = Statistics.median(baselineValues) ?? mean(baselineValues)
            // MAD scaled by 0.6745 lands on the same scale as a standard
            // deviation under a normal distribution -- see `Statistics.robustZ`
            // for the same convention. Falls back to plain SD only when MAD is
            // degenerate (near-zero, e.g. a metric that's been nearly
            // identical every baseline night), the same fallback shape
            // `robustZ` uses, rather than letting a near-zero MAD make the
            // tolerance band collapse to nothing.
            let mad = Statistics.medianAbsoluteDeviation(baselineValues, median: baseMedian)
            let robustSD = (mad.map { $0 / 0.6745 }).flatMap { $0 > 0.01 ? $0 : nil }
                ?? standardDeviation(baselineValues, mean: baseMedian)
            let tolerance = max(robustSD * driftSigma, kind.minimumTolerance)

            // Every night in the window must be on the same side of the band —
            // one big night surrounded by normal ones is not a drift.
            let allElevated = recentValues.allSatisfy { $0 > baseMedian + tolerance }
            let allSuppressed = recentValues.allSatisfy { $0 < baseMedian - tolerance }
            guard allElevated || allSuppressed else { continue }

            detected.append(Signal(
                kind: kind,
                direction: allElevated ? .elevated : .suppressed,
                consecutiveNights: recentWindow.count,
                recentMean: Statistics.median(recentValues) ?? mean(recentValues),
                baseline: baseMedian
            ))
        }

        return HealthRadar(signals: detected, nightCount: sorted.count)
    }

    private static func value(_ kind: VitalsStatus.Kind, in night: SleepNightFeatures) -> Double? {
        switch kind {
        case .restingHeartRate: night.restingHeartRate
        case .hrv: night.avgHRV
        case .respiratoryRate: night.avgRespiratoryRate
        case .oxygenSaturation: night.avgSpO2
        case .wristTemperature: night.wristTempDeltaC
        case .sleepDuration: night.timeAsleepMinutes
        case .breathingDisturbances: night.breathingDisturbances
        }
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviation(_ values: [Double], mean m: Double) -> Double {
        guard values.count > 1 else { return 0 }
        return (values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count)).squareRoot()
    }
}

// MARK: - Presentation

extension HealthRadar {

    var isActive: Bool { !signals.isEmpty }

    /// Severity rises with how many signals moved together, because
    /// co-movement is the actual signal — one drifting metric is common,
    /// three at once is not.
    enum Severity: String, Sendable {
        case clear, watch, notable

        var label: String {
            switch self {
            case .clear: "Nothing unusual"
            case .watch: "Worth watching"
            case .notable: "Several signals moving"
            }
        }
    }

    var severity: Severity {
        switch signals.count {
        case 0: .clear
        case 1...2: .watch
        default: .notable
        }
    }

    var headline: String {
        guard isActive else { return "No sustained changes" }
        let names = signals.map(\.kind.label).joined(separator: ", ")
        return names
    }

    var detail: String {
        guard nightCount >= Self.minimumBaselineNights else {
            return "Zoon needs about two weeks of nights before it can spot sustained changes."
        }
        guard isActive else {
            return "Nothing has been drifting from your baseline for three nights or more."
        }

        let base = "\(signals.count == 1 ? "This signal has" : "These signals have") been outside your usual range for \(Self.minimumConsecutiveNights) nights running."

        // The interpretation is only offered when several signals move
        // together — a single drifting metric has too many explanations to
        // narrow usefully.
        switch severity {
        case .notable:
            return base + " Several moving at once often accompanies illness onset, a heavy training block, alcohol, or travel. Worth easing off and watching."
        case .watch:
            return base + " One or two signals drifting is common and usually resolves on its own."
        case .clear:
            return base
        }
    }
}
