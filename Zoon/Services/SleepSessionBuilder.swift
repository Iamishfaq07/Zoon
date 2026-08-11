import Foundation
import HealthKit

/// Turns a flat, messy array of `HKCategorySample`s into discrete sleep sessions.
///
/// This is the least glamorous file in the project and the one most likely to be
/// the cause of a wrong number on screen. Three HealthKit realities drive it:
///
/// 1. **Samples are not grouped into nights.** A query returns everything in the
///    time range. An afternoon nap and last night's sleep arrive in the same
///    array with nothing marking the boundary. Treating `first.startDate` to
///    `last.endDate` as one session silently merges them and reports a "night"
///    that includes the entire waking day between — tanking efficiency.
///
/// 2. **Samples overlap.** If an Apple Watch and a third-party app both write
///    sleep, you get two full sets of samples for the same night. Summing
///    durations then double-counts and can produce >100% efficiency.
///
/// 3. **Not every source writes stages.** Apple Watch writes core/deep/REM;
///    iPhone sleep schedule and most third-party apps write only
///    `asleepUnspecified`. Code that only handles the staged values reports
///    "0h 0m" for a night the user definitely slept.
///
/// The builder handles all three: it picks a single best source, merges
/// overlapping intervals per stage, and treats unspecified sleep as sleep.
struct SleepSessionBuilder {

    /// A gap longer than this ends a session.
    ///
    /// 60 minutes is a pragmatic choice: long enough to survive a bathroom trip
    /// or a gap in watch coverage, short enough to keep an evening nap separate
    /// from the main night.
    var sessionGapThreshold: TimeInterval = 60 * 60

    /// Sessions shorter than this are discarded outright, as sensor noise
    /// rather than real sleep -- a few minutes of a stray `inBed` sample, not
    /// anything a person would call a sleep or a nap.
    ///
    /// This used to be two hours, which silently discarded genuinely real
    /// short sleep along with actual noise: a fragmented main-sleep night cut
    /// short by an early flight, or an honest 45-minute nap, both vanished
    /// with no record at all -- not shown as short, just absent, which reads
    /// to a user as "the app didn't track last night" rather than "you slept
    /// less than usual." 15 minutes is a genuine sensor-noise floor; nothing
    /// above it gets classified as main-sleep-vs-nap yet (that's a larger
    /// change -- `latestSession` still just takes the most recent cluster),
    /// but it no longer disappears.
    var minimumSessionDuration: TimeInterval = 60 * 15

    // MARK: - Public API

    /// Groups samples into sessions, newest last.
    ///
    /// Source selection happens **after** clustering, one winner per cluster —
    /// not once for the whole batch. `buildSessions` is routinely called with
    /// weeks of history in one query (an initial import, a wide incremental
    /// sync window), and choosing a single source for that entire span meant
    /// switching Apple Watches, or losing Watch coverage for even one night,
    /// silently discarded every night written by whichever source didn't win
    /// -- not just that one night's ambiguity, but every other night's
    /// perfectly good data from the "losing" source. Clustering by time gap
    /// doesn't care which source a sample came from, so it's safe to run
    /// across every source's samples together; only the per-night dedup step
    /// that follows needs to pick one source, and it needs to do that once
    /// per night, not once for the query.
    func buildSessions(from samples: [HKCategorySample]) -> [SleepSession] {
        guard !samples.isEmpty else { return [] }

        let sorted = samples.sorted { $0.startDate < $1.startDate }

        // Walk the samples, cutting a new session whenever the gap from the
        // furthest-seen end date exceeds the threshold. Tracking the max end
        // (not the previous sample's end) matters because samples can be
        // out of order in duration even when sorted by start.
        var clusters: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var currentEnd: Date?

        for sample in sorted {
            if let end = currentEnd, sample.startDate.timeIntervalSince(end) > sessionGapThreshold {
                clusters.append(current)
                current = []
                currentEnd = nil
            }
            current.append(sample)
            currentEnd = max(currentEnd ?? sample.endDate, sample.endDate)
        }
        if !current.isEmpty { clusters.append(current) }

        return clusters
            .map(preferredSourceSamples)
            .compactMap(makeSession)
            .filter { $0.timeInBed >= minimumSessionDuration }
    }

    /// The most recent qualifying session — "last night".
    func latestSession(from samples: [HKCategorySample]) -> SleepSession? {
        buildSessions(from: samples).last
    }

    // MARK: - Source selection

    /// Picks one source and drops the rest, **within a single already-clustered
    /// session's candidate samples** -- called once per cluster, not once for
    /// an entire query's worth of samples. See `buildSessions`'s doc comment
    /// for why that distinction is the whole fix.
    ///
    /// Merging *across* sources is a trap: two trackers disagree about stage
    /// boundaries, and any union of their samples produces a night that neither
    /// device reported. Choosing the single richest source gives an answer that
    /// matches what the user sees in the Health app.
    ///
    /// Preference order: most staged samples wins (an Apple Watch will always
    /// beat an iPhone here), ties broken by total sample count.
    private func preferredSourceSamples(from samples: [HKCategorySample]) -> [HKCategorySample] {
        let grouped = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        guard grouped.count > 1 else { return samples }

        let best = grouped.max { lhs, rhs in
            let lhsStaged = lhs.value.filter(\.isStagedAsleep).count
            let rhsStaged = rhs.value.filter(\.isStagedAsleep).count
            if lhsStaged != rhsStaged { return lhsStaged < rhsStaged }
            return lhs.value.count < rhs.value.count
        }
        return best?.value ?? samples
    }

