import Foundation

/// What tomorrow is likely to bring, conditioned on what tomorrow actually
/// looks like -- as an interval, never as a number.
///
/// ## What this adds over `UncertaintyForecast`
///
/// `UncertaintyForecast` reports where the last three weeks landed. It is
/// honest and it is deliberately not a forecast: its own doc comment says so,
/// because it conditions on nothing. Every Tuesday looks like every Saturday
/// to it, a night after a hard session looks like a rest day, and a night
/// carrying four hours of debt looks like a night carrying none.
///
/// This conditions. It describes tomorrow as a `Context` -- the handful of
/// things about it that are already known or intended -- finds the nights in
/// the person's own history that most resembled it, and reads the interval
/// off those nights instead of off all of them.
///
/// ## Why neighbours and not a model
///
/// The obvious implementation is a regression on the context features. With
/// six features and thirty nights it would fit the noise, and the failure
/// mode of an overfitted regression is not a wide interval -- it is a narrow,
/// confident, wrong one, which is the single worst thing this could produce.
///
/// Matched neighbours degrade the right way. When tomorrow resembles plenty
/// of past nights the interval tightens around them; when it resembles
/// nothing the neighbour set thins out and the whole thing falls back to the
/// unconditioned range and says so. There is no configuration in which it
/// invents precision it has not earned.
///
/// ## What it does not claim
///
/// The V9 spec lists inputs a forecast *can* use. This uses the six that live
/// on the stored night itself, so every one of them is available for any past
/// night and the whole thing is backtestable with no extra plumbing: weekday
/// shape, sleep debt, bedtime, late caffeine, the previous day's training,
/// and the previous night's sleep.
///
/// Daylight exposure, naps, the Body Clock's own phase estimate and the
/// current baseline era are **not** inputs here. They are not on the night
/// record, so including them would mean a forecast that can be made for
/// tomorrow and never scored against yesterday -- and an unscoreable forecast
/// is exactly what `CalibrationLedger` exists to stop this app from shipping.
enum ContextForecast {

    // MARK: - Describing a night

    /// The things about a night that are known before it happens.
    ///
    /// Every field is optional and a missing one is *skipped*, never imputed.
    /// Filling a missing sleep-debt with zero would silently assert the person
    /// was fully rested, which is a claim, not a default.
    struct Context: Hashable, Sendable {
        /// Matched as a category, not a number. Day-of-week as an integer
        /// makes Sunday and Monday maximally far apart, which is backwards --
        /// what actually separates nights is whether something is required of
        /// you the next morning.
        var isWeekend: Bool
        var sleepDebtMinutes: Double?
        /// Fractional hour, compared circularly -- 23:30 and 00:30 are an
        /// hour apart, not twenty-three.
        var bedtimeHour: Double?
        var lateCaffeineMg: Double?
        var exerciseMinutesPreviousDay: Double?
        var previousNightAsleepMinutes: Double?

        /// The context a stored night presents.
        ///
        /// - Parameter previous: the night before it, when there is one. The
        ///   only field that needs a neighbour in time, and nil on the first
        ///   night rather than defaulted.
        static func describing(
            _ night: SleepNightFeatures,
            previous: SleepNightFeatures? = nil,
            calendar: Calendar = .current
        ) -> Context {
            var calendar = calendar
            calendar.timeZone = night.timeZone
            let components = calendar.dateComponents([.hour, .minute], from: night.bedtime)
            let hour = components.hour.map { Double($0) + Double(components.minute ?? 0) / 60 }

            return Context(
                isWeekend: calendar.isDateInWeekend(night.date),
                sleepDebtMinutes: night.sleepDebtMinutes,
                bedtimeHour: hour,
                lateCaffeineMg: night.lateCaffeineMg,
                exerciseMinutesPreviousDay: night.exerciseMinutesPreviousDay,
                previousNightAsleepMinutes: previous?.timeAsleepMinutes
            )
        }
    }

    // MARK: - Similarity

