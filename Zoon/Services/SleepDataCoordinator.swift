import Foundation
import HealthKit
import SwiftData
import WidgetKit
import os

/// The one object views observe.
///
/// Owns the pipeline end to end: HealthKit → sessions → features → SwiftData →
/// insight → widget snapshot. Views read `state` and call `refresh()`; they know
/// nothing about `HKQuery` or `ModelContext`.
@MainActor
@Observable
final class SleepDataCoordinator {

    // MARK: - State

    /// Explicit states, not `Optional<SleepNightFeatures>`.
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
        case loaded(SleepNightFeatures, SleepInsight)
        /// Simulator or no HealthKit — synthetic data, badged in the UI.
        case mock(SleepNightFeatures, SleepInsight)
        /// Queries ran fine, there was just nothing to find.
        case empty(reason: EmptyReason)
        case failed(String)

        var features: SleepNightFeatures? {
            switch self {
            case let .loaded(features, _), let .mock(features, _): features
            default: nil
            }
        }

        var insight: SleepInsight? {
            switch self {
            case let .loaded(_, insight), let .mock(_, insight): insight
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
    private(set) var recentNights: [SleepNightFeatures] = []
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    // MARK: - Dependencies

    private let healthKit: HealthKitManager
    private let store: SleepHistoryStore
    private let preferences: UserPreferences
    private let sessionBuilder = SleepSessionBuilder()
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "Coordinator")

    /// Swapped in Settings. `RuleBasedInsightEngine` is the only one that
    /// currently produces output; see `LocalLLMInsightEngine`.
    private var engine: any SleepInsightEngine

    /// How far back the initial backfill reaches. 30 nights is enough to make
    /// the 30-day charts meaningful on day one without a slow first launch.
    private let backfillDays = 30

    init(
        healthKit: HealthKitManager,
        store: SleepHistoryStore,
        preferences: UserPreferences
    ) {
        self.healthKit = healthKit
        self.store = store
        self.preferences = preferences
        self.engine = RuleBasedInsightEngine()
    }

    // MARK: - Lifecycle

    /// Called once on launch.
    func start() async {
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
            // A thrown error here is a real failure (Health unavailable, entitlement
            // missing) — user denial does NOT throw, it succeeds silently.
            logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }

        // Register the observer every launch: observer queries don't survive
        // process death, and background delivery relaunches us expecting one.
        healthKit.startObservingSleep { [weak self] in
            await self?.refresh()
        }

        await refresh()
    }

    /// Full pass: fetch, extract, persist, derive insight, publish to widget.
    func refresh() async {
        guard !isRefreshing else { return }
        guard HealthKitManager.isHealthDataAvailable else {
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

            // Anchored query for the incremental path. On first run the anchor is
            // nil and this returns the whole window; afterwards it returns only
            // what changed, which is what makes a background wake-up cheap.
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

            publishLatest()
            lastRefresh = .now
        } catch {
            logger.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            // Don't blow away good data on a transient query failure — an error
            // banner over yesterday's night beats an empty screen.
            if state.features == nil {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Processing

    /// Rebuilds every session in the window and upserts each one.
    ///
    /// Session building stays on the main actor even though it's pure
    /// computation: `HKCategorySample` is not `Sendable`, so handing the array to
    /// a detached task is a concurrency violation under strict checking. The
    /// work is a sort and a linear sweep over a few hundred samples — well under
    /// a frame, and it only runs when HealthKit reports a change.
    private func processSessions(from samples: [HKCategorySample]) async {
        let sessions = sessionBuilder.buildSessions(from: samples)
        guard !sessions.isEmpty else { return }

        let extractor = FeatureExtractor(healthKit: healthKit)
        let goal = preferences.sleepGoalMinutes

        // Oldest first: each night's baseline is drawn from the nights before it,
        // so they must land in the store in chronological order.
        for session in sessions {
            let nightDate = Calendar.current.startOfDay(for: session.end)
            let baseline = store.baseline(for: nightDate, goalMinutes: goal)
            let result = await extractor.extract(from: session, baseline: baseline)

            // The absolute wrist temperature is persisted unconditionally, even
            // on nights that produced no delta — it's what future baselines are
            // built from.
            store.upsert(result.features, absoluteWristTempC: result.absoluteWristTempC)
        }
    }

    /// Reads the newest stored night back out, derives an insight, updates state
    /// and hands a snapshot to the widget.
    private func publishLatest() {
        let goal = preferences.sleepGoalMinutes

        guard let record = store.latestNight else {
            state = .empty(reason: .noSleepData)
            recentNights = []
            return
        }

        let baseline = store.baseline(for: record.date, goalMinutes: goal)
        let features = record.features(baseline: baseline)
        let insight = engine.generate(for: features, baseline: baseline, goalMinutes: goal)

        store.attach(insight, to: record)

        state = .loaded(features, insight)
        recentNights = store.nights(inLast: 30).map { $0.features(baseline: baseline) }

        let score = SleepScore.compute(for: features, goalMinutes: goal)
        SnapshotStore.write(SleepSnapshot(features: features, score: score, insight: insight, goalMinutes: goal))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Mock path

    /// Populates every observable property from `MockData`.
    ///
    /// Used in the Simulator and in previews. Deliberately runs the *real*
    /// insight engine over the *real* score computation — only the input samples
    /// are synthetic, so a bug in the rules still shows up on a laptop.
    func loadMockData() {
        let goal = preferences.sleepGoalMinutes
        let features = MockData.goodNight
        let baseline = RollingBaseline(
            hrv7DayAvg: features.hrv7DayAvg,
            sleepDebtMinutes14Day: features.sleepDebtMinutes14Day,
            deep7DayAvg: 74,
            duration7DayAvg: 421,
            efficiency7DayAvg: 89,
            minHeartRate7DayAvg: 52,
            wristTempBaselineC: 35.1,
            bedtimeConsistencyMinutes: 38,
            sampleCount: 7
        )
        let insight = engine.generate(for: features, baseline: baseline, goalMinutes: goal)

        state = .mock(features, insight)
        recentNights = MockData.history
        lastRefresh = .now
    }

    // MARK: - Settings actions

    func setEngine(_ choice: UserPreferences.EngineChoice) {
        switch choice {
        case .ruleBased:
            engine = RuleBasedInsightEngine()
        case .localLLM:
            // Composed with the rule engine as fallback, so selecting the model
            // can never leave the user with a blank card — see the wrapper's docs.
            engine = LocalLLMInsightEngine(fallback: RuleBasedInsightEngine())
        }
        preferences.preferredEngine = choice
        publishLatestIfPossible()
    }

    /// Recomputes everything after a settings change that affects derived values
    /// (sleep goal in particular — it feeds score and sleep debt).
    func recomputeDerivedValues() {
        publishLatestIfPossible()
    }

    private func publishLatestIfPossible() {
        if state.isMock || !HealthKitManager.isHealthDataAvailable {
            loadMockData()
        } else {
            publishLatest()
        }
    }

    /// Deletes every stored night. Wired to Settings → Delete all data.
    func deleteAllData() {
        store.deleteAll()
        state = .empty(reason: .noSleepData)
        recentNights = []
        WidgetCenter.shared.reloadAllTimelines()
    }
}
