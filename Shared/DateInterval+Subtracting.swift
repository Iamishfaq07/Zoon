import Foundation

extension DateInterval {

    /// `base` with every interval in `excluded` cut out.
    ///
    /// Used to build "today, minus any workouts" for the Stress Score: a hard
    /// run legitimately elevates heart rate, and averaging that in with the
    /// rest of the day reads exercise as autonomic stress -- the exact
    /// opposite of what the score is meant to say. Subtracting workout
    /// windows before averaging keeps the two concepts separate.
    ///
    /// `excluded` need not be sorted, non-overlapping, or clipped to `base` --
    /// this clips and merges them first, so two overlapping exclusions (or
    /// one that starts before `base` and ends after it) can't produce a
    /// negative-width or duplicate gap.
    static func subtracting(_ excluded: [DateInterval], from base: DateInterval) -> [DateInterval] {
        let clipped = excluded
            .compactMap { $0.intersection(with: base) }
            .sorted { $0.start < $1.start }

        guard !clipped.isEmpty else { return [base] }

        var result: [DateInterval] = []
        var cursor = base.start
        for interval in clipped {
            if interval.start > cursor {
                result.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < base.end {
            result.append(DateInterval(start: cursor, end: base.end))
        }
        return result
    }

    /// Merges overlapping intervals into their union, e.g. for combining two
    /// sources describing the same underlying event (a nap logged manually
    /// and the same nap auto-detected by HealthKit) without double-counting
    /// the minutes both agree on.
    ///
    /// The two sources rarely describe the *exact* same window -- a manual
    /// log's start/end is whenever the user tapped, not whenever their body
    /// actually fell asleep -- so any overlap at all, not just a large one,
    /// is treated as "the same event": once two intervals touch, the
    /// combined credit is their union's duration, not their sum. This
    /// intentionally never double-counts overlapping minutes, which matters
    /// more here than precisely classifying "is this really the same nap".
    static func merging(_ intervals: [DateInterval]) -> [DateInterval] {
        guard intervals.count > 1 else { return intervals }
        let sorted = intervals.sorted { $0.start < $1.start }

        var result: [DateInterval] = []
        var current = sorted[0]

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                if interval.end > current.end {
                    current = DateInterval(start: current.start, end: interval.end)
                }
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }
}
