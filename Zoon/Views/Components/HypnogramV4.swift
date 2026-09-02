import SwiftUI

/// The RIBBON visual grammar for last night: the hypnogram as the Sleep
/// tab's hero, edge-to-edge, with overlay toggles, a scrub readout and
/// tap-to-zoom on any awakening.
///
/// Wraps `HypnogramView`'s proven Canvas drawing rather than re-implementing
/// it: the stage blocks, risers, HR line and sound dots are the same code
/// with the same truthfulness (a block is exactly as wide as the stage
/// lasted). What this adds is the *frame* around that drawing:
///
/// * **Overlay pills** -- Stages is always on; Heart, Breathing and Sound
///   are toggles, at most two extra at once so the chart never clutters.
/// * **Readout** -- while scrubbing, the time, stage, nearest HR and (when
///   available) respiration sit in a fixed line *above* the chart, so the
///   finger never covers what it's reading.
/// * **Awakening zoom** -- tap an awakening in the list below and the chart
///   animates into ±15 minutes around it. Tap again, or "Full night", to
///   return. This is the doorway to Night Detective.
///
/// Draw-in is once per night (`drawOnce`) and never replays on scroll.
struct HypnogramV4: View {
    let night: SleepNightFeatures
    var heartRateSamples: [(date: Date, bpm: Double)] = []
    var soundEvents: [SoundEvent] = []

    enum Overlay: String, CaseIterable, Identifiable {
        case heart, breathing, sound
        var id: String { rawValue }
        var label: String {
            switch self {
            case .heart: "Heart"
            case .breathing: "Breathing"
            case .sound: "Sound"
            }
        }
        var symbol: String {
            switch self {
            case .heart: "heart.fill"
            case .breathing: "wind"
            case .sound: "waveform"
            }
        }
        var tint: Color {
            switch self {
            case .heart: Theme.Metric.heart
            case .breathing: Theme.Family.breathing
            case .sound: Theme.Family.bodySignals
            }
        }
    }

    @State private var overlays: Set<Overlay> = []
    @State private var scrubFraction: CGFloat?
    /// The window currently shown; `nil` means the whole night.
    @State private var zoom: DateInterval?
    @State private var progress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fullSpan: DateInterval? { night.stageSegments.span }
    private var shownSpan: DateInterval? { zoom ?? fullSpan }

    /// Segments clipped to the shown window, so a zoomed chart's blocks are
    /// exactly as long as the time they occupy inside the window.
    private var shownSegments: [StageSegment] {
        guard let shownSpan else { return night.stageSegments }
        return night.stageSegments.compactMap { segment in
            let start = max(segment.start, shownSpan.start)
            let end = min(segment.end, shownSpan.end)
            guard end > start else { return nil }
            return StageSegment(stage: segment.stage, start: start, end: end)
        }
    }

    /// Awakenings after sleep onset, long enough to matter -- the same rule
    /// `SleepStory` applies, so the list here matches the story below it.
    private var awakenings: [StageSegment] {
        let sorted = night.stageSegments.sorted { $0.start < $1.start }
        guard let onset = sorted.first(where: { SleepStage.asleepStages.contains($0.stage) })?.start else { return [] }
        return sorted.filter { ($0.stage == .awake || $0.stage == .inBed) && $0.start > onset && $0.minutes >= 3 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            readout
            chart
            controls
            if !awakenings.isEmpty {
                awakeningRow
            }
        }
        .drawOnce(id: night.nightKey, progress: $progress)
    }

    // MARK: - Readout

