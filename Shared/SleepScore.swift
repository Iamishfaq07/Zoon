import Foundation

/// A 0–100 nightly score, computed identically in the app and the widget.
///
/// This lives in `Shared/` precisely so the number on the home screen and the
/// number on the lock screen can never disagree — a class of bug that is
/// invisible in testing and obvious to the user.
///
/// The weighting is opinionated and intentionally simple. It is *not* a clinical
/// instrument; it is a legible summary the user can learn to read. Each component
/// scores 0–1, then contributes its weight.
struct SleepScore: Codable, Hashable, Sendable {

    let value: Int              // 0...100
    let components: [Component]

    struct Component: Codable, Hashable, Sendable, Identifiable {
        let label: String
        /// 0...1 — how well this dimension did.
        let normalized: Double
        /// Share of the total score.
        let weight: Double

        var id: String { label }
        var points: Double { normalized * weight * 100 }
    }

    // Weights sum to 1.0.
    private static let durationWeight = 0.40
    private static let efficiencyWeight = 0.25
    private static let deepWeight = 0.15
    private static let remWeight = 0.10
    private static let continuityWeight = 0.10

    /// - Parameter goalMinutes: the user's nightly sleep goal. Duration is scored
    ///   against the user's own target, not a population average — someone whose
    ///   goal is 7h shouldn't be marked down for not hitting 8.
    static func compute(for features: SleepNightFeatures, goalMinutes: Double) -> SleepScore {
        var components: [Component] = []

        // Duration: linear ramp to goal, full credit at or above it.
        let duration = clamp01(features.timeAsleepMinutes / max(goalMinutes, 1))
        components.append(.init(label: "Duration", normalized: duration, weight: durationWeight))

        // Efficiency: 85% is the conventional "good" threshold; scale 60→95.
        let efficiency = clamp01((features.sleepEfficiencyPercent - 60) / 35)
        components.append(.init(label: "Efficiency", normalized: efficiency, weight: efficiencyWeight))

        if features.hasStageBreakdown {
            // Deep: ~13–23% of total sleep is typical adult range. Full credit at 18%.
            let deepPct = features.deepPercentOfAsleep ?? 0
            components.append(.init(label: "Deep", normalized: clamp01(deepPct / 18), weight: deepWeight))

            // REM: ~20–25% typical. Full credit at 22%.
            let remPct = features.remPercentOfAsleep ?? 0
            components.append(.init(label: "REM", normalized: clamp01(remPct / 22), weight: remWeight))
        } else {
            // No staging from this source. Rather than zeroing those components —
            // which would permanently cap an iPhone-only user around 75 — we
            // credit them at the efficiency score, so the score stays comparable
            // across sources. The UI notes that staging is unavailable.
            components.append(.init(label: "Deep", normalized: efficiency, weight: deepWeight))
            components.append(.init(label: "REM", normalized: efficiency, weight: remWeight))
        }

        // Continuity: 0 wakes = 1.0, decaying to 0 at 8 wakes.
        let continuity = clamp01(1 - Double(features.wakeCount) / 8)
        components.append(.init(label: "Continuity", normalized: continuity, weight: continuityWeight))

        let total = components.reduce(0) { $0 + $1.points }
        return SleepScore(value: Int(total.rounded()), components: components)
    }

    private static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}

extension SleepScore {

    enum Band: String, Sendable {
        case poor, fair, good, excellent

        var label: String {
            switch self {
            case .poor: "Poor"
            case .fair: "Fair"
            case .good: "Good"
            case .excellent: "Excellent"
            }
        }

        /// Single source of truth for the score thresholds, callable from a
        /// bare `Int` -- the widget/watch targets only ever have
        /// `SleepSnapshot.score`, not a full `SleepScore`, and re-deriving
        /// these cutoffs independently (as `SleepScoreWidget.scoreColor`
        /// once did) is exactly how the two silently drift apart.
        static func forValue(_ value: Int) -> Band {
            switch value {
            case ..<50: .poor
            case 50..<70: .fair
            case 70..<85: .good
            default: .excellent
            }
        }
    }

    var band: Band { Band.forValue(value) }
}
