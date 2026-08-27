import CoreSpotlight
import SwiftUI

/// Tab shell.
struct RootView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(BedtimeReminder.self) private var reminders
    @Environment(GlobalPresentation.self) private var presentation
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = Tab(launchArgument: LaunchOptions.initialScreen?.tab
                                            ?? LaunchOptions.initialTab) ?? .today
    /// Set when a Control Center button asked for a specific screen.
    @State private var sleepPath = NavigationPath()
    /// Owned here rather than injected: this is the only place that re-arms
    /// the wake schedule, and `WakeAlarm` holds no state worth sharing --
    /// AlarmKit itself is the store of record for what's scheduled.
    @State private var wakeAlarm = WakeAlarm()

    /// Today, Sleep, Insights, Coach — Journal and Settings/More moved off
    /// the tab bar entirely (see `GlobalPresentation`), which is what frees
    /// the fourth slot for Coach instead of splitting it across a fifth tab.
    enum Tab: Hashable {
        case today, sleep, trends, coach

        /// Maps `-zoonTab <name>` onto a tab. `nil` for anything unrecognised
        /// -- including "journal" and "more", which are still valid
        /// `-zoonTab` values for screenshot capture but now open a sheet
        /// rather than select a tab; `RootView.onAppear` handles those
        /// directly rather than through this initializer, so a typo or one
        /// of those two names both fall back to the default tab here without
        /// otherwise failing.
        init?(launchArgument: String?) {
            switch launchArgument {
            case "today": self = .today
            case "sleep": self = .sleep
            case "trends": self = .trends
            case "coach": self = .coach
            default: return nil
            }
        }
    }

    var body: some View {
        @Bindable var bindablePresentation = presentation

        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.heart.fill") }
                .tag(Tab.today)

            SleepTabView(path: $sleepPath)
                .tabItem { Label("Sleep", systemImage: "moon.stars.fill") }
                .tag(Tab.sleep)

            TrendsView()
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)

            CoachTabView()
                .tabItem { Label("Coach", systemImage: "sparkles") }
                .tag(Tab.coach)
        }
        .tint(Theme.Metric.sleep)
        // System/Dark/Light, from Settings — `nil` for System lets SwiftUI
        // follow the device setting. `Theme`'s core surface tokens
        // (background, heroGlow, cardStroke, cardFill) are trait-adaptive,
        // so this is what actually switches the whole app's appearance
        // rather than just unlocking a toggle that used to do nothing.
        .preferredColorScheme(preferences.appearance.colorScheme)
        .sheet(isPresented: $bindablePresentation.showingJournal) {
            JournalView()
        }
        .sheet(isPresented: $bindablePresentation.showingMore) {
            MoreView(path: $bindablePresentation.morePath)
        }
        .task {
            await coordinator.start()
            await refreshReminders()
        }
        .onAppear {
            // A launch argument is consumed once, on appear. It is not routed
            // through DeepLink's shared storage, which is for cross-process
            // hand-off from an extension and would outlive this launch.
            if let screen = LaunchOptions.initialScreen {
                push(screen)
            } else if LaunchOptions.initialTab == "more" {
                // The one `-zoonTab` value that is neither a real `Tab` case
                // nor a valid `DeepLink.Destination` (unlike "journal", which
                // is both a tab name historically and a Destination case, so
                // it already flows through `push(_:)` below).
                presentation.presentMore()
            }
            consumeDeepLink()
            SpotlightIndexer.indexDestinations()
        }
        // Pushed directly rather than routed through `DeepLink.pending`: that
        // store exists for cross-process hand-off from an extension, and a
        // Spotlight tap is delivered straight to this process. Writing it
        // there would risk the pending value outliving the launch that asked
        // for it.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard
                let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                let destination = SpotlightIndexer.destination(forSearchableItemIdentifier: identifier)
            else { return }
            push(destination)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Controls launch the app rather than acting in place (an extension
            // can't start audio), so the destination is picked up here.
            consumeDeepLink()
            // Background delivery is best-effort — HealthKit clamps sleep updates
            // to roughly hourly and defers further under low power — so returning
            // to the app is when the user most expects fresh data.
            Task {
                await coordinator.refresh()
                await refreshReminders()
            }
        }
    }

    /// Re-arms the nightly reminders against the current sleep need.
    ///
    /// Runs on every activation rather than once: the target bedtime moves
    /// with sleep debt and yesterday's strain, so a reminder scheduled a week
    /// ago would be firing at last week's bedtime.
    private func refreshReminders() async {
        await reminders.refreshAuthorization()
        // `focusSilencesBedtimeNudges` is checked here as well as in the
        // filter itself: without it, opening the app during a Focus would
        // re-arm the very notifications the Focus just cancelled, and the
        // setting would appear to do nothing.
        guard preferences.bedtimeRemindersEnabled,
              !preferences.focusSilencesBedtimeNudges,
              let bedtime = coordinator.state.context?.targetBedtime()
        else {
            if !preferences.bedtimeRemindersEnabled || preferences.focusSilencesBedtimeNudges {
                reminders.cancel()
            }
            return
        }
        await reminders.schedule(bedtime: bedtime)

        // Wake window rides on the same authorization and the same body-clock
        // data, but is its own toggle — someone might want the bedtime nudge
        // without a second alarm layered on top of the one they already use.
        guard preferences.smartWakeEnabled,
              let wakeTime = coordinator.state.context?.bodyClock?.window(for: .now)?.end
        else {
            if !preferences.smartWakeEnabled {
                reminders.cancelWakeWindow()
                wakeAlarm.cancel()
            }
            return
        }
        await reminders.scheduleWakeWindow(wakeTime: wakeTime, leadMinutes: Self.wakeWindowLeadMinutes)

        // The notification and the alarm are two halves of one idea, not
        // duplicates: the notification fires at the *start* of the window as a
        // silent nudge that catches someone already stirring, and the alarm
        // rings at the *end* of it as the backstop that actually wakes anyone
        // still asleep. Scheduling the alarm at the window's start instead
        // would just be an alarm 20 minutes early.
        if preferences.wakeAlarmEnabled {
            await wakeAlarm.schedule(at: wakeTime)
        } else {
            wakeAlarm.cancel()
        }
    }

    /// How early the wake-window notification can fire relative to the usual
    /// wake time. Wider than the bedtime lead — a wake window is trying to
    /// straddle a plausible light-sleep stretch, not just give advance notice.
    private static let wakeWindowLeadMinutes = 20

    private func consumeDeepLink() {
        guard let destination = DeepLink.consume() else { return }
        push(destination)
    }

    /// Routes a destination to the tab that owns it, or to the appropriate
    /// global sheet for the two screens (Journal, More/Settings) that no
    /// longer live on the tab bar.
    private func push(_ destination: DeepLink.Destination) {
        switch destination {
        case .soundscapes, .nap, .sleepDetail, .breathing, .snoreCheck, .bodyClock:
            selection = .sleep
            sleepPath = NavigationPath()
            sleepPath.append(destination)
        case .report, .settings, .badges, .evidence, .patterns, .sensorTruth:
            presentation.presentMore(pushing: destination)
        case .journal:
            presentation.presentJournal()
        }
    }
}

