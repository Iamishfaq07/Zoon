import Foundation

/// Explains why one night stood out, by ranking how far each signal drifted
/// from that person's own recent baseline.
///
/// The question this answers is "what was different about this night", and
/// deliberately not "what caused this night". Every factor here is a
/// *coincidence with* the outcome, measured on the same night -- there is no
/// control, no matched pair, and no randomisation, so nothing in a report can
/// support a causal claim. `JournalCorrelator` is the engine that earns
/// causal language, across many nights and matched comparisons; this one
/// describes a single night and says so in its copy ("stood out", "alongside"),
/// never "because".
///
/// Ranking is by robust z-score against the person's own history, not against
/// any population norm: a resting heart rate of 62 is unremarkable for one
/// person and a five-point excursion for another, and only the second is
/// worth a sentence.
///
/// Lives in `Zoon/Insights` rather than `Shared` because it names
/// `BehaviorTag`, which is an app model. `Shared` compiles into the widget
/// and watch targets, which do not carry app models -- see `WatchLink`, which
/// passes tag *identifiers* across precisely because the watch cannot see the
/// type. `JournalCorrelator` and `GuidedExperiment` sit here for the same
/// reason.
enum NightDetective {

    /// Prior nights needed before any baseline is trustworthy enough to call
    /// something unusual.
    ///
    /// `Statistics.robustZ` needs 3 to produce a number at all; this is
    /// deliberately much higher. A median and MAD drawn from four nights will
    /// happily label the fifth an outlier, which is how you end up telling
    /// someone their perfectly ordinary Tuesday was remarkable.
    static let minimumBaselineNights = 14

    /// Baseline window. Matches `DayContextBuilder.recoveryBaselineWindow` so
    /// a factor called unusual here is unusual against the same history the
    /// Today screen scores against.
    static let baselineWindow = 30

    /// How far from baseline a signal must sit before it is worth reporting.
    /// 1.5 robust z is roughly the point where a value stops looking like an
    /// ordinary night and starts looking like a different kind of night.
    static let minimumZ = 1.5

    /// Signals a night can stand out on.
    ///
    /// Only measured, physiological or architectural quantities -- nothing
    /// derived from a score. Reporting that "your sleep score was low" as an
    /// explanation for a low sleep score is circular, and the scores are
    /// already explained by their own component breakdowns.
    enum Signal: String, CaseIterable, Hashable, Sendable {
        case duration, efficiency, wakeCount, latency
        case deepMinutes, remMinutes
        case restingHeartRate, hrv, respiratoryRate, wristTemperature

        var label: String {
            switch self {
            case .duration: "time asleep"
            case .efficiency: "sleep efficiency"
            case .wakeCount: "awakenings"
            case .latency: "time to fall asleep"
            case .deepMinutes: "deep sleep"
            case .remMinutes: "REM sleep"
            case .restingHeartRate: "resting heart rate"
            case .hrv: "HRV"
            case .respiratoryRate: "breathing rate"
            case .wristTemperature: "wrist temperature"
            }
        }

        /// Whether a higher-than-baseline reading is the better direction.
        /// Used only to describe the excursion, never to score it -- an
        /// unusually *high* HRV is still worth surfacing as unusual.
        var higherIsBetter: Bool {
            switch self {
            case .duration, .efficiency, .deepMinutes, .remMinutes, .hrv: true
            case .wakeCount, .latency, .restingHeartRate, .respiratoryRate, .wristTemperature: false
            }
        }

        func value(from night: SleepNightFeatures) -> Double? {
            switch self {
            case .duration: night.timeAsleepMinutes
            case .efficiency: night.sleepEfficiencyPercent
            case .wakeCount: Double(night.wakeCount)
            case .latency: night.sleepLatencyMinutes
            // Stage minutes are only meaningful when the source actually
            // reported stages; a source that reports none would otherwise
            // read as a night of zero deep sleep.
            case .deepMinutes: night.hasStageBreakdown ? night.deepMinutes : nil
            case .remMinutes: night.hasStageBreakdown ? night.remMinutes : nil
            case .restingHeartRate: night.restingHeartRate
            case .hrv: night.avgHRV
            case .respiratoryRate: night.avgRespiratoryRate
            case .wristTemperature: night.wristTempDeltaC
            }
        }