    /// How far apart two contexts are, and on how many features that was
    /// actually decided.
    ///
    /// Each numeric feature is divided by a scale chosen so that "one unit of
    /// distance" means roughly the same amount of real difference across
    /// features -- two hours of bedtime shift and two hours of sleep debt are
    /// both about one unit. Without that, whichever feature happens to be
    /// measured in the largest numbers would dominate the match.
    struct Distance: Hashable, Sendable {
        let value: Double
        /// Numeric features both nights had. A match decided on one feature
        /// is not the same evidence as one decided on five, and confidence
        /// is graded on this as well as on the neighbour count.
        let comparedFeatures: Int
    }

    static let debtScale = 120.0
    static let bedtimeScale = 2.0
    static let caffeineScale = 100.0
    static let exerciseScale = 60.0
    static let previousSleepScale = 90.0
    /// Added when one night is a weekend and the other is not. Large enough
    /// that a same-shape night is preferred whenever one exists, small enough
    /// that a very close weekday can still beat a distant weekend one.
    static let weekendMismatchPenalty = 0.75

    /// How many numeric features a fully-described night can offer.
    static let numericFeatureCount = 5

    /// What ignorance costs.
    ///
    /// A night matched on two features and a night matched on five are not
    /// equally good matches even when both match perfectly, and without this
    /// term the sparser one is *mechanically better* -- see `Distance`.
    /// Set to one full unit of mean difference: knowing nothing about a night
    /// is about as bad as knowing everything and being wrong by one scale
    /// unit on all of it.
    static let missingCoveragePenalty = 1.0

    static func distance(from a: Context, to b: Context) -> Distance {
        var difference = 0.0
        var compared = 0

        func compare(_ lhs: Double?, _ rhs: Double?, scale: Double) {
            guard let lhs, let rhs else { return }
            compared += 1
            difference += abs(lhs - rhs) / scale
        }

        compare(a.sleepDebtMinutes, b.sleepDebtMinutes, scale: debtScale)
        compare(a.lateCaffeineMg, b.lateCaffeineMg, scale: caffeineScale)
        compare(a.exerciseMinutesPreviousDay, b.exerciseMinutesPreviousDay, scale: exerciseScale)
        compare(a.previousNightAsleepMinutes, b.previousNightAsleepMinutes, scale: previousSleepScale)

        if let lhs = a.bedtimeHour, let rhs = b.bedtimeHour {
            compared += 1
            let raw = abs(lhs - rhs)
            difference += min(raw, 24 - raw) / bedtimeScale
        }

        // The mean, not the sum. A sum grows with the number of features that
        // could be compared, so a night missing three of them scored lower
        // simply by having less to disagree about -- and less information
        // came out ranked as a better match.
        let mean = compared > 0 ? difference / Double(compared) : 0
        let uncovered = Double(numericFeatureCount - compared) / Double(numericFeatureCount)
        let weekend = a.isWeekend == b.isWeekend ? 0 : weekendMismatchPenalty

        return Distance(
            value: weekend + mean + missingCoveragePenalty * uncovered,
            comparedFeatures: compared
        )
    }

    // MARK: - The forecast

    /// Neighbours needed before the interval is read off them rather than off
    /// every night.
    ///
    /// Twelve because the interval is an empirical 10th-to-90th percentile,
    /// and below about a dozen samples those percentiles are barely
    /// distinguishable from the smallest and largest values -- which is a
    /// restatement of the neighbours' extremes, not a distribution.
    static let minimumNeighbours = 12

    /// How many neighbours to use once there are enough.
    ///
    /// Wider than the minimum so the interval is not built from the twelve
    /// closest nights alone: the very closest neighbours share the target's
    /// context almost exactly, and an interval fitted only to them is too
    /// narrow for the same reason a training-set error is too low.
    static let neighbourCount = 18

    /// A neighbour further than this is not a match, whatever the ranking
    /// says. Without a ceiling, a person with 30 nights of history always has
    /// 18 "nearest" ones, however unlike tomorrow they all are.
    ///
    /// One, on the scale `distance` now produces: zero for an identical
    /// context, and exactly 1.0 for a night that differs by one full scale
    /// unit on every feature. The previous 2.4 belonged to the summed scale
    /// and would admit roughly twice as much difference here -- a ceiling
    /// carried across a units change is not a ceiling.
    static let maximumDistance = 1.0

