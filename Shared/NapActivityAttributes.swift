import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity payload for a running nap.
///
/// In `Shared/` because both sides need it: the app starts and updates the
/// activity, the widget extension renders it.
///
/// Guarded by `canImport` so the file survives on any SDK without ActivityKit,
/// and because the widget extension is also built for contexts where Live
/// Activities aren't available.
#if canImport(ActivityKit)
struct NapActivityAttributes: ActivityAttributes {

    /// Fixed for the life of the nap.
    let targetMinutes: Int
    let startedAt: Date

    /// Updated as the nap runs.
    public struct ContentState: Codable, Hashable {
        /// When the nap is due to end. Stored as a date rather than a
        /// countdown because SwiftUI can render a live-updating timer from a
        /// date range without the app pushing an update every second — an
        /// activity that woke the app 1,200 times for a 20-minute nap would be
        /// both wasteful and quickly throttled by the system.
        let endsAt: Date
        /// 0...1, for the progress ring.
        let progress: Double
    }

    var endDate: Date {
        startedAt.addingTimeInterval(Double(targetMinutes) * 60)
    }
}
#else
// Reaching this means the nap Live Activity silently does not exist in this
// build. The source-coverage check in CI cannot detect that — a file excluded
// by a false #if is still compiled, just to nothing — so the guard reports
// itself instead.
#warning("ActivityKit unavailable: nap Live Activity excluded from this build.")
#endif
