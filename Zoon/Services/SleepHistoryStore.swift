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

    /// Every stored night, oldest first, rebuilt with the rolling context that
    /// existed immediately before that night.
    ///
    /// Comparative fields are intentionally not persisted, but that does not
    /// mean one current baseline can be stamped onto all of history. Sleep debt
    /// in particular is a date-derived value consumed by charts, achievements,
    /// and journal correlations. This bounded chronological pass fetches once
    /// and retains only the longest rolling window used by any baseline field.
    func historicalFeatures(goalMinutes: Double) -> [SleepNightFeatures] {
        let chronological = allNights().reversed()
        var priorNewestFirst: [SleepNightRecord] = []
        var features: [SleepNightFeatures] = []

        for record in chronological {
            let rolling = makeBaseline(
                priorNightsNewestFirst: priorNewestFirst,
                goalMinutes: goalMinutes
            )
            features.append(record.features(baseline: rolling))

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

    /// Wipes all stored nights. Exposed in Settings — a local-first app owes the
    /// user a one-tap way to destroy everything it holds.
    @discardableResult
    func deleteAll() -> Bool {
        do {
            try context.delete(model: SleepNightRecord.self)
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
    func baseline(for date: Date, goalMinutes: Double) -> RollingBaseline {
        let history = allNights()
        let priorNights = history.filter { $0.date < date }

        return makeBaseline(
            priorNightsNewestFirst: priorNights,
            goalMinutes: goalMinutes
        )
    }

    private func makeBaseline(
        priorNightsNewestFirst priorNights: [SleepNightRecord],
        goalMinutes: Double
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
            hrv7DayAvg: mean(last7.compactMap(\.avgHRV)),
            sleepDebtMinutes: sleepDebt(nights: debtWindow, goalMinutes: goalMinutes),
            deep7DayAvg: mean(last7.filter { $0.deepMinutes > 0 }.map(\.deepMinutes)),
            duration7DayAvg: mean(last7.map(\.timeAsleepMinutes)),
            efficiency7DayAvg: mean(last7.map(\.sleepEfficiencyPercent)),
            minHeartRate7DayAvg: mean(last7.compactMap(\.minHeartRate)),
            restingHeartRate7DayAvg: mean(last7.compactMap(\.restingHeartRate)),
            wristTempBaselineC: tempWindow.count >= 7 ? mean(tempWindow.compactMap(\.wristTempAbsoluteC)) : nil,
            bedtimeConsistencyMinutes: bedtimeStandardDeviation(last7),
            sampleCount: last7.count
        )
    }

    /// Baseline for tonight, i.e. drawn from everything stored.
    func currentBaseline(goalMinutes: Double) -> RollingBaseline {
        baseline(for: .now.addingTimeInterval(86_400), goalMinutes: goalMinutes)
    }

    // MARK: - Statistics

    /// See `SleepDebtCalculator` for the model and why it decays rather than
    /// using a hard window cutoff. `nights` arrives newest-first, matching
    /// what that function expects.
    private func sleepDebt(nights: [SleepNightRecord], goalMinutes: Double) -> Double? {
        SleepDebtCalculator.debt(
            timeAsleepMinutesNewestFirst: nights.map(\.timeAsleepMinutes),
            goalMinutes: goalMinutes
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
        let calendar = Calendar.current

        let angles: [Double] = nights.map { night in
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
}
