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
    /// Which recovery signal the reader has tapped in the hero ring.
    @State private var selectedSignalID: String?
    @State private var setup = PersonalSetupStore.shared

    private var scoreLight: Bool { setup.value.scoreLight }
    /// The band Today is drawing for.
    ///
    /// Was a computed `.current()`, which is correct whenever the body runs
    /// and never causes the body to run: leave the screen open at 16:59 and
    /// at 17:01 it still shows the day hero. State plus
    /// `refreshingOnPhaseBoundary` makes the change itself the invalidation,
    /// from the same `Band` the background uses -- one set of boundaries for
    /// the greeting, the hero, the cards and the gradient.
    @State private var moment: ZoonAmbientBackground.Band = .current()

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .stateTransition(stateKey)
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
            // The hero, greeting and card set all key off `moment`. Without
            // this the screen keeps drawing the band it opened in.
            .refreshingOnPhaseBoundary($moment)
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

    /// Which *kind* of state Today is in, with the payload deliberately
    /// dropped.
    ///
    /// The crossfade should fire when the screen becomes a different screen
    /// -- loading giving way to last night -- and never when a pull to
    /// refresh replaces one loaded context with another. Keying on the whole
    /// state would flash the entire page on every refresh.
    private var stateKey: String {
        switch coordinator.state {
        case .idle, .loading: "loading"
        case .loaded, .mock: "loaded"
        case .empty: "empty"
        case .failed: "failed"
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
                tonightCircleHero(context)
                    .entrance(0)

                let steps = tonightSteps(context)
                if !steps.isEmpty {
                    TonightPlanCardView(
                        steps: steps,
                        targetMinutes: autopilotPlan(context)?.targetSleepMinutes
                            ?? context.sleepNeed.totalNeedMinutes,
                        bedIn: plannedBedtime(context).map { $0.timeIntervalSinceNow }
                    )
                    .entrance(1)
                }

                // Actual against need, on one scale. The shortfall between
                // them is what the hero above is counting, so `TodayNeedTracks`
                // -- which draws a Debt bar of its own -- would be saying it
                // twice on this moment's screen.
                SleepMetricsView(
                    actualMinutes: context.night.total24hAsleepMinutes + napMinutesToday,
                    needMinutes: context.sleepNeed.totalNeedMinutes,
                    napMinutes: napMinutesToday
                )
                .entrance(2)

                TonightSection(context: context, autopilot: autopilotPlan(context))
                    .entrance(3)
                TravelTonightCard()
                    .entrance(3)
                NavigationLink {
                    ZoonTomorrowView()
                } label: {
                    tomorrowCard(context)
                }
                .buttonStyle(.plain)
                .entrance(4)
            } else if moment == .day && !scoreLight {
                daytimeHero(context).entrance(0)
            } else {
                TodayNightHero(context: context, greeting: greeting, scoreLight: scoreLight)
                    .entrance(0)
            }

            if moment != .evening && moment != .night {
                TodayNeedTracks(context: context, napMinutesToday: napMinutesToday)
                    .entrance(1)
            }

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
                MovementContextCard(
                    snapshot: MovementContext.snapshot(
                        stepsSoFar: nil,
                        typicalStepsByNow: nil,
                        weekday: Calendar.current.component(.weekday, from: .now)
                    )
                )
                .entrance(5)
            }

            if moment == .morning || moment == .day {
                TonightSection(context: context, autopilot: autopilotPlan(context))
                    .entrance(6)
                NavigationLink {
                    ZoonTomorrowView()
                } label: {
                    tomorrowCard(context)
                }
                .buttonStyle(.plain)
                .entrance(6)
            }

            if moment == .day {
                TravelTonightCard()
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

            if moment == .morning || moment == .day {
                NapsTodayCard(
                    napMinutesToday: napMinutesToday,
                    debtMinutes: context.night.sleepDebtMinutes ?? 0,
                    recommendation: napRecommendation(context)
                )
                .entrance(8)
            }

            // Last on Today, and only here.
            //
            // These are the only things in the app you *do* rather than
            // read, and they have now been in three places: buried at the
            // bottom of the Sleep tab, then leading Sleep and repeated on
            // Today, then Sleep alone. Bottom of Today is where they stay --
            // one home, on the screen that opens the app, after the reading
            // rather than in front of it.
            SleepToolsStrip().entrance(8)

            footer(context).entrance(9)
        }
    }

    // MARK: - Naps

    /// Nap minutes recorded today, from both the in-app timer and Health,
    /// read live rather than from a stored night.
    ///
    /// Nap credit is attributed to the calendar day before a wake, so a nap
    /// taken this afternoon belongs to tomorrow morning's record and does
    /// not exist until that night is written. Today's shortfall is a number
    /// about today, so it reads today's naps.
    private var napMinutesToday: Double {
        coordinator.napMinutesToday()
    }

    private func napRecommendation(_ context: DayContext) -> NapCoach.Recommendation {
        NapCoach.recommend(
            debtMinutes: max(0, context.night.sleepDebtMinutes ?? 0),
            plannedBedtime: plannedBedtime(context),
            napMinutesToday: napMinutesToday
        )
    }

    /// Tonight's target bedtime as a `Date`, which is what `NapCoach` needs
    /// to judge "is bedtime too close for this nap to be worth it".
    ///
    /// The plan stores minutes-from-midnight and wraps past 1440 for a
    /// bedtime after midnight, so the wrap decides the day: 23:10 is tonight,
    /// 00:40 is tomorrow. Resolving it against today's midnight alone would
    /// put an after-midnight bedtime in the past and make every nap look
    /// safe.
    private func plannedBedtime(_ context: DayContext) -> Date? {
        guard let minutes = autopilotPlan(context)?.targetBedtimeMinutes else { return nil }
        return PlannedBedtimeResolver.nextOccurrence(ofMinutesFromMidnight: minutes, after: .now)
    }

    // MARK: - Hero helpers

    private func daytimeHero(_ context: DayContext) -> some View {
        VStack(spacing: 16) {
            // Addresses the reader, and says what the number means before
            // showing it. "67%, Moderate" is a measurement; "your body needs
            // moderate output today" is the thing they opened the app for.
            Text(openingLine(context))
                .font(Theme.label(19, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // The ring says how much. The radar inside says in what shape --
            // whether the number came from everything being middling or from
            // three strong signals and one that collapsed.
            RecoveryRing(
                recovery: context.recovery,
                size: 236,
                lineWidth: 16,
                selectedSignalID: $selectedSignalID
            ) {
                // 190 inside a 236 ring, so a full-value vertex lands at
                // radius 95 -- inside the stroke's inner edge at 110. The
                // web crosses the centre type by design and is drawn pale
                // enough to sit under it; see RecoveryRadar.
                RecoveryRadar(
                    components: context.recovery.components,
                    size: 190,
                    selectedID: $selectedSignalID
                )
            }

            ScoreDrivers(components: context.recovery.components)

            TodayActionPlan(recovery: context.recovery, forecast: energyForecast(context))

            Text(context.recovery.confidence.label)
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkSecondary)
            RightNowLine(load: coordinator.todayStress)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Ishfaq, your body needs moderate output today." — or the same
    /// sentence without the name, when none has been set. The name is a
    /// local preference and empty is a real answer; nothing here nags for it
    /// or invents one.
    private func openingLine(_ context: DayContext) -> String {
        // The band is a reading of the same score the ring may be declining
        // to state. Saying "your body needs moderate output today" off a
        // score built from sleep duration alone is the same claim in prose.
        guard context.recovery.presentation.isShowable else {
            let name = preferences.displayName
            let line = "here is last night. Recovery needs more physiological data before it can call today."
            return name.isEmpty
                ? line.prefix(1).uppercased() + line.dropFirst()
                : "\(name), \(line)"
        }
        let body = switch context.recovery.band {
        case .high: "your body can take load today."
        case .moderate: "your body needs moderate output today."
        case .low: "your body is asking for a light day."
        }
        let name = preferences.displayName
        return name.isEmpty
            ? body.prefix(1).uppercased() + body.dropFirst()
            : "\(name), \(body)"
    }

    /// One construction, shared by the plan card and the energy section, so
    /// the window the plan names is the window the curve draws.
    private func tomorrowCard(_ context: DayContext) -> some View {
        let event = preferences.tomorrowEventEnabled
            ? ZoonTomorrow.Event(start: preferences.tomorrowEventDate(), isAllDay: false, source: .manual)
            : nil
        let plan = ZoonTomorrow.plan(
            event: event,
            nights: coordinator.recentNights,
            sleepNeedMinutes: context.sleepNeed.totalNeedMinutes,
            sleepDebtMinutes: context.night.sleepDebtMinutes ?? 0,
            napMinutesToday: napMinutesToday
        )
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tomorrow", systemImage: "sunrise.fill")
            if let plan {
                Text(plan.sentence)
                    .font(Theme.text(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HorizonStrip(
                    nodes: plan.nodes,
                    sleepWindowStart: plan.sleepWindowStart,
                    sleepWindowEnd: plan.sleepWindowEnd
                )
                Text(plan.caveat)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Name a morning start time and Zoon will arrange tonight around it.")
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityHint("Opens Tomorrow")
    }

    private func energyForecast(_ context: DayContext) -> EnergyForecast {
        EnergyForecast.compute(
            wakeTime: context.night.wakeTime,
            sleepDebtMinutes: context.night.sleepDebtMinutes ?? 0,
            windDownHour: (context.bodyClock?.isEstimate == false) ? context.bodyClock?.onsetHour : nil
        )
    }

    private func tonightCircleHero(_ context: DayContext) -> some View {
        let plan = autopilotPlan(context)
        return VStack(spacing: 18) {
            Text(greeting)
                .font(Theme.kicker)
                .foregroundStyle(Theme.inkSecondary)

            SleepDebtArcView(
                debtMinutes: max(0, (context.night.sleepDebtMinutes ?? 0) - napMinutesToday),
                weekChangeMinutes: weekChange(context),
                repaymentMinutes: plan?.debtRepaymentMinutes
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// Tonight's three steps, built from the plan the app already computes.
    ///
    /// Wind down is half an hour before the target bedtime -- the same
    /// half-hour `TonightSection` already talks about, given a place on the
    /// line rather than only a sentence.
    private func tonightSteps(_ context: DayContext) -> [TonightPlanCardView.Step] {
        guard let plan = autopilotPlan(context), let bed = plannedBedtime(context) else { return [] }
        let windDown = bed.addingTimeInterval(-30 * 60)
        let wake = bed.addingTimeInterval(plan.targetSleepMinutes * 60)

        var bedNote: String?
        if plan.debtRepaymentMinutes >= 1 {
            bedNote = "\(Int(plan.debtRepaymentMinutes.rounded())) minutes earlier than your habit, to start clearing the shortfall."
        } else if plan.isHolding {
            bedNote = "Where you already are — this target is holding, not correcting."
        }

        return [
            .init(kind: .windDown, time: windDown, note: nil),
            .init(kind: .bed, time: bed, note: bedNote),
            .init(kind: .wake, time: wake, note: nil)
        ]
    }

    /// Signed change in shortfall against the same weekday last week.
    ///
    /// Negative is an improvement. Takes the *delta* from one same-basis
    /// series rather than differencing two separately-computed figures --
    /// that mistake once put "improved by 24h 4m" on this screen.
    private func weekChange(_ context: DayContext) -> Double? {
        guard let weekAgo = debtWeekAgo(context) else { return nil }
        return (context.night.sleepDebtMinutes ?? 0) - weekAgo
    }

    /// Derived from `moment`, not from the clock.
    ///
    /// It used to read `Calendar.current.component(.hour,...)` on its own,
    /// which agreed with the hero by coincidence -- both read the same clock.
    /// Once `-zoonMoment` could pin the band for capture they disagreed, and
    /// the first day-band render greeted "Good evening" over a daytime hero.
    /// One source for both settles it, and the greeting now cannot drift
    /// from the screen it sits above.
    private var greeting: String {
        switch moment {
        case .morning: "Good morning"
        case .day: "Good afternoon"
        case .evening: "Good evening"
        case .night: "Good night"
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
                forecast: energyForecast(context),
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
    /// The debt figure from a week back, for the reservoir's trend line.
    ///
    /// Returned as `displayed debt − the change over the week`, not as the
    /// series' own value from seven nights ago. That distinction is the whole
    /// correctness of this function.
    ///
    /// `context.night.sleepDebtMinutes` — the number the arc displays — is
    /// computed from `total24hAsleepMinutes` against each night's own frozen
    /// `sleepNeedBaselineMinutes`, with decay. A series built any other way
    /// is on a different basis, and subtracting one from the other compares
    /// two things that were never the same measurement. The first render said
    /// "Improved by 24h 4m since last week" under a 1h 35m shortfall, which
    /// is what that mistake looks like from the outside.
    ///
    /// So the series is built with the same inputs the stored debt uses, and
    /// only its *delta* is taken — the part that is basis-independent — then
    /// applied to the displayed number. `debtMinutes − weekAgoMinutes` is
    /// then exactly the change the series measured, whatever the bases.
    ///
    /// Needs eight nights: below that there is no week to compare and the
    /// line stays hidden.
    private func debtWeekAgo(_ context: DayContext) -> Double? {
        let nights = coordinator.recentNights
        guard nights.count >= 8 else { return nil }
        let series = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: nights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: nights.map {
                $0.sleepNeedBaselineMinutes ?? preferences.sleepGoalMinutes
            }
        )
        guard let latest = series.last, series.count >= 8 else { return nil }
        let change = latest - series[series.count - 8]
        return (context.night.sleepDebtMinutes ?? 0) - change
    }

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
        .foregroundStyle(Theme.inkTertiary)
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


/// The one line on Today that is about *now* rather than about last night.
///
/// The ring above it is Morning Recovery: scored from the night that ended
/// and unchanged for the rest of the day. This used to be followed by
/// `StressScore.baselineContextNote` on its own -- a sentence about how the
/// *load* comparison was made, sitting directly under the *recovery* number,
/// with no label to say it had changed subject. Worse, the fallback when no
/// load score existed read "Based on last night's recovery; daytime change
/// appears when enough quiet data is available", which describes the morning
/// figure as though it were something that moves during the day. That is
/// exactly the conflation the naming work was meant to end.
///
/// So it says which is which. There is no fourth score here and deliberately
/// so: Zoon already has a verdict on the night (Morning Recovery), an
/// accounting curve for the day (Energy) and a live measurement against your
/// own waking baseline (Physiological Load). A "Readiness Now" number
/// recombining those three would be a new claim resting on no new evidence.
/// Composition, not invention.
private struct RightNowLine: View {

    let load: StressScore?

    var body: some View {
        VStack(spacing: 2) {
            if let load {
                Text("Right now: \(load.band.label.lowercased())")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(tint(load.band))
                Text(load.baselineContextNote)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
            } else {
                Text("Right now: not enough quiet daytime readings yet.")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Text(RecoveryPresentationState.timingNote)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func tint(_ band: StressScore.Band) -> Color {
        switch band {
        case .calm: Theme.Metric.recoveryHigh
        case .elevated: Theme.Metric.recoveryMid
        case .high: Theme.Metric.recoveryLow
        }
    }
}
