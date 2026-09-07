import Foundation

/// How much a widget entry should be favoured for iOS's Smart Stack.
///
/// Pulled out of `ZoonWidget/SleepTimelineProvider.swift`'s `SleepEntry.relevance`
/// so the actual logic is testable: `SleepEntry` itself lives in the widget
/// extension target (it conforms to WidgetKit's `TimelineEntry`), which
/// `ZoonTests` doesn't compile against.
///
/// ## Freshness is not relevance
///
/// This used to answer with freshness alone -- 80 for a few hours after a
/// snapshot arrived, 20 the rest of the day -- and all four iOS widgets
/// shared one provider, so all four returned the same number at the same
/// time. The Smart Stack had nothing to order them by.
///
/// That is word for word the defect `SurfaceRelevance` was written to fix on
/// the watch, and it stayed here through a release because the type that
/// fixed it was called `WatchRelevance`. It is not called that any more.
///
/// The two judgments are still separate, which is the part worth keeping
/// from the old version: *when does this surface matter* and *is this data
/// current* are different questions, and a stale number is not worth raising
/// however well its hour matches.
enum WidgetRelevance {

    /// Placeholder entries never compete. Sample data must not take a
    /// prominent slot from a real reading.
    static let placeholderScore: Int = 10

    /// After this long without a fresh snapshot, the number is stale and its
    /// window no longer earns it a promotion.
    static let staleAfterHours: Double = 24

    /// Surfaces whose day-part window does not apply when the person has
    /// told the app their day is not shaped like the clock.
    ///
    /// The windows below assume "morning" means the morning. For a shift
    /// worker waking at three in the afternoon, that would put *last night*
    /// out of window at the one moment it is most wanted -- a regression the
    /// freshness-only rule this replaced did not have.
    ///
    /// The obvious repair is to promote whatever arrived recently, and it is
    /// wrong: `generatedAt` is when the app last refreshed, not when a night
    /// was processed, so it goes high every time someone opens the app and
    /// puts back most of the defect. `SleepSnapshot` carries no wake time to
    /// use instead.
    ///
    /// What it does carry is `isShiftWorkModeEnabled` -- the person having
    /// said so themselves, which is better evidence than any proxy derived
    /// from it. When that is set, last night stays available all day rather
    /// than being ranked by an assumption they have already rejected.
    static let alwaysAvailableInShiftWork: Set<SurfaceRelevance.Kind> = [.lastNight]

    /// The Smart Stack score for one widget surface.
    ///
    /// - Parameters:
    ///   - kind: which surface this entry is for. The whole point: four
    ///     widgets that answer with one score are four widgets the system
    ///     cannot rank.
    ///   - isPlaceholder: sample data shouldn't compete for a prominent slot.
    ///   - now: the entry's own date, not the snapshot's -- an entry an hour
    ///     out must be judged on the hour it is for.
    ///   - generatedAt: when the snapshot was written.
    ///   - isNapRunning: judged at `now` by the caller, for the same reason.
    ///   - isShiftWorkModeEnabled: see `alwaysAvailableInShiftWork`.
    static func score(
        for kind: SurfaceRelevance.Kind,
        isPlaceholder: Bool,
        now: Date,
        generatedAt: Date,
        isNapRunning: Bool = false,
        isShiftWorkModeEnabled: Bool = false,
        calendar: Calendar = .current
    ) -> Int {
        guard !isPlaceholder else { return placeholderScore }

        var windowed = SurfaceRelevance.score(
            for: kind, at: now, isNapRunning: isNapRunning, calendar: calendar
        )

        // Applied before the freshness gate and the nap check, both of which
        // may still pull it back down -- shift work changes which hours count
        // as this person's morning, not whether stale data or a running nap
        // outrank it.
        if isShiftWorkModeEnabled, !isNapRunning, alwaysAvailableInShiftWork.contains(kind) {
            windowed = max(windowed, SurfaceRelevance.inWindowScore)
        }

        // Freshness gates the window rather than replacing it. Same rule the
        // watch bundle applies, in the same words: a stale number is not
        // worth raising however well its hour matches.
        let hoursSinceGenerated = now.timeIntervalSince(generatedAt) / 3600
        let isStale = hoursSinceGenerated < 0 || hoursSinceGenerated >= staleAfterHours
        return Int(isStale ? min(windowed, SurfaceRelevance.outOfWindowScore) : windowed)
    }
}
