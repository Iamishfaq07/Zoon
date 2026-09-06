import WidgetKit
import SwiftUI

/// Timeline entry carrying one snapshot.
struct SleepEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepSnapshot
    /// True when showing sample data because no real snapshot was readable.
    /// The widget marks these so a home screen never displays invented health
    /// numbers as if they were measured.
    let isPlaceholder: Bool
    /// Which widget this entry is for. Relevance is per-surface, so the entry
    /// has to know which surface it belongs to -- see `WidgetRelevance`.
    var kind: SurfaceRelevance.Kind = .lastNight

    /// How much iOS should favour this entry when picking what to surface in
    /// the Smart Stack.
    ///
    /// Every widget in this extension used to share one score computed from
    /// how recently the phone had written a snapshot. That is a *freshness*
    /// signal, not a relevance one, and with all four returning it at the
    /// same time the Smart Stack had nothing to order them by -- the same
    /// defect `SurfaceRelevance` fixed on the watch, which survived here
    /// because the type that fixed it was named after the other platform.
    ///
    /// Judged at `date`, the instant this entry is *for*, never at the
    /// instant the snapshot was written: an entry an hour out must not
    /// inherit the nap state of an hour ago, and the snapshot stores absolute
    /// instants precisely so this can be re-decided per entry.
    var relevance: TimelineEntryRelevance? {
        let score = Float(
            WidgetRelevance.score(
                for: kind,
                isPlaceholder: isPlaceholder,
                now: date,
                generatedAt: snapshot.generatedAt,
                isNapRunning: snapshot.isNapRunning(at: date),
                isShiftWorkModeEnabled: snapshot.isShiftWorkModeEnabled
            )
        )
        return isPlaceholder
            ? TimelineEntryRelevance(score: score)
            : TimelineEntryRelevance(score: score, duration: SurfaceRelevance.duration)
    }
}

/// Supplies entries from the snapshot the app writes.
///
/// The refresh strategy is intentionally lazy. Sleep data changes once a day,
/// in the morning, and the app calls `WidgetCenter.reloadAllTimelines()` the
/// moment it processes a new night — so the timeline exists as a safety net, not
/// as the primary update path. Requesting frequent refreshes would burn the
/// widget's daily budget and get the extension throttled, making it *less*
/// current, not more.
struct SleepTimelineProvider: TimelineProvider {

    /// Which widget this provider feeds, so its entries can carry a relevance
    /// that is about this surface rather than about the extension. Defaulted
    /// so a caller that has no opinion still gets the morning window rather
    /// than a compile error, which is the behaviour every widget had before
    /// any of them had an opinion.
    var kind: SurfaceRelevance.Kind = .lastNight

    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true, kind: kind)
    }

    /// Shown in the widget gallery. Always sample data — the gallery preview
    /// should look good and shouldn't leak a real user's numbers into a
    /// screenshot-heavy surface.
    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        if context.isPreview {
            completion(SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true, kind: kind))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let entry = currentEntry()

        // A running nap suppresses every widget here, exactly as it does on
        // the watch, so the timeline has to schedule the instant that lifts.
        // Without it they all stay demoted until tomorrow morning's refresh --
        // Zoon absent from the Smart Stack for the rest of the day because of
        // a twenty-minute nap.
        if let napEnd = entry.snapshot.napSuppressionEnd,
           entry.snapshot.isNapRunning(at: entry.date),
           napEnd > entry.date {
            let after = SleepEntry(
                date: napEnd, snapshot: entry.snapshot,
                isPlaceholder: entry.isPlaceholder, kind: kind
            )
            completion(Timeline(entries: [entry, after], policy: .after(napEnd)))
            return
        }

        // Next scheduled wake-up: the following morning at 09:00, by which time
        // the watch has normally synced the night. The app's explicit reload
        // usually beats this.
        let calendar = Calendar.current
        let tomorrowMorning = calendar.nextDate(
            after: .now,
            matching: DateComponents(hour: 9, minute: 0),
            matchingPolicy: .nextTime
        ) ?? Date.now.addingTimeInterval(6 * 3600)

        completion(Timeline(entries: [entry], policy: .after(tomorrowMorning)))
    }

    private func currentEntry() -> SleepEntry {
        if let snapshot = SnapshotStore.read() {
            return SleepEntry(
                date: .now, snapshot: snapshot, isPlaceholder: snapshot.isMock, kind: kind
            )
        }
        // No snapshot readable. Two causes: the app has never completed a
        // refresh, or no App Group is configured so the extension can't see the
        // app's container. Either way, show sample data clearly marked as such.
        return SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true, kind: kind)
    }
}
