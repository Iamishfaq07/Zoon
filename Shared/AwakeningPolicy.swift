import Foundation

/// What counts as an awakening, stated once.
///
/// **Three definitions, three answers.** The night's stored wake count came
/// from `SleepSessionBuilder`: awake stretches of at least two minutes, after
/// sleep onset, that the person fell back asleep after. The hypnogram's list
/// used three minutes, counted in-bed time as awake, and counted the final
/// stretch before getting up. The Sleep Story used three minutes and excluded
/// that final stretch. A night with a 30-second flicker, a two-and-a-half
/// minute wake and a two-minute stretch before rising read as one awakening
/// in the numbers, one in the story and a different one on the chart -- three
/// numbers all called the same thing.
///
/// The builder's rule is the one kept, because it is the one the scores and
/// the stored history already use:
///
/// - **Observed awake only.** In-bed time is not an observation of being
///   awake; nothing measured it.
/// - **After sleep onset.** Lying awake before falling asleep is latency.
/// - **Fell back asleep after it.** The stretch before getting up is the
///   wake, not an awakening.
/// - **At least two minutes.** Shorter is a classification flicker the
///   sleeper does not remember.
enum AwakeningPolicy {

    static let minimumDuration: TimeInterval = 120

    /// The awakenings in a night's stage segments, in time order.
    static func episodes(in segments: [StageSegment]) -> [StageSegment] {
        let sorted = segments.sorted { $0.start < $1.start }
        let asleep = sorted.filter { SleepStage.asleepStages.contains($0.stage) }
        guard let onset = asleep.first?.start,
              let lastAsleepEnd = asleep.map(\.end).max() else { return [] }
        return sorted.filter {
            $0.stage == .awake
                && $0.start > onset
                && $0.end <= lastAsleepEnd
                && $0.duration >= minimumDuration
        }
    }
}
