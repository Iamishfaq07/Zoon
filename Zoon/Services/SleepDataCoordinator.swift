import Foundation
import HealthKit
import SwiftData
import WidgetKit
import os

/// The one object views observe.
///
/// Owns the pipeline end to end: HealthKit → sessions → features → SwiftData →
/// derived metrics → widget snapshot. Views read `state` and call `refresh()`;
/// they know nothing about `HKQuery` or `ModelContext`.
@MainActor
@Observable
final class SleepDataCoordinator {

    // MARK: - State

    /// Explicit states, not `Optional<DayContext>`.
    ///
    /// A nil-Optional cannot distinguish "still loading" from "permission
    /// denied" from "you genuinely didn't wear your watch", and since HealthKit
    /// refuses to tell us about read denial (see `HealthKitManager`), collapsing
    /// them leaves the user staring at a spinner forever with no way to know
    /// what went wrong. Every one of these renders differently.
    enum State: Equatable {
        case idle
        case loading
        /// Real data.
        case loaded(DayContext)
        /// Simulator or no HealthKit — synthetic data, badged in the UI.
        case mock(DayContext)
        /// Queries ran fine, there was just nothing to find.
        case empty(reason: EmptyReason)
        case failed(String)

        var context: DayContext? {
            switch self {
            case let .loaded(context), let .mock(context): context
            default: nil
            }
        }

        var isMock: Bool {
            if case .mock = self { return true }
            return false
        }
    }

    enum EmptyReason: Equatable {
        case noHealthKit
        case noSleepData

        var title: String {
            switch self {
            case .noHealthKit: "Health data unavailable"
            case .noSleepData: "No sleep data yet"
            }
        }

        var message: String {
            switch self {
            case .noHealthKit:
                "Zoon needs the Health app, which isn't available on this device."
            case .noSleepData:
                """
                Zoon couldn't find any sleep in your Health data for the last few nights.

                Two things to check: wear your Apple Watch to bed with Sleep Focus on, \
                and make sure you allowed Zoon to read Sleep in Health → Sharing → Apps.
                """
            }
        }
    }

    private(set) var state: State = .idle
    /// Stored history, oldest first — what the charts read.
    private(set) var recentNights: [SleepNightFeatures] = []
    /// Recovery percent per night, for trends and the weekly report.
    private(set) var recoveryHistory: [Date: Int] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    // MARK: - Dependencies

