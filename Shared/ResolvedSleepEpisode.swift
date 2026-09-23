import Foundation

/// Tonight's sleep episode, resolved once and read by every surface.
///
/// **The defect this exists for.** Before this type, "tonight" was computed
/// in five places from three different sources:
///
/// - The Today hero's Bed node read `DayContext.targetBedtime()`: last night's
///   wake clock minus tonight's need, anchored on *tomorrow* relative to now.
///   At 00:30 that is the morning after next, so the countdown read ~22h.
/// - The same hero's sentence read `SleepAutopilot`'s bedtime, which is a
///   different number. The node and the sentence under it could disagree.
/// - The nap coach and the Tomorrow plan resolved the autopilot bedtime with
///   `PlannedBedtimeResolver.nextOccurrence`, which rolls to tomorrow the
///   minute a bedtime passes. At 23:01 for a 23:00 bedtime: "Bed in 23h 59m".
/// - Reminders read a manual plan when there was one, and the wake alarm read
///   `BodyClock.window(for: .now)`, which at 02:00 is *tomorrow* morning's
///   wake. Re-arming at 02:00 moved this morning's alarm a day later.
///
/// Every one of those is the same question -- which night is tonight, and
/// when does it start and end -- and this answers it once.
///
/// **The lifecycle.** An episode is `upcoming` until wind-down, `windingDown`
/// until bed, `overdue` from bed until its wake, and `completed` after that.
/// The explicit expiry is the wake: a bedtime that has passed stays *tonight's*
/// bedtime until the morning it was planning for has arrived. It never rolls
/// to tomorrow because a clock ticked past it.
///
/// **What this does not know.** The times are a schedule -- the person's own,
/// or one derived from their history. Nothing here observes sleep; a phase of
/// `overdue` means the planned bedtime has passed, not that the person is
/// awake.
struct ResolvedSleepEpisode: Hashable, Sendable {

    /// Where the times came from, strongest first.
    enum Source: String, Codable, Sendable {
        /// A sleep plan the person set, for this date or this weekday.
        case manualPlan
        /// `SleepAutopilot`'s bedtime against the person's habitual wake.
        case autopilot
        /// The person's usual wake clock minus tonight's need. The fallback
        /// when there is not yet enough history for the autopilot.
        case usualWake
    }

    enum Phase: String, Codable, Sendable {
        case upcoming
        case windingDown
        /// Bed has passed; the wake it was planning for has not.
        case overdue
        case completed
    }

    let bed: Date
    let windDown: Date
    /// The wake the alarm rings at and every surface shows.
    let wake: Date
    /// A wake the person cannot move, when one is known. Always at or after
    /// `wake`: the chosen wake is never later than a hard commitment.
    let obligationWake: Date?
    /// What tonight asks for. The opportunity may not reach it.
    let targetSleepMinutes: Double
    let timeZone: TimeZone
    let source: Source
    /// The manual plan's name, when `source` is `.manualPlan`.
    let planName: String?
    /// How much to trust the *schedule*. A manual plan is high: the person
    /// said so. It is not a claim about physiology.
    let confidence: MetricConfidence

    /// Time between bed and wake. Not sleep: falling asleep takes time and
    /// nights have wakes in them.
    var opportunityMinutes: Double { max(0, wake.timeIntervalSince(bed) / 60) }

    /// How far the opportunity falls short of the target. Zero when it does
    /// not. Shown rather than hidden: an impossible target is a fact the
    /// reader should see, not one to paper over by moving the wake.
    var shortfallMinutes: Double { max(0, targetSleepMinutes - opportunityMinutes) }

    var isFeasible: Bool { shortfallMinutes < 1 }

