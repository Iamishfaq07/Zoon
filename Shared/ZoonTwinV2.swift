import Foundation

/// The Twin, estimated rather than described.
///
/// ## What was wrong with V1
///
/// `ZoonTwin` splits the history on one lever and compares the two medians.
/// Its own doc comment is honest that this is not causal, and that honesty is
/// the right instinct -- but three things about it make the number weaker
/// than it looks on screen.
///
/// The groups are not comparable. Nights with much more sleep than usual are
/// disproportionately weekends, and a weekend differs from a Tuesday in every
/// way at once. Splitting on the lever compares those two populations and
/// attributes the whole gap to the lever.
///
/// There is no interval on the difference. V1 reports each group's own
/// 10th-90th band, which describes how the two groups are spread, not how
/// precisely their gap is known. Two medians four apart with a gap that could
/// plausibly be anywhere from minus six to plus fourteen is not a finding,
/// and nothing in V1 can say so.
///
/// The outcome is chosen after the fact. `projectAll` ranks every outcome by
/// effect size and the screen shows the strongest, which is selection on the
/// result -- the single most reliable way to manufacture an effect out of
/// noise.
///
/// ## What V2 does
///
/// Matched pairs. Each night meeting the lever condition is paired with the
/// most similar night that does not, on the things that were true *before*
/// the night: exactly the same day shape, and close on the remaining
/// pre-night context and on when in the person's history it happened. Pairs
/// further apart than `caliper` are not made at all -- an unmatched night is
/// dropped and counted, rather than compared to something unlike it.
///
/// Then it checks its own work. Balance is measured on every covariate after
/// matching, and an estimate whose matched groups still differ is refused.
/// So is one whose two sides come from different stretches of the person's
/// history, because baselines drift.
///
/// The difference is a median over the pairs, with a 95% percentile bootstrap
/// interval resampling *pairs* -- the unit that was matched. An interval
/// spanning zero is reported as spanning zero, not rounded up into a claim.
///
/// And the outcome is fixed in advance: `preselectedOutcome`, the same one
/// for every lever, chosen once and not per screen.
///
/// ## Refusing is the answer, not the failure
///
/// The spec is explicit about this and it is the part most likely to be
/// mistaken for a bug: *"Zoon doesn't have enough comparable no-caffeine
/// nights to estimate this yet. That is a FEATURE, not a failure."*
/// `Unsupported` carries which check stopped it and says so in the person's
/// own terms.
///
/// ## What this still is not
///
/// It is not a randomised comparison. Matching balances what it was given;
/// it can do nothing about what was never measured. Somebody who sleeps
/// longer on the nights they feel well has a reason for the extra sleep that
/// no covariate here captures. `caveat` says this every time, and
/// `GuidedExperiment` -- which assigns the condition rather than observing it
/// -- remains the stronger instrument.
///
/// ## Measured before it was written
///
/// Simulated over 200 synthetic histories per condition, at 60/90/120
/// nights, against an outcome generated with and without a real dependence
/// on the lever. Under the null, 6-7% of supported estimates had an interval
/// excluding zero -- close to the 5% the interval nominally promises, and
/// what a percentile bootstrap on a median is expected to give. With a real
/// effect present, 28% (60 nights), 38% (90) and 54% (120). Support itself
/// was refused in 24% of runs at 60 nights and 0% at 120, almost entirely on
/// the balance check.
enum ZoonTwinV2 {

    // MARK: - Thresholds

    /// Matched pairs required before an estimate is offered.
    ///
    /// Higher than a bootstrap strictly needs, because the interval is only
    /// as meaningful as the matching under it: ten pairs that survived the
    /// caliper is a real comparison, three is a coincidence with an interval
    /// drawn around it.
    static let minimumPairs = 10

    /// How far apart two nights may sit on the covariates and still be
    /// paired, in mean scaled units -- the same scale-per-unit idea
    /// `ContextForecast.distance` uses, so "close" means a comparable amount
    /// of real difference across metrics.
    static let caliper = 0.5

