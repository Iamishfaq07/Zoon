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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep Tools")
                .font(Theme.label(12, weight: .bold))
                .foregroundStyle(.tertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    NavigationLink {
                        SoundscapeView()
                    } label: {
                        tile("Sleep Sounds", symbol: "waveform", tint: Theme.Metric.battery)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        NapView()
                    } label: {
                        tile("Nap", symbol: "powersleep", tint: Theme.Metric.strain)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        BreathingView()
                    } label: {
                        tile("Wind Down", symbol: "wind", tint: Theme.Metric.recoveryHigh)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        SnoreCheckView()
                    } label: {
                        tile("Snore Check", symbol: "waveform.and.mic", tint: Theme.Metric.hrv)
                    }
                    .buttonStyle(PressableStyle())

                    NavigationLink {
                        BreathingHealthView()
                    } label: {
                        tile("Breathing", symbol: "lungs.fill", tint: Theme.Metric.sleep)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func tile(_ title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(Theme.text(20))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(Theme.label(11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 76)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .glassCard(padding: 0)
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
