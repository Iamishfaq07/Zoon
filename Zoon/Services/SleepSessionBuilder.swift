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

    /// A single sample longer than this is not a real sleep record, and is
    /// dropped before clustering.
    ///
    /// HealthKit faithfully stores whatever a writer hands it, and one
    /// malformed multi-hour "asleep" block is a known third-party artifact.
    /// Grouping per source stops such a sample corrupting *other* sources'
    /// nights, but within its own source there is no rival account to
    /// arbitrate against: the block simply bridges every genuine episode it
    /// spans, and the result is a physically impossible night whose duration
    /// then poisons debt, need, and every baseline computed downstream. An
    /// integration test caught exactly this -- two 8-hour nights and one
    /// 20-hour block emerging as a single 32-hour "night".
    ///
    /// Dropping the sample loses whatever it claimed. That is the right
    /// trade: what it claimed was not true, and keeping it destroys the real
    /// nights on either side by merging them into it. 16 hours is deliberately
    /// generous -- longer than any plausible single sleep record, including a
    /// long `inBed` span -- so this only ever catches the pathological case.
    var maximumPlausibleSampleDuration: TimeInterval = 16 * 60 * 60

    /// Overrides automatic source selection when set -- see
    /// `UserPreferences.preferredSleepSourceBundleIdentifier`. `nil` (the
    /// default) keeps the automatic richest-source pick.
    ///
    /// Preferred over `preferredSourceName` below whenever both are set:
    /// a bundle identifier is stable across a device rename, a display
    /// language change, or Apple renaming a source in a future OS release,
    /// none of which change a matched-by-name preference gracefully -- it
    /// just silently stops matching and falls through to automatic
    /// selection with no visible error.
    var preferredSourceBundleIdentifier: String? = nil

    /// Legacy display-name-based override, kept only for a preference
    /// stored before `preferredSourceBundleIdentifier` existed. Settings
    /// now writes both fields together (see `SettingsView.sourceSection`),
    /// so this is purely a fallback for a preference set before that
    /// change shipped -- it stays honored rather than silently dropped
    /// until the user next opens Settings' source picker, which re-saves
    /// it as a bundle identifier.
    var preferredSourceName: String? = nil

    // MARK: - Public API

    /// Groups samples into sessions, newest last.
    ///
    /// The pipeline is deliberately **per source first**:
    ///
    /// ```text
    /// samples grouped by source
    ///   -> candidate episodes per source
    ///   -> overlapping candidates grouped
    ///   -> quality scoring
    ///   -> canonical episode selection
    /// ```
    ///
    /// The order matters, and getting it wrong was a real defect. Clustering
    /// every source's samples together by time gap looks safe -- a gap is a
    /// gap -- but it lets *one* malformed sample from *one* source silently
    /// restructure another source's night. A third-party app that writes a
    /// single 20-hour "asleep" block spans the gap between two genuine Apple
    /// Watch episodes, so they land in one cluster and are emitted as one
    /// impossible night with the waking day inside it. Clustering each source
    /// against only its own samples contains that damage: a bad sample can
    /// still ruin its own source's episodes, and nothing else.
    ///
    /// Selection still happens per episode rather than once per query. That
    /// was the earlier fix and it stays: choosing one source for a whole
    /// multi-week import meant switching Apple Watches, or losing Watch
    /// coverage for a single night, discarded every night the "losing" source
    /// wrote. Both properties hold now -- one winner per real-world episode,
    /// and no cross-source bridging.
    func buildSessions(from samples: [HKCategorySample]) -> [SleepSession] {
        guard !samples.isEmpty else { return [] }

        // Discard impossible individual samples before anything groups them,
        // so one of them cannot glue unrelated episodes together. See
        // `maximumPlausibleSampleDuration`.
        let plausible = samples.filter {
            $0.endDate.timeIntervalSince($0.startDate) <= maximumPlausibleSampleDuration
        }
        guard !plausible.isEmpty else { return [] }

        let candidates = Dictionary(grouping: plausible) { $0.sourceRevision.source.bundleIdentifier }
            .values
            .flatMap { Self.clusterByGap($0, threshold: sessionGapThreshold) }
            .map(Candidate.init)

        return Self.overlapGroups(in: candidates)
            .flatMap { canonicalCandidates(in: $0) }
            .compactMap { makeSession(from: $0.samples) }
            // An in-bed schedule with no asleep sample is not a sleep episode.
            // Letting it through can make a long empty span beat the user's
            // actual staged night when the coordinator chooses one row per day.
            .filter {
                $0.timeInBed >= minimumSessionDuration
                    && $0.totalAsleepMinutes > 0
            }
            .sorted { $0.start < $1.start }
    }

    /// The most recent qualifying session — "last night".
    func latestSession(from samples: [HKCategorySample]) -> SleepSession? {
        buildSessions(from: samples).last
    }

    /// Chooses the episode most likely to be the main sleep when several end
    /// on the same calendar date. Total asleep is the primary signal; staged
    /// coverage breaks close calls, followed by the overall span.
    static func preferredMainSleep(in sessions: [SleepSession]) -> SleepSession? {
        sessions.max { lhs, rhs in
            if lhs.totalAsleepMinutes != rhs.totalAsleepMinutes {
                return lhs.totalAsleepMinutes < rhs.totalAsleepMinutes
            }
            if lhs.stagedAsleepMinutes != rhs.stagedAsleepMinutes {
                return lhs.stagedAsleepMinutes < rhs.stagedAsleepMinutes
            }
            return lhs.timeInBed < rhs.timeInBed
        }
    }

    // MARK: - Candidates

    /// One source's view of one episode, before any cross-source arbitration.
    struct Candidate {
        let samples: [HKCategorySample]
        let span: DateInterval
        let sourceBundleIdentifier: String

        init(samples: [HKCategorySample]) {
            self.samples = samples
            let start = samples.map(\.startDate).min() ?? .distantPast
            let end = max(samples.map(\.endDate).max() ?? start, start)
            self.span = DateInterval(start: start, end: end)
            self.sourceBundleIdentifier = samples.first?.sourceRevision.source.bundleIdentifier ?? ""
        }
    }

    /// Splits one source's samples on the gap threshold. Extracted so it can
    /// run per source rather than across the whole batch.
    ///
    /// Tracks the furthest-seen end date rather than the previous sample's,
    /// because samples can be out of order in duration even when sorted by
    /// start -- a long `inBed` sample followed by short stage samples inside it.
    static func clusterByGap(_ samples: [HKCategorySample], threshold: TimeInterval) -> [[HKCategorySample]] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }

        var clusters: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var currentEnd: Date?

        for sample in sorted {
            if let end = currentEnd, sample.startDate.timeIntervalSince(end) > threshold {
                clusters.append(current)
                current = []
                currentEnd = nil
            }
            current.append(sample)
            currentEnd = max(currentEnd ?? sample.endDate, sample.endDate)
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    /// Groups candidates that describe the same real-world episode, i.e. that
    /// overlap in time. Transitive by design: A overlapping B and B
    /// overlapping C puts all three in one group, because they are all
    /// competing accounts of one span of the user's night.
    ///
    /// Two candidates from the *same* source can never overlap -- they were
    /// split by gap -- so a group only ever contains rival sources.
    static func overlapGroups(in candidates: [Candidate]) -> [[Candidate]] {
        let sorted = candidates.sorted { $0.span.start < $1.span.start }
        var groups: [[Candidate]] = []
        var current: [Candidate] = []
        var currentEnd = Date.distantPast

        for candidate in sorted {
            if current.isEmpty || candidate.span.start < currentEnd {
                current.append(candidate)
                currentEnd = max(currentEnd, candidate.span.end)
            } else {
                groups.append(current)
                current = [candidate]
                currentEnd = candidate.span.end
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // MARK: - Canonical selection

    /// Picks the winning source for one overlap group and returns **all** of
    /// that source's candidates in it.
    ///
    /// Returning all of them is what actually undoes a bridge. When a bad
    /// 20-hour sample from source B overlaps two clean episodes from source A,
    /// the group is `[A1, A2, B1]`; A wins on quality, and both A1 and A2 are
    /// emitted as the separate episodes they always were. B's bridge is
    /// discarded rather than being allowed to define the night's shape.
    ///
    /// Merging *across* sources is never an option: two trackers disagree
    /// about stage boundaries, and any union of them produces a night neither
    /// device reported and the Health app never shows.
    private func canonicalCandidates(in group: [Candidate]) -> [Candidate] {
        let bySource = Dictionary(grouping: group, by: \.sourceBundleIdentifier)
        guard bySource.count > 1 else { return group }

        // An explicit user choice is not a heuristic input -- it wins outright.
        if let preferredSourceBundleIdentifier, let match = bySource[preferredSourceBundleIdentifier] {
            return match
        }
        if preferredSourceBundleIdentifier == nil, let preferredSourceName,
           let match = bySource.values.first(where: {
               $0.first?.samples.first?.sourceRevision.source.name == preferredSourceName
           }) {
            return match
        }

        let best = bySource.max { lhs, rhs in
            let lhsScore = Self.qualityScore(for: lhs.value)
            let rhsScore = Self.qualityScore(for: rhs.value)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            // Deterministic last resort, so the same input never yields a
            // different night between two runs.
            return lhs.key < rhs.key
        }
        return best?.value ?? group
    }

    /// How much to trust one source's account of an episode.
    ///
    /// Weighted so that *what the samples actually say* dominates, and
    /// provenance only breaks ties. The previous implementation made
    /// `productType != nil` a hard tier, which meant a paired Apple Watch won
    /// even when the thing it wrote was obviously broken -- an implausibly
    /// long block, or a span with almost no sleep in it. Apple Watch staging
    /// is genuinely better *on average*, which is a reason to weight it, not
    /// a reason to stop reading the data.
    static func qualityScore(for candidates: [Candidate]) -> Double {
        let samples = candidates.flatMap(\.samples)
        guard !samples.isEmpty else { return 0 }

        // Staged coverage: does this source distinguish core/deep/REM at all,
        // or is it writing undifferentiated "asleep"?
        let staged = Double(samples.filter(\.isStagedAsleep).count)
        let stagedFraction = staged / Double(samples.count)

        // Plausibility: no real sleep episode runs 16 hours. Decays to zero by
        // 24h rather than cliff-edging, so a merely-long night is not treated
        // the same as a clearly broken one.
        let longest = candidates.map(\.span.duration).max() ?? 0
        let plausibility = longest <= 16 * 3600
            ? 1.0
            : max(0, 1 - (longest - 16 * 3600) / (8 * 3600))

        // Continuity: how much of the claimed span is actually asleep. A
        // source that spans ten hours to report forty minutes of sleep is
        // describing something other than a night.
        let asleepSeconds = samples
            .filter { sample in
                guard let stage = SleepStage(sampleValue: sample.value) else { return false }
                return SleepStage.asleepStages.contains(stage)
            }
            .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        let totalSpan = candidates.reduce(0.0) { $0 + $1.span.duration }
        let coverage = totalSpan > 0 ? min(1, asleepSeconds / totalSpan) : 0

        return 3.0 * stagedFraction
            + 2.0 * plausibility
            + 1.0 * coverage
            + 0.5 * provenanceBonus(for: samples)
    }

    /// A modest thumb on the scale for a source Apple measures on-device,
    /// deliberately smaller than any single data-driven term above.
    ///
    /// `productType` is only ever populated for a sample written by a paired
    /// Apple Watch (e.g. "Watch7,4"); every other source, Apple's own iPhone
    /// Sleep Schedule included, leaves it nil.
    private static func provenanceBonus(for samples: [HKCategorySample]) -> Double {
        guard let sample = samples.first else { return 0 }
        if sample.sourceRevision.productType != nil { return 1.0 }
        if sample.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple.health") { return 0.5 }
        return 0
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
            sourceName: samples.first?.sourceRevision.source.name,
            sourceBundleIdentifier: samples.first?.sourceRevision.source.bundleIdentifier,
            timeZoneIdentifier: samples.compactMap { sample in
                guard let identifier = sample.metadata?[HKMetadataKeyTimeZone] as? String,
                      TimeZone(identifier: identifier) != nil else { return nil }
                return identifier
            }.first ?? TimeZone.current.identifier
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
    /// `sourceRevision.source.bundleIdentifier` -- stable across a device
    /// rename or a locale change, unlike `sourceName`. This is what an
    /// explicit "preferred source" choice should actually be matched
    /// against; `sourceName` stays around only for display and for
    /// matching sources recorded before this field existed. See
    /// `SleepSessionBuilder.canonicalCandidates`'s doc comment.
    let sourceBundleIdentifier: String?
    /// Timezone recorded with the HealthKit samples. This must travel with the
    /// episode: `Calendar.current` may be somewhere else when a traveler next
    /// refreshes the same historical night.
    let timeZoneIdentifier: String

    var wakeDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.startOfDay(for: end)
    }

    var nightKey: String {
        NightKey.make(wakeInstant: end, timeZoneIdentifier: timeZoneIdentifier)
    }

    /// Session span from first sample to last -- **not** necessarily a real
    /// measurement of time in bed. When the source wrote explicit `inBed`
    /// samples (`hasExplicitInBedData`), this is exactly that. When it
    /// didn't (Apple Watch alone never does), this is standing in for it:
    /// the span of asleep/awake activity, which omits any time lying awake
    /// before the first asleep sample or after the last, so it understates
    /// true time in bed and correspondingly overstates efficiency. See
    /// `FeatureExtractor` for where that distinction gets surfaced.
    var timeInBed: TimeInterval { end.timeIntervalSince(start) }

    /// True when the source wrote real `inBed` samples for this session, so
    /// `timeInBed` is an actual measurement rather than a same-shaped
    /// approximation from the asleep/awake span.
    var hasExplicitInBedData: Bool { !inBedIntervals.isEmpty }

    func minutes(_ stage: SleepStage) -> Double { stageMinutes[stage] ?? 0 }

    var totalAsleepMinutes: Double {
        asleepIntervals.reduce(0) { $0 + $1.duration } / 60
    }

    var stagedAsleepMinutes: Double {
        minutes(.core) + minutes(.deep) + minutes(.rem)
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

    /// Shortest awake stretch that counts as a real awakening.
    ///
    /// Wearable stage classification flickers: a single restless movement can
    /// produce a 30-second `awake` sample between two `core` samples, and the
    /// sleeper has no memory of it. Counting those as awakenings inflates a
    /// number the score and the insight engine both read as fragmentation,
    /// and it inflates it most for light sleepers wearing the watch tightly
    /// -- exactly the people most likely to already believe they sleep badly.
    ///
    /// Two minutes is the conventional floor for a "meaningful" awakening in
    /// actigraphy. The raw intervals stay untouched in `awakeIntervals` and
    /// the raw samples in `segments`, so the hypnogram still draws every
    /// blip -- this only governs the count that gets scored.
    static let meaningfulAwakeningThreshold: TimeInterval = 120

    /// Meaningful awakenings after sleep onset.
    ///
    /// Tossing around before you fall asleep is not fragmentation, and counting
    /// it inflates a number the insight engine reads as a signal. Neither is a
    /// momentary classification flicker -- see
    /// `meaningfulAwakeningThreshold`.
    var wakeCountAfterOnset: Int {
        guard let onset = sleepOnset else { return 0 }
        return awakeIntervals
            .filter { $0.start > onset && $0.duration >= Self.meaningfulAwakeningThreshold }
            .count
    }

    /// Every awake stretch after onset, including sub-threshold flickers.
    /// Kept separate so a view that wants the raw picture can still get it.
    var rawAwakeningCountAfterOnset: Int {
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
