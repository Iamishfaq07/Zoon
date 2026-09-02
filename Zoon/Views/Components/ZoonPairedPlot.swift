import SwiftUI

/// The Cause Finder's DISTRIBUTION visual: every matched pair drawn as a
/// comparison-night dot on the left, a tagged-night dot on the right, and
/// the connector between them.
///
/// ```
/// WITHOUT                    WITH
/// 12m ●──────────────────● 29m
/// 15m   ●───────────────● 27m
/// ```
///
/// What the slope of the connectors says is the finding. Twelve lines that
/// all lean the same way are a pattern a reader takes in without a number;
/// twelve that cross each other are the picture of "no effect", however the
/// median came out. That is why this shows the pairs themselves and not a
/// bar of the median: `JournalCorrelator` already reduced the pairs to a
/// median and an interval, and this puts the reduction's input back on the
/// page so the summary underneath can be checked against it by eye.
///
/// * Values are placed on a shared vertical axis across both columns, so a
///   connector's slope is the pair's delta in the metric's own units.
/// * Draw-in is two beats, once per finding: dots settle, then connectors
///   draw left → right. Never replays on scroll (`drawOnce`).
/// * Vertical scrub highlights the nearest pair and reads it out. Lifting
///   the finger returns to the whole picture.
/// * Improvement vs. deterioration is told by the summary's words and the
///   connector direction, never colour alone.
struct ZoonPairedPlot: View {
    let finding: JournalCorrelator.Finding
    var tint: Color = Theme.Family.sleep

    @State private var progress: Double = 0
    @State private var scrubFraction: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Pairs in ascending order of comparison value, so the plot reads as a
    /// stack rather than the matching order. Stable across renders.
    private var pairs: [JournalCorrelator.Finding.Pair] {
        finding.pairs.sorted { $0.matched < $1.matched }
    }

    private var range: ClosedRange<Double> {
        let values = pairs.flatMap { [$0.matched, $0.exposed] }
        guard let low = values.min(), let high = values.max(), high > low else {
            let value = values.first ?? 0
            return (value - 1)...(value + 1)
        }
        let pad = (high - low) * 0.08
        return (low - pad)...(high + pad)
    }

    /// The pair whose comparison dot is nearest the finger. Nearest-by-y
    /// rather than an even bucket, because the dots sit at their values,
    /// not in evenly spaced lanes.
    private var selectedIndex: Int? {
        guard let scrubFraction, !pairs.isEmpty else { return nil }
        return nearestPair(toFraction: scrubFraction)
    }

    private func nearestPair(toFraction fraction: CGFloat) -> Int? {
        guard !pairs.isEmpty else { return nil }
        // yFraction 0 = top of plot = range.upperBound.
        let targetValue = range.upperBound - Double(fraction) * (range.upperBound - range.lowerBound)
        return pairs.indices.min { abs(pairs[$0].matched - targetValue) < abs(pairs[$1].matched - targetValue) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            columnHeaders

            plot
                .frame(height: plotHeight)
                .drawOnce(id: finding.id, progress: $progress)

            summary
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Headers

    private var columnHeaders: some View {
        HStack {
            Text("Without")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            Text(finding.tag.label)
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Plot

    /// Enough height for each pair to have its own lane, with a floor so
    /// eight pairs don't cramp and a ceiling so forty don't scroll the page.
    private var plotHeight: CGFloat {
        let base: CGFloat = dynamicTypeSize.isAccessibilitySize ? 14 : 11
        return min(max(CGFloat(pairs.count) * base, 120), 260)
    }

    private var plot: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            // Room for the value labels at either end.
            let labelWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 56 : 44
            let leftX = labelWidth + 6
            let rightX = width - labelWidth - 6

            ZStack(alignment: .topLeading) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                    let isSelected = selectedIndex == index
                    let isDimmed = selectedIndex != nil && !isSelected
                    let y0 = yPosition(pair.matched, height: height)
                    let y1 = yPosition(pair.exposed, height: height)

                    connector(from: CGPoint(x: leftX, y: y0), to: CGPoint(x: rightX, y: y1))
                        .trimmedPath(from: 0, to: connectorProgress)
                        .stroke(
                            tint.opacity(isSelected ? 0.95 : isDimmed ? 0.12 : 0.45),
                            style: StrokeStyle(lineWidth: isSelected ? 2 : 1, lineCap: .round)
                        )

                    dot(selected: isSelected, dimmed: isDimmed, filled: false)
                        .position(x: leftX, y: y0)
                    dot(selected: isSelected, dimmed: isDimmed, filled: true)
                        .position(x: rightX, y: y1)

                    if isSelected {
                        Text(finding.metric.formatAbsolute(pair.matched))
                            .font(Theme.supportingLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, alignment: .trailing)
                            .position(x: labelWidth / 2, y: y0)
                        Text(finding.metric.formatAbsolute(pair.exposed))
                            .font(Theme.supportingLabel)
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .frame(width: labelWidth, alignment: .leading)
                            .position(x: width - labelWidth / 2, y: y1)
                    }
                }

                if selectedIndex == nil {
                    medianLabels(labelWidth: labelWidth, width: width, height: height)
                }
            }
            .opacity(progress > 0 ? 1 : 0)
            .animation(Motion.respecting(reduceMotion, Motion.scrub), value: selectedIndex)
        }
        .zoonScrubbable(fraction: $scrubFraction, axis: .vertical, detent: { nearestPair(toFraction: $0) })
        .chartSummary(chartLabel, selectedPairDescription ?? chartSummaryText)
        .accessibilityHint("Press and hold, then drag up or down to inspect individual pairs.")
    }

