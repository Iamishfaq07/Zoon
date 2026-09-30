import SwiftUI
import Charts

extension SnoreLoudness {
    var tint: Color {
        switch self {
        case .quiet: Theme.Metric.sleep
        case .moderate: Theme.Metric.recoveryMid
        case .loud: Theme.Metric.recoveryLow
        }
    }
}

/// Snore Check's mark: the app's crescent with sound rolling off it.
///
/// The waves travel outward while `active`, and breathe slowly otherwise.
/// Still under Reduce Motion.
struct SnoreEmblem: View {
    var size: CGFloat = 120
    var active = false
    var tint: Color = Theme.Metric.sleep

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvas in
                draw(in: &ctx, size: canvas, time: t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(in ctx: inout GraphicsContext, size canvas: CGSize, time t: Double) {
        let s = min(canvas.width, canvas.height)
        let moonCenter = CGPoint(x: canvas.width * 0.36, y: canvas.height * 0.5)
        let r = s * 0.24

        // glow
        let glow = Path(ellipseIn: CGRect(x: moonCenter.x - r * 2, y: moonCenter.y - r * 2, width: r * 4, height: r * 4))
        ctx.fill(glow, with: .radialGradient(
            Gradient(colors: [tint.opacity(0.35), tint.opacity(0)]),
            center: moonCenter, startRadius: 0, endRadius: r * 2
        ))

        // sound waves, to the right of the moon
        for i in 0..<3 {
            let base = r * (1.45 + Double(i) * 0.42)
            let phase = active ? (t * 1.4 - Double(i) * 0.55) : (t * 0.6 - Double(i) * 0.9)
            let travel = active ? (phase.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) : 0
            let radius = base + (active ? travel * r * 0.35 : 0)
            let opacity = active ? 0.85 * (1 - travel * 0.7) : 0.35 + 0.35 * (0.5 + 0.5 * sin(phase * 2 * .pi))
            var arc = Path()
            arc.addArc(center: moonCenter, radius: radius, startAngle: .degrees(-38), endAngle: .degrees(38), clockwise: false)
            ctx.stroke(arc, with: .color(tint.opacity(opacity)), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
        }

        // the crescent: a disc with a second disc taken out of it
        ctx.drawLayer { layer in
            let disc = Path(ellipseIn: CGRect(x: moonCenter.x - r, y: moonCenter.y - r, width: r * 2, height: r * 2))
            layer.fill(disc, with: .linearGradient(
                Gradient(colors: [Theme.Family.Moon.lit, Theme.Family.Moon.body]),
                startPoint: CGPoint(x: moonCenter.x, y: moonCenter.y - r),
                endPoint: CGPoint(x: moonCenter.x, y: moonCenter.y + r)
            ))
            layer.blendMode = .destinationOut
            let bite = CGRect(x: moonCenter.x - r * 0.62, y: moonCenter.y - r * 1.12, width: r * 1.84, height: r * 1.84)
            layer.fill(Path(ellipseIn: bite), with: .color(.black))
        }
    }
}

/// The live listening dial: the room's level against its own quiet, a ring
/// that turns amber inside a snoring episode, and ripples on each
/// snore-shaped sound.
struct SnoreLiveMeter: View {
    /// dB above the room's quiet level.
    let levelDB: Double
    let snoring: Bool
    /// A snore-shaped sound was heard in the last second or so.
    let pulse: Bool
    let arriving: Bool
    let elapsed: String
    let status: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        if !arriving { return Theme.inkTertiary }
        return snoring ? Theme.Metric.recoveryMid : Theme.Metric.sleep
    }

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, canvas in
                    draw(in: &ctx, size: canvas, time: t)
                }
            }
            VStack(spacing: 4) {
                Text(elapsed)
                    .font(Theme.numeral(40))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(status)
                    .font(Theme.label(14, weight: .semibold))
                    .foregroundStyle(snoring ? Theme.Metric.recoveryMid : Theme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .frame(width: 250, height: 250)
        .accessibilityElement(children: .combine)
    }

    private func draw(in ctx: inout GraphicsContext, size canvas: CGSize, time t: Double) {
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let big = min(canvas.width, canvas.height) / 2 - 8
        let level = min(1, max(0, levelDB / 30))

        // ripples while snoring or on a snore-shaped sound
        if snoring || pulse {
            for k in 0..<3 {
                let p = ((t * 0.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                let radius = big * (0.62 + 0.38 * p)
                let ring = Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                ctx.stroke(ring, with: .color(tint.opacity(0.35 * (1 - p))), lineWidth: 2)
            }
        }

        // track
        let track = Path(ellipseIn: CGRect(x: c.x - big, y: c.y - big, width: big * 2, height: big * 2).insetBy(dx: 6, dy: 6))
        ctx.stroke(track, with: .color(Theme.neutral(0.12)), lineWidth: 10)

        // level arc, from the top, clockwise
        if level > 0.01 {
            var arc = Path()
            arc.addArc(center: c, radius: big - 6, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * level), clockwise: false)
            ctx.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        }

        // soft body that swells with the sound
        let swell = big * (0.55 + 0.12 * level + (pulse && !reduceMotion ? 0.03 * sin(t * 12) : 0))
        let disc = Path(ellipseIn: CGRect(x: c.x - swell, y: c.y - swell, width: swell * 2, height: swell * 2))
        ctx.fill(disc, with: .radialGradient(
            Gradient(colors: [tint.opacity(0.28), tint.opacity(0.04)]),
            center: c, startRadius: 0, endRadius: swell
        ))
    }
}

/// The night as one bar: every snoring episode where it happened, coloured
/// by how loud it ran, with the session's start, middle and end beneath.
struct SnoreNightTimeline: View {
    let report: SnoreNightReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.neutral(0.10))
                    ForEach(Array(report.episodes.enumerated()), id: \.offset) { _, episode in
                        let x = report.position(of: episode.start) * width
                        let w = max(3, (report.position(of: episode.end) - report.position(of: episode.start)) * width)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill((episode.loudness?.tint ?? Theme.Metric.sleep).gradient)
                            .frame(width: w)
                            .offset(x: min(x, width - w))
                    }
                }
            }
            .frame(height: 30)
            if let span = report.span {
                HStack {
                    Text(span.start, format: .dateTime.hour().minute())
                    Spacer()
                    Text(span.start.addingTimeInterval(span.duration / 2), format: .dateTime.hour().minute())
                    Spacer()
                    Text(span.end, format: .dateTime.hour().minute())
                }
                .font(Theme.text(11))
                .foregroundStyle(Theme.inkTertiary)
                .monospacedDigit()
            }
            let levels = Set(report.episodes.compactMap(\.loudness)).sorted()
            if !levels.isEmpty {
                HStack(spacing: 14) {
                    ForEach(levels, id: \.self) { level in
                        HStack(spacing: 5) {
                            Circle().fill(level.tint).frame(width: 8, height: 8)
                            Text(level.label)
                                .font(Theme.text(11))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard !report.episodes.isEmpty else { return "No snoring episodes on the night timeline." }
        let times = report.episodes.prefix(6).map {
            "\($0.start.formatted(date: .omitted, time: .shortened)) for \(max(1, Int(($0.duration / 60).rounded()))) minutes"
        }
        return "\(report.episodeCount) snoring episodes: " + times.joined(separator: ", ")
    }
}

/// Snoring minutes night by night, with the average as a dashed line.
struct SnoreHistoryChart: View {
    struct Night: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    let nights: [Night]

    private var average: Double? {
        guard !nights.isEmpty else { return nil }
        return nights.reduce(0) { $0 + $1.minutes } / Double(nights.count)
    }

    var body: some View {
        Chart {
            ForEach(nights) { night in
                BarMark(
                    x: .value("Night", night.date, unit: .day),
                    y: .value("Snoring", night.minutes)
                )
                .foregroundStyle(Theme.Metric.sleep.gradient)
                .cornerRadius(4)
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.neutral(0.08))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes))m").font(Theme.text(10))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, nights.count / 5))) { _ in
                AxisValueLabel(format: .dateTime.day().month(.narrow), centered: true)
                    .font(Theme.text(10))
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Snoring minutes over the last \(nights.count) nights")
    }
}