    /// Standardised mean difference above which the matched groups are
    /// declared still different on a covariate, and the estimate refused.
    /// 0.25 is the conventional line in the matching literature and is
    /// stricter than the 0.1 sometimes used only because the samples here
    /// are a few dozen nights, not a few thousand patients.
    static let maximumStandardisedDifference = 0.25

    /// How far apart the two sides' mean position in the history may sit.
    ///
    /// A person's baseline moves. A comparison that draws its treated nights
    /// from March and its controls from December is partly a comparison of
    /// two versions of that person.
    static let maximumEraGapDays = 45.0

    /// Reuses V1's threshold so the two engines split the history the same
    /// way. Only what happens after the split differs.
    static let leverThresholdZ = ZoonTwin.leverThresholdZ

    /// The outcome every lever is estimated against, fixed here rather than
    /// chosen per question.
    ///
    /// Choosing per lever, or per screen, or by which came out strongest, is
    /// selection on the outcome. One outcome, decided in advance and written
    /// down in the source, is the only version of this that a person can
    /// trust. It is the recovery signal because that is the outcome none of
    /// the levers is.
    static let preselectedOutcome = TrendEngine.Metric.hrv

    /// One unit of real difference, per metric, for the covariate distance.
    static func scale(for metric: TrendEngine.Metric) -> Double {
        switch metric {
        case .duration: 60
        case .bedtime: 60
        case .hrv: 12
        case .restingHeartRate: 6
        case .efficiency: 6
        case .sleepDebt: 120
        }
    }

    /// Days of history that count as one unit of distance.
    static let eraScale = 30.0

    /// What the pairs are matched on, besides the day's shape.
    ///
    /// Only things settled *before* the night: what the person was carrying
    /// into it, and when they chose to go to bed. Duration, efficiency, HRV
    /// and resting heart rate are all properties of the night itself. Matching
    /// on one of those would, when the lever is bedtime, be matching on a step
    /// between the lever and the outcome -- which removes part of the very
    /// effect being estimated rather than a confound.
    static func covariates(lever: TrendEngine.Metric) -> [TrendEngine.Metric] {
        [.sleepDebt, .bedtime].filter { $0 != lever }
    }

    // MARK: - Why an estimate was not made

    /// The check that stopped the estimate, and how to say it.
    enum Unsupported: Hashable, Sendable {
        /// A lever compared against itself reports only that longer nights
        /// are longer.
        case sameMetric
        case notEnoughNights(have: Int, need: Int)
        /// The lever never varied enough to divide the history at all.
        case noContrast
        case notEnoughComparableNights(matched: Int, need: Int)
        case unbalanced(TrendEngine.Metric)
        case differentEras(daysApart: Int)

        /// Written as a statement about the evidence, never as an error. The
        /// person did nothing wrong and nothing is broken.
        var message: String {
            switch self {
            case .sameMetric:
                "That comparison would only report that these nights are these nights."
            case let .notEnoughNights(have, need):
                "Zoon has \(have) night\(have == 1 ? "" : "s") it can use here and needs about \(need)."
            case .noContrast:
                "Your nights have been too alike on this for Zoon to split them into two groups."
            case let .notEnoughComparableNights(matched, need):
                "Zoon found only \(matched) close comparison\(matched == 1 ? "" : "s") for those nights and needs \(need). "
                    + "It will not pair a night with one that was unlike it."
            case let .unbalanced(metric):
                "The two sets of nights still differ on \(metric.label), so a difference between them "
                    + "would not be about this."
            case let .differentEras(days):
                "Those two sets of nights sit about \(days) days apart in your history, far enough that "
                    + "your baseline may have moved between them."
            }
        }

        /// True for the reasons more nights will eventually solve, so the UI
        /// can say "yet" honestly and not say it when it is not true.
        var improvesWithMoreNights: Bool {
            switch self {
            case .sameMetric: false
            case .notEnoughNights, .noContrast, .notEnoughComparableNights, .unbalanced, .differentEras: true
            }
        }
    }

