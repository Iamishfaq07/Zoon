import SwiftUI

/// Seven nights as moons filled by asleep vs need. Tap opens that night.
struct WeekMoonStrip: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double
    @Binding var selected: SleepNightFeatures?

    private var week: [SleepNightFeatures] {
        Array(nights.suffix(7))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week) { night in
                let fill = min(1, night.timeAsleepMinutes / max(goalMinutes, 1))
                let on = selected?.id == night.id
                Button {
                    Haptics.select()
                    selected = night
                } label: {
                    VStack(spacing: 6) {
                        MoonFill(fill: fill, active: on, size: 34)
                        Text(night.date, format: .dateTime.weekday(.narrow))
                            .font(Theme.text(11, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: night, fill: fill))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func accessibilityLabel(for night: SleepNightFeatures, fill: Double) -> String {
        let day = night.date.formatted(.dateTime.weekday(.wide))
        let percent = Int((fill * 100).rounded())
        return "\(day), \(night.formattedTimeAsleep) asleep, \(percent) percent of need"
    }
}

struct NightFilmStrip: View {
    let nights: [SleepNightFeatures]
    let goalMinutes: Double

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(nights) { night in
                    let fill = min(1, night.timeAsleepMinutes / max(goalMinutes, 1))
                    let met = night.timeAsleepMinutes >= goalMinutes
                    NavigationLink {
                        PastNightDetailView(night: night)
                    } label: {
                        VStack(alignment: .center, spacing: 8) {
                            MoonWell(fill: fill, metNeed: met)
                            Text(night.date, format: .dateTime.weekday(.abbreviated).day())
                                .font(Theme.text(11))
                                .foregroundStyle(.secondary)
                            Text(night.formattedTimeAsleep)
                                .font(Theme.label(13, weight: .semibold))
                                .monospacedDigit()
                        }
                        .frame(width: 88)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// Circular night sky holding a phase moon — the past-night icon.
struct MoonWell: View {
    var fill: Double
    var metNeed: Bool
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Theme.Family.sleep.opacity(metNeed ? 0.42 : 0.22),
                            Theme.Family.Moon.dark
                        ],
                        center: UnitPoint(x: 0.5, y: 0.42),
                        startRadius: 0,
                        endRadius: size * 0.52
                    )
                )
            MoonStars()
            MoonFill(fill: fill, active: metNeed, size: size * 0.72)
        }
        .frame(width: size, height: size)
        .overlay {
            Circle().stroke(metNeed ? Theme.Family.sleep.opacity(0.5) : Theme.cardStroke, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct MoonStars: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(.white.opacity(0.55)).frame(width: 2.2, height: 2.2)
                    .offset(x: s * -0.34, y: s * -0.30)
                Circle().fill(.white.opacity(0.4)).frame(width: 1.6, height: 1.6)
                    .offset(x: s * 0.34, y: s * -0.34)
                Circle().fill(.white.opacity(0.5)).frame(width: 2, height: 2)
                    .offset(x: s * 0.38, y: s * 0.24)
                Circle().fill(.white.opacity(0.35)).frame(width: 1.4, height: 1.4)
                    .offset(x: s * -0.38, y: s * 0.28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Waxing moon whose illumination is asleep ÷ need.
struct MoonFill: View {
    var fill: Double
    var active: Bool
    var size: CGFloat = 28

    var body: some View {
        Canvas { context, canvasSize in
            drawMoon(in: &context, canvasSize: canvasSize, fill: fill, active: active)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private func drawMoon(
    in context: inout GraphicsContext,
    canvasSize: CGSize,
    fill: Double,
    active: Bool
) {
    let t = min(1, max(0, fill))
    let s = min(canvasSize.width, canvasSize.height)
    let scale = s / 200
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    let moonR = 58 * scale

    let glowR = 78 * scale
    let glow = Path(ellipseIn: CGRect(
        x: center.x - glowR, y: center.y - glowR, width: glowR * 2, height: glowR * 2
    ))
    context.fill(glow, with: .color(Theme.Family.sleep.opacity(active ? 0.28 : 0.12)))

    let discRect = CGRect(x: center.x - moonR, y: center.y - moonR, width: moonR * 2, height: moonR * 2)
    context.fill(Path(ellipseIn: discRect), with: .color(Theme.Family.Moon.body.opacity(0.32)))

    var crescent = Path()
    crescent.addEllipse(in: discRect)
    if t < 0.96 {
        let biteR = 54 * scale
        let biteCenter = CGPoint(x: center.x - t * 128 * scale, y: center.y - 4 * scale)
        crescent.addEllipse(in: CGRect(
            x: biteCenter.x - biteR,
            y: biteCenter.y - biteR,
            width: biteR * 2,
            height: biteR * 2
        ))
    }
    context.fill(crescent, with: .color(Theme.Family.Moon.lit), style: FillStyle(eoFill: true))
}
