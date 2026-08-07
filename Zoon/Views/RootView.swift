import SwiftUI

/// Tab shell.
struct RootView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Sleep", systemImage: "moon.stars.fill") }

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task {
            await coordinator.start()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Refresh on foreground. Background delivery is best-effort — Apple
            // clamps sleep updates to roughly hourly and defers them further under
            // low power — so returning to the app is the moment the user most
            // expects fresh data.
            if newPhase == .active {
                Task { await coordinator.refresh() }
            }
        }
    }
}

#Preview("Root") {
    RootView()
        .zoonPreviewEnvironment()
}
