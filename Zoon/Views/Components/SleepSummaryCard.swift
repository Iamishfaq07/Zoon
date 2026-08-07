import SwiftUI

/// The hero card: last night's duration, score, and the headline metrics.
struct SleepSummaryCard: View {

    let features: SleepNightFeatures
    let score: SleepScore
    let goalMinutes: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(features.formattedTimeAsleep)
                    // Rounded design and a monospaced-digit width so the number
                    // doesn't jitter as it updates.
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                ScoreRing(score: score)
            }

            goalProgress

            Divider()

            metrics
        }
        .zoonCard()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last Night")
                    .font(.headline)
                Text(features.date, format: .dateTime.weekday(.wide).month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if features.isMock { MockDataBadge() }
        }
    }

    @ViewBuilder
    private var goalProgress: some View {
        let progress = min(features.timeAsleepMinutes / max(goalMinutes, 1), 1)
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: progress)
                .tint(ZoonStyle.scoreColor(score.band))
            Text(goalCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var goalCaption: String {
        let delta = features.timeAsleepMinutes - goalMinutes
        if delta >= 0 {
            return "Goal met — \(SleepNightFeatures.formatMinutes(delta)) over your \(SleepNightFeatures.formatMinutes(goalMinutes)) target"
        }
        return "\(SleepNightFeatures.formatMinutes(-delta)) short of your \(SleepNightFeatures.formatMinutes(goalMinutes)) goal"
    }

    private var metrics: some View {
        // Adaptive grid rather than an HStack: with large Dynamic Type sizes
        // three metrics in a row overflow, and this reflows instead of clipping.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 12, alignment: .leading)],
            alignment: .leading,
            spacing: 12
        ) {
            MetricChip(
                symbol: "gauge.medium",
                value: "\(Int(features.sleepEfficiencyPercent))%",
                label: "Efficiency"
            )
            if let hrv = features.avgHRV {
                MetricChip(
                    symbol: "waveform.path.ecg",
                    value: "\(Int(hrv)) ms",
                    label: "HRV",
                    trend: hrvTrend
                )
            }
            if let minHR = features.minHeartRate {
                MetricChip(symbol: "heart.fill", value: "\(Int(minHR))", label: "Low HR")
            }
            if let latency = features.sleepLatencyMinutes {
                MetricChip(symbol: "hourglass", value: "\(Int(latency)) min", label: "To sleep")
            }
            if features.wakeCount > 0 {
                MetricChip(symbol: "eye", value: "\(features.wakeCount)", label: "Wake-ups")
            }
        }
    }

    /// Compares tonight's HRV to the 7-day average. Returns nil when there isn't
    /// enough history — an arrow with nothing behind it is worse than no arrow.
    private var hrvTrend: MetricChip.Trend? {
        guard let hrv = features.avgHRV, let base = features.hrv7DayAvg, base > 0 else { return nil }
        let change = (hrv - base) / base
        if change > 0.08 { return .up }
        if change < -0.08 { return .down }
        return .flat
    }
}

/// Circular score indicator.
struct ScoreRing: View {
    let score: SleepScore

    var body: some View {
        ZStack {
            Circle()
                .stroke(ZoonStyle.scoreColor(score.band).opacity(0.2), lineWidth: 7)
            Circle()
                .trim(from: 0, to: CGFloat(score.value) / 100)
                .stroke(
                    ZoonStyle.scoreColor(score.band),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                Text("\(score.value)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(score.band.label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 66, height: 66)
        .animation(.snappy, value: score.value)
        // One label for the whole ring — VoiceOver reading "72" then "Good" as
        // two unrelated elements is meaningless.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep score")
        .accessibilityValue("\(score.value) out of 100, \(score.band.label)")
    }
}

/// One small labelled metric.
struct MetricChip: View {

    enum Trend {
        case up, down, flat

        var symbol: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .flat: "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: .green
            case .down: .orange
            case .flat: .secondary
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .up: "above your average"
            case .down: "below your average"
            case .flat: "in line with your average"
            }
        }
    }

    let symbol: String
    let value: String
    let label: String
    var trend: Trend?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let trend {
                    Image(systemName: trend.symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(trend.color)
                }
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(trend.map { "\(value), \($0.accessibilityDescription)" } ?? value)
    }
}

#Preview("Good night") {
    ScrollView {
        SleepSummaryCard(
            features: MockData.goodNight,
            score: SleepScore.compute(for: MockData.goodNight, goalMinutes: 480),
            goalMinutes: 480
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Poor night") {
    ScrollView {
        SleepSummaryCard(
            features: MockData.poorNight,
            score: SleepScore.compute(for: MockData.poorNight, goalMinutes: 480),
            goalMinutes: 480
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("No staging") {
    ScrollView {
        SleepSummaryCard(
            features: MockData.unstagedNight,
            score: SleepScore.compute(for: MockData.unstagedNight, goalMinutes: 480),
            goalMinutes: 480
        )
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
