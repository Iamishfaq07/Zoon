import Foundation

/// Schedule support for one shift: where the sleep can go, and what the fixed
/// points around it are.
///
/// **This is not an occupational-health judgement, and the brief says so
/// outright.** It produces no fatigue score, no fitness-for-duty verdict, and
/// no statement about whether anyone is safe to work or to drive. It says
/// where the sleep opportunity is and what time the schedule makes the caffeine
/// and light decisions — facts about a calendar, which is the only thing here
/// that is actually known. `DiagnosticLanguageGuard` covers the medical end of
/// that; `bannedPositioning` below covers the occupational end, and the tests
/// hold every line this type produces to both.
///
/// **Why a shift is classified against the person's own sleep, not the
/// clock.** "Night shift" is not a range of hours — it is a shift that lands
/// on the hours this person would otherwise be asleep. An 18:00–02:00 shift
/// takes three hours off somebody who normally sleeps 23:00–07:00 and nothing
/// at all off somebody who normally sleeps 03:00–11:00; the same two clock
/// times, two different schedules. The habitual window comes from
/// `SleepRunway.Habit`, which is already built per weekday on the shifted
/// circular scale, so the same figures drive the roster and the runway and
/// the two can never disagree about when this person sleeps.
///
/// **Scope: one shift and the sleep either side of it.** The plan places one
/// sleep need around one shift, not a need per calendar day it happens to
/// span. A night worker's cycle is not a day, and slicing it by midnight is
/// how a plan ends up asking for sixteen hours of sleep in thirty-six. The
/// multi-day view is `SleepRunway`'s job, which this feeds rather than
/// duplicates.
///
/// **Opportunity is a ceiling.** Every window below is the room the schedule
/// leaves, not a prediction that anyone sleeps through it — the same
/// distinction `SleepRunway` and `SleepOpportunity` draw, for the same reason:
/// a window too short to fit the need is provable from the calendar today and
/// stays true however the sleep itself goes.
enum ShiftPlan {

    /// Getting from the end of a shift to a bed, and from a bed to the start
    /// of one. A single figure rather than two, because nobody knows their
    /// outbound and inbound commute as different numbers, and a default that
    /// pretends to is a false precision.
    static let defaultCommuteMinutes = 30.0

    /// How much of the habitual sleep window a shift has to cover before it
    /// counts as displacing sleep. A third: less than that and the ordinary
    /// single-window plan still applies, and duplicating it here would put two
    /// contradictory plans on one screen.
    static let displacementFraction = 1.0 / 3.0

    /// Shortfall in the pre-shift window below which a nap is not suggested.
    /// Matches `SleepRunway.warningGapMinutes` — a gap smaller than the most
    /// a bedtime may deliberately move in one night is not something a plan
    /// can act on.
    static let napThresholdMinutes = 20.0

    /// The nap window's own length cap. Beyond this a nap stops being a top-up
    /// and starts being the sleep, and `NapLearning`'s own buckets already
    /// treat over-35-minute naps as a different thing from short ones.
    static let maximumNapMinutes = 30.0

    /// The shortest window worth calling sleep rather than a nap. Ninety
    /// minutes is roughly one sleep cycle: below it the plan would be
    /// labelling forty minutes on a sofa "sleep before your shift", which is
    /// both wrong and the kind of thing somebody would act on.
    static let minimumSleepWindowMinutes = 90.0

    enum Kind: String, Hashable, Sendable {
        /// The shift covers enough of this person's habitual sleep window that
        /// the sleep has to move.
        case displacesSleep
        /// The shift sits inside this person's waking day. The ordinary
        /// single-night plan applies and this type defers to it.
        case ordinary

        var label: String {
            switch self {
            case .displacesSleep: "Overlaps your usual sleep"
            case .ordinary: "Inside your usual day"
            }
        }
    }

    /// One named window in the plan. Kept as a list rather than as seven
    /// optional properties so the surface renders whatever the schedule
    /// actually produced, in order, without a cascade of `if let`s — and so a
    /// window that could not be placed is simply absent rather than rendered
    /// as a zero-length one.
    struct Window: Hashable, Sendable, Identifiable {
        enum Role: String, Hashable, Sendable {
            case preShiftSleep, nap, shift, postShiftSleep
        }

        let role: Role
        let start: Date
        let end: Date

        var id: String { "\(role.rawValue)-\(start.timeIntervalSince1970)" }
        var minutes: Double { end.timeIntervalSince(start) / 60 }
        var interval: DateInterval { DateInterval(start: start, end: end) }

        var title: String {
            switch role {
            case .preShiftSleep: "Sleep before"
            case .nap: "Optional nap"
            case .shift: "Shift"
            case .postShiftSleep: "Sleep after"
            }
        }
    }

