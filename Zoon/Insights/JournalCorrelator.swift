import Foundation

/// Finds which tagged behaviours track with better or worse nights, using
/// matched-pair comparison rather than a naive "all tagged vs all untagged"
/// average.
///
/// The naive version this replaced had a real confounding problem the old
/// doc comment even named without fixing: someone who drinks also tends to
/// go to bed later, sleep less, and be more sleep-debted for reasons that
/// have nothing to do with the alcohol itself. Averaging "all alcohol
/// nights" against "all other nights" bakes those differences into the
/// result and calls it the tag's effect.
///
/// This version matches each tagged night against the *closest* untagged
/// night on the confounders available -- weekend/weekday (hard match) and
/// sleep debt and bedtime (soft, nearest-neighbour) -- and reports the
/// median difference across those matched pairs instead. Still correlation,
/// still stated as correlation (rule 3 below still applies in full), but a
/// meaningfully less confounded correlation.
///
/// Three rules keep it honest:
///
/// 1. **Minimum sample size.** A behaviour needs enough tagged nights *and*
///    enough of them to find a comparable match for. Two data points either
///    side is an anecdote, not a finding, and presenting it as one would be
///    worse than saying nothing.
/// 2. **Effect size, not just direction.** A 0.4% difference in deep sleep is
///    noise. Findings must clear a threshold that a person could plausibly feel.
/// 3. **Correlation is stated as correlation.** The copy says "nights you
///    logged X averaged Y" — never "X causes Y". This method reduces some
///    confounding; it does not prove causation, and never claims to.
struct JournalCorrelator {

    /// Matched pairs required before a behaviour is eligible at all.
    static let minimumMatchedPairs = 8

    /// One night's outcomes joined to its tags, plus the confounders used to
    /// find a comparable match.
    struct Observation {
        let date: Date
        let tags: Set<BehaviorTag>
        let recoveryPercent: Double?
        let sleepPerformance: Double?
        let deepMinutes: Double?
        let remMinutes: Double?
        let efficiency: Double?
        let wakeCount: Double?
        /// Confounders. All optional -- a night missing one just can't be
        /// matched as tightly, rather than being excluded outright.
        let isWeekend: Bool
        let sleepDebtMinutes: Double?
        let bedtimeHour: Double?
    }

    struct Finding: Identifiable, Hashable {
        let tag: BehaviorTag
        let metric: Metric
        /// Median outcome on the tagged nights actually used in a match.
        let taggedMedian: Double
        /// Median outcome on their matched comparison nights.
        let matchedMedian: Double
        let matchedPairCount: Int
        let confidence: Confidence

        var id: String { "\(tag.rawValue)-\(metric.rawValue)" }

        var delta: Double { taggedMedian - matchedMedian }