/// Sleep tab: last night's detail, plus the tools you use at bedtime.
struct SleepTabView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                // Last Night leads -- the redesign spec's reversal of the old
                // order, where five tool rows sat between opening the tab and
                // seeing anything about how you actually slept. Tools move to
                // a horizontal strip below, still one tap away, not first.
                VStack(spacing: Theme.stackSpacing) {
                    if let context = coordinator.state.context {
                        SleepNeedCard(need: context.sleepNeed).entrance(0)
                        // A live hypnogram preview, not a generic icon+label
                        // row -- the redesign spec's complaint was that this
                        // tab's interactive content sat one tap behind a
                        // list row indistinguishable from "Past Nights"
                        // below it. Reuses `SleepSummaryStrip` as-is (already
                        // doing exactly this on Today) rather than a second,
                        // parallel implementation of the same preview.
                        SleepSummaryStrip(context: context).entrance(1)
                        NavigationLink {
                            NightHistoryView()
                        } label: {
                            toolRow(
                                "Past Nights",
                                detail: coordinator.recentNights.isEmpty
                                    ? "Nothing recorded yet"
                                    : "\(coordinator.recentNights.count) night\(coordinator.recentNights.count == 1 ? "" : "s") on file",
                                symbol: "calendar",
                                tint: Theme.Metric.hrv
                            )
                        }
                        .buttonStyle(PressableStyle())
                        .entrance(1)
                        ChronotypeCard(chronotype: context.chronotype).entrance(2)
                        if let clock = context.bodyClock {
                            BodyClockCard(
                                bodyClock: clock,
                                plannedBedtime: context.targetBedtime(),
                                actualBedtime: context.night.bedtime,
                                actualWakeTime: context.night.wakeTime
                            )
                            .entrance(3)
                        }
                    }

                    // BedtimeCountdownCard moved to Today: showing the exact
                    // same card on both tabs was redundant rather than
                    // reinforcing, and Sleep's job here is "how did I sleep"
                    // and "what tools do I have," not "when should I go to
                    // bed" -- that's a today/planning question.
                    SleepToolsStrip().entrance(4)
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .zoonGlobalToolbar()
            .navigationDestination(for: DeepLink.Destination.self) { destination in
                switch destination {
                case .soundscapes: SoundscapeView()
                case .nap: NapView()
                case .breathing: BreathingView()
                case .snoreCheck: SnoreCheckView()
                case .bodyClock: BodyClockView()
                case .sleepDetail:
                    if let context = coordinator.state.context {
                        SleepDetailView(context: context)
                    } else {
                        ContentUnavailableView(
                            "No night yet",
                            systemImage: "moon.zzz",
                            description: Text("Zoon hasn't read a night of sleep yet.")
                        )
                    }
                // Owned by the More tab; unreachable here, but the switch has
                // to stay exhaustive.
                case .report, .settings, .badges, .evidence, .patterns, .sensorTruth: EmptyView()
                // Owned by the Journal tab; never pushed onto this stack.
                case .journal: EmptyView()
                }
            }
        }
    }

    private func toolRow(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(Theme.text(17))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.label(15, weight: .semibold))
                Text(detail)
                    .font(Theme.text(11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }
}

#Preview("Root") {
    RootView().zoonPreviewEnvironment()
}
