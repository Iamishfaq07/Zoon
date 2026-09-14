import Foundation

/// The sequence of recorded events around one awakening.
///
/// Language is deliberately co-occurrence, never cause. A snore that ended
/// two minutes before an awake epoch is a neighbour on the timeline, not an
/// explanation. Missing streams are omitted, never fabricated.
enum AwakeningInspector {

    struct Marker: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable {
            case hrRise, awake, soundEnded, movement, stageResume, snore
        }
        let date: Date
        let kind: Kind
        let caption: String
        var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
    }

    struct Sequence: Hashable, Sendable {
        let awakeningStart: Date
        let awakeningMinutes: Double
        let markers: [Marker]
        let caveat: String
        let missingStreams: [String]
    }

    /// How far either side of the awakening to look.
    static let windowMinutes = 12.0
    /// Sound events quieter than this are not called out, matching `SleepReplay`.
    static let minimumSoundConfidence = 0.6

    static func inspect(
        awakening: DateInterval,
        stages: [StageSegment],
        sounds: [SoundEvent] = [],
        heartRateRiseAt: Date? = nil,
        movementAt: Date? = nil
    ) -> Sequence {
        let start = awakening.start
        let minutes = max(0, awakening.duration / 60)
        let window = DateInterval(
            start: start.addingTimeInterval(-windowMinutes * 60),
            end: start.addingTimeInterval(windowMinutes * 60)
        )

        var markers: [Marker] = []
        if let heartRateRiseAt, window.contains(heartRateRiseAt) {
            markers.append(Marker(date: heartRateRiseAt, kind: .hrRise, caption: "Heart rate began increasing"))
        }
        markers.append(Marker(
            date: start,
            kind: .awake,
            caption: minutes >= 1
                ? "Awake for \(SleepNightFeatures.formatMinutes(minutes))"
                : "Brief awakening"
        ))
        if let movementAt, window.contains(movementAt) {
            markers.append(Marker(date: movementAt, kind: .movement, caption: "Movement detected"))
        }

        let nearbySounds = sounds.filter {
            $0.confidence >= minimumSoundConfidence && window.contains($0.date)
        }
        for sound in nearbySounds {
            let ended: Bool
            if sound.date < start {
                ended = true
            } else {
                ended = false
            }
            let kind: Marker.Kind = sound.identifier == "snoring" || sound.identifier == "snore"
                ? .snore : .soundEnded
            let caption = ended
                ? "\(sound.label) event ended"
                : "\(sound.label) event"
            markers.append(Marker(date: sound.date, kind: kind, caption: caption))
        }

        if let resume = stages.first(where: {
            $0.start >= awakening.end && SleepStage.asleepStages.contains($0.stage)
        }), window.contains(resume.start) || resume.start.timeIntervalSince(start) <= windowMinutes * 60 {
            markers.append(Marker(
                date: resume.start,
                kind: .stageResume,
                caption: "\(resume.stage.displayName) sleep resumed"
            ))
        }

        markers.sort { $0.date < $1.date }

        var missing: [String] = []
        if heartRateRiseAt == nil { missing.append("heart rate") }
        if movementAt == nil { missing.append("movement") }
        if sounds.isEmpty { missing.append("sound") }

        return Sequence(
            awakeningStart: start,
            awakeningMinutes: minutes,
            markers: markers,
            caveat: "These events occurred around the same time. Zoon does not claim that one caused the awakening.",
            missingStreams: missing
        )
    }

    /// Awake runs long enough to inspect, from a night's stage list.
    static func awakenings(in stages: [StageSegment], minimumMinutes: Double = 2) -> [DateInterval] {
        stages
            .filter { $0.stage == .awake && $0.minutes >= minimumMinutes }
            .map { DateInterval(start: $0.start, end: $0.end) }
    }
}
