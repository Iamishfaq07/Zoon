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
                        let existing = setup.value.repairs.first { $0.nightKey == night.nightKey }
                        candidate = night
                        reason = existing?.reason ?? "Conflicting source or incomplete recording"
                        bedShift = existing?.bedtimeShiftMinutes ?? 0
                        wakeShift = existing?.wakeShiftMinutes ?? 0
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(night.date, style: .date)
                                Spacer()
                                if let existing = setup.value.repairs.first(where: { $0.nightKey == night.nightKey }),
                                   existing.hasBoundaryEdit {
                                    Text("Locally corrected")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.Family.sleep)
                                } else if let existing = setup.value.repairs.first(where: { $0.nightKey == night.nightKey }),
                                          existing.excluded {
                                    Text("Excluded")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.inkSecondary)
                                }
                            }
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
                            Button("Revert") {
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
                RepairEditor(
                    night: preview.night,
                    reason: $reason,
                    bedShift: $bedShift,
                    wakeShift: $wakeShift,
                    onCancel: { candidate = nil },
                    onSave: { excluded, bed, wake in
                        saveRepair(preview.night, excluded: excluded, bed: bed, wake: wake)
                    },
                    onRevert: {
                        saveRepair(preview.night, excluded: false, bed: 0, wake: 0)
                    }
                )
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
        Self.shiftLabel(minutes)
    }

    static func shiftLabel(_ minutes: Double) -> String {
        if abs(minutes) < 1 { return "unchanged" }
        let rounded = Int(minutes.rounded())
        return rounded < 0 ? "\(abs(rounded))m earlier" : "\(rounded)m later"
    }

    private func saveRepair(_ night: SleepNightFeatures, excluded: Bool, bed: Double, wake: Double) {
        setup.value.repairs.removeAll { $0.nightKey == night.nightKey }
        if excluded || abs(bed) >= 1 || abs(wake) >= 1 {
            setup.value.repairs.append(.init(
                nightKey: night.nightKey,
                reason: reason,
                excluded: excluded,
                bedtimeShiftMinutes: bed,
                wakeShiftMinutes: wake
            ))
        }
        candidate = nil
        Task { await coordinator.recomputeDerivedValues() }
    }

    private struct RepairPreview: Identifiable {

        let night: SleepNightFeatures
        var id: String { night.nightKey }
    }
}

/// Repair 2.0: original vs corrected preview, explicit Save, Revert.
/// Handles are steppers plus a timeline — HealthKit is never written.
private struct RepairEditor: View {
    let night: SleepNightFeatures
    @Binding var reason: String
    @Binding var bedShift: Double
    @Binding var wakeShift: Double
    let onCancel: () -> Void
    let onSave: (_ excluded: Bool, _ bed: Double, _ wake: Double) -> Void
    let onRevert: () -> Void

    private var hasShift: Bool { abs(bedShift) >= 1 || abs(wakeShift) >= 1 }
    private var corrected: SleepNightFeatures {
        hasShift
            ? night.shiftingBounds(bedtimeShiftMinutes: bedShift, wakeShiftMinutes: wakeShift)
            : night
    }

