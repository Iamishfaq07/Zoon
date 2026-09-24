import SwiftUI

/// Overnight snore estimate.
///
/// Pushed from the Sleep tab, so it supplies no `NavigationStack` of its own.
struct SnoreCheckView: View {

    @Environment(SnoreSessionController.self) private var session
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(SoundscapeEngine.self) private var soundscape
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionDenied = false
    @State private var conflictMessage: String?
    @State private var showingDetails = false

    var body: some View {
        VStack(spacing: 20) {
            explainer

            if let recovered = session.recoveredCheckpoint {
                recoveredCard(recovered)
            }

            if session.isRunning {
                runningCard
            } else if let last = session.lastSummary {
                lastNightCard(last)
            }

            if !session.monitoringGaps.isEmpty || !session.fusedIntervals.isEmpty {
                coverageCard
            }

            if !session.isRunning && !session.storedEvents.isEmpty {
                timelineCard
            }

            Spacer(minLength: 0)

            actionButton
        }
        .padding()
        .nightBackground()
        .navigationTitle("Snore Check")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase) { _, phase in
            session.handleScenePhase(phase)
        }
        .alert("Microphone access needed", isPresented: $permissionDenied) {
            Button("OK") {}
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
                    if let message = await session.stopAudioAndStart(soundscape: soundscape),
                       message.lowercased().contains("microphone") {
                        permissionDenied = true
                    }
                }
            }
            Button("Cancel", role: .cancel) { conflictMessage = nil }
        } message: {
            Text(conflictMessage ?? "")
        }
        .sheet(isPresented: $showingDetails) {
            sessionDetails
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "How this works", systemImage: "waveform.and.mic")
            Text("""
                While running, Zoon listens on-device. Apple's sound classifier is \
                the primary snoring evidence when the system supports it; a cadence \
                heuristic fills in when it does not. Treat the result as an estimate, \
                not a measurement.

                Audio is processed in short bursts and never saved. Zoon keeps a minutes-\
                snoring count and timestamped labels on this device — nothing else \
                survives the session, and nothing at all leaves the phone.
                """)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func recoveredCard(_ checkpoint: SnoreCheckpoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(checkpoint.unexpectedEndMessage())
                .font(Theme.text(13))
                .fixedSize(horizontal: false, vertical: true)
            Text("Save it as a partial session, or discard it. Dismissing used to throw the night away.")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
            HStack(spacing: 12) {
                Button("Save partial session") {
                    session.saveRecoveredCheckpoint()
                    Haptics.success()
                }
                .font(Theme.label(13, weight: .semibold))
                Button("Discard", role: .destructive) {
                    session.dismissRecoveredCheckpoint()
                }
                .font(Theme.label(13, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var runningCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isAudioArriving ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                    .frame(width: 8, height: 8)
                    .breathing(session.isAudioArriving, tint: session.isAudioArriving ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                Text(statusTitle)
                    .font(Theme.label(14, weight: .semibold))
            }
            Text(formattedDuration(session.monitoredSeconds))
                .font(Theme.numeral(34))
                .monospacedDigit()
            Text("\(Int(session.snoreSeconds / 60)) min flagged so far · Monitoring quality \(session.confidence.label.lowercased())")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            Button("Session details") { showingDetails = true }
                .font(.caption)
            if let last = session.lastBufferAt {
                Text(session.isAudioArriving ? "Microphone active" : "Last buffer \(Int(Date.now.timeIntervalSince(last)))s ago")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Snore Check \(statusTitle). \(formattedDuration(session.monitoredSeconds)) monitored. \(session.confidence.accessibilityName).")
    }

    private var statusTitle: String {
        switch session.state {
        case .preparing: "Preparing microphone…"
        case .listening: session.isAudioArriving ? "Listening" : "No audio arriving"
        case .background: session.isAudioArriving ? "Background monitoring" : "Listening interrupted"
        case .interrupted: "Listening interrupted"
        case .resuming: "Trying to resume…"
        case .failed(let message): message
        case .stopped, .idle: "Stopped"
        }
    }

    private func lastNightCard(_ summary: SnoreStore.NightSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Last session", systemImage: "clock.arrow.circlepath")
            HStack {
                Text("Estimated snoring")
                Spacer()
                Text("\(summary.snorePercent)% of the night")
                    .foregroundStyle(Theme.Metric.recoveryMid)
                    .monospacedDigit()
            }
            .font(Theme.label(13))

            Text(partialLine(summary))
                .font(.caption2)
                .foregroundStyle(Theme.inkTertiary)
        }
        .glassCard()
    }

    private func partialLine(_ summary: SnoreStore.NightSummary) -> String {
        var parts = ["\(Int(summary.monitoredMinutes)) minutes monitored, \(Int(summary.snoreMinutes)) minutes flagged."]
        if let coverage = summary.coveragePercent {
            parts.append("\(coverage)% of the planned night covered.")
            // A quiet result on a short session is not a finding.
            if summary.snoreMinutes < 1, summary.monitoringQuality == SnoreMonitoringConfidence.limited.rawValue {
                parts.append("No conclusion — not enough of the night was monitored to say there was no snoring.")
            }
        }
        if summary.isPartial == true { parts.append("Partial session.") }
        if let quality = summary.monitoringQuality {
            parts.append("Monitoring quality \(quality).")
        } else {
            parts.append("Monitoring quality is an estimate of coverage, not a diagnosis.")
        }
        return parts.joined(separator: " ")
    }

    private var clusters: [SoundEvent.Cluster] {
        SoundEvent.clusters(from: session.storedEvents)
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Coverage", systemImage: "timeline.selection")
            coverageBar
            if session.monitoringGaps.isEmpty {
                Text("No interruption gaps this session.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                ForEach(session.monitoringGaps) { gap in
                    HStack {
                        Text("Gap")
                            .font(Theme.text(13))
                        Spacer()
                        Text(gapCaption(gap))
                            .font(Theme.text(12))
                            .foregroundStyle(Theme.inkSecondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCard()
    }

    private var coverageBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let start = session.lastSummary.map { $0.date } ?? session.monitoringGaps.first?.startedAt
            let end = session.monitoringGaps.last?.endedAt ?? Date()
            let span = max(end.timeIntervalSince(start ?? end), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Metric.sleep.opacity(0.22))
                ForEach(session.monitoringGaps) { gap in
                    let origin = start ?? gap.startedAt
                    let x = CGFloat(gap.startedAt.timeIntervalSince(origin) / span) * width
                    let w = CGFloat(max(gap.duration, 30) / span) * width
                    Capsule()
                        .fill(Theme.inkTertiary.opacity(0.55))
                        .frame(width: max(w, 4), height: 10)
                        .offset(x: x)
                }
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Monitored span with interruption gaps")
    }

    private func gapCaption(_ gap: SnoreMonitoringGap) -> String {
        let start = gap.startedAt.formatted(.dateTime.hour().minute())
        if let ended = gap.endedAt {
            return "\(start) – \(ended.formatted(.dateTime.hour().minute()))"
        }
        return "\(start) – now"
    }

    private var timelineCard: some View {
        let episodes = clusters
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Session timeline", systemImage: "list.bullet.clipboard")
            if episodes.isEmpty {
                Text("No clustered events from the last session.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
            }
            ForEach(episodes) { episode in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: episode.symbol)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.Metric.sleep)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.label)
                            .font(Theme.text(13))
                        if !episode.isMomentary {
                            Text("\(Int(episode.minutes.rounded())) min")
                                .font(Theme.text(11))
                                .foregroundStyle(Theme.inkTertiary)
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                    Text(timing(episode))
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                if episode.id != episodes.last?.id {
                    Divider().overlay(Theme.cardStroke)
                }
            }
        }
        .glassCard()
    }

    private var sessionDetails: some View {
        NavigationStack {
            List {
                LabeledContent("Microphone", value: session.isAudioArriving ? "Active" : "Quiet")
                LabeledContent("Sound analysis", value: session.classifierAvailable ? "Active" : "Unavailable")
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
        .presentationDetents([.medium])
    }

    private func timing(_ episode: SoundEvent.Cluster) -> String {
        let start = episode.start.formatted(.dateTime.hour().minute())
        guard !episode.isMomentary else { return start }
        return "\(start) – \(episode.end.formatted(.dateTime.hour().minute()))"
    }

    private var actionButton: some View {
        Button {
            Haptics.tap()
            Task { await toggle() }
        } label: {
            Text(session.isRunning ? "Stop" : "Start listening")
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
    }

    private func toggle() async {
        if session.isRunning {
            session.stop()
            return
        }
        if let message = await session.start(
            soundscapePlaying: soundscape.isPlaying || soundscape.playing != nil,
            routineActive: TonightRoutineController.shared.active,
            // Coverage is judged against tonight's planned window, the same
            // episode the reminders and the alarm use.
            intendedWindowSeconds: coordinator.tonightEpisode().map { $0.opportunityMinutes * 60 }
        ) {
            if message.lowercased().contains("microphone") {
                permissionDenied = true
            } else {
                conflictMessage = message
            }
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Snore Check") {
    NavigationStack { SnoreCheckView() }
        .zoonPreviewEnvironment()
}
