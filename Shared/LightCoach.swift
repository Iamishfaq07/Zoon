import Foundation

/// Time-anchored light-exposure guidance.
///
/// Zoon has no ambient light sensor -- HealthKit doesn't expose one -- so this
/// is deliberately coaching, not measurement: fixed, well-established guidance
/// (morning bright light anchors the body clock; evening light delays it)
/// anchored to *this person's* actual wake time and usual bedtime window
/// rather than a generic "get sun in the morning" tip that ignores when their
/// morning actually is.
///
/// Two windows, both grounded in data Zoon already has:
/// - Morning: the 90 minutes after `wakeTime`, when outdoor light does the
///   most to anchor circadian phase.
/// - Evening: the two hours before `BodyClock.onsetHour`, when bright light
///   (screens especially) pushes the body clock later and delays sleep onset.
///
/// Outside both windows there's nothing actionable to say right now, so
/// `guidance` returns `nil` rather than padding the screen with a card that
/// says "nothing to do at the moment."
enum LightCoach {

    struct Guidance: Sendable, Hashable {
        let headline: String
        let detail: String
        let symbol: String
    }

    /// - Parameters:
    ///   - wakeTime: this morning's actual wake time.
    ///   - onsetHour: `BodyClock.onsetHour` when a usual-bedtime estimate
    ///     exists. `nil` disables the evening window rather than guessing.
    static func guidance(
        wakeTime: Date,
        onsetHour: Double?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Guidance? {
        let minutesSinceWake = now.timeIntervalSince(wakeTime) / 60
        if minutesSinceWake >= 0, minutesSinceWake <= 90 {
            return Guidance(
                headline: "Get outside if you can",
                detail: "Bright light in the hour or so after waking is the strongest single cue for your body clock -- stronger than caffeine for feeling alert, and it helps tonight's bedtime arrive on schedule. Even an overcast sky is far brighter than indoor lighting.",
                symbol: "sun.max"
            )
        }

        if let onsetHour, let bedtime = resolveEvening(onsetHour: onsetHour, near: now, calendar: calendar) {
            let minutesToBedtime = bedtime.timeIntervalSince(now) / 60
            if minutesToBedtime >= 0, minutesToBedtime <= 120 {
                return Guidance(
                    headline: "Start dimming the lights",
                    detail: "Bright light -- especially from screens -- in the couple of hours before bed pushes your body clock later and makes it harder to fall asleep on time. Warmer, dimmer light from here on helps tonight's bedtime feel natural rather than forced.",
                    symbol: "moon.stars"
                )
            }
        }

        return nil
    }

    /// Resolves `BodyClock.onsetHour` (hours from midnight, evening negative)
    /// onto the evening closest to `now`, mirroring the convention
    /// `BodyClock.window(for:)` already uses.
    private static func resolveEvening(onsetHour: Double, near now: Date, calendar: Calendar) -> Date? {
        guard let midnight = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now) else { return nil }
        let today = midnight.addingTimeInterval(onsetHour * 3600)
        // If today's resolved onset already passed by more than a few hours,
        // the relevant one is tomorrow evening's.
        if now.timeIntervalSince(today) > 6 * 3600 {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        return today
    }
}