        var percentChange: Double {
            guard matchedMedian != 0 else { return 0 }
            return (taggedMedian - matchedMedian) / abs(matchedMedian) * 100
        }

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
            Across \(matchedPairCount) nights you logged \(tag.label.lowercased()), matched against \
            comparable nights without it (similar weekday/weekend, sleep debt, and bedtime), \
            \(metric.shortLabel) differed by \(metric.format(delta)). \(confidence.label). \
            An association in your data, not proof of cause.
            """
        }
    }

    enum Confidence: String, Hashable {
        case low, moderate, high

        var label: String {
            switch self {
            case .low: "Low confidence"
            case .moderate: "Moderate confidence"
            case .high: "High confidence"
            }
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
                String(format: "%+.0f%%", value)
            case .deepSleep, .remSleep:
                (value >= 0 ? "+" : "−") + SleepNightFeatures.formatMinutes(abs(value))
            case .wakeCount:
                String(format: "%+.1f", value)
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

    /// Runs every tag × metric pair through matched-pair comparison, keeping
    /// only findings that clear both the sample-size and effect-size bars.
    /// Sorted by magnitude, strongest first.
    func findings(from observations: [Observation]) -> [Finding] {
        var results: [Finding] = []

        for tag in BehaviorTag.allCases {
            for metric in Metric.allCases {
                guard let pairs = matchedPairs(tag: tag, metric: metric, observations: observations),
                      pairs.count >= Self.minimumMatchedPairs else { continue }

                let taggedValues = pairs.map(\.exposedValue)
                let matchedValues = pairs.map(\.matchedValue)
                guard let taggedMedian = Statistics.median(taggedValues),
                      let matchedMedian = Statistics.median(matchedValues),
                      matchedMedian != 0 else { continue }

                let percentChange = abs((taggedMedian - matchedMedian) / abs(matchedMedian) * 100)
                guard percentChange >= metric.minimumEffectPercent else { continue }

                results.append(Finding(
                    tag: tag,
                    metric: metric,
                    taggedMedian: taggedMedian,
                    matchedMedian: matchedMedian,
                    matchedPairCount: pairs.count,
                    confidence: confidence(for: pairs)
                ))
            }
        }

        return results.sorted { abs($0.percentChange) > abs($1.percentChange) }
    }

    struct LearningTag: Identifiable, Hashable {
        let tag: BehaviorTag
        let loggedNights: Int
        var id: String { tag.rawValue }
        var remainingNights: Int { max(0, JournalCorrelator.minimumMatchedPairs - loggedNights) }
        var progress: Double { min(1, Double(loggedNights) / Double(JournalCorrelator.minimumMatchedPairs)) }
    }

    /// Tags that have been logged at all, but not enough to run a matched
    /// comparison yet -- the "still learning" tab, so logging a behaviour
    /// once shows *something* happening rather than silence until the
    /// threshold is cleared.
    func stillLearning(from observations: [Observation]) -> [LearningTag] {
        let found = Set(findings(from: observations).map(\.tag))
        var counts: [BehaviorTag: Int] = [:]
        for observation in observations {
            for tag in observation.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .filter { tag, count in count > 0 && count < Self.minimumMatchedPairs && !found.contains(tag) }
            .map { LearningTag(tag: $0.key, loggedNights: $0.value) }
            .sorted { $0.loggedNights > $1.loggedNights }
    }

    /// The strongest finding per tag, so one behaviour doesn't fill the screen
    /// with six near-identical rows.
    func topFindingPerTag(from observations: [Observation]) -> [Finding] {
        var seen = Set<BehaviorTag>()
        return findings(from: observations).filter { finding in
            seen.insert(finding.tag).inserted
        }
    }

    // MARK: - Matching

    private struct MatchedPair {
        let exposedDate: Date
        let exposedValue: Double
        let matchedValue: Double
    }

    /// Greedy nearest-neighbour matching, without replacement: each untagged
    /// night can back at most one tagged night, so a handful of unusually
    /// "convenient" comparison nights can't get reused to inflate the count.
    ///
    /// Weekend/weekday is a hard constraint -- a Saturday tagged night is
    /// simply not compared against a Tuesday, no matter how close its other
    /// numbers are. Sleep debt and bedtime are soft, nearest-distance
    /// matches; a night more than a fairly loose tolerance away is treated
    /// as no match at all rather than forced into a bad pair.
    private func matchedPairs(tag: BehaviorTag, metric: Metric, observations: [Observation]) -> [MatchedPair]? {
        let exposed = observations.filter { $0.tags.contains(tag) }
        guard exposed.count >= Self.minimumMatchedPairs else { return nil }

        var pool = observations.filter { !$0.tags.contains(tag) }
        var pairs: [MatchedPair] = []

        for night in exposed.sorted(by: { $0.date < $1.date }) {
            guard let exposedValue = metric.value(from: night) else { continue }
            guard let (index, distance) = bestMatch(for: night, in: pool) else { continue }
            guard distance < 3.0 else { continue }
            let candidate = pool[index]
            guard let candidateValue = metric.value(from: candidate) else { continue }

            pairs.append(MatchedPair(exposedDate: night.date, exposedValue: exposedValue, matchedValue: candidateValue))
            pool.remove(at: index)
        }

        return pairs
    }

    private func bestMatch(for night: Observation, in pool: [Observation]) -> (index: Int, distance: Double)? {
        var best: (index: Int, distance: Double)?

        for (index, candidate) in pool.enumerated() {
            // Hard constraint: only compare weekend-to-weekend, weekday-to-weekday.
            guard night.isWeekend == candidate.isWeekend else { continue }

            var distance = 0.0
            if let a = night.sleepDebtMinutes, let b = candidate.sleepDebtMinutes {
                distance += abs(a - b) / 90.0
            }
            if let a = night.bedtimeHour, let b = candidate.bedtimeHour {
                distance += abs(a - b)
            }

            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best
    }

    /// Sample count alone doesn't earn High confidence -- the spec this
    /// implements is explicit about that. A cheap, deterministic stand-in
    /// for a full bootstrap confidence interval: split the matched pairs
    /// chronologically in half and check the effect points the same
    /// direction in both halves. An effect that flips sign between the
    /// first and second half of the data isn't a stable pattern yet,
    /// however many pairs produced it.
    private func confidence(for pairs: [MatchedPair]) -> Confidence {
        let sorted = pairs.sorted { $0.exposedDate < $1.exposedDate }
        let mid = sorted.count / 2
        let firstHalf = Array(sorted.prefix(mid))
        let secondHalf = Array(sorted.suffix(sorted.count - mid))

        let firstDiff = medianDifference(firstHalf)
        let secondDiff = medianDifference(secondHalf)
        let isStable = firstHalf.count >= 3 && secondHalf.count >= 3
            && (firstDiff == 0 || secondDiff == 0 || (firstDiff > 0) == (secondDiff > 0))

        switch pairs.count {
        case ..<16: return .low
        case 16..<30: return isStable ? .moderate : .low
        default: return isStable ? .high : .moderate
        }
    }

    private func medianDifference(_ pairs: [MatchedPair]) -> Double {
        let exposed = Statistics.median(pairs.map(\.exposedValue)) ?? 0
        let matched = Statistics.median(pairs.map(\.matchedValue)) ?? 0
        return exposed - matched
    }
}
