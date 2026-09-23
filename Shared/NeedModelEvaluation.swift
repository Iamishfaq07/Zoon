import Foundation

/// Checks the sleep-debt model against how people said they felt.
///
/// **What this is for.** `SleepDebtCalculator`'s decay (0.933 a night) and the
/// two repayment rules -- `SleepNeed`'s 33% up to 90 minutes, which *assesses*
/// a night, and `SleepAutopilot`'s 25% up to 30, which *plans* one -- are
/// modelling choices, not measurements. The release brief is explicit that
/// they must not be changed because another app uses different numbers. The
/// honest step before any change is to measure whether the shortfall the model
/// reports actually tracks anything the person experiences.
///
/// This does that and nothing else. It never adjusts a coefficient. It pairs
/// each night's reported shortfall with that morning's restedness rating,
/// counts what was missing, and reports the rank correlation overall and per
/// stratum (device/source, stage coverage, shift work, time-zone change), so
/// a model that only works for Watch nights, or only for day workers, shows up
/// as exactly that.
///
/// **What it cannot say.** A correlation between a modelled shortfall and a
/// self-rating is association on observational data. It cannot validate the
/// model and it is not a clinical measure. The minimum sample below is set so
/// the result at least is not noise.
enum NeedModelEvaluation {

    /// One night's model output and what the person reported.
    struct Night: Sendable, Hashable {
        /// The shortfall the model reported going into the morning.
        let shortfallMinutes: Double?
        /// The morning restedness rating, 1 (not at all) to 5 (fully).
        let restedRating: Int?
        /// A label for the slice this night belongs to: source, staging,
        /// shift or travel. Free text so new strata need no schema change.
        let stratum: String
    }

    struct Summary: Sendable, Hashable {
        let stratum: String
        /// Nights offered.
        let nights: Int
        /// Nights with both a shortfall and a rating.
        let usable: Int
        /// Nights missing one or both.
        var missing: Int { nights - usable }
        /// Spearman's rank correlation of shortfall against restedness.
        /// Negative is the direction the model predicts: more shortfall,
        /// less rested. `nil` below `minimumUsable` or with no variation.
        let rankCorrelation: Double?
    }

    /// Pairs needed before a correlation is reported at all. At twenty the
    /// 95% interval on a rank correlation is still roughly ±0.4; below it the
    /// number is not worth printing.
    static let minimumUsable = 20

    /// Overall first, then each stratum, largest first.
    static func evaluate(_ nights: [Night]) -> [Summary] {
        let overall = summarize(nights, stratum: "All nights")
        let strata = Dictionary(grouping: nights, by: \.stratum)
            .map { summarize($0.value, stratum: $0.key) }
            .sorted { $0.nights == $1.nights ? $0.stratum < $1.stratum : $0.nights > $1.nights }
        return [overall] + strata
    }

    static func summarize(_ nights: [Night], stratum: String) -> Summary {
        let pairs: [(Double, Double)] = nights.compactMap { night in
            guard let shortfall = night.shortfallMinutes, shortfall.isFinite,
                  let rating = night.restedRating, (1...5).contains(rating) else { return nil }
            return (shortfall, Double(rating))
        }
        let correlation = pairs.count >= minimumUsable
            ? spearman(pairs.map(\.0), pairs.map(\.1))
            : nil
        return Summary(stratum: stratum, nights: nights.count, usable: pairs.count, rankCorrelation: correlation)
    }

    /// Spearman's rho with average ranks for ties. `nil` when either side
    /// has no variation, where a correlation is undefined rather than zero.
    static func spearman(_ x: [Double], _ y: [Double]) -> Double? {
        guard x.count == y.count, x.count >= 3 else { return nil }
        let rx = ranks(x), ry = ranks(y)
        let mx = rx.reduce(0, +) / Double(rx.count)
        let my = ry.reduce(0, +) / Double(ry.count)
        var num = 0.0, dx = 0.0, dy = 0.0
        for i in rx.indices {
            let a = rx[i] - mx, b = ry[i] - my
            num += a * b; dx += a * a; dy += b * b
        }
        guard dx > 0, dy > 0 else { return nil }
        return num / (dx * dy).squareRoot()
    }

    private static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var result = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < order.count {
            var j = i
            while j + 1 < order.count, values[order[j + 1]] == values[order[i]] { j += 1 }
            let average = Double(i + j) / 2 + 1
            for k in i...j { result[order[k]] = average }
            i = j + 1
        }
        return result
    }
}
