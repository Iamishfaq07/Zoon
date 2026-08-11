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
    static var title: LocalizedStringResource = "Get Recovery"
    static var description = IntentDescription("Your latest recovery score from Zoon.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.read() else {
            return .result(dialog: "I don't have a recovery reading yet — open Zoon once to get started.")
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
    static var title: LocalizedStringResource = "Get Last Night's Sleep"
    static var description = IntentDescription("How long you slept and your sleep score for last night.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SnapshotStore.read() else {
            return .result(dialog: "I don't have last night's data yet — open Zoon once to get started.")
        }
        let duration = SleepNightFeatures.formatMinutes(snapshot.timeAsleepMinutes)
        return .result(dialog: "You slept \(duration) last night, a sleep score of \(snapshot.score).")
    }
}

struct LogSleepTagIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Sleep Habit"
    static var description = IntentDescription("Log something that might affect tonight's sleep in Zoon's journal.")

    @Parameter(title: "Habit")
    var tag: BehaviorTag

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$tag) in Zoon")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try PersistentStore.open()
        let store = JournalStore(context: container.mainContext)
        store.toggle(tag, on: .now)
        return .result(dialog: "Logged \(tag.label) for today.")
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
    }
}

extension BehaviorTag: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Sleep Habit" }

    static var caseDisplayRepresentations: [BehaviorTag: DisplayRepresentation] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, DisplayRepresentation(title: "\($0.label)")) })
    }
}
