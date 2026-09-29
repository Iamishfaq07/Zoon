import Foundation

/// What one short buffer of room sound looked like. Derived numbers only:
/// no samples, nothing that could be played back.
struct SnoreFrame: Equatable, Sendable {
    /// Seconds of audio the frame covers.
    var duration: TimeInterval
    /// Broadband RMS level, dBFS.
    var levelDB: Double
    /// Share of the RMS that sits in the 60–700 Hz band, 0...1.
    var lowRatio: Double
    /// Zero crossings per second. Low for snoring, high for hiss, speech
    /// fricatives and clicks.
    var zeroCrossingRate: Double
    /// Strength of a 40–300 Hz fundamental, 0...1: the normalised
    /// autocorrelation peak of the band-passed signal. Palatal snoring is
    /// strongly periodic; a fan or rain is not.
    var periodicity: Double
}

/// How loud a snoring episode stood out from the room, by its peak above
/// the room's own quiet level. A proxy, not a sound-pressure measurement:
/// the phone's distance and case change the absolute number.
enum SnoreLoudness: String, Codable, Sendable, Comparable, CaseIterable {
    case quiet
    case moderate
    case loud

    init(peakAboveFloorDB: Double) {
        switch peakAboveFloorDB {
        case ..<12: self = .quiet
        case ..<22: self = .moderate
        default: self = .loud
        }
    }

    var label: String {
        switch self {
        case .quiet: "Quiet"
        case .moderate: "Moderate"
        case .loud: "Loud"
        }
    }

    private var rank: Int {
        switch self {
        case .quiet: 0
        case .moderate: 1
        case .loud: 2
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// One sound the engine heard that had the shape of a snore: loud enough
/// against the room, low-pitched, and the length of a breath.
struct SnoreSoundEvent: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    /// 0...1: how snore-like the sound was.
    var score: Double
    var peakAboveFloorDB: Double

    var duration: TimeInterval { max(0, end - start) }
}

/// A run of snore-shaped sounds that repeated with the rhythm of breathing.
/// Times are session seconds (monitored time, gaps excluded).
struct SnoreEpisode: Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var events: Int
    var peakAboveFloorDB: Double
    var scoreTotal: Double

    var duration: TimeInterval { max(0, end - start) }
    var meanScore: Double { events > 0 ? scoreTotal / Double(events) : 0 }
    var loudness: SnoreLoudness { SnoreLoudness(peakAboveFloorDB: peakAboveFloorDB) }
}

/// Zoon's own snore detector: three stages, all on the device, all on the
/// CPU, so it keeps working with the screen locked.
///
/// 1. **Against the room.** The room's quiet level is tracked continuously
///    (it falls quickly and rises slowly, so a fan that starts at 2am becomes
///    the new quiet within a minute). A sound only counts when it rises
///    `onDB` above that level. The old detector used one fixed loudness for
///    every room and every phone: a snore across a quiet bedroom never
///    reached it, and in a room with a fan the level never dropped below it,
///    so there was never a start of a sound to find.
/// 2. **Shape.** A sound becomes a candidate when it is the length of a
///    breath (`minEvent`...`maxEvent` seconds), most of its energy is below
///    700 Hz, it crosses zero rarely, and it is either periodic (a
///    fundamental between 40 and 300 Hz) or very low-pitched. Door slams are
///    too short, speech crosses zero too often, a passing car is too long.
/// 3. **Rhythm.** Snoring repeats with breathing. An episode opens when at
///    least `openRun` candidates follow each other at breathing intervals
///    (`minInterval`...`maxInterval` seconds) that are regular, and stays open
///    while they keep coming. A single cough, a word, or someone turning
///    over never makes an episode.
///
/// The thresholds are engineering values, set against the published
/// acoustics of snoring (fundamental roughly 40–300 Hz, energy mostly below
/// 800 Hz, one event per breath at 8–30 breaths a minute) and meant to be
/// calibrated against real nights, not presented as science.
struct SnoreAcousticEngine: Sendable {

