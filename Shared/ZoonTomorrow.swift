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

    /// Default minutes before the commitment to wake, so getting ready is
    /// possible.
    ///
    /// A default, not a constant. How long it takes to shower, eat and travel
    /// is a fact about a person's morning, not about human physiology, and
    /// `UserPreferences.morningReadyBufferMinutes` is what callers actually
    /// pass. This value is what a new install starts from.
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
        /// The centre of the sleep window -- the single time the rest of the
        /// plan is built from. The window, wind-down and caffeine cutoff are
        /// all offsets from it, so exposing only the window left every caller
        /// to reconstruct the one number that generated them.
        let bedtime: Date
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

    /// The range the ready buffer may be set to, in minutes.
    static let readyBufferRange: ClosedRange<Double> = 0...180

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
    ///   - planning: baseline need, the outstanding shortfall and tonight's
    ///     own modifiers, with no repayment applied yet. See
    ///     `SleepPlanningInputs` for why a composed total must not be passed.
    ///   - napMinutesToday: already-banked nap minutes.
    ///   - windDownLeadMinutes: from the reminder system when known.
    ///   - readyBufferMinutes: the person's own getting-ready time.
    static func plan(
        now: Date = .now,
        event: Event?,
        nights: [SleepNightFeatures],
        planning: SleepPlanningInputs,
        napMinutesToday: Double = 0,
        windDownLeadMinutes: Double = windDownLeadMinutes,
        readyBufferMinutes: Double = readyBufferMinutes,
        calendar: Calendar = .current
    ) -> Plan? {
        guard planning.baselineNeedMinutes > 0 else { return nil }
        let sleepDebtMinutes = planning.currentShortfallMinutes

        let buffer = min(max(readyBufferMinutes, readyBufferRange.lowerBound), readyBufferRange.upperBound)
        let morning = meaningfulMorningEvent(event, calendar: calendar)
        let wakeFromEvent = morning.flatMap {
            eventWake(for: $0, bufferMinutes: buffer, calendar: calendar)
        }
        let obligationMinutes = wakeFromEvent.map { minutesFromMidnight($0, calendar: calendar) }

        // The autopilot owns the repayment rule, so it is handed the need
        // *before* one has been applied. It used to receive a composed total
        // that already contained 33% of the debt and then added 25% of it
        // again -- the double count `SleepPlanningInputs` exists to end.
        let autopilot = SleepAutopilot.plan(
            nights: nights,
            sleepNeedMinutes: planning.tonightNeedBeforeRepaymentMinutes,
            obligationWakeMinutes: obligationMinutes,
            sleepDebtMinutes: sleepDebtMinutes
        )

        let targetSleep = autopilot?.targetSleepMinutes ?? planning.tonightNeedMinutes

        let wake: Date
        let bedtime: Date
        // Whether the shown bedtime is the one SleepAutopilot rate-limited.
        // The `why` line claims a 20-minute cap, and it may only say so when
        // the number it is describing actually went through the cap.
        var bedtimeIsRateLimited = false
        if let wakeFromEvent {
            wake = wakeFromEvent
            // The event wake is already handed to `SleepAutopilot.plan` as
            // `obligationWakeMinutes`, so `targetBedtimeMinutes` is the
            // rate-limited, deadbanded answer *for this obligation*. Deriving
            // the bedtime as `wake - targetSleep` instead threw that away and
            // could move bedtime by hours while the `why` line underneath
            // still said it had only moved twenty minutes.
            //
            // Capping means the plan may not reach `targetSleep` tonight.
            // That is the honest outcome: the alarm cannot move, and a
            // bedtime nobody will keep is not a plan.
            if let autopilot,
               let bed = PlannedBedtimeResolver.nextOccurrence(
                ofMinutesFromMidnight: autopilot.targetBedtimeMinutes, after: now, calendar: calendar
               ) {
                bedtime = bed
                bedtimeIsRateLimited = true
            } else {
                // No autopilot plan means not enough history to have a
                // habitual bedtime to move *from*, so there is no shift to
                // cap and nothing to claim about one.
                bedtime = calendar.date(
                    byAdding: .minute, value: -Int(targetSleep.rounded()), to: wake
                ) ?? wake
            }
        } else if let autopilot,
                  let bed = PlannedBedtimeResolver.nextOccurrence(
                    ofMinutesFromMidnight: autopilot.targetBedtimeMinutes, after: now, calendar: calendar
                  ) {
            bedtime = bed
            bedtimeIsRateLimited = true
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

        // Only the shift that actually shaped the shown bedtime. When the
        // bedtime did not come through the rate limiter there is no cap to
        // describe, and describing one anyway is the failure this guards.
        let shift = bedtimeIsRateLimited ? (autopilot?.shiftMinutes ?? 0) : 0
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
            readyBufferMinutes: buffer,
            calendar: calendar
        )

        let sentence = makeSentence(
            targetSleep: targetSleep,
            bedtime: bedtime,
            wake: wake,
            windowStart: windowStart,
            windowEnd: windowEnd,
            morning: morning,
            calendar: calendar
        )

        return Plan(
            event: morning,
            targetSleepMinutes: targetSleep,
            bedtime: bedtime,
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

    private static func eventWake(for event: Event, bufferMinutes: Double, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .minute, value: -Int(bufferMinutes.rounded()), to: event.start)
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
        readyBufferMinutes: Double,
        calendar: Calendar
    ) -> [String] {
        var why: [String] = []
        if let morning {
            let source = morning.source == .calendar
                ? "Tomorrow's first Calendar commitment"
                : "The time you asked Zoon to protect"
            if readyBufferMinutes >= 1 {
                why.append(
                    "\(source) is at \(clock(morning.start, calendar: calendar)), so wake is \(SleepNightFeatures.formatMinutes(readyBufferMinutes)) earlier — your getting-ready time, which you can change."
                )
            } else {
                why.append("\(source) is at \(clock(morning.start, calendar: calendar)), and you have asked for no getting-ready time before it.")
            }
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

    /// How far the plan may fall short of the target before the sentence has
    /// to say so rather than quote the target.
    static let sentenceShortfallTolerance = 15.0

    private static func makeSentence(
        targetSleep: Double,
        bedtime: Date,
        wake: Date,
        windowStart: Date,
        windowEnd: Date,
        morning: Event?,
        calendar: Calendar
    ) -> String {
        // What this plan actually delivers, rather than what was aimed at.
        //
        // The sentence used to quote `targetSleep` unconditionally. Once the
        // bedtime goes through SleepAutopilot's rate limiter it frequently
        // cannot reach that target, and a device screenshot caught the result:
        // "Aim for 10h 12m tonight. Suggested sleep window: 2:20 AM - 2:50 AM.
        // Wake leaves 50 minutes before 8:30 AM." — a five-hour window under a
        // ten-hour promise, in one sentence.
        //
        // A fixed wake and a bedtime that may only move so far in one night
        // are both deliberate. The shortfall they produce is real, and naming
        // it is the honest version of this sentence.
        let achievable = max(0, wake.timeIntervalSince(bedtime) / 60)
        let window = "Suggested sleep window: \(clock(windowStart, calendar: calendar)) – \(clock(windowEnd, calendar: calendar))."

        var text: String
        if targetSleep - achievable > sentenceShortfallTolerance {
            text = "This window gives about \(SleepNightFeatures.formatMinutes(achievable)), short of the \(SleepNightFeatures.formatMinutes(targetSleep)) you need. \(window)"
        } else {
            text = "Aim for \(SleepNightFeatures.formatMinutes(targetSleep)) tonight. \(window)"
        }

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
