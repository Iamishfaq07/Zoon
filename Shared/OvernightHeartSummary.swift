import Foundation

/// What the heart did while asleep, in words anyone can follow.
///
/// Two things are worth knowing about a night's heart rate, and neither is
/// the raw line on the hypnogram:
///
/// - **How low it settled** against the person's own daytime resting rate.
///   Sleep is when the heart gets its longest rest; a night spent well
///   below the resting rate is a night the body actually slowed down.
/// - **When the lowest point came.** In a settled night the heart reaches
///   its low in the first half and drifts up toward morning. A low that
///   arrives just before waking usually means the body spent the night
///   busy with something: a late meal, alcohol, a hard late workout,
///   illness or stress. Oura's recovery guidance uses the same reading.
///
/// The lowest point is taken from a 15-minute rolling mean over the
/// five-minute bins, not from a single bin, so one noisy reading does not
/// decide when "the lowest point" was.
struct OvernightHeartSummary: Hashable, Sendable {

    let averageBPM: Double
    /// Lowest 15-minute average while asleep.
    let lowestBPM: Double
    let lowestAt: Date
    /// Where the lowest point fell between falling asleep (0) and waking (1).
    let lowestFraction: Double
    /// The daytime resting heart rate the night is compared with, when known.
    let restingBPM: Double?

    enum Timing: String, Hashable, Sendable {
        case early, middle, late
    }

    var timing: Timing {
        switch lowestFraction {
        case ..<0.5: .early
        case ..<0.75: .middle
        default: .late
        }
    }

    /// How far the sleeping average sat below the daytime resting rate, in
    /// percent. Positive means slower while asleep. `nil` without a resting
    /// rate to compare with.
    var belowRestingPercent: Double? {
        guard let restingBPM, restingBPM > 0 else { return nil }
        return (restingBPM - averageBPM) / restingBPM * 100
    }

    /// Fewer points than this and there is no night to describe.
    static let minimumSamples = 6

    static func make(
        samples: [(date: Date, bpm: Double)],
        night: DateInterval,
        restingHeartRate: Double?
    ) -> OvernightHeartSummary? {
        let inside = OvernightSeries.clipped(samples, to: night)
        guard inside.count >= minimumSamples, night.duration > 0 else { return nil }

        let average = inside.map(\.bpm).reduce(0, +) / Double(inside.count)

        // Rolling mean of three neighbouring bins, centred.
        var lowest: (bpm: Double, date: Date)?
        for index in inside.indices {
            let window = inside[max(0, index - 1)...min(inside.count - 1, index + 1)]
            let mean = window.map(\.bpm).reduce(0, +) / Double(window.count)
            if mean < (lowest?.bpm ?? .infinity) {
                lowest = (mean, inside[index].date)
            }
        }
        guard let lowest else { return nil }

        let fraction = lowest.date.timeIntervalSince(night.start) / night.duration
        return OvernightHeartSummary(
            averageBPM: average,
            lowestBPM: lowest.bpm,
            lowestAt: lowest.date,
            lowestFraction: min(1, max(0, fraction)),
            restingBPM: restingHeartRate.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    /// The timing sentence. `clock` renders a time in the night's own zone.
    func timingSentence(clock: (Date) -> String) -> String {
        let at = clock(lowestAt)
        switch timing {
        case .early:
            return "Your heart reached its lowest point at \(at), in the first half of the night. That usually means your body settled quickly."
        case .middle:
            return "Your heart reached its lowest point at \(at), in the middle of the night. A slightly slow settle, often after a later meal or a busy evening."
        case .late:
            return "Your heart reached its lowest point at \(at), close to waking. A late meal, alcohol, a hard late workout, illness or stress can keep the heart working longer into the night."
        }
    }

    /// The comparison with the daytime resting rate, or `nil` without one.
    var restingSentence: String? {
        guard let belowRestingPercent, let restingBPM else { return nil }
        let percent = Int(abs(belowRestingPercent).rounded())
        let resting = Int(restingBPM.rounded())
        if belowRestingPercent >= 1 {
            return "Asleep, it averaged \(percent)% below your daytime resting rate of \(resting) bpm."
        }
        if belowRestingPercent <= -1 {
            return "Asleep, it averaged \(percent)% above your daytime resting rate of \(resting) bpm, which is unusual and often a sign the body was under strain."
        }
        return "Asleep, it averaged about the same as your daytime resting rate of \(resting) bpm."
    }
}
