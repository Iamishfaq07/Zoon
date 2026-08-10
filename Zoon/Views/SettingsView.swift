import SwiftUI

/// Pushed from the More tab, so it supplies no `NavigationStack` of its own.
struct SettingsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps
    @Environment(BedtimeReminder.self) private var reminders

    @State private var showingDeleteConfirmation = false

    var body: some View {
        // Bindings are built by hand rather than with @Bindable because each
        // setter has to trigger a recompute, not just store a value.
        Form {
            goalSection
            remindersSection
            cycleSection
            profileSection
            engineSection
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
                coordinator.deleteAllData()
                naps.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                This removes every night, journal entry, and nap Zoon has stored on this device. \
                Your data in the Health app is untouched — Zoon only ever reads from it.
                """)
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

    /// Wind-down and bedtime notifications.
    ///
    /// The toggle requests permission on the way *on*, which is the only
    /// moment the request has context — an app that asks at launch, before
    /// showing what the notification is for, mostly gets denied permanently.
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
                Health Radar watches for.
                """)
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
                Strain and Body Battery. Nothing else reads it, and it never leaves the device.
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
                ForEach(UserPreferences.EngineChoice.allCases) { choice in
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
        } header: {
            Text("Insights")
        }
    }

    private var dataSection: some View {
        Section {
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
