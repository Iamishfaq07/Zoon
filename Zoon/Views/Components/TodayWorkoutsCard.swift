import SwiftUI

/// Today's logged workouts, real `HKWorkout` sessions rather than the
/// continuous heart-rate binning `Daily Load`'s own number is built from --
/// see `WorkoutSummary`'s doc comment for why the two stay separate.
/// Hidden entirely on a day with nothing logged, same as every other
/// optional card on this screen.
struct TodayWorkoutsCard: View {
    let workouts: [WorkoutSummary]

    var body: some View {
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Today's Workouts", systemImage: "figure.run")
                ForEach(workouts) { workout in
                    HStack(spacing: 10) {
                        Image(systemName: workout.symbol)
                            .font(Theme.text(13))
                            .foregroundStyle(Theme.Metric.strain)
                            .frame(width: 20)
                        Text(workout.activityLabel)
                            .font(Theme.label(13, weight: .medium))
                        Spacer()
                        Text("\(Int(workout.durationMinutes.rounded())) min")
                            .font(Theme.text(12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if let kcal = workout.activeEnergyKcal {
                            Text("\(Int(kcal.rounded())) kcal")
                                .font(Theme.text(12))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .glassCard()
        }
    }
}

#Preview("Today's Workouts") {
    ScrollView {
        TodayWorkoutsCard(workouts: [
            WorkoutSummary(activityLabel: "Run", symbol: "figure.run", start: .now.addingTimeInterval(-3600 * 3), durationMinutes: 32, activeEnergyKcal: 310),
            WorkoutSummary(activityLabel: "Strength Training", symbol: "figure.strengthtraining.traditional", start: .now.addingTimeInterval(-3600 * 6), durationMinutes: 45, activeEnergyKcal: 220)
        ])
        .padding()
    }
    .nightBackground()
}
