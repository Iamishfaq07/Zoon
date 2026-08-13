import Foundation

/// Cardiovascular age estimated from overnight heart metrics.
///
/// Oura's Cardiovascular Age, reimplemented. The appeal is that it converts two
/// numbers most people can't interpret — resting heart rate and HRV — into one
/// they can: *your heart looks like a 34-year-old's*. That translation is the
/// entire product.
///
/// ## How it works
///
/// Resting HR and HRV both track age on a population level: HRV falls roughly
/// log-linearly across adulthood, resting HR drifts up slowly. Comparing your
/// values against the expected curve for your age gives a deviation, which is
/// converted back into years.
///
/// ## What it is not
///
/// A clinical measure of anything. It's a legible restatement of two metrics
/// against population averages, and someone unusually fit or unusually
/// stressed will find it flattering or alarming beyond what the underlying
/// signals support. The UI says so, and the result is deliberately clamped to
/// ±15 years so it can never produce an absurd claim.
struct CardiovascularAge: Codable, Hashable, Sendable {

    /// Estimated cardiovascular age in years.
    let estimatedAge: Double
    /// The user's actual age.
    let chronologicalAge: Int
    /// Nights the estimate is drawn from.
    let nightCount: Int

    let averageHRV: Double?
    let averageRestingHR: Double?

    /// Positive = older than your years.
    var deltaYears: Double { estimatedAge - Double(chronologicalAge) }

    /// Nights of history required. Fewer than this and a bad week reads as
    /// a decade of ageing.
    static let minimumNights = 14

    /// Samples a single metric (HRV or RHR) needs before its mean is worth
    /// feeding into the blend -- same reasoning as
    /// `RecoveryBaseline.minimumSamplesPerMetric`. A 30-night window with
    /// only one or two HRV readings (the watch rarely worn, say) would
    /// otherwise blend that one reading into the estimate carrying the same
    /// weight as a properly-sampled signal.
    private static let minimumSamplesPerMetric = 3

    /// Maximum deviation the model will claim, in years.
    private static let maxDelta = 15.0

    // MARK: - Population reference curves
    //
    // Approximations of published adult population means. They are reference
    // points for a consumer comparison, not clinical norms.

    /// Expected overnight SDNN (ms) at a given age.
    ///
    /// HRV declines steeply through the twenties and thirties and flattens
    /// later, so this is exponential rather than linear — a straight line would
    /// badly misjudge both ends of the range.
    static func expectedHRV(age: Double) -> Double {
        // ~68ms at 25, ~48ms at 45, ~35ms at 65.
        80 * exp(-0.0165 * age)
    }

    /// Expected resting heart rate (bpm) at a given age. Nearly flat, drifting
    /// up slightly across adulthood.
    static func expectedRestingHR(age: Double) -> Double {
        58 + 0.06 * age
    }

    // MARK: - Computation

    static func compute(nights: [SleepNightFeatures], chronologicalAge: Int?) -> CardiovascularAge? {
        guard let chronologicalAge, chronologicalAge >= 18, chronologicalAge <= 99 else { return nil }

        let window = Array(nights.suffix(30))
        let hrvValues = window.compactMap(\.avgHRV)
        // True RHR (see SleepNightFeatures.restingHeartRate) wherever a night
        // has it; the sleep-window low is a fallback only for nights recorded
        // before that field existed, not a preferred source.
        let rhrValues = window.compactMap { $0.restingHeartRate ?? $0.minHeartRate }

        guard window.count >= minimumNights else { return nil }

        // Each metric must clear its own sample-count floor, not just be
        // non-empty -- see `minimumSamplesPerMetric`.
        let hrv = hrvValues.count >= minimumSamplesPerMetric ? mean(hrvValues) : nil
        let rhr = rhrValues.count >= minimumSamplesPerMetric ? mean(rhrValues) : nil
        guard hrv != nil || rhr != nil else { return nil }

        let age = Double(chronologicalAge)

        // Each signal produces its own age estimate; they're then blended.
        var estimates: [(years: Double, weight: Double)] = []

        if let hrv {
            // Invert the exponential: what age has this HRV as its mean?
            // hrv = 80·e^(−0.0165·a)  →  a = ln(80/hrv) / 0.0165
            let implied = log(80 / max(hrv, 5)) / 0.0165
            estimates.append((implied, 0.65))
        }

        if let rhr {
            // Invert the linear curve, then damp heavily: the slope is so
            // shallow that a few bpm would otherwise imply decades. The damping
            // factor deliberately pulls the estimate toward chronological age.
            let implied = age + (rhr - expectedRestingHR(age: age)) * 1.4
            estimates.append((implied, 0.35))
        }

        let totalWeight = estimates.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let blended = estimates.reduce(0.0) { $0 + $1.years * $1.weight } / totalWeight
        let clamped = max(age - maxDelta, min(age + maxDelta, blended))

        return CardiovascularAge(
            estimatedAge: clamped,
            chronologicalAge: chronologicalAge,
            nightCount: window.count,
            averageHRV: hrv,
            averageRestingHR: rhr
        )
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Presentation

extension CardiovascularAge {

    enum Standing: String, Sendable {
        case younger, aligned, older

        var label: String {
            switch self {
            case .younger: "Younger than your years"
            case .aligned: "In line with your age"
            case .older: "Older than your years"
            }
        }
    }

    /// Within five years counts as aligned — the same tolerance Oura uses, and
    /// about the width of the underlying noise.
    var standing: Standing {
        switch deltaYears {
        case ..<(-5): .younger
        case -5...5: .aligned
        default: .older
        }
    }

    var displayAge: String { "\(Int(estimatedAge.rounded()))" }

    var summary: String {
        let years = abs(deltaYears).rounded()
        switch standing {
        case .aligned:
            return "Your overnight heart metrics sit close to the average for \(chronologicalAge)."
        case .younger:
            return "Your overnight heart metrics look like someone about \(Int(years)) years younger. That usually reflects aerobic fitness."
        case .older:
            return "Your overnight heart metrics look about \(Int(years)) years older than your age. Often training load, stress, alcohol, or sleep debt rather than anything structural."
        }
    }

    static let disclaimer = """
        A restatement of your resting heart rate and HRV against population \
        averages — not a clinical assessment, and not a measurement of anything \
        in your arteries.
        """
}
