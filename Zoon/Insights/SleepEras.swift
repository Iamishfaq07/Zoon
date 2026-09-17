import Foundation

/// Descriptive periods in a person's history. Eras report what changed,
/// without inferring a cause from observational data.
struct SleepEra: Identifiable, Equatable {
    let id: String
    let start: Date
    let end: Date
    let nights: Int
    let medianBedtime: Date
    let averageSleepMinutes: Double
    let timingShiftMinutes: Int?
    let durationShiftMinutes: Int?
}

enum SleepEras {

    /// Consecutive shifted nights before a change is called an era.
    ///
    /// One night used to be enough: a single flight, a newborn's bad night,
    /// one late shift, and the history was cut in two and told the reader
    /// their sleep had entered a new period. An era is a claim about a
    /// *stretch* of someone's life, and one night is not one.
    ///
    /// Three, not more: two consecutive shifted nights happens by chance
    /// often enough to be noise -- the same reasoning `HealthRadar` uses for
    /// its own three-night rule -- and a threshold high enough to exclude a
    /// week away would also exclude a genuine schedule change someone made
    /// last Monday.
    ///
    /// What this deliberately does *not* do is try to tell a holiday from a
    /// permanent move. That distinction needs the future. A week away shows
    /// as a short era between two similar ones, which is descriptive and
    /// true; calling it "temporary" would be a guess about what happens next.
    static let sustainedNights = 3

    static func detect(in nights: [SleepNightFeatures], minimumNights: Int = 7) -> [SleepEra] {
        let ordered = nights.sorted { $0.date < $1.date }
        guard ordered.count >= minimumNights else { return [] }
        var groups: [[SleepNightFeatures]] = []
        var current: [SleepNightFeatures] = []
        /// Shifted nights not yet numerous enough to call an era. Absorbed
        /// back into `current` the moment sleep returns to the old pattern.
        var pending: [SleepNightFeatures] = []

        for night in ordered {
            if current.isEmpty {
                current = [night]
                continue
            }

            let reference = current.suffix(minimumNights)
            let referenceBedtime = medianMinutes(reference.map { minutes($0) })
            let referenceDuration = Statistics.median(reference.map(\.timeAsleepMinutes)) ?? 0

            // An era needs a floor of its own before it can be left.
            guard current.count >= minimumNights else {
                current.append(night)
                continue
            }

            let timing = abs(circularDelta(minutes(night), referenceBedtime))
            let duration = abs(night.timeAsleepMinutes - referenceDuration)
            let isShifted = timing >= 45 || duration >= 60

            guard isShifted else {
                // Back to the old pattern: whatever was pending was a
                // disruption, not a new era, and belongs to this one.
                current.append(contentsOf: pending)
                current.append(night)
                pending.removeAll()
                continue
            }

            pending.append(night)
            guard pending.count >= Self.sustainedNights else { continue }

            // The run is long enough. It also has to still be shifted *as a
            // group*: three nights that each cleared the threshold in
            // different directions are unsettled sleep, not a new schedule.
            let pendingBedtime = medianMinutes(pending.map { minutes($0) })
            let pendingDuration = Statistics.median(pending.map(\.timeAsleepMinutes)) ?? 0
            let groupTiming = abs(circularDelta(pendingBedtime, referenceBedtime))
            let groupDuration = abs(pendingDuration - referenceDuration)

            if groupTiming >= 45 || groupDuration >= 60 {
                groups.append(current)
                current = pending
            } else {
                current.append(contentsOf: pending)
            }
            pending.removeAll()
        }

        // A run that never reached the threshold ends inside the era it
        // interrupted, not as one of its own.
        current.append(contentsOf: pending)
        if !current.isEmpty { groups.append(current) }

        // Avoid tiny tail fragments: merge them into the preceding era.
        if groups.count > 1, let lastGroup = groups.last, lastGroup.count < minimumNights {
            let tail = groups.removeLast()
            groups[groups.count - 1].append(contentsOf: tail)
        }

        return groups.map { group in
            let bed = medianMinutes(group.map { minutes($0) })
            let previous = groups.firstIndex(where: { $0.first?.date == group.first?.date }).flatMap { index -> [SleepNightFeatures]? in
                guard index > 0 else { return nil }; return groups[index - 1]
            }
            let previousBed = previous.map { medianMinutes($0.map { minutes($0) }) }
            let previousDuration = previous.flatMap { Statistics.median($0.map(\.timeAsleepMinutes)) }
            return SleepEra(
                id: "\(group[0].date.timeIntervalSince1970)-\(group.count)",
                start: group[0].date,
                end: group[group.count - 1].date,
                nights: group.count,
                medianBedtime: dateFromMinutes(bed, reference: group[0]),
                averageSleepMinutes: group.map(\.timeAsleepMinutes).reduce(0, +) / Double(group.count),
                timingShiftMinutes: previousBed.map { Int(circularDelta(bed, $0).rounded()) },
                durationShiftMinutes: previousDuration.map { Int(((Statistics.median(group.map(\.timeAsleepMinutes)) ?? 0) - $0).rounded()) }
            )
        }
    }

    /// Bedtime as signed minutes from midnight, folded the way
    /// `Statistics.circularMinutesFromMidnight` does (18:00 and later are
    /// negative). A linear 0..1439 scale put 23:50 and 00:10 at opposite ends,
    /// so an even-sized era straddling midnight averaged its two middle
    /// values to noon. Uses the night's own timezone, not the device's
    /// current one -- see `SleepNightFeatures.timeZoneIdentifier`.
    private static func minutes(_ night: SleepNightFeatures) -> Double {
        Statistics.circularMinutesFromMidnight(night.bedtime, calendar: nightCalendar(for: night))
    }
    private static func nightCalendar(for night: SleepNightFeatures) -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = night.timeZone
        return calendar
    }
    private static func medianMinutes(_ values: [Double]) -> Double { Statistics.median(values) ?? 0 }
    /// Signed shortest way round, from the one shared implementation. This was
    /// a fourth hand-rolled copy of the same three lines; they agreed, which is
    /// the only reason nobody noticed, and agreement between copies is not a
    /// property anybody was maintaining.
    private static func circularDelta(_ a: Double, _ b: Double) -> Double {
        Statistics.circularDifference(a, b)
    }
    /// Places folded minutes onto the reference night: `date` is the morning
    /// the night is filed under, so negative minutes land on the evening
    /// before it and positive ones on that morning.
    private static func dateFromMinutes(_ value: Double, reference: SleepNightFeatures) -> Date {
        let day = nightCalendar(for: reference).startOfDay(for: reference.date)
        return day.addingTimeInterval(value * 60)
    }
}
