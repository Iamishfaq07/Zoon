import SwiftUI

/// Tab shell.
struct RootView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(BedtimeReminder.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = Tab(launchArgument: LaunchOptions.initialScreen?.tab
                                            ?? LaunchOptions.initialTab) ?? .today
    /// Set when a Control Center button asked for a specific screen.
    @State private var sleepPath = NavigationPath()
    /// Same, for screens pushed from the More tab.
    @State private var morePath = NavigationPath()

    enum Tab: Hashable {
        case today, sleep, trends, journal, more

        /// Maps `-zoonTab <name>` onto a tab. `nil` for anything unrecognised,
        /// so a typo in a CI script opens the default tab rather than failing.
        init?(launchArgument: String?) {
            switch launchArgument {
            case "today": self = .today
            case "sleep": self = .sleep
            case "trends": self = .trends
            case "journal": self = .journal
            case "more": self = .more
            default: return nil
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.heart.fill") }
                .tag(Tab.today)

            SleepTabView(path: $sleepPath)
                .tabItem { Label("Sleep", systemImage: "moon.stars.fill") }
                .tag(Tab.sleep)

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)

            JournalView()
                .tabItem { Label("Journal", systemImage: "square.and.pencil") }
                .tag(Tab.journal)

            MoreView(path: $morePath)
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(Tab.more)
        }
        .tint(Theme.Metric.sleep)
        // Dark-committed rather than adaptive: the palette is built for a dark
        // bedroom, and a half-translated light variant would look worse than
        // either done properly.
        .preferredColorScheme(.dark)
        .task {
            await coordinator.start()
            await refreshReminders()
        }
        .onAppear {
            // A launch argument is consumed once, on appear. It is not routed
            // through DeepLink's shared storage, which is for cross-process
            // hand-off from an extension and would outlive this launch.
            if let screen = LaunchOptions.initialScreen { push(screen) }
            consumeDeepLink()
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
        guard preferences.bedtimeRemindersEnabled,
              let bedtime = coordinator.state.context?.targetBedtime()
        else {
            if !preferences.bedtimeRemindersEnabled { reminders.cancel() }
            return
        }
        await reminders.schedule(bedtime: bedtime)
    }

    private func consumeDeepLink() {
        guard let destination = DeepLink.consume() else { return }
        push(destination)
    }

    /// Selects the owning tab and pushes the screen onto its stack.
    private func push(_ destination: DeepLink.Destination) {
        switch destination {
        case .soundscapes, .nap, .sleepDetail:
            selection = .sleep
            sleepPath = NavigationPath()
            sleepPath.append(destination)
        case .report, .settings, .badges:
            selection = .more
            morePath = NavigationPath()
            morePath.append(destination)
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
                VStack(spacing: Theme.stackSpacing) {
                    BedtimeCountdownCard().entrance(0)

                    NavigationLink {
                        SoundscapeView()
                    } label: {
                        toolRow(
                            "Sleep Sounds",
                            detail: "Generated on device — rain, waves, noise",
                            symbol: "waveform",
                            tint: Theme.Metric.battery
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .entrance(1)

                    NavigationLink {
                        NapView()
                    } label: {
                        toolRow(
                            "Nap",
                            detail: "Track a nap and credit it against tonight's need",
                            symbol: "powersleep",
                            tint: Theme.Metric.strain
                        )
                    }
                    .buttonStyle(PressableStyle())
                    .entrance(2)

                    if let context = coordinator.state.context {
                        Divider().overlay(Theme.cardStroke).padding(.vertical, 4)
                        SleepNeedCard(need: context.sleepNeed).entrance(3)
                        NavigationLink {
                            SleepDetailView(context: context)
                        } label: {
                            toolRow(
                                "Last night in full",
                                detail: context.night.formattedTimeAsleep,
                                symbol: "chart.xyaxis.line",
                                tint: Theme.Metric.sleep
                            )
                        }
                        .buttonStyle(PressableStyle())
                        .entrance(4)
                        ChronotypeCard(chronotype: context.chronotype).entrance(5)
                        if let clock = context.bodyClock {
                            BodyClockCard(
                                bodyClock: clock,
                                plannedBedtime: context.targetBedtime()
                            )
                            .entrance(6)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: DeepLink.Destination.self) { destination in
                switch destination {
                case .soundscapes: SoundscapeView()
                case .nap: NapView()
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
                case .report, .settings, .badges: EmptyView()
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
