import Foundation

/// The day after a clearly short or disrupted night, assembled once instead of
/// left in five places.
///
/// Everything here already existed. `LightCoach` knows about the morning
/// window, `NapCoach` about whether a nap helps or eats tonight's pressure,
/// `CaffeineCutoff` about the eight hours before bed, `MovementContext` about
/// how today compares with a usual one, and `ZoonTomorrow` about tonight's
/// window. On the morning that most needs them, they were five separate cards
/// on three screens, each individually correct and collectively a research
/// task for somebody who slept five hours.
///
/// **This adds no physiology and no score.** It is composition: the engines
/// are called, their answers are placed under Morning, Afternoon and Tonight,
/// and the sentences they produced are carried through unedited. A "rescue
/// score" would be a new number claiming to summarise a day that has not
/// happened, which is exactly the thing §13 says not to invent — and it would
/// have to be built from these same engines anyway.
///
/// **One day does not erase a short night.** Nothing here says or implies
/// that it does; there is no "recovered" state to reach and no percentage
/// restored. The plan offers today's ordinary levers, in the order the day
/// presents them, and `caveat` says plainly what it is not.
enum RecoveryDayPlan {

    /// How far under the night's target counts as clearly short.
    ///
    /// Ninety minutes. Not a threshold with physiology behind it — an hour and
    /// a half under what this person was aiming for is simply past the point
    /// where the day is worth planning differently, and setting it lower would
    /// put a rescue plan in front of somebody after an ordinary Tuesday.
    static let shortfallMinutes = 90.0

    /// Awakenings below which fragmentation is not even a candidate.
    ///
    /// **This is necessary and no longer sufficient**, which is the change.
    /// It used to trigger the whole Recovery Day on its own, and that was my
    /// mistake: consumer wake detection is not good enough to carry it. Six
    /// brief detected awakenings can be six genuine wakes, or a restless
    /// hour, or an arm slept on awkwardly — the count alone does not
    /// distinguish them, and a whole "bad night rescue" experience is a heavy
    /// thing to hang on a signal that imprecise.
    ///
    /// So a high count now has to be corroborated by time actually spent
    /// awake. See `qualifyingReason`.
    static let disruptedWakeCount = 6

    /// Efficiency below which time in bed stopped being sleep.
    ///
    /// Only consulted when time in bed was **measured**. Apple Watch alone
    /// never writes an `inBed` sample, so for those nights the window is
    /// inferred from the sleep period itself and efficiency is an artefact of
    /// that inference rather than a measurement — see
    /// `SleepNightFeatures.timeInBedIsEstimated`. Reading a threshold off an
    /// inferred number would fire this feature on the users whose data is
    /// thinnest, which is the opposite of what it is for.
    static let disruptedEfficiencyPercent = 75.0

    /// How far above their own usual time-awake a night has to sit before the
    /// awakenings count as meaningful.
    ///
    /// A robust z of 1.5 against the person's own recent nights. Personal
    /// deviation rather than a global minute count, because what counts as a
    /// disturbed night differs enormously between people — somebody who
    /// habitually spends forty minutes awake has not had a bad night when
    /// they spend forty-five.
    static let wasoElevationZ = 1.5

    /// Nights of history needed before a personal comparison is used.
    static let minimumHistoryNights = 10

    /// The smallest absolute rise in time awake worth calling a broken night.
    ///
    /// Required *alongside* the z, not instead of it, and this is the guard
    /// that stops the z misfiring. A robust z divides by the spread of the
    /// person's own nights, so for somebody very regular — a median around
    /// fifty minutes awake with a couple of minutes of variation — a
    /// four-minute difference scores about 2.7 and clears the threshold. It
    /// is a real statistical deviation and it is not a bad night. Fifteen
    /// minutes is the smallest rise that means anything to somebody's day.
    ///
    /// Found by simulating the gate against its own fixtures before running
    /// it, which is the second time that has caught a threshold of mine that
    /// was technically correct and practically wrong.
    static let minimumWasoElevationMinutes = 15.0

    /// The fallback when history is too thin for a personal comparison.
    ///
    /// An hour awake inside the sleep window is a lot by any reading. Used
    /// only when there is no baseline to compare against — never in
    /// preference to one.
    static let wasoFloorMinutes = 60.0

    enum Part: String, Hashable, Sendable, CaseIterable {
        case morning, afternoon, tonight

