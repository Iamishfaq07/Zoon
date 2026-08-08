import SwiftUI
import UniformTypeIdentifiers

/// Report, settings, export, and everything that doesn't earn a tab.
struct MoreView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps

    /// Owned by RootView so a launch argument or a Control Center intent can
    /// push onto it.
    @Binding var path: NavigationPath

    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    StreakCard(nights: coordinator.recentNights, goalMinutes: preferences.sleepGoalMinutes)
                        .entrance(0)

                    navRow("Weekly Report", "Your week in review", "calendar.badge.clock", Theme.Metric.recoveryHigh) {
                        ReportView()
                    }
                    .entrance(1)
                    navRow("Settings", "Goal, engine, privacy", "gearshape.fill", .secondary) {
                        SettingsView()
                    }
                    .entrance(2)

                    dataCard.entrance(3)
                    privacyCard.entrance(4)
                    aboutCard.entrance(5)
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: DeepLink.Destination.self) { destination in
                switch destination {
                case .report: ReportView()
                case .settings: SettingsView()
                // Owned by the Sleep tab.
                case .soundscapes, .nap, .sleepDetail: EmptyView()
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: .constant(importMessage != nil)) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func navRow<Destination: View>(
        _ title: String, _ detail: String, _ symbol: String, _ tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.label(15, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .glassCard()
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Your Data",
                subtitle: "Local-first has to mean portable. Take it with you whenever you like.",
                systemImage: "square.and.arrow.up"
            )

            if let url = exportURL {
                ShareLink(item: url) {
                    actionRow("Share export", "Ready — tap to send", "square.and.arrow.up.fill", Theme.Metric.battery)
                }
                .buttonStyle(.plain)
            }

            Button {
                buildExport(json: true)
            } label: {
                actionRow("Export as JSON", "Complete backup, re-importable", "doc.badge.gearshape", Theme.Metric.sleep)
            }
            .buttonStyle(.plain)

            Button {
                buildExport(json: false)
            } label: {
                actionRow("Export as CSV", "One row per night, opens in any spreadsheet", "tablecells", Theme.Metric.strain)
            }
            .buttonStyle(.plain)

            Button {
                isImporting = true
            } label: {
                actionRow("Import a backup", "Restore nights, journal, and naps", "square.and.arrow.down", Theme.Metric.hrv)
            }
            .buttonStyle(.plain)
        }
        .glassCard()
    }

    private func actionRow(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(13, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func buildExport(json: Bool) {
        do {
            let url: URL
            if json {
                let archive = DataExporter.archive(
                    nights: coordinator.recentNights,
                    journal: coordinator.journal.allEntries(),
                    naps: naps.naps,
                    goalMinutes: preferences.sleepGoalMinutes
                )
                url = try DataExporter.writeTemporary(
                    try DataExporter.jsonData(archive),
                    filename: DataExporter.defaultFilename(extension: "json")
                )
            } else {
                let csv = DataExporter.csv(nights: coordinator.recentNights)
                url = try DataExporter.writeTemporary(
                    Data(csv.utf8),
                    filename: DataExporter.defaultFilename(extension: "csv")
                )
            }
            exportURL = url
            Haptics.success()
        } catch {
            importMessage = "Couldn't build the export: \(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // Files chosen through the picker live outside the sandbox; without
            // the security scope the read silently returns nothing.
            guard url.startAccessingSecurityScopedResource() else {
                importMessage = "Couldn't open that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let archive = try DataExporter.decode(try Data(contentsOf: url))
            Task {
                let summary = await coordinator.importArchive(archive)
                importMessage = summary
                Haptics.success()
            }
        } catch {
            importMessage = error.localizedDescription
        }
    }

    // MARK: - Static cards

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Privacy", systemImage: "lock.shield.fill")
            privacyRow("wifi.slash", "No network calls",
                       "Zoon contains no networking code. Your data can't leave because there's nowhere for it to go.")
            privacyRow("iphone", "Processed on device",
                       "Every score, insight, and sound is computed locally.")
            privacyRow("eye.slash", "Read-only Health access",
                       "Zoon requests read permission only. It can never write to your Health data.")
            privacyRow("person.crop.circle.badge.xmark", "No account, no analytics",
                       "No sign-in, no telemetry, no third-party SDKs.")
        }
        .glassCard()
    }

    private func privacyRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Metric.recoveryHigh)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zoon")
                .font(Theme.label(15, weight: .bold))
            Text("“Zoon” means moon in Kashmiri.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(SleepInsight.disclaimer)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

/// Streaks and milestones.
///
/// Gamification kept deliberately modest: a streak counter and a handful of
/// milestones, no badges, no levels, no notifications nagging you to protect a
/// number. A streak that punishes you for one bad night is actively harmful in a
/// sleep app — the entire point is that some nights are bad and that's data, not
/// failure.
struct StreakCard: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    private var currentStreak: Int {
        var count = 0
        for night in nights.reversed() {
            guard night.timeAsleepMinutes >= goalMinutes else { break }
            count += 1
        }
        return count
    }

    private var bestStreak: Int {
        var best = 0, running = 0
        for night in nights {
            if night.timeAsleepMinutes >= goalMinutes {
                running += 1
                best = max(best, running)
            } else {
                running = 0
            }
        }
        return best
    }

    private var consistencyDays: Int {
        nights.suffix(30).filter { $0.timeAsleepMinutes >= goalMinutes }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            stat("\(currentStreak)", "night streak", Theme.Metric.recoveryHigh, "flame.fill")
            divider
            stat("\(bestStreak)", "personal best", Theme.Metric.sleep, "trophy.fill")
            divider
            stat("\(consistencyDays)/30", "goal met", Theme.Metric.battery, "checkmark.seal.fill")
        }
        .glassCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.cardStroke)
            .frame(width: 1, height: 34)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color, _ symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(tint)
            Text(value)
                .font(Theme.numeral(20))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Countdown to the bedtime that would hit your goal.
struct BedtimeCountdownCard: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    /// Computed by `DayContext` so the reminder notification and this card can
    /// never disagree about when bedtime is.
    private var targetBedtime: Date? {
        coordinator.state.context?.targetBedtime()
    }

    var body: some View {
        if let target = targetBedtime {
            let remaining = target.timeIntervalSince(.now)

            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Tonight's bedtime", systemImage: "bed.double.fill")

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(target, format: .dateTime.hour().minute())
                        .font(Theme.numeral(32))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Metric.sleep)

                    if remaining > 0 {
                        Text("in \(formattedRemaining(remaining))")
                            .font(Theme.label(13))
                            .foregroundStyle(.secondary)
                    } else {
                        StatusPill(text: "Wind down now", systemImage: "moon.fill", tint: Theme.Metric.temperature)
                    }
                }

                Text(remaining > 0
                     ? "Being asleep by then hits your full sleep need for tomorrow."
                     : "You're past the ideal bedtime. Going now still recovers most of it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }

    private func formattedRemaining(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

#Preview("More") {
    MoreView(path: .constant(NavigationPath())).zoonPreviewEnvironment()
}

#Preview("Streaks") {
    ScrollView {
        StreakCard(nights: MockData.history, goalMinutes: 420)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
