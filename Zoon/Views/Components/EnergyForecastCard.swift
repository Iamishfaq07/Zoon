import SwiftUI

/// Today's estimated energy curve — RISE's daily schedule, in one row.
struct EnergyForecastCard: View {
    let forecast: EnergyForecast

    @State private var showingInfo = false
    /// Drag position as a 0...1 fraction across the curve's width -- same
    /// touch-to-time convention `HypnogramView` uses for its own scrubber.
    @State private var selectedFraction: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SectionHeader(
                    title: "Today's Energy",
                    subtitle: "Estimated from your wake time" + (forecast.isGenericWindDown ? "" : " and body clock"),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                Spacer(minLength: 8)
                MetricInfoButton(
                    title: "Today's Energy",
                    symbol: "chart.line.uptrend.xyaxis",
                    tint: Theme.Metric.battery,
                    explanation: [
                        "A heuristic estimate, not a measurement -- nothing on a wrist measures circadian phase directly. This models the well-documented shape most people's alertness follows through a day: rising after sleep inertia clears, peaking mid-morning, dipping mid-afternoon, a second rise in the evening, then winding down.",
                        "Anchored to when you actually woke up today, nudged by how much sleep debt you're carrying. Treat it as a rough guide to when focus and rest might come easiest, not a schedule to follow exactly."
                    ]
                )
            }

            horizon

            HStack(spacing: 0) {
                ForEach(forecast.windows) { window in
                    VStack(spacing: 4) {
                        Image(systemName: window.kind.symbol)
                            .font(Theme.text(15))
                            .foregroundStyle(tint(for: window.kind))
                        Text(window.time, format: .dateTime.hour().minute())
                            .font(Theme.label(11, weight: .semibold))
                            .monospacedDigit()
                        Text(window.kind.label)
                            .font(Theme.text(8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .glassCard()
    }

    /// The curve itself -- discrete icon columns previously stood in for the
    /// whole idea of "today's energy," with no line connecting them. This is
    /// the actual horizon graphic the spec asks for: a continuous shape from
    /// wake to wind-down, with a marker for where "now" sits on it.
    ///
    /// Also carries a drag-to-inspect scrubber, matching `HypnogramView`'s
    /// own gesture -- the redesign audit found the curve shipped without one,
    /// leaving "what's my energy at 3pm" answerable only by eyeballing the
    /// line against the axis.
    private var horizon: some View {
        let samples = forecast.curveSamples(count: 40)

        return GeometryReader { geo in
            let points = samples.map { sample -> CGPoint in
                let first = samples.first?.time ?? sample.time
                let last = samples.last?.time ?? sample.time
                let span = max(last.timeIntervalSince(first), 1)
                let x = geo.size.width * CGFloat(sample.time.timeIntervalSince(first) / span)
                let y = geo.size.height * (1 - CGFloat(sample.level))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geo.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Theme.Metric.battery.opacity(0.3), Theme.Metric.battery.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(Theme.Metric.battery, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                if selectedFraction == nil, let now = nowPosition(samples: samples, width: geo.size.width, height: geo.size.height) {
                    Circle()
                        .fill(Theme.Metric.battery)
                        .frame(width: 6, height: 6)
                        .position(now)
                }

                if let selectedFraction {
                    let x = geo.size.width * selectedFraction
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    // Theme.neutral rather than white: every sibling chart
                    // draws this same drag indicator with Theme.neutral(0.25)
                    // (SleepNeedView, BreathingHealthView, MetricTrendView),
                    // and a hardcoded white line is the one value here that
                    // does not adapt -- on the Light theme it is white on a
                    // light card.
                    .stroke(Theme.neutral(0.25), lineWidth: 1)

                    if let time = time(atFraction: selectedFraction, samples: samples) {
                        let level = Self.interpolate(time, in: samples)
                        ChartSelectionBadge(
                            title: time.formatted(.dateTime.hour().minute()),
                            lines: [("Energy", "\(Int((level * 100).rounded()))%", Theme.Metric.battery)]
                        )
                        .offset(x: min(max(0, x - 60), geo.size.width - 120), y: -6)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectedFraction = min(1, max(0, value.location.x / geo.size.width))
                    }
                    .onEnded { _ in selectedFraction = nil }
            )
        }
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    /// The wall-clock time a drag fraction corresponds to, in the same
    /// span `nowPosition`/`interpolate` already use.
    private func time(atFraction fraction: CGFloat, samples: [(time: Date, level: Double)]) -> Date? {
        guard let first = samples.first?.time, let last = samples.last?.time, last > first else { return nil }
        return first.addingTimeInterval(last.timeIntervalSince(first) * Double(fraction))
    }

    /// Where "now" falls along the curve, in the same coordinate space as
    /// `horizon`'s points -- `nil` outside the forecast's own span (before
    /// wake or well after wind-down), so the marker doesn't appear stuck at
    /// an edge when it isn't actually where "now" is.
    private func nowPosition(samples: [(time: Date, level: Double)], width: CGFloat, height: CGFloat) -> CGPoint? {
        guard let first = samples.first?.time, let last = samples.last?.time, last > first else { return nil }
        let now = Date.now
        guard now >= first, now <= last else { return nil }

        let span = last.timeIntervalSince(first)
        let x = width * CGFloat(now.timeIntervalSince(first) / span)
        let level = Self.interpolate(now, in: samples)
        return CGPoint(x: x, y: height * (1 - CGFloat(level)))
    }

    private static func interpolate(_ time: Date, in samples: [(time: Date, level: Double)]) -> Double {
        guard let upperIndex = samples.firstIndex(where: { $0.time >= time }), upperIndex > 0 else {
            return samples.last?.level ?? 0
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let span = upper.time.timeIntervalSince(lower.time)
        guard span > 0 else { return lower.level }
        let fraction = time.timeIntervalSince(lower.time) / span
        return lower.level + (upper.level - lower.level) * fraction
    }

    private func tint(for kind: EnergyForecast.Window.Kind) -> Color {
        switch kind {
        case .morningRise, .eveningRise: Theme.Metric.battery
        case .morningPeak: Theme.Metric.recoveryHigh
        case .afternoonDip: Theme.Metric.recoveryMid
        case .windDown: Theme.Metric.sleep
        }
    }
}

#Preview("Energy Forecast") {
    ScrollView {
        EnergyForecastCard(forecast: EnergyForecast.compute(
            wakeTime: .now.addingTimeInterval(-3 * 3600),
            sleepDebtMinutes: 45,
            windDownHour: -0.75
        ))
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
