import SwiftUI

/// `UncertaintyForecast` drawn: a translucent band spanning where the
/// person's recent nights landed, a soft crest over the typical value, and
/// the two ends labelled. The copy never calls it a prediction, for the
/// reasons that type's own doc gives.
///
/// ```
///           ╭──────────╮
///  ─────────╯          ╰─────────
///  6h 20m                 8h 05m
/// ```
///
/// Two things about the shape are true and everything else is drawing:
/// the band's **width** is `Forecast.lower...upper` (the 10th–90th
/// percentile of the person's own nights) and its **crest** sits over
/// `Forecast.typical` (their median). The curve between those anchors is a
/// smooth hump, not an estimated density -- `UncertaintyForecast` reports
/// three numbers, and this shows three numbers, so a wide band reads as
/// "your nights vary a lot" and a narrow one as "your nights are steady",
/// which is the comparison the forecast exists to make.
///
/// * Draw-in is once per forecast: the band widens from the crest outward,
///   so the first thing seen is the typical value and the second is how far
///   nights stray from it.
/// * The confidence badge is the number of nights behind the interval,
///   never the width of the interval -- those are different facts.
/// * "Why this range?" expands to the caveat and the coverage, in the
///   forecast's own words, rather than paraphrasing them here.
struct ZoonUncertaintyBand: View {
    let forecast: UncertaintyForecast.Forecast
    var tint: Color = Theme.Family.sleep
    /// Shows the "Expected / Confidence" summary under the band. `false`
    /// when the caller lays those out itself.
    var showsSummary: Bool = true

    @State private var progress: Double = 0
    @State private var showsWhy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            band
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 84 : 68)
                .drawOnce(id: forecast, progress: $progress)
                .chartSummary(chartLabel, chartSummaryText)

            if showsSummary { summary }
        }
    }

    // MARK: - Band

    /// The axis runs a little past both ends so the band never touches the
    /// edge of its frame and the end labels have room to sit under it.
    private var axis: ClosedRange<Double> {
        let pad = max(forecast.spread * 0.35, 1)
        return (forecast.lower - pad)...(forecast.upper + pad)
    }

    private func x(_ value: Double, width: CGFloat) -> CGFloat {
        let span = axis.upperBound - axis.lowerBound
        return width * CGFloat((value - axis.lowerBound) / span)
    }

    private var band: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let labelHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 24 : 18
            let curveHeight = geo.size.height - labelHeight - 6
            let crestX = x(forecast.typical, width: width)
            // Band grows out from the crest as progress runs 0 → 1.
            let leftX = crestX + (x(forecast.lower, width: width) - crestX) * CGFloat(progress)
            let rightX = crestX + (x(forecast.upper, width: width) - crestX) * CGFloat(progress)

            ZStack(alignment: .topLeading) {
                // Baseline the band rises from.
                Rectangle()
                    .fill(Theme.neutral(0.16))
                    .frame(height: 1)
                    .offset(y: curveHeight)

                // The hump: fill then edge.
                hump(left: leftX, crest: crestX, right: rightX, height: curveHeight)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.42), tint.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                hump(left: leftX, crest: crestX, right: rightX, height: curveHeight)
                    .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Crest marker over the typical value.
                Rectangle()
                    .fill(tint.opacity(0.55))
                    .frame(width: 1, height: curveHeight * 0.55)
                    .offset(x: crestX - 0.5, y: curveHeight * 0.45)
                    .opacity(progress > 0.15 ? 1 : 0)

                // End labels, clamped inside the frame.
                endLabel(forecast.metric.formattedMagnitude(forecast.lower), at: x(forecast.lower, width: width), width: width, alignment: .trailing)
                    .offset(y: curveHeight + 6)
                endLabel(forecast.metric.formattedMagnitude(forecast.upper), at: x(forecast.upper, width: width), width: width, alignment: .leading)
                    .offset(y: curveHeight + 6)
            }
            .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.3)), value: progress > 0.15)
        }
        .accessibilityHidden(true)
    }

    /// A smooth crest over `crest`, meeting the baseline at `left` and
    /// `right`. Two cubic segments so the shoulders are soft and the peak is
    /// exactly over the typical value rather than the midpoint.
    private func hump(left: CGFloat, crest: CGFloat, right: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let base = height
            let top = height * 0.18
            path.move(to: CGPoint(x: left, y: base))
            path.addCurve(
                to: CGPoint(x: crest, y: top),
                control1: CGPoint(x: left + (crest - left) * 0.55, y: base),
                control2: CGPoint(x: left + (crest - left) * 0.55, y: top)
            )
            path.addCurve(
                to: CGPoint(x: right, y: base),
                control1: CGPoint(x: crest + (right - crest) * 0.45, y: top),
                control2: CGPoint(x: crest + (right - crest) * 0.45, y: base)
            )
            path.closeSubpath()
        }
    }

    private func endLabel(_ text: String, at position: CGFloat, width: CGFloat, alignment: Alignment) -> some View {
        let labelWidth: CGFloat = dynamicTypeSize.isAccessibilitySize ? 90 : 64
        let x = alignment == .trailing
            ? max(0, min(position - labelWidth * 0.75, width - labelWidth))
            : max(0, min(position - labelWidth * 0.25, width - labelWidth))
        return Text(text)
            .font(Theme.supportingLabel)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: labelWidth, alignment: alignment)
            .offset(x: x)
            .opacity(progress >= 0.9 ? 1 : 0)
            .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.25)), value: progress >= 0.9)
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    // "Recent nights", not "Expected": the type is explicit
                    // that this is where nights landed, not a prediction.
                    Text("Recent nights")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text("\(forecast.metric.formattedMagnitude(forecast.lower))–\(forecast.metric.formattedMagnitude(forecast.upper))")
                        .font(Theme.supportingValue)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Confidence")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    ZoonEvidenceBadge(confidence: forecast.confidence)
                }
            }
            .accessibilityElement(children: .combine)

            Button {
                withAnimation(Motion.respecting(reduceMotion, Motion.standard)) { showsWhy.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text("Why this range?")
                    Image(systemName: "chevron.down")
                        .font(Theme.text(9, weight: .bold))
                        .rotationEffect(.degrees(showsWhy ? 180 : 0))
                }
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsWhy ? "Hides the explanation" : "Explains how the range was worked out")

            if showsWhy {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The band is where the middle \(Int(UncertaintyForecast.upperPercentile - UncertaintyForecast.lowerPercentile))% of your last \(forecast.nightsUsed.pluralized("night")) landed for \(forecast.metric.label); the crest is your typical night. A wider band means your nights vary more.")
                    Text(forecast.caveat)
                }
                .font(Theme.evidence)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Accessibility

    private var chartLabel: String {
        "Range for \(forecast.metric.label)"
    }

    private var chartSummaryText: String {
        forecast.sentence + " \(forecast.confidence.label)."
    }
}

#Preview("Uncertainty band") {
    let coordinator = PreviewSupport.coordinator
    ScrollView {
        VStack(alignment: .leading, spacing: 32) {
            ForEach(UncertaintyForecast.forecastAll(nights: coordinator.recentNights).prefix(3), id: \.metric) { forecast in
                VStack(alignment: .leading, spacing: 8) {
                    Text(forecast.metric.label.capitalizedFirst)
                        .font(Theme.label(15, weight: .semibold))
                    ZoonUncertaintyBand(forecast: forecast)
                }
            }
        }
        .padding()
    }
    .nightBackground()
    .zoonPreviewEnvironment()
}
