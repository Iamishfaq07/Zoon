import SwiftUI

/// Recovery and sleep performance, averaged by estimated cycle timing.
///
/// Only ever shown when the user has opted into cycle tracking and logged at
/// least one period start in Health — both gates live in the caller, not
/// here, so this view can assume it has something to draw.
struct CycleCorrelationCard: View {
    let correlations: [CyclePhaseCorrelation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Estimated Cycle Context",
                subtitle: "Broad timing bands based on your recorded cycle history.",
                systemImage: "circle.hexagongrid.circle"
            )

            ForEach(correlations) { row in
                HStack(spacing: 10) {
                    Text(row.phase.label)
                        .font(Theme.label(12, weight: .medium))
                        .frame(width: 78, alignment: .leading)

                    if let recovery = row.avgRecoveryPercent {
                        barRow(
                            label: "Recovery",
                            value: recovery,
                            tint: Theme.recoveryColor(recovery)
                        )
                    }
                }
                if let sleep = row.avgSleepPerformance {
                    HStack {
                        Spacer().frame(width: 78)
                        barRow(label: "Sleep", value: sleep, tint: Theme.Metric.sleep)
                    }
                }
                Text("\(row.nightCount) nights")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.leading, 78)
                if row.id != correlations.last?.id {
                    Divider().overlay(Theme.cardStroke).padding(.vertical, 2)
                }
            }

            Text("These are calendar estimates, not detected physiological phases or ovulation. Irregular histories remain unclassified.")
                .font(.caption2)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func barRow(label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                Capsule()
                    .fill(tint.opacity(0.8))
                    .frame(width: geo.size.width * min(1, value / 100))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(Theme.neutral(0.08)))
            }
            .frame(height: 8)

            Text("\(Int(value.rounded()))")
                .font(Theme.text(11))
                .monospacedDigit()
                .foregroundStyle(Theme.inkSecondary)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

#Preview("Cycle Correlation") {
    CycleCorrelationCard(correlations: [
        CyclePhaseCorrelation(phase: .periodDays, nightCount: 4, avgRecoveryPercent: 52, avgSleepPerformance: 78),
        CyclePhaseCorrelation(phase: .earlier, nightCount: 8, avgRecoveryPercent: 71, avgSleepPerformance: 88),
        CyclePhaseCorrelation(phase: .middle, nightCount: 3, avgRecoveryPercent: 68, avgSleepPerformance: 84),
        CyclePhaseCorrelation(phase: .later, nightCount: 10, avgRecoveryPercent: 58, avgSleepPerformance: 75)
    ])
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
