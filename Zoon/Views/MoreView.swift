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
    /// On by default: a full backup carries every night, journal note and
    /// check-in, and it leaves the phone the moment it is shared. Turning it
    /// off is one tap for someone who wants plain JSON.
    @State private var encryptBackup = true
    @State private var archivePassphrase = ""
    @State private var pendingArchive: DataExporter.Archive?
    @State private var showingRestorePreview = false
    @State private var restoring = false
    @State private var importMessage: String?
    @State private var showsBackup = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: Theme.stackSpacing) {
                    if !setup.value.scoreLight {
                        StreakCard(nights: coordinator.recentNights, goalMinutes: preferences.sleepGoalMinutes).entrance(0)
                    }

                    // Grouped by what someone came here to do. "This week"
                    // used to hold Settings and Badges, and "Later" held a
                    // data repair tool beside the reading list; Repair now
                    // sits with Data quality, the screen that sends people
                    // to it.
                    // Fourteen rows became six. Related screens now share
                    // one hub each (see `FeatureHubs.swift`), so this list
                    // names the questions, and the hub's chips name the
                    // screens inside.
                    sectionLabel("Plan and review")
                    navRow("Plan", "Tonight, tomorrow and travel", "moon.stars.fill", Theme.Metric.sleep) { PlanHub() }
                    navRow("Reports", "Your week, month and year, and a PDF for a doctor", "calendar.badge.clock", Theme.Metric.recoveryHigh) {
                        ReportsHub()
                    }
                    navRow("Your patterns", "What goes with your good and bad nights", "sparkles", Theme.Family.sleep) {
                        PatternsHub()
                    }
                    navRow("Badges", "What you've earned so far", "hexagon.fill", Theme.Metric.recoveryMid) {
                        AchievementsView()
                    }

                    sectionLabel("Your data and settings")
                    navRow("Your data", "What Zoon measured, estimated and knows", "waveform.path.ecg", Theme.Metric.hrv) {
                        DataHub()
                    }
                    navRow("Learn", "Sleep science and every word, in plain language", "book.pages.fill", Theme.Metric.sleep) {
                        LearnHub()
                    }
                    navRow("Settings", "Goal, your own behaviours, privacy", "gearshape.fill", .secondary) {
                        SettingsView()
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
                case .report: ReportsHub(initial: .week)
                case .settings: SettingsView()
                case .badges: AchievementsView()
                case .evidence: PatternsHub(initial: .proven)
                case .patterns: PatternsHub(initial: .noticed)
                case .sensorTruth: DataHub(initial: .sources)
                case .tomorrow: PlanHub(initial: .tomorrow)
                // Owned by the Sleep tab.
                case .soundscapes, .nap, .sleepDetail, .nightHistory, .breathing, .snoreCheck, .bodyClock, .windDown: EmptyView()
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
                    Text(detail).font(Theme.text(11)).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .glassCard()
        }
        .buttonStyle(PressableStyle())
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.label(12, weight: .semibold))
            .foregroundStyle(Theme.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.select()
                withAnimation(Motion.standard) { showsBackup.toggle() }
            } label: {
                HStack {
                    SectionHeader(
                        title: "Back up or move",
                        subtitle: "Export, share or restore everything",
                        systemImage: "square.and.arrow.up"
                    )
                    Image(systemName: "chevron.down")
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(showsBackup ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsBackup ? "Expanded" : "Collapsed")

            // Folded: a passphrase field and four export rows are used a
            // few times a year, and sat open on every visit to More.
            if showsBackup || exportURL != nil || restoring {
            Toggle("Encrypt JSON backup", isOn: $encryptBackup)
            SecureField("Backup passphrase (for export or import)", text: $archivePassphrase)
                .textContentType(.password)
            Text("Encrypted backups need this passphrase to restore. Zoon does not save it.").font(.caption).foregroundStyle(Theme.inkSecondary)
            if restoring {
                HStack(spacing: 10) {
                    ZoonLoadingRing(size: 18, lineWidth: 2.5, showsMoon: false)
                    Text("Restoring backup…")
                }
            }
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
                Text(detail).font(Theme.text(10)).foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func buildExport(json: Bool) {
        do {
            let url: URL
            if json {
                // A read that fails while gathering history must not become
                // a backup that looks complete. See `StoreRead`.
                let readFailuresBefore = StoreRead.failureCount
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
                    personalSetup: setup.value,
                    customBehaviors: CustomBehaviorStore.shared.behaviors,
                    alertnessSessions: AlertnessCheckStore().sessions
                )
                guard StoreRead.failureCount == readFailuresBefore else { throw IncompleteHistoryReadError() }
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

    /// Four promises as four badges. They were four paragraphs, and the
    /// promise is the part people remember; the detail is read aloud by
    /// VoiceOver and lives in Settings → Data Quality & Privacy.
    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Privacy", systemImage: "lock.shield.fill")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                privacyBadge("wifi.slash", "No network calls", "Zoon makes no network calls and has no analytics.")
                privacyBadge("iphone", "All on device", "Every score, insight and sound is computed on this phone.")
                privacyBadge("eye.slash", "Read-only Health", "Zoon can read Health data but never write to it.")
                privacyBadge("person.crop.circle.badge.xmark", "No account", "No sign-in, no telemetry, no third-party code.")
            }
            if !encryptBackup {
                Label("Exports are unencrypted while Encrypt is off.", systemImage: "exclamationmark.triangle")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.Metric.recoveryMid)
            }
        }
        .glassCard()
    }

    private func privacyBadge(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(Theme.text(13, weight: .semibold))
                .foregroundStyle(Theme.Metric.recoveryHigh)
                .frame(width: 30, height: 30)
                .background(Theme.Metric.recoveryHigh.opacity(0.12), in: Circle())
            Text(title)
                .font(Theme.label(12, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                MoonFill(fill: 0.62, active: true, size: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zoon")
                        .font(Theme.label(15, weight: .bold))
                    Text("“Zoon” means moon in Kashmiri.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            Text(SleepInsight.disclaimer)
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkTertiary)
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

    /// All three figures from `SleepStreakEngine`, so the card cannot
    /// disagree with achievements, insights or widgets about the same run.
    ///
    /// The previous local implementation walked the nights array and broke
    /// only on a night under goal, so Mon-Tue-[no record]-Thu-Fri counted as
    /// four consecutive nights. It also measured `timeAsleepMinutes` while
    /// the shortfall and need on every other screen use the 24-hour total.
    private var streak: SleepStreakEngine.Result {
        SleepStreakEngine.evaluate(nights: nights, goalMinutes: goalMinutes)
    }

    var body: some View {
        HStack(spacing: 0) {
            stat("\(streak.current)", "night streak", Theme.Metric.recoveryHigh, "flame.fill")
            divider
            stat("\(streak.best)", "personal best", Theme.Metric.sleep, "trophy.fill")
            divider
            stat("\(streak.metInWindow)/\(streak.windowSize)", "goal met", Theme.Metric.battery, "checkmark.seal.fill")
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
                .foregroundStyle(Theme.inkTertiary)
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
                            .foregroundStyle(Theme.inkSecondary)
                    } else {
                        StatusPill(text: "Wind down now", systemImage: "moon.fill", tint: Theme.Metric.temperature)
                    }
                }

                Text(remaining > 0
                     ? "Being asleep by then hits your full sleep need for tomorrow."
                     : "You're past the ideal bedtime. Going now still recovers most of it.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
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
