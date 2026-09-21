import Foundation

/// Canonical Sleep Sounds timer rules.
///
/// Timer = Off means Off. An active timer may be inherited when the user
/// switches sounds, but a nearly-expired deadline is treated as Off so the
/// new sound does not die after a few seconds — the failure that reads as
/// "sounds only play for a moment."
enum SoundscapeTimerPolicy: Sendable {

    /// Remaining time below this is too short to inherit. Switching sounds
    /// with 8 seconds left on a 15-minute timer was the user-visible bug.
    static let inheritCutoffSeconds: TimeInterval = 15

    /// Deadline to keep after a sound switch. `nil` is Off.
    static func deadlineAfterSwitchingSound(
        currentDeadline: Date?,
        now: Date = .now
    ) -> Date? {
        guard let currentDeadline else { return nil }
        let remaining = currentDeadline.timeIntervalSince(now)
        if remaining <= inheritCutoffSeconds { return nil }
        return currentDeadline
    }

    static func remainingSeconds(deadline: Date?, now: Date = .now) -> Int {
        guard let deadline else { return 0 }
        return max(0, Int(ceil(deadline.timeIntervalSince(now))))
    }

    static func formattedRemaining(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    /// Copy shown on the now-playing card. Inherited timers must not hide.
    static func stopsInCopy(seconds: Int) -> String {
        "Stops in \(formattedRemaining(seconds: seconds))"
    }
}
