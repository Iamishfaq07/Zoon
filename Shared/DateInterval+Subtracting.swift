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
}
