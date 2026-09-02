import Foundation

/// "What tends to happen on your nights when X is different?"
///
/// The obvious way to build a counterfactual is to take last night, add
/// thirty minutes to it, re-run the scoring engine, and show the new number.
/// That was rejected deliberately. A night with thirty more minutes of sleep
/// but *identical* efficiency, identical stage split, identical HRV and
/// identical resting heart rate is not a night that could physically happen;
/// re-scoring it would produce a confident number describing nothing real,
/// and the number would move purely because one input to a formula moved.
///
/// This projects from the person's own history instead. It splits their real
/// nights on the lever, compares the outcome between the two groups, and
/// reports what actually tended to happen. Every night in both groups is a
/// night they really had.
///
/// **Still not causal**, and the caveat says so. Nights where someone slept
/// much longer than usual differ in every other way too -- weekends,
/// holidays, illness, no alarm -- and this cannot separate the extra sleep
/// from the reason it was available. `JournalCorrelator` earns stronger
/// language than this because it matches pairs on confounders; this splits on
/// one variable and does not.
///
/// Complementary to `JournalCorrelator` rather than a duplicate of it: that
/// engine matches on discrete `BehaviorTag`s the person logged, this one
/// splits on a continuous property of the night itself, which no tag
/// captures.
enum ZoonTwin {

    /// Nights required on each side of the split.
    ///
    /// Matches `GuidedExperiment.minimumPeriodNights` for the same reason: a
    /// median over three nights is not a level, and a difference between two
    /// such medians is an artifact of which nights happened to land where.
    static let minimumGroupNights = 7

    /// How far from the person's own median a night must sit to count as
    /// "one of the different ones", in robust z units. 0.5 is deliberately
    /// modest -- the split needs to divide the history into two usefully
    /// sized groups, not isolate a handful of extremes.
    static let leverThresholdZ = 0.5

    enum Direction: String, Hashable, Sendable {
        /// Nights where the lever sat above the person's usual.
        case more
        /// Nights where it sat below.
        case less

        var word: String { self == .more ? "more" : "less" }
    }

    struct Projection: Identifiable, Hashable, Sendable {
        let lever: TrendEngine.Metric
        let direction: Direction
        let outcome: TrendEngine.Metric

        let leverNights: Int
        let otherNights: Int
        /// Median outcome on the nights meeting the lever condition.
        let outcomeWithLever: Double
        /// Median outcome on the rest.
        let outcomeOtherwise: Double
        let confidence: MetricConfidence

        /// Where the middle 80% of each group's outcomes landed -- the same
        /// 10th–90th percentile band `UncertaintyForecast` reports, so the
        /// two groups can be drawn as two ranges on one axis. Carried for
        /// the view layer only: `delta`, `isImprovement` and `sentence` are
        /// still computed from the medians alone, exactly as before. Two
        /// medians that differ by 4 bpm while both bands span 20 bpm is a
        /// different picture from the same 4 bpm between two bands 5 bpm
        /// wide, and a sentence cannot show that difference.
        let withLeverRange: ClosedRange<Double>
        let otherwiseRange: ClosedRange<Double>

        var id: String { "\(lever.rawValue)-\(direction.rawValue)-\(outcome.rawValue)" }

        var delta: Double { outcomeWithLever - outcomeOtherwise }
        var isImprovement: Bool { outcome.higherIsBetter ? delta > 0 : delta < 0 }

        var sentence: String {
            let better = isImprovement ? "better" : "worse"
            return "On your \(leverNights) nights with \(direction.word) \(lever.label), "
                + "\(outcome.label) was typically \(outcome.formattedMagnitude(abs(delta))) "
                + "\(better) than on the other \(otherNights)."
        }

        /// Travels with every projection. The split is on one variable; the
        /// nights differ on all the others too.
        var caveat: String {
            "These are your real nights, split by \(lever.label) -- not a prediction, "
                + "and not proof. Nights like these usually differ in other ways too."
        }
    }

    // MARK: - Projection

