import SwiftUI

/// The sleep shortfall, as an open gauge.
///
/// A 240° arc with the gap at the bottom, rather than a closed ring. A closed
/// ring says "this fills up and then you are done", which is true of a goal
/// and false of a debt: shortfall has no full mark, and the number people
/// need is how far along a scale they are, not what fraction of a circle they
/// have completed. The open bottom is where the scale runs out.
///
/// Amber at the near end running to mint at the far one, so the direction of
/// travel is legible before any of the text is: shortfall shrinking means the
/// filled arc retreats out of the amber and toward the green.
struct SleepDebtArcView: View {

    /// Current shortfall.
    let debtMinutes: Double
    /// What the arc treats as its far end. Four hours by convention — the
    /// point past which the app stops distinguishing degrees of "a lot".
    var fullScaleMinutes: Double = 4 * 60
    /// Signed change since the same weekday last week; negative is an
    /// improvement. `nil` when there is not a week of history to compare.
    var weekChangeMinutes: Double?
    /// What tonight's plan pays back, when there is a plan.
    var repaymentMinutes: Double?

    var size: CGFloat = 240
    var lineWidth: CGFloat = 18

    @State private var animatedFraction: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 240° of sweep, centred on 12 o'clock, leaving 120° open at the bottom.
    private static let sweep: Double = 240
    private static var startAngle: Double { 90 + (360 - sweep) / 2 }
    private static var trackTrim: Double { sweep / 360 }

    private var fraction: Double {
        min(1, max(0, debtMinutes / max(fullScaleMinutes, 1)))
    }

    private var band: String {
        switch debtMinutes {
        case ..<30: "Clear"
        case ..<90: "Mild debt"
        case ..<180: "Moderate debt"
        default: "High debt"
        }
    }

    private var bandTint: Color {
        switch debtMinutes {
        case ..<30: Theme.Family.recovery
        case ..<90: Theme.Family.sleep
        default: Theme.Family.attention
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                track
                fill
                centre
            }
            .frame(width: size, height: size)

            if let weekChangeMinutes, abs(weekChangeMinutes) >= 1 {
                weekChangeLine(weekChangeMinutes)
            }
        }
        .onAppear { animate(to: fraction) }
        .onChange(of: debtMinutes) { _, _ in animate(to: fraction) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep shortfall")
        .accessibilityValue(accessibilityValue)
    }

    private var track: some View {
        Circle()
            .trim(from: 0, to: Self.trackTrim)
            .stroke(
                Theme.neutral(0.10),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(Self.startAngle))
    }

    private var fill: some View {
        Circle()
            .trim(from: 0, to: Self.trackTrim * animatedFraction)
            .stroke(
                AngularGradient(
                    colors: [
                        Theme.Family.attention,
                        Theme.Family.attention,
                        Theme.Family.sleep,
                        Theme.Family.recovery
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(Self.sweep)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(Self.startAngle))
            .shadow(color: Theme.Family.attention.opacity(0.35), radius: 12)
    }

    private var centre: some View {
        VStack(spacing: 7) {
            Text("SLEEP SHORTFALL")
                .font(Theme.label(10, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(Theme.inkSecondary)

            Text(SleepNightFeatures.formatMinutes(debtMinutes))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            pill
        }
        // The gauge is a fixed diameter; its centre text is not, and at the
        // largest accessibility sizes it would run out through the stroke.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // The stroke's inner edge is `lineWidth` in from the frame; 12 more
        // keeps the stack off it without giving the pill less room than it
        // needs.
        .padding(.horizontal, lineWidth + 12)
    }

    private var pill: some View {
        HStack(spacing: 5) {
            Text(band)
            if let repaymentMinutes, repaymentMinutes >= 1 {
                Text("•")
                    .foregroundStyle(Theme.inkTertiary)
                Text("−\(Int(repaymentMinutes.rounded()))m tonight")
            }
        }
        .font(Theme.label(11, weight: .semibold))
        // One line, always. "Moderate debt • −8m tonight" wrapped onto two
        // inside the gauge, which splits the band name across lines and
        // makes the badge taller than the number above it. Scaling down is
        // the right trade here: the pill is a qualifier, and a qualifier
        // that reflows is worse than one a point smaller.
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(bandTint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(bandTint.opacity(0.14), in: Capsule())
        .overlay {
            Capsule().stroke(bandTint.opacity(0.28), lineWidth: 0.5)
        }
    }

    /// Down and mint is an improvement; up and amber is not. The arrow and
    /// the colour say the same thing, so neither has to be read carefully.
    private func weekChangeLine(_ change: Double) -> some View {
        let improved = change < 0
        return HStack(spacing: 5) {
            Image(systemName: improved ? "arrow.down" : "arrow.up")
                .font(Theme.text(11, weight: .bold))
            Text("\(improved ? "Improved" : "Up") by \(SleepNightFeatures.formatMinutes(abs(change))) since last week")
                .font(Theme.text(13))
        }
        .foregroundStyle(improved ? Theme.Family.recovery : Theme.Family.attention)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilityValue: String {
        var parts = ["\(SleepNightFeatures.formatMinutes(debtMinutes)), \(band)"]
        if let repaymentMinutes, repaymentMinutes >= 1 {
            parts.append("tonight's plan repays \(Int(repaymentMinutes.rounded())) minutes")
        }
        if let weekChangeMinutes, abs(weekChangeMinutes) >= 1 {
            parts.append(
                weekChangeMinutes < 0
                    ? "improved by \(SleepNightFeatures.formatMinutes(abs(weekChangeMinutes))) since last week"
                    : "up by \(SleepNightFeatures.formatMinutes(weekChangeMinutes)) since last week"
            )
        }
        return parts.joined(separator: ". ")
    }

    private func animate(to target: Double) {
        guard !reduceMotion else {
            animatedFraction = target
            return
        }
        withAnimation(Motion.hero) { animatedFraction = target }
    }
}

#Preview("Sleep shortfall") {
    ZStack {
        Theme.background.ignoresSafeArea()
        SleepDebtArcView(
            debtMinutes: 992,
            weekChangeMinutes: -39,
            repaymentMinutes: 23
        )
    }
    .zoonPreviewEnvironment()
}
