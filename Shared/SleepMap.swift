import Foundation

/// The territory a person's nights actually occupy, and which part of it
/// their best nights come from.
///
/// Every other engine here reduces sleep to one dimension at a time:
/// `TrendEngine` reports that bedtime drifted later, `ZoonTwin` splits
/// history on a single lever. But "later bedtime is worse" and "shorter
/// sleep is worse" are not independent facts -- a late night that still runs
/// long is a different night from a late night cut short, and a
/// one-dimensional summary averages the two together into a number
/// describing neither.
///
/// This bins the person's nights on **two** axes at once and reports the
/// median outcome in each region. The bands are cut from their own history
/// rather than from clock times or guideline durations, so "earlier" means
/// earlier *for them*: a 2am sleeper's early nights and a 10pm sleeper's
/// late ones can both be described without either being told they are doing
/// it wrong.
///
/// **Descriptive, not prescriptive.** A region where their best nights
/// happen to sit is not an instruction to move there, and this cannot tell
/// them whether the region caused the outcome or merely coincided with it --
/// the good nights in a region may all be weekends. The copy says so.
enum SleepMap {

    /// Nights before a two-dimensional map is worth drawing at all.
    ///
    /// Nine regions need materially more history than a one-dimensional
    /// split does: 28 nights averages barely three per region, and only the
    /// populated ones will clear `minimumRegionNights`. This is the floor
    /// for attempting a map, not a promise that it will be a full one.
    static let minimumNights = 28

    /// Nights inside one region before its outcome is reported.
    ///
    /// Below this a region is still drawn -- it is part of where they sleep
    /// -- but carries no median and can never be ranked. A "best region"
    /// chosen from two nights is a coin toss dressed up as a finding.
    static let minimumRegionNights = 4

    /// Scored regions needed before one can be called best. With only one,
    /// there is nothing to be better than.
    static let minimumScoredRegions = 2

    // MARK: - Bands

    /// Which third of the person's own range a night sits in on one axis.
    enum Band: Int, CaseIterable, Hashable, Sendable {
        case low, middle, high

        /// Wording depends on the axis: a low bedtime is "earlier", a low
        /// duration is "shorter". `middle` is deliberately "usual" rather
        /// than "average" -- it is the middle third of their nights, not a
        /// mean, and not a target.
        func phrase(for metric: TrendEngine.Metric) -> String {
            switch self {
            case .low: metric.lowerWord
            case .middle: "usual"
            case .high: metric.higherWord
            }
        }
    }

    // MARK: - Regions

    struct Region: Identifiable, Hashable, Sendable {
        let x: Band
        let y: Band
        let nightCount: Int
        /// `nil` when the region holds fewer than `minimumRegionNights`.
        let medianOutcome: Double?

        var id: String { "\(x.rawValue)-\(y.rawValue)" }
        var isScored: Bool { medianOutcome != nil }
    }

    struct Map: Hashable, Sendable {
        let xAxis: TrendEngine.Metric
        let yAxis: TrendEngine.Metric
        let outcome: TrendEngine.Metric
        /// All nine regions, including the empty ones -- the gaps in where
        /// someone sleeps are part of the picture.
        let regions: [Region]
        let totalNights: Int
        /// Best-scoring region, respecting whether the outcome is better
        /// high or low. `nil` when fewer than `minimumScoredRegions` were
        /// dense enough to score.
        let best: Region?
        /// The region holding the most nights, scored or not.
        let usual: Region
        let confidence: MetricConfidence

        /// True when their best-scoring region is the one they already sleep
        /// in most. Worth saying plainly rather than dressing an unchanged
        /// pattern up as a discovery.
        var bestIsAlreadyUsual: Bool {
            guard let best else { return false }
            return best.id == usual.id
        }

        var scoredRegions: [Region] { regions.filter(\.isScored) }

        var sentence: String {
            guard let best, let median = best.medianOutcome else {
                return "Not enough nights in any one part of your \(xAxis.axisLabel)"
                    + " and \(yAxis.axisLabel) range to compare them yet."
            }
            let where_ = "\(best.x.phrase(for: xAxis)) \(xAxis.axisLabel)"
                + " with \(best.y.phrase(for: yAxis)) \(yAxis.axisLabel)"
            if bestIsAlreadyUsual {
                return "Your best \(outcome.label) comes from \(where_) --"
                    + " which is already where most of your nights sit"
                    + " (\(outcome.formattedMagnitude(median)) across \(best.nightCount) nights)."
            }
            return "Your best \(outcome.label) comes from \(where_):"
                + " \(outcome.formattedMagnitude(median)) across \(best.nightCount) nights."
        }

        /// Travels with the map. Two axes still leave every other difference
        /// between nights uncontrolled.
        var caveat: String {
            "This is a map of nights you have already had, not a target."
                + " Regions differ in more than \(xAxis.axisLabel) and \(yAxis.axisLabel),"
                + " and a thin region says more about where you rarely sleep than about what works."
        }
    }

    // MARK: - Building

