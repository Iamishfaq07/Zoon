import Foundation

/// A live, daytime read on autonomic load — Garmin's Stress Score and Whoop's
/// intraday strain signal, reimplemented. Presented to the user as
/// "Physiological Load", not "Stress" -- see `StressCard`'s doc comment for
/// why. The Swift type name is unchanged (a rename here would be a large,
/// purely cosmetic diff across every call site for no behavior change); only
/// the user-facing label moved.
///
/// Every other score in Zoon looks backward at a finished night. This is the
/// one exception: it compares *right now* against your rolling baseline, so
/// it can say something about the day that's still happening rather than only
/// the one that already ended.
///
/// ## Why this can be honest with no new permission
///
/// Heart rate and HRV are already granted for the overnight pipeline. Reusing
/// them for a daytime average costs nothing new to ask for — the trade-off is
/// resolution: this is a single average over however much of the day has
/// elapsed, not a continuous trace. A watch app with a live workout session
/// could sample every few seconds; a phone reading HealthKit after the fact
/// gets whatever discrete samples happened to land. Good enough to say
/// "elevated today", not good enough to say "elevated at 2:14pm".
///
/// ## Why "Experimental" -- and when it stops being
///
/// Excluding workouts, the minutes after them, and high-movement hours (see
/// `SleepDataCoordinator.refreshTodayStress`) removes the worst source of
/// false "elevated" readings, but doesn't close the deeper gap: the rolling
/// baseline this compares against is built from *overnight* resting
/// physiology (`RollingBaseline.restingHeartRate7DayAvg`/`hrv7DayAvg`), and
/// autonomic tone during sleep is not the same physiological state as calm
/// wakefulness. A perfectly relaxed waking hour can still read as
/// "Elevated" simply because waking and sleeping HR/HRV don't live on the
/// same scale. A genuine fix needs a real activity-and-time-of-day-aware
/// daytime baseline built from historical daytime samples.
///
/// `DaytimeBaseline` is that baseline, and where it has enough history this
/// score now compares waking readings with waking readings. The Experimental
/// label follows the fact rather than the feature: `experimentalReason` is
/// `nil` once every component used a waking comparison, and the label comes
/// off. A caveat that outlives its own cause stops being read, and teaches
/// people to read past every other caveat too.
///
/// It stays on wherever the waking baseline is not ready -- a new user, a
/// quiet hour with too little history -- because there the original problem
/// is still exactly as described above.
struct StressScore: Codable, Hashable, Sendable {

    /// 0–100. Higher means further from baseline in the stressed direction.
    let percent: Int
    let band: Band
    /// Minutes of the day this average is drawn from — small early, larger
    /// by evening. Shown so the number reads as "so far today", not final.
    let sampledMinutes: Double

    /// How much of the waking day had elapsed when this was computed.
    ///
    /// `nil` for a score computed without it — an older stored record, or a
    /// caller that does not know. Absent means no coverage judgement is
    /// offered, rather than a guessed one.
    let elapsedWakingMinutes: Double?
    let avgHeartRate: Double?
    let avgHRV: Double?
    /// The rolling overnight baselines today's readings were compared
    /// against -- carried on the score itself (rather than left as `compute`
    /// locals) so a detail screen can show "today vs your baseline" for each
    /// signal, not just the blended percent.
    let hrBaseline: Double?
    let hrvBaseline: Double?
    /// False once there's baseline history to compare against honestly.
    let isEstimate: Bool
    /// Which kind of baseline each component was actually measured against.
    ///
    /// Carried rather than inferred, because the two are not interchangeable
    /// and the difference is the whole reason this score was labelled
    /// experimental. `nil` when that component had no baseline at all.
    var hrBasis: BaselineBasis?
    var hrvBasis: BaselineBasis?

    /// What a reading was compared against.
    enum BaselineBasis: String, Codable, Hashable, Sendable {
        /// The person's own waking readings at this hour of the day. The
        /// comparison this score always wanted.
        case wakingTimeOfDay
        /// Overnight resting physiology. Kept as a fallback because it is
        /// better than no comparison, but sleeping and calm-waking values do
        /// not live on the same scale -- a normal desk-bound heart rate can
        /// read 30% above a normal sleeping one.
        case overnightResting
    }

    enum Band: String, Codable, Sendable {
        case calm, elevated, high

        var label: String {
            switch self {
            case .calm: "Calm"
            case .elevated: "Elevated"
            case .high: "High"
            }
        }

        var detail: String {
            switch self {
            case .calm: "Autonomic load today is around your usual."
            case .elevated: "Running a bit hot today. Not urgent, worth noticing."
            case .high: "Well above your usual for today. Consider easing off."
            }
        }
    }

