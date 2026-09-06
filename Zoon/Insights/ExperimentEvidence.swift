import Foundation

/// A finished Guided Experiment, as a ledger claim.
///
/// App-side rather than in `Shared/EvidenceClaims.swift` for the plain reason
/// that `SleepExperimentStore.Outcome` is app-side: the widget and watch
/// targets compile `Shared/` and have no experiment store to compile it
/// against. Everything else about a claim lives in that file.
///
/// This is the strongest kind of claim the app can make, and the only one
/// where the person declared what they were testing before the nights came
/// in. That is exactly why it needs the most careful reading, not the least:
/// a trial nobody actually complied with, or one that moved the metric by a
/// rounding error, is not a result in either direction, and the two guards
/// below are what stop it being written down as one.
extension EvidenceLedger {

    /// Bumped when a change to `GuidedExperiment.summarize` makes its
    /// numbers stop being comparable with earlier ones -- which is what
    /// `Revision.algorithmVersion` exists to record.
    static let experimentAlgorithmVersion = 1

    /// The share of trial nights that must have actually landed on the side
    /// the experiment was testing before its result means anything.
    ///
    /// `GuidedExperiment` already refuses to summarize below seven adherent
    /// nights, so this is the second, proportional bar: seven compliant
    /// nights out of ten is a trial, and seven out of forty is a month of
    /// not doing the thing with a week of doing it buried inside. The
    /// comparison is still computed -- the screen can show it as what it is
    /// -- but the ledger records it as `.inconclusive` rather than as an
    /// answer.
    static let experimentMinimumAdherence = 0.6

    /// How far the trial median must sit from the baseline, as a fraction of
    /// the baseline, before the difference is called a result.
    ///
    /// Not a significance test -- a before/after median comparison has no
    /// standard error to test against, which `GuidedExperiment` says plainly
    /// about itself. It is the smaller guard against the opposite mistake:
    /// reporting "not supported" because a metric moved 0.4% and happened to
    /// move the wrong way. Below this the honest answer is that the
    /// experiment did not separate the two periods.
    static let experimentMinimumRelativeChange = 0.05

    /// One completed experiment, as a claim.
    static func revision(
        for outcome: SleepExperimentStore.Outcome,
        at recordedAt: Date = .now
    ) -> Revision {
        // The thinner of the two sides, for the same reason `ZoonTwin`'s
        // claim uses the smaller group: a comparison built on 30 baseline
        // nights and 8 compliant trial nights rests on 8.
        let trialSize = outcome.trialCompliantNightCount ?? outcome.trialNightCount
        return Revision(
            claimID: Claim.experiment(tag: outcome.tag).id,
            recordedAt: recordedAt,
            status: experimentStatus(for: outcome),
            headline: experimentHeadline(for: outcome),
            effect: outcome.delta,
            // No unit: `Outcome.metricLabel` is the metric's *name* ("deep
            // sleep", "sleep efficiency"), not what it is measured in, and
            // the outcome record has never carried the second. Putting the
            // name here would render "+40 deep sleep". The name belongs in
            // `sourceFeature` and the headline, and both have it.
            effectUnit: nil,
            // A before/after median difference carries no interval, and the
            // summary never computed one. Left nil rather than fabricated.
            uncertaintyLower: nil,
            uncertaintyUpper: nil,
            sampleSize: min(outcome.baselineNightCount, trialSize),
            windowStart: outcome.startDate,
            windowEnd: outcome.endDate,
            algorithmVersion: experimentAlgorithmVersion,
            sourceFeature: outcome.metricLabel,
            provenance: "GuidedExperiment"
        )
    }

    static func experimentStatus(
        for outcome: SleepExperimentStore.Outcome
    ) -> Status {
        // Adherence first. A trial the behaviour was not actually kept in
        // cannot support or refute anything, whichever way the medians fell,
        // and checking the medians first would let a 20%-adherent trial
        // produce a confident "Not supported".
        guard let adherence = outcome.adherenceRate,
              adherence >= experimentMinimumAdherence else { return .inconclusive }

        let baseline = abs(outcome.baselineMedian)
        guard baseline > 0 else { return .inconclusive }
        guard abs(outcome.delta) / baseline >= experimentMinimumRelativeChange else {
            return .inconclusive
        }

        return outcome.isImprovement ? .supported : .notSupported
    }

    /// The sentence stored with the revision.
    ///
    /// Written here rather than taken from a view, because the ledger keeps
    /// the headline verbatim forever and a sentence assembled for one screen
    /// would carry that screen's assumptions into a record meant to outlive
    /// it. It names the behaviour, the direction, the size and the adherence
    /// -- the four things someone reading this row in a year would need to
    /// know whether to believe it.
    static func experimentHeadline(
        for outcome: SleepExperimentStore.Outcome
    ) -> String {
        // Lower-cased first letter only: the tag labels are written as
        // standalone captions ("Caffeine after 4pm") and these sentences put
        // them mid-clause. Lower-casing the whole label instead would be the
        // same fix everywhere today and wrong the first time a label carries
        // a proper noun.
        let label = BehaviorTag(rawValue: outcome.tag)?.label ?? outcome.tag
        let tag = label.prefix(1).lowercased() + label.dropFirst()
        let size = Change.formatted(outcome.delta, unit: nil)
        let adherence = outcome.adherenceRate.map { " Adherence \(Int(($0 * 100).rounded()))%." } ?? ""
        switch experimentStatus(for: outcome) {
        case .inconclusive:
            return "The \(tag) experiment did not separate the two periods.\(adherence)"
        case .supported:
            return "Testing \(tag) moved \(outcome.metricLabel) by \(size), in the direction hoped for.\(adherence)"
        default:
            return "Testing \(tag) moved \(outcome.metricLabel) by \(size), against the direction hoped for.\(adherence)"
        }
    }
}
