import SwiftUI

/// When a Coach question is about a metric Zoon actually tracks, the answer
/// shows that metric — as the same baseline lane the rest of the app draws —
/// instead of describing it in prose.
///
/// ```
/// ANSWER      Mostly stable.
/// CHART       [baseline lane]
/// EVIDENCE    30-night median 51 ms · previous 53 ms
/// ```
///
/// **Every number here is computed, never generated.** The model's text
/// stays in the answer paragraph above this view; the chart, the medians and
/// the window are read from `VitalsStatus` and `TrendEngine` — the same
/// engines Body Signals and Insights read. That split is the whole point: a
/// language model asked to recall "your HRV was 51" will sometimes say 52,
/// and a chart drawn from generated numbers would be a fabrication wearing
/// the visual authority of a chart.
///
/// Which metric to show is decided by keyword match on the *user's own
/// question*, not by asking the model to name one. A missed match shows no
/// chart, which is the safe failure; a wrong match would attach a confident
/// visual to the wrong question.
struct CoachDataAnswer: View {
    /// The question the user asked, used only to pick a metric.
    let question: String

    @Environment(SleepDataCoordinator.self) private var coordinator

    var body: some View {
        if let kind = Self.metric(in: question), let metric = metric(for: kind) {
            VStack(alignment: .leading, spacing: 12) {
                lane(metric, kind: kind)
                if let evidence = evidence(for: kind) {
                    evidenceBlock(evidence)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Chart

    private func metric(for kind: VitalsStatus.Kind) -> VitalsStatus.Metric? {
        coordinator.state.context?.vitals.metrics.first { $0.kind == kind && $0.value != nil }
    }

    /// Reuses `ZoonBaselineLane` rather than drawing a Coach-specific chart:
    /// the redesign's rule is that HRV looks the same everywhere it appears,
    /// and a coach that invents its own visual for a metric the user already
    /// recognises from Body Signals makes them learn it twice.
    private func lane(_ metric: VitalsStatus.Metric, kind: VitalsStatus.Kind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.label)
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            ZoonBaselineLane(metric: metric)
        }
    }

    // MARK: - Evidence

    /// The trend the app already detected for this metric, if it maps onto a
    /// `TrendEngine.Metric`. Not every vital does -- blood oxygen and
    /// breathing disturbances have no trend metric -- and where there is
    /// none, the lane stands alone rather than inventing a comparison.
    private func evidence(for kind: VitalsStatus.Kind) -> TrendEngine.Result? {
        guard let trendMetric = Self.trendMetric(for: kind) else { return nil }
        return TrendEngine.detect(nights: coordinator.recentNights)
            .first { $0.metric == trendMetric }
    }

    private func evidenceBlock(_ result: TrendEngine.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Evidence")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(result.sentence)
                .font(Theme.evidence)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Question → metric

    /// Keyword match, deliberately narrow.
    ///
    /// Ordered so the most specific phrases win: "heart rate variability"
    /// must beat "heart rate", or every HRV question would draw a resting
    /// heart rate chart.
    static func metric(in question: String) -> VitalsStatus.Kind? {
        let text = question.lowercased()
        let table: [(needles: [String], kind: VitalsStatus.Kind)] = [
            (["heart rate variability", "hrv"], .hrv),
            (["resting heart rate", "resting hr", "heart rate", "pulse", "bpm"], .restingHeartRate),
            (["respiratory", "respiration", "breathing rate", "breaths"], .respiratoryRate),
            (["blood oxygen", "oxygen", "spo2", "saturation"], .oxygenSaturation),
            (["wrist temperature", "temperature"], .wristTemperature),
            (["breathing disturbance", "disturbance", "snor"], .breathingDisturbances),
            (["sleep duration", "hours of sleep", "total sleep"], .sleepDuration),
        ]
        for entry in table where entry.needles.contains(where: text.contains) {
            return entry.kind
        }
        return nil
    }

    /// The `TrendEngine` metric covering the same signal, where one exists.
    static func trendMetric(for kind: VitalsStatus.Kind) -> TrendEngine.Metric? {
        switch kind {
        case .hrv: .hrv
        case .restingHeartRate: .restingHeartRate
        case .sleepDuration: .duration
        case .respiratoryRate, .oxygenSaturation, .wristTemperature, .breathingDisturbances: nil
        }
    }
}

#Preview("Coach data answer") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            CoachDataAnswer(question: "Is my HRV falling?")
            CoachDataAnswer(question: "What about my resting heart rate?")
            // No metric in the question: renders nothing, by design.
            CoachDataAnswer(question: "Should I train today?")
        }
        .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}
