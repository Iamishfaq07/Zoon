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
        let id: Date
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
        minimumAwakeMinutes: Double = 3
    ) -> SleepStory {
        var events: [Event] = []

        for nap in napIntervals.sorted(by: { $0.start < $1.start }) where nap.start < night.bedtime {
            events.append(Event(
                id: nap.start,
                time: nap.start,
                title: "Napped",
                detail: "\(SleepNightFeatures.formatMinutes(nap.duration / 60)) before bedtime",
                symbol: "powersleep"
            ))
        }

        if !tagLabels.isEmpty {
            events.append(Event(
                id: night.bedtime.addingTimeInterval(-1),
                time: night.bedtime.addingTimeInterval(-1),
                title: "Logged for the day",
                detail: tagLabels.sorted().joined(separator: ", "),
                symbol: "tag"
            ))
        }

        events.append(Event(
            id: night.bedtime,
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
                id: onset,
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
            let midNightAwakenings = sorted.filter {
                $0.stage == .awake && $0.start > onset && $0.end < lastAsleepEnd
                    && $0.minutes >= minimumAwakeMinutes
            }
            for awakening in midNightAwakenings {
                events.append(Event(
                    id: awakening.start,
                    time: awakening.start,
                    title: "Woke briefly",
                    detail: SleepNightFeatures.formatMinutes(awakening.minutes),
                    symbol: "eye"
                ))
            }
        }

        events.append(Event(
            id: night.wakeTime,
            time: night.wakeTime,
            title: "Woke for the day",
            detail: nil,
            symbol: "sun.max"
        ))

        return SleepStory(events: events.sorted { $0.time < $1.time })
    }
}
