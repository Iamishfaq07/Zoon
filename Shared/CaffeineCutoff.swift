import Foundation

/// The general-guideline caffeine cutoff shown as a node on Tonight's
/// timeline (`TonightTimelineCard`).
///
/// A pure, `Shared/`-level type rather than a static method on the view
/// itself, so the calculation is testable from `ZoonTests` without pulling
/// a SwiftUI view (and its own app-only dependencies -- `Theme`,
/// `SectionHeader`, `.glassCard()`) into a test target that otherwise never
/// links against app code, same reasoning as every other pure calculation
/// in this file's siblings.
enum CaffeineCutoff {

    /// How many hours before target bedtime caffeine should stop, per the
    /// general sleep-hygiene guideline this app already cites elsewhere --
    /// see `Article.swift`'s "How Long Caffeine Actually Stays With You"
    /// ("many sleep researchers suggest stopping caffeine 8 to 10 hours
    /// before your intended bedtime") and `RuleBasedInsightEngine`'s own
    /// "Set a caffeine cutoff 8h before bed" tip. A general guideline, not
    /// personalized to this user's own caffeine sensitivity -- nothing in
    /// the app currently measures that.
    static let leadHours = 8.0

    /// How long after its own cutoff time today still shows it -- long
    /// enough to stay useful across an afternoon check-in, short enough
    /// that it's gone by evening rather than reading as stale clutter next
    /// to a bedtime that's actually approaching.
    private static let staleToleranceHours = 3.0

    /// The cutoff for a given target bedtime, or `nil` once it's far enough
    /// in the past that showing it would be clutter rather than guidance.
    static func time(bedtime: Date, now: Date = .now) -> Date? {
        let cutoff = bedtime.addingTimeInterval(-leadHours * 3600)
        return cutoff > now.addingTimeInterval(-staleToleranceHours * 3600) ? cutoff : nil
    }
}
