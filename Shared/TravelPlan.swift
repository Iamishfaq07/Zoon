import Foundation

/// A plan for moving a body clock across time zones, anchored to the one
/// Zoon already measured rather than to a textbook sleeper.
///
/// ## What this is careful not to claim
///
/// Circadian phase-shifting is real and well-studied, and the studies are
/// about laboratory light protocols on people whose phase was measured
/// directly from melatonin. This app measures neither. What it has is the
/// person's own sleep timing over recent weeks -- `BodyClock` -- and the
/// arithmetic of two time zones.
///
/// So every rate here is a **rule of thumb, presented as one**. The plan
/// says "shift bedtime 40 minutes earlier" because that is a schedule
/// somebody can follow, not because Zoon has established that this person's
/// clock advances at 40 minutes a day. `rateCaveat` travels with the plan
/// and says exactly that, and nothing in the copy anywhere converts a rate
/// into a prediction about their physiology.
///
/// Two places where the honest answer is "Zoon does not know" are handled
/// explicitly rather than papered over:
///
/// - **Near the antipode.** Past about eight hours, whether a body clock
///   settles by advancing or by delaying stops being a matter of which is
///   arithmetically shorter, and it is not something sleep timing alone can
///   reveal. Light guidance is withheld at that point -- withheld, and said
///   to be withheld -- while the sleep-timing steps remain, because those
///   are just a schedule.
/// - **A body clock still being learned.** `BodyClock.isEstimate` is carried
///   into the plan, so a plan built on eleven nights says so instead of
///   presenting the same confident schedule as one built on ninety.
///
/// ## Integration, not another island
///
/// The V9 spec asks for this to work with Body Clock and Autopilot rather
/// than become a disconnected feature. The anchor is `BodyClock.onsetHour`
/// and `wakeHour` -- the same numbers the Body Clock screen draws -- and the
/// destination light window is `LightCoach.morningWindowMinutes` wide, the
/// same window the Light card uses. A plan that invented its own bedtime or
/// its own morning window would put two different answers on two screens.
enum TravelPlan {

    // MARK: - The trip

    struct Trip: Hashable, Sendable {
        var origin: TimeZone
        var destination: TimeZone
        var departure: Date
        var arrival: Date

        init(origin: TimeZone, destination: TimeZone, departure: Date, arrival: Date) {
            self.origin = origin
            self.destination = destination
            self.departure = departure
            self.arrival = arrival
        }
    }

    /// Which way this trip moves the clock, including the case where the
    /// answer is "not far enough to matter".
    ///
    /// Separate from `plan` so a caller can render the negligible case as a
    /// sentence rather than as an empty screen -- `plan` returns nil there,
    /// and nil on its own does not say why.
    static func direction(for trip: Trip) -> Direction {
        let shift = shiftHours(for: trip)
        guard abs(shift) >= negligibleShiftHours else { return .negligible }
        return shift > 0 ? .eastward : .westward
    }

    /// How many clock hours the destination is ahead of home, at arrival.
    ///
    /// Evaluated at the arrival instant rather than now, because both zones'
    /// offsets can change between booking and landing -- the two ends of a
    /// trip in late March can be an hour different from what today implies.
    ///
    /// Normalised to (-12, 12]: a fourteen-hour-ahead destination is ten
    /// hours behind by the clock, and the shorter description is the one a
    /// schedule should be built from.
    static func shiftHours(for trip: Trip) -> Double {
        let origin = Double(trip.origin.secondsFromGMT(for: trip.arrival))
        let destination = Double(trip.destination.secondsFromGMT(for: trip.arrival))
        var hours = (destination - origin) / 3600
        while hours > 12 { hours -= 24 }
        while hours <= -12 { hours += 24 }
        return hours
    }

    enum Direction: String, Hashable, Sendable {
        /// Destination is ahead. The clock has to *advance*, which is the
        /// harder direction for most people.
        case eastward
        /// Destination is behind. The clock *delays*, which is easier --
        /// staying up late is something bodies do willingly.
        case westward
        /// Not far enough to be worth planning around.
        case negligible
    }

    // MARK: - Rules of thumb

