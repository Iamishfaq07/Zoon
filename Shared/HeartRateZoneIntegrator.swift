import Foundation

/// Where a day's heart-rate zone boundaries came from.
///
/// Separate from sample coverage on purpose. A day can have perfect
/// second-by-second heart rate and still be an estimate, because the zones
/// those beats are sorted into rest on a guessed maximum. Coverage answers
/// "did we watch?"; this answers "do we know what we were watching for?".
/// **Why there is no `appleWorkoutZones` case.** The obvious fifth source
/// would be Apple's own workout zones. There is still no public API for them:
/// `HKWorkoutZone`, `HKWorkoutZonesSample` and `HKWorkoutZonesType` exist in
/// `HealthKit.tbd` -- the linker stub listing every class in the shipped
/// binary -- alongside plainly private ones like `_HKDaemonPreferences` and
/// `_HKEntitlements`, and are declared in no public header, no
/// `.swiftinterface` and no `.apinotes`, on iOS or watchOS.
///
/// Re-verified by the `sdk-probe` CI job rather than recalled. Its output on
/// iPhoneOS 26.5 and WatchOS 26.5, the SDKs the runner actually has:
///
/// ```text
/// -- symbols named *Zone* in public headers, .swiftinterface and .apinotes --
/// HKMetadataKeyTimeZone
/// -- for contrast, the same search over the linker stub --
/// _HKWorkoutZonesTypeIdentifierCyclingPower
/// _HKWorkoutZonesTypeIdentifierHeartRate
/// HKWorkoutZone
/// HKWorkoutZonesSample
/// HKWorkoutZonesType
/// ```
///
/// The only public symbol matching "Zone" is a timezone metadata key. The
/// zone classes are in the binary and reachable from nothing a third-party
/// app may compile against. (The brief asked for this to be checked against
/// an Xcode 27 SDK; the installed toolchain is Xcode 26.6, so that is what
/// was checked and what this states.)
///
/// Reading them would mean declaring private interfaces by hand. A case that
/// can never be produced is worse than no case, so this documents the gap
/// instead of pretending to fill it. Zoon16 asked again against current
/// Apple platforms; this sandbox still has no Xcode 27 SDK to compile a
/// public workout-zone API against, so the gap stays documented rather than
/// faked. If Apple publishes the API, it belongs at the top of
/// `isPersonalized` -- measured zones beat every estimate here.
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

/// Where the resting heart rate under a Load score came from.
///
/// This is the other half of the zone model and it was invisible. Zones are
/// Karvonen — `(bpm − resting) / (max − resting)` — so a guessed resting rate
/// shifts every boundary just as surely as a guessed maximum does, and Zoon
/// would silently substitute a flat 60 bpm when no measurement existed. A day
/// scored that way is a population estimate in both terms, and nothing said
/// so.
///
/// Direction of the error is worth stating plainly: someone whose true
/// resting rate is 48 scored against 60 has every sample's reserve fraction
/// understated, so their Load is too *low*, not too high. That is the safer
/// direction — the same one `maxInterpolationWindow` chooses — which is why
/// the fallback stays rather than being replaced with a different model on a
/// guess. What changes here is that it can no longer pass itself off as
/// personal.
enum RestingHRProvenance: String, Codable, Hashable, Sendable, CaseIterable {
    /// A resting heart rate Health measured for this day.
    case measuredDailyRestingHR
    /// A measured resting heart rate from an earlier day.
    case historicalPersonalRestingHR
    /// The low point of the sleep window — this person's own physiology, but
    /// not the same quantity Health calls resting heart rate.
    case sleepDerivedPersonalEstimate
    /// A flat constant. Not this person at all.
    case genericFallback

    /// Whether the number describes this person.
    var isPersonalized: Bool { self != .genericFallback }

    var label: String {
        switch self {
        case .measuredDailyRestingHR: "Measured today"
        case .historicalPersonalRestingHR: "Your recent resting rate"
        case .sleepDerivedPersonalEstimate: "Estimated from your sleep"
        case .genericFallback: "Generic default"
        }
    }

