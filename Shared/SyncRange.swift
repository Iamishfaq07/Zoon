import Foundation

/// Which slices of history a HealthKit delta actually requires rebuilding.
///
/// The sync path used the anchored query as a *change gate* and nothing more:
/// if anything at all had changed, it discarded the delta and re-fetched the
/// entire 90-day window, then rebuilt and re-upserted every night in it. One
/// corrected nap from last Tuesday cost the same work as a first launch.
///
/// The anchored delta genuinely cannot be rebuilt from directly -- the
/// original comment is right that a delta can land mid-night, and segmenting
/// against a partial picture would split one night into two. But that is an
/// argument for fetching *enough surrounding context*, not for fetching
/// everything. This works out the windows that actually need re-reading.
///
/// Deliberately free of HealthKit: it takes `Date`s, so it is testable
/// without a store, a device, or a sample.
enum SyncRange {

    /// How far either side of a changed instant to reach.
    ///
    /// A sleep session spans at most about fourteen hours, and
    /// `SleepSessionBuilder` merges across gaps within a night. Eighteen hours
    /// either side therefore guarantees that whatever night contains the
    /// changed instant is fully inside the rebuilt range, boundaries included
    /// -- which is the whole requirement, since a partially-covered night is
    /// exactly the failure the full-window fetch was avoiding.
    static let contextHours: Double = 18

    /// Beyond this share of the window, a partial rebuild is not worth the
    /// bookkeeping and the full window is simpler and safer.
    static let fullRebuildFraction: Double = 0.4

    /// Merges overlapping or touching intervals into the fewest that cover
    /// the same instants.
    ///
    /// - Parameter gapTolerance: intervals separated by no more than this are
    ///   merged. Two nights a few hours apart are cheaper to rebuild as one
    ///   range than as two overlapping fetches.
    static func merge(_ intervals: [DateInterval], gapTolerance: TimeInterval = 0) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]

        for interval in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if interval.start <= last.end.addingTimeInterval(gapTolerance) {
                merged[merged.count - 1] = DateInterval(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// The windows to re-read, given the instants a delta touched.
    ///
    /// Each instant is padded by `contextHours` either side, clamped to the
    /// sync window, then merged. Returns an empty array when nothing changed,
    /// which the caller should read as "no work", not as "rebuild nothing of
    /// a window that needed it".
    static func affected(
        changedAt instants: [Date],
        clampedTo window: DateInterval,
        contextHours: Double = contextHours
    ) -> [DateInterval] {
        guard !instants.isEmpty else { return [] }
        let padding = contextHours * 3600

        let padded = instants.compactMap { instant -> DateInterval? in
            let start = max(window.start, instant.addingTimeInterval(-padding))
            let end = min(window.end, instant.addingTimeInterval(padding))
            // An instant outside the window pads to an inverted range.
            // `DateInterval(start:end:)` traps on that, so it is dropped:
            // a change outside the window is not this pass's business.
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }

        // Merged with a tolerance of the same padding, so two changed nights
        // within a day and a half of each other become one fetch.
        return merge(padded, gapTolerance: padding)
    }

    /// Whether rebuilding `ranges` is actually cheaper than the whole window.
    ///
    /// A delta scattered across most of the window has no partial path worth
    /// taking -- the ranges would nearly cover it anyway, and the full fetch
    /// is one query instead of many.
    static func isPartialRebuildWorthwhile(
        _ ranges: [DateInterval],
        window: DateInterval,
        fullRebuildFraction: Double = fullRebuildFraction
    ) -> Bool {
        guard !ranges.isEmpty else { return false }
        let windowDuration = window.duration
        guard windowDuration > 0 else { return false }
        let covered = ranges.reduce(0) { $0 + $1.duration }
        return covered / windowDuration <= fullRebuildFraction
    }

    /// How far back to re-extract on every refresh regardless of the sleep
    /// delta.
    ///
    /// This exists because of an asymmetry that is easy to miss. The anchored
    /// query is on `sleepAnalysis` alone, so a change to *physiology* -- the
    /// HRV, resting heart rate, respiratory rate, wrist temperature or
    /// breathing disturbances for a night already stored -- produces an
    /// **empty delta**. Watch physiology commonly lands minutes to tens of
    /// minutes after the stages do.
    ///
    /// So widening the observer set is necessary but not sufficient: without
    /// this floor, a late-HRV observer would wake Zoon up and Zoon would find
    /// no sleep changes and do nothing, which is the same outcome as not
    /// observing at all. Three days is comfortably past when a night's
    /// physiology stops arriving, while still being a tiny fraction of the
    /// ninety-day window.
    static let physiologyRecheckDays = 3

    /// The single decision the sync path needs.
    enum Plan: Equatable {
        /// Nothing to re-extract.
        case nothingToDo
        /// Rebuild only the nights intersecting these windows.
        case partial([DateInterval])
        /// Rebuild every night in the sync window.
        case full
    }

    /// - Parameters:
    ///   - changedAt: the instants covered by changed sleep samples. For a
    ///     sample, both its start and its end, since either edge moving
    ///     changes which night it belongs to.
    ///   - hasDeletions: whether the delta reported deleted objects.
    ///     **Forces `.full`.** HealthKit reports deletions as bare UUIDs with
    ///     no dates, so there is no instant to build a range around, and a
    ///     deletion is exactly the case that has to reach
    ///     `SleepHistoryStore.prune` over a window wide enough to contain the
    ///     night that vanished.
    ///   - storeIsEmpty: first launch, or after an erase. Always `.full`.
    ///   - recheckFrom: the floor described by `physiologyRecheckDays`. Always
    ///     included in the returned ranges, so a physiology-only change is
    ///     picked up even though it produces no sleep delta. Pass `nil` to
    ///     opt out.
    static func plan(
        changedAt instants: [Date],
        hasDeletions: Bool,
        storeIsEmpty: Bool,
        window: DateInterval,
        recheckFrom: Date? = nil
    ) -> Plan {
        if storeIsEmpty || hasDeletions {
            return .full
        }

        var candidates = affected(changedAt: instants, clampedTo: window)

        if let recheckFrom {
            let start = max(window.start, recheckFrom)
            if start < window.end {
                candidates.append(DateInterval(start: start, end: window.end))
            }
        }

        let ranges = merge(candidates, gapTolerance: contextHours * 3600)
        guard !ranges.isEmpty else { return .nothingToDo }
        return isPartialRebuildWorthwhile(ranges, window: window) ? .partial(ranges) : .full
    }
}
