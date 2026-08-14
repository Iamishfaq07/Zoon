import SwiftUI

/// "Sleep / Need / Debt" -- the redesign spec's floating metric cluster,
/// meant to sit directly under the Sleep Intelligence hero.
///
/// Distinct from `SleepSummaryStrip` further down the screen: that's a card
/// leading to the full night detail (hypnogram, navigation chevron); this is
/// three glanceable numbers with no navigation, answering "how did tonight
/// compare to what I need, and what's still owed" in one line.
struct FloatingMetricCluster: View {
    let timeAsleepMinutes: Double
    let needMinutes: Double
    let debtMinutes: Double

    var body: some View {
        AdaptiveStack(spacing: 10) {
            pill(label: "Sleep", value: SleepNightFeatures.formatMinutes(timeAsleepMinutes), tint: Theme.Metric.sleep)
            pill(label: "Need", value: SleepNightFeatures.formatMinutes(needMinutes), tint: Theme.Metric.recoveryHigh)
            pill(
                label: "Debt",
                value: debtMinutes > 1 ? SleepNightFeatures.formatMinutes(debtMinutes) : "None",
                tint: debtMinutes > 1 ? Theme.Metric.recoveryMid : Theme.Metric.recoveryHigh
            )
        }
    }

    private func pill(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(Theme.label(15, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(Theme.text(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .zoonGlassPill(tint: tint)
    }
}

#Preview("Floating Metric Cluster") {
    FloatingMetricCluster(timeAsleepMinutes: 467, needMinutes: 492, debtMinutes: 104)
        .padding()
        .nightBackground()
}
