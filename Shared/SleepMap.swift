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

    /// Shrinkage strength, in nights.
    ///
    /// Nine regions competing on their own raw medians is a
    /// winner-selection problem: with four nights each, the region that
    /// wins is usually the one that got lucky, and it will not be the same
    /// region next week. Each region's median is therefore pulled toward
    /// the map's overall median by `k / (n + k)`, so a four-night region
    /// keeps a third of its own signal and a twenty-four-night region keeps
    /// three quarters. Ranking happens on the shrunk value; the sentence
    /// still quotes the region's real median, because that is what those
    /// nights actually were.
    static let shrinkageNights = 8.0

    /// How much two regions' intervals may overlap before the map stops
    /// claiming one is better.
    ///
    /// Measured as a fraction of the narrower interval. Requiring *no*
    /// overlap would silence the map almost permanently -- a bootstrap on
    /// four to eight nights is wide -- while allowing any overlap would let
    /// two indistinguishable regions produce a confident headline. Half is
    /// the point where the two intervals are describing more of the same
    /// range than not.
    static let materialOverlapFraction = 0.5

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

    /// A range the region's true median plausibly sits in.
    struct Interval: Hashable, Sendable {
        let lower: Double
        let upper: Double

        var width: Double { upper - lower }

        /// How much of the narrower of two intervals the two share, 0...1.
        func overlap(with other: Interval) -> Double {
            let shared = min(upper, other.upper) - max(lower, other.lower)
            // `>= 0`, not `> 0`. A zero-width interval sitting inside
            // another shares exactly zero width with it, and rejecting that
            // case here would report *no* overlap for an estimate that is
            // entirely contained -- the opposite of the truth. Genuinely
            // disjoint intervals give a negative share and still return 0.
            guard shared >= 0 else { return 0 }
            let narrower = min(width, other.width)
            // Two point estimates that coincide overlap completely, and a
            // width of zero cannot be divided by.
            guard narrower > 0 else { return 1 }
            return min(1, shared / narrower)
        }
    }

    struct Region: Identifiable, Hashable, Sendable {
        let x: Band
        let y: Band
        let nightCount: Int
        /// The region's own median. `nil` when the region holds fewer than
        /// `minimumRegionNights`. This is what gets quoted -- it is what
        /// those nights actually were.
        let medianOutcome: Double?
        /// The median pulled toward the map's overall median in proportion
        /// to how thin the region is. This is what gets *ranked*, so a
        /// four-night fluke cannot outrank a twenty-night pattern.
        var shrunkOutcome: Double? = nil
        /// Bootstrap interval on the region's median. `nil` for a region
        /// too thin to resample.
        var interval: Interval? = nil

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
        /// Whether the best region is actually separable from the next one.
        ///
        /// False when their intervals overlap materially -- two regions
        /// describing more of the same range than not. The map is still
        /// drawn and the region is still highlighted; what changes is that
        /// it stops being called better, because at that point it has not
        /// been shown to be.
        let headlineIsSupported: Bool

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
            // The spec's own distinction: "this is your ideal zone" from
            // four nights is a claim; "your stronger nights cluster here"
            // is an observation, and it is the only one available while the
            // regions still overlap.
            guard headlineIsSupported else {
                return "Your stronger \(outcome.label) nights cluster around \(where_),"
                    + " but the regions are still close enough that Zoon can't call one better."
            }
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

        // The map's own centre of gravity, and what thin regions are pulled
        // back toward. Taken across every usable night rather than across
        // the region medians, so a single dense region cannot define
        // "typical" for the whole map.
        let overallMedian = Statistics.median(usable.map(\.outcome))

        var regions: [Region] = []
        for x in Band.allCases {
            for y in Band.allCases {
                let key = "\(x.rawValue)-\(y.rawValue)"
                let values = buckets[key] ?? []
                let median = values.count >= minimumRegionNights
                    ? Statistics.median(values)
                    : nil
                var region = Region(
                    x: x, y: y, nightCount: values.count, medianOutcome: median
                )
                if let median, let overallMedian {
                    region.shrunkOutcome = shrink(median, nightCount: values.count, toward: overallMedian)
                }
                if median != nil, let ci = Statistics.pairedBootstrapCI(deltas: values) {
                    region.interval = Interval(lower: ci.lower, upper: ci.upper)
                }
                regions.append(region)
            }
        }

        // `usual` is the densest region; ties break on region id so the same
        // history always produces the same map rather than reshuffling with
        // dictionary order.
        guard let usual = regions.max(by: {
            $0.nightCount == $1.nightCount ? $0.id > $1.id : $0.nightCount < $1.nightCount
        }) else { return nil }

        let scored = regions.filter(\.isScored)
        // Ranked on the shrunk value, so the winner is the region with the
        // strongest *evidence*, not the one that got the luckiest four
        // nights.
        // Ties break on region id, for the same reason `usual` does: the
        // same history must produce the same map every time rather than
        // reshuffling with sort order.
        let ranked = scored.sorted { a, b in
            if isWorse(a, than: b, outcome: outcome) { return false }
            if isWorse(b, than: a, outcome: outcome) { return true }
            return a.id < b.id
        }
        let best: Region? = scored.count >= minimumScoredRegions ? ranked.first : nil

        return Map(
            xAxis: xAxis, yAxis: yAxis, outcome: outcome,
            regions: regions,
            totalNights: usable.count,
            best: best,
            usual: usual,
            confidence: confidence(best: best, scoredRegions: scored.count),
            headlineIsSupported: isSeparated(ranked)
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
        // Falls back to the raw median only when there was no overall
        // median to shrink toward, which means there were no usable outcome
        // values at all -- in which case nothing here is scored anyway.
        guard let lhs = a.shrunkOutcome ?? a.medianOutcome else { return true }
        guard let rhs = b.shrunkOutcome ?? b.medianOutcome else { return false }
        return outcome.higherIsBetter ? lhs < rhs : lhs > rhs
    }

    /// Pulls a thin region's median toward the map's overall median.
    ///
    /// `n / (n + k)` of the region's own signal is kept. Stated as its own
    /// function so the weight can be argued with rather than buried in the
    /// loop that applies it.
    static func shrink(_ median: Double, nightCount: Int, toward overall: Double) -> Double {
        let weight = Double(nightCount) / (Double(nightCount) + shrinkageNights)
        return weight * median + (1 - weight) * overall
    }

    /// Whether the top region is distinguishable from the runner-up.
    ///
    /// A region with no interval -- too thin to resample -- is not treated
    /// as separated. Absence of an interval is absence of evidence, and the
    /// alternative would let the thinnest regions in the map be the ones
    /// that produce confident headlines.
    static func isSeparated(_ ranked: [Region]) -> Bool {
        guard ranked.count >= minimumScoredRegions else { return false }
        guard let best = ranked.first?.interval, let next = ranked.dropFirst().first?.interval else {
            return false
        }
        return best.overlap(with: next) < materialOverlapFraction
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
