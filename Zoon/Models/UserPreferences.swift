import Foundation
import SwiftUI

/// User-tunable settings.
///
/// Backed by `UserDefaults` rather than SwiftData: these are a handful of
/// scalars read on every launch and on every score computation, and they carry
/// no health data, so the heavier store buys nothing.
@MainActor
@Observable
final class UserPreferences {

    private enum Key {
        static let sleepGoalMinutes = "zoon.pref.sleepGoalMinutes"
        static let hasCompletedOnboarding = "zoon.pref.hasCompletedOnboarding"
        static let preferredEngine = "zoon.pref.preferredEngine"
        static let age = "zoon.pref.age"
        static let bedtimeRemindersEnabled = "zoon.pref.bedtimeRemindersEnabled"
        static let focusSilencesBedtimeNudges = "zoon.pref.focusSilencesBedtimeNudges"
        static let cycleTrackingEnabled = "zoon.pref.cycleTrackingEnabled"
        static let lifestyleInsightsEnabled = "zoon.pref.lifestyleInsightsEnabled"
        static let smartWakeEnabled = "zoon.pref.smartWakeEnabled"
        static let wakeAlarmEnabled = "zoon.pref.wakeAlarmEnabled"
        static let appearance = "zoon.pref.appearance"
        static let recoveryModeDate = "zoon.pref.recoveryModeDate"
        static let experimentTag = "zoon.pref.experimentTag"
        static let experimentStartDate = "zoon.pref.experimentStartDate"
        static let experimentHypothesis = "zoon.pref.experimentHypothesis"
        static let experimentPrimaryMetric = "zoon.pref.experimentPrimaryMetric"
        static let experimentDirection = "zoon.pref.experimentDirection"
        static let obligationWeekdays = "zoon.pref.obligationWeekdays"
        static let shiftWorkModeEnabled = "zoon.pref.shiftWorkModeEnabled"
        static let preferredSleepSourceName = "zoon.pref.preferredSleepSourceName"
        static let preferredSleepSourceBundleIdentifier = "zoon.pref.preferredSleepSourceBundleIdentifier"
        static let trackedBehaviorTagIdentifiers = "zoon.pref.trackedBehaviorTagIdentifiers"
    }

    private let defaults: UserDefaults

