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
    ///
    /// Tuned against a rendered capture rather than guessed: the first pass
    /// used eight segments at 0.09 x 0.14 of the side, which at the 13pt the
    /// Insights hero draws it works out to roughly 1.2 x 1.8pt per segment.
    /// That collapsed into an indistinct smudge -- the ring read as noise
    /// beside the crisp SF Symbols in the rows below it. Six chunkier
    /// segments hold their shape down to about 14pt.
    struct SleepIntelligence: View {
        var tint: Color = Theme.Metric.sleep

        var body: some View {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: side * 0.40, height: side * 0.40)
                    ForEach(0..<6, id: \.self) { segment in
                        Capsule()
                            .fill(tint.opacity(0.85))
                            .frame(width: side * 0.15, height: side * 0.24)
                            .offset(y: -side * 0.38)
                            .rotationEffect(.degrees(Double(segment) / 6 * 360))
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

    /// Sleep Need: a capsule track with a partial fill, echoing
    /// `CoreIntelligenceGrid`'s own Sleep Need tile visual (a horizontal
    /// achieved-vs-need bar) rather than the generic "target" SF Symbol it
    /// used before this existed.
    struct SleepNeed: View {
        var tint: Color = Theme.Metric.sleep
        /// Fraction of the need achieved, 0...1.
        var fraction: Double = 0.8

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.25))
                        .frame(width: width, height: height * 0.32)
                    Capsule()
                        .fill(tint)
                        .frame(width: width * max(0.18, min(1, fraction)), height: height * 0.32)
                }
            }
        }
    }

    /// Body Signals: a small cluster of dots at varying opacity, echoing
    /// `CoreIntelligenceGrid`'s own Body Signals tile (one dot per drifting
    /// vital) rather than the generic "dot.radiowaves" SF Symbol.
    struct BodySignals: View {
        var tint: Color = Theme.Metric.recoveryMid

        var body: some View {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                HStack(spacing: side * 0.14) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(tint.opacity(index == 1 ? 1 : 0.4))
                            .frame(width: side * 0.16, height: side * 0.16)
                            .offset(y: index % 2 == 0 ? -side * 0.08 : side * 0.08)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
    }

    /// Cause Finder: two dots joined by a connecting line -- a matched pair,
    /// the statistical unit `JournalCorrelator`/`PairedDotPlot` actually
    /// compare, rather than the generic "sparkle.magnifyingglass" SF Symbol.
    struct CauseFinder: View {
        var tint: Color = Theme.Metric.hrv

        var body: some View {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                ZStack {
                    Rectangle()
                        .fill(tint.opacity(0.5))
                        .frame(width: width * 0.5, height: 1.4)
                    Circle()
                        .stroke(tint, lineWidth: 1.6)
                        .frame(width: width * 0.34, height: width * 0.34)
                        .offset(x: -width * 0.24)
                    Circle()
                        .fill(tint)
                        .frame(width: width * 0.34, height: width * 0.34)
                        .offset(x: width * 0.24)
                }
                .frame(width: width, height: height)
            }
        }
    }

    /// Recovery: a mostly-filled ring, echoing `RecoveryRing`'s own filled
    /// arc-gauge language rather than a generic heart or battery SF Symbol.
    struct Recovery: View {
        var tint: Color = Theme.Metric.recoveryHigh
        /// Fraction of the ring filled, 0...1.
        var fraction: Double = 0.78

        var body: some View {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: max(0.06, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
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
        ZoonIcon.SleepNeed().frame(width: 28, height: 28)
        ZoonIcon.SleepDebt().frame(width: 28, height: 28)
        ZoonIcon.BodyClock().frame(width: 28, height: 28)
        ZoonIcon.BodySignals().frame(width: 28, height: 28)
        ZoonIcon.CauseFinder().frame(width: 28, height: 28)
        ZoonIcon.Recovery().frame(width: 28, height: 28)
        ZoonIcon.Breathing().frame(width: 28, height: 28)
    }
    .padding()
    .background(Color.black)
}
