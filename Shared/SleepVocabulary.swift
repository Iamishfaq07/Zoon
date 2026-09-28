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
        /// What is usual, in plain numbers, when there is something honest
        /// to say. Shown under the meaning in the glossary.
        var typical: String? = nil
        /// SF Symbol for the glossary row.
        var symbol: String = "character.book.closed"

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
        meaning: "How much the time between your heartbeats varies. More variation usually means a more rested nervous system. It differs a lot between people and falls with age, so your own history is the fairest comparison.",
        typical: "Most adults' Apple Watch readings sit between about 20 and 75 ms, lower with age.",
        symbol: "waveform.path.ecg"
    )

    static let restingHeartRate = Term(
        plain: "Resting heart rate",
        technical: "RHR",
        meaning: "Your heart rate when you are completely at rest. It drifts up when your body is working harder than usual -- illness, alcohol, a hard training block.",
        typical: "60–100 bpm for adults, lower with fitness. Women's usually runs a few beats higher than men's.",
        symbol: "heart.fill"
    )

    static let core = Term(
        plain: "Light sleep",
        technical: "Core",
        meaning: "The bulk of a normal night. Apple Health calls this Core; it is the same thing other trackers call light sleep.",
        typical: "Roughly half of the night.",
        symbol: "moon.fill"
    )

    static let waso = Term(
        plain: "Time awake after falling asleep",
        technical: "WASO",
        meaning: "Minutes spent awake between first falling asleep and finally getting up. Restlessness before you fall asleep is not counted.",
        typical: "Under about 20 minutes on an efficient night.",
        symbol: "eye"
    )

    static let sleepDebt = Term(
        plain: "Estimated sleep shortfall",
        technical: "Sleep debt",
        meaning: "How far behind your own sleep need you have fallen lately, with recent nights counting most and older ones fading. An estimate, and one you cannot bank credit against by sleeping in.",
        symbol: "hourglass.bottomhalf.filled"
    )

    static let circadianAlignment = Term(
        plain: "Body-clock timing",
        technical: "Circadian alignment",
        meaning: "Whether last night sat where your body expects to sleep. Going to bed at a very different hour than usual costs you even when the hours add up.",
        symbol: "sun.and.horizon.fill"
    )

    static let sleepEfficiency = Term(
        plain: "Time asleep while in bed",
        technical: "Sleep efficiency",
        meaning: "The share of your time in bed that you were actually asleep.",
        typical: "85% or more is considered efficient.",
        symbol: "bed.double.fill"
    )

    static let stagePattern = Term(
        plain: "Stage pattern",
        technical: "Sleep architecture",
        meaning: "How tonight's split between deep, REM and light sleep compares with your own usual split. A night far from your pattern in either direction is worth noticing; it is not a mark out of ten.",
        symbol: "chart.bar.fill"
    )

    static let regularity = Term(
        plain: "Schedule consistency",
        technical: "Timing consistency",
        meaning: "How closely each day's sleep timing matches the day before.",
        symbol: "calendar"
    )

    // MARK: - The rest of the glossary
    //
    // Every word a screen puts in front of someone, so the glossary can
    // answer "what does this mean?" for all of them, not only the nine that
    // started this table.

    static let deep = Term(
        plain: "Deep sleep",
        technical: "Slow-wave sleep",
        meaning: "The heaviest sleep, when the body repairs itself and the brain clears the day. Most of it comes in the first few hours of the night.",
        typical: "Usually 13–23% of the night, less as you get older.",
        symbol: "moon.zzz.fill"
    )

    static let rem = Term(
        plain: "Dream sleep",
        technical: "REM",
        meaning: "Rapid eye movement sleep, when most vivid dreams happen. It helps memory and mood, and grows longer toward morning.",
        typical: "Usually 20–25% of the night.",
        symbol: "sparkles"
    )

    static let sleepNeed = Term(
        plain: "Sleep need",
        technical: nil,
        meaning: "How much sleep your body asks for on an ordinary night. Zoon starts from your goal and learns your real figure from your best-rested nights.",
        typical: "7–9 hours for most adults, 8–10 for teenagers and 7–8 over 65.",
        symbol: "target"
    )

    static let sleepScore = Term(
        plain: "Sleep score",
        technical: "Sleep Intelligence",
        meaning: "One number for last night out of 100, built from how long you slept against your need, how unbroken it was, how regular your timing is and how your stages compared with your usual.",
        typical: "70–84 is good, 85 and above is excellent.",
        symbol: "gauge.with.dots.needle.67percent"
    )

    static let recovery = Term(
        plain: "Morning recovery",
        technical: "Recovery score",
        meaning: "How rested your body looked on waking, from your overnight heart signals and your sleep, each compared with your own normal. It does not change during the day.",
        symbol: "bolt.heart.fill"
    )

    static let dailyLoad = Term(
        plain: "Daily load",
        technical: "Strain",
        meaning: "How hard your heart worked today, mostly from exercise and activity. A heavy day raises tonight's sleep need a little.",
        symbol: "flame.fill"
    )

    static let energyReserve = Term(
        plain: "Energy reserve",
        technical: nil,
        meaning: "An estimate of how much energy you have left right now. Sleep refills it, and activity and stress through the day drain it.",
        symbol: "battery.75percent"
    )

    static let bodyClock = Term(
        plain: "Body clock",
        technical: "Circadian rhythm",
        meaning: "Your internal 24-hour timer. It decides when you feel sleepy and alert, and it is set mostly by morning light and regular sleep times.",
        symbol: "clock.fill"
    )

    static let windDown = Term(
        plain: "Wind-down",
        technical: nil,
        meaning: "The quiet half hour before bed: dim lights, screens away, something calm. It gives your body the signal that sleep is coming.",
        symbol: "moon.haze.fill"
    )

    static let sleepLatency = Term(
        plain: "Time to fall asleep",
        technical: "Sleep latency",
        meaning: "How long it takes from lying down to falling asleep.",
        typical: "Under 20 minutes for most people.",
        symbol: "hourglass"
    )

    static let respiratoryRate = Term(
        plain: "Breathing rate",
        technical: "Respiratory rate",
        meaning: "Breaths per minute while you sleep. It is very steady from night to night, so a rise of one or two breaths can be an early sign of illness.",
        typical: "About 12–20 breaths a minute for adults.",
        symbol: "lungs.fill"
    )

    static let bloodOxygen = Term(
        plain: "Blood oxygen",
        technical: "SpO₂",
        meaning: "How much of your blood is carrying oxygen, measured by your watch during the night.",
        typical: "95–100% is usual; it can dip slightly in sleep.",
        symbol: "drop.fill"
    )

    static let wristTemperature = Term(
        plain: "Wrist temperature",
        technical: nil,
        meaning: "How warm your wrist was overnight compared with your own normal. Illness, alcohol, a hot room and the menstrual cycle all move it.",
        symbol: "thermometer.medium"
    )

    static let breathingDisturbances = Term(
        plain: "Breathing disturbances",
        technical: nil,
        meaning: "Apple Watch's count of moments when your breathing was interrupted during sleep. It is the signal behind Apple's sleep apnea notifications, not a diagnosis.",
        symbol: "waveform.path.ecg"
    )

    static let cardioFitness = Term(
        plain: "Cardio fitness",
        technical: "VO₂ max",
        meaning: "How well your heart and lungs deliver oxygen during exercise. Apple Watch estimates it from outdoor walks and runs. It falls with age, and exercise raises it at any age.",
        symbol: "figure.run"
    )

    static let all: [Term] = [
        sleepScore, sleepNeed, sleepDebt, deep, rem, core, waso, sleepLatency,
        sleepEfficiency, stagePattern, regularity, bodyClock, circadianAlignment, windDown,
        recovery, hrv, restingHeartRate, respiratoryRate, bloodOxygen, wristTemperature,
        breathingDisturbances, cardioFitness, dailyLoad, energyReserve
    ]
}
