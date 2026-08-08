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

    // MARK: - Writes

    /// Inserts or updates the night, keyed on date.
    ///
    /// Upsert rather than insert because HealthKit revises nights: the watch
    /// syncs progressively through the morning, and the same night gets richer
    /// over a few hours. Blind inserts would produce duplicates that break the
    /// one-row-per-day assumption the rolling windows rely on.
    @discardableResult
    func upsert(_ features: SleepNightFeatures, absoluteWristTempC: Double? = nil) -> SleepNightRecord {
        if let existing = night(on: features.date) {
            existing.update(from: features, absoluteWristTempC: absoluteWristTempC)
            save()
            return existing
        }
        let record = SleepNightRecord(features: features, absoluteWristTempC: absoluteWristTempC)
        context.insert(record)
        save()
        return record
    }

    func attach(_ insight: SleepInsight, to record: SleepNightRecord) {
        record.apply(insight)
        save()
    }

    /// Wipes all stored nights. Exposed in Settings — a local-first app owes the
    /// user a one-tap way to destroy everything it holds.
    func deleteAll() {
        do {
            try context.delete(model: SleepNightRecord.self)
            try context.save()
            AnchorStore.clear()
        } catch {
            logger.error("Delete-all failed: \(error.localizedDescription, privacy: .public)")
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
    func importNights(_ nights: [SleepNightFeatures]) -> Int {
        var written = 0
        for night in nights.sorted(by: { $0.date < $1.date }) {
            upsert(night, absoluteWristTempC: nil)
            written += 1
        }
        return written
    }

    private func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
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

        let last7 = Array(priorNights.prefix(7))
        let last14 = Array(priorNights.prefix(14))

        // Wrist-temp baseline uses a longer window: the signal is small (tenths
        // of a degree) and needs more samples before a delta means anything.
        let tempWindow = Array(priorNights.prefix(21))

        return RollingBaseline(
            hrv7DayAvg: mean(last7.compactMap(\.avgHRV)),
            sleepDebtMinutes14Day: sleepDebt(nights: last14, goalMinutes: goalMinutes),
            deep7DayAvg: mean(last7.filter { $0.deepMinutes > 0 }.map(\.deepMinutes)),
            duration7DayAvg: mean(last7.map(\.timeAsleepMinutes)),
            efficiency7DayAvg: mean(last7.map(\.sleepEfficiencyPercent)),
            minHeartRate7DayAvg: mean(last7.compactMap(\.minHeartRate)),
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

    /// Cumulative shortfall against the goal, in minutes, floored at zero.
    ///
    /// Two deliberate choices:
    ///
    /// - **Surplus does not cancel debt.** Sleeping ten hours on Saturday does
    ///   not undo five short weeknights; the physiology doesn't work that way and
    ///   a metric that says otherwise encourages exactly the wrong behaviour. Only
    ///   nights *below* goal contribute.
    /// - **Missing nights are skipped, not counted as zero sleep.** A night you
    ///   didn't wear the watch isn't a night you didn't sleep, and treating it as
    ///   8 hours of debt would make the number useless after one forgotten charge.
    private func sleepDebt(nights: [SleepNightRecord], goalMinutes: Double) -> Double? {
        guard !nights.isEmpty else { return nil }
        let debt = nights.reduce(0.0) { total, night in
            total + max(0, goalMinutes - night.timeAsleepMinutes)
        }
        return debt
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
