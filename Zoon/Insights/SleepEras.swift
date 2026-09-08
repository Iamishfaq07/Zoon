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
    static func detect(in nights: [SleepNightFeatures], minimumNights: Int = 7) -> [SleepEra] {
        let ordered = nights.sorted { $0.date < $1.date }
        guard ordered.count >= minimumNights else { return [] }
        var groups: [[SleepNightFeatures]] = []
        var current: [SleepNightFeatures] = []

        for night in ordered {
            if current.isEmpty { current = [night]; continue }
            let reference = current.suffix(minimumNights)
            let timing = abs(circularDelta(minutes(night.bedtime), medianMinutes(reference.map { minutes($0.bedtime) })))
            let duration = abs(night.timeAsleepMinutes - (Statistics.median(reference.map(\.timeAsleepMinutes)) ?? 0))
            if current.count >= minimumNights && (timing >= 45 || duration >= 60) {
                groups.append(current)
                current = [night]
            } else {
                current.append(night)
            }
        }
        if !current.isEmpty { groups.append(current) }

        // Avoid tiny tail fragments: merge them into the preceding era.
        if groups.count > 1, groups.last!.count < minimumNights {
            let tail = groups.removeLast()
            groups[groups.count - 1].append(contentsOf: tail)
        }

        return groups.map { group in
            let bed = medianMinutes(group.map { minutes($0.bedtime) })
            let previous = groups.firstIndex(where: { $0.first?.date == group.first?.date }).flatMap { index -> [SleepNightFeatures]? in
                guard index > 0 else { return nil }; return groups[index - 1]
            }
            let previousBed = previous.map { medianMinutes($0.map { minutes($0.bedtime) }) }
            let previousDuration = previous.flatMap { Statistics.median($0.map(\.timeAsleepMinutes)) }
            return SleepEra(
                id: "\(group[0].date.timeIntervalSince1970)-\(group.count)",
                start: group[0].date,
                end: group[group.count - 1].date,
                nights: group.count,
                medianBedtime: dateFromMinutes(bed, reference: group[0].bedtime),
                averageSleepMinutes: group.map(\.timeAsleepMinutes).reduce(0, +) / Double(group.count),
                timingShiftMinutes: previousBed.map { Int(circularDelta(bed, $0).rounded()) },
                durationShiftMinutes: previousDuration.map { Int(((Statistics.median(group.map(\.timeAsleepMinutes)) ?? 0) - $0).rounded()) }
            )
        }
    }

    private static func minutes(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
    private static func medianMinutes(_ values: [Double]) -> Double { Statistics.median(values) ?? 0 }
    private static func circularDelta(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 1440)
        return d > 720 ? d - 1440 : (d < -720 ? d + 1440 : d)
    }
    private static func dateFromMinutes(_ value: Double, reference: Date) -> Date {
        let day = Calendar.current.startOfDay(for: reference)
        return day.addingTimeInterval(value * 60)
    }
}
