import Foundation

/// Finds *when* a metric shifted regime, not just whether the last two weeks
/// differ from the two before them.
///
/// `TrendEngine` answers "is the current window different from the previous
/// one" against a fixed, caller-chosen split. That is the right question for
/// a dashboard, and the wrong one for "something changed -- when?": a shift
/// that happened 40 nights ago sits entirely inside both of `TrendEngine`'s
/// windows and reads as no change at all, while a shift halfway through the
/// current window is diluted by the half that predates it. This scans every
/// admissible split point instead and reports the strongest one, so the
/// answer carries a date.
///
/// Deliberately single change point. A multiple-change-point search
/// (PELT, binary segmentation) fits far more structure than 60-odd noisy
/// nights can actually support, and every extra reported "change" is another
/// chance to tell someone their sleep changed on a night nothing happened.
/// One well-evidenced date is worth more than a timeline of maybes.
///
/// Robust throughout -- medians and MAD, never mean and standard deviation.
/// One travel night or one illness spike would otherwise drag a mean far
/// enough to invent a change point that isn't there, which is the same
/// reasoning `Statistics.robustZ` and `JournalCorrelator` already follow.
enum ChangePointDetector {

    /// Nights required on *each* side of a candidate split.
    ///
    /// Matches `GuidedExperiment.minimumPeriodNights` for the same reason it
    /// does: a median drawn from two or three nights is not a level, it is
    /// noise, and a "change point" between two such medians is an artifact of
    /// where the window happened to land.
    static let minimumSegmentNights = 7

    /// How many standard errors the two segment medians must separate before
    /// this is called a change rather than drift.
    ///
    /// 3.0, not the ~2.0 a single planned comparison would justify: this
    /// *scans* every admissible split and reports the largest, and the
    /// maximum of forty-odd correlated statistics runs well above what any
    /// one of them would. Treating a scan's winner as though it were a single
    /// pre-planned test is the same multiple-comparisons trap
    /// `GuidedExperiment` documents for post-hoc metric picking.
    static let minimumEffect = 3.0

    /// Scales MAD onto the same footing as a standard deviation for normally
    /// distributed data (1 / 0.6745). `Statistics.robustZ` uses the same
    /// constant from the other direction.
    private static let madToSigma = 1.4826

    /// Asymptotic ratio of a median's standard error to a mean's, for
    /// normally distributed data (sqrt(pi / 2)). A median is the robust
    /// choice here but it pays for that with a wider sampling distribution,
    /// and pretending otherwise would make short segments look far more
    /// certain than they are.
    private static let medianStandardErrorFactor = 1.2533

    struct Result: Identifiable, Hashable {
        let metric: TrendEngine.Metric
        /// The night the new level begins -- the first night of the "after"
        /// segment, not the last of the "before" one.
        let date: Date
        let beforeMedian: Double
        let afterMedian: Double
        let beforeNights: Int
        let afterNights: Int
        /// Separation between the two levels, in standard errors of the
        /// difference between the segment medians.
        let effect: Double

        var id: String { "\(metric.rawValue)@\(date.timeIntervalSince1970)" }

        var delta: Double { afterMedian - beforeMedian }
        var isImprovement: Bool { metric.higherIsBetter ? delta > 0 : delta < 0 }

        var sentence: String {
            let direction = delta > 0 ? "rose" : "fell"
            let magnitude = metric.formattedMagnitude(abs(delta))
            return "Your \(metric.label) \(direction) by \(magnitude) starting around "
                + date.formatted(.dateTime.month(.abbreviated).day())
                + ", and has stayed there since."
        }
    }

    // MARK: - Detection

