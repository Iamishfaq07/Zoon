import Foundation

/// Extra sleep *opportunity* on the nights before a constraint nobody can
/// move.
///
/// The runway already finds the night the schedule cannot accommodate. This
/// answers the only useful follow-up: is there anywhere earlier in the week
/// with room to spare, and how much. Thursday's 05:30 start cannot be fixed on
/// Wednesday night — but Tuesday can be gone to bed earlier, and Tuesday is
/// still three days away.
///
/// **What this is not.** It is not banking sleep. Sleeping longer beforehand
/// does not create a reserve that a short night then draws on, and no claim
/// here says or implies that it does. The physiology is genuinely unsettled;
/// what is not unsettled is the arithmetic, which is all this offers. Going to
/// bed thirty minutes earlier on Tuesday produces thirty more minutes of
/// opportunity on Tuesday. That is a fact about a clock, in the same sense the
/// runway's own figures are, and it is stated without a promise attached to
/// it.
///
/// So the language is "creating extra sleep opportunity before a known
/// constraint", never "bank", "store", "protect against" or "offset". Those
/// would each be a physiological claim Zoon cannot support, and `Suggestion`
/// carries the caveat that says so.
///
/// **Conservative by construction.** Three limits, none of them adjustable by
/// a caller who happens to want a bigger number:
///
/// - At most `maximumNightlyExtensionMinutes` earlier on any one night, so no
///   suggestion is a large abrupt shift. Moving a bedtime an hour and a half
///   "to prepare" reliably produces a night of lying awake.
/// - Only nights that already have slack. A night with no room of its own is
///   not somewhere to find more; suggesting it would just move the shortfall.
/// - Only `maximumNights` of them, the ones nearest the constraint, because a
///   plan that rearranges somebody's whole week to prepare for one morning is
///   not a plan anybody follows.
///
/// Experimental, and labelled so in the app: the arithmetic is sound and the
/// benefit is not established. `isExperimental` exists so no surface can quietly
/// present this with the confidence of a measurement.
enum SleepBuffer {

    /// The most any one night's bedtime is asked to move.
    ///
    /// Thirty minutes. `SleepAutopilot.maximumNightlyShift` is twenty, but
    /// that governs a nightly drift the autopilot applies on its own; this is
    /// a change the person chooses, once, for a named reason, which carries
    /// further. It is still under an hour on purpose.
    static let maximumNightlyExtensionMinutes = 30.0

    /// Below this, an extension is not worth asking anybody for.
    ///
    /// Ten minutes, matching `SleepAutopilot.deadband`: a suggestion smaller
    /// than the noise in a bedtime is a suggestion to do nothing, dressed up.
    static let minimumUsefulExtensionMinutes = 10.0

    /// How many nights before the constraint to look at.
    static let maximumNights = 3

    /// How far ahead a constraint is worth preparing for.
    ///
    /// A night four days out is still movable; the same night tomorrow is
    /// simply tonight, and Zoon Tomorrow already owns it. One night's notice
    /// is not preparation.
    static let minimumLeadNights = 2

    /// One night with room, and how much of it to use.
    struct Suggestion: Identifiable, Hashable, Sendable {
        /// The morning this night ends on, as `SleepRunway.Day` files it.
        let date: Date
        /// Bedtime as the runway currently plans it.
        let plannedBedtime: Date
        /// How much earlier to go to bed. Never more than
        /// `maximumNightlyExtensionMinutes`, and never more than this night
        /// actually has room for.
        let extensionMinutes: Double

        var id: Date { date }

        var suggestedBedtime: Date {
            plannedBedtime.addingTimeInterval(-extensionMinutes * 60)
        }
    }

    struct Plan: Hashable, Sendable {
        /// The night that cannot be fixed on the day.
        let constrainedDate: Date
        /// Its opportunity, which is what makes it a constraint.
        let constrainedOpportunityMinutes: Double
        /// How short that night is against the need.
        let constrainedGapMinutes: Double
        let suggestions: [Suggestion]
        let sentence: String
        let caveat: String
        /// Always true for now, and read by the surfaces rather than assumed.
        let isExperimental: Bool

