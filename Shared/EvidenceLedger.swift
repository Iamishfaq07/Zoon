import Foundation

/// How a belief changed, kept rather than replaced.
///
/// `EvidenceNotebook` compiles what Zoon believes *now*: it runs the engines
/// over current history and ranks the results. Ask it what it thought three
/// weeks ago and it has no answer, because nothing was ever written down.
/// That is the whole gap this closes.
///
/// It matters more here than it would in most apps. Zoon tells people their
/// own data changed its mind -- an association appears, an experiment
/// contradicts it, a longer window washes it out -- and "we now think X" is a
/// much weaker thing to say than "on 3 February this was still learning, on
/// 21 February an association appeared across 17 matched nights, and on 22
/// March a pre-specified experiment put the effect at +9 minutes." The second
/// is checkable. The first asks to be trusted.
///
/// ## Never erase, but do not log
///
/// The two failure modes point in opposite directions. Overwriting the
/// previous belief destroys the history. Appending the current belief on
/// every refresh produces a revision every time the app opens, and a
/// thousand identical rows hide the four that matter as effectively as
/// deleting them would.
///
/// So a revision is recorded only when the belief has *materially* changed --
/// see `hasMateriallyChanged(from:)`, which is where every threshold in this
/// file lives so they can be argued with in one place.
enum EvidenceLedger {

    /// Where a claim stands. Ordered roughly weakest to strongest, though
    /// the sequence is not monotonic in practice: a claim can go from
    /// `supported` back to `inconclusive` when a longer window washes an
    /// effect out, and recording that is the point.
    enum Status: String, Codable, CaseIterable, Hashable, Sendable {
        /// Seen, not yet enough matched nights to compare.
        case learning
        /// A matched-pair association exists.
        case associated
        /// A pre-specified experiment is running.
        case testing
        /// The experiment agreed with the association.
        case supported
        /// The experiment disagreed with it.
        case notSupported
        /// Enough data to look, not enough signal to call it either way.
        case inconclusive
        /// A later revision replaced the claim this one made.
        case superseded

        var label: String {
            switch self {
            case .learning: "Learning"
            case .associated: "Association detected"
            case .testing: "Experiment started"
            case .supported: "Supported"
            case .notSupported: "Not supported"
            case .inconclusive: "Inconclusive"
            case .superseded: "Superseded"
            }
        }
    }

    /// One entry in a claim's history.
    ///
    /// Every field the V9 spec asks a revision to carry: what was believed,
    /// how strongly, over which window, from how many nights, by which
    /// algorithm version, and where the number came from. The provenance and
    /// version fields are what make an old revision interpretable at all --
    /// an effect recorded under a scoring model that no longer exists is
    /// only meaningful if you can tell that is what happened.
    struct Revision: Codable, Hashable, Sendable, Identifiable {
        /// Stable across revisions of the same claim, e.g. "tag:caffeineLate".
        let claimID: String
        let recordedAt: Date
        let status: Status
        /// The sentence as it was shown at the time.
        let headline: String
        /// Signed effect in `effectUnit`, when there was one.
        let effect: Double?
        let effectUnit: String?
        /// The interval around `effect`, when the engine produced one.
        let uncertaintyLower: Double?
        let uncertaintyUpper: Double?
        /// Matched pairs, experiment nights -- whatever the claim rests on.
        let sampleSize: Int
        /// The history this was computed over.
        let windowStart: Date?
        let windowEnd: Date?
        /// The engine version that produced it. An effect from a superseded
        /// model is not comparable with a current one.
        let algorithmVersion: Int
        /// Which measurement the claim is about, e.g. "sleepEfficiency".
        let sourceFeature: String
        /// Which engine said so, e.g. "JournalCorrelator".
        let provenance: String

        var id: String { "\(claimID)-\(recordedAt.timeIntervalSince1970)" }

        /// A meaningful sample growth before an otherwise-identical belief is
        /// worth writing down again.
        ///
        /// Half as much data again. Below that the interval barely moves and
        /// the row would say nothing the previous one did not; above it, the
        /// claim genuinely rests on different evidence even when the number
        /// lands in the same place.
        static let materialSampleGrowth = 1.5

