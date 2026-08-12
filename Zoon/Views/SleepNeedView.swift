import SwiftUI
import Charts

/// Tonight's estimated requirement, broken down into what it's built from.
struct SleepNeedView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    private var need: SleepNeed? { coordinator.state.context?.sleepNeed }
    private var learned: LearnedSleepNeed? { coordinator.state.context?.learnedSleepNeed }

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
            StatusPill(text: learned?.confidence.label ?? "Low confidence", tint: Theme.Metric.sleep)
            if let learned, let learnedMinutes = learned.learnedMinutes {
                Text("Based on \(learned.qualifyingNightCount) qualifying nights -- your own baseline is estimated at \(SleepNightFeatures.formatMinutes(learnedMinutes)), blended with your goal below.")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
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

    @State private var selectedDate: Date?

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

                    if let selectedDate, let night = nights.nearest(toDay: selectedDate) {
                        RuleMark(x: .value("Selected", night.date, unit: .day))
                            .foregroundStyle(Theme.neutral(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [("Asleep", night.formattedTimeAsleep, Theme.Metric.sleep)]
                                )
                            }
                    }
                }
                .frame(height: 100)
                .chartXSelection(value: $selectedDate)
            }
            .glassCard()
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How this is estimated", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(learnedExplanationText)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var learnedExplanationText: String {
        let base: String
        if let learned, learned.learnedMinutes != nil {
            base = """
                The baseline starts from your own recent history rather than just your goal: \
                the typical duration of your efficient, unfragmented, well-measured nights \
                (\(learned.qualifyingNightCount) of them so far), blended with your Settings \
                goal -- more weight on your own history the more qualifying nights you have, \
                up to \(LearnedSleepNeed.fullConfidenceNights).
                """
        } else {
            base = """
                Starts from your sleep goal in Settings. Once you have \
                \(LearnedSleepNeed.minimumQualifyingNights) or more nights of efficient, \
                well-measured sleep, this baseline starts blending in a figure learned from \
                your own history instead of relying on the goal alone.
                """
        }
        return base + """
             Then it adjusts up for outstanding sleep debt and yesterday's exertion, and down \
            for any naps -- so a harder day or a short night genuinely raises tonight's target \
            instead of treating every night the same.
            """
    }
}

#Preview("Sleep Need") {
    NavigationStack { SleepNeedView() }
        .zoonPreviewEnvironment()
}
