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

                BodyBatteryCard(
                    battery: context.bodyBattery,
                    workouts: coordinator.todayWorkouts.map(\.namedInterval)
                )
                .entrance(1)

                if let stress = coordinator.todayStress {
                    StressCard(stress: stress, todayStrain: context.strain.value).entrance(2)
                }

                loadCard.entrance(2)

                TodayWorkoutsCard(workouts: coordinator.todayWorkouts).entrance(3)

                // Directly under the workouts, because it is the other half
                // of the same day: that card is where effort went, this one
                // is where it did not. Renders nothing when the engine found
                // nothing, so an empty day shows no gap here.
                RestorativeWindowsCard(windows: coordinator.todayRestorativeWindows)
                    .entrance(3)

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
            sleepDebtMinutes: context.shortfallNowMinutes ?? 0,
            windDownHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil
        )
    }

    /// The one thing worth doing about today's load, or nothing.
    ///
    /// A light or moderate day needs no instruction -- a sheet that always
    /// ends with advice teaches people to stop reading the advice. Only the
    /// two bands that actually change tonight's sleep need say so, and the
    /// weak-zone case says the thing that would sharpen every future score.
    private var loadAction: String? {
        // The resting floor comes first. It is the weaker of the two
        // boundaries when it is missing -- it sits in both the numerator and
        // the denominator of every reserve fraction -- and it is the one the
        // person cannot fix from Settings, so the instruction has to be a
        // different one.
        if context.strain.restingProvenance == .genericFallback {
            return "Wear your watch overnight. Without a resting heart rate, your zones are drawn from a default rather than from you."
        }
        if context.strain.zoneProvenance == .genericFallback {
            return "Add your age in Settings so your zones stop resting on a default maximum heart rate."
        }
        switch context.strain.value {
        case 14...:
            return "Give tonight extra time in bed — a day this hard raises what your body needs to recover from it."
        case 10..<14:
            return "Protect your usual bedtime tonight; a strenuous day is the one most easily undone by a late one."
        default:
            return nil
        }
    }

    /// The two boundaries the zones were drawn between, named.
    ///
    /// Both are usually estimates and the score has no way to say which kind
    /// without this. `nil` for the active-energy fallback, which sorts
    /// nothing into zones and so has no boundaries to describe.
    private var zoneBasis: String? {
        guard let zones = context.strain.zoneProvenance,
              let resting = context.strain.restingProvenance
        else { return nil }
        return "Zones run from \(resting.label.lowercased()) up to \(zones.label.lowercased())."
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
                        .foregroundStyle(Theme.inkSecondary)
                }
                HStack(spacing: 4) {
                    Text(context.strain.band)
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.inkTertiary)
                    // Sparse coverage and guessed zone boundaries are
                    // different weaknesses; `confidenceTag` names whichever
                    // is binding rather than either going unsaid.
                    if let tag = context.strain.confidenceTag {
                        Text("· \(tag)")
                            .font(Theme.text(10))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    // Both weaknesses, in one word. A fully-sampled day
                    // sorted by a guessed ceiling is not a high-confidence
                    // number, and the tag alone did not say so.
                    Text("· \(context.strain.confidence.label)")
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.inkTertiary)
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
                ],
                // `confidenceNote` used to be appended to the prose above,
                // where it read as a third paragraph about the metric rather
                // than a caveat on today's number. It is the same sentence;
                // it now sits in the row that is labelled as the caveat.
                facets: MetricFacets(
                    confidence: context.strain.confidence,
                    confidenceReason: context.strain.confidenceNote,
                    baseline: zoneBasis,
                    action: loadAction
                )
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
                .foregroundStyle(Theme.inkSecondary)
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
                .foregroundStyle(Theme.inkSecondary)
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
