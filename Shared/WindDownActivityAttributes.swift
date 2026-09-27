import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Live Activity payload for a running Tonight wind-down: the Lock Screen and
/// Dynamic Island count down to lights-out while the routine plays.
///
/// In `Shared/` for the same reason as `NapActivityAttributes`: the app
/// starts and updates it, the widget extension draws it. The countdown is a
/// date range the system renders itself, so a thirty-minute routine costs a
/// start, one update per stage change and an end.
#if canImport(ActivityKit)
struct WindDownActivityAttributes: ActivityAttributes {

    let startedAt: Date

    public struct ContentState: Codable, Hashable {
        /// When the routine ends.
        let endsAt: Date
        /// "Arrive", "Guided breathing", "Quiet", "Settling".
        let stageLabel: String
    }

    /// The range the Lock Screen and Dynamic Island timers count over.
    ///
    /// `startedAt...endsAt` traps when the end is earlier than the start, and
    /// the stored end can be: a routine resumed with no time left, or the
    /// clock moved back while it ran. A crash here takes down the widget
    /// extension's rendering of the activity, so the end is floored at the
    /// start and the timer simply reads zero.
    func timerRange(_ state: ContentState) -> ClosedRange<Date> {
        startedAt...max(startedAt, state.endsAt)
    }
}
#endif
