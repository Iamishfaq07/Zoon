import SwiftUI

/// The first thing on Today: how you slept, how your body reads, what to do.
///
/// Three lines, no chart, no score arcs, nothing to interpret. The
/// explanation is one tap away and stays there until asked for -- see
/// `MorningInThree` for why the sentences are assembled in `Shared` rather
/// than written into this file.
struct MorningInThreeCard: View {

    let summary: MorningInThree
    /// Reveals the hero orbit and the rest of the analysis.
    let isExplanationShown: Bool
    let onToggleExplanation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Morning in 3")
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)

            ForEach(summary.lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.label)
                        .font(Theme.label(10, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                    Text(line.headline)
                        .font(Theme.numeral(22))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = line.detail {
                        Text(detail)
                            .font(Theme.text(12))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            Button(action: onToggleExplanation) {
                HStack(spacing: 5) {
                    Text(isExplanationShown ? "Hide the detail" : "Explore why")
                    Image(systemName: isExplanationShown ? "chevron.up" : "chevron.down")
                        .font(Theme.text(10, weight: .semibold))
                }
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(Theme.Metric.sleep)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isExplanationShown
                    ? "Hide the detailed breakdown"
                    : "Explore why, opens the score breakdown"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

#Preview("Morning in 3") {
    MorningInThreeCard(
        summary: MorningInThree.build(
            timeAsleepMinutes: 452,
            flagshipScore: 81,
            flagshipBand: "Good",
            bodySignalsHeadline: nil,
            debtMinutes: 95,
            hasEnoughHistoryForNeed: true
        ),
        isExplanationShown: false,
        onToggleExplanation: {}
    )
    .padding()
    .nightBackground()
}

#Preview("Morning in 3 - still learning") {
    MorningInThreeCard(
        summary: MorningInThree.build(
            timeAsleepMinutes: 388,
            flagshipScore: 58,
            flagshipBand: "Fair",
            bodySignalsHeadline: "Resting heart rate has been higher than usual for three nights.",
            debtMinutes: 0,
            hasEnoughHistoryForNeed: false
        ),
        isExplanationShown: true,
        onToggleExplanation: {}
    )
    .padding()
    .nightBackground()
}

/// The line most likely to crowd at large text sizes is TODAY's detail.
#Preview("Morning in 3 - large text") {
    MorningInThreeCard(
        summary: MorningInThree.build(
            timeAsleepMinutes: 452,
            flagshipScore: 81,
            flagshipBand: "Good",
            bodySignalsHeadline: nil,
            debtMinutes: 95,
            hasEnoughHistoryForNeed: true
        ),
        isExplanationShown: false,
        onToggleExplanation: {}
    )
    .padding()
    .nightBackground()
    .environment(\.dynamicTypeSize, .accessibility3)
}
