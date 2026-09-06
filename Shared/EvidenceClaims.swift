import Foundation

/// What a claim *is*, and how each engine turns its own result into one.
///
/// `EvidenceLedger` knows how to keep a belief's history. Until this file
/// existed it did not know where beliefs came from: exactly one call site
/// built a revision, spelling its identifier inline as `"tag:\(rawValue)"`,
/// and every other engine in the app -- experiments, change points, the
/// twin, the sleep map -- changed its mind in private and left no trace.
///
/// Two problems, and they are the same problem seen from either end.
///
/// **Identity.** A claim's history is `history.filter { $0.claimID == ... }`,
/// so an identifier assembled by hand at each call site is a silent
/// correctness hazard: a typo splits one belief into two histories that each
/// look complete, and a collision merges two beliefs into one timeline that
/// reads as a single thing changing its mind. `Claim` makes the identifier a
/// value with one construction path and one parser, so neither can happen.
///
/// **Standing.** The engines do not all produce evidence of the same kind. A
/// pre-specified experiment, a matched-pair association and a contrast
/// between two groups of the person's own nights are three different
/// strengths of claim, and the ledger is the one place they get written down
/// side by side. `Claim.tier` carries that ordering explicitly so a screen
/// listing them cannot accidentally rank a scan above an experiment.
///
/// ## What is deliberately not recorded
///
/// Not every number an engine can produce belongs here. `ZoonTwin.projectAll`
/// and `SleepMap.build` are lenses a person points at their own history, and
/// writing down whatever the lens is pointed at would produce a revision per
/// screen visit -- the exact noise `EvidenceLedger`'s own doc comment says
/// buries the rows that matter.
///
/// So the recorders below take fixed configurations, not whatever a view has
/// in `@State`, and each claim is keyed by its *whole* configuration rather
/// than by a slot like "the strongest projection". A claim whose identity is
/// a slot changes subject between revisions, and its timeline would then
/// compare two unrelated comparisons and call the difference a change of
/// mind. Keying by configuration means a claim is about one fixed question
/// forever, which is the only way `change(from:to:)` says something true.
extension EvidenceLedger {

    /// A claim's stable identity across every revision of it.
    ///
    /// Cases are ordered weakest to strongest evidence, and `tier` depends on
    /// that order, so a new case goes in at its epistemic position rather
    /// than at the end.
    enum Claim: Hashable, Sendable {

        /// One region of the sleep map, keyed by the map's three metrics.
        case sleepMap(x: String, y: String, outcome: String)

        /// One `ZoonTwin` split: this lever, this direction, this outcome.
        case twin(lever: String, direction: String, outcome: String)

        /// A level shift in one metric.
        ///
        /// Keyed by metric alone, deliberately -- not by metric *and* date.
        /// "Your resting heart rate stepped up at some point" is one belief
        /// that Zoon can revise as more nights arrive, including revising
        /// *when* it happened. Folding the date into the identity would make
        /// every re-dated shift a brand new claim with no history, which is
        /// the opposite of what this ledger is for.
        case changePoint(metric: String)

        /// A matched-pair association for one behaviour, from Cause Finder.
        case behaviour(tag: String)

        /// A pre-specified experiment on one behaviour.
        ///
        /// Separate from `behaviour` even though both are about the same tag.
        /// They are two different claims about it -- "these nights differ"
        /// and "I set out to test this and here is what happened" -- and the
        /// second is the stronger one precisely because it was declared
        /// before the data came in. Merging their timelines would let an
        /// association silently supply the answer an experiment was supposed
        /// to earn.
        case experiment(tag: String)

        /// Separates the kind from its subject in `id`.
        ///
        /// Every component is an engine `rawValue` -- a Swift case name --
        /// so none of them can contain this. `parse` still checks the
        /// component count rather than trusting that.
        static let separator = ":"

