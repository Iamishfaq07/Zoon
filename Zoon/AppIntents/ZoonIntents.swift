import AppIntents
import SwiftData

/// Siri and Shortcuts entry points.
///
/// Declared in the main app target rather than a separate extension -- App
/// Intents don't need one, and adding one would mean a second process reading
/// the same store just to answer a question the app process can answer
/// itself. `GetRecoveryIntent` and `GetSleepSummaryIntent` read the same
/// pre-computed `SleepSnapshot` the widget reads, so "what's my recovery" is
/// instant even if HealthKit sync is slow. `LogSleepTagIntent` is the one
/// intent that writes, so it opens the real SwiftData store via
/// `PersistentStore` rather than the lightweight snapshot.

struct GetRecoveryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recovery"
    static let description = IntentDescription("Your latest recovery score from Zoon.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.read(), !snapshot.isMock else {
            return .result(dialog: "I don't have a recovery reading yet — open Zoon once to get started.")
        }
        // `recoveryPercent` defaults to 0 when the snapshot predates the
        // field or the reading could not be made -- say so rather than
        // announce "0 percent, low".
        guard snapshot.canStateRecovery else {
            return .result(dialog: "Recovery isn't available yet — Zoon needs a few nights of heart-rate data first.")
        }
        let band: String = switch snapshot.recoveryPercent {
        case 67...: "high"
        case 34..<67: "moderate"
        default: "low"
        }
        return .result(dialog: "Your recovery is \(snapshot.recoveryPercent) percent — \(band).")
    }
}

struct GetSleepSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Night's Sleep"
    static let description = IntentDescription("How long you slept and your Sleep Intelligence result for last night.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.read(), !snapshot.isMock else {
            return .result(dialog: "I don't have last night's data yet — open Zoon once to get started.")
        }
        let duration = SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes)
        return .result(dialog: "You slept \(duration) last night. Your Sleep Intelligence was \(snapshot.flagshipScore).")
    }
}

struct LogSleepTagIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Sleep Habit"
    static let description = IntentDescription("Log something that might affect tonight's sleep in Zoon's journal.")

    @Parameter(title: "Habit")
    var tag: BehaviorTag

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$tag) in Zoon")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try PersistentStore.open()
        let store = JournalStore(context: container.mainContext)
        // A behaviour logged today belongs to the night ahead, whose entry is
        // keyed by the morning it ends on -- see `JournalEntry.date`.
        let calendar = Calendar.current
        let nightAhead = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        store.toggle(tag, on: nightAhead)
        return .result(dialog: "Logged \(tag.label) for today.")
    }
}

struct StartNapIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Nap"
    static let description = IntentDescription("Start Zoon's nap timer.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes", default: 20)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes)-minute nap in Zoon")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bounded = min(90, max(10, minutes))
        DeepLink.pending = .nap
        DeepLink.pendingNapMinutes = bounded
        return .result(dialog: "Starting a \(bounded)-minute nap.")
    }
}

struct StartSoundscapeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Sleep Sounds"
    static let description = IntentDescription("Open Zoon's sleep sounds.")
    static let openAppWhenRun = true

    @Parameter(title: "Sound", default: .brownNoise)
    var sound: SoundscapeSound

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$sound) in Zoon")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLink.pending = .soundscapes
        DeepLink.pendingSound = sound.rawValue
        return .result(dialog: "Opening \(sound.label) in Zoon.")
    }
}

/// Starts the Tonight routine: guided breathing and the saved sound scene,
/// with its countdown on the Lock Screen. Opens the app, because the audio
/// session and the routine live there.
struct StartWindDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Wind Down"
    static let description = IntentDescription("Begin Zoon's Tonight routine: guided breathing and your sound scene.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DeepLink.pending = .windDown
        DeepLink.pendingStartsWindDown = true
        return .result(dialog: "Starting your wind-down.")
    }
}

struct GetBedtimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Tonight's Bedtime"
    static let description = IntentDescription("Tonight's bed and wake target from Zoon.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.read(), !snapshot.tonightTargetLabel.isEmpty else {
            return .result(dialog: "I don't have a bedtime target yet — a week of nights and Zoon can suggest one.")
        }
        if snapshot.isTonightTargetHolding {
            return .result(dialog: "Hold \(snapshot.tonightTargetLabel). \(snapshot.tonightTargetNote)")
        }
        return .result(dialog: "Aim for \(snapshot.tonightTargetLabel). \(snapshot.tonightTargetNote)")
    }
}

