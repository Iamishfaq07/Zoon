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
    /// Live daytime read, refreshed alongside everything else. `nil` until the
    /// first successful sample — a phone that's never queried HealthKit today
    /// has nothing honest to report yet.
    private(set) var todayStress: StressScore?
    /// Populated only when cycle tracking is on. Empty otherwise, including
    /// on every code path that never asks HealthKit for it.
    private(set) var cyclePeriodStarts: [Date] = []

    // MARK: - Dependencies

    private let healthKit: HealthKitManager
    private let store: SleepHistoryStore
    let journal: JournalStore
    private let naps: NapStore
    private let preferences: UserPreferences
    /// Pushes the snapshot to a paired Apple Watch. Owned here because this is
    /// the one place a finished snapshot exists.
    private let watchLink = WatchLink()
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
        watchLink.activate()
    }

    // MARK: - Lifecycle

    /// Requests the separate menstrual-flow authorization and, if granted,
    /// loads what's there. Call only from the Settings toggle — see
    /// `UserPreferences.cycleTrackingEnabled`.
    func enableCycleTracking() async {
        guard !LaunchOptions.isDemo, HealthKitManager.isHealthDataAvailable else {
            cyclePeriodStarts = AppMockData.cyclePeriodStarts
            return
        }
        do {
            try await healthKit.requestCycleTrackingAuthorization()
            await refreshCycleData()
        } catch {
            logger.error("Cycle tracking authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disableCycleTracking() {
        cyclePeriodStarts = []
    }

    private func refreshCycleData() async {
        let window = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -180, to: .now) ?? .now,
            end: .now
        )
        guard let samples = try? await healthKit.menstrualFlowSamples(in: window) else { return }
        cyclePeriodStarts = CycleContext.periodStarts(from: samples)
    }

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
        await refreshTodayStress()
        if preferences.cycleTrackingEnabled { await refreshCycleData() }
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

            // The anchored delta alone isn't enough to rebuild whole sessions —
            // a delta can land mid-night and we'd segment against a partial
            // picture. So when anything changed, re-read the full window and
            // rebuild from complete data. The anchor still earns its keep: when
            // nothing changed we skip all of this.
            let hasChanges = !result.samples.isEmpty || !result.deletedUUIDs.isEmpty
            var persisted = true
            if hasChanges || store.isEmpty {
                // Not gated on `!samples.isEmpty`: a window whose only sample
                // was deleted in Health legitimately refetches to nothing,
                // and `processSessions` still needs to run so it prunes the
                // now-stale stored night rather than leaving it behind.
                let samples = try await healthKit.fetchAllSleepSamples(in: window)
                persisted = await processSessions(from: samples, window: window)
            }

            // Anchor advances only after the delta it covers has actually been
            // processed and written. Saving it immediately after the fetch --
            // as this did previously -- meant a throw from
            // `fetchAllSleepSamples`, a failed SwiftData write, or the app
            // being killed mid-processing left the anchor pointing past data
            // Zoon never stored, and HealthKit would never report that change
            // again. Keeping the old anchor costs one redundant re-fetch on
            // the next refresh; advancing it early can silently lose a night.
            if persisted {
                AnchorStore.save(result.anchor)
            } else {
                logger.error("Persistence failed; keeping the previous HealthKit anchor so this delta is retried")
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
    /// - Returns: whether every write in this pass actually reached disk.
    ///   `refresh()` gates the HealthKit anchor advance on this.
    @discardableResult
    private func processSessions(from samples: [HKCategorySample], window: DateInterval) async -> Bool {
        store.beginTrackingWrites()
        let sessions = sessionBuilder.buildSessions(from: samples)

        // `SleepNightRecord` is one row per calendar day (see its own doc
        // comment), keyed by the date the session ended -- so two sessions
        // that both end on the same day, a main sleep and a same-day nap most
        // often, both want the same row. `SleepSessionBuilder` no longer
        // discards short sessions as aggressively as it used to (see its
        // `minimumSessionDuration` comment), which means a real nap now
        // survives to reach here far more often. Upserting in chronological
        // order would let whichever session merely happened to be *processed
        // last* silently overwrite the other -- typically the nap
        // clobbering the main sleep, since naps tend to fall later in the
        // day. Keeping only the longest session per date is a stopgap for
        // that, not the full multi-episode-per-day model (naps still aren't
        // recorded anywhere once discarded here); it just guarantees the
        // one thing that would otherwise be silently wrong: a full night's
        // sleep can never be replaced by a shorter same-day nap.
        let longestPerDate = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.end) }
            .compactMapValues { $0.max { $0.timeInBed < $1.timeInBed } }
            .values
            .sorted { $0.start < $1.start }

        let extractor = FeatureExtractor(healthKit: healthKit)
        let goal = preferences.sleepGoalMinutes

        // Oldest first: each night's baseline is drawn from the nights before
        // it, so they must land in the store in chronological order.
        for session in longestPerDate {
            let nightDate = Calendar.current.startOfDay(for: session.end)
            let baseline = store.baseline(for: nightDate, goalMinutes: goal)
            let result = await extractor.extract(from: session, baseline: baseline)
            store.upsert(result.features, absoluteWristTempC: result.absoluteWristTempC)
        }

        // `samples` here is always a full re-fetch of `window` (see call site),
        // never an incremental delta -- so any previously-stored night in
        // `window` that didn't produce a session this pass genuinely no
        // longer has HealthKit data behind it (deleted or corrected away in
        // the Health app), not just "wasn't included in today's delta".
        let validDates = Set(longestPerDate.map { Calendar.current.startOfDay(for: $0.end) })
        store.prune(window: window, keeping: validDates)

        return store.writesSucceeded
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
        // True RHR first (see SleepNightFeatures.restingHeartRate), falling
        // back to the sleep-window low only when no daily RHR sample exists
        // yet — heart-rate-reserve zones are sensitive to this baseline, so
        // the more accurate figure is worth preferring wherever it's there.
        let restingHR = history.compactMap(\.restingHeartRate).last
            ?? night.restingHeartRate
            ?? history.compactMap(\.minHeartRate).last
            ?? night.minHeartRate
            ?? 60

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

            // Same factory the live path uses, so history can't be scored
            // against a differently-built baseline than the Today screen —
            // which has happened here before.
            let baseline = RecoveryBaseline.from(nights: prior)
            let performance = min(100, night.timeAsleepMinutes / max(goal, 1) * 100)
            result[night.date] = RecoveryScore.compute(
                features: night, baseline: baseline, sleepPerformance: performance
            ).percent
        }

        recoveryHistory = result
    }

    private func publishSnapshot(_ context: DayContext, goal: Double) {
        var snapshot = SleepSnapshot(
            features: context.night,
            score: context.sleepScore,
            insight: context.insight,
            goalMinutes: goal,
            recoveryPercent: context.recovery.percent,
            bodyBattery: context.bodyBattery.current,
            strain: context.strain.value,
            sleepPerformance: context.sleepNeed.performancePercent
        )

        // Badges are evaluated here rather than in the extension: the engine
        // needs the whole night history and the journal, and the widget
        // deliberately reads nothing but this snapshot.
        let achievements = AchievementEngine.evaluate(
            nights: recentNights,
            goalMinutes: goal,
            journalTaggedNights: journal.taggedNightCount(),
            napCount: naps.naps.count,
            regularityIndex: context.regularity.index
        )
        snapshot.badgesUnlocked = achievements.filter(\.isUnlocked).count
        snapshot.badgesTotal = achievements.count
        if let headline = AchievementEngine.headline(achievements) {
            snapshot.badgeTitle = headline.title
            snapshot.badgeSymbol = headline.symbol
            snapshot.badgeTier = headline.tier.rawValue
        }
        if let next = AchievementEngine.nextUp(achievements) {
            snapshot.nextBadgeTitle = next.title
            snapshot.nextBadgeProgress = next.progress
        }

        SnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // Same payload to the wrist. Cheap to call every refresh: the framework
        // keeps only the latest context and drops an unchanged one rather than
        // waking the watch for nothing.
        watchLink.send(snapshot)
    }

    /// Averages heart rate and HRV from midnight to now, and compares against
    /// the same rolling baseline the overnight recovery score uses.
    ///
    /// Deliberately its own pass rather than folded into `refresh()`'s main
    /// pipeline: it has nothing to do with sessions or SwiftData, and running
    /// it independently means a HealthKit hiccup here can never block the
    /// night's real data from landing.
    private func refreshTodayStress() async {
        guard !LaunchOptions.isDemo, HealthKitManager.isHealthDataAvailable else {
            todayStress = AppMockData.stress
            return
        }

        let calendar = Calendar.current
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        guard dayStart < now else { return }
        let interval = DateInterval(start: dayStart, end: now)

        async let hrTask = try? healthKit.average(.heartRate, unit: .beatsPerMinute, in: interval)
        async let hrvTask = try? healthKit.average(
            .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: interval
        )
        let avgHR = await hrTask ?? nil
        let avgHRV = await hrvTask ?? nil

        let baseline = store.baseline(for: dayStart, goalMinutes: preferences.sleepGoalMinutes)

        todayStress = StressScore.compute(
            avgHeartRate: avgHR,
            avgHRV: avgHRV,
            hrBaseline: baseline.minHeartRate7DayAvg,
            hrvBaseline: baseline.hrv7DayAvg,
            sampledMinutes: now.timeIntervalSince(dayStart) / 60,
            baselineNightCount: baseline.sampleCount
        )
    }

    // MARK: - Mock path

    /// Populates every observable property from `MockData`.
    ///
    /// Deliberately runs the *real* builders over synthetic inputs, so a bug in
    /// a scoring formula still shows up on a laptop.
    func loadMockData() {
        let goal = preferences.sleepGoalMinutes
        // Stage segments are grafted on here, not stored in MockData.
        //
        // `MockData` lives in `Shared/` and carries no timeline — the widget has
        // no use for one. So without this the hypnogram, which is the single
        // most distinctive thing in the app, rendered as *nothing at all* on
        // every Simulator run and in every screenshot. The previews grafted
        // segments and looked right; the running app did not. That gap survived
        // because previews and the app used different paths to the same screen,
        // and only a screenshot of the real thing exposed it.
        var night = MockData.goodNight
        night.stageSegments = AppMockData.stageSegments(for: night)
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
        todayStress = AppMockData.stress
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
    ///
    /// Only nights with a `JournalEntry` row are included -- a night nobody
    /// opened the Journal for is genuinely unknown for every tag, not
    /// evidence any particular behaviour didn't happen, and treating it as a
    /// confirmed "no" biases whatever tag happens to be under test. A
    /// `JournalEntry` row exists as soon as the screen is opened for that
    /// date, before any tag is toggled (see `JournalStore.entryOrCreate`), so
    /// its presence -- not whether it happens to carry the tag in question --
    /// is the real "the user actually looked" signal. This does shrink the
    /// comparison pool versus treating every recorded night as a control,
    /// especially early on when few nights are logged at all, but a smaller
    /// honest pool is the right trade against a larger biased one.
    func journalObservations() -> [JournalCorrelator.Observation] {
        let entries = journal.allEntries()
        let tagsByDate = Dictionary(uniqueKeysWithValues: entries.map { ($0.date, Set($0.tags)) })
        let goal = preferences.sleepGoalMinutes
        let calendar = Calendar.current

        return recentNights.compactMap { night -> JournalCorrelator.Observation? in
            guard let tags = tagsByDate[night.date] else { return nil }
            let weekday = calendar.component(.weekday, from: night.date)
            return JournalCorrelator.Observation(
                date: night.date,
                tags: tags,
                recoveryPercent: recoveryHistory[night.date].map(Double.init),
                sleepPerformance: min(100, night.timeAsleepMinutes / max(goal, 1) * 100),
                deepMinutes: night.hasStageBreakdown ? night.deepMinutes : nil,
                remMinutes: night.hasStageBreakdown ? night.remMinutes : nil,
                efficiency: night.sleepEfficiencyPercent,
                wakeCount: Double(night.wakeCount),
                isWeekend: weekday == 1 || weekday == 7,
                sleepDebtMinutes: night.sleepDebtMinutes,
                bedtimeHour: DayContextBuilder.shiftedBedtimeHour(night.bedtime)
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
}