    // MARK: - What an estimate looks like

    /// One covariate, after matching.
    struct Balance: Hashable, Sendable, Identifiable {
        let metric: TrendEngine.Metric
        /// Difference in means between the matched sides, in pooled standard
        /// deviations. Signed, so the direction of any residual imbalance is
        /// visible rather than only its size.
        let standardisedDifference: Double

        var id: String { metric.rawValue }
        var isBalanced: Bool { abs(standardisedDifference) <= ZoonTwinV2.maximumStandardisedDifference }
    }

    struct Estimate: Hashable, Sendable, Identifiable {
        let lever: TrendEngine.Metric
        let direction: ZoonTwin.Direction
        let outcome: TrendEngine.Metric

        /// Nights that met the lever condition, before matching.
        let candidateNights: Int
        /// Pairs that survived the caliper. Always at most `candidateNights`,
        /// and the gap between the two is the support the matching had to
        /// throw away -- shown, not hidden.
        let pairs: Int

        /// Median of the paired differences: the outcome on the lever night
        /// minus the outcome on its match.
        let difference: Double
        let lower: Double
        let upper: Double
        let confidence: MetricConfidence
        let balance: [Balance]

        var id: String { "\(lever.rawValue)-\(direction.rawValue)-\(outcome.rawValue)" }

        /// Whether the interval excludes zero. An interval spanning zero is
        /// an answer -- "Zoon cannot tell which way this goes" -- and must
        /// never be rendered as a small effect.
        var isDecisive: Bool { lower > 0 || upper < 0 }

        /// nil rather than false when the interval spans zero, so no caller
        /// can accidentally print "worse" for "cannot tell".
        var isImprovement: Bool? {
            guard isDecisive else { return nil }
            return outcome.higherIsBetter ? difference > 0 : difference < 0
        }

        var nightsDropped: Int { max(0, candidateNights - pairs) }

        /// A bound of the interval, with its sign in front of a magnitude.
        ///
        /// Not `formattedMagnitude(lower)` directly: three of the six metrics
        /// format through `SleepNightFeatures.formatMinutes`, which is written
        /// for a duration and has no defined reading for a negative one. A
        /// bound below zero is ordinary here -- it is most of what an
        /// inconclusive interval looks like.
        func formattedBound(_ value: Double) -> String {
            let magnitude = outcome.formattedMagnitude(abs(value))
            if value > 0 { return "+\(magnitude)" }
            if value < 0 { return "-\(magnitude)" }
            return "no change"
        }

        var sentence: String {
            let magnitude = outcome.formattedMagnitude(abs(difference))
            let interval = "\(formattedBound(lower)) to \(formattedBound(upper))"
            guard let isImprovement else {
                return "Across \(pairs) matched pairs of your own nights, \(outcome.label) differed by "
                    + "\(magnitude) with \(direction.word) \(lever.label) -- but the range around that "
                    + "difference (\(interval)) includes no change at all, so Zoon cannot say which way it goes."
            }
            return "Across \(pairs) matched pairs of your own nights, \(outcome.label) was typically "
                + "\(magnitude) \(isImprovement ? "better" : "worse") with \(direction.word) "
                + "\(lever.label) (\(interval))."
        }

        var caveat: String {
            "Each of those nights was paired with a night of the same shape, similar sleep debt and "
                + "bedtime, from a similar stretch of your history. That removes the differences Zoon "
                + "can measure, not the ones it cannot -- there is usually a reason a night was "
                + "different, and Zoon does not know it. A guided experiment, where you choose the "
                + "condition in advance, is stronger evidence than this."
        }
    }

    enum Result: Hashable, Sendable {
        case estimated(Estimate)
        case unsupported(Unsupported)

        var estimate: Estimate? {
            if case let .estimated(estimate) = self { return estimate }
            return nil
        }

        var refusal: Unsupported? {
            if case let .unsupported(reason) = self { return reason }
            return nil
        }
    }

    // MARK: - Estimating

