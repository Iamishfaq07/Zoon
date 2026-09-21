import Foundation

/// A personal morning ramp, learned from repeated alertness checks.
///
/// The check already records `minutesSinceWaking`. This is the thing those
/// numbers can answer once there are enough of them: when this person's
/// reaction time usually stops being the slow first-wake reading and starts
/// looking like the rest of their morning.
///
/// **Association, not neurology.** Nothing here is a measurement of sleep
/// inertia as a clinical phenomenon. It is "in your own checks, the slower
/// medians clustered in the first N minutes." The copy is required to say
/// so. Practice sessions are excluded, because learning the task would
/// otherwise look like a ramp that got shorter with every week of use.
enum SleepInertiaProfile {

    /// Post-practice checks with a known time-since-waking.
    static let minimumSessions = 8

    /// Minutes after waking treated as "later morning" for the comparison
    /// baseline. Matches `AlertnessCheck.wakeWindowToleranceMinutes`.
    static let laterMorningMinutes = 90.0

    struct Result: Hashable, Sendable {
        /// Earliest minute after waking where the median has usually settled.
        let settleLowMinutes: Double
        let settleHighMinutes: Double
        let sessionCount: Int
        let sentence: String
        let caveat: String
    }

    static func learn(sessions: [AlertnessCheck.Session]) -> Result? {
        let usable = sessions
            .dropFirst(AlertnessCheck.practiceSessions)
            .compactMap { session -> (minutes: Double, median: Double)? in
                guard let minutes = session.minutesSinceWaking,
                      minutes >= 0, minutes <= 240,
                      session.medianMilliseconds > 0
                else { return nil }
                return (minutes, session.medianMilliseconds)
            }
        guard usable.count >= minimumSessions else { return nil }

        let later = usable.filter { $0.minutes >= laterMorningMinutes }
        let early = usable.filter { $0.minutes < 40 }
        guard later.count >= 3, early.count >= 2, let laterMedian = Statistics.median(later.map(\.median)) else {
            return nil
        }


        // Walk 15-minute windows from wake. The first window whose median is
        // inside the check's own noise of the later-morning median is the
        // settle band. If none is, the person is still ramping at 90 minutes
        // and we say that rather than invent a number.
        let noise = AlertnessCheck.meaningfulDifferenceMilliseconds
        var settle: Double?
        for start in stride(from: 0.0, through: laterMorningMinutes, by: 15) {
            let window = usable.filter { $0.minutes >= start && $0.minutes < start + 20 }
            guard window.count >= 2, let median = Statistics.median(window.map(\.median)) else {
                continue
            }
            if abs(median - laterMedian) <= noise {
                settle = start
                break
            }
        }

        let low: Double
        let high: Double
        let sentence: String
        if let settle {
            low = settle
            high = min(laterMorningMinutes, settle + 20)
            sentence = "Your checks usually settle around \(band(low, high)) after waking."
        } else {
            low = laterMorningMinutes
            high = laterMorningMinutes
            sentence = "Your first \(Int(laterMorningMinutes)) minutes after waking are usually your slowest checks."
        }

        return Result(
            settleLowMinutes: low,
            settleHighMinutes: high,
            sessionCount: usable.count,
            sentence: sentence,
            caveat: "An association in your own optional checks, not a neurological finding. Practice runs are excluded."
        )
    }

    private static func band(_ low: Double, _ high: Double) -> String {
        if abs(high - low) < 1 {
            return SleepNightFeatures.formatMinutes(low)
        }
        return "\(SleepNightFeatures.formatMinutes(low))–\(SleepNightFeatures.formatMinutes(high))"
    }
}