    /// Compares `outcome` between the person's nights where `lever` sat
    /// notably above (or below) their usual, and all their other nights.
    ///
    /// - Returns: `nil` when either group is too small to have a meaningful
    ///   median, when the lever has no spread to split on, or when lever and
    ///   outcome are the same metric -- which would report only that nights
    ///   with more sleep have more sleep.
    static func project(
        nights: [SleepNightFeatures],
        lever: TrendEngine.Metric,
        direction: Direction,
        outcome: TrendEngine.Metric,
        minimumGroupNights: Int = minimumGroupNights
    ) -> Projection? {
        guard lever != outcome else { return nil }

        // Only nights carrying both values can be compared at all; dropping
        // them from one side and not the other would compare two different
        // populations.
        let usable = nights.compactMap { night -> (lever: Double, outcome: Double)? in
            guard let l = lever.value(from: night), let o = outcome.value(from: night) else { return nil }
            return (l, o)
        }
        guard usable.count >= minimumGroupNights * 2 else { return nil }

        let leverValues = usable.map(\.lever)
        var withLever: [Double] = []
        var otherwise: [Double] = []
        for sample in usable {
            guard let z = Statistics.robustZ(sample.lever, in: leverValues) else { return nil }
            let meets = direction == .more ? z >= leverThresholdZ : z <= -leverThresholdZ
            if meets { withLever.append(sample.outcome) } else { otherwise.append(sample.outcome) }
        }

        guard withLever.count >= minimumGroupNights,
              otherwise.count >= minimumGroupNights,
              let a = Statistics.median(withLever),
              let b = Statistics.median(otherwise) else { return nil }

        return Projection(
            lever: lever,
            direction: direction,
            outcome: outcome,
            leverNights: withLever.count,
            otherNights: otherwise.count,
            outcomeWithLever: a,
            outcomeOtherwise: b,
            confidence: confidence(smallestGroup: min(withLever.count, otherwise.count)),
            withLeverRange: middleRange(withLever, fallback: a),
            otherwiseRange: middleRange(otherwise, fallback: b)
        )
    }

    /// 10th–90th percentile of a group, matching `UncertaintyForecast`'s
    /// coverage so the two visuals mean the same thing by "range". Both
    /// groups already cleared `minimumGroupNights`, so the percentiles are
    /// defined; the fallback only guards the type.
    private static func middleRange(_ values: [Double], fallback: Double) -> ClosedRange<Double> {
        guard let lower = Statistics.percentile(values, UncertaintyForecast.lowerPercentile),
              let upper = Statistics.percentile(values, UncertaintyForecast.upperPercentile) else {
            return fallback...fallback
        }
        return min(lower, upper)...max(lower, upper)
    }

    /// Every projection worth showing for one lever, strongest effect first.
    ///
    /// Ranked by effect relative to the outcome's own scale, so metrics in
    /// different units are comparable -- 5 bpm and 5 minutes are not the same
    /// size of finding.
    static func projectAll(
        nights: [SleepNightFeatures],
        lever: TrendEngine.Metric,
        direction: Direction,
        minimumGroupNights: Int = minimumGroupNights
    ) -> [Projection] {
        TrendEngine.Metric.allCases
            .compactMap {
                project(nights: nights, lever: lever, direction: direction,
                        outcome: $0, minimumGroupNights: minimumGroupNights)
            }
            .sorted { relativeEffect($0) > relativeEffect($1) }
    }

    private static func relativeEffect(_ projection: Projection) -> Double {
        abs(projection.delta) / max(abs(projection.outcomeOtherwise), 1)
    }

    /// Confidence from the *smaller* of the two groups -- a comparison is
    /// only as trustworthy as its thinner side, however many nights sit on
    /// the other one.
    private static func confidence(smallestGroup count: Int) -> MetricConfidence {
        switch count {
        case ..<minimumGroupNights: .insufficient
        case minimumGroupNights..<12: .low
        case 12..<20: .moderate
        default: .high
        }
    }
}
