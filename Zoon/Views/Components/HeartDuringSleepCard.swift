import SwiftUI

/// What the heart did overnight, in two numbers and a sentence.
///
/// The hypnogram already draws the heart-rate line, but a line is not an
/// answer. This card says how low the heart settled, when, and what the
/// timing usually means. See `OvernightHeartSummary`.
struct HeartDuringSleepCard: View {
    let summary: OvernightHeartSummary
    /// Renders a time in the night's own time zone.
    let clock: (Date) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped on appear: three beats, then still. A beat that never stopped
    /// would run for as long as the screen stayed open.
    @State private var beats = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Heart during sleep", systemImage: "heart.fill")
                MetricInfoButton(
                    title: "Heart during sleep",
                    symbol: "heart.fill",
                    tint: Theme.Metric.heart,
                    explanation: [
                        "Sleep is when your heart gets its longest rest. On a settled night it slows well below your daytime resting rate and reaches its lowest point in the first half of the night.",
                        "A low point close to waking usually means your body spent the night busy with something: a late meal, alcohol, a hard late workout, illness or stress.",
                        "The lowest point here is a 15-minute average, so one noisy reading does not decide it."
                    ]
                )
            }

            HStack(spacing: 12) {
                stat(
                    label: "Average",
                    value: "\(Int(summary.averageBPM.rounded()))",
                    unit: "bpm"
                )
                stat(
                    label: "Lowest",
                    value: "\(Int(summary.lowestBPM.rounded()))",
                    unit: "bpm at \(clock(summary.lowestAt))"
                )
            }

            timingTrack

            Text(summary.timingSentence(clock: clock))
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let resting = summary.restingSentence {
                Text(resting)
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    private func stat(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.label(12))
                .foregroundStyle(Theme.inkSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Theme.numeral(28))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Metric.heart)
                Text(unit)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Metric.heart.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Asleep to awake as a line, with the lowest point marked by a beating
    /// heart and the first half shaded: the half where a settled night
    /// reaches its low.
    private var timingTrack: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.neutral(0.10))
                        .frame(height: 6)
                    Capsule()
                        .fill(Theme.Metric.recoveryHigh.opacity(0.28))
                        .frame(width: width / 2, height: 6)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Metric.heart)
                        .symbolEffect(.bounce, options: .repeat(3), value: beats)
                        .shadow(color: Theme.Metric.heart.opacity(0.6), radius: 4)
                        .offset(x: CGFloat(summary.lowestFraction) * width - 8)
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            HStack {
                Text("Fell asleep")
                Spacer()
                Text("Woke")
            }
            .font(Theme.text(11))
            .foregroundStyle(Theme.inkTertiary)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            beats += 1
        }
    }
}
