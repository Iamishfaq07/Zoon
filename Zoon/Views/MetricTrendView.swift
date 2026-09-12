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
    @State private var asking: ChartQuestion?

    private var points: [(date: Date, value: Double)] {
        coordinator.recentNights.compactMap { night in
            guard let value = VitalsStatus.currentValue(kind, features: night) else { return nil }
            return (night.date, value)
        }
    }

    private var currentMetric: VitalsStatus.Metric? {
        coordinator.state.context?.vitals.metrics.first { $0.kind == kind }
    }

    /// The question for whatever is currently selected.
    ///
    /// Baseline and tolerance come from `VitalsStatus`, which computed both
    /// from the person's history under its own rules, rather than being
    /// re-derived from the handful of points on screen -- see
    /// `ChartQuestion.forVital`.
    private var selectedQuestion: ChartQuestion? {
        guard let selectedDate else { return nil }
        let plotted = points.map { ChartQuestion.Point(date: $0.date, value: $0.value) }
        guard let nearest = plotted.nearest(toDay: selectedDate, keyPath: \.date) else { return nil }
        return ChartQuestion.forVital(
            kind,
            selected: nearest,
            in: plotted,
            baseline: currentMetric?.baseline,
            tolerance: currentMetric?.tolerance,
            baselineNightCount: currentMetric?.sampleCount ?? 0
        )
    }

    /// The night the coach is otherwise grounded in. A chart question narrows
    /// that ground rather than replacing it, so the most recent night is the
    /// right one even when an older point is selected.
    private var askedNight: SleepNightFeatures? { coordinator.recentNights.last }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                hero
                if points.count >= 3 {
                    chartCard
                    // Below the card, not inside it: a button in a Chart
                    // annotation competes with `chartXSelection`'s own drag
                    // recogniser for the same touches. Same placement and
                    // reasoning as the HRV card in Trends.
                    if let selectedQuestion {
                        AskZoonAboutChart(question: selectedQuestion) { asking = selectedQuestion }
                    }
                } else {
                    GatheringNights(
                        title: "Not enough history yet",
                        message: "Zoon needs a few more nights before it can chart a trend for \(kind.label.lowercased()).",
                        nights: points.count,
                        needed: 3
                    )
                    .padding(.top, 40)
                }
                evidenceCard
            }
            .padding()
        }
        .nightBackground()
        .askZoonSheet(about: $asking, night: askedNight)
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Text(kind.label)
                .font(Theme.label(13))
                .foregroundStyle(Theme.inkSecondary)
            Text(currentMetric?.formattedValue ?? "—")
                .font(Theme.numeral(40))
                .monospacedDigit()
            // Only once there is a baseline: "Typical" is the fallback state
            // for a reading with no history behind it, and showing it as a
            // pill turns that fallback into a verdict.
            if let metric = currentMetric, metric.baseline != nil {
                StatusPill(text: metric.state.label, tint: tint(for: metric.state))
            }
            if let range = currentMetric?.formattedRange {
                Text("Your typical range: \(range)")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
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

    /// The third tier of the Body Signals disclosure: what the typical range
    /// was actually built from.
    ///
    /// The first two tiers say what the signal means and what it reads. This
    /// one says how much is behind that -- how many nights, how far they can
    /// be trusted, and what the band literally is -- because "your typical
    /// range" from eight nights and from eighty are different claims wearing
    /// the same words. It is always shown, including when there is not enough
    /// history to chart, since that is exactly when the count matters most.
    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How this is measured", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            VStack(spacing: 6) {
                evidenceRow("Nights behind the baseline", sampleDescription)
                if let confidence = currentMetric?.confidence {
                    evidenceRow("Confidence", confidence.label)
                }
                if let baseline = currentMetric?.baseline {
                    evidenceRow("Your average", kind.format(baseline))
                }
                if let range = currentMetric?.formattedRange {
                    evidenceRow("Typical range", range)
                }
            }

            Text(method)
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func evidenceRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.evidence)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Says "not recorded" rather than "0 nights" when the count is missing,
    /// which happens for a status decoded from a backup written before the
    /// count was stored. Those are different facts.
    private var sampleDescription: String {
        guard let count = currentMetric?.sampleCount else { return "Not recorded" }
        return count == 1 ? "1 night" : "\(count) nights"
    }

    private var method: String {
        """
        Your typical range is the average of the last \(VitalsStatus.minimumNights)+ nights that carried a \
        \(kind.label.lowercased()) reading, plus or minus one standard deviation of those same nights. Nights \
        without a reading are left out rather than filled in. A value outside the band is an observation about \
        your own history, not a clinical finding.
        """
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
