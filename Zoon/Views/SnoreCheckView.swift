import SwiftUI
import UIKit

/// Snore Check: when you snored, for how long, and how loud.
///
/// Three states on one screen. Before a night: the emblem, what it tells
/// you, and how to set the phone up. While listening: a live dial that
/// follows the room and turns amber inside a snoring episode. In the
/// morning: the night as a timeline of episodes coloured by loudness, the
/// numbers that matter, and the nights before it.
///
/// Pushed from the Sleep tab, so it supplies no `NavigationStack` of its own.
struct SnoreCheckView: View {

    @Environment(SnoreSessionController.self) private var session
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(SoundscapeEngine.self) private var soundscape
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var permissionDenied = false
    /// Zoon's own audio is playing; the alert offers to stop it and start.
    @State private var conflictMessage: String?
    /// Any other failure: said plainly, with nothing that would reset the
    /// session.
    @State private var errorMessage: String?
    @State private var showingDetails = false
    @State private var showingHowItWorks = false
    /// Snoring against logged behaviours; worked out once per new night,
    /// not on every redraw of the live dial.
    @State private var habitLinks: [SnoreHabitLink.Link] = []

    var body: some View {
        // Scrolls, with the button pinned to the bottom edge. The floating tab
        // bar is hidden here: it does not inset pushed screens, and sat on
        // the button.
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if session.isRunning {
                    liveCard
                } else {
                    hero
                }

                if let recovered = session.recoveredCheckpoint {
                    recoveredCard(recovered)
                }

                if !session.isRunning {
                    if let shown = shownSummary {
                        resultCard(shown.summary, isSample: shown.isSample)
                    } else if session.recoveredCheckpoint == nil {
                        setupCard
                    }
                    if historyNights.count >= 2 {
                        historyCard
                    }
                    if !shownHabitLinks.links.isEmpty {
                        habitCard
                    }
                    if !otherSounds.isEmpty {
                        otherSoundsCard
                    }
                }

                howItWorksCard
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if session.state == .interrupted {
                    resumeButton
                }
                actionButton
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .nightBackground()
        .navigationTitle("Snore Check")
        .hidesFloatingTabBar()
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            session.handleScenePhase(phase)
        }
        .task(id: session.history.count) {
            habitLinks = computeHabitLinks()
        }
        .alert("Microphone access needed", isPresented: $permissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Turn on microphone access for Zoon in iOS Settings to use Snore Check.")
        }
        .alert(
            "Snore Check needs a quiet microphone",
            isPresented: Binding(
                get: { conflictMessage != nil },
                set: { if !$0 { conflictMessage = nil } }
            )
        ) {
            Button("Stop & Start") {
                Task {
                    conflictMessage = nil
                    handle(await session.stopAudioAndStart(soundscape: soundscape))
                }
            }
            Button("Cancel", role: .cancel) { conflictMessage = nil }
        } message: {
            Text(conflictMessage ?? "")
        }
        .alert(
            "Snore Check",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showingDetails) {
            sessionDetails
        }
    }

    // MARK: - Data

    /// The latest stored night, or in the demo build a sample one, marked.
    private var shownSummary: (summary: SnoreStore.NightSummary, isSample: Bool)? {
        if let last = session.lastSummary { return (last, false) }
        if LaunchOptions.isDemo { return (SnoreSample.lastNight(), true) }
        return nil
    }

    private var historyNights: [SnoreHistoryChart.Night] {
        let stored = session.history
        let nights = stored.isEmpty && LaunchOptions.isDemo ? SnoreSample.history() : stored
        return nights.suffix(14).map { SnoreHistoryChart.Night(date: $0.date, minutes: $0.snoreMinutes) }
    }

    /// Real links, or in the demo build sample ones, marked.
    private var shownHabitLinks: (links: [SnoreHabitLink.Link], isSample: Bool) {
        if !habitLinks.isEmpty || !session.history.isEmpty || !LaunchOptions.isDemo { return (habitLinks, false) }
        return (SnoreSample.habitLinks, true)
    }

    private func computeHabitLinks() -> [SnoreHabitLink.Link] {
        let calendar = Calendar.current
        let nights = session.history
            .filter { $0.monitoredMinutes >= 60 }
            .map { SnoreHabitLink.Night(day: calendar.startOfDay(for: $0.date), snorePercent: Double($0.snorePercent)) }
        guard nights.count >= SnoreHabitLink.minimumNightsEachSide * 2 else { return [] }
        var tagsByDay: [Date: Set<String>] = [:]
        for entry in coordinator.journal.allEntries() {
            tagsByDay[calendar.startOfDay(for: entry.date)] = Set(entry.tagIdentifiers)
        }
        return SnoreHabitLink.links(nights: nights, tagsByDay: tagsByDay)
    }

    /// Coughs and a crying baby from Apple's classifier. Snoring has its own
    /// timeline above.
    private var otherSounds: [SoundEvent.Cluster] {
        SoundEvent.clusters(from: session.storedEvents).filter { $0.identifier != "snoring" }
    }

    // MARK: - Before a night

    private var hero: some View {
        VStack(spacing: 14) {
            SnoreEmblem(size: 132, active: false)
            VStack(spacing: 6) {
                Text("Hear your night")
                    .font(Theme.heading(26))
                Text("When you snored, for how long, and how loud. Worked out on this iPhone, with nothing recorded.")
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                chip("clock", "When")
                chip("waveform", "How loud")
                chip("lock.fill", "Private")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func chip(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol)
            .font(Theme.label(12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.neutral(0.10), in: Capsule())
            .foregroundStyle(Theme.inkSecondary)
    }

    /// Before the first session: how to set the phone up, since that decides
    /// how much of the night is covered. Gone after one night.
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Before you start", systemImage: "bed.double.fill")
            ForEach(Self.setupTips, id: \.text) { tip in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: tip.symbol)
                        .font(Theme.text(14, weight: .semibold))
                        .foregroundStyle(Theme.Family.sleep)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(tip.text)
                        .font(Theme.text(14))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private static let setupTips: [(symbol: String, text: String)] = [
        ("iphone", "Put the phone on the nightstand, within about a metre of your head."),
        ("bolt.fill", "Plug it in. Listening all night uses more battery than an idle phone."),
        ("lock.fill", "Lock the phone once it's listening. Snore Check keeps going."),
        ("moon.fill", "Turn on Sleep Focus so a call or notification doesn't interrupt it."),
        ("speaker.slash.fill", "Zoon's Sleep Sounds pause while it listens. Play sound from another speaker if you need it.")
    ]

    // MARK: - Listening

    private var liveCard: some View {
        VStack(spacing: 16) {
            SnoreLiveMeter(
                levelDB: session.levelAboveRoomDB,
                snoring: session.isSnoringNow,
                pulse: (session.secondsSinceSnoreSound ?? .infinity) < 1.2,
                arriving: session.isAudioArriving,
                elapsed: formattedDuration(session.monitoredSeconds),
                status: statusTitle
            )
            HStack(spacing: 10) {
                liveStat("Snoring", SnoreResultSummary.duration(session.snoreSeconds / 60))
                liveStat("Episodes", "\(session.liveEpisodeCount)")
                liveStat("Quality", session.confidence.label)
            }
            Text("You can lock your phone. Snore Check keeps listening, and nothing is recorded.")
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Session details") { showingDetails = true }
                .font(Theme.label(13))
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Snore Check \(statusTitle). \(formattedDuration(session.monitoredSeconds)) monitored. \(session.confidence.accessibilityName).")
    }

    private func liveStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Theme.label(17, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.neutral(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch session.state {
        case .preparing: "Preparing microphone…"
        case .listening:
            session.isAudioArriving ? (session.isSnoringNow ? "Snoring now" : "Listening") : "No audio arriving"
        case .background:
            session.isAudioArriving ? (session.isSnoringNow ? "Snoring now" : "Listening, locked") : "Listening interrupted"
        case .interrupted: "Listening interrupted"
        case .resuming: "Trying to resume…"
        case .failed(let message): message
        case .stopped, .idle: "Stopped"
        }
    }

    private var resumeButton: some View {
        Button {
            Haptics.tap()
            if !session.resume() {
                errorMessage = session.conflictMessage
                    ?? "Snore Check couldn't get the microphone back. Close any app that may be using it, then try again."
            }
        } label: {
            Label("Resume listening", systemImage: "mic.fill")
                .font(Theme.label(16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.neutral(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .accessibilityHint("Starts listening again after the interruption.")
    }

    // MARK: - The morning

    private func resultCard(_ summary: SnoreStore.NightSummary, isSample: Bool) -> some View {
        let result = SnoreResultSummary(
            monitoredMinutes: summary.monitoredMinutes,
            snoreMinutes: summary.snoreMinutes,
            coveragePercent: summary.coveragePercent,
            interruptionMinutes: summary.interruptionDurationMinutes,
            quality: summary.monitoringQuality.flatMap(SnoreMonitoringConfidence.init(rawValue:))
        )
        let report = summary.report
        let flagged = summary.snoreMinutes >= 1
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Last night", subtitle: nightCaption(summary, report: report), systemImage: "moon.zzz.fill")
                Spacer(minLength: 8)
                if isSample {
                    Text("Sample")
                        .font(Theme.label(11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.neutral(0.14), in: Capsule())
                }
            }

            if flagged {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(SnoreResultSummary.duration(summary.snoreMinutes))
                        .font(Theme.numeral(40))
                        .monospacedDigit()
                    Text("snoring · \(report.sharePercent)% of the time monitored")
                        .font(Theme.text(14))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(result.headline)
                    .font(Theme.heading(28))
                    .foregroundStyle(result.isConclusive ? Theme.ink : Theme.inkSecondary)
            }

            if report.span != nil, !report.episodes.isEmpty {
                SnoreNightTimeline(report: report)
            } else if flagged {
                Text("The timeline appears from your next night: this one was saved before Snore Check kept times.")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if flagged, report.episodeCount > 0 {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    stat("Episodes", "\(report.episodeCount)")
                    stat("Longest", report.longest.map { SnoreResultSummary.duration($0.duration / 60) } ?? "—")
                    stat("Loudest", report.loudest?.label ?? "—", tint: report.loudest?.tint)
                    stat("Busiest hour", report.busiestHour().map { $0.formatted(.dateTime.hour()) } ?? "—")
                }
                episodeList(report)
            }

            VStack(spacing: 6) {
                ForEach(result.rows) { row in
                    HStack {
                        Text(row.label)
                        Spacer()
                        Text(row.value).monospacedDigit()
                    }
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityElement(children: .combine)
                }
            }

            Text(partialLine(summary))
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func nightCaption(_ summary: SnoreStore.NightSummary, report: SnoreNightReport) -> String {
        let day = summary.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        guard let span = report.span else { return day }
        let start = span.start.formatted(date: .omitted, time: .shortened)
        let end = span.end.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(start) – \(end)"
    }

    private func stat(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(Theme.label(18, weight: .bold))
                .foregroundStyle(tint ?? Theme.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.neutral(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// The longest few episodes, in the order they happened.
    private func episodeList(_ report: SnoreNightReport) -> some View {
        let top = report.episodes
            .sorted { $0.duration > $1.duration }
            .prefix(4)
            .sorted { $0.start < $1.start }
        return VStack(spacing: 0) {
            ForEach(Array(top.enumerated()), id: \.offset) { index, episode in
                HStack(spacing: 10) {
                    Capsule()
                        .fill(episode.loudness?.tint ?? Theme.Metric.sleep)
                        .frame(width: 4, height: 26)
                    Text("\(episode.start.formatted(date: .omitted, time: .shortened)) – \(episode.end.formatted(date: .omitted, time: .shortened))")
                        .font(Theme.text(13))
                        .monospacedDigit()
                    Spacer()
                    Text(SnoreResultSummary.duration(episode.duration / 60))
                        .font(Theme.label(13))
                        .monospacedDigit()
                    if let loudness = episode.loudness {
                        Text(loudness.label)
                            .font(Theme.text(11))
                            .foregroundStyle(loudness.tint)
                            .frame(width: 64, alignment: .trailing)
                    }
                }
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
                if index < top.count - 1 {
                    Divider().overlay(Theme.cardStroke)
                }
            }
        }
    }

    /// The sentence under the rows: what the numbers do and do not mean.
    private func partialLine(_ summary: SnoreStore.NightSummary) -> String {
        var parts: [String] = []
        if summary.snoreMinutes < 1, summary.monitoringQuality == SnoreMonitoringConfidence.limited.rawValue {
            parts.append("Not enough of the night was monitored to say there was no snoring.")
        }
        if summary.isPartial == true { parts.append("Partial session.") }
        parts.append("Loudness is compared with your room's quiet level, not measured in decibels. Snoring on its own is not a medical finding.")
        return parts.joined(separator: " ")
    }

    private var historyCard: some View {
        let nights = historyNights
        let average = nights.reduce(0) { $0 + $1.minutes } / Double(max(nights.count, 1))
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Night by night",
                subtitle: "About \(SnoreResultSummary.duration(average)) a night over \(nights.count) nights",
                systemImage: "chart.bar.fill"
            )
            SnoreHistoryChart(nights: nights)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var habitCard: some View {
        let shown = shownHabitLinks
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(
                    title: "What goes with your snoring",
                    subtitle: "Nights you listened and kept the Journal; the number is how many nights.",
                    systemImage: "link"
                )
                Spacer(minLength: 8)
                if shown.isSample {
                    Text("Sample")
                        .font(Theme.label(11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.neutral(0.14), in: Capsule())
                }
            }
            ForEach(shown.links.prefix(4), id: \.tag) { link in
                habitRow(link)
            }
            Text("Snoring on nights with and without each habit. A pattern, not a cause.")
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func habitRow(_ link: SnoreHabitLink.Link) -> some View {
        let label = BehaviorTag(rawValue: link.tag)?.label ?? link.tag
        let scale = max(link.withPercent, link.withoutPercent, 1)
        let more = link.difference > 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(Theme.label(14, weight: .semibold))
                Spacer()
                Text("\(more ? "+" : "−")\(Int(abs(link.difference).rounded())) pts")
                    .font(Theme.label(13, weight: .bold))
                    .foregroundStyle(more ? Theme.Metric.recoveryMid : Theme.Metric.recoveryHigh)
                    .monospacedDigit()
            }
            habitBar("With", percent: link.withPercent, nights: link.withNights, scale: scale, tint: more ? Theme.Metric.recoveryMid : Theme.Metric.recoveryHigh)
            habitBar("Without", percent: link.withoutPercent, nights: link.withoutNights, scale: scale, tint: Theme.inkTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(Int(link.withPercent.rounded())) percent snoring on \(link.withNights) nights with it, \(Int(link.withoutPercent.rounded())) percent on \(link.withoutNights) nights without.")
    }

    private func habitBar(_ label: String, percent: Double, nights: Int, scale: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text("\(label) · \(nights)")
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .monospacedDigit()
                .frame(width: 74, alignment: .leading)
            GeometryReader { geo in
                Capsule()
                    .fill(tint.opacity(0.85))
                    .frame(width: max(4, geo.size.width * percent / scale))
            }
            .frame(height: 8)
            Text("\(Int(percent.rounded()))%")
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkSecondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }

    private var otherSoundsCard: some View {
        let episodes = otherSounds
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Other sounds heard", systemImage: "ear.fill")
            ForEach(episodes) { episode in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: episode.symbol)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.Metric.sleep)
                        .frame(width: 20)
                    Text(episode.label)
                        .font(Theme.text(13))
                    Spacer()
                    Text(timing(episode))
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - How it works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(Motion.standard) { showingHowItWorks.toggle() }
            } label: {
                HStack {
                    SectionHeader(title: "How Snore Check works", systemImage: "waveform.and.magnifyingglass")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showingHowItWorks ? 180 : 0))
                        .foregroundStyle(Theme.inkTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showingHowItWorks ? "Hides the explanation." : "Shows the explanation.")

            if showingHowItWorks {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Listens against your room", "It learns how quiet your bedroom is, and only notices sounds that rise above it, so a fan or traffic doesn't count.")
                    step(2, "Checks each sound's shape", "A snore is low-pitched and lasts about as long as a breath. Clicks, speech and passing cars are the wrong shape.")
                    step(3, "Waits for the rhythm of breathing", "Snoring repeats with every breath. Only a run of them becomes an episode, so a single cough or word never does.")
                    Text("When Apple's sound classifier is running, it double-checks the result and rules out speech, music and TV. Audio is analysed in tenths of a second and thrown away: Zoon keeps only the times, lengths and loudness of each episode, on this iPhone.")
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(Theme.label(13, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Theme.Metric.sleep.opacity(0.22), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.label(14, weight: .semibold))
                Text(detail)
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Recovery, details, actions

    private func recoveredCard(_ checkpoint: SnoreCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(checkpoint.unexpectedEndMessage())
                .font(Theme.text(13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Save it as a partial night, or discard it.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
            HStack(spacing: 12) {
                Button("Save partial night") {
                    session.saveRecoveredCheckpoint()
                    Haptics.success()
                }
                .font(Theme.label(13, weight: .semibold))
                .frame(minHeight: 44)
                Button("Discard", role: .destructive) {
                    session.dismissRecoveredCheckpoint()
                }
                .font(Theme.label(13, weight: .semibold))
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func gapCaption(_ gap: SnoreMonitoringGap) -> String {
        let start = gap.startedAt.formatted(.dateTime.hour().minute())
        if let ended = gap.endedAt {
            return "\(start) – \(ended.formatted(.dateTime.hour().minute()))"
        }
        return "\(start) – now"
    }

    private func timing(_ episode: SoundEvent.Cluster) -> String {
        let start = episode.start.formatted(.dateTime.hour().minute())
        guard !episode.isMomentary else { return start }
        return "\(start) – \(episode.end.formatted(.dateTime.hour().minute()))"
    }

    /// Whether Apple's sound classifier is actually listening. It can stop
    /// mid-session (on some iOS versions once the phone locks) while the
    /// microphone and Zoon's own engine carry on.
    private var soundAnalysisStatus: String {
        guard session.classifierAvailable else { return "Unavailable, Zoon's engine only" }
        guard let paused = session.classifierPausedSince else { return "Active" }
        return "Paused since \(paused.formatted(date: .omitted, time: .shortened)), Zoon's engine only"
    }

    private var sessionDetails: some View {
        NavigationStack {
            List {
                LabeledContent("Microphone", value: session.isAudioArriving ? "Active" : "Quiet")
                LabeledContent("Room level", value: session.isAudioArriving ? "+\(Int(session.levelAboveRoomDB.rounded())) dB above quiet" : "—")
                LabeledContent("Apple sound analysis", value: soundAnalysisStatus)
                LabeledContent("Last audio", value: session.lastBufferAt.map { "\(Int(Date.now.timeIntervalSince($0)))s ago" } ?? "—")
                LabeledContent("Interruptions", value: "\(session.interruptionGaps)")
                if session.monitoringGaps.isEmpty {
                    LabeledContent("Gaps", value: "None")
                } else {
                    ForEach(session.monitoringGaps) { gap in
                        LabeledContent("Gap", value: gapCaption(gap))
                    }
                }
                LabeledContent("Monitoring quality", value: session.confidence.label)
            }
            .navigationTitle("Session details")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingDetails = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    /// Routes what `start` returned: the microphone permission, a conflict
    /// with Zoon's own audio, or anything else.
    private func handle(_ message: String?) {
        guard let message else { return }
        if message == SnoreSessionController.microphoneAccessNeeded {
            permissionDenied = true
        } else if soundscape.playing != nil || TonightRoutineController.shared.active {
            conflictMessage = message
        } else {
            errorMessage = message
        }
    }

    private var actionButton: some View {
        Button {
            Haptics.tap()
            Task { await toggle() }
        } label: {
            Label(session.isRunning ? "Stop" : "Start listening", systemImage: session.isRunning ? "stop.fill" : "waveform")
                .font(Theme.label(16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    session.isRunning
                    ? AnyShapeStyle(Theme.neutral(0.12))
                    : AnyShapeStyle(LinearGradient(
                        colors: [Theme.Metric.sleep, Theme.Metric.battery],
                        startPoint: .leading, endPoint: .trailing
                      )),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .foregroundStyle(session.isRunning ? Color.primary : Color.black)
        }
        .accessibilityLabel(session.isRunning ? "Stop" : "Start listening")
    }

    private func toggle() async {
        if session.isRunning {
            session.stop()
            Haptics.success()
            return
        }
        if let message = await session.start(
            soundscapePlaying: soundscape.isPlaying || soundscape.playing != nil,
            routineActive: TonightRoutineController.shared.active,
            // Coverage is judged against tonight's planned window, the same
            // episode the reminders and the alarm use.
            intendedWindowSeconds: coordinator.tonightEpisode().map { $0.opportunityMinutes * 60 }
        ) {
            handle(message)
        }
    }

    /// "4:12" under an hour, "7:17:12" over one.
    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, total % 60)
            : String(format: "%d:%02d", minutes, total % 60)
    }
}

/// The demo build's night: shown only with the demo launch argument, and
/// always labelled "Sample" on screen.
private enum SnoreSample {
    static func lastNight(now: Date = .now, calendar: Calendar = .current) -> SnoreStore.NightSummary {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let episodes = [
            SnoreEpisodeRecord(start: at(1, 12), end: at(1, 31), events: 271, loudness: .moderate),
            SnoreEpisodeRecord(start: at(2, 40), end: at(2, 52), events: 168, loudness: .quiet),
            SnoreEpisodeRecord(start: at(3, 55), end: at(4, 31), events: 522, loudness: .loud),
            SnoreEpisodeRecord(start: at(5, 20), end: at(5, 34), events: 197, loudness: .moderate),
            SnoreEpisodeRecord(start: at(6, 10), end: at(6, 18), events: 109, loudness: .quiet)
        ]
        return SnoreStore.NightSummary(
            date: today,
            monitoredMinutes: 462,
            snoreMinutes: 89,
            monitoringQuality: SnoreMonitoringConfidence.high.rawValue,
            coveragePercent: 96,
            episodes: episodes,
            startedAt: at(23, 6, dayOffset: -1),
            endedAt: at(6, 48)
        )
    }

    static let habitLinks = [
        SnoreHabitLink.Link(tag: "alcohol", withPercent: 24, withoutPercent: 9, withNights: 4, withoutNights: 8),
        SnoreHabitLink.Link(tag: "lateMeal", withPercent: 17, withoutPercent: 10, withNights: 3, withoutNights: 9),
        SnoreHabitLink.Link(tag: "coolRoom", withPercent: 7, withoutPercent: 14, withNights: 5, withoutNights: 7)
    ]

    static func history(now: Date = .now, calendar: Calendar = .current) -> [SnoreStore.NightSummary] {
        let minutes: [Double] = [34, 58, 12, 71, 40, 22, 95, 63, 30, 48, 17, 89]
        let today = calendar.startOfDay(for: now)
        return minutes.enumerated().compactMap { index, value in
            guard let date = calendar.date(byAdding: .day, value: index - minutes.count + 1, to: today) else { return nil }
            return SnoreStore.NightSummary(date: date, monitoredMinutes: 450, snoreMinutes: value)
        }
    }
}

#Preview("Snore Check") {
    NavigationStack { SnoreCheckView() }
        .zoonPreviewEnvironment()
}
