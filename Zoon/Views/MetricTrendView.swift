import SwiftUI
import Charts

/// One vital's own history -- the "tap → trend" the redesign spec asks for
/// on every `HealthRadarView` baseline row, which previously had no action
/// at all. Generic over `VitalsStatus.Kind` rather than one screen per
/// vital, since all seven share the same shape: a line of recent nights
/// against the personal typical band `VitalsStatus.evaluate` already
/// computes for that same row.
struct MetricTrendView: View {

    let kind: VitalsStatus.Kind

    @Environment(SleepDataCoordinator.self) private var coordinator
    @State private var selectedDate: Date?

    private var points: [(date: Date, value: Double)] {
        coordinator.recentNights.compactMap { night in
            guard let value = VitalsStatus.currentValue(kind, features: night) else { return nil }
            return (night.date, value)
        }
    }

    private var currentMetric: VitalsStatus.Metric? {
        coordinator.state.context?.vitals.metrics.first { $0.kind == kind }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                hero
                if points.count >= 3 {
                    chartCard
                } else {
                    ContentUnavailableView(
                        "Not enough history yet",
                        systemImage: kind.symbol,
                        description: Text("Zoon needs a few more nights before it can chart a trend for \(kind.label.lowercased()).")
                    )
                    .padding(.top, 40)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text(kind.label)
                .font(Theme.label(13))
                .foregroundStyle(.secondary)
            Text(currentMetric?.formattedValue ?? "—")
                .font(Theme.numeral(40))
                .monospacedDigit()
            if let metric = currentMetric {
                StatusPill(text: metric.state.label, tint: tint(for: metric.state))
            }
            if let range = currentMetric?.formattedRange {
                Text("Your typical range: \(range)")
                    .font(Theme.text(11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private var chartCard: some View {
        let sorted = points.sorted { $0.date < $1.date }

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent nights", systemImage: "chart.line.uptrend.xyaxis")
            Chart {
                ForEach(sorted, id: \.date) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(kind.label, point.value)
                    )
                    .foregroundStyle(Theme.Metric.hrv)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value(kind.label, point.value)
                    )
                    .foregroundStyle(Theme.Metric.hrv)
                    .symbolSize(18)
                }

                if let baseline = currentMetric?.baseline {
                    RuleMark(y: .value("Typical", baseline))
                        .foregroundStyle(Theme.neutral(0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }

                if let selectedDate, let point = sorted.nearest(toDay: selectedDate, keyPath: \.date) {
                    RuleMark(x: .value("Selected", point.date, unit: .day))
                        .foregroundStyle(Theme.neutral(0.25))
                        .annotation(
                            position: .top,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                        ) {
                            ChartSelectionBadge(
                                title: point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                lines: [(kind.label, kind.format(point.value), Theme.Metric.hrv)]
                            )
                        }
                }
            }
            .frame(height: 140)
            .chartXSelection(value: $selectedDate)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(kind.label) over the last \(sorted.count) nights")
            .accessibilityValue(selectedPointDescription(in: sorted) ?? "")
        }
        .glassCard()
    }

    private func selectedPointDescription(in sorted: [(date: Date, value: Double)]) -> String? {
        guard let selectedDate, let point = sorted.nearest(toDay: selectedDate, keyPath: \.date) else { return nil }
        let day = point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return "\(day): \(kind.format(point.value))"
    }

    private func tint(for state: VitalsStatus.State) -> Color {
        switch state {
        case .typical: Theme.Metric.recoveryHigh
        case .aboveTypical, .belowTypical: Theme.Metric.recoveryMid
        case .unavailable: .secondary
        }
    }
}

private extension Array {
    /// Same closest-by-day match `[SleepNightFeatures].nearest(toDay:)` uses,
    /// generalized over any element with a `Date` field via a key path --
    /// this array is `(date: Date, value: Double)`, not `SleepNightFeatures`.
    func nearest(toDay day: Date, keyPath: KeyPath<Element, Date>) -> Element? {
        let calendar = Calendar.current
        return self.first { calendar.isDate($0[keyPath: keyPath], inSameDayAs: day) }
            ?? self.min { abs($0[keyPath: keyPath].timeIntervalSince(day)) < abs($1[keyPath: keyPath].timeIntervalSince(day)) }
    }
}

#Preview("HRV Trend") {
    NavigationStack { MetricTrendView(kind: .hrv) }
        .zoonPreviewEnvironment()
}
