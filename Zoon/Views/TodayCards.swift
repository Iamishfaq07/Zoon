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
    /// Named periods to attribute the day's drain to. Defaulted so the
    /// existing call sites and previews are unchanged.
    var workouts: [EnergyDrivers.NamedInterval] = []

    /// Whether a precise Energy number may be printed.
    ///
    /// `BodyBattery.Provenance.isPresentable` has existed to answer exactly
    /// this and nothing asked it. The watch and the widgets already decline
    /// to state Energy they cannot stand behind; this card printed a
    /// two-digit level and three more precise stats regardless, which is the
    /// same asymmetry the other way round.
    ///
    /// The chart below stays either way: a shape is an indication, a numeral
    /// is a claim -- the same line drawn for the Recovery ring and the
    /// watch's sleep dial.
    private var showsNumbers: Bool { battery.provenance.isPresentable }

    private func number(_ value: Int) -> String {
        showsNumbers ? "\(value)" : "—"
    }

    /// What moved the curve, named.
    ///
    /// Energy has always known its own hourly deltas and never said what was
    /// happening in those hours. This is the sentence the "Readiness Now"
    /// idea was really asking for -- *down 18 since waking, because of the
    /// afternoon run* -- without a second score built on weights nothing
    /// calibrates.
    @ViewBuilder
    private var drivers: some View {
        let state = EnergyDrivers.explain(
            battery: battery, workouts: workouts, isPresentable: showsNumbers
        )
        if case .notEnoughYet = state {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(state.headline)
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                ForEach(state.drivers) { driver in
                    HStack(spacing: 6) {
                        Image(systemName: driver.symbol)
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.Metric.battery)
                            .frame(width: 16)
                        Text(driver.label)
                            .font(Theme.text(12))
                        Spacer(minLength: 4)
                        Text("−\(driver.spent)")
                            .font(Theme.label(12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

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
                        "Fills overnight with restful sleep, then drains with activity and stress through the day.",
                        "Drag along the chart to see any moment."
                    ]
                )
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(number(battery.current))
                        .font(Theme.numeral(28))
                        .monospacedDigit()
                        .foregroundStyle(
                            showsNumbers
                                ? Theme.batteryColor(Double(battery.current))
                                : Theme.inkSecondary
                        )
                    if showsNumbers {
                        Text("/100")
                            .font(Theme.label(12))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }

            BodyBatteryChart(battery: battery)

            drivers

            AdaptiveStack(spacing: 14) {
                stat("Woke at", number(battery.morningPeak))
                stat("Spent", number(battery.spentToday))
                stat("Low", number(battery.dayLow))
            }

            // Guidance is a reading of the number above it ("running low,
            // take it easy"), so it cannot outlive the number. Printing a
            // dash and then advice derived from the hidden value would be
            // worse than printing neither.
            if showsNumbers {
                Text(battery.guidance)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = battery.confidenceNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                .foregroundStyle(Theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    subtitle: "Each against your own baseline.",
                    systemImage: "chart.bar.doc.horizontal"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Recovery Score",
                    symbol: "chart.bar.doc.horizontal",
                    tint: Theme.recoveryColor(Double(recovery.percent)),
                    explanation: [
                        "Blends HRV, resting heart rate and how much sleep you got, each against your own baseline.",
                        "The bars show how much each pulled the score. A missing signal is left out, never guessed."
                    ]
                )
            }

            // How much to believe the number, above the working rather than
            // below it. `dataCompletenessPercent` has always been computed
            // and never rendered, so a score built from 55% of its inputs
            // looked exactly like one built from all of them.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(Theme.text(11))
                Text(recovery.confidence.label)
                    .font(Theme.label(12, weight: .semibold))
                if let reason = recovery.confidenceReason {
                    Text(reason)
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(
                recovery.confidence >= .moderate ? Color.secondary : Theme.Metric.strain
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(recovery.components) { component in
                HStack(spacing: 10) {
                    Text(component.label)
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(component.isAvailable ? .primary : Theme.inkTertiary)
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
                        .foregroundStyle(Theme.inkSecondary)
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
                // One segment per signal, lit when it counted: the coverage
                // reads as a shape before the words do.
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(recovery.components.indices, id: \.self) { index in
                            Capsule()
                                .fill(recovery.components[index].isAvailable ? Theme.Metric.recoveryHigh : Theme.neutral(0.15))
                                .frame(width: 14, height: 5)
                        }
                    }
                    Text("\(recovery.availableComponentCount) of \(recovery.components.count) signals. Missing ones left out, not guessed.")
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
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
                        "Your HRV this week against your own range from the last few months.",
                        "Needs a few weeks to settle. One low night is just noise."
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
                        .foregroundStyle(Theme.inkTertiary)
                        .monospacedDigit()
                }
            }

            Text(status.state.detail)
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
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
        case .building: Theme.inkSecondary
        }
    }
}
