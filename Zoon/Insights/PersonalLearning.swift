import Foundation

/// Personal, observational learning that stays outside Zoon's scored metrics.
enum PersonalLearning {
    struct Resilience: Identifiable, Equatable {
        enum Metric: String { case sleepTiming, sleepDebt, hrv }
        let metric: Metric
        let nights: Int
        let disruptions: Int
        var id: String { metric.rawValue }
        var title: String {
            switch metric {
            case .sleepTiming: "Sleep timing"
            case .sleepDebt: "Sleep debt"
            case .hrv: "HRV"
            }
        }
        var sentence: String {
            let unit = nights == 1 ? "night" : "nights"
            return "\(title) usually returned to your recent range in \(nights) \(unit)."
        }
    }

    struct CircadianResponse: Equatable {
        let minutesEarlier: Int
        let daylightNights: Int
        let comparisonNights: Int
        let uncertaintyMinutes: Int
        var sentence: String {
            let direction = minutesEarlier >= 0 ? "earlier" : "later"
            return "Nights after morning daylight were followed by sleep timing about \(abs(minutesEarlier)) minutes \(direction)."
        }
    }

    struct ProactiveItem: Identifiable, Equatable {
        enum Kind: String { case debt, timing, bodySignals, experiment }
        let kind: Kind
        let title: String
        let detail: String
        let action: String
        var id: String { kind.rawValue }
    }

    /// Requires at least two independent disruptions and reports a median,
    /// never a best case. Recovery means two consecutive nights back inside
    /// the person's pre-event range so a single noisy night cannot end it.
    static func resilience(
        nights: [SleepNightFeatures],
        disruptionDates: Set<Date>,
        calendar: Calendar = .current
    ) -> [Resilience] {
        let ordered = nights.sorted { $0.date < $1.date }
        guard ordered.count >= 12, disruptionDates.count >= 2 else { return [] }

        func isDisruption(_ date: Date) -> Bool {
            disruptionDates.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        func median(_ values: [Double]) -> Double? { Statistics.median(values) }
        func bedtimeMinute(_ night: SleepNightFeatures) -> Double {
            let zone = TimeZone(identifier: night.timeZoneIdentifier) ?? calendar.timeZone
            var local = calendar; local.timeZone = zone
            let c = local.dateComponents([.hour, .minute], from: night.bedtime)
            var value = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if value < 12 * 60 { value += 24 * 60 }
            return value
        }

        var timing: [Int] = [], debt: [Int] = [], hrv: [Int] = []
        for index in ordered.indices where isDisruption(ordered[index].date) && index >= 5 {
            let baseline = Array(ordered[(index - 5)..<index])
            let future = Array(ordered.dropFirst(index + 1).prefix(7))
            guard future.count >= 2 else { continue }

            if let center = median(baseline.map(bedtimeMinute)),
               let recovered = firstStableIndex(future.map { abs(bedtimeMinute($0) - center) <= 35 }) {
                timing.append(recovered)
            }
            if let center = median(baseline.compactMap(\.sleepDebtMinutes)),
               let recovered = firstStableIndex(future.map { ($0.sleepDebtMinutes ?? Double.greatestFiniteMagnitude) <= center + 45 }) {
                debt.append(recovered)
            }
            if let center = median(baseline.compactMap(\.avgHRV)), center > 0,
               let recovered = firstStableIndex(future.map { abs(($0.avgHRV ?? -Double.greatestFiniteMagnitude) - center) / center <= 0.12 }) {
                hrv.append(recovered)
            }
        }

        return [(Resilience.Metric.sleepTiming, timing), (.sleepDebt, debt), (.hrv, hrv)].compactMap { metric, values in
            guard values.count >= 2, let typical = Statistics.median(values.map(Double.init)) else { return nil }
            return Resilience(metric: metric, nights: Int(typical.rounded()), disruptions: values.count)
        }
    }

    private static func firstStableIndex(_ withinRange: [Bool]) -> Int? {
        guard withinRange.count >= 2 else { return nil }
        for index in 0..<(withinRange.count - 1) where withinRange[index] && withinRange[index + 1] {
            return index + 1
        }
        return nil
    }

    /// Compares explicitly answered daylight/no-daylight nights. The result is
    /// observational and deliberately withheld below six nights per group.
    static func circadianResponse(observations: [JournalCorrelator.Observation]) -> CircadianResponse? {
        let yes = observations.filter { $0.exposureState(for: .morningDaylight) == .yes }.compactMap(\.bedtimeHour)
        let no = observations.filter { $0.exposureState(for: .morningDaylight) == .no }.compactMap(\.bedtimeHour)
        guard yes.count >= 6, no.count >= 6,
              let yesMedian = Statistics.median(yes), let noMedian = Statistics.median(no) else { return nil }
        let minutesEarlier = Int(((noMedian - yesMedian) * 60).rounded())
        guard abs(minutesEarlier) >= 10 else { return nil }
        let spread = (Statistics.medianAbsoluteDeviation(yes, median: yesMedian) ?? 0.5)
            + (Statistics.medianAbsoluteDeviation(no, median: noMedian) ?? 0.5)
        return CircadianResponse(
            minutesEarlier: minutesEarlier,
            daylightNights: yes.count,
            comparisonNights: no.count,
            uncertaintyMinutes: max(10, Int((spread * 30).rounded()))
        )
    }

    /// One or two high-value items only. Repeated low-level nudges are omitted.
    static func proactiveItems(nights: [SleepNightFeatures], radar: HealthRadar) -> [ProactiveItem] {
        guard let latest = nights.sorted(by: { $0.date < $1.date }).last else { return [] }
        var items: [ProactiveItem] = []
        if radar.isActive {
            items.append(.init(kind: .bodySignals, title: "Body signals changed together", detail: radar.detail, action: "Review body signals"))
        }
        if let debt = latest.sleepDebtMinutes, debt >= 240 {
            items.append(.init(kind: .debt, title: "Sleep debt is building", detail: "Your recent shortfall is about \(Int((debt / 60).rounded())) hours.", action: "Plan tonight"))
        }
        if items.isEmpty, nights.count >= 8 {
            let recent = Array(nights.sorted(by: { $0.date < $1.date }).suffix(3))
            let earlier = Array(nights.sorted(by: { $0.date < $1.date }).dropLast(3).suffix(7))
            let minute: (SleepNightFeatures) -> Double = { night in
                let c = Calendar.current.dateComponents([.hour, .minute], from: night.bedtime)
                var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)); if m < 720 { m += 1440 }; return m
            }
            if let a = Statistics.median(recent.map(minute)), let b = Statistics.median(earlier.map(minute)), abs(a - b) >= 60 {
                items.append(.init(kind: .timing, title: "Your timing shifted", detail: "Recent bedtimes moved about \(Int(abs(a - b).rounded())) minutes from your prior week.", action: "See body clock"))
            }
        }
        return Array(items.prefix(2))
    }
}