    /// Baseline nights required before this is more than a guess.
    static let minimumBaselineNights = 7

    /// Why this score is still marked Experimental, or `nil` once it isn't.
    ///
    /// The label had one stated reason: the baseline came from overnight
    /// resting physiology, and calm wakefulness does not sit on that scale.
    /// `DaytimeBaseline` removes that reason wherever it has enough history,
    /// so the label has to be able to come off.
    ///
    /// The *other* limitation the detail view names -- resolution, one
    /// average over however much of the day has elapsed -- is unchanged, and
    /// is carried by `sampledMinutes` and the Estimate pill, which is where
    /// it belongs.
    var experimentalReason: String? {
        isScaleMatched
            ? nil
            : "Marked Experimental because part of this compares waking readings against your overnight baseline, and even a genuinely calm waking hour doesn't sit on the scale sleep does. Once there are enough quiet readings from this time of day, it compares like with like instead."
    }

    // MARK: - How much of the day this rests on

    /// The fraction of the elapsed waking day that was quiet enough to sample.
    ///
    /// **What this is and is not.** `sampledMinutes` is the duration of the
    /// windows left after workouts, the buffer following them, and
    /// high-movement hours are removed. So this measures sampling
    /// *opportunity*: how much of the day was in a state where a resting
    /// reading meant anything.
    ///
    /// It is deliberately not called sample density, because it is not that.
    /// Observed density — how many readings a watch actually took in those
    /// windows — would distinguish denser hardware from sparser hardware
    /// without naming either, which is what the audit asks for. It needs a
    /// sample-count query, and `HealthKitManager` has only averages and sums
    /// today. That is a real limitation and it is written down here rather
    /// than papered over by labelling this something it is not.
    ///
    /// What it does deliver is the half that matters most for trust: a score
    /// resting on forty minutes of a twelve-hour day should not read with the
    /// same confidence as one resting on seven hours, and until now they did.
    var quietCoverage: Double? {
        guard let elapsedWakingMinutes, elapsedWakingMinutes > 0 else { return nil }
        return min(1, max(0, sampledMinutes / elapsedWakingMinutes))
    }

    /// Confidence in the day's coverage, from the coverage itself.
    ///
    /// **Two conditions, not one.** A fraction alone is wrong first thing in
    /// the morning: an hour after waking, an entirely quiet hour is 100%
    /// coverage of a very short day, and reporting that as high confidence
    /// would be an artefact of the clock. So each band needs a share of the
    /// day *and* an absolute amount of quiet time behind it.
    ///
    /// This is the same shape as the awakening gate in `RecoveryDayPlan`: the
    /// ratio asks whether the day was mostly quiet, the minutes ask whether
    /// there is enough of it to mean anything.
    ///
    /// No device model is consulted anywhere here, by design. Newer hardware
    /// benefits when it genuinely produces more usable quiet time; older
    /// hardware is never marked down for being older.
    var coverageConfidence: MetricConfidence? {
        guard let quietCoverage else { return nil }
        if quietCoverage >= 0.50, sampledMinutes >= 180 { return .high }
        if quietCoverage >= 0.30, sampledMinutes >= 90 { return .moderate }
        if sampledMinutes >= 30 { return .low }
        return .insufficient
    }

    /// Coverage said plainly, for a surface that wants to disclose it.
    var coverageNote: String? {
        guard let quietCoverage, let coverageConfidence else { return nil }
        let percent = Int((quietCoverage * 100).rounded())
        let hours = sampledMinutes / 60
        let amount = hours >= 1
            ? String(format: "%.1f hours", hours)
            : "\(Int(sampledMinutes.rounded())) minutes"
        switch coverageConfidence {
        case .high, .moderate:
            return "Based on \(amount) of quiet time, about \(percent)% of your day so far."
        case .low:
            return "Based on \(amount) of quiet time — most of your day so far was too active to read from."
        case .insufficient:
            return "Barely any quiet time yet today, so this rests on very little."
        }
    }

    /// True when every component used was compared against waking readings
    /// from this hour of the day, so the scale mismatch does not apply.
    var isScaleMatched: Bool {
        let used = [hrBasis, hrvBasis].compactMap { $0 }
        return !used.isEmpty && used.allSatisfy { $0 == .wakingTimeOfDay }
    }

    /// What this number was measured against. Kept on the model so every
    /// surface discloses the same thing instead of relying on a detail screen
    /// being opened.
    var baselineContextNote: String {
        switch (hrBasis, hrvBasis) {
        case (.wakingTimeOfDay, .wakingTimeOfDay),
             (.wakingTimeOfDay, nil), (nil, .wakingTimeOfDay):
            return "Compared with your own waking readings from this time of day."
        case (nil, nil):
            return "Compared with your overnight baseline; waking physiology normally differs."
        default:
            return "Partly compared with your overnight baseline, where there aren't enough waking readings from this hour yet."
        }
    }

