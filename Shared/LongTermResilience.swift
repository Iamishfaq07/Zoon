import Foundation

/// Slow-moving personal baselines, compared the only way that can detect a
/// sustained shift: a recent window against a reference window that does not
/// contain it.
///
/// Not biological age, not cardiovascular age, not a comparison to a
/// population curve. A signal is described against *this person's* own earlier
/// history — "resting heart rate has run about 4 bpm below your previous 90
/// days" — and missing values stay missing.
///
/// **What this replaced, and why.** The first version took one window, took
/// its median, and compared the single latest reading against it. Two things
/// are wrong with that, and they compound. A sustained shift contaminates its
/// own reference: three weeks of a genuinely lower resting heart rate drag the
/// 90-day median down with them, so the very change being looked for shrinks
/// the distance that would have revealed it. And the "current" value was one
/// reading — the noisiest possible estimator — so a single restless night
/// could produce a sentence about a quarter of a year.
///
/// The reference window now ends where the recent window begins, and both
/// sides are medians. A long-term statement is made from a run of days
/// against a run of days, or not at all.
enum LongTermResilience {

    enum Window: Int, Hashable, Sendable, CaseIterable {
        case days30 = 30
        case days90 = 90
        case days180 = 180
        case days365 = 365

        var label: String {
            switch self {
            case .days30: "30 days"
            case .days90: "90 days"
            case .days180: "6 months"
            case .days365: "1 year"
            }
        }

        /// How many trailing days count as "recent".
        ///
        /// Fourteen everywhere except the shortest window, where a fortnight
        /// would be half the comparison and the two sides would stop being
        /// distinguishable.
        var recentDays: Int { self == .days30 ? 7 : 14 }
    }

    struct Point: Hashable, Sendable {
        let date: Date
        let value: Double
    }

    /// What one signal needs before a statement about it is defensible.
    ///
    /// Deliberately per-signal. A 3% tolerance — which is what the previous
    /// version applied to everything — is 1.6 bpm of resting heart rate, 1.7
    /// ms of HRV and 0.45 breaths a minute. Those are not comparable
    /// quantities: overnight HRV routinely swings 20% night to night while a
    /// resting heart rate that moves 5% has done something. One formula
    /// across all of them is a formula tuned for none of them.
    ///
    /// None of these are clinical thresholds. They are the smallest change
    /// worth a sentence, chosen against each signal's own night-to-night
    /// spread.
    struct Spec: Hashable, Sendable {
        let name: String
        let unit: String
        /// Whether a fall is the good direction.
        let lowerIsFavourable: Bool
        /// Smallest change in this signal's own units worth reporting.
        let practicalThreshold: Double
        /// Minimum observations in the reference window.
        let minimumReference: Int
        /// Minimum observations in the recent window.
        let minimumRecent: Int
        let decimals: Int

        func format(_ value: Double) -> String {
            String(format: "%.\(decimals)f", value)
        }

        /// Nightly resting heart rate. Stable enough that 2 bpm sustained is
        /// a real move.
        static let restingHeartRate = Spec(
            name: "resting heart rate", unit: "bpm", lowerIsFavourable: true,
            practicalThreshold: 2, minimumReference: 20, minimumRecent: 5, decimals: 0
        )

        /// Overnight HRV. The noisiest of these by a wide margin, so the
        /// threshold is proportionally larger and the sample floor higher.
        static let heartRateVariability = Spec(
            name: "HRV", unit: "ms", lowerIsFavourable: false,
            practicalThreshold: 4, minimumReference: 20, minimumRecent: 6, decimals: 0
        )

        /// Overnight respiratory rate. Very stable; half a breath a minute
        /// sustained is not noise.
        static let respiratoryRate = Spec(
            name: "respiratory rate", unit: "breaths/min", lowerIsFavourable: true,
            practicalThreshold: 0.5, minimumReference: 20, minimumRecent: 5, decimals: 1
        )

        /// VO2 max. Estimated from outdoor walks and runs, so it arrives
        /// every few days at best — the sample floors are much lower and the
        /// confidence ceiling is correspondingly lower too.
        static let vo2Max = Spec(
            name: "VO2 max", unit: "mL/kg/min", lowerIsFavourable: false,
            practicalThreshold: 1.0, minimumReference: 6, minimumRecent: 2, decimals: 1
        )

