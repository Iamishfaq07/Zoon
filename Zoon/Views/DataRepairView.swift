import SwiftUI

struct DataRepairView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @State private var setup = PersonalSetupStore.shared
    @State private var candidate: SleepNightFeatures?
    @State private var reason = "Conflicting source or incomplete recording"

    var body: some View {
        Form {
            Section("Check the source") {
                Text("Missing readings can mean no samples, an unworn Watch, a sync delay, or unavailable Health access. Zoon cannot distinguish these from a read query.")
                Button("Refresh from Health") { Task { await coordinator.refresh() } }
                    .disabled(coordinator.isRefreshing)
                if let refresh = coordinator.lastRefresh { LabeledContent("Last refresh", value: refresh.formatted()) }
                NavigationLink("Inspect sensor coverage") { SensorTruthView() }
                Picker("Preferred sleep source", selection: Binding(
                    get: { preferences.preferredSleepSourceName ?? "" },
                    set: { value in
                        preferences.preferredSleepSourceName = value.isEmpty ? nil : value
                        preferences.preferredSleepSourceBundleIdentifier = nil
                        Task { await coordinator.refresh() }
                    })) {
                    Text("Automatic").tag("")
                    ForEach(coordinator.knownSleepSources(), id: \.name) { Text($0.name).tag($0.name) }
                }
            }
            Section("Local corrections") {
                Text("Exclude a suspect night from comparisons. Original readings remain available and Health is unchanged. Every correction can be undone.")
                ForEach(coordinator.nightsForRepair().suffix(30).reversed(), id: \.nightKey) { night in
                    Button {
                        candidate = night
                    } label: {
                        VStack(alignment: .leading) {
                            Text(night.date, style: .date)
                            Text("\(night.formattedTimeAsleep) · \(night.sourceName ?? "Source unavailable")").font(.caption)
                        }
                    }
                }
            }
            Section("Correction history") {
                ForEach(setup.value.repairs) { repair in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(repair.reason)
                        Text(repair.recordedAt, style: .date).font(.caption)
                        Text(repair.excluded ? "Excluded from comparisons" : "Restored to comparisons").font(.caption)
                        if repair.excluded {
                            Button("Undo correction") {
                                if let index = setup.value.repairs.firstIndex(where: { $0.id == repair.id }) {
                                    setup.value.repairs[index].excluded = false
                                    Task { await coordinator.recomputeDerivedValues() }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Repair sleep data")
        .scrollContentBackground(.hidden).nightBackground()
        .sheet(item: Binding(get: { candidate.map(RepairPreview.init) }, set: { candidate = $0?.night })) { preview in
            NavigationStack {
                Form {
                    Section("Preview correction") {
                        Text(preview.night.date, style: .date)
                        LabeledContent("Recorded sleep", value: preview.night.formattedTimeAsleep)
                        Text("Before: this night participates in trends and personal baselines. After: its original record stays here, but comparisons skip it.")
                        TextField("Reason", text: $reason)
                        Button("Apply local exclusion") {
                            setup.value.repairs.removeAll { $0.nightKey == preview.night.nightKey && $0.excluded }
                            setup.value.repairs.append(.init(nightKey: preview.night.nightKey, reason: reason))
                            candidate = nil
                            Task { await coordinator.recomputeDerivedValues() }
                        }.disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }.navigationTitle("Review change")
                    .toolbar { Button("Cancel") { candidate = nil } }
            }
        }
    }

    private struct RepairPreview: Identifiable {
        let night: SleepNightFeatures
        var id: String { night.nightKey }
    }
}
