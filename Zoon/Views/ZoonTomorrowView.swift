import SwiftUI

/// Big Day / Tomorrow — one horizon, one plan, no extra tab.
struct ZoonTomorrowView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps
    @State private var selectedID: String?

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

                timePicker
                calendarToggle
            }
            .padding(.horizontal)
            .padding(.bottom, 28)
        }
        .nightBackground()
        .navigationTitle("Tomorrow")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: preferences.calendarAccessEnabled) {
            guard preferences.calendarAccessEnabled else { return }
            if let commitment = await EventKitCommitmentReader.firstTomorrow() {
                preferences.setTomorrowEvent(date: commitment.start)
            }
        }
    }

    private var plan: ZoonTomorrow.Plan? {
        let event: ZoonTomorrow.Event?
        if preferences.tomorrowEventEnabled {
            event = ZoonTomorrow.Event(
                start: preferences.tomorrowEventDate(),
                isAllDay: false,
                source: .manual
            )
        } else {
            event = nil
        }
        return ZoonTomorrow.plan(
            event: event,
            nights: coordinator.recentNights,
            sleepNeedMinutes: coordinator.state.context?.sleepNeed.totalNeedMinutes ?? preferences.sleepGoalMinutes,
            sleepDebtMinutes: coordinator.state.context?.night.sleepDebtMinutes ?? 0,
            napMinutesToday: naps.minutes(on: .now)
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
        }
        .glassCard()
    }
}
