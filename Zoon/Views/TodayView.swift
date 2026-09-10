import SwiftUI
import UIKit

/// The morning screen: last night, in one look.
///
/// 1. **Hero** -- night sky, waxing crescent, asleep vs need as a ring.
///    Tap the moon for stages. Same moon as first-run and the home icon.
/// 2. **Tracks** -- Sleep / Need / Debt as filled bars, each a destination.
/// 3. **Morning brief** -- always on the page, not hidden behind a toggle.
/// 4. **Worth noticing** -- only when something actually moved.
/// 5. **Energy** -- scrubbable curve with a now marker.
/// 6. **Tonight** -- one timeline. No second "Prepare for tonight" button.
/// 7. **Check-in** -- how last night felt.
///
/// Score-light mode (Settings) hides the intelligence ring and the pulse
/// strip so Today stays duration, need, debt, and the brief.
struct TodayView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    // Owned locally rather than read fresh from `coordinator.journal` on
    // every render: a tap saved through the store and re-fetched wouldn't
    // reliably trigger a SwiftUI update on its own -- same reasoning as
    // JournalView's `answers`, see that type's doc comment.
    @State private var checkInFeeling: MorningFeeling?
    @State private var checkInDetails: [CheckInDimension: Int] = [:]
    /// Shared between the orbit and its legend so either can drive selection.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedComponentID: String?
    @State private var showsExplanation = false
    @State private var setup = PersonalSetupStore.shared

    private var scoreLight: Bool { setup.value.scoreLight }
    private var moment: ZoonAmbientBackground.Band { .current() }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal)
                    .padding(.bottom, 28)
            }
            .zoonTypography()
            .background { todayBackdrop }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .zoonGlobalToolbar()
            .refreshable { await coordinator.refresh() }
        }
    }

    @ViewBuilder
    private var todayBackdrop: some View {
        ZoonAmbientBackground()
            .overlay {
                if moment == .night {
                    NightSky(starCount: 40).opacity(0.45).allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .idle, .loading:
            ZoonLoadingState(title: "Gathering last night")
        case let .loaded(context), let .mock(context):
            loadedContent(context)
        case let .empty(reason):
            emptyState(reason)
        case let .failed(message):
            ZoonEmptyState(
                kind: .failed(title: "Couldn't read your sleep", message: message),
                primaryAction: ("Try Again", { Task { await coordinator.refresh() } })
            )
        }
    }

    private func emptyState(_ reason: SleepDataCoordinator.EmptyReason) -> some View {
        ZoonEmptyState(
            kind: .noData(
                title: reason.title,
                message: reason.message,
                unlocks: [
                    "Sleep Intelligence and last night's story",
                    "Body clock, energy and tonight's plan",
                    "Recovery and body signals against your own baseline"
                ]
            ),
            primaryAction: reason == .noSleepData
                ? ("Open Health Access", {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                })
                : nil,
            secondaryAction: ("Check again", { Task { await coordinator.refresh() } })
        )
    }

    // MARK: - Loaded

    private func loadedContent(_ context: DayContext) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            if moment == .evening || moment == .night {
                TonightSection(context: context, autopilot: autopilotPlan(context))
                    .entrance(0)
            } else if moment == .day && !scoreLight {
                daytimeHero(context).entrance(0)
            } else {
                TodayNightHero(context: context, greeting: greeting, scoreLight: scoreLight)
                    .entrance(0)
            }

            TodayNeedTracks(context: context)
                .entrance(1)

            if moment == .morning {
                MorningBrief(context: context)
                    .entrance(2)
            }

            if !scoreLight && (moment == .morning || moment == .day) {
                Button {
                    Haptics.select()
                    withAnimation(Motion.respecting(reduceMotion, Motion.standard)) {
                        showsExplanation.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(showsExplanation ? "Hide the breakdown" : "Explore why")
                        Image(systemName: showsExplanation ? "chevron.up" : "chevron.down")
                            .font(Theme.text(10, weight: .semibold))
                    }
                    .font(Theme.label(13, weight: .semibold))
                    .foregroundStyle(Theme.Family.sleep)
                }
                .buttonStyle(.plain)
            }

            if showsExplanation && !scoreLight && (moment == .morning || moment == .day) {
                LunarOrbit(
                    score: context.sleepIntelligence,
                    selectedID: $selectedComponentID,
                    showsComponents: true
                )
                .entrance(3)
                LunarOrbitLegend(score: context.sleepIntelligence, selectedID: $selectedComponentID)
                HealthPulseStrip(context: context, recentNights: coordinator.recentNights)
                    .entrance(3)
            }

            if moment != .night {
                WorthNoticing(
                context: context,
                stress: coordinator.todayStress,
                recoveryMode: RecoveryMode.evaluate(
                    band: context.recovery.band,
                    manuallyEnabledToday: preferences.isRecoveryModeManuallyEnabledToday
                ),
                lightGuidance: LightCoach.guidance(
                    wakeTime: context.night.wakeTime,
                    onsetHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil,
                    todayDaylightMinutes: preferences.lifestyleInsightsEnabled
                        ? coordinator.todayLifestyleInsights?.daylightMinutes : nil
                ),
                nightsTracked: coordinator.recentNights.count,
                taggedNights: coordinator.journal.taggedNightCount(),
                proactiveItems: PersonalLearning.proactiveItems(
                    nights: coordinator.recentNights,
                    radar: context.healthRadar
                ),
                onTurnOffRecoveryMode: { preferences.setRecoveryModeEnabledToday(false) }
                )
                .entrance(4)
            }

            if moment == .day {
                energySection(context).entrance(5)
            }

            if moment == .morning || moment == .day {
                TonightSection(context: context, autopilot: autopilotPlan(context))
                    .entrance(6)
            }

            if moment == .morning {
                MorningCheckInCard(
                selected: checkInFeeling,
                details: checkInDetails,
                onSelectFeeling: { feeling in
                    Haptics.select()
                    checkInFeeling = feeling
                    coordinator.journal.setFeeling(feeling, on: context.night.date, nightKey: context.night.nightKey)
                },
                onSelectDetail: { dimension, value in
                    checkInDetails[dimension] = value
                    coordinator.journal.setCheckIn(dimension, value: value, on: context.night.date, nightKey: context.night.nightKey)
                }
            )
                .entrance(7)
                .task(id: context.night.date) {
                let entry = coordinator.journal.entry(forNightKey: context.night.nightKey, fallbackDate: context.night.date)
                checkInFeeling = entry?.feeling
                checkInDetails = CheckInDimension.allCases.reduce(into: [:]) { result, dimension in
                    result[dimension] = entry?.value(for: dimension)
                }
                }
            }

            if moment == .morning || moment == .day {
                ShareLastNightButton(
                    night: context.night,
                    line: context.insight.summary
                )
                .entrance(8)
            }

            footer(context).entrance(8)
        }
    }

    // MARK: - Hero helpers

    private func daytimeHero(_ context: DayContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting).font(Theme.kicker).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(context.recovery.percent)")
                    .font(Theme.numeral(52))
                    .monospacedDigit()
                    .foregroundStyle(Theme.recoveryColor(Double(context.recovery.percent)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capacity now").font(Theme.label(18, weight: .semibold))
                    Text("\(context.recovery.band.label) recovery · \(context.recovery.confidence.label)")
                        .font(Theme.text(12)).foregroundStyle(.secondary)
                }
            }
            Text(coordinator.todayStress?.baselineContextNote ?? "Based on last night's recovery; daytime change appears when enough quiet data is available.")
                .font(Theme.evidence).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    // MARK: - Energy

    private func energySection(_ context: DayContext) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZoonSectionHeader("Today's energy") {
                NavigationLink {
                    EnergyDetailView(context: context)
                } label: {
                    HStack(spacing: 3) {
                        Text("Details")
                        Image(systemName: "chevron.right").font(Theme.text(10, weight: .semibold))
                    }
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.Family.sleep)
                }
                .buttonStyle(.plain)
            }
            EnergyHorizon(
                forecast: EnergyForecast.compute(
                    wakeTime: context.night.wakeTime,
                    sleepDebtMinutes: context.night.sleepDebtMinutes ?? 0,
                    windDownHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil
                ),
                battery: context.bodyBattery,
                targetBedtime: context.targetBedtime()
            )
        }
    }

    // MARK: - Tonight

    /// Tonight's autopilot plan, or `nil` when there is too little history.
    ///
    /// Written as a method rather than inline in the body so the optional
    /// wake time has somewhere to land: `bodyClock?.window(for:)?.end` is a
    /// non-optional `Date` *inside* the chain, so mapping it there applies
    /// `map` to `Date` rather than to `Date?`.
    private func autopilotPlan(_ context: DayContext) -> SleepAutopilot.Plan? {
        let obligationWake: Date? = context.bodyClock?.window(for: .now)?.end
        return SleepAutopilot.plan(
            nights: coordinator.recentNights,
            sleepNeedMinutes: context.learnedSleepNeed.minutes,
            obligationWakeMinutes: obligationWake.map {
                Statistics.circularMinutesFromMidnight($0)
            },
            sleepDebtMinutes: context.sleepNeed.debtMinutes
        )
    }

    // MARK: - Footer

    private func footer(_ context: DayContext) -> some View {
        VStack(spacing: 6) {
            // The manual Recovery Mode switch used to be its own row near the
            // top of the screen. It's a rarely-used override, so it lives
            // with the other provenance lines at the bottom -- still one tap.
            if RecoveryMode.evaluate(
                band: context.recovery.band,
                manuallyEnabledToday: preferences.isRecoveryModeManuallyEnabledToday
            ) == nil {
                RecoveryModeEnableLink { preferences.setRecoveryModeEnabledToday(true) }
            }
            if let source = context.night.sourceName {
                // "Sleep source", not "Source": this names which HealthKit
                // source the sleep-*stage* samples came from (see
                // SleepNightFeatures.sourceName), not a claim that every
                // vital on screen came from the same device.
                Text("Sleep source: \(source)")
            }
            if let last = coordinator.lastRefresh {
                Text("Updated \(last, format: .dateTime.hour().minute())")
            }
        }
        .font(Theme.text(10))
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

#Preview("Today") {
    TodayView().zoonPreviewEnvironment()
}

#Preview("Today - light") {
    TodayView().zoonPreviewEnvironment().preferredColorScheme(.light)
}

#Preview("Today - large text") {
    TodayView().zoonPreviewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
