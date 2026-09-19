import SwiftUI

/// Where a vital sits against its own long-run baseline, and for how long.
///
/// `LongTermResilience` shipped with tests and no caller, so none of this
/// reached a screen. The engine is unchanged; this is the surface it was
/// missing.
///
/// Deliberately not a "biological age" or a fitness grade. It reports a
/// distance from the person's own baseline over a window they pick, and how
/// many consecutive days that distance has held — both facts, neither a
/// verdict.
struct LongTermBaselineCard: View {
    let signals: [LongTermResilience.Signal]
    @Binding var window: LongTermResilience.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Long-term baselines",
                subtitle: "Your own history, not a population range.",
                systemImage: "chart.xyaxis.line"
            )

            Picker("Window", selection: $window) {
                ForEach(LongTermResilience.Window.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .adaptiveSegmentedStyle()
            .onChange(of: window) { _, _ in Haptics.select() }

            ForEach(signals, id: \.name) { signal in
                row(signal)
                if signal.name != signals.last?.name {
                    Rectangle().fill(Theme.cardStroke).frame(height: 1)
                }
            }
        }
        .glassCard()
    }

    private func row(_ signal: LongTermResilience.Signal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint(for: signal))
                    .frame(width: 7, height: 7)
                Text(signal.name.capitalized)
                    .font(Theme.label(13, weight: .semibold))
                Spacer(minLength: 6)
                Text(signal.confidence.label)
                    .font(Theme.text(10))
                    .foregroundStyle(Theme.inkTertiary)
            }
            Text(signal.sentence)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(signal.name). \(signal.sentence) \(signal.confidence.label).")
    }

    /// Neutral when the value sits inside its own tolerance band. A metric
    /// resting at its baseline is the ordinary case and should not be
    /// coloured as if something had happened.
    private func tint(for signal: LongTermResilience.Signal) -> Color {
        switch signal.favourable {
        case true: Theme.Metric.recoveryHigh
        case false: Theme.Metric.recoveryMid
        case nil: Theme.inkSecondary
        }
    }
}
