import Foundation

/// Dose-response and time-response bands for the behaviours that carry a real
/// quantity, and a refusal for the ones that do not.
///
/// **Why this is not built for every behaviour.** `BehaviorObservationRecord`
/// stores yes / no / unknown. There is no quantity, no unit and no event time
/// on it, so "did you drink alcohol" cannot become "how much, and when"
/// without somebody inventing the dose. Four dimensions in the app *do* carry
/// a real number, and those are the four this ships:
///
/// - late caffeine, in milligrams (`SleepNightFeatures.lateCaffeineMg`),
/// - the last workout's timing, in hours before bed
///   (`lastWorkoutHoursBeforeBed`),
/// - nap duration, in minutes (`NapStore` holds real start and end times),
/// - nap timing, as the hour it started.
///
/// Anything else would be a curve drawn through a yes and a no. §M records the
/// storage change that would unblock the rest.
///
/// **Bands, not a fitted curve.** A smooth curve through a few dozen nights
/// implies a resolution nobody has, and the shape it draws between two sparse
/// regions is the model talking rather than the person's data. Bands say only
/// what each range of doses looked like, and a band without enough nights
/// behind it says so instead of being interpolated across.
///
/// **Every band is measured against the first band that qualifies**, and
/// the interval is an unpaired bootstrap, because the nights at 200 mg are
/// different nights from the ones at 50 mg and there is no pairing between
/// them. `Statistics.unpairedBootstrapCI` exists for exactly this; using the
/// paired one would report an interval far narrower than the data supports.
///
/// **"Little difference" and "uncertain" are different answers**, and the
/// brief's own example draws that line. A band whose interval excludes zero is
/// an association. A band whose interval sits entirely inside the practical
/// threshold is a band where a meaningful effect can be ruled out — little
/// observed difference. A band whose interval spans both is simply uncertain,
/// and saying "no effect" there would be claiming a null nobody established.
///
/// Association wording throughout. Nothing here implies cause.
enum SensitivityCurve {

    /// Nights a band needs before it is reported as anything but uncertain.
    /// Five is the floor the bootstrap needs to be worth running at all; the
    /// interval it produces from five is wide, which is the honest outcome
    /// rather than a reason to hide the band.
    static let minimumNightsPerBand = 5

    /// Bands that must qualify before a curve is published. One band is not a
    /// curve — it is a single group with nothing to compare against.
    static let minimumQualifyingBands = 2

    /// What is being varied.
    struct Dose: Hashable, Sendable {
        let behaviour: String
        let unit: String
        /// Bands in the order they should be read, with the comparison band
        /// first. That is usually ascending dose, but `workoutTiming` runs the
        /// other way on purpose: the control there is the workout furthest
        /// from bed, not the one closest to it.
        let bands: [Band]
    }

    struct Band: Hashable, Sendable {
        let label: String
        /// Inclusive.
        let lower: Double
        /// Exclusive. `nil` is an open top band.
        let upper: Double?

        func contains(_ value: Double) -> Bool {
            guard value >= lower else { return false }
            guard let upper else { return true }
            return value < upper
        }
    }

    /// The sleep measure a curve is read against.
    struct Outcome: Hashable, Sendable {
        let noun: String
        let unit: String
        /// A difference smaller than this is not worth a person's attention
        /// whatever the statistics say, and is what "little observed
        /// difference" is measured against.
        let practicalThreshold: Double
        /// What to call a positive difference, and a negative one.
        let higherLabel: String
        let lowerLabel: String

        static let sleepOnset = Outcome(
            noun: "time to fall asleep",
            unit: "min",
            practicalThreshold: 10,
            higherLabel: "later sleep onset",
            lowerLabel: "earlier sleep onset"
        )

        static let asleepMinutes = Outcome(
            noun: "sleep duration",
            unit: "min",
            practicalThreshold: 20,
            higherLabel: "longer sleep",
            lowerLabel: "shorter sleep"
        )

        static let wakeCount = Outcome(
            noun: "awakenings",
            unit: "",
            practicalThreshold: 1,
            higherLabel: "more awakenings",
            lowerLabel: "fewer awakenings"
        )
    }

