import Foundation

/// How much a widget entry should be favoured for iOS's Smart Stack.
///
/// Pulled out of `ZoonWidget/SleepTimelineProvider.swift`'s `SleepEntry.relevance`
/// so the actual time-window logic is testable: `SleepEntry` itself lives in the
/// widget extension target (it conforms to WidgetKit's `TimelineEntry`), which
/// `ZoonTests` doesn't compile against.
enum WidgetRelevance {

    /// - Parameters:
    ///   - isPlaceholder: sample data shouldn't compete for a prominent slot.
    ///   - now: the entry's own date.
    ///   - generatedAt: when the snapshot was written.
    /// - Returns: 10 for placeholder data; 80 in the few hours right after a
    ///   fresh snapshot (when someone is actually likely to check "how did I
    ///   sleep"); 20 the rest of the day.
    static func score(isPlaceholder: Bool, now: Date, generatedAt: Date) -> Int {
        guard !isPlaceholder else { return 10 }
        let hoursSinceGenerated = now.timeIntervalSince(generatedAt) / 3600
        let recentlyRefreshed = hoursSinceGenerated >= 0 && hoursSinceGenerated < 4
        return recentlyRefreshed ? 80 : 20
    }
}
