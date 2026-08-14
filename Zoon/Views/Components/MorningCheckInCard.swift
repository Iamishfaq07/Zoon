import SwiftUI

/// Quick, optional self-report: how the morning feels, independent of
/// anything measured. See `MorningFeeling`'s doc comment for why this is
/// never blended into a score.
///
/// Morning Check-In V2: the single-tap feeling stays the compact default --
/// most mornings that's all anyone wants to log -- with an optional
/// disclosure underneath for the four `CheckInDimension` questions (rested,
/// energy, sleepiness, mood). Expanding is remembered only for the current
/// view session, not persisted, so the card starts collapsed every morning.
struct MorningCheckInCard: View {
    let selected: MorningFeeling?
    let details: [CheckInDimension: Int]
    let onSelectFeeling: (MorningFeeling) -> Void
    let onSelectDetail: (CheckInDimension, Int?) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How do you feel this morning?")
                .font(Theme.label(13, weight: .semibold))

            HStack(spacing: 8) {
                ForEach(MorningFeeling.allCases) { feeling in
                    let isSelected = selected == feeling
                    Button {
                        onSelectFeeling(feeling)
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

            Button {
                withAnimation(Motion.tap) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Less detail" : "More detail")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(Theme.text(11, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(CheckInDimension.allCases) { dimension in
                        CheckInDimensionRow(
                            dimension: dimension,
                            value: details[dimension],
                            onSelect: { onSelectDetail(dimension, $0) }
                        )
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard()
    }
}

/// One 1...5 self-report question with tap-to-select dots. Tapping the
/// already-selected dot clears it -- every question here is skippable, and a
/// dead end (no way to say "I didn't mean to answer that") would discourage
/// answering the others honestly.
private struct CheckInDimensionRow: View {
    let dimension: CheckInDimension
    let value: Int?
    let onSelect: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dimension.question)
                .font(Theme.text(12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(dimension.lowLabel)
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { rating in
                        let isSelected = value == rating
                        Button {
                            onSelect(isSelected ? nil : rating)
                        } label: {
                            Circle()
                                .fill(isSelected ? Theme.Metric.sleep : Theme.neutral(0.1))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle().strokeBorder(Theme.Metric.sleep.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(dimension.question) \(rating) of 5")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .frame(maxWidth: .infinity)

                Text(dimension.highLabel)
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}

#Preview("Morning Check-In") {
    VStack(spacing: 16) {
        MorningCheckInCard(selected: nil, details: [:], onSelectFeeling: { _ in }, onSelectDetail: { _, _ in })
        MorningCheckInCard(
            selected: .good,
            details: [.rested: 4, .energy: 3],
            onSelectFeeling: { _ in },
            onSelectDetail: { _, _ in }
        )
    }
    .padding()
    .nightBackground()
    .preferredColorScheme(.dark)
}