    /// Below this, a trip is a late night, not a time-zone problem.
    static let negligibleShiftHours = 2.0

    /// Minutes per day, eastward. Lower than the westward rate because
    /// advancing a clock is the harder direction -- not because Zoon
    /// measured this person doing it.
    static let advanceMinutesPerDay = 40.0

    /// Minutes per day, westward.
    static let delayMinutesPerDay = 60.0

    /// The most days of pre-trip shifting to ask for. Beyond about four days
    /// a preparation schedule stops being something people follow, and a
    /// plan nobody follows is worse than a shorter one they do.
    static let maximumPreparationDays = 4

    /// The most a bedtime is moved before departure, in total.
    ///
    /// A day cap alone is not enough. Four days westward at an hour a day is
    /// four hours of accumulated shift, which puts the night before a flight
    /// at three in the morning -- advice that gives someone jet lag before
    /// they have left, and that nobody sane follows. Two hours is about the
    /// most that can be absorbed without the preparation costing more than
    /// the trip. Whatever is left over is dealt with at the destination,
    /// which is where the light is anyway.
    static let maximumTotalShiftMinutes = 120.0

    /// Nights of destination repayment, each capped at Autopilot's nightly
    /// shift so the plan and Tonight cannot disagree about how far a night
    /// is allowed to move.
    static let destinationRepaymentNights = 3

    /// Past this, light guidance is withheld rather than guessed.
    static let lightGuidanceLimitHours = 8.0

    // MARK: - Steps

    struct Step: Identifiable, Hashable, Sendable {
        enum Phase: Hashable, Sendable {
            case before(daysBefore: Int)
            case flight
            case destination
        }

        let phase: Phase
        /// "2 days before", "Flight", "At the destination".
        let when: String
        /// The single thing to do.
        let action: String

        var id: String { "\(when)|\(action)" }
    }

    struct Plan: Hashable, Sendable {
        let shiftHours: Double
        let direction: Direction
        /// Days of preparation the plan actually asks for -- capped by
        /// `maximumPreparationDays` and by how long there is before takeoff.
        let preparationDays: Int
        /// Per-day steps, then the flight, then the destination.
        let steps: [Step]
        /// True when light guidance was withheld because the shift is too
        /// close to the antipode to call.
        let lightGuidanceWithheld: Bool
        /// True when the plan is anchored to a body clock Zoon is still
        /// learning.
        let anchoredToEstimate: Bool

        /// The three-line version: what to do before, on the way, and after.
        ///
        /// The per-day steps collapse into one line rather than being
        /// truncated, so the simple plan is a summary of the whole thing
        /// instead of the first third of it.
        var simpleSteps: [Step] {
            var simple: [Step] = []
            if preparationDays > 0, let first = steps.first(where: {
                if case .before = $0.phase { return true }
                return false
            }) {
                simple.append(Step(
                    phase: .before(daysBefore: preparationDays),
                    when: "Before you go",
                    action: first.action + " Repeat each day for \(preparationDays) "
                        + (preparationDays == 1 ? "day" : "days") + "."
                ))
            }
            simple.append(contentsOf: steps.filter { $0.phase == .flight })

            // The destination phase is several steps now: the light advice,
            // then one line per Autopilot-capped repayment night. Same rule
            // as the preparation days above -- collapsed into a line that
            // still says how many nights and how far each one moves, rather
            // than truncated away. Simple is one line per phase, not a
            // shorter prefix of the detailed plan.
            let atDestination = steps.filter { $0.phase == .destination }
            if let light = atDestination.first {
                let nights = atDestination.count - 1
                if nights > 0 {
                    let cap = Int(SleepAutopilot.maximumNightlyShift.rounded())
                    simple.append(Step(
                        phase: .destination,
                        when: light.when,
                        action: light.action + " Then move bedtime \(cap) minutes per night "
                            + "for \(nights) " + (nights == 1 ? "night" : "nights") + "."
                    ))
                } else {
                    simple.append(light)
                }
            }
            return simple
        }

        /// Travels with every plan. The rates are a schedule, not a
        /// measurement of this person's physiology.
        var rateCaveat: String {
            "These timings are a rule of thumb for shifting a schedule, not a measurement "
                + "of your own body clock. Zoon knows when you sleep; it has never measured "
                + "how fast you adjust."
        }

