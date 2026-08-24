import Foundation

/// One night's meaningful events, told in the order they happened.
///
/// Every other screen in the app answers "how was this night" with a number.
/// Sleep Story answers a different question -- "what actually happened,
/// when" -- as a plain chronological account: naps beforehand, what got
/// logged that day, bedtime, how long it took to fall asleep, each
/// noteworthy awakening, and the final wake. Nothing here is a score or a
/// verdict, and nothing claims one event caused the next -- two things
/// appearing close together in time is exactly that and no more, which is
/// why event text describes *sequence*, never causation.
struct SleepStory: Sendable {

    struct Event: Identifiable, Sendable {
        /// Composite of timestamp, title, and symbol -- not the bare `Date`
        /// this used to be. Two distinct events can share an exact instant
        /// (duplicate or merged-source HealthKit segments produce this in
        /// practice, not just in theory -- see the source-merging notes in
        /// `HealthKitManager`), and `ForEach(story.events, id: \.id)` with a
        /// colliding key silently drops or misrenders one of them. Two
        /// genuinely different events sharing timestamp *and* title *and*
        /// symbol is not a case this needs to distinguish -- at that point
        /// they're indistinguishable in the UI anyway.
        var id: String { "\(symbol)|\(Int(time.timeIntervalSince1970))|\(title)" }
        let time: Date
        let title: String
        let detail: String?
        let symbol: String
    }

    let events: [Event]

    /// - Parameters:
    ///   - night: the night to build a story for.
    ///   - tagLabels: behaviours logged for the day this night's sleep
    ///     followed, already formatted (`BehaviorTag.label`) -- taken as
    ///     plain strings rather than the enum itself so this type has no
    ///     dependency on Journal model types and stays testable in
    ///     isolation.
    ///   - napIntervals: naps taken before bedtime, if any.
    ///   - soundEvents: classified overnight sounds (snoring, coughing, a
    ///     crying baby) from `SoundEventStore`, if any were captured for
    ///     this night. Only ever the most recently completed listening
    ///     session, so this is typically empty for anything but the latest
    ///     night -- an honest gap, not a bug, since nothing else in the app
    ///     stores this by date either.
    ///   - minimumAwakeMinutes: how long a mid-night awake segment has to
    ///     last before it earns its own event -- HealthKit's staging
    ///     produces plenty of sub-minute "awake" blips that are movement
    ///     artifacts, not anything the user actually experienced as waking
    ///     up. Below this, they're folded silently into the surrounding
    ///     sleep rather than cluttering the timeline with noise nobody
    ///     would recognize.
    static func build(
        night: SleepNightFeatures,
        tagLabels: [String] = [],
        napIntervals: [DateInterval] = [],
        soundEvents: [SoundEvent] = [],
        minimumAwakeMinutes: Double = 3
    ) -> SleepStory {
        var events: [Event] = []
        // Populated below, read again by the sound-event pass -- real
        // `StageSegment` intervals, not a re-derivation from `events`, so
        // "coincided with" (see that pass) is checked against the actual
        // awake window rather than guessing from a symbol string.
        var midNightAwakenings: [StageSegment] = []

        for nap in napIntervals.sorted(by: { $0.start < $1.start }) where nap.start < night.bedtime {
            events.append(Event(
                time: nap.start,
                title: "Napped",
                detail: "\(SleepNightFeatures.formatMinutes(nap.duration / 60)) before bedtime",
                symbol: "powersleep"
            ))
        }

        if !tagLabels.isEmpty {
            events.append(Event(
                time: night.bedtime.addingTimeInterval(-1),
                title: "Logged for the day",
                detail: tagLabels.sorted().joined(separator: ", "),
                symbol: "tag"
            ))
        }

        events.append(Event(
            time: night.bedtime,
            title: "Went to bed",
            detail: nil,
            symbol: "bed.double"
        ))

        let sorted = night.stageSegments.sorted { $0.start < $1.start }
        let asleepSegments = sorted.filter { SleepStage.asleepStages.contains($0.stage) }

        if let onset = asleepSegments.first?.start {
            let detail = night.sleepLatencyMinutes.map {
                "\(SleepNightFeatures.formatMinutes($0)) after getting into bed"
            }
            events.append(Event(
                time: onset,
                title: "Fell asleep",
                detail: detail,
                symbol: "moon.zzz"
            ))
        }

        // Awake segments strictly between the first asleep moment and the
        // last one -- the segment that trails off into the final wake is
        // reported separately, below, as "Woke for the day" rather than as
        // just another mid-night awakening.
        if let onset = asleepSegments.first?.start, let lastAsleepEnd = asleepSegments.last?.end {
            midNightAwakenings = sorted.filter {
                $0.stage == .awake && $0.start > onset && $0.end < lastAsleepEnd
                    && $0.minutes >= minimumAwakeMinutes
            }
            for awakening in midNightAwakenings {
                events.append(Event(
                    time: awakening.start,
                    title: "Woke briefly",
                    detail: SleepNightFeatures.formatMinutes(awakening.minutes),
                    symbol: "eye"
                ))
            }
        }

        events.append(Event(
            time: night.wakeTime,
            title: "Woke for the day",
            detail: nil,
            symbol: "sun.max"
        ))

        // Overnight sound events -- see this type's own doc comment on why
        // detail text never claims causation: a snore or a cry landing
        // close to a logged awakening is reported as exactly that, two
        // things near each other in time, never as what woke anyone.
        let sleepWindow = DateInterval(start: night.bedtime, end: night.wakeTime)
        let relevantSounds = soundEvents
            .filter { sleepWindow.contains($0.date) }
            .sorted { $0.date < $1.date }

        // Collapse a run of the same category into one timeline entry -- a
        // snoring bout naturally produces many closely-spaced samples, and
        // without this each one would clutter the story as its own event.
        var soundGroups: [[SoundEvent]] = []
        for sound in relevantSounds {
            if let lastSound = soundGroups.last?.last,
               lastSound.identifier == sound.identifier,
               sound.date.timeIntervalSince(lastSound.date) < 10 * 60 {
                soundGroups[soundGroups.count - 1].append(sound)
            } else {
                soundGroups.append([sound])
            }
        }

        for group in soundGroups {
            guard let first = group.first else { continue }
            var detail = group.count > 1
                ? "\(group.count) times over \(SleepNightFeatures.formatMinutes(group.last!.date.timeIntervalSince(first.date) / 60))"
                : nil

            if midNightAwakenings.contains(where: { abs($0.start.timeIntervalSince(first.date)) < 10 * 60 }) {
                let prefix = detail.map { "\($0) -- " } ?? ""
                detail = "\(prefix)occurred near a brief awakening"
            }

            events.append(Event(time: first.date, title: first.label, detail: detail, symbol: first.symbol))
        }

        return SleepStory(events: events.sorted { $0.time < $1.time })
    }
}
