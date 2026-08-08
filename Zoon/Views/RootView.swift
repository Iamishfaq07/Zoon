import SwiftUI

/// Tab shell.
struct RootView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Tab = .today
    /// Set when a Control Center button asked for a specific screen.
    @State private var sleepPath = NavigationPath()

    enum Tab: Hashable {
        case today, sleep, trends, journal, more
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

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(Tab.more)
        }
        .tint(Theme.Metric.sleep)
        // Dark-committed rather than adaptive: the palette is built for a dark
        // bedroom, and a half-translated light variant would look worse than
        // either done properly.
        .preferredColorScheme(.dark)
        .task { await coordinator.start() }
        .onAppear(perform: consumeDeepLink)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Controls launch the app rather than acting in place (an extension
            // can't start audio), so the destination is picked up here.
            consumeDeepLink()
            // Background delivery is best-effort — HealthKit clamps sleep updates
            // to roughly hourly and defers further under low power — so returning
            // to the app is when the user most expects fresh data.
            Task { await coordinator.refresh() }
        }
    }

    private func consumeDeepLink() {
        guard let destination = DeepLink.consume() else { return }
        selection = .sleep
        sleepPath = NavigationPath()
        sleepPath.append(destination)
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
                    BedtimeCountdownCard()

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
                    .buttonStyle(.plain)

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
                    .buttonStyle(.plain)

                    if let context = coordinator.state.context {
                        Divider().overlay(Theme.cardStroke).padding(.vertical, 4)
                        SleepNeedCard(need: context.sleepNeed)
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
                        .buttonStyle(.plain)
                        ChronotypeCard(chronotype: context.chronotype)
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
                }
            }
        }
    }

    private func toolRow(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.label(15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }
}

#Preview("Root") {
    RootView().zoonPreviewEnvironment()
}
