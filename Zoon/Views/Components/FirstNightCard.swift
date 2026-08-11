import SwiftUI

/// The first tracked night gets a different message than every night after
/// it: celebrate that data was successfully collected, not the score.
///
/// A score on night one is measured against a baseline that doesn't exist
/// yet -- treating it as a normal "84, Very Good" reading would be the exact
/// kind of false-confident number the rest of this app goes out of its way
/// to avoid. And sleep genuinely isn't always controllable, so "great job!"
/// is the wrong instinct even setting the baseline problem aside.
struct FirstNightCard: View {
    let night: SleepNightFeatures

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(Theme.text(20))
                    .foregroundStyle(Theme.Metric.sleep)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your first sleep is ready")
                        .font(Theme.label(15, weight: .bold))
                    Text(night.formattedTimeAsleep + " tracked")
                        .font(Theme.text(11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 16) {
                dataPoint("Sleep stages", available: !night.stageSegments.isEmpty)
                dataPoint("Heart rate", available: night.avgHeartRate != nil)
                dataPoint("Respiration", available: night.avgRespiratoryRate != nil)
            }

            Text("Personal baselines become more accurate as you collect more nights -- scores and comparisons below will start appearing over the next couple of weeks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private func dataPoint(_ label: String, available: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: available ? "checkmark.circle.fill" : "circle.dashed")
                .font(Theme.text(14))
                .foregroundStyle(available ? Theme.Metric.recoveryHigh : .secondary)
            Text(label)
                .font(Theme.text(9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("First Night") {
    ScrollView {
        FirstNightCard(night: AppMockData.dayContext().night)
            .padding()
    }
    .nightBackground()
    .preferredColorScheme(.dark)
}
