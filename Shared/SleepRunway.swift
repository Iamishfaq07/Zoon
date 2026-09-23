import Foundation

/// The next several mornings, and where the schedule stops leaving room for
/// the sleep this person needs.
///
/// Zoon Tomorrow answers one night. This answers the question a week ahead of
/// it: **where does insufficient sleep become unavoidable, while there is
/// still time to do something about it?** Somebody with a 06:00 start on
/// Thursday cannot fix Thursday on Wednesday night; they can move Tuesday.
///
/// **Opportunity is a ceiling, not a forecast.** Every figure here is the
/// most sleep a schedule leaves room for, assuming the person is asleep for
/// the whole window. Nobody is. That is deliberate: a window too short to fit
/// the need is a fact about the calendar, provable now, and it stays true
/// however the night itself goes. A predicted *achieved* duration would be a
/// physiological claim several days out, which is exactly what this must not
/// make. `SleepOpportunity` is the same distinction measured after the fact.
///
/// Nothing here predicts Recovery, or a score, or how anyone will feel.
enum SleepRunway {

    /// How far ahead to plan. Beyond about a week the habitual inputs stop
    /// describing the same person's schedule, and a calendar that far out is
    /// mostly empty anyway.
    static let horizonDays = 7

    /// Same-weekday nights needed before a weekday-specific habit is used
    /// rather than the overall one.
    ///
    /// Three, because the distinction being drawn — a Saturday lie-in
    /// against a Tuesday alarm — is large and shows up immediately, and
    /// waiting for a statistically comfortable count would mean never using
    /// it: a fortnight of history holds two of each weekday.
    static let minimumWeekdayNights = 3

    /// Nights of history needed before any habitual figure is used at all.
    static let minimumNights = 7

    /// A gap this size or larger is worth a warning.
    ///
    /// Twenty minutes, matching `SleepAutopilot.maximumNightlyShift`: a
    /// shortfall smaller than the most a bedtime may move in one night is
    /// not something a plan can act on anyway.
    static let warningGapMinutes = 20.0

    /// Where a morning's wake time came from.
    enum WakeSource: String, Hashable, Sendable {
        /// A dated commitment, read from Calendar.
        case calendar
        /// The standing morning time the person set.
        case manual
        /// A sleep plan the person saved for this night: bed and wake both.
        /// The same plan tonight's episode, the reminders and the alarm use,
        /// so the runway cannot show a habit where they show the plan.
        case plan
        /// This person's own habit for that weekday.
        case habit
        /// This person's own habit, overall — not enough same-weekday nights.
        case overallHabit

        var label: String {
            switch self {
            case .calendar: "From your calendar"
            case .manual: "The time you set"
            case .plan: "Your saved plan"
            case .habit: "Your usual for this day"
            case .overallHabit: "Your usual"
            }
        }

        /// Whether this morning is pinned by something outside the person's
        /// control tonight. A habit can move; a meeting cannot.
        var isFixed: Bool { self == .calendar || self == .manual || self == .plan }
    }

    struct Day: Identifiable, Hashable, Sendable {
        /// The morning being planned for.
        let date: Date
        let needMinutes: Double
        /// The most sleep this schedule leaves room for.
        let opportunityMinutes: Double
        let bedtime: Date
        let wake: Date
        let wakeSource: WakeSource
        /// Projected outstanding shortfall at the end of this night, on the
        /// optimistic assumption that every window above was slept in full.
        let projectedShortfallMinutes: Double

        var id: Date { date }

        /// Need minus opportunity. Positive means the schedule cannot fit it.
        var gapMinutes: Double { needMinutes - opportunityMinutes }

        var isShort: Bool { gapMinutes >= SleepRunway.warningGapMinutes }
    }

    struct Plan: Hashable, Sendable {
        let days: [Day]
        /// The first morning the schedule cannot accommodate, if any.
        let firstShortDay: Day?
        let sentence: String
        let caveat: String
        let confidence: MetricConfidence
        /// Whether any Calendar commitment fed this at all.
        let usedCalendar: Bool
    }

