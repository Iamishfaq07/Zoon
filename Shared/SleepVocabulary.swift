import Foundation

/// The plain name for every piece of jargon this app shows, and the jargon
/// itself kept alongside it.
///
/// ## The rule
///
/// Lead with meaning, keep the technical term available. Not "dumb it down"
/// -- an advanced user needs "HRV" to compare Zoon against anything else
/// they read, and losing the word would make the app *less* useful to them.
/// The failure being fixed is the opposite one: someone who does not know
/// what HRV is gets a three-letter acronym and a number, and no way in.
///
/// So every term here carries both, and each surface decides which leads
/// based on how much room it has and how much the reader has already been
/// told. A trend sentence has room for "your recovery signal"; a 40-point
/// chart legend does not, and jargon there is correct.
///
/// ## Why this is a table rather than inline strings
///
/// The same concept was already being named three different ways across the
/// app -- "HRV" in the Recovery breakdown, "Heart rate variability" in
/// Sensor Truth, "hrv" as a chart series -- with nothing tying them
/// together. A reader who learns the term in one place should recognise it
/// in the next, and that only holds if there is one place the names live.
enum SleepVocabulary {

    struct Term: Hashable, Sendable {
        /// What it is, in words someone who has never read a sleep study
        /// would use.
        let plain: String
        /// The term the literature and every other app uses. `nil` when the
        /// plain name *is* the standard one.
        let technical: String?
        /// One sentence, for a definition popover.
        let meaning: String

        /// Plain name first, jargon in parentheses: the form for anywhere
        /// with room for both.
        var full: String {
            guard let technical else { return plain }
            return "\(plain) (\(technical))"
        }
    }

    static let hrv = Term(
        plain: "Recovery signal",
        technical: "HRV",
        meaning: "How much the time between your heartbeats varies. More variation usually means a more rested nervous system -- but the number only means anything against your own history, never against someone else's."
    )

    static let restingHeartRate = Term(
        plain: "Resting heart rate",
        technical: "RHR",
        meaning: "Your heart rate when you are completely at rest. It drifts up when your body is working harder than usual -- illness, alcohol, a hard training block."
    )

    static let core = Term(
        plain: "Light sleep",
        technical: "Core",
        meaning: "The bulk of a normal night. Apple Health calls this Core; it is the same thing other trackers call light sleep."
    )

    static let waso = Term(
        plain: "Time awake after falling asleep",
        technical: "WASO",
        meaning: "Minutes spent awake between first falling asleep and finally getting up. Restlessness before you fall asleep is not counted."
    )

    static let sleepDebt = Term(
        plain: "Estimated sleep shortfall",
        technical: "Sleep debt",
        meaning: "How far behind your own sleep need you have fallen over the last two weeks. An estimate, and one you cannot bank credit against by sleeping in."
    )

    static let circadianAlignment = Term(
        plain: "Body-clock timing",
        technical: "Circadian alignment",
        meaning: "Whether last night sat where your body expects to sleep. Going to bed at a very different hour than usual costs you even when the hours add up."
    )

    static let sleepEfficiency = Term(
        plain: "Time asleep while in bed",
        technical: "Sleep efficiency",
        meaning: "The share of your time in bed that you were actually asleep."
    )

    static let stagePattern = Term(
        plain: "Stage pattern",
        technical: "Sleep architecture",
        meaning: "How tonight's split between deep, REM and light sleep compares with your own usual split. A night far from your pattern in either direction is worth noticing; it is not a mark out of ten."
    )

    static let regularity = Term(
        plain: "Schedule consistency",
        technical: "Timing consistency",
        meaning: "How closely each day's sleep timing matches the day before."
    )

    static let all: [Term] = [
        hrv, restingHeartRate, core, waso, sleepDebt,
        circadianAlignment, sleepEfficiency, stagePattern, regularity
    ]
}
