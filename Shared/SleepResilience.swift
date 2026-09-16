import Foundation

/// How quickly a signal comes back to its own baseline after it is disturbed.
///
/// **What this replaces.** Zoon carried a Cardiovascular Age estimator: it
/// inverted a population curve for overnight HRV and reported the result as a
/// number of years. Two things were wrong with it. The HRV branch never read
/// the person's actual age at all — the "age" it produced was a restatement of
/// one number against a curve — and the overnight SDNN a watch reports is not
/// the quantity those population curves were built from, so the comparison was
/// between two things that are not the same measurement. It was clamped to
/// ±15 years, which hid how little it knew rather than fixing it, and it was
/// already wired to nothing. Deleted rather than repaired.
///
/// **What this does instead.** It asks a question the data can answer: when
/// one of your signals leaves your own typical band, how many nights does it
/// take to come back? That is measured entirely against the person's own
/// history, makes no population claim, and is the thing "resilience" actually
/// means. Nothing here is an age, a diagnosis, or a comparison to anyone else.
enum SleepResilience {

    /// One night's value for one metric. Ordered oldest first by the caller.
    struct Observation: Sendable, Hashable {
        let date: Date
        let value: Double

        init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Which way is the bad way for this metric.
    ///
    /// HRV falling below the band is the disturbance; resting heart rate,
    /// respiratory rate and wrist temperature rising above it are. A metric
    /// that deviates the *favourable* way is not something to recover from.
    enum Direction: Sendable, Hashable {
        case belowIsDisruption
        case aboveIsDisruption

        func isDisrupted(_ value: Double, baseline: Double, tolerance: Double) -> Bool {
            switch self {
            case .belowIsDisruption: value < baseline - tolerance
            case .aboveIsDisruption: value > baseline + tolerance
            }
        }
    }

    /// Nights of history before the question is worth asking.
    static let minimumNights = 21
    /// Disruptions needed before a median is a pattern rather than an anecdote.
    static let minimumEvents = 3

    struct Result: Sendable, Hashable {
        let state: State
        /// Disruptions found in the window, resolved and unresolved together.
        let eventCount: Int
        /// Disruptions still outside the band when the window ended. These
        /// have no return time *yet* — see `State.unresolved`.
        let censoredCount: Int
        let nightCount: Int
    }

    enum State: Sendable, Hashable {
        case insufficientHistory(nights: Int, required: Int)
        /// History enough, but the signal never left the band. Nothing to
        /// measure, and a good thing rather than a gap.
        case steady
        case tooFewEvents(found: Int, required: Int)
        case measured(medianNights: Double)

        var medianNights: Double? {
            if case .measured(let median) = self { return median }
            return nil
        }
    }

    /// Half-width of this person's own typical band for a metric.
    ///
    /// `1.4826 x MAD` is the robust analogue of a standard deviation, so the
    /// band is "about one of your own standard deviations", measured in a way
    /// one bad night cannot move.
    ///
    /// The bounds are not cosmetic. A hyper-regular sleeper has a MAD of a
    /// few minutes, and a band that narrow makes almost every night a
    /// disruption — the metric would report someone with excellent sleep as
    /// constantly recovering from something. An erratic sleeper has the
    /// opposite problem: a band wide enough to swallow a genuinely terrible
    /// night, so nothing is ever a disruption and the answer is always
    /// "steady". Both failures are silent.
    ///
    /// This replaces a flat 25 minutes applied to everyone, which was a claim
    /// that all sleepers vary by the same amount.
    static func personalTolerance(
        _ values: [Double],
        floor: Double,
        ceiling: Double
    ) -> Double? {
        guard values.count >= 3, let mad = Statistics.medianAbsoluteDeviation(values) else {
            return nil
        }
        return min(max(mad * 1.4826, floor), ceiling)
    }

    /// Bounds for sleep duration, in minutes.
    ///
    /// Thirty minutes is about the resolution at which a night reads as
    /// shorter than usual at all; ninety is where "a short night for you"
    /// stops meaning anything.
    static let durationToleranceFloor = 30.0
    static let durationToleranceCeiling = 90.0

    /// Bounds for bedtime, in minutes.
    static let bedtimeToleranceFloor = 45.0
    static let bedtimeToleranceCeiling = 120.0

    /// What knocked the sleep off course.
    ///
    /// The *outcome* measured is always the same — sleep length returning to
    /// this person's own usual — because that is what "bounced back" means.
    /// These are the triggers, and they are worth separating because the
    /// answers differ: a short night is usually repaid quickly, a displaced
    /// schedule less so, and travel least of all.
    enum DisruptionKind: String, Hashable, Sendable, CaseIterable {
        /// A night unusually short for this person.
        case shortSleep
        /// A bedtime unusually late for this person.
        case lateSchedule
        /// A night recorded in a different timezone from the one before it.
        case travel

        var label: String {
            switch self {
            case .shortSleep: "Short sleep"
            case .lateSchedule: "Late schedule"
            case .travel: "Travel"
            }
        }
    }

    struct TypedResult: Hashable, Sendable, Identifiable {
        let kind: DisruptionKind
        let result: Result
        var id: String { kind.rawValue }

