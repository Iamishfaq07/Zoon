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

    /// How much iOS should favour this entry when picking what to surface in
    /// the Smart Stack -- the platform gap named in the Release 4 audit
    /// ("widget relevance") that every other one already had an answer for.
    ///
    /// There's no measured wake time on `SleepSnapshot` to anchor against,
    /// but `generatedAt` is a close proxy: the app writes a fresh snapshot
    /// once it finishes processing a night, which happens close to when the
    /// watch syncs after waking up. Scored high for the few hours right
    /// after that -- when someone is actually likely to check "how did I
    /// sleep" -- and low the rest of the day, rather than a flat score that
    /// gives the Smart Stack no signal about *when* this widget matters.
    /// Placeholder/mock entries stay at the low score: sample data
    /// shouldn't compete for a prominent slot.
    var relevance: TimelineEntryRelevance? {
        let score = WidgetRelevance.score(isPlaceholder: isPlaceholder, now: date, generatedAt: snapshot.generatedAt)
        return isPlaceholder
            ? TimelineEntryRelevance(score: score)
            : TimelineEntryRelevance(score: score, duration: 4 * 3600)
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

    func placeholder(in context: Context) -> SleepEntry {
        SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true)
    }

    /// Shown in the widget gallery. Always sample data — the gallery preview
    /// should look good and shouldn't leak a real user's numbers into a
    /// screenshot-heavy surface.
    func getSnapshot(in context: Context, completion: @escaping (SleepEntry) -> Void) {
        if context.isPreview {
            completion(SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepEntry>) -> Void) {
        let entry = currentEntry()

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
            return SleepEntry(date: .now, snapshot: snapshot, isPlaceholder: snapshot.isMock)
        }
        // No snapshot readable. Two causes: the app has never completed a
        // refresh, or no App Group is configured so the extension can't see the
        // app's container. Either way, show sample data clearly marked as such.
        return SleepEntry(date: .now, snapshot: MockData.snapshot, isPlaceholder: true)
    }
}
