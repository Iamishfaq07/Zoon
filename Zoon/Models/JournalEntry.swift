import Foundation
import SwiftData

/// Things you did that might have affected the night.
///
/// Whoop's journal. It's the feature that turns a passive tracker into
/// something that can answer *why*: HealthKit knows your HRV dropped, but only
/// you know you had three drinks. Tag the behaviour, and after a couple of weeks
/// the correlation engine can tell you what actually costs you.
///
/// Deliberately a small, fixed vocabulary rather than free text. Free-text
/// journalling produces data nobody can correlate; twenty checkboxes produce
/// something you can actually run statistics against.
enum BehaviorTag: String, Codable, CaseIterable, Identifiable, Sendable {

    // Substances
    case alcohol
    case caffeineLate
    case nicotine
    case cannabis
    case sleepAid
    case magnesium

    // Timing & food
    case lateMeal
    case largeDinner
    case fasted
    case hydrated

    // Activity
    case hardTraining
    case lateTraining
    case restDay
    case sauna
    case coldPlunge
    case stretching

    // Environment & state
    case screenBeforeBed
    case readBeforeBed
    case stressfulDay
    case travelled
    case sharedBed
    case coolRoom
    case sick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alcohol: "Alcohol"
        case .caffeineLate: "Caffeine after 4pm"
        case .nicotine: "Nicotine"
        case .cannabis: "Cannabis"
        case .sleepAid: "Sleep aid"
        case .magnesium: "Magnesium"
        case .lateMeal: "Ate late"
        case .largeDinner: "Large dinner"
        case .fasted: "Fasted evening"
        case .hydrated: "Well hydrated"
        case .hardTraining: "Hard training"
        case .lateTraining: "Trained late"
        case .restDay: "Rest day"
        case .sauna: "Sauna"
        case .coldPlunge: "Cold plunge"
        case .stretching: "Stretched"
        case .screenBeforeBed: "Screens in bed"
        case .readBeforeBed: "Read before bed"
        case .stressfulDay: "Stressful day"
        case .travelled: "Travelled"
        case .sharedBed: "Shared bed"
        case .coolRoom: "Cool room"
        case .sick: "Feeling unwell"
        }
    }

    var symbol: String {
        switch self {
        case .alcohol: "wineglass"
        case .caffeineLate: "cup.and.saucer"
        case .nicotine: "smoke"
        case .cannabis: "leaf"
        case .sleepAid: "pills"
        case .magnesium: "pills.circle"
        case .lateMeal: "fork.knife"
        case .largeDinner: "takeoutbag.and.cup.and.straw"
        case .fasted: "circle.slash"
        case .hydrated: "drop"
        case .hardTraining: "figure.run"
        case .lateTraining: "figure.run.circle"
        case .restDay: "figure.cooldown"
        case .sauna: "flame"
        case .coldPlunge: "snowflake"
        case .stretching: "figure.flexibility"
        case .screenBeforeBed: "iphone"
        case .readBeforeBed: "book"
        case .stressfulDay: "exclamationmark.triangle"
        case .travelled: "airplane"
        case .sharedBed: "person.2"
        case .coolRoom: "thermometer.snowflake"
        case .sick: "cross.case"
        }
    }

    var category: Category {
        switch self {
        case .alcohol, .caffeineLate, .nicotine, .cannabis, .sleepAid, .magnesium:
            .substances
        case .lateMeal, .largeDinner, .fasted, .hydrated:
            .food
        case .hardTraining, .lateTraining, .restDay, .sauna, .coldPlunge, .stretching:
            .activity
        case .screenBeforeBed, .readBeforeBed, .stressfulDay, .travelled, .sharedBed, .coolRoom, .sick:
            .environment
        }
    }

    enum Category: String, CaseIterable, Identifiable, Sendable {
        case substances, food, activity, environment

        var id: String { rawValue }

        var label: String {
            switch self {
            case .substances: "Substances"
            case .food: "Food & Drink"
            case .activity: "Activity"
            case .environment: "Environment & State"
            }
        }

        var tags: [BehaviorTag] {
            BehaviorTag.allCases.filter { $0.category == self }
        }
    }
}

/// A quick subjective read on how the morning feels, logged separately from
/// any measured score.
///
/// Deliberately not fed into `RecoveryScore`, `SleepIntelligenceScore`, or any
/// other computed metric: those are built specifically to be measured rather
/// than self-reported, and blending a five-point mood scale into a number
/// built from HRV and sleep staging would muddy what that number means
/// without making it more accurate. This exists for the user's own record,
/// and as a future confounder `JournalCorrelator` could match on -- not
/// (yet) as scoring input.
enum MorningFeeling: Int, Codable, CaseIterable, Identifiable, Sendable {
    case terrible = 1, poor, okay, good, great

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .terrible: "Terrible"
        case .poor: "Poor"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var symbol: String {
        switch self {
        case .terrible: "face.dashed"
        case .poor: "cloud.rain"
        case .okay: "minus.circle"
        case .good: "sun.min"
        case .great: "sun.max"
        }
    }
}

