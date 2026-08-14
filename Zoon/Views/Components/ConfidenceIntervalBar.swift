import SwiftUI

/// "Add compact distribution/dot visualization" -- the redesign spec's ask
/// for Cause Finder result rows, currently prose-only
/// (`Finding.detail`'s "95% range: X to Y" sentence).
///
/// Individual matched-pair deltas aren't stored on `Finding` (only the
/// median and the bootstrap interval), so this isn't the spec's literal
/// paired-dot plot -- it's the visualization that data actually supports: a
/// zero-anchored bar for the 95% confidence interval, with a tick for the
/// median pair delta. Whether the shaded band crosses zero is the same
/// "clearly one side or genuinely uncertain" read a paired-dot plot would
/// give, just built from the interval Zoon already computed rather than
/// values invented for the picture.
struct ConfidenceIntervalBar: View {
    let median: Double
    let lower: Double
    let upper: Double
    let tint: Color

    /// Half-width of the visible window, symmetric around zero -- wide
    /// enough that the interval never touches the track's edges.
    private var halfWindow: Double {
        max(abs(lower), abs(upper), abs(median)) * 1.35
    }

    private func fraction(_ value: Double) -> Double {
        min(max((value + halfWindow) / (halfWindow * 2), 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.neutral(0.08))

                // Zero reference -- the line that answers "does this
                // interval actually clear no-effect".
                Rectangle()
                    .fill(Theme.neutral(0.25))
                    .frame(width: 1)
                    .offset(x: width * fraction(0))

                let lowerX = width * fraction(lower)
                let upperX = width * fraction(upper)
                Capsule()
                    .fill(tint.opacity(0.30))
                    .frame(width: max(upperX - lowerX, 3))
                    .offset(x: lowerX)

                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .offset(x: width * fraction(median) - 4)
            }
        }
        .frame(height: 12)
    }
}

#Preview("Confidence Interval Bar") {
    VStack(spacing: 20) {
        ConfidenceIntervalBar(median: 16, lower: 7, upper: 25, tint: Theme.Metric.recoveryLow)
        ConfidenceIntervalBar(median: -3, lower: -12, upper: 6, tint: Theme.Metric.recoveryHigh)
    }
    .padding()
    .nightBackground()
}
