import Foundation

/// Why a night on the runway is short, rather than only that it is.
///
/// `SleepRunway` already says "Friday: -45 min" and says it well. What it
/// cannot say is what did the constraining, and a gap without a cause is not
/// actionable: the reader is told there is a problem and left to work out
/// whether it is the 7:30 meeting, the wake time they set themselves, or
/// simply a habit that drifted late. Those call for completely different
/// responses, and two of the three are things they can change tonight.
///
/// **This attributes; it does not predict.** Every contributor here is read
/// off a schedule the person or their calendar already fixed. Nothing
/// forecasts physiology, nothing claims a night will feel a particular way,
/// and the runway's own caveat about that still applies unchanged.
enum ScheduleFriction {

    /// One reason the opportunity is smaller than the need.
    ///
    /// Ordered by how much the person can do about it tonight, which is the
    /// order that matters when only one can be named as the main constraint:
    /// a meeting is immovable, a wake time they set is theirs to move, and a
    /// late bedtime habit is the most movable of all.
    enum Contributor: String, Codable, Sendable, CaseIterable, Comparable {
        /// A dated commitment read from Calendar.
        case calendarEvent
        /// A shift that pins the morning.
        case shift
        /// Getting-ready time held before the first commitment.
        case readyBuffer
        /// The standing wake time the person set for themselves.
        case protectedWakeTime
        /// A habitual bedtime later than the need allows.
        case lateBedtimeHabit

        /// Lower is harder to move. Used to pick the main constraint, so the
        /// named cause is the binding one rather than whichever was computed
        /// first.
        private var immovability: Int {
            switch self {
            case .calendarEvent: 0
            case .shift: 1
            case .readyBuffer: 2
            case .protectedWakeTime: 3
            case .lateBedtimeHabit: 4
            }
        }

        static func < (lhs: Contributor, rhs: Contributor) -> Bool {
            lhs.immovability < rhs.immovability
        }

        /// Names the thing, not the person. "Early event at 7:30 AM", never
        /// "you scheduled too much".
        func label(at time: Date?, calendar: Calendar) -> String {
            let clock = time.map { ClockText.atomic(formatted($0, calendar: calendar)) }
            switch self {
            case .calendarEvent:
                return clock.map { "Early event at \($0)" } ?? "An early calendar event"
            case .shift:
                return clock.map { "Shift starts at \($0)" } ?? "A shift start"
            case .readyBuffer:
                return "Getting-ready time before your first commitment"
            case .protectedWakeTime:
                return clock.map { "Wake time you set, \($0)" } ?? "The wake time you set"
            case .lateBedtimeHabit:
                return "Your usual bedtime is later than this night needs"
            }
        }

        private func formatted(_ date: Date, calendar: Calendar) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    /// The friction on one runway day.
    struct Reading: Sendable, Hashable {
        let date: Date
        /// What the night actually offers.
        let opportunityMinutes: Double
        /// How far short of the need that falls. Zero or less when the night
        /// is not constrained at all.
        let gapMinutes: Double
        /// Everything contributing, hardest to move first.
        let contributors: [Contributor]
        /// The time the main constraint happens at, when it has one.
        let constraintTime: Date?
        let calendar: Calendar

        /// The one to name. `nil` when the night is not short, because a
        /// constraint on a night with no gap is a fact about the schedule
        /// rather than a problem to solve.
        var mainConstraint: Contributor? {
            guard isConstrained else { return nil }
            return contributors.min()
        }

        var isConstrained: Bool { gapMinutes >= SleepRunway.warningGapMinutes }

        /// The line under the bar.
        var explanation: String? {
            mainConstraint?.label(at: constraintTime, calendar: calendar)
        }
    }

    /// Read the friction off a runway day.
    ///
    /// - Parameters:
    ///   - day: the runway day to explain.
    ///   - firstCommitment: when the morning's first dated commitment starts,
    ///     when there is one. Distinct from the day's wake: the wake is the
    ///     commitment minus getting-ready time, and telling somebody their
    ///     constraint is 7:30 when their meeting is at 8:00 names the wrong
    ///     thing.
    ///   - readyBufferMinutes: how much getting-ready time sits between them.
    ///   - isShiftWork: whether the fixed morning is a shift rather than an
    ///     ordinary meeting. The app already knows; the wake source alone
    ///     cannot tell them apart, and calling a 5am shift "an early event"
    ///     is the sort of wording that makes somebody stop trusting a screen.
    static func read(
        day: SleepRunway.Day,
        firstCommitment: Date? = nil,
        readyBufferMinutes: Double = 0,
        isShiftWork: Bool = false,
        calendar: Calendar = .current
    ) -> Reading {
        var contributors: [Contributor] = []
        var constraintTime: Date?

        switch day.wakeSource {
        case .calendar:
            contributors.append(isShiftWork ? .shift : .calendarEvent)
            constraintTime = firstCommitment ?? day.wake
        case .manual:
            contributors.append(.protectedWakeTime)
            constraintTime = day.wake
        case .habit, .overallHabit:
            // Nothing outside the person pinned this morning, so whatever
            // shortfall exists comes from the other end of the night.
            break
        }

        // Getting-ready time is only a contributor when it is doing real
        // work: a buffer of zero constrains nothing, and naming it would
        // pad the explanation with something the reader cannot act on.
        if readyBufferMinutes > 0, day.wakeSource.isFixed {
            contributors.append(.readyBuffer)
        }

        // A late habitual bedtime contributes to any short night, including
        // one whose morning is pinned by a meeting. Both ends can be wrong at
        // once, and this is the end the reader can move tonight -- excluding
        // it whenever a calendar event exists would hide the only actionable
        // contributor behind the one that is not.
        if day.gapMinutes >= SleepRunway.warningGapMinutes {
            contributors.append(.lateBedtimeHabit)
        }

        return Reading(
            date: day.date,
            opportunityMinutes: day.opportunityMinutes,
            gapMinutes: day.gapMinutes,
            contributors: contributors.sorted(),
            constraintTime: constraintTime,
            calendar: calendar
        )
    }

    /// The whole horizon, in runway order.
    static func read(
        runway: SleepRunway.Plan,
        firstCommitments: [Date: Date] = [:],
        readyBufferMinutes: Double = 0,
        isShiftWork: Bool = false,
        calendar: Calendar = .current
    ) -> [Reading] {
        runway.days.map { day in
            read(
                day: day,
                firstCommitment: firstCommitments[day.date],
                readyBufferMinutes: readyBufferMinutes,
                isShiftWork: isShiftWork,
                calendar: calendar
            )
        }
    }
}
