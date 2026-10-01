import SwiftUI

/// One journal finding, read at a glance instead of as a paragraph.
///
/// The Patterns screen used to print every finding as three lines of prose
/// -- "On nights you logged alcohol, your sleep sufficiency tends to be
/// worse. 10 matched nights · Low confidence" -- four times over, which is a
/// page people scroll past. The same facts fit a row: the behaviour's
/// symbol, a better/worse verdict, the two medians as bars you can compare
/// without reading numbers, and confidence as filled dots. The sentence is
/// one tap away for anyone who wants it in words.
struct FindingGlance: View {

    let finding: JournalCorrelator.Finding

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var verdictTint: Color {
        finding.isImprovement ? Theme.Metric.recoveryHigh : Theme.Metric.recoveryMid
    }

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { expanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                AdaptiveStack(spacing: 10) {
                    Image(systemName: finding.symbol)
                        .font(Theme.text(14, weight: .semibold))
                        .foregroundStyle(verdictTint)
                        .frame(width: 34, height: 34)
                        .background(verdictTint.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.label)
                            .font(Theme.label(14, weight: .semibold))
                            .lineLimit(2)
                        HStack(spacing: 4) {
                            Image(systemName: finding.isImprovement ? "arrow.up.right" : "arrow.down.right")
                                .font(Theme.text(10, weight: .bold))
                            Text("\(finding.isImprovement ? "Better" : "Worse") \(finding.metric.shortLabel)")
                                .font(Theme.text(12, weight: .medium))
                        }
                        .foregroundStyle(verdictTint)
                    }
                    Spacer(minLength: 8)
                    ConfidenceDots(confidence: finding.confidence)
                }

                comparison

                if expanded {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.plainSentence)
                            .font(Theme.text(13))
                        Text(finding.supportLine)
                            .font(Theme.evidence)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(finding.label). \(finding.plainSentence) \(finding.supportLine)")
        .accessibilityHint(expanded ? "Hides the sentence" : "Shows the finding in words")
    }

    /// With against without, as two bars on one scale.
    private var comparison: some View {
        let with = finding.taggedMedian
        let without = finding.matchedMedian
        let top = max(abs(with), abs(without), 0.0001)
        return VStack(spacing: 5) {
            bar(title: "With", value: with, fraction: abs(with) / top, tint: verdictTint)
            bar(title: "Without", value: without, fraction: abs(without) / top, tint: Theme.neutral(0.35))
        }
    }

    private func bar(title: String, value: Double, fraction: Double, tint: Color) -> some View {
        LabeledBar(
            title: title,
            valueText: Self.value(value, metric: finding.metric),
            fraction: fraction,
            tint: tint,
            labelWidth: 52
        )
    }

    /// An unsigned median in the metric's own units.
    static func value(_ value: Double, metric: JournalCorrelator.Metric) -> String {
        switch metric {
        case .recovery, .sleepPerformance, .efficiency: String(format: "%.0f%%", value)
        case .deepSleep, .remSleep: SleepNightFeatures.formatMinutes(max(0, value))
        case .wakeCount: String(format: "%.1f", value)
        }
    }
}

/// Confidence as one to three filled dots over a one-word caption, so
/// "Low confidence" stops being a phrase people have to read to weigh.
struct ConfidenceDots: View {
    let filled: Int
    let caption: String
    @State private var progress: Double = 0

    init(filled: Int, caption: String) {
        self.filled = filled
        self.caption = caption
    }

    init(confidence: JournalCorrelator.Confidence) {
        switch confidence {
        case .low: self.init(filled: 1, caption: "Early")
        case .moderate: self.init(filled: 2, caption: "Likely")
        case .high: self.init(filled: 3, caption: "Strong")
        }
    }

    init(confidence: MetricConfidence) {
        switch confidence {
        case .insufficient: self.init(filled: 0, caption: "Guess")
        case .low: self.init(filled: 1, caption: "Early")
        case .moderate: self.init(filled: 2, caption: "Likely")
        case .high: self.init(filled: 3, caption: "Strong")
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    // Lit one after another as the row appears.
                    let lit = index < filled && progress * 3 > Double(index)
                    Circle()
                        .fill(lit ? Theme.Family.sleep : Theme.neutral(0.15))
                        .frame(width: 6, height: 6)
                        .scaleEffect(lit ? 1 : 0.8)
                }
            }
            .drawOnce(id: filled, progress: $progress)
            Text(caption)
                .font(Theme.text(10))
                .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityHidden(true)
    }
}

/// Supporting prose folded behind one tappable line.
///
/// Many screens ended with the reasoning written out in full -- three
/// paragraphs on why tonight's bedtime moved, a caveat, a confidence label --
/// under the numbers that already answered the question. Most people stop at
/// the numbers; the reasoning is for the few who ask. This keeps it for them
/// without making everyone scroll past it.
struct ExplainDisclosure: View {
    let title: String
    let lines: [String]
    var footnote: String? = nil
    var confidence: ConfidenceDots? = nil
    var systemImage: String = "questionmark.circle"

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.select()
                withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    // At accessibility sizes the icon and dots took the width
                    // and the title broke one word per line; the title wins.
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: systemImage)
                            .font(Theme.text(13, weight: .semibold))
                            .foregroundStyle(Theme.Family.sleep)
                    }
                    Text(title)
                        .font(Theme.label(14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let confidence, !dynamicTypeSize.isAccessibilitySize { confidence }
                    Image(systemName: "chevron.down")
                        .font(Theme.text(11, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides the explanation" : "Shows the explanation")

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Theme.Family.sleep.opacity(0.6))
                                .frame(width: 5, height: 5)
                                .offset(y: -2)
                            Text(line)
                                .font(Theme.text(14))
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let footnote {
                        Text(footnote)
                            .font(Theme.evidence)
                            .foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A label, a bar and a value on one line -- or, at accessibility text
/// sizes, the label and value on a line with the bar underneath. A fixed
/// label column at those sizes broke "With" into "Wi / th".
struct LabeledBar: View {
    let title: String
    let valueText: String
    let fraction: Double
    let tint: Color
    var labelWidth: CGFloat = 60

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// 0 → 1 once on appear: the bar grows to its value rather than
    /// arriving full, so the eye lands on the comparison.
    @State private var progress: Double = 0

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    label
                    Spacer(minLength: 8)
                    value
                }
                track
            }
        } else {
            HStack(spacing: 8) {
                label.frame(width: labelWidth, alignment: .leading)
                track
                value.frame(minWidth: 36, alignment: .trailing)
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(Theme.text(11))
            .foregroundStyle(Theme.inkTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var value: some View {
        Text(valueText)
            .font(Theme.text(11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.inkSecondary)
    }

    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.neutral(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(6, proxy.size.width * min(1, max(0, fraction)) * progress))
            }
        }
        .frame(height: 8)
        .drawOnce(id: fraction, progress: $progress)
    }
}