        /// The string written to the ledger. Stable forever: changing one of
        /// these orphans every revision already recorded under it.
        var id: String {
            switch self {
            case let .sleepMap(x, y, outcome):
                Self.join("sleepMap", x, y, outcome)
            case let .twin(lever, direction, outcome):
                Self.join("twin", lever, direction, outcome)
            case let .changePoint(metric):
                Self.join("changePoint", metric)
            case let .behaviour(tag):
                Self.join("tag", tag)
            case let .experiment(tag):
                Self.join("experiment", tag)
            }
        }

        private static func join(_ parts: String...) -> String {
            parts.joined(separator: separator)
        }

        /// The inverse of `id`, for a reader that has only the stored string.
        ///
        /// Returns `nil` for anything it does not recognise rather than
        /// guessing. Old rows written under a kind a later release removed
        /// are exactly that case, and the ledger promises to keep them
        /// readable, so callers show the stored headline instead -- which is
        /// kept verbatim for this reason.
        static func parse(_ id: String) -> Claim? {
            let parts = id.components(separatedBy: separator)
            switch (parts.first ?? "", parts.count) {
            case ("sleepMap", 4): return .sleepMap(x: parts[1], y: parts[2], outcome: parts[3])
            case ("twin", 4): return .twin(lever: parts[1], direction: parts[2], outcome: parts[3])
            case ("changePoint", 2): return .changePoint(metric: parts[1])
            case ("tag", 2): return .behaviour(tag: parts[1])
            case ("experiment", 2): return .experiment(tag: parts[1])
            default: return nil
            }
        }

        /// Where this kind of claim sits in the evidence hierarchy, weakest
        /// first. The one number a screen should sort by when it is showing
        /// claims of different kinds together.
        var tier: Int {
            switch self {
            case .sleepMap: 0
            case .twin: 1
            case .changePoint: 2
            case .behaviour: 3
            case .experiment: 4
            }
        }

        /// What kind of evidence this is, in the words the app uses for it.
        var kindLabel: String {
            switch self {
            case .sleepMap: "Sleep map"
            case .twin: "Night comparison"
            case .changePoint: "Change over time"
            case .behaviour: "Cause Finder"
            case .experiment: "Experiment"
            }
        }
    }
}

// MARK: - Change points

extension EvidenceLedger {

    /// The version of the change-point method, bumped when a revision's
    /// numbers stop being comparable with the ones before it.
    ///
    /// Lives here rather than on `ChangePointDetector` for the same reason
    /// every other threshold in this area does: the ledger is what the
    /// number means something to.
    static let changePointAlgorithmVersion = 1

    /// A detected level shift, as a claim.
    ///
    /// Status is always `.observed`. A change point says a metric sat at one
    /// level and now sits at another; it does not say why, and nothing about
    /// the detection controls for anything. Calling it an association would
    /// be claiming a comparison that was never made.
    static func revision(
        for result: ChangePointDetector.Result,
        at recordedAt: Date = .now
    ) -> Revision {
        Revision(
            claimID: Claim.changePoint(metric: result.metric.rawValue).id,
            recordedAt: recordedAt,
            status: .observed,
            headline: result.sentence,
            effect: result.delta,
            effectUnit: result.metric.unitLabel,
            // The detector reports separation in standard errors, not an
            // interval on the difference, so there is no honest interval to
            // put here. Left nil rather than derived from the effect, which
            // would be inventing a precision the engine never computed.
            uncertaintyLower: nil,
            uncertaintyUpper: nil,
            sampleSize: result.beforeNights + result.afterNights,
            // The window is the history the split was found in, which is the
            // two segments together -- not the shift date, which is the
            // finding rather than its extent.
            windowStart: nil,
            windowEnd: result.date,
            algorithmVersion: changePointAlgorithmVersion,
            sourceFeature: result.metric.rawValue,
            provenance: "ChangePointDetector"
        )
    }
}

// MARK: - Twin projections

extension EvidenceLedger {

    static let twinAlgorithmVersion = 1

