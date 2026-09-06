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

    /// One stretch of a single stage, after micro-runs have been resolved.
    ///
    /// The replay's own view of the night, deliberately coarser than the
    /// stored hypnogram. Nothing here is written back: `SleepNightFeatures`
    /// keeps every segment the source reported, and the chart still draws
    /// them. This is only what the *narration* is built from.
    struct Run: Hashable, Sendable {
        let stage: SleepStage
        let start: Date
        let end: Date

        var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    /// Collapses the stored segments into the runs worth narrating.
    ///
    /// ## The bug this replaces
    ///
    /// Events used to be derived straight from the segments, with short runs
    /// skipped by `continue` -- but the loop updated `previousStage` in a
    /// `defer`, which runs on the way out of *every* iteration including the
    /// skipped ones. So an ignored two-minute Core between two stretches of
    /// Deep still moved `previousStage` to Core, and the second stretch then
    /// looked like a fresh transition:
    ///
    ///     Deep 30m, Core 2m, Deep 25m  ->  "Deep sleep", "Deep sleep"
    ///
    /// The run was ignored for captioning and obeyed for state, which is the
    /// worst of both. Deciding what counts as a run *before* deriving any
    /// event removes the possibility rather than patching it: there is no
    /// longer a place where a segment can be half-ignored.
    ///
    /// A micro-run is absorbed into the stretch it interrupted, so the two
    /// Deep stretches above become one 57-minute run and produce one event.
    /// A micro-run before any run at all is simply dropped -- there is
    /// nothing for it to interrupt.
    static func significantRuns(from segments: [StageSegment]) -> [Run] {
        var runs: [Run] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            if let last = runs.last, last.stage == segment.stage {
                // Continues the current run, whatever its length.
                runs[runs.count - 1] = Run(stage: last.stage, start: last.start, end: segment.end)
            } else if segment.minutes >= minimumRunMinutes {
                runs.append(Run(stage: segment.stage, start: segment.start, end: segment.end))
            } else if let last = runs.last {
                // Too short to be its own moment, so it belongs to the run it
                // interrupted rather than ending it.
                runs[runs.count - 1] = Run(stage: last.stage, start: last.start, end: segment.end)
            }
        }
        return runs
    }

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

        // Stage changes, one per significant run. Runs are already free of
        // micro-interruptions and never repeat a stage back to back, so
        // there is no previous-stage bookkeeping here to get wrong.
        for run in significantRuns(from: ordered) {
            guard run.start != moments.first?.date else { continue }

            switch run.stage {
            case .awake:
                moments.append(Moment(
                    date: run.start,
                    kind: .awoke,
                    caption: "Awake \(Int(run.minutes.rounded()))m"
                ))
            case .core, .deep, .rem:
                moments.append(Moment(
                    date: run.start,
                    kind: .stageChange,
                    caption: run.stage.displayName
                ))
            case .inBed, .unspecified:
                // Neither is a transition anyone can act on: `inBed` is not
                // sleep, and `unspecified` is what a source writes when it
                // cannot tell you the stage at all. Captioning "Asleep" in
                // the middle of a night would imply a change that the data
                // does not claim. The run still separates the stretches
                // around it -- an hour Zoon cannot read is not nothing --
                // it just carries no caption of its own.
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