    struct Tuning: Equatable, Sendable {
        /// A sound starts this far above the room's quiet level...
        var onDB = 6.0
        /// ...and lasts while it stays this far above it.
        var offDB = 3.0
        var minEvent: TimeInterval = 0.25
        var maxEvent: TimeInterval = 3.5
        /// Longer than this is a sustained sound (a fan, traffic, a TV): it
        /// is not a candidate, and the quiet level starts following it.
        var sustained: TimeInterval = 6
        var minLowRatio = 0.5
        /// Zero crossings per second above which a sound is not a snore.
        var maxZeroCrossingRate = 1_800.0
        /// A candidate needs this periodicity, unless it is very low-pitched.
        var minPeriodicity = 0.25
        var veryLowRatio = 0.72
        /// Breath-to-breath intervals, onset to onset.
        var minInterval: TimeInterval = 1.6
        var maxInterval: TimeInterval = 9
        /// Longest interval / shortest interval in the opening run.
        var maxIrregularity = 2.4
        var openRun = 3
        /// An open episode survives a missed breath or two.
        var extendInterval: TimeInterval = 13
        /// Seconds the quiet level takes to rise to a louder room.
        var floorRiseSeconds: TimeInterval = 30
        /// Share of the distance the quiet level falls per frame.
        var floorFallRate = 0.3
        /// Candidates kept for the rhythm check, in seconds.
        var rhythmMemory: TimeInterval = 45
    }

    let tuning: Tuning

    /// The room's quiet level, dBFS. `nil` before the first frame.
    private(set) var floorDB: Double?
    /// The latest frame's level, dBFS.
    private(set) var levelDB: Double = -120
    private(set) var episodes: [SnoreEpisode] = []
    private(set) var openEpisode: SnoreEpisode?
    private(set) var candidates: [SnoreSoundEvent] = []
    /// Every candidate this session, including ones that never joined an
    /// episode.
    private(set) var candidateCount = 0
    private(set) var lastCandidateEnd: TimeInterval?
    /// Session time the last frame ended at.
    private(set) var now: TimeInterval = 0

    private var event: Accumulator?

    private struct Accumulator: Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var lowWeighted = 0.0
        var zcrWeighted = 0.0
        var periodicityWeighted = 0.0
        var periodicityPeak = 0.0
        var peakAbove = 0.0
        var weight = 0.0

        var duration: TimeInterval { end - start }
    }

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Feeds one frame that ended at session time `t`.
    mutating func ingest(_ frame: SnoreFrame, endingAt t: TimeInterval) {
        let dt = max(0, frame.duration)
        let start = t - dt
        now = t
        levelDB = frame.levelDB
        guard let floor = floorDB else {
            floorDB = frame.levelDB
            return
        }
        let above = frame.levelDB - floor

        if var current = event {
            if above >= tuning.offDB {
                current.end = t
                current.lowWeighted += frame.lowRatio * dt
                current.zcrWeighted += frame.zeroCrossingRate * dt
                current.periodicityWeighted += frame.periodicity * dt
                current.periodicityPeak = max(current.periodicityPeak, frame.periodicity)
                current.peakAbove = max(current.peakAbove, above)
                current.weight += dt
                if current.duration > tuning.sustained {
                    // A sound that will not end is the room now. Let the quiet
                    // level follow it, faster than usual, so detection resumes
                    // on top of it instead of waiting for it to stop.
                    adaptFloor(toward: frame.levelDB, dt: dt, riseSeconds: tuning.floorRiseSeconds / 3)
                }
                event = current
            } else {
                event = nil
                finishEvent(current)
                adaptFloor(toward: frame.levelDB, dt: dt, riseSeconds: tuning.floorRiseSeconds)
            }
        } else if above >= tuning.onDB {
            event = Accumulator(
                start: start,
                end: t,
                lowWeighted: frame.lowRatio * dt,
                zcrWeighted: frame.zeroCrossingRate * dt,
                periodicityWeighted: frame.periodicity * dt,
                periodicityPeak: frame.periodicity,
                peakAbove: above,
                weight: dt
            )
        } else {
            adaptFloor(toward: frame.levelDB, dt: dt, riseSeconds: tuning.floorRiseSeconds)
        }

        closeEpisodeIfQuiet(at: t)
    }

    /// Ends the session: an open sound is judged, an open episode closed.
    mutating func finish() {
        if let current = event {
            event = nil
            finishEvent(current)
        }
        if let open = openEpisode {
            episodes.append(open)
            openEpisode = nil
        }
    }

    /// Closed episodes plus the one still open.
    var allEpisodes: [SnoreEpisode] {
        openEpisode.map { episodes + [$0] } ?? episodes
    }

    var isInEpisode: Bool { openEpisode != nil }

    /// Seconds inside snoring episodes so far.
    var snoreSeconds: Double {
        allEpisodes.reduce(0) { $0 + $1.duration }
    }

    /// Episode spans, for fusion with Apple's classifier.
    var intervals: [(start: TimeInterval, end: TimeInterval)] {
        allEpisodes.map { (start: $0.start, end: $0.end) }
    }

    /// How far the latest frame stood above the room, in dB (0 when below).
    var levelAboveFloorDB: Double {
        guard let floorDB else { return 0 }
        return max(0, levelDB - floorDB)
    }

