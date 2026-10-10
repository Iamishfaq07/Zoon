import SwiftUI
import UIKit

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
    @State private var setup = PersonalSetupStore.shared
    @State private var wakeAlarm = WakeAlarm()

    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteFailure = false
    @State private var isFillingProfile = false
    @State private var profileFillMessage: String?
    @State private var group: SettingsGroup = .you

    var body: some View {
        // Bindings are built by hand rather than with @Bindable because each
        // setter has to trigger a recompute, not just store a value.
        Form {
            // Thirteen sections in one scroll, grouped into four. The picker
            // stays at the top; each group is a screenful at most.
            Section {
                Picker("Settings group", selection: $group) {
                    ForEach(SettingsGroup.allCases) { group in
                        Text(group.label).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch group {
            case .you:
                youSections
            case .schedule:
                remindersSection
                obligationDaysSection
                Section {
                    NavigationLink { SavedSleepPlansView() } label: { Label("Saved sleep schedules", systemImage: "calendar") }
                    NavigationLink { ShiftRosterView() } label: { Label("Work roster", systemImage: "briefcase") }
                }
            case .health:
                trackedBehaviorsSection
                lifestyleInsightsSection
                cycleSection
                sourceSection
            case .app:
                engineSection
                dataSection
                medicalSection
            }
        }
        .scrollContentBackground(.hidden)
        // Every writer HealthKit knows, so the source section can offer one
        // that never won a night -- and can appear at all when only such a
        // writer makes a second choice.
        .task { await coordinator.refreshSleepWriters() }
        .nightBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete all Zoon data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task { showingDeleteFailure = !(await coordinator.deleteAllData()) }
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
            Text("Some data couldn't be cleared. Try again before deleting the app.")
        }
    }

    enum SettingsGroup: String, CaseIterable, Identifiable {
        case you, schedule, health, app
        var id: String { rawValue }
        var label: String {
            switch self {
            case .you: "You"
            case .schedule: "Schedule"
            case .health: "Health"
            case .app: "App"
            }
        }
    }

    @ViewBuilder
    private var youSections: some View {
        Section("Your experience") {
            Toggle("Score-light mode", isOn: $setup.value.scoreLight)
                .accessibilityIdentifier("scoreLightToggle")
            Text("Sleep and timing first. Scores stay a tap away.").font(.caption)
        }
        goalSection
        profileSection
        appearanceSection
        AppIconSection()
    }

    // MARK: - Sections

    private var goalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nightly goal")
                    Spacer()
                    Text(preferences.sleepGoalDisplay)
                        .foregroundStyle(Theme.inkSecondary)
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
                if let guideline = SleepNeedGuideline.forAge(preferences.age) {
                    // Where the goal sits against the recommendation for
                    // this age, and a one-tap way to the middle of it.
                    Text(guideline.goalSentence(goalMinutes: preferences.sleepGoalMinutes))
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if guideline.fit(preferences.sleepGoalMinutes) != .withinRecommended {
                        Button("Use \(SleepNightFeatures.formatMinutes(guideline.suggestedGoalMinutes)), the middle of that range") {
                            preferences.sleepGoalMinutes = guideline.suggestedGoalMinutes
                            Haptics.select()
                            Task { await coordinator.recomputeDerivedValues() }
                        }
                        .font(Theme.label(13, weight: .semibold))
                    }
                } else {
                    Text("Add your age below to see the recommended range.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Sleep Goal")
        } footer: {
            Text("A starting point. Zoon learns your real need from your nights.")
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
            .adaptiveSegmentedStyle()
            Button("Replay the first night") {
                preferences.hasCompletedOnboarding = false
            }
            .accessibilityIdentifier("replayFirstNight")
        } header: {
            Text("Appearance")
        } footer: {
            Text("Replay shows the welcome again. Your data stays.")
        }
    }

    /// Wind-down and bedtime notifications.
    ///
    /// The toggle requests permission on the way *on*, which is the only
    /// moment the request has context — an app that asks at launch, before
    /// showing what the notification is for, mostly gets denied permanently.
    /// What to say under the "Wake alarm" toggle -- the actual next
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
            // The day as well as the time: this is one dated alarm, re-armed
            // when the app opens, not a repeating one. "Rings around 7:00"
            // read as every morning.
            return "Set for \(scheduledWakeTime.formatted(.dateTime.weekday(.abbreviated).hour().minute())), "
                + "through Silent mode and Sleep Focus. Opening Zoon sets the next one."
        }
        return "Rings at your planned wake time, through Silent mode and Sleep Focus."
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
                            if granted {
                                await reminders.schedule(
                                    bedtimes: coordinator.tonightHorizon(nights: ReminderSchedule.horizonNights).map(\.bed)
                                )
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
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if let bedtime = coordinator.tonightEpisode()?.bed {
                LabeledContent(preferences.isShiftWorkModeEnabled ? "Next sleep" : "Tonight") {
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

                    Text("Add Zoon as a Focus filter to pause these. Your alarm still sounds.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
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
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            // Its own switch. It used to sit under the wake window and only
            // exist while the window was on, and the scheduler matched: an
            // alarm asked for anywhere else (the Coach's "set an alarm") was
            // cancelled for anyone without the window notification. The alarm
            // rings at the planned wake either way; the window is an optional
            // gentler nudge before it.
            Toggle(isOn: Binding(
                get: { preferences.wakeAlarmEnabled },
                set: { wantsOn in
                    Task {
                        if wantsOn {
                            preferences.wakeAlarmEnabled = await wakeAlarm.requestAuthorization()
                        } else {
                            // Off only if the cancel took. A failed cancel
                            // leaves a real alarm set, and a switch
                            // showing off above it would be the one
                            // place the app claims otherwise.
                            preferences.wakeAlarmEnabled = !wakeAlarm.cancel()
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake alarm")
                    Text(alarmStatusDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .disabled(!wakeAlarm.isAvailable)

            Toggle(isOn: Binding(
                get: { preferences.morningBriefEnabled },
                set: { wantsOn in
                    Task {
                        if wantsOn {
                            let granted = await reminders.requestAuthorization()
                            preferences.morningBriefEnabled = granted
                        } else {
                            preferences.morningBriefEnabled = false
                            reminders.cancelMorningBrief()
                        }
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morning brief")
                    Text("Nudge \(BedtimeReminder.morningBriefLeadMinutes) minutes after your usual wake. Names no numbers — open the app for those.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
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
            Text("Set on this phone. The time follows your sleep debt.")
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

            VStack(alignment: .leading, spacing: 6) {
                Picker("Schedule", selection: Binding(
                    get: { preferences.shiftWorkMode },
                    set: { preferences.shiftWorkMode = $0 }
                )) {
                    ForEach(ShiftWorkMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(preferences.shiftWorkMode.explanation)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Obligation days")
        } footer: {
            Text("Days with a fixed start. The rest count as free days.")
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
                .foregroundStyle(isObligation ? Theme.Metric.sleep : Theme.inkSecondary)
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
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        } header: {
            Text("Cycle")
        } footer: {
            Text("Reads period dates so a normal cycle shift isn't mistaken for illness.")
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
                    Text("Reads measured caffeine, alcohol, daylight, mindfulness and logged mood from Health.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        } header: {
            Text("Lifestyle Insights")
        } footer: {
            Text("Off by default. Ten minutes of morning daylight ticks \"time outdoors\" for you; your own answers are never changed.")
        }
    }

    /// A NavigationLink rather than an inline section: ~22 tags across four
    /// categories doesn't fit a `Form` row without either overwhelming
    /// Settings or being cut off, and this is a "set once, rarely revisit"
    /// choice anyway -- the same reasoning `AlgorithmTransparencyView` gets
    /// its own screen instead of an inline explainer.
    private var trackedBehaviorsSection: some View {
        Section {
            NavigationLink {
                TrackedBehaviorsView()
            } label: {
                Label("Tracked Behaviours", systemImage: "checklist")
            }
            // Moved here from More: adding your own behaviour and choosing
            // which ones the Journal asks about are the same decision.
            NavigationLink {
                CustomBehaviorsView()
            } label: {
                Label("Your own behaviours", systemImage: "plus.circle")
            }
        } footer: {
            Text("Choose what the Journal asks about each day, or add your own.")
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
            Picker(
                "Sex",
                selection: Binding(
                    get: { preferences.biologicalSex },
                    set: { newValue in
                        preferences.biologicalSex = newValue
                        Task { await coordinator.recomputeDerivedValues() }
                    }
                )
            ) {
                Text("Not set").tag(DemographicBaseline.Sex.unspecified)
                Text("Female").tag(DemographicBaseline.Sex.female)
                Text("Male").tag(DemographicBaseline.Sex.male)
            }
            Picker(
                "BMI",
                selection: Binding(
                    get: { preferences.bodyMassIndex.map { Int($0.rounded()) } ?? 0 },
                    set: { newValue in
                        preferences.bodyMassIndex = newValue > 0 ? Double(newValue) : nil
                        Task { await coordinator.recomputeDerivedValues() }
                    }
                )
            ) {
                Text("Not set").tag(0)
                ForEach(16...45, id: \.self) { bmi in
                    Text("\(bmi)").tag(bmi)
                }
            }
            if DataEnvironment.current.isLive && HealthKitManager.isHealthDataAvailable {
                Button {
                    Task {
                        isFillingProfile = true
                        let profile = await coordinator.fillProfileFromHealth(
                            requestingAccess: true, onlyMissing: false
                        )
                        profileFillMessage = ForYourAgeCard.fillSummary(profile)
                        isFillingProfile = false
                    }
                } label: {
                    HStack {
                        Label("Fill from Health", systemImage: "heart.text.square")
                        if isFillingProfile {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isFillingProfile)
            }
            if let profileFillMessage {
                Text(profileFillMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
        } header: {
            Text("Profile")
        } footer: {
            Text(profileFooter)
        }
    }

    /// What each field changes, with this person's own numbers where they
    /// are set, so "optional" does not read as "pointless".
    private var profileFooter: String {
        var lines: [String] = []
        if let age = preferences.age {
            let maximum = Int(HeartRateZoneIntegrator.maximumHeartRate(age: age).bpm.rounded())
            if let guideline = SleepNeedGuideline.forAge(age) {
                lines.append("At \(age): \(guideline.recommendedText) of sleep recommended, and a maximum heart rate near \(maximum) bpm for Daily Load and Energy Reserve.")
            } else {
                lines.append("At \(age): a maximum heart rate near \(maximum) bpm for Daily Load and Energy Reserve.")
            }
        } else {
            lines.append("Tunes your sleep range, heart zones and typical numbers.")
        }
        lines.append("Optional, and never leaves this iPhone.")
        return lines.joined(separator: " ")
    }

    private var engineSection: some View {
        Section {
            // The picker itself now lives on the Coach tab, which is the one
            // screen where its effect is visible. It was here, three screens
            // from anything it changes: someone wondering why the coach
            // sounded mechanical had no reason to look in Settings for the
            // answer, and no hint that the choice might not be available on
            // their device at all.
            HStack {
                Label("Answered by", systemImage: "cpu")
                Spacer()
                Text(preferences.preferredEngine.displayName)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text("Change this on the Coach tab, where you can see what it changes.")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)

            // No row for the bundled on-device model (`LocalLLMInsightEngine`):
            // no model ships, so a "Labs / not yet available" row was a
            // placeholder for a feature that does not exist -- exactly what
            // App Review guideline 2.1 rejects. It returns here when a model
            // does, alongside a place in `EngineChoice.shippingCases`.

            NavigationLink {
                DataHub(initial: .method)
            } label: {
                Label("How your Sleep Intelligence score works", systemImage: "function")
            }
            .font(.caption)
        } header: {
            Text("Insights")
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
                        // One path for both pickers -- see
                        // `SleepDataCoordinator.selectSleepSource`. It stores
                        // the bundle identifier alongside the name and forces
                        // a full re-sync so the choice applies to stored
                        // history, not only nights processed from here on.
                        Task { await coordinator.selectSleepSource(named: newValue) }
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
                Text("Zoon picks the fullest source each night, or choose one.")
            }
        }
    }

    /// Said once in onboarding and kept here, where someone looks for what
    /// the app is and is not. The feature screens (Snore Check, Breathing,
    /// the clinician report) repeat it where a result could be read as one.
    private var medicalSection: some View {
        Section {
            Text("Zoon describes your sleep from the data your devices record. It is not a medical device and does not diagnose, treat or prevent any condition.")
            Text("If you are often very sleepy during the day, stop breathing or gasp in your sleep, or have trouble sleeping for weeks, talk to a doctor.")
        } header: {
            Text("Health, not medicine")
        }
        .font(.footnote)
        .foregroundStyle(Theme.inkSecondary)
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                DataHub(initial: .arrived)
            } label: {
                Label("Data Quality", systemImage: "waveform.path.ecg")
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
                    .foregroundStyle(AppGroup.isConfigured ? .green : Theme.inkSecondary)
            }

            NavigationLink {
                DataHub(initial: .privacy)
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

/// The Home Screen icon. The crescent is the default; the other four are
/// alternates the build declares (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES
/// in Tools/generate-pbxproj.py) and Tools/generate-alternate-icons.py draws.
/// Each shows as its own picture, because an icon is chosen by looking.
private struct AppIconSection: View {
    private struct Option: Identifiable {
        /// `nil` is the default icon, as `setAlternateIconName` expects.
        let iconName: String?
        let label: String
        let preview: String
        var id: String { iconName ?? "default" }
    }

    private static let options = [
        Option(iconName: nil, label: "Crescent", preview: "IconPreviewDefault"),
        Option(iconName: "AppIconTextured", label: "Moon", preview: "IconPreviewTextured"),
        Option(iconName: "AppIconRing", label: "Ring", preview: "IconPreviewRing"),
        Option(iconName: "AppIconCrescent", label: "Stars", preview: "IconPreviewCrescent"),
        Option(iconName: "AppIconMoonrise", label: "Moonrise", preview: "IconPreviewMoonrise"),
    ]

    @State private var current: String?
    @State private var failed = false

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Self.options) { option in
                            tile(option)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                Text("App icon")
            } footer: {
                if failed {
                    Text("iOS didn't change the icon. Try again.")
                }
            }
            .onAppear { current = UIApplication.shared.alternateIconName }
        }
    }

    private func tile(_ option: Option) -> some View {
        let selected = option.iconName == current
        return Button {
            guard !selected else { return }
            Haptics.select()
            Task {
                do {
                    try await UIApplication.shared.setAlternateIconName(option.iconName)
                    current = option.iconName
                    failed = false
                } catch {
                    failed = true
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(option.preview)
                    .resizable()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(selected ? Theme.Family.sleep : .clear, lineWidth: 2.5)
                            .padding(-4)
                    }
                Text(option.label)
                    .font(Theme.text(11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
            }
            .padding(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.label) icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .zoonPreviewEnvironment()
}