    /// Builds the horizon.
    ///
    /// - Parameters:
    ///   - nights: history, any order. Fewer than `minimumNights` produces
    ///     `nil` rather than a runway drawn from a habit nobody has yet.
    ///   - planning: baseline need and the outstanding shortfall, with the
    ///     repayment **not** yet applied. The horizon walks the ledger itself,
    ///     night by night, so a pre-composed total would be repaid twice --
    ///     see `SleepPlanningInputs`.
    ///   - commitments: start times of known morning obligations, keyed by
    ///     the start of the local day they fall on. Only mornings before
    ///     `ZoonTomorrow.latestMorningEventHour` move a wake time.
    ///   - manual: the standing morning time, when the person set one. It
    ///     applies to obligation weekdays only — a 07:00 alarm someone keeps
    ///     for work is not a claim about their Sunday.
    ///   - obligationWeekdays: `Calendar` weekday numbers the manual time
    ///     applies to.
    ///   - readyBufferMinutes: the person's own getting-ready time.
    static func build(
        now: Date = .now,
        nights: [SleepNightFeatures],
        planning: SleepPlanningInputs,
        commitments: [Date: Date] = [:],
        manual: ManualCommitment? = nil,
        obligationWeekdays: Set<Int> = [],
        readyBufferMinutes: Double = ZoonTomorrow.readyBufferMinutes,
        plans: [PersonalSetup.SleepPlan] = [],
        calendar: Calendar = .current
    ) -> Plan? {
        // Every night on the horizon is planned from the baseline. Today's
        // strain bonus and nap credit are deliberately absent: they are facts
        // about tonight, and spreading them across a week would plan Friday
        // around Monday's hard session.
        let baseNeed = planning.futureNightNeedMinutes
        guard baseNeed > 0 else { return nil }
        let history = nights.sorted { $0.date < $1.date }.suffix(28)
        guard history.count >= minimumNights else { return nil }
        guard let firstMorning = PlanningDay.morning(after: now, calendar: calendar)?.start else {
            return nil
        }

        let habit = Habit(nights: Array(history), calendar: calendar)
        guard let overallBedtime = habit.overallBedtime, let overallWake = habit.overallWake else {
            return nil
        }

        var days: [Day] = []
        var shortfall = planning.currentShortfallMinutes
        var usedCalendar = false

        for offset in 0..<horizonDays {
            guard let morning = calendar.date(byAdding: .day, value: offset, to: firstMorning) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: morning)

            // Wake, in order of authority: a dated commitment, then a
            // standing time the person set for this kind of day, then their
            // own habit.
            let commitment = commitments[calendar.startOfDay(for: morning)]
                .flatMap { start -> Date? in
                    guard calendar.component(.hour, from: start) < ZoonTomorrow.latestMorningEventHour
                    else { return nil }
                    return calendar.date(byAdding: .minute, value: -Int(readyBufferMinutes.rounded()), to: start)
                }
            let manualWake = manual.flatMap { manual -> Date? in
                guard obligationWeekdays.isEmpty || obligationWeekdays.contains(weekday) else { return nil }
                return calendar.date(
                    bySettingHour: manual.hour, minute: manual.minute, second: 0, of: morning
                )
            }

            // A saved plan covering this night sets both ends of it, above
            // everything else: the person chose these times for this night.
            let planned = plans
                .compactMap { $0.nextWindow(after: calendar.startOfDay(for: morning)) }
                .filter { calendar.isDate($0.end, inSameDayAs: morning) }
                .min { $0.start < $1.start }

            let wake: Date
            let source: WakeSource
            if let planned {
                wake = planned.end
                source = .plan
            } else if let commitment {
                wake = commitment
                source = .calendar
                usedCalendar = true
            } else if let manualWake {
                wake = manualWake
                source = .manual
            } else if let weekdayWake = habit.wake(forWeekday: weekday) {
                guard let date = Self.date(minutesFromMidnight: weekdayWake, on: morning, calendar: calendar)
                else { continue }
                wake = date
                source = .habit
            } else {
                guard let date = Self.date(minutesFromMidnight: overallWake, on: morning, calendar: calendar)
                else { continue }
                wake = date
                source = .overallHabit
            }

            // Bedtime the evening before, from the same habit. Negative
            // minutes are the evening side of midnight, which is why the
            // shifted scale is used throughout rather than raw clock
            // minutes: subtracting a 23:00 bedtime from a 07:00 wake has to
            // give eight hours, not minus sixteen.
            let bedtimeMinutes = habit.bedtime(forWeekday: weekday) ?? overallBedtime
            guard let habitBedtime = Self.date(minutesFromMidnight: bedtimeMinutes, on: morning, calendar: calendar)
            else { continue }
            let bedtime = planned?.start ?? habitBedtime

            let opportunity = max(0, wake.timeIntervalSince(bedtime) / 60)

            // One repayment rule, owned by `SleepPlanningInputs`, applied to
            // the shortfall as it stands going into *this* night. The need
            // handed in carries no repayment of its own, so this is the only
            // place the debt is serviced.
            let need = baseNeed + SleepPlanningInputs.repayment(for: shortfall)

            // The ledger moves against the *base* need, not the target.
            // Repayment raises what to aim for; it is not a second debt to
            // service. Subtracting the target would mean a window that
            // comfortably covers the need still grew the shortfall, so a debt
            // could never be paid off -- the arithmetic would have made its
            // own warning permanent.
            shortfall = max(0, shortfall + baseNeed - opportunity)

            days.append(Day(
                date: morning,
                needMinutes: need,
                opportunityMinutes: opportunity,
                bedtime: bedtime,
                wake: wake,
                wakeSource: source,
                projectedShortfallMinutes: shortfall
            ))
        }