    private let healthKit: HealthKitManager
    private let store: SleepHistoryStore
    let journal: JournalStore
    private let naps: NapStore
    private let preferences: UserPreferences
    private let sessionBuilder = SleepSessionBuilder()
    private let contextBuilder = DayContextBuilder()
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "Coordinator")

    private var engine: any SleepInsightEngine

    /// How far back the initial backfill reaches. 90 nights makes the HRV status
    /// baseline reachable on first launch rather than three months from now.
    private let backfillDays = 90

    init(
        healthKit: HealthKitManager,
        store: SleepHistoryStore,
        journal: JournalStore,
        naps: NapStore,
        preferences: UserPreferences
    ) {
        self.healthKit = healthKit
        self.store = store
        self.journal = journal
        self.naps = naps
        self.preferences = preferences
        self.engine = RuleBasedInsightEngine()
    }

    // MARK: - Lifecycle

    /// Presents the Health permission sheet, if there is one to present.
    ///
    /// Split out of `start()` so onboarding can trigger it at a moment the user
    /// has just been told what it's for. Returns once the sheet is dismissed —
    /// **not** once permission is granted, because HealthKit deliberately never
    /// reveals a read denial. An app that could tell would be able to infer
    /// that you have data worth hiding.
    func requestHealthAccess() async {
        guard !LaunchOptions.isDemo, HealthKitManager.isHealthDataAvailable else { return }
        do {
            try await healthKit.requestAuthorization()
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func start() async {
        // Screenshot/demo runs: no permission sheet, no queries, no waiting.
        // Checked before availability because the Simulator *does* have a
        // Health store, so the guard below wouldn't catch it.
        guard !LaunchOptions.isDemo else {
            logger.info("Demo launch argument — using mock data")
            loadMockData()
            return
        }

        // Simulator and any device without Health: go straight to mock data so
        // the whole UI is explorable. This is the difference between a project
        // you can develop on a laptop and one that requires a phone for every
        // pixel change.
        guard HealthKitManager.isHealthDataAvailable else {
            logger.info("HealthKit unavailable — using mock data")
            loadMockData()
            return
        }

        do {
            try await healthKit.requestAuthorization()
        } catch {
            // A thrown error here is a real failure (Health unavailable,
            // entitlement missing) — user denial does NOT throw.
            logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }

        healthKit.startObservingSleep { [weak self] in
            await self?.refresh()
        }

        await refresh()
    }

    /// Full pass: fetch, extract, persist, derive metrics, publish to widget.
    func refresh() async {
        guard !isRefreshing else { return }
        // Also guarded here: `refresh()` runs again on every foreground, and a
        // demo session that quietly swapped to live data on the second
        // activation would be worse than one that never started.
        guard !LaunchOptions.isDemo, HealthKitManager.isHealthDataAvailable else {
            loadMockData()
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        if case .idle = state { state = .loading }

        do {
            let window = DateInterval(
                start: Calendar.current.date(byAdding: .day, value: -backfillDays, to: .now) ?? .now,
                end: .now
            )

            let anchor = AnchorStore.load()
            let result = try await healthKit.fetchSleepSamples(since: anchor, window: window)
            AnchorStore.save(result.anchor)

            // The anchored delta alone isn't enough to rebuild whole sessions —
            // a delta can land mid-night and we'd segment against a partial
            // picture. So when anything changed, re-read the full window and
            // rebuild from complete data. The anchor still earns its keep: when
            // nothing changed we skip all of this.
            let hasChanges = !result.samples.isEmpty || !result.deletedUUIDs.isEmpty
            if hasChanges || store.isEmpty {
                let samples = try await healthKit.fetchAllSleepSamples(in: window)
                if !samples.isEmpty {
                    await processSessions(from: samples)
                }
            }

            await publishLatest()
            lastRefresh = .now
        } catch {
            logger.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            // Don't blow away good data on a transient query failure — an error
            // banner over yesterday's night beats an empty screen.
            if state.context == nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Processing

    /// Rebuilds every session in the window and upserts each one.
    ///
    /// Session building stays on the main actor even though it's pure
    /// computation: `HKCategorySample` is not `Sendable`, so handing the array
    /// to a detached task is a concurrency violation under strict checking.
    private func processSessions(from samples: [HKCategorySample]) async {
        let sessions = sessionBuilder.buildSessions(from: samples)
        guard !sessions.isEmpty else { return }

        let extractor = FeatureExtractor(healthKit: healthKit)
        let goal = preferences.sleepGoalMinutes

        // Oldest first: each night's baseline is drawn from the nights before
        // it, so they must land in the store in chronological order.
        for session in sessions {
            let nightDate = Calendar.current.startOfDay(for: session.end)
            let baseline = store.baseline(for: nightDate, goalMinutes: goal)
            let result = await extractor.extract(from: session, baseline: baseline)
            store.upsert(result.features, absoluteWristTempC: result.absoluteWristTempC)
        }
    }

    /// Reads the newest stored night back out, derives everything, updates state
    /// and hands a snapshot to the widget.
    private func publishLatest() async {
        let goal = preferences.sleepGoalMinutes

        guard let record = store.latestNight else {
            state = .empty(reason: .noSleepData)
            recentNights = []
            return
        }

        let baseline = store.baseline(for: record.date, goalMinutes: goal)
        let night = record.features(baseline: baseline)
        // Foundation Models inference is async and the engine protocol is not,
        // so generation is primed here and read back synchronously below.
        if let modelEngine = engine as? FoundationModelInsightEngine {
            await modelEngine.prepare(for: night, baseline: baseline, goalMinutes: goal)
        }

        let insight = engine.generate(for: night, baseline: baseline, goalMinutes: goal)
        store.attach(insight, to: record)

        // History for trends and for every rolling baseline, oldest first,
        // excluding tonight.
        let history = store.allNights()
            .map { $0.features(baseline: baseline) }
            .filter { $0.date < night.date }
            .sorted { $0.date < $1.date }

        let maxHR = DayContextBuilder.estimatedMaxHeartRate(age: preferences.age)
        let restingHR = history.compactMap(\.minHeartRate).last ?? night.minHeartRate ?? 60

        let (todayStrain, yesterdayStrain, hourly) = await loadActivity(
            wakeTime: night.wakeTime, restingHR: restingHR, maxHR: maxHR
        )

        let context = contextBuilder.build(.init(
            night: night,
            insight: insight,
            history: history,
            goalMinutes: goal,
            yesterdayStrain: yesterdayStrain,
            todayStrain: todayStrain,
            hourlyHeartRate: hourly,
            maxHeartRate: maxHR,
            napMinutes: naps.minutesBefore(night: night.date),
            bedtimeConsistencyMinutes: baseline.bedtimeConsistencyMinutes,
            age: preferences.age
        ))

        state = .loaded(context)
        recentNights = history + [night]
        rebuildRecoveryHistory(goal: goal)
        publishSnapshot(context, goal: goal)
    }

    /// Today's and yesterday's strain plus today's hourly heart rate.
    ///
    /// Failures degrade to zero rather than propagating: a missing activity
    /// query should cost you the strain ring, not the entire screen.
    private func loadActivity(
        wakeTime: Date,
        restingHR: Double,
        maxHR: Double
    ) async -> (today: StrainScore, yesterday: StrainScore, hourly: [(date: Date, bpm: Double)]) {

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        async let todayTask = strain(
            in: DateInterval(start: todayStart, end: .now), restingHR: restingHR, maxHR: maxHR
        )
        async let yesterdayTask = strain(
            in: DateInterval(start: yesterdayStart, end: todayStart), restingHR: restingHR, maxHR: maxHR
        )

        let today = await todayTask
        let yesterday = await yesterdayTask

        let hourly = (try? await healthKit.hourlyHeartRate(
            in: DateInterval(start: min(wakeTime, .now), end: .now)
        )) ?? []

        return (today, yesterday, hourly)
    }

    private func strain(in interval: DateInterval, restingHR: Double, maxHR: Double) async -> StrainScore {
        guard interval.duration > 0 else { return .zero }

        let energy = (try? await healthKit.sum(.activeEnergyBurned, unit: .kilocalorie(), in: interval)) ?? nil
        let exercise = (try? await healthKit.sum(.appleExerciseTime, unit: .minute(), in: interval)) ?? nil

        guard let result = try? await healthKit.heartRateZones(
            in: interval, restingHeartRate: restingHR, maxHeartRate: maxHR
        ), !result.zones.isEmpty, result.coverage >= 0.4 else {
            // Thin heart-rate coverage — fall back to the energy estimate and
            // let the UI say so rather than presenting a confident wrong number.
            return .estimate(activeEnergyKcal: energy ?? 0, exerciseMinutes: exercise ?? 0)
        }

        return .compute(
            zoneMinutes: result.zones,
            activeEnergyKcal: energy,
            hasHeartRateCoverage: true
        )
    }

    /// Recomputes recovery for every stored night, for trends and the report.
    ///
    /// Each night is scored against the 30 nights *before it*, not against
    /// today's baseline — otherwise a night from six weeks ago would be judged
    /// by a body that didn't exist yet.
    private func rebuildRecoveryHistory(goal: Double) {
        var result: [Date: Int] = [:]
        let nights = recentNights

        for (index, night) in nights.enumerated() {
            let prior = Array(nights[..<index].suffix(DayContextBuilder.recoveryBaselineWindow))
            guard prior.count >= RecoveryScore.minimumBaselineNights else { continue }

            let baseline = RecoveryBaseline(
                hrv: mean(prior.compactMap(\.avgHRV)),
                restingHeartRate: mean(prior.compactMap(\.minHeartRate)),
                respiratoryRate: mean(prior.compactMap(\.avgRespiratoryRate)),
                wristTemperature: mean(prior.compactMap(\.wristTempDeltaC)),
                nightCount: prior.count
            )
            let performance = min(100, night.timeAsleepMinutes / max(goal, 1) * 100)
            result[night.date] = RecoveryScore.compute(
                features: night, baseline: baseline, sleepPerformance: performance
            ).percent
        }

        recoveryHistory = result
    }

    private func publishSnapshot(_ context: DayContext, goal: Double) {
        SnapshotStore.write(SleepSnapshot(
            features: context.night,
            score: context.sleepScore,
            insight: context.insight,
            goalMinutes: goal,
            recoveryPercent: context.recovery.percent,
            bodyBattery: context.bodyBattery.current,
            strain: context.strain.value,
            sleepPerformance: context.sleepNeed.performancePercent
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Mock path

    /// Populates every observable property from `MockData`.
    ///
    /// Deliberately runs the *real* builders over synthetic inputs, so a bug in
    /// a scoring formula still shows up on a laptop.
    func loadMockData() {
        let goal = preferences.sleepGoalMinutes
        let night = MockData.goodNight
        let history = MockData.history.filter { $0.date < night.date }

        let context = contextBuilder.build(.init(
            night: night,
            insight: engine.generate(for: night, baseline: AppMockData.baseline, goalMinutes: goal),
            history: history,
            goalMinutes: goal,
            yesterdayStrain: MockData.yesterdayStrain,
            todayStrain: MockData.todayStrain,
            hourlyHeartRate: MockData.hourlyHeartRate(wakeTime: night.wakeTime),
            maxHeartRate: 185,
            napMinutes: 0,
            bedtimeConsistencyMinutes: 38,
            age: preferences.age ?? 34
        ))

        state = .mock(context)
        recentNights = MockData.history
        rebuildRecoveryHistory(goal: goal)
        lastRefresh = .now
    }

    // MARK: - Actions

    func setEngine(_ choice: UserPreferences.EngineChoice) {
        switch choice {
        case .ruleBased:
            engine = RuleBasedInsightEngine()
        case .appleIntelligence:
            engine = FoundationModelInsightEngine(fallback: RuleBasedInsightEngine())
        case .localLLM:
            engine = LocalLLMInsightEngine(fallback: RuleBasedInsightEngine())
        }
        preferences.preferredEngine = choice
        Task { await recomputeDerivedValues() }
    }

    /// Recomputes everything after a settings change that affects derived
    /// values (the sleep goal feeds score, sleep need, and debt).
    func recomputeDerivedValues() async {
        if state.isMock || !HealthKitManager.isHealthDataAvailable {
            loadMockData()
        } else {
            await publishLatest()
        }
    }

    /// Restores a backup into the live stores, then rebuilds everything.
    ///
    /// - Returns: a human-readable summary of what landed.
    func importArchive(_ archive: DataExporter.Archive) async -> String {
        let nights = store.importNights(archive.nights)
        let entries = journal.importEntries(
            archive.journal.map { (date: $0.date, tags: $0.tags, note: $0.note) }
        )
        let restoredNaps = naps.importNaps(archive.naps)

        // The archive carries the goal the data was recorded against. Adopting
        // it matters: sleep debt, need and recovery are all measured against
        // the goal, so importing nights while keeping a different target would
        // silently rescore the entire history.
        if archive.goalMinutes > 0 {
            preferences.sleepGoalMinutes = archive.goalMinutes
        }

        // Anchored sync must start over — the store now contains nights
        // HealthKit never told us about, and the old anchor would skip them.
        AnchorStore.clear()
        await recomputeDerivedValues()

        return "Restored \(nights) nights, \(entries) journal entries and \(restoredNaps) naps."
    }

    func deleteAllData() {
        store.deleteAll()
        journal.deleteAll()
        state = .empty(reason: .noSleepData)
        recentNights = []
        recoveryHistory = [:]
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Derived views of history

    /// Journal observations joined to outcomes, for the correlation engine.
    func journalObservations() -> [JournalCorrelator.Observation] {
        let entries = journal.allEntries()
        let tagsByDate = Dictionary(uniqueKeysWithValues: entries.map { ($0.date, Set($0.tags)) })
        let goal = preferences.sleepGoalMinutes

        return recentNights.compactMap { night in
            guard let tags = tagsByDate[night.date], !tags.isEmpty else { return nil }
            return JournalCorrelator.Observation(
                date: night.date,
                tags: tags,
                recoveryPercent: recoveryHistory[night.date].map(Double.init),
                sleepPerformance: min(100, night.timeAsleepMinutes / max(goal, 1) * 100),
                deepMinutes: night.hasStageBreakdown ? night.deepMinutes : nil,
                remMinutes: night.hasStageBreakdown ? night.remMinutes : nil,
                efficiency: night.sleepEfficiencyPercent,
                wakeCount: Double(night.wakeCount)
            )
        }
    }

    /// This week vs last week.
    func weeklyReport() -> WeeklyReport? {
        guard recentNights.count >= 3 else { return nil }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let previousCutoff = calendar.date(byAdding: .day, value: -14, to: .now) ?? .now

        let thisWeek = recentNights.filter { $0.date >= cutoff }
        let lastWeek = recentNights.filter { $0.date >= previousCutoff && $0.date < cutoff }
        guard !thisWeek.isEmpty else { return nil }

        return WeeklyReport.build(
            nights: thisWeek,
            recoveries: recoveryHistory,
            previousNights: lastWeek,
            previousRecoveries: recoveryHistory,
            goalMinutes: preferences.sleepGoalMinutes,
            consistencyMinutes: state.context?.chronotype.consistencyMinutes
        )
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