    /// One night, reduced to what the matching needs.
    private struct Candidate {
        let isWeekend: Bool
        /// Days from the earliest usable night, so era is a number the same
        /// scale logic can use.
        let era: Double
        let covariates: [TrendEngine.Metric: Double]
        let outcome: Double
        /// Only for a stable ordering -- greedy matching depends on the order
        /// treated nights are offered, and an unstable order would produce a
        /// different estimate on each redraw.
        let order: Int
    }

    static func estimate(
        nights: [SleepNightFeatures],
        lever: TrendEngine.Metric,
        direction: ZoonTwin.Direction,
        outcome: TrendEngine.Metric = preselectedOutcome,
        calendar: Calendar = .current
    ) -> Result {
        guard lever != outcome else { return .unsupported(.sameMetric) }

        let covariateMetrics = covariates(lever: lever)
        let ordered = nights.sorted { $0.date < $1.date }
        guard let earliest = ordered.first?.date else {
            return .unsupported(.notEnoughNights(have: 0, need: minimumPairs * 2))
        }

        // A night missing the lever, the outcome or any covariate cannot be
        // matched *or* compared, and keeping it on one side only would make
        // the two sides different populations before anything else happened.
        var usable: [(lever: Double, candidate: Candidate)] = []
        for (index, night) in ordered.enumerated() {
            guard let leverValue = lever.value(from: night),
                  let outcomeValue = outcome.value(from: night) else { continue }

            var values: [TrendEngine.Metric: Double] = [:]
            var complete = true
            for metric in covariateMetrics {
                guard let value = metric.value(from: night) else { complete = false; break }
                values[metric] = value
            }
            guard complete else { continue }

            var nightCalendar = calendar
            nightCalendar.timeZone = night.timeZone
            let days = nightCalendar.dateComponents([.day], from: earliest, to: night.date).day ?? 0

            usable.append((
                leverValue,
                Candidate(
                    isWeekend: nightCalendar.isDateInWeekend(night.date),
                    era: Double(days),
                    covariates: values,
                    outcome: outcomeValue,
                    order: index
                )
            ))
        }

        guard usable.count >= minimumPairs * 2 else {
            return .unsupported(.notEnoughNights(have: usable.count, need: minimumPairs * 2))
        }

        let leverValues = usable.map(\.lever)
        var treated: [Candidate] = []
        var controls: [Candidate] = []
        for entry in usable {
            guard let z = Statistics.robustZ(entry.lever, in: leverValues) else {
                return .unsupported(.noContrast)
            }
            let meets = direction == .more ? z >= leverThresholdZ : z <= -leverThresholdZ
            if meets { treated.append(entry.candidate) } else { controls.append(entry.candidate) }
        }

        guard !treated.isEmpty, !controls.isEmpty else { return .unsupported(.noContrast) }

        let pairs = match(treated: treated, controls: controls, covariates: covariateMetrics)
        guard pairs.count >= minimumPairs else {
            return .unsupported(.notEnoughComparableNights(matched: pairs.count, need: minimumPairs))
        }

        let balance = covariateMetrics.map { metric in
            Balance(
                metric: metric,
                standardisedDifference: standardisedDifference(
                    pairs.map { $0.treated.covariates[metric] ?? 0 },
                    pairs.map { $0.control.covariates[metric] ?? 0 }
                )
            )
        }
        if let broken = balance.first(where: { !$0.isBalanced }) {
            return .unsupported(.unbalanced(broken.metric))
        }

        let treatedEra = Statistics.mean(pairs.map(\.treated.era)) ?? 0
        let controlEra = Statistics.mean(pairs.map(\.control.era)) ?? 0
        let eraGap = abs(treatedEra - controlEra)
        guard eraGap <= maximumEraGapDays else {
            return .unsupported(.differentEras(daysApart: Int(eraGap.rounded())))
        }

        let deltas = pairs.map { $0.treated.outcome - $0.control.outcome }
        guard let difference = Statistics.median(deltas),
              let interval = Statistics.pairedBootstrapCI(deltas: deltas) else {
            return .unsupported(.notEnoughComparableNights(matched: pairs.count, need: minimumPairs))
        }

        return .estimated(
            Estimate(
                lever: lever,
                direction: direction,
                outcome: outcome,
                candidateNights: treated.count,
                pairs: pairs.count,
                difference: difference,
                lower: min(interval.lower, interval.upper),
                upper: max(interval.lower, interval.upper),
                confidence: confidence(pairs: pairs.count),
                balance: balance
            )
        )
    }

