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

    /// The hour a nap started, on a 24-hour clock.
    ///
    /// **The evening band is the point of this table.** These bands used to
    /// stop at 18:00, on the reasoning that "a nap after 18:00 is not a nap".
    /// That is a claim about the clock standing in for a claim about the
    /// episode, and it fails in both directions. A twenty-minute doze at 19:30
    /// is a nap by any reading, and it is the nap most likely to matter to
    /// that night's sleep onset — which is the one thing this curve measures.
    /// Meanwhile a night-shift worker's main sleep can begin at 08:00 and
    /// would sail straight through "before noon" if the hour were what decided
    /// eligibility.
    ///
    /// It is not. Eligibility is the episode architecture's: `classify`
    /// labels an episode `.nap` or `.secondarySleep` from its duration and
    /// the person's schedule, `preferredMainSleep` picks the main block by
    /// length rather than by hour, and only episodes already typed `.nap`
    /// reach this curve. These bands only say *when*, and so the last one is
    /// open: a nap Zoon has classified never falls out of its own curve for
    /// happening at an inconvenient hour.
    ///
    /// Naps do not cross the 18:00 seam the circular helpers exist for — a
    /// nap band boundary is a boundary, not a discontinuity — so a plain hour
    /// is still what these take.
    static let napTiming = Dose(
        behaviour: "Nap timing",
        unit: "h",
        bands: [
            Band(label: "Morning", lower: 0, upper: 12),
            Band(label: "Early afternoon", lower: 12, upper: 15),
            Band(label: "Late afternoon", lower: 15, upper: 18),
            Band(label: "Evening", lower: 18, upper: nil)
        ]
    )

    /// §18. The hour the last caffeine of the day was drunk.
    ///
    /// **This became buildable when §9 landed, and only for the nights it
    /// covers.** Zoon used to record how much late caffeine there was and not
    /// when any of it happened -- that gap is why `unavailable` named this for
    /// so long. An observation now carries a confirmed clock time, so the
    /// bands below have something to sort on.
    ///
    /// They will be thin for a long while, and that is the honest state
    /// rather than a defect: only nights where somebody said a time and
    /// confirmed it appear here, and the `tooFew` verdict says so per band
    /// instead of averaging a handful of nights into a finding. The brief's
    /// own example is exactly this shape -- one band ruled out, one uncertain,
    /// one associated.
    static let caffeineTiming = Dose(
        behaviour: "Caffeine timing",
        unit: "h",
        bands: [
            Band(label: "Before 1 PM", lower: 0, upper: 13),
            Band(label: "1–4 PM", lower: 13, upper: 16),
            Band(label: "After 4 PM", lower: 16, upper: nil)
        ]
    )

    /// How many caffeinated drinks, as the person counted them.
    ///
    /// Their own unit, deliberately. Zoon does not convert a cup into
    /// milligrams: a "coffee" is a double espresso to one person and a mug of
    /// instant to another, and a conversion factor would put a fabricated
    /// precision on the one number here that somebody actually stated.
    ///
    /// No zero band. A night with no recorded count is a night with an
    /// unknown count -- see `BehaviorDetail` -- and is absent rather than
    /// sorted into "none", which would be a control arm built out of missing
    /// data.
    static let caffeineDose = Dose(
        behaviour: "Caffeine, how much",
        unit: "drinks",
        bands: [
            Band(label: "One", lower: 1, upper: 2),
            Band(label: "Two", lower: 2, upper: 3),
            Band(label: "Three or more", lower: 3, upper: nil)
        ]
    )

    /// How hard the session was, as the person described it.
    ///
    /// The other gap §9 closed. `workoutTiming` has always known how long
    /// before bed the last workout ended and never how hard it was, so an
    /// easy evening spin and a race sat in the same band. The scale is the
    /// three words `BehaviorDetail.intensityLabel` maps back to, because
    /// three words is the resolution somebody actually supplied.
    ///
    /// Not derived from heart rate or Load. Those are separate measurements
    /// with their own provenance, and mixing a measured strain into a curve
    /// labelled "what you said" would make neither readable.
    static let workoutLoad = Dose(
        behaviour: "Workout load",
        unit: "",
        bands: [
            Band(label: "Easy", lower: 0, upper: 0.34),
            Band(label: "Moderate", lower: 0.34, upper: 0.67),
            Band(label: "Hard", lower: 0.67, upper: nil)
        ]
    )

    /// Every dose Zoon ships, in one place.
    ///
    /// A list rather than seven separate statics referenced ad hoc, so a
    /// dimension added later is held to the same guards as the rest without
    /// anybody remembering to add it to a test. `napTiming` shipped with a
    /// closed top band and silently dropped every evening nap precisely
    /// because the check that would have caught it enumerated the doses by
    /// hand and that one was on the list -- the guard was there, the coverage
    /// was the thing that slipped.
    static let shipped: [Dose] = [
        lateCaffeine, caffeineTiming, caffeineDose,
        workoutTiming, workoutLoad,
        napDuration, napTiming
    ]

    /// A dimension the brief asks for that cannot be built from what is
    /// stored. A named type rather than a tuple because the view iterates
    /// these, and Swift has no key paths into a tuple to identify them by.
    struct Gap: Hashable, Sendable, Identifiable {
        let behaviour: String
        let reason: String
        var id: String { behaviour }
    }

    /// Named so the gap is visible in the app rather than only in a document.
    /// Two of the three gaps named here closed when observations started
    /// carrying a time and an intensity. They are curves now -- thin ones,
    /// which the `tooFew` verdict reports honestly -- and listing them as
    /// impossible would be as wrong as the silence they were added to
    /// replace. What remains is genuinely not derivable from what is stored.
    static let unavailable: [Gap] = [
        Gap(
            behaviour: "Light timing",
            reason: "Daylight is stored as a total for the day, so Zoon cannot tell morning light from evening light. A logged daylight observation records that you went out, not for how long."
        )
    ]
}
