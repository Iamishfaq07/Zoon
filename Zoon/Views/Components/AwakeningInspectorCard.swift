import SwiftUI

struct AwakeningInspectorCard: View {
    let night: SleepNightFeatures
    var sounds: [SoundEvent] = []
    @State private var index = 0

    /// Says *why* a stream is absent, which differs by stream.
    private func missingLine(_ streams: [String]) -> String {
        let notReadAtThisResolution = streams.filter { $0 == "heart rate" || $0 == "movement" }
        let notRecorded = streams.filter { !notReadAtThisResolution.contains($0) }

        var parts: [String] = []
        if !notReadAtThisResolution.isEmpty {
            parts.append(
                "Zoon doesn't read \(list(notReadAtThisResolution)) minute by minute yet, so \(notReadAtThisResolution.count == 1 ? "it isn't" : "they aren't") on this timeline."
            )
        }
        if !notRecorded.isEmpty {
            parts.append("No \(list(notRecorded)) was recorded for this night.")
        }
        return parts.joined(separator: " ")
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
                sounds: sounds
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
                Text(sequence.caveat)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // "Not recorded" blamed the sensor for something Zoon does
                // not ask for. Heart rate and movement are absent here
                // because this screen has no minute-level series to read: the
                // app fetches heart rate hourly, and an hourly bucket cannot
                // place a rise inside a four-minute awakening. Sound is
                // genuinely a recording question, so the two are said
                // differently.
                //
                // Feeding the hourly series in as `heartRateRiseAt` would
                // have filled the gap by inventing a precision the data does
                // not have, which is the one thing this screen must not do.
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
}
