import Foundation

/// Where HRV sits relative to a slow personal baseline.
///
/// Garmin's HRV Status. The distinction from the recovery score matters: recovery
/// is about *today*, this is about the last week against the last three months.
/// A single low night is normal. A week of low nights inside a stable long-term
/// baseline is the thing worth telling someone about, and it's invisible in any
/// day-to-day view.
struct HRVStatus: Codable, Hashable, Sendable {

    let state: State
    /// Mean HRV over the last 7 nights.
    let weeklyAverage: Double?
    /// Long-term personal baseline (up to 90 nights).
    let baseline: Double?
    /// Bounds of the personal balanced range.
    let lowerBound: Double?
    let upperBound: Double?
    let nightCount: Int

    enum State: String, Codable, Hashable, Sendable {
        case balanced
        case unbalanced
        case low
        case poor
        case building

        var label: String {
            switch self {
            case .balanced: "Balanced"
            case .unbalanced: "Unbalanced"
            case .low: "Low"
            case .poor: "Poor"
            case .building: "Building baseline"
            }
        }

        var detail: String {
            switch self {
            case .balanced:
                "Your HRV over the past week sits inside your personal range. Your body is handling its current load."
            case .unbalanced:
                "Your weekly HRV has drifted outside your usual range. Often training load, travel, stress, or alcohol."
            case .low:
                "Your HRV has been below your usual range for several days. Consider easing off and prioritising sleep."
            case .poor:
                "Your HRV has been well below baseline for an extended period. Worth backing off substantially."
            case .building:
                "Zoon needs about three weeks of nights to establish your personal HRV range."
            }
        }
    }

    /// Nights required before a status is claimed.
    static let minimumNights = 21

    /// Baseline window. Long on purpose — a short window tracks a training
    /// block so closely that it quietly redefines "normal" and stops noticing
    /// that you're buried.
    static let baselineWindow = 90

    static func evaluate(recentHRV: [Double], longTermHRV: [Double]) -> HRVStatus {
        guard longTermHRV.count >= minimumNights, !recentHRV.isEmpty else {
            return HRVStatus(
                state: .building,
                weeklyAverage: recentHRV.isEmpty ? nil : recentHRV.reduce(0, +) / Double(recentHRV.count),
                baseline: nil, lowerBound: nil, upperBound: nil,
                nightCount: longTermHRV.count
            )
        }

        let window = Array(longTermHRV.suffix(baselineWindow))
        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + pow($1 - mean, 2) } / Double(window.count)
        let sd = variance.squareRoot()

        let weekly = recentHRV.reduce(0, +) / Double(recentHRV.count)
        let lower = mean - sd
        let upper = mean + sd

        let state: State
        if weekly >= lower && weekly <= upper {
            state = .balanced
        } else if weekly > upper {
            // Above the range isn't a problem, but it isn't "balanced" either —
            // it usually means a deload, or a very easy week.
            state = .unbalanced
        } else if weekly >= mean - 2 * sd {
            state = .low
        } else {
            state = .poor
        }

        return HRVStatus(
            state: state,
            weeklyAverage: weekly,
            baseline: mean,
            lowerBound: lower,
            upperBound: upper,
            nightCount: window.count
        )
    }
}

/// Sleep chronotype, inferred from habitual timing.
///
/// Fitbit's "sleep animal", which is a genuinely good idea dressed up in a fun
/// name: the actionable part isn't the label, it's that consistency against
/// *your* natural window beats forcing yourself onto someone else's schedule.
struct Chronotype: Codable, Hashable, Sendable {

    let kind: Kind
    /// Median bedtime as hours from midnight (negative = before midnight).
    let medianBedtimeHour: Double
    let medianDurationMinutes: Double
    /// Bedtime spread, minutes. High = irregular.
    let consistencyMinutes: Double
    let nightCount: Int

    enum Kind: String, Codable, Hashable, Sendable {
        case lion       // early to bed, early to rise
        case bear       // tracks the sun, the majority
        case wolf       // late to bed, late to rise
        case dolphin    // short, light, irregular sleeper
        case unknown

        var label: String {
            switch self {
            case .lion: "Lion"
            case .bear: "Bear"
            case .wolf: "Wolf"
            case .dolphin: "Dolphin"
            case .unknown: "Learning"
            }
        }

        var symbol: String {
            switch self {
            case .lion: "sun.horizon.fill"
            case .bear: "sun.max.fill"
            case .wolf: "moon.stars.fill"
            case .dolphin: "wind"
            case .unknown: "questionmark.circle"
            }
        }

        var detail: String {
            switch self {
            case .lion:
                "You're a natural early riser — asleep well before midnight, awake before most. Your best work happens in the morning; guard your early bedtime rather than pushing through evenings."
            case .bear:
                "You follow the sun, like most people. Your schedule is the one the world is built around, which makes consistency the easiest win available to you."
            case .wolf:
                "You're a night owl. Forcing a 6am start will cost you more than it gains — where you have the freedom, shift your day later rather than fighting it."
            case .dolphin:
                "You sleep light, short, and irregularly. Consistency will do more for you than duration: same bedtime, same wake time, even on weekends."
            case .unknown:
                "Zoon needs a couple of weeks of nights to recognise your pattern."
            }
        }
    }

    static let minimumNights = 10

    /// - Parameter bedtimeHours: bedtimes as hours from midnight, where an
    ///   evening bedtime is negative (23:30 → −0.5). Callers should use the
    ///   same shifted convention as the consistency chart.
    static func infer(
        bedtimeHours: [Double],
        durations: [Double],
        consistencyMinutes: Double?
    ) -> Chronotype {

        guard bedtimeHours.count >= minimumNights else {
            return Chronotype(
                kind: .unknown, medianBedtimeHour: 0, medianDurationMinutes: 0,
                consistencyMinutes: consistencyMinutes ?? 0, nightCount: bedtimeHours.count
            )
        }

        let bedtime = median(bedtimeHours)
        let duration = median(durations)
        let spread = consistencyMinutes ?? 0

        // Order matters: irregular-and-short is checked first, because a
        // dolphin's median bedtime can land anywhere and would otherwise be
        // misread as one of the stable types.
        let kind: Kind
        if spread > 75 || duration < 360 {
            kind = .dolphin
        } else if bedtime <= -1.5 {
            kind = .lion
        } else if bedtime >= 0.5 {
            kind = .wolf
        } else {
            kind = .bear
        }

        return Chronotype(
            kind: kind,
            medianBedtimeHour: bedtime,
            medianDurationMinutes: duration,
            consistencyMinutes: spread,
            nightCount: bedtimeHours.count
        )
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    /// "23:20" from the shifted hour convention.
    var formattedBedtime: String {
        let hour = medianBedtimeHour < 0 ? medianBedtimeHour + 24 : medianBedtimeHour
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60)
        return String(format: "%02d:%02d", h % 24, abs(m))
    }
}