    /// Bins `nights` into a 3x3 grid on `xAxis` and `yAxis`, cut at the
    /// person's own terciles, and reports the median `outcome` per region.
    ///
    /// - Returns: `nil` when there is too little history, when the three
    ///   metrics are not distinct, or when either axis has no spread to cut
    ///   -- a flat axis would drop every night into one band and produce a
    ///   grid with a single occupied column.
    static func build(
        nights: [SleepNightFeatures],
        xAxis: TrendEngine.Metric,
        yAxis: TrendEngine.Metric,
        outcome: TrendEngine.Metric,
        minimumNights: Int = minimumNights,
        minimumRegionNights: Int = minimumRegionNights
    ) -> Map? {
        guard xAxis != yAxis, xAxis != outcome, yAxis != outcome else { return nil }

        // A night missing any of the three values cannot be placed or
        // scored; dropping it from the outcome but keeping it in the counts
        // would make a region look denser than the number it reports.
        let usable = nights.compactMap { night -> (x: Double, y: Double, outcome: Double)? in
            guard let x = xAxis.value(from: night),
                  let y = yAxis.value(from: night),
                  let o = outcome.value(from: night) else { return nil }
            return (x, y, o)
        }
        guard usable.count >= minimumNights else { return nil }

        guard let xCuts = terciles(usable.map(\.x)),
              let yCuts = terciles(usable.map(\.y)) else { return nil }

        var buckets: [String: [Double]] = [:]
        var occupiedX: Set<Band> = []
        var occupiedY: Set<Band> = []
        for sample in usable {
            let x = band(sample.x, cuts: xCuts)
            let y = band(sample.y, cuts: yCuts)
            occupiedX.insert(x)
            occupiedY.insert(y)
            buckets["\(x.rawValue)-\(y.rawValue)", default: []].append(sample.outcome)
        }

        // A cut landing exactly on a repeated value leaves one band empty --
        // the grid is then a 2x3 wearing a 3x3's label, and its "thirds" are
        // not thirds. That happens when a third or more of the nights share
        // one value on an axis, which is a real property of the history, not
        // a rounding artifact, so the honest answer is to decline the map
        // rather than draw a lopsided one.
        guard occupiedX.count == Band.allCases.count,
              occupiedY.count == Band.allCases.count else { return nil }

        var regions: [Region] = []
        for x in Band.allCases {
            for y in Band.allCases {
                let key = "\(x.rawValue)-\(y.rawValue)"
                let values = buckets[key] ?? []
                let median = values.count >= minimumRegionNights
                    ? Statistics.median(values)
                    : nil
                regions.append(Region(
                    x: x, y: y, nightCount: values.count, medianOutcome: median
                ))
            }
        }

        // `usual` is the densest region; ties break on region id so the same
        // history always produces the same map rather than reshuffling with
        // dictionary order.
        guard let usual = regions.max(by: {
            $0.nightCount == $1.nightCount ? $0.id > $1.id : $0.nightCount < $1.nightCount
        }) else { return nil }

        let scored = regions.filter(\.isScored)
        let best: Region? = scored.count >= minimumScoredRegions
            ? scored.max(by: { isWorse($0, than: $1, outcome: outcome) })
            : nil

        return Map(
            xAxis: xAxis, yAxis: yAxis, outcome: outcome,
            regions: regions,
            totalNights: usable.count,
            best: best,
            usual: usual,
            confidence: confidence(best: best, scoredRegions: scored.count)
        )
    }

    // MARK: - Internals

    /// Cut points at the 33rd and 67th percentile of the person's own
    /// values. `nil` when the two cuts coincide, which means a third or more
    /// of the nights share one value and the axis cannot be split into
    /// thirds at all.
    private static func terciles(_ values: [Double]) -> (Double, Double)? {
        guard let low = Statistics.percentile(values, 100.0 / 3),
              let high = Statistics.percentile(values, 200.0 / 3),
              high > low else { return nil }
        return (low, high)
    }

    private static func band(_ value: Double, cuts: (Double, Double)) -> Band {
        if value < cuts.0 { return .low }
        if value < cuts.1 { return .middle }
        return .high
    }

    /// Ordering predicate for `max(by:)`: true when `a` is the worse of the
    /// two, so the maximum is the best region under the outcome's own
    /// direction. Unscored regions are never better than a scored one.
    private static func isWorse(
        _ a: Region, than b: Region, outcome: TrendEngine.Metric
    ) -> Bool {
        guard let lhs = a.medianOutcome else { return true }
        guard let rhs = b.medianOutcome else { return false }
        return outcome.higherIsBetter ? lhs < rhs : lhs > rhs
    }

    /// Confidence is bounded by the winning region's own depth, then capped
    /// by how many regions it actually beat. A region that outscored one
    /// other region has not been shown to be the best of nine.
    private static func confidence(best: Region?, scoredRegions: Int) -> MetricConfidence {
        guard let best, best.isScored else { return .insufficient }
        let depth: MetricConfidence = switch best.nightCount {
        case ..<minimumRegionNights: .insufficient
        case minimumRegionNights..<8: .low
        case 8..<15: .moderate
        default: .high
        }
        let breadth: MetricConfidence = scoredRegions >= 4 ? .high : .low
        return min(depth, breadth)
    }
}

private extension TrendEngine.Metric {
    /// Noun for this metric when it names an axis of the map. Distinct from
    /// `label` because that reads as a summary ("average sleep duration"),
    /// which turns into "longer average sleep duration" once a comparative
    /// is attached to it.
    var axisLabel: String {
        self == .duration ? "sleep duration" : label
    }

    /// Comparative word for the low end of this metric's range.
    var lowerWord: String {
        switch self {
        case .duration: "shorter"
        case .bedtime: "earlier"
        case .hrv, .restingHeartRate, .efficiency, .sleepDebt: "lower"
        }
    }

    var higherWord: String {
        switch self {
        case .duration: "longer"
        case .bedtime: "later"
        case .hrv, .restingHeartRate, .efficiency, .sleepDebt: "higher"
        }
    }
}
