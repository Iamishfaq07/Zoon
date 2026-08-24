import SwiftUI
import Charts

/// Estimated sleep debt on its own screen: the running balance, the last
/// few nights' contribution to it, and what it means.
struct SleepDebtView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Set only when pushed from `CoreIntelligenceGrid`'s tile -- see
    /// `SleepNeedView`'s doc comment on the same pair of properties.
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    private var currentDebt: Double { coordinator.state.context?.night.sleepDebtMinutes ?? 0 }

    private var band: (label: String, tint: Color) {
        switch currentDebt {
        case ..<30: ("Minimal", Theme.Metric.recoveryHigh)
        case 30..<120: ("Mild", Theme.Metric.battery)
        case 120..<240: ("Moderate", Theme.Metric.recoveryMid)
        default: ("High", Theme.Metric.recoveryLow)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                hero
                recentNightsCard
                trendChart
                explanationCard
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Sleep Debt")
        .navigationBarTitleDisplayMode(.inline)
        .navigationTransition(zoomNamespace == nil ? .automatic : .zoom(sourceID: zoomID ?? "", in: zoomNamespace!))
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text("Estimated sleep debt")
                .font(Theme.label(13))
                .foregroundStyle(.secondary)
            Text(SleepNightFeatures.formatMinutes(currentDebt))
                .font(Theme.numeral(46))
                .monospacedDigit()
                .foregroundStyle(band.tint)
            StatusPill(text: band.label, tint: band.tint)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var recentNightsCard: some View {
        let nights = Array(coordinator.recentNights.suffix(5)).reversed()
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent nights", systemImage: "list.bullet")
            ForEach(Array(nights), id: \.date) { night in
                HStack {
                    Text(night.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        .font(Theme.label(12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(SleepNightFeatures.formatMinutes(night.sleepDebtMinutes ?? 0) + " owed")
                        .font(Theme.label(12, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .glassCard()
    }

    @State private var selectedDate: Date?

    @ViewBuilder
    private var trendChart: some View {
        let nights = Array(coordinator.recentNights.suffix(30))
        if nights.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Running balance, last 30 nights", systemImage: "chart.line.uptrend.xyaxis")
                Chart {
                    ForEach(nights, id: \.date) { night in
                        AreaMark(
                            x: .value("Date", night.date, unit: .day),
                            y: .value("Debt", (night.sleepDebtMinutes ?? 0) / 60)
                        )
                        .foregroundStyle(
                            .linearGradient(colors: [band.tint.opacity(0.4), band.tint.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                        )
                        LineMark(
                            x: .value("Date", night.date, unit: .day),
                            y: .value("Debt", (night.sleepDebtMinutes ?? 0) / 60)
                        )
                        .foregroundStyle(band.tint)
                    }

                    if let selectedDate, let night = nights.nearest(toDay: selectedDate) {
                        RuleMark(x: .value("Selected", night.date, unit: .day))
                            .foregroundStyle(Theme.neutral(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [(
                                        "Owed",
                                        SleepNightFeatures.formatMinutes(night.sleepDebtMinutes ?? 0),
                                        band.tint
                                    )]
                                )
                            }
                    }
                }
                .chartYAxisLabel("hours owed")
                .frame(height: 110)
                .chartXSelection(value: $selectedDate)
            }
            .glassCard()
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What this number means", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                A running shortfall against your sleep goal -- a planning figure, not a direct \
                physiological measurement. Recent nights count most; older ones fade out \
                gradually rather than dropping off all at once. A single long night doesn't \
                erase it -- there's no one-for-one repayment -- but consistently adequate nights \
                bring the balance down over time.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Sleep Debt") {
    NavigationStack { SleepDebtView() }
        .zoonPreviewEnvironment()
}