    enum Verdict: Hashable, Sendable {
        /// Not enough nights in this band to say anything.
        case tooFew
        /// The band the others are measured against.
        case reference
        /// Interval spans zero and is narrow enough to rule out a meaningful
        /// difference.
        case littleDifference
        /// Interval spans zero and is too wide to rule anything out.
        case uncertain
        /// Interval excludes zero.
        case associated(higher: Bool)
    }

    struct Reading: Hashable, Sendable, Identifiable {
        let band: Band
        let nights: Int
        /// Median outcome inside this band, when there were enough nights.
        let median: Double?
        /// Median difference against the reference band.
        let difference: Double?
        let intervalLower: Double?
        let intervalUpper: Double?
        let verdict: Verdict

        var id: String { band.label }

        /// The brief's display shape: a band label and one line under it.
        func sentence(outcome: Outcome) -> String {
            switch verdict {
            case .tooFew:
                return "not enough nights yet"
            case .reference:
                return "your comparison band"
            case .littleDifference:
                return "little observed difference"
            case .uncertain:
                return "uncertain"
            case .associated(let higher):
                let label = higher ? outcome.higherLabel : outcome.lowerLabel
                guard let difference else { return "\(label) associated" }
                let magnitude = Int(abs(difference).rounded())
                let unit = outcome.unit.isEmpty ? "" : " \(outcome.unit)"
                return "\(label) associated, about \(magnitude)\(unit)"
            }
        }

        /// The interval, for a caller that wants to show the band rather than
        /// only the verdict.
        func intervalText(outcome: Outcome) -> String? {
            guard let intervalLower, let intervalUpper else { return nil }
            let unit = outcome.unit.isEmpty ? "" : " \(outcome.unit)"
            return "95% interval \(Int(intervalLower.rounded())) to \(Int(intervalUpper.rounded()))\(unit)"
        }
    }

    struct Curve: Hashable, Sendable {
        let dose: Dose
        let outcome: Outcome
        let readings: [Reading]
        let totalNights: Int
        let caveat: String

        /// Bands that said something other than "not enough nights".
        var qualifyingBands: Int {
            readings.filter { $0.verdict != .tooFew }.count
        }

        /// Whether any band found an association at all. A curve of entirely
        /// uncertain bands is still worth showing — it says the question has
        /// been asked and not answered — but a caller may want to rank it
        /// below one that found something.
        var foundAnAssociation: Bool {
            readings.contains {
                if case .associated = $0.verdict { return true }
                return false
            }
        }
    }

    /// One night's dose and outcome.
    struct Observation: Hashable, Sendable {
        let dose: Double
        let outcome: Double

        init(dose: Double, outcome: Double) {
            self.dose = dose
            self.outcome = outcome
        }
    }

    /// Builds the curve, or refuses.
    ///
    /// Returns `nil` when fewer than `minimumQualifyingBands` bands cleared
    /// the night threshold — a single group is not a curve, and drawing it
    /// alone would invite the reader to compare it against nothing.
    static func build(
        dose: Dose,
        outcome: Outcome,
        observations: [Observation]
    ) -> Curve? {
        guard !dose.bands.isEmpty, !observations.isEmpty else { return nil }

        let grouped: [[Double]] = dose.bands.map { band in
            observations.filter { band.contains($0.dose) }.map(\.outcome)
        }

        // The reference is the first qualifying band, which is what the
        // brief's example does: "Before 1 PM" is the line everything after it
        // is read against. Each `Dose` declares its bands so that the band
        // which should serve as the control comes first.
        guard let referenceIndex = grouped.firstIndex(where: { $0.count >= minimumNightsPerBand })
        else { return nil }
        let reference = grouped[referenceIndex]

        var readings: [Reading] = []
        for (index, values) in grouped.enumerated() {
            let band = dose.bands[index]

            guard values.count >= minimumNightsPerBand, let median = Statistics.median(values) else {
                readings.append(
                    Reading(
                        band: band,
                        nights: values.count,
                        median: nil,
                        difference: nil,
                        intervalLower: nil,
                        intervalUpper: nil,
                        verdict: .tooFew
                    )
                )
                continue
            }

            if index == referenceIndex {
                readings.append(
                    Reading(
                        band: band,
                        nights: values.count,
                        median: median,
                        difference: nil,
                        intervalLower: nil,
                        intervalUpper: nil,
                        verdict: .reference
                    )
                )
                continue
            }

            let referenceMedian = Statistics.median(reference)
            let difference = referenceMedian.map { median - $0 }
            let interval = Statistics.unpairedBootstrapCI(reference: reference, group: values)

            readings.append(
                Reading(
                    band: band,
                    nights: values.count,
                    median: median,
                    difference: difference,
                    intervalLower: interval?.lower,
                    intervalUpper: interval?.upper,
                    verdict: verdict(interval: interval, outcome: outcome)
                )
            )
        }

        let qualifying = readings.filter { $0.verdict != .tooFew }.count
        guard qualifying >= minimumQualifyingBands else { return nil }

        return Curve(
            dose: dose,
            outcome: outcome,
            readings: readings,
            totalNights: observations.count,
            caveat: "Associations in your own nights, not causes. Each band is compared with "
                + "your lowest band, and the interval is how much the comparison could move."
        )
    }

