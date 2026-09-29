import Foundation

/// One snoring episode as stored: when it started and ended, how many
/// snoring breaths it held and how loud it was. No audio, no waveform.
struct SnoreEpisodeRecord: Codable, Hashable, Sendable, Identifiable {
    let start: Date
    let end: Date
    /// Snoring breaths Zoon's own engine counted in it. `nil` when only
    /// Apple's classifier heard this stretch.
    let events: Int?
    /// `nil` for the same reason: the classifier reports no level.
    let loudness: SnoreLoudness?

    var id: Date { start }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Episodes for a session, from its fused snoring intervals.
    ///
    /// Classifier windows arrive a second or so at a time and the engine's
    /// episodes can butt up against them, so spans closer than `joinGap` are
    /// one episode: a person does not stop snoring for four seconds and start
    /// a new episode. Breath counts and loudness come from the engine's
    /// episodes that overlap each span.
    static func make(
        fused: [SnoreEvidenceFusion.Interval],
        engineEpisodes: [SnoreEpisode],
        clock: SnoreSessionClock,
        joinGap: TimeInterval = 8
    ) -> [SnoreEpisodeRecord] {
        let spans = fused
            .filter { $0.end > $0.start }
            .map { (start: $0.start, end: $0.end) }
            .sorted { $0.start < $1.start }
        var merged: [(start: TimeInterval, end: TimeInterval)] = []
        for span in spans {
            if let last = merged.last, span.start <= last.end + joinGap {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        return merged.compactMap { span in
            guard let start = clock.date(at: span.start), let end = clock.date(at: span.end) else { return nil }
            let overlapping = engineEpisodes.filter { $0.start < span.end && span.start < $0.end }
            let events = overlapping.isEmpty ? nil : overlapping.reduce(0) { $0 + $1.events }
            let loudness = overlapping.map(\.loudness).max()
            return SnoreEpisodeRecord(start: start, end: max(start, end), events: events, loudness: loudness)
        }
    }
}

/// Maps session time (monitored seconds, interruptions excluded) onto the
/// wall clock (interruptions included).
///
/// An anchor is dropped every time listening starts or resumes. Session time
/// after an anchor advances with the wall clock; across a 20-minute phone
/// call it does not, so an episode after the call lands after the call.
struct SnoreSessionClock: Codable, Equatable, Sendable {
    struct Anchor: Codable, Equatable, Sendable {
        let session: TimeInterval
        let wall: Date
    }

    private(set) var anchors: [Anchor] = []

    mutating func mark(session: TimeInterval, wall: Date) {
        anchors.removeAll { $0.session >= session }
        anchors.append(Anchor(session: session, wall: wall))
    }

    func date(at session: TimeInterval) -> Date? {
        guard let anchor = anchors.last(where: { $0.session <= session }) ?? anchors.first else { return nil }
        return anchor.wall.addingTimeInterval(session - anchor.session)
    }
}

/// What the Snore Check result shows for one night, beyond the headline:
/// how many episodes, the longest, how loud they ran, and when.
struct SnoreNightReport: Equatable, Sendable {
    let episodes: [SnoreEpisodeRecord]
    let monitoredMinutes: Double
    let snoreMinutes: Double
    /// The span the timeline covers: the session, or the episodes when an
    /// older summary did not store the session's ends.
    let span: DateInterval?

    init(
        monitoredMinutes: Double,
        snoreMinutes: Double,
        episodes: [SnoreEpisodeRecord]?,
        startedAt: Date?,
        endedAt: Date?
    ) {
        let sorted = (episodes ?? []).sorted { $0.start < $1.start }
        self.episodes = sorted
        self.monitoredMinutes = monitoredMinutes
        self.snoreMinutes = snoreMinutes
        let first = [startedAt, sorted.first?.start].compactMap { $0 }.min()
        let last = [endedAt, sorted.map(\.end).max()].compactMap { $0 }.max()
        if let first, let last, last > first {
            span = DateInterval(start: first, end: last)
        } else {
            span = nil
        }
    }

    var episodeCount: Int { episodes.count }

    var longest: SnoreEpisodeRecord? { episodes.max { $0.duration < $1.duration } }

    var loudest: SnoreLoudness? { episodes.compactMap(\.loudness).max() }

    /// Snoring as a share of the time actually monitored, 0...100.
    var sharePercent: Int {
        guard monitoredMinutes > 0 else { return 0 }
        return min(100, Int((snoreMinutes / monitoredMinutes * 100).rounded()))
    }

    /// Minutes of episodes at each loudness, loudest first, zeros left out.
    var minutesByLoudness: [(loudness: SnoreLoudness, minutes: Double)] {
        SnoreLoudness.allCases.reversed().compactMap { level in
            let minutes = episodes.filter { $0.loudness == level }.reduce(0) { $0 + $1.duration } / 60
            return minutes > 0 ? (loudness: level, minutes: minutes) : nil
        }
    }

    /// The clock hour with the most snoring, as the hour's start. `nil` with
    /// no episodes.
    func busiestHour(calendar: Calendar = .current) -> Date? {
        var byHour: [Date: TimeInterval] = [:]
        for episode in episodes {
            var cursor = episode.start
            while cursor < episode.end {
                guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
                let sliceEnd = min(hour.end, episode.end)
                byHour[hour.start, default: 0] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }
        return byHour.max { $0.value < $1.value }?.key
    }

    /// Where an instant falls along `span`, 0...1.
    func position(of date: Date) -> Double {
        guard let span, span.duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(span.start) / span.duration))
    }
}
