import Foundation

/// Hourly expected cognitive energy for the waking day.
///
/// `EnergyForecast` already draws the *shape* of the day (morning peak,
/// afternoon dip, second wind) from wake time and sleep debt. This type
/// fills the *amplitude*: last night's HRV, the overnight resting-heart-rate
/// dip, and the REM/Deep mix decide how high the peak sits and how deep the
/// slump goes.
///
/// Explicitly an estimate. Nothing on a wrist measures cognitive performance.
/// The array is labelled that way wherever it is shown.
struct CognitiveEnergyCurve: Hashable, Sendable {

    struct Hour: Hashable, Sendable, Identifiable {
        /// Hours since wake, 0-based.
        let offset: Int
        /// 0...1 relative alertness. Not a physical unit.
        let level: Double
        /// Peak focus vs afternoon slump vs other.
        let band: Band
        var id: Int { offset }
    }

    enum Band: String, Sendable {
        case peakFocus, steady, slump, windDown

        var label: String {
            switch self {
            case .peakFocus: "Peak focus"
            case .steady: "Steady"
            case .slump: "Afternoon slump"
            case .windDown: "Wind down"
            }
        }
    }

    let hours: [Hour]
    /// Inputs that were missing, so a caller can say so rather than
    /// presenting a fully-informed curve.
    let missing: [String]

    /// - Parameters:
    ///   - wakeTime: when the person actually woke.
    ///   - hourCount: waking hours to project. Clamped to 12...18.
    ///   - hrvSDNN: overnight HRV in milliseconds.
    ///   - hrvBaseline: typical HRV for this person; `nil` treats the night
    ///     as average (ratio 1).
    ///   - restingHeartRate: today's resting HR.
    ///   - minOvernightHeartRate: the sleep-window low. The dip is
    ///     `resting - min`; a larger dip is a healthier overnight recovery
    ///     signal, within a bounded nudge.
    ///   - remMinutes / deepMinutes / asleepMinutes: last night's mix.
    ///   - sleepDebtMinutes: already-computed debt, so this type does not
    ///     re-derive it.
    static func compute(
        wakeTime: Date,
        hourCount: Int = 16,
        hrvSDNN: Double?,
        hrvBaseline: Double?,
        restingHeartRate: Double?,
        minOvernightHeartRate: Double?,
        remMinutes: Double,
        deepMinutes: Double,
        asleepMinutes: Double,
        sleepDebtMinutes: Double
    ) -> CognitiveEnergyCurve {
        var missing: [String] = []
        let hrvRatio: Double
        if let hrvSDNN, let hrvBaseline, hrvBaseline > 0 {
            hrvRatio = min(1.15, max(0.75, hrvSDNN / hrvBaseline))
        } else {
            hrvRatio = 1
            if hrvSDNN == nil { missing.append("HRV") }
        }

        let dipNudge: Double
        if let restingHeartRate, let minOvernightHeartRate, restingHeartRate > 0 {
            let dip = max(0, restingHeartRate - minOvernightHeartRate)
            // A 6–12 bpm overnight dip is typical; scale a ±8% nudge around 8 bpm.
            dipNudge = min(1.08, max(0.92, 0.92 + (dip / 8) * 0.16))
        } else {
            dipNudge = 1
            if minOvernightHeartRate == nil { missing.append("overnight HR dip") }
        }

        let stageNudge: Double
        if asleepMinutes > 0 {
            let rem = remMinutes / asleepMinutes
            let deep = deepMinutes / asleepMinutes
            // REM feeds daytime cognition; deep feeds restoration. Both are
            // nudges, not scores — a night without stages must not collapse
            // the curve to zero.
            stageNudge = min(1.1, max(0.85, 0.85 + rem * 0.5 + deep * 0.4))
        } else {
            stageNudge = 1
            missing.append("sleep stages")
        }

        let debtHours = max(0, sleepDebtMinutes) / 60
        let debtAttenuation = max(0.75, 1 - min(debtHours * 0.06, 0.25))
        let amplitude = hrvRatio * dipNudge * stageNudge * debtAttenuation

        let count = min(18, max(12, hourCount))
        let hours: [Hour] = (0..<count).map { offset in
            let shape = twoProcessShape(hoursAwake: Double(offset))
            let level = min(1, max(0, shape * amplitude))
            let band: Band
            switch offset {
            case 2...5: band = level >= 0.7 ? .peakFocus : .steady
            case 6...9: band = level <= 0.45 ? .slump : .steady
            case 13...: band = .windDown
            default: band = .steady
            }
            return Hour(offset: offset, level: level, band: band)
        }

        return CognitiveEnergyCurve(hours: hours, missing: missing)
    }

    /// Instant of each hour, anchored to `wakeTime`.
    func timeline(from wakeTime: Date) -> [(date: Date, hour: Hour)] {
        hours.map { hour in
            (date: wakeTime.addingTimeInterval(Double(hour.offset) * 3600), hour: hour)
        }
    }

    /// Borbély two-process sketch: homeostatic pressure building since wake
    /// (Process S) plus a mid-afternoon circadian dip (Process C). Matches
    /// the windows `EnergyForecast` already names, as a continuous curve.
    static func twoProcessShape(hoursAwake: Double) -> Double {
        let s = exp(-hoursAwake / 18)           // slow decay of morning alertness
        let morning = 1 - exp(-hoursAwake / 1.6) // rise over the first ~3h
        let dip = 0.22 * exp(-pow((hoursAwake - 7.5) / 2.2, 2))
        let secondWind = 0.12 * exp(-pow((hoursAwake - 11.0) / 1.8, 2))
        return min(1, max(0, (0.35 + 0.65 * morning) * s - dip + secondWind))
    }
}
