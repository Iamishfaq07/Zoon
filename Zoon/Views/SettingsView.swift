import SwiftUI

/// Pushed from the More tab, so it supplies no `NavigationStack` of its own.
struct SettingsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps

    @State private var showingDeleteConfirmation = false

    var body: some View {
        // Bindings are built by hand rather than with @Bindable because each
        // setter has to trigger a recompute, not just store a value.
        Form {
            goalSection
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
