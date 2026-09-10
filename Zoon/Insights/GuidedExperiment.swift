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

    /// What the experiment is actually testing: whether *doing less* of the
    /// tracked behaviour helps, or whether *doing more* of it does. Without
    /// this, "compliant" has no meaning -- a night the user had a drink is
    /// a broken trial for "cut back on alcohol" but a successful one for
    /// "try adding an evening walk". Defaults to `.avoid`: the large
    /// majority of tracked behaviours (alcohol, late caffeine, screens) are
    /// things people are testing whether to cut back on, and it was the
    /// only behaviour this app's adherence math implicitly assumed before
    /// this type existed.
    enum Direction: String, Codable, CaseIterable, Sendable {
        case avoid
        case pursue

        var label: String {
            switch self {
            case .avoid: "Cutting back on it"
            case .pursue: "Doing more of it"
            }
        }

        /// The exposure state that counts as a compliant night under this
        /// direction. `.unknown` is never compliant for either direction --
        /// an unjournaled night hasn't demonstrated compliance, it's just
        /// missing.
        var compliantExposureState: JournalCorrelator.ExposureState {
            switch self {
            case .avoid: .no
            case .pursue: .yes
            }
        }
    }

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
        direction: Direction = .avoid,
        startDate: Date,
        endDate: Date,
        baselineDays: Int = 14,
        observations: [JournalCorrelator.Observation],
        calendar: Calendar = .current
    ) -> SleepExperimentStore.Outcome? {
        // Defence in depth behind the picker's own filter. A stored
        // preference, a restored backup or an experiment started before
        // `BehaviorTag.ExposureControl` existed could all arrive here asking
        // for a direction Zoon does not offer, and the summary is the last
        // place that pairing could still reach a screen.
        guard tag.testableDirections.contains(direction) else { return nil }

        let baselineStart = calendar.date(byAdding: .day, value: -baselineDays, to: startDate) ?? startDate
        let baseline = observations.filter { $0.date >= baselineStart && $0.date < startDate }
        let trial = observations.filter { $0.date >= startDate && $0.date <= endDate }
        guard baseline.count >= minimumPeriodNights, trial.count >= minimumPeriodNights else { return nil }

        // How many trial nights actually had a known yes/no for this tag --
        // i.e. how consistently the behaviour itself kept getting logged
        // once the experiment was under way, not just how many nights had
        // *any* journal entry. A trial where half the nights never got
        // tagged either way is a trial the result can't really speak for.
        let trialKnownNightCount = trial.filter { $0.exposureState(for: tag) != .unknown }.count

        // True adherence: nights that actually landed on the side of the
        // tag this experiment is testing for, out of *all* trial nights --
        // not out of only the ones that got logged either way. A trial with
        // 14 nights, 5 of them compliant and 9 not (all 14 known), is 36%
        // adherence, not 100%: an unlogged night and a logged-but-wrong-way
        // night are both failures to demonstrate compliance, just for
        // different reasons. `trialKnownNightCount` above still answers a
        // real, different question -- how much of the trial got tagged at
        // all -- and stays alongside this for that reason.
        let trialCompliantNightCount = trial.filter {
            $0.exposureState(for: tag) == direction.compliantExposureState
        }.count

        // The primary comparison is baseline against the nights that actually
        // complied with what the experiment tests -- not the whole trial
        // window. Averaging in noncompliant nights as if they demonstrated
        // the behaviour would dilute a real effect toward zero, or manufacture
        // one from nights that never tested the hypothesis at all: a trial
        // that's 36% adherent (the worked example above) has a trialMedian
        // dominated by the 64% of nights nothing was actually being tried.
        // Same minimum as baseline/trial -- a "result" built from three
        // compliant nights out of fourteen isn't one to report as settled.
        let adherentTrial = trial.filter { $0.exposureState(for: tag) == direction.compliantExposureState }
        guard adherentTrial.count >= minimumPeriodNights else { return nil }
        let baselineValues = baseline.compactMap(primaryMetric.value(from:))
        let trialValues = adherentTrial.compactMap(primaryMetric.value(from:))
        guard let baselineMedian = Statistics.median(baselineValues),
              let trialMedian = Statistics.median(trialValues) else { return nil }
        let interval = medianDifferenceInterval(baseline: baselineValues, trial: trialValues)

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
            trialKnownNightCount: trialKnownNightCount,
            direction: direction,
            trialCompliantNightCount: trialCompliantNightCount,
            uncertaintyLower: interval?.lower,
            uncertaintyUpper: interval?.upper
        )
    }

    // MARK: - Controlled designs

    /// Reads a finished controlled trial (`ExperimentDesign.isControlled`)
    /// against the schedule it was given, and records it in the same shape
    /// `summarize` produces so the store, the ledger and the notebook need
    /// no second path.
    ///
    /// The two arms are the two "periods". The arm that does what the
    /// experiment asks (`without` for `.avoid`, `with` for `.pursue`) is the
    /// trial; the other arm is its baseline -- planned and interleaved with
    /// it, which is the whole advantage over the fortnight-before that
    /// `summarize` has to use. Each side's median is the median of its
    /// blocks' medians, exactly as `ExperimentDesign.analyse` takes the
    /// difference, so the two readings agree.
    ///
    /// Adherence covers the whole trial, both arms: a crossover whose "with"
    /// stretch was never actually performed is as broken as one whose
    /// "without" stretch was not, and `EvidenceLedger.experimentStatus`
    /// reads one rate. `baselineNightCount` is the baseline arm's followed
    /// nights -- the ones its median rests on -- and `trialNightCount` is
    /// every assigned night, so `adherenceRate` is followed over assigned.
    ///
    /// nil when `analyse` refused (a stretch too thin, one arm only).
    /// `Unusable` carries the reason for a screen; a stored outcome has
    /// nowhere honest to put "there was no result".
    static func summarizeCrossover(
        tag: BehaviorTag,
        hypothesis: String?,
        primaryMetric: JournalCorrelator.Metric,
        direction: Direction,
        schedule: [ExperimentDesign.Assignment],
        endDate: Date,
        observations: [JournalCorrelator.Observation],
        calendar: Calendar = .current
    ) -> SleepExperimentStore.Outcome? {
        guard tag.testableDirections.contains(direction),
              let startDate = schedule.map(\.date).min() else { return nil }

        // Assignments are start-of-day dates and so are nights; joined on
        // the day rather than the instant in case either side was
        // normalised in a different timezone.
        let byDay = Dictionary(
            observations.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let analysed = ExperimentDesign.analyse(
            schedule: schedule,
            value: { byDay[calendar.startOfDay(for: $0)].flatMap(primaryMetric.value(from:)) },
            exposure: { byDay[calendar.startOfDay(for: $0)]?.exposureState(for: tag) ?? .unknown },
            calendar: calendar
        )
        guard case .analysed(let analysis) = analysed else { return nil }

        let trialArm: ExperimentDesign.Arm = direction == .avoid ? .without : .with
        let trialBlocks = analysis.blocks.filter { $0.arm == trialArm }
        let baselineBlocks = analysis.blocks.filter { $0.arm != trialArm }
        guard let trialMedian = Statistics.median(trialBlocks.compactMap(\.median)),
              let baselineMedian = Statistics.median(baselineBlocks.compactMap(\.median)) else { return nil }
        let adherence = analysis.adherence

        // Per-night values for the interval, one array per arm, restricted to
        // the nights that actually followed their arm -- the same nights the
        // block medians above rest on. `analyse` only offers its own interval
        // from three block pairs, which no shipping design reaches.
        var trialValues: [Double] = []
        var baselineValues: [Double] = []
        for assignment in schedule {
            let day = calendar.startOfDay(for: assignment.date)
            guard let observation = byDay[day],
                  let value = primaryMetric.value(from: observation) else { continue }
            let followed = switch (observation.exposureState(for: tag), assignment.arm) {
            case (.yes, .with), (.no, .without): true
            default: false
            }
            guard followed else { continue }
            if assignment.arm == trialArm { trialValues.append(value) } else { baselineValues.append(value) }
        }
        let interval = medianDifferenceInterval(baseline: baselineValues, trial: trialValues)

        return SleepExperimentStore.Outcome(
            id: UUID(),
            tag: tag.rawValue,
            hypothesis: hypothesis,
            startDate: startDate,
            endDate: endDate,
            metricLabel: primaryMetric.shortLabel,
            baselineMedian: baselineMedian,
            trialMedian: trialMedian,
            baselineNightCount: baselineBlocks.reduce(0) { $0 + $1.adherence.adherent },
            trialNightCount: adherence.total,
            higherIsBetter: primaryMetric.higherIsBetter,
            trialKnownNightCount: adherence.adherent + adherence.nonAdherent,
            direction: direction,
            trialCompliantNightCount: adherence.adherent,
            uncertaintyLower: interval?.lower,
            uncertaintyUpper: interval?.upper
        )
    }

    // MARK: - Uncertainty

    /// 95% percentile-bootstrap interval on (median of `trial` − median of
    /// `baseline`), resampling each side independently. The two-sample
    /// counterpart of `Statistics.pairedBootstrapCI`, which resamples
    /// per-pair deltas and has nothing to pair here: a before/after
    /// comparison has different nights on each side.
    ///
    /// Deterministic for the same reason that one is -- an interval that
    /// reshuffled between two visits to the screen would make the stated
    /// confidence a random number. nil below `minimumPeriodNights` a side,
    /// the floor `summarize` already applies to the medians themselves.
    static func medianDifferenceInterval(
        baseline: [Double],
        trial: [Double],
        iterations: Int = 2000,
        seed: UInt64 = 0x5A0E_1DA7_5EED_0002
    ) -> (lower: Double, upper: Double)? {
        guard baseline.count >= minimumPeriodNights, trial.count >= minimumPeriodNights else { return nil }

        var generator = SeededGenerator(seed: seed)
        var differences: [Double] = []
        differences.reserveCapacity(iterations)

        for _ in 0..<iterations {
            var baselineSample: [Double] = []
            baselineSample.reserveCapacity(baseline.count)
            for _ in 0..<baseline.count {
                baselineSample.append(baseline[Int.random(in: 0..<baseline.count, using: &generator)])
            }
            var trialSample: [Double] = []
            trialSample.reserveCapacity(trial.count)
            for _ in 0..<trial.count {
                trialSample.append(trial[Int.random(in: 0..<trial.count, using: &generator)])
            }
            if let baselineMedian = Statistics.median(baselineSample),
               let trialMedian = Statistics.median(trialSample) {
                differences.append(trialMedian - baselineMedian)
            }
        }

        guard let lower = Statistics.percentile(differences, 2.5),
              let upper = Statistics.percentile(differences, 97.5) else { return nil }
        return (lower, upper)
    }
}