    /// What this source is worth on its own.
    var confidence: MetricConfidence {
        switch self {
        case .measuredDailyRestingHR: .high
        case .historicalPersonalRestingHR: .high
        case .sleepDerivedPersonalEstimate: .moderate
        case .genericFallback: .low
        }
    }
}

/// A resting heart rate and where it came from, so the two cannot be
/// separated by accident.
struct RestingHeartRateInput: Hashable, Sendable {
    let bpm: Double
    let provenance: RestingHRProvenance
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

    /// Age-predicted maximum heart rate (Tanaka), with where it came from.
    ///
    /// Closer to observed values across adult ages than the older 220−age
    /// rule, which systematically underestimates for over-40s. Still a
    /// population formula applied to one person: two people the same age can
    /// differ by 20 bpm at maximum, which moves every zone boundary below and
    /// the Load score with them. The provenance travels with the number so a
    /// surface can say that rather than presenting a guessed ceiling as a
    /// measured one.
    ///
    /// `.observedPersonalized` and `.userConfigured` are not produced here:
    /// nothing in the app records a maximum someone actually hit, and there is
    /// no setting for one. Those cases exist so that when either arrives it
    /// has a name, and so "is this personal" has a single answer today rather
    /// than being rewritten then.
    ///
    /// Lives beside the zones rather than in the app target because the zones
    /// are meaningless without it -- and because the test target compiles
    /// `Shared` directly.
    static func maximumHeartRate(age: Int?) -> (bpm: Double, provenance: HRZoneProvenance) {
        guard let age, age > 0, age < 120 else { return (190, .genericFallback) }
        return (208 - 0.7 * Double(age), .ageEstimated)
    }

    /// The generic resting heart rate, used only when nothing personal exists.
    static let genericRestingHeartRate = 60.0

    /// Picks a resting heart rate and records which of four sources produced
    /// it.
    ///
    /// Order is most-recent-measurement-first, which is also a fix: the
    /// previous chain reached for the *previous* night's measured value ahead
    /// of the current night's, so a fresh reading lost to a day-old one. With
    /// provenance attached the distinction is no longer cosmetic —
    /// `.measuredDailyRestingHR` and `.historicalPersonalRestingHR` have to
    /// mean what they say.
    ///
    /// Values outside 25–120 bpm are rejected at every tier rather than
    /// carried into the reserve denominator: a corrupt sample there does not
    /// produce a slightly wrong Load, it produces a nonsensical one.
    static func restingHeartRate(
        measuredToday: Double?,
        measuredEarlier: Double?,
        sleepDerived: Double?
    ) -> RestingHeartRateInput {
        func plausible(_ value: Double?) -> Double? {
            guard let value, value >= 25, value <= 120 else { return nil }
            return value
        }
        if let value = plausible(measuredToday) {
            return RestingHeartRateInput(bpm: value, provenance: .measuredDailyRestingHR)
        }
        if let value = plausible(measuredEarlier) {
            return RestingHeartRateInput(bpm: value, provenance: .historicalPersonalRestingHR)
        }
        if let value = plausible(sleepDerived) {
            return RestingHeartRateInput(bpm: value, provenance: .sleepDerivedPersonalEstimate)
        }
        return RestingHeartRateInput(bpm: genericRestingHeartRate, provenance: .genericFallback)
    }

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

            // Coverage counts the observation whatever the intensity. The
            // lowest zone starts at 50% of heart-rate reserve, so an entire
            // restful day sits below every zone -- and attributing coverage
            // only when a zone matched made such a day look unobserved,
            // which pushed the caller onto its "thin coverage" estimate
            // despite complete sampling. "Did we watch?" and "was it hard?"
            // are different questions.
            attributed += duration

            let hrr = (sample.bpm - restingHeartRate) / reserve
            guard let zone = StrainScore.Zone.allCases
                .filter({ hrr >= $0.lowerBoundHRR })
                .max(by: { $0.lowerBoundHRR < $1.lowerBoundHRR })
            else { continue }

            zones[zone, default: 0] += duration / 60
        }

        return Result(
            zoneMinutes: zones,
            coverage: min(1, attributed / interval.duration),
            attributedSeconds: attributed
        )
    }
}
