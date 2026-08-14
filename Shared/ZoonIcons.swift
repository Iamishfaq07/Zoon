import SwiftUI

/// Custom vector icons for Zoon-specific concepts, alongside SF Symbols for
/// familiar system actions -- the redesign spec's "Custom Icon Family".
///
/// Built entirely from primitives (`Circle`, `.trim`, simple `Path` curves)
/// this codebase already uses successfully elsewhere at icon scale
/// (`MetricRing`, `BodyClockCard`'s dial) rather than freehand shapes like a
/// crescent moon, which need boolean path operations to get right and are
/// much easier to get visibly wrong. These have not been checked against a
/// rendered screenshot -- only verified to compile -- so treat the exact
/// proportions as a first pass, not a finished mark.
enum ZoonIcon {

    /// Sleep Intelligence: a segmented orbit ring around a solid core --
    /// echoes the seven-arc orb hero on Today without duplicating its full
    /// interactive complexity at icon scale.
    struct SleepIntelligence: View {
        var tint: Color = Theme.Metric.sleep

        var body: some View {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: side * 0.44, height: side * 0.44)
                    ForEach(0..<8, id: \.self) { segment in
                        Capsule()
                            .fill(tint.opacity(0.7))
                            .frame(width: side * 0.09, height: side * 0.14)
                            .offset(y: -side * 0.42)
                            .rotationEffect(.degrees(Double(segment) / 8 * 360))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    /// Sleep Debt: a ring with a deliberate gap -- the deficit -- rather
    /// than a complete circle, echoing `SleepDebtCalculator`'s ring
    /// visualizations elsewhere in the app.
    struct SleepDebt: View {
        var tint: Color = Theme.Metric.recoveryMid
        /// Fraction of the ring left open, matching how much is "owed".
        var deficit: Double = 0.28

        var body: some View {
            Circle()
                .trim(from: 0, to: 1 - deficit)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    /// Body Clock: a 24-hour ring with quarter ticks and a center dot,
    /// directly echoing `BodyClockCard`'s dial at a much smaller scale.
    struct BodyClock: View {
        var tint: Color = Theme.Metric.battery

        var body: some View {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.85), lineWidth: 1.6)
                    ForEach(0..<4, id: \.self) { tick in
                        Capsule()
                            .fill(tint)
                            .frame(width: 1.2, height: side * 0.14)
                            .offset(y: -side * 0.43)
                            .rotationEffect(.degrees(Double(tick) / 4 * 360))
                    }
                    Circle()
                        .fill(tint)
                        .frame(width: side * 0.14, height: side * 0.14)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    /// Breathing: two offset wave arcs, echoing an inhale/exhale pair rather
    /// than a single literal waveform.
    struct Breathing: View {
        var tint: Color = Theme.Metric.respiratory

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    wave(width: width, height: height, verticalOffset: height * 0.32)
                        .stroke(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    wave(width: width, height: height, verticalOffset: height * 0.6)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                }
            }
        }

        private func wave(width: CGFloat, height: CGFloat, verticalOffset: CGFloat) -> Path {
            Path { path in
                path.move(to: CGPoint(x: 0, y: verticalOffset))
                path.addCurve(
                    to: CGPoint(x: width, y: verticalOffset),
                    control1: CGPoint(x: width * 0.25, y: verticalOffset - height * 0.22),
                    control2: CGPoint(x: width * 0.75, y: verticalOffset + height * 0.22)
                )
            }
        }
    }
}

#Preview("Zoon Icons") {
    HStack(spacing: 20) {
        ZoonIcon.SleepIntelligence().frame(width: 28, height: 28)
        ZoonIcon.SleepDebt().frame(width: 28, height: 28)
        ZoonIcon.BodyClock().frame(width: 28, height: 28)
        ZoonIcon.Breathing().frame(width: 28, height: 28)
    }
    .padding()
    .background(Color.black)
}
