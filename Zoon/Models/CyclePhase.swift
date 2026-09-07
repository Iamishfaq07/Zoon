import Foundation
import HealthKit

/// A broad, calendar-estimated part of a recorded cycle.
///
/// These are deliberately timing bands, not physiological phase or ovulation
/// claims. Apple Health gives Zoon recorded period starts, not evidence that
/// ovulation happened on a particular date.
///
/// Entirely opt-in — see `HealthKitManager.requestCycleTrackingAuthorization`.
/// Nothing here is read, computed, or shown unless the user turns it on.
enum CyclePhase: String, Codable, Sendable, CaseIterable {
    case periodDays, earlier, middle, later

    var label: String {
        switch self {
        case .periodDays: "Days 1–5"
        case .earlier: "Earlier cycle"
        case .middle: "Middle cycle"
        case .later: "Later cycle"
        }
    }

    /// Divides a person's observed typical cycle into broad timing bands.
    /// A caller must first establish a stable personal cycle length; there is
    /// intentionally no textbook 28-day fallback.
    static func phase(forCycleDay day: Int, typicalCycleLength: Int) -> CyclePhase? {
        guard day > 0, typicalCycleLength >= 21, typicalCycleLength <= 45,
              day <= typicalCycleLength + 7 else { return nil }
        if day <= 5 { return .periodDays }
        let position = Double(day - 1) / Double(typicalCycleLength)
        if position < 0.45 { return .earlier }
        if position < 0.65 { return .middle }
        return .later
    }
}

/// Cycle-day estimate for a specific date, from logged period starts.
struct CycleContext: Sendable {
    /// 1-based day within the current cycle, or `nil` before the first
    /// logged start.
    let cycleDay: Int?

    /// Finds the most recent period start on or before `date` and returns the
    /// day offset. `starts` need not be sorted.
    static func compute(date: Date, starts: [Date], calendar: Calendar = .current) -> CycleContext {
        let priorStarts = starts.filter { $0 <= date }
        guard let mostRecent = priorStarts.max() else {
            return CycleContext(cycleDay: nil)
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: mostRecent), to: calendar.startOfDay(for: date)).day ?? 0
        return CycleContext(cycleDay: days + 1)
    }

    /// Extracts period-start dates from raw samples, using the
    /// `menstrualCycleStart` metadata flag HealthKit attaches to the first
    /// logged sample of each period. Falls back to nothing rather than
    /// guessing from gaps — a wrong guess here mislabels every phase after it.
    static func periodStarts(from samples: [HKCategorySample]) -> [Date] {
        samples.compactMap { sample in
            (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) == true
                ? sample.startDate
                : nil
        }
    }

    /// Median interval between recorded starts when the history is stable
    /// enough to support broad calendar context. Highly variable histories
    /// stay as cycle-day data only rather than receiving misleading bands.
    static func typicalCycleLength(starts: [Date], calendar: Calendar = .current) -> Int? {
        let ordered = Array(Set(starts.map { calendar.startOfDay(for: $0) })).sorted()
        let intervals = zip(ordered, ordered.dropFirst()).compactMap { pair -> Int? in
            let (start, end) = pair
            guard let days = calendar.dateComponents([.day], from: start, to: end).day,
                  (21...45).contains(days) else { return nil }
            return days
        }
        guard intervals.count >= 2,
              let shortest = intervals.min(), let longest = intervals.max(),
              longest - shortest <= 9 else { return nil }
        let sorted = intervals.sorted()
        return sorted[sorted.count / 2]
    }
}

/// Mean recovery and sleep performance grouped by cycle phase, for the Trends
/// correlation card.
struct CyclePhaseCorrelation: Identifiable, Sendable {
    let phase: CyclePhase
    let nightCount: Int
    let avgRecoveryPercent: Double?
    let avgSleepPerformance: Double?

    var id: String { phase.rawValue }

    /// Groups nights by the phase they fell in and averages recovery/sleep
    /// performance within each. Phases with fewer than three nights are
    /// dropped — same reasoning as everywhere else in the app that a
    /// two-night average isn't a pattern yet.
    static func compute(
        nights: [(date: Date, recoveryPercent: Int, sleepPerformance: Double)],
        periodStarts: [Date],
        calendar: Calendar = .current
    ) -> [CyclePhaseCorrelation] {
        guard let typicalLength = CycleContext.typicalCycleLength(
            starts: periodStarts, calendar: calendar
        ) else { return [] }

        var byPhase: [CyclePhase: [(Int, Double)]] = [:]
        for night in nights {
            guard let day = CycleContext.compute(date: night.date, starts: periodStarts, calendar: calendar).cycleDay
            else { continue }
            guard let phase = CyclePhase.phase(
                forCycleDay: day, typicalCycleLength: typicalLength
            ) else { continue }
            byPhase[phase, default: []].append((night.recoveryPercent, night.sleepPerformance))
        }

        return CyclePhase.allCases.compactMap { phase in
            guard let values = byPhase[phase], values.count >= 3 else { return nil }
            let recovery = values.map { Double($0.0) }.reduce(0, +) / Double(values.count)
            let sleep = values.map(\.1).reduce(0, +) / Double(values.count)
            return CyclePhaseCorrelation(
                phase: phase, nightCount: values.count,
                avgRecoveryPercent: recovery, avgSleepPerformance: sleep
            )
        }
    }
}
