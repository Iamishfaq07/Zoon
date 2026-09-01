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
            // V8: personal baseline lanes on the page, each a tap from its
            // trend, separated by hairlines rather than boxed one per card.
            VStack(alignment: .leading, spacing: 24) {
                if let context {
                    hero(context.healthRadar)
                    VStack(spacing: 0) {
                        ForEach(Array(context.vitals.metrics.enumerated()), id: \.element.id) { index, metric in
                            if index > 0 {
                                Rectangle().fill(Theme.cardStroke).frame(height: 1)
                            }
                            NavigationLink {
                                MetricTrendView(kind: metric.kind)
                            } label: {
                                ZoonBaselineLane(
                                    metric: metric,
                                    drift: driftSignal(for: metric.kind, in: context.healthRadar),
                                    tint: laneTint(for: metric.kind)
                                )
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Show \(metric.kind.label) trend")
                        }
                    }
                    if context.healthRadar.isActive {
                        multiSignalNote(context.healthRadar)
                    }
                    disclaimerCard
                } else {
                    ZoonEmptyState(kind: .noData(
                        title: "No night yet",
                        message: "Body signals are compared against your own overnight baseline once Zoon has a night to read.",
                        unlocks: []
                    ))
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

    /// The same family colour a signal carries everywhere else in the app.
    private func laneTint(for kind: VitalsStatus.Kind) -> Color {
        switch kind {
        case .restingHeartRate: Theme.Metric.heart
        case .hrv: Theme.Metric.hrv
        case .respiratoryRate, .breathingDisturbances, .oxygenSaturation: Theme.Family.breathing
        case .wristTemperature: Theme.Family.circadian
        case .sleepDuration: Theme.Family.sleep
        }
    }

    private func hero(_ radar: HealthRadar) -> some View {
        VStack(spacing: 8) {
            Text("Body Signals")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(radar.isActive ? radar.severity.label : "Nothing unusual")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .foregroundStyle(radar.isActive ? tint(for: radar.severity) : .primary)
            Text("Each signal against your own recent overnight baseline.")
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func tint(for severity: HealthRadar.Severity) -> Color {
        switch severity {
        case .clear: Theme.Family.recovery
        case .watch: Theme.Family.attention
        case .notable: Theme.Family.deviation
        }
    }

    private func multiSignalNote(_ radar: HealthRadar) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(radar.signals.count) signals moved together", systemImage: "dot.radiowaves.left.and.right")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(tint(for: radar.severity))
            Text(radar.detail)
                .font(Theme.text(12))
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
