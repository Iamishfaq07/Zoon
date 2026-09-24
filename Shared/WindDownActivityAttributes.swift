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
}
#endif
