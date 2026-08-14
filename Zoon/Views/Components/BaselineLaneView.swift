import SwiftUI

/// "Personal Baseline Lanes" -- the redesign spec's replacement for a
/// radar/spider chart: a shaded band for the personal typical range and a
/// dot for tonight's value, nothing more. No blinking, no alarm red -- an
/// out-of-range dot just sits wherever the number puts it, coloured the same
/// as every other state.
///
/// `value`/`baseline`/`tolerance` mirror `VitalsStatus.Metric` exactly
/// (personal mean ± one standard deviation), so this renders straight from
/// data the app already computes rather than a new statistic invented for
/// the visual.
struct BaselineLaneView: View {
    let value: Double?
    let baseline: Double?
    let tolerance: Double?
    let tint: Color

    /// How many tolerances wide the visible lane is, centred on baseline.
    /// Wider than the shaded band itself (2 tolerances across) so a value at
    /// the edge of "typical" still has room to sit inside the band rather
    /// than pinned to the lane's edge.
    private let windowInTolerances: Double = 2.2

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.neutral(0.08))

                if let baseline, let tolerance, tolerance > 0 {
                    let bandWidth = width / windowInTolerances
                    Capsule()
                        .fill(tint.opacity(0.28))
                        .frame(width: bandWidth)
                        .offset(x: (width - bandWidth) / 2)
                }

                if let value, let baseline, let tolerance, tolerance > 0 {
                    let span = tolerance * windowInTolerances
                    let fraction = ((value - baseline) / span + 1) / 2
                    let clamped = min(max(fraction, 0), 1)
                    Circle()
                        .fill(tint)
                        .frame(width: 9, height: 9)
                        .offset(x: width * clamped - 4.5)
                }
            }
        }
        .frame(height: 14)
    }
}

#Preview("Baseline Lane") {
    VStack(spacing: 16) {
        BaselineLaneView(value: 54, baseline: 52, tolerance: 6, tint: Theme.Metric.hrv)
        BaselineLaneView(value: 68, baseline: 52, tolerance: 6, tint: Theme.Metric.hrv)
        BaselineLaneView(value: nil, baseline: nil, tolerance: nil, tint: Theme.Metric.hrv)
    }
    .padding()
    .nightBackground()
}
