import SwiftUI

struct SettingsView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences

    @State private var showingDeleteConfirmation = false

    var body: some View {
        // Bindings are built by hand rather than with @Bindable because each
        // setter has to trigger a recompute, not just store a value.
        NavigationStack {
            Form {
                goalSection
                engineSection
                privacySection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete all sleep history?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    coordinator.deleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("""
                    This removes every night Zoon has stored on this device. \
                    Your data in the Health app is untouched — Zoon only ever reads from it.
                    """)
            }
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
                            // Score and sleep debt are both measured against the
                            // goal, so everything downstream needs recomputing.
                            coordinator.recomputeDerivedValues()
                        }
                    ),
                    in: 360...600,
                    step: 15
                )
            }
        } header: {
            Text("Sleep Goal")
        } footer: {
            Text("Your score and sleep debt are measured against this, not a population average.")
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

    /// The privacy pitch, stated plainly in the app rather than only in the
    /// README. This is the product's core claim; it should be legible to the
    /// person trusting it, not just to whoever reads the repo.
    private var privacySection: some View {
        Section {
            PrivacyRow(
                symbol: "wifi.slash",
                title: "No network calls",
                detail: "Zoon contains no networking code. Your sleep data cannot leave this device because there is nowhere for it to go."
            )
            PrivacyRow(
                symbol: "iphone",
                title: "Processed on device",
                detail: "Feature extraction and every insight are computed locally."
            )
            PrivacyRow(
                symbol: "eye.slash",
                title: "Read-only access",
                detail: "Zoon requests read permission only. It can never write to or modify your Health data."
            )
            PrivacyRow(
                symbol: "person.crop.circle.badge.xmark",
                title: "No account, no analytics",
                detail: "No sign-in, no telemetry, no third-party SDKs."
            )
        } header: {
            Text("Privacy")
        }
    }

    private var dataSection: some View {
        Section {
            LabeledContent("Nights stored", value: "\(coordinator.recentNights.count)")

            if let last = coordinator.lastRefresh {
                LabeledContent("Last updated") {
                    Text(last, format: .dateTime.hour().minute())
                }
            }

            Button("Refresh from Health") {
                Task { await coordinator.refresh() }
            }

            Button("Delete All Sleep History", role: .destructive) {
                showingDeleteConfirmation = true
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Deleting removes Zoon's local copy only. Health keeps the originals.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Widget data") {
                Text(AppGroup.isConfigured ? "Live" : "Sample only")
                    .foregroundStyle(AppGroup.isConfigured ? .green : .secondary)
            }
            Text(SleepInsight.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("About")
        } footer: {
            Text("“Zoon” means moon in Kashmiri.")
        }
    }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("Settings") {
    SettingsView()
        .zoonPreviewEnvironment()
}
