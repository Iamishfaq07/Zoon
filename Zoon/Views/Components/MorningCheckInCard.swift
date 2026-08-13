import SwiftUI

/// Quick, optional self-report: how the morning feels, independent of
/// anything measured. See `MorningFeeling`'s doc comment for why this is
/// never blended into a score.
struct MorningCheckInCard: View {
    let selected: MorningFeeling?
    let onSelect: (MorningFeeling) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How do you feel this morning?")
                .font(Theme.label(13, weight: .semibold))

            HStack(spacing: 8) {
                ForEach(MorningFeeling.allCases) { feeling in
                    let isSelected = selected == feeling
                    Button {
                        onSelect(feeling)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: feeling.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(isSelected ? Theme.Metric.sleep : .secondary)
                                .frame(width: 36, height: 36)
                                .background(
                                    isSelected ? Theme.Metric.sleep.opacity(0.18) : Theme.neutral(0.06),
                                    in: Circle()
                                )
                            Text(feeling.label)
                                .font(Theme.text(9, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(feeling.label)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
        .glassCard()
    }
}

#Preview("Morning Check-In") {
    VStack(spacing: 16) {
        MorningCheckInCard(selected: nil) { _ in }
        MorningCheckInCard(selected: .good) { _ in }
    }
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