        /// Whether this belief differs from `previous` enough to be worth
        /// keeping as its own revision.
        ///
        /// Four ways a belief can change, and each is recorded:
        ///
        /// 1. The status moved. Always material -- it is the headline of the
        ///    whole timeline.
        /// 2. The algorithm changed. An effect computed by a different model
        ///    is a different claim even at the same number, which is why
        ///    `SleepIntelligenceScore.currentVersion` exists at all.
        /// 3. The effect moved outside the previous uncertainty interval.
        ///    Inside it, the two readings are the same claim with more data;
        ///    outside it, Zoon has changed its mind about the size.
        /// 4. The sample grew by half again. Same conclusion, materially more
        ///    evidence behind it.
        ///
        /// Anything else is the same belief seen again, and appending it
        /// would bury the four above in noise.
        func hasMateriallyChanged(from previous: Revision?) -> Bool {
            guard let previous else { return true }
            if status != previous.status { return true }
            if algorithmVersion != previous.algorithmVersion { return true }
            if Double(sampleSize) >= Double(previous.sampleSize) * Self.materialSampleGrowth,
               sampleSize > previous.sampleSize {
                return true
            }
            if let effect,
               let lower = previous.uncertaintyLower,
               let upper = previous.uncertaintyUpper,
               effect < lower || effect > upper {
                return true
            }
            return false
        }
    }

    /// Appends `candidate` to a claim's history when it says something new.
    ///
    /// Returns the history unchanged when it does not, so a caller can run
    /// this on every refresh without thinking about it -- which is the point,
    /// since a rule only applied when someone remembers is not a rule.
    static func recording(
        _ candidate: Revision,
        into history: [Revision]
    ) -> [Revision] {
        let mine = history.filter { $0.claimID == candidate.claimID }
        let latest = mine.max { $0.recordedAt < $1.recordedAt }
        guard candidate.hasMateriallyChanged(from: latest) else { return history }
        return history + [candidate]
    }

    /// One claim's history, oldest first -- the order a timeline reads in.
    ///
    /// Oldest first rather than newest first on purpose. This screen exists
    /// to show how a belief arrived at where it is, and that story only makes
    /// sense forwards.
    static func timeline(for claimID: String, in history: [Revision]) -> [Revision] {
        history
            .filter { $0.claimID == claimID }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    /// Every claim that has a history, most recently updated first.
    static func claimIDs(in history: [Revision]) -> [String] {
        var newestByClaim: [String: Date] = [:]
        for revision in history {
            let existing = newestByClaim[revision.claimID]
            if existing == nil || revision.recordedAt > existing! {
                newestByClaim[revision.claimID] = revision.recordedAt
            }
        }
        return newestByClaim.sorted { $0.value > $1.value }.map(\.key)
    }
}

// MARK: - Why did this change?

extension EvidenceLedger {

    /// The difference between one revision and the one before it, in the
    /// terms a person would ask about.
    ///
    /// The timeline already shows *that* a belief moved. This says *why*,
    /// which is the difference between a system that reports and one that
    /// can be checked. The reasons are the same four `hasMateriallyChanged`
    /// tests -- there is deliberately no fifth, because a change the ledger
    /// would not have recorded is not a change that needs explaining.
    struct Change: Hashable, Sendable {

        /// What moved, in the order that explains the most.
        enum Reason: Hashable, Sendable {
            /// The engine itself changed. Listed first wherever it appears,
            /// because it makes the other comparisons meaningless.
            case methodChanged(from: Int, to: Int)
            case statusMoved(from: Status, to: Status)
            /// Only ever produced when the method did *not* change.
            case effectMoved(from: Double, to: Double, unit: String?)
            case evidenceGrew(added: Int)
            case evidenceShrank(removed: Int)
        }

        let previous: Revision
        let current: Revision
        let reasons: [Reason]

        /// Whether the two revisions' numbers can be compared at all.
        ///
        /// They cannot when a different algorithm produced them. This is the
        /// same principle `Revision.algorithmVersion` exists for: an effect
        /// from a superseded model is not a smaller or larger version of the
        /// current one, it is a different measurement, and putting the two
        /// side by side invites a comparison that was never valid.
        var isComparable: Bool { previous.algorithmVersion == current.algorithmVersion }

