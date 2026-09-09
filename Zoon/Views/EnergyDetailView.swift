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

                CognitiveEnergyCard(curve: context.cognitiveEnergy).entrance(5)
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

/// Amplitude of today's energy curve: last night's HRV, overnight HR dip,
/// and REM/Deep mix. The horizon above is the *shape*; this is how high
/// the peak sits and how deep the slump goes. Explicitly an estimate.
private struct CognitiveEnergyCard: View {
    let curve: CognitiveEnergyCurve

    private var peak: CognitiveEnergyCurve.Hour? {
        curve.hours.filter { $0.band == .peakFocus }.max(by: { $0.level < $1.level })
    }

    private var slump: CognitiveEnergyCurve.Hour? {
        curve.hours.filter { $0.band == .slump }.min(by: { $0.level < $1.level })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Cognitive energy",
                subtitle: missingLine,
                systemImage: "brain.head.profile"
            )

            HStack(alignment: .bottom, spacing: 3) {
                ForEach(curve.hours) { hour in
                    Capsule()
                        .fill(tint(for: hour.band).opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: 64)
                        .frame(height: max(4, 64 * hour.level))
                        .accessibilityLabel("\(hour.band.label), hour \(hour.offset)")
                }
            }
            .frame(height: 64, alignment: .bottom)

            HStack {
                if let peak {
                    stat("+\(peak.offset)h", peak.band.label, Theme.Metric.recoveryHigh)
                }
                if let slump {
                    stat("+\(slump.offset)h", slump.band.label, Theme.Metric.recoveryMid)
                }
            }

            Text("Estimated from last night's HRV, the overnight heart-rate dip, and REM/Deep mix. Nothing on a wrist measures cognition.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var missingLine: String {
        if curve.missing.isEmpty {
            return "Amplitude from last night, not a measurement"
        }
        return "Missing " + curve.missing.joined(separator: ", ") + " — treated as average"
    }

    private func tint(for band: CognitiveEnergyCurve.Band) -> Color {
        switch band {
        case .peakFocus: Theme.Metric.recoveryHigh
        case .steady: Theme.Metric.battery
        case .slump: Theme.Metric.recoveryMid
        case .windDown: Theme.Metric.sleep
        }
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.label(15, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(Theme.text(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Energy detail") {
    NavigationStack {
        EnergyDetailView(context: AppMockData.dayContext())
    }
    .zoonPreviewEnvironment()
}
