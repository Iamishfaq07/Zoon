import SwiftUI

/// "Sleep / Need / Debt" -- the redesign spec's floating metric cluster,
/// meant to sit directly under the Sleep Intelligence hero.
///
/// Distinct from `SleepSummaryStrip` further down the screen: that's a card
/// leading to the full night detail (hypnogram, navigation chevron); this is
/// three glanceable numbers that also tap through to the screen that
/// explains each one -- Sleep to tonight's full detail, Need and Debt to
/// their own standing analytical screens (the same ones `CoreIntelligenceGrid`
/// links to from Insights).
struct FloatingMetricCluster: View {
    let context: DayContext
    let timeAsleepMinutes: Double
    let needMinutes: Double
    let debtMinutes: Double

    var body: some View {
        AdaptiveStack(spacing: 10) {
            pill(label: "Sleep", value: SleepNightFeatures.formatMinutes(timeAsleepMinutes), tint: Theme.Metric.sleep) {
                SleepDetailView(context: context)
            }
            pill(label: "Need", value: SleepNightFeatures.formatMinutes(needMinutes), tint: Theme.Metric.recoveryHigh) {
                SleepNeedView()
            }
            pill(
                label: "Debt",
                value: debtMinutes > 1 ? SleepNightFeatures.formatMinutes(debtMinutes) : "None",
                tint: debtMinutes > 1 ? Theme.Metric.recoveryMid : Theme.Metric.recoveryHigh
            ) {
                SleepDebtView()
            }
        }
    }

    private func pill<Destination: View>(
        label: String,
        value: String,
        tint: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
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
        .buttonStyle(.plain)
    }
}

#Preview("Floating Metric Cluster") {
    NavigationStack {
        FloatingMetricCluster(
            context: AppMockData.dayContext(),
            timeAsleepMinutes: 467,
            needMinutes: 492,
            debtMinutes: 104
        )
        .padding()
    }
    .nightBackground()
}
