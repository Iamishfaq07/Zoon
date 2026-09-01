import SwiftUI

// Cards that used to live at the bottom of TodayView.swift. Unchanged in
// V8; they are still used by RecoveryDetailView (RecoveryBreakdownCard,
// HRVStatusCard), EnergyDetailView (BodyBatteryCard) and SleepTabView
// (SleepSummaryStrip). Moved here so TodayView.swift contains only the
// Today screen. The old LoadingState/EmptyState/ErrorState views are gone:
// ZoonLoadingState and ZoonEmptyState replace them.

// MARK: - Cards

struct BodyBatteryCard: View {
    let battery: BodyBattery

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Energy Reserve", systemImage: "bolt.fill")
                Spacer()
                MetricInfoButton(
                    title: "Energy Reserve",
                    symbol: "bolt.fill",
                    tint: Theme.Metric.battery,
                    explanation: [
                        "Fills overnight based on how restorative your sleep was, then drains through the day with activity and stress signals -- a same-day curve, not a running average.",
                        "Tap and drag anywhere on the chart below to see the exact level at any point in the day."
                    ]
                )
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

            AdaptiveStack(spacing: 14) {
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
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Compact sleep row on Today; the full breakdown lives on the Sleep tab.
struct SleepSummaryStrip: View {
    let context: DayContext
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        NavigationLink {
            SleepDetailView(context: context)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(
                        title: preferences.isShiftWorkModeEnabled ? "Last Sleep" : "Last Night",
                        systemImage: "moon.stars.fill"
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Theme.text(12, weight: .semibold))
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
            HStack(alignment: .top) {
                SectionHeader(
                    title: "What drove your recovery",
                    subtitle: "Each input measured against your own baseline, not a population average.",
                    systemImage: "chart.bar.doc.horizontal"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Recovery Score",
                    symbol: "chart.bar.doc.horizontal",
                    tint: Theme.recoveryColor(Double(recovery.percent)),
                    explanation: [
                        "Recovery blends several signals -- HRV, resting heart rate, and sleep performance among them -- each compared against your own baseline rather than a fixed target.",
                        "The bars above show how much each input pulled the score up or down. A signal with nothing to measure tonight (no reading, or no baseline yet) is left out entirely and its weight redistributes among the rest -- it's never scored as average or assumed fine."
                    ]
                )
            }

            ForEach(recovery.components) { component in
                HStack(spacing: 10) {
                    Text(component.label)
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(component.isAvailable ? .primary : .tertiary)
                        .frame(width: 82, alignment: .leading)

                    if component.isAvailable {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.neutral(0.08))
                                Capsule()
                                    .fill(Theme.recoveryColor(component.normalized * 100))
                                    .frame(width: geo.size.width * min(1, max(0.02, component.normalized)))
                            }
                        }
                        .frame(height: 7)
                    } else {
                        // Not a zero-width or zero-value bar: that would read
                        // as "scored badly" rather than "wasn't measured."
                        Capsule()
                            .strokeBorder(Theme.neutral(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(height: 7)
                    }

                    Text(component.isAvailable ? component.detail : "Not available")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 74, alignment: .trailing)

                    if let deviation = component.deviationPercent, component.isAvailable {
                        Text(String(format: "%+.0f%%", deviation))
                            .font(Theme.text(10, weight: .semibold))
                            .foregroundStyle(deviation >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid)
                            .frame(width: 40, alignment: .trailing)
                    } else {
                        Spacer().frame(width: 40)
                    }
                }
            }

            if recovery.dataCompletenessPercent < 100 {
                Divider().overlay(Theme.cardStroke)
                Text("Based on \(recovery.availableComponentCount) of \(recovery.components.count) signals tonight (\(recovery.dataCompletenessPercent)% of the full model). Missing signals were excluded, not assumed average.")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
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
                MetricInfoButton(
                    title: "HRV Status",
                    symbol: "heart.text.square",
                    tint: tint,
                    explanation: [
                        "This compares your HRV this week against your own rolling quarterly range, not a population average -- what's balanced for you can be a meaningful drop for someone else.",
                        "It needs a few weeks of nights before the range is trustworthy, and one low night on its own is normal noise, not a signal."
                    ],
                    relatedArticleID: "hrv-explained",
                    // The only call site on this screen with an exact
                    // SensorTruth mapping. Daily Load, Energy Reserve,
                    // Recovery and Sleep Intelligence are composite scores
                    // with no single provenance -- a score is not "measured"
                    // just because one of its inputs is, and inventing a
                    // mapping for them is the exact dishonesty SensorTruth
                    // exists to prevent.
                    quantity: .hrv
                )
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
                        .font(Theme.text(10))
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
