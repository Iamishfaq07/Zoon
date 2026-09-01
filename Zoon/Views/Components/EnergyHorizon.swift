import SwiftUI

/// The HORIZON visual grammar: one wide, scrubbable curve for today's
/// estimated energy, on the page with no card.
///
/// Replaces three Today cards that each drew part of the same idea --
/// `EnergyForecastCard` (the curve), `BodyBatteryCard` (a chart of the same
/// day) and `dailyLoadRow` (one number). Everything here reads existing
/// values: the curve is `EnergyForecast.curveSamples`, the markers are its
/// `windows`, and the "now" readout is `BodyBattery.current` when present.
/// Nothing is re-modelled for the picture.
///
/// Time is the x-axis, from wake to wind-down. Peak, dip and wind-down sit
/// on the curve as labelled points; the sleep window is a soft band at the
/// right edge. Drag to read any hour. The curve draws left → right once per
/// forecast change and never replays on scroll.
struct EnergyHorizon: View {
    let forecast: EnergyForecast
    /// Same-day reserve, for the readout. Optional: the horizon is still
    /// meaningful on a day the battery model had nothing to build from.
    let battery: BodyBattery?
    /// Tonight's target bedtime, for the sleep-window band at the right edge.
    let targetBedtime: Date?

    @State private var progress: Double = 0
    @State private var scrubFraction: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sampled once per view value rather than on every helper call -- the
    /// curve, the markers, the readout and the now-marker all read it.
    private let samples: [(time: Date, level: Double)]

    init(forecast: EnergyForecast, battery: BodyBattery? = nil, targetBedtime: Date? = nil) {
        self.forecast = forecast
        self.battery = battery
        self.targetBedtime = targetBedtime
        self.samples = forecast.curveSamples(count: 64)
    }

    private var span: (start: Date, end: Date)? {
        guard let first = samples.first?.time, let last = samples.last?.time, last > first else { return nil }
        return (first, last)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            readout

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height
                ZStack(alignment: .topLeading) {
                    sleepWindowBand(width: width, height: height)
                    curve(width: width, height: height)
                    markers(width: width, height: height)
                    if let now = nowPosition(width: width, height: height) {
                        nowMarker(at: now, height: height)
                    }
                    if let scrubFraction {
                        ScrubCursor(fraction: scrubFraction)
                    }
                }
            }
            .frame(height: 110)
            .zoonScrubbable(fraction: $scrubFraction, detent: hourDetent)
            .drawOnce(id: forecast, progress: $progress)

            axis
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's energy")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: - Readout

