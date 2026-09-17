import Foundation

/// The smallest set of bedtime changes that would close a gap the runway has
/// already found.
///
/// **How this differs from `SleepBuffer`, and why both exist.** The buffer
/// answers "is there room earlier this week, and where" — it offers the slack
/// a night happens to have, without a target. This answers a narrower
/// question: the runway says Friday is fifty-five minutes short; what is the
/// least anybody has to change to close fifty-five minutes? One is an offer,
/// the other is an allocation against a number. They share the reasoning about
/// what a night's slack is, and they are deliberately not merged: a plan that
/// both offered slack and allocated it would have to pick one to show, and the
/// two answers differ whenever the gap is smaller than the room available.
///
/// **It only ever moves bedtimes, and only earlier.** Never a wake time. The
/// wake time is usually the part that cannot move — it is a shift start, a
/// school run, a flight — and "get up later" is precisely the advice that
/// breaks the obligation the runway read off the calendar in the first place.
/// Where the constrained morning's wake is fixed, the plan says so as a step
/// of its own: protect it, and find the minutes on the earlier nights.
///
/// **Rate-limited to `SleepAutopilot.maximumNightlyShift`.** Twenty minutes a
/// night, not the thirty `SleepBuffer` allows, and the difference is not an
/// inconsistency. The buffer's extension is one choice a person makes once,
/// for a named reason. This is a progressive advance across consecutive
/// nights, which is the autopilot's own territory, and a schedule that moves
/// faster than the autopilot would move it is a schedule the autopilot will
/// spend the following week undoing.
///
/// **It predicts nothing.** Every figure is opportunity: minutes a clock does
/// or does not leave room for. Whether the person sleeps them is a question
/// about a night that has not happened, and this says nothing about it — no
/// Recovery, no score, no "you will feel". `residualGapMinutes` states plainly
/// when the adjustments cannot close the gap, because a plan that quietly
/// stopped short would read as one that worked.
enum SleepRunwayOptimizer {

    /// The most any one night's bedtime is moved.
    ///
    /// `SleepAutopilot.maximumNightlyShift`, deliberately read from there
    /// rather than copied: a second constant is how the planning bug in §6
    /// started.
    static var maximumNightlyShiftMinutes: Double { SleepAutopilot.maximumNightlyShift }

    /// Below this, a night's adjustment is not worth asking for.
    static let minimumUsefulShiftMinutes = 5.0

    /// How many nights before the constraint may be adjusted.
    ///
    /// Three. Beyond that the advance stops being preparation and becomes a
    /// different sleep schedule, which is not what somebody asked for when
    /// they wanted Friday to work.
    static let maximumNights = 3

    enum Step: Hashable, Sendable, Identifiable {
        /// Go to bed this many minutes earlier on this night.
        case shiftBedtime(date: Date, earlierMinutes: Double, from: Date)
        /// Keep the constrained morning's wake time where it is.
        case protectWakeTime(date: Date, wake: Date, source: SleepRunway.WakeSource)

        var date: Date {
            switch self {
            case let .shiftBedtime(date, _, _): date
            case let .protectWakeTime(date, _, _): date
            }
        }

        var id: Date { date }

        var minutes: Double {
            if case let .shiftBedtime(_, earlierMinutes, _) = self { return earlierMinutes }
            return 0
        }
    }

    struct Plan: Hashable, Sendable {
        let constrainedDate: Date
        /// The deficit this plan is allocating against.
        let gapMinutes: Double
        let steps: [Step]
        /// What the plan does not reach. Zero when the gap is fully covered.
        let residualGapMinutes: Double
        let sentence: String
        let caveat: String

        var allocatedMinutes: Double { steps.reduce(0) { $0 + $1.minutes } }

        /// Whether the adjustments close the gap on their own.
        var closesTheGap: Bool { residualGapMinutes <= 0 }
    }