    /// At least this many numeric features must have been comparable for the
    /// match to count as conditioned at all.
    static let minimumComparedFeatures = 2

    static let lowerPercentile = 10.0
    static let upperPercentile = 90.0

    /// What the interval was actually built from. Carried into the UI so a
    /// fallback is never displayed as though it were a conditioned forecast.
    enum Basis: Hashable, Sendable {
        /// Read off nights that resembled tomorrow.
        case matchedNights(Int)
        /// Not enough resembling nights; this is the unconditioned recent
        /// range, and the copy says so.
        case recentRange(Int)

        var isConditioned: Bool {
            if case .matchedNights = self { return true }
            return false
        }
    }

    struct Prediction: Hashable, Sendable {
        /// Middle of what the matched nights did. Present because a range
        /// with no centre is hard to read, and deliberately never the
        /// headline -- see `sentence`.
        let typical: Double
        let lower: Double
        let upper: Double
        let basis: Basis
        let confidence: MetricConfidence
        /// What the matched nights actually had in common with tomorrow, most
        /// agreed-upon first. Empty on a `.recentRange` basis, because that
        /// interval was conditioned on nothing and listing a shared context
        /// under it would be a claim about a match that was never made.
        var matches: [Match] = []

        var spread: Double { upper - lower }

        /// The features the neighbours broadly agreed with tomorrow on.
        var sharedMatches: [Match] { matches.filter(\.isShared) }

        /// Features tomorrow has that the matched nights did *not* broadly
        /// share. Shown with the shared ones rather than hidden: a range
        /// built from nights that differed on caffeine is a weaker answer to
        /// a question about caffeine, and only saying what agreed would hide
        /// exactly that.
        var unsharedMatches: [Match] { matches.filter { !$0.isShared } }

        /// How a bare outcome value is written out.
        ///
        /// A parameter rather than a property of this type, because the type
        /// does not know what it is forecasting: 79 is a score and 430 is
        /// seven hours ten, and hard-coding either would make the engine
        /// usable for exactly one metric. Defaults to a plain integer, which
        /// is right for the 0-100 scores.
        typealias Format = (Double) -> String

        static let integerFormat: Format = { String(Int($0.rounded())) }

        /// "79–86". The interval, first and alone. There is deliberately no
        /// rendering anywhere in this type that produces a single number for
        /// tomorrow.
        func rangeLabel(format: Format = Prediction.integerFormat) -> String {
            "\(format(lower))–\(format(upper))"
        }

        func sentence(format: Format = Prediction.integerFormat) -> String {
            switch basis {
            case .matchedNights(let count):
                return "On the \(count) nights most like tomorrow, you landed between "
                    + "\(format(lower)) and \(format(upper))."
            case .recentRange(let count):
                return "Your last \(count) nights ranged from \(format(lower)) to "
                    + "\(format(upper)). Not enough of them resembled tomorrow for "
                    + "Zoon to narrow that down."
            }
        }

        /// What the range does not know. Always shown with it.
        var caveat: String {
            "Built from your own nights, matched on the day's shape, your sleep debt, "
                + "your bedtime, late caffeine, training and the night before. It does not "
                + "know your plans, the light you'll get, or anything it has never measured."
        }
    }

    /// One sample the forecast can learn from: a night's context and what it
    /// scored.
    ///
    /// Kept separate from `SleepNightFeatures` so the outcome is whatever the
    /// caller is forecasting. The engine has no opinion about which number it
    /// is predicting, which is also what makes it testable without dragging
    /// the whole scoring pipeline in.
    struct Sample: Hashable, Sendable {
        let context: Context
        let outcome: Double

        init(context: Context, outcome: Double) {
            self.context = context
            self.outcome = outcome
        }
    }