    struct Plan: Hashable, Sendable {
        let kind: Kind
        let shift: ShiftRoster.Occurrence
        let windows: [Window]
        /// The last time caffeine would clear before the sleep window it
        /// would otherwise sit inside. Absent when that moment has passed.
        let caffeineCutoff: Date?
        /// When the sleep opportunity ends — the thing an alarm would be set
        /// to, and the only "target" in here.
        let wakeTarget: Date?
        /// Need minus the total sleep opportunity the plan could place.
        /// Positive means the schedule does not leave room for it.
        let shortfallMinutes: Double
        let sentence: String
        let caveat: String

        /// Every window that is an opportunity to sleep, the nap included --
        /// thirty minutes banked before a night shift is thirty minutes.
        var sleepOpportunityMinutes: Double {
            windows
                .filter { $0.role != .shift }
                .reduce(0) { $0 + $1.minutes }
        }

        var napWindow: Window? { windows.first { $0.role == .nap } }
        var isShort: Bool { shortfallMinutes >= SleepRunway.warningGapMinutes }
    }

    /// Words this feature must never reach for, on top of the medical ones
    /// `DiagnosticLanguageGuard` already refuses. Every one of them turns
    /// schedule support into a claim about whether somebody is fit to work,
    /// which is the single thing the brief rules out.
    static let bannedPositioning = [
        "fit to work", "fit for duty", "fitness for duty", "safe to drive",
        "safe to work", "unsafe", "impair", "fatigue risk", "cleared to",
        "not cleared", "medically", "certif"
    ]