    /// The headline line above the curve. While scrubbing it names the hour
    /// under the finger; at rest it names the next thing on the curve.
    private var readout: some View {
        HStack(alignment: .firstTextBaseline) {
            if let scrubFraction, let time = time(at: scrubFraction) {
                let level = Self.interpolate(time, in: samples)
                VStack(alignment: .leading, spacing: 1) {
                    Text(time, format: .dateTime.hour().minute())
                        .font(Theme.supportingValue)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(Self.describe(level: level))
                        .font(Theme.supportingLabel)
                        .foregroundStyle(.secondary)
                }
            } else if let next = nextWindow {
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.kind.label)
                        .font(Theme.supportingValue)
                    Text(next.time, format: .dateTime.hour().minute())
                        .font(Theme.supportingLabel)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Winding down")
                        .font(Theme.supportingValue)
                    Text("Today's curve is behind you")
                        .font(Theme.supportingLabel)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let battery {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(battery.current)")
                        .font(Theme.supportingValue)
                        .monospacedDigit()
                        .foregroundStyle(Theme.batteryColor(Double(battery.current)))
                    Text("Reserve")
                        .font(Theme.supportingLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(Motion.respecting(reduceMotion, Motion.scrub), value: scrubFraction == nil)
    }

    private var nextWindow: EnergyForecast.Window? {
        forecast.windows.first { $0.time > .now }
    }

    // MARK: - Drawing

    private func point(for sample: (time: Date, level: Double), width: CGFloat, height: CGFloat) -> CGPoint {
        guard let span else { return .zero }
        let x = width * CGFloat(sample.time.timeIntervalSince(span.start) / span.end.timeIntervalSince(span.start))
        // Leave headroom for marker labels above the peak.
        let y = height * (1 - CGFloat(sample.level)) * 0.82 + height * 0.12
        return CGPoint(x: x, y: y)
    }

    private func curvePath(width: CGFloat, height: CGFloat) -> Path {
        Path { path in
            let points = samples.map { point(for: $0, width: width, height: height) }
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func curve(width: CGFloat, height: CGFloat) -> some View {
        let path = curvePath(width: width, height: height)
        return ZStack {
            // Fill under the curve, faded, so the shape reads as a landscape.
            Path { p in
                p.addPath(path)
                let points = samples.map { point(for: $0, width: width, height: height) }
                if let last = points.last, let first = points.first {
                    p.addLine(to: CGPoint(x: last.x, y: height))
                    p.addLine(to: CGPoint(x: first.x, y: height))
                    p.closeSubpath()
                }
            }
            .fill(
                LinearGradient(
                    colors: [Theme.Metric.strain.opacity(0.14), Theme.Family.circadian.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask(alignment: .leading) {
                Rectangle().frame(width: width * progress)
            }

            path
                .trimmedPath(from: 0, to: progress)
                .stroke(Theme.Family.energy, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }

    private func markers(width: CGFloat, height: CGFloat) -> some View {
        ForEach(forecast.windows.filter { $0.kind != .morningRise && $0.kind != .eveningRise }) { window in
            // Read the marker's height off the sampled curve rather than
            // re-declaring the anchor levels here: the curve already passes
            // through every anchor, and one source of truth means the dot
            // can't drift off the line if the model's levels ever change.
            let level = Self.interpolate(window.time, in: samples)
            let p = point(for: (window.time, level), width: width, height: height)
            VStack(spacing: 3) {
                Text(window.kind.label)
                    .font(Theme.text(9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(window.time, format: .dateTime.hour().minute())
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Circle()
                    .fill(tint(for: window.kind))
                    .frame(width: 6, height: 6)
            }
            .fixedSize()
            .position(x: min(max(p.x, 28), width - 28), y: p.y - 22)
            .opacity(progress >= fraction(of: window.time) ? 1 : 0)
            .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.2)), value: progress)
        }
    }

    private func sleepWindowBand(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let targetBedtime, let span, targetBedtime > span.start {
                let startX = width * CGFloat(min(1, targetBedtime.timeIntervalSince(span.start) / span.end.timeIntervalSince(span.start)))
                Rectangle()
                    .fill(Theme.Family.sleep.opacity(0.10))
                    .frame(width: max(0, width - startX), height: height)
                    .offset(x: startX)
            }
        }
    }

    private func nowMarker(at p: CGPoint, height: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Theme.neutral(0.14))
                .frame(width: 1, height: height)
                .position(x: p.x, y: height / 2)
            Circle()
                .fill(Theme.dialMarker)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Theme.Family.energy, lineWidth: 2))
                .position(p)
        }
        .opacity(progress >= 0.95 ? 1 : 0)
        .animation(Motion.respecting(reduceMotion, .easeOut(duration: 0.25)), value: progress)
    }

    private var axis: some View {
        HStack {
            if let span {
                Text(span.start, format: .dateTime.hour())
                Spacer()
                Text("Now")
                    .opacity(nowPosition(width: 1, height: 1) == nil ? 0 : 1)
                Spacer()
                Text(span.end, format: .dateTime.hour())
            }
        }
        .font(Theme.text(10))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }

    // MARK: - Mapping

    private func fraction(of time: Date) -> Double {
        guard let span else { return 0 }
        return min(1, max(0, time.timeIntervalSince(span.start) / span.end.timeIntervalSince(span.start)))
    }

    private func time(at fraction: CGFloat) -> Date? {
        guard let span else { return nil }
        return span.start.addingTimeInterval(span.end.timeIntervalSince(span.start) * Double(fraction))
    }

    /// One haptic per hour crossed while scrubbing.
    private func hourDetent(_ fraction: CGFloat) -> Int? {
        guard let time = time(at: fraction) else { return nil }
        return Calendar.current.component(.hour, from: time)
    }

    private func nowPosition(width: CGFloat, height: CGFloat) -> CGPoint? {
        guard let span else { return nil }
        let now = Date.now
        guard now >= span.start, now <= span.end else { return nil }
        return point(for: (now, Self.interpolate(now, in: samples)), width: width, height: height)
    }

    private static func interpolate(_ time: Date, in samples: [(time: Date, level: Double)]) -> Double {
        guard let upperIndex = samples.firstIndex(where: { $0.time >= time }), upperIndex > 0 else {
            return samples.first(where: { $0.time >= time })?.level ?? samples.last?.level ?? 0
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let span = upper.time.timeIntervalSince(lower.time)
        guard span > 0 else { return lower.level }
        let fraction = time.timeIntervalSince(lower.time) / span
        return lower.level + (upper.level - lower.level) * fraction
    }

    /// Plain words for a 0...1 alertness level. A heuristic estimate gets a
    /// heuristic label, never a percentage that implies measurement.
    private static func describe(level: Double) -> String {
        switch level {
        case ..<0.3: "Low energy, good for rest"
        case ..<0.55: "Easing off"
        case ..<0.8: "Steady"
        default: "Near your peak"
        }
    }

    private func tint(for kind: EnergyForecast.Window.Kind) -> Color {
        switch kind {
        case .morningRise, .eveningRise: Theme.Metric.strain
        case .morningPeak: Theme.Family.recovery
        case .afternoonDip: Theme.Family.attention
        case .windDown: Theme.Family.sleep
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        for window in forecast.windows where window.kind != .morningRise && window.kind != .eveningRise {
            parts.append("\(window.kind.label) around \(window.time.formatted(.dateTime.hour().minute()))")
        }
        if let battery {
            parts.append("Energy reserve \(battery.current) of 100")
        }
        if forecast.isGenericWindDown {
            parts.append("Wind-down is a general estimate until Zoon knows your body clock")
        }
        return parts.joined(separator: ". ")
    }
}

#Preview("Energy Horizon") {
    let wake = Calendar.current.date(bySettingHour: 6, minute: 50, second: 0, of: .now) ?? .now
    return ScrollView {
        VStack(spacing: 32) {
            EnergyHorizon(
                forecast: EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 45, windDownHour: -0.75),
                battery: AppMockData.dayContext().bodyBattery,
                targetBedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: .now)
            )
            EnergyHorizon(
                forecast: EnergyForecast.compute(wakeTime: wake, sleepDebtMinutes: 0, windDownHour: nil),
                battery: nil,
                targetBedtime: nil
            )
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
