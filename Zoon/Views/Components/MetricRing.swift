import SwiftUI

/// The hero recovery ring.
///
/// A single big arc with the number inside. Everything about it is tuned for
/// one job: being readable at a glance, half-awake, from arm's length.
///
/// - The arc animates from zero on appear, which gives the number weight —
///   a value that's just *there* on load reads as static text.
/// - Digits are monospaced so the number doesn't wobble mid-animation.
/// - The whole thing is one accessibility element; VoiceOver reading "72",
///   "percent", "High" as three unrelated fragments is worse than useless.
struct RecoveryRing: View {

    let recovery: RecoveryScore
    var size: CGFloat = 200
    var lineWidth: CGFloat = 18

    @State private var animatedFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { min(1, max(0, Double(recovery.percent) / 100)) }
    private var color: Color { Theme.recoveryColor(Double(recovery.percent)) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Theme.neutral(0.07), lineWidth: lineWidth)

            // Soft outer bloom — reads as light rather than paint.
            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(
                    Theme.recoveryGradient(Double(recovery.percent)),
                    style: StrokeStyle(lineWidth: lineWidth + 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: 14)
                .opacity(0.55)

            Circle()
                .trim(from: 0, to: animatedFraction)
                .stroke(
                    Theme.recoveryGradient(Double(recovery.percent)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            content
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else {
                animatedFraction = fraction
                return
            }
            withAnimation(Motion.hero) {
                animatedFraction = fraction
            }
        }
        .onChange(of: recovery.percent) { _, _ in
            withAnimation(reduceMotion ? nil : Motion.hero) {
                animatedFraction = fraction
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recovery")
        .accessibilityValue(
            recovery.isEstimate
                ? "\(recovery.percent) percent, still building your baseline"
                : "\(recovery.percent) percent, \(recovery.band.label)"
        )
    }

    private var content: some View {
        VStack(spacing: 0) {
            Text("RECOVERY")
                .font(Theme.label(10, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 1) {
                Text("\(recovery.percent)")
                    .font(Theme.numeral(size * 0.30))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("%")
                    .font(Theme.numeral(size * 0.13))
                    .padding(.top, size * 0.05)
            }
            .foregroundStyle(color)

            Text(recovery.isEstimate ? "Estimate" : recovery.band.label)
                .font(Theme.label(12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Compact multi-arc ring for secondary metrics (strain, sleep, battery).
///
/// Concentric rather than side-by-side because the whole point is that these
/// three are read *together* — strain against recovery is the actual signal.
struct TripleRing: View {

    struct Arc {
        let fraction: Double
        let color: Color
        let label: String
        let value: String
    }

    let arcs: [Arc]
    var size: CGFloat = 92
    var lineWidth: CGFloat = 8

    @State private var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { index, arc in
                let inset = CGFloat(index) * (lineWidth + 4)

                Circle()
                    .stroke(arc.color.opacity(0.15), lineWidth: lineWidth)
                    .padding(inset)

                Circle()
                    .trim(from: 0, to: animated ? min(1, max(0, arc.fraction)) : 0)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion {
                animated = true
            } else {
                withAnimation(Motion.hero.delay(0.1)) {
                    animated = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(arcs.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }
}

/// Horizontal gauge with a marked "typical" band — used by the vitals rows.
struct RangeGauge: View {
    /// 0...1 position of the current value.
    let position: Double
    /// 0...1 bounds of the typical band.
    let bandStart: Double
    let bandEnd: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.neutral(0.08))

                Capsule()
                    .fill(tint.opacity(0.28))
                    .frame(width: geo.size.width * max(0, bandEnd - bandStart))
                    .offset(x: geo.size.width * bandStart)

                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .shadow(color: tint.opacity(0.8), radius: 4)
                    .offset(x: geo.size.width * min(max(position, 0), 1) - 4.5)
            }
        }
        .frame(height: 9)
    }
}

#Preview("Rings") {
    ScrollView {
        VStack(spacing: 30) {
            RecoveryRing(recovery: AppMockData.dayContext().recovery)
            RecoveryRing(recovery: AppMockData.poorDayContext().recovery, size: 150, lineWidth: 14)
            TripleRing(arcs: [
                .init(fraction: 0.62, color: Theme.Metric.strain, label: "Load", value: "13.1"),
                .init(fraction: 0.88, color: Theme.Metric.sleep, label: "Sleep", value: "88%"),
                .init(fraction: 0.44, color: Theme.Metric.battery, label: "Energy", value: "44")
            ])
            RangeGauge(position: 0.72, bandStart: 0.3, bandEnd: 0.7, tint: Theme.Metric.hrv)
                .padding(.horizontal, 40)
        }
        .padding(40)
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
