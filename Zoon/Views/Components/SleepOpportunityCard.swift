import SwiftUI

/// Need, opportunity, actual — and which of the two gaps the shortfall
/// mostly came from.
///
/// Three numbers and a sentence. Deliberately the plainest card in the app:
/// its whole value is that the arithmetic is an identity a person can check
/// in their head, and any chart drawn over it would obscure that rather than
/// help. The bars are proportional to the same scale, so the two gaps are
/// visible as lengths before the sentence names them.
struct SleepOpportunityCard: View {

    let opportunity: SleepOpportunity
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Everything is measured against the longest of the three, so the bars
    /// share one scale and a longer-than-needed window reads as longer.
    private var scale: Double {
        max(opportunity.needMinutes, opportunity.opportunityMinutes, opportunity.actualMinutes, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Opportunity and execution",
                subtitle: "How much time you allowed, and how much of it you slept.",
                systemImage: "rectangle.compress.vertical"
            )

            VStack(alignment: .leading, spacing: 10) {
                ForEach(opportunity.rows, id: \.label) { row in
                    self.row(label: row.label, minutes: row.minutes)
                }
            }

            if let sentence = opportunity.sentence {
                Text(sentence)
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("You met your sleep need.")
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if opportunity.opportunityIsEstimated {
                Text("Your time in bed was estimated from the sleep period rather than measured, so the split between the two is not stated.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    /// One row. At accessibility sizes the bar drops away entirely rather
    /// than competing with the label for a width neither can have: it is
    /// decoration for the number beside it, and the number is the content.
    @ViewBuilder
    private func row(label: String, minutes: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 6)
                Text(SleepNightFeatures.formatMinutes(minutes))
                    .font(Theme.numeral(16))
                    .monospacedDigit()
            }
            if !dynamicTypeSize.isAccessibilitySize {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.neutral(0.08))
                        Capsule()
                            .fill(tint(for: label))
                            .frame(width: geometry.size.width * min(1, minutes / scale))
                    }
                }
                .frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    /// Need is the reference, so it is neutral; the two measured quantities
    /// carry the metric's own colour. Never colour alone — each row is
    /// labelled and the number is the point.
    private func tint(for label: String) -> Color {
        label == "Sleep need" ? Theme.neutral(0.35) : Theme.Metric.sleep
    }

    private var accessibilitySummary: String {
        let rows = opportunity.rows
            .map { "\($0.label), \(SleepNightFeatures.formatMinutes($0.minutes))" }
            .joined(separator: ". ")
        return "\(rows). \(opportunity.sentence ?? "You met your sleep need.")"
    }
}