    /// Builds samples from an ordered run of nights.
    ///
    /// - Parameter outcome: the value being forecast, per night. Nights it
    ///   returns nil for are dropped -- a night with no score cannot teach
    ///   anything about tomorrow's.
    static func samples(
        from nights: [SleepNightFeatures],
        calendar: Calendar = .current,
        outcome: (SleepNightFeatures) -> Double?
    ) -> [Sample] {
        let ordered = nights.sorted { $0.date < $1.date }
        return ordered.enumerated().compactMap { index, night in
            guard let value = outcome(night) else { return nil }
            return Sample(
                context: .describing(
                    night,
                    previous: index > 0 ? ordered[index - 1] : nil,
                    calendar: calendar
                ),
                outcome: value
            )
        }
    }

    /// One scored candidate. A struct rather than a tuple because key paths
    /// -- `\.outcome`, `\.distance` -- do not apply to tuple elements.
    private struct Neighbour {
        let outcome: Double
        let distance: Distance
        /// Kept so the forecast can say *what* the matched nights had in
        /// common with tomorrow, not only how many there were. The distance
        /// is a single number and cannot be taken apart again afterwards.
        let context: Context
    }

    /// Forecasts one night.
    ///
    /// - Returns: nil only when there is not enough history for even the
    ///   unconditioned range to mean anything. A thin *match* is not nil --
    ///   it is a `.recentRange` basis, which is a different and honest answer.
    static func predict(
        for target: Context,
        from samples: [Sample],
        minimumNights: Int = UncertaintyForecast.minimumNights
    ) -> Prediction? {
        guard samples.count >= minimumNights else { return nil }

        let ranked = samples
            .map {
                Neighbour(
                    outcome: $0.outcome,
                    distance: distance(from: target, to: $0.context),
                    context: $0.context
                )
            }
            .filter { $0.distance.value <= maximumDistance
                && $0.distance.comparedFeatures >= minimumComparedFeatures }
            .sorted { $0.distance.value < $1.distance.value }
            .prefix(neighbourCount)

        if ranked.count >= minimumNeighbours {
            let outcomes = ranked.map(\.outcome)
            if let interval = interval(of: outcomes) {
                let count = Double(ranked.count)
                let meanDistance = ranked.reduce(0.0) { $0 + $1.distance.value } / count
                let meanCoverage = ranked.reduce(0.0) {
                    $0 + Double($1.distance.comparedFeatures) / Double(numericFeatureCount)
                } / count
                return Prediction(
                    typical: interval.typical,
                    lower: interval.lower,
                    upper: interval.upper,
                    basis: .matchedNights(outcomes.count),
                    confidence: confidence(
                        neighbours: outcomes.count,
                        meanDistance: meanDistance,
                        meanCoverage: meanCoverage
                    ),
                    matches: matches(of: target, against: ranked.map(\.context))
                )
            }
        }

        // Nothing resembling tomorrow. Report where every night landed, and
        // say that is what happened -- never silently widen a "matched"
        // interval, which would look identical to a real one in the UI.
        guard let interval = interval(of: samples.map(\.outcome)) else { return nil }
        return Prediction(
            typical: interval.typical,
            lower: interval.lower,
            upper: interval.upper,
            basis: .recentRange(samples.count),
            confidence: .low
        )
    }

    private static func interval(
        of values: [Double]
    ) -> (typical: Double, lower: Double, upper: Double)? {
        guard let typical = Statistics.median(values),
              let lower = Statistics.percentile(values, lowerPercentile),
              let upper = Statistics.percentile(values, upperPercentile) else { return nil }
        return (typical, min(lower, upper), max(lower, upper))
    }

