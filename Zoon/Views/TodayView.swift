import SwiftUI
import UIKit

/// The morning screen, V8: one question -- *how am I today?* -- answered in
/// the first screenful, with everything else one tap deeper.
///
/// Reads top to bottom as a story rather than a stack of cards:
///
/// 1. **Hero** -- greeting, the Sleep Intelligence orbit, last night's
///    duration, and Sleep / Need / Debt in one typographic row. No card.
/// 2. **Health Pulse** -- four domain glances between two hairlines.
/// 3. **Morning Brief** -- one insight, one action, "Why?" on demand.
/// 4. **Worth noticing** -- the single most notable conditional item, or
///    nothing at all on an ordinary day.
/// 5. **Energy Horizon** -- one scrubbable curve for the day ahead.
/// 6. **Tonight** -- the plan as a timeline with the autopilot folded in.
/// 7. **Check-in** -- the one remaining card, because it is an input.
///
/// Fourteen cards became one. Every value shown still comes from
/// `DayContext`; every card that left this screen is reachable from the
/// thing that replaced it (see `docs/V8-UI-AUDIT.md` for the map):
///
/// - `SleepSummaryStrip` leads the Sleep tab; it was a duplicate here.
/// - `BedtimeCountdownCard`, `TonightTimelineCard`, `AutopilotCard` are
///   folded into `TonightSection`.
/// - `EnergyForecastCard`, `BodyBatteryCard`, the Daily Load row,
///   `TodayWorkoutsCard`, `LightCoachCard` live in `EnergyDetailView`.
/// - `StressCard`, `HealthRadarCard`, `RecoveryModeCard`,
///   `PersonalizationProgressCard` are ranked by `WorthNoticing`.
/// - `InsightCard`, the brief card and `WhyScoreWaterfall` are `MorningBrief`.
/// - `FloatingMetricCluster` is the typographic Sleep / Need / Debt row.
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
    @State private var selectedComponentID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal)
                    .padding(.bottom, 28)
            }
            .nightBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .zoonGlobalToolbar()
            .refreshable { await coordinator.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.state {
        case .idle, .loading:
            ZoonLoadingState(title: "Reading last night…")
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
            if coordinator.recentNights.count <= 1 {
                FirstNightCard(night: context.night).entrance(0)
            } else {
                hero(context)
                HealthPulseStrip(context: context, recentNights: coordinator.recentNights)
                    .entrance(2)
                MorningBrief(context: context)
                    .entrance(3)
            }

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
                onTurnOffRecoveryMode: { preferences.setRecoveryModeEnabledToday(false) }
            )
            .entrance(4)

            energySection(context).entrance(5)

            TonightSection(context: context, autopilot: autopilotPlan(context))
                .entrance(6)

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

            footer(context).entrance(8)
        }
    }

    // MARK: - Hero

    /// Greeting → orbit → duration → legend → Sleep / Need / Debt. Full width,
    /// no card. The orbit and its legend share `selectedComponentID` so a chip
    /// tap highlights the arc and a scrub highlights the chip.
    private func hero(_ context: DayContext) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                if context.isMock {
                    StatusPill(text: "Sample data", systemImage: "wand.and.stars", tint: Theme.Family.sleep)
                }
                Text(greeting)
                    .font(Theme.label(15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .entrance(0)

            LunarOrbit(score: context.sleepIntelligence, selectedID: $selectedComponentID)
                .entrance(1)

            VStack(spacing: 4) {
                Text("\(context.night.formattedTimeAsleep) asleep")
                    .font(Theme.label(15, weight: .medium))
                Text("\(context.sleepIntelligence.confidence.label) · \(context.sleepIntelligence.dataCompletenessPercent)% data coverage")
                    .font(Theme.evidence)
                    .foregroundStyle(.tertiary)
            }
            .entrance(2)

            LunarOrbitLegend(score: context.sleepIntelligence, selectedID: $selectedComponentID)
                .entrance(2)

            sleepNeedDebtRow(context)
                .entrance(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Good night"
        }
    }

    /// The three numbers that used to be `FloatingMetricCluster`'s glass
    /// pills, as a typographic row with the same three destinations.
    private func sleepNeedDebtRow(_ context: DayContext) -> some View {
        let debt = context.night.sleepDebtMinutes ?? 0
        return ZoonMetricRow<AnyView>(items: [
            .init(
                id: "sleep", label: "Sleep",
                value: SleepNightFeatures.formatMinutes(context.night.timeAsleepMinutes),
                tint: Theme.Family.sleep,
                destination: { AnyView(SleepDetailView(context: context)) }
            ),
            .init(
                id: "need", label: "Need",
                value: SleepNightFeatures.formatMinutes(context.sleepNeed.totalNeedMinutes),
                destination: { AnyView(SleepNeedView()) }
            ),
            .init(
                id: "debt", label: "Debt",
                value: debt > 1 ? SleepNightFeatures.formatMinutes(debt) : "None",
                tint: debt > 1 ? Theme.Family.attention : Theme.Family.recovery,
                destination: { AnyView(SleepDebtView()) }
            )
        ])
        .padding(.top, 6)
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
