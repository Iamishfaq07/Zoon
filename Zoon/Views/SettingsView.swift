import SwiftUI

/// Pushed from the More tab, so it supplies no `NavigationStack` of its own.
struct SettingsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps
    @Environment(BedtimeReminder.self) private var reminders

    /// Its own instance rather than one shared with `RootView`: AlarmKit is
    /// still the real store of record for what's scheduled, and the one bit
    /// of derived state `WakeAlarm` does keep (`scheduledWakeTime`, for
    /// `alarmStatusDescription` below) is mirrored through `UserDefaults`,
    /// so a second instance here reads the same answer `RootView`'s last
    /// successful schedule wrote rather than disagreeing with it.
    @State private var wakeAlarm = WakeAlarm()

    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFailure = false

    var body: some View {
        // Bindings are built by hand rather than with @Bindable because each
        // setter has to trigger a recompute, not just store a value.
        Form {
            goalSection
            appearanceSection
            remindersSection
            obligationDaysSection
            cycleSection
            lifestyleInsightsSection
            trackedBehaviorsSection
            profileSection
            engineSection
            sourceSection
            dataSection
        }
        .scrollContentBackground(.hidden)
        .nightBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete all Zoon data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                showingDeleteFailure = !coordinator.deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                This removes every night, journal entry, and nap Zoon has stored on this device. \
                Your data in the Health app is untouched — Zoon only ever reads from it.
                """)
        }
        .alert("Some data could not be deleted", isPresented: $showingDeleteFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Zoon cleared every store it could, but one or more local files or database rows reported an error. Try again before uninstalling the app.")
        }
    }

    // MARK: - Sections

    private var goalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nightly goal")
                    Spacer()
                    Text(preferences.sleepGoalDisplay)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { preferences.sleepGoalMinutes },
                        set: { newValue in
                            preferences.sleepGoalMinutes = newValue
                            // Recovery, sleep need, score, and debt are all
                            // measured against the goal, so everything
                            // downstream needs recomputing.
                            Task { await coordinator.recomputeDerivedValues() }
                        }
                    ),
                    in: 360...600,
                    step: 15
                )
            }
        } header: {
            Text("Sleep Goal")
        } footer: {
            Text("Your recovery score, sleep need, and debt are all measured against this — not a population average.")
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: Binding(
                get: { preferences.appearance },
                set: { preferences.appearance = $0 }
            )) {
                ForEach(UserPreferences.AppearancePreference.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("Zoon was built dark-first for a bedroom screen. Light follows the same palette in daylight tones.")
        }
    }

    /// Wind-down and bedtime notifications.
    ///
    /// The toggle requests permission on the way *on*, which is the only
    /// moment the request has context — an app that asks at launch, before
    /// showing what the notification is for, mostly gets denied permanently.
    /// What to say under the "Ring an alarm" toggle -- the actual next
    /// scheduled time when there is one, not just a generic description of
    /// what the feature does regardless of whether anything is currently
    /// armed. `wakeAlarm.scheduledWakeTime` reflects the wake time
    /// `RootView`'s last successful `schedule(at:)` call actually set (see
    /// `WakeAlarm`'s doc comment), so this can go stale between opens the
    /// same way the real alarm can -- but it's a real reflection of what
    /// AlarmKit was last told, not a static string that never disagreed
    /// with reality because it never claimed anything about it.
    private var alarmStatusDescription: String {
        if let unavailabilityReason = wakeAlarm.unavailabilityReason {
            return unavailabilityReason
        }
        if preferences.wakeAlarmEnabled, let scheduledWakeTime = wakeAlarm.scheduledWakeTime {
            return "Rings around \(scheduledWakeTime.formatted(.dateTime.hour().minute())), "
                + "through Silent mode and Sleep Focus."
        }
        return "Sounds at the end of the window, through Silent mode and Sleep Focus."
    }

    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.bedtimeRemindersEnabled },
                set: { wantsOn in
                    Task {
                        if wantsOn {
                            let granted = await reminders.requestAuthorization()
                            // Only record it as on if iOS actually agreed.
                            // A switch that stays on while nothing is delivered
                            // is a lie the user finds out about a week later.
                            preferences.bedtimeRemindersEnabled = granted
                            if granted, let bedtime = coordinator.state.context?.targetBedtime() {
                                await reminders.schedule(bedtime: bedtime)
                            }
                        } else {
                            preferences.bedtimeRemindersEnabled = false
                            reminders.cancel()
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bedtime reminders")
                    Text("Wind-down nudge \(BedtimeReminder.windDownLeadMinutes) minutes ahead, then bedtime.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let bedtime = coordinator.state.context?.targetBedtime() {
                LabeledContent("Tonight") {
                    Text(bedtime, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(Theme.Metric.sleep)
                }
            }

            // `SleepFocusFilter` is only reachable through Settings → Focus →
            // (a Focus) → Add Filter, which almost nobody goes looking for. A
            // feature nobody can find may as well not exist, so it's named
            // here, beside the reminders it silences -- which is where someone
            // annoyed by a nudge during Sleep Focus would actually look.
            //
            // Shows live state rather than just advertising the capability,
            // because "why did my reminders stop?" is the other question this
            // section has to be able to answer.
            if preferences.bedtimeRemindersEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    Label(
                        preferences.focusSilencesBedtimeNudges
                            ? "Silenced by a Focus right now"
                            : "Works with Focus",
                        systemImage: preferences.focusSilencesBedtimeNudges
                            ? "moon.fill"
                            : "moon"
                    )
                    .font(Theme.label(13))
                    .foregroundStyle(
                        preferences.focusSilencesBedtimeNudges
                            ? Theme.Metric.sleep
                            : .primary
                    )

                    Text("Add Zoon as a filter to any Focus (Settings → Focus → Add Filter) and these nudges pause while it's on. Your wake alarm still sounds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: Binding(
                get: { preferences.smartWakeEnabled },
                set: { wantsOn in
                    Task {
                        if wantsOn {
                            let granted = await reminders.requestAuthorization()
                            preferences.smartWakeEnabled = granted
                        } else {
                            preferences.smartWakeEnabled = false
                            reminders.cancelWakeWindow()
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake window")
                    Text("Notifies within your usual wake window, not a live sleep-stage alarm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Nested under the wake window because it's a property *of* it --
            // the alarm rings at the end of the same window the notification
            // opens -- and hidden entirely when the window is off, where it
            // would have nothing to attach to.
            if preferences.smartWakeEnabled {
                Toggle(isOn: Binding(
                    get: { preferences.wakeAlarmEnabled },
                    set: { wantsOn in
                        Task {
                            if wantsOn {
                                preferences.wakeAlarmEnabled = await wakeAlarm.requestAuthorization()
                            } else {
                                preferences.wakeAlarmEnabled = false
                                wakeAlarm.cancel()
                            }
                        }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ring an alarm")
                        Text(alarmStatusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!wakeAlarm.isAvailable)
            }

            if reminders.authorization == .denied {
                Label(reminders.statusDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Metric.recoveryMid)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("""
                Scheduled on this device. Zoon has no push notifications and no server, \
                so nothing about your sleep leaves the phone to deliver these. The time \
                moves with your sleep debt, so it is re-armed each time you open the app.
                """)
        }
    }

    /// Which days count as "obligation" days -- work, school, or any other
    /// fixed commitment -- for Sleep Regularity's work/free split and Cause
    /// Finder's weekend/weekday matched-pair constraint. Defaults to the
    /// standard Mon-Fri workweek; anyone on a different schedule (a
    /// four-day week, weekend shifts) can correct it here instead of both
    /// features silently assuming Saturday and Sunday are free.
    private var obligationDaysSection: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    dayToggle(weekday)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Obligation days")
        } footer: {
            Text("The days you have a fixed commitment on. Everything else is treated as a free day when Zoon looks at your schedule's regularity.")
        }
    }

    private func dayToggle(_ weekday: Int) -> some View {
        let calendar = Calendar.current
        let symbol = calendar.veryShortWeekdaySymbols[weekday - 1]
        let isObligation = preferences.obligationWeekdays.contains(weekday)
        return Button {
            var updated = preferences.obligationWeekdays
            if isObligation {
                updated.remove(weekday)
            } else {
                updated.insert(weekday)
            }
            // Never allow every day to become a free day -- Social jetlag
            // and the work/free split both need at least one of each to
            // mean anything, and an accidental empty selection would
            // silently disable them rather than error.
            guard !updated.isEmpty, updated.count < 7 else { return }
            preferences.obligationWeekdays = updated
        } label: {
            Text(symbol)
                .font(Theme.label(13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    isObligation ? Theme.Metric.sleep.opacity(0.25) : Theme.neutral(0.06),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .foregroundStyle(isObligation ? Theme.Metric.sleep : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
        .accessibilityValue(isObligation ? "Obligation day" : "Free day")
        .accessibilityAddTraits(isObligation ? [.isSelected] : [])
    }

    /// Off by default, and asks for its own separate HealthKit permission the
    /// moment it's turned on — see `HealthKitManager.requestCycleTrackingAuthorization`.
    /// Reproductive health data doesn't belong in the same blanket prompt every
    /// other read type shares, even though it's technically readable there.
    private var cycleSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.cycleTrackingEnabled },
                set: { wantsOn in
                    preferences.cycleTrackingEnabled = wantsOn
                    Task {
                        if wantsOn {
                            await coordinator.enableCycleTracking()
                        } else {
                            coordinator.disableCycleTracking()
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle tracking")
                    Text("Correlates recovery and sleep with your cycle phase.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Cycle")
        } footer: {
            Text("""
                Off by default. Turning this on asks Health for your logged period \
                dates specifically — a separate permission from everything else Zoon \
                reads. Useful because a normal luteal-phase shift in HRV and resting \
                heart rate can otherwise look identical to the illness-drift pattern \
                Body Signals watches for.
                """)
        }
    }

    /// Off by default, and asks for its own separate HealthKit permission the
    /// moment it's turned on — see
    /// `HealthKitManager.requestLifestyleInsightsAuthorization`. Caffeine,
    /// alcohol, daylight, and mindfulness are measured signals the Journal
    /// currently only has manual tags for; this reads them directly when
    /// available, alongside (not instead of) manual tagging.
    private var lifestyleInsightsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.lifestyleInsightsEnabled },
                set: { wantsOn in
                    preferences.lifestyleInsightsEnabled = wantsOn
                    Task {
                        if wantsOn {
                            await coordinator.enableLifestyleInsights()
                        } else {
                            coordinator.disableLifestyleInsights()
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifestyle Insights")
                    Text("Reads measured caffeine, alcohol, daylight, and mindfulness from Health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Lifestyle Insights")
        } footer: {
            Text("""
                Off by default. Turning this on asks Health for caffeine, alcohol, \
                time in daylight, and Mindfulness sessions — a separate permission \
                from everything else Zoon reads. Shown alongside your Journal tags \
                as measured reference, not a replacement for them.
                """)
        }
    }

    /// A NavigationLink rather than an inline section: ~22 tags across four
    /// categories doesn't fit a `Form` row without either overwhelming
    /// Settings or being cut off, and this is a "set once, rarely revisit"
    /// choice anyway -- the same reasoning `AlgorithmTransparencyView` gets
    /// its own screen instead of an inline explainer.
    private var trackedBehaviorsSection: some View {
        Section {
            NavigationLink("Tracked Behaviours") {
                TrackedBehaviorsView()
            }
        } footer: {
            Text("Choose which behaviours the Journal asks about each day. Everything is tracked until you narrow it down.")
        }
    }

    private var profileSection: some View {
        Section {
            Picker(
                "Age",
                selection: Binding(
                    get: { preferences.age ?? 0 },
                    set: { newValue in
                        preferences.age = newValue > 0 ? newValue : nil
                        Task { await coordinator.recomputeDerivedValues() }
                    }
                )
            ) {
                Text("Not set").tag(0)
                ForEach(16...90, id: \.self) { age in
                    Text("\(age)").tag(age)
                }
            }
        } header: {
            Text("Profile")
        } footer: {
            Text("""
                Used only to estimate your maximum heart rate, which sets the zones behind \
                Daily Load and Energy Reserve. Nothing else reads it, and it never leaves the device.
                """)
        }
    }

    private var engineSection: some View {
        Section {
            Picker(
                "Insight engine",
                selection: Binding(
                    get: { preferences.preferredEngine },
                    set: { coordinator.setEngine($0) }
                )
            ) {
                ForEach(UserPreferences.EngineChoice.shippingCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            Text(preferences.preferredEngine.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Apple Intelligence can be selected, report itself `.available`,
            // and still fall back silently every single night if generation
            // throws or the model's own safety guardrail rejects the prompt.
            // Without this, that reads as "the toggle doesn't do anything" --
            // there is otherwise no way to see why short of a Mac and Console.
            if preferences.preferredEngine == .appleIntelligence,
               let reason = FoundationModelDiagnostics.shared.lastFailureReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Theme.Metric.recoveryLow)
            }

            // Not a third picker option -- see `EngineChoice.shippingCases`.
            // `LocalLLMInsightEngine` always falls back to rules today, so
            // letting it sit in the same list as two real choices would read
            // as a real one. This row says plainly what it is instead of
            // hiding it entirely.
            HStack {
                Label("Bundled on-device model", systemImage: "flask")
                Spacer()
                Text("Labs").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Bundled on-device model, in Labs, not yet available")

            NavigationLink("How your Sleep Intelligence score works") {
                AlgorithmTransparencyView()
            }
            .font(.caption)
        } header: {
            Text("Insights")
        } footer: {
            Text("A bundled on-device model is still in Labs -- no model ships yet, so it isn't offered as a selectable engine.")
        }
    }

    /// Only shown once there's more than one known source -- a picker with
    /// one option (or none yet) has nothing to choose between.
    @ViewBuilder
    private var sourceSection: some View {
        let sources = coordinator.knownSleepSources()
        if sources.count > 1 {
            Section {
                Picker("Preferred source", selection: Binding(
                    get: { preferences.preferredSleepSourceName ?? "" },
                    set: { newValue in
                        preferences.preferredSleepSourceName = newValue.isEmpty ? nil : newValue
                        // Written alongside the name -- see
                        // `SleepSessionBuilder.preferredSourceBundleIdentifier`'s
                        // doc comment for why matching by this instead of
                        // the name alone is worth doing. `nil` for a source
                        // whose stored nights all predate the column; the
                        // name-based fallback still makes the choice work
                        // until a re-sync backfills it.
                        preferences.preferredSleepSourceBundleIdentifier =
                            sources.first { $0.name == newValue }?.bundleIdentifier
                        // The picked source only takes effect for nights
                        // processed from here on -- force a full re-sync so
                        // it also applies to what's already stored, the same
                        // way restoring a backup does.
                        AnchorStore.clear()
                        Task { await coordinator.refresh() }
                    }
                )) {
                    Text("Automatic").tag("")
                    ForEach(sources, id: \.name) { source in
                        Text(source.name).tag(source.name)
                    }
                }
            } header: {
                Text("Sleep Source")
            } footer: {
                Text("""
                    When more than one source reports sleep for the same night, Zoon picks \
                    whichever has the richest data automatically. Choose one here to always \
                    prefer it instead.
                    """)
            }
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink("Data Quality") {
                DataQualityView()
            }
            LabeledContent("Nights recorded", value: "\(coordinator.recentNights.count)")
            LabeledContent("Naps logged", value: "\(naps.naps.count)")

            if let last = coordinator.lastRefresh {
                LabeledContent("Last updated") {
                    Text(last, format: .dateTime.hour().minute())
                }
            }

            LabeledContent("Widget data") {
                Text(AppGroup.isConfigured ? "Live" : "Sample only")
                    .foregroundStyle(AppGroup.isConfigured ? .green : .secondary)
            }

            NavigationLink {
                DataPrivacyView()
            } label: {
                Label("Data Quality & Privacy", systemImage: "checkmark.shield")
            }

            Button("Refresh from Health") {
                Task { await coordinator.refresh() }
            }

            Button("Delete All Data", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Deleting removes Zoon's local copy only. Health keeps the originals.")
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .zoonPreviewEnvironment()
}