    // MARK: - Matching

    private struct Pair {
        let treated: Candidate
        let control: Candidate
    }

    /// Greedy nearest-neighbour matching without replacement, exact on day
    /// shape and subject to `caliper`.
    ///
    /// Greedy rather than optimal on purpose. Optimal matching would pair a
    /// few more nights, at the cost of an assignment that changes globally
    /// when one night is added -- and a finding that reshuffles because
    /// yesterday happened is not one anybody can build a habit on. Treated
    /// nights are offered in a fixed order for the same reason.
    ///
    /// Without replacement because a control matched to five treated nights
    /// would put its own noise into five pairs and let the bootstrap count
    /// that as five independent observations.
    private static func match(
        treated: [Candidate],
        controls: [Candidate],
        covariates: [TrendEngine.Metric]
    ) -> [Pair] {
        var available = controls.sorted { $0.order < $1.order }
        var pairs: [Pair] = []

        for candidate in treated.sorted(by: { $0.order < $1.order }) {
            var bestIndex: Int?
            var bestDistance = Double.greatestFiniteMagnitude

            for (index, control) in available.enumerated() where control.isWeekend == candidate.isWeekend {
                let d = distance(candidate, control, covariates: covariates)
                if d < bestDistance {
                    bestDistance = d
                    bestIndex = index
                }
            }

            guard let bestIndex, bestDistance <= caliper else { continue }
            pairs.append(Pair(treated: candidate, control: available.remove(at: bestIndex)))
        }

        return pairs
    }

    /// Mean scaled difference across the covariates and the era. The mean,
    /// not the sum, for the reason `ContextForecast.distance` records: a sum
    /// grows with how many things were compared.
    private static func distance(
        _ a: Candidate,
        _ b: Candidate,
        covariates: [TrendEngine.Metric]
    ) -> Double {
        var total = abs(a.era - b.era) / eraScale
        var count = 1.0

        for metric in covariates {
            guard let lhs = a.covariates[metric], let rhs = b.covariates[metric] else { continue }
            total += gap(lhs, rhs, metric: metric) / scale(for: metric)
            count += 1
        }

        return total / count
    }

    /// Bedtime is compared around the clock, not along it -- the same fold
    /// `ContextForecast` and `Statistics.circularMinutesFromMidnight` apply.
    /// The values here are signed minutes from midnight, so a straight
    /// subtraction is already right for a pair either side of it; the fold
    /// guards the case where one is stored unsigned.
    private static func gap(_ lhs: Double, _ rhs: Double, metric: TrendEngine.Metric) -> Double {
        guard metric == .bedtime else { return abs(lhs - rhs) }
        let raw = abs(lhs - rhs)
        return min(raw, 1440 - raw)
    }

    /// Difference in means over the pooled standard deviation. Zero when the
    /// covariate did not vary at all, which is perfect balance rather than a
    /// division by zero.
    static func standardisedDifference(_ a: [Double], _ b: [Double]) -> Double {
        guard let meanA = Statistics.mean(a), let meanB = Statistics.mean(b) else { return 0 }
        let pooled = Statistics.standardDeviation(a + b) ?? 0
        guard pooled > 0 else { return 0 }
        return (meanA - meanB) / pooled
    }

    /// Graded on pairs, not on nights. Fifty nights that produced twelve
    /// pairs is a twelve-pair comparison.
    private static func confidence(pairs: Int) -> MetricConfidence {
        switch pairs {
        case ..<minimumPairs: .insufficient
        case minimumPairs..<16: .low
        case 16..<28: .moderate
        default: .high
        }
    }
}