        /// "usual bounce-back: 1.8 nights", or why there is not one yet.
        var sentence: String {
            switch result.state {
            case .measured(let median):
                let nights = median == 1 ? "1 night" : "\(Self.formatted(median)) nights"
                return "usual bounce-back: \(nights)"
            case .steady:
                return "hasn't happened in this window"
            case .tooFewEvents(let found, let required):
                return "\(found) of \(required) episodes so far"
            case .insufficientHistory(let nights, let required):
                return "\(nights) of \(required) nights"
            }
        }

        private static func formatted(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }
    }

    /// Bounce-back after each kind of disruption.
    ///
    /// - Parameter nights: history, any order. Sorted internally.
    static func byDisruptionType(
        nights: [SleepNightFeatures],
        calendar: Calendar = .current
    ) -> [TypedResult] {
        let sorted = nights.sorted { $0.date < $1.date }
        let durations = sorted.map(\.timeAsleepMinutes)
        guard let durationCentre = Statistics.median(durations),
              let durationTolerance = personalTolerance(
                durations, floor: durationToleranceFloor, ceiling: durationToleranceCeiling
              )
        else { return [] }

        // The outcome, shared by every kind: sleep length back inside this
        // person's own band. A disruption is not over because the trip is
        // over; it is over when the sleep comes back.
        let isRecovered = durations.map { $0 >= durationCentre - durationTolerance }

        let bedtimes = sorted.map { night -> Double in
            var nightCalendar = calendar
            nightCalendar.timeZone = night.timeZone
            return Statistics.circularMinutesFromMidnight(night.bedtime, calendar: nightCalendar)
        }
        let bedtimeCentre = Statistics.median(bedtimes)
        let bedtimeTolerance = personalTolerance(
            bedtimes, floor: bedtimeToleranceFloor, ceiling: bedtimeToleranceCeiling
        )

        return DisruptionKind.allCases.compactMap { kind -> TypedResult? in
            let triggers: [Bool]
            switch kind {
            case .shortSleep:
                triggers = durations.map { $0 < durationCentre - durationTolerance }
            case .lateSchedule:
                guard let bedtimeCentre, let bedtimeTolerance else { return nil }
                triggers = bedtimes.map { $0 > bedtimeCentre + bedtimeTolerance }
            case .travel:
                // A night whose recorded timezone differs from the previous
                // stored night's. A same-timezone trip is real travel this
                // cannot see, which is why its absence is evidence of
                // nothing -- the same rule `JournalCorrelator` applies.
                triggers = sorted.enumerated().map { index, night in
                    guard index > 0 else { return false }
                    return sorted[index - 1].timeZoneIdentifier != night.timeZoneIdentifier
                }
            }
            return TypedResult(
                kind: kind,
                result: measure(triggers: triggers, isRecovered: isRecovered, nightCount: sorted.count)
            )
        }
    }

    /// Return times when the trigger and the recovery signal are different
    /// things — a travel night is the disruption, and sleep length coming
    /// back is the recovery.
    ///
    /// A run of consecutive triggers is one event, and the return time is
    /// counted from the first night of that run, matching
    /// `measure(observations:baseline:tolerance:direction:)`.
    static func measure(
        triggers: [Bool],
        isRecovered: [Bool],
        nightCount: Int
    ) -> Result {
        guard nightCount >= minimumNights, triggers.count == isRecovered.count else {
            return Result(
                state: .insufficientHistory(nights: nightCount, required: minimumNights),
                eventCount: 0,
                censoredCount: 0,
                nightCount: nightCount
            )
        }

        var returnTimes: [Int] = []
        var censored = 0
        var index = 0

        while index < triggers.count {
            guard triggers[index] else {
                index += 1
                continue
            }
            var blockEnd = index
            while blockEnd + 1 < triggers.count, triggers[blockEnd + 1] { blockEnd += 1 }

            var cursor = blockEnd + 1
            while cursor < triggers.count, !isRecovered[cursor] || triggers[cursor] { cursor += 1 }

            if cursor < triggers.count {
                returnTimes.append(cursor - index)
            } else {
                censored += 1
            }
            index = cursor + 1
        }

        let events = returnTimes.count + censored
        if events == 0 {
            return Result(state: .steady, eventCount: 0, censoredCount: 0, nightCount: nightCount)
        }
        if events < minimumEvents {
            return Result(
                state: .tooFewEvents(found: events, required: minimumEvents),
                eventCount: events,
                censoredCount: censored,
                nightCount: nightCount
            )
        }
        return Result(
            state: .measured(medianNights: median(of: returnTimes, totalEvents: events)),
            eventCount: events,
            censoredCount: censored,
            nightCount: nightCount
        )
    }

