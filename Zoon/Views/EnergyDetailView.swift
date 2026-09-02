import SwiftUI

/// Where the Energy Horizon leads: the full same-day picture that used to
/// sit as three separate cards on Today.
///
/// Nothing here is new. `BodyBatteryCard`, `EnergyForecastCard`,
/// `TodayWorkoutsCard` and the Daily Load row are the same views they were,
/// moved one tap deeper so Today can show one horizon instead of three
/// overlapping charts. Load lives here because energy spent is the other
/// side of energy left.
struct EnergyDetailView: View {
    let context: DayContext

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                EnergyHorizon(
                    forecast: forecast,
                    battery: context.bodyBattery,
                    targetBedtime: context.targetBedtime()
                )
                .padding(.bottom, 8)
                .entrance(0)

                BodyBatteryCard(battery: context.bodyBattery).entrance(1)

                if let stress = coordinator.todayStress {
                    StressCard(stress: stress, todayStrain: context.strain.value).entrance(2)
                }

                loadCard.entrance(2)

                TodayWorkoutsCard(workouts: coordinator.todayWorkouts).entrance(3)

                if let guidance = LightCoach.guidance(
                    wakeTime: context.night.wakeTime,
                    onsetHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil,
                    todayDaylightMinutes: preferences.lifestyleInsightsEnabled
                        ? coordinator.todayLifestyleInsights?.daylightMinutes : nil
                ) {
                    LightCoachCard(guidance: guidance).entrance(3)
                }

                EnergyForecastCard(forecast: forecast).entrance(4)
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Energy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var forecast: EnergyForecast {
        EnergyForecast.compute(
            wakeTime: context.night.wakeTime,
            sleepDebtMinutes: context.night.sleepDebtMinutes ?? 0,
            windDownHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil
        )
    }

    /// Daily Load, exactly as `TodayView.dailyLoadRow` drew it.
    private var loadCard: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.Metric.strain).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text(context.strain.displayValue)
                        .font(Theme.label(17, weight: .bold))
                        .monospacedDigit()
                    Text("Load")
                        .font(Theme.label(11))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    Text(context.strain.band)
                        .font(Theme.text(10))
                        .foregroundStyle(.tertiary)
                    if context.strain.isEstimate {
                        Text("· estimated")
                            .font(Theme.text(10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 4)
            MetricInfoButton(
                title: "Daily Load",
                symbol: "flame.fill",
                tint: Theme.Metric.strain,
                explanation: [
                    "Daily Load is a cardiovascular load score built from your heart rate through the day, weighted by how far above resting it ran and for how long -- not just a step count or a workout minutes total.",
                    "It's read next to Sleep Need and Recovery deliberately: a high-load day increases what your body needs from that night's sleep to fully recover."
                ]
            )
        }
        .glassCard()
    }
}

#Preview("Energy detail") {
    NavigationStack {
        EnergyDetailView(context: AppMockData.dayContext())
    }
    .zoonPreviewEnvironment()
}
