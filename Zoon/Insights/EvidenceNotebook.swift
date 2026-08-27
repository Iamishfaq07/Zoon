import Foundation

/// One durable, honestly-graded record of what this app has actually
/// established about a person -- and, just as importantly, what it has only
/// *noticed*.
///
/// The app already produces four kinds of claim from four different engines,
/// and left to themselves they all render as confident-looking sentences on
/// cards. They are not equally believable, and the difference is not a matter
/// of degree but of study design:
///
/// - A **Guided Experiment** outcome is the only one the person deliberately
///   set up in advance, with a metric chosen before the data came in and
///   adherence tracked while it ran. Still not randomised, still not
///   controlled, but pre-specified -- which is exactly the property that
///   stops a result from being the best of six metrics picked afterwards.
/// - A **Cause Finder** finding is a matched-pair comparison across many
///   nights with a bootstrap interval. Strong, but observational and
///   retrospective: the person chose when to drink, and whatever else drove
///   that choice rides along with it.
/// - A **change point** or **trend** is a description of history. Something
///   moved. Nothing at all is implied about why.
///
/// Sorting by that hierarchy first, and only then by recency, is the whole
/// point of the type: the most recent claim is usually the flimsiest, and a
/// reverse-chronological feed would put it on top every time.
enum EvidenceNotebook {

    /// How much weight a claim can carry, ordered weakest to strongest.
    ///
    /// Declared in ascending order so the implicit raw values encode the
    /// hierarchy directly. Anything inserted mid-list shifts the ones after
    /// it, which is the intended behaviour: a new tier takes its place in the
    /// ordering rather than being bolted on at the end.
    enum Strength: Int, CaseIterable, Comparable, Hashable, Sendable {
        /// One night. Interesting, never evidence.
        case anecdote
        /// A described change in history, with no comparison group at all.
        case observed
        /// A matched-pair association across many nights.
        case associated
        /// A pre-specified, adherence-tracked personal experiment.
        case tested

        static func < (a: Strength, b: Strength) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .anecdote: "Single night"
            case .observed: "Observed change"
            case .associated: "Association"
            case .tested: "You tested this"
            }
        }

        /// The honest one-line caveat for this tier. Shown with the entry,
        /// not buried in a help screen -- a caveat nobody reads is decoration.
        var caveat: String {
            switch self {
            case .anecdote:
                "One night only. Not a pattern, and not evidence of anything yet."
            case .observed:
                "Your history changed. Nothing here says what changed it."
            case .associated:
                "Matched comparison across many nights. Still what you happened to do, not a controlled test."
            case .tested:
                "You planned this one in advance, so the result isn't the best of several metrics picked afterwards."
            }
        }
    }

    struct Entry: Identifiable, Hashable, Sendable {
        let id: String
        /// The date the claim is *about* -- an experiment's end, a change
        /// point's date -- not when it was compiled.
        ///
        /// `nil` for a Cause Finder finding, which summarises a whole history
        /// rather than a moment. Deliberately optional rather than a
        /// far-future sentinel: a sentinel sorts correctly and then renders
        /// as a literal date somewhere in the year 4001 the first time a view
        /// formats it without checking.
        let date: Date?
        let headline: String
        let strength: Strength
        /// Present when the underlying engine produced one.
        let confidence: MetricConfidence?

        var caveat: String { strength.caveat }
    }

    /// The weakest claim allowed onto a glance surface.
    ///
    /// Higher than the bar for the Evidence screen, deliberately. On the
    /// phone every claim arrives with its tier heading above it and its
    /// caveat below it, and the reader has chosen to be there. A watch face
    /// or a complication has room for the sentence and almost nothing else,
    /// is read in two seconds, and is never scrolled.
    ///
    /// So the two tiers that depend most on their caveat are excluded.
    /// `.anecdote` is one night -- "interesting, never evidence" -- and
    /// `.observed` is a change with no comparison group, whose own caveat has
    /// to say that nothing here explains what caused it. Stripped of that
    /// sentence and shown alone on a wrist, both read as findings. An
    /// association at least rests on matched pairs across many nights.
    static let glanceMinimumStrength: Strength = .associated

    /// The single claim worth putting on a glance surface, or `nil`.
    ///
    /// Takes an already-compiled list rather than recompiling, so the watch
    /// and the Evidence screen cannot disagree about what the strongest
    /// claim is. `compile` returns strongest-first, so this is the first
    /// entry that clears the bar, not a re-sort.
    static func glanceHeadline(from entries: [Entry]) -> Entry? {
        entries.first { $0.strength >= glanceMinimumStrength }
    }

    // MARK: - Compilation

    /// Gathers every claim into one ranked list.
    ///
    /// Ordered by `strength` descending, then by `date` descending. Recency
    /// is the tie-breaker and never the primary key: a change point noticed
    /// this morning must not outrank an experiment the person actually ran.
    ///
    /// - Parameter nightReport: an optional `NightDetective` report. Only its
    ///   single top factor is admitted, and only as `.anecdote` -- listing
    ///   every excursion from one night would flood the notebook with the
    ///   weakest possible claims.
    static func compile(
        experiments: [SleepExperimentStore.Outcome] = [],
        findings: [JournalCorrelator.Finding] = [],
        changePoints: [ChangePointDetector.Result] = [],
        nightReport: NightDetective.Report? = nil
    ) -> [Entry] {
        var entries: [Entry] = []

        for outcome in experiments {
            let tag = BehaviorTag(rawValue: outcome.tag)?.label ?? outcome.tag
            let direction = outcome.isImprovement ? "improved" : "worsened"
            entries.append(Entry(
                id: "experiment-\(outcome.id.uuidString)",
                date: outcome.endDate,
                headline: "\(tag): \(outcome.metricLabel) \(direction) during your trial.",
                strength: .tested,
                confidence: nil
            ))
        }

        for finding in findings {
            let direction = finding.isImprovement ? "better" : "worse"
            // JournalCorrelator.Confidence and MetricConfidence are separate
            // enums that share three meaningful cases; map across rather than
            // making either one know about the other's extra case.
            let confidence: MetricConfidence
            switch finding.confidence {
            case .low: confidence = .low
            case .moderate: confidence = .moderate
            case .high: confidence = .high
            }
            entries.append(Entry(
                id: "finding-\(finding.id)",
                date: nil,
                headline: "\(finding.tag.label) goes with \(direction) \(finding.metric.shortLabel).",
                strength: .associated,
                confidence: confidence
            ))
        }

        for change in changePoints {
            entries.append(Entry(
                id: "change-\(change.id)",
                date: change.date,
                headline: change.sentence,
                strength: .observed,
                confidence: nil
            ))
        }

        if let nightReport, let top = nightReport.factors.first {
            entries.append(Entry(
                id: "night-\(nightReport.date.timeIntervalSince1970)-\(top.signal.rawValue)",
                date: nightReport.date,
                headline: top.sentence,
                strength: .anecdote,
                confidence: nil
            ))
        }

        return entries.sorted(by: isOrderedBefore)
    }

    /// Strength first, then undated history-wide claims, then most recent.
    ///
    /// A dateless finding sorts above a dated one *within its own tier*
    /// because "across all your nights" subsumes any single dated claim
    /// beside it. It never jumps a tier: strength is always compared first.
    private static func isOrderedBefore(_ a: Entry, _ b: Entry) -> Bool {
        if a.strength != b.strength { return a.strength > b.strength }
        switch (a.date, b.date) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case let (lhs?, rhs?): return lhs > rhs
        }
    }
}
