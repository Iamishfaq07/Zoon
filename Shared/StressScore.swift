import Foundation

/// A live, daytime read on autonomic load — Garmin's Stress Score and Whoop's
/// intraday strain signal, reimplemented.
///
/// Every other score in Zoon looks backward at a finished night. This is the
/// one exception: it compares *right now* against your rolling baseline, so
/// it can say something about the day that's still happening rather than only
/// the one that already ended.
///
/// ## Why this can be honest with no new permission
///
/// Heart rate and HRV are already granted for the overnight pipeline. Reusing
/// them for a daytime average costs nothing new to ask for — the trade-off is
/// resolution: this is a single average over however much of the day has
/// elapsed, not a continuous trace. A watch app with a live workout session
/// could sample every few seconds; a phone reading HealthKit after the fact
/// gets whatever discrete samples happened to land. Good enough to say
/// "elevated today", not good enough to say "elevated at 2:14pm".
struct StressScore: Codable, Hashable, Sendable {

    /// 0–100. Higher means further from baseline in the stressed direction.
    let percent: Int
    let band: Band
    /// Minutes of the day this average is drawn from — small early, larger
    /// by evening. Shown so the number reads as "so far today", not final.
    let sampledMinutes: Double
    let avgHeartRate: Double?
    let avgHRV: Double?
    /// False once there's baseline history to compare against honestly.
    let isEstimate: Bool

    enum Band: String, Sendable {
        case calm, elevated, high

        var label: String {
            switch self {
            case .calm: "Calm"
            case .elevated: "Elevated"
            case .high: "High"
            }
        }

        var detail: String {
            switch self {
            case .calm: "Autonomic load today is at or below your usual."
            case .elevated: "Running a bit hot today. Not urgent, worth noticing."
            case .high: "Well above your usual for today. Consider easing off."
            }
        }
    }

    /// Baseline nights required before this is more than a guess.
    static let minimumBaselineNights = 4

    static func compute(
        avgHeartRate: Double?,
        avgHRV: Double?,
        hrBaseline: Double?,
        hrvBaseline: Double?,
        sampledMinutes: Double,
        baselineNightCount: Int
    ) -> StressScore? {
        // Needs at least one live signal today — a score built from zero
        // samples would just be restating the baseline back as "calm".
        guard avgHeartRate != nil || avgHRV != nil else { return nil }

        var points: [Double] = []

        // HR component: higher than baseline reads as more stressed.
        if let hr = avgHeartRate, let base = hrBaseline, base > 0 {
            let deviation = (hr - base) / base
            points.append(clamp01(0.5 + deviation / 0.20))
        }

        // HRV component: inverted — lower than baseline reads as more
        // stressed. HRV is the more sensitive of the two, so it gets the
        // narrower band.
        if let hrv = avgHRV, let base = hrvBaseline, base > 0 {
            let deviation = (hrv - base) / base
            points.append(clamp01(0.5 - deviation / 0.35))
        }

        // With neither baseline available yet, fall back to a flat middle
        // reading rather than nothing — "calm" by default, revised the
        // moment history exists.
        let normalized = points.isEmpty ? 0.5 : points.reduce(0, +) / Double(points.count)
        let value = Int((normalized * 100).rounded())

        let band: Band = switch value {
        case ..<40: .calm
        case 40..<70: .elevated
        default: .high
        }

        return StressScore(
            percent: value,
            band: band,
            sampledMinutes: sampledMinutes,
            avgHeartRate: avgHeartRate,
            avgHRV: avgHRV,
            isEstimate: baselineNightCount < minimumBaselineNights
        )
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}
