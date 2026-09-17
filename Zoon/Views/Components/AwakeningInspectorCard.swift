import SwiftUI

struct AwakeningInspectorCard: View {
    let night: SleepNightFeatures
    var sounds: [SoundEvent] = []
    /// The overnight minute-level series, when the night has one. Defaulted so
    /// every existing call site and preview is unchanged and simply gets the
    /// markers without the trace.
    var series = AwakeningInspector.Series()

    @State private var index = 0
    /// Progressive disclosure, as §25 asks for: the timeline is the screen and
    /// the trace is the layer underneath it. Both at once is the unreadable
    /// chart the brief warns about, and the timeline is what answers the
    /// question most people came with.
    @State private var showsTrace = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Says *why* a stream is absent.
    ///
    /// This used to draw a distinction that no longer exists: heart rate and
    /// movement were reported as "not read minute by minute yet", because the
    /// only overnight series the app fetched was hourly. It now fetches them
    /// at one minute, so an absent stream here means the same thing it means
    /// for sound — nothing was recorded for this night. The old wording blamed
    /// the app for a gap that is now the sensor's, and keeping it would have
    /// been an apology for a limitation that had been fixed.
    private func missingLine(_ streams: [String]) -> String {
        "No \(list(streams)) was recorded for this night."
    }

    private func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }

    private var awakenings: [DateInterval] {
        AwakeningInspector.awakenings(in: night.stageSegments)
    }

    var body: some View {
        let intervals = awakenings
        if intervals.isEmpty {
            EmptyView()
        } else {
            let interval = intervals[min(index, intervals.count - 1)]
            let sequence = AwakeningInspector.inspect(
                awakening: interval,
                stages: night.stageSegments,
                sounds: sounds,
                series: series
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeader(title: "Awakening inspector", systemImage: "waveform.path.ecg")
                    Spacer()
                    if intervals.count > 1 {
                        Button("Next") {
                            Haptics.select()
                            index = (index + 1) % intervals.count
                        }
                        .font(Theme.label(12, weight: .semibold))
                    }
                }
                Text("\(interval.start.formatted(date: .omitted, time: .shortened)) · \(SleepNightFeatures.formatMinutes(sequence.awakeningMinutes)) awake")
                    .font(Theme.text(22, weight: .semibold))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sequence.markers) { marker in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(marker.date.formatted(date: .omitted, time: .shortened))
                                .font(Theme.label(12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.inkTertiary)
                                .frame(width: 56, alignment: .leading)
                            Text(marker.caption)
                                .font(Theme.text(15))
                        }
                    }
                }
                if let note = sequence.respiratoryNote {
                    Text(note)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The trace is a layer, not the headline. It appears only when
                // there is one to draw and only when asked for, and never at
                // accessibility sizes, where a 64pt sparkline is decoration
                // that pushes the markers -- which carry every figure it does
                // -- off the screen.
                if sequence.heartRateWindow.contains(where: { $0.value != nil }),
                   !dynamicTypeSize.isAccessibilitySize {
                    DisclosureGroup(isExpanded: $showsTrace) {
                        trace(sequence)
                            .padding(.top, 8)
                    } label: {
                        Text("Heart rate around this awakening")
                            .font(Theme.label(13, weight: .semibold))
                    }
                    .onChange(of: showsTrace) { _, _ in Haptics.select() }
                }

                if let provenance = sequence.movementProvenance {
                    Text(provenance)
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(sequence.caveat)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // Only genuinely absent streams reach here now. A series that
                // arrived and held no rise is not missing -- the engine strips
                // it from this list -- so the screen no longer apologises for
                // data it has.
                if !sequence.missingStreams.isEmpty {
                    Text(missingLine(sequence.missingStreams))
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Awakening at \(interval.start.formatted(date: .omitted, time: .shortened)), \(SleepNightFeatures.formatMinutes(sequence.awakeningMinutes)). \(sequence.caveat)")
        }
    }

    /// The heart-rate trace across the window, with the awakening marked.
    ///
    /// Gaps are drawn as gaps. A watch writes a heart rate every few minutes,
    /// so most one-minute bins are empty, and joining across them would draw a
    /// straight line through minutes nobody measured — which on a chart reads
    /// as a steady heart rate rather than as an absence.
    private func trace(_ sequence: AwakeningInspector.Sequence) -> some View {
        let readings = sequence.heartRateWindow.compactMap { sample -> (Date, Double)? in
            sample.value.map { (sample.date, $0) }
        }
        let values = readings.map(\.1)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(1, high - low)
        let window = sequence.window

        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Where the awakening starts, so the trace can be read
                    // against it rather than beside it.
                    let markerX = geo.size.width
                        * (sequence.awakeningStart.timeIntervalSince(window.start) / window.duration)
                    Rectangle()
                        .fill(Theme.cardStroke)
                        .frame(width: 1)
                        .offset(x: markerX)

                    ForEach(Array(readings.enumerated()), id: \.offset) { _, reading in
                        let x = geo.size.width
                            * (reading.0.timeIntervalSince(window.start) / window.duration)
                        let y = geo.size.height * (1 - (reading.1 - low) / span)
                        Circle()
                            .fill(Theme.Metric.heart)
                            .frame(width: 4, height: 4)
                            .offset(x: x - 2, y: y - 2)
                    }
                }
            }
            .frame(height: 64)

            HStack {
                Text("\(Int(low.rounded()))–\(Int(high.rounded())) bpm")
                Spacer()
                Text("\(readings.count.pluralized("reading")) in 24 minutes")
            }
            .font(Theme.evidence)
            .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate around this awakening")
        .accessibilityValue(
            "\(readings.count.pluralized("reading")), between \(Int(low.rounded())) and \(Int(high.rounded())) beats per minute."
        )
    }
}
