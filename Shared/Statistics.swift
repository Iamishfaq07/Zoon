import Foundation

/// Deterministic robust-statistics primitives, shared by every engine that
/// compares a night against personal history.
///
/// Median/MAD rather than mean/SD throughout: a single bad night (a stomach
/// bug, a red-eye flight) shouldn't be able to drag a rolling average around
/// and quietly redefine "normal" for the two weeks after it. A median barely
/// moves; a mean does.
enum Statistics {

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Median absolute deviation — the robust analogue of standard deviation.
    static func medianAbsoluteDeviation(_ values: [Double], median: Double? = nil) -> Double? {
        guard !values.isEmpty else { return nil }
        guard let center = median ?? Self.median(values) else { return nil }
        let deviations = values.map { abs($0 - center) }
        return Self.median(deviations)
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let m = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let rank = p / 100 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        guard lower != upper else { return sorted[lower] }
        let fraction = rank - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    /// Robust z-score: how many (scaled) MADs `value` sits from the sample's
    /// median. 0.6745 makes the MAD comparable in scale to a standard
    /// deviation under a normal distribution, so the usual "±2 is unusual"
    /// intuition still roughly applies.
    ///
    /// Falls back to IQR, then to plain standard deviation, rather than
    /// dividing by a near-zero MAD -- a metric that's been nearly identical
    /// every night (MAD ≈ 0) would otherwise turn any tiny wobble into an
    /// enormous, meaningless z-score.
    static func robustZ(_ value: Double, in values: [Double]) -> Double? {
        guard values.count >= 3, let med = median(values) else { return nil }

        if let mad = medianAbsoluteDeviation(values, median: med), mad > 0.01 {
            return 0.6745 * (value - med) / mad
        }
        if let p25 = percentile(values, 25), let p75 = percentile(values, 75) {
            let iqr = p75 - p25
            if iqr > 0.01 { return (value - med) / (iqr / 1.349) }
        }
        if let sd = standardDeviation(values), sd > 0.01 {
            return (value - (mean(values) ?? med)) / sd
        }
        return nil
    }

    /// Piecewise-linear interpolation across a set of (x, y) anchors, sorted
    /// ascending by x. Clamps to the first/last anchor's y outside the range.
    /// Every score curve in `SleepIntelligenceScore` is one of these rather
    /// than an inline formula, so the anchors are the whole story and can be
    /// read, argued with, and tuned in one place.
    static func interpolate(_ x: Double, anchors: [(x: Double, y: Double)]) -> Double {
        guard !anchors.isEmpty else { return 0 }
        let sorted = anchors.sorted { $0.x < $1.x }
        if x <= sorted.first!.x { return sorted.first!.y }
        if x >= sorted.last!.x { return sorted.last!.y }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            if x >= a.x && x <= b.x {
                guard b.x > a.x else { return a.y }
                let fraction = (x - a.x) / (b.x - a.x)
                return a.y + (b.y - a.y) * fraction
            }
        }
        return sorted.last!.y
    }

    /// Minutes-from-midnight for a wall-clock time, shifted so evening times
    /// plot as negative -- the convention every regularity/circadian
    /// calculation in this app already shares (see
    /// `DayContextBuilder.shiftedBedtimeHour`), restated here in minutes for
    /// the statistics that want finer resolution than a fractional hour.
    static func circularMinutesFromMidnight(_ date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return minutes >= 18 * 60 ? minutes - 24 * 60 : minutes
    }
}