        func formatted(_ value: Double) -> String {
            switch self {
            case .duration, .deepMinutes, .remMinutes, .latency:
                SleepNightFeatures.formatMinutes(value)
            case .efficiency: String(format: "%.0f%%", value)
            case .wakeCount: String(format: "%.0f", value)
            case .restingHeartRate: String(format: "%.0f bpm", value)
            case .hrv: String(format: "%.0f ms", value)
            case .respiratoryRate: String(format: "%.1f br/min", value)
            case .wristTemperature: String(format: "%+.1f°C", value)
            }
        }
    }

    struct Factor: Identifiable, Hashable, Sendable {
        let signal: Signal
        let value: Double
        let baseline: Double
        /// Robust z against the person's own baseline window. Signed: the
        /// direction of the excursion, not of its desirability.
        let z: Double

        var id: String { signal.rawValue }
        var isAboveBaseline: Bool { z > 0 }
        /// Whether the excursion went the direction that usually reads as a
        /// worse night for this signal.
        var isUnfavourable: Bool { isAboveBaseline != signal.higherIsBetter }

        var sentence: String {
            let direction = isAboveBaseline ? "higher" : "lower"
            return "\(signal.label.capitalizedFirst) was \(signal.formatted(value)), "
                + "\(direction) than your usual \(signal.formatted(baseline))."
        }
    }

    struct Report: Hashable, Sendable {
        let date: Date
        /// Ranked most-unusual first.
        let factors: [Factor]
        /// Behaviours logged for this night, if any. Carried alongside the
        /// factors, never merged into them: a tag is something the person
        /// reported, a factor is something a sensor measured, and blurring
        /// the two would let a self-report inherit a measurement's authority.
        let loggedTags: [BehaviorTag]
        let baselineNights: Int

        var isUnremarkable: Bool { factors.isEmpty }

        var headline: String {
            guard let top = factors.first else {
                return "Nothing about this night stood out from your usual pattern."
            }
            return "\(top.signal.label.capitalizedFirst) stood out most on this night."
        }

        /// Deliberately hedged. See the type doc: same-night coincidence is
        /// not evidence of cause, and the copy must not imply otherwise.
        var tagSentence: String? {
            guard !loggedTags.isEmpty else { return nil }
            let names = loggedTags.map(\.label).joined(separator: ", ")
            return "You logged \(names) alongside this night. "
                + "That's what happened at the same time, not a proven cause."
        }
    }

    // MARK: - Investigation

    /// Ranks what was unusual about `night` against the `baselineWindow`
    /// nights before it.
    ///
    /// - Parameter history: any nights; those on or after `night.date` are
    ///   discarded. A baseline must never contain the night being explained,
    ///   or the night drags its own comparison toward itself and the most
    ///   extreme values are the ones most understated.
    /// - Returns: `nil` when there is not yet enough history to say what
    ///   "usual" means for this person.
    static func investigate(
        night: SleepNightFeatures,
        history: [SleepNightFeatures],
        loggedTags: [BehaviorTag] = [],
        minimumZ: Double = minimumZ
    ) -> Report? {
        let prior = history
            .filter { $0.date < night.date }
            .sorted { $0.date < $1.date }
            .suffix(baselineWindow)

        guard prior.count >= minimumBaselineNights else { return nil }

        var factors: [Factor] = []
        for signal in Signal.allCases {
            guard let value = signal.value(from: night) else { continue }
            let baselineValues = prior.compactMap(signal.value)
            guard baselineValues.count >= minimumBaselineNights,
                  let baseline = Statistics.median(baselineValues),
                  let z = Statistics.robustZ(value, in: baselineValues),
                  abs(z) >= minimumZ else { continue }

            factors.append(Factor(signal: signal, value: value, baseline: baseline, z: z))
        }

        return Report(
            date: night.date,
            factors: factors.sorted { abs($0.z) > abs($1.z) },
            loggedTags: loggedTags.sorted { $0.rawValue < $1.rawValue },
            baselineNights: prior.count
        )
    }
}
