import SwiftUI

/// A glance at every vital before the detailed breakdown further down Today.
///
/// `VitalsCard` already shows each metric with its typical range and a
/// sentence of context -- this is deliberately not a smaller version of that.
/// It's the thing you'd look at in three seconds while still half asleep: one
/// row of icons, colour alone carrying "is anything off tonight", with the
/// full explanation one scroll away for whoever wants it. Reuses
/// `VitalsStatus.Metric` directly rather than computing anything new, so the
/// two views can never disagree about whether a reading is typical.
struct HealthPulseStrip: View {
    let vitals: VitalsStatus

    var body: some View {
        HStack(spacing: 0) {
            ForEach(vitals.metrics) { metric in
                pulse(metric)
                if metric.id != vitals.metrics.last?.id {
                    Spacer(minLength: 4)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .glassCard(padding: 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Health pulse")
    }

    private func pulse(_ metric: VitalsStatus.Metric) -> some View {
        VStack(spacing: 4) {
            Image(systemName: metric.kind.symbol)
                .font(Theme.text(15))
                .foregroundStyle(tint(for: metric.state))
            Text(metric.formattedValue)
                .font(Theme.label(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(metric.state == .unavailable ? .tertiary : .primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.kind.label)
        .accessibilityValue("\(metric.formattedValue), \(metric.state.label)")
    }

    private func tint(for state: VitalsStatus.State) -> Color {
        switch state {
        case .typical: Theme.Metric.recoveryHigh
        case .aboveTypical, .belowTypical: Theme.Metric.recoveryMid
        case .unavailable: .secondary
        }
    }
}
