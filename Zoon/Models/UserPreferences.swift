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
        static let cycleTrackingEnabled = "zoon.pref.cycleTrackingEnabled"
        static let smartWakeEnabled = "zoon.pref.smartWakeEnabled"
        static let appearance = "zoon.pref.appearance"
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

    /// Wind-down and bedtime notifications. Off until asked for — see
    /// `BedtimeReminder.requestAuthorization`.
    var bedtimeRemindersEnabled: Bool {
        didSet { defaults.set(bedtimeRemindersEnabled, forKey: Key.bedtimeRemindersEnabled) }
    }

    /// Off by default. Turning it on triggers a *separate* HealthKit
    /// authorization request — see `HealthKitManager.requestCycleTrackingAuthorization`
    /// — rather than reading reproductive health data for everyone by default.
    var cycleTrackingEnabled: Bool {
        didSet { defaults.set(cycleTrackingEnabled, forKey: Key.cycleTrackingEnabled) }
    }

    /// Wake-window notification — see `BedtimeReminder.scheduleWakeWindow`.
    var smartWakeEnabled: Bool {
        didSet { defaults.set(smartWakeEnabled, forKey: Key.smartWakeEnabled) }
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

    /// Which insight engine to use. The LLM option is present but stubbed —
    /// see `LocalLLMInsightEngine`.
    var preferredEngine: EngineChoice {
        didSet { defaults.set(preferredEngine.rawValue, forKey: Key.preferredEngine) }
    }

    enum EngineChoice: String, CaseIterable, Identifiable {
        case ruleBased
        case appleIntelligence
        case localLLM

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
        self.cycleTrackingEnabled = defaults.bool(forKey: Key.cycleTrackingEnabled)
        self.smartWakeEnabled = defaults.bool(forKey: Key.smartWakeEnabled)
        self.appearance = AppearancePreference(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .dark
        let storedAge = defaults.integer(forKey: Key.age)
        self.age = storedAge > 0 ? storedAge : nil
        self.preferredEngine = EngineChoice(
            rawValue: defaults.string(forKey: Key.preferredEngine) ?? ""
        ) ?? .ruleBased
    }

    var sleepGoalDisplay: String {
        SleepNightFeatures.formatMinutes(sleepGoalMinutes)
    }
}