        guard !days.isEmpty else { return nil }
        let firstShort = days.first(where: \.isShort)

        return Plan(
            days: days,
            firstShortDay: firstShort,
            sentence: sentence(firstShort: firstShort, days: days, calendar: calendar),
            caveat: "Opportunity is the most sleep each schedule leaves room for, not a prediction of how you will sleep. Zoon does not forecast recovery days ahead.",
            confidence: confidence(nights: history.count, usedCalendar: usedCalendar),
            usedCalendar: usedCalendar
        )
    }

    // MARK: - Internals

    private static func sentence(
        firstShort: Day?,
        days: [Day],
        calendar: Calendar
    ) -> String {
        guard let firstShort else {
            return "Every morning in the next week leaves room for the sleep you need, if you keep to your usual bedtime."
        }
        let name = firstShort.date.formatted(.dateTime.weekday(.wide))
        let gap = SleepNightFeatures.formatMinutes(firstShort.gapMinutes)
        let pinned = firstShort.wakeSource.isFixed
            ? " That start time is fixed, so the bedtime before it is the part that can move."
            : ""
        return "\(name) is about \(gap) short of what you need, at your usual bedtime.\(pinned)"
    }

    private static func confidence(nights: Int, usedCalendar: Bool) -> MetricConfidence {
        switch nights {
        case ..<minimumNights: .insufficient
        case minimumNights..<14: .low
        case 14..<21: .moderate
        default: usedCalendar ? .high : .moderate
        }
    }

    /// Places a shifted minutes-from-midnight value on the day that owns it.
    ///
    /// Negative values belong to the previous evening — that is the whole
    /// point of the shifted scale — so a −60 (23:00) bedtime for a Tuesday
    /// morning lands on Monday night.
    static func date(
        minutesFromMidnight minutes: Double,
        on day: Date,
        calendar: Calendar
    ) -> Date? {
        let midnight = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: Int(minutes.rounded()), to: midnight)
    }

    /// Habitual bedtime and wake, overall and per weekday.
    struct Habit {
        private let bedtimesByWeekday: [Int: [Double]]
        private let wakesByWeekday: [Int: [Double]]
        let overallBedtime: Double?
        let overallWake: Double?

        init(nights: [SleepNightFeatures], calendar: Calendar) {
            var bedtimes: [Int: [Double]] = [:]
            var wakes: [Int: [Double]] = [:]
            var allBedtimes: [Double] = []
            var allWakes: [Double] = []

            for night in nights {
                // Each night in its own timezone: a wall-clock habit does not
                // change because the phone has since moved.
                var nightCalendar = calendar
                nightCalendar.timeZone = night.timeZone
                let weekday = nightCalendar.component(.weekday, from: night.date)
                let bedtime = Statistics.circularMinutesFromMidnight(night.bedtime, calendar: nightCalendar)
                let wake = Statistics.circularMinutesFromMidnight(night.wakeTime, calendar: nightCalendar)
                bedtimes[weekday, default: []].append(bedtime)
                wakes[weekday, default: []].append(wake)
                allBedtimes.append(bedtime)
                allWakes.append(wake)
            }

            bedtimesByWeekday = bedtimes
            wakesByWeekday = wakes
            overallBedtime = Statistics.median(allBedtimes)
            overallWake = Statistics.median(allWakes)
        }

        func bedtime(forWeekday weekday: Int) -> Double? {
            median(bedtimesByWeekday[weekday])
        }

        func wake(forWeekday weekday: Int) -> Double? {
            median(wakesByWeekday[weekday])
        }

        private func median(_ values: [Double]?) -> Double? {
            guard let values, values.count >= minimumWeekdayNights else { return nil }
            return Statistics.median(values)
        }
    }
}
