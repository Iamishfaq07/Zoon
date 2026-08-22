import SwiftUI

/// One dot per matched pair, plotted against a zero-anchored axis --
/// `Finding.pairDeltas`, unsummarized. The redesign spec's literal ask for
/// Cause Finder result rows: not the median and interval alone, but the
/// actual spread those numbers were computed from, so a tight cluster of
/// eleven dots on one side of zero and one loose cluster straddling it read
/// as visibly different findings even at the same median.
///
/// Vertical position is decorative jitter only, spread deterministically by
/// index so the same finding always draws the same picture rather than
/// reshuffling on every re-render.
struct PairedDotPlot: View {
    let deltas: [Double]
    let tint: Color

    private var halfWindow: Double {
        max(deltas.map(abs).max() ?? 1, 1) * 1.15
    }

    private func fraction(_ value: Double) -> Double {
        min(max((value + halfWindow) / (halfWindow * 2), 0), 1)
    }

    /// Deterministic pseudo-random spread in -1...1, keyed by index rather
    /// than `Double.random` -- a jittered dot that moved to a new spot every
    /// time SwiftUI redrew the row would read as noise in the data itself.
    private func jitter(_ index: Int) -> Double {
        let seed = (index &* 2_654_435_761) % 1000
        return Double(seed) / 500 - 1
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.neutral(0.25))
                    .frame(width: 1)
                    .offset(x: width * fraction(0))

                ForEach(Array(deltas.enumerated()), id: \.offset) { index, delta in
                    Circle()
                        .fill(tint.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .position(
                            x: width * fraction(delta),
                            y: height / 2 + jitter(index) * (height / 2 - 4)
                        )
                }
            }
        }
        .frame(height: 28)
        // Decorative: the shape a sighted reader takes in at a glance is
        // already stated as prose in `Finding.detail` right below this plot.
        .accessibilityHidden(true)
    }
}

#Preview("Paired Dot Plot") {
    VStack(spacing: 20) {
        PairedDotPlot(deltas: [4, 6, 5, 7, 3, 8, 6, 5], tint: Theme.Metric.recoveryLow)
        PairedDotPlot(deltas: [-8, 3, -2, 6, -5, 1, -4], tint: Theme.Metric.recoveryHigh)
    }
    .padding()
    .nightBackground()
}