    /// A fixed-height line above the chart, so the layout doesn't jump when
    /// scrubbing starts and the finger never covers the numbers.
    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            if let time = scrubTime, let segment = segment(at: time) {
                Text(time, format: .dateTime.hour().minute())
                    .font(Theme.supportingValue)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(HypnogramV4.normalized(segment.stage).displayName)
                    .font(Theme.label(14, weight: .semibold))
                    .foregroundStyle(Theme.Stage.color(for: HypnogramV4.normalized(segment.stage)))
                if let hr = nearestHeartRate(to: time) {
                    metric("HR", "\(Int(hr.rounded())) bpm", tint: Theme.Metric.heart)
                }
                if let event = nearestSoundEvent(to: time) {
                    metric(event.label, event.date.formatted(.dateTime.hour().minute()), tint: Theme.Family.bodySignals)
                }
                Spacer(minLength: 0)
            } else if let zoom {
                Text("\(zoom.start, format: .dateTime.hour().minute()) – \(zoom.end, format: .dateTime.hour().minute())")
                    .font(Theme.supportingValue)
                    .monospacedDigit()
                Text("Zoomed")
                    .font(Theme.supportingLabel)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Full night") {
                    Haptics.tap()
                    withAnimation(Motion.respecting(reduceMotion, Motion.hero)) { self.zoom = nil }
                }
                .font(Theme.text(12, weight: .semibold))
                .foregroundStyle(Theme.Family.sleep)
                .buttonStyle(.plain)
            } else if let fullSpan {
                Text(fullSpan.start, format: .dateTime.hour().minute())
                    .font(Theme.supportingValue)
                    .monospacedDigit()
                Rectangle().fill(Theme.neutral(0.25)).frame(width: 40, height: 1)
                Text(fullSpan.end, format: .dateTime.hour().minute())
                    .font(Theme.supportingValue)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("Drag to explore")
                    .font(Theme.text(11))
                    .foregroundStyle(.quaternary)
            }
        }
        .frame(minHeight: 28)
        .animation(Motion.respecting(reduceMotion, Motion.scrub), value: scrubFraction == nil)
    }

    private func metric(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(label).font(Theme.text(11)).foregroundStyle(.secondary)
            Text(value).font(Theme.label(12, weight: .semibold)).monospacedDigit()
        }
    }

    // MARK: - Chart

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                HypnogramView(
                    segments: shownSegments,
                    height: 190,
                    showsAxis: false,
                    heartRateSamples: overlays.contains(.heart) ? heartRateSamples : [],
                    soundEvents: overlays.contains(.sound) ? soundEvents : []
                )
                .allowsHitTesting(false)
                .mask(alignment: .leading) {
                    // Left → right reveal, once.
                    GeometryReader { geo in
                        Rectangle().frame(width: geo.size.width * progress)
                    }
                }

                if let scrubFraction {
                    ScrubCursor(fraction: scrubFraction)
                        .padding(.leading, 50)
                }

                if overlays.contains(.breathing), let rate = night.avgRespiratoryRate {
                    Text("Breathing \(rate, format: .number.precision(.fractionLength(1)))/min overnight")
                        .font(Theme.text(10, weight: .medium))
                        .foregroundStyle(Theme.Family.breathing)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.neutral(0.06), in: Capsule())
                        .padding(.leading, 50)
                        .padding(.top, 4)
                }
            }
            .frame(height: 190)
            // The scrub surface covers only the plot, not the 50pt stage
            // label column `HypnogramView` draws down the left, so a fraction
            // of 0 is the first minute of the night rather than the word
            // "Awake". `HypnogramView`'s own gesture is disabled above.
            .overlay {
                Color.clear
                    .zoonScrubbable(fraction: $scrubFraction, detent: segmentDetent)
                    .padding(.leading, 50)
            }

            axis
        }
        .animation(Motion.respecting(reduceMotion, Motion.hero), value: zoom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stages through the night")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint(awakenings.isEmpty ? "" : "Awakenings are listed below and can be opened for detail")
    }

    private var axis: some View {
        HStack {
            if let shownSpan {
                Text(shownSpan.start, format: .dateTime.hour().minute())
                Spacer()
                Text(shownSpan.start.addingTimeInterval(shownSpan.duration / 2), format: .dateTime.hour().minute())
                Spacer()
                Text(shownSpan.end, format: .dateTime.hour().minute())
            }
        }
        .font(Theme.text(10))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
        .padding(.leading, 50)
    }

    // MARK: - Controls

    /// Stages is always on. Heart/Breathing/Sound toggle, at most two extra
    /// at once; a pill is disabled (not hidden) when there's no data behind
    /// it, so the reader learns what the watch *could* show.
    private var controls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ZoonMetricPill(text: "Stages", systemImage: "square.stack.3d.up", tint: Theme.Family.sleep, isSelected: true)
                    .accessibilityLabel("Stages, always shown")
                ForEach(Overlay.allCases) { overlay in
                    let available = isAvailable(overlay)
                    Button {
                        toggle(overlay)
                    } label: {
                        ZoonMetricPill(text: overlay.label, systemImage: overlay.symbol, tint: overlay.tint, isSelected: overlays.contains(overlay))
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .opacity(available ? 1 : 0.4)
                    .accessibilityLabel("\(overlay.label) overlay")
                    .accessibilityValue(available ? (overlays.contains(overlay) ? "on" : "off") : "no data")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func isAvailable(_ overlay: Overlay) -> Bool {
        switch overlay {
        case .heart: heartRateSamples.count >= 2
        case .breathing: night.avgRespiratoryRate != nil
        case .sound: !soundEvents.isEmpty
        }
    }

    private func toggle(_ overlay: Overlay) {
        Haptics.select()
        withAnimation(Motion.respecting(reduceMotion, Motion.tap)) {
            if overlays.contains(overlay) {
                overlays.remove(overlay)
            } else {
                if overlays.count >= 2, let oldest = overlays.first { overlays.remove(oldest) }
                overlays.insert(overlay)
            }
        }
    }

    // MARK: - Awakenings

    /// Each meaningful awakening as a chip; tapping zooms the chart to ±15
    /// minutes around it. The selected chip shows a "Night Detective" link.
    private var awakeningRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZoonSectionHeader("Awakenings") {
                Text("\(awakenings.count)")
                    .font(Theme.label(12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(awakenings) { awakening in
                        let isZoomed = zoom.map { $0.contains(awakening.start) } ?? false
                        Button {
                            zoom(to: awakening)
                        } label: {
                            HStack(spacing: 6) {
                                Text(awakening.start, format: .dateTime.hour().minute())
                                    .font(Theme.label(12, weight: .semibold))
                                    .monospacedDigit()
                                Text("\(Int(awakening.minutes.rounded()))m")
                                    .font(Theme.text(11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(isZoomed ? Theme.Stage.awake.opacity(0.22) : Theme.neutral(0.05), in: Capsule())
                            .overlay(Capsule().strokeBorder(isZoomed ? Theme.Stage.awake.opacity(0.6) : .clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Awakening at \(awakening.start.formatted(.dateTime.hour().minute())), \(Int(awakening.minutes.rounded())) minutes")
                        .accessibilityHint(isZoomed ? "Zoomed in. Tap to show the full night" : "Zoom the chart to this awakening")
                        .accessibilityAddTraits(isZoomed ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func zoom(to awakening: StageSegment) {
        Haptics.milestone()
        let window = DateInterval(
            start: awakening.start.addingTimeInterval(-15 * 60),
            end: awakening.end.addingTimeInterval(15 * 60)
        )
        let clamped = fullSpan.map { DateInterval(start: max($0.start, window.start), end: min($0.end, window.end)) } ?? window
        withAnimation(Motion.respecting(reduceMotion, Motion.hero)) {
            zoom = (zoom == clamped) ? nil : clamped
        }
    }

    // MARK: - Mapping

    private var scrubTime: Date? {
        guard let shownSpan, shownSpan.duration > 0, let scrubFraction else { return nil }
        return shownSpan.start.addingTimeInterval(shownSpan.duration * Double(scrubFraction))
    }

    private func segment(at time: Date) -> StageSegment? {
        night.stageSegments.first { $0.start <= time && time < $0.end }
            ?? night.stageSegments.min { abs($0.start.timeIntervalSince(time)) < abs($1.start.timeIntervalSince(time)) }
    }

    /// One haptic per stage block crossed while scrubbing.
    private func segmentDetent(_ fraction: CGFloat) -> Int? {
        guard let shownSpan, shownSpan.duration > 0 else { return nil }
        let time = shownSpan.start.addingTimeInterval(shownSpan.duration * Double(fraction))
        return night.stageSegments.sorted { $0.start < $1.start }.firstIndex { $0.start <= time && time < $0.end }
    }

    private func nearestHeartRate(to time: Date) -> Double? {
        heartRateSamples
            .filter { abs($0.date.timeIntervalSince(time)) <= 30 * 60 }
            .min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }?.bpm
    }

    private func nearestSoundEvent(to time: Date) -> SoundEvent? {
        guard overlays.contains(.sound) else { return nil }
        return soundEvents
            .filter { abs($0.date.timeIntervalSince(time)) <= 120 }
            .min { abs($0.date.timeIntervalSince(time)) < abs($1.date.timeIntervalSince(time)) }
    }

    /// Sources without staging write `unspecified`; shown as Core, as
    /// `HypnogramView` does.
    static func normalized(_ stage: SleepStage) -> SleepStage {
        stage == .unspecified ? .core : (stage == .inBed ? .awake : stage)
    }

    private var accessibilitySummary: String {
        guard !night.stageSegments.isEmpty else { return "No stage detail available" }
        var parts = SleepStage.hypnogramOrder.compactMap { stage -> String? in
            let minutes = night.stageSegments.minutes(of: stage)
            guard minutes > 0 else { return nil }
            return "\(stage.displayName) \(SleepNightFeatures.formatMinutes(minutes))"
        }
        if !awakenings.isEmpty {
            parts.append("\(awakenings.count) awakening\(awakenings.count == 1 ? "" : "s") after falling asleep")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Hypnogram V4") {
    var staged = MockData.poorNight
    staged.stageSegments = AppMockData.stageSegments(for: staged)
    return ScrollView {
        HypnogramV4(
            night: staged,
            heartRateSamples: MockData.hourlyHeartRate(wakeTime: staged.wakeTime),
            soundEvents: []
        )
        .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
