import Foundation

/// The handful of moments that actually happened during a night.
///
/// A hypnogram is a shape. Someone reading one has to decode it before it
/// tells them anything, and most people do not: the eye sees a staircase, not
/// "you fell asleep at 23:04 and lost twenty minutes at 03:13". This turns
/// the same stored timeline into the sentences the shape is made of.
///
/// ## Not decoration
///
/// The V9 spec is explicit that a replay exists to explain the night rather
/// than to look alive, and that is a constraint on what counts as a moment,
/// not only on the animation. Every moment here is a real transition in the
/// stored data or a recorded sound event. Nothing is inserted to give the
/// cursor something to do during a quiet stretch, because a night with three
/// interesting moments should play three, not six.
///
/// ## Why this is not in the view
///
/// It decides what a night *means* -- which transitions are worth a caption
/// and which are noise -- so it is the part worth testing, and the animation
/// on top of it is not. A view that both derives the moments and draws them
/// makes the first half unverifiable.
enum SleepReplay {

    /// One captioned instant.
    struct Moment: Identifiable, Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case fellAsleep
            case stageChange
            case awoke
            case sound
            case wokeUp
        }

        let date: Date
        let kind: Kind
        /// "Fell asleep", "Deep sleep", "Snoring", "Awake".
        let caption: String

        var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
    }

    /// A stage run shorter than this is not a moment.
    ///
    /// Consumer wearables flip between adjacent stages constantly, and every
    /// flip is a "stage change" if you let it be. Captioning them would bury
    /// the four or five transitions that describe the night under thirty that
    /// describe the classifier. Five minutes is roughly the shortest run that
    /// tends to survive from one night's scoring to the next.
    static let minimumRunMinutes = 5.0

    /// A sound event quieter than this is not called out.
    ///
    /// The classifier returns a confidence and the low end of it is noise.
    /// A caption is a claim that something happened.
    static let minimumSoundConfidence = 0.6

    /// Every moment worth captioning, in chronological order.
    ///
    /// - Parameters:
    ///   - segments: the night's stage timeline, in any order.
    ///   - soundEvents: overnight sound events. Ones outside the night's
    ///     span are ignored rather than clamped -- a snore recorded at noon
    ///     belongs to a different night, and moving it would invent data.
    static func moments(
        from segments: [StageSegment],
        soundEvents: [SoundEvent] = []
    ) -> [Moment] {
        let ordered = segments.sorted { $0.start < $1.start }
        guard let first = ordered.first, let last = ordered.last else { return [] }

        var moments: [Moment] = []

        // Falling asleep: the first run that is actually sleep, not the first
        // run of the session -- which is usually `inBed` or `awake`.
        if let onset = ordered.first(where: { SleepStage.asleepStages.contains($0.stage) }) {
            moments.append(Moment(date: onset.start, kind: .fellAsleep, caption: "Fell asleep"))
        }

        // Stage changes, skipping runs too short to mean anything and the
        // onset run already captioned above.
        var previousStage: SleepStage?
        for segment in ordered {
            defer { previousStage = segment.stage }
            guard segment.minutes >= minimumRunMinutes else { continue }
            guard segment.stage != previousStage else { continue }
            guard segment.start != moments.first?.date else { continue }

            switch segment.stage {
            case .awake:
                moments.append(Moment(date: segment.start, kind: .awoke, caption: "Awake"))
            case .core, .deep, .rem:
                moments.append(Moment(
                    date: segment.start,
                    kind: .stageChange,
                    caption: segment.stage.displayName
                ))
            case .inBed, .unspecified:
                // Neither is a transition anyone can act on: `inBed` is not
                // sleep, and `unspecified` is what a source writes when it
                // cannot tell you the stage at all. Captioning "Asleep" in
                // the middle of a night would imply a change that the data
                // does not claim.
                continue
            }
        }

        // Sound events inside the night, confident ones only.
        let span = DateInterval(start: first.start, end: last.end)
        for event in soundEvents
            where event.confidence >= minimumSoundConfidence && span.contains(event.date) {
            moments.append(Moment(date: event.date, kind: .sound, caption: event.label))
        }

        moments.append(Moment(date: last.end, kind: .wokeUp, caption: "Wake"))

        return moments.sorted { $0.date < $1.date }
    }

    /// How long the replay should run for, in seconds.
    ///
    /// The spec asks for 10-15 seconds "configurable to available content".
    /// A four-hour night and a ten-hour night should not both take fifteen
    /// seconds -- the pacing is what carries the sense of a long night -- but
    /// neither should a nap take one. Clamped at both ends.
    static let shortestDurationSeconds = 8.0
    static let longestDurationSeconds = 15.0

    /// The ramp runs between the hours nights actually occupy rather than
    /// from zero. Anchoring it at zero spends most of its range on durations
    /// no one sleeps, so every real night lands in the top third and the
    /// pacing stops distinguishing them -- and the short-end clamp becomes
    /// unreachable, which is the same as not having one.
    static let shortestNightHours = 4.0
    static let longestNightHours = 10.0

    static func duration(forNightHours hours: Double) -> Double {
        let span = longestNightHours - shortestNightHours
        let position = (hours - shortestNightHours) / span
        let scaled = shortestDurationSeconds + position * (longestDurationSeconds - shortestDurationSeconds)
        return min(longestDurationSeconds, max(shortestDurationSeconds, scaled))
    }

    /// Where a moment sits in the night, 0...1 -- what the cursor animates
    /// along, and what a tap on a caption scrubs to.
    static func fraction(of date: Date, in segments: [StageSegment]) -> Double? {
        let ordered = segments.sorted { $0.start < $1.start }
        guard let first = ordered.first, let last = ordered.last else { return nil }
        let total = last.end.timeIntervalSince(first.start)
        guard total > 0 else { return nil }
        return min(1, max(0, date.timeIntervalSince(first.start) / total))
    }
}
