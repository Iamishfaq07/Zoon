import SwiftUI

struct AwakeningInspectorCard: View {
    let night: SleepNightFeatures
    var sounds: [SoundEvent] = []
    @State private var index = 0

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
                if !sequence.missingStreams.isEmpty {
                    Text("Not recorded: \(sequence.missingStreams.joined(separator: ", ")).")
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Awakening at \(interval.start.formatted(date: .omitted, time: .shortened)), \(SleepNightFeatures.formatMinutes(sequence.awakeningMinutes)). \(sequence.caveat)")
        }
    }
}