    /// Builds the plan for one shift.
    ///
    /// - Parameters:
    ///   - shift: the occurrence being planned around.
    ///   - habit: this person's own bedtime and wake habit. Required: without
    ///     it there is no way to tell a shift that displaces sleep from one
    ///     that does not, and guessing from the clock would be wrong for
    ///     exactly the people this feature exists for.
    ///   - nextShift: the occurrence after this one, when the roster holds
    ///     one. It caps the sleep window after this shift, which is the only
    ///     thing that can produce a shortfall — a single shift leaves an
    ///     unbounded window behind it.
    ///   - commuteMinutes: door-to-door each way.
    ///   - now: windows are truncated at `now`, never drawn in the past.
    static func make(
        shift: ShiftRoster.Occurrence,
        nextShift: ShiftRoster.Occurrence? = nil,
        sleepNeedMinutes: Double,
        habit: SleepRunway.Habit,
        commuteMinutes: Double = defaultCommuteMinutes,
        readyBufferMinutes: Double = ZoonTomorrow.readyBufferMinutes,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Plan? {

        guard sleepNeedMinutes > 0 else { return nil }
        guard let habitualBedtime = habit.overallBedtime, let habitualWake = habit.overallWake
        else { return nil }

        let kind = classify(
            shift: shift,
            habitualBedtime: habitualBedtime,
            habitualWake: habitualWake,
            calendar: calendar
        )

        var windows: [Window] = [
            Window(role: .shift, start: shift.start, end: shift.end)
        ]

        // Leaving for work is the fixed point everything before it is measured
        // back from: the shift's start, less getting ready, less the commute.
        let leaveBy = shift.start
            .addingTimeInterval(-(readyBufferMinutes + commuteMinutes) * 60)
        // Home and settled is the same sum on the other side. Getting-ready
        // time is not subtracted twice -- winding down after a shift is not
        // the same act as getting ready for one, but it takes about as long,
        // which is the only honest thing to say about a figure nobody has
        // measured.
        let homeBy = shift.end
            .addingTimeInterval((commuteMinutes + ZoonTomorrow.windDownLeadMinutes) * 60)

        var preShiftMinutes = 0.0
        var postShiftMinutes = 0.0
        var napMinutes = 0.0

        switch kind {
        case .ordinary:
            // The single-night plan already covers this shape, and a second
            // plan beside it would be two answers to one question. Only the
            // shift itself is placed.
            break

        case .displacesSleep:
            // Sleep before: back from leaving, capped at the need and at now.
            //
            // What is left when there is not a sleep cycle's worth of it is a
            // nap, and is named one. That is not a downgrade for tidiness: a
            // plan that called forty minutes "sleep before your shift" would
            // be describing something nobody can do, and somebody would set an
            // alarm by it.
            let preStart = max(now, leaveBy.addingTimeInterval(-sleepNeedMinutes * 60))
            let available = leaveBy.timeIntervalSince(preStart) / 60
            if available >= minimumSleepWindowMinutes {
                let window = Window(role: .preShiftSleep, start: preStart, end: leaveBy)
                preShiftMinutes = window.minutes
                windows.append(window)
            } else if available >= napThresholdMinutes {
                let minutes = min(available, maximumNapMinutes)
                windows.append(
                    Window(
                        role: .nap,
                        start: leaveBy.addingTimeInterval(-minutes * 60),
                        end: leaveBy
                    )
                )
                napMinutes = minutes
            }

            // Sleep after: forward from getting home, for whatever the windows
            // before could not hold, and cut off by the next shift when there
            // is one. A split night is the shape this schedule actually has;
            // a full need placed after a shift that already had six hours
            // before it would be asking for fourteen.
            //
            // The cap is where the shortfall comes from. A single shift leaves
            // an unbounded window after it, so its shortfall is genuinely
            // zero; back-to-back nights are what squeeze it, and that is the
            // case a roster exists to show.
            let remaining = max(0, sleepNeedMinutes - preShiftMinutes - napMinutes)
            if remaining > 0 {
                let ceiling = nextShift.map {
                    $0.start.addingTimeInterval(-(readyBufferMinutes + commuteMinutes) * 60)
                }
                let end = min(
                    homeBy.addingTimeInterval(remaining * 60),
                    ceiling ?? .distantFuture
                )
                if end > homeBy {
                    let window = Window(role: .postShiftSleep, start: homeBy, end: end)
                    postShiftMinutes = window.minutes
                    windows.append(window)
                }
            }
        }

        let opportunity = preShiftMinutes + napMinutes + postShiftMinutes
        let shortfall = kind == .ordinary ? 0 : max(0, sleepNeedMinutes - opportunity)

        // The nap is deliberately not an anchor for the caffeine cutoff:
        // stopping caffeine eight hours before a thirty-minute nap would put
        // the cutoff in the middle of the previous night.
        let sleepWindows = windows
            .filter { $0.role == .preShiftSleep || $0.role == .postShiftSleep }
            .sorted { $0.start < $1.start }
        let wakeTarget = sleepWindows.last?.end

        // The cutoff is measured against whichever sleep window caffeine would
        // actually land in -- for a night shift that is the one *after* the
        // shift, which puts the cutoff in the middle of it. That is the whole
        // point: it is the time the schedule makes, and it is not obvious.
        let caffeineAnchor = sleepWindows.first { $0.start > now } ?? sleepWindows.last
        let caffeineCutoff = caffeineAnchor.flatMap {
            CaffeineCutoff.time(bedtime: $0.start, now: now)
        }

        return Plan(
            kind: kind,
            shift: shift,
            windows: windows.sorted { $0.start < $1.start },
            caffeineCutoff: kind == .ordinary ? nil : caffeineCutoff,
            wakeTarget: wakeTarget,
            shortfallMinutes: shortfall,
            sentence: sentence(
                kind: kind,
                shortfall: shortfall,
                opportunity: opportunity,
                need: sleepNeedMinutes
            ),
            caveat: caveat(kind: kind)
        )
    }

    /// How much of the habitual sleep window this shift covers.
    ///
    /// The habitual window is expressed on `Statistics`' shifted scale, where
    /// an evening bedtime is negative, so it is rebuilt against the shift's
    /// own day and then intersected. Doing it any other way means asking
    /// whether 23:00 is before 07:00, which has two answers.
    static func classify(
        shift: ShiftRoster.Occurrence,
        habitualBedtime: Double,
        habitualWake: Double,
        calendar: Calendar = .current
    ) -> Kind {
        let day = calendar.startOfDay(for: shift.start)
        // The habitual window is anchored to the night the shift starts in,
        // and then also to the night before, because a shift beginning at
        // 02:00 belongs to the window that opened the previous evening.
        let anchors = [-1, 0, 1].compactMap { offset -> DateInterval? in
            guard let base = calendar.date(byAdding: .day, value: offset, to: day),
                  let bed = SleepRunway.date(
                      minutesFromMidnight: habitualBedtime, on: base, calendar: calendar
                  ),
                  let wake = SleepRunway.date(
                      minutesFromMidnight: habitualWake, on: base, calendar: calendar
                  ),
                  wake > bed
            else { return nil }
            return DateInterval(start: bed, end: wake)
        }

        let overlap = anchors.reduce(0.0) { total, window in
            guard let shared = window.intersection(with: shift.interval) else { return total }
            return total + shared.duration
        }
        guard let longest = anchors.map(\.duration).max(), longest > 0 else { return .ordinary }

        return overlap / longest >= displacementFraction ? .displacesSleep : .ordinary
    }

    private static func sentence(
        kind: Kind,
        shortfall: Double,
        opportunity: Double,
        need: Double
    ) -> String {
        switch kind {
        case .ordinary:
            return "This shift sits inside your usual waking day, so your ordinary plan for the night still applies."
        case .displacesSleep:
            let room = SleepNightFeatures.formatMinutes(opportunity)
            let needed = SleepNightFeatures.formatMinutes(need)
            if shortfall >= SleepRunway.warningGapMinutes {
                return "Around this shift the schedule leaves room for \(room), short of the \(needed) you need."
            }
            return "Around this shift the schedule leaves room for \(room), which covers the \(needed) you need."
        }
    }

    private static func caveat(kind: Kind) -> String {
        switch kind {
        case .ordinary:
            return "Schedule support only. Nothing here is a judgement about the work itself."
        case .displacesSleep:
            return "These are the windows your schedule leaves, not a forecast of how you will sleep in them. "
                + "Schedule support only — nothing here is a judgement about the work itself."
        }
    }
}