        // MARK: The three lines

        /// "Association detected, +3 minutes, 8 nights"
        var earlierLine: String { Self.reading(previous) }

        /// "Supported, +11 minutes, 17 nights"
        var nowLine: String { Self.reading(current) }

        /// Why the two differ, in sentences.
        ///
        /// Empty when nothing material moved, which the ledger would not
        /// have recorded in the first place -- so a caller showing this can
        /// treat an empty string as "there is nothing to explain" rather
        /// than having to decide for itself.
        var whyLine: String {
            reasons.map(Self.sentence).joined(separator: " ")
        }

        private static func reading(_ revision: Revision) -> String {
            var parts = [revision.status.label]
            if let effect = revision.effect {
                parts.append(formatted(effect, unit: revision.effectUnit))
            }
            parts.append("\(revision.sampleSize) night\(revision.sampleSize == 1 ? "" : "s")")
            return parts.joined(separator: ", ")
        }

        /// Signed, because the sign is the finding: "3 minutes" does not say
        /// whether the night got better or worse.
        static func formatted(_ effect: Double, unit: String?) -> String {
            let rounded = (effect * 10).rounded() / 10
            let magnitude = rounded == rounded.rounded()
                ? String(format: "%.0f", abs(rounded))
                : String(format: "%.1f", abs(rounded))
            let signed = (rounded < 0 ? "-" : "+") + magnitude
            guard let unit, !unit.isEmpty else { return signed }
            return "\(signed) \(unit)"
        }

        static func sentence(for reason: Reason) -> String {
            switch reason {
            case let .methodChanged(from, to):
                // Deliberately not "the effect changed". It did not: the
                // instrument did, and the two readings were never on the
                // same scale.
                return "Zoon's method changed (v\(from) to v\(to)), so this reading isn't a"
                    + " larger or smaller version of the last one -- it's a different measurement."
            case let .statusMoved(from, to):
                return "\(from.label) became \(to.label)."
            case let .effectMoved(from, to, unit):
                return "The effect moved from \(formatted(from, unit: unit)) to \(formatted(to, unit: unit))."
            case let .evidenceGrew(added):
                return "\(added) new comparable night\(added == 1 ? " was" : "s were") added."
            case let .evidenceShrank(removed):
                return "\(removed) night\(removed == 1 ? "" : "s") dropped out of the window."
            }
        }
    }

    /// The change that produced `revision`, or `nil` when it is the first
    /// thing ever recorded about its claim -- a first belief did not change
    /// from anything, and saying it did would invent a history.
    static func change(to revision: Revision, in history: [Revision]) -> Change? {
        let earlier = history
            .filter { $0.claimID == revision.claimID && $0.recordedAt < revision.recordedAt }
            .max { $0.recordedAt < $1.recordedAt }
        guard let previous = earlier else { return nil }
        return change(from: previous, to: revision)
    }

    static func change(from previous: Revision, to current: Revision) -> Change {
        var reasons: [Change.Reason] = []

        let methodChanged = previous.algorithmVersion != current.algorithmVersion
        if methodChanged {
            reasons.append(.methodChanged(
                from: previous.algorithmVersion, to: current.algorithmVersion
            ))
        }

        if previous.status != current.status {
            reasons.append(.statusMoved(from: previous.status, to: current.status))
        }

        // Suppressed outright when the method changed. Two numbers from two
        // models are not a movement, and "+3 became +11" would read as one.
        if !methodChanged,
           let before = previous.effect,
           let after = current.effect,
           before != after {
            reasons.append(.effectMoved(from: before, to: after, unit: current.effectUnit))
        }

        let delta = current.sampleSize - previous.sampleSize
        if delta > 0 {
            reasons.append(.evidenceGrew(added: delta))
        } else if delta < 0 {
            // Said rather than hidden. A shrinking sample is unusual -- a
            // window rolling forward past old nights, an entry deleted --
            // and it is exactly the case where a silently moving number
            // would look like new evidence.
            reasons.append(.evidenceShrank(removed: -delta))
        }

        return Change(previous: previous, current: current, reasons: reasons)
    }
}