        var title: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .tonight: "Tonight"
            }
        }
    }

    struct Step: Identifiable, Hashable, Sendable {
        let part: Part
        let text: String
        /// Which engine said this, so a surface can link back to it and a
        /// reader can find out why. No step here is this file's own opinion.
        let source: String
        let symbol: String

        var id: String { "\(part.rawValue)|\(text)" }
    }

    struct Plan: Hashable, Sendable {
        /// What made the night qualify, for the heading.
        let reason: String
        let steps: [Step]
        let caveat: String

        func steps(in part: Part) -> [Step] { steps.filter { $0.part == part } }

        var parts: [Part] { Part.allCases.filter { !steps(in: $0).isEmpty } }
    }

    /// Whether last night was short or disrupted enough to plan the day
    /// around.
    ///
    /// Returns the reason rather than a `Bool`, because the heading has to say
    /// which of the cases it was: "after a short night" and "after a broken
    /// night" are different mornings, and a plan that opened with the wrong
    /// one would be describing somebody else's night back at them.
    ///
    /// Three ways in, and the second and third both carry a confidence gate
    /// the first does not need:
    ///
    /// 1. **A clear shortfall.** Duration is duration. If somebody slept
    ///    ninety minutes under what they were aiming for, that is true
    ///    whatever the wearable thinks about stages or wake events.
    ///
    /// 2. **Low efficiency, on a measured window.** Efficiency is
    ///    asleep-over-in-bed, so it is only a reading when in-bed was
    ///    actually recorded. On a watch-only night the window is inferred
    ///    from the sleep period and the ratio is close to circular.
    ///
    /// 3. **Many awakenings *and* time awake genuinely elevated for this
    ///    person.** The count alone used to be enough. It is not: consumer
    ///    wake detection is imperfect, and six brief detected awakenings do
    ///    not establish a disturbed night. Corroborated by WASO against this
    ///    person's own recent nights, it does.
    ///
    /// `nil` for a night Zoon did not measure. Missing is not short.
    ///
    /// - Parameter history: recent nights, for the personal WASO comparison.
    ///   Below `minimumHistoryNights` an absolute floor is used instead —
    ///   never in preference to a baseline that exists.
    static func qualifyingReason(
        night: SleepNightFeatures,
        needMinutes: Double,
        history: [SleepNightFeatures] = []
    ) -> String? {
        // 1. Short by duration.
        let asleep = night.timeAsleepMinutes
        if asleep > 0, needMinutes - asleep >= shortfallMinutes {
            let short = Int((needMinutes - asleep).rounded())
            return "About \(short) minutes under what you were aiming for"
        }

        // 2. Low efficiency, only where the window was measured.
        if !night.timeInBedIsEstimated,
           night.timeInBedMinutes > 0,
           night.sleepEfficiencyPercent < disruptedEfficiencyPercent {
            return "About \(Int(night.sleepEfficiencyPercent.rounded()))% of your time in bed was asleep"
        }

        // 3. Fragmentation: the count, corroborated.
        if night.wakeCount >= disruptedWakeCount, isTimeAwakeElevated(night, history: history) {
            let awake = Int(night.awakeMinutes.rounded())
            return "\(night.wakeCount) awakenings and about \(awake) minutes awake — more than your usual"
        }

        return nil
    }

    /// Whether time spent awake inside the sleep window was genuinely high
    /// for this person.
    ///
    /// Personal first: a robust z against their own recent nights, which
    /// handles the person who always spends half an hour awake and the person
    /// who never does without either of them needing a special case. The
    /// absolute floor is only reached when there is no baseline yet.
    static func isTimeAwakeElevated(
        _ night: SleepNightFeatures,
        history: [SleepNightFeatures]
    ) -> Bool {
        let comparable = history
            .filter { $0.date != night.date && $0.awakeMinutes > 0 }
            .map(\.awakeMinutes)

        if comparable.count >= minimumHistoryNights,
           let z = Statistics.robustZ(night.awakeMinutes, in: comparable),
           let usual = Statistics.median(comparable) {
            // Both, deliberately: the z asks "is this unusual for them", the
            // minutes ask "is it enough to matter". A very regular sleeper
            // clears the first on a difference that fails the second.
            return z >= wasoElevationZ
                && night.awakeMinutes - usual >= minimumWasoElevationMinutes
        }
        return night.awakeMinutes >= wasoFloorMinutes
    }

    /// Assembles the day.
    ///
    /// Every argument is another engine's already-computed answer. Nothing is
    /// recomputed here and nothing is inferred: an engine that returned `nil`
    /// contributes no step, and a part with no steps does not appear.
    ///
    /// - Parameters:
    ///   - light: `LightCoach.guidance(...)`, or `nil` outside its window.
    ///   - nap: `NapCoach.recommend(...)`. Its `.avoid` is as much a step as
    ///     its `.recommended` — "not this afternoon" is the advice on a day
    ///     when a nap would cost tonight.
    ///   - caffeineCutoff: `CaffeineCutoff.time(...)`, or `nil` when it has
    ///     already passed.
    ///   - movement: today's `MovementContext.Snapshot`, when there is one.
    ///   - plannedBedtime: tonight's window opening, from `ZoonTomorrow`.
    static func build(
        reason: String,
        light: LightCoach.Guidance?,
        nap: NapCoach.Recommendation?,
        caffeineCutoff: Date?,
        movement: MovementContext.Snapshot?,
        plannedBedtime: Date?,
        calendar: Calendar = .current
    ) -> Plan? {
        var steps: [Step] = []

        if let light {
            steps.append(Step(
                part: .morning, text: light.headline, source: "Light Coach", symbol: light.symbol
            ))
        }

        if let caffeineCutoff {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            steps.append(Step(
                part: .morning,
                text: "Keep caffeine to before \(formatter.string(from: caffeineCutoff))",
                source: "Caffeine cutoff",
                symbol: "cup.and.saucer"
            ))
        }

        if let nap {
            let text: String
            switch nap.advice {
            case let .recommended(durationMinutes):
                text = "A \(durationMinutes)-minute nap if you want one"
            case .optional:
                text = "A short nap is available, not needed"
            case .avoid:
                text = "Better to skip a nap today"
            }
            steps.append(Step(
                part: .afternoon, text: text, source: "Nap Coach", symbol: "powersleep"
            ))
        }

        if let movement {
            steps.append(Step(
                part: .afternoon, text: movement.sentence, source: "Movement", symbol: "figure.walk"
            ))
        }

        if let plannedBedtime {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = .current
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            steps.append(Step(
                part: .tonight,
                text: "Your best available window opens around \(formatter.string(from: plannedBedtime))",
                source: "Zoon Tonight",
                symbol: "moon.stars"
            ))
        }

        guard !steps.isEmpty else { return nil }

        return Plan(
            reason: reason,
            steps: steps,
            caveat: "These are today's ordinary levers, gathered in one place. One day does not undo a short night, and it is not a treatment for anything."
        )
    }
}
