import SwiftUI

/// The Body Clock's ORBIT: one 24-hour dial carrying every timing layer
/// Zoon knows about the day, with midnight at the top and the hours running
/// clockwise.
///
/// Layers, inside to out:
/// * **Usual sleep window** -- the wide translucent band. Where this
///   person's sleep tends to sit, from `BodyClock`.
/// * **Last night** -- the thin solid arc. Where sleep actually fell. When
///   the two arcs sit on top of each other the night was aligned; a visible
///   offset *is* the drift, in the direction it happened.
/// * **Energy marks** -- peak, dip and wind-down from `EnergyForecast`, on
///   the rim, so the day's shape reads against the night's.
/// * **Now** -- the small bright dot. Where in the day the reader is.
///
/// The centre answers "how aligned was I?" until a finger lands on the dial,
/// then answers "what is this hour?" -- asleep, in the window, a peak, a
/// dip, or simply awake. Hours are haptic detents, so a slow drag around the
/// ring ticks like a clock being set.
///
/// Draw-in is once per night: the window band sweeps first, the night arc
/// follows. Nothing on the dial rotates or pulses on its own.
struct ZoonBodyClockOrbit: View {
    let bodyClock: BodyClock
    let night: SleepNightFeatures
    let energyMarks: [EnergyForecast.Window]
    /// 0...100 circadian alignment, computed by the caller.
    let alignment: Double

    @State private var progress: Double = 0
    @State private var inspectedFraction: Double?
    @State private var lastDetent: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Geometry of the day

    private var windowStart: Double { Self.wallClockFraction(bodyClock.onsetHour) }
    private var windowEnd: Double { Self.wallClockFraction(bodyClock.wakeHour) }
    private var actualStart: Double { Self.wallClockFraction(Self.hourOfDay(night.bedtime)) }
    private var actualEnd: Double { Self.wallClockFraction(Self.hourOfDay(night.wakeTime)) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, 300)
            let center = CGPoint(x: geo.size.width / 2, y: side / 2)
            let radius = side / 2 - 26