    var body: some View {
        Form {
            Section("Original HealthKit night") {
                Text(night.date, style: .date)
                LabeledContent("Recorded sleep", value: night.formattedTimeAsleep)
                LabeledContent("Sleep opportunity", value: SleepNightFeatures.formatMinutes(night.timeInBedMinutes))
                LabeledContent("Efficiency", value: "\(Int(night.sleepEfficiencyPercent.rounded()))%")
                LabeledContent("Bedtime", value: night.bedtime.formatted(date: .omitted, time: .shortened))
                LabeledContent("Wake", value: night.wakeTime.formatted(date: .omitted, time: .shortened))
                if night.hasStageBreakdown {
                    LabeledContent(
                        "Stages",
                        value: "Core \(Int(night.coreMinutes.rounded())) · Deep \(Int(night.deepMinutes.rounded())) · REM \(Int(night.remMinutes.rounded()))"
                    )
                }
                Text("Apple Health is not changed. Zoon engines read the local overlay below.")
                    .font(.caption)
            }
            Section("Move the bounds") {
                BoundTimeline(
                    originalBed: night.bedtime,
                    originalWake: night.wakeTime,
                    correctedBed: corrected.bedtime,
                    correctedWake: corrected.wakeTime
                )
                .frame(height: 56)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Stepper(
                    "Bedtime \(DataRepairView.shiftLabel(bedShift))",
                    value: $bedShift,
                    in: -LocalSleepCorrection.maximumShiftMinutes...LocalSleepCorrection.maximumShiftMinutes,
                    step: 5
                )
                Slider(
                    value: $bedShift,
                    in: -LocalSleepCorrection.maximumShiftMinutes...LocalSleepCorrection.maximumShiftMinutes,
                    step: 5
                )
                .accessibilityLabel("Bedtime shift")
                Stepper(
                    "Wake \(DataRepairView.shiftLabel(wakeShift))",
                    value: $wakeShift,
                    in: -LocalSleepCorrection.maximumShiftMinutes...LocalSleepCorrection.maximumShiftMinutes,
                    step: 5
                )
                Slider(
                    value: $wakeShift,
                    in: -LocalSleepCorrection.maximumShiftMinutes...LocalSleepCorrection.maximumShiftMinutes,
                    step: 5
                )
                .accessibilityLabel("Wake shift")
            }
            if hasShift {
                Section("Preview before saving") {
                    LabeledContent("Original window", value: windowLabel(night.bedtime, night.wakeTime))
                    LabeledContent("Corrected window", value: windowLabel(corrected.bedtime, corrected.wakeTime))
                    LabeledContent("Sleep", value: delta(SleepNightFeatures.formatMinutes(night.timeAsleepMinutes), SleepNightFeatures.formatMinutes(corrected.timeAsleepMinutes)))
                    LabeledContent("Opportunity", value: delta(SleepNightFeatures.formatMinutes(night.timeInBedMinutes), SleepNightFeatures.formatMinutes(corrected.timeInBedMinutes)))
                    LabeledContent("Efficiency", value: delta("\(Int(night.sleepEfficiencyPercent.rounded()))%", "\(Int(corrected.sleepEfficiencyPercent.rounded()))%"))
                    if night.hasStageBreakdown || corrected.hasStageBreakdown {
                        LabeledContent(
                            "Stage clip",
                            value: "Core \(Int(night.coreMinutes.rounded()))→\(Int(corrected.coreMinutes.rounded())) · Deep \(Int(night.deepMinutes.rounded()))→\(Int(corrected.deepMinutes.rounded())) · REM \(Int(night.remMinutes.rounded()))→\(Int(corrected.remMinutes.rounded()))"
                        )
                    }
                    if night.lastWorkoutHoursBeforeBed != nil || corrected.lastWorkoutHoursBeforeBed != nil {
                        LabeledContent(
                            "Workout before bed",
                            value: "\(workoutLabel(night.lastWorkoutHoursBeforeBed)) → \(workoutLabel(corrected.lastWorkoutHoursBeforeBed))"
                        )
                    }
                    Text(SleepTimingProvenance.locallyCorrected.explanation)
                        .font(.caption)
                    Text("Save writes a reversible overlay. Revert restores the HealthKit bounds inside Zoon.")
                        .font(.caption)
                }
            }
            Section("Save") {
                TextField("Reason", text: $reason)
                Button("Save correction") {
                    onSave(false, bedShift, wakeShift)
                }
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasShift)
                Button("Revert to original") {
                    onRevert()
                }
                Button("Exclude this night from comparisons") {
                    onSave(true, 0, 0)
                }
                .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Review change")
        .toolbar { Button("Cancel", action: onCancel) }
    }

    private func windowLabel(_ bed: Date, _ wake: Date) -> String {
        "\(bed.formatted(date: .omitted, time: .shortened)) – \(wake.formatted(date: .omitted, time: .shortened))"
    }

    private func delta(_ original: String, _ next: String) -> String {
        original == next ? next : "\(original) → \(next)"
    }

    private func workoutLabel(_ hours: Double?) -> String {
        guard let hours else { return "none" }
        return String(format: "%.1fh", hours)
    }
}

/// Original window as a thin bar, corrected window as a filled bar. The
/// handles are the steppers above; this is the preview, not a drag surface
/// that would fight VoiceOver.
private struct BoundTimeline: View {
    let originalBed: Date
    let originalWake: Date
    let correctedBed: Date
    let correctedWake: Date

    var body: some View {
        let spanStart = min(originalBed, correctedBed)
        let spanEnd = max(originalWake, correctedWake)
        let span = max(1, spanEnd.timeIntervalSince(spanStart))
        GeometryReader { geo in
            let width = geo.size.width
            VStack(alignment: .leading, spacing: 8) {
                bar(
                    start: originalBed,
                    end: originalWake,
                    spanStart: spanStart,
                    span: span,
                    width: width,
                    height: 8,
                    color: Theme.inkTertiary
                )
                bar(
                    start: correctedBed,
                    end: correctedWake,
                    spanStart: spanStart,
                    span: span,
                    width: width,
                    height: 14,
                    color: Theme.Family.sleep
                )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Original \(originalBed.formatted(date: .omitted, time: .shortened)) to \(originalWake.formatted(date: .omitted, time: .shortened)). Corrected \(correctedBed.formatted(date: .omitted, time: .shortened)) to \(correctedWake.formatted(date: .omitted, time: .shortened)).")
    }

    private func bar(
        start: Date,
        end: Date,
        spanStart: Date,
        span: TimeInterval,
        width: CGFloat,
        height: CGFloat,
        color: Color
    ) -> some View {
        let x = CGFloat(start.timeIntervalSince(spanStart) / span) * width
        let w = max(4, CGFloat(end.timeIntervalSince(start) / span) * width)
        return ZStack(alignment: .leading) {
            Capsule().fill(Theme.cardStroke)
            Capsule()
                .fill(color)
                .frame(width: w, height: height)
                .offset(x: x)
        }
        .frame(height: height)
    }
}