        /// Sleep Regularity Index, 0–100.
        static let sleepRegularity = Spec(
            name: "sleep regularity", unit: "points", lowerIsFavourable: false,
            practicalThreshold: 5, minimumReference: 20, minimumRecent: 5, decimals: 0
        )

        /// Nightly asleep minutes.
        static let sleepDuration = Spec(
            name: "sleep duration", unit: "min", lowerIsFavourable: false,
            practicalThreshold: 20, minimumReference: 20, minimumRecent: 5, decimals: 0
        )
    }

    /// How large a move has to be relative to the reference window's own
    /// spread before it counts as a shift rather than as the signal doing
    /// what it always does.
    ///
    /// One MAD. Both gates have to pass: a change can be statistically
    /// unusual for a very steady signal and still be too small to mean
    /// anything, and it can be large in absolute terms and still sit inside
    /// the ordinary swing of a noisy one.
    static let minimumRobustEffect = 1.0

    struct Signal: Hashable, Sendable {
        let name: String
        let window: Window
        let unit: String
        /// Median of the recent window. Not a single latest reading.
        let recentCenter: Double?
        /// Median of the reference window, which excludes the recent one.
        let referenceCenter: Double?
        /// Spread of the reference window (MAD), the scale a change is
        /// judged against.
        let referenceVariability: Double?
        let absoluteChange: Double?
        let relativeChange: Double?
        /// `absoluteChange / referenceVariability`, when the reference has
        /// any spread at all.
        let robustEffect: Double?
        let referenceCount: Int
        let recentCount: Int
        /// Calendar days the recent observations actually span, which is not
        /// the same as how many there are.
        let recentSpanDays: Int
        let sentence: String
        let confidence: MetricConfidence
        /// True when the recent run sits on the favourable side, `nil` when
        /// there is no meaningful move to have a side.
        let favourable: Bool?
        /// Whether both gates were cleared.
        let isMeaningfulChange: Bool
    }

