import SwiftUI

/// The explainable score: a number, a band, and — the whole point of it — a
/// "why" that sums to the number instead of gesturing at it.
///
/// The canonical sleep-period score. Recovery remains a separate answer to
/// how prepared the body appears for today.
struct SleepIntelligenceCard: View {
    let score: SleepIntelligenceScore

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch score.band {
        case .poor: Theme.Metric.recoveryLow
        case .fair: Theme.Metric.recoveryMid
        case .good: Theme.Metric.battery
        case .excellent: Theme.Metric.recoveryHigh
        }
    }


    /// The component that cost the most points, named. A score with nothing
    /// holding it back gets no action: the honest answer is that the night
    /// was fine.
    private var weakestComponentAction: String? {
        guard let worst = score.negativeContributors.first else { return nil }
        return "\(worst.label) cost the most tonight. \(worst.detail)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Sleep Intelligence",
                    subtitle: score.confidence == .insufficient
                        ? "Not enough data tonight to score confidently."
                        : "\(score.confidence.label) · \(score.dataCompletenessPercent)% of the model ran",
                    systemImage: "brain.head.profile"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Sleep Intelligence Score",
                    symbol: "brain.head.profile",
                    tint: tint,
                    explanation: [
                        // Named as the score itself names them. This sentence still said
                        // "Circadian timing" and "Sleep Architecture" after the
                        // components were renamed to "Timing" and "Stage Pattern",
                        // so the one place explaining the score used two words for
                        // it that appear nowhere else in the app.
                        "Combines five sleep-period components -- Duration, Continuity, Regularity, Timing, and Stage Pattern. Recovery and body-signal anomalies are reported separately.",
                        "A component with no data tonight (not enough timing history or no stage detail) is left out and the rest are reweighted to fill 100% -- missing data never counts against you.",
                        "Stage Pattern compares your Deep and REM share of sleep with your own nights from the same kind of device, and only counts stages your watch or wearable classified. It is 5% of the score and says nothing about whether more deep sleep is better.",
                        "A night well short of your need is capped: 60 minutes short can be at most Good, 120 at most Fair, 180 Poor. When that happens the card says so."
                    ],
                    // No baseline facet. Each component is already scored
                    // against its own `expectedNeutral`, so "your usual" is
                    // built into the number rather than being a separate
                    // range to quote -- and there is no personal baseline
                    // for the composite itself to state honestly.
                    facets: MetricFacets(
                        confidence: score.confidence,
                        confidenceReason: score.confidenceReason,
                        action: weakestComponentAction
                    )
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(score.percent)")
                    .font(Theme.numeral(46))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(score.band.label)
                    .font(Theme.label(16, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
            }

            // Said beside the number it changed, not behind a tap: a capped
            // score is a different claim from the weighted sum, and the
            // person should not have to open a breakdown to learn that.
            if let cap = score.durationCap {
                Text(cap.explanation)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                withAnimation(Motion.respecting(reduceMotion, Motion.tap)) { expanded.toggle() }
                Haptics.tap()
            } label: {
                HStack(spacing: 5) {
                    Text(expanded ? "Hide the breakdown" : "Why wasn't it higher?")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.text(10, weight: .semibold))
                }
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)

            if expanded {
                breakdown
            }
        }
        .glassCard()
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.cardStroke)

            if !score.positiveContributors.isEmpty {
                contributorGroup("What helped", score.positiveContributors, positive: true)
            }
            if !score.negativeContributors.isEmpty {
                contributorGroup("What held you back", score.negativeContributors, positive: false)
            }
            if score.positiveContributors.isEmpty && score.negativeContributors.isEmpty {
                Text("Every component landed close to neutral tonight -- nothing stood out either way.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func contributorGroup(_ title: String, _ items: [SleepIntelligenceScore.Component], positive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label(11, weight: .bold))
                .foregroundStyle(Theme.inkTertiary)
            ForEach(items) { component in
                HStack(spacing: 8) {
                    Image(systemName: positive ? "checkmark" : "minus")
                        .font(Theme.text(10, weight: .bold))
                        .foregroundStyle(positive ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                        .frame(width: 14)
                    Text(component.label)
                        .font(Theme.label(12, weight: .medium))
                    Text(component.detail)
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.inkTertiary)
                    Spacer()
                    Text(String(format: "%+.0f", component.pointContribution))
                        .font(Theme.text(11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(positive ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryLow)
                }
            }
        }
    }
}

#Preview("Sleep Intelligence") {
    ScrollView {
        SleepIntelligenceCard(score: AppMockData.dayContext().sleepIntelligence)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