        var estimateCaveat: String? {
            guard anchoredToEstimate else { return nil }
            return "Anchored to a body clock Zoon is still learning, so treat the exact times "
                + "as approximate."
        }

        var lightCaveat: String? {
            guard lightGuidanceWithheld else { return nil }
            return "A shift this large can settle by moving either way, and sleep timing alone "
                + "can't tell which. Zoon is giving you the sleep schedule and no light advice, "
                + "rather than guessing."
        }
    }

    // MARK: - Building the plan

    /// - Parameters:
    ///   - bodyClock: the person's measured schedule. The plan is expressed
    ///     relative to their own bedtime, not to a generic 23:00.
    ///   - now: when the plan is being made, which decides how many days of
    ///     preparation are actually available.
    /// - Returns: nil only for a trip not worth planning -- see
    ///   `Direction.negligible`, which the caller should render as a sentence
    ///   rather than as an empty screen.
    static func plan(
        for trip: Trip,
        bodyClock: BodyClock,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Plan? {
        let shift = shiftHours(for: trip)
        // Qualified: a local named `direction` initialised from a call to
        // `direction` is the shadowing trap, not a self-reference.
        let direction = TravelPlan.direction(for: trip)
        guard direction != .negligible else { return nil }

        let eastward = direction == .eastward
        let ratePerDay = eastward ? advanceMinutesPerDay : delayMinutesPerDay

        let daysAvailable = max(0, calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: trip.departure)
        ).day ?? 0)

        // Never ask for more shifting than the trip needs: a two-hour hop
        // does not want four days of preparation.
        let daysNeeded = Int((abs(shift) * 60 / ratePerDay).rounded(.up))
        let daysWithinShiftCap = Int(maximumTotalShiftMinutes / ratePerDay)
        let preparationDays = min(
            daysAvailable, maximumPreparationDays, daysNeeded, daysWithinShiftCap
        )

        let withheld = abs(shift) > lightGuidanceLimitHours

        var steps: [Step] = []
        for day in stride(from: preparationDays, through: 1, by: -1) {
            let shifted = Int((Double(preparationDays - day + 1) * ratePerDay).rounded())
            steps.append(Step(
                phase: .before(daysBefore: day),
                when: day == 1 ? "The night before" : "\(day) days before",
                action: "Go to bed \(shifted) minutes "
                    + (eastward ? "earlier" : "later")
                    + " than usual — around \(BodyClock.formatted(hour: bodyClock.onsetHour + (eastward ? -1 : 1) * Double(shifted) / 60))."
            ))
        }

        // Hours already banked before takeoff: the night before departure
        // has moved by `preparationDays` days' worth, and the destination
        // nights carry on from there rather than starting over.
        let preparationShiftHours = Double(preparationDays) * ratePerDay / 60

        steps.append(flightStep(for: trip, bodyClock: bodyClock, calendar: calendar))
        steps.append(destinationStep(
            eastward: eastward, bodyClock: bodyClock, withheld: withheld
        ))
        steps.append(contentsOf: repaymentSteps(
            eastward: eastward,
            bodyClock: bodyClock,
            shiftHours: shift,
            preparationShiftHours: preparationShiftHours
        ))

