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
    /// `.idle` -- nothing running. `.refreshing` -- one pass in flight.
    /// `.refreshingWithPending` -- a pass is in flight *and* something else
    /// asked for another one while it ran. That third state is the fix: the
    /// old code was a plain `guard !isRefreshing else { return }`, which
    /// silently dropped an overlapping call entirely rather than queuing it.
    /// A foreground activation landing mid-refresh could ask for fresher
    /// data than the in-flight pass was already fetching (new HealthKit
    /// samples, a changed goal) and never get it until the *next*
    /// independent trigger happened to come along.
    private enum RefreshState { case idle, refreshing, refreshingWithPending }
    private var refreshState: RefreshState = .idle
    var isRefreshing: Bool { refreshState != .idle }
    /// Live daytime read, refreshed alongside everything else. `nil` until the
    /// first successful sample — a phone that's never queried HealthKit today
    /// has nothing honest to report yet.
    private(set) var todayStress: StressScore?
    /// Today's logged workouts, oldest first -- refreshed alongside
    /// `todayStress` since both come from the same `workouts(in:)` query.
    /// Purely a display list; see `WorkoutSummary`'s doc comment for why
    /// this doesn't feed `StrainScore` itself.
    private(set) var todayWorkouts: [WorkoutSummary] = []
    /// Populated only when cycle tracking is on. Empty otherwise, including
    /// on every code path that never asks HealthKit for it.
    private(set) var cyclePeriodStarts: [Date] = []
    /// Populated only when Lifestyle Insights is on. `nil` otherwise,
    /// including on every code path that never asks HealthKit for it.
    private(set) var todayLifestyleInsights: LifestyleInsights?

    // MARK: - Dependencies

    private let healthKit: HealthKitManager
    private let store: SleepHistoryStore
    let journal: JournalStore
    /// Durable per-behaviour answers. Injected alongside `journal` because
    /// both are SwiftData stores over the same context, and the Journal
    /// screen writes to this one directly.
    let behaviors: BehaviorObservationStore
    /// History of completed Guided Experiments. Default-constructed rather
    /// than injected -- unlike `journal`/`naps` it has no HealthKit
    /// dependency and no test needs a distinct instance, so the extra
    /// wiring at both `SleepDataCoordinator` call sites would buy nothing.
    let experiments = SleepExperimentStore()
    private let naps: NapStore
    private let preferences: UserPreferences
    private let reminders: BedtimeReminder
    /// Pushes the snapshot to a paired Apple Watch. Owned here because this is
    /// the one place a finished snapshot exists.
    private let watchLink = WatchLink()
    private var sessionBuilder = SleepSessionBuilder()
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
        behaviors: BehaviorObservationStore,
        naps: NapStore,
        preferences: UserPreferences,
        reminders: BedtimeReminder
    ) {
        self.healthKit = healthKit
        self.store = store
        self.journal = journal
        self.behaviors = behaviors
        self.naps = naps
        self.preferences = preferences
        self.reminders = reminders
        // The picker persists independently of this coordinator. Restore the
        // selected implementation here so the displayed preference and the
        // engine doing the work cannot diverge after a relaunch.
        self.engine = Self.makeEngine(for: preferences.preferredEngine)
        // One-time forward-fill of legacy positive tags into the
        // observation store. Guarded by its own UserDefaults flag, which
        // it checks before touching the store, so every launch after the
        // first costs a single Bool read. Runs here rather than lazily on
        // a read path because `journalObservations()` is called from
        // several SwiftUI view bodies, and a write triggered from inside
        // a body evaluation is how you get a mutation-during-render loop.
        behaviors.migrateLegacyTags(from: journal.allEntries())
        watchLink.activate()
        watchLink.onQuickAction = { [journal, naps] action in
            Self.apply(action, journal: journal, naps: naps)
        }
    }

    /// Applies a quick action logged from the watch. `static` and passed its
    /// dependencies explicitly rather than a `self` method: the closure set
    /// on `watchLink.onQuickAction` above is held by `WatchLink` for the
    /// coordinator's whole lifetime, and capturing `self` there would be a
    /// retain cycle (`watchLink` is itself a property of this coordinator).
    private static func apply(_ action: WatchQuickAction, journal: JournalStore, naps: NapStore) {
        switch action {
        case .behaviorTag(let rawValue):
            guard let tag = BehaviorTag(rawValue: rawValue) else { return }
            journal.toggle(tag, on: .now)
        case .morningFeeling(let rawValue):
            guard let feeling = MorningFeeling(rawValue: rawValue) else { return }
            journal.setFeeling(feeling, on: .now)
        case .nap(let minutes):
            guard minutes > 0 else { return }
            let end = Date.now
            naps.importNaps([NapStore.Nap(start: end.addingTimeInterval(-Double(minutes) * 60), end: end)])
        }
    }

    // MARK: - Lifecycle

    /// Requests the separate menstrual-flow authorization and, if granted,
    /// loads what's there. Call only from the Settings toggle — see
    /// `UserPreferences.cycleTrackingEnabled`.
    func enableCycleTracking() async {
        guard DataEnvironment.current.isLive else {
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

    /// Requests the separate Lifestyle Insights authorization and, if
    /// granted, loads today's values. Call only from the Settings toggle —
    /// see `UserPreferences.lifestyleInsightsEnabled`.
    func enableLifestyleInsights() async {
        guard DataEnvironment.current.isLive else {
            todayLifestyleInsights = LifestyleInsights(
                caffeineMg: 140, alcoholicBeverages: nil, daylightMinutes: 38, mindfulMinutes: 10
            )
            return
        }
        do {
            try await healthKit.requestLifestyleInsightsAuthorization()
            await refreshLifestyleInsights()
        } catch {
            logger.error("Lifestyle Insights authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disableLifestyleInsights() {
        todayLifestyleInsights = nil
    }

    private func refreshLifestyleInsights() async {
        let today = DateInterval(start: Calendar.current.startOfDay(for: .now), end: .now)
        todayLifestyleInsights = await healthKit.lifestyleInsights(for: today)
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
    ///
    /// Time-boxed at 20 seconds. `OnboardingView` awaits this and only then
    /// advances past its "Connect Health" page -- a real TestFlight report
    /// found that page permanently stuck showing only the Sleep sheet, with
    /// no way forward short of granting access from Settings and relaunching.
    /// `HealthKitManager.requestAuthorization()`'s own fix addresses the
    /// most likely cause (a sheet-presentation race between its two system
    /// prompts), but HealthKit's completion handler is outside this app's
    /// control and has no OS-level timeout guarantee of its own -- this is
    /// the backstop that makes onboarding unable to hang forever regardless
    /// of why a given device's HealthKit call never completes. 20 seconds is
    /// well past how long even both system sheets, answered promptly, should
    /// ever take.
    func requestHealthAccess() async {
        guard DataEnvironment.current.isLive else { return }
        do {
            try await Self.withTimeout(seconds: 20) { [healthKit] in
                try await healthKit.requestAuthorization()
            }
        } catch is TimeoutError {
            logger.error("Authorization request timed out after 20s; proceeding without waiting further")
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct TimeoutError: Error {}

    /// Races `operation` against a deadline. If the deadline wins, `operation`
    /// is left to finish on its own (its `Task` is cancelled, but a
    /// completion-handler-backed call like HealthKit's can't actually be
    /// interrupted mid-flight) and this throws `TimeoutError` so the caller
    /// can stop waiting rather than hang indefinitely.
    private static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw TimeoutError()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw TimeoutError() }
            return result
        }
    }

    /// Starts the pipeline: observers plus an initial refresh. Does **not**
    /// request HealthKit authorization — that is `requestHealthAccess()`'s
    /// job alone, called from onboarding at the moment the user has just
    /// been told what it's for.
    ///
    /// This used to also call `healthKit.requestAuthorization()` directly,
    /// which was a silent duplicate of onboarding's call: `RootView` (the
    /// only caller of `start()`) is shown only once `hasCompletedOnboarding`
    /// is true, so by the time this runs, onboarding's `requestHealthAccess()`
    /// has always already run first. The duplicate was harmless *today*
    /// only because HealthKit doesn't reprompt for a type it has already
    /// answered — but that protection silently disappears the moment the
    /// requested type set ever gains a new type: every returning user's very next
    /// cold launch would then trigger a brand-new system permission sheet,
    /// unexplained, on `start()`, with no onboarding context and no Settings
    /// visit involved. Removing the call here closes that gap without
    /// changing anything about the request onboarding already makes.
    func start() async {
        // Screenshot/demo runs take no permission sheet, run no queries, and
        // wait for nothing; the Simulator and any device without Health go
        // straight to mock data so the whole UI stays explorable, which is the
        // difference between a project you can develop on a laptop and one
        // that needs a phone for every pixel change. `DataEnvironment` decides
        // which of those applies (and in which order — see its note).
        let environment = DataEnvironment.current
        if environment.isSample {
            if let message = environment.fallbackLogMessage {
                logger.info("\(message, privacy: .public)")
            }
            loadMockData()
            return
        }

        healthKit.startObservingSleep { [weak self] in
            await self?.refresh()
        }

        await refresh()
    }

    /// Full pass: fetch, extract, persist, derive metrics, publish to widget.
    ///
    /// The state check is the very first thing that runs, ahead of even
    /// `refreshTodayStress`/`refreshCycleData`. It used to sit after them,
    /// which meant every overlapping call -- a foreground activation
    /// landing while an observer-triggered refresh was still mid-flight,
    /// say -- redundantly re-ran both before finding out a full refresh was
    /// already in progress and bailing. `@MainActor` isolation already
    /// makes checking and setting `refreshState` here race-free.
    ///
    /// A call that lands while another is already running doesn't bail
    /// outright the way the old `guard !isRefreshing` did -- it marks
    /// `.refreshingWithPending` and returns immediately (never blocking the
    /// caller), and the in-flight pass runs itself again once before going
    /// idle. That second pass picks up whatever the second caller wanted
    /// fresher (new HealthKit samples an observer just reported, a goal
    /// change) instead of that request being silently dropped until some
    /// unrelated later trigger happened to come along.
    func refresh() async {
        switch refreshState {
        case .idle:
            refreshState = .refreshing
        case .refreshing:
            refreshState = .refreshingWithPending
            return
        case .refreshingWithPending:
            return
        }

        await performRefresh()
        while refreshState == .refreshingWithPending {
            refreshState = .refreshing
            await performRefresh()
        }
        refreshState = .idle
    }

    private func performRefresh() async {
        await refreshTodayStress()
        if preferences.cycleTrackingEnabled { await refreshCycleData() }
        if preferences.lifestyleInsightsEnabled { await refreshLifestyleInsights() }

        // Also guarded here: `refresh()` runs again on every foreground, and a
        // demo session that quietly swapped to live data on the second
        // activation would be worse than one that never started.
        guard DataEnvironment.current.isLive else {
            loadMockData()
            return
        }

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
        sessionBuilder.preferredSourceBundleIdentifier = preferences.preferredSleepSourceBundleIdentifier
        sessionBuilder.preferredSourceName = preferences.preferredSleepSourceName
        let sessions = sessionBuilder.buildSessions(from: samples)

        // `SleepNightRecord` is one row per wake date, so a main sleep and a
        // same-day nap compete for that row: `preferredMainSleep` picks the
        // one that becomes the night's row (actual asleep duration and stage
        // quality, not raw first-to-last sample span, so a long in-bed-only
        // schedule never beats a real Watch night). Everything else in the
        // group used to be discarded entirely -- `persistSecondaryEpisodes`
        // below is what keeps a same-day nap alive instead of losing it here.
        let groupedByWakeDate = Dictionary(grouping: sessions) { $0.wakeDate }
        let mainSleepPerDate = groupedByWakeDate
            .compactMapValues { SleepSessionBuilder.preferredMainSleep(in: $0) }
            .values
            .sorted { $0.start < $1.start }

        let extractor = FeatureExtractor(healthKit: healthKit)
        let goal = preferences.sleepGoalMinutes

        // Sleep-need baseline as of just before this batch, kept updated as
        // this pass's own earlier nights land -- see the loop below. Nights
        // this batch is about to reprocess are excluded up front so a
        // same-night re-sync can't appear twice in "nights before" for a
        // later night in the same pass.
        let batchDates = Set(mainSleepPerDate.map(\.wakeDate))
        let priorFeaturesBeforeBatch = store.allNights()
            .filter { !batchDates.contains($0.date) }
            .sorted { $0.date < $1.date }
            .map { $0.features() }
        var thisBatchFeaturesOldestFirst: [SleepNightFeatures] = []

        // Oldest first: each night's baseline is drawn from the nights before
        // it, so they must land in the store in chronological order. This
        // also matters for sleepNeedBaselineMinutes below, which needs the
        // same chronological guarantee.
        for session in mainSleepPerDate {
            let nightDate = session.wakeDate
            let baseline = store.baseline(for: nightDate, goalMinutes: goal, manualNaps: naps.naps)
            let result = await extractor.extract(from: session, baseline: baseline)
            var features = result.features

            // Frozen at first insert only (see SleepNightRecord.update's doc
            // comment) -- computed here regardless, since store.upsert below
            // simply ignores it on the re-sync path.
            let priorBeforeThisNight = priorFeaturesBeforeBatch.filter { $0.date < nightDate } + thisBatchFeaturesOldestFirst
            features.sleepNeedBaselineMinutes = LearnedSleepNeed.compute(
                goalMinutes: goal,
                history: priorBeforeThisNight
            ).minutes

            store.upsert(
                features,
                absoluteWristTempC: result.absoluteWristTempC,
                confirmedAbsent: result.confirmedAbsent,
                nightKey: session.nightKey
            )
            thisBatchFeaturesOldestFirst.append(features)
        }

        let validEpisodeIDs = persistSecondaryEpisodes(groupedByWakeDate: groupedByWakeDate, mainSleepPerDate: mainSleepPerDate)

        // `samples` here is always a full re-fetch of `window` (see call site),
        // never an incremental delta -- so any previously-stored night in
        // `window` that didn't produce a session this pass genuinely no
        // longer has HealthKit data behind it (deleted or corrected away in
        // the Health app), not just "wasn't included in today's delta".
        let validDates = Set(mainSleepPerDate.map(\.wakeDate))
        store.prune(window: window, keeping: validDates)
        store.pruneEpisodes(window: window, keeping: validEpisodeIDs)

        return store.writesSucceeded
    }

    /// Persists every session in a wake-date group that wasn't the one chosen
    /// as main sleep -- a nap, a second sleep block, a split-sleep session --
    /// as a `SleepEpisodeRecord` instead of discarding it.
    ///
    /// Classification is a first pass: clock-time only (a session mostly
    /// inside a broad daytime window reads as a nap, everything else as
    /// secondary sleep), not the fuller duration/schedule/shift-work-aware
    /// model a mature version would use. Deliberately conservative rather
    /// than confidently wrong.
    ///
    /// - Returns: the `id` of every episode this pass wrote, so the caller
    ///   can prune any previously-stored episode that this full re-fetch did
    ///   not reconfirm -- see `SleepHistoryStore.pruneEpisodes`.
    @discardableResult
    private func persistSecondaryEpisodes(
        groupedByWakeDate: [Date: [SleepSession]],
        mainSleepPerDate: [SleepSession]
    ) -> Set<String> {
        // Below this, a session is more likely a HealthKit fragment (a brief
        // "in bed" flicker, a watch mis-detection) than a real nap worth
        // surfacing -- the same reasoning `SleepSessionBuilder`'s minimum
        // session duration already applies to main sleep candidates.
        let minimumMeaningfulMinutes = 10.0

        let mainByWakeDate = Dictionary(uniqueKeysWithValues: mainSleepPerDate.map { ($0.wakeDate, $0) })
        var writtenIDs: Set<String> = []

        for (wakeDate, group) in groupedByWakeDate {
            guard let main = mainByWakeDate[wakeDate] else { continue }
            let secondary = group.filter { $0.start != main.start || $0.end != main.end }

            for session in secondary where session.totalAsleepMinutes >= minimumMeaningfulMinutes {
                let id = "\(main.nightKey)@\(Int(session.start.timeIntervalSince1970))"
                store.upsertEpisode(
                    id: id,
                    nightKey: main.nightKey,
                    startDate: session.start,
                    endDate: session.end,
                    timezoneIdentifier: session.timeZoneIdentifier,
                    episodeType: classify(session),
                    asleepMinutes: session.totalAsleepMinutes,
                    timeInBedMinutes: session.timeInBed / 60,
                    sourceName: session.sourceName
                )
                writtenIDs.insert(id)
            }
        }
        return writtenIDs
    }

    /// A session whose midpoint falls in a broad daytime window (9am-6pm, in
    /// its own recorded timezone) reads as a nap; anything else -- an early
    /// morning or late-evening block -- reads as secondary sleep rather than
    /// guessing which one is "primary" from duration alone.
    ///
    /// That 9am-6pm window assumes the main sleep happens at night, which
    /// inverts for a night-shift worker: their long block is the daytime
    /// one, and a break during their overnight work hours is the nap. With
    /// `UserPreferences.isShiftWorkModeEnabled` on, the two windows swap --
    /// 6pm-9am reads as nap instead. (`preferredMainSleep(in:)` itself
    /// already picks the main block by duration, not clock time, so it
    /// needs no change here; this only affects how the *other* sessions on
    /// the same day get labeled.)
    private func classify(_ session: SleepSession) -> SleepEpisodeType {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.timeZoneIdentifier) ?? .current
        let midpoint = session.start.addingTimeInterval(session.end.timeIntervalSince(session.start) / 2)
        let hour = calendar.component(.hour, from: midpoint)
        let isDaytime = (9..<18).contains(hour)
        let isNap = preferences.isShiftWorkModeEnabled ? !isDaytime : isDaytime
        return isNap ? .nap : .secondarySleep
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

        let baseline = store.baseline(for: record.date, goalMinutes: goal, manualNaps: naps.naps)
        let night = record.features(
            baseline: baseline,
            secondaryAsleepMinutes: store.secondaryEpisodeAsleepMinutes(
                forNightKey: record.nightKey ?? "", wakeDate: record.date,
                timeZone: record.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current,
                manualNaps: naps.naps
            )
        )
        // Foundation Models inference is async and the engine protocol is not,
        // so generation is primed here and read back synchronously below.
        if let modelEngine = engine as? FoundationModelInsightEngine {
            await modelEngine.prepare(for: night, baseline: baseline, goalMinutes: goal)
        }

        let insight = engine.generate(for: night, baseline: baseline, goalMinutes: goal)
        store.attach(insight, to: record)

        // Rebuild each stored night against the context that existed before
        // that specific night. Reusing the latest baseline for the whole array
        // makes historical debt flat and can corrupt correlations and
        // achievements that consume `recentNights`.
        let history = store.historicalFeatures(goalMinutes: goal, manualNaps: naps.naps)
            .filter { $0.date < night.date }

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
            napMinutes: deduplicatedNapMinutes(before: night.date, timeZone: night.timeZone),
            bedtimeConsistencyMinutes: baseline.bedtimeConsistencyMinutes,
            age: preferences.age,
            obligationWeekdays: preferences.obligationWeekdays
        ))

        state = .loaded(context)
        recentNights = history + [night]
        rebuildRecoveryHistory(goal: goal)
        publishSnapshot(context, goal: goal)
    }

    /// Nap credit for the night ending `night`, combining manually-logged
    /// naps with HealthKit-auto-detected ones without double-crediting a nap
    /// caught by both.
    ///
    /// Before this, `SleepNeed`'s nap offset only ever looked at `NapStore`
    /// (see its own doc comment: HealthKit "rarely" catches a short daytime
    /// nap, which is why manual logging exists at all) -- auto-detected naps
    /// contributed nothing to it, even though they're already persisted as
    /// `SleepEpisodeRecord`s. Routed through `SleepDaySummary`'s
    /// overlap-aware dedupe: a nap caught by both sources is credited once,
    /// using whichever source's own asleep-time estimate is larger, rather
    /// than summing both sources' full session durations (which used to
    /// credit any in-bed-but-awake padding a HealthKit session included as
    /// sleep).
    private func deduplicatedNapMinutes(before night: Date, timeZone: TimeZone) -> Double {
        // The night's own recorded timezone, not the device's current one --
        // otherwise "the day before this night" can shift by a day for a
        // night recorded while traveling and later revisited from home.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let previousDay = calendar.date(byAdding: .day, value: -1, to: night) ?? night
        guard let dayInterval = calendar.dateInterval(of: .day, for: previousDay) else {
            return naps.minutesBefore(night: night, timeZone: timeZone)
        }

        let manualNaps = naps.naps
            .filter { calendar.isDate($0.start, inSameDayAs: previousDay) }
            .map { SleepDaySummary.ManualNap(interval: DateInterval(start: $0.start, end: $0.end), minutes: $0.minutes) }
        let autoEpisodes = store.autoDetectedNaps(in: dayInterval)

        let summary = SleepDaySummary.compute(mainSleepMinutes: 0, autoEpisodes: autoEpisodes, manualNaps: manualNaps)
        return summary.automaticNapAsleepMinutes + summary.manualNapMinutes
    }

    /// Every nap before `night`, as literal intervals for `SleepStory`'s
    /// chronological account -- `deduplicatedNapMinutes` above already
    /// covers the case that just needs a total.
    ///
    /// A lighter dedupe than `SleepDaySummary`'s full overlap clustering:
    /// an auto-detected episode is dropped only when it overlaps a manual
    /// log, keeping the manual interval (the user's own start/stop, more
    /// authoritative than a HealthKit guess) rather than showing the same
    /// nap as two timeline events. Doesn't handle a cluster of more than
    /// two overlapping records the way the full dedupe does -- naps rarely
    /// produce that, and Sleep Story is an illustrative account, not a
    /// total that needs to be exactly right.
    func napIntervals(before night: Date, timeZone: TimeZone) -> [DateInterval] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let previousDay = calendar.date(byAdding: .day, value: -1, to: night) ?? night
        guard let dayInterval = calendar.dateInterval(of: .day, for: previousDay) else { return [] }

        let manualIntervals = naps.naps
            .filter { calendar.isDate($0.start, inSameDayAs: previousDay) }
            .map { DateInterval(start: $0.start, end: $0.end) }
        let autoIntervals = store.autoDetectedNaps(in: dayInterval).map(\.interval)
        let unmatchedAuto = autoIntervals.filter { auto in
            !manualIntervals.contains { $0.intersects(auto) }
        }

        return (manualIntervals + unmatchedAuto).sorted { $0.start < $1.start }
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
            // total24hAsleepMinutes against this night's own learned need
            // (falling back to the flat goal only for nights predating that
            // column) -- the same baseline-only approximation the Cause
            // Finder observation builder below also uses, so this and Cause
            // Finder can't disagree with each other. It is deliberately NOT
            // the live Today path's figure: DayContextBuilder's `SleepNeed`
            // adds a debt-payback and strain bonus and subtracts a nap
            // credit on top of the same baseline, none of which this
            // reconstructs (yesterday's strain in particular isn't stored
            // per historical night, so it can't be). Previously this scored
            // main-sleep-only against the *current* flat goal instead of
            // each night's own learned baseline, which was the strictly
            // worse bug this replaced -- but treat this as its own
            // baseline-only figure, not a stand-in for what Today showed.
            let performance = min(
                100, night.total24hAsleepMinutes / max(night.sleepNeedBaselineMinutes ?? goal, 1) * 100
            )
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
            sleepPerformance: context.sleepNeed.performancePercent,
            sleepIntelligencePercent: context.sleepIntelligence.percent,
            sleepIntelligenceBand: context.sleepIntelligence.band.label,
            isShiftWorkModeEnabled: preferences.isShiftWorkModeEnabled
        )
        snapshot.bodySignalsLabel = context.healthRadar.isActive
            ? context.healthRadar.severity.label
            : "Nothing unusual"

        // Autopilot and forecast are computed here for the same reason
        // badges are: both need the whole night history, and neither the
        // widget nor the watch has a HealthKit pipeline to rebuild it from.
        // The clock formatting happens here too -- see the snapshot fields'
        // own documentation for why it is not left to each extension.
        let obligationWake: Date? = context.bodyClock?.window(for: .now)?.end
        if let plan = SleepAutopilot.plan(
            nights: recentNights,
            sleepNeedMinutes: context.learnedSleepNeed.minutes,
            obligationWakeMinutes: obligationWake.map {
                Statistics.circularMinutesFromMidnight($0)
            },
            sleepDebtMinutes: context.sleepNeed.debtMinutes
        ) {
            snapshot.tonightTargetLabel = plan.targetRangeLabel
            snapshot.tonightTargetNote = plan.sentence
            snapshot.isTonightTargetHolding = plan.isHolding
        }
        if let forecast = UncertaintyForecast.forecastAll(nights: recentNights).first {
            snapshot.tomorrowRangeLabel = forecast.rangeLabel
        }

        // The strongest claim, for the watch. Same compilation the Evidence
        // screen runs, so the two cannot disagree about what that claim is,
        // and gated by `glanceMinimumStrength` so the tiers that depend on
        // their caveat never reach a surface with no room to print one.
        //
        // This is the most expensive line in `publishSnapshot`: a matched-pair
        // correlator pass plus change-point detection across every metric.
        // It runs on refresh, not on render, and the Evidence screen already
        // pays the same cost per appearance -- but if snapshot publishing
        // ever moves somewhere hotter, this is the call to hoist or cache.
        if let headline = EvidenceNotebook.glanceHeadline(from: notebookEntries()) {
            snapshot.headlineFindingText = headline.headline
            snapshot.headlineFindingStrength = headline.strength.label
        }

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

    /// Averages heart rate and HRV from today's wake time to now, and compares
    /// them against rolling values from equivalent physiological metrics.
    ///
    /// Deliberately its own pass rather than folded into `refresh()`'s main
    /// pipeline: it has nothing to do with sessions or SwiftData, and running
    /// it independently means a HealthKit hiccup here can never block the
    /// night's real data from landing.
    ///
    /// How long after a workout ends its elevated HR/HRV are still treated
    /// as exertion rather than autonomic load, for `refreshTodayStress`.
    private static let postWorkoutBufferMinutes: TimeInterval = 30
    /// Active-energy-per-hour above which an unlogged hour is treated as
    /// genuinely active rather than sedentary. A resting hour is typically
    /// well under this; a brisk walk or light chores can approach it, a
    /// real workout clears it easily.
    private static let highMovementKcalPerHour = 150.0

    /// Three kinds of exertion are excluded from the average before it's
    /// computed, since none of them are autonomic stress and averaging them
    /// in reads exercise as if it were psychological load, which is
    /// backwards: workouts, the minutes right after a workout ends (HR/HRV
    /// don't snap back to resting instantly), and hours with high active
    /// energy that were never logged as a formal workout at all (a brisk
    /// errand, chores). None of this closes the deeper gap this score still
    /// has -- the baseline it compares against is built from *overnight*
    /// resting physiology, and even a genuinely calm waking hour reads
    /// differently from sleep does -- which is why this presents as
    /// "Physiological Load — Experimental" rather than a confident clinical-
    /// sounding "Stress" number. See `StressCard`'s own doc comment.
    private func refreshTodayStress() async {
        guard DataEnvironment.current.isLive else {
            todayStress = AppMockData.stress
            return
        }

        let calendar = Calendar.current
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        let samplingStart = max(dayStart, store.latestNight?.wakeTime ?? dayStart)
        guard samplingStart < now else { return }
        let interval = DateInterval(start: samplingStart, end: now)

        let workouts = (try? await healthKit.workouts(in: interval)) ?? []
        todayWorkouts = workouts.map(WorkoutSummary.init).sorted { $0.start < $1.start }
        // Extended past the workout's own end: heart rate and HRV don't snap
        // back to a resting state the instant a session stops, so the
        // minutes right after a hard effort still read as exertion, not
        // autonomic load, even though no workout is technically running.
        let workoutIntervals = workouts.map {
            DateInterval(start: $0.startDate, end: $0.endDate.addingTimeInterval(Self.postWorkoutBufferMinutes * 60))
        }

        // Movement that was never logged as a formal workout -- a brisk
        // errand, chores, an unlogged walk -- still isn't autonomic stress,
        // and without this the average kept treating it as one. Reuses the
        // same active-energy series `Daily Load`'s own strain fallback
        // already queries, at hourly resolution -- fine-grained enough to
        // isolate genuinely active hours without a second new HealthKit
        // permission.
        let hourlyEnergy = (try? await healthKit.hourlyActiveEnergy(in: interval)) ?? []
        let highMovementIntervals = hourlyEnergy
            .filter { $0.bpm >= Self.highMovementKcalPerHour }
            .map { DateInterval(start: $0.date, duration: 3600) }

        let samplingIntervals = DateInterval.subtracting(workoutIntervals + highMovementIntervals, from: interval)
        guard !samplingIntervals.isEmpty else { return }

        async let hrTask = try? healthKit.average(.heartRate, unit: .beatsPerMinute, in: samplingIntervals)
        async let hrvTask = try? healthKit.average(
            .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), in: samplingIntervals
        )
        let avgHR = await hrTask ?? nil
        let avgHRV = await hrvTask ?? nil

        let baseline = store.baseline(for: dayStart, goalMinutes: preferences.sleepGoalMinutes)

        todayStress = StressScore.compute(
            avgHeartRate: avgHR,
            avgHRV: avgHRV,
            hrBaseline: baseline.restingHeartRate7DayAvg,
            hrvBaseline: baseline.hrv7DayAvg,
            sampledMinutes: samplingIntervals.reduce(0) { $0 + $1.duration } / 60,
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
            age: preferences.age ?? 34,
            obligationWeekdays: preferences.obligationWeekdays
        ))

        state = .mock(context)
        recentNights = MockData.history
        rebuildRecoveryHistory(goal: goal)
        todayStress = AppMockData.stress
        lastRefresh = .now
    }

    // MARK: - Actions

    private static func makeEngine(
        for choice: UserPreferences.EngineChoice
    ) -> any SleepInsightEngine {
        switch choice {
        case .ruleBased:
            RuleBasedInsightEngine()
        case .appleIntelligence:
            FoundationModelInsightEngine(fallback: RuleBasedInsightEngine())
        case .localLLM:
            LocalLLMInsightEngine(fallback: RuleBasedInsightEngine())
        }
    }

    /// Source names available to pick from in Settings -- see
    /// `UserPreferences.preferredSleepSourceName`.
    func knownSleepSourceNames() -> [String] {
        store.knownSourceNames()
    }

    /// Name paired with the stable bundle identifier to actually store as
    /// the preference -- see `SleepHistoryStore.knownSleepSources()`.
    func knownSleepSources() -> [(name: String, bundleIdentifier: String?)] {
        store.knownSleepSources()
    }

    func setEngine(_ choice: UserPreferences.EngineChoice) {
        engine = Self.makeEngine(for: choice)
        preferences.preferredEngine = choice
        Task { await recomputeDerivedValues() }
    }

    /// Recomputes everything after a settings change that affects derived
    /// values (the sleep goal feeds score, sleep need, and debt).
    func recomputeDerivedValues() async {
        // Two questions, not one: `state.isMock` asks what's currently on
        // screen (a live session that fell back for want of data stays on
        // mock rather than flipping mid-session), while the environment asks
        // what this process is allowed to read at all. Either being true
        // means recomputing from the sample set.
        if state.isMock || DataEnvironment.current.isSample {
            loadMockData()
        } else {
            await publishLatest()
        }
    }

    /// Restores a backup into the live stores, then rebuilds everything.
    ///
    /// - Returns: a human-readable summary of what landed.
    func importArchive(_ archive: DataExporter.Archive) async -> String {
        let nights = store.importNights(
            archive.nights,
            absoluteTemperatures: archive.wristTemperaturesByDate
        )
        let entries = journal.importEntries(
            archive.journal.map {
                (
                    date: $0.date, tags: $0.tags, note: $0.note, feelingRaw: $0.feeling,
                    restedRaw: $0.rested, energyRaw: $0.energy, sleepinessRaw: $0.sleepiness, moodRaw: $0.mood,
                    nightKey: $0.nightKey
                )
            }
        )
        let restoredNaps = naps.importNaps(archive.naps)
        let restoredSnore = SnoreStore().importSummaries(archive.snoreSummaries ?? [])
        let restoredEpisodes = store.importEpisodes(archive.episodes ?? [])
        let restoredExperiments = experiments.importOutcomes(archive.experiments ?? [])
        let restoredSoundEvents = SoundEventStore().importEvents(archive.soundEvents ?? [])
        // A V3 archive has no observations. They import as nothing rather
        // than being reconstructed from `archive.journal`'s positive tags:
        // the legacy-tag path in `exposureState` already covers those, and
        // synthesising rows here would claim the archive recorded answers
        // it never held.
        let restoredObservations = behaviors.importObservations(archive.behaviorObservations ?? [])

        // The archive carries the goal the data was recorded against. Adopting
        // it matters: sleep debt, need and recovery are all measured against
        // the goal, so importing nights while keeping a different target would
        // silently rescore the entire history.
        if archive.goalMinutes > 0 {
            preferences.sleepGoalMinutes = archive.goalMinutes
        }
        if let restored = archive.preferences {
            preferences.age = restored.age
            preferences.appearance = UserPreferences.AppearancePreference(
                rawValue: restored.appearance
            ) ?? .dark
            preferences.bedtimeRemindersEnabled = restored.bedtimeRemindersEnabled
            preferences.cycleTrackingEnabled = restored.cycleTrackingEnabled
            preferences.lifestyleInsightsEnabled = restored.lifestyleInsightsEnabled ?? false
            preferences.smartWakeEnabled = restored.smartWakeEnabled
            preferences.wakeAlarmEnabled = restored.wakeAlarmEnabled ?? false
            preferences.focusSilencesBedtimeNudges = restored.focusSilencesBedtimeNudges ?? false
            preferences.preferredSleepSourceName = restored.preferredSleepSourceName
            preferences.preferredEngine = UserPreferences.EngineChoice(
                rawValue: restored.preferredEngine
            ) ?? .ruleBased
            preferences.preferredSleepSourceBundleIdentifier = restored.preferredSleepSourceBundleIdentifier
            if let obligationWeekdays = restored.obligationWeekdays {
                preferences.obligationWeekdays = Set(obligationWeekdays)
            }
            preferences.isShiftWorkModeEnabled = restored.isShiftWorkModeEnabled ?? false
            preferences.trackedBehaviorTagIdentifiers = restored.trackedBehaviorTagIdentifiers.map(Set.init)
            preferences.restoreActiveExperiment(
                tag: restored.activeExperimentTag.flatMap(BehaviorTag.init(rawValue:)),
                startDate: restored.experimentStartDate,
                hypothesis: restored.experimentHypothesis,
                primaryMetric: restored.experimentPrimaryMetric.flatMap(JournalCorrelator.Metric.init(rawValue:)),
                direction: restored.experimentDirection.flatMap(GuidedExperiment.Direction.init(rawValue:))
            )
            preferences.restoreRecoveryModeDate(restored.recoveryModeDate)
            engine = Self.makeEngine(for: preferences.preferredEngine)
        }

        // Anchored sync must start over — the store now contains nights
        // HealthKit never told us about, and the old anchor would skip them.
        AnchorStore.clear()
        await recomputeDerivedValues()

        if preferences.bedtimeRemindersEnabled {
            await reminders.refreshAuthorization()
            if let bedtime = state.context?.targetBedtime() {
                await reminders.schedule(bedtime: bedtime)
            }
        }

        // Every count, every chance to read "1 naps". Restoring a backup with
        // exactly one nap or one snore summary is ordinary, not an edge case.
        var summary = "Restored \(nights.pluralized("night")), \(entries.pluralized("journal entry", "journal entries")), "
            + "\(restoredNaps.pluralized("nap")) and \(restoredSnore.pluralized("snore summary", "snore summaries"))."
        // Episodes/experiments/sound events are all format-3 additions --
        // omitted entirely for a pre-3 backup rather than always printing
        // "0 experiments" and making every older restore look incomplete.
        var extras: [String] = []
        if restoredEpisodes > 0 { extras.append(restoredEpisodes.pluralized("secondary sleep episode")) }
        if restoredExperiments > 0 { extras.append(restoredExperiments.pluralized("experiment")) }
        if restoredSoundEvents > 0 { extras.append(restoredSoundEvents.pluralized("sound event")) }
        if restoredObservations > 0 {
            extras.append(restoredObservations.pluralized("behaviour answer"))
        }
        if !extras.isEmpty {
            summary += " Also restored \(extras.joined(separator: ", "))."
        }
        return summary
    }

    func absoluteWristTemperaturesForExport() -> [(date: Date, absoluteCelsius: Double)] {
        store.absoluteWristTemperaturesForExport()
    }

    func episodesForExport() -> [DataExporter.Archive.EpisodeRecord] {
        store.episodesForExport()
    }

    func behaviorObservationsForExport() -> [DataExporter.Archive.BehaviorObservationRecordExport] {
        behaviors.observationsForExport()
    }

    /// Erases every Zoon-owned representation of the user's data, including
    /// derived copies outside SwiftData. HealthKit itself remains untouched.
    /// - Returns: `false` if any disk-backed deletion reported a failure.
    @discardableResult
    func deleteAllData() -> Bool {
        let nightsDeleted = store.deleteAll()
        let journalDeleted = journal.deleteAll()
        let behaviorsDeleted = behaviors.deleteAll()
        naps.deleteAll()
        experiments.deleteAll()
        SnoreStore.erasePersistedData()
        SoundEventStore.erasePersistedData()
        let snapshotDeleted = SnapshotStore.clear()
        let legacyStoreDeleted = PersistentStore.eraseLegacyStoreFiles()
        let temporaryExportsDeleted = DataExporter.clearTemporaryExports()
        watchLink.clearSnapshot()
        InsightCache.shared.clear()
        DeepLink.clear()
        // The Spotlight index lives outside the app container, so uninstalling
        // clears it but erasing from inside the app would not -- and this
        // action promises to leave nothing behind.
        SpotlightIndexer.removeAll()
        AnchorStore.clear()
        reminders.cancel()
        reminders.cancelWakeWindow()
        preferences.resetForDataErasure()
        engine = Self.makeEngine(for: preferences.preferredEngine)

        state = .empty(reason: .noSleepData)
        recentNights = []
        recoveryHistory = [:]
        todayStress = nil
        cyclePeriodStarts = []
        todayLifestyleInsights = nil
        lastRefresh = nil
        WidgetCenter.shared.reloadAllTimelines()

        return nightsDeleted
            && journalDeleted
            && behaviorsDeleted
            && snapshotDeleted
            && legacyStoreDeleted
            && temporaryExportsDeleted
    }

    // MARK: - Derived views of history

    /// Every claim Zoon holds, strongest first.
    ///
    /// Lives here rather than in `EvidenceView` because the snapshot needs
    /// the same list. Two call sites assembling the notebook's inputs
    /// separately is how the watch ends up naming a different "strongest
    /// claim" than the screen that exists to list them -- and the inputs are
    /// easy to get subtly wrong: `findings(from:)` and `topFindingPerTag`
    /// are both plausible here and produce different top rows.
    ///
    /// Findings are a parameter because `EvidenceView` already computes them
    /// once per render and passes them to the planner as well; making it
    /// recompute here would undo that hoisting on the app's most expensive
    /// screen.
    func notebookEntries(findings: [JournalCorrelator.Finding]) -> [EvidenceNotebook.Entry] {
        let sorted = recentNights.sorted { $0.date < $1.date }
        // Only last night is investigated -- NightDetective is about one
        // night against its own history, not a survey.
        let nightReport = sorted.last.flatMap {
            NightDetective.investigate(night: $0, history: Array(sorted.dropLast()))
        }
        return EvidenceNotebook.compile(
            experiments: experiments.outcomes,
            findings: findings,
            changePoints: ChangePointDetector.detectAll(nights: recentNights),
            nightReport: nightReport
        )
    }

    /// The same list, computing findings itself. For callers off the render
    /// path -- the snapshot publisher -- where there is nothing to hoist.
    func notebookEntries() -> [EvidenceNotebook.Entry] {
        notebookEntries(
            findings: JournalCorrelator().findings(from: journalObservations())
        )
    }

    /// Journal observations joined to outcomes, for the correlation engine.
    ///
    /// Every recent night is included, not just nights carrying a
    /// `JournalEntry`. What separates a night that tells us something from
    /// one that doesn't is now `Observation.hasAnyExplicitAnswer`, which
    /// asks whether any behaviour was actually answered -- rather than
    /// whether a journal row exists, which `JournalStore.entryOrCreate`
    /// creates the moment the screen renders a day.
    ///
    /// Including unanswered nights is what makes two downstream numbers
    /// mean anything. `AdaptiveJournal.Prompt.unknownNights` counts nights
    /// nobody reviewed, and `ExperimentPlanner.estimatedNights` inflates a
    /// trial's length by how often this person actually answers -- both were
    /// computing over a list filtered to answered nights only, so the first
    /// was always zero and the second always found a 100% answer rate and
    /// never inflated anything.
    ///
    /// The comparison pool is unaffected: `JournalCorrelator` only ever
    /// draws controls from nights whose `exposureState` is an explicit
    /// `.no`, which an unanswered night can never produce.
    /// The answers recorded for one day, for the Journal screen.
    ///
    /// Falls back to the provisional key so answers given before a night
    /// existed for that date keep showing once one does. Real key wins
    /// when both carry answers.
    func behaviorAnswers(on date: Date, nightKey: String?) -> BehaviorAnswers {
        let provisional = BehaviorObservationRecord.provisionalNightKey(for: date)
        guard let nightKey else { return behaviors.answers(forNightKey: provisional) }
        let real = behaviors.answers(forNightKey: nightKey)
        return real.hasAnyAnswer ? real : behaviors.answers(forNightKey: provisional)
    }

    /// Records an explicit answer for one behaviour on one day.
    ///
    /// Writes both the canonical observation and the legacy positive-tag
    /// set, deliberately. `BehaviorObservationRecord` is the answer every
    /// engine reads, but `JournalEntry.tagIdentifiers` is still what the
    /// journal badge counts (`JournalStore.taggedNightCount`), what the
    /// archive exports, and what `exposureState(for:)` falls back to for
    /// historical nights. Keeping it as exactly "the behaviours answered
    /// yes" preserves all three without giving it a second meaning.
    func setBehavior(
        _ state: BehaviorObservationState,
        for tag: BehaviorTag,
        on date: Date,
        nightKey: String?
    ) {
        let key = nightKey ?? BehaviorObservationRecord.provisionalNightKey(for: date)
        behaviors.set(state, for: tag, nightKey: key)
        let entry = journal.entryOrCreate(for: date, nightKey: nightKey)
        // The tag set tracks yes and nothing else, so an explicit no and
        // a cleared answer both remove it.
        if (state == .yes) != entry.contains(tag) {
            journal.toggle(tag, on: date, nightKey: nightKey)
        }
    }

    /// Advances one behaviour through unanswered, yes, no, unanswered.
    /// - Returns: the state now recorded.
    @discardableResult
    func cycleBehavior(for tag: BehaviorTag, on date: Date, nightKey: String?) -> BehaviorObservationState {
        let current = behaviorAnswers(on: date, nightKey: nightKey).state(for: tag)
        let next: BehaviorObservationState = switch current {
        case .unknown: .yes
        case .yes: .no
        case .no: .unknown
        }
        setBehavior(next, for: tag, on: date, nightKey: nightKey)
        return next
    }

    /// Answers every still-unanswered tracked behaviour `.no` for a day.
    /// - Returns: how many answers were recorded.
    @discardableResult
    func answerRemainingBehaviorsNo(on date: Date, nightKey: String?, candidates: [BehaviorTag]) -> Int {
        let key = nightKey ?? BehaviorObservationRecord.provisionalNightKey(for: date)
        return behaviors.answerRemainingNo(nightKey: key, candidates: candidates)
    }

    func journalObservations() -> [JournalCorrelator.Observation] {
        let entries = journal.allEntries()
        let answersByNightKey = behaviors.allAnswersByNightKey()
        let tagsByDate = Dictionary(uniqueKeysWithValues: entries.map { ($0.date, Set($0.tags)) })
        // Entries that carry a `nightKey` (see `JournalEntry.nightKey`) join
        // against a night's own `nightKey` instead of its `date` -- safe
        // across a timezone change between the night itself and whenever
        // the entry actually got written, which the exact-`Date` join below
        // isn't: both sides of that comparison are computed via whatever
        // timezone was current *at the moment each was written*, and after
        // travel those can silently disagree about which night a `Date`
        // instant belongs to. Legacy entries with no `nightKey` yet fall
        // back to `tagsByDate`. `uniquingKeysWith` rather than
        // `uniqueKeysWithValues`: two entries collapsing to the same
        // nightKey shouldn't be possible (`date` is unique and nightKey is
        // derived per-date), but silently keeping one is safer than a crash
        // if that assumption is ever wrong.
        let tagsByNightKey = Dictionary(
            entries.compactMap { entry -> (String, Set<BehaviorTag>)? in
                guard let key = entry.nightKey else { return nil }
                return (key, Set(entry.tags))
            },
            uniquingKeysWith: { first, _ in first }
        )
        let goal = preferences.sleepGoalMinutes
        var calendar = Calendar.current

        // Travel Mode groundwork (finding #55/#56): each night's timezone
        // against the *chronologically previous stored night's* -- not
        // just the adjacent array element, in case history ever has gaps
        // or arrives out of order.
        let sortedByDate = recentNights.sorted { $0.date < $1.date }
        var previousTimeZoneByDate: [Date: String] = [:]
        for (previous, current) in zip(sortedByDate, sortedByDate.dropFirst()) {
            previousTimeZoneByDate[current.date] = previous.timeZoneIdentifier
        }

        return recentNights.map { night -> JournalCorrelator.Observation in
            // Empty rather than nil for a night with no entry: an
            // unanswered night is still an observation, it just carries no
            // behaviour information. See this method's doc comment.
            let tags = tagsByNightKey[night.nightKey] ?? tagsByDate[night.date] ?? []
            // Each night's own timezone, not the device's current one -- see
            // SleepNightFeatures.timeZoneIdentifier. Otherwise a night
            // recorded while traveling can flip which weekday it's classified
            // as once the user is back home.
            calendar.timeZone = night.timeZone
            return JournalCorrelator.Observation(
                date: night.date,
                tags: tags,
                // The explicit answers recorded for this night, and nothing
                // inferred from the night having been visited. A night with
                // no answers gets `.none`, which resolves every behaviour to
                // `.unknown`.
                // Real key first, then any answers recorded for that day
                // before a night existed for it -- see
                // `BehaviorObservationRecord.provisionalNightKey`.
                answers: answersByNightKey[night.nightKey]
                    ?? answersByNightKey[
                        BehaviorObservationRecord.provisionalNightKey(
                            for: night.date, calendar: calendar
                        )
                    ]
                    ?? .none,
                recoveryPercent: recoveryHistory[night.date].map(Double.init),
                // 24-hour sleep (main sleep plus naps) against this night's
                // own historical need, not main sleep alone against one
                // current Settings goal applied uniformly to every night --
                // see JournalCorrelator.Metric.sleepPerformance's doc
                // comment.
                sleepPerformance: min(
                    100, night.total24hAsleepMinutes / max(night.sleepNeedBaselineMinutes ?? goal, 1) * 100
                ),
                deepMinutes: night.hasStageBreakdown ? night.deepMinutes : nil,
                remMinutes: night.hasStageBreakdown ? night.remMinutes : nil,
                efficiency: night.sleepEfficiencyPercent,
                wakeCount: Double(night.wakeCount),
                // Same `UserPreferences.obligationWeekdays`-driven split
                // SleepRegularity's social-jetlag classification uses --
                // previously a hardcoded calendar-weekend check here while
                // SleepRegularity had its own identical hardcoding, two
                // separate copies of the same simplification that could
                // never be corrected together. Now both read the one
                // user-configurable setting.
                isWeekend: preferences.isFreeDay(night.date, calendar: calendar),
                sleepDebtMinutes: night.sleepDebtMinutes,
                bedtimeHour: DayContextBuilder.shiftedBedtimeHour(night.bedtime, timeZone: night.timeZone),
                alcoholicBeverages: night.alcoholicBeverages,
                lateCaffeineMg: night.lateCaffeineMg,
                measuredTimeZoneShift: previousTimeZoneByDate[night.date].map { $0 != night.timeZoneIdentifier } ?? false
            )
        }
    }

    /// Ends the active Guided Experiment, snapshotting a baseline-vs-trial
    /// comparison into `experiments` first if there's enough data on both
    /// sides -- see `GuidedExperiment.summarize`. Call only from the Cause
    /// Finder "End experiment" action.
    func endActiveExperiment() {
        if let tag = preferences.activeExperimentTag, let startDate = preferences.experimentStartDate {
            if let outcome = GuidedExperiment.summarize(
                tag: tag,
                hypothesis: preferences.experimentHypothesis,
                primaryMetric: preferences.experimentPrimaryMetric ?? .sleepPerformance,
                direction: preferences.experimentDirection ?? .avoid,
                startDate: startDate,
                endDate: .now,
                observations: journalObservations()
            ) {
                experiments.record(outcome)
            }
        }
        preferences.endExperiment()
    }

    // MARK: - Coach longitudinal context

    /// Compact JSON summary of standing patterns -- this week vs last, the
    /// current regularity/sleep-need read, whatever Cause Finder has
    /// actually found, and what the evidence engines know -- fed to
    /// `CoachChat` alongside tonight's own numbers.
    ///
    /// The evidence half was added after those engines shipped, because the
    /// app had reached a state where it could answer "what changed lately?"
    /// and "what should I test next?" on a screen but not in conversation:
    /// Coach was still reading a digest written before any of them existed.
    /// A question the app can answer in one place and not the other is a
    /// worse failure than one it cannot answer at all -- the person has
    /// already seen that Zoon knows.
    ///
    /// Before this, Coach's only input was `SleepNightFeatures.summaryForLLM`
    /// for the one night on screen: it could describe *tonight* but had no
    /// way to say "your recovery has been climbing all week" or "you tested
    /// worse after late caffeine" -- both already computed elsewhere in the
    /// app (`weeklyReport()`, `JournalCorrelator`) and simply never handed to
    /// the model. This closes that gap the same way `summaryForLLM` closes it
    /// for one night: a flat, terse, `nil`-omitting JSON payload, not a
    /// per-turn tool call -- `FoundationModels.Tool` would let the model ask
    /// for exactly what a given question needs rather than reading a fixed
    /// digest on every turn, but its exact protocol shape couldn't be
    /// verified against Apple's actual SDK in this environment, and 14 wrong
    /// tool conformances is a worse failure mode than an eagerly-built digest
    /// that's merely more context than any single question needs. Live
    /// tool-calling is a clearly scoped follow-up, not implemented here.
    func coachContextDigest() -> String {
        let findings = JournalCorrelator().topFindingPerTag(from: journalObservations())
            .sorted { abs($0.percentChange) > abs($1.percentChange) }
            .prefix(5)

        let report = weeklyReport()
        let context = state.context

        let payload = CoachContextDigest(
            nightsLogged: recentNights.count,
            weekAvgRecoveryPct: report?.averageRecovery?.rounded(to: 0),
            weekAvgSleepPerformancePct: report?.averageSleepPerformance?.rounded(to: 0),
            weekAvgHrvMs: report?.averageHRV?.rounded(to: 0),
            weekAvgRestingHeartRate: report?.averageRestingHR?.rounded(to: 0),
            recoveryTrendPct: report?.recoveryTrend?.rounded(to: 0),
            sleepTrendPct: report?.sleepTrend?.rounded(to: 0),
            hrvTrendPct: report?.hrvTrend?.rounded(to: 0),
            goalHitNightsThisWeek: report?.goalHitCount,
            currentRegularityIndex: context?.regularity.index.rounded(to: 0),
            currentRegularityBand: context?.regularity.hasEnoughData == true ? context?.regularity.band.label : nil,
            learnedSleepNeedMinutes: context?.learnedSleepNeed.minutes.rounded(to: 0),
            sleepDebtMinutes: context?.sleepNeed.debtMinutes.rounded(to: 0),
            activeExperimentTag: preferences.activeExperimentTag?.label,
            causeFinderFindings: findings.map {
                CoachContextDigest.CorrelatorFinding(
                    behavior: $0.tag.label,
                    metric: $0.metric.shortLabel,
                    percentChange: Int($0.percentChange.rounded()),
                    isImprovement: $0.isImprovement,
                    confidence: $0.confidence.rawValue
                )
            },
            // Capped at three. The digest doc above already worries about
            // handing the model more context than any one question needs,
            // and these engines rank their own output, so the cap costs
            // nothing a fourth entry would have added.
            recentChanges: ChangePointDetector.detectAll(nights: recentNights)
                .prefix(3)
                .map {
                    CoachContextDigest.ChangePoint(
                        metric: $0.metric.label,
                        daysAgo: max(0, Calendar.current.dateComponents(
                            [.day], from: $0.date, to: .now
                        ).day ?? 0),
                        isImprovement: $0.isImprovement
                    )
                },
            testedResults: experiments.outcomes
                .sorted { $0.endDate > $1.endDate }
                .prefix(3)
                .map {
                    CoachContextDigest.TestedResult(
                        behavior: BehaviorTag(rawValue: $0.tag)?.label ?? $0.tag,
                        metric: $0.metricLabel,
                        isImprovement: $0.isImprovement
                    )
                },
            suggestedNextTest: ExperimentPlanner.next(
                observations: journalObservations(),
                associatedTags: Set(findings.map(\.tag)),
                settledTags: Set(experiments.outcomes.map(\.tag))
            )?.tag.label,
            tonightTarget: context.flatMap {
                SleepAutopilot.plan(
                    nights: recentNights,
                    sleepNeedMinutes: $0.learnedSleepNeed.minutes,
                    sleepDebtMinutes: $0.sleepNeed.debtMinutes
                )?.sentence
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Flat DTO mirroring `SleepNightFeatures.LLMPayload` -- `nil` fields
    /// omitted rather than encoded as `null`, so a question the data can't
    /// answer yet doesn't dress up as a measured zero.
    private struct CoachContextDigest: Encodable {
        let nightsLogged: Int
        let weekAvgRecoveryPct: Double?
        let weekAvgSleepPerformancePct: Double?
        let weekAvgHrvMs: Double?
        let weekAvgRestingHeartRate: Double?
        let recoveryTrendPct: Double?
        let sleepTrendPct: Double?
        let hrvTrendPct: Double?
        let goalHitNightsThisWeek: Int?
        let currentRegularityIndex: Double?
        let currentRegularityBand: String?
        let learnedSleepNeedMinutes: Double?
        let sleepDebtMinutes: Double?
        let activeExperimentTag: String?
        let causeFinderFindings: [CorrelatorFinding]
        /// Shifts `ChangePointDetector` located, so "has anything changed
        /// lately?" stops being a question the app can answer on a screen
        /// but not in conversation.
        let recentChanges: [ChangePoint]
        /// Finished experiments -- the only claims in the app that came from
        /// something the person deliberately ran, and the tier Coach should
        /// lean on hardest when they conflict with a mere association.
        let testedResults: [TestedResult]
        /// What `ExperimentPlanner` would suggest testing next. A question,
        /// not a prediction -- the field name says "suggested", and no
        /// direction travels with it, for the same reason the planner
        /// refuses to see one.
        let suggestedNextTest: String?
        /// Tonight's `SleepAutopilot` target, already phrased.
        let tonightTarget: String?

        struct CorrelatorFinding: Encodable {
            let behavior: String
            let metric: String
            let percentChange: Int
            let isImprovement: Bool
            let confidence: String
        }

        struct ChangePoint: Encodable {
            let metric: String
            let daysAgo: Int
            let isImprovement: Bool
        }

        struct TestedResult: Encodable {
            let behavior: String
            let metric: String
            let isImprovement: Bool
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
