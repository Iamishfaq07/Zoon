import SwiftUI

struct DataRepairView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @State private var setup = PersonalSetupStore.shared
    @State private var candidate: SleepNightFeatures?
    @State private var reason = "Conflicting source or incomplete recording"
    @State private var bedShift: Double = 0
    @State private var wakeShift: Double = 0


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
                Text("Health is never overwritten. You can exclude a night from comparisons, or move the recorded bedtime and wake so Zoon's engines read the session you actually had. Every change can be undone.")
                ForEach(coordinator.nightsForRepair().suffix(30).reversed(), id: \.nightKey) { night in
                    Button {
                        candidate = night
                        reason = "Conflicting source or incomplete recording"
                        bedShift = 0
                        wakeShift = 0
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
                        Text(historyLine(repair)).font(.caption)
                        if repair.excluded || repair.hasBoundaryEdit {
                            Button("Undo correction") {
                                if let index = setup.value.repairs.firstIndex(where: { $0.id == repair.id }) {
                                    setup.value.repairs[index].excluded = false
                                    setup.value.repairs[index].bedtimeShiftMinutes = 0
                                    setup.value.repairs[index].wakeShiftMinutes = 0
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
                    Section("Original HealthKit night") {
                        Text(preview.night.date, style: .date)
                        LabeledContent("Recorded sleep", value: preview.night.formattedTimeAsleep)
                        LabeledContent("Bedtime", value: preview.night.bedtime.formatted(date: .omitted, time: .shortened))
                        LabeledContent("Wake", value: preview.night.wakeTime.formatted(date: .omitted, time: .shortened))
                        Text("Apple Health is not changed. Zoon engines read the local overlay below.")
                            .font(.caption)
                    }
                    Section("Move the bounds") {
                        Stepper(
                            "Bedtime \(shiftLabel(bedShift))",
                            value: $bedShift,
                            in: -LocalSleepCorrection.maximumShiftMinutes...LocalSleepCorrection.maximumShiftMinutes,
                            step: 5
                        )
                        Stepper(
                            "Wake \(shiftLabel(wakeShift))",
                            value: $wakeShift,
                            in: -LocalSleepCorrection.maximumShiftMinutes...LocalSleepCorrection.maximumShiftMinutes,
                            step: 5
                        )
                        if abs(bedShift) >= 1 || abs(wakeShift) >= 1 {
                            let corrected = preview.night.shiftingBounds(
                                bedtimeShiftMinutes: bedShift,
                                wakeShiftMinutes: wakeShift
                            )
                            LabeledContent("Corrected window", value: "\(corrected.bedtime.formatted(date: .omitted, time: .shortened)) – \(corrected.wakeTime.formatted(date: .omitted, time: .shortened))")
                            LabeledContent("Asleep after correction", value: SleepNightFeatures.formatMinutes(corrected.timeAsleepMinutes))
                        }
                    }
                    Section("Or exclude the night") {
                        Text("Comparisons skip it. The original record stays here.")
                        TextField("Reason", text: $reason)
                        Button("Apply local exclusion") {
                            saveRepair(preview.night, excluded: true, bed: 0, wake: 0)
                        }
                        .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Apply bound correction") {
                            saveRepair(preview.night, excluded: false, bed: bedShift, wake: wakeShift)
                        }
                        .disabled(
                            reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || (abs(bedShift) < 1 && abs(wakeShift) < 1)
                        )
                    }
                }.navigationTitle("Review change")
                    .toolbar { Button("Cancel") { candidate = nil } }
            }
        }
    }

    private func historyLine(_ repair: PersonalSetup.Repair) -> String {
        if repair.excluded { return "Excluded from comparisons" }
        if repair.hasBoundaryEdit {
            return "Local overlay · bed \(shiftLabel(repair.bedtimeShiftMinutes)), wake \(shiftLabel(repair.wakeShiftMinutes)). Health unchanged."
        }
        return "Restored to comparisons"
    }

    private func shiftLabel(_ minutes: Double) -> String {
        if abs(minutes) < 1 { return "unchanged" }
        let rounded = Int(minutes.rounded())
        return rounded < 0 ? "\(abs(rounded))m earlier" : "\(rounded)m later"
    }

    private func saveRepair(_ night: SleepNightFeatures, excluded: Bool, bed: Double, wake: Double) {
        setup.value.repairs.removeAll { $0.nightKey == night.nightKey }
        setup.value.repairs.append(.init(
            nightKey: night.nightKey,
            reason: reason,
            excluded: excluded,
            bedtimeShiftMinutes: bed,
            wakeShiftMinutes: wake
        ))
        candidate = nil
        Task { await coordinator.recomputeDerivedValues() }
    }

    private struct RepairPreview: Identifiable {

        let night: SleepNightFeatures
        var id: String { night.nightKey }
    }
}