    /// - Parameters:
    ///   - wakingHRBaseline: this hour's own waking centre, when there is one.
    ///     Preferred over `hrBaseline` whenever present -- it is the same
    ///     physiological state as the reading being scored.
    ///   - wakingHRVBaseline: the same for HRV.
    static func compute(
        avgHeartRate: Double?,
        avgHRV: Double?,
        hrBaseline: Double?,
        hrvBaseline: Double?,
        sampledMinutes: Double,
        baselineNightCount: Int,
        /// Minutes of the waking day elapsed so far. Optional because a
        /// caller that does not know must not have one invented for it —
        /// see `quietCoverage`.
        elapsedWakingMinutes: Double? = nil,
        wakingHRBaseline: Double? = nil,
        wakingHRVBaseline: Double? = nil
    ) -> StressScore? {
        // Needs at least one live signal today — a score built from zero
        // samples would just be restating the baseline back as "calm".
        guard avgHeartRate != nil || avgHRV != nil else { return nil }

        var points: [Double] = []
        // The waking centre wins wherever it exists: comparing a waking
        // reading against a sleeping one is the defect this replaces, and a
        // fallback that silently takes over would reintroduce it.
        let hrComparison = wakingHRBaseline ?? hrBaseline
        let hrvComparison = wakingHRVBaseline ?? hrvBaseline
        var hrBasis: BaselineBasis?
        var hrvBasis: BaselineBasis?

        // HR component: higher than baseline reads as more stressed. Maps
        // ±20% around baseline onto 0…1 (so +10% → 0.75, +20% → 1.0); the
        // divisor is the full width of that band, the same convention
        // `RecoveryScore` uses.
        if let hr = avgHeartRate, let base = hrComparison, base > 0 {
            let deviation = (hr - base) / base
            points.append(clamp01(0.5 + deviation / 0.40))
            hrBasis = wakingHRBaseline != nil ? .wakingTimeOfDay : .overnightResting
        }

        // HRV component: inverted — lower than baseline reads as more
        // stressed. HRV is the noisier of the two, so it gets the wider
        // band: ±35% around baseline onto 0…1 (−35% → 1.0).
        if let hrv = avgHRV, let base = hrvComparison, base > 0 {
            let deviation = (hrv - base) / base
            points.append(clamp01(0.5 - deviation / 0.70))
            hrvBasis = wakingHRVBaseline != nil ? .wakingTimeOfDay : .overnightResting
        }

        // Neither baseline is available yet: there is nothing to compare
        // today's reading against, so there is no stress score to report.
        // This used to fall back to a flat 0.5 -- which lands as 50,
        // "Elevated" -- presenting a real-looking result for a comparison
        // that never happened. `todayStress` is optional precisely so the
        // UI can show "Building baseline" instead of a card, the same way
        // it already does when there's no live HR/HRV sample at all.
        guard !points.isEmpty else { return nil }
        let normalized = points.reduce(0, +) / Double(points.count)
        let value = Int((normalized * 100).rounded())

        // Re-centred with the baseline fix, and only defensible because of
        // it. The scale is 50 at your usual, and the old bands called 50
        // "Elevated" -- which was survivable only while the comparison was
        // against sleeping physiology, where a normal waking reading sat far
        // above 50 anyway. Against a matched waking baseline those bands
        // would have reported a perfectly typical day as elevated, every day.
        //
        // Stated as deviation from usual, which is what the scale means:
        //   under +5%        calm
        //   +5% up to +15%   elevated
        //   +15% and above   high
        // (`value` is 50 + deviation/0.40 x 50, so those are 63 and 88.)
        let band: Band = switch value {
        case ..<63: .calm
        case 63..<88: .elevated
        default: .high
        }

        return StressScore(
            percent: value,
            band: band,
            sampledMinutes: sampledMinutes,
            elapsedWakingMinutes: elapsedWakingMinutes,
            avgHeartRate: avgHeartRate,
            avgHRV: avgHRV,
            hrBaseline: hrComparison,
            hrvBaseline: hrvComparison,
            // A waking baseline stands on its own history, so a thin *night*
            // count no longer makes the score an estimate when nothing was
            // drawn from the nights.
            isEstimate: [hrBasis, hrvBasis].contains(.overnightResting)
                && baselineNightCount < minimumBaselineNights,
            hrBasis: hrBasis,
            hrvBasis: hrvBasis
        )
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
