import SwiftUI

/// The explainable score: a number, a band, and — the whole point of it — a
/// "why" that sums to the number instead of gesturing at it.
///
/// Deliberately additive to the existing Recovery ring and Sleep Score rather
/// than replacing either. Those are established, referenced elsewhere (the
/// widget, previews, the hero ring), and this is a new, separately-versioned
/// model sitting alongside them — not a rip-and-replace.
struct SleepIntelligenceCard: View {
    let score: SleepIntelligenceScore

    @State private var expanded = false

    private var tint: Color {
        switch score.band {
        case .poor: Theme.Metric.recoveryLow
        case .fair: Theme.Metric.recoveryMid
        case .good: Theme.Metric.battery
        case .excellent: Theme.Metric.recoveryHigh
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Sleep Intelligence",
                    subtitle: score.confidence == .insufficient
                        ? "Not enough data tonight to score confidently."
                        : "\(score.confidence.label) · \(score.dataCompletenessPercent)% of the model ran",
                    systemImage: "brain.head.profile"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Sleep Intelligence Score",
                    symbol: "brain.head.profile",
                    tint: tint,
                    explanation: [
                        "Combines seven components -- Duration, Continuity, Regularity, Recovery, Circadian timing, Breathing, and Sleep Architecture -- each measured against your own recent history, not a fixed target.",
                        "A component with no data tonight (no HRV sensor, not enough history for a body clock yet) is left out and the rest are reweighted to fill 100% -- missing data never counts against you."
                    ]
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(score.percent)")
                    .font(Theme.numeral(46))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(score.band.label)
                    .font(Theme.label(16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                Haptics.tap()
            } label: {
                HStack(spacing: 5) {
                    Text(expanded ? "Hide the breakdown" : "Why wasn't it higher?")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.text(10, weight: .semibold))
                }
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)

            if expanded {
                breakdown
            }
        }
        .glassCard()
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.cardStroke)

            if !score.positiveContributors.isEmpty {
                contributorGroup("What helped", score.positiveContributors, positive: true)
            }
            if !score.negativeContributors.isEmpty {
                contributorGroup("What held you back", score.negativeContributors, positive: false)
            }
            if score.positiveContributors.isEmpty && score.negativeContributors.isEmpty {
                Text("Every component landed close to neutral tonight -- nothing stood out either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func contributorGroup(_ title: String, _ items: [SleepIntelligenceScore.Component], positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label(11, weight: .bold))
                .foregroundStyle(.tertiary)
            ForEach(items) { component in
                HStack(spacing: 8) {
                    Image(systemName: positive ? "checkmark" : "minus")
                        .font(Theme.text(10, weight: .bold))
                        .foregroundStyle(positive ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                        .frame(width: 14)
                    Text(component.label)
                        .font(Theme.label(12, weight: .medium))
                    Text(component.detail)
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(String(format: "%+.0f", component.pointContribution))
                        .font(Theme.text(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(positive ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                }
            }
        }
    }
}

#Preview("Sleep Intelligence") {
    ScrollView {
        SleepIntelligenceCard(score: AppMockData.dayContext().sleepIntelligence)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
