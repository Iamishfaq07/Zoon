import Foundation

/// One HealthKit sleep sample, stripped of `HKCategorySample` so overlap
/// arbitration can be tested without a fake `sourceRevision` (HealthKit
/// synthesises that from the running process and there is no public API
/// to override it on an unsaved sample — see `SleepSessionBuilderTests`).
///
/// `id` is this fragment's identity. `sourceUUID` is the original sample
/// UUID: two records with the same `sourceUUID` are the same write, not
/// two nights, and must not be counted twice.
struct SleepSampleRecord: Hashable, Sendable, Identifiable {
    let id: UUID
    let sourceUUID: UUID
    let start: Date
    let end: Date
    let stage: SleepStage
    let priority: SourcePriority
    var sourceBundleIdentifier: String = ""

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var interval: DateInterval { DateInterval(start: start, end: end) }

    init(
        id: UUID = UUID(),
        sourceUUID: UUID? = nil,
        start: Date,
        end: Date,
        stage: SleepStage,
        priority: SourcePriority,
        sourceBundleIdentifier: String = ""
    ) {
        self.id = id
        self.sourceUUID = sourceUUID ?? id
        self.start = start
        self.end = end
        self.stage = stage
        self.priority = priority
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }
}

/// Priority-and-UUID overlap arbitration for sleep samples.
///
/// `SleepSessionBuilder` still picks **one source per episode** as the
/// canonical night. Two trackers disagree about stage boundaries, and a
/// union of them is a night neither device reported. That choice stays.
///
/// What this type does is the narrower job the spec actually asked for:
/// when two samples *overlap in time*, the higher-priority writer keeps
/// the overlap, and the lower-priority writer is clipped to the minutes
/// it uniquely covers. UUID identity means the same sample arriving twice
/// is one sample. Disagreeing stage labels are never averaged, never
/// unioned, never "both" — the winner's stage is the stage of the
/// overlap, and the loser's remnant (if any) keeps the loser's stage.
///
/// Ladder, same as `SourcePriority`: Watch hardware, then a recognised
/// third-party wearable, then phone / manual.
enum SleepSourceArbitration {

    /// Dedup by `sourceUUID`, then clip lower-priority samples to the
    /// time they uniquely cover. Result is sorted by start, non-overlapping
    /// except at exact endpoints (touching is allowed; overlapping is not).
    static func fuse(_ samples: [SleepSampleRecord]) -> [SleepSampleRecord] {
        var seen = Set<UUID>()
        var unique: [SleepSampleRecord] = []
        unique.reserveCapacity(samples.count)
        for sample in samples {
            guard sample.end > sample.start else { continue }
            if seen.contains(sample.sourceUUID) { continue }
            seen.insert(sample.sourceUUID)
            unique.append(sample)
        }

        // Higher trust first (smaller rawValue), then earlier start, then
        // longer duration so a short flicker does not punch a hole in a
        // longer same-priority sample that already covers it.
        let ordered = unique.sorted { a, b in
            if a.priority != b.priority { return a.priority < b.priority }
            if a.start != b.start { return a.start < b.start }
            return a.duration > b.duration
        }

        var occupied: [DateInterval] = []
        var result: [SleepSampleRecord] = []
        result.reserveCapacity(ordered.count)

        for sample in ordered {
            let remnants = DateInterval.subtracting(occupied, from: sample.interval)
            for remnant in remnants where remnant.duration > 0 {
                result.append(
                    SleepSampleRecord(
                        id: UUID(),
                        sourceUUID: sample.sourceUUID,
                        start: remnant.start,
                        end: remnant.end,
                        stage: sample.stage,
                        priority: sample.priority,
                        sourceBundleIdentifier: sample.sourceBundleIdentifier
                    )
                )
            }
            occupied = DateInterval.merging(occupied + remnants)
        }

        return result.sorted { $0.start < $1.start }
    }

    /// After a winning source has been chosen, fill any holes in its
    /// coverage with lower-priority samples. Does **not** rewrite the
    /// winner: overlapping minutes stay the winner's stage, and winner
    /// records keep their original identity. `fuse` would re-arbitrate
    /// the winner against itself, which is wrong once a source has
    /// already been picked.
    ///
    /// Only *interior* gaps are filled. Every rival remnant is clipped to
    /// the winner's span (first start to last end): a phone `inBed`
    /// 22:00–08:00 must not stretch a Watch night of 23:00–07:00 into ten
    /// hours, because the minutes outside the winner's span are exactly
    /// the ones the winner said were not the night. Remnants entirely
    /// outside the span are dropped; those straddling an edge are trimmed.
    static func fillGaps(
        winner: [SleepSampleRecord],
        candidates: [SleepSampleRecord]
    ) -> [SleepSampleRecord] {
        let kept = winner.filter { $0.end > $0.start }
        guard let spanStart = kept.map(\.start).min(),
              let spanEnd = kept.map(\.end).max() else { return kept }
        let span = DateInterval(start: spanStart, end: spanEnd)
        var occupied = DateInterval.merging(kept.map(\.interval))
        var seen = Set(kept.map(\.sourceUUID))
        var extras: [SleepSampleRecord] = []

        let ordered = candidates
            .filter { $0.end > $0.start && !seen.contains($0.sourceUUID) }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority < b.priority }
                if a.start != b.start { return a.start < b.start }
                return a.duration > b.duration
            }

        for sample in ordered {
            if seen.contains(sample.sourceUUID) { continue }
            seen.insert(sample.sourceUUID)
            guard let clipped = sample.interval.intersection(with: span),
                  clipped.duration > 0 else { continue }
            let remnants = DateInterval.subtracting(occupied, from: clipped)
            for remnant in remnants where remnant.duration > 0 {
                extras.append(
                    SleepSampleRecord(
                        id: UUID(),
                        sourceUUID: sample.sourceUUID,
                        start: remnant.start,
                        end: remnant.end,
                        stage: sample.stage,
                        priority: sample.priority,
                        sourceBundleIdentifier: sample.sourceBundleIdentifier
                    )
                )
            }
            occupied = DateInterval.merging(occupied + remnants)
        }

        return (kept + extras).sorted { $0.start < $1.start }
    }
}