    /// Nightly sleep target, minutes. Everything comparative — score, sleep
    /// debt, "you're short by" — is measured against this, not a population
    /// average, so a 7-hour sleeper isn't permanently marked down.
    var sleepGoalMinutes: Double {
        didSet { defaults.set(sleepGoalMinutes, forKey: Key.sleepGoalMinutes) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// `Calendar.component(.weekday:)` values (1 = Sunday ... 7 = Saturday)
    /// the user has a fixed obligation on -- work, school, or any other
    /// standing commitment. Free days are the complement. Feeds Sleep
    /// Regularity's work/free split and Cause Finder's weekend/weekday
    /// matched-pair constraint, both of which used to hardcode the calendar
    /// weekend -- correct for a standard Mon-Fri job, wrong for anyone on a
    /// different schedule (a four-day week, weekend retail shifts, and so
    /// on). Defaults to the standard workweek so nothing changes for anyone
    /// who's never touched the setting.
    var obligationWeekdays: Set<Int> {
        didSet { defaults.set(Array(obligationWeekdays), forKey: Key.obligationWeekdays) }
    }

    static let defaultObligationWeekdays = SleepRegularity.defaultObligationWeekdays

    func isFreeDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        !obligationWeekdays.contains(calendar.component(.weekday, from: date))
    }

    /// The user's primary sleep happens during conventional daytime hours
    /// rather than at night. `SleepDataCoordinator.classify(_:)` normally
    /// treats a session centered in the 9am-6pm window as a nap (anything
    /// else is "secondary sleep") on the assumption that the main block
    /// happens at night; that assumption inverts for a night-shift worker,
    /// where a short break during the overnight work hours is the nap and
    /// the long daytime block is the main sleep. This toggle flips which
    /// window counts as "expected primary sleep" for that classification,
    /// and swaps a handful of night-relative UI labels ("Last Night",
    /// "Tonight") for schedule-neutral ones. Off by default so nothing
    /// changes for anyone who's never touched the setting.
    var isShiftWorkModeEnabled: Bool {
        didSet { defaults.set(isShiftWorkModeEnabled, forKey: Key.shiftWorkModeEnabled) }
    }

    /// Which behaviours the Journal's daily quick-confirm screen shows.
    /// `nil` -- the default, and the state of every account created before
    /// this existed -- means unrestricted: every `BehaviorTag` shows, same
    /// as before this setting existed. Once the user curates a set (even
    /// down to all of them, explicitly), this switches to that concrete
    /// list; there is no separate "show everything" state once customized
    /// other than re-selecting every tag.
    var trackedBehaviorTagIdentifiers: Set<String>? {
        didSet {
            if let trackedBehaviorTagIdentifiers {
                defaults.set(Array(trackedBehaviorTagIdentifiers), forKey: Key.trackedBehaviorTagIdentifiers)
            } else {
                defaults.removeObject(forKey: Key.trackedBehaviorTagIdentifiers)
            }
        }
    }

    /// Whether the Journal should offer `tag` today. Always true until the
    /// user has customized the tracked set at all.
    func isTracked(_ tag: BehaviorTag) -> Bool {
        trackedBehaviorTagIdentifiers?.contains(tag.rawValue) ?? true
    }

    /// Turns behaviour tracking on/off for one tag. The first call after
    /// the set has never been customized seeds it from every tag that
    /// existed at that point (i.e. "everything, minus this one" or
    /// "everything, confirmed"), not an empty set -- an empty starting
    /// set would read as "track nothing" the instant the user touches any
    /// single toggle, which isn't what tapping one row means.
    func setTracked(_ tag: BehaviorTag, tracked: Bool) {
        var current = trackedBehaviorTagIdentifiers ?? Set(BehaviorTag.allCases.map(\.rawValue))
        if tracked {
            current.insert(tag.rawValue)
        } else {
            current.remove(tag.rawValue)
        }
        trackedBehaviorTagIdentifiers = current
    }

    /// Returns to the unrestricted default -- every current and future tag
    /// shown, with no stored customization at all.
    func resetTrackedBehaviors() {
        trackedBehaviorTagIdentifiers = nil
    }

    /// Wind-down and bedtime notifications. Off until asked for — see
    /// `BedtimeReminder.requestAuthorization`.
    var bedtimeRemindersEnabled: Bool {
        didSet { defaults.set(bedtimeRemindersEnabled, forKey: Key.bedtimeRemindersEnabled) }
    }

    /// Set by `SleepFocusFilter` while a Focus carrying Zoon's filter is on.
    ///
    /// Separate from `bedtimeRemindersEnabled` rather than folded into it: one
    /// is the user's standing preference, the other is a temporary system
    /// state. Collapsing them would mean a Focus turning on looked identical
    /// to the user switching reminders off in Settings, and the toggle would
    /// appear to flip by itself.
    var focusSilencesBedtimeNudges: Bool {
        didSet { defaults.set(focusSilencesBedtimeNudges, forKey: Key.focusSilencesBedtimeNudges) }
    }

    /// Off by default. Turning it on triggers a *separate* HealthKit
    /// authorization request — see `HealthKitManager.requestCycleTrackingAuthorization`
    /// — rather than reading reproductive health data for everyone by default.
    var cycleTrackingEnabled: Bool {
        didSet { defaults.set(cycleTrackingEnabled, forKey: Key.cycleTrackingEnabled) }
    }

    /// Off by default. Turning it on triggers a *separate* HealthKit
    /// authorization request for caffeine, alcohol, daylight, and
    /// mindfulness — see `HealthKitManager.requestLifestyleInsightsAuthorization`
    /// — rather than reading those by default alongside everything else.
    var lifestyleInsightsEnabled: Bool {
        didSet { defaults.set(lifestyleInsightsEnabled, forKey: Key.lifestyleInsightsEnabled) }
    }

    /// Wake-window notification — see `BedtimeReminder.scheduleWakeWindow`.
    var smartWakeEnabled: Bool {
        didSet { defaults.set(smartWakeEnabled, forKey: Key.smartWakeEnabled) }
    }

    /// A real alarm at the end of the wake window — see `WakeAlarm`.
    ///
    /// Its own toggle rather than riding on `smartWakeEnabled`, and off by
    /// default, for one reason: the wake window has always been a *silent*
    /// notification, and an alarm rings through Silent mode and a Sleep
    /// Focus. Turning it on for everyone who already enabled the notification
    /// would mean an OS update silently converting something that has never
    /// made a sound into something that blasts them awake. Nobody should be
    /// woken by an app because they updated it.
    var wakeAlarmEnabled: Bool {
        didSet { defaults.set(wakeAlarmEnabled, forKey: Key.wakeAlarmEnabled) }
    }

    /// System / Dark / Light. Defaults to Dark, not System: the palette was
    /// built dark-first for a bedroom screen, and defaulting to System would
    /// silently put a daytime user into a mode the app never used to have,
    /// on an upgrade they didn't ask for. Anyone who wants it light now can
    /// have it -- see `Theme`'s adaptive tokens -- but the existing look
    /// stays the default rather than changing out from under people already
    /// using it.
    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    enum AppearancePreference: String, CaseIterable, Identifiable {
        case system, dark, light

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: "System"
            case .dark: "Dark"
            case .light: "Light"
            }
        }