            ZStack {
                dialTicks(center: center, radius: radius + 12)

                // Usual window: the wide band the night is judged against.
                arc(from: windowStart, to: windowEnd, center: center, radius: radius)
                    .trimmedPath(from: 0, to: progress)
                    .stroke(Theme.Family.sleep.opacity(0.28), style: StrokeStyle(lineWidth: 18, lineCap: .round))

                // Last night: thin and solid, on the same radius so an
                // offset between the two is the drift itself.
                arc(from: actualStart, to: actualEnd, center: center, radius: radius)
                    .trimmedPath(from: 0, to: nightProgress)
                    .stroke(Theme.Family.sleep, style: StrokeStyle(lineWidth: 4, lineCap: .round))

                ForEach(energyMarks) { mark in
                    energyMarker(mark, center: center, radius: radius + 14)
                        .opacity(progress >= 0.9 ? 1 : 0)
                }

                nowDot(center: center, radius: radius)
                    .opacity(progress >= 0.9 ? 1 : 0)

                if let inspectedFraction {
                    cursor(fraction: inspectedFraction, center: center, radius: radius)
                }

                centerReadout
                    .frame(width: radius * 1.3)
                    .position(center)
            }
            .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.25)), value: progress >= 0.9)
            .animation(Motion.respecting(reduceMotion, Motion.scrub), value: inspectedFraction == nil)
            .contentShape(Circle().path(in: CGRect(x: center.x - side / 2, y: 0, width: side, height: side)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = Self.dialFraction(for: value.location, center: center)
                        inspectedFraction = fraction
                        let hour = Int(fraction * 24)
                        if hour != lastDetent {
                            if lastDetent != nil { Haptics.scrubDetent() }
                            lastDetent = hour
                        }
                    }
                    .onEnded { _ in
                        inspectedFraction = nil
                        lastDetent = nil
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 300)
        .drawOnce(id: night.nightKey, progress: $progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body clock")
        .accessibilityValue(inspectedFraction.map(hourDescription) ?? summary)
        .accessibilityHint("Swipe up or down to step through the hours of the day.")
        .accessibilityAdjustableAction { direction in
            let current = Int((inspectedFraction ?? Self.wallClockFraction(Self.hourOfDay(.now))) * 24)
            let next = direction == .increment ? (current + 1) % 24 : (current + 23) % 24
            inspectedFraction = Double(next) / 24
        }
    }

    /// The night arc waits for the window band: second half of the draw.
    private var nightProgress: Double {
        min(max((progress - 0.35) / 0.65, 0), 1)
    }

    // MARK: - Dial parts

    /// Twenty-four unlabeled ticks; the four quarter-hours are heavier. A
    /// clock face without numerals -- the arcs are the information, the
    /// ticks only give them a scale.
    private func dialTicks(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(0..<24, id: \.self) { hour in
            let major = hour % 6 == 0
            Rectangle()
                .fill(Theme.neutral(major ? 0.28 : 0.10))
                .frame(width: major ? 2 : 1, height: major ? 10 : 5)
                .offset(y: -radius)
                .rotationEffect(.degrees(Double(hour) / 24 * 360))
                .position(center)
        }
    }

    private func arc(from start: Double, to end: Double, center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let startAngle = Angle(degrees: start * 360 - 90)
        var endAngle = Angle(degrees: end * 360 - 90)
        if endAngle.degrees <= startAngle.degrees { endAngle.degrees += 360 }
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }

    private func energyMarker(_ window: EnergyForecast.Window, center: CGPoint, radius: CGFloat) -> some View {
        let fraction = Self.wallClockFraction(Self.hourOfDay(window.time))
        return Image(systemName: window.kind.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.Family.circadian)
            .frame(width: 18, height: 18)
            .background(Theme.background.opacity(0.92), in: Circle())
            .offset(y: -radius)
            .rotationEffect(.degrees(fraction * 360))
            .position(center)
    }

    private func nowDot(center: CGPoint, radius: CGFloat) -> some View {
        Circle()
            .fill(Theme.dialMarker)
            .frame(width: 8, height: 8)
            .shadow(color: Theme.dialMarker.opacity(0.6), radius: 4)
            .offset(y: -radius)
            .rotationEffect(.degrees(Self.wallClockFraction(Self.hourOfDay(.now)) * 360))
            .position(center)
    }

    /// A hairline from the centre to the rim at the finger's angle.
    private func cursor(fraction: Double, center: CGPoint, radius: CGFloat) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.35))
            .frame(width: 1, height: radius + 20)
            .offset(y: -(radius + 20) / 2)
            .rotationEffect(.degrees(fraction * 360))
            .position(center)
            .allowsHitTesting(false)
    }

    // MARK: - Centre

    @ViewBuilder
    private var centerReadout: some View {
        if let inspectedFraction {
            let hour = inspectedFraction * 24
            VStack(spacing: 3) {
                Text(BodyClock.formatted(hour: hour))
                    .font(Theme.numeral(24))
                    .monospacedDigit()
                Text(stateLabel(atFraction: inspectedFraction))
                    .font(Theme.meaning)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(spacing: 2) {
                Text("Body clock")
                    .font(Theme.kicker)
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(alignmentWord)
                    .font(Theme.meaning)
                    .foregroundStyle(Theme.recoveryColor(alignment))
                Text("\(Int(alignment))")
                    .font(Theme.numeral(34))
                    .monospacedDigit()
            }
        }
    }

    private var alignmentWord: String {
        switch alignment {
        case 85...: "Aligned"
        case 60..<85: "Close"
        default: "Drifted"
        }
    }

    // MARK: - What an hour means

    /// The most specific thing true at this hour. Order matters: last
    /// night's actual sleep beats the usual window, which beats an energy
    /// mark, which beats plain "awake".
    private func stateLabel(atFraction fraction: Double) -> String {
        if Self.contains(fraction, from: actualStart, to: actualEnd) {
            return "Asleep last night"
        }
        if Self.contains(fraction, from: windowStart, to: windowEnd) {
            return "In your usual window"
        }
        if let mark = energyMarks.min(by: { distance(fraction, to: $0) < distance(fraction, to: $1) }),
           distance(fraction, to: mark) <= 0.5 / 24 {
            return mark.kind.label
        }
        return "Awake"
    }

    private func distance(_ fraction: Double, to window: EnergyForecast.Window) -> Double {
        Self.circularDistance(fraction, Self.wallClockFraction(Self.hourOfDay(window.time)))
    }

    private func hourDescription(_ fraction: Double) -> String {
        "\(BodyClock.formatted(hour: fraction * 24)), \(stateLabel(atFraction: fraction).lowercased())."
    }

    private var summary: String {
        "Usual window \(BodyClock.formatted(hour: bodyClock.onsetHour)) to \(BodyClock.formatted(hour: bodyClock.wakeHour)). "
            + "Last night \(BodyClock.formatted(hour: Self.hourOfDay(night.bedtime))) to \(BodyClock.formatted(hour: Self.hourOfDay(night.wakeTime))). "
            + "Alignment \(Int(alignment)) out of 100, \(alignmentWord.lowercased())."
    }

    // MARK: - Clock math

    static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    /// Hours-from-midnight (possibly negative, evening convention) to a
    /// 0...1 fraction of the dial.
    static func wallClockFraction(_ hour: Double) -> Double {
        var h = hour
        while h < 0 { h += 24 }
        while h >= 24 { h -= 24 }
        return h / 24
    }

    static func dialFraction(for location: CGPoint, center: CGPoint) -> Double {
        let dx = location.x - center.x
        let dy = location.y - center.y
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees / 360
    }

    static func circularDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(diff, 1 - diff)
    }

    /// Whether `fraction` lies on the clockwise arc from `start` to `end`,
    /// which may wrap past midnight.
    static func contains(_ fraction: Double, from start: Double, to end: Double) -> Bool {
        if start <= end { return fraction >= start && fraction <= end }
        return fraction >= start || fraction <= end
    }
}

#Preview("Body clock orbit") {
    let night = MockData.goodNight
    let clock = BodyClock.compute(nights: MockData.history) ?? BodyClock(
        midpoint: 3.2, spreadHours: 0.6, nightCount: 21, typicalDurationMinutes: 452
    )
    let forecast = EnergyForecast.compute(
        wakeTime: night.wakeTime, sleepDebtMinutes: 40, windDownHour: clock.onsetHour
    )
    return ZoonBodyClockOrbit(
        bodyClock: clock,
        night: night,
        energyMarks: forecast.windows.filter {
            $0.kind == .morningPeak || $0.kind == .afternoonDip || $0.kind == .windDown
        },
        alignment: 88
    )
    .padding()
    .nightBackground()
    .zoonPreviewEnvironment()
}
