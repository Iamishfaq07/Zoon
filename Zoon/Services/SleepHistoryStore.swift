import Foundation
import SwiftData
import os

/// All SwiftData reads and writes, plus the rolling-window math the insight
/// engine depends on.
///
/// Concentrating the statistics here rather than scattering them across views
/// means "what is the 7-day HRV average?" has exactly one answer, and the widget
/// and dashboard can't drift apart.
@MainActor
final class SleepHistoryStore {

    private let context: ModelContext
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "HistoryStore")

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Reads

    /// All nights, newest first.
    func allNights(limit: Int? = nil) -> [SleepNightRecord] {
        var descriptor = FetchDescriptor<SleepNightRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Nights within the last `days` calendar days, oldest first — the order
    /// charts want.
    func nights(inLast days: Int) -> [SleepNightRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        // The predicate captures a plain `Date` local; `#Predicate` cannot call
        // Calendar APIs inside the expression.
        let descriptor = FetchDescriptor<SleepNightRecord>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Windowed fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    var latestNight: SleepNightRecord? {
        allNights(limit: 1).first
    }

    func night(on date: Date) -> SleepNightRecord? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<SleepNightRecord>(
            predicate: #Predicate { $0.date == day }
        )
        return try? context.fetch(descriptor).first
    }

    var isEmpty: Bool {
        (try? context.fetchCount(FetchDescriptor<SleepNightRecord>())) ?? 0 == 0
    }

    /// Distinct HealthKit source names seen across every stored night and
    /// episode, sorted alphabetically -- the choices for the "Preferred
    /// source" setting. Built from what's already on disk rather than a
    /// fresh HealthKit source query: nothing new to ask permission for, and
    /// it naturally only lists sources that have actually written sleep for
    /// this person, not every source HealthKit happens to know about.
    func knownSourceNames() -> [String] {
        let nightSources = allNights().compactMap(\.sourceName)
        let episodeSources = (try? context.fetch(FetchDescriptor<SleepEpisodeRecord>()))?.compactMap(\.sourceName) ?? []
        return Set(nightSources + episodeSources).sorted()
    }

    /// Display name paired with the stable bundle identifier Settings'
    /// "Preferred source" picker should actually store -- see
    /// `SleepSessionBuilder.preferredSourceBundleIdentifier`'s doc comment
    /// for why. Built from stored nights only, not episodes: a source that
    /// only ever wrote secondary episodes and never a main night is a real
    /// but narrow gap, not worth the extra column `SleepEpisodeRecord`
    /// would need to close it here too.
    ///
    /// `bundleIdentifier` is `nil` for a source seen only in rows written
    /// before that column existed -- the picker falls back to name-based
    /// matching for those until a re-sync backfills it.
    func knownSleepSources() -> [(name: String, bundleIdentifier: String?)] {
        var byName: [String: String?] = [:]
        for night in allNights() {
            guard let name = night.sourceName else { continue }
            // A later row's bundleIdentifier (if any) wins over an earlier
            // nil -- the same "richer data supersedes" spirit as the rest
            // of this file's backfill columns.
            if byName[name, default: nil] == nil {
                byName[name] = night.sourceBundleIdentifier
            }
        }
        return byName.map { (name: $0.key, bundleIdentifier: $0.value) }.sorted { $0.name < $1.name }
    }

    /// Every stored night, oldest first, rebuilt with the rolling context that
    /// existed immediately before that night.
    ///
    /// Comparative fields are intentionally not persisted, but that does not
    /// mean one current baseline can be stamped onto all of history. Sleep debt
    /// in particular is a date-derived value consumed by charts, achievements,
    /// and journal correlations. This bounded chronological pass fetches once
    /// and retains only the longest rolling window used by any baseline field.
    func historicalFeatures(goalMinutes: Double, manualNaps: [NapStore.Nap] = []) -> [SleepNightFeatures] {
        let chronological = allNights().reversed()
        var priorNewestFirst: [SleepNightRecord] = []
        var features: [SleepNightFeatures] = []

        for record in chronological {
            let rolling = makeBaseline(
                priorNightsNewestFirst: priorNewestFirst,
                goalMinutes: goalMinutes,
                manualNaps: manualNaps
            )
            features.append(record.features(
                baseline: rolling,
                secondaryAsleepMinutes: secondaryEpisodeAsleepMinutes(
                    forNightKey: record.nightKey ?? "", wakeDate: record.date,
                    timeZone: record.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current,
                    manualNaps: manualNaps
                )
            ))

            priorNewestFirst.insert(record, at: 0)
            if priorNewestFirst.count > 60 {
                priorNewestFirst.removeLast(priorNewestFirst.count - 60)
            }
        }

        return features
    }

    // MARK: - Writes

    /// Inserts or updates the night, keyed on date.
    ///
    /// Upsert rather than insert because HealthKit revises nights: the watch
    /// syncs progressively through the morning, and the same night gets richer
    /// over a few hours. Blind inserts would produce duplicates that break the
    /// one-row-per-day assumption the rolling windows rely on.
    /// - Parameter confirmedAbsent: metrics HealthKit definitively reported no
    ///   data for, which may therefore clear a stored value. Defaults to empty
    ///   so callers without query provenance -- an archive import, say -- can
    ///   never clear a measured value they know nothing about.
    @discardableResult
    func upsert(
        _ features: SleepNightFeatures,
        absoluteWristTempC: Double? = nil,
        confirmedAbsent: Set<VitalMetric> = [],
        nightKey: String? = nil
    ) -> SleepNightRecord {
        if let existing = matchingNight(
            key: nightKey,
            date: features.date,
            wakeTime: features.wakeTime
        ) {
            // A legacy row may have been filed using the device timezone at the
            // time of import. Once the recorded timezone is available, migrate
            // both its stable key and canonical wake-date boundary in place.
            existing.nightKey = nightKey ?? existing.nightKey
            existing.date = features.date
            existing.update(
                from: features,
                absoluteWristTempC: absoluteWristTempC,
                confirmedAbsent: confirmedAbsent
            )
            save()
            return existing
        }
        let record = SleepNightRecord(
            features: features,
            absoluteWristTempC: absoluteWristTempC,
            nightKey: nightKey
        )
        context.insert(record)
        save()
        return record
    }

    private func matchingNight(
        key: String?,
        date: Date,
        wakeTime: Date
    ) -> SleepNightRecord? {
        if let key {
            let descriptor = FetchDescriptor<SleepNightRecord>(
                predicate: #Predicate { $0.nightKey == key }
            )
            if let keyed = try? context.fetch(descriptor).first {
                return keyed
            }
        }

        // Migration fallback for rows created before `nightKey`: the same
        // HealthKit episode can move to a different absolute midnight after a
        // timezone change, but its actual wake instant remains stable.
        if let nearby = allNights().min(by: {
            abs($0.wakeTime.timeIntervalSince(wakeTime))
                < abs($1.wakeTime.timeIntervalSince(wakeTime))
        }), abs(nearby.wakeTime.timeIntervalSince(wakeTime)) < 6 * 3_600 {
            return nearby
        }

        return night(on: date)
    }

    func attach(_ insight: SleepInsight, to record: SleepNightRecord) {
        record.apply(insight)
        save()
    }

    /// Removes stored nights within `window` that no longer have a
    /// corresponding session in `validDates` — the counterpart to `upsert`
    /// for a night deleted or corrected away in the Health app, rather than
    /// added or changed.
    ///
    /// Scoped to `window`: only nights the caller actually re-verified
    /// against a fresh full-window fetch are eligible. A night stored outside
    /// `window` was never re-checked by this pass and must not be touched,
    /// or an old record could vanish just because the rolling sync window
    /// has since moved past it.
    func prune(window: DateInterval, keeping validDates: Set<Date>) {
        let start = window.start
        let end = window.end
        let descriptor = FetchDescriptor<SleepNightRecord>(
            predicate: #Predicate { $0.date >= start && $0.date <= end }
        )
        let inWindow: [SleepNightRecord]
        do {
            inWindow = try context.fetch(descriptor)
        } catch {
            logger.error("Prune fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let stale = inWindow.filter { !validDates.contains($0.date) }
        guard !stale.isEmpty else { return }
        for night in stale { context.delete(night) }
        save()
    }

    // MARK: - Secondary sleep episodes (naps, split sleep)

    /// Persists a session that wasn't selected as its wake date's main sleep.
    /// Upserts on `id` so a re-processed session updates in place rather than
    /// duplicating, the same shape as `upsert(_:)` for the main night.
    func upsertEpisode(
        id: String,
        nightKey: String,
        startDate: Date,
        endDate: Date,
        timezoneIdentifier: String,
        episodeType: SleepEpisodeType,
        asleepMinutes: Double,
        timeInBedMinutes: Double,
        sourceName: String?
    ) {
        let descriptor = FetchDescriptor<SleepEpisodeRecord>(predicate: #Predicate { $0.id == id })
        if let existing = try? context.fetch(descriptor).first {
            existing.nightKey = nightKey
            existing.startDate = startDate
            existing.endDate = endDate
            existing.timezoneIdentifier = timezoneIdentifier
            existing.episodeType = episodeType
            existing.asleepMinutes = asleepMinutes
            existing.timeInBedMinutes = timeInBedMinutes
            existing.sourceName = sourceName
        } else {
            context.insert(SleepEpisodeRecord(
                id: id,
                nightKey: nightKey,
                startDate: startDate,
                endDate: endDate,
                timezoneIdentifier: timezoneIdentifier,
                episodeType: episodeType,
                asleepMinutes: asleepMinutes,
                timeInBedMinutes: timeInBedMinutes,
                sourceName: sourceName
            ))
        }
        save()
    }

    /// Counterpart to `prune(window:keeping:)` for episodes: removes stored
    /// episodes whose `id` wasn't reconfirmed by this pass's full re-fetch of
    /// `window` -- a nap deleted or corrected away in the Health app should
    /// disappear from Zoon the same way a deleted main night does.
    ///
    /// Matches by episode `id`, not by the parent night's `nightKey`. A
    /// nightKey stays valid as long as *some* main sleep still exists for
    /// that wake date, so matching against it only ever caught the case
    /// where the whole night vanished -- a specific nap being deleted, or a
    /// nap's boundary being corrected in Health (which changes its `id`,
    /// since that's derived from the start time), left the old episode row
    /// behind forever because its nightKey was still perfectly valid.
    func pruneEpisodes(window: DateInterval, keeping validEpisodeIDs: Set<String>) {
        let start = window.start
        let end = window.end
        let descriptor = FetchDescriptor<SleepEpisodeRecord>(
            predicate: #Predicate { $0.startDate >= start && $0.startDate <= end }
        )
        let inWindow: [SleepEpisodeRecord]
        do {
            inWindow = try context.fetch(descriptor)
        } catch {
            logger.error("Episode prune fetch failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let stale = inWindow.filter { !validEpisodeIDs.contains($0.id) }
        guard !stale.isEmpty else { return }
        for episode in stale { context.delete(episode) }
        save()
    }

    /// Total minutes asleep across every stored secondary episode tied to a
    /// given night's key -- naps and split-sleep blocks the main night's own
    /// `timeAsleepMinutes` doesn't include -- plus any manually-logged naps
    /// for the same day, deduped against the auto-detected ones through
    /// `SleepDaySummary` so a nap caught by both sources is credited once.
    /// Manual naps previously never reached this calculation at all, so a
    /// nap only a Zoon timer caught (HealthKit "rarely" detects a short
    /// daytime nap -- see `NapStore`'s own doc comment) silently vanished
    /// from historical debt. Used to build a day's true 24-hour asleep
    /// total alongside the main sleep figure.
    func secondaryEpisodeAsleepMinutes(
        forNightKey nightKey: String,
        wakeDate: Date,
        timeZone: TimeZone = .current,
        manualNaps: [NapStore.Nap] = []
    ) -> Double {
        let descriptor = FetchDescriptor<SleepEpisodeRecord>(
            predicate: #Predicate { $0.nightKey == nightKey }
        )
        let episodes = (try? context.fetch(descriptor)) ?? []
        let autoEpisodes = episodes.map {
            SleepDaySummary.AutoEpisode(
                isNap: $0.episodeType == .nap,
                interval: DateInterval(start: $0.startDate, end: $0.endDate),
                asleepMinutes: $0.asleepMinutes
            )
        }

        // Manual naps are attributed to the day before the night they
        // credit -- the same convention `NapStore.minutesBefore(night:)`
        // and `SleepDataCoordinator.deduplicatedNapMinutes` already use,
        // now including their same `timeZone` parameter: the night's own
        // recorded timezone, not the device's current one, so which
        // calendar day a nap counts toward doesn't shift after travel.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDate) ?? wakeDate
        let manualEpisodes = manualNaps
            .filter { calendar.isDate($0.start, inSameDayAs: previousDay) }
            .map { SleepDaySummary.ManualNap(interval: DateInterval(start: $0.start, end: $0.end), minutes: $0.minutes) }

        return SleepDaySummary.compute(
            mainSleepMinutes: 0, autoEpisodes: autoEpisodes, manualNaps: manualEpisodes
        ).total24HourSleepMinutes
    }

    /// HealthKit-auto-detected naps whose start falls within `dayInterval`,
    /// as `SleepDaySummary` episodes -- used to dedupe against manually-
    /// logged naps covering the same time before crediting `SleepNeed`'s
    /// nap offset, so a nap caught by both a manual log and HealthKit
    /// doesn't count twice, and is credited by its measured asleep time
    /// rather than its full session span (which can include in-bed-but-
    /// awake padding).
    func autoDetectedNaps(in dayInterval: DateInterval) -> [SleepDaySummary.AutoEpisode] {
        let start = dayInterval.start
        let end = dayInterval.end
        let napRaw = SleepEpisodeType.nap.rawValue
        let descriptor = FetchDescriptor<SleepEpisodeRecord>(
            predicate: #Predicate { $0.episodeTypeRaw == napRaw && $0.startDate >= start && $0.startDate < end }
        )
        let episodes = (try? context.fetch(descriptor)) ?? []
        return episodes.map {
            SleepDaySummary.AutoEpisode(
                isNap: true,
                interval: DateInterval(start: $0.startDate, end: $0.endDate),
                asleepMinutes: $0.asleepMinutes
            )
        }
    }

    /// Every stored secondary episode, as export DTOs -- backup archives
    /// carry these too now, since without them a restored device has no way
    /// to reconstruct historical naps/secondary-sleep credit that isn't
    /// re-derivable from a fresh HealthKit anchor sync alone (a resync
    /// starts from "now," not from a backup's own history).
    func episodesForExport() -> [DataExporter.Archive.EpisodeRecord] {
        let episodes = (try? context.fetch(FetchDescriptor<SleepEpisodeRecord>())) ?? []
        return episodes.map {
            DataExporter.Archive.EpisodeRecord(
                id: $0.id, nightKey: $0.nightKey, startDate: $0.startDate, endDate: $0.endDate,
                timezoneIdentifier: $0.timezoneIdentifier, episodeType: $0.episodeTypeRaw,
                asleepMinutes: $0.asleepMinutes, timeInBedMinutes: $0.timeInBedMinutes,
                sourceName: $0.sourceName
            )
        }
    }

    /// Restores secondary episodes from a backup, upserting by `id` same as
    /// a live HealthKit sync does -- a restore onto a device that's kept
    /// recording since shouldn't discard or duplicate its own episodes.
    /// - Returns: how many rows were written.
    @discardableResult
    func importEpisodes(_ episodes: [DataExporter.Archive.EpisodeRecord]) -> Int {
        for episode in episodes {
            upsertEpisode(
                id: episode.id, nightKey: episode.nightKey,
                startDate: episode.startDate, endDate: episode.endDate,
                timezoneIdentifier: episode.timezoneIdentifier,
                episodeType: SleepEpisodeType(rawValue: episode.episodeType) ?? .unknown,
                asleepMinutes: episode.asleepMinutes, timeInBedMinutes: episode.timeInBedMinutes,
                sourceName: episode.sourceName
            )
        }
        return episodes.count
    }

    /// Wipes all stored nights. Exposed in Settings — a local-first app owes the
    /// user a one-tap way to destroy everything it holds.
    @discardableResult
    func deleteAll() -> Bool {
        do {
            try context.delete(model: SleepNightRecord.self)
            try context.delete(model: SleepEpisodeRecord.self)
            try context.save()
            AnchorStore.clear()
            return true
        } catch {
            logger.error("Delete-all failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Restores nights from a backup.
    ///
    /// Upserts rather than replaces, so restoring onto a device that has kept
    /// recording merges instead of discarding. Imported nights are marked as
    /// having no live wrist-temperature reading — the archive carries the delta,
    /// which is meaningless without the baseline it was computed against.
    /// - Returns: how many rows were written.
    @discardableResult
    func importNights(
        _ nights: [SleepNightFeatures],
        absoluteTemperatures: [Date: Double] = [:]
    ) -> Int {
        var written = 0
        for night in nights.sorted(by: { $0.date < $1.date }) {
            upsert(
                night,
                absoluteWristTempC: absoluteTemperatures[night.date]
            )
            written += 1
        }
        return written
    }

    func absoluteWristTemperaturesForExport() -> [(date: Date, absoluteCelsius: Double)] {
        allNights().compactMap { record in
            guard let value = record.wristTempAbsoluteC else { return nil }
            return (date: record.date, absoluteCelsius: value)
        }
    }

    /// True when every write since the last `beginTrackingWrites()` actually
    /// reached disk.
    ///
    /// Exists because `save()` deliberately swallows its error -- a failed
    /// write should never crash a health app mid-sync -- but `refresh()` must
    /// still know whether persistence succeeded before it advances the
    /// HealthKit anchor past a delta. Without this, a swallowed save failure
    /// looked identical to success at the call site, and the anchor moved on
    /// regardless. See `SleepDataCoordinator.refresh`.
    private(set) var writesSucceeded = true

    /// Resets the write-success flag at the start of a batch the caller
    /// intends to check afterwards.
    func beginTrackingWrites() {
        writesSucceeded = true
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            writesSucceeded = false
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Rolling context

    /// Computes comparative context for a night.
    ///
    /// - Parameters:
    ///   - date: the night being described. Excluded from its own baselines —
    ///     comparing a night to a window that contains it drags the baseline
    ///     toward the value being tested and mutes exactly the deviations we
    ///     want to catch.
    ///   - goalMinutes: the user's nightly sleep goal, for sleep debt.
    func baseline(for date: Date, goalMinutes: Double, manualNaps: [NapStore.Nap] = []) -> RollingBaseline {
        let history = allNights()
        let priorNights = history.filter { $0.date < date }

        return makeBaseline(
            priorNightsNewestFirst: priorNights,
            goalMinutes: goalMinutes,
            manualNaps: manualNaps
        )
    }

    private func makeBaseline(
        priorNightsNewestFirst priorNights: [SleepNightRecord],
        goalMinutes: Double,
        manualNaps: [NapStore.Nap] = []
    ) -> RollingBaseline {

        let last7 = Array(priorNights.prefix(7))
        // Wide enough that the decay in `sleepDebt` below has fully faded a
        // night's contribution before it would fall out of this window —
        // see that function's doc comment for why a hard cutoff is wrong.
        let debtWindow = Array(priorNights.prefix(60))

        // Wrist-temp baseline uses a longer window: the signal is small (tenths
        // of a degree) and needs more samples before a delta means anything.
        let tempWindow = Array(priorNights.prefix(21))

        return RollingBaseline(
            hrv7DayAvg: gatedMean(last7.compactMap(\.avgHRV)),
            sleepDebtMinutes: sleepDebt(nights: debtWindow, goalMinutes: goalMinutes, manualNaps: manualNaps),
            deep7DayAvg: mean(last7.filter { $0.deepMinutes > 0 }.map(\.deepMinutes)),
            duration7DayAvg: mean(last7.map(\.timeAsleepMinutes)),
            efficiency7DayAvg: mean(last7.map(\.sleepEfficiencyPercent)),
            minHeartRate7DayAvg: gatedMean(last7.compactMap(\.minHeartRate)),
            restingHeartRate7DayAvg: gatedMean(last7.compactMap(\.restingHeartRate)),
            wristTempBaselineC: gatedMean(tempWindow.compactMap(\.wristTempAbsoluteC), minimumSamples: 7),
            bedtimeConsistencyMinutes: bedtimeStandardDeviation(last7),
            sampleCount: last7.count
        )
    }

    /// Baseline for tonight, i.e. drawn from everything stored.
    ///
    /// `Calendar.current.date(byAdding: .day, value: 1, to: .now)`, not
    /// `.now.addingTimeInterval(86_400)` -- a fixed 24-hour offset is wrong
    /// on any day that crosses a DST transition (23 or 25 real hours), and
    /// "tomorrow" is a calendar concept, not a duration.
    func currentBaseline(goalMinutes: Double, manualNaps: [NapStore.Nap] = []) -> RollingBaseline {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now.addingTimeInterval(86_400)
        return baseline(for: tomorrow, goalMinutes: goalMinutes, manualNaps: manualNaps)
    }

    // MARK: - Statistics

    /// See `SleepDebtCalculator` for the model and why it decays rather than
    /// using a hard window cutoff. `nights` arrives newest-first, matching
    /// what that function expects.
    ///
    /// Each night's shortfall is measured against its full 24-hour asleep
    /// total -- main sleep plus any naps/secondary episodes tied to that
    /// night's key -- not main sleep alone. A short main-sleep night
    /// followed by a compensating nap previously still counted as the full
    /// shortfall every time debt was recomputed, because
    /// `secondaryEpisodeAsleepMinutes` was never consulted here.
    ///
    /// Each night is also judged against *its own* frozen
    /// `sleepNeedBaselineMinutesAtProcessing` when one exists, not against
    /// `goalMinutes` uniformly -- `goalMinutes` is only the fallback for
    /// nights stored before that column existed. See
    /// `SleepDebtCalculator.debtSeries(timeAsleepMinutesOldestFirst:goalMinutesOldestFirst:)`
    /// for why a single shared value can't be used once a night's target can
    /// be a learned figure rather than a stable one.
    private func sleepDebt(
        nights: [SleepNightRecord], goalMinutes: Double, manualNaps: [NapStore.Nap] = []
    ) -> Double? {
        SleepDebtCalculator.debt(
            timeAsleepMinutesNewestFirst: nights.map {
                $0.timeAsleepMinutes + secondaryEpisodeAsleepMinutes(
                    forNightKey: $0.nightKey ?? "", wakeDate: $0.date,
                    timeZone: $0.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current,
                    manualNaps: manualNaps
                )
            },
            goalMinutesNewestFirst: nights.map { $0.sleepNeedBaselineMinutesAtProcessing ?? goalMinutes }
        )
    }

    /// Standard deviation of bedtime-of-day, in minutes.
    ///
    /// Bedtimes are circular — 23:50 and 00:10 are twenty minutes apart, not
    /// twenty-three hours — so this uses circular statistics rather than naive
    /// clock-minute arithmetic. Getting this wrong makes every late-night sleeper
    /// look maximally inconsistent.
    private func bedtimeStandardDeviation(_ nights: [SleepNightRecord]) -> Double? {
        guard nights.count >= 3 else { return nil }

        // Each night's clock-time-of-day is read in *that night's own*
        // recorded timezone, not the device's current one -- a night's
        // bedtime should read as "11pm" every time it's revisited, even if
        // the device has since traveled, or bedtime consistency looks like
        // it swings every time the user crosses a timezone.
        let angles: [Double] = nights.map { night in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = night.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            let components = calendar.dateComponents([.hour, .minute], from: night.bedtime)
            let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            return minutes / (24 * 60) * 2 * .pi
        }

        let sinMean = angles.map(sin).reduce(0, +) / Double(angles.count)
        let cosMean = angles.map(cos).reduce(0, +) / Double(angles.count)
        let resultant = (sinMean * sinMean + cosMean * cosMean).squareRoot()

        // Circular standard deviation. R near 1 = tightly clustered bedtimes.
        guard resultant > 0, resultant <= 1 else { return nil }
        let circularSD = (-2 * log(resultant)).squareRoot()
        return circularSD / (2 * .pi) * 24 * 60
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Same as `mean(_:)`, but requires a minimum number of *actual
    /// measurements* rather than trusting the caller's window size.
    ///
    /// The bug this fixes: `wristTempBaselineC` used to gate on
    /// `tempWindow.count >= 7` -- the number of *nights* in a 21-night
    /// window -- then compute the mean over `tempWindow.compactMap(...)`,
    /// a completely different, potentially much smaller set. 21 nights in
    /// the window with only 1 of them carrying a temperature reading still
    /// satisfied `count >= 7` and produced a "baseline" from a single
    /// sample. `hrv7DayAvg`, `minHeartRate7DayAvg`, and
    /// `restingHeartRate7DayAvg` had the same shape of bug, just silent --
    /// no threshold at all, so even one HRV reading in 7 nights produced a
    /// confident-looking 7-day average. Each metric now owns its own
    /// eligibility, checked against its own compacted sample count.
    private func gatedMean(_ values: [Double], minimumSamples: Int = 3) -> Double? {
        guard values.count >= minimumSamples else { return nil }
        return mean(values)
    }
}
