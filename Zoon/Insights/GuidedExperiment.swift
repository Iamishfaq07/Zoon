import Foundation

/// A user-initiated, single-behaviour focus: "I'm going to track alcohol
/// for a while and find out if it actually costs me anything."
///
/// Deliberately adds no new statistics of its own -- it's a focused lens
/// onto `JournalCorrelator`'s existing matched-pair engine for one tag at a
/// time. Cause Finder already computes findings, still-learning tags, and
/// tested-no-effect tags across every behaviour every time it's viewed;
/// this just answers "what's the state of *this one*" so a user who
/// deliberately started tracking something has a clear, dedicated place to
/// come back to rather than hunting for it across three tabs.
enum GuidedExperiment {

    enum Status {
        /// Not yet enough matched-pair comparisons for any metric.
        case learning(JournalCorrelator.LearningTag)
        /// At least one metric cleared both bars. Split the same way
        /// Cause Finder's own tabs are.
        case result(helpful: [JournalCorrelator.Finding], harmful: [JournalCorrelator.Finding])
        /// Enough comparable nights existed, but nothing cleared the
        /// effect-size bar on any metric.
        case noEffect

        var isResolved: Bool {
            switch self {
            case .learning: false
            case .result, .noEffect: true
            }
        }
    }

    /// - Parameter since: the experiment's start date, if one is active. When
    ///   set, only nights on or after it feed the comparison -- an
    ///   experiment answers "since I started deliberately tracking this, has
    ///   it made a difference", not "across my whole history including
    ///   before I started paying attention to it". `nil` (no active
    ///   experiment, or a caller that just wants the tag's all-time picture)
    ///   falls back to the full history, matching the previous behaviour.
    static func status(
        for tag: BehaviorTag,
        observations: [JournalCorrelator.Observation],
        since: Date? = nil
    ) -> Status {
        let observations = since.map { start in
            observations.filter { $0.date >= start }
        } ?? observations
        let correlator = JournalCorrelator()

        if let learning = correlator.stillLearning(from: observations).first(where: { $0.tag == tag }) {
            return .learning(learning)
        }

        let findings = correlator.findings(from: observations).filter { $0.tag == tag }
        if !findings.isEmpty {
            return .result(
                helpful: findings.filter(\.isImprovement),
                harmful: findings.filter { !$0.isImprovement }
            )
        }

        if correlator.testedNoEffect(from: observations).contains(tag) {
            return .noEffect
        }

        // Not yet logged at all, or the residual matched-pair gap
        // `testedNoEffect` documents (raw count clears the threshold, but
        // no metric produced enough *matched* pairs). Either way there's
        // nothing to show yet -- treat it as the start of learning rather
        // than leaving the screen blank.
        return .learning(JournalCorrelator.LearningTag(tag: tag, loggedNights: 0))
    }

    /// Nights required in both the baseline and trial windows before
    /// `summarize` will produce an outcome at all -- a before/after
    /// comparison built from one or two nights on either side is noise, not
    /// a finding, same "minimum sample size" principle `JournalCorrelator`
    /// applies to its own matched pairs.
    static let minimumPeriodNights = 3

    /// A simple before/after comparison for one completed experiment:
    /// median outcome in the `baselineDays` immediately before `startDate`,
    /// versus median outcome from `startDate` through `endDate`.
    ///
    /// Deliberately not matched-pair like `JournalCorrelator`'s own findings
    /// -- this answers a different, more literal question ("did my nights
    /// actually change once I started paying attention to this"), and
    /// matching would need a control group this single-tag, single-window
    /// comparison doesn't have. Both are shown as what they are: a
    /// before/after average, not a controlled comparison.
    ///
    /// Picks whichever metric moved the most between the two periods as the
    /// headline outcome -- across six metrics, showing all of them for a
    /// single experiment would bury the one that actually changed.
    static func summarize(
        tag: BehaviorTag,
        hypothesis: String?,
        startDate: Date,
        endDate: Date,
        baselineDays: Int = 14,
        observations: [JournalCorrelator.Observation],
        calendar: Calendar = .current
    ) -> SleepExperimentStore.Outcome? {
        let baselineStart = calendar.date(byAdding: .day, value: -baselineDays, to: startDate) ?? startDate
        let baseline = observations.filter { $0.date >= baselineStart && $0.date < startDate }
        let trial = observations.filter { $0.date >= startDate && $0.date <= endDate }
        guard baseline.count >= minimumPeriodNights, trial.count >= minimumPeriodNights else { return nil }

        var strongest: (metric: JournalCorrelator.Metric, baselineMedian: Double, trialMedian: Double)?
        for metric in JournalCorrelator.Metric.allCases {
            guard let baselineMedian = Statistics.median(baseline.compactMap(metric.value(from:))),
                  let trialMedian = Statistics.median(trial.compactMap(metric.value(from:))) else { continue }
            let delta = abs(trialMedian - baselineMedian)
            let strongestDelta = strongest.map { abs($0.trialMedian - $0.baselineMedian) } ?? -1
            if delta > strongestDelta {
                strongest = (metric, baselineMedian, trialMedian)
            }
        }
        guard let strongest else { return nil }

        return SleepExperimentStore.Outcome(
            id: UUID(),
            tag: tag.rawValue,
            hypothesis: hypothesis,
            startDate: startDate,
            endDate: endDate,
            metricLabel: strongest.metric.shortLabel,
            baselineMedian: strongest.baselineMedian,
            trialMedian: strongest.trialMedian,
            baselineNightCount: baseline.count,
            trialNightCount: trial.count,
            higherIsBetter: strongest.metric.higherIsBetter
        )
    }
}
