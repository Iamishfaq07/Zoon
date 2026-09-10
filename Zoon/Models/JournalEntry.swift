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
    case caffeine
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
    case morningDaylight

    // Environment & state
    case screenBeforeBed
    case readBeforeBed
    case stressfulDay
    case travelled
    case sharedBed
    case coolRoom
    case sick

    var id: String { rawValue }

    /// Whether Zoon may ever propose *increasing* this, and whether it is
    /// something a person elects at all.
    ///
    /// The V10 spec states the rule plainly: *never ask users to increase
    /// harmful exposures.* Until now the experiment picker offered "Doing
    /// more of it" for every one of these tags, alcohol and nicotine
    /// included -- and an app that proposes a fortnight of more drinking to
    /// see what it does to your sleep has crossed a line no amount of
    /// statistical care redeems.
    ///
    /// Three states rather than a boolean, because two different things are
    /// being ruled out. Some of these are choices with a known harm, so only
    /// the reducing direction may be tested. Others are not choices at all
    /// -- proposing either direction means asking somebody to arrange being
    /// ill, or to travel on a schedule that suits a trial.
    enum ExposureControl: Hashable, Sendable {
        /// Testing more of it or less of it is equally reasonable.
        case eitherDirection
        /// Only reducing may be proposed.
        case reduceOnly
        /// Not something the person chooses. No trial is proposed either way.
        case notChosen
    }

    var exposureControl: ExposureControl {
        switch self {
        // Known harms. A trial that cuts these back is a fair question; one
        // that increases them is not a question Zoon gets to ask.
        case .alcohol, .nicotine, .cannabis, .caffeine, .caffeineLate, .sleepAid:
            .reduceOnly
        // Not chosen. Being unwell, travelling and a hard day happen to
        // people; they are context to record, not conditions to assign.
        case .sick, .travelled, .stressfulDay:
            .notChosen
        // Everything else -- eating, training, temperature, screens, reading,
        // hydration, sauna, stretching -- is a genuine choice a person can
        // reasonably be asked to make either way for a couple of weeks.
        case .magnesium, .lateMeal, .largeDinner, .fasted, .hydrated,
             .hardTraining, .lateTraining, .restDay, .sauna, .coldPlunge,
             .stretching, .morningDaylight, .screenBeforeBed, .readBeforeBed, .sharedBed, .coolRoom:
            .eitherDirection
        }
    }

    /// The directions an experiment on this behaviour may take. Empty for a
    /// behaviour nobody elects, which is a refusal rather than an oversight.
    var testableDirections: [GuidedExperiment.Direction] {
        switch exposureControl {
        case .eitherDirection: [.avoid, .pursue]
        case .reduceOnly: [.avoid]
        case .notChosen: []
        }
    }

    /// Why a direction is not offered, in the person's own terms. `nil` when
    /// the pairing is allowed.
    func refusal(for direction: GuidedExperiment.Direction) -> String? {
        guard !testableDirections.contains(direction) else { return nil }
        switch exposureControl {
        case .eitherDirection:
            return nil
        case .reduceOnly:
            return "Zoon will help you test cutting back on \(label.lowercased()), but it will not ask you to have more of it."
        case .notChosen:
            return "\(label) is not something you choose, so there is nothing here to assign. Zoon still records it and uses it when it looks at your nights."
        }
    }

    var label: String {
        switch self {
        case .alcohol: "Alcohol"
        case .caffeine: "Caffeine"
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
        case .morningDaylight: "Morning daylight"
        case .screenBeforeBed: "Screens in bed"
        case .readBeforeBed: "Read before bed"
        case .stressfulDay: "Stressful day"
        case .travelled: "Travelled"
        case .sharedBed: "Shared bed"
        case .coolRoom: "Cool room"
        case .sick: "Feeling unwell"
        }
    }

    /// The behaviour as a yes/no question, for the one-question ask.
    ///
    /// Separate from `label` rather than derived from it. A chip is a noun
    /// the person scans past ("Alcohol"); a question is addressed to them and
    /// has to be answerable with one tap, which means naming the day it is
    /// about. Generating these by pasting "Did you " in front of a label
    /// produces "Did you Cool room?", so each one is written out.
    var question: String {
        switch self {
        case .alcohol: "Did you drink alcohol today?"
        case .caffeine: "Did you have caffeine today?"
        case .caffeineLate: "Did you have caffeine after 4pm today?"
        case .nicotine: "Did you use nicotine today?"
        case .cannabis: "Did you use cannabis today?"
        case .sleepAid: "Did you take a sleep aid tonight?"
        case .magnesium: "Did you take magnesium today?"
        case .lateMeal: "Did you eat late today?"
        case .largeDinner: "Was dinner large today?"
        case .fasted: "Did you skip eating this evening?"
        case .hydrated: "Did you drink enough water today?"
        case .hardTraining: "Did you train hard today?"
        case .lateTraining: "Did you train late today?"
        case .restDay: "Was today a rest day?"
        case .sauna: "Did you use a sauna today?"
        case .coldPlunge: "Did you take a cold plunge today?"
        case .stretching: "Did you stretch today?"
        case .morningDaylight: "Did you spend time outdoors this morning?"
        case .screenBeforeBed: "Were you on a screen in bed tonight?"
        case .readBeforeBed: "Did you read before bed tonight?"
        case .stressfulDay: "Was today stressful?"
        case .travelled: "Did you travel today?"
        case .sharedBed: "Are you sharing a bed tonight?"
        case .coolRoom: "Is your room cool tonight?"
        case .sick: "Are you feeling unwell?"
        }
    }

    var symbol: String {
        switch self {
        case .alcohol: "wineglass"
        case .caffeine: "cup.and.saucer.fill"
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
        case .morningDaylight: "sun.max"
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
        case .alcohol, .caffeine, .caffeineLate, .nicotine, .cannabis, .sleepAid, .magnesium:
            .substances
        case .lateMeal, .largeDinner, .fasted, .hydrated:
            .food
        case .hardTraining, .lateTraining, .restDay, .sauna, .coldPlunge, .stretching, .morningDaylight:
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
///
/// Two calendar days are involved in every row, and they must not be
/// confused. The behaviours happened on day D (the alcohol, the late coffee,
/// the hard session). The night they can affect is the one that *follows*
/// D, and that night is keyed -- here and in `SleepNightRecord` -- by the
/// morning it ends on, D+1. So the entry carrying "drank alcohol on Tuesday"
/// has `date` = Wednesday. Writers (`JournalView`, the watch path in
/// `SleepDataCoordinator.apply`) do that shift; readers join on `date` or
/// `nightKey` and never shift again.
@Model
final class JournalEntry {

    /// Start-of-day for the morning the user woke up — the same key
    /// `SleepNightRecord` uses, so the join is trivial.
    ///
    /// Not the day the behaviours happened on: that is the calendar day
    /// *before* this one. See the type comment.
    @Attribute(.unique) var date: Date

    /// `SleepNightFeatures.nightKey` for the night this entry is actually
    /// about -- the one ending on the morning of `date` -- captured at write
    /// time. Optional and backfill-safe, same pattern as
    /// `SleepNightRecord.nightKey`: existing rows predate this column and
    /// fall back to `date`-based matching. `nil` is also the normal value
    /// for tonight's entry written this evening: the night has not been
    /// slept yet, so it has no key, and `BehaviorObservationRecord` keeps
    /// the answers under a provisional key until it does.
    ///
    /// `date` alone is unsafe as a night-matching key across a timezone
    /// change: it's computed via `Calendar.current` *at whatever moment the
    /// entry was written*, and a night's own `nightKey` is computed from the
    /// timezone that night actually happened in. The two usually agree
    /// (people journal from wherever they slept), but not on a travel day --
    /// exactly when getting this right matters most, since a mismatch here
    /// silently drops the entry from Cause Finder/Guided Experiment matching
    /// rather than producing a visibly wrong answer.
    var nightKey: String?

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

    init(date: Date, tags: [BehaviorTag] = [], note: String? = nil, nightKey: String? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.nightKey = nightKey
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
