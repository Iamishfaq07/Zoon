import SwiftUI

/// Sleep Sounds / Nap / Wind Down / Snore Check / Breathing, as a
/// horizontally-scrollable strip of compact tiles.
///
/// These five used to be individual full-width `NavigationLink` rows sitting
/// between opening the Sleep tab and seeing anything about how you actually
/// slept -- the redesign spec's specific complaint about the old hierarchy.
/// Moving them here keeps every tool one tap away while letting "Last Night"
/// lead the screen instead.
struct SleepToolsStrip: View {
    @Environment(SoundscapeEngine.self) private var soundscape
    @Environment(NapStore.self) private var naps
    @Environment(SnoreSessionController.self) private var snore
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Tools")
                .font(Theme.label(12, weight: .bold))
                .foregroundStyle(Theme.inkTertiary)

            if hasLiveSession {
                liveStatus
            } else if !reliabilityLines.isEmpty {
                reliabilityCard
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink {
                        SoundscapeView()
                    } label: {
                        tile("Sleep Sounds", symbol: "waveform", tint: Theme.Metric.battery, status: soundStatus)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        NapView()
                    } label: {
                        tile("Nap", symbol: "powersleep", tint: Theme.Metric.strain, status: napStatus)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        TonightRoutineView()
                    } label: {
                        tile("Wind Down", symbol: "wind", tint: Theme.Metric.recoveryHigh, status: windDownStatus)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        SnoreCheckView()
                    } label: {
                        tile("Snore Check", symbol: "waveform.and.mic", tint: Theme.Metric.hrv, status: snoreStatus)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        BreathingHealthView()
                    } label: {
                        customTile(
                            "Breathing",
                            icon: ZoonIcon.Breathing(tint: Theme.Metric.sleep),
                            tint: Theme.Metric.sleep,
                            status: nil
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private var hasLiveSession: Bool {
        soundscape.isPlaying || naps.activeNap != nil || TonightRoutineController.shared.active || snore.isRunning
    }

    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sound = soundscape.playing {
                Text("\(sound.label) · \(soundscape.timerCaption ?? "Timer Off")")
            }
            if TonightRoutineController.shared.active, let caption = TonightRoutineController.shared.remainingCaption {
                Text("Wind Down · \(caption)")
            }
            if let nap = naps.activeNap {
                Text("Nap · \(nap.wakeKind?.shortLabel ?? "Arming") · \(nap.targetMinutes) min")
            }
            if snore.isRunning {
                Text("Snore Check · \(snoreStatus ?? "Listening")")
            }
        }
        .font(Theme.label(12, weight: .medium))
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var reliabilityLines: [SleepToolReliability.Line] {
        let summary = snore.lastSummary
        let snoreRecent = summary.map { Calendar.current.isDateInToday($0.date) || Calendar.current.isDateInYesterday($0.date) } ?? false
        let lastNap = naps.naps.last
        let napRecent = lastNap.map { Calendar.current.isDateInToday($0.start) || Calendar.current.isDateInYesterday($0.start) } ?? false
        return SleepToolReliability.lines(
            snoreMonitoredMinutes: snoreRecent ? summary.map { Int($0.monitoredMinutes.rounded()) } : nil,
            snoreGapMinutes: snoreRecent ? summary?.interruptionDurationMinutes.map { Int($0.rounded()) } : nil,
            snoreInterruptions: snoreRecent && (summary?.interruptionDurationMinutes ?? 0) > 0 ? 1 : nil,
            snorePartial: summary?.isPartial == true,
            napMinutes: napRecent ? lastNap.map { Int($0.minutes.rounded()) } : nil,
            napWake: napRecent ? (naps.lastArmed?.wake ?? naps.activeNap?.wakeKind) : nil,
            soundsMinutes: nil,
            soundsUninterrupted: nil
        )
    }

    private var reliabilityCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last session")
                .font(Theme.label(11, weight: .bold))
                .foregroundStyle(Theme.inkTertiary)
            ForEach(reliabilityLines, id: \.title) { line in
                Text("\(line.title) · \(line.detail)")
            }
        }
        .font(Theme.label(12, weight: .medium))
        .foregroundStyle(Theme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var soundStatus: String? {
        guard let sound = soundscape.playing else { return nil }
        return soundscape.isPlaying ? "Playing" : sound.label
    }

    private var napStatus: String? {
        guard let nap = naps.activeNap else { return nil }
        switch nap.wakeKind {
        case .alarmKit: return "AlarmKit"
        case .notification: return "Notification"
        case .unavailable: return "No wake"
        case nil: return "Arming"
        }
    }

    private var windDownStatus: String? {
        TonightRoutineController.shared.active ? "On" : nil
    }

    private var snoreStatus: String? {
        switch snore.state {
        case .listening, .background: "Listening"
        case .interrupted: "Interrupted"
        case .resuming, .preparing: "Resuming"
        default: nil
        }
    }

    private func tile(_ title: String, symbol: String, tint: Color, status: String?) -> some View {
        customTile(
            title,
            icon: Image(systemName: symbol)
                .font(Theme.text(20))
                .foregroundStyle(tint)
                .breathing(status != nil, tint: tint),
            tint: tint,
            status: status
        )
    }

    private func customTile(_ title: String, icon: some View, tint: Color, status: String?) -> some View {
        VStack(spacing: 8) {
            icon
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(Theme.label(11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .frame(width: typeSize.isAccessibilitySize ? 96 : 76)
            if let status {
                Text(status)
                    .font(Theme.label(10, weight: .medium))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .glassCard(padding: 0)
        .accessibilityLabel(status.map { "\(title). \($0)" } ?? title)
    }
}

#Preview("Sleep Tools") {
    NavigationStack {
        SleepToolsStrip()
            .padding()
            .nightBackground()
    }
    .zoonPreviewEnvironment()
}