    /// "10:45 PM - 6:30 AM", in the episode's own zone, formatted where the
    /// dates are known so the watch and widget never fold minutes themselves.
    var rangeLabel: String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        return "\(bed.formatted(style)) - \(wake.formatted(style))"
    }

    func phase(at now: Date) -> Phase {
        if now >= wake { return .completed }
        if now >= bed { return .overdue }
        if now >= windDown { return .windingDown }
        return .upcoming
    }

    // MARK: - Resolving

    /// The bed and wake of the night that contains `now`, or the next one.
    ///
    /// Both arguments are clock minutes on any scale: `SleepAutopilot` uses
    /// negative minutes for evenings, plans use 0..<1440, and a wake derived
    /// from a bedtime plus a long sleep can exceed 1440. Each is folded to a
    /// wall-clock time first.
    ///
    /// Built from wall-clock components rather than added seconds, for the
    /// reason `BodyClock.window` documents: a day is not always 86,400
    /// seconds, and on a clock-change night elapsed-time arithmetic lands an
    /// hour off.
    ///
    /// Candidates are anchored two days either side of today and the first
    /// whose wake is still ahead wins. That covers an after-midnight bedtime
    /// already passed (anchored today) and one not yet reached (anchored
    /// today or tomorrow) without special cases.
    static func window(
        bedMinute: Double,
        wakeMinute: Double,
        containingOrAfter now: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard bedMinute.isFinite, wakeMinute.isFinite else { return nil }
        let bed = folded(bedMinute)
        let wake = folded(wakeMinute)
        let today = calendar.startOfDay(for: now)
        for offset in -2...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let bedDate = wallClock(bed, on: day, calendar: calendar),
                  var wakeDate = wallClock(wake, on: day, calendar: calendar)
            else { continue }
            if wakeDate <= bedDate {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                      let next = wallClock(wake, on: nextDay, calendar: calendar)
                else { continue }
                wakeDate = next
            }
            guard wakeDate > bedDate else { continue }
            if wakeDate > now { return DateInterval(start: bedDate, end: wakeDate) }
        }
        return nil
    }

    /// Resolve tonight.
    ///
    /// - Parameters:
    ///   - plans: the person's sleep plans. One whose night overlaps the
    ///     derived night, or comes before it, wins -- the person's own
    ///     schedule beats one inferred from history. A weekday plan that does
    ///     not cover tonight does not reach forward and claim next Monday.
    ///   - autopilot: tonight's autopilot plan, when there is enough history.
    ///   - usualWakeMinute: the habitual wake clock (the body clock's, or last
    ///     night's). The chosen wake when no plan says otherwise.
    ///   - needMinutes: tonight's need, for the fallback bedtime and for the
    ///     shortfall against a manual plan.
    ///   - hardWakeMinute: a wake that cannot move, when one is known. The
    ///     chosen wake is capped at it, never scheduled after it.
    static func resolve(
        plans: [PersonalSetup.SleepPlan] = [],
        autopilot: SleepAutopilot.Plan?,
        usualWakeMinute: Double?,
        needMinutes: Double,
        hardWakeMinute: Double? = nil,
        windDownLeadMinutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> ResolvedSleepEpisode? {
        let derived = derivedEpisode(
            autopilot: autopilot,
            usualWakeMinute: usualWakeMinute,
            needMinutes: needMinutes,
            hardWakeMinute: hardWakeMinute,
            windDownLeadMinutes: windDownLeadMinutes,
            now: now,
            calendar: calendar
        )

        let manual = plans
            .compactMap { plan in plan.nextWindow(after: now).map { (plan, $0) } }
            .min { $0.1.start < $1.1.start }

        if let (plan, window) = manual, derived.map({ window.start < $0.wake }) ?? true {
            let zone = TimeZone(identifier: plan.timeZoneIdentifier) ?? calendar.timeZone
            return ResolvedSleepEpisode(
                bed: window.start,
                windDown: window.start.addingTimeInterval(-Double(windDownLeadMinutes) * 60),
                wake: window.end,
                obligationWake: window.end,
                targetSleepMinutes: max(0, needMinutes),
                timeZone: zone,
                source: .manualPlan,
                planName: plan.name,
                confidence: .high
            )
        }
        return derived
    }

    /// The next `nights` episodes, starting with tonight's.
    ///
    /// For scheduling one-off notifications ahead, so a person who does not
    /// open the app for two days still gets their reminders. Nights after
    /// tonight repeat tonight's derived clock times -- the autopilot plans
    /// one night at a time, and the horizon is re-resolved every time the app
    /// refreshes -- while manual plans are exact on every night they cover.
    static func horizon(
        nights: Int,
        plans: [PersonalSetup.SleepPlan] = [],
        autopilot: SleepAutopilot.Plan?,
        usualWakeMinute: Double?,
        needMinutes: Double,
        hardWakeMinute: Double? = nil,
        windDownLeadMinutes: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [ResolvedSleepEpisode] {
        var result: [ResolvedSleepEpisode] = []
        var cursor = now
        // Bounded: each pass either appends or moves the cursor past a wake.
        for _ in 0..<(max(0, nights) * 3) where result.count < nights {
            guard let episode = resolve(
                plans: plans,
                autopilot: autopilot,
                usualWakeMinute: usualWakeMinute,
                needMinutes: needMinutes,
                // A hard wake is known for tonight only; a calendar event
                // tomorrow says nothing about next Thursday.
                hardWakeMinute: result.isEmpty ? hardWakeMinute : nil,
                windDownLeadMinutes: windDownLeadMinutes,
                now: cursor,
                calendar: calendar
            ) else { break }
            cursor = episode.wake.addingTimeInterval(1)
            // A manual night that ends early leaves the derived night it
            // replaced still "in progress" a moment later. Skip it rather
            // than queue a second, overlapping night.
            if let last = result.last, episode.bed < last.wake { continue }
            result.append(episode)
        }
        return result
    }

    // MARK: - Private

    private static func derivedEpisode(
        autopilot: SleepAutopilot.Plan?,
        usualWakeMinute: Double?,
        needMinutes: Double,
        hardWakeMinute: Double?,
        windDownLeadMinutes: Int,
        now: Date,
        calendar: Calendar
    ) -> ResolvedSleepEpisode? {
        let wakeMinute = hardWakeMinute ?? usualWakeMinute ?? autopilot?.targetWakeMinutes
        guard let wakeMinute else { return nil }

        let source: Source
        let bedMinute: Double
        let target: Double
        let confidence: MetricConfidence
        if let autopilot {
            source = .autopilot
            bedMinute = autopilot.targetBedtimeMinutes
            target = autopilot.targetSleepMinutes
            confidence = autopilot.confidence
        } else {
            guard needMinutes > 0 else { return nil }
            source = .usualWake
            bedMinute = wakeMinute - needMinutes
            target = needMinutes
            confidence = .low
        }

        guard let window = window(
            bedMinute: bedMinute, wakeMinute: wakeMinute, containingOrAfter: now, calendar: calendar
        ) else { return nil }

        return ResolvedSleepEpisode(
            bed: window.start,
            windDown: window.start.addingTimeInterval(-Double(windDownLeadMinutes) * 60),
            wake: window.end,
            obligationWake: hardWakeMinute == nil ? nil : window.end,
            targetSleepMinutes: target,
            timeZone: calendar.timeZone,
            source: source,
            planName: nil,
            confidence: confidence
        )
    }

    private static func folded(_ minutes: Double) -> Int {
        let rounded = Int(minutes.rounded())
        return ((rounded % 1440) + 1440) % 1440
    }

    private static func wallClock(_ minute: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
    }
}
