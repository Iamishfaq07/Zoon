import Foundation

/// Where a day's heart-rate zone boundaries came from.
///
/// Separate from sample coverage on purpose. A day can have perfect
/// second-by-second heart rate and still be an estimate, because the zones
/// those beats are sorted into rest on a guessed maximum. Coverage answers
/// "did we watch?"; this answers "do we know what we were watching for?".
enum HRZoneProvenance: String, Codable, Hashable, Sendable, CaseIterable {
    /// Boundaries the user set themselves.
    case userConfigured
    /// Derived from the user's own observed maximum.
    case observedPersonalized
    /// 208 − 0.7 × age. A population formula applied to one person.
    case ageEstimated
    /// No age either: a flat constant.
    case genericFallback

    /// Only the first two describe this person rather than a population.
    var isPersonalized: Bool {
        self == .userConfigured || self == .observedPersonalized
    }

    var label: String {
        switch self {
        case .userConfigured: "Your settings"
        case .observedPersonalized: "Your observed max"
        case .ageEstimated: "Age-estimated"
        case .genericFallback: "Generic default"
        }
    }
}

/// Turns heart-rate samples into zone minutes by integrating over time.
///
/// **The bug this replaces.** Zones were built from 10-minute statistics
/// bins: each bin's mean was classified and the *whole bin* was credited to
/// that zone. A single passive sample of 142 bpm — one reading, taken while
/// climbing a flight of stairs — became ten minutes of vigorous exercise.
/// Sparse sampling therefore inflated time-in-zone, cardiovascular load and
/// the Load score itself, and inflated them most for the users with the
/// oldest watches and the least data.
///
/// **What it does instead.** Each sample is credited only the time until the
/// next one, capped: a reading tells us about the moments around it, not
/// about a gap it happens to precede. The cap is what stops one measurement
/// from colouring an unobserved hour.
///
/// Consequence worth stating: quiet stretches are now *under*-counted, since
/// a resting sample every five minutes credits only the capped window. That
/// is the right direction of error for a load model — low zones carry almost
/// no weight, and the failure this fixes was overstating hard minutes.
enum HeartRateZoneIntegrator {

    struct Sample {
        let date: Date
        let bpm: Double

        init(date: Date, bpm: Double) {
            self.date = date
            self.bpm = bpm
        }
    }

    struct Result {
        let zoneMinutes: [StrainScore.Zone: Double]
        /// Observed fraction of the interval, 0–1.
        let coverage: Double
        /// Seconds actually attributed, before conversion to minutes.
        let attributedSeconds: Double
    }

    /// How long one sample may speak for.
    ///
    /// An Apple Watch samples roughly every five minutes at rest and every
    /// few seconds in a workout, so 150 seconds credits dense workout
    /// sampling in full while halving what a lone passive reading can claim.
    /// Chosen to be shorter than the resting sampling interval deliberately:
    /// the gap between two resting samples is genuinely unobserved, and this
    /// model does not pretend otherwise.
    static let maxInterpolationWindow: TimeInterval = 150

    /// - Parameters:
    ///   - samples: any order; sorted internally.
    ///   - restingHeartRate: used for the heart-rate reserve denominator.
    ///   - maxHeartRate: upper bound of the reserve.
    ///   - interval: the window being scored; bounds the final sample.
    static func integrate(
        samples: [Sample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        interval: DateInterval,
        cap: TimeInterval = maxInterpolationWindow
    ) -> Result {
        guard !samples.isEmpty, interval.duration > 0 else {
            return Result(zoneMinutes: [:], coverage: 0, attributedSeconds: 0)
        }

        let sorted = samples
            .filter { interval.contains($0.date) || $0.date == interval.end }
            .sorted { $0.date < $1.date }
        guard !sorted.isEmpty else {
            return Result(zoneMinutes: [:], coverage: 0, attributedSeconds: 0)
        }

        // Karvonen: zones on heart-rate reserve, not raw percentage of max,
        // so two people with the same max and different resting rates are not
        // scored as working equally hard at the same bpm.
        let reserve = max(20, maxHeartRate - restingHeartRate)

        var zones: [StrainScore.Zone: Double] = [:]
        var attributed: TimeInterval = 0

        for (index, sample) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].date : interval.end
            let gap = next.timeIntervalSince(sample.date)
            guard gap > 0 else { continue }
            let duration = min(gap, cap)

            let hrr = (sample.bpm - restingHeartRate) / reserve
            guard let zone = StrainScore.Zone.allCases
                .filter({ hrr >= $0.lowerBoundHRR })
                .max(by: { $0.lowerBoundHRR < $1.lowerBoundHRR })
            else { continue }

            zones[zone, default: 0] += duration / 60
            attributed += duration
        }

        return Result(
            zoneMinutes: zones,
            coverage: min(1, attributed / interval.duration),
            attributedSeconds: attributed
        )
    }
}