        /// `nil` lets SwiftUI follow the system setting.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .dark: .dark
            case .light: .light
            }
        }
    }

    /// Used only to estimate maximum heart rate, which sets the heart-rate
    /// reserve that strain zones and body battery drain are scaled against.
    /// `nil` falls back to a generic 190 bpm ceiling.
    var age: Int? {
        didSet { defaults.set(age ?? 0, forKey: Key.age) }
    }

    /// The date Recovery Mode was manually turned on, if any -- not a plain
    /// Bool, because it needs to stop applying once the day it was set for
    /// has passed rather than staying stuck on indefinitely. See
    /// `isRecoveryModeManuallyEnabledToday` and `RecoveryMode`.
    private var recoveryModeDate: Date? {
        didSet {
            if let recoveryModeDate {
                defaults.set(recoveryModeDate, forKey: Key.recoveryModeDate)
            } else {
                defaults.removeObject(forKey: Key.recoveryModeDate)
            }
        }
    }

    var isRecoveryModeManuallyEnabledToday: Bool {
        guard let recoveryModeDate else { return false }
        return Calendar.current.isDateInToday(recoveryModeDate)
    }

    func setRecoveryModeEnabledToday(_ enabled: Bool) {
        recoveryModeDate = enabled ? .now : nil
    }

    /// The behaviour a Guided Experiment is currently tracking, if any --
    /// see `GuidedExperiment`. Only one at a time: running several at once
    /// would make it unclear which behaviour a result actually belongs to,
    /// since the matched-pair comparison already runs across the same
    /// shared journal history regardless of what's "active".
    private(set) var activeExperimentTag: BehaviorTag? {
        didSet {
            if let activeExperimentTag {
                defaults.set(activeExperimentTag.rawValue, forKey: Key.experimentTag)
            } else {
                defaults.removeObject(forKey: Key.experimentTag)
            }
        }
    }

    /// When the active experiment was started. Passed to
    /// `GuidedExperiment.status(for:observations:since:)` to gate the
    /// matched-pair comparison to nights on or after this date, and also
    /// used for display so the user can see how long they've been tracking
    /// it.
    private(set) var experimentStartDate: Date? {
        didSet {
            if let experimentStartDate {
                defaults.set(experimentStartDate, forKey: Key.experimentStartDate)
            } else {
                defaults.removeObject(forKey: Key.experimentStartDate)
            }
        }
    }

    /// What the user expects to find, in their own words -- optional, shown
    /// alongside the eventual result but never fed into the statistics
    /// themselves. Purely for the user's own record of what they were
    /// testing, same non-scoring role as `JournalEntry.note`.
    private(set) var experimentHypothesis: String? {
        didSet {
            if let experimentHypothesis {
                defaults.set(experimentHypothesis, forKey: Key.experimentHypothesis)
            } else {
                defaults.removeObject(forKey: Key.experimentHypothesis)
            }
        }
    }

    /// Which outcome metric the eventual result is judged on -- chosen when
    /// the experiment starts, not after seeing the data. Scanning every
    /// metric after the fact and reporting whichever moved the most is a
    /// classic multiple-comparisons trap: with six metrics in play, *some*
    /// of them will drift by chance even with no real effect, and picking
    /// the biggest post-hoc dresses that noise up as a finding. Locking the
    /// metric in at the start is what makes the eventual before/after
    /// comparison mean anything.
    private(set) var experimentPrimaryMetric: JournalCorrelator.Metric? {
        didSet {
            if let experimentPrimaryMetric {
                defaults.set(experimentPrimaryMetric.rawValue, forKey: Key.experimentPrimaryMetric)
            } else {
                defaults.removeObject(forKey: Key.experimentPrimaryMetric)
            }
        }
    }

    /// Which side of the tag the active experiment is testing for --
    /// cutting back on it, or doing more of it. This is what "compliant"
    /// means for `GuidedExperiment.summarize`'s adherence figure; without
    /// it there's no way to tell a broken trial from a successful one.
    private(set) var experimentDirection: GuidedExperiment.Direction? {
        didSet {
            if let experimentDirection {
                defaults.set(experimentDirection.rawValue, forKey: Key.experimentDirection)
            } else {
                defaults.removeObject(forKey: Key.experimentDirection)
            }
        }
    }

    func startExperiment(
        _ tag: BehaviorTag,
        hypothesis: String? = nil,
        primaryMetric: JournalCorrelator.Metric = .sleepPerformance,
        direction: GuidedExperiment.Direction = .avoid
    ) {
        activeExperimentTag = tag
        experimentStartDate = .now
        experimentHypothesis = (hypothesis?.isEmpty ?? true) ? nil : hypothesis
        experimentPrimaryMetric = primaryMetric
        experimentDirection = direction
    }

    func endExperiment() {
        activeExperimentTag = nil
        experimentStartDate = nil
        experimentHypothesis = nil
        experimentPrimaryMetric = nil
        experimentDirection = nil
    }

    /// Which insight engine to use. The LLM option is present but stubbed —
    /// see `LocalLLMInsightEngine`.
    var preferredEngine: EngineChoice {
        didSet { defaults.set(preferredEngine.rawValue, forKey: Key.preferredEngine) }
    }

    /// The HealthKit source name to prefer when more than one source writes
    /// sleep for the same cluster of samples -- e.g. an Apple Watch and a
    /// third-party tracker both reporting the same night. `nil` (the
    /// default) means automatic: `SleepSessionBuilder` picks whichever
    /// source has the richest staged coverage, same as before this setting
    /// existed. When set, a cluster whose sources include this name uses it
    /// outright; a cluster that doesn't (this source simply didn't write
    /// anything that night) still falls back to automatic picking rather
    /// than silently discarding the night.
    var preferredSleepSourceName: String? {
        didSet {
            if let preferredSleepSourceName {
                defaults.set(preferredSleepSourceName, forKey: Key.preferredSleepSourceName)
            } else {
                defaults.removeObject(forKey: Key.preferredSleepSourceName)
            }
        }
    }

    /// Stable identity for the same preference above -- see
    /// `SleepSessionBuilder.preferredSourceBundleIdentifier`'s doc comment
    /// for why matching by this instead of `preferredSleepSourceName` is
    /// worth a second field rather than a plain rename: a rename in place
    /// would silently stop matching every preference set before it shipped,
    /// with no error and no visible sign why "Preferred source" quietly
    /// stopped doing anything. Both are written together by
    /// `SettingsView.sourceSection` now; this one is `nil` only for a
    /// preference set before this field existed, at which point
    /// `preferredSleepSourceName` alone still keeps it working.
    var preferredSleepSourceBundleIdentifier: String? {
        didSet {
            if let preferredSleepSourceBundleIdentifier {
                defaults.set(preferredSleepSourceBundleIdentifier, forKey: Key.preferredSleepSourceBundleIdentifier)
            } else {
                defaults.removeObject(forKey: Key.preferredSleepSourceBundleIdentifier)
            }
        }
    }

    enum EngineChoice: String, CaseIterable, Identifiable {
        case ruleBased
        case appleIntelligence
        case localLLM

        /// Engines actually worth choosing between today -- `.localLLM` is
        /// deliberately excluded (see `SettingsView.engineSection`'s Labs
        /// row): `LocalLLMInsightEngine` is a stub that always falls back to
        /// rules (`isModelAvailable` is hard-coded `false`), so offering it
        /// in the same picker as two real choices reads as a third real
        /// choice with no way to tell it apart. `allCases` (from
        /// `CaseIterable`) still lists all three -- persistence and the
        /// `localLLM` case itself are unaffected, this only narrows what's
        /// user-selectable.
        static var shippingCases: [EngineChoice] { [.ruleBased, .appleIntelligence] }

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ruleBased: "Rules"
            case .appleIntelligence: "Apple Intelligence"
            case .localLLM: "Bundled model"
            }
        }

        var detail: String {
            switch self {
            case .ruleBased:
                "Deterministic thresholds and correlations. Fast, predictable, always available."
            case .appleIntelligence:
                "Apple's on-device model. Runs locally, nothing downloaded, no network. Falls back to rules if unavailable."
            case .localLLM:
                "Reserved for a bundled MLX or Core ML model. None ships today, so this falls back to rules."
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 8 hours is the default target, overridable in Settings.
        let storedGoal = defaults.double(forKey: Key.sleepGoalMinutes)
        self.sleepGoalMinutes = storedGoal > 0 ? storedGoal : 480
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.bedtimeRemindersEnabled = defaults.bool(forKey: Key.bedtimeRemindersEnabled)
        self.focusSilencesBedtimeNudges = defaults.bool(forKey: Key.focusSilencesBedtimeNudges)
        self.cycleTrackingEnabled = defaults.bool(forKey: Key.cycleTrackingEnabled)
        self.lifestyleInsightsEnabled = defaults.bool(forKey: Key.lifestyleInsightsEnabled)
        self.smartWakeEnabled = defaults.bool(forKey: Key.smartWakeEnabled)
        self.wakeAlarmEnabled = defaults.bool(forKey: Key.wakeAlarmEnabled)
        self.appearance = AppearancePreference(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .dark
        let storedAge = defaults.integer(forKey: Key.age)
        self.age = storedAge > 0 ? storedAge : nil
        self.preferredEngine = EngineChoice(
            rawValue: defaults.string(forKey: Key.preferredEngine) ?? ""
        ) ?? .ruleBased
        self.recoveryModeDate = defaults.object(forKey: Key.recoveryModeDate) as? Date
        self.activeExperimentTag = (defaults.string(forKey: Key.experimentTag)).flatMap(BehaviorTag.init(rawValue:))
        self.experimentStartDate = defaults.object(forKey: Key.experimentStartDate) as? Date
        self.experimentHypothesis = defaults.string(forKey: Key.experimentHypothesis)
        self.experimentPrimaryMetric = (defaults.string(forKey: Key.experimentPrimaryMetric)).flatMap(JournalCorrelator.Metric.init(rawValue:))
        self.experimentDirection = (defaults.string(forKey: Key.experimentDirection)).flatMap(GuidedExperiment.Direction.init(rawValue:))
        self.preferredSleepSourceName = defaults.string(forKey: Key.preferredSleepSourceName)
        self.preferredSleepSourceBundleIdentifier = defaults.string(forKey: Key.preferredSleepSourceBundleIdentifier)
        self.obligationWeekdays = (defaults.array(forKey: Key.obligationWeekdays) as? [Int]).map(Set.init)
            ?? Self.defaultObligationWeekdays
        self.isShiftWorkModeEnabled = defaults.bool(forKey: Key.shiftWorkModeEnabled)
        self.trackedBehaviorTagIdentifiers = (defaults.array(forKey: Key.trackedBehaviorTagIdentifiers) as? [String]).map(Set.init)
    }

    var sleepGoalDisplay: String {
        SleepNightFeatures.formatMinutes(sleepGoalMinutes)
    }

    /// Resets every app-owned preference to its first-launch value and removes
    /// the persisted keys. Assigning first updates the observable in-memory
    /// state; removing afterwards ensures the erase operation leaves no age,
    /// cycle choice, engine choice, schedule, or onboarding marker on disk.
    func resetForDataErasure() {
        sleepGoalMinutes = 480
        hasCompletedOnboarding = false
        bedtimeRemindersEnabled = false
        focusSilencesBedtimeNudges = false
        cycleTrackingEnabled = false
        lifestyleInsightsEnabled = false
        smartWakeEnabled = false
        wakeAlarmEnabled = false
        appearance = .dark
        age = nil
        preferredEngine = .ruleBased
        recoveryModeDate = nil
        activeExperimentTag = nil
        experimentStartDate = nil
        experimentHypothesis = nil
        experimentPrimaryMetric = nil
        experimentDirection = nil
        preferredSleepSourceName = nil
        preferredSleepSourceBundleIdentifier = nil
        obligationWeekdays = Self.defaultObligationWeekdays
        isShiftWorkModeEnabled = false
        trackedBehaviorTagIdentifiers = nil

        let keys = [
            Key.sleepGoalMinutes,
            Key.hasCompletedOnboarding,
            Key.preferredEngine,
            Key.age,
            Key.bedtimeRemindersEnabled,
            Key.focusSilencesBedtimeNudges,
            Key.cycleTrackingEnabled,
            Key.lifestyleInsightsEnabled,
            Key.smartWakeEnabled,
            Key.wakeAlarmEnabled,
            Key.appearance,
            Key.recoveryModeDate,
            Key.experimentTag,
            Key.preferredSleepSourceName,
            Key.preferredSleepSourceBundleIdentifier,
            Key.experimentStartDate,
            Key.experimentHypothesis,
            Key.experimentPrimaryMetric,
            Key.experimentDirection,
            Key.obligationWeekdays,
            Key.shiftWorkModeEnabled,
            Key.trackedBehaviorTagIdentifiers,
        ]
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
