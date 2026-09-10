import SwiftUI

/// Sounds as a Sleep-tab surface, not a tool tile under the night.
struct SleepSoundsHero: View {
    @Environment(SoundscapeEngine.self) private var engine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZoonSectionHeader("Sounds") {
                NavigationLink {
                    SoundscapeView()
                } label: {
                    HStack(spacing: 3) {
                        Text("Catalog")
                        Image(systemName: "chevron.right").font(Theme.text(10, weight: .semibold))
                    }
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.Family.sleep)
                }
                .buttonStyle(.plain)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.label)
                        .font(Theme.label(16, weight: .semibold))
                    Text(engine.isPlaying ? "Playing" : subtitle)
                        .font(Theme.text(13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Haptics.select()
                    if engine.isPlaying {
                        engine.stop()
                    } else {
                        engine.play(current, toggle: false)
                    }
                } label: {
                    Text(engine.isPlaying ? "Pause" : "Play")
                        .font(Theme.label(13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.Family.sleep, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var current: SoundscapeEngine.Sound {
        engine.playing ?? .rain
    }

    private var subtitle: String {
        current.fileName == nil ? "Generated, seamless" : "Recorded bed"
    }
}
