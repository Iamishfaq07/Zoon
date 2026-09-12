import SwiftUI

/// Sleep debt as a reservoir, not a number with a colour.
///
/// A 270° arc: the empty track is the full reservoir, the filled portion is
/// how much of it debt currently occupies. Scale is deliberately gentle --
/// the arc is full at four hours, the point where `SleepDebtView` already
/// calls debt "High" -- so a typical 30–90 minute debt reads as a quarter to
/// a third of the arc, not a flashing warning. No red: the fill is the
/// sleep hue, shifting to attention amber only past two hours.
///
/// Under the arc, the change since a week ago, from the same
/// `sleepDebtMinutes` history the debt chart plots.
struct LunarReservoir: View {
    let debtMinutes: Double
    /// Debt a week ago, if known, for the trend line.
    var weekAgoMinutes: Double?
    /// What tonight's plan already sets aside to repay, from
    /// `SleepAutopilot.Plan.debtRepaymentMinutes`. Drawn as the far end of
    /// the filled arc in the recovery hue, so the part of the shortfall
    /// tonight is going to clear is visible rather than only stated in a
    /// sentence further down the screen.
    var repaymentMinutes: Double?
    var size: CGFloat = 200

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0

    /// The arc is full at four hours of debt.
    private static let fullMinutes: Double = 240
    /// The arc spans 270 degrees, starting at 135.
    private static let sweep: Double = 270
    private var fraction: Double { min(1, max(0, debtMinutes / Self.fullMinutes)) }

    /// How much of the filled arc tonight's plan clears, as a fraction of the
    /// whole reservoir. Never more than what is actually owed.
    private var repaidFraction: Double {
        guard let repaymentMinutes, repaymentMinutes > 0 else { return 0 }
        return min(fraction, repaymentMinutes / Self.fullMinutes)
    }

    private var tint: Color {
        debtMinutes >= 120 ? Theme.Family.attention : Theme.Family.sleep
    }

    private var band: String {
        switch debtMinutes {
        case ..<30: "Minimal"
        case 30..<120: "Mild"
        case 120..<240: "Moderate"
        default: "High"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Theme.neutral(0.07), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: 0.75 * fraction * progress)
                    .stroke(
                        LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(135))

                // The slice of the shortfall tonight's plan already clears,
                // drawn over the far end of the fill. Arrives after the arc
                // has finished rather than with it: it is a consequence of
                // the number, and showing it at the same moment reads as two
                // arcs racing.
                if repaidFraction > 0 {
                    Circle()
                        .trim(
                            from: 0.75 * (fraction - repaidFraction) * progress,
                            to: 0.75 * fraction * progress
                        )
                        .stroke(
                            Theme.Family.recovery,
                            style: StrokeStyle(lineWidth: 16, lineCap: .round)
                        )
                        .rotationEffect(.degrees(135))
                        .opacity(progress > 0.92 ? 1 : 0)
                        .animation(Motion.respecting(reduceMotion, Motion.hero), value: progress > 0.92)
                }

                // Hour marks. The reservoir is full at four hours and said so
                // only in a doc comment -- without them the arc has no scale
                // at all and a quarter-full ring means nothing in particular.
                ForEach(1..<4) { hour in
                    let t = Double(hour) * 60 / Self.fullMinutes
                    Capsule()
                        .fill(Theme.neutral(0.22))
                        .frame(width: 2, height: 5)
                        // Inside the ring, not under it. At `size/2 - 8`
                        // these sat exactly within the stroke band (centred
                        // on size/2, 16 wide, so ±8) and were painted over
                        // by the arc -- invisible in the first render.
                        .offset(y: -(size / 2 - 26))
                        .rotationEffect(.degrees(135 + Self.sweep * t + 90))
                }

                VStack(spacing: 4) {
                    Text("Sleep shortfall")
                        .font(Theme.kicker)
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSecondary)
                    Text(debtMinutes > 1 ? SleepNightFeatures.formatMinutes(debtMinutes) : "None")
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(band)
                        .font(Theme.meaning)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(tint)

                    if let repaymentMinutes, repaymentMinutes >= 1 {
                        Text("−\(SleepNightFeatures.formatMinutes(repaymentMinutes)) tonight")
                            .font(Theme.label(12, weight: .semibold))
                            .foregroundStyle(Theme.Family.recovery)
                            .monospacedDigit()
                            .padding(.top, 2)
                    }
                }
                .opacity(progress > 0.2 ? 1 : 0)
                .animation(Motion.respecting(reduceMotion, Motion.hero), value: progress > 0.2)
            }
            .frame(width: size, height: size)

            if let weekAgoMinutes {
                trendLine(weekAgo: weekAgoMinutes)
            }
        }
        .frame(maxWidth: .infinity)
        .drawOnce(id: Int(debtMinutes.rounded()), progress: $progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated sleep shortfall")
        .accessibilityValue(accessibilityValue)
    }

    private func trendLine(weekAgo: Double) -> some View {
        let delta = debtMinutes - weekAgo
        return HStack(spacing: 6) {
            if abs(delta) < 5 {
                Image(systemName: "equal")
                Text("About the same as a week ago")
            } else if delta < 0 {
                Image(systemName: "arrow.down.right")
                Text("Improved by \(SleepNightFeatures.formatMinutes(abs(delta))) since last week")
            } else {
                Image(systemName: "arrow.up.right")
                Text("Up \(SleepNightFeatures.formatMinutes(delta)) since last week")
            }
        }
        .font(Theme.text(13, weight: .medium))
        .foregroundStyle(abs(delta) < 5 ? Theme.inkSecondary : (delta < 0 ? Theme.Family.recovery : Theme.Family.attention))
    }

    private var accessibilityValue: String {
        var parts = ["\(debtMinutes > 1 ? SleepNightFeatures.formatMinutes(debtMinutes) : "none") short, \(band.lowercased())"]
        if let repaymentMinutes, repaymentMinutes >= 1 {
            parts.append("tonight's plan repays \(SleepNightFeatures.formatMinutes(repaymentMinutes))")
        }
        if let weekAgoMinutes {
            let delta = debtMinutes - weekAgoMinutes
            if abs(delta) >= 5 {
                parts.append("\(delta < 0 ? "down" : "up") \(SleepNightFeatures.formatMinutes(abs(delta))) since last week")
            }
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Lunar Reservoir") {
    ScrollView {
        VStack(spacing: 40) {
            LunarReservoir(debtMinutes: 78, weekAgoMinutes: 104)
            LunarReservoir(debtMinutes: 190, weekAgoMinutes: 150)
            LunarReservoir(debtMinutes: 0, weekAgoMinutes: 20)
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