    static func measure(
        spec: Spec,
        points: [Point],
        window: Window,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Signal {
        let recentStart = calendar.date(byAdding: .day, value: -window.recentDays, to: now) ?? now
        let referenceStart = calendar.date(byAdding: .day, value: -window.rawValue, to: recentStart)
            ?? recentStart

        // Both windows are half-open at the bottom, `(start, end]`. That is
        // what makes them adjacent rather than overlapping: a reading exactly
        // on the boundary belongs to the older window and to that one only. A
        // point counted on both sides would sit inside its own comparison,
        // which is the failure this whole redesign exists to remove. It also
        // makes a fourteen-day window hold fourteen daily readings rather
        // than fifteen.
        let usable = points.filter { $0.value.isFinite }
        let recent = usable.filter { $0.date > recentStart && $0.date <= now }
            .sorted { $0.date < $1.date }
        let reference = usable.filter { $0.date > referenceStart && $0.date <= recentStart }
            .sorted { $0.date < $1.date }

        let recentSpan = span(of: recent, calendar: calendar)

        func insufficient(_ reason: String) -> Signal {
            Signal(
                name: spec.name,
                window: window,
                unit: spec.unit,
                recentCenter: Statistics.median(recent.map(\.value)),
                referenceCenter: nil,
                referenceVariability: nil,
                absoluteChange: nil,
                relativeChange: nil,
                robustEffect: nil,
                referenceCount: reference.count,
                recentCount: recent.count,
                recentSpanDays: recentSpan,
                sentence: reason,
                confidence: .insufficient,
                favourable: nil,
                isMeaningfulChange: false
            )
        }

        guard recent.count >= spec.minimumRecent else {
            return insufficient(
                "Not enough recent \(spec.name) to compare — \(coverage(recent.count, spanDays: recentSpan)) in the last \(window.recentDays) days."
            )
        }
        guard reference.count >= spec.minimumReference else {
            return insufficient(
                "Not enough \(spec.name) history before the last \(window.recentDays) days to compare against — \(coverage(reference.count, spanDays: span(of: reference, calendar: calendar)))."
            )
        }
        guard let referenceCenter = Statistics.median(reference.map(\.value)),
              let recentCenter = Statistics.median(recent.map(\.value))
        else {
            return insufficient("Not enough \(spec.name) history to describe a baseline.")
        }

        let variability = Statistics.medianAbsoluteDeviation(
            reference.map(\.value), median: referenceCenter
        ) ?? 0
        let absoluteChange = recentCenter - referenceCenter
        let relativeChange = referenceCenter == 0 ? 0 : absoluteChange / referenceCenter
        // A reference window with no spread at all cannot scale anything.
        // That is real — a signal Health reports to the nearest whole unit
        // can sit on one value for weeks — so the practical threshold decides
        // alone rather than a division by zero deciding for it.
        let robustEffect: Double? = variability > 0 ? absoluteChange / variability : nil

        let clearsPractical = abs(absoluteChange) >= spec.practicalThreshold
        let clearsEffect = robustEffect.map { abs($0) >= minimumRobustEffect } ?? true
        let meaningful = clearsPractical && clearsEffect

        let favourable: Bool? = meaningful
            ? (spec.lowerIsFavourable ? absoluteChange < 0 : absoluteChange > 0)
            : nil

        let confidence = confidence(
            referenceCount: reference.count,
            referenceDays: window.rawValue,
            recentCount: recent.count,
            recentDays: window.recentDays,
            hasVariability: variability > 0
        )

        let sentence: String
        if meaningful {
            let side = absoluteChange < 0 ? "below" : "above"
            sentence = "Your \(spec.name) has run about \(spec.format(abs(absoluteChange))) \(spec.unit) \(side) your previous \(window.label) — \(spec.format(recentCenter)) across \(coverage(recent.count, spanDays: recentSpan)), against \(spec.format(referenceCenter)) before that."
        } else {
            sentence = "Your \(spec.name) has stayed close to your previous \(window.label) — \(spec.format(recentCenter)) across \(coverage(recent.count, spanDays: recentSpan)), against \(spec.format(referenceCenter)) before that."
        }

        return Signal(
            name: spec.name,
            window: window,
            unit: spec.unit,
            recentCenter: recentCenter,
            referenceCenter: referenceCenter,
            referenceVariability: variability,
            absoluteChange: absoluteChange,
            relativeChange: relativeChange,
            robustEffect: robustEffect,
            referenceCount: reference.count,
            recentCount: recent.count,
            recentSpanDays: recentSpan,
            sentence: sentence,
            confidence: confidence,
            favourable: favourable,
            isMeaningfulChange: meaningful
        )
    }

    // MARK: - Internals

    /// "8 observations spanning 19 days", or "8 nights" when the sampling is
    /// dense enough that the two numbers say the same thing.
    ///
    /// The distinction is the point. "For 8 days" reads as eight consecutive
    /// days, and when the eight readings are scattered across three weeks
    /// that sentence is simply false — which is what the previous run-length
    /// counter reported.
    static func coverage(_ count: Int, spanDays: Int) -> String {
        let nights = count == 1 ? "1 reading" : "\(count) readings"
        guard spanDays > count else { return nights }
        return "\(nights) spanning \(spanDays) days"
    }

    /// Calendar days between the first and last observation, inclusive.
    private static func span(of points: [Point], calendar: Calendar) -> Int {
        guard let first = points.first?.date, let last = points.last?.date else { return 0 }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: first), to: calendar.startOfDay(for: last)
        ).day ?? 0
        return max(1, days + 1)
    }

    /// How dense the sampling was on each side, taken at the weaker one.
    ///
    /// A comparison is only as good as its thinner window: sixty reference
    /// nights against five recent ones is not a well-observed fortnight, and
    /// averaging the two densities would hide that.
    private static func confidence(
        referenceCount: Int,
        referenceDays: Int,
        recentCount: Int,
        recentDays: Int,
        hasVariability: Bool
    ) -> MetricConfidence {
        func band(_ count: Int, _ days: Int) -> MetricConfidence {
            let density = Double(count) / Double(max(days, 1))
            return switch density {
            case 0.6...: .high
            case 0.35..<0.6: .moderate
            default: .low
            }
        }
        let observed = min(band(referenceCount, referenceDays), band(recentCount, recentDays))
        // With no spread in the reference there is no scale to judge against,
        // so the practical threshold is carrying the decision alone. That is
        // defensible but it is not high confidence.
        return hasVariability ? observed : min(observed, .moderate)
    }
}
