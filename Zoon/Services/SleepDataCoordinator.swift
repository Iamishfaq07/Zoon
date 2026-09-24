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
    #if DEBUG
    /// Counters for the incremental-sync path, so a change here can be
    /// measured rather than argued about.
    ///
    /// DEBUG-only on purpose. Zoon has no telemetry and this is not the
    /// beginning of any -- it is a development instrument, readable from the
    /// debugger or a test, and compiled out of release builds entirely.
    struct SyncMetrics {
        var refreshes = 0
        var fullRebuilds = 0
        var partialRebuilds = 0
        var skippedRebuilds = 0
        var rangesRebuilt = 0
        var nightsRebuilt = 0
        var episodesRebuilt = 0
        var changedSamplesSeen = 0
        var deletionsSeen = 0
        var lastRefreshSeconds: Double = 0

        mutating func record(plan: SyncRange.Plan, changedSamples: Int, deletions: Int) {
            refreshes += 1
            changedSamplesSeen += changedSamples
            deletionsSeen += deletions
            switch plan {
            case .nothingToDo:
                skippedRebuilds += 1
            case .partial(let ranges):
                partialRebuilds += 1
                rangesRebuilt += ranges.count
            case .full:
                fullRebuilds += 1
            }
        }

        /// The line worth reading. `nightsRebuilt` against `refreshes` is the
        /// number this whole change is about: it used to be every night in the
        /// ninety-day window, every time.
        var summary: String {
            """
            refreshes \(refreshes) | rebuilds full \(fullRebuilds) partial \(partialRebuilds)             skipped \(skippedRebuilds) | ranges \(rangesRebuilt) | nights \(nightsRebuilt)             episodes \(episodesRebuilt) | delta samples \(changedSamplesSeen) deletions \(deletionsSeen)             | last \(String(format: "%.2f", lastRefreshSeconds))s
            """
        }
    }

    private(set) var syncMetrics = SyncMetrics()
    #endif

    private enum RefreshState { case idle, refreshing, refreshingWithPending }
    private var refreshState: RefreshState = .idle
    private var refreshTask: Task<Void, Never>?
    private var isErasing = false
    /// Bumped by `deleteAllData()`. A `publishLatest()` suspended across an
    /// `await` while the erase ran would otherwise resume after `isErasing`
    /// has been reset and publish -- or write back -- the night it had
    /// already read from the store that no longer exists. Each await in
    /// `publishLatest` re-checks this instead.
    private var storeGeneration = 0
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

    /// Stretches of today's waking hours where heart rate sat below this
    /// person's own usual figure for that hour, with movement low. Empty
    /// until `refreshRestorativeWindows` has run, and empty is also the
    /// honest answer whenever the baseline has not earned a block yet --
    /// see `RestorativeWindow`.
    private(set) var todayRestorativeWindows: [RestorativeWindow.Window] = []

    /// Minute-level overnight series for the Awakening Inspector (§25).
    ///
    /// Fetched once for the whole night rather than per awakening: a night
    /// holds a handful of them, and three queries beat three per awakening.
    /// Empty until `refreshAwakeningSeries` has run, and empty on a night with
    /// no watch -- which the inspector reports as a missing stream rather than
    /// as a flat line.
    private(set) var awakeningSeries = AwakeningInspector.Series()
    /// Today's step count against what this weekday usually looks like by
    /// now. `nil` until a sample actually arrives — the card was previously
    /// constructed with hardcoded `nil`s at the call site, so it reported
    /// "steps have not been recorded" to everyone forever while the step read
    /// scope fed nothing.
    private(set) var todayMovement: MovementContext.Snapshot?
    /// Populated only when cycle tracking is on. Empty otherwise, including
    /// on every code path that never asks HealthKit for it.
    private(set) var cyclePeriodStarts: [Date] = []
    /// Populated only when Lifestyle Insights is on. `nil` otherwise,
    /// including on every code path that never asks HealthKit for it.
    private(set) var todayLifestyleInsights: LifestyleInsights?

    // MARK: - Dependencies

    private let healthKit: HealthKitManager
    private let store: SleepHistoryStore
    // MARK: - Model evaluation

    /// The sleep-debt model against the person's own morning ratings.
    /// See `NeedModelEvaluation`: measured, never used to adjust anything.
    ///
    /// Each night is paired with the shortfall *through* it -- the debt the
    /// next night carried in, or the current figure for the latest -- because
    /// that is what the model says the person woke up owing. Strata are the
    /// night's stage source and the person's schedule mode.
    func needModelEvaluation() -> [NeedModelEvaluation.Summary] {
        let nights = recentNights.sorted { $0.date < $1.date }
        guard !nights.isEmpty else { return [] }
        let entries = journal.allEntries()
        let byKey = Dictionary(
            entries.compactMap { entry in entry.nightKey.map { ($0, entry) } },
            uniquingKeysWith: { first, _ in first }
        )
        let byDay = Dictionary(
            entries.map { (Calendar.current.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let shift = preferences.isShiftWorkModeEnabled
        return NeedModelEvaluation.evaluate(nights.enumerated().map { index, night in
            let through = index + 1 < nights.count
                ? nights[index + 1].sleepDebtMinutes
                : state.context?.shortfallNowMinutes
            let entry = byKey[night.nightKey] ?? byDay[Calendar.current.startOfDay(for: night.date)]
            let source = night.stageTrust.supportsStageFigures ? "Measured stages" : "Unstaged or unknown source"
            return NeedModelEvaluation.Night(
                shortfallMinutes: through,
                restedRating: entry?.restedRaw,
                stratum: shift ? "\(source), shift work" : source
            )
        })
    }

    // MARK: - Tonight

    /// The habitual wake clock, on `SleepAutopilot`'s signed scale.
    ///
    /// The body clock's when it exists, last night's wake otherwise. Only the
    /// clock time is used, so which day `window(for:)` lands on does not
    /// matter here -- which is the one place that is true.
    private func usualWakeMinute(_ context: DayContext, now: Date) -> Double {
        let wake = context.bodyClock?.window(for: now)?.end ?? context.night.wakeTime
        return Statistics.circularMinutesFromMidnight(wake)
    }

    /// Tonight's autopilot plan. One place, so the Today hero, the nap coach,
    /// the watch snapshot and the episode all read the same plan instead of
    /// each rebuilding it with slightly different inputs.
    ///
    /// - Parameter context: the context to plan from, when the caller holds
    ///   one that has not been published to `state` yet.
    func tonightAutopilotPlan(
        for context: DayContext? = nil,
        now: Date = .now
    ) -> SleepAutopilot.Plan? {
        guard let context = context ?? state.context else { return nil }
        // Tonight's need before repayment, and the whole outstanding
        // shortfall: the autopilot owns the repayment rule. It used to be
        // handed `sleepNeed.debtMinutes` -- already a 33% repayment of the
        // debt carried into *last* night -- and took 25% of that again, so
        // tonight asked for about 8% of a figure that did not include the
        // night just slept.
        //
        // Now built once, in `DayContextBuilder`, as `context.tonight`: the
        // same inputs and the same habitual wake as `usualWakeMinute`. This
        // returns that plan rather than a second one.
        return context.tonight.autopilot
    }

    /// Tonight's episode: the one bed, wind-down and wake every surface uses.
    ///
    /// The person's own plan wins when it covers tonight; otherwise the
    /// autopilot's bedtime against their usual wake; otherwise their usual
    /// wake minus tonight's need. See `ResolvedSleepEpisode` for why this is
    /// resolved once rather than per screen.
    func tonightEpisode(
        for context: DayContext? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ResolvedSleepEpisode? {
        tonightHorizon(nights: 1, for: context, now: now, calendar: calendar).first
    }

    /// Tonight and the nights after it, for scheduling ahead.
    func tonightHorizon(
        nights: Int,
        for explicitContext: DayContext? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ResolvedSleepEpisode] {
        let context = explicitContext ?? state.context
        return ResolvedSleepEpisode.horizon(
            nights: nights,
            plans: PersonalSetupStore.shared.value.plans,
            autopilot: tonightAutopilotPlan(for: context, now: now),
            usualWakeMinute: context.map { usualWakeMinute($0, now: now) },
            needMinutes: context?.tonightPlanning.tonightNeedMinutes ?? preferences.sleepGoalMinutes,
            windDownLeadMinutes: BedtimeReminder.windDownLeadMinutes,
            now: now,
            calendar: calendar
        )
    }

    func nightsForRepair() -> [SleepNightFeatures] { store.historicalFeatures(goalMinutes: preferences.sleepGoalMinutes, manualNaps: naps.naps) }
    private func applyLocalRepairs() {
        store.excludedNightKeys = Set(PersonalSetupStore.shared.value.repairs.filter(\.excluded).map(\.nightKey))
    }
    func evidenceHistoryForExport() -> [EvidenceLedger.Revision] { store.evidenceHistory() }
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
        // SwiftData fetches and WatchConnectivity used to run here. Build 65
        // constructed this coordinator from `ZoonApp.init` against a recovery
        // container whose schema had drifted, and `migrateLegacyTags` trapped
        // on the fetch -- `try?` does not catch a SwiftData trap -- before
        // any window existed. `start()` is the first moment a view asked for
        // this work anyway (RootView `.task`), and a write from a view body
        // is still avoided because `start()` is not a body.
    }

    /// Applies a quick action logged from the watch. `static` and passed its
    /// dependencies explicitly rather than a `self` method: the closure set
    /// on `watchLink.onQuickAction` in `start()` is held by `WatchLink` for the
    /// coordinator's whole lifetime, and capturing `self` there would be a
    /// retain cycle (`watchLink` is itself a property of this coordinator).
    private static func apply(
        _ event: WatchActionEnvelope,
        journal: JournalStore,
        naps: NapStore,
        behaviors: BehaviorObservationStore
    ) {
        let date = event.targetDate
        let key = BehaviorObservationRecord.provisionalNightKey(for: date, calendar: event.calendar)
        // Behaviours are about the day that just happened and belong to the
        // night after it, which is keyed by the morning it ends on -- see
        // `JournalEntry.date`. Feelings, naps and awakenings stay on `date`.
        let nightDate = event.behaviorNightDate
        let nightKey = BehaviorObservationRecord.provisionalNightKey(for: nightDate, calendar: event.calendar)
        switch event.action {
        case .behaviorTag(let rawValue):
            guard let tag = BehaviorTag(rawValue: rawValue) else { return }
            journal.toggle(tag, on: nightDate, nightKey: nightKey)
            let happened = journal.entryOrCreate(for: nightDate, nightKey: nightKey).contains(tag)
            behaviors.set(happened ? .yes : .no, for: tag, nightKey: nightKey)
        case .behaviorAnswer(let rawValue, let happened):
            guard let tag = BehaviorTag(rawValue: rawValue) else { return }
            behaviors.set(happened ? .yes : .no, for: tag, nightKey: nightKey)
            let entry = journal.entryOrCreate(for: nightDate, nightKey: nightKey)
            if happened != entry.contains(tag) { journal.toggle(tag, on: nightDate, nightKey: nightKey) }
        case .morningFeeling(let rawValue):
            guard let feeling = MorningFeeling(rawValue: rawValue) else { return }
            journal.setFeeling(feeling, on: date)
        case .nap(let minutes):
            guard (1...720).contains(minutes) else { return }
            let end = event.occurredAt
            naps.importNaps([NapStore.Nap(start: end.addingTimeInterval(-Double(minutes) * 60), end: end)])
        case .midnightAwakening:
            let hour = event.calendar.component(.hour, from: event.occurredAt)
            let minute = event.calendar.component(.minute, from: event.occurredAt)
            let stamp = String(format: "Midnight awakening at %02d:%02d", hour, minute)
            let existing = journal.entryOrCreate(for: date, nightKey: key).note
            let combined = [existing, stamp]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            journal.setNote(combined, on: date, nightKey: key)
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
        guard let samples = await healthRead("cycle.flow", source: "menstrualFlow", { try await healthKit.menstrualFlowSamples(in: window) }) else { return }
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
    ///
    /// The deadline is `Deadline.race`, not a task group: a group waits for
    /// every child, so a HealthKit call that never completed kept the
    /// "timed-out" request waiting anyway. A second call while one is still
    /// outstanding returns at once rather than stacking a second prompt.
    func requestHealthAccess() async {
        guard DataEnvironment.current.isLive, !isRequestingHealthAccess else { return }
        isRequestingHealthAccess = true
        defer { isRequestingHealthAccess = false }
        do {
            try await Deadline.race(seconds: 20) { [healthKit] in
                try await healthKit.requestAuthorization()
            }
        } catch is Deadline.Expired {
            logger.error("Authorization request timed out after 20s; proceeding without waiting further")
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// True while a permission request is outstanding, so two callers
    /// cannot put two sheets up.
    private var isRequestingHealthAccess = false

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
        // One-time forward-fill of legacy positive tags into the
        // observation store. Guarded by its own UserDefaults flag, which
        // it checks before touching the store, so every launch after the
        // first costs a single Bool read. Runs here rather than lazily on
        // a read path because `journalObservations()` is called from
        // several SwiftUI view bodies, and a write triggered from inside
        // a body evaluation is how you get a mutation-during-render loop.
        behaviors.migrateLegacyTags(from: journal.allEntries())
        watchLink.activate()
        // Captures the stores, not `self`, for the same reason `init` used
        // to: `watchLink` is a property of this coordinator, so a closure
        // it holds that captured `self` would cycle.
        let journal = journal
        let naps = naps
        let behaviors = behaviors
        watchLink.onQuickAction = { [weak self] event in
            guard let self, !isErasing, preferences.hasCompletedOnboarding else { return }
            Self.apply(event, journal: journal, naps: naps, behaviors: behaviors)
            if case .nap = event.action {
                Task { await self.napRecorded() }
            }
        }

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

        healthKit.startObserving { [weak self] in
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
    /// Every observer waits for the shared refresh, including its pending pass.
    /// HealthKit must not be acknowledged before those writes complete.
    func refresh() async {
        guard !isErasing else { return }
        if let refreshTask {
            refreshState = .refreshingWithPending
            await refreshTask.value
            return
        }
        refreshState = .refreshing
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await performRefresh()
            while refreshState == .refreshingWithPending && !isErasing {
                refreshState = .refreshing
                await performRefresh()
            }
            refreshState = .idle
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        applyLocalRepairs()
        #if DEBUG
        let startedAt = Date.now
        defer { syncMetrics.lastRefreshSeconds = Date.now.timeIntervalSince(startedAt) }
        #endif
        await refreshTodayStress()
        await refreshRestorativeWindows()
        await refreshAwakeningSeries()
        await refreshTodayMovement()
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

            // The samples fetch stays full-window on purpose. The anchored
            // delta cannot be rebuilt from directly -- a delta can land
            // mid-night, and segmenting against a partial picture would split
            // one night in two -- and fetching a narrower *range* has the same
            // problem at its edges: a night straddling the boundary would come
            // back truncated and overwrite a good record. One query over the
            // window is cheap and always yields complete sessions.
            //
            // What the plan narrows is the expensive half. `processSessions`
            // runs `FeatureExtractor.extract` per night, and that issues
            // roughly eight HealthKit queries each -- so a full pass over
            // ninety nights is several hundred queries, and it ran on every
            // single change. With the observer set now covering physiology as
            // well as sleep, that had to stop being the per-callback cost.
            let plan = SyncRange.plan(
                // Both edges of every changed sample: either one moving can
                // change which night the sample belongs to.
                changedAt: result.samples.flatMap { [$0.startDate, $0.endDate] },
                hasDeletions: !result.deletedUUIDs.isEmpty,
                storeIsEmpty: store.isEmpty,
                window: window,
                recheckFrom: Calendar.current.date(
                    byAdding: .day, value: -SyncRange.physiologyRecheckDays, to: .now
                )
            )

            var persisted = true
            switch plan {
            case .nothingToDo:
                break
            case .partial(let ranges):
                // Not gated on `!samples.isEmpty` here: `processSessions`
                // decides for itself what an empty fetch means. With history
                // already in the store it refuses to prune on one -- a window
                // whose only sample was deleted in Health is indistinguishable
                // from a failed query -- so that stale night is only removed
                // by a later pass that returns at least one sample. (Deletions
                // force `.full` anyway, so this case never reaches `.partial`.)
                let samples = try await healthKit.fetchAllSleepSamples(in: window)
                persisted = await processSessions(from: samples, window: window, rebuilding: ranges)
            case .full:
                let samples = try await healthKit.fetchAllSleepSamples(in: window)
                persisted = await processSessions(from: samples, window: window, rebuilding: nil)
            }

            #if DEBUG
            syncMetrics.record(plan: plan, changedSamples: result.samples.count, deletions: result.deletedUUIDs.count)
            #endif

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
    /// - Parameter rebuilding: when non-nil, only nights intersecting one of
    ///   these ranges are re-extracted and upserted. `nil` rebuilds every
    ///   night in the window.
    ///
    ///   Narrowing is safe here specifically because `samples` is always a
    ///   complete fetch of `window`: every session is built from full data
    ///   whether or not it is then rebuilt, so `validDates` below stays
    ///   complete and pruning is unaffected. A night skipped for rebuilding
    ///   keeps the row it already has -- it is not pruned, because HealthKit
    ///   still has data behind it.
    private func processSessions(
        from samples: [HKCategorySample],
        window: DateInterval,
        rebuilding ranges: [DateInterval]? = nil
    ) async -> Bool {
        // An empty full-window fetch against a store that already has
        // history is far more likely to be HealthKit failing -- authorization
        // revoked, a transient query error surfacing as zero rows -- than the
        // user having deleted every night in Health. Pruning on it would wipe
        // the whole window's worth of records in one pass, so nothing is
        // touched. The cost is that a genuine erase-everything-in-Health is
        // not mirrored until at least one sample exists again. Nothing was
        // written, so `true` is the honest answer to "did every write land".
        if samples.isEmpty, !store.isEmpty {
            logger.error("HealthKit returned no sleep samples while the store has history; skipping prune")
            return true
        }
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

        // The subset actually worth re-extracting. Compared against each
        // session's own interval rather than its wake date, so a night that
        // began inside a range but ended outside it still counts.
        let sessionsToRebuild: [SleepSession]
        if let ranges {
            sessionsToRebuild = mainSleepPerDate.filter { session in
                ranges.contains { $0.intersects(DateInterval(start: session.start, end: session.end)) }
            }
        } else {
            sessionsToRebuild = mainSleepPerDate
        }

        let extractor = FeatureExtractor(healthKit: healthKit)
        let goal = preferences.sleepGoalMinutes

        // Sleep-need baseline as of just before this batch, kept updated as
        // this pass's own earlier nights land -- see the loop below. Nights
        // this batch is about to reprocess are excluded up front so a
        // same-night re-sync can't appear twice in "nights before" for a
        // later night in the same pass.
        // Only the nights this pass will actually rewrite. A night left
        // alone keeps its stored row, and that row is exactly what the
        // baseline should read for it -- excluding it here would drop it out
        // of the history a later night in this batch compares against.
        let batchDates = Set(sessionsToRebuild.map(\.wakeDate))
        let priorFeaturesBeforeBatch = store.allNights()
            .filter { !batchDates.contains($0.date) }
            .sorted { $0.date < $1.date }
            .map { $0.features() }
        var thisBatchFeaturesOldestFirst: [SleepNightFeatures] = []

        // Oldest first: each night's baseline is drawn from the nights before
        // it, so they must land in the store in chronological order. This
        // also matters for sleepNeedBaselineMinutes below, which needs the
        // same chronological guarantee.
        #if DEBUG
        syncMetrics.nightsRebuilt += sessionsToRebuild.count
        #endif

        for session in sessionsToRebuild {
            let nightDate = session.wakeDate
            let baseline = store.baseline(for: nightDate, goalMinutes: goal, manualNaps: naps.naps)
            let previousWake = (priorFeaturesBeforeBatch + thisBatchFeaturesOldestFirst)
                .map(\.wakeTime).filter { $0 < session.start }.max()
            let result = await extractor.extract(from: session, baseline: baseline, previousWake: previousWake)
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
        #if DEBUG
        syncMetrics.episodesRebuilt += validEpisodeIDs.count
        #endif

        // `samples` here is always a full re-fetch of `window` (see call site),
        // never an incremental delta -- so any previously-stored night in
        // `window` that didn't produce a session this pass genuinely no
        // longer has HealthKit data behind it (deleted or corrected away in
        // the Health app), not just "wasn't included in today's delta".
        //
        // Deliberately built from `mainSleepPerDate` and not from
        // `sessionsToRebuild`: a night that exists in HealthKit but was not
        // worth re-extracting must not look stale to the pruner.
        let validDates = Set(mainSleepPerDate.map(\.wakeDate))
        // A partial rebuild only re-extracted the nights inside `ranges`, so
        // that is also all it is allowed to prune. The bounds are widened to
        // whole days because a night's `date` is the start of its wake day,
        // which can sit before the range that touched it. `validDates` is
        // complete either way (see above), so this is a second fence rather
        // than a correctness requirement -- it bounds the damage should a
        // partial plan and a bad fetch ever coincide.
        let pruneWindow: DateInterval
        if let ranges, let earliest = ranges.map(\.start).min(), let latest = ranges.map(\.end).max() {
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: earliest)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest)) ?? latest
            pruneWindow = DateInterval(start: dayStart, end: dayEnd)
        } else {
            pruneWindow = window
        }
        store.prune(window: pruneWindow, keeping: validDates)
        store.pruneEpisodes(window: pruneWindow, keeping: validEpisodeIDs)

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
    /// one, and a break during their overnight work hours is the nap.
    ///
    /// For a rotating or custom schedule there is no honest window in either
    /// direction -- the shift moves between cycles, or the pattern is split --
    /// so applying one just relabels the assumption instead of removing it.
    /// Those fall back to duration, which is the only signal that does not
    /// encode a belief about when a person *ought* to sleep. This is the
    /// "don't penalise daytime main sleep merely because it is daytime" case.
    ///
    /// (`preferredMainSleep(in:)` itself already picks the main block by
    /// duration, not clock time, so it needs no change here; this only
    /// affects how the *other* sessions on the same day get labeled.)
    private func classify(_ session: SleepSession) -> SleepEpisodeType {
        let mode = preferences.shiftWorkMode

        guard mode.usesClockTimeWindow else {
            let duration = session.end.timeIntervalSince(session.start)
            return duration < Self.napDurationCeiling ? .nap : .secondarySleep
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: session.timeZoneIdentifier) ?? .current
        let midpoint = session.start.addingTimeInterval(session.end.timeIntervalSince(session.start) / 2)
        let hour = calendar.component(.hour, from: midpoint)
        let isDaytime = (9..<18).contains(hour)
        let isNap = mode.treatsDaytimeAsNap ? isDaytime : !isDaytime
        return isNap ? .nap : .secondarySleep
    }

    /// Above this, a non-primary episode is secondary sleep rather than a nap.
    ///
    /// Only consulted for schedules with no usable clock-time window. Three
    /// hours is the point past which calling something "a nap" stops matching
    /// what people mean by the word.
    static let napDurationCeiling: TimeInterval = 3 * 60 * 60

    /// Reads the newest stored night back out, derives everything, updates state
    /// and hands a snapshot to the widget.
    private func publishLatest() async {
        applyLocalRepairs()
        guard !isErasing else { return }
        let generation = storeGeneration
        let goal = preferences.sleepGoalMinutes

        guard let record = store.latestNight else {
            state = .empty(reason: .noSleepData)
            recentNights = []
            return
        }

        let baseline = store.baseline(for: record.date, goalMinutes: goal, manualNaps: naps.naps)
        let rawNight = record.features(
            baseline: baseline,
            secondaryAsleepMinutes: store.secondaryEpisodeAsleepMinutes(
                forNightKey: record.nightKey ?? "", wakeDate: record.date,
                timeZone: record.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current,
                manualNaps: naps.naps
            )
        )
        let repairs = PersonalSetupStore.shared.value.repairs
        let night = LocalSleepCorrection.apply(rawNight, repairs: repairs)

        // Foundation Models inference is async and the engine protocol is not,
        // so generation is primed here and read back synchronously below.
        if let modelEngine = engine as? FoundationModelInsightEngine {
            await modelEngine.prepare(for: night, baseline: baseline, goalMinutes: goal)
        }
        guard generation == storeGeneration else { return }

        // Rebuild each stored night against the context that existed before
        // that specific night. Reusing the latest baseline for the whole array
        // makes historical debt flat and can corrupt correlations and
        // achievements that consume `recentNights`.
        let history = LocalSleepCorrection.apply(
            store.historicalFeatures(goalMinutes: goal, manualNaps: naps.naps)
                .filter { $0.date < night.date && !store.excludedNightKeys.contains($0.nightKey) },
            repairs: repairs
        )


        let maximum = HeartRateZoneIntegrator.maximumHeartRate(age: preferences.age)
        let maxHR = maximum.bpm
        // Heart-rate-reserve zones are as sensitive to this floor as to the
        // ceiling above, and it used to end in a bare `?? 60` -- a population
        // constant that arrived with no label and made the Load model
        // generic in both terms while nothing said so.
        let resting = HeartRateZoneIntegrator.restingHeartRate(
            measuredToday: night.restingHeartRate,
            measuredEarlier: history.compactMap(\.restingHeartRate).last,
            sleepDerived: night.minHeartRate ?? history.compactMap(\.minHeartRate).last
        )
        let restingHR = resting.bpm

        let (todayStrain, yesterdayStrain, hourly) = await loadActivity(
            wakeTime: night.wakeTime, restingHR: restingHR, maxHR: maxHR,
            zoneProvenance: maximum.provenance,
            restingProvenance: resting.provenance
        )

        // The night's own heart rate, for the hypnogram. Five-minute bins:
        // hourly ones give a seven-hour night seven points and flatten the
        // dip that makes the line worth drawing.
        let overnightHeartRate = night.bedtime < night.wakeTime
            ? (await healthRead("night.binnedHeartRate", source: "heartRate", {
                try await healthKit.binnedHeartRate(
                    in: DateInterval(start: night.bedtime, end: night.wakeTime), binMinutes: 5
                )
            }) ?? [])
            : []

        guard !isErasing, generation == storeGeneration else { return }

        // Generation is deferred into the builder rather than run above,
        // because the summary's opening grade has to come from Sleep
        // Intelligence and that is computed inside `build`. Running the
        // engine here and the score there is what let the sentence and the
        // hero orb disagree about the same night.
        let context = contextBuilder.build(.init(
            night: night,
            // `[engine]` rather than `self.engine`: the closure is stored
            // on Inputs, so it escapes, and capturing it by value keeps the
            // coordinator out of the capture entirely.
            insight: { [engine] band in
                engine.generate(
                    for: night, baseline: baseline, goalMinutes: goal, band: band
                )
            },
            history: history,
            goalMinutes: goal,
            yesterdayStrain: yesterdayStrain,
            todayStrain: todayStrain,
            hourlyHeartRate: hourly,
            maxHeartRate: maxHR,
            napMinutes: deduplicatedNapMinutes(before: night.date, timeZone: night.timeZone),
            bedtimeConsistencyMinutes: baseline.bedtimeConsistencyMinutes,
            age: preferences.age,
            sex: preferences.biologicalSex,
            bodyMassIndex: preferences.bodyMassIndex,
            obligationWeekdays: preferences.obligationWeekdays,
            // Tonight is planned from the ledger with last night on it and
            // from today's naps -- not from what was carried into last night.
            shortfallThroughLatestNightMinutes: store.currentBaseline(
                goalMinutes: goal, manualNaps: naps.naps
            ).sleepDebtMinutes,
            napMinutesToday: napMinutesToday(),
            overnightHeartRate: overnightHeartRate
        ))

        store.attach(context.insight, to: record)
        state = .loaded(context)
        recentNights = (history + [night]).filter { !store.excludedNightKeys.contains($0.nightKey) }
        recordCurrentBeliefs()
        rebuildRecoveryHistory(goal: goal)
        publishSnapshot(context, goal: goal)
    }

    /// Widgets and the watch only see a nap after `publishSnapshot`.
    /// Start/stop used to wait for the next HealthKit refresh, which is
    /// minutes later if the app stays in the foreground.
    func republishGlanceSurfaces() {
        guard let context = state.context else { return }
        publishSnapshot(context, goal: preferences.sleepGoalMinutes)
    }

    /// A nap was recorded -- finished on the phone or logged from the Watch.
    ///
    /// Today's nap credit feeds tonight's need, and that is fixed when the
    /// day's context is built, so republishing the existing context left
    /// tonight's plan (Today, the widgets, the Watch) without the nap until
    /// the next Health refresh. This rebuilds from stored data -- no Health
    /// query -- and publishes. Sample data has nothing to rebuild from, so
    /// there it only republishes.
    func napRecorded() async {
        guard !state.isMock, !DataEnvironment.current.isSample else {
            republishGlanceSurfaces()
            return
        }
        await publishLatest()
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

    /// Naps recorded **today**, from both sources, deduplicated.
    ///
    /// `deduplicatedNapMinutes(before:)` answers "what naps does this
    /// finished night carry", which is the day before its wake. Nothing
    /// answered "what have I napped today", and today is the only day whose
    /// shortfall is still moving — so a nap this afternoon, from the in-app
    /// timer or from Health, could not affect anything on screen until
    /// tomorrow morning's night was written.
    ///
    /// Both sources, not just the in-app timer: a nap Apple Health recorded
    /// arrives as a `SleepEpisodeRecord` and never touches `NapStore`, so
    /// reading `NapStore` alone misses exactly the naps a watch caught by
    /// itself. Routed through `SleepDaySummary` for the same overlap-aware
    /// dedupe, so a nap caught by both is credited once.
    ///
    /// Today's own calendar day in the device's current timezone, which is
    /// right here for the same reason a stored night uses its own: today is
    /// happening now, wherever the phone is now.
    func napMinutesToday(now: Date = .now) -> Double {
        let calendar = Calendar.current
        guard let dayInterval = calendar.dateInterval(of: .day, for: now) else {
            return naps.minutes(on: now)
        }

        let manualNaps = naps.naps
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
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
    /// Every logged nap paired with the night that followed it.
    ///
    /// `NapLearning` needs the join, not the naps: what it reports is whether
    /// naps of a given shape have sat alongside a later bedtime or a shorter
    /// night, which is only answerable with both halves. The engine was added
    /// with tests and no caller, so nothing ever built these.
    ///
    /// Strictly observational, and the engine's own wording keeps it that
    /// way -- a nap and a later bedtime appearing together is not the nap
    /// causing it.
    func napObservations() -> [NapLearning.Observation] {
        let sorted = recentNights.sorted { $0.date < $1.date }
        var priorAsleep: [Date: Double] = [:]
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            priorAsleep[current.date] = previous.timeAsleepMinutes
        }

        // Every night, not only the ones with a nap. The control arm is the
        // whole point: the version this replaced skipped no-nap days
        // outright, so the engine downstream had nothing to compare against
        // and was reporting associations it had not measured.
        return sorted.map { night in
            var calendar = Calendar.current
            calendar.timeZone = night.timeZone
            let naps = napIntervals(before: night.date, timeZone: night.timeZone)
            // The longest nap stands for the day. Two observations of one day
            // would let it back its own comparison twice.
            let longest = naps.max { $0.duration < $1.duration }

            return NapLearning.Observation(
                date: night.date,
                nap: longest.map { nap in
                    NapLearning.Observation.Nap(
                        startHour: Double(calendar.component(.hour, from: nap.start))
                            + Double(calendar.component(.minute, from: nap.start)) / 60,
                        minutes: nap.duration / 60
                    )
                },
                bedtimeMinutes: Statistics.circularMinutesFromMidnight(
                    night.bedtime, calendar: calendar
                ),
                latencyMinutes: night.sleepLatencyMinutes,
                nextAsleepMinutes: night.timeAsleepMinutes,
                isWeekend: calendar.isDateInWeekend(night.date),
                priorNightAsleepMinutes: priorAsleep[night.date],
                shortfallMinutes: night.sleepDebtMinutes,
                timeZoneIdentifier: night.timeZoneIdentifier
            )
        }
    }

    /// Long-term baselines for the vitals with enough history behind them to
    /// have one.
    ///
    /// Each signal carries its own thresholds and sample floors rather than
    /// sharing one generic tolerance: HRV swings twenty per cent night to
    /// night while a resting heart rate that moves five per cent has done
    /// something, and a single formula across both is tuned for neither.
    /// Signals whose windows are too thin still appear — an explicit "not
    /// enough yet" is the honest state, and hiding the row would leave the
    /// person wondering where respiratory rate went.
    func longTermSignals(window: LongTermResilience.Window) -> [LongTermResilience.Signal] {
        func points(_ value: @escaping (SleepNightFeatures) -> Double?) -> [LongTermResilience.Point] {
            recentNights.compactMap { night in
                value(night).map { LongTermResilience.Point(date: night.date, value: $0) }
            }
        }
        let specs: [(LongTermResilience.Spec, [LongTermResilience.Point])] = [
            (.restingHeartRate, points(\.restingHeartRate)),
            (.heartRateVariability, points(\.avgHRV)),
            (.respiratoryRate, points(\.avgRespiratoryRate)),
            (.sleepDuration, points { $0.timeAsleepMinutes })
        ]
        return specs.map { spec, values in
            LongTermResilience.measure(spec: spec, points: values, window: window)
        }
    }

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
        maxHR: Double,
        zoneProvenance: HRZoneProvenance,
        restingProvenance: RestingHRProvenance
    ) async -> (today: StrainScore, yesterday: StrainScore, hourly: [(date: Date, bpm: Double)]) {

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: .now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        async let todayTask = strain(
            in: DateInterval(start: todayStart, end: .now), restingHR: restingHR, maxHR: maxHR,
            zoneProvenance: zoneProvenance, restingProvenance: restingProvenance
        )
        async let yesterdayTask = strain(
            in: DateInterval(start: yesterdayStart, end: todayStart), restingHR: restingHR, maxHR: maxHR,
            zoneProvenance: zoneProvenance, restingProvenance: restingProvenance
        )

        let today = await todayTask
        let yesterday = await yesterdayTask

        let hourly = await healthRead("day.hourlyHeartRate", source: "heartRate", {
            try await healthKit.hourlyHeartRate(in: DateInterval(start: min(wakeTime, .now), end: .now))
        }) ?? []

        return (today, yesterday, hourly)
    }

    private func strain(
        in interval: DateInterval,
        restingHR: Double,
        maxHR: Double,
        zoneProvenance: HRZoneProvenance,
        restingProvenance: RestingHRProvenance
    ) async -> StrainScore {
        guard interval.duration > 0 else { return .zero }

        let energy = await healthRead("strain.energy", source: "activeEnergyBurned", {
            try await healthKit.sum(.activeEnergyBurned, unit: .kilocalorie(), in: interval)
        }) ?? nil
        let exercise = await healthRead("strain.exercise", source: "appleExerciseTime", {
            try await healthKit.sum(.appleExerciseTime, unit: .minute(), in: interval)
        }) ?? nil

        guard let result = await healthRead("strain.zones", source: "heartRate", {
            try await healthKit.heartRateZones(in: interval, restingHeartRate: restingHR, maxHeartRate: maxHR)
        }), !result.zones.isEmpty, result.coverage >= 0.4 else {
            // Thin heart-rate coverage — fall back to the energy estimate and
            // let the UI say so rather than presenting a confident wrong number.
            return .estimate(activeEnergyKcal: energy ?? 0, exerciseMinutes: exercise ?? 0)
        }

        return .compute(
            zoneMinutes: result.zones,
            activeEnergyKcal: energy,
            hasHeartRateCoverage: true,
            zoneProvenance: zoneProvenance,
            restingProvenance: restingProvenance
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
            // Said explicitly rather than inherited from a default. This is
            // the one question the flag exists to answer, and the answer is
            // already computed -- `presentation.isShowable` is what every
            // phone surface gates on.
            hasRecovery: context.recovery.presentation.isShowable,
            bodyBattery: context.bodyBattery.current,
            strain: context.strain.value,
            sleepPerformance: context.sleepNeed.performancePercent,
            sleepIntelligencePercent: context.sleepIntelligence.percent,
            sleepIntelligenceBand: context.sleepIntelligence.band.label,
            sleepIntelligenceVersion: context.sleepIntelligence.scoringVersion,
            isShiftWorkModeEnabled: preferences.isShiftWorkModeEnabled,
            // The same shortfall Today's arc shows, last night included.
            currentShortfallMinutes: context.shortfallNowMinutes
        )
        // The watch needs the confidence alongside the number so it can
        // decline to state one it cannot stand behind (V9 item 30).
        snapshot.recoveryConfidence = context.recovery.confidence.rawValue
        // Same reason, same rule: the glance surfaces lead with Sleep
        // Intelligence and need to know when not to state it.
        snapshot.sleepIntelligenceConfidence = context.sleepIntelligence.confidence.rawValue
        // Energy inherits Recovery's verdict; the wrist needs that too.
        snapshot.energyConfidence = context.bodyBattery.confidence.rawValue
        // The radar's own state, not `isActive` collapsed to a reassurance.
        // `!isActive` is true of a clear fortnight, of night four, and of a
        // phone that records sleep but no physiology; only the first of those
        // is "nothing unusual", and the watch and complications were showing
        // all three as "Typical".
        snapshot.bodySignalsState = context.healthRadar.stateShortLabel
        snapshot.bodySignalsLabel = context.healthRadar.stateHeadline

        // Autopilot and forecast are computed here for the same reason
        // badges are: both need the whole night history, and neither the
        // widget nor the watch has a HealthKit pipeline to rebuild it from.
        // The clock formatting happens here too -- see the snapshot fields'
        // own documentation for why it is not left to each extension.
        if let plan = context.tonight.autopilot {
            snapshot.tonightTargetLabel = plan.targetRangeLabel
            snapshot.tonightTargetNote = plan.sentence
            snapshot.tonightTargetNoteShort = plan.shortSentence
            snapshot.isTonightTargetHolding = plan.isHolding
        }
        // The times themselves come from the resolved episode, the same one
        // the phone's Tonight section, reminders and alarm use. The label
        // used to be the autopilot's range, which knew nothing of a manual
        // plan and could put a different bed on the wrist from the phone.
        // The wake alarm's recorded state, else the wake window's: the one
        // thing the wrist most needs to know at bedtime is whether anything
        // will wake them, and which kind of thing it is.
        let schedules = ScheduleStateStore()
        let wakeSlots: [(ScheduleStateStore.Slot, ScheduleReconciliation.Delivery)] = [
            (.wakeAlarm, .alarm),
            (.wakeWindow, .notification)
        ]
        snapshot.wakeStatusLine = ""
        for (slot, delivery) in wakeSlots {
            let entry = schedules.entry(slot)
            if let line = ScheduleReconciliation.statusLine(
                label: slot.label, delivery: delivery, status: entry.status,
                scheduledFor: entry.scheduledFor, now: .now,
                timeText: { $0.formatted(date: .omitted, time: .shortened) }
            ) {
                snapshot.wakeStatusLine = line
                break
            }
        }
        if let episode = tonightEpisode(for: context) {
            snapshot.tonightTargetLabel = episode.rangeLabel
            if episode.source == .manualPlan {
                let name = episode.planName.map { "Your plan \u{201C}\($0)\u{201D}." } ?? "Your plan."
                let short = episode.isFeasible
                    ? ""
                    : " \(SleepNightFeatures.formatMinutes(episode.shortfallMinutes)) short of tonight's need."
                snapshot.tonightTargetNote = name + short
                snapshot.tonightTargetNoteShort = episode.isFeasible
                    ? "Your plan"
                    : "\(SleepNightFeatures.formatMinutes(episode.shortfallMinutes)) short"
                snapshot.isTonightTargetHolding = false
            }
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

        // A nap in flight, so the watch's Smart Stack can raise the nap
        // surface while it matters and stop when it does not. The relevance
        // engine has always handled this case and been tested for it; the
        // production call site had nothing to tell it and passed `false`,
        // which made the whole path dead code on a real wrist.
        if let active = naps.activeNap {
            snapshot.napStartedAt = active.start
            snapshot.napTargetEnd = active.targetEnd
        }

        // Tonight's one question, so the watch can ask it without needing the
        // ranking engine, the journal history or `BehaviorTag` -- none of
        // which exist in that target. Behaviours already answered today are
        // excluded here rather than on the wrist, so the watch never shows a
        // question the phone would not.
        let answeredToday = behaviorAnswers(on: .now, nightKey: nil)
        if let question = AdaptiveJournal.question(
            observations: journalObservations(),
            activeExperimentTag: preferences.activeExperimentTag?.rawValue,
            pinnedTags: Set(BehaviorTag.allCases.filter(preferences.isTracked)),
            alreadyAnswered: Set(BehaviorTag.allCases.filter { answeredToday.state(for: $0) != .unknown })
        ) {
            snapshot.questionTag = question.tag.rawValue
            snapshot.questionText = question.tag.question
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

        snapshot.scoreLightMode = PersonalSetupStore.shared.value.scoreLight
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
    /// How long after a workout still reads as exertion rather than
    /// autonomic load.
    ///
    /// Was 30. Heart rate does not come back to a resting level that fast
    /// after anything but the lightest session, and this window now also
    /// defines the *baseline* (`DaytimeBaseline`), where the cost of being
    /// too short is the worse one: post-exercise readings raise what counts
    /// as usual, and an inflated baseline makes genuinely elevated days look
    /// normal. Ninety minutes covers an ordinary session's recovery with
    /// margin; the high-movement-hour filter below catches the rest.
    ///
    /// A judgement call, not a measurement -- stated here rather than left as
    /// a bare number.
    private static let postWorkoutBufferMinutes: TimeInterval = 90
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
    /// Today's movement, compared with the same weekday at the same hour.
    ///
    /// "Typical" is the median of the same clock window on the previous four
    /// matching weekdays. A median rather than a mean because one holiday or
    /// one marathon should not redefine an ordinary Tuesday, and four weeks
    /// rather than more because step habits drift.
    ///
    /// Any weekday with no step data contributes nothing rather than a zero:
    /// a day the phone spent on a desk is not a day with no walking, and
    /// averaging it in as zero is exactly the error `MovementContext` exists
    /// to avoid.
    private func refreshTodayMovement() async {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)

        // Same idiom as `strain(in:...)` above: a throw and a no-data result
        // both collapse to nil, and nil steps is a reportable state rather
        // than a failure -- it is what "movement is unknown" means.
        let todaySteps = await healthRead("activity.steps", source: "stepCount", {
            try await healthKit.sum(.stepCount, unit: .count(), in: DateInterval(start: startOfToday, end: now))
        }) ?? nil

        // The same *point in the day*, four same-weekdays back. The slice is
        // `MovementContext`'s to define -- see `comparableSlice`, which is
        // where the DST reasoning and the seam tests live.
        var priors: [Double] = []
        for weeksBack in 1...4 {
            guard let day = calendar.date(byAdding: .day, value: -7 * weeksBack, to: startOfToday),
                  let slice = MovementContext.comparableSlice(
                      of: day, matching: now, calendar: calendar
                  ) else { continue }
            let steps = await healthRead("activity.priorSteps", source: "stepCount", {
                try await healthKit.sum(.stepCount, unit: .count(), in: slice)
            }) ?? nil
            guard let steps else { continue }
            priors.append(steps)
        }

        // The other measures §27 names. Each is optional for the same reason
        // steps are: an absent reading is not a zero one, and the snapshot
        // omits what it did not get rather than reporting none of it.
        let interval = DateInterval(start: startOfToday, end: now)
        let exercise = await healthRead("activity.exercise", source: "appleExerciseTime", {
            try await healthKit.sum(.appleExerciseTime, unit: .minute(), in: interval)
        }) ?? nil
        let activeEnergy = await healthRead("activity.energy", source: "activeEnergyBurned", {
            try await healthKit.sum(.activeEnergyBurned, unit: .kilocalorie(), in: interval)
        }) ?? nil

        let typical = Statistics.median(priors).map { Int($0.rounded()) }
        todayMovement = MovementContext.snapshot(
            stepsSoFar: todaySteps.map { Int($0.rounded()) },
            typicalStepsByNow: typical,
            activeEnergyKcal: activeEnergy,
            exerciseMinutes: exercise,
            // Already deduplicated by `refreshTodayStress`, which runs first:
            // a run mirrored by a second app is one workout, not two.
            workoutCount: todayWorkouts.count,
            weekday: weekday,
            now: now
        )
    }

    /// §23. Runs after `refreshTodayStress` because it reuses exactly the
    /// exclusions that function already computed the coarse version of --
    /// workouts plus their buffer, and sleep -- and the same waking baseline
    /// the Physiological Load comparison is made against, so a window and a
    /// load reading can never be measured against different ideas of "your
    /// usual".
    ///
    /// The three series are asked for at five-minute bins rather than hourly.
    /// `HKStatisticsCollectionQuery` buckets inside its own store, so the
    /// finer request costs about what the hourly one does, and an hour is
    /// wider than most of the windows being looked for.
    private func refreshRestorativeWindows() async {
        guard DataEnvironment.current.isLive else {
            todayRestorativeWindows = []
            return
        }

        let calendar = Calendar.current
        let now = Date.now
        let dayStart = calendar.startOfDay(for: now)
        guard dayStart < now else { return }
        let interval = DateInterval(start: dayStart, end: now)

        let workouts = await healthRead("workouts", source: "workout", { try await healthKit.workouts(in: interval) }) ?? []
        let excluded = workouts.map {
            DateInterval(
                start: $0.startDate,
                end: $0.endDate.addingTimeInterval(Self.postWorkoutBufferMinutes * 60)
            )
        } + store.nights(inLast: 2).compactMap { night -> DateInterval? in
            guard night.wakeTime > night.bedtime else { return nil }
            return DateInterval(start: night.bedtime, end: night.wakeTime)
        }

        let bin = RestorativeWindow.binMinutes
        async let hrTask = try? healthKit.binnedHeartRate(in: interval, binMinutes: bin)
        async let energyTask = try? healthKit.binnedActiveEnergy(in: interval, binMinutes: bin)
        async let hrvTask = try? healthKit.binnedHeartRateVariability(in: interval, binMinutes: bin)

        let heartRate = await hrTask ?? []
        let energy = await energyTask ?? []
        let hrv = await hrvTask ?? []

        // The baseline is built to the start of today, not to now: a window
        // found this afternoon must not be compared against a median that
        // already contains it.
        guard let baseline = await wakingBaselines(endingAt: dayStart, calendar: calendar).heartRate
        else {
            todayRestorativeWindows = []
            return
        }

        func samples(_ series: [(date: Date, bpm: Double)]) -> [RestorativeWindow.Sample] {
            series.map { RestorativeWindow.Sample(date: $0.date, value: $0.bpm) }
        }

        todayRestorativeWindows = RestorativeWindow.windows(
            heartRate: samples(heartRate),
            activeEnergy: samples(energy),
            hrv: samples(hrv),
            baseline: baseline,
            excluded: excluded,
            calendar: calendar
        )
    }

    /// §25. The overnight series the inspector derives its layers from.
    ///
    /// One minute rather than the five `RestorativeWindow` asks for: that one
    /// looks for a settled half hour, this one has to place an event inside a
    /// twelve-minute window, and at five minutes there are not enough readings
    /// before an awakening to say what a rise would be a rise against.
    private func refreshAwakeningSeries() async {
        guard DataEnvironment.current.isLive, let night = store.latestNight else {
            awakeningSeries = AwakeningInspector.Series()
            return
        }
        guard night.wakeTime > night.bedtime else { return }
        let window = DateInterval(start: night.bedtime, end: night.wakeTime)
        let bin = AwakeningInspector.binMinutes

        async let hrTask = try? healthKit.binnedHeartRate(in: window, binMinutes: bin)
        async let energyTask = try? healthKit.binnedActiveEnergy(in: window, binMinutes: bin)
        async let breathTask = try? healthKit.binnedRespiratoryRate(in: window, binMinutes: bin)

        func samples(_ series: [(date: Date, bpm: Double)]) -> [AwakeningInspector.Sample] {
            series.map { AwakeningInspector.Sample(date: $0.date, value: $0.bpm) }
        }

        awakeningSeries = AwakeningInspector.Series(
            heartRate: samples(await hrTask ?? []),
            movement: samples(await energyTask ?? []),
            respiratory: samples(await breathTask ?? [])
        )
    }

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

        let workouts = await healthRead("workouts", source: "workout", { try await healthKit.workouts(in: interval) }) ?? []
        // One row per real session. A run recorded by the Watch and mirrored
        // by a third-party app arrives as two workouts with different UUIDs,
        // and the day's list showed it twice.
        //
        // The exclusion intervals below are deliberately built from the raw
        // `workouts`, not the deduplicated list: subtracting the same window
        // twice removes it once, so duplicates are harmless there, and using
        // the full set keeps the quiet-sampling windows correct even when
        // two records of one session disagree slightly at the edges.
        let summaries = workouts.map(WorkoutSummary.init)
        let keptIDs = Set(
            WorkoutDeduplicator
                .deduplicate(summaries.map(\.deduplicationCandidate))
                .map(\.id)
        )
        todayWorkouts = summaries
            .filter { keptIDs.contains($0.id) }
            .sorted { $0.start < $1.start }
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
        let hourlyEnergy = await healthRead("movement.hourlyEnergy", source: "activeEnergyBurned", { try await healthKit.hourlyActiveEnergy(in: interval) }) ?? []
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
        let waking = await wakingBaselines(endingAt: dayStart, calendar: calendar)

        todayStress = StressScore.compute(
            avgHeartRate: avgHR,
            avgHRV: avgHRV,
            hrBaseline: baseline.restingHeartRate7DayAvg,
            hrvBaseline: baseline.hrv7DayAvg,
            sampledMinutes: samplingIntervals.reduce(0) { $0 + $1.duration } / 60,
            baselineNightCount: baseline.sampleCount,
            // Wake to now. The quiet windows are carved out of exactly this,
            // so the two are the same denominator and the ratio means what
            // it says.
            elapsedWakingMinutes: interval.duration / 60,
            wakingHRBaseline: waking.heartRate?.bin(for: now, calendar: calendar)?.median,
            wakingHRVBaseline: waking.hrv?.bin(for: now, calendar: calendar)?.median
        )
    }

    /// This person's own waking heart rate and HRV, by time of day.
    ///
    /// Built from the same quiet windows today's reading is sampled from --
    /// workouts and the window after them, high-movement hours, and now sleep
    /// itself removed -- so both sides of the comparison are the same
    /// quantity. Sleep matters here and not for today's reading: today only
    /// samples from waking onward, but a fortnight of history is mostly
    /// nights, and a bin that swallowed them would be back to comparing
    /// waking readings against sleeping ones, which is the entire defect this
    /// replaces.
    ///
    /// Two binned queries per metric rather than a query per bin: HealthKit
    /// buckets in its own store, so a fortnight costs four statistics
    /// collections in total, not a hundred.
    private func wakingBaselines(
        endingAt end: Date,
        calendar: Calendar
    ) async -> (heartRate: DaytimeBaseline?, hrv: DaytimeBaseline?) {
        guard let start = calendar.date(
            byAdding: .day, value: -DaytimeBaseline.windowDays, to: end
        ), start < end else { return (nil, nil) }
        let window = DateInterval(start: start, end: end)

        let workouts = await healthRead("workouts", source: "workout", { try await healthKit.workouts(in: window) }) ?? []
        let workoutIntervals = workouts.map {
            DateInterval(
                start: $0.startDate,
                end: $0.endDate.addingTimeInterval(Self.postWorkoutBufferMinutes * 60)
            )
        }
        let hourlyEnergy = await healthRead("movement.hourlyEnergy", source: "activeEnergyBurned", { try await healthKit.hourlyActiveEnergy(in: window) }) ?? []
        let movementIntervals = hourlyEnergy
            .filter { $0.bpm >= Self.highMovementKcalPerHour }
            .map { DateInterval(start: $0.date, duration: 3600) }
        let sleepIntervals = store.nights(inLast: DaytimeBaseline.windowDays + 1)
            .compactMap { night -> DateInterval? in
                guard night.wakeTime > night.bedtime else { return nil }
                return DateInterval(start: night.bedtime, end: night.wakeTime)
            }

        let quiet = DateInterval.subtracting(
            workoutIntervals + movementIntervals + sleepIntervals, from: window
        )
        guard !quiet.isEmpty else { return (nil, nil) }

        func baseline(from series: [(date: Date, bpm: Double)]) -> DaytimeBaseline? {
            // An hourly bucket is kept only when its whole hour is quiet. A
            // bucket that straddles the end of a workout averages the tail of
            // it in, and there is no way to take that back out of a mean.
            let samples = series.compactMap { point -> DaytimeBaseline.Sample? in
                let hour = DateInterval(start: point.date, duration: 3600)
                guard quiet.contains(where: { $0.contains(hour.start) && $0.end >= hour.end })
                else { return nil }
                return DaytimeBaseline.Sample(date: point.date, value: point.bpm)
            }
            let built = DaytimeBaseline.build(samples: samples, calendar: calendar)
            return built.isEmpty ? nil : built
        }

        async let hrTask = try? healthKit.hourlyHeartRate(in: window)
        async let hrvTask = try? healthKit.hourlyHeartRateVariability(in: window)
        return (
            baseline(from: await hrTask ?? []),
            baseline(from: await hrvTask ?? [])
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
            insight: { [engine] band in
                engine.generate(
                    for: night, baseline: AppMockData.baseline, goalMinutes: goal, band: band
                )
            },
            history: history,
            goalMinutes: goal,
            yesterdayStrain: MockData.yesterdayStrain,
            todayStrain: MockData.todayStrain,
            hourlyHeartRate: MockData.hourlyHeartRate(wakeTime: night.wakeTime),
            maxHeartRate: 185,
            napMinutes: 0,
            bedtimeConsistencyMinutes: 38,
            age: preferences.age ?? 34,
            sex: preferences.biologicalSex,
            bodyMassIndex: preferences.bodyMassIndex,
            obligationWeekdays: preferences.obligationWeekdays,
            overnightHeartRate: MockData.overnightHeartRate(bedtime: night.bedtime, wakeTime: night.wakeTime)
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
        SleepSourceList.merged(stored: store.knownSleepSources(), writers: sleepWriters)
    }

    /// Every writer HealthKit reports for sleep, refreshed by
    /// `refreshSleepWriters()`. Empty until then, and in demo mode.
    private(set) var sleepWriters: [(name: String, bundleIdentifier: String)] = []

    /// Asks HealthKit which apps and devices have written sleep. Failure
    /// leaves the list as it was: the stored winners still populate the
    /// picker, which is what it showed before this existed.
    func refreshSleepWriters() async {
        guard DataEnvironment.current.isLive,
              let writers = await healthRead("sources.sleep", source: "sleepAnalysis", { try await healthKit.sleepSources() }) else { return }
        sleepWriters = writers
    }

    /// The one way a preferred sleep source is chosen, from either screen.
    ///
    /// Settings and Data Repair each had their own picker. Settings stored
    /// the bundle identifier and cleared the sync anchor so the choice
    /// re-arbitrated stored history; Data Repair cleared the identifier and
    /// only refreshed from the anchor, so the same choice made there applied
    /// to new nights alone. Both now call this.
    func selectSleepSource(named name: String?) async {
        let chosen = name.flatMap { $0.isEmpty ? nil : $0 }
        preferences.preferredSleepSourceName = chosen
        preferences.preferredSleepSourceBundleIdentifier = chosen.flatMap { chosen in
            knownSleepSources().first { $0.name == chosen }?.bundleIdentifier
        }
        // Re-arbitrate what is already stored, not only new nights.
        AnchorStore.clear()
        await refresh()
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
        store.importEvidenceHistory(archive.evidenceHistory ?? [])
        if var setup = archive.personalSetup, setup.isValid {
            setup.session = nil
            PersonalSetupStore.shared.value = setup
        }
        let restoredExperiments = experiments.importOutcomes(archive.experiments ?? [])
        let restoredSoundEvents = SoundEventStore().importEvents(archive.soundEvents ?? [])
        // A V3 archive has no observations. They import as nothing rather
        // than being reconstructed from `archive.journal`'s positive tags:
        // the legacy-tag path in `exposureState` already covers those, and
        // synthesising rows here would claim the archive recorded answers
        // it never held.
        let restoredObservations = behaviors.importObservations(archive.behaviorObservations ?? [])
        // The definitions, so the restored answers have names. Existing ones
        // win, the same rule every other importer here follows.
        CustomBehaviorStore.shared.importBehaviors(archive.customBehaviors ?? [])
        let restoredAlertness = AlertnessCheckStore().importSessions(archive.alertnessSessions ?? [])

        // The archive carries the goal the data was recorded against. Adopting
        // it matters: sleep debt, need and recovery are all measured against
        // the goal, so importing nights while keeping a different target would
        // silently rescore the entire history.
        if archive.goalMinutes > 0 {
            preferences.sleepGoalMinutes = archive.goalMinutes
        }
        if let restored = archive.preferences {
            preferences.age = restored.age
            if let sex = restored.biologicalSex.flatMap(DemographicBaseline.Sex.init(rawValue:)) {
                preferences.biologicalSex = sex
            }
            preferences.bodyMassIndex = restored.bodyMassIndex
            preferences.appearance = UserPreferences.AppearancePreference(
                rawValue: restored.appearance
            ) ?? .dark
            preferences.bedtimeRemindersEnabled = restored.bedtimeRemindersEnabled
            preferences.morningBriefEnabled = restored.morningBriefEnabled ?? false
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
            // Prefer the explicit mode; fall back to migrating the Bool so a
            // pre-V2 backup restores as the night shift it actually described.
            preferences.shiftWorkMode = restored.shiftWorkMode
                .flatMap(ShiftWorkMode.init(rawValue:))
                ?? .migrating(fromLegacyEnabled: restored.isShiftWorkModeEnabled ?? false)
            preferences.trackedBehaviorTagIdentifiers = restored.trackedBehaviorTagIdentifiers.map(Set.init)
            preferences.restoreActiveExperiment(
                tag: restored.activeExperimentTag.flatMap(BehaviorTag.init(rawValue:)),
                startDate: restored.experimentStartDate,
                hypothesis: restored.experimentHypothesis,
                primaryMetric: restored.experimentPrimaryMetric.flatMap(JournalCorrelator.Metric.init(rawValue:)),
                direction: restored.experimentDirection.flatMap(GuidedExperiment.Direction.init(rawValue:)),
                design: restored.experimentDesign.flatMap(ExperimentDesign.init(rawValue:)),
                seed: restored.experimentDesignSeed.map { UInt64(bitPattern: Int64($0)) }
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
            await reminders.schedule(
                bedtimes: tonightHorizon(nights: ReminderSchedule.horizonNights).map(\.bed)
            )
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
        if restoredAlertness > 0 {
            extras.append(restoredAlertness.pluralized("alertness check"))
        }
        if !extras.isEmpty {
            summary += " Also restored \(extras.joined(separator: ", "))."
        }
        // Counted from what reached disk. A restore that failed part-way
        // says so instead of reporting the archive's size as a success.
        let unsavedNights = archive.nights.count - nights
        let unsavedEpisodes = (archive.episodes ?? []).count - restoredEpisodes
        if unsavedNights > 0 || unsavedEpisodes > 0 {
            var failed: [String] = []
            if unsavedNights > 0 { failed.append(unsavedNights.pluralized("night")) }
            if unsavedEpisodes > 0 { failed.append(unsavedEpisodes.pluralized("sleep episode")) }
            summary += " \(failed.joined(separator: " and ")) could not be saved; the rest were restored."
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
    func deleteAllData() async -> Bool {
        guard !isErasing else { return false }
        isErasing = true
        defer { isErasing = false }
        storeGeneration += 1
        healthKit.stopObserving()
        healthKit.disableBackgroundDelivery()
        // Drain the in-flight query before clearing stores; it cannot repopulate
        // erased rows after this method returns.
        await refreshTask?.value
        TonightRoutineController.shared.stop()
        PersonalSetupStore.shared.clearAll()
        store.excludedNightKeys = []
        let alarmDeleted = WakeAlarm().cancel()
        ScheduleStateStore().clearAll()
        let nightsDeleted = store.deleteAll()
        let journalDeleted = journal.deleteAll()
        let behaviorsDeleted = behaviors.deleteAll()
        naps.deleteAll()
        experiments.deleteAll()
        SnoreStore.erasePersistedData()
        SoundEventStore.erasePersistedData()
        AlertnessCheckStore().deleteAll()
        CustomBehaviorStore.shared.deleteAll()
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
        reminders.cancelMorningBrief()
        preferences.resetForDataErasure()
        engine = Self.makeEngine(for: preferences.preferredEngine)

        state = .empty(reason: .noSleepData)
        recentNights = []
        recoveryHistory = [:]
        todayStress = nil
        todayWorkouts = []
        todayMovement = nil
        lastRecordedNightSet = nil
        cyclePeriodStarts = []
        todayLifestyleInsights = nil
        lastRefresh = nil
        WidgetCenter.shared.reloadAllTimelines()
        // Last, once the persisted data is gone: live holders -- a snore
        // session still listening, a screen's store with erased summaries in
        // memory -- stop or reload rather than writing them back.
        DataErasure.announce()

        return alarmDeleted
            && nightsDeleted
            && journalDeleted
            && behaviorsDeleted
            && snapshotDeleted
            && legacyStoreDeleted
            && temporaryExportsDeleted
    }

    /// Offers everything Zoon currently believes to the ledger. Most of the
    /// time nothing is written, which is the intended behaviour.
    ///
    /// Five engines, four kinds of evidence, one append-only history. What
    /// each of them contributes -- and, for the twin and the map, what is
    /// deliberately left out -- is argued in `Shared/EvidenceClaims.swift`;
    /// this only assembles the inputs.
    private func recordCurrentBeliefs() {
        recordAssociations()
        recordExperiments()

        // Change points, twin splits and the sleep map are pure functions of
        // `recentNights` and nothing else. With the same nights they cannot
        // produce a revision the ledger would keep, so running them again is
        // work with a guaranteed empty result -- and it is not cheap work:
        // the map bootstraps an interval per region, and the twin scans every
        // outcome for six lever/direction pairs. `hasMateriallyChanged`
        // suppresses the *write*; this suppresses the computation, on a path
        // that runs on the main actor at the end of every refresh.
        //
        // Keyed on the night set rather than its count: excluding one night
        // and gaining another leaves the count identical and the inputs
        // different.
        let nights = recentNights.map(\.nightKey).sorted()
        var hasher = Hasher()
        hasher.combine(nights)
        let fingerprint = hasher.finalize()
        guard fingerprint != lastRecordedNightSet else { return }
        lastRecordedNightSet = fingerprint

        recordChangePoints()
        recordObservedContrasts()
    }

    /// Hash of the night set the observation-tier claims were last computed
    /// over.
    ///
    /// In memory only. A cached decision about work that produces no output
    /// is not state worth persisting: a fresh launch recomputes once, writes
    /// nothing because nothing materially changed, and cannot be wrong the
    /// way a stale on-disk fingerprint could be.
    private var lastRecordedNightSet: Int?

    private func recordAssociations() {
        let observations = journalObservations()
        let correlator = JournalCorrelator()
        let findings = correlator.topFindingPerTag(from: observations, catalog: behaviorCatalog)
        for finding in findings {
            store.recordBelief(
                EvidenceLedger.Revision(
                    claimID: EvidenceLedger.Claim.behaviour(tag: finding.behavior.identifier).id,
                    recordedAt: .now,
                    status: status(for: finding),
                    headline: finding.plainSentence,
                    effect: finding.delta,
                    effectUnit: finding.metric.shortLabel,
                    uncertaintyLower: finding.confidenceIntervalLower,
                    uncertaintyUpper: finding.confidenceIntervalUpper,
                    sampleSize: finding.matchedPairCount,
                    windowStart: finding.pairs.map(\.date).min(),
                    windowEnd: finding.pairs.map(\.date).max(),
                    algorithmVersion: JournalCorrelator.algorithmVersion,
                    sourceFeature: finding.metric.rawValue,
                    provenance: "JournalCorrelator"
                )
            )
        }

        // The half offering beliefs cannot do. A finding that stopped being
        // produced said nothing, so its last "Association detected" stood
        // in the ledger indefinitely -- see `EvidenceLedger.retraction`.
        // Withdrawn as inconclusive when the comparison pool is still deep
        // enough that the engine looked and found nothing, as learning when
        // the pool itself has thinned below what a comparison needs.
        // Built from the catalogue, not from `BehaviorTag.allCases`. A custom
        // behaviour's association can be withdrawn for exactly the same
        // reasons a built-in's can, and keying this on the enum meant its
        // claim ID matched nothing, the `guard` below skipped it, and its
        // last "Association detected" would have stood in the ledger for
        // good -- the precise failure the retraction pass exists to prevent.
        let behaviorByClaimID = Dictionary(
            uniqueKeysWithValues: behaviorCatalog.analysable.map {
                (EvidenceLedger.Claim.behaviour(tag: $0.identifier).id, $0)
            }
        )
        let current = Set(findings.map { EvidenceLedger.Claim.behaviour(tag: $0.behavior.identifier).id })
        for latest in EvidenceLedger.associationsToRetract(
            in: store.evidenceHistory(), currentClaimIDs: current, provenance: "JournalCorrelator"
        ) {
            guard let behavior = behaviorByClaimID[latest.claimID] else { continue }
            let pairs = correlator.matchedPairCount(for: behavior, observations: observations)
            store.recordBelief(
                EvidenceLedger.retraction(
                    of: latest,
                    status: pairs >= JournalCorrelator.minimumMatchedPairs ? .inconclusive : .learning,
                    sampleSize: pairs
                )
            )
        }
    }

    /// The strongest claims the app can make, and the only ones the person
    /// declared in advance.
    private func recordExperiments() {
        for outcome in experiments.outcomes {
            store.recordBelief(EvidenceLedger.revision(for: outcome))
        }
    }

    /// One claim per metric, keyed by the metric rather than by the shift's
    /// date, so a re-dated shift revises the belief it already holds instead
    /// of starting a second history beside it.
    private func recordChangePoints() {
        for result in ChangePointDetector.detectAll(nights: recentNights) {
            store.recordBelief(EvidenceLedger.revision(for: result))
        }
    }

    /// Contrasts between groups of the person's own nights: weaker than a
    /// matched-pair association, and recorded as such.
    ///
    /// The configurations are fixed -- `ZoonTwin.levers` in both directions,
    /// and the single map `SleepMap.defaultConfiguration` names -- not
    /// whatever a screen last had selected. `EvidenceLedger.revision(for:)`
    /// drops any projection below `twinMinimumConfidence` on top of that, so
    /// most of these produce nothing on most days.
    private func recordObservedContrasts() {
        for lever in ZoonTwin.levers {
            for direction in [ZoonTwin.Direction.more, .less] {
                let projections = ZoonTwin.projectAll(
                    nights: recentNights, lever: lever, direction: direction
                )
                for projection in projections {
                    guard let revision = EvidenceLedger.revision(for: projection) else { continue }
                    store.recordBelief(revision)
                }
            }
        }

        let configuration = SleepMap.defaultConfiguration
        if let map = SleepMap.build(
            nights: recentNights,
            xAxis: configuration.x,
            yAxis: configuration.y,
            outcome: configuration.outcome
        ), let revision = EvidenceLedger.revision(for: map) {
            store.recordBelief(revision)
        }
    }

    /// A matched-pair finding is an association, never a tested result --
    /// only a pre-specified experiment earns `.supported`, and this engine
    /// does not run one. Low confidence is still learning.
    private func status(for finding: JournalCorrelator.Finding) -> EvidenceLedger.Status {
        switch finding.confidence {
        case .low: .learning
        case .moderate, .high: .associated
        }
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
            findings: JournalCorrelator().findings(from: journalObservations(), catalog: behaviorCatalog)
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
    /// - Parameter detail: the structured part, when the person confirmed one
    ///   in the review step. Defaults to `nil`, so every existing caller keeps
    ///   writing a plain yes or no, and `nil` on an update clears any detail
    ///   already stored -- see `BehaviorObservationStore.set`.
    func setBehavior(
        _ state: BehaviorObservationState,
        for behavior: BehaviorID,
        on date: Date,
        nightKey: String?,
        detail: BehaviorDetail? = nil
    ) {
        let key = nightKey ?? BehaviorObservationRecord.provisionalNightKey(for: date)
        behaviors.set(state, for: behavior, nightKey: key, detail: detail)
        // The legacy tag set is built-in only and stays that way. It exists
        // for the journal badge count, the archive export and the historical
        // fallback in `exposureState`, all three of which predate custom
        // behaviours; widening it would give it a second meaning rather than
        // preserve the one it has. A custom behaviour's answer lives in the
        // observation record, which is what every engine actually reads.
        guard let tag = behavior.builtIn else { return }
        let entry = journal.entryOrCreate(for: date, nightKey: nightKey)
        // The tag set tracks yes and nothing else, so an explicit no and
        // a cleared answer both remove it.
        if (state == .yes) != entry.contains(tag) {
            journal.toggle(tag, on: date, nightKey: nightKey)
        }
    }

    func setBehavior(
        _ state: BehaviorObservationState,
        for tag: BehaviorTag,
        on date: Date,
        nightKey: String?
    ) {
        setBehavior(state, for: tag.behaviorID, on: date, nightKey: nightKey)
    }

    /// Advances one behaviour through unanswered, yes, no, unanswered.
    /// - Returns: the state now recorded.
    @discardableResult
    func cycleBehavior(for behavior: BehaviorID, on date: Date, nightKey: String?) -> BehaviorObservationState {
        let current = behaviorAnswers(on: date, nightKey: nightKey)
            .state(forIdentifier: behavior.identifier)
        let next: BehaviorObservationState = switch current {
        case .unknown: .yes
        case .yes: .no
        case .no: .unknown
        }
        setBehavior(next, for: behavior, on: date, nightKey: nightKey)
        return next
    }

    @discardableResult
    func cycleBehavior(for tag: BehaviorTag, on date: Date, nightKey: String?) -> BehaviorObservationState {
        cycleBehavior(for: tag.behaviorID, on: date, nightKey: nightKey)
    }

    /// Answers every still-unanswered tracked behaviour `.no` for a day.
    /// - Returns: how many answers were recorded.
    @discardableResult
    func answerRemainingBehaviorsNo(on date: Date, nightKey: String?, candidates: [BehaviorTag]) -> Int {
        let key = nightKey ?? BehaviorObservationRecord.provisionalNightKey(for: date)
        return behaviors.answerRemainingNo(nightKey: key, candidates: candidates)
    }

    /// Every behaviour the analysis should consider: the built-ins plus
    /// whatever the person has invented.
    ///
    /// Read through the coordinator rather than each view reaching for the
    /// singleton, so a correlator call that forgets the catalogue is a
    /// visible omission at one layer instead of a silent one at nine.
    var behaviorCatalog: BehaviorCatalog { CustomBehaviorStore.shared.catalog }

    /// §22. The sensitivity curves this person has enough nights to support.
    ///
    /// Built on demand rather than stored: the inputs are `recentNights` and
    /// the nap store, both already in memory, and a cached copy would be one
    /// more thing that can go stale behind a night arriving late.
    ///
    /// Only the four dimensions carrying a real quantity are attempted --
    /// `SensitivityCurve` says why -- and each one is dropped entirely rather
    /// than shown thin when it cannot clear its own thresholds.
    func sensitivityCurves() -> [SensitivityCurve.Curve] {
        let nights = recentNights
        guard !nights.isEmpty else { return [] }

        /// A night's value for whichever outcome is being read. `Outcome` is
        /// `Hashable`, so this matches the presets themselves rather than
        /// dispatching on one of their strings.
        func outcome(_ night: SleepNightFeatures, _ kind: SensitivityCurve.Outcome) -> Double? {
            if kind == .sleepOnset { return night.sleepLatencyMinutes }
            if kind == .asleepMinutes { return night.timeAsleepMinutes }
            return Double(night.wakeCount)
        }

        func curve(
            dose: SensitivityCurve.Dose,
            outcome kind: SensitivityCurve.Outcome,
            value: (SleepNightFeatures) -> Double?
        ) -> SensitivityCurve.Curve? {
            let observations = nights.compactMap { night -> SensitivityCurve.Observation? in
                guard let dose = value(night), let result = outcome(night, kind) else { return nil }
                return SensitivityCurve.Observation(dose: dose, outcome: result)
            }
            return SensitivityCurve.build(dose: dose, outcome: kind, observations: observations)
        }

        /// Confirmed structured detail, by behaviour and night key.
        ///
        /// Built once for the whole call rather than fetched per night per
        /// curve: three curves over a history window would otherwise issue a
        /// fetch per night each, on a path several view bodies already call
        /// more than once per render -- the same reasoning
        /// `allAnswersByNightKey` documents.
        //
        // Written as a plain loop with explicit types on purpose. The
        // expression form -- a `Dictionary(uniqueKeysWithValues:)` over a map
        // that builds another `Dictionary` from tuples -- is the shape Swift's
        // type checker is worst at, and a single slow expression in a file
        // this size is paid on every build by everybody.
        let detailTags: [BehaviorTag] = [.caffeine, .caffeineLate, .hardTraining, .lateTraining]
        var detailsByBehavior: [String: [String: BehaviorDetail]] = [:]
        for tag in detailTags {
            var byNight: [String: BehaviorDetail] = [:]
            for row in behaviors.details(for: tag.behaviorID) where byNight[row.nightKey] == nil {
                byNight[row.nightKey] = row.detail
            }
            detailsByBehavior[tag.rawValue] = byNight
        }

        func detail(_ tag: BehaviorTag, for night: SleepNightFeatures) -> BehaviorDetail? {
            detailsByBehavior[tag.rawValue]?[night.nightKey]
        }

        /// The longest nap credited to the day before a night, and when it
        /// started. The longest rather than the total: two twenty-minute naps
        /// are not one forty-minute nap, and adding them would put a day in a
        /// band neither nap belongs to.
        func longestNap(before night: SleepNightFeatures) -> DateInterval? {
            napIntervals(before: night.date, timeZone: night.timeZone)
                .max { $0.duration < $1.duration }
        }

        var calendar = Calendar.current

        return [
            // Caffeine and workouts read straight off the night.
            curve(dose: SensitivityCurve.lateCaffeine, outcome: .sleepOnset) {
                // A night with no late caffeine recorded is a real zero here
                // *only* when Lifestyle Insights was on to record it. Without
                // it the field is absent, and absent is not none.
                $0.lateCaffeineMg
            },
            curve(dose: SensitivityCurve.workoutTiming, outcome: .sleepOnset) {
                $0.lastWorkoutHoursBeforeBed
            },
            // Naps come from the nap store, keyed to the day before the night.
            //
            // The two nap curves treat a napless day differently on purpose.
            // For duration, no nap is a real zero and is the control band --
            // that is the comparison the curve exists to make. For timing,
            // a napless day has no nap *hour* at all, and putting it in a band
            // would be inventing one, so it drops out.
            curve(dose: SensitivityCurve.napDuration, outcome: .asleepMinutes) { night in
                longestNap(before: night).map { $0.duration / 60 } ?? 0
            },
            curve(dose: SensitivityCurve.napTiming, outcome: .sleepOnset) { night in
                guard let nap = longestNap(before: night) else { return nil }
                calendar.timeZone = night.timeZone
                return Statistics.clockMinutes(nap.start, calendar: calendar) / 60
            },

            // §18. Three dimensions that only exist because observations now
            // carry a confirmed quantity, time and intensity -- see
            // `BehaviorDetail`. Each reads from rows somebody confirmed, so a
            // night with no recorded detail is absent rather than sorted into
            // a control band it was never measured into.
            curve(dose: SensitivityCurve.caffeineTiming, outcome: .sleepOnset) { night in
                guard let detail = detail(BehaviorTag.caffeine, for: night)
                    ?? detail(BehaviorTag.caffeineLate, for: night) else { return nil }
                calendar.timeZone = night.timeZone
                return detail.eventClockMinutes(calendar: calendar).map { $0 / 60 }
            },
            curve(dose: SensitivityCurve.caffeineDose, outcome: .sleepOnset) { night in
                (detail(BehaviorTag.caffeine, for: night)
                    ?? detail(BehaviorTag.caffeineLate, for: night))?.quantity
            },
            curve(dose: SensitivityCurve.workoutLoad, outcome: .asleepMinutes) { night in
                (detail(BehaviorTag.hardTraining, for: night)
                    ?? detail(BehaviorTag.lateTraining, for: night))?.intensity
            }
        ].compactMap { $0 }
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
            let primaryMetric = preferences.experimentPrimaryMetric ?? .sleepPerformance
            let direction = preferences.experimentDirection ?? .avoid
            let observations = journalObservations()
            // A controlled design is read against the schedule it was given,
            // not against the fortnight before it -- the schedule is the
            // whole reason the person chose it. `experimentSchedule` is
            // empty for `.beforeAfter`, which keeps the before/after summary.
            let schedule = preferences.experimentSchedule
            let outcome: SleepExperimentStore.Outcome?
            if preferences.experimentDesign?.isControlled == true, !schedule.isEmpty {
                outcome = GuidedExperiment.summarizeCrossover(
                    tag: tag,
                    hypothesis: preferences.experimentHypothesis,
                    primaryMetric: primaryMetric,
                    direction: direction,
                    schedule: schedule,
                    endDate: .now,
                    observations: observations
                )
            } else {
                outcome = GuidedExperiment.summarize(
                    tag: tag,
                    hypothesis: preferences.experimentHypothesis,
                    primaryMetric: primaryMetric,
                    direction: direction,
                    startDate: startDate,
                    endDate: .now,
                    observations: observations
                )
            }
            if let outcome {
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
        let findings = JournalCorrelator().topFindingPerTag(from: journalObservations(), catalog: behaviorCatalog)
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
            // The shortfall itself. This was `sleepNeed.debtMinutes`, which is
            // a 33% repayment slice, so the coach quoted a third of the debt
            // as the debt.
            sleepDebtMinutes: context?.shortfallNowMinutes?.rounded(to: 0),
            activeExperimentTag: preferences.activeExperimentTag?.label,
            // Percent-scaled findings only: the digest carries a percentage,
            // and a zero-baseline finding has none to give.
            causeFinderFindings: findings.filter(\.hasRelativeScale).map {
                CoachContextDigest.CorrelatorFinding(
                    behavior: $0.label,
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
                .map { outcome -> CoachContextDigest.TestedResult in
                    // The ledger's verdict, not the raw sign of the median
                    // difference: an inconclusive trial has no direction to
                    // hand Coach. See `EvidenceLedger.experimentStatus`.
                    let status = EvidenceLedger.experimentStatus(for: outcome)
                    return CoachContextDigest.TestedResult(
                        behavior: BehaviorTag(rawValue: outcome.tag)?.label ?? outcome.tag,
                        metric: outcome.metricLabel,
                        verdict: status.label,
                        isImprovement: status == .inconclusive ? nil : outcome.isImprovement
                    )
                },
            suggestedNextTest: ExperimentPlanner.next(
                observations: journalObservations(),
                // Built-ins only: the planner proposes guided experiments,
                // and an experiment is always on a behaviour Zoon ships.
                associatedTags: Set(findings.compactMap(\.tag)),
                settledTags: Set(experiments.outcomes.map(\.tag))
            )?.tag.label,
            tonightTarget: context?.tonight.autopilot?.sentence
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
            /// `EvidenceLedger.Status.label` -- "Supported", "Not supported"
            /// or "Inconclusive" -- so Coach reads the trial the way the
            /// ledger recorded it.
            let verdict: String
            /// Omitted for an inconclusive trial, which has no direction.
            let isImprovement: Bool?
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

// MARK: - HealthKit reads that keep why they failed

extension SleepDataCoordinator {
    /// See `HealthRead`: `nil` is still "unknown", but a denied permission
    /// or a locked device is recorded for Data Quality instead of looking
    /// like an empty night.
    func healthRead<T>(_ operation: String, source: String, _ read: () async throws -> T) async -> T? {
        await HealthRead.value(operation, source: source, read)
    }
}
