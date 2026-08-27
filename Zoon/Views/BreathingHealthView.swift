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
            VStack(spacing: Theme.stackSpacing) {
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let baseline = health.baselineRespiratoryRate {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Baseline \(String(format: "%.1f", baseline))")
                                .font(Theme.text(10))
                                .foregroundStyle(.tertiary)
                            if let deviation = health.respiratoryDeviationPercent {
                                Text(String(format: "%+.0f%%", deviation))
                                    .font(Theme.label(12, weight: .semibold))
                                    .foregroundStyle(abs(deviation) < 8 ? .secondary : Theme.Metric.recoveryMid)
                            }
                        }
                    }
                }
            } else {
                Text("No respiratory rate reading for last night.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    subtitle: "Apple's overnight measure, as % of the night.",
                    systemImage: "waveform.path.ecg"
                )
                Spacer()
                StatusPill(text: health.pattern.label, tint: patternTint)
            }

            if health.disturbanceTrend.count < 2 {
                Text("Needs a Series 9 / Ultra 2 or later with the feature enabled, and a few nights of history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(health.disturbanceTrend) { point in
                        BarMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Percent", point.value)
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
                                    lines: [("Disturbances", "\(Int(point.value))%", Theme.Metric.sleep)]
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
                        "Last night \(Int($0.value))%. "
                    } ?? "")
                        + ChartTrend.describe(
                            health.disturbanceTrend.map(\.value), higherIsBetter: false
                        ) + "."
                )

                if case .repeatedPattern(let elevated, let window) = health.pattern {
                    Text("Elevated on \(elevated) of the last \(window) tracked nights. Consider discussing a repeated pattern like this with a healthcare professional if it continues.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .glassCard()
    }

    private var patternTint: Color {
        switch health.pattern {
        case .insufficientData: .secondary
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
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(night.snorePercent)% of \(Int(night.monitoredMinutes))m monitored")
                            .font(Theme.label(12, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            .glassCard()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Snoring", systemImage: "waveform.and.mic")
                Text("No Snore Check sessions yet. Run one from the Sleep tab to start building history here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .glassCard()
        }
    }

    // MARK: - Safety

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("What this screen can't tell you", systemImage: "exclamationmark.shield")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Zoon cannot diagnose sleep apnea, or any other condition, from consumer-device \
                measurements. It can only show you the pattern in your own recorded data. If \
                breathing disturbances stay elevated over time, or you notice symptoms like \
                loud snoring with gasping or persistent daytime sleepiness, talk to a healthcare \
                professional.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Breathing Health") {
    NavigationStack { BreathingHealthView() }
        .zoonPreviewEnvironment()
}
