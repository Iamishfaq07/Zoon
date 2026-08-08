import SwiftUI

/// The night's shape: stage against time.
///
/// The most recognisable graphic in any sleep app, and the one that carries the
/// most information per pixel — you can see sleep onset, how quickly you dropped
/// into deep, whether the first half was disturbed, and how REM clustered toward
/// morning, all without reading a number.
///
/// Drawn with `Canvas` rather than Swift Charts. Charts is excellent at
/// data-driven marks but a hypnogram is really a hand-drawn diagram: variable
/// row heights, connective risers between stages, and rounded caps on every
/// block. Expressing that in Charts fights the framework; in Canvas it's forty
/// lines and it's exactly right.
struct HypnogramView: View {

    let segments: [StageSegment]
    var height: CGFloat = 150
    var showsAxis: Bool = true

    /// Stage rows, top to bottom. Awake at the top so the trace descends into
    /// deep sleep — the convention people already know how to read.
    private let rows = SleepStage.hypnogramOrder

    private var span: DateInterval? { segments.span }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                rowLabels
                chart
            }
            if showsAxis { axis }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages through the night")
        .accessibilityValue(accessibilitySummary)
    }

    private var rowLabels: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { stage in
                Text(stage.displayName)
                    .font(Theme.label(9, weight: .medium))
                    .foregroundStyle(Theme.Stage.color(for: stage))
                    .frame(height: height / CGFloat(rows.count), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: 34)
    }

    private var chart: some View {
        Canvas { context, size in
            guard let span, span.duration > 0 else { return }

            let rowHeight = size.height / CGFloat(rows.count)
            // Blocks are inset within their row so adjacent stages read as
            // separate bars rather than one continuous slab.
            let blockHeight = rowHeight * 0.62
            let total = span.duration

            func rect(for segment: StageSegment) -> CGRect? {
                guard let rowIndex = rows.firstIndex(of: normalized(segment.stage)) else { return nil }
                let x = (segment.start.timeIntervalSince(span.start) / total) * size.width
                let width = max(1.5, (segment.duration / total) * size.width)
                let y = CGFloat(rowIndex) * rowHeight + (rowHeight - blockHeight) / 2
                return CGRect(x: x, y: y, width: width, height: blockHeight)
            }

            let ordered = segments.sorted { $0.start < $1.start }

            // Risers first, behind the blocks: thin vertical connectors between
            // consecutive stages so the eye follows one continuous trace instead
            // of reading disconnected bars.
            for (previous, next) in zip(ordered, ordered.dropFirst()) {
                guard let from = rect(for: previous), let to = rect(for: next) else { continue }
                let x = from.maxX
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: from.midY))
                    p.addLine(to: CGPoint(x: x, y: to.midY))
                }
                context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
            }

            for segment in ordered {
                guard let frame = rect(for: segment) else { continue }
                let color = Theme.Stage.color(for: normalized(segment.stage))
                let shape = Path(roundedRect: frame, cornerRadius: min(4, frame.height / 2))

                context.fill(shape, with: .linearGradient(
                    Gradient(colors: [color, color.opacity(0.72)]),
                    startPoint: CGPoint(x: frame.minX, y: frame.minY),
                    endPoint: CGPoint(x: frame.minX, y: frame.maxY)
                ))
            }
        }
        .frame(height: height)
    }

    private var axis: some View {
        HStack {
            if let span {
                Text(span.start, format: .dateTime.hour().minute())
                Spacer()
                Text(midpointLabel(span))
                Spacer()
                Text(span.end, format: .dateTime.hour().minute())
            }
        }
        .font(Theme.text(9))
        .foregroundStyle(.tertiary)
        .padding(.leading, 42)
    }

    /// Sources without staging write `unspecified`; render it on the Core row
    /// so the chart still has a shape rather than an empty band.
    private func normalized(_ stage: SleepStage) -> SleepStage {
        stage == .unspecified ? .core : (stage == .inBed ? .awake : stage)
    }

    private func midpointLabel(_ span: DateInterval) -> String {
        let mid = span.start.addingTimeInterval(span.duration / 2)
        return mid.formatted(.dateTime.hour().minute())
    }

    private var accessibilitySummary: String {
        guard !segments.isEmpty else { return "No stage detail available" }
        let parts = SleepStage.hypnogramOrder.compactMap { stage -> String? in
            let minutes = segments.minutes(of: stage)
            guard minutes > 0 else { return nil }
            return "\(stage.displayName) \(SleepNightFeatures.formatMinutes(minutes))"
        }
        return parts.joined(separator: ", ")
    }
}

/// Compact stacked proportion bar — the stage split in one line.
///
/// Complements the hypnogram rather than duplicating it: the hypnogram shows
/// *when*, this shows *how much*.
struct StageProportionBar: View {
    let features: SleepNightFeatures
    var height: CGFloat = 12

    private var parts: [(stage: SleepStage, minutes: Double)] {
        [
            (.deep, features.deepMinutes),
            (.rem, features.remMinutes),
            (.core, features.coreMinutes + features.unspecifiedAsleepMinutes),
            (.awake, features.awakeMinutes)
        ].filter { $0.minutes > 0 }
    }

    private var total: Double { parts.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(parts, id: \.stage) { part in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.Stage.color(for: part.stage),
                                    Theme.Stage.color(for: part.stage).opacity(0.7)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: total > 0 ? geo.size.width * (part.minutes / total) : 0)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stage proportions")
    }
}

/// Legend row with minutes and percentage per stage.
struct StageLegend: View {
    let features: SleepNightFeatures

    private var rows: [(stage: SleepStage, minutes: Double, reference: String)] {
        [
            (.deep, features.deepMinutes, "13–23%"),
            (.rem, features.remMinutes, "20–25%"),
            (.core, features.coreMinutes + features.unspecifiedAsleepMinutes, "45–60%"),
            (.awake, features.awakeMinutes, "—")
        ]
    }

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows, id: \.stage) { row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.Stage.color(for: row.stage))
                        .frame(width: 8, height: 8)

                    Text(row.stage.displayName)
                        .font(Theme.label(13, weight: .medium))

                    Spacer()

                    Text(percent(row.minutes, stage: row.stage))
                        .font(Theme.label(13, weight: .semibold))
                        .monospacedDigit()

                    Text(SleepNightFeatures.formatMinutes(row.minutes))
                        .font(Theme.text(12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)

                    Text(row.reference)
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    /// Sleep stages are a share of time *asleep*; awake time is a share of time
    /// in bed. Using one denominator for both would let the bars exceed 100%.
    private func percent(_ minutes: Double, stage: SleepStage) -> String {
        let denominator = stage == .awake ? features.timeInBedMinutes : features.timeAsleepMinutes
        guard denominator > 0 else { return "—" }
        return "\(Int((minutes / denominator * 100).rounded()))%"
    }
}

#Preview("Hypnogram") {
    ScrollView {
        VStack(spacing: 20) {
            HypnogramView(segments: AppMockData.stageSegments(for: MockData.goodNight))
                .glassCard()
            StageProportionBar(features: MockData.goodNight)
                .padding(.horizontal)
            StageLegend(features: MockData.goodNight)
                .glassCard()
        }
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