    /// Graded on how many nights matched, how well they matched, and how much
    /// was actually known about them.
    ///
    /// All three, because any two of them can look good while the third makes
    /// the match worthless. Eighteen neighbours at the edge of
    /// `maximumDistance` are not eighteen sitting on top of the target; and
    /// eighteen close neighbours matched on two features out of five are not
    /// eighteen matched on all five, however close they look -- the closeness
    /// is measured over whatever happened to be known.
    ///
    /// `Distance` carried `comparedFeatures` from the start and this function
    /// ignored it, which is the same omission as the summed distance one
    /// level up: coverage was recorded and not used.
    ///
    /// The ceiling is `.high`; no combination here reports certainty.
    ///
    /// Not yet included, and named rather than quietly missing: temporal
    /// recency, regime similarity, forecast variance and historical
    /// calibration. The last needs `CalibrationLedger` to carry a
    /// `ContextForecast` arm, which is V10.1 work.
    static func confidence(
        neighbours: Int,
        meanDistance: Double,
        meanCoverage: Double
    ) -> MetricConfidence {
        guard neighbours >= minimumNeighbours else { return .insufficient }

        // Matched on half the features or fewer: whatever the distance says,
        // most of the night was never compared.
        guard meanCoverage > 0.5 else { return .low }

        let close = meanDistance <= maximumDistance / 2
        let wellCovered = meanCoverage >= 0.8

        switch neighbours {
        case ..<15:
            return close && wellCovered ? .moderate : .low
        default:
            if close && wellCovered { return .high }
            return close || wellCovered ? .moderate : .low
        }
    }
}

// MARK: - Why this range?

/// What the matched nights had in common with tomorrow.
///
/// The interval alone answers "how much", and the V10 spec asks the forecast
/// to also answer "on what grounds" -- *Similar bedtime. Similar recent debt.
/// Similar weekday.* Without it, a conditioned range and an unconditioned one
/// look identical on screen, and the person has no way to judge whether the
/// nights behind the number resemble the night they are about to have.
///
/// One property of the list worth knowing when reading it: day shape is
/// shared in very nearly every forecast, because `weekendMismatchPenalty` is
/// large enough that a night of the wrong shape rarely survives into the
/// neighbour set at all. It confirms rather than discriminates. The other
/// five each land shared in roughly half to four fifths of forecasts on
/// simulated histories, which is what makes them worth printing.
///
/// Two things this deliberately does not say. It does not rank the features
/// by influence: agreement is measured against tomorrow, over the neighbours
/// the interval was actually built from, and says nothing about which feature
/// moved the outcome. And it never reports a feature that was not compared --
/// see `featureCoverage`.
extension ContextForecast {

    /// One thing a night can be similar on. The same six `Context` carries,
    /// named as a person would say them.
    enum Feature: String, Hashable, Sendable, CaseIterable {
        case dayShape
        case sleepDebt
        case bedtime
        case lateCaffeine
        case exercise
        case previousNight

        /// Reads after "Similar": *Similar bedtime*, *Similar recent debt*.
        var label: String {
            switch self {
            case .dayShape: "weekday shape"
            case .sleepDebt: "recent sleep debt"
            case .bedtime: "bedtime"
            case .lateCaffeine: "late caffeine"
            case .exercise: "training the day before"
            case .previousNight: "sleep the night before"
            }
        }

        var symbol: String {
            switch self {
            case .dayShape: "calendar"
            case .sleepDebt: "hourglass"
            case .bedtime: "moon.stars"
            case .lateCaffeine: "cup.and.saucer"
            case .exercise: "figure.run"
            case .previousNight: "bed.double"
            }
        }

        /// Whether the night carries this feature at all. A missing feature
        /// is not a zero -- `Context` is explicit about that -- so it cannot
        /// be compared and is not reported either way.
        func isPresent(in context: ContextForecast.Context) -> Bool {
            switch self {
            case .dayShape: true
            case .sleepDebt: context.sleepDebtMinutes != nil
            case .bedtime: context.bedtimeHour != nil
            case .lateCaffeine: context.lateCaffeineMg != nil
            case .exercise: context.exerciseMinutesPreviousDay != nil
            case .previousNight: context.previousNightAsleepMinutes != nil
            }
        }

