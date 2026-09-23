import SwiftUI
import AVFoundation

struct TonightRoutineView: View {
    @Environment(SoundscapeEngine.self) private var audio
    @State private var store = PersonalSetupStore.shared
    @State private var controller = TonightRoutineController.shared
    @State private var showingVoiceStudio = false

    var body: some View {
        Form {
            Section {
                Label("Settle into tonight", systemImage: "moon.stars.fill").font(.title2.bold())
                Text("Begin with guided breathing and your sound scene. Audio fades at the end. Your routine continues when you leave this screen.")
                    .font(.callout).foregroundStyle(Theme.inkSecondary)
                if let window = store.value.nextWindow() {
                    LabeledContent("Saved bedtime", value: window.start.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Saved wake time", value: window.end.formatted(date: .abbreviated, time: .shortened))
                    Text("Alarm status and permissions are shown in Settings.").font(.caption)
                }
                NavigationLink("Travel and shift schedules") { SavedSleepPlansView() }
            }

            Section {
                RelatedReading(placement: .tonightRoutine, title: "Setting up for tonight")
            }
            Section("Routine") {
                Stepper("\(store.value.routine.minutes) minutes", value: $store.value.routine.minutes, in: 5...120, step: 5)
                    .onChange(of: store.value.routine.minutes) { _, minutes in
                        let cap = WindDownGuidanceConfiguration.maxGuidedMinutes(routineMinutes: minutes)
                        if store.value.routine.guidedBreathingMinutes > cap {
                            store.value.routine.guidedBreathingMinutes = cap
                        }
                    }
                Stepper(
                    "\(store.value.routine.guidedBreathingMinutes) min guided breathing",
                    value: $store.value.routine.guidedBreathingMinutes,
                    in: 2...WindDownGuidanceConfiguration.maxGuidedMinutes(routineMinutes: store.value.routine.minutes),
                    step: 1
                )
                Toggle("Start with breathing", isOn: $store.value.routine.breathing)
                Picker("Cues", selection: $store.value.routine.voiceMode) {
                    ForEach(WindDownGuidanceConfiguration.VoiceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Button {
                    showingVoiceStudio = true
                } label: {
                    LabeledContent("Spoken voice", value: selectedVoiceLabel)
                }
                Toggle("Phase haptics", isOn: $store.value.routine.haptics)
                Picker("Sound scene", selection: $store.value.routine.sceneID) {
                    Text("Soft rain").tag(UUID?.none)
                    ForEach(store.value.scenes) { Text($0.name).tag(Optional($0.id)) }
                }
                NavigationLink("Create a sound scene") { AudioStudioView() }
                if controller.active {
                    Text(stageCopy)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }.disabled(controller.active)
            Section {
                if let session = store.value.session {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("\(Int(ceil(session.remaining(at: context.date) / 60))) minutes remaining")
                            .monospacedDigit().accessibilityIdentifier("routineRemaining")
                    }
                    Text(controller.active ? "Routine playing" : "Routine paused").font(.headline)
                    if controller.active {
                        Button("Pause routine") { controller.pause() }
                    } else {
                        Button("Resume routine") { controller.resume(audio: audio) }
                    }
                    Button("Restart guidance") { controller.start(audio: audio) }
                    Button("End routine", role: .destructive) { controller.stop() }
                } else {
                    Button("Begin tonight's routine") { controller.start(audio: audio) }
                        .accessibilityIdentifier("beginRoutine")
                }
            }
        }
        .navigationTitle("Tonight")
        .scrollContentBackground(.hidden).nightBackground()
        .onAppear { controller.reconcile() }
        .sheet(isPresented: $showingVoiceStudio) {
            WindDownVoiceStudio(selection: $store.value.routine.voiceIdentifier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(controller.active ? "Wind Down. \(stageCopy)" : "Wind Down")
    }

    private var selectedVoiceLabel: String {
        guard let id = store.value.routine.voiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: id) else {
            return "Automatic"
        }
        return "\(voice.name) · \(BreathingCoach.qualityLabel(voice))"
    }

    private var stageCopy: String {
        switch controller.stage {
        case .arrive: "Arrive — get comfortable."
        case .guided: "Guided breathing."
        case .quiet: "Quiet continuation — sound only."
        case .close: "Settling into sleep."
        }
    }
}

struct WindDownVoiceStudio: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var preview = BreathingCoach()

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selection = nil
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Automatic")
                            Text("Best installed voice for this language.")
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        if selection == nil { Image(systemName: "checkmark") }
                    }
                }
                ForEach(BreathingCoach.installedVoices(), id: \.identifier) { voice in
                    Button {
                        selection = voice.identifier
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.name)
                                Text("\(voice.language) · \(BreathingCoach.qualityLabel(voice))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                            Spacer()
                            if selection == voice.identifier { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            .navigationTitle("Voice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Preview") {
                        preview.voiceIdentifier = selection
                        preview.voiceEnabled = true
                        preview.previewVoice()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onDisappear { preview.stop() }
    }
}

struct SavedSleepPlansView: View {
    @State private var store = PersonalSetupStore.shared
    @State private var name = "My sleep schedule"
    @State private var bed = Self.timeToday(hour: 23)
    @State private var wake = Self.timeToday(hour: 7)
    @State private var firstDate = Date.now
    @State private var zone = TimeZone.current.identifier
    @State private var repeating = true
    @State private var weekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    private static func timeToday(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
    }

    var body: some View {
        Form {
            Section("Saved schedules") {
                ForEach($store.value.plans) { $plan in
                    VStack(alignment: .leading) {
                        Toggle(plan.name, isOn: $plan.enabled)
                        Text(plan.timeZoneIdentifier).font(.caption).foregroundStyle(Theme.inkSecondary)
                        if let window = plan.nextWindow(after: .now) {
                            Text("\(window.start.formatted(date: .abbreviated, time: .shortened)) – \(window.end.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                        }
                    }
                }.onDelete { store.value.plans.remove(atOffsets: $0) }
                Text("The earliest active sleep window takes priority. Saved times feed Tonight and enabled reminders or alarms.").font(.caption)
            }
            Section("New schedule") {
                TextField("Name", text: $name)
                Picker("Time zone", selection: $zone) {
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("First bedtime date", selection: $firstDate, displayedComponents: .date)
                DatePicker("Bedtime", selection: $bed, displayedComponents: .hourAndMinute)
                DatePicker("Wake", selection: $wake, displayedComponents: .hourAndMinute)
                Toggle("Repeat each week", isOn: $repeating)
                if repeating {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(
                            get: { weekdays.contains(day) },
                            set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                    }
                }
                Button("Save and use these times") {
                    let calendar = Calendar.current
                    store.value.plans.append(.init(name: name, timeZoneIdentifier: zone,
                        bedtimeMinute: calendar.component(.hour, from: bed) * 60 + calendar.component(.minute, from: bed),
                        wakeMinute: calendar.component(.hour, from: wake) * 60 + calendar.component(.minute, from: wake),
                        weekdays: repeating ? weekdays : [], firstDate: firstDate))
                }.disabled(name.isEmpty || (repeating && weekdays.isEmpty))
            }
            Section { NavigationLink("Travel planning guidance") { TravelPlanView() } }
        }
        .navigationTitle("Sleep schedules")
        .scrollContentBackground(.hidden).nightBackground()
    }
}