struct PrepareTomorrowIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare Me for Tomorrow"
    static let description = IntentDescription("Open Zoon Tomorrow to protect a morning start time.")
    static let openAppWhenRun = true

    @Parameter(title: "Hour", default: 8)
    var hour: Int

    @Parameter(title: "Minute", default: 30)
    var minute: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Prepare me for \(\.$hour):\(\.$minute) tomorrow in Zoon")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let boundedHour = min(13, max(0, hour))
        let boundedMinute = min(59, max(0, minute))
        let prefs = UserPreferences()
        prefs.tomorrowHour = boundedHour
        prefs.tomorrowMinute = boundedMinute
        prefs.tomorrowEventEnabled = true
        return .result(dialog: "Zoon will arrange tonight around \(boundedHour):\(String(format: "%02d", boundedMinute)). Open Tomorrow on Today to see the plan.")
    }
}

/// Registers the phrases Siri matches to each intent, and gives Shortcuts a
/// curated set to suggest rather than requiring the user to search for them.
struct ZoonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRecoveryIntent(),
            phrases: [
                "What's my recovery in \(.applicationName)",
                "Check my recovery in \(.applicationName)"
            ],
            shortTitle: "Recovery",
            systemImageName: "bolt.heart.fill"
        )
        AppShortcut(
            intent: GetSleepSummaryIntent(),
            phrases: [
                "How did I sleep in \(.applicationName)",
                "Check last night's sleep in \(.applicationName)"
            ],
            shortTitle: "Last Night",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: LogSleepTagIntent(),
            phrases: [
                "Log a habit in \(.applicationName)",
                "Log to my \(.applicationName) journal"
            ],
            shortTitle: "Log Habit",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: StartNapIntent(),
            phrases: [
                "Start a nap in \(.applicationName)",
                "Nap in \(.applicationName)"
            ],
            shortTitle: "Start Nap",
            systemImageName: "powersleep"
        )
        AppShortcut(
            intent: StartSoundscapeIntent(),
            phrases: [
                "Start sleep sounds in \(.applicationName)",
                "Play white noise in \(.applicationName)"
            ],
            shortTitle: "Sleep Sounds",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: StartWindDownIntent(),
            phrases: [
                "Start wind down in \(.applicationName)",
                "Start my bedtime routine in \(.applicationName)"
            ],
            shortTitle: "Wind Down",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: GetBedtimeIntent(),
            phrases: [
                "What's my bedtime in \(.applicationName)",
                "When should I sleep in \(.applicationName)"
            ],
            shortTitle: "Tonight's Bedtime",
            systemImageName: "bed.double.fill"
        )
        AppShortcut(
            intent: PrepareTomorrowIntent(),
            phrases: [
                "Prepare me for tomorrow in \(.applicationName)",
                "Set up tomorrow in \(.applicationName)"
            ],
            shortTitle: "Tomorrow",
            systemImageName: "sunrise.fill"
        )
    }
}

extension BehaviorTag: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sleep Habit" }

    // The App Intents metadata processor statically analyses this property at
    // build time to generate Siri's vocabulary -- it can't evaluate a
    // `Dictionary(uniqueKeysWithValues: allCases.map { ... })` the way the
    // compiler can, only a literal dictionary. Duplicates the text `.label`
    // already has, but there's no way around it for this one property.
    static var caseDisplayRepresentations: [BehaviorTag: DisplayRepresentation] {
        [
            .alcohol: DisplayRepresentation(title: "Alcohol"),
            .caffeine: DisplayRepresentation(title: "Caffeine"),
            .caffeineLate: DisplayRepresentation(title: "Caffeine after 4pm"),
            .nicotine: DisplayRepresentation(title: "Nicotine"),
            .cannabis: DisplayRepresentation(title: "Cannabis"),
            .sleepAid: DisplayRepresentation(title: "Sleep aid"),
            .magnesium: DisplayRepresentation(title: "Magnesium"),
            .lateMeal: DisplayRepresentation(title: "Ate late"),
            .largeDinner: DisplayRepresentation(title: "Large dinner"),
            .fasted: DisplayRepresentation(title: "Fasted evening"),
            .hydrated: DisplayRepresentation(title: "Well hydrated"),
            .hardTraining: DisplayRepresentation(title: "Hard training"),
            .lateTraining: DisplayRepresentation(title: "Trained late"),
            .restDay: DisplayRepresentation(title: "Rest day"),
            .sauna: DisplayRepresentation(title: "Sauna"),
            .coldPlunge: DisplayRepresentation(title: "Cold plunge"),
            .stretching: DisplayRepresentation(title: "Stretched"),
            .screenBeforeBed: DisplayRepresentation(title: "Screens in bed"),
            .readBeforeBed: DisplayRepresentation(title: "Read before bed"),
            .morningDaylight: DisplayRepresentation(title: "Morning daylight"),
            .stressfulDay: DisplayRepresentation(title: "Stressful day"),
            .travelled: DisplayRepresentation(title: "Travelled"),
            .sharedBed: DisplayRepresentation(title: "Shared bed"),
            .coolRoom: DisplayRepresentation(title: "Cool room"),
            .sick: DisplayRepresentation(title: "Feeling unwell")
        ]
    }
}
