import SwiftUI

/// The signature 24-hour circadian visualization — your estimated preferred
/// sleep window laid against what actually happened last night, on one ring.
struct BodyClockView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator

    /// Set only when pushed from `CoreIntelligenceGrid`'s tile -- see
    /// `SleepNeedView`'s doc comment on the same pair of properties.
    var zoomNamespace: Namespace.ID? = nil
    var zoomID: String? = nil

    private var bodyClock: BodyClock? { coordinator.state.context?.bodyClock }
    private var night: SleepNightFeatures? { coordinator.state.context?.night }

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
                if let bodyClock, let night {
                    ring(bodyClock: bodyClock, night: night)
                    stabilityCard(bodyClock)
                    explanationCard
                } else {
                    ContentUnavailableView(
                        "Building your body clock",
                        systemImage: "clock",
                        description: Text("Zoon needs \(BodyClock.minimumNights) nights of history before it can estimate your preferred sleep window.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Body Clock")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Ring

    /// The orbit itself, plus the one sentence that says what it shows. The
    /// dial, its drag-to-inspect and its accessibility live in
    /// `ZoonBodyClockOrbit`; this only decides what goes on it.
    private func ring(bodyClock: BodyClock, night: SleepNightFeatures) -> some View {
        let driftMinutes = bodyClock.drift(of: night.bedtime) ?? 0
        let alignment = alignmentScore(driftMinutes: driftMinutes)
        let forecast = EnergyForecast.compute(
            wakeTime: night.wakeTime,
            sleepDebtMinutes: night.sleepDebtMinutes ?? 0,
            windDownHour: bodyClock.isEstimate ? nil : bodyClock.onsetHour
        )
        // Peak, dip, and wind-down only. Morning rise and second wind sit
        // close enough to the window edges already on the dial that marking
        // them too would be noise around the same arc.
        let energyMarks = forecast.windows.filter {
            $0.kind == .morningPeak || $0.kind == .afternoonDip || $0.kind == .windDown
        }

        return VStack(spacing: 16) {
            ZoonBodyClockOrbit(
                bodyClock: bodyClock,
                night: night,
                energyMarks: energyMarks,
                alignment: alignment
            )

            HStack(spacing: 14) {
                legend(color: Theme.Family.sleep.opacity(0.35), label: "Usual window")
                legend(color: Theme.Family.sleep, label: "Last night")
                legend(color: Theme.Family.circadian, label: "Energy")
            }

            Text(alignmentSentence(driftMinutes: driftMinutes))
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(Theme.text(10)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Alignment

    private func alignmentScore(driftMinutes: Double) -> Double {
        Statistics.interpolate(abs(driftMinutes), anchors: [
            (0, 100), (15, 100), (30, 90), (60, 75), (90, 55), (120, 35), (180, 10), (240, 0)
        ])
    }

    private func alignmentSentence(driftMinutes: Double) -> String {
        guard abs(driftMinutes) >= 10 else {
            return "Your sleep started right around your usual preferred timing."
        }
        let direction = driftMinutes > 0 ? "later" : "earlier"
        return "Your sleep started about \(Int(abs(driftMinutes))) minutes \(direction) than your recent preferred timing."
    }

    // MARK: - Stability

    private func stabilityCard(_ bodyClock: BodyClock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Rhythm Stability", systemImage: "waveform.path")
                Spacer()
                StatusPill(text: bodyClock.stability.label, tint: stabilityTint(bodyClock.stability))
            }
            Text(bodyClock.stability.detail)
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
        }
        .glassCard()
    }

    private func stabilityTint(_ stability: BodyClock.Stability) -> Color {
        switch stability {
        case .tight: Theme.Metric.recoveryHigh
        case .typical: Theme.Metric.battery
        case .scattered: Theme.Metric.recoveryMid
        }
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("How is this estimated?", systemImage: "info.circle")
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("""
                Estimated body clock, not a direct measurement -- nothing on a wrist measures \
                circadian phase. This is built from your recent sleep midpoint, bedtime, wake \
                time, and regularity, averaged as clock positions rather than plain numbers so a \
                night crossing midnight doesn't distort the result.
                """)
                .font(Theme.text(10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }
}

#Preview("Body Clock") {
    NavigationStack { BodyClockView() }
        .zoonPreviewEnvironment()
}