/// A single 1–5 self-report dimension, collected optionally alongside the
/// overall `MorningFeeling` tap.
///
/// Kept separate from `MorningFeeling` (rather than replacing it) because the
/// single-tap feeling is the compact default -- most mornings, most users
/// tap once and move on. These four are the "tell us more" expansion: rested,
/// energy, sleepiness and mood are distinct enough subjectively (someone can
/// feel rested but low-energy, or alert but in a bad mood) that collapsing
/// them into one number would lose exactly the signal that makes them useful
/// to `JournalCorrelator` as confounders and to Sleep Need validation later.
///
/// Same non-scoring rule as `MorningFeeling`: never blended into `RecoveryScore`,
/// `SleepIntelligenceScore`, or any other measured metric.
enum CheckInDimension: String, CaseIterable, Identifiable, Sendable {
    case rested, energy, sleepiness, mood

    var id: String { rawValue }

    var question: String {
        switch self {
        case .rested: "How rested do you feel?"
        case .energy: "Energy level?"
        case .sleepiness: "How alert are you?"
        case .mood: "Mood this morning?"
        }
    }

    var lowLabel: String {
        switch self {
        case .rested: "Not rested"
        case .energy: "Drained"
        case .sleepiness: "Very sleepy"
        case .mood: "Low"
        }
    }

    var highLabel: String {
        switch self {
        case .rested: "Fully rested"
        case .energy: "Energized"
        case .sleepiness: "Fully alert"
        case .mood: "Great"
        }
    }
}

/// One day's tagged behaviours, keyed to the night they preceded.
@Model
final class JournalEntry {

    /// Start-of-day for the morning the user woke up — the same key
    /// `SleepNightRecord` uses, so the join is trivial.
    @Attribute(.unique) var date: Date

    /// Stored as raw strings rather than an array of enums: SwiftData persists
    /// `[String]` natively, and an unknown value from a future build then decays
    /// to "ignored" instead of failing to decode the whole row.
    var tagIdentifiers: [String]

    /// Optional free-text note. Never fed to the correlation engine — it's for
    /// the user's own recall.
    var note: String?

    /// This morning's self-reported feeling, if logged. Optional so existing
    /// stores migrate without assigning every historical row a value nobody
    /// actually reported -- same backfill-safe pattern used for
    /// `SleepNightRecord.nightKey` and `.timeZoneIdentifier`.
    var feelingRaw: Int?

    /// The four Morning Check-In V2 dimensions, 1...5. Optional both because
    /// existing rows migrate without them and because each is its own
    /// separately-skippable question -- someone might log rested and energy
    /// but not mood.
    var restedRaw: Int?
    var energyRaw: Int?
    var sleepinessRaw: Int?
    var moodRaw: Int?

    var updatedAt: Date

    init(date: Date, tags: [BehaviorTag] = [], note: String? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.tagIdentifiers = tags.map(\.rawValue)
        self.note = note
        self.updatedAt = .now
    }

    var feeling: MorningFeeling? {
        get { feelingRaw.flatMap(MorningFeeling.init(rawValue:)) }
        set {
            feelingRaw = newValue?.rawValue
            updatedAt = .now
        }
    }

    var rested: Int? {
        get { restedRaw }
        set { restedRaw = newValue.map { min(5, max(1, $0)) }; updatedAt = .now }
    }

    var energy: Int? {
        get { energyRaw }
        set { energyRaw = newValue.map { min(5, max(1, $0)) }; updatedAt = .now }
    }

    var sleepiness: Int? {
        get { sleepinessRaw }
        set { sleepinessRaw = newValue.map { min(5, max(1, $0)) }; updatedAt = .now }
    }

    var mood: Int? {
        get { moodRaw }
        set { moodRaw = newValue.map { min(5, max(1, $0)) }; updatedAt = .now }
    }

    func value(for dimension: CheckInDimension) -> Int? {
        switch dimension {
        case .rested: rested
        case .energy: energy
        case .sleepiness: sleepiness
        case .mood: mood
        }
    }

    func setValue(_ value: Int?, for dimension: CheckInDimension) {
        switch dimension {
        case .rested: rested = value
        case .energy: energy = value
        case .sleepiness: sleepiness = value
        case .mood: mood = value
        }
    }

    var tags: [BehaviorTag] {
        get { tagIdentifiers.compactMap(BehaviorTag.init(rawValue:)) }
        set {
            tagIdentifiers = newValue.map(\.rawValue)
            updatedAt = .now
        }
    }

    func toggle(_ tag: BehaviorTag) {
        if tagIdentifiers.contains(tag.rawValue) {
            tagIdentifiers.removeAll { $0 == tag.rawValue }
        } else {
            tagIdentifiers.append(tag.rawValue)
        }
        updatedAt = .now
    }

    func contains(_ tag: BehaviorTag) -> Bool {
        tagIdentifiers.contains(tag.rawValue)
    }
}