    // MARK: - Session assembly

    private func makeSession(from samples: [HKCategorySample]) -> SleepSession? {
        guard !samples.isEmpty else { return nil }

        // Bucket by stage, then merge overlapping intervals *within* each bucket.
        // Merging per-stage rather than globally preserves the breakdown while
        // still killing duplicate-source double counting.
        var intervals: [SleepStage: [DateInterval]] = [:]
        for sample in samples {
            guard let stage = SleepStage(sampleValue: sample.value),
                  sample.endDate > sample.startDate else { continue }
            intervals[stage, default: []].append(DateInterval(start: sample.startDate, end: sample.endDate))
        }

        let merged = intervals.mapValues { Self.mergeOverlapping($0) }
        let minutes = merged.mapValues { $0.reduce(0) { $0 + $1.duration } / 60 }

        // Session bounds span every sample, including inBed and awake.
        guard let start = samples.map(\.startDate).min(),
              let end = samples.map(\.endDate).max() else { return nil }

        let asleepIntervals = SleepStage.asleepStages.flatMap { merged[$0] ?? [] }
        let mergedAsleep = Self.mergeOverlapping(asleepIntervals)

        // Chronological timeline for the hypnogram. Built from the *merged*
        // per-stage intervals so duplicate-source overlap is already gone, then
        // flattened and sorted. `inBed` is excluded — it spans the whole night
        // and would draw as a bar behind everything else.
        let segments = merged
            .filter { $0.key != .inBed }
            .flatMap { stage, intervals in
                intervals.map { StageSegment(stage: stage, start: $0.start, end: $0.end) }
            }
            .sorted { $0.start < $1.start }

        return SleepSession(
            start: start,
            end: end,
            stageMinutes: minutes,
            asleepIntervals: mergedAsleep,
            inBedIntervals: merged[.inBed] ?? [],
            awakeIntervals: merged[.awake] ?? [],
            segments: segments,
            sourceName: samples.first?.sourceRevision.source.name
        )
    }

    /// Classic sweep-and-merge. Sorted by start, extend the open interval while
    /// the next one overlaps or touches, otherwise close it and start a new one.
    static func mergeOverlapping(_ intervals: [DateInterval]) -> [DateInterval] {
        guard intervals.count > 1 else { return intervals }
        let sorted = intervals.sorted { $0.start < $1.start }

        var result: [DateInterval] = []
        var current = sorted[0]

        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                if interval.end > current.end {
                    current = DateInterval(start: current.start, end: interval.end)
                }
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }
}

// MARK: - Session

/// One contiguous sleep session with duplicate-free, per-stage totals.
struct SleepSession {
    let start: Date
    let end: Date
    let stageMinutes: [SleepStage: Double]
    /// Merged asleep intervals (all asleep stages unioned), used for sleep onset
    /// and for scoping the vitals queries.
    let asleepIntervals: [DateInterval]
    let inBedIntervals: [DateInterval]
    let awakeIntervals: [DateInterval]
    /// Chronological stage timeline, overlap already merged. Drives the hypnogram.
    let segments: [StageSegment]
    let sourceName: String?

    var timeInBed: TimeInterval { end.timeIntervalSince(start) }

    func minutes(_ stage: SleepStage) -> Double { stageMinutes[stage] ?? 0 }

    var totalAsleepMinutes: Double {
        asleepIntervals.reduce(0) { $0 + $1.duration } / 60
    }

    /// When the user actually fell asleep — start of the first asleep interval.
    var sleepOnset: Date? { asleepIntervals.first?.start }

    /// Minutes from first in-bed record to sleep onset.
    ///
    /// `nil` when the source writes no `inBed` samples. Apple Watch does not, so
    /// for most users this stays `nil` unless iPhone sleep schedule is on — the
    /// UI hides the row rather than showing a fabricated zero.
    var latencyMinutes: Double? {
        guard let bedStart = inBedIntervals.map(\.start).min(),
              let onset = sleepOnset,
              onset > bedStart else { return nil }
        return onset.timeIntervalSince(bedStart) / 60
    }

    /// Awakenings after sleep onset only.
    ///
    /// Tossing around before you fall asleep is not fragmentation, and counting
    /// it inflates a number the insight engine reads as a signal.
    var wakeCountAfterOnset: Int {
        guard let onset = sleepOnset else { return 0 }
        return awakeIntervals.filter { $0.start > onset }.count
    }
}

// MARK: - Stage mapping

/// HealthKit raw-value mapping for `SleepStage`.
///
/// The stage vocabulary itself lives in `Shared/SleepStage.swift` so the widget
/// and the hypnogram renderer can use it without importing HealthKit. Only this
/// mapping is HealthKit-specific, and keeping it in one place is what stops the
/// "did you remember `asleepUnspecified`?" question from recurring at every
/// switch site.
extension SleepStage {
    init?(sampleValue: Int) {
        switch sampleValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue: self = .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue: self = .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: self = .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: self = .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: self = .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: self = .unspecified
        default: return nil
        }
    }
}

private extension HKCategorySample {
    /// True for the three staged asleep values — used to rank sources by how
    /// much detail they provide.
    var isStagedAsleep: Bool {
        // Unwrapped first: `switch` over an Optional can't match bare enum cases.
        guard let stage = SleepStage(sampleValue: value) else { return false }
        switch stage {
        case .core, .deep, .rem: return true
        default: return false
        }
    }
}