        var totalExtensionMinutes: Double {
            suggestions.reduce(0) { $0 + $1.extensionMinutes }
        }
    }

    /// Builds a buffer for the first constrained night on a runway, if there
    /// is one and if there is anywhere earlier with room.
    ///
    /// `nil` rather than an empty plan whenever there is nothing to say: no
    /// constraint, a constraint too close to prepare for, or no night before
    /// it with slack of its own. A surface that renders nothing is better than
    /// one that renders a heading over an empty list.
    ///
    /// - Parameter shiftOccurrences: shifts on the roster, so a night already
    ///   spoken for by one is not offered as a night with room. A rostered
    ///   shift is exactly the kind of constraint that does not appear in a
    ///   habitual bedtime.
    static func build(
        runway: SleepRunway.Plan,
        shiftOccurrences: [ShiftRoster.Occurrence] = [],
        calendar: Calendar = .current
    ) -> Plan? {
        guard let constrained = runway.firstShortDay,
              let index = runway.days.firstIndex(where: { $0.id == constrained.id }),
              index >= minimumLeadNights
        else { return nil }

        // Only the nights before it, nearest first. A night after the
        // constraint is not preparation for it.
        let earlier = runway.days[..<index].suffix(maximumNights)

        let suggestions: [Suggestion] = earlier.reversed().compactMap { day in
            // The room this night already has. A night with none is not a
            // night to find more in.
            let slack = -day.gapMinutes
            guard slack >= minimumUsefulExtensionMinutes else { return nil }

            // A rostered shift overlapping the proposed window means the
            // room is not really there, whatever the habitual bedtime says.
            let proposed = DateInterval(
                start: day.bedtime.addingTimeInterval(-maximumNightlyExtensionMinutes * 60),
                end: day.wake
            )
            guard !shiftOccurrences.contains(where: {
                $0.interval.intersects(proposed)
            }) else { return nil }

            let amount = min(slack, maximumNightlyExtensionMinutes)
            guard amount >= minimumUsefulExtensionMinutes else { return nil }
            return Suggestion(
                date: day.date,
                plannedBedtime: day.bedtime,
                extensionMinutes: (amount / 5).rounded(.down) * 5
            )
        }
        .filter { $0.extensionMinutes >= minimumUsefulExtensionMinutes }
        .sorted { $0.date < $1.date }

        guard !suggestions.isEmpty else { return nil }

        return Plan(
            constrainedDate: constrained.date,
            constrainedOpportunityMinutes: constrained.opportunityMinutes,
            constrainedGapMinutes: constrained.gapMinutes,
            suggestions: suggestions,
            sentence: sentence(constrained: constrained, suggestions: suggestions, calendar: calendar),
            caveat: "Going to bed earlier on those nights creates more sleep opportunity on those nights. It is not sleep saved up for the short one, and Zoon does not claim it protects you from a short night.",
            isExperimental: true
        )
    }

    /// The reading sentence. States the constraint, names the nights with
    /// room, and stops — no promise about what the extra opportunity does.
    static func sentence(
        constrained: SleepRunway.Day,
        suggestions: [Suggestion],
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")

        let constrainedName = formatter.string(from: constrained.date)
        let hours = Int(constrained.opportunityMinutes) / 60
        let minutes = Int(constrained.opportunityMinutes) % 60
        let opportunity = minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"

        let names = suggestions.map { formatter.string(from: $0.date) }
        let listed: String
        switch names.count {
        case 1: listed = names[0]
        case 2: listed = "\(names[0]) and \(names[1])"
        default: listed = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }

        let range = suggestions.map(\.extensionMinutes)
        let low = Int(range.min() ?? 0)
        let high = Int(range.max() ?? 0)
        let amount = low == high ? "\(low) minutes" : "\(low)–\(high) minutes"

        return "\(constrainedName) leaves room for about \(opportunity) of sleep. "
            + "\(listed) \(names.count == 1 ? "has" : "have") more room — "
            + "going to bed \(amount) earlier would add that much opportunity before it."
    }
}
