import SwiftUI
import Charts

/// The weekly review — Whoop's Performance Assessment, Garmin's Morning Report.
struct ReportView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    private var report: WeeklyReport? { coordinator.weeklyReport() }

    @State private var selectedRecoveryDate: Date?

    /// Pushed from the More tab, so it supplies no `NavigationStack` of its
    /// own — the same contract `SettingsView` follows.
    ///
    /// It used to carry one. Nesting a stack inside a stack meant the push
    /// from More didn't land, which nothing revealed until a screenshot of
    /// `-zoonTab report` came back showing the More screen. Every route to
    /// this view goes through a tap, so it was invisible for as long as
    /// nobody could tap.
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let report {
                    header(report)
                    highlights(report)
                    averages(report)
                    recoveryChart
                    trendsCard
                    extremes(report)
                } else {
                    notEnoughData
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Weekly Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ report: WeeklyReport) -> some View {
        VStack(spacing: 6) {
            Text("\(report.periodStart, format: .dateTime.month().day()) – \(report.periodEnd, format: .dateTime.month().day())")
                .font(Theme.label(13))
                .foregroundStyle(.secondary)

            if let recovery = report.averageRecovery {
                Text("\(Int(recovery))%")
                    .font(Theme.numeral(50))
                    .monospacedDigit()
                    .foregroundStyle(Theme.recoveryColor(recovery))
                Text("average recovery across \(report.nightCount) nights")
                    .font(Theme.label(12))
                    .foregroundStyle(.secondary)
            }

            if let trend = report.recoveryTrend {
                StatusPill(
                    text: String(format: "%+.0f%% vs last week", trend),
                    systemImage: trend >= 0 ? "arrow.up.right" : "arrow.down.right",
                    tint: trend >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func highlights(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Highlights", systemImage: "sparkles")

            ForEach(report.highlights) { highlight in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: highlight.symbol)
                        .font(Theme.text(13))
                        .foregroundStyle(tint(highlight.tone))
                        .frame(width: 26, height: 26)
                        .background(tint(highlight.tone).opacity(0.15), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(highlight.title)
                            .font(Theme.label(13, weight: .semibold))
                        Text(highlight.detail)
                            .font(Theme.text(11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .glassCard()
    }

    private func tint(_ tone: WeeklyReport.Highlight.Tone) -> Color {
        switch tone {
        case .positive: Theme.Metric.recoveryHigh
        case .neutral: Theme.Metric.strain
        case .caution: Theme.Metric.recoveryMid
        }
    }

    private func averages(_ report: WeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Weekly Averages", systemImage: "chart.bar")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 12
            ) {
                if let sleep = report.averageSleepMinutes {
                    statTile("Sleep", SleepNightFeatures.formatMinutes(sleep),
                             trend: report.sleepTrend, color: Theme.Metric.sleep)
                }
                if let hrv = report.averageHRV {
                    statTile("HRV", "\(Int(hrv)) ms",
                             trend: report.hrvTrend, color: Theme.Metric.hrv)
                }
                if let rhr = report.averageRestingHR {
                    statTile("Resting HR", "\(Int(rhr)) bpm", trend: nil, color: Theme.Metric.heart)
                }
                statTile("Goal met", "\(report.goalHitCount)/\(report.nightCount)",
                         trend: nil, color: Theme.Metric.recoveryHigh)
            }
        }
        .glassCard()
    }

    private func statTile(_ label: String, _ value: String, trend: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(Theme.label(18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            if let trend {
                Text(String(format: "%+.0f%%", trend))
                    .font(Theme.text(10, weight: .semibold))
                    .foregroundStyle(trend >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var recoveryChart: some View {
        let points = coordinator.recentNights
            .compactMap { night -> (Date, Int)? in
                guard let value = coordinator.recoveryHistory[night.date] else { return nil }
                return (night.date, value)
            }
            .suffix(14)

        if points.count >= 3 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recovery, last 14 days", systemImage: "bolt.heart")

                Chart {
                    ForEach(Array(points), id: \.0) { date, value in
                        BarMark(
                            x: .value("Date", date, unit: .day),
                            y: .value("Recovery", value)
                        )
                        .foregroundStyle(Theme.recoveryColor(Double(value)))
                        .cornerRadius(3)
                    }
                    // The 67% line is the boundary between moderate and high —
                    // the level above which hard training is a good idea.
                    RuleMark(y: .value("High", 67))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.white.opacity(0.25))

                    if let selectedRecoveryDate,
                       let match = points.first(where: {
                           Calendar.current.isDate($0.0, inSameDayAs: selectedRecoveryDate)
                       }) {
                        RuleMark(x: .value("Selected", match.0, unit: .day))
                            .foregroundStyle(.white.opacity(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: match.0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [("Recovery", "\(match.1)%", Theme.recoveryColor(Double(match.1)))]
                                )
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0.0, 50.0, 100.0]) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.07))
                        AxisValueLabel().font(Theme.text(9)).foregroundStyle(.tertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisValueLabel(format: .dateTime.day())
                            .font(Theme.text(9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(height: 150)
                .chartXSelection(value: $selectedRecoveryDate)
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private var trendsCard: some View {
        let trends = TrendEngine.detect(nights: coordinator.recentNights)
        if !trends.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: "What Changed",
                    subtitle: "Meaningful shifts only -- small night-to-night noise is filtered out.",
                    systemImage: "arrow.up.arrow.down"
                )
                ForEach(trends.prefix(4)) { trend in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: trend.isImprovement ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                            .font(Theme.text(14))
                            .foregroundStyle(trend.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                        Text(trend.sentence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .glassCard()
        }
    }

    @ViewBuilder
    private func extremes(_ report: WeeklyReport) -> some View {
        if let best = report.bestNight, let worst = report.worstNight, best.date != worst.date {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Best & Worst", systemImage: "arrow.up.arrow.down")
                nightRow("Best night", best, tint: Theme.Metric.recoveryHigh)
                Divider().overlay(Theme.cardStroke)
                nightRow("Worst night", worst, tint: Theme.Metric.recoveryLow)
            }
            .glassCard()
        }
    }

    private func nightRow(_ label: String, _ night: SleepNightFeatures, tint: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
                Text(night.date, format: .dateTime.weekday(.wide))
                    .font(Theme.label(13, weight: .semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(night.formattedTimeAsleep)
                    .font(Theme.label(15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("\(Int(night.sleepEfficiencyPercent))% efficiency")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var notEnoughData: some View {
        ContentUnavailableView {
            Label("Not enough history", systemImage: "calendar")
        } description: {
            Text("Your weekly report appears once Zoon has recorded a few nights.")
        }
        .padding(.top, 60)
    }
}

#Preview("Report") {
    ReportView().zoonPreviewEnvironment()
}
