import SwiftUI
import UIKit

/// The morning screen: recovery, what to do about it, and why.
///
/// Ordered by what someone actually wants at 7am — the verdict first, the
/// prescription immediately under it, and the evidence below that. Nobody opens
/// a recovery app to browse; they open it to find out whether to train.
struct TodayView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal)
                    .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .refreshable { await coordinator.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .idle, .loading:
            LoadingState()
        case let .loaded(context), let .mock(context):
            loadedContent(context)
        case let .empty(reason):
            EmptyState(reason: reason) { Task { await coordinator.refresh() } }
        case let .failed(message):
            ErrorState(message: message) { Task { await coordinator.refresh() } }
        }
    }

    private func loadedContent(_ context: DayContext) -> some View {
        // Indices drive the entrance cascade — see Motion.stagger. Written out
        // rather than derived, because the order is a design decision and a
        // reader should be able to see it.
        VStack(spacing: Theme.stackSpacing) {
            hero(context).entrance(0)
            guidanceCard(context).entrance(1)
            ringsCard(context).entrance(2)
            BodyBatteryCard(battery: context.bodyBattery).entrance(3)
            SleepSummaryStrip(context: context).entrance(4)
            // Radar first among the diagnostics: a sustained multi-signal drift
            // is the rarest and most consequential thing on this screen, and it
            // renders as nothing at all when there's nothing to say.
            HealthRadarCard(radar: context.healthRadar).entrance(5)
            RecoveryBreakdownCard(recovery: context.recovery).entrance(6)
            VitalsCard(vitals: context.vitals).entrance(7)
            HRVStatusCard(status: context.hrvStatus).entrance(8)
            RegularityCard(regularity: context.regularity).entrance(9)
            if let cvAge = context.cardiovascularAge {
                CardiovascularAgeCard(cvAge: cvAge).entrance(10)
            }
            InsightCard(insight: context.insight, engineName: context.insight.source.displayName)
                .entrance(11)
            footer(context).entrance(12)
        }
    }

    // MARK: - Hero

    private func hero(_ context: DayContext) -> some View {
        VStack(spacing: 12) {
            if context.isMock {
                StatusPill(text: "Sample data", systemImage: "wand.and.stars", tint: Theme.Metric.sleep)
            }

            RecoveryRing(recovery: context.recovery)
                .padding(.top, 4)

            Text(context.headline)
                .font(Theme.label(22, weight: .bold))
                .multilineTextAlignment(.center)

            if context.recovery.isEstimate {
                Text("Zoon needs a few more nights before this number is trustworthy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func guidanceCard(_ context: DayContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Today's call", systemImage: "flag.checkered")
                .font(Theme.label(13, weight: .bold))
                .foregroundStyle(Theme.recoveryColor(Double(context.recovery.percent)))

            Text(context.recovery.band.guidance)
                .font(Theme.label(15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            if !context.strain.isEstimate || context.strain.value > 0 {
                Divider().overlay(Theme.cardStroke)
                Text(StrainScore.balanceVerdict(
                    strain: context.strain.value,
                    recoveryPercent: context.recovery.percent
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    // MARK: - Rings

    private func ringsCard(_ context: DayContext) -> some View {
        HStack(spacing: 16) {
            TripleRing(arcs: [
                .init(
                    fraction: context.strain.value / StrainScore.maxValue,
                    color: Theme.Metric.strain,
                    label: "Strain", value: context.strain.displayValue
                ),
                .init(
                    fraction: context.sleepNeed.performancePercent / 100,
                    color: Theme.Metric.sleep,
                    label: "Sleep", value: "\(Int(context.sleepNeed.performancePercent))%"
                ),
                .init(
                    fraction: Double(context.bodyBattery.current) / 100,
                    color: Theme.Metric.battery,
                    label: "Battery", value: "\(context.bodyBattery.current)"
                )
            ])

            VStack(alignment: .leading, spacing: 10) {
                metricRow(
                    "Strain", context.strain.displayValue,
                    detail: context.strain.band, color: Theme.Metric.strain,
                    caveat: context.strain.isEstimate ? "estimated" : nil
                )
                metricRow(
                    "Sleep", "\(Int(context.sleepNeed.performancePercent))%",
                    detail: context.sleepNeed.performanceBand, color: Theme.Metric.sleep
                )
                metricRow(
                    "Battery", "\(context.bodyBattery.current)",
                    detail: context.bodyBattery.band, color: Theme.Metric.battery
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }

    private func metricRow(
        _ title: String, _ value: String,
        detail: String, color: Color, caveat: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(value)
                        .font(Theme.label(17, weight: .bold))
                        .monospacedDigit()
                    Text(title)
                        .font(Theme.label(11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if let caveat {
                        Text("· \(caveat)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func footer(_ context: DayContext) -> some View {
        VStack(spacing: 3) {
            if let source = context.night.sourceName {
                Text("Source: \(source)")
            }
            if let last = coordinator.lastRefresh {
                Text("Updated \(last, format: .dateTime.hour().minute())")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - Cards

struct BodyBatteryCard: View {
    let battery: BodyBattery

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Body Battery", systemImage: "bolt.fill")
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(battery.current)")
                        .font(Theme.numeral(28))
                        .monospacedDigit()
                        .foregroundStyle(Theme.batteryColor(Double(battery.current)))
                    Text("/100")
                        .font(Theme.label(12))
                        .foregroundStyle(.tertiary)
                }
            }

            BodyBatteryChart(battery: battery)

            HStack(spacing: 14) {
                stat("Woke at", "\(battery.morningPeak)")
                stat("Spent", "\(battery.spentToday)")
                stat("Low", "\(battery.dayLow)")
            }

            Text(battery.guidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.label(15, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact sleep row on Today; the full breakdown lives on the Sleep tab.
struct SleepSummaryStrip: View {
    let context: DayContext

    var body: some View {
        NavigationLink {
            SleepDetailView(context: context)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Last Night", systemImage: "moon.stars.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(context.night.formattedTimeAsleep)
                        .font(Theme.numeral(34))
                        .monospacedDigit()
                    Text("\(Int(context.sleepNeed.performancePercent))% of need")
                        .font(Theme.label(13))
                        .foregroundStyle(.secondary)
                }

                if !context.night.stageSegments.isEmpty {
                    HypnogramView(
                        segments: context.night.stageSegments,
                        height: 74,
                        showsAxis: false
                    )
                } else {
                    StageProportionBar(features: context.night)
                }
            }
            .glassCard()
        }
        .buttonStyle(.plain)
    }
}

/// Shows the recovery score's working — which input dragged it where.
struct RecoveryBreakdownCard: View {
    let recovery: RecoveryScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "What drove your recovery",
                subtitle: "Each input measured against your own baseline, not a population average.",
                systemImage: "chart.bar.doc.horizontal"
            )

            ForEach(recovery.components) { component in
                HStack(spacing: 10) {
                    Text(component.label)
                        .font(Theme.label(12, weight: .medium))
                        .frame(width: 82, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Theme.recoveryColor(component.normalized * 100))
                                .frame(width: geo.size.width * min(1, max(0.02, component.normalized)))
                        }
                    }
                    .frame(height: 7)

                    Text(component.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 62, alignment: .trailing)

                    if let deviation = component.deviationPercent {
                        Text(String(format: "%+.0f%%", deviation))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(deviation >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                            .frame(width: 40, alignment: .trailing)
                    } else {
                        Spacer().frame(width: 40)
                    }
                }
            }
        }
        .glassCard()
    }
}

/// Apple-Health-style vitals panel: typical vs outlier.
struct VitalsCard: View {
    let vitals: VitalsStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(title: "Vitals", subtitle: vitals.detail, systemImage: "waveform.path.ecg")
                Spacer(minLength: 8)
                StatusPill(
                    text: vitals.outliers.isEmpty ? "Typical" : "\(vitals.outliers.count)",
                    systemImage: vitals.outliers.isEmpty ? "checkmark" : "exclamationmark",
                    tint: vitals.outliers.isEmpty ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
                )
            }

            ForEach(vitals.metrics) { metric in
                VitalRow(metric: metric)
            }

            Text(SleepInsight.disclaimer)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

private struct VitalRow: View {
    let metric: VitalsStatus.Metric

    private var tint: Color {
        switch metric.state {
        case .typical: Theme.Metric.recoveryHigh
        case .aboveTypical, .belowTypical: Theme.Metric.recoveryMid
        case .unavailable: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: metric.kind.symbol)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.kind.label)
                    .font(Theme.label(12, weight: .medium))
                if let range = metric.formattedRange {
                    Text("Typical \(range)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(metric.formattedValue)
                .font(Theme.label(13, weight: .semibold))
                .monospacedDigit()

            Image(systemName: metric.state.symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.kind.label)
        .accessibilityValue("\(metric.formattedValue), \(metric.state.label)")
    }
}

/// Garmin-style HRV status: the week against the quarter.
struct HRVStatusCard: View {
    let status: HRVStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "HRV Status", systemImage: "heart.text.square")
                Spacer()
                StatusPill(text: status.state.label, tint: tint)
            }

            if let weekly = status.weeklyAverage,
               let lower = status.lowerBound,
               let upper = status.upperBound {

                // Pad the plotted range beyond the balanced band so a weekly
                // average sitting outside it still lands on the gauge.
                let span = max(upper - lower, 1)
                let plotMin = lower - span
                let plotMax = upper + span

                RangeGauge(
                    position: (weekly - plotMin) / (plotMax - plotMin),
                    bandStart: (lower - plotMin) / (plotMax - plotMin),
                    bandEnd: (upper - plotMin) / (plotMax - plotMin),
                    tint: tint
                )

                HStack {
                    Text("\(Int(weekly)) ms this week")
                        .font(Theme.label(12, weight: .semibold))
                        .monospacedDigit()
                    Spacer()
                    Text("Your range \(Int(lower))–\(Int(upper)) ms")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            Text(status.state.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var tint: Color {
        switch status.state {
        case .balanced: Theme.Metric.recoveryHigh
        case .unbalanced: Theme.Metric.recoveryMid
        case .low: Theme.Metric.temperature
        case .poor: Theme.Metric.recoveryLow
        case .building: .secondary
        }
    }
}

// MARK: - States

struct LoadingState: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Reading last night…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
    }
}

/// Shown when queries succeeded but found nothing.
///
/// This screen exists because the failure mode it replaces — an eternal spinner
/// — is indistinguishable from a hang, and HealthKit gives us no way to tell the
/// user "you denied permission". So it names both plausible causes and offers a
/// direct route to Settings.
struct EmptyState: View {
    let reason: SleepDataCoordinator.EmptyReason
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(reason.title, systemImage: "moon.zzz")
        } description: {
            Text(reason.message)
        } actions: {
            if reason == .noSleepData {
                Button("Open Health Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Check Again", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.top, 40)
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't read your sleep", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }
}

#Preview("Today") {
    TodayView().zoonPreviewEnvironment()
}