    /// Median nights to return to the typical band after leaving it.
    ///
    /// - Parameters:
    ///   - observations: oldest first. Nights missing this metric are simply
    ///     absent; gaps are counted in nights of *record*, not calendar days,
    ///     because a night nobody measured cannot say whether the signal had
    ///     returned.
    ///   - baseline: the person's own centre for this metric.
    ///   - tolerance: half-width of their typical band, as `VitalsStatus`
    ///     already computes it.
    static func measure(
        observations: [Observation],
        baseline: Double,
        tolerance: Double,
        direction: Direction
    ) -> Result {
        let nights = observations.count
        guard nights >= minimumNights else {
            return Result(
                state: .insufficientHistory(nights: nights, required: minimumNights),
                eventCount: 0,
                censoredCount: 0,
                nightCount: nights
            )
        }
        guard tolerance > 0 else {
            // A zero-width band makes every night a disruption. That is a
            // broken baseline, not a fragile person.
            return Result(
                state: .insufficientHistory(nights: nights, required: minimumNights),
                eventCount: 0,
                censoredCount: 0,
                nightCount: nights
            )
        }

        let disrupted = observations.map {
            direction.isDisrupted($0.value, baseline: baseline, tolerance: tolerance)
        }

        var returnTimes: [Int] = []
        var censored = 0
        var index = 0

        while index < disrupted.count {
            guard disrupted[index] else {
                index += 1
                continue
            }
            // Walk to the first night back inside the band. A run of
            // consecutive disrupted nights is one event, not several.
            var cursor = index + 1
            while cursor < disrupted.count, disrupted[cursor] { cursor += 1 }

            if cursor < disrupted.count {
                returnTimes.append(cursor - index)
            } else {
                censored += 1
            }
            index = cursor + 1
        }

        let events = returnTimes.count + censored

        if events == 0 {
            return Result(state: .steady, eventCount: 0, censoredCount: 0, nightCount: nights)
        }
        if events < minimumEvents {
            return Result(
                state: .tooFewEvents(found: events, required: minimumEvents),
                eventCount: events,
                censoredCount: censored,
                nightCount: nights
            )
        }
        // Right-censoring: an event still outside the band when the window
        // ends has a return time of "at least this long, and we don't know
        // how much longer". Dropping it and taking the median of the rest
        // would bias the answer toward fast recovery -- the flattering
        // direction, and so the one to be careful about.
        //
        // It cannot bias this median, and the reason is structural rather
        // than statistical: only the run that touches the end of the window
        // can be censored, so `censored` is never more than 1. With at least
        // three events, fewer than half are censored, and the median
        // therefore falls among the return times actually observed. The
        // censored event is known to be longer than all of them, so it sorts
        // last without needing a value. `censoredCount` is still reported,
        // because a surface should be able to say one disruption is ongoing.
        return Result(
            state: .measured(medianNights: median(of: returnTimes, totalEvents: events)),
            eventCount: events,
            censoredCount: censored,
            nightCount: nights
        )
    }

    /// Median over all events. A censored event is known only to be longer
    /// than every observed return time, so it sorts last without needing a
    /// value — see the reasoning at the call site for why that never moves
    /// the median out of the observed range.
    private static func median(of returnTimes: [Int], totalEvents: Int) -> Double {
        let sorted = returnTimes.sorted()
        let middle = totalEvents / 2
        if totalEvents.isMultiple(of: 2) {
            // Both middle positions are known values: at most one event is
            // censored and there are at least three, so index `middle` is
            // still within `sorted`.
            let lower = Double(sorted[middle - 1])
            let upper = Double(sorted[middle])
            return (lower + upper) / 2
        }
        return Double(sorted[middle])
    }
}

extension SleepResilience.Direction {

    /// Which way is the unfavourable way for each vital.
    ///
    /// HRV, blood oxygen and sleep duration are worse when they fall; resting
    /// heart rate, respiratory rate, wrist temperature and breathing
    /// disturbances are worse when they rise. Getting this backwards would
    /// score someone's best nights as disruptions to recover from.
    static func forVital(_ kind: VitalsStatus.Kind) -> Self {
        switch kind {
        case .hrv, .oxygenSaturation, .sleepDuration: .belowIsDisruption
        case .restingHeartRate, .respiratoryRate, .wristTemperature, .breathingDisturbances:
            .aboveIsDisruption
        }
    }
}

extension SleepResilience.Result {

    /// The headline a surface shows. Never a number without the events behind
    /// it, and never an age.
    var headline: String {
        switch state {
        case .insufficientHistory(let nights, let required):
            "\(nights) of \(required) nights"
        case .steady:
            "Hasn't left your range"
        case .tooFewEvents(let found, let required):
            "\(found) of \(required) dips"
        case .measured(let median):
            median == 1 ? "Back in 1 night" : "Back in \(formatted(median)) nights"
        }
    }

    func explanation(metric: String) -> String {
        let name = metric.lowercased()
        switch state {
        case .insufficientHistory(_, let required):
            return "Resilience needs about \(required) nights of \(name) before it means anything."
        case .steady:
            return "Your \(name) has stayed inside your typical range for every night here — there's nothing to recover from."
        case .tooFewEvents(_, let required):
            return "Zoon waits for \(required) separate dips before calling this a pattern rather than an odd night."
        case .measured:
            let ongoing = censoredCount > 0 ? " One is still ongoing." : ""
            return "Across \(eventCount) times your \(name) left your typical range, this is how long it usually took to come back.\(ongoing)"
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