    /// The connectors wait for the dots: the second half of `progress`.
    private var connectorProgress: Double {
        min(max((progress - 0.45) / 0.55, 0), 1)
    }

    private func yPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        let fraction = (value - range.lowerBound) / span
        // Higher values sit higher on the page, with 6pt breathing room.
        return 6 + (height - 12) * CGFloat(1 - fraction)
    }

    private func connector(from: CGPoint, to: CGPoint) -> Path {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
    }

    /// Comparison nights are outlined; tagged nights are filled -- the
    /// column is told by shape as well as by position.
    private func dot(selected: Bool, dimmed: Bool, filled: Bool) -> some View {
        Circle()
            .strokeBorder(tint.opacity(dimmed ? 0.2 : 0.9), lineWidth: 1.2)
            .background(Circle().fill(filled ? tint.opacity(dimmed ? 0.15 : 0.9) : Color.clear))
            .frame(width: selected ? 9 : 6, height: selected ? 9 : 6)
            .scaleEffect(progress > 0 ? 1 : 0.2)
    }

    /// The two column medians as quiet end labels, so the plot carries its
    /// own scale without an axis.
    private func medianLabels(labelWidth: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(finding.metric.formatAbsolute(finding.matchedMedian))
                .font(Theme.supportingLabel)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: labelWidth, alignment: .trailing)
                .position(x: labelWidth / 2, y: yPosition(finding.matchedMedian, height: height))
            Text(finding.metric.formatAbsolute(finding.taggedMedian))
                .font(Theme.supportingLabel)
                .monospacedDigit()
                .foregroundStyle(tint.opacity(0.8))
                .frame(width: labelWidth, alignment: .leading)
                .position(x: width - labelWidth / 2, y: yPosition(finding.taggedMedian, height: height))
        }
        .opacity(progress >= 0.95 ? 1 : 0)
        .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.25)), value: progress)
        .allowsHitTesting(false)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Median paired difference")
                .font(Theme.kicker)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text("\(finding.metric.format(finding.delta)) \(finding.metric.shortLabel)")
                .font(Theme.supportingValue)
                .monospacedDigit()
                .foregroundStyle(tint)
            HStack(spacing: 10) {
                Text(finding.matchedPairCount.pluralized("matched pair"))
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
                ZoonEvidenceBadge(confidence: Self.metricConfidence(finding.confidence))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Accessibility

    private var chartLabel: String {
        "\(finding.tag.label) against \(finding.metric.shortLabel), matched pairs"
    }

    private var chartSummaryText: String {
        let direction = finding.isImprovement ? "better" : "worse"
        return "\(finding.matchedPairCount.pluralized("pair")). On the typical pair, \(finding.metric.shortLabel) was \(finding.metric.format(finding.delta)), \(direction), with \(finding.tag.label.lowercased()). \(finding.confidence.label)."
    }

    private var selectedPairDescription: String? {
        guard let selectedIndex, pairs.indices.contains(selectedIndex) else { return nil }
        let pair = pairs[selectedIndex]
        return "Pair \(selectedIndex + 1): \(finding.metric.formatAbsolute(pair.matched)) without, \(finding.metric.formatAbsolute(pair.exposed)) with, \(finding.metric.format(pair.delta))."
    }

    /// `JournalCorrelator.Confidence` has three levels to `MetricConfidence`'s
    /// four; no `.insufficient` finding is ever emitted.
    static func metricConfidence(_ confidence: JournalCorrelator.Confidence) -> MetricConfidence {
        switch confidence {
        case .low: .low
        case .moderate: .moderate
        case .high: .high
        }
    }
}

extension JournalCorrelator.Metric {
    /// The metric's value as a plain reading rather than a signed change --
    /// `format` is for deltas ("+14m", "−3%"); this is for the two ends a
    /// delta was taken between ("1h 18m", "91%").
    func formatAbsolute(_ value: Double) -> String {
        switch self {
        case .recovery, .sleepPerformance, .efficiency:
            String(format: "%.0f%%", value)
        case .deepSleep, .remSleep:
            SleepNightFeatures.formatMinutes(value)
        case .wakeCount:
            String(format: "%.0f", value)
        }
    }
}

#Preview("Paired plot") {
    ScrollView {
        VStack(alignment: .leading, spacing: 36) {
            ForEach(AppMockData.correlationFindings.prefix(2)) { finding in
                ZoonPairedPlot(
                    finding: finding,
                    tint: finding.isImprovement ? Theme.Family.recovery : Theme.Family.attention
                )
            }
        }
        .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}
