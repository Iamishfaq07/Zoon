import Foundation

/// Slow-moving personal baselines over 30 / 90 / 180 / 365 days.
///
/// Not biological age, not cardiovascular age, not a comparison to a
/// population curve. A signal is described against *this person's* own
/// window: "resting HR has been about 4 bpm below your 90-day baseline
/// for 18 days." Missing values stay missing.
enum LongTermResilience {

    enum Window: Int, Hashable, Sendable, CaseIterable {
        case days30 = 30
        case days90 = 90
        case days180 = 180
        case days365 = 365

        var label: String {
            switch self {
            case .days30: "30 days"
            case .days90: "90 days"
            case .days180: "6 months"
            case .days365: "1 year"
            }
        }
    }

    struct Point: Hashable, Sendable {
        let date: Date
        let value: Double
    }

    struct Signal: Hashable, Sendable {
        let name: String
        let window: Window
        let current: Double?
        let baseline: Double?
        let delta: Double?
        let daysHeld: Int?
        let unit: String
        let sentence: String
        let confidence: MetricConfidence
        /// True when the recent run is on the favourable side of baseline.
        let favourable: Bool?
    }

    static let minimumPoints = 14

    static func measure(
        name: String,
        points: [Point],
        window: Window,
        now: Date = .now,
        calendar: Calendar = .current,
        unit: String,
        lowerIsFavourable: Bool,
        format: (Double) -> String = { String(format: "%.0f", $0) }
    ) -> Signal {
        let cutoff = calendar.date(byAdding: .day, value: -window.rawValue, to: now) ?? now
        let inWindow = points.filter { $0.date >= cutoff && $0.date <= now }.sorted { $0.date < $1.date }

        guard inWindow.count >= minimumPoints, let current = inWindow.last?.value else {
            return Signal(
                name: name,
                window: window,
                current: inWindow.last?.value,
                baseline: nil,
                delta: nil,
                daysHeld: nil,
                unit: unit,
                sentence: "Not enough \(name) history in the last \(window.label) to describe a baseline.",
                confidence: .insufficient,
                favourable: nil
            )
        }

        let values = inWindow.map(\.value)
        guard let baseline = Statistics.median(values) else {
            return Signal(
                name: name,
                window: window,
                current: current,
                baseline: nil,
                delta: nil,
                daysHeld: nil,
                unit: unit,
                sentence: "Not enough \(name) history in the last \(window.label) to describe a baseline.",
                confidence: .insufficient,
                favourable: nil
            )
        }

        let delta = current - baseline
        let tolerance = max(abs(baseline) * 0.03, 1)
        let favourable: Bool? = abs(delta) < tolerance
            ? nil
            : (lowerIsFavourable ? delta < 0 : delta > 0)

        let daysHeld = runLength(inWindow, baseline: baseline, tolerance: tolerance, below: lowerIsFavourable)

        let confidence: MetricConfidence = inWindow.count >= 60 ? .high : (inWindow.count >= 30 ? .moderate : .low)

        let sentence: String
        if abs(delta) < tolerance {
            sentence = "Your \(name) is close to your \(window.label) baseline of \(format(baseline)) \(unit)."
        } else {
            let side = delta < 0 ? "below" : "above"
            let held = daysHeld.map { " for \($0) days" } ?? ""
            sentence = "Your \(name) has been about \(format(abs(delta))) \(unit) \(side) your \(window.label) baseline\(held)."
        }

        return Signal(
            name: name,
            window: window,
            current: current,
            baseline: baseline,
            delta: delta,
            daysHeld: daysHeld,
            unit: unit,
            sentence: sentence,
            confidence: confidence,
            favourable: favourable
        )
    }

    /// Consecutive trailing days on the same side of the band.
    private static func runLength(
        _ points: [Point],
        baseline: Double,
        tolerance: Double,
        below: Bool
    ) -> Int? {
        guard points.count >= 3 else { return nil }
        var count = 0
        for point in points.reversed() {
            let delta = point.value - baseline
            let onSide = below ? delta < -tolerance : delta > tolerance
            if onSide {
                count += 1
            } else {
                break
            }
        }
        return count >= 3 ? count : nil
    }
}
