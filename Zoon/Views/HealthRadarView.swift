import SwiftUI

/// Every overnight vital on personal-baseline bars — signature visual #4:
/// a current point against your own normal band, not a sci-fi radar chart.
struct HealthRadarView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Set only when pushed from `CoreIntelligenceGrid`'s tile -- see
    /// `SleepNeedView`'s doc comment on the same pair of properties.
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    private var context: DayContext? { coordinator.state.context }

    var body: some View {
        // `.zoom(...)` and `.automatic` are different concrete types
        // conforming to `NavigationTransition`, so branching the transition
        // value itself (e.g. via a ternary) doesn't type-check -- branching
        // the view instead lets each branch's `.navigationTransition(_:)`
        // call resolve its own concrete opaque type independently.
        if let zoomNamespace, let zoomID {
            content.navigationTransition(.zoom(sourceID: zoomID, in: zoomNamespace))
        } else {
            content.navigationTransition(.automatic)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                if let context {
                    hero(context.healthRadar)
                    ForEach(context.vitals.metrics) { metric in
                        baselineBarRow(metric, drift: driftSignal(for: metric.kind, in: context.healthRadar))
                    }
                    if context.healthRadar.isActive {
                        multiSignalNote(context.healthRadar)
                    }
                    disclaimerCard
                } else {
                    ContentUnavailableView("No night yet", systemImage: "moon.zzz")
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Body Signals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func driftSignal(for kind: VitalsStatus.Kind, in radar: HealthRadar) -> HealthRadar.Signal? {
        radar.signals.first { $0.kind == kind }
    }

    private func hero(_ radar: HealthRadar) -> some View {
        VStack(spacing: 8) {
            Text("Body Signals")
                .font(Theme.label(13))
                .foregroundStyle(.secondary)
            Text(radar.isActive ? radar.severity.label : "Normal")
                .font(Theme.numeral(30))
                .foregroundStyle(radar.isActive ? tint(for: radar.severity) : Theme.Metric.recoveryHigh)
            Text("Compared with your recent overnight baseline.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func tint(for severity: HealthRadar.Severity) -> Color {
        switch severity {
        case .clear: Theme.Metric.recoveryHigh
        case .watch: Theme.Metric.recoveryMid
        case .notable: Theme.Metric.recoveryLow
        }
    }

    private func baselineBarRow(_ metric: VitalsStatus.Metric, drift: HealthRadar.Signal?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: metric.kind.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(metric.kind.label)
                    .font(Theme.label(13, weight: .semibold))
                Spacer()
                Text(metric.formattedValue)
                    .font(Theme.label(14, weight: .bold))
                    .monospacedDigit()
                if let drift {
                    Image(systemName: drift.direction.symbol)
                        .font(Theme.text(11, weight: .bold))
                        .foregroundStyle(Theme.Metric.recoveryMid)
                }
            }

            BaselineLaneView(
                value: metric.value,
                baseline: metric.baseline,
                tolerance: metric.tolerance,
                tint: drift != nil ? Theme.Metric.recoveryMid : Theme.Metric.recoveryHigh
            )

            if let range = metric.formattedRange {
                Text("Your typical range: \(range)")
                    .font(Theme.text(10))
                    .foregroundStyle(.tertiary)
            }
        }
        .glassCard()
    }

    private func multiSignalNote(_ radar: HealthRadar) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(radar.signals.count) signals moved together", systemImage: "dot.radiowaves.left.and.right")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(tint(for: radar.severity))
            Text(radar.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var disclaimerCard: some View {
        Text(SleepInsight.disclaimer)
            .font(Theme.text(10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

#Preview("Health Radar") {
    NavigationStack { HealthRadarView() }
        .zoonPreviewEnvironment()
}