    // MARK: - Stages

    private mutating func adaptFloor(toward level: Double, dt: TimeInterval, riseSeconds: TimeInterval) {
        guard let floor = floorDB else {
            floorDB = level
            return
        }
        if level < floor {
            floorDB = floor + (level - floor) * min(1, tuning.floorFallRate)
        } else {
            floorDB = floor + (level - floor) * min(1, dt / max(riseSeconds, 0.001))
        }
        floorDB = max(-120, floorDB ?? level)
    }

    /// Stage 2: is this sound snore-shaped?
    static func candidate(
        start: TimeInterval,
        end: TimeInterval,
        lowRatio: Double,
        zeroCrossingRate: Double,
        periodicity: Double,
        peakAboveFloorDB: Double,
        tuning: Tuning
    ) -> SnoreSoundEvent? {
        let duration = end - start
        guard duration >= tuning.minEvent, duration <= tuning.maxEvent else { return nil }
        guard lowRatio >= tuning.minLowRatio else { return nil }
        guard zeroCrossingRate <= tuning.maxZeroCrossingRate else { return nil }
        guard periodicity >= tuning.minPeriodicity || lowRatio >= tuning.veryLowRatio else { return nil }
        func unit(_ x: Double) -> Double { min(1, max(0, x)) }
        let score = 0.45 * unit((lowRatio - tuning.minLowRatio) / 0.35)
            + 0.35 * unit(periodicity)
            + 0.20 * unit((peakAboveFloorDB - tuning.onDB) / 14)
        return SnoreSoundEvent(start: start, end: end, score: score, peakAboveFloorDB: peakAboveFloorDB)
    }

    private mutating func finishEvent(_ e: Accumulator) {
        guard e.weight > 0 else { return }
        let periodicity = max(e.periodicityWeighted / e.weight, 0.8 * e.periodicityPeak)
        guard let candidate = Self.candidate(
            start: e.start,
            end: e.end,
            lowRatio: e.lowWeighted / e.weight,
            zeroCrossingRate: e.zcrWeighted / e.weight,
            periodicity: periodicity,
            peakAboveFloorDB: e.peakAbove,
            tuning: tuning
        ) else { return }
        register(candidate)
    }

    /// Stage 3: does it repeat like breathing?
    mutating func register(_ c: SnoreSoundEvent) {
        candidateCount += 1
        lastCandidateEnd = c.end
        candidates.append(c)
        candidates.removeAll { $0.start < c.start - tuning.rhythmMemory }

        if var open = openEpisode, let previousOnset = lastOnset(in: open) {
            if c.start - previousOnset <= tuning.extendInterval {
                open.end = max(open.end, c.end)
                open.events += 1
                open.peakAboveFloorDB = max(open.peakAboveFloorDB, c.peakAboveFloorDB)
                open.scoreTotal += c.score
                openEpisode = open
                return
            }
            episodes.append(open)
            openEpisode = nil
        }

        let run = trailingRun()
        guard run.count >= tuning.openRun else { return }
        let intervals = zip(run.dropFirst(), run).map { $0.0.start - $0.1.start }
        guard let shortest = intervals.min(), let longest = intervals.max(), shortest > 0,
              longest / shortest <= tuning.maxIrregularity else { return }
        openEpisode = SnoreEpisode(
            start: run[0].start,
            end: run.map(\.end).max() ?? c.end,
            events: run.count,
            peakAboveFloorDB: run.map(\.peakAboveFloorDB).max() ?? c.peakAboveFloorDB,
            scoreTotal: run.reduce(0) { $0 + $1.score }
        )
    }

    /// The candidates at the end of the list whose onsets follow each other
    /// at breathing intervals, oldest first.
    private func trailingRun() -> [SnoreSoundEvent] {
        guard var previous = candidates.last else { return [] }
        var run = [previous]
        for c in candidates.dropLast().reversed() {
            let gap = previous.start - c.start
            guard gap >= tuning.minInterval, gap <= tuning.maxInterval else { break }
            run.append(c)
            previous = c
        }
        return run.reversed()
    }

    private var lastOnsetInOpenEpisode: TimeInterval? {
        openEpisode.flatMap { lastOnset(in: $0) }
    }

    private func lastOnset(in episode: SnoreEpisode) -> TimeInterval? {
        candidates.last { $0.start >= episode.start && $0.start <= episode.end }?.start
    }

    private mutating func closeEpisodeIfQuiet(at t: TimeInterval) {
        guard let open = openEpisode else { return }
        let last = lastOnsetInOpenEpisode ?? open.end
        if t - last > tuning.extendInterval {
            episodes.append(open)
            openEpisode = nil
        }
    }
}
