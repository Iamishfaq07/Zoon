import Foundation
import SwiftData

/// One recorded belief, kept forever.
///
/// The whole point of `EvidenceLedger` is that previous beliefs are never
/// erased, which makes this the one table in the app that is append-only by
/// design. Nothing here updates a row: a changed belief is a new row, and the
/// old one stays exactly as it was written.
///
/// Fields are flat and primitive rather than a JSON blob, unlike
/// `stageSegmentsData`. The difference is what they are for: stage segments
/// are only ever read whole to draw one hypnogram, while these are queried
/// across -- every revision of one claim, the most recently changed claims,
/// eventually "what did Zoon believe in March". A blob cannot answer those
/// without decoding every row.
@Model
final class EvidenceRevisionRecord {

    /// Stable across every revision of the same claim, e.g. "tag:caffeineLate".
    var claimID: String
    /// When Zoon formed this belief -- not when the underlying nights happened.
    var recordedAt: Date

    /// `EvidenceLedger.Status.rawValue`. Stored raw so a status added or
    /// renamed in a later release leaves old rows readable rather than
    /// failing the whole fetch.
    var statusRaw: String
    /// The sentence as it was shown at the time, kept verbatim. Regenerating
    /// it later from current code would show what Zoon would say *now*, which
    /// is precisely the thing this table exists to stop.
    var headline: String

    var effect: Double?
    var effectUnit: String?
    var uncertaintyLower: Double?
    var uncertaintyUpper: Double?
    var sampleSize: Int

    var windowStart: Date?
    var windowEnd: Date?

    /// The engine version that produced the effect. An old number computed by
    /// a model that no longer exists is only interpretable if you can tell
    /// that is what it is.
    var algorithmVersion: Int
    var sourceFeature: String
    var provenance: String

    init(_ revision: EvidenceLedger.Revision) {
        self.claimID = revision.claimID
        self.recordedAt = revision.recordedAt
        self.statusRaw = revision.status.rawValue
        self.headline = revision.headline
        self.effect = revision.effect
        self.effectUnit = revision.effectUnit
        self.uncertaintyLower = revision.uncertaintyLower
        self.uncertaintyUpper = revision.uncertaintyUpper
        self.sampleSize = revision.sampleSize
        self.windowStart = revision.windowStart
        self.windowEnd = revision.windowEnd
        self.algorithmVersion = revision.algorithmVersion
        self.sourceFeature = revision.sourceFeature
        self.provenance = revision.provenance
    }

    /// Back to the value type the engine and the views work in.
    ///
    /// An unreadable status resolves to `.learning` rather than throwing:
    /// losing one row's label is recoverable, and failing the fetch would
    /// take the entire history down with it.
    var revision: EvidenceLedger.Revision {
        EvidenceLedger.Revision(
            claimID: claimID,
            recordedAt: recordedAt,
            status: EvidenceLedger.Status(rawValue: statusRaw) ?? .learning,
            headline: headline,
            effect: effect,
            effectUnit: effectUnit,
            uncertaintyLower: uncertaintyLower,
            uncertaintyUpper: uncertaintyUpper,
            sampleSize: sampleSize,
            windowStart: windowStart,
            windowEnd: windowEnd,
            algorithmVersion: algorithmVersion,
            sourceFeature: sourceFeature,
            provenance: provenance
        )
    }
}
