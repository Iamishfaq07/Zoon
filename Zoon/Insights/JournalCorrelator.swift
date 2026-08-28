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

    /// Distance charged for a confounder that could not be compared because
    /// one of the two nights is missing it. See `bestMatch`.
    static let unknownConfounderPenalty = 1.0

    /// Whether a given behaviour happened, didn't happen, or simply wasn't
    /// reviewed on a given night.
    ///
    /// The distinction that used to be missing: a tag's absence from
    /// `Observation.tags` doesn't mean "didn't happen" unless the user
    /// actually looked at the tag list that night. Someone who tagged
    /// `alcohol` on a handful of nights and never opened the Journal on the
    /// rest has told Zoon nothing about caffeine, training, or travel on
    /// those other nights -- treating their silence as a confident "no"
    /// quietly recruited every un-journaled night into the control group for
    /// every behaviour, which is exactly the confounding this engine exists
    /// to avoid.
    enum ExposureState: Equatable {
        case yes, no, unknown
    }

    /// One night's outcomes joined to its tags, plus the confounders used to
    /// find a comparable match.
    struct Observation {
        let date: Date
        let tags: Set<BehaviorTag>
        /// The explicit per-behaviour answers recorded for this night.
        ///
        /// This replaced an `isJournaled: Bool`, and the replacement is the
        /// point of the whole type. That flag was true for any night with a
        /// `JournalEntry` row, and `JournalStore.entryOrCreate` writes a row
        /// the moment the journal screen renders a day -- so merely opening
        /// the screen used to manufacture a confident "did not happen" for
        /// all twenty-three behaviours, and those fabricated negatives
        /// became the control arm of every matched-pair comparison below.
        ///
        /// A behaviour with no entry here is `.unknown`. Nothing about the
        /// night as a whole can promote it to `.no`.
        let answers: BehaviorAnswers
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
        /// Measured directly from HealthKit (finding #49), independent of
        /// whether the user tagged anything that night -- see
        /// `SleepNightFeatures.alcoholicBeverages`/`.lateCaffeineMg`. `nil`
        /// when Lifestyle Insights was never granted or nothing was logged;
        /// the two look identical to a HealthKit query by design, so
        /// `exposureState` can't and doesn't try to tell them apart either.
        let alcoholicBeverages: Double?
        let lateCaffeineMg: Double?
        /// Whether this night's recorded timezone differs from the
        /// previous stored night's -- Travel Mode groundwork (finding
        /// #55/#56): a night that starts in a new timezone is measured
        /// evidence of travel independent of whether the user remembered
        /// to tag it, the same "measured closes gaps manual tagging
        /// leaves open" idea finding #49 already established for
        /// alcohol/caffeine. Full Travel Mode itself -- trip detection,
        /// adjusted targets, jet-lag-aware coaching -- is out of scope
        /// here; this is only the underlying signal.
        let measuredTimeZoneShift: Bool

        /// Resolves one behaviour for this night, in strict order of
        /// authority.
        ///
        /// 1. An explicit answer the user gave. The only source of `.no`.
        /// 2. A legacy positive tag, which is a `.yes` the user really did
        ///    record before this model existed.
        /// 3. Measured data, which can only ever *upgrade* an unanswered
        ///    behaviour to `.yes`.
        /// 4. Otherwise `.unknown`.
        ///
        /// Step 3 is upgrade-only for a reason the previous version stated
        /// in its own doc comment and then violated for alcohol and
        /// caffeine: it read a non-nil zero as a confident `.no`. But
        /// `FeatureExtractor.alcoholicBeverages` returns nil both when
        /// nothing was logged and when Lifestyle Insights was never
        /// authorized -- HealthKit makes read-permission denial and absent
        /// data deliberately indistinguishable -- so an absent sample can
        /// never prove abstinence. Travel was already handled correctly:
        /// a same-timezone trip is real travel the heuristic cannot see,
        /// so its absence is evidence of nothing.
        ///
        /// There is deliberately no path from "this night has a journal
        /// row" to `.no`.
        func exposureState(for tag: BehaviorTag) -> ExposureState {
            switch answers.state(for: tag) {
            case .yes: return .yes
            case .no: return .no
            case .unknown: break
            }
            if tags.contains(tag) { return .yes }
            switch tag {
            case .alcohol:
                if let alcoholicBeverages, alcoholicBeverages > 0 { return .yes }
            case .caffeineLate:
                if let lateCaffeineMg, lateCaffeineMg > 0 { return .yes }
            case .travelled:
                if measuredTimeZoneShift { return .yes }
            default:
                break
            }
            return .unknown
        }

        /// Whether anything at all is known about this night's behaviours.
        ///
        /// The night-level gate that `isJournaled` used to serve, with the
        /// meaning it should always have had: a journal row exists for every
        /// day whose screen was opened, but only an answered behaviour is
        /// data. A legacy positive tag counts, because it is a real recorded
        /// answer.
        var hasAnyExplicitAnswer: Bool {
            answers.hasAnyAnswer || !tags.isEmpty
        }

        /// Travel and illness are themselves loggable confounders (finding
        /// #45): a hard hotel bed or a cold plausibly explains a bad night on
        /// its own, independent of whatever else got tagged that day.
        /// Routed through `exposureState` rather than reading `tags`
        /// directly, so an explicit answer wins here too -- otherwise a
        /// night the user answered "no travel" would still be treated as a
        /// travel night by the matcher because a stale legacy tag said so.
        var isTravelDay: Bool { exposureState(for: .travelled) == .yes }
        var isSickDay: Bool { exposureState(for: .sick) == .yes }
    }

    struct Finding: Identifiable, Hashable {
        let tag: BehaviorTag
        let metric: Metric
        /// Median outcome on the tagged nights actually used in a match, for
        /// display context only -- `delta` below is not derived from this.
        let taggedMedian: Double
        /// Median outcome on their matched comparison nights, for display
        /// context only -- `delta` below is not derived from this.
        let matchedMedian: Double
        /// Median of each pair's own (exposed − matched) difference. Kept
        /// distinct from `taggedMedian - matchedMedian`: that
        /// difference-of-medians is computed across two groups separately and
        /// can mask pairs that move in opposite directions cancelling out in
        /// aggregate, while this reflects what the typical *pair* itself
        /// showed.
        let pairDeltaMedian: Double
        /// 95% bootstrap confidence interval on `pairDeltaMedian`. Nil when
        /// there weren't enough pairs to bootstrap (see
        /// `Statistics.pairedBootstrapCI`).
        let confidenceIntervalLower: Double?
        let confidenceIntervalUpper: Double?
        let matchedPairCount: Int
        let confidence: Confidence
        /// Each matched pair's own (exposed − matched) delta, same units as
        /// `metric`. Kept alongside the summary stats above so a result row
        /// can plot the actual matched pairs -- the redesign spec's
        /// "paired-dot plot" -- rather than only the median and interval
        /// derived from them.
        let pairDeltas: [Double]

        var id: String { "\(tag.rawValue)-\(metric.rawValue)" }

        var delta: Double { pairDeltaMedian }

        var percentChange: Double {
            guard matchedMedian != 0 else { return 0 }
            return pairDeltaMedian / abs(matchedMedian) * 100
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
            var rangeClause = ""
            if let lower = confidenceIntervalLower, let upper = confidenceIntervalUpper {
                rangeClause = " 95% range: \(metric.format(lower)) to \(metric.format(upper))."
            }
            return """
            Across \(matchedPairCount) nights you logged \(tag.label.lowercased()), matched against \
            comparable nights without it (similar weekday/weekend, sleep debt, and bedtime), \
            \(metric.shortLabel) differed by \(metric.format(delta)) on the typical matched pair.\(rangeClause) \
            \(confidence.label). An association in your data, not proof of cause.
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
        /// 24-hour sleep (main sleep plus naps) against each night's own
        /// historical learned-baseline need, not main sleep alone against
        /// one current Settings goal applied uniformly to every night --
        /// see `SleepDataCoordinator.journalObservations()`, where
        /// `Observation.sleepPerformance` is actually built. This is a
        /// baseline-only approximation, the same one Sleep Health's
        /// sufficiency component and `rebuildRecoveryHistory` use -- it
        /// does not include the debt-payback/strain/nap adjustments the
        /// live Today screen's `SleepNeed` applies, since those aren't
        /// reconstructable for a past night without a stored strain
        /// history. Don't expect this to match what Today showed for the
        /// same night; it will only ever agree with Sleep Health and
        /// Recovery history, which use the same approximation.
        case sleepPerformance
        case deepSleep
        case remSleep
        case efficiency
        case wakeCount

        var shortLabel: String {
            switch self {
            case .recovery: "recovery"
            case .sleepPerformance: "sleep sufficiency"
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
                let pairDeltas = pairs.map(\.delta)
                guard let taggedMedian = Statistics.median(taggedValues),
                      let matchedMedian = Statistics.median(matchedValues),
                      let pairDeltaMedian = Statistics.median(pairDeltas),
                      matchedMedian != 0 else { continue }

                let percentChange = abs(pairDeltaMedian / abs(matchedMedian) * 100)
                guard percentChange >= metric.minimumEffectPercent else { continue }

                let ci = Statistics.pairedBootstrapCI(deltas: pairDeltas)

                results.append(Finding(
                    tag: tag,
                    metric: metric,
                    taggedMedian: taggedMedian,
                    matchedMedian: matchedMedian,
                    pairDeltaMedian: pairDeltaMedian,
                    confidenceIntervalLower: ci?.lower,
                    confidenceIntervalUpper: ci?.upper,
                    matchedPairCount: pairs.count,
                    confidence: confidence(forPairCount: pairDeltas.count, ci: ci),
                    pairDeltas: pairDeltas
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

    /// Behaviours that actually got a fair test -- enough comparable nights
    /// existed to run at least one matched-pair comparison -- but no metric
    /// cleared the effect-size bar. This is a third, distinct answer from
    /// `stillLearning`: those tags never had enough data to compare at all;
    /// these did, and "no clear pattern found" is itself real information
    /// worth showing, not silence that reads the same as "not enough data
    /// yet" to someone who has diligently logged a behaviour for weeks.
    ///
    /// Not exhaustive: a tag can in principle clear `minimumMatchedPairs` on
    /// raw exposed-night count yet still fail to produce that many *matched*
    /// pairs for every metric (the weekend/weekday hard constraint or the
    /// distance cutoff in `bestMatch` can exhaust the comparison pool). That
    /// residual case is rare enough in practice, and correctly falls back to
    /// simply not appearing in any tab, matching this method's prior
    /// (unhandled) behaviour rather than a regression.
    func testedNoEffect(from observations: [Observation]) -> [BehaviorTag] {
        let foundTags = Set(findings(from: observations).map(\.tag))
        let learningTags = Set(stillLearning(from: observations).map(\.tag))

        return BehaviorTag.allCases.filter { tag in
            guard !foundTags.contains(tag), !learningTags.contains(tag) else { return false }
            return Metric.allCases.contains { metric in
                (matchedPairs(tag: tag, metric: metric, observations: observations)?.count ?? 0)
                    >= Self.minimumMatchedPairs
            }
        }
    }

    // MARK: - Matching

    private struct MatchedPair {
        let exposedDate: Date
        let exposedValue: Double
        let matchedValue: Double
        var delta: Double { exposedValue - matchedValue }
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
        let exposed = observations.filter { $0.exposureState(for: tag) == .yes }
        guard exposed.count >= Self.minimumMatchedPairs else { return nil }

        // `.no` only, never `.unknown` -- an un-journaled night has told
        // Zoon nothing about whether this tag applied, so it can't stand in
        // as a confident comparison night. See `ExposureState`'s doc comment.
        var pool = observations.filter { $0.exposureState(for: tag) == .no }
        var pairs: [MatchedPair] = []

        for night in exposed.sorted(by: { $0.date < $1.date }) {
            guard let exposedValue = metric.value(from: night) else { continue }
            guard let (index, distance) = bestMatch(for: night, in: pool, confounderTag: tag) else { continue }
            guard distance < 3.0 else { continue }
            let candidate = pool[index]
            guard let candidateValue = metric.value(from: candidate) else { continue }

            pairs.append(MatchedPair(exposedDate: night.date, exposedValue: exposedValue, matchedValue: candidateValue))
            pool.remove(at: index)
        }

        return pairs
    }

    /// `confounderTag` is the behaviour being tested -- travel/illness are
    /// skipped as hard constraints when *they're* the tag under test,
    /// otherwise every exposed night (travel = true) could only ever match
    /// against pool nights that are by definition travel = false, producing
    /// zero matches for those two tags specifically.
    private func bestMatch(
        for night: Observation,
        in pool: [Observation],
        confounderTag: BehaviorTag
    ) -> (index: Int, distance: Double)? {
        var best: (index: Int, distance: Double)?

        for (index, candidate) in pool.enumerated() {
            // Hard constraints: only compare weekend-to-weekend/weekday-to-weekday,
            // travel-to-travel, and illness-to-illness (finding #45) -- each is
            // plausibly enough on its own to explain a bad night regardless of
            // whatever else got tagged.
            guard night.isWeekend == candidate.isWeekend else { continue }
            if confounderTag != .travelled {
                guard night.isTravelDay == candidate.isTravelDay else { continue }
            }
            if confounderTag != .sick {
                guard night.isSickDay == candidate.isSickDay else { continue }
            }

            // A confounder that cannot be compared is charged a fixed
            // penalty rather than skipped.
            //
            // Skipping it inverted the whole point of matching: distance is
            // minimised, so a candidate *missing* a confounder scored
            // strictly better than one whose value was known and close, and
            // the matcher preferentially picked the nights it knew least
            // about. `SleepNightFeatures.sleepDebtMinutes` is nil until
            // fourteen nights of history exist, so the bias was strongest
            // exactly when this engine first starts producing findings.
            //
            // One unit is the same cost as 90 minutes of debt difference or
            // one hour of bedtime difference -- a real but not disqualifying
            // gap, so an unmatched-on-one-axis night stays eligible under
            // the cutoff below while losing to any night with a genuinely
            // close known value.
            var distance = 0.0
            if let a = night.sleepDebtMinutes, let b = candidate.sleepDebtMinutes {
                distance += abs(a - b) / 90.0
            } else {
                distance += Self.unknownConfounderPenalty
            }
            if let a = night.bedtimeHour, let b = candidate.bedtimeHour {
                distance += abs(a - b)
            } else {
                distance += Self.unknownConfounderPenalty
            }

            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best
    }

    /// Sample count alone doesn't earn High confidence -- the spec this
    /// implements is explicit about that. Driven by a real deterministic
    /// paired-bootstrap confidence interval (`Statistics.pairedBootstrapCI`)
    /// on the pair deltas: a finding only reaches Moderate/High once enough
    /// pairs exist *and* the 95% interval for the typical pair difference
    /// excludes zero, i.e. resampling the same data consistently points the
    /// same direction rather than merely having produced enough of it to
    /// run the test once.
    private func confidence(forPairCount count: Int, ci: (lower: Double, upper: Double)?) -> Confidence {
        let excludesZero = ci.map { ($0.lower > 0 && $0.upper > 0) || ($0.lower < 0 && $0.upper < 0) } ?? false

        switch count {
        case ..<16: return .low
        case 16..<30: return excludesZero ? .moderate : .low
        default: return excludesZero ? .high : .moderate
        }
    }
}
