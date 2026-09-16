import SwiftUI

/// Big Day / Tomorrow — one horizon, one plan, no extra tab.
struct ZoonTomorrowView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps
    @State private var selectedID: String?
    /// Read live when the screen appears and never persisted: one dated
    /// stored record with expiry semantics is the model, and a second store
    /// keyed by day would be a second thing that can go stale.
    @State private var horizonCommitments: [Date: Date] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                if let plan {
                    Text(plan.sentence)
                        .font(Theme.text(22, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    HorizonStrip(
                        nodes: plan.nodes,
                        sleepWindowStart: plan.sleepWindowStart,
                        sleepWindowEnd: plan.sleepWindowEnd,
                        selectedID: selectedID
                    ) { node in
                        selectedID = node.id
                    }
                    .padding(.vertical, 8)

                    if let node = plan.nodes.first(where: { $0.id == selectedID }) {
                        Text(node.detail)
                            .font(Theme.text(15))
                            .foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(plan.why, id: \.self) { line in
                            Text(line)
                                .font(Theme.text(15))
                                .foregroundStyle(Theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    LabeledContent("Confidence", value: plan.confidence.label)

                    Text(plan.caveat)
                        .font(Theme.evidence)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ZoonEmptyState(
                        kind: .noData(
                            title: "No plan yet",
                            message: "Zoon needs a sleep need before it can arrange tonight around tomorrow.",
                            unlocks: ["Sleep need", "A morning start time"]
                        )
                    )
                }

                if let plan {
                    WhatIfTonightCard(
                        plan: plan,
                        needMinutes: coordinator.state.context?.sleepNeed.totalNeedMinutes
                            ?? preferences.sleepGoalMinutes,
                        shortfallMinutes: coordinator.state.context?.night.sleepDebtMinutes ?? 0,
                        napMinutesToday: naps.minutes(on: .now)
                    )
                }

                if let runway {
                    SleepRunwayCard(plan: runway)
                }

                timePicker
                readyBuffer
                calendarToggle
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Tomorrow")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: preferences.calendarAccessEnabled) {
            guard preferences.calendarAccessEnabled else {
                // Switching Calendar off forgets the borrowed fact. The
                // manual time is the person's own and stays.
                preferences.forgetCalendarCommitment()
                horizonCommitments = [:]
                return
            }
            horizonCommitments = await EventKitCommitmentReader.mornings(
                through: SleepRunway.horizonDays
            )
            switch await EventKitCommitmentReader.firstTomorrow() {
            case let .read(commitment):
                // Including `nil`. "Nothing tomorrow" is an answer, and
                // recording it is what stops yesterday's meeting surviving
                // into a day it was never on.
                preferences.recordCalendarRead(commitment)
            case .unavailable:
                // Permission withdrawn or EventKit unreachable. Zoon did not
                // look, so it may not assert what it last saw either.
                preferences.forgetCalendarCommitment()
            }
        }
    }

    private var commitment: CommitmentResolver.Outcome { preferences.commitment() }

    /// The week ahead. Tomorrow answers one night; this answers where the
    /// schedule stops leaving room, while there is still time to move
    /// something.
    private var runway: SleepRunway.Plan? {
        SleepRunway.build(
            nights: coordinator.recentNights,
            sleepNeedMinutes: coordinator.state.context?.sleepNeed.totalNeedMinutes ?? preferences.sleepGoalMinutes,
            sleepDebtMinutes: coordinator.state.context?.night.sleepDebtMinutes ?? 0,
            commitments: horizonCommitments,
            manual: preferences.manualCommitment,
            obligationWeekdays: preferences.obligationWeekdays,
            readyBufferMinutes: preferences.morningReadyBufferMinutes
        )
    }

    private var plan: ZoonTomorrow.Plan? {
        ZoonTomorrow.plan(
            event: commitment.event,
            nights: coordinator.recentNights,
            sleepNeedMinutes: coordinator.state.context?.sleepNeed.totalNeedMinutes ?? preferences.sleepGoalMinutes,
            sleepDebtMinutes: coordinator.state.context?.night.sleepDebtMinutes ?? 0,
            napMinutesToday: naps.minutes(on: .now),
            readyBufferMinutes: preferences.morningReadyBufferMinutes
        )
    }

    private var timePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "I need to be sharp at", systemImage: "alarm")
            DatePicker(
                "Start time",
                selection: Binding(
                    get: { preferences.tomorrowEventDate() },
                    set: { preferences.setTomorrowEvent(date: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .onChange(of: preferences.tomorrowHour) { _, _ in Haptics.select() }
            Toggle("Protect this time tomorrow", isOn: Binding(
                get: { preferences.tomorrowEventEnabled },
                set: { preferences.tomorrowEventEnabled = $0 }
            ))
        }
        .glassCard()
    }

    /// Getting-ready time, which used to be a fifty-minute constant inside
    /// the planner. It is a fact about this person's morning — commute,
    /// shower, children — not about physiology, so it is theirs to set.
    private var readyBuffer: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Getting ready takes me", systemImage: "figure.walk")
            Stepper(
                value: Binding(
                    get: { preferences.morningReadyBufferMinutes },
                    set: { preferences.morningReadyBufferMinutes = $0 }
                ),
                in: ZoonTomorrow.readyBufferRange,
                step: 5
            ) {
                Text(preferences.morningReadyBufferMinutes < 1
                     ? "No time needed"
                     : SleepNightFeatures.formatMinutes(preferences.morningReadyBufferMinutes))
                    .font(Theme.numeral(20))
                    .monospacedDigit()
            }
            .onChange(of: preferences.morningReadyBufferMinutes) { _, _ in Haptics.select() }
            Text("Zoon wakes you this long before the commitment. It is your estimate, not a physiological constant.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .glassCard()
    }

    private var calendarToggle: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Calendar", systemImage: "calendar")
            Toggle("Use tomorrow's first commitment", isOn: Binding(
                get: { preferences.calendarAccessEnabled },
                set: { preferences.calendarAccessEnabled = $0 }
            ))
            Text("Optional. Zoon only reads the start time of tomorrow's first morning event. Titles, people and locations are not stored.")
                .font(Theme.evidence)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if preferences.calendarAccessEnabled {
                Text(calendarStatus)
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    /// What Zoon currently holds from Calendar, in words.
    ///
    /// Worth showing because the interesting state is the empty one: a person
    /// who sees "no qualifying event" understands why the plan fell back to
    /// their own time, where silence would read as Zoon having ignored the
    /// calendar.
    private var calendarStatus: String {
        guard case let .calendar(event) = commitment else {
            return preferences.calendarCommitmentRecord == nil
                ? "No qualifying morning event found for tomorrow. Tonight's plan is using the time you set."
                : "The last event Zoon read no longer applies to tomorrow, so it is not being used."
        }
        return "Using tomorrow's first commitment at \(event.start.formatted(date: .omitted, time: .shortened))."
    }
}
