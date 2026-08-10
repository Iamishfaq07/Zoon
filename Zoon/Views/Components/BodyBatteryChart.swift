import SwiftUI
import Charts

/// The day's energy curve.
///
/// The gradient under the line is coloured by *level* rather than by a single
/// hue, so the shape tells you the story on its own: a curve that starts green
/// and ends orange is a day that cost more than it had.
struct BodyBatteryChart: View {

    let battery: BodyBattery
    var height: CGFloat = 150

    @State private var selectedDate: Date?

    var body: some View {
        if battery.points.count < 2 {
            emptyState
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            ForEach(battery.points) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Level", point.level)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    .linearGradient(
                        colors: [
                            Theme.batteryColor(Double(battery.morningPeak)).opacity(0.55),
                            Theme.batteryColor(Double(battery.current)).opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Level", point.level)
                )
                // Monotone rather than catmullRom: cubic interpolation happily
                // overshoots past 100 or below 0 between points, which on a
                // *battery* looks like a bug rather than a curve.
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundStyle(
                    .linearGradient(
                        colors: [Theme.Metric.battery, Theme.batteryColor(Double(battery.current))],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
            }

            if let last = battery.points.last {
                PointMark(
                    x: .value("Time", last.date),
                    y: .value("Level", last.level)
                )
                .foregroundStyle(Theme.batteryColor(Double(battery.current)))
                .symbolSize(90)
            }

            if let selectedDate, let point = nearestPoint(to: selectedDate) {
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(.white.opacity(0.25))
                    .annotation(
                        position: .top,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ChartSelectionBadge(
                            title: point.date.formatted(.dateTime.hour().minute()),
                            lines: [("Level", "\(Int(point.level.rounded()))", Theme.batteryColor(point.level))]
                        )
                    }
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let level = value.as(Double.self) {
                        Text("\(Int(level))")
                            .font(Theme.text(9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.05))
                AxisValueLabel(format: .dateTime.hour())
                    .font(Theme.text(9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: height)
        .chartXSelection(value: $selectedDate)
    }

    /// Points are timestamped continuously through the day, not bucketed —
    /// `chartXSelection` lands on whatever instant is under the finger, so
    /// this needs closest-by-time rather than the same-day match the
    /// once-per-night charts use.
    private func nearestPoint(to date: Date) -> BodyBattery.Point? {
        battery.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.slash")
                .foregroundStyle(.secondary)
            Text("Not enough heart-rate data yet today")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

/// Small line for trend cards — no axes, no labels, just shape.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = .white
    var height: CGFloat = 34
    var filled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)

            ZStack {
                if filled, points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }

                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                if let last = points.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 5, height: 5)
                        .position(last)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        // A flat series would divide by zero; draw it down the middle instead.
        let range = maximum - minimum
        let step = size.width / CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            let normalized = range > 0 ? (value - minimum) / range : 0.5
            return CGPoint(
                x: CGFloat(index) * step,
                // Inset vertically so the stroke and end dot aren't clipped.
                y: size.height - (normalized * (size.height - 6)) - 3
            )
        }
    }
}

#Preview("Battery & sparkline") {
    ScrollView {
        VStack(spacing: 20) {
            BodyBatteryChart(battery: AppMockData.dayContext().bodyBattery)
                .glassCard()

            Sparkline(values: MockData.history.compactMap(\.avgHRV), tint: Theme.Metric.hrv)
                .glassCard()

            Sparkline(
                values: MockData.history.map(\.timeAsleepMinutes),
                tint: Theme.Metric.sleep,
                height: 50
            )
            .glassCard()
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