        return Plan(
            shiftHours: shift,
            direction: direction,
            preparationDays: preparationDays,
            steps: steps,
            lightGuidanceWithheld: withheld,
            anchoredToEstimate: bodyClock.isEstimate
        )
    }

    /// Whether to sleep on the plane, decided by what time it will be at the
    /// destination when you land -- which is the only thing on board that
    /// matters. Landing at breakfast means the flight was the night.
    private static func flightStep(
        for trip: Trip,
        bodyClock: BodyClock,
        calendar: Calendar
    ) -> Step {
        var destinationCalendar = calendar
        destinationCalendar.timeZone = trip.destination
        let components = destinationCalendar.dateComponents([.hour], from: trip.arrival)
        let arrivalHour = Double(components.hour ?? 12)

        // Landing between midnight and mid-morning: the flight covered the
        // destination's night, so sleeping on it is the plan.
        let landsAtNight = arrivalHour < 10

        let local = "You land around \(BodyClock.formatted(hour: arrivalHour)) local time."
        return Step(
            phase: .flight,
            when: "On the flight",
            action: landsAtNight
                ? "\(local) Sleep as much of the flight as you can, and set your watch to "
                    + "destination time before you board."
                : "\(local) Stay awake, and set your watch to destination time before you board."
        )
    }

    private static func destinationStep(
        eastward: Bool,
        bodyClock: BodyClock,
        withheld: Bool
    ) -> Step {
        guard !withheld else {
            return Step(
                phase: .destination,
                when: "At the destination",
                action: "Keep local hours from the first day: meals, bedtime and getting up all "
                    + "on the new clock."
            )
        }

        // Minutes, not hours: the window is 90, and rendering it in whole
        // hours produces both a wrong number and "within 1 hours".
        let window = Int(LightCoach.morningWindowMinutes.rounded())
        return Step(
            phase: .destination,
            when: "At the destination",
            action: eastward
                ? "Get outside within \(window) minutes of waking, and keep the evening dim. "
                    + "Morning light is what pulls the clock earlier."
                : "Get outside in the late afternoon and keep the evening bright. "
                    + "Late light is what holds the clock later."
        )
    }

    /// Three destination nights, each moved by Autopilot's 20-minute cap.
    ///
    /// The pre-trip rate is a rule of thumb (40/60 min/day). Once someone
    /// has landed, Tonight already refuses to move more than
    /// `SleepAutopilot.maximumNightlyShift` in a night, and a plan that
    /// asked for 40 would put two different answers on two screens.
    ///
    /// The clock time printed is a *destination-local* bedtime. The body
    /// still wants to sleep at its home `onsetHour`; `shiftHours` is how far
    /// the destination clock is *ahead* of home, so that same instant reads
    /// `onsetHour + shiftHours` there. From that starting point the bedtime
    /// is moved toward the destination's own `onsetHour` by everything
    /// already shifted -- the preparation nights, plus `cap` minutes for
    /// each destination night -- and never past it:
    ///
    ///     remaining = max(0, |shiftHours| - preparationShiftHours - cap * night / 60)
    ///     bedtime   = onsetHour + (eastward ? remaining : -remaining)
    ///
    /// Worked example, London -> Tokyo in July (shift +8, eastward) for a
    /// 23:00 sleeper (`onsetHour` -1) with three preparation days at 40
    /// minutes (2 h): unshifted, 23:00 London is 07:00 Tokyo. Two hours of
    /// preparation bring that to 05:00, and the first night's 20 minutes
    /// to 04:40, then 04:20, then 04:00 -- each step closer to a 23:00
    /// Tokyo bedtime, never beyond it. Westward the sign flips: 23:00
    /// London is 18:00 New York (shift -5); two hours of preparation make
    /// it 20:00 and the first night 20:20. The old form printed
    /// `onsetHour -/+ cap * night` -- 22:40, 22:20, 22:00 for Tokyo -- a
    /// home-clock time with no conversion and no credit for the
    /// preparation, which for that trip meant asking someone to sleep at
    /// what their body felt as 14:40.
    private static func repaymentSteps(
        eastward: Bool,
        bodyClock: BodyClock,
        shiftHours: Double,
        preparationShiftHours: Double
    ) -> [Step] {
        let cap = Int(SleepAutopilot.maximumNightlyShift.rounded())
        return (1...destinationRepaymentNights).map { night in
            let moved = preparationShiftHours + Double(cap * night) / 60
            let remaining = max(0, abs(shiftHours) - moved)
            let hour = bodyClock.onsetHour + (eastward ? 1.0 : -1.0) * remaining
            return Step(
                phase: .destination,
                when: night == 1 ? "First night there" : "Night \(night) there",
                action: "Move bedtime \(cap) minutes "
                    + (eastward ? "earlier" : "later")
                    + " than last night — around \(BodyClock.formatted(hour: hour)). "
                    + "That's Autopilot's nightly cap, not a faster push."
            )
        }
    }
}
