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
    /// applies to its own matched pairs. Higher than that floor's own 3:
    /// this comparison is a plain before/after median, not matched pairs,
    /// so it has no other defense against a couple of unusually good or bad
    /// nights swinging the whole result.
    static let minimumPeriodNights = 7

    /// A simple before/after comparison for one completed experiment:
    /// median outcome in the `baselineDays` immediately before `startDate`,
    /// versus median outcome from `startDate` through `endDate`, on
    /// whichever `primaryMetric` was chosen when the experiment started.
    ///
    /// Deliberately not matched-pair like `JournalCorrelator`'s own findings
    /// -- this answers a different, more literal question ("did my nights
    /// actually change once I started paying attention to this"), and
    /// matching would need a control group this single-tag, single-window
    /// comparison doesn't have. Both are shown as what they are: a
    /// before/after average, not a controlled comparison.
    ///
    /// `primaryMetric` is fixed by the caller, not chosen here from
    /// whichever metric happened to move the most -- scanning every metric
    /// after the fact and reporting the biggest mover is a multiple-
    /// comparisons trap: some of six metrics will drift by chance even with
    /// no real effect, and picking the winner post-hoc dresses that noise
    /// up as a finding. If the pre-specified metric itself has no data on
    /// one side, this returns `nil` rather than silently substituting
    /// another metric.
    static func summarize(
        tag: BehaviorTag,
        hypothesis: String?,
        primaryMetric: JournalCorrelator.Metric,
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
        guard let baselineMedian = Statistics.median(baseline.compactMap(primaryMetric.value(from:))),
              let trialMedian = Statistics.median(trial.compactMap(primaryMetric.value(from:))) else { return nil }

        // How many trial nights actually had a known yes/no for this tag --
        // i.e. how consistently the behaviour itself kept getting logged
        // once the experiment was under way, not just how many nights had
        // *any* journal entry. A trial where half the nights never got
        // tagged either way is a trial the result can't really speak for.
        let trialKnownNightCount = trial.filter { $0.exposureState(for: tag) != .unknown }.count

        return SleepExperimentStore.Outcome(
            id: UUID(),
            tag: tag.rawValue,
            hypothesis: hypothesis,
            startDate: startDate,
            endDate: endDate,
            metricLabel: primaryMetric.shortLabel,
            baselineMedian: baselineMedian,
            trialMedian: trialMedian,
            baselineNightCount: baseline.count,
            trialNightCount: trial.count,
            higherIsBetter: primaryMetric.higherIsBetter,
            trialKnownNightCount: trialKnownNightCount
        )
    }
}
