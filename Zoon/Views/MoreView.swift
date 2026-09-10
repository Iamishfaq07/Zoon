import SwiftUI
import UniformTypeIdentifiers

/// Report, settings, export, and everything that doesn't earn a tab.
struct MoreView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps
    @Environment(\.dismiss) private var dismiss

    /// Owned by `GlobalPresentation` so a launch argument or a Control Center
    /// intent can push onto it before the sheet even opens.
    @Binding var path: NavigationPath

    @State private var setup = PersonalSetupStore.shared
    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var encryptBackup = false
    @State private var archivePassphrase = ""
    @State private var pendingArchive: DataExporter.Archive?
    @State private var showingRestorePreview = false
    @State private var restoring = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    if !setup.value.scoreLight {
                        StreakCard(nights: coordinator.recentNights, goalMinutes: preferences.sleepGoalMinutes).entrance(0)
                    }

                    sectionLabel("This week")
                    navRow("Tonight", "Breathing, saved sounds and your schedule", "moon.stars.fill", Theme.Metric.sleep) { TonightRoutineView() }
                    navRow("Badges", "What you've earned so far", "hexagon.fill", Theme.Metric.recoveryMid) {
                        AchievementsView()
                    }
                    navRow("Weekly Report", "Your week in review", "calendar.badge.clock", Theme.Metric.recoveryHigh) {
                        ReportView()
                    }
                    navRow("Settings", "Goal, engine, privacy, replay first night", "gearshape.fill", .secondary) {
                        SettingsView()
                    }

                    sectionLabel("Later")
                    navRow("Repair sleep data", "Check coverage and manage local corrections", "wrench.and.screwdriver", Theme.Metric.sleep) { DataRepairView() }
                    navRow("Learn", "Sleep science, in plain language", "book.pages.fill", Theme.Metric.sleep) {
                        ArticlesView()
                    }
                    navRow("What Zoon knows", "Every claim, ranked by how it was found",
                            "checkmark.seal.fill", Theme.Metric.recoveryHigh) {
                        EvidenceView()
                    }
                    navRow("Your patterns", "Where your good nights sit, and tomorrow's range",
                            "square.grid.3x3.fill", Theme.Metric.sleep) {
                        PatternsView()
                    }
                    navRow("How well Zoon knows you", "Which parts are settled, and which are still forming",
                            "square.stack.3d.up.fill", Theme.Metric.hrv) {
                        ModelHealthView()
                    }
                    navRow("Personal learning", "Resilience, light response and alertness checks",
                            "sparkles.rectangle.stack.fill", Theme.Family.sleep) {
                        PersonalLearningView()
                    }
                    navRow("Sleep fingerprint", "Your recent sleep signature at a glance",
                            "circle.hexagongrid.fill", Theme.Family.recovery) {
                        SleepFingerprintView()
                    }
                    navRow("Sleep eras", "Stable stretches and meaningful shifts over time",
                            "timeline.selection", Theme.Family.sleep) {
                        SleepErasView()
                    }
                    navRow("Chart builder", "Ask for a transparent local chart",
                            "chart.xyaxis.line", Theme.Family.sleep) {
                        ChartBuilderView()
                    }
                    navRow("Voice journal", "Speak a note and review the transcript",
                            "mic.circle.fill", Theme.Family.sleep) {
                        VoiceJournalView()
                    }
                    navRow("Custom behaviours", "Track signals unique to your routine",
                            "plus.circle.fill", Theme.Family.sleep) {
                        CustomBehaviorsView()
                    }
                    navRow("Clinician Report", "7/30/90-day PDF summary to share", "doc.text.fill", Theme.Metric.hrv) {
                        ClinicianReportView()
                    }

                    dataCard.entrance(5)
                    privacyCard.entrance(6)
                    aboutCard.entrance(7)
                }
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sheet-presented from every tab now rather than a tab of its
                // own — same reasoning as JournalView's Done button.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: DeepLink.Destination.self) { destination in
                switch destination {
                case .report: ReportView()
                case .settings: SettingsView()
                case .badges: AchievementsView()
                case .evidence: EvidenceView()
                case .patterns: PatternsView()
                case .sensorTruth: SensorTruthView()
                // Owned by the Sleep tab.
                case .soundscapes, .nap, .sleepDetail, .breathing, .snoreCheck, .bodyClock: EmptyView()
                // Presented as its own sheet from GlobalPresentation, not
                // reachable through this stack.
                case .journal: EmptyView()
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json]
            ) { result in
                handleImport(result)
            }
            .confirmationDialog("Restore this backup?", isPresented: $showingRestorePreview, titleVisibility: .visible) {
                Button("Restore and merge") {
                    guard let archive = pendingArchive else { return }
                    restoring = true
                    Task {
                        importMessage = await coordinator.importArchive(archive)
                        pendingArchive = nil
                        archivePassphrase = ""
                        restoring = false
                    }
                }
                Button("Cancel", role: .cancel) { pendingArchive = nil }
            } message: {
                if let archive = pendingArchive {
                    let existing = Set(coordinator.nightsForRepair().map(\.nightKey))
                    let conflicts = archive.nights.filter { existing.contains($0.nightKey) }.count
                    Text("Format \(archive.formatVersion), exported \(archive.exportedAt.formatted()). \(archive.nights.count) nights (\(conflicts) existing nights updated), \(archive.journal.count) journal entries, \(archive.evidenceHistory?.count ?? 0) evidence revisions. Preferences and saved setup in this backup replace current settings. Other nights are kept. No audio starts automatically.")
                }
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
                    .font(Theme.text(16))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.label(15, weight: .semibold))
                    Text(detail).font(Theme.text(11)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .glassCard()
        }
        .buttonStyle(PressableStyle())
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.label(12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Your Data",
                subtitle: "Local-first has to mean portable. Take it with you whenever you like.",
                systemImage: "square.and.arrow.up"
            )

            Toggle("Encrypt JSON backup", isOn: $encryptBackup)
            SecureField("Backup passphrase (for export or import)", text: $archivePassphrase)
                .textContentType(.password)
            Text("Encrypted backups need this passphrase to restore. Zoon does not save it.").font(.caption).foregroundStyle(.secondary)
            if restoring { ProgressView("Restoring backup…") }
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
                actionRow("Import a backup", "Restores everything an export contains", "square.and.arrow.down", Theme.Metric.hrv)
            }
            .buttonStyle(.plain)

        }
        .glassCard()
    }

    private func actionRow(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(Theme.text(14))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(13, weight: .semibold))
                Text(detail).font(Theme.text(10)).foregroundStyle(.tertiary)
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
                    nights: coordinator.nightsForRepair(),
                    journal: coordinator.journal.allEntries(),
                    naps: naps.naps,
                    goalMinutes: preferences.sleepGoalMinutes,
                    preferences: preferences,
                    snoreSummaries: SnoreStore().nights,
                    wristTemperatures: coordinator.absoluteWristTemperaturesForExport(),
                    episodes: coordinator.episodesForExport(),
                    experiments: coordinator.experiments.outcomes,
                    soundEvents: SoundEventStore().recentEvents,
                    behaviorObservations: coordinator.behaviorObservationsForExport(),
                    evidenceHistory: coordinator.evidenceHistoryForExport(),
                    personalSetup: setup.value
                )
                let plain = try DataExporter.jsonData(archive)
                let data = encryptBackup ? try ArchiveCipher.seal(plain, passphrase: archivePassphrase) : plain
                url = try DataExporter.writeTemporary(
                    data,
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

            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 64 * 1024 * 1024 else { throw DataExporter.ImportError.unreadable }
            let plain = ArchiveCipher.isEncrypted(data) ? try ArchiveCipher.open(data, passphrase: archivePassphrase) : data
            pendingArchive = try DataExporter.decode(plain)
            showingRestorePreview = true
        } catch {
            importMessage = error.localizedDescription
        }
    }

    // MARK: - Static cards

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Privacy", systemImage: "lock.shield.fill")
            // Exports are plain JSON unless the toggle above is on; say which.
            privacyRow("wifi.slash", "No network calls",
                       encryptBackup
                           ? "Zoon contains no URLSession and no analytics. Health data stays on this device unless you explicitly export an encrypted file."
                           : "Zoon contains no URLSession and no analytics. Health data stays on this device unless you explicitly export a file. Exports are unencrypted unless you turn on Encrypt JSON backup.")
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
                .font(Theme.text(13))
                .foregroundStyle(Theme.Metric.recoveryHigh)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(12, weight: .semibold))
                Text(detail)
                    .font(Theme.text(10))
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
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

/// Streaks and milestones.
///
/// Gamification kept deliberately modest: no levels, no notifications nagging
/// you to protect a number. A streak that punishes you for one bad night is
/// actively harmful in a sleep app — the entire point is that some nights are
/// bad and that's data, not failure.
///
/// Badges exist now (see `AchievementsView`) and are built on the same rule:
/// every one is cumulative or best-ever, so nothing can be lost. The current
/// streak below is the one live number in the app, and it is shown as a fact
/// rather than as something to defend.
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
                .font(Theme.text(13))
                .foregroundStyle(tint)
            Text(value)
                .font(Theme.numeral(20))
                .monospacedDigit()
            Text(label)
                .font(Theme.text(9))
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
