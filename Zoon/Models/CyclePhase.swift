import Foundation
import HealthKit

/// Where in the cycle a given date falls, and how recovery/sleep compare
/// across phases.
///
/// Oura and Whoop both correlate cycle phase with readiness; the luteal phase
/// in particular is well-documented to run with elevated resting heart rate
/// and suppressed HRV in many people, which otherwise looks exactly like the
/// Health Radar's illness-drift pattern with no illness behind it. Reading
/// cycle data is what lets Zoon tell those two apart instead of flagging a
/// normal luteal shift as something to worry about.
///
/// Entirely opt-in — see `HealthKitManager.requestCycleTrackingAuthorization`.
/// Nothing here is read, computed, or shown unless the user turns it on.
enum CyclePhase: String, Codable, Sendable, CaseIterable {
    case menstrual, follicular, ovulation, luteal

    var label: String {
        switch self {
        case .menstrual: "Menstrual"
        case .follicular: "Follicular"
        case .ovulation: "Ovulation"
        case .luteal: "Luteal"
        }
    }

    /// Textbook day ranges for a idealised 28-day cycle. Real cycles vary —
    /// this positions each night approximately, which is honest about the
    /// limits of what a handful of logged period-start dates can support.
    /// Zoon does not attempt ovulation prediction from temperature; that's a
    /// different, harder claim than "roughly where in the cycle was this".
    static func phase(forCycleDay day: Int) -> CyclePhase {
        switch day {
        case ..<6: .menstrual
        case 6..<13: .follicular
        case 13..<16: .ovulation
        default: .luteal
        }
    }
}

/// Cycle-day estimate for a specific date, from logged period starts.
struct CycleContext: Sendable {
    /// 1-based day within the current cycle, or `nil` before the first
    /// logged start.
    let cycleDay: Int?
    var phase: CyclePhase? { cycleDay.map(CyclePhase.phase(forCycleDay:)) }

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
        guard !periodStarts.isEmpty else { return [] }

        var byPhase: [CyclePhase: [(Int, Double)]] = [:]
        for night in nights {
            guard let day = CycleContext.compute(date: night.date, starts: periodStarts, calendar: calendar).cycleDay
            else { continue }
            let phase = CyclePhase.phase(forCycleDay: day)
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
