import Foundation

/// One coherent preparation timeline for a morning that actually has a start time.
///
/// Tonight's autopilot answers "where should bed and wake sit, given habit".
/// This answers a narrower question: *if something is required of you at a
/// known hour tomorrow, what should tonight look like?* It reuses the same
/// rate limit, the same caffeine guideline, the same nap and light coaches,
/// and never invents a second score.
///
/// Missing is not zero. No event still produces tonight's plan; it simply
/// omits the EVENT node. An all-day event, or one after 14:00, is not a
/// morning commitment and is ignored as a wake anchor.
enum ZoonTomorrow {

    /// Minutes before the commitment to wake, so getting ready is possible.
    static let readyBufferMinutes = 50.0
    /// Wind-down lead used when the reminder system has not supplied one.
    static let windDownLeadMinutes = 40.0
    /// Half-width of the bedtime window shown on the horizon.
    static let sleepWindowHalfMinutes = 15.0
    /// Morning light window after wake, matching `LightCoach.morningWindowMinutes`
    /// in spirit but kept short here so the horizon stays a handful of nodes.
    static let morningLightMinutes = 30.0
    /// Commitments at or after this hour are not treated as a morning start.
    static let latestMorningEventHour = 14

    struct Event: Hashable, Sendable {
        enum Source: String, Sendable { case manual, calendar }
        let start: Date
        let isAllDay: Bool
        let source: Source
    }

