import SwiftUI

/// The BASELINE LANE visual grammar, full form: LOW / YOUR NORMAL / HIGH
/// labels above the lane, the shaded personal band, tonight's dot settling
/// into place, and the exact value under the dot.
///
/// `BaselineLaneView` remains the compact form used inside grids; this is
/// the one Body Signals uses as a row. Same inputs (`VitalsStatus.Metric`'s
/// value / baseline / tolerance), same window (±2.2 tolerances), so the two
/// always place the dot at the same fraction.
///
/// Meaning first: the headline says "Near your normal range" or "Above your
/// typical range"; the number and the range are the supporting line.
struct ZoonBaselineLane: View {
    let metric: VitalsStatus.Metric
    /// A sustained multi-night drift for this signal, if `HealthRadar`
    /// detected one -- shown as a small arrow beside the value, never as a
    /// colour change alone.
    var drift: HealthRadar.Signal?
    var tint: Color = Theme.Family.bodySignals

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    private let windowInTolerances: Double = 2.2

    private var fraction: Double? {
        guard let value = metric.value, let baseline = metric.baseline, let tolerance = metric.tolerance, tolerance > 0 else { return nil }
        let span = tolerance * windowInTolerances
        return min(max(((value - baseline) / span + 1) / 2, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Image(systemName: metric.kind.symbol)
                        .font(Theme.text(12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(metric.kind.label)
                        .font(Theme.label(15, weight: .semibold))
                }
                Spacer()
                Text(meaning)
                    .font(Theme.text(12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            lane

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(metric.formattedValue)
                    .font(Theme.supportingValue)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let drift {
                    HStack(spacing: 2) {
                        Image(systemName: drift.direction.symbol)
                            .font(Theme.text(10, weight: .bold))
                        Text("\(drift.consecutiveNights) nights")
                            .font(Theme.text(11, weight: .medium))
                    }
                    .foregroundStyle(Theme.Family.attention)
                }
                Spacer()
                if let range = metric.formattedRange {
                    Text("Your normal \(range)")
                        .font(Theme.evidence)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .onAppear {
            withAnimation(Motion.respecting(reduceMotion, Motion.hero)) { settled = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.kind.label)
        .accessibilityValue(accessibilityValue)
    }

    private var lane: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Low")
                Spacer()
                Text("Your normal")
                Spacer()
                Text("High")
            }
            .font(Theme.text(9, weight: .semibold))
            .foregroundStyle(.quaternary)
            .textCase(.uppercase)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.neutral(0.07))

                    if metric.tolerance.map({ $0 > 0 }) == true {
                        let bandWidth = width / windowInTolerances
                        Capsule()
                            .fill(tint.opacity(0.26))
                            .frame(width: bandWidth)
                            .offset(x: (width - bandWidth) / 2)
                        Rectangle()
                            .fill(tint.opacity(0.5))
                            .frame(width: 1)
                            .offset(x: width / 2)
                    }

                    if let fraction {
                        Circle()
                            .fill(metric.state.isOutlier ? Theme.Family.attention : tint)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Theme.dialMarker.opacity(0.9), lineWidth: 1.5))
                            .offset(x: (settled ? width * fraction : width / 2) - 6)
                            .animation(Motion.respecting(reduceMotion, Motion.value), value: metric.value)
                    }
                }
            }
            .frame(height: 16)
        }
    }

    private var meaning: String {
        switch metric.state {
        case .typical: "Near your normal range"
        case .aboveTypical: "Above your typical range"
        case .belowTypical: "Below your typical range"
        case .unavailable: "No reading tonight"
        }
    }

    private var accessibilityValue: String {
        var parts = [metric.formattedValue, meaning]
        if let range = metric.formattedRange { parts.append("your normal is \(range)") }
        if let drift { parts.append("\(drift.direction == .elevated ? "elevated" : "below baseline") for \(drift.consecutiveNights) nights") }
        return parts.joined(separator: ", ")
    }
}

#Preview("Baseline lanes") {
    let context = AppMockData.poorDayContext()
    return ScrollView {
        VStack(spacing: 28) {
            ForEach(context.vitals.metrics) { metric in
                ZoonBaselineLane(metric: metric, drift: context.healthRadar.signals.first { $0.kind == metric.kind })
            }
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
