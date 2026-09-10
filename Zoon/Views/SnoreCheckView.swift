import SwiftUI

/// Overnight snore estimate.
///
/// Pushed from the Sleep tab, so it supplies no `NavigationStack` of its own.
struct SnoreCheckView: View {

    @State private var detector = SnoreDetector()
    @State private var store = SnoreStore()
    @State private var eventStore = SoundEventStore()
    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 20) {
            explainer

            if detector.isRunning {
                runningCard
            } else if let last = store.mostRecent {
                lastNightCard(last)
            }

            if !detector.isRunning && !eventStore.recentEvents.isEmpty {
                eventsCard
            }

            Spacer(minLength: 0)

            actionButton
        }
        .padding()
        .nightBackground()
        .navigationTitle("Snore Check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "How this works", systemImage: "waveform.and.mic")
            Text("""
                While running, Zoon listens for the repeating low-frequency pattern \
                snoring produces. It's a heuristic, not a trained model — treat the \
                result as a rough estimate, not a measurement.

                Audio is processed in short bursts and never saved. Zoon keeps a minutes-\
                snoring count and up to 200 timestamped sound-event labels on this device \
                — nothing else survives the session, and nothing at all leaves the phone.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var runningCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.Metric.recoveryLow).frame(width: 8, height: 8)
                    .breathing(true, tint: Theme.Metric.recoveryLow)
                Text("Listening")
                    .font(Theme.label(14, weight: .semibold))
            }
            Text(formattedDuration(detector.monitoredSeconds))
                .font(Theme.numeral(34))
                .monospacedDigit()
            Text("\(Int(detector.snoreSeconds / 60)) min flagged so far")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
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
                .foregroundStyle(.tertiary)
        }
        .glassCard()
    }

    /// Episodes, not classified moments.
    ///
    /// A timestamped list rather than a count is still the right idea -- "3am
    /// a cough, 4:20am snoring" is something to actually look at, where a
    /// second aggregate number beside the existing snore percentage would
    /// only compete with it. What was wrong was the grain.
    ///
    /// `SoundAnalysis` classifies a buffer at a time, so twenty minutes of
    /// snoring arrived here as several hundred rows a second or two apart.
    /// That is not just long, it is misleading: three hundred rows read as
    /// three hundred things that happened, when they are one thing sampled
    /// three hundred times, and the number belongs to the classifier's buffer
    /// size rather than to the night. `SoundEvent.clusters(from:)` is where
    /// the grouping and its thresholds live.
    private var clusters: [SoundEvent.Cluster] {
        SoundEvent.clusters(from: eventStore.recentEvents)
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
                        // Only for an episode with real extent. A single
                        // moment rendering as "01:42 - 01:42, 0 min" is worse
                        // than rendering as "01:42", which is what the row
                        // already says on the right.
                        if !episode.isMomentary {
                            Text("\(Int(episode.minutes.rounded())) min")
                                .font(Theme.text(11))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                    Text(timing(episode))
                        .font(Theme.text(12))
                        .foregroundStyle(.secondary)
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
            Text(detector.isRunning ? "Stop" : "Start listening")
                .font(Theme.label(16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    detector.isRunning
                    ? AnyShapeStyle(Theme.neutral(0.12))
                    : AnyShapeStyle(LinearGradient(
                        colors: [Theme.Metric.sleep, Theme.Metric.battery],
                        startPoint: .leading, endPoint: .trailing
                      )),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .foregroundStyle(detector.isRunning ? Color.primary : Color.black)
        }
        .alert("Microphone access needed", isPresented: $permissionDenied) {
            Button("OK") {}
        } message: {
            Text("Turn on microphone access for Zoon in iOS Settings to use Snore Check.")
        }
    }

    private func toggle() async {
        if detector.isRunning {
            let recognizedEvents = detector.recentEvents
            if let summary = detector.stop() {
                store.record(summary)
                eventStore.record(recognizedEvents)
            }
            return
        }

        guard detector.isAvailable else {
            permissionDenied = true
            return
        }
        guard await detector.requestPermission() else {
            permissionDenied = true
            return
        }
        do {
            try detector.start()
        } catch {
            permissionDenied = true
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Snore Check") {
    NavigationStack { SnoreCheckView() }
}