    /// Allocates the smallest adjustment that closes the first gap on a runway.
    ///
    /// Nearest the constraint first: a night two days out is a more reliable
    /// place to find minutes than one five days out, because less can change
    /// in between. Each night contributes the least of its own slack, the
    /// nightly rate limit, and what is still needed — so a fifteen-minute gap
    /// produces one fifteen-minute step rather than three five-minute ones.
    ///
    /// `nil` when there is no gap, or when no night before it can contribute.
    /// An empty plan for a week nobody can improve is worse than no plan: it
    /// invites somebody to look for the part they missed.
    static func optimize(
        runway: SleepRunway.Plan,
        shiftOccurrences: [ShiftRoster.Occurrence] = [],
        calendar: Calendar = .current
    ) -> Plan? {
        guard let constrained = runway.firstShortDay,
              let index = runway.days.firstIndex(where: { $0.id == constrained.id }),
              index > 0
        else { return nil }

        let gap = constrained.gapMinutes
        var remaining = gap
        var steps: [Step] = []

        // Nearest the constraint first, and no further back than
        // `maximumNights`.
        let candidates = runway.days[..<index].suffix(maximumNights).reversed()

        for day in candidates where remaining > 0 {
            let slack = -day.gapMinutes
            guard slack >= minimumUsefulShiftMinutes else { continue }

            // A night the roster has spoken for has no room to give, whatever
            // the habitual bedtime says about it. Preserving a shift worker's
            // schedule means not planning inside their shift.
            let proposed = DateInterval(
                start: day.bedtime.addingTimeInterval(-maximumNightlyShiftMinutes * 60),
                end: day.wake
            )
            guard !shiftOccurrences.contains(where: { $0.interval.intersects(proposed) }) else {
                continue
            }

            let amount = min(slack, maximumNightlyShiftMinutes, remaining)
            let rounded = (amount / 5).rounded(.down) * 5
            guard rounded >= minimumUsefulShiftMinutes else { continue }

            steps.append(.shiftBedtime(
                date: day.date, earlierMinutes: rounded, from: day.bedtime
            ))
            remaining -= rounded
        }

        guard !steps.isEmpty else { return nil }

        // The constrained morning itself, when its wake time is pinned by
        // something outside tonight's control. Nothing to do but leave it
        // alone -- which is a step, because the alternative somebody reaches
        // for on a short morning is the snooze button.
        if constrained.wakeSource.isFixed {
            steps.append(.protectWakeTime(
                date: constrained.date, wake: constrained.wake, source: constrained.wakeSource
            ))
        }

        steps.sort { $0.date < $1.date }
        let residual = max(0, remaining)

        return Plan(
            constrainedDate: constrained.date,
            gapMinutes: gap,
            steps: steps,
            residualGapMinutes: residual,
            sentence: sentence(
                constrained: constrained, steps: steps, residual: residual, calendar: calendar
            ),
            caveat: "Every figure here is sleep opportunity — what the clock leaves room for. Moving a bedtime earlier does not predict how the night goes, and Zoon does not forecast recovery days ahead."
        )
    }

    static func sentence(
        constrained: SleepRunway.Day,
        steps: [Step],
        residual: Double,
        calendar: Calendar = .current
    ) -> String {
        let weekday = DateFormatter()
        weekday.calendar = calendar
        weekday.locale = .current
        weekday.setLocalizedDateFormatFromTemplate("EEEE")

        let name = weekday.string(from: constrained.date)
        let gap = Int(constrained.gapMinutes.rounded())

        let moves = steps.compactMap { step -> String? in
            guard case let .shiftBedtime(date, minutes, _) = step else { return nil }
            return "\(weekday.string(from: date)) \(Int(minutes)) min earlier"
        }

        var sentence = "\(name) is about \(gap) minutes short of sleep opportunity. "
            + moves.joined(separator: ", ") + "."

        if residual > 0 {
            sentence += " That leaves about \(Int(residual.rounded())) minutes the week cannot find."
        }
        return sentence
    }
}
