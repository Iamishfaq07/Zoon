import Foundation

/// The canonical accounting of everything counted as sleep for one wake
/// date -- main sleep, auto-detected naps, manually-logged naps, and
/// auto-detected secondary sleep -- so historical Sleep Debt, today's nap
/// credit, and anything else that needs "how much did this day actually
/// sleep" can't independently compute three different answers from the
/// same underlying `SleepEpisodeRecord`/`NapStore` data.
///
/// Before this, that question had two separate, disagreeing
/// implementations: `SleepHistoryStore.historicalFeatures` folded only
/// HealthKit-auto-detected episodes into a night's 24-hour total (manual
/// naps never entered historical debt at all), while
/// `SleepDataCoordinator.deduplicatedNapMinutes` folded both sources
/// together for *today's* nap credit, but by summing each source's full
/// session interval rather than actual asleep time -- crediting
/// in-bed-but-awake padding as sleep, and simply summing both sources'
/// intervals when a nap really was caught by both instead of counting it
/// once.
struct SleepDaySummary: Sendable {
    let mainSleepMinutes: Double
    let automaticNapAsleepMinutes: Double
    let manualNapMinutes: Double
    let secondarySleepMinutes: Double
    /// Auto-detected episodes plus manual naps that contributed to this
    /// summary, counted individually even when two sources' records were
    /// merged into one credited nap -- the "preserve both provenance
    /// sources" half of the fix: nothing here hides that a nap was seen
    /// twice, only that it's credited once.
    let episodeCount: Int

    var total24HourSleepMinutes: Double {
        mainSleepMinutes + automaticNapAsleepMinutes + manualNapMinutes + secondarySleepMinutes
    }

    /// A HealthKit-detected session not selected as the night's main
    /// sleep. Mirrors the shape of `SleepEpisodeRecord` without depending
    /// on it, so this type stays a pure, dependency-free function callable
    /// from `Shared/` and trivially testable in isolation -- only whether
    /// an episode is a nap matters here, not its full classification.
    struct AutoEpisode: Sendable {
        let isNap: Bool
        let interval: DateInterval
        let asleepMinutes: Double

        init(isNap: Bool, interval: DateInterval, asleepMinutes: Double) {
            self.isNap = isNap
            self.interval = interval
            self.asleepMinutes = asleepMinutes
        }
    }

    /// A manually-logged nap. A user's own start/stop timer already *is*
    /// the asleep estimate -- there's no separate in-bed-but-awake padding
    /// to strip the way there can be for a HealthKit session.
    struct ManualNap: Sendable {
        let interval: DateInterval
        let minutes: Double

        init(interval: DateInterval, minutes: Double) {
            self.interval = interval
            self.minutes = minutes
        }
    }

    static func compute(
        mainSleepMinutes: Double,
        autoEpisodes: [AutoEpisode],
        manualNaps: [ManualNap]
    ) -> SleepDaySummary {
        let autoNaps = autoEpisodes.filter(\.isNap)
        let secondary = autoEpisodes.filter { !$0.isNap }
        let credit = dedupedNapCredit(autoNaps: autoNaps, manualNaps: manualNaps)

        return SleepDaySummary(
            mainSleepMinutes: mainSleepMinutes,
            automaticNapAsleepMinutes: credit.auto,
            manualNapMinutes: credit.manual,
            secondarySleepMinutes: secondary.reduce(0) { $0 + $1.asleepMinutes },
            episodeCount: autoEpisodes.count + manualNaps.count
        )
    }

    /// Overlap-aware nap dedupe. Each source's full interval is used only
    /// to detect that a Zoon-timer nap and a Watch-detected nap were the
    /// same event -- exactly the comparison the previous implementation
    /// made -- but once a cluster of overlapping records is found, it's
    /// credited once, using whichever single source's own asleep-time
    /// estimate is larger, rather than summing every record's full
    /// interval width. Handles clusters of more than two overlapping
    /// records (e.g. two auto-detected fragments of one nap plus a manual
    /// log spanning both), not just pairs.
    private static func dedupedNapCredit(
        autoNaps: [AutoEpisode], manualNaps: [ManualNap]
    ) -> (auto: Double, manual: Double) {
        enum Source { case auto, manual }
        struct Item { let interval: DateInterval; let minutes: Double; let source: Source }

        var items = autoNaps.map { Item(interval: $0.interval, minutes: $0.asleepMinutes, source: .auto) }
            + manualNaps.map { Item(interval: $0.interval, minutes: $0.minutes, source: .manual) }
        guard !items.isEmpty else { return (0, 0) }
        items.sort { $0.interval.start < $1.interval.start }

        var autoTotal = 0.0
        var manualTotal = 0.0
        var cluster = [items[0]]
        var clusterEnd = items[0].interval.end

        func flushCluster() {
            guard let winner = cluster.max(by: { $0.minutes < $1.minutes }) else { return }
            switch winner.source {
            case .auto: autoTotal += winner.minutes
            case .manual: manualTotal += winner.minutes
            }
        }

        for item in items.dropFirst() {
            if item.interval.start < clusterEnd {
                cluster.append(item)
                clusterEnd = max(clusterEnd, item.interval.end)
            } else {
                flushCluster()
                cluster = [item]
                clusterEnd = item.interval.end
            }
        }
        flushCluster()

        return (autoTotal, manualTotal)
    }
}
