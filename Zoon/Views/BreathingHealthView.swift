import SwiftUI
import Charts

/// A dedicated breathing dashboard: respiratory rate vs. baseline, a
/// breathing-disturbances trend, SpO2 trend, and snoring history all in one
/// place, instead of scattered one-line rows across other screens.
///
/// Screening/pattern information, explicitly not a diagnosis anywhere on
/// this screen -- see `BreathingHealth`'s doc comment for why the repeated-
/// pattern check exists at all.
struct BreathingHealthView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    // Not injected via environment -- `SnoreCheckView` owns its data the same
    // way, a local instance backed by the same UserDefaults key, since
    // nothing else in the app currently shares a SnoreStore through the
    // environment.
    @State private var snore = SnoreStore()

    @State private var selectedDate: Date?

    private var health: BreathingHealth {
        BreathingHealth.compute(nights: coordinator.recentNights)
    }

    var body: some View {
        ScrollView {
            CascadeStack(spacing: Theme.stackSpacing) {
                respiratoryCard
                disturbanceCard
                oxygenCard
                snoringCard
                safetyCard
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Breathing")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Respiratory rate

    private var respiratoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Respiratory Rate", systemImage: "lungs.fill")

            if let rate = health.tonightRespiratoryRate {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.1f", rate))
                        .font(Theme.numeral(32))
                        .monospacedDigit()
                    Text("br/min")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer()
                    if let baseline = health.baselineRespiratoryRate {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Baseline \(String(format: "%.1f", baseline))")
                                .font(Theme.text(10))
                                .foregroundStyle(Theme.inkTertiary)
                            if let deviation = health.respiratoryDeviationPercent {
                                Text(String(format: "%+.0f%%", deviation))
                                    .font(Theme.label(12, weight: .semibold))
                                    .foregroundStyle(abs(deviation) < 8 ? Theme.inkSecondary : Theme.Metric.recoveryMid)
                            }
                        }
                    }
                }
            } else {
                Text("No respiratory rate reading for last night.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .glassCard()
    }

    // MARK: - Disturbances

    @ViewBuilder
    private var disturbanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(
                    title: "Breathing Disturbances",
                    subtitle: "Apple's overnight measure, in events per hour of sleep.",
                    systemImage: "waveform.path.ecg"
                )
                Spacer()
                StatusPill(text: health.pattern.label, tint: patternTint)
            }

            if health.disturbanceTrend.count < 2 {
                Text("Needs Apple Watch Series 9 or Ultra 2 or later, with the feature on.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                Chart {
                    ForEach(health.disturbanceTrend) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Events per hour", point.value)
                        )
                        .foregroundStyle(point.isElevated ? Theme.Metric.recoveryMid : Theme.Metric.sleep)
                        .cornerRadius(2)
                    }
                    if let selectedDate,
                       let point = health.disturbanceTrend.first(where: {
                           Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
                       }) {
                        RuleMark(x: .value("Selected", point.date, unit: .day))
                            .foregroundStyle(Theme.neutral(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [("Disturbances", String(format: "%.1f/h", point.value), Theme.Metric.sleep)]
                                )
                            }
                    }
                }
                .frame(height: 100)
                .chartXSelection(value: $selectedDate)
                // Higher disturbance is worse, so the trend helper is told
                // so -- otherwise a rising bar chart would be summarised as
                // an improvement.
                .chartSummary(
                    "Breathing disturbances, last \(health.disturbanceTrend.count) nights",
                    (health.disturbanceTrend.last.map {
                        "Last night \(String(format: "%.1f", $0.value)) events per hour. "
                    } ?? "")
                        + ChartTrend.describe(
                            health.disturbanceTrend.map(\.value), higherIsBetter: false
                        ) + "."
                )

                if case .repeatedPattern(let elevated, let window) = health.pattern {
                    // A row of nights, lit where it ran high, then one line.
                    HStack(spacing: 4) {
                        ForEach(0..<window, id: \.self) { index in
                            Capsule()
                                .fill(index < elevated ? Theme.Metric.recoveryMid : Theme.neutral(0.15))
                                .frame(height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                    Text("High on \(elevated) of \(window) nights. If this keeps up, mention it to a doctor.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .unclassified(let window) = health.pattern {
                    Text("Recorded on \(window) nights but not graded by Apple, so Zoon won't call any of it high.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassCard()
    }

    private var patternTint: Color {
        switch health.pattern {
        case .insufficientData: Theme.inkSecondary
        // Not a reassuring colour. Zoon has readings but no classification,
        // which is not the same as nothing being wrong.
        case .unclassified: Theme.inkSecondary
        case .normal: Theme.Metric.recoveryHigh
        case .repeatedPattern: Theme.Metric.recoveryMid
        }
    }

    // MARK: - Oxygen

    @State private var selectedOxygenDate: Date?

    @ViewBuilder
    private var oxygenCard: some View {
        if health.oxygenTrend.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Blood Oxygen", subtitle: "Trend only -- not a screening tool on its own.", systemImage: "drop.fill")
                Chart {
                    ForEach(health.oxygenTrend) { point in
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("SpO2", point.value)
                        )
                        .foregroundStyle(Theme.Metric.hrv)
                        .symbol(.circle)
                    }
                    if let selectedOxygenDate,
                       let point = health.oxygenTrend.first(where: {
                           Calendar.current.isDate($0.date, inSameDayAs: selectedOxygenDate)
                       }) {
                        RuleMark(x: .value("Selected", point.date, unit: .day))
                            .foregroundStyle(Theme.neutral(0.25))
                            .annotation(
                                position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionBadge(
                                    title: point.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                    lines: [("SpO2", String(format: "%.0f%%", point.value), Theme.Metric.hrv)]
                                )
                            }
                    }
                }
                .chartYScale(domain: 88...100)
                .frame(height: 90)
                .chartXSelection(value: $selectedOxygenDate)
                .chartSummary(
                    "Blood oxygen, last \(health.oxygenTrend.count) nights",
                    (health.oxygenTrend.last.map {
                        String(format: "Last night %.0f%%. ", $0.value)
                    } ?? "")
                        + ChartTrend.describe(health.oxygenTrend.map(\.value))
                        + ". Trend only, not a screening tool."
                )
            }
            .glassCard()
        }
    }

    // MARK: - Snoring

    @ViewBuilder
    private var snoringCard: some View {
        if !snore.nights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Snoring", subtitle: "On-device estimate from Snore Check sessions.", systemImage: "waveform.and.mic")
                ForEach(snore.nights.suffix(7).reversed()) { night in
                    HStack {
                        Text(night.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(Theme.label(12))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(minWidth: 84, alignment: .leading)
                        // Share of the night spent snoring, on a 0-40% scale
                        // so a typical night isn't a sliver.
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.neutral(0.08))
                                Capsule()
                                    .fill(night.report.loudest?.tint ?? Theme.Family.breathing)
                                    .frame(width: max(3, proxy.size.width * min(1, Double(night.snorePercent) / 40)))
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                        Text(snoreLine(night))
                            .font(Theme.label(12, weight: .semibold))
                            .monospacedDigit()
                        if let loudest = night.report.loudest {
                            Circle()
                                .fill(loudest.tint)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel("Loudest \(loudest.label.lowercased())")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                NavigationLink {
                    SnoreCheckView()
                } label: {
                    Text("Open Snore Check")
                        .font(Theme.label(13, weight: .semibold))
                        .frame(minHeight: 44)
                }
            }
            .glassCard()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Snoring", systemImage: "waveform.and.mic")
                Text("No Snore Check nights yet. Start one from the Sleep tab.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .glassCard()
        }
    }

    /// "42 min · 9% · 5 episodes", or "None flagged in 7 h".
    private func snoreLine(_ night: SnoreStore.NightSummary) -> String {
        guard night.snoreMinutes >= 1 else {
            return "None flagged in \(SnoreResultSummary.duration(night.monitoredMinutes))"
        }
        var parts = [SnoreResultSummary.duration(night.snoreMinutes), "\(night.snorePercent)%"]
        let count = night.report.episodeCount
        if count > 0 { parts.append("\(count) episode\(count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Safety

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What this screen can't tell you", systemImage: "exclamationmark.shield")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            Text("Zoon can't diagnose sleep apnea or anything else. If this stays high, or you gasp or feel very sleepy by day, see a doctor.")
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Breathing Health") {
    NavigationStack { BreathingHealthView() }
        .zoonPreviewEnvironment()
}
