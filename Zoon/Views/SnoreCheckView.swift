import SwiftUI

/// Overnight snore estimate.
///
/// Pushed from the Sleep tab, so it supplies no `NavigationStack` of its own.
struct SnoreCheckView: View {

    @Environment(SnoreSessionController.self) private var session
    @Environment(SoundscapeEngine.self) private var soundscape
    @Environment(\.scenePhase) private var scenePhase
    @State private var permissionDenied = false
    @State private var conflictMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            explainer

            if session.isRunning {
                runningCard
            } else if let last = session.lastSummary {
                lastNightCard(last)
            }

            if !session.isRunning && !session.storedEvents.isEmpty {
                eventsCard
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
            "Stop sleep audio first",
            isPresented: Binding(
                get: { conflictMessage != nil },
                set: { if !$0 { conflictMessage = nil } }
            )
        ) {
            Button("OK") { conflictMessage = nil }
        } message: {
            Text(conflictMessage ?? "")
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
            Text("\(Int(session.snoreSeconds / 60)) min flagged so far · \(session.confidence.label) confidence")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
            if let last = session.lastBufferAt {
                Text(session.isAudioArriving ? "Microphone active" : "Last buffer \(Int(Date.now.timeIntervalSince(last)))s ago")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Snore Check \(statusTitle). \(formattedDuration(session.monitoredSeconds)) monitored.")
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

            Text("\(Int(summary.monitoredMinutes)) minutes monitored, \(Int(summary.snoreMinutes)) minutes flagged.")
                .font(.caption2)
                .foregroundStyle(Theme.inkTertiary)
        }
        .glassCard()
    }

    private var clusters: [SoundEvent.Cluster] {
        SoundEvent.clusters(from: session.storedEvents)
    }

    private var eventsCard: some View {
        let episodes = clusters
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Events", systemImage: "list.bullet.clipboard")
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
            routineActive: TonightRoutineController.shared.active
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
