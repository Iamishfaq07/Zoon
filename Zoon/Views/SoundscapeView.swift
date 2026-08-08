import SwiftUI

/// Sleep sounds with a fading timer.
struct SoundscapeView: View {

    @Environment(SoundscapeEngine.self) private var engine

    private let timerOptions: [Int?] = [nil, 15, 30, 45, 60, 90]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                nowPlaying
                grid
                timerCard
                explanation
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Sleep Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Now playing

    @ViewBuilder
    private var nowPlaying: some View {
        if let sound = engine.playing {
            VStack(spacing: 14) {
                AudioWaveform(isActive: true)
                    .frame(height: 56)

                Text(sound.label)
                    .font(Theme.numeral(26))

                if engine.timerMinutes != nil {
                    Text(engine.formattedRemaining)
                        .font(Theme.label(15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Metric.battery)
                }

                volumeSlider

                Button {
                    engine.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(Theme.label(14, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .glassCard()
        }
    }

    private var volumeSlider: some View {
        @Bindable var engine = engine
        return HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Slider(value: $engine.volume, in: 0...1)
                .tint(Theme.Metric.battery)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(SoundscapeEngine.Sound.allCases) { sound in
                soundTile(sound)
            }
        }
    }

    private func soundTile(_ sound: SoundscapeEngine.Sound) -> some View {
        let isActive = engine.playing == sound

        return Button {
            engine.play(sound)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: sound.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(isActive ? Theme.Metric.battery : .secondary)
                    .symbolEffect(.variableColor.iterative, isActive: isActive)

                Text(sound.label)
                    .font(Theme.label(14, weight: .semibold))

                Text(sound.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? Theme.Metric.battery.opacity(0.18) : Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isActive ? Theme.Metric.battery : Theme.cardStroke,
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Timer

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Sleep Timer",
                subtitle: "Fades out over the last minute rather than cutting — an abrupt stop can wake you.",
                systemImage: "timer"
            )

            FlowLayout(spacing: 8) {
                ForEach(Array(timerOptions.enumerated()), id: \.offset) { _, option in
                    timerChip(option)
                }
            }
        }
        .glassCard()
    }

    private func timerChip(_ minutes: Int?) -> some View {
        let isSelected = engine.timerMinutes == minutes
        let label = minutes.map { "\($0)m" } ?? "Off"

        return Button {
            engine.setTimer(minutes: minutes)
        } label: {
            Text(label)
                .font(Theme.label(13, weight: .semibold))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background {
                    Capsule()
                        .fill(isSelected ? Theme.Metric.battery.opacity(0.28) : Color.white.opacity(0.06))
                        .overlay {
                            Capsule().strokeBorder(
                                isSelected ? Theme.Metric.battery : Theme.cardStroke,
                                lineWidth: 1
                            )
                        }
                }
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(!engine.isPlaying)
        .opacity(engine.isPlaying ? 1 : 0.45)
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Generated on device", systemImage: "cpu")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(Theme.Metric.battery)
            Text("""
                Every sound here is synthesised in real time rather than streamed or \
                played from a file. Nothing is downloaded, and because the audio is \
                generated continuously there's no loop to notice.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

/// Animated bars that respond to nothing in particular.
///
/// Honest about what it is: a *motion* indicator, not a level meter. Tapping the
/// real output buffer to drive it would mean an audio-thread read on every frame
/// for a decoration nobody is looking at while asleep.
struct AudioWaveform: View {
    let isActive: Bool

    @State private var phase: Double = 0

    private let barCount = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isActive)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let barWidth = size.width / CGFloat(barCount) * 0.55
                let spacing = size.width / CGFloat(barCount)

                for index in 0..<barCount {
                    // Two detuned sines per bar so the pattern doesn't visibly
                    // repeat across the row.
                    let offset = Double(index) * 0.45
                    let wave = sin(time * 1.9 + offset) * 0.5 + sin(time * 0.7 + offset * 1.7) * 0.5
                    let height = size.height * (0.18 + abs(wave) * 0.4)

                    let rect = CGRect(
                        x: CGFloat(index) * spacing + (spacing - barWidth) / 2,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )

                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .linearGradient(
                            Gradient(colors: [Theme.Metric.battery, Theme.Metric.sleep]),
                            startPoint: CGPoint(x: rect.minX, y: rect.minY),
                            endPoint: CGPoint(x: rect.minX, y: rect.maxY)
                        )
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Soundscapes") {
    NavigationStack {
        SoundscapeView()
    }
    .environment(SoundscapeEngine())
    .preferredColorScheme(.dark)
}