    /// The three-way distinction the brief's example draws.
    static func verdict(
        interval: (lower: Double, upper: Double)?,
        outcome: Outcome
    ) -> Verdict {
        guard let interval else { return .uncertain }

        // Excludes zero: an association, in whichever direction.
        if interval.lower > 0 { return .associated(higher: true) }
        if interval.upper < 0 { return .associated(higher: false) }

        // Spans zero, and both ends sit inside what would matter to a person:
        // a meaningful difference has been ruled out, which is a stronger and
        // rarer statement than "uncertain".
        let threshold = outcome.practicalThreshold
        if interval.lower >= -threshold && interval.upper <= threshold {
            return .littleDifference
        }

        // Spans zero and could still be large either way.
        return .uncertain
    }

    // MARK: - The four doses that carry a real quantity

    /// Late caffeine, in milligrams. The bands are a rough cup scale rather
    /// than pharmacology: about one cup, about two, more.
    static let lateCaffeine = Dose(
        behaviour: "Late caffeine",
        unit: "mg",
        bands: [
            Band(label: "None", lower: 0, upper: 1),
            Band(label: "Up to 100 mg", lower: 1, upper: 100),
            Band(label: "100–200 mg", lower: 100, upper: 200),
            Band(label: "Over 200 mg", lower: 200, upper: nil)
        ]
    )

    /// How long before bed the last workout ended.
    static let workoutTiming = Dose(
        behaviour: "Last workout before bed",
        unit: "h",
        bands: [
            Band(label: "Over 6 hours before", lower: 6, upper: nil),
            Band(label: "3–6 hours before", lower: 3, upper: 6),
            Band(label: "Under 3 hours before", lower: 0, upper: 3)
        ]
    )

    static let napDuration = Dose(
        behaviour: "Nap length",
        unit: "min",
        bands: [
            Band(label: "No nap", lower: 0, upper: 1),
            Band(label: "Under 15 minutes", lower: 1, upper: 15),
            Band(label: "15–35 minutes", lower: 15, upper: 35),
            Band(label: "Over 35 minutes", lower: 35, upper: nil)
        ]
    )

    /// The hour a nap started, on a 24-hour clock. Naps do not cross the
    /// 18:00 seam the circular helpers exist for, so a plain hour is safe
    /// here — and a nap after 18:00 is not a nap.
    static let napTiming = Dose(
        behaviour: "Nap timing",
        unit: "h",
        bands: [
            Band(label: "Before noon", lower: 0, upper: 12),
            Band(label: "Noon–3 PM", lower: 12, upper: 15),
            Band(label: "After 3 PM", lower: 15, upper: 18)
        ]
    )

    /// A dimension the brief asks for that cannot be built from what is
    /// stored. A named type rather than a tuple because the view iterates
    /// these, and Swift has no key paths into a tuple to identify them by.
    struct Gap: Hashable, Sendable, Identifiable {
        let behaviour: String
        let reason: String
        var id: String { behaviour }
    }

    /// Named so the gap is visible in the app rather than only in a document.
    static let unavailable: [Gap] = [
        Gap(
            behaviour: "Caffeine timing",
            reason: "Zoon records how much late caffeine there was, not the clock time of each drink."
        ),
        Gap(
            behaviour: "Light timing",
            reason: "Daylight is stored as a total for the day, so Zoon cannot tell morning light from evening light."
        ),
        Gap(
            behaviour: "Workout load",
            reason: "Workout intensity is not carried on a night, only how long before bed the last one ended."
        )
    ]
}
