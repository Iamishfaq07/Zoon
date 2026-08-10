import Foundation

/// Finds which tagged behaviours track with better or worse nights.
///
/// This is the payoff for journalling, and the place where it would be easiest
/// to mislead someone. Three rules keep it honest:
///
/// 1. **Minimum sample size.** A behaviour needs enough tagged nights *and*
///    enough untagged nights to compare against. Two data points either side is
///    an anecdote, not a finding, and presenting it as one would be worse than
///    saying nothing.
/// 2. **Effect size, not just direction.** A 0.4% difference in deep sleep is
///    noise. Findings must clear a threshold that a person could plausibly feel.
/// 3. **Correlation is stated as correlation.** The copy says "nights you
///    logged X averaged Y" — never "X causes Y". People who drink also tend to
///    eat late and sleep badly for other reasons, and this method cannot
///    separate those.
struct JournalCorrelator {

    /// Tagged nights required before a behaviour is eligible.
    static let minimumTaggedNights = 4
    /// Untagged nights required as a comparison group.
    static let minimumBaselineNights = 4

    /// One night's outcomes joined to its tags.
    struct Observation {
        let date: Date
        let tags: Set<BehaviorTag>
        let recoveryPercent: Double?
        let sleepPerformance: Double?
        let deepMinutes: Double?
        let remMinutes: Double?
        let efficiency: Double?
        let wakeCount: Double?
    }

    struct Finding: Identifiable, Hashable {
        let tag: BehaviorTag
        let metric: Metric
        /// Mean on nights with the tag.
        let taggedMean: Double
        /// Mean on nights without it.
        let baselineMean: Double
        let taggedCount: Int
        let baselineCount: Int

        var id: String { "\(tag.rawValue)-\(metric.rawValue)" }

        /// Signed change, in the metric's own units.
        var delta: Double { taggedMean - baselineMean }

        /// Signed change as a percentage of the baseline.
        var percentChange: Double {
            guard baselineMean != 0 else { return 0 }
            return (taggedMean - baselineMean) / abs(baselineMean) * 100
        }

        /// True when the change is in the direction the user would want.
        var isImprovement: Bool {
            metric.higherIsBetter ? delta > 0 : delta < 0
        }

        var headline: String {
            let direction = isImprovement ? "better" : "worse"
            let magnitude = abs(percentChange)
            return "\(tag.label): \(String(format: "%.0f%%", magnitude)) \(direction) \(metric.shortLabel)"
        }

        var detail: String {
            """
            Across \(taggedCount) nights you logged \(tag.label.lowercased()), \
            \(metric.shortLabel) averaged \(metric.format(taggedMean)) — against \
            \(metric.format(baselineMean)) on \(baselineCount) nights you didn't. \
            That's a pattern, not proof of cause.
            """
        }
    }

    enum Metric: String, CaseIterable, Hashable {
        case recovery
        case sleepPerformance
        case deepSleep
        case remSleep
        case efficiency
        case wakeCount

        var shortLabel: String {
            switch self {
            case .recovery: "recovery"
            case .sleepPerformance: "sleep performance"
            case .deepSleep: "deep sleep"
            case .remSleep: "REM sleep"
            case .efficiency: "sleep efficiency"
            case .wakeCount: "awakenings"
            }
        }

        var higherIsBetter: Bool { self != .wakeCount }

        /// Minimum percentage change worth reporting. Tuned per metric: deep
        /// sleep swings widely night to night so it needs a bigger move to mean
        /// anything, whereas efficiency is stable and a small shift is real.
        var minimumEffectPercent: Double {
            switch self {
            case .recovery: 8
            case .sleepPerformance: 6
            case .deepSleep: 12
            case .remSleep: 12
            case .efficiency: 4
            case .wakeCount: 20
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .recovery, .sleepPerformance, .efficiency:
                String(format: "%.0f%%", value)
            case .deepSleep, .remSleep:
                SleepNightFeatures.formatMinutes(value)
            case .wakeCount:
                String(format: "%.1f", value)
            }
        }

        func value(from observation: Observation) -> Double? {
            switch self {
            case .recovery: observation.recoveryPercent
            case .sleepPerformance: observation.sleepPerformance
            case .deepSleep: observation.deepMinutes
            case .remSleep: observation.remMinutes
            case .efficiency: observation.efficiency
            case .wakeCount: observation.wakeCount
            }
        }
    }

    /// Runs every tag × metric pair, keeping only findings that clear both the
    /// sample-size and effect-size bars. Sorted by magnitude, strongest first.
    func findings(from observations: [Observation]) -> [Finding] {
        guard observations.count >= Self.minimumTaggedNights + Self.minimumBaselineNights else { return [] }

        var results: [Finding] = []

        for tag in BehaviorTag.allCases {
            let tagged = observations.filter { $0.tags.contains(tag) }
            let untagged = observations.filter { !$0.tags.contains(tag) }

            guard tagged.count >= Self.minimumTaggedNights,
                  untagged.count >= Self.minimumBaselineNights else { continue }

            for metric in Metric.allCases {
                let taggedValues = tagged.compactMap { metric.value(from: $0) }
                let baselineValues = untagged.compactMap { metric.value(from: $0) }

                guard taggedValues.count >= Self.minimumTaggedNights,
                      baselineValues.count >= Self.minimumBaselineNights else { continue }

                let taggedMean = mean(taggedValues)
                let baselineMean = mean(baselineValues)
                guard baselineMean != 0 else { continue }

                let change = abs((taggedMean - baselineMean) / abs(baselineMean) * 100)
                guard change >= metric.minimumEffectPercent else { continue }

                results.append(Finding(
                    tag: tag,
                    metric: metric,
                    taggedMean: taggedMean,
                    baselineMean: baselineMean,
                    taggedCount: taggedValues.count,
                    baselineCount: baselineValues.count
                ))
            }
        }

        return results.sorted { abs($0.percentChange) > abs($1.percentChange) }
    }

    /// The strongest finding per tag, so one behaviour doesn't fill the screen
    /// with six near-identical rows.
    func topFindingPerTag(from observations: [Observation]) -> [Finding] {
        var seen = Set<BehaviorTag>()
        return findings(from: observations).filter { finding in
            seen.insert(finding.tag).inserted
        }
    }

    private func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
