import SwiftUI

/// Today's estimated energy curve — RISE's daily schedule, in one row.
struct EnergyForecastCard: View {
    let forecast: EnergyForecast

    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Today's Energy",
                    subtitle: "Estimated from your wake time" + (forecast.isGenericWindDown ? "" : " and body clock"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Today's Energy",
                    symbol: "chart.line.uptrend.xyaxis",
                    tint: Theme.Metric.battery,
                    explanation: [
                        "A heuristic estimate, not a measurement -- nothing on a wrist measures circadian phase directly. This models the well-documented shape most people's alertness follows through a day: rising after sleep inertia clears, peaking mid-morning, dipping mid-afternoon, a second rise in the evening, then winding down.",
                        "Anchored to when you actually woke up today, nudged by how much sleep debt you're carrying. Treat it as a rough guide to when focus and rest might come easiest, not a schedule to follow exactly."
                    ]
                )
            }

            HStack(spacing: 0) {
                ForEach(forecast.windows) { window in
                    VStack(spacing: 4) {
                        Image(systemName: window.kind.symbol)
                            .font(Theme.text(15))
                            .foregroundStyle(tint(for: window.kind))
                        Text(window.time, format: .dateTime.hour().minute())
                            .font(Theme.label(11, weight: .semibold))
                            .monospacedDigit()
                        Text(window.kind.label)
                            .font(Theme.text(8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .glassCard()
    }

    private func tint(for kind: EnergyForecast.Window.Kind) -> Color {
        switch kind {
        case .morningRise, .eveningRise: Theme.Metric.battery
        case .morningPeak: Theme.Metric.recoveryHigh
        case .afternoonDip: Theme.Metric.recoveryMid
        case .windDown: Theme.Metric.sleep
        }
    }
}

#Preview("Energy Forecast") {
    ScrollView {
        EnergyForecastCard(forecast: EnergyForecast.compute(
            wakeTime: .now.addingTimeInterval(-3 * 3600),
            sleepDebtMinutes: 45,
            windDownHour: -0.75
        ))
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
