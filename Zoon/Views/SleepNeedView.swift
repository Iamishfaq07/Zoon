import SwiftUI
import Charts

/// Tonight's estimated requirement, broken down into what it's built from.
struct SleepNeedView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var need: SleepNeed? { coordinator.state.context?.sleepNeed }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let need {
                    hero(need)
                    breakdownCard(need)
                    trendChart
                    explanationCard
                } else {
                    ContentUnavailableView("No night yet", systemImage: "moon.zzz")
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Need")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ need: SleepNeed) -> some View {
        VStack(spacing: 6) {
            Text("Tonight's estimated need")
                .font(Theme.label(13))
                .foregroundStyle(.secondary)
            Text(SleepNightFeatures.formatMinutes(need.totalNeedMinutes))
                .font(Theme.numeral(46))
                .monospacedDigit()
            StatusPill(text: confidenceLabel, tint: Theme.Metric.sleep)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var confidenceLabel: String {
        switch coordinator.recentNights.count {
        case ..<7: "Low confidence"
        case 7..<30: "Moderate confidence"
        default: "High confidence"
        }
    }

    private func breakdownCard(_ need: SleepNeed) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "What it's built from", systemImage: "list.bullet.rectangle")
            ForEach(need.contributions) { contribution in
                HStack {
                    Text(contribution.label)
                        .font(Theme.label(12))
                    Spacer()
                    Text((contribution.minutes >= 0 ? "+" : "−") + SleepNightFeatures.formatMinutes(abs(contribution.minutes)))
                        .font(Theme.label(13, weight: .semibold))
                        .monospacedDigit()
                }
            }
            Divider().overlay(Theme.cardStroke)
            HStack {
                Text("Total estimated need")
                    .font(Theme.label(12, weight: .bold))
                Spacer()
                Text(SleepNightFeatures.formatMinutes(need.totalNeedMinutes))
                    .font(Theme.label(13, weight: .bold))
                    .monospacedDigit()
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private var trendChart: some View {
        let nights = Array(coordinator.recentNights.suffix(30))
        if nights.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Actual sleep vs. goal", systemImage: "chart.bar")
                Chart {
                    ForEach(nights) { night in
                        BarMark(
                            x: .value("Date", night.date, unit: .day),
                            y: .value("Hours", night.timeAsleepMinutes / 60)
                        )
                        .foregroundStyle(Theme.Metric.sleep.opacity(0.85))
                        .cornerRadius(2)
                    }
                }
                .frame(height: 100)
            }
            .glassCard()
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How this is estimated", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Starts from your sleep goal in Settings, then adjusts up for outstanding sleep \
                debt and yesterday's exertion, and down for any naps -- so a harder day or a \
                short night genuinely raises tonight's target instead of treating every night \
                the same.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Sleep Need") {
    NavigationStack { SleepNeedView() }
        .zoonPreviewEnvironment()
}