    /// The weakest confidence a projection may have and still be written
    /// down.
    ///
    /// `ZoonTwin` computes confidence from the smaller of its two groups,
    /// and below `.moderate` the split is a difference between two handfuls
    /// of nights. The screen may still draw it -- showing a thin comparison
    /// as thin is fine -- but the ledger is a record of what Zoon believed,
    /// and a number it would not stand behind is not a belief.
    static let twinMinimumConfidence = MetricConfidence.moderate

    /// One twin split, as a claim, or `nil` when the split is too thin to
    /// record.
    static func revision(
        for projection: ZoonTwin.Projection,
        at recordedAt: Date = .now
    ) -> Revision? {
        guard projection.confidence >= twinMinimumConfidence else { return nil }
        return Revision(
            claimID: Claim.twin(
                lever: projection.lever.rawValue,
                direction: projection.direction.rawValue,
                outcome: projection.outcome.rawValue
            ).id,
            recordedAt: recordedAt,
            status: .observed,
            headline: projection.sentence,
            effect: projection.delta,
            effectUnit: projection.outcome.unitLabel,
            // The two per-group ranges are spreads of nights, not an interval
            // on their difference, and putting one of them here would read as
            // the second. The nights are the evidence; the sample size says
            // how many there were.
            uncertaintyLower: nil,
            uncertaintyUpper: nil,
            // The smaller group. A contrast is only as strong as its thinner
            // side, the same rule `ZoonTwin.confidence(smallestGroup:)`
            // already applies -- and recording the total would make a 40/7
            // split look like 47 nights of evidence.
            sampleSize: min(projection.leverNights, projection.otherNights),
            windowStart: nil,
            windowEnd: nil,
            algorithmVersion: twinAlgorithmVersion,
            sourceFeature: projection.outcome.rawValue,
            provenance: "ZoonTwin"
        )
    }
}

// MARK: - Sleep map

extension EvidenceLedger {

    static let sleepMapAlgorithmVersion = 1

    /// One map's headline region, as a claim.
    ///
    /// Two statuses, and the difference between them is the whole reason
    /// `SleepMap.headlineIsSupported` exists: when the best region's interval
    /// still overlaps the next one's, the map has found where the better
    /// nights cluster but has not shown that region to be better, and
    /// `.inconclusive` is what that is. Recording both as `.observed` would
    /// erase a distinction the engine went to some trouble to compute.
    static func revision(
        for map: SleepMap.Map,
        at recordedAt: Date = .now
    ) -> Revision? {
        // A map with no scored region has found nothing to record.
        guard let best = map.best, best.medianOutcome != nil else { return nil }
        return Revision(
            claimID: Claim.sleepMap(
                x: map.xAxis.rawValue,
                y: map.yAxis.rawValue,
                outcome: map.outcome.rawValue
            ).id,
            recordedAt: recordedAt,
            status: map.headlineIsSupported ? .observed : .inconclusive,
            headline: map.sentence,
            // No effect, deliberately, and this is the one claim where that
            // is the honest answer. `Revision.effect` is a *signed change* --
            // `Change.formatted` puts a leading + or - on it, and every
            // consumer reads it as "the finding moved things by this much".
            // A map produces a level: the best region's median is 62 ms, not
            // +62 ms, and storing it here would render a measurement as a
            // difference from nothing. The median, its night count and its
            // region are all in `map.sentence`, which is kept verbatim.
            //
            // The region's interval goes with it. An interval whose point
            // estimate is not recorded is an invitation to compare it against
            // one that is.
            effect: nil,
            effectUnit: nil,
            uncertaintyLower: nil,
            uncertaintyUpper: nil,
            sampleSize: best.nightCount,
            windowStart: nil,
            windowEnd: nil,
            algorithmVersion: sleepMapAlgorithmVersion,
            sourceFeature: map.outcome.rawValue,
            provenance: "SleepMap"
        )
    }
}
