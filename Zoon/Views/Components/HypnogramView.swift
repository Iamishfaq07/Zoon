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
    /// Optional heart-rate overlay, drawn as a thin line across the full
    /// chart height on its own min/max scale. Empty by default -- the three
    /// existing call sites that don't have this data (Today's compact strip,
    /// `PastNightDetailView`) render exactly as before.
    var heartRateSamples: [(date: Date, bpm: Double)] = []
    /// Optional sound-event markers (snoring, coughing, etc.), drawn as small
    /// dots along the top edge at the moment each was detected.
    var soundEvents: [SoundEvent] = []

    /// Stage rows, top to bottom. Awake at the top so the trace descends into
    /// deep sleep — the convention people already know how to read.
    private let rows = SleepStage.hypnogramOrder

    /// Drag/tap position as a 0...1 fraction across the chart width. Driven by
    /// a gesture rather than `chartXSelection` because this view is a `Canvas`,
    /// not a Swift Charts mark — the touch-to-time math has to be done by hand.
    @State private var selectedFraction: CGFloat?

    private var span: DateInterval? { segments.span }

    private var selectedSegment: StageSegment? {
        guard let span, span.duration > 0, let selectedFraction else { return nil }
        let time = span.start.addingTimeInterval(span.duration * Double(selectedFraction))
        return segments.first { $0.start <= time && time < $0.start.addingTimeInterval($0.duration) }
            ?? segments.min { abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time)) }
    }

    /// Nearest sound event to the drag position, within two minutes -- close
    /// enough that surfacing it in the badge reads as "this is what happened
    /// here," not a coincidental nearby moment.
    private var selectedSoundEvent: SoundEvent? {
        guard let span, span.duration > 0, let selectedFraction else { return nil }
        let time = span.start.addingTimeInterval(span.duration * Double(selectedFraction))
        return soundEvents
            .filter { abs($0.date.timeIntervalSince(time)) <= 120 }
            .min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                rowLabels
                chart
            }
            if showsAxis { axis }
            // The chart has always supported drag-to-inspect -- the gesture
            // above is unconditional -- but nothing on screen said so, on
            // any of its three call sites, so the feature was invisible.
            // Gated on `showsAxis` (true only where there's room to spare a
            // line): Today's compact strip stays exactly as dense as it was.
            if showsAxis && selectedFraction == nil {
                Text("Drag to see stage and time")
                    .font(Theme.text(9))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 42)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages through the night")
        .accessibilityValue(accessibilitySummary)
    }

    /// Stage names down the left edge.
    ///
    /// `lineLimit(1)` and a scale floor, because the column is a fixed width
    /// and the type is no longer a fixed size. When the fonts became Dynamic
    /// Type-aware, `label(9)` started resolving to `.caption2` — larger than
    /// the 9 points this 34-wide column was measured for — and "Awake" wrapped
    /// to "Awak / e" in the middle of the chart. Shrinking beats wrapping for
    /// an axis label, and a wider column would eat chart width at every size
    /// to fix the widest one.
    private var rowLabels: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { stage in
                Text(stage.displayName)
                    .font(Theme.label(9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.Stage.color(for: stage))
                    .frame(height: height / CGFloat(rows.count), alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: 42)
    }

    private var chart: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Canvas { context, size in
                    guard let span, span.duration > 0 else { return }

                    let rowHeight = size.height / CGFloat(rows.count)
                    // Blocks are inset within their row so adjacent stages read as
                    // separate bars rather than one continuous slab.
                    let blockHeight = rowHeight * 0.62
                    let total = span.duration

                    func rect(for segment: StageSegment) -> CGRect? {
                        guard let rowIndex = rows.firstIndex(of: segment.stage.hypnogramRow) else { return nil }
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
                        context.stroke(path, with: .color(Theme.neutral(0.18)), lineWidth: 1)
                    }

                    for segment in ordered {
                        guard let frame = rect(for: segment) else { continue }
                        // The stage's own colour: unstaged sleep is neutral,
                        // not Core's, and in-bed time is not Awake's.
                        let color = Theme.Stage.color(for: segment.stage)
                        let shape = Path(roundedRect: frame, cornerRadius: min(4, frame.height / 2))

                        context.fill(shape, with: .linearGradient(
                            Gradient(colors: [color, color.opacity(0.72)]),
                            startPoint: CGPoint(x: frame.minX, y: frame.minY),
                            endPoint: CGPoint(x: frame.minX, y: frame.maxY)
                        ))
                    }

                    // Only the samples inside the night: the scale and the
                    // availability both used to count points the line could
                    // never draw. See `OvernightSeries`.
                    let nightHeartRate = OvernightSeries.clipped(heartRateSamples, to: span)
                    if nightHeartRate.count >= 2 {
                        let bpms = nightHeartRate.map(\.bpm)
                        let minBPM = bpms.min() ?? 0
                        let maxBPM = bpms.max() ?? 1
                        let bpmRange = max(1, maxBPM - minBPM)

                        func point(for sample: (date: Date, bpm: Double)) -> CGPoint? {
                            guard sample.date >= span.start, sample.date <= span.end else { return nil }
                            let x = (sample.date.timeIntervalSince(span.start) / total) * size.width
                            // Confined to the top 55% of the chart so the
                            // line reads as an overlay riding above the
                            // stage blocks rather than competing with them.
                            let y = (1 - (sample.bpm - minBPM) / bpmRange) * size.height * 0.55
                            return CGPoint(x: x, y: y)
                        }

                        let path = Path { p in
                            var started = false
                            for sample in nightHeartRate {
                                guard let point = point(for: sample) else { continue }
                                if started { p.addLine(to: point) } else { p.move(to: point); started = true }
                            }
                        }
                        context.stroke(path, with: .color(Theme.Metric.heart.opacity(0.7)), lineWidth: 1.5)
                    }

                    if !soundEvents.isEmpty {
                        for event in soundEvents {
                            guard event.date >= span.start, event.date <= span.end else { continue }
                            let x = (event.date.timeIntervalSince(span.start) / total) * size.width
                            let dot = Path(ellipseIn: CGRect(x: x - 2.5, y: 2, width: 5, height: 5))
                            context.fill(dot, with: .color(Theme.Metric.respiratory.opacity(0.85)))
                        }
                    }

                    if let selectedFraction {
                        let x = size.width * selectedFraction
                        let path = Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        context.stroke(path, with: .color(Theme.dialMarker.opacity(0.55)), lineWidth: 1)
                    }
                }
                .frame(width: geo.size.width, height: height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            selectedFraction = min(1, max(0, value.location.x / geo.size.width))
                        }
                        .onEnded { _ in selectedFraction = nil }
                )

                if let selectedFraction, let selectedSegment {
                    let x = geo.size.width * selectedFraction
                    ChartSelectionBadge(
                        title: selectedSegment.start.formatted(.dateTime.hour().minute()),
                        lines: badgeLines(for: selectedSegment)
                    )
                    .offset(x: min(max(0, x - 60), geo.size.width - 120), y: -6)
                }
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
        .foregroundStyle(Theme.inkTertiary)
        .padding(.leading, 42)
    }


    private func badgeLines(for segment: StageSegment) -> [(label: String, value: String, tint: Color)] {
        var lines: [(label: String, value: String, tint: Color)] = [(
            "Stage",
            segment.stage.chartLabel,
            Theme.Stage.color(for: segment.stage)
        )]
        if let nearestHR = nearestHeartRate(to: segment.start) {
            lines.append(("Heart rate", "\(Int(nearestHR.rounded())) bpm", Theme.Metric.heart))
        }
        if let event = selectedSoundEvent {
            lines.append((event.label, event.date.formatted(.dateTime.hour().minute()), Theme.Metric.respiratory))
        }
        return lines
    }

    private func nearestHeartRate(to time: Date) -> Double? {
        guard let span else { return nil }
        return OvernightSeries.nearest(to: time, in: heartRateSamples, over: span)
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
            (.core, features.coreMinutes),
            // Its own neutral part, never added to Core: nothing classified it.
            (.unspecified, features.unspecifiedAsleepMinutes),
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
        .accessibilityValue(accessibilitySummary)
    }

    /// The split, spoken. `children: .ignore` collapses the capsules into one
    /// element, which is right -- four unlabelled shapes are not four things
    /// to swipe through -- but it left the element carrying a title and no
    /// content, so VoiceOver announced "Stage proportions" and stopped.
    ///
    /// A value rather than `accessibilityHidden`, because two of this view's
    /// four call sites (`RootView`, `TodayCards`) have no `StageLegend` under
    /// them: there the bar is the only statement of the night's stage split,
    /// and hiding it would remove the information rather than de-duplicate
    /// it. On the two screens that do carry a legend this repeats what the
    /// legend says, and repeating beats silence.
    private var accessibilitySummary: String {
        guard total > 0 else { return "No stage data for this night." }
        return parts
            .map { part in
                let percent = Int((part.minutes / total * 100).rounded())
                return "\(part.stage.chartLabel) \(percent) percent"
            }
            .joined(separator: ", ")
    }
}

