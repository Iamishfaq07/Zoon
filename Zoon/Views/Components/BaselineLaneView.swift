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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                if let tolerance, tolerance > 0 {
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
                        // Item #61/#80: the dot used to jump straight to its
                        // new position on every refresh -- unremarkable for a
                        // single lane, but jarring across a whole Body
                        // Signals screen of them updating at once.
                        .animation(reduceMotion ? nil : Motion.value, value: value)
                }
            }
        }
        .frame(height: 14)
        // The row's own text (`HealthRadarView.baselineBarRow`) already
        // reads out the metric name, value, and typical range -- what it
        // doesn't say is the one thing this visual actually shows: whether
        // tonight's dot landed inside or outside that range. State that
        // explicitly rather than leaving VoiceOver with nothing at all for a
        // Capsule/Circle-drawn view.
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(inRangeDescription == nil)
        .accessibilityLabel(inRangeDescription ?? "")
    }

    private var inRangeDescription: String? {
        guard let value, let baseline, let tolerance, tolerance > 0 else { return nil }
        return abs(value - baseline) <= tolerance ? "Within your typical range" : "Outside your typical range"
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
