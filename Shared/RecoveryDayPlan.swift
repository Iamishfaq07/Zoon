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

    /// How far under the night's need counts as clearly short.
    ///
    /// Ninety minutes. Not a threshold with physiology behind it — an hour and
    /// a half under what this person needs is simply past the point where the
    /// day is worth planning differently, and setting it lower would put a
    /// rescue plan in front of somebody after an ordinary Tuesday.
    static let shortfallMinutes = 90.0

    /// Wake-ups above which a night of the right length was still disrupted.
    ///
    /// The other way a night goes wrong. Seven hours broken into six pieces is
    /// not seven hours, and a plan keyed only on duration would have nothing
    /// to say about it.
    static let disruptedWakeCount = 6

    /// Efficiency below which time in bed stopped being sleep.
    static let disruptedEfficiencyPercent = 75.0

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

    /// Whether last night was short or disrupted enough to plan the day around.
    ///
    /// Returns the reason rather than a `Bool`, because the heading has to say
    /// which of the two it was: "after a short night" and "after a broken
    /// night" are different mornings, and a plan that opened with the wrong
    /// one would be describing somebody else's night back at them.
    ///
    /// `nil` for a night Zoon did not measure. Missing is not short.
    static func qualifyingReason(
        asleepMinutes: Double?,
        needMinutes: Double,
        wakeCount: Int?,
        efficiencyPercent: Double?
    ) -> String? {
        if let asleepMinutes, needMinutes - asleepMinutes >= shortfallMinutes {
            let short = Int((needMinutes - asleepMinutes).rounded())
            return "About \(short) minutes under what you usually need"
        }
        if let wakeCount, wakeCount >= disruptedWakeCount {
            return "\(wakeCount) awakenings — the length was there, the continuity was not"
        }
        if let efficiencyPercent, efficiencyPercent < disruptedEfficiencyPercent {
            return "About \(Int(efficiencyPercent.rounded()))% of your time in bed was asleep"
        }
        return nil
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