        /// The same scaled difference `ContextForecast.distance` computes,
        /// for this one feature. Shares the scales rather than inventing
        /// second ones, so "similar" here means what "close" means there.
        ///
        /// Returns nil when either night is missing the feature.
        func scaledDifference(
            _ a: ContextForecast.Context,
            _ b: ContextForecast.Context
        ) -> Double? {
            func gap(_ lhs: Double?, _ rhs: Double?, scale: Double) -> Double? {
                guard let lhs, let rhs else { return nil }
                return abs(lhs - rhs) / scale
            }

            switch self {
            case .dayShape:
                return a.isWeekend == b.isWeekend ? 0 : 1
            case .sleepDebt:
                return gap(a.sleepDebtMinutes, b.sleepDebtMinutes, scale: ContextForecast.debtScale)
            case .bedtime:
                guard let lhs = a.bedtimeHour, let rhs = b.bedtimeHour else { return nil }
                let raw = abs(lhs - rhs)
                return min(raw, 24 - raw) / ContextForecast.bedtimeScale
            case .lateCaffeine:
                return gap(a.lateCaffeineMg, b.lateCaffeineMg, scale: ContextForecast.caffeineScale)
            case .exercise:
                return gap(
                    a.exerciseMinutesPreviousDay,
                    b.exerciseMinutesPreviousDay,
                    scale: ContextForecast.exerciseScale
                )
            case .previousNight:
                return gap(
                    a.previousNightAsleepMinutes,
                    b.previousNightAsleepMinutes,
                    scale: ContextForecast.previousSleepScale
                )
            }
        }
    }

    /// How much the matched nights agreed with tomorrow on one feature.
    struct Match: Hashable, Sendable, Identifiable {
        let feature: Feature
        /// Neighbours close to tomorrow on this feature, as a fraction of the
        /// neighbours that carried it.
        let agreement: Double

        var id: String { feature.rawValue }

        var isShared: Bool { agreement >= ContextForecast.sharedAgreement }

        /// "Similar bedtime" / "Mixed bedtime". Never "bedtime caused this".
        var phrase: String {
            "\(isShared ? "Similar" : "Mixed") \(feature.label)"
        }
    }

    /// How close two nights must sit on one feature to count as similar on
    /// it. Half a scale unit -- an hour of bedtime, an hour of sleep debt,
    /// half a coffee -- which is comfortably inside `maximumDistance` and
    /// still a difference a person would call small.
    static let featureTightness = 0.5

    /// How many of the neighbours must agree before the feature is described
    /// as shared. Two thirds: a bare majority of eighteen nights is ten, and
    /// ten agreeing while eight differ is not something to print under the
    /// heading "why this range".
    static let sharedAgreement = 2.0 / 3.0

    /// How many of the neighbours must have *carried* the feature before it
    /// is reported at all.
    ///
    /// Below this the feature is dropped rather than scored zero. Zero
    /// agreement reads as "those nights differed from yours on caffeine",
    /// which is a finding; "most of them had no caffeine reading" is an
    /// absence, and the two must not print the same way.
    static let featureCoverage = 0.5

    /// What tomorrow and its matched nights share, most agreed-upon first.
    ///
    /// - Parameter neighbours: the contexts of the nights the interval was
    ///   read off -- not every night in the history. Reporting agreement over
    ///   nights that did not contribute would describe a different match.
    static func matches(of target: Context, against neighbours: [Context]) -> [Match] {
        guard !neighbours.isEmpty else { return [] }

        return Feature.allCases.compactMap { feature -> Match? in
            guard feature.isPresent(in: target) else { return nil }

            let differences = neighbours.compactMap { feature.scaledDifference(target, $0) }
            guard Double(differences.count) / Double(neighbours.count) >= featureCoverage,
                  !differences.isEmpty else { return nil }

            let close = differences.filter { $0 <= featureTightness }.count
            return Match(feature: feature, agreement: Double(close) / Double(differences.count))
        }
        .sorted { lhs, rhs in
            // Ties broken by the feature's own declaration order rather than
            // left to `sorted`'s instability, so the same forecast lists the
            // same reasons in the same order every time it is drawn.
            if lhs.agreement != rhs.agreement { return lhs.agreement > rhs.agreement }
            let order = Feature.allCases
            return (order.firstIndex(of: lhs.feature) ?? 0) < (order.firstIndex(of: rhs.feature) ?? 0)
        }
    }
}
