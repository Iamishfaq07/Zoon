import SwiftUI

/// Level 1 + Level 2 of the data hierarchy, stacked: the hero number and
/// the word that says what it means. Used for the centre of an orbit, the
/// top of a detail screen, the Insights hero.
///
/// `value` animates through `contentTransition(.numericText())` so a change
/// from 74 → 81 counts rather than snaps -- but only when the value changes,
/// never on appear (see `Motion.draw`'s rule against replaying).
struct ZoonHeroMetric: View {
    let value: String
    let meaning: String
    var tint: Color = .primary
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(value)
                .font(Theme.heroNumeral)
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(meaning)
                .font(Theme.meaning)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Level 3: a row of supporting values under a hero, separated by type and
/// whitespace rather than by pills. Reflows to a column at accessibility
/// sizes. Each column can be a navigation target.
struct ZoonMetricRow<Destination: View>: View {
    struct Item: Identifiable {
        let id: String
        let label: String
        let value: String
        var tint: Color = .primary
        var destination: (() -> Destination)?
    }

    let items: [Item]

    var body: some View {
        AdaptiveStack(spacing: 0, alignment: .leading) {
            ForEach(items) { item in
                if let destination = item.destination {
                    NavigationLink(destination: destination) {
                        column(item)
                    }
                    .buttonStyle(.plain)
                } else {
                    column(item)
                }
            }
        }
    }

    private func column(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.value)
                .font(Theme.supportingValue)
                .monospacedDigit()
                .foregroundStyle(item.tint)
                .contentTransition(.numericText())
            Text(item.label)
                .font(Theme.supportingLabel)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.label), \(item.value)")
    }
}

/// A small floating value chip -- the one place native Liquid Glass is the
/// right material. Used for overlay toggles on the hypnogram, the time-range
/// picker, a selected metric.
struct ZoonMetricPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.Family.sleep
    var isSelected = true

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Theme.text(10, weight: .bold))
            }
            Text(text)
                .font(Theme.label(12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? tint : .secondary)
        .zoonGlassPill(tint: isSelected ? tint : Theme.neutral(0.20))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}


/// How sure Zoon is, said with an icon and a word rather than colour alone.
/// Confidence never uses red/green: it uses filled vs outlined marks so it
/// survives greyscale and colour-blindness.
struct ZoonEvidenceBadge: View {
    let confidence: MetricConfidence

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .strokeBorder(Theme.neutral(0.35), lineWidth: 1)
                    .background(Circle().fill(index < filled ? Theme.neutral(0.75) : .clear))
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(Theme.text(10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(confidence.label)
    }

    private var filled: Int {
        switch confidence {
        case .insufficient: 0
        case .low: 1
        case .moderate: 2
        case .high: 3
        }
    }

    private var label: String {
        switch confidence {
        case .insufficient: "Not enough data"
        case .low: "Early"
        case .moderate: "Moderate evidence"
        case .high: "Strong evidence"
        }
    }
}

/// "Simple explanation, then details": a one-line human sentence with a
/// disclosure that reveals the technical values underneath. The default
/// surface shows meaning; the numbers are one tap deeper, never hidden.
struct ZoonExplainThenDetail<Detail: View>: View {
    let explanation: String
    var detailLabel: String = "Details"
    @ViewBuilder var detail: Detail

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // An empty explanation means the caller only wants the
            // disclosure (e.g. "Why this score?" under a headline that is
            // itself the explanation).
            if !explanation.isEmpty {
                Text(explanation)
                    .font(Theme.text(14))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                withAnimation(Motion.respecting(reduceMotion, Motion.tap)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Less" : detailLabel)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(Theme.Family.sleep)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide details" : "Show details")

            if isExpanded {
                detail
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview("Metric primitives") {
    NavigationStack {
        VStack(alignment: .leading, spacing: 28) {
            ZoonHeroMetric(value: "81", meaning: "Good", tint: Theme.Family.sleep)
            ZoonMetricRow<EmptyView>(items: [
                .init(id: "sleep", label: "Sleep", value: "7h 42m", tint: Theme.Family.sleep),
                .init(id: "need", label: "Need", value: "8h 14m"),
                .init(id: "debt", label: "Debt", value: "32m", tint: Theme.Family.attention)
            ])
            HStack {
                ZoonMetricPill(text: "Stages", systemImage: "square.stack.3d.up")
                ZoonMetricPill(text: "Heart", systemImage: "heart", tint: Theme.Metric.heart, isSelected: false)
            }
            ZoonEvidenceBadge(confidence: .moderate)
            ZoonExplainThenDetail(explanation: "Your timing was more consistent this week.") {
                Text("Regularity index 88 (+8.3% vs 30-day baseline)")
                    .font(Theme.evidence)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
