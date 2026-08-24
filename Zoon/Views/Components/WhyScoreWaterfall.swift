import SwiftUI

/// "Why 88?" -- the redesign spec's animated score waterfall, made real
/// rather than decorative: each row shows `Component.pointContribution`
/// verbatim, the same signed number `SleepIntelligenceScore` itself sums
/// components from (see that type's doc comment: "the number the 'why' UI
/// sums to"). Nothing here is re-derived or approximated -- every value
/// traces straight back to the score calculation, which is the whole point
/// of an explainable score.
///
/// Replaces the old top-3, arrow-only "What moved it" list: that showed
/// direction but not magnitude, so two components with wildly different
/// impact read as visually identical. This shows every component that
/// actually moved (skipping the ones close enough to neutral to be noise)
/// and reconciles them against the total.
struct WhyScoreWaterfall: View {
    let components: [SleepIntelligenceScore.Component]
    /// For the two components (Continuity, Architecture) whose own detail
    /// screen is `SleepDetailView`, which -- unlike every other destination
    /// here -- takes tonight's context explicitly rather than reading it
    /// from the environment.
    let context: DayContext

    /// Components close enough to a neutral 0.5-normalized baseline that
    /// showing them would be noise, not signal -- mirrors the ±0.5-point
    /// threshold `positiveContributors`/`negativeContributors` already use.
    private var movers: [SleepIntelligenceScore.Component] {
        components
            .filter { abs($0.pointContribution) > 0.5 }
            .sorted { abs($0.pointContribution) > abs($1.pointContribution) }
    }

    private var maxMagnitude: Double {
        movers.map { abs($0.pointContribution) }.max() ?? 1
    }

    var body: some View {
        if !movers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Why this score")
                    .font(Theme.label(12, weight: .bold))
                    .foregroundStyle(.tertiary)
                ForEach(movers) { component in
                    row(component)
                }
            }
        }
    }

    private func row(_ component: SleepIntelligenceScore.Component) -> some View {
        let contribution = component.pointContribution
        let tint = contribution >= 0 ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow

        return NavigationLink {
            destination(for: component)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(component.label)
                        .font(Theme.label(12, weight: .semibold))
                    Text(component.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(formattedPoints(contribution))
                        .font(Theme.label(12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.neutral(0.08))
                        Capsule()
                            .fill(tint)
                            .frame(width: geometry.size.width * min(abs(contribution) / maxMagnitude, 1))
                    }
                }
                .frame(height: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tap → evidence, the redesign spec's ask for these rows -- each
    /// component's own full detail screen, the same one its metric shows up
    /// on elsewhere in the app (`CoreIntelligenceGrid`, `HealthPulseStrip`).
    @ViewBuilder
    private func destination(for component: SleepIntelligenceScore.Component) -> some View {
        switch component.label {
        case "Duration": SleepNeedView()
        case "Regularity": RegularityDetailView()
        case "Recovery": RecoveryDetailView()
        case "Circadian": BodyClockView()
        case "Breathing": BreathingHealthView()
        default: SleepDetailView(context: context)
        }
    }

    private func formattedPoints(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded >= 0 ? "+\(rounded)" : "\(rounded)"
    }
}

#Preview("Why Score") {
    NavigationStack {
        WhyScoreWaterfall(
            components: [
                .init(label: "Duration", detail: "7h52 vs 8h10 need", normalized: 0.42, weightUsed: 0.25),
                .init(label: "Regularity", detail: "±22m this week", normalized: 0.68, weightUsed: 0.15),
                .init(label: "Continuity", detail: "3 awakenings", normalized: 0.35, weightUsed: 0.20),
                .init(label: "Recovery", detail: "HRV +9% vs baseline", normalized: 0.61, weightUsed: 0.15)
            ],
            context: AppMockData.dayContext()
        )
        .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}