    /// Scans one metric across `nights` for its strongest single change point.
    ///
    /// - Returns: `nil` when there is too little history, when no split
    ///   separates the levels by more than the within-segment noise, or when
    ///   the shift is real but too small to be worth a sentence (the metric's
    ///   own `clearsThreshold`, shared with `TrendEngine` rather than
    ///   re-tuned here).
    static func detect(
        nights: [SleepNightFeatures],
        metric: TrendEngine.Metric,
        minimumSegmentNights: Int = minimumSegmentNights,
        minimumEffect: Double = minimumEffect
    ) -> Result? {
        // Nights missing this metric are dropped rather than interpolated: a
        // gap is missing data, and inventing a value for it would let a run
        // of unmeasured nights manufacture a level change.
        let samples = nights
            .sorted { $0.date < $1.date }
            .compactMap { night -> (date: Date, value: Double)? in
                metric.value(from: night).map { (night.date, $0) }
            }

        guard samples.count >= minimumSegmentNights * 2 else { return nil }
        let values = samples.map(\.value)

        var best: Result?
        for split in minimumSegmentNights...(samples.count - minimumSegmentNights) {
            let before = Array(values[..<split])
            let after = Array(values[split...])
            guard let beforeMedian = Statistics.median(before),
                  let afterMedian = Statistics.median(after) else { continue }

            let effect = separation(before: before, after: after,
                                    beforeMedian: beforeMedian, afterMedian: afterMedian)
            guard effect >= minimumEffect else { continue }
            guard metric.clearsThreshold(afterMedian - beforeMedian,
                                         previousMedian: beforeMedian) else { continue }
            guard effect > (best?.effect ?? 0) else { continue }

            best = Result(
                metric: metric,
                date: samples[split].date,
                beforeMedian: beforeMedian,
                afterMedian: afterMedian,
                beforeNights: before.count,
                afterNights: after.count,
                effect: effect
            )
        }
        return best
    }

    /// Every metric's strongest change point, sorted by effect.
    static func detectAll(
        nights: [SleepNightFeatures],
        minimumSegmentNights: Int = minimumSegmentNights,
        minimumEffect: Double = minimumEffect
    ) -> [Result] {
        TrendEngine.Metric.allCases
            .compactMap {
                detect(nights: nights, metric: $0,
                       minimumSegmentNights: minimumSegmentNights,
                       minimumEffect: minimumEffect)
            }
            .sorted { $0.effect > $1.effect }
    }

    // MARK: - Effect size

    /// Separation between the two segment medians, in standard errors.
    ///
    /// Two things this deliberately accounts for that a raw
    /// difference-over-spread ratio does not:
    ///
    /// 1. **Segment size.** The standard error carries `1/n` from each side,
    ///    so a split that leaves only the minimum seven nights on one end is
    ///    held to a much larger raw difference than an even one. Without this
    ///    the scan reliably "finds" its strongest change at whichever edge
    ///    happened to draw a lopsided handful of nights.
    /// 2. **Median inflation.** A median's standard error is wider than a
    ///    mean's by `medianStandardErrorFactor`.
    ///
    /// Noise is taken from the noisier of the two segments rather than from
    /// the series as a whole: a series-wide spread includes the very shift
    /// being tested, which inflates the denominator and hides exactly the
    /// large, clean step changes this is meant to find.
    private static func separation(
        before: [Double], after: [Double],
        beforeMedian: Double, afterMedian: Double
    ) -> Double {
        let delta = abs(afterMedian - beforeMedian)
        let spreads = [
            Statistics.medianAbsoluteDeviation(before, median: beforeMedian),
            Statistics.medianAbsoluteDeviation(after, median: afterMedian)
        ].compactMap { $0 }
        let sigma = (spreads.max() ?? 0) * madToSigma

        // A perfectly flat pair of segments has no noise to normalize by. A
        // real step between them is then as separated as it is possible to
        // be, rather than undefined -- but an identical pair is still no
        // change at all, so zero delta stays zero.
        guard sigma > 0 else { return delta > 0 ? .infinity : 0 }
        guard !before.isEmpty, !after.isEmpty else { return 0 }

        let standardError = sigma * medianStandardErrorFactor
            * (1 / Double(before.count) + 1 / Double(after.count)).squareRoot()
        guard standardError > 0 else { return delta > 0 ? .infinity : 0 }
        return delta / standardError
    }
}