    struct Node: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable {
            case now, caffeine, windDown, sleep, wake, event
        }
        let kind: Kind
        let date: Date
        let title: String
        let detail: String
        var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
        var isBand: Bool { kind == .sleep }
    }

    struct Plan: Hashable, Sendable {
        let event: Event?
        let targetSleepMinutes: Double
        let sleepWindowStart: Date
        let sleepWindowEnd: Date
        let windDown: Date
        let caffeineCutoff: Date?
        let wake: Date
        let morningLightUntil: Date
        let napAdvice: NapCoach.Recommendation
        let shiftMinutes: Double
        let isHolding: Bool
        let nodes: [Node]
        let why: [String]
        let caveat: String
        let confidence: MetricConfidence
        let sentence: String
    }

    /// A morning commitment that is allowed to move wake, or `nil`.
    static func meaningfulMorningEvent(_ event: Event?, calendar: Calendar = .current) -> Event? {
        guard let event, !event.isAllDay else { return nil }
        let hour = calendar.component(.hour, from: event.start)
        guard hour < latestMorningEventHour else { return nil }
        return event
    }

    /// Builds the plan.
    ///
    /// - Parameters:
    ///   - now: the moment the plan is being asked for.
    ///   - event: tomorrow's first commitment, when the person (or Calendar)
    ///     has named one. Titles are never an input.
    ///   - nights: recent history, any order. Fewer than seven still produces
    ///     a plan from need + event; confidence drops.
    ///   - sleepNeedMinutes: the person's own need, never a guideline.
    ///   - sleepDebtMinutes: outstanding shortfall, never negative.
    ///   - napMinutesToday: already-banked nap minutes.
    ///   - windDownLeadMinutes: from the reminder system when known.
    static func plan(
        now: Date = .now,
        event: Event?,
        nights: [SleepNightFeatures],
        sleepNeedMinutes: Double,
        sleepDebtMinutes: Double = 0,
        napMinutesToday: Double = 0,
        windDownLeadMinutes: Double = windDownLeadMinutes,
        calendar: Calendar = .current
    ) -> Plan? {
        guard sleepNeedMinutes > 0 else { return nil }

        let morning = meaningfulMorningEvent(event, calendar: calendar)
        let wakeFromEvent = morning.flatMap { eventWake(for: $0, calendar: calendar) }
        let obligationMinutes = wakeFromEvent.map { minutesFromMidnight($0, calendar: calendar) }

        let autopilot = SleepAutopilot.plan(
            nights: nights,
            sleepNeedMinutes: sleepNeedMinutes,
            obligationWakeMinutes: obligationMinutes,
            sleepDebtMinutes: max(sleepDebtMinutes, 0)
        )

        let targetSleep = autopilot?.targetSleepMinutes
            ?? (sleepNeedMinutes + min(max(sleepDebtMinutes, 0) * SleepAutopilot.debtRepaymentRate,
                                       SleepAutopilot.maximumDebtRepayment))

        let wake: Date
        let bedtime: Date
        if let wakeFromEvent {
            wake = wakeFromEvent
            bedtime = calendar.date(
                byAdding: .minute, value: -Int(targetSleep.rounded()), to: wake
            ) ?? wake
        } else if let autopilot,
                  let bed = PlannedBedtimeResolver.nextOccurrence(
                    ofMinutesFromMidnight: autopilot.targetBedtimeMinutes, after: now, calendar: calendar
                  ) {
            bedtime = bed
            wake = calendar.date(
                byAdding: .minute, value: Int(autopilot.targetSleepMinutes.rounded()), to: bed
            ) ?? bed
        } else {
            return nil
        }

        let windowStart = calendar.date(
            byAdding: .minute, value: -Int(sleepWindowHalfMinutes), to: bedtime
        ) ?? bedtime
        let windowEnd = calendar.date(
            byAdding: .minute, value: Int(sleepWindowHalfMinutes), to: bedtime
        ) ?? bedtime
        let windDown = calendar.date(
            byAdding: .minute, value: -Int(windDownLeadMinutes.rounded()), to: bedtime
        ) ?? bedtime
        let caffeine = CaffeineCutoff.time(bedtime: bedtime, now: now)
        let lightUntil = calendar.date(
            byAdding: .minute, value: Int(morningLightMinutes), to: wake
        ) ?? wake

        let nap = NapCoach.recommend(
            now: now,
            debtMinutes: max(sleepDebtMinutes, 0),
            plannedBedtime: bedtime,
            napMinutesToday: napMinutesToday
        )

        let shift = autopilot?.shiftMinutes ?? 0
        let holding = autopilot?.isHolding ?? true
        let confidence = combinedConfidence(nights: nights.count, hasEvent: morning != nil)

        let nodes = makeNodes(
            now: now,
            caffeine: caffeine,
            windDown: windDown,
            windowStart: windowStart,
            windowEnd: windowEnd,
            wake: wake,
            event: morning,
            calendar: calendar
        )

        let why = makeWhy(
            morning: morning,
            targetSleep: targetSleep,
            shift: shift,
            holding: holding,
            debtMinutes: sleepDebtMinutes,
            caffeine: caffeine,
            calendar: calendar
        )

        let sentence = makeSentence(
            targetSleep: targetSleep,
            windowStart: windowStart,
            windowEnd: windowEnd,
            morning: morning,
            calendar: calendar
        )

        return Plan(
            event: morning,
            targetSleepMinutes: targetSleep,
            sleepWindowStart: windowStart,
            sleepWindowEnd: windowEnd,
            windDown: windDown,
            caffeineCutoff: caffeine,
            wake: wake,
            morningLightUntil: lightUntil,
            napAdvice: nap,
            shiftMinutes: shift,
            isHolding: holding,
            nodes: nodes,
            why: why,
            caveat: "This is a plan from your nights and tomorrow's start time. It is not a medical recommendation and does not predict how you will feel.",
            confidence: confidence,
            sentence: sentence
        )
    }

    // MARK: - Internals

    static func minutesFromMidnight(_ date: Date, calendar: Calendar) -> Double {
        Double(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
    }

    private static func eventWake(for event: Event, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .minute, value: -Int(readyBufferMinutes), to: event.start)
    }

    private static func combinedConfidence(nights: Int, hasEvent: Bool) -> MetricConfidence {
        switch (nights, hasEvent) {
        case (..<SleepAutopilot.minimumNights, false): .insufficient
        case (..<SleepAutopilot.minimumNights, true): .low
        case (SleepAutopilot.minimumNights..<14, _): .moderate
        default: hasEvent ? .high : .moderate
        }
    }

    private static func makeNodes(
        now: Date,
        caffeine: Date?,
        windDown: Date,
        windowStart: Date,
        windowEnd: Date,
        wake: Date,
        event: Event?,
        calendar: Calendar
    ) -> [Node] {
        var nodes: [Node] = [
            Node(
                kind: .now,
                date: now,
                title: "Now",
                detail: "Where tonight starts from."
            )
        ]
        if let caffeine {
            nodes.append(Node(
                kind: .caffeine,
                date: caffeine,
                title: "Caffeine",
                detail: "A general 8-hour guideline before the sleep window, not your personal sensitivity."
            ))
        }
        nodes.append(contentsOf: [
            Node(
                kind: .windDown,
                date: windDown,
                title: "Wind-down",
                detail: "Dim lights and drop stimulation so bedtime can arrive on time."
            ),
            Node(
                kind: .sleep,
                date: windowStart,
                title: "Sleep window",
                detail: "\(clock(windowStart, calendar: calendar)) – \(clock(windowEnd, calendar: calendar)). A range, not a single minute you have to hit."
            ),
            Node(
                kind: .wake,
                date: wake,
                title: "Wake",
                detail: "Morning light within \(Int(morningLightMinutes)) minutes of waking is the strongest cue Zoon can name."
            )
        ])
        if let event {
            nodes.append(Node(
                kind: .event,
                date: event.start,
                title: "Event",
                detail: event.source == .calendar
                    ? "First morning commitment from Calendar. The title was not stored."
                    : "The time you asked Zoon to protect."
            ))
        }
        return nodes.sorted { $0.date < $1.date }
    }

    private static func makeWhy(
        morning: Event?,
        targetSleep: Double,
        shift: Double,
        holding: Bool,
        debtMinutes: Double,
        caffeine: Date?,
        calendar: Calendar
    ) -> [String] {
        var why: [String] = []
        if let morning {
            why.append(
                "Tomorrow's first commitment is at \(clock(morning.start, calendar: calendar)), so wake is \(Int(readyBufferMinutes)) minutes earlier."
            )
        }
        why.append("Aim for \(SleepNightFeatures.formatMinutes(targetSleep)) tonight, measured against your own sleep need.")
        if !holding, abs(shift) >= 1 {
            let direction = shift < 0 ? "earlier" : "later"
            why.append(
                "Bedtime only moves \(SleepNightFeatures.formatMinutes(abs(shift))) \(direction) because larger jumps are hard to keep."
            )
        }
        if debtMinutes >= 20 {
            why.append(
                "A slice of the \(SleepNightFeatures.formatMinutes(debtMinutes)) shortfall is in tonight's target, capped so one night cannot repay a week."
            )
        }
        if caffeine != nil {
            why.append("Caffeine cutoff is eight hours before the sleep window — a general guideline.")
        }
        return why
    }

    private static func makeSentence(
        targetSleep: Double,
        windowStart: Date,
        windowEnd: Date,
        morning: Event?,
        calendar: Calendar
    ) -> String {
        var text = "Aim for \(SleepNightFeatures.formatMinutes(targetSleep)) tonight. Suggested sleep window: \(clock(windowStart, calendar: calendar)) – \(clock(windowEnd, calendar: calendar))."
        if let morning {
            text += " Wake leaves \(Int(readyBufferMinutes)) minutes before \(clock(morning.start, calendar: calendar))."
        }
        return text
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