/// Legend row with minutes and percentage per stage.
struct StageLegend: View {
    let features: SleepNightFeatures

    /// Reference ranges only where the stages were measured. On a night a
    /// schedule or a phone "staged", or with most of it unstaged, "Deep
    /// 13–23%" beside a figure nothing measured invites a comparison the data
    /// cannot support.
    private var showsReferences: Bool {
        let asleep = features.coreMinutes + features.deepMinutes + features.remMinutes
            + features.unspecifiedAsleepMinutes
        guard features.stageTrust.supportsStageFigures, asleep > 0 else { return false }
        return features.unspecifiedAsleepMinutes / asleep < 0.25
    }

    private var rows: [(stage: SleepStage, minutes: Double, reference: String)] {
        let shown = showsReferences
        var result: [(stage: SleepStage, minutes: Double, reference: String)] = [
            (.deep, features.deepMinutes, shown ? "13–23%" : "—"),
            (.rem, features.remMinutes, shown ? "20–25%" : "—"),
            (.core, features.coreMinutes, shown ? "45–60%" : "—")
        ]
        if features.unspecifiedAsleepMinutes > 0 {
            result.append((.unspecified, features.unspecifiedAsleepMinutes, "—"))
        }
        result.append((.awake, features.awakeMinutes, "—"))
        return result
    }

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows, id: \.stage) { row in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.Stage.color(for: row.stage))
                        .frame(width: 8, height: 8)

                    Text(row.stage.chartLabel)
                        .font(Theme.label(13, weight: .medium))

                    Spacer()

                    Text(percent(row.minutes, stage: row.stage))
                        .font(Theme.label(13, weight: .semibold))
                        .monospacedDigit()

                    // Same reasoning as the axis labels: fixed-width columns
                    // holding text that is no longer a fixed size. "1h 22m"
                    // fits at default and not at the largest setting, and a
                    // duration that wraps mid-value is unreadable.
                    Text(SleepNightFeatures.formatMinutes(row.minutes))
                        .font(Theme.text(12))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 56, alignment: .trailing)

                    Text(row.reference)
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.inkTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
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
