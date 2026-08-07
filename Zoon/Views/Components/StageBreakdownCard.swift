import SwiftUI

/// Per-stage bars for the night.
///
/// Hides itself entirely when the source didn't provide staging — drawing four
/// empty bars reads as "you got no deep sleep", which is a very different claim
/// from "this device doesn't measure deep sleep".
struct StageBreakdownCard: View {

    let features: SleepNightFeatures

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep Stages")
                .font(.headline)

            if features.hasStageBreakdown {
                stageBars
            } else {
                unavailableNotice
            }
        }
        .zoonCard()
    }

    private var stageBars: some View {
        VStack(spacing: 12) {
            // Percentages are of total *asleep* time, so the three sleep stages
            // sum to 100%.
            StageBar(
                stage: .deep,
                minutes: features.deepMinutes,
                total: features.timeAsleepMinutes,
                referenceRange: 13...23
            )
            StageBar(
                stage: .rem,
                minutes: features.remMinutes,
                total: features.timeAsleepMinutes,
                referenceRange: 20...25
            )
            StageBar(
                stage: .core,
                minutes: features.coreMinutes,
                total: features.timeAsleepMinutes,
                referenceRange: 45...60
            )
            // Awake is measured against time in bed, not time asleep — awake
            // time is by definition not part of sleep, so using the sleep total
            // as the denominator would let this bar exceed 100%.
            StageBar(
                stage: .awake,
                minutes: features.awakeMinutes,
                total: features.timeInBedMinutes,
                referenceRange: nil
            )
        }
    }

    private var unavailableNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "applewatch.slash")
                    .foregroundStyle(.secondary)
                Text("\(SleepNightFeatures.formatMinutes(features.timeAsleepMinutes)) asleep, no stage detail")
                    .font(.subheadline.weight(.medium))
            }
            Text("""
                \(features.sourceName ?? "This source") records sleep without breaking it into \
                stages. Wearing an Apple Watch to bed adds Deep, REM, and Core.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One stage bar with an optional typical-range marker.
struct StageBar: View {

    let stage: SleepStage
    let minutes: Double
    let total: Double
    /// Typical adult share of total sleep, as a percentage range. Drawn as a
    /// subtle band so the user can see whether they're in range without the app
    /// having to tell them they're "wrong".
    let referenceRange: ClosedRange<Double>?

    private var fraction: Double {
        guard total > 0 else { return 0 }
        // Clamped: overlapping samples from a bad source could otherwise push a
        // bar past its track.
        return min(max(minutes / total, 0), 1)
    }

    private var percent: Double { fraction * 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(stage.displayName)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(minutes.rounded())) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text("(\(Int(percent))%)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ZoonStyle.Stage.color(for: stage).opacity(0.18))

                    if let referenceRange {
                        Capsule()
                            .fill(ZoonStyle.Stage.color(for: stage).opacity(0.15))
                            .frame(width: geo.size.width * (referenceRange.upperBound - referenceRange.lowerBound) / 100)
                            .offset(x: geo.size.width * referenceRange.lowerBound / 100)
                    }

                    Capsule()
                        .fill(ZoonStyle.Stage.color(for: stage))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 10)
            .animation(.snappy, value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage.displayName)
        .accessibilityValue("\(Int(minutes.rounded())) minutes, \(Int(percent)) percent")
    }
}

#Preview("Staged") {
    ScrollView {
        StageBreakdownCard(features: MockData.goodNight)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Fragmented") {
    ScrollView {
        StageBreakdownCard(features: MockData.poorNight)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Unstaged source") {
    ScrollView {
        StageBreakdownCard(features: MockData.unstagedNight)
            .padding()
    }
    .background(Color(.systemGroupedBackground))
}
