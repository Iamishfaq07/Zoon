import Foundation

/// A slow-moving read on how sleep has actually been going, distinct from
/// any single night's score.
///
/// Recovery and Sleep Intelligence both answer "how did last night go" --
/// useful, but a number that resets every morning can't say anything about
/// the pattern underneath it. Sleep Health looks at a whole window (two
/// weeks, a month, a quarter) and combines several angles that only mean
/// something in aggregate: one night's low efficiency is noise, a month of
/// it is a pattern. Built only from data Zoon already measures or the user
/// already logged -- nothing here is invented to fill a component that has
/// no real signal behind it, which is why the component list shrinks
/// automatically when data (breathing, self-reported feeling) isn't there.
struct SleepHealth: Sendable {

    enum Window: Int, CaseIterable, Identifiable, Sendable {
        case twoWeeks = 14
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .twoWeeks: "2 Weeks"
            case .month: "Month"
            case .quarter: "Quarter"
            }
        }
    }

    struct Component: Identifiable, Sendable {
        let id: String
        let label: String
        /// 0...100. Every component is oriented so higher is always better,
        /// even ones built from a raw measurement where lower is better
        /// (breathing disturbances, sleep debt) -- inverted at computation
        /// time so nothing downstream has to remember which direction a
        /// given component runs.
        let score: Double
    }

    /// A self-reported morning check-in, dated so `compute` can scope it to
    /// exactly the window it's building -- the field this type replaces
    /// (`[Int]`, undated) is why the two-call "current vs previous" trend in
    /// `InsightsHero` used to hand both computations the exact same feelings
    /// regardless of which window each was supposedly scoring. `rested`,
    /// `energy`, `sleepiness`, and `mood` are carried alongside `feeling`
    /// even though only `feeling` feeds a component today, so this type can
    /// stand in for whichever check-in dimension a future component needs
    /// without changing shape again.
    struct DatedMorningCheckIn: Sendable {
        let date: Date
        let feeling: Int?
        let rested: Int?
        let energy: Int?
        let sleepiness: Int?
        let mood: Int?

        init(date: Date, feeling: Int?, rested: Int? = nil, energy: Int? = nil, sleepiness: Int? = nil, mood: Int? = nil) {
            self.date = date
            self.feeling = feeling
            self.rested = rested
            self.energy = energy
            self.sleepiness = sleepiness
            self.mood = mood
        }
    }

    let window: Window
    /// Mean of `components`' scores, 0...100. `nil` when there wasn't
    /// enough history in the window to compute anything at all.
    let score: Double?
    /// Only the components that had enough data to compute -- never padded
    /// with a placeholder for a component that has nothing behind it.
    let components: [Component]
    let nightCount: Int
    let confidence: MetricConfidence

    /// Nights required in the window before a score is reported at all.
    static let minimumNights = 7

    /// Every component this model can possibly produce, in the order
    /// `compute` evaluates them. Used only to size confidence's "how much of
    /// the full model actually ran" term -- `components.count` alone can't
    /// distinguish "5 of 6 possible" from "5 of 5 possible."
    private static let maxComponentCount = 6

    /// - Parameters:
    ///   - nights: does not need to be pre-filtered to the window -- this
    ///     filters by `window` itself, so callers can pass full history.
    ///   - now: the instant this window is anchored to. Not just a testing
    ///     seam: `InsightsHero`'s "previous period" comparison calls this a
    ///     second time with `now` shifted back by one window, and relies on
    ///     the resulting interval having a real upper bound (see below) so
    ///     the previous window actually stops where the current one starts.
    static func compute(
        window: Window,
        goalMinutes: Double,
        nights: [SleepNightFeatures],
        morningCheckIns: [DatedMorningCheckIn] = [],
        configuration: Configuration = .current,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SleepHealth {
        // Explicit, non-overlapping DateInterval: [now - window, now). Bare
        // "date >= cutoff" with no upper bound was the actual bug -- called
        // a second time with `now` shifted back for a "previous period"
        // comparison, every night between that shifted `now` and the real
        // present still passed the filter, so "previous month" silently
        // included this month too and the two periods could never actually
        // differ from each other's overlap.
        let cutoff = calendar.date(byAdding: .day, value: -window.rawValue, to: now) ?? .distantPast
        let interval = DateInterval(start: cutoff, end: now)
        let windowNights = nights.filter { interval.contains($0.date) }.sorted { $0.date < $1.date }
        let windowCheckIns = morningCheckIns.filter { interval.contains($0.date) }

        guard windowNights.count >= minimumNights else {
            return SleepHealth(
                window: window, score: nil, components: [],
                nightCount: windowNights.count, confidence: .insufficient
            )
        }

        // Each night judged against its own historical need where one was
        // recorded, not one current Settings goal applied uniformly to
        // nights that may have been processed under a different learned
        // baseline -- the same semantics canonical Sleep Debt already uses
        // (see `SleepDebtCalculator.debtSeries`'s per-night goal overload).
        let personalNeeds = windowNights.map { $0.sleepNeedBaselineMinutes ?? goalMinutes }
        let averageNeed = Statistics.mean(personalNeeds) ?? goalMinutes

        var components: [Component] = []

        // Sufficiency: 24-hour sleep (main night plus naps -- a 45-minute
        // nap is real sleep and shouldn't vanish from a long-term
        // sufficiency read) against each night's own personal need,
        // averaged. Capped at 100 per night -- sleeping well past goal
        // isn't a deficiency in the other direction, this component just
        // has nothing more to say once met.
        let sufficiencyValues = zip(windowNights, personalNeeds).map { night, need in
            min(100, night.total24hAsleepMinutes / max(need, 1) * 100)
        }
        if let sufficiency = Statistics.mean(sufficiencyValues) {
            components.append(Component(id: "sufficiency", label: "Sufficiency", score: sufficiency))
        }

        // Regularity: SleepRegularity's own index, unmodified -- it's
        // already a 0...100 "higher is more regular" score built for
        // exactly this kind of window.
        let regularity = SleepRegularity.compute(nights: windowNights, calendar: calendar)
        if regularity.hasEnoughData {
            components.append(Component(id: "regularity", label: "Regularity", score: regularity.index))
        }

        // Continuity: efficiency, further penalized for frequent
        // awakenings -- two nights can share an efficiency percent while
        // one woke up eight times and the other twice, and only the
        // wake count actually tells them apart.
        if let avgEfficiency = Statistics.mean(windowNights.map(\.sleepEfficiencyPercent)),
           let avgWakes = Statistics.mean(windowNights.map { Double($0.wakeCount) }) {
            let continuity = max(0, avgEfficiency - avgWakes * 2)
            components.append(Component(id: "continuity", label: "Continuity", score: continuity))
        }

        // Estimated debt: the same exponential-decay model, over the same
        // 24-hour sleep and the same per-night personal need as
        // sufficiency above -- canonical Sleep Debt's exact inputs, not a
        // second, independent accounting of debt built from different
        // numbers. Inverted onto a 0...100 scale where zero debt is 100.
        // Three nights' worth of the window's average need is treated as
        // "as bad as this component usefully distinguishes" -- beyond
        // that, more debt doesn't make the underlying pattern any clearer.
        let debtSeries = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: windowNights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: personalNeeds
        )
        if let finalDebt = debtSeries.last {
            let ceiling = max(averageNeed * 3, 1)
            let debtScore = max(0, 100 - finalDebt / ceiling * 100)
            components.append(Component(id: "debt", label: "Sleep debt", score: debtScore))
        }

        // Breathing stability: inverted disturbance percentage, only when
        // at least half the window's nights actually measured it --
        // Watch-generation-gated, so many users will have none at all.
        let breathingValues = windowNights.compactMap(\.breathingDisturbances)
        let breathingCoverage = Double(breathingValues.count) / Double(windowNights.count)
        if breathingCoverage >= 0.5, let avgDisturbance = Statistics.mean(breathingValues) {
            let breathingScore = max(0, 100 - avgDisturbance * 10)
            components.append(Component(id: "breathing", label: "Breathing stability", score: breathingScore))
        }

        // Subjective restfulness: self-reported Morning Check-In feeling,
        // only for check-ins that actually fall inside this window, and
        // only when at least one was logged. Never blended into any
        // *nightly* score elsewhere in the app (see MorningFeeling's own
        // doc comment) -- this is the one place an aggregate of it is
        // deliberately used, because a slow-moving, self-reported signal
        // averaged over weeks is a different, much sturdier thing than
        // folding one morning's mood into last night's measured score.
        let feelingValues = windowCheckIns.compactMap(\.feeling)
        let checkInCoverage = Double(feelingValues.count) / Double(windowNights.count)
        if !feelingValues.isEmpty, let avgFeeling = Statistics.mean(feelingValues.map(Double.init)) {
            let restfulness = max(0, min(100, (avgFeeling - 1) / 4 * 100))
            components.append(Component(id: "restfulness", label: "Restfulness", score: restfulness))
        }

        let overall = configuration.weightedScore(components)
        let confidence = Self.confidence(
            nightCount: windowNights.count,
            componentCount: components.count,
            checkInCoverage: checkInCoverage,
            breathingCoverage: breathingCoverage
        )

        return SleepHealth(
            window: window, score: overall, components: components,
            nightCount: windowNights.count, confidence: confidence
        )
    }

    /// Confidence tracks more than "how many components happened to have
    /// data" -- five components computed from exactly the seven-night
    /// minimum, with nobody logging a check-in and half the nights missing
    /// breathing data, is not the same confidence as five components from a
    /// full quarter of dense data. Blended from four signals: how much
    /// history is actually behind the window (against three times the
    /// minimum, not the minimum itself -- "just cleared the bar" shouldn't
    /// read as abundant), how much of the six-component model ran at all,
    /// and the two coverage fractions that gate the two optional
    /// components. Coverage terms carry less weight than the first two --
    /// they refine confidence, they don't gate it, since a person who never
    /// logs a morning feeling shouldn't be capped out of high confidence on
    /// a score built entirely from measured signals.
    private static func confidence(
        nightCount: Int,
        componentCount: Int,
        checkInCoverage: Double,
        breathingCoverage: Double
    ) -> MetricConfidence {
        let nightSignal = min(1, Double(nightCount) / Double(minimumNights * 3))
        let componentSignal = Double(componentCount) / Double(maxComponentCount)
        let blended = nightSignal * 0.4 + componentSignal * 0.4
            + checkInCoverage * 0.1 + breathingCoverage * 0.1
        switch blended {
        case ..<0.35: return .low
        case 0.35..<0.7: return .moderate
        default: return .high
        }
    }
}

// MARK: - Configuration

extension SleepHealth {

    /// The weights and version behind the public score -- previously an
    /// implicit, unversioned equal mean of whatever components happened to
    /// be present. Weighted the same way `SleepIntelligenceScore` weights
    /// its own components: components missing from a given window
    /// (`weightedScore` below) have their weight redistributed across the
    /// ones that did compute, so a score is always out of the same 100
    /// regardless of which components a given window could support.
    struct Configuration: Sendable {
        /// Bumped whenever the weights or component set change, so a score
        /// computed under an old version stays interpretable as such rather
        /// than silently meaning something different after an app update.
        let algorithmVersion: Int
        let weights: [String: Double]

        static let currentVersion = 1

        static let current = Configuration(
            algorithmVersion: currentVersion,
            weights: [
                "sufficiency": 25,
                "regularity": 20,
                "continuity": 20,
                "debt": 20,
                "breathing": 8,
                "restfulness": 7
            ]
        )

        /// Weighted mean of whatever components are present, renormalized
        /// to the weight actually available -- the same "missing data
        /// doesn't silently penalize" contract `SleepIntelligenceScore`
        /// uses, applied here instead of a flat, unweighted average.
        func weightedScore(_ components: [Component]) -> Double? {
            guard !components.isEmpty else { return nil }
            var weightedSum = 0.0
            var totalWeight = 0.0
            for component in components {
                let weight = weights[component.id] ?? 1
                weightedSum += component.score * weight
                totalWeight += weight
            }
            guard totalWeight > 0 else { return nil }
            return weightedSum / totalWeight
        }
    }
}

// MARK: - Presentation

extension SleepHealth {

    enum Band: String, Sendable {
        case needsAttention, developing, solid, strong

        var label: String {
            switch self {
            case .needsAttention: "Needs attention"
            case .developing: "Developing"
            case .solid: "Solid"
            case .strong: "Strong"
            }
        }
    }

    var band: Band? {
        guard let score else { return nil }
        switch score {
        case ..<50: return .needsAttention
        case 50..<70: return .developing
        case 70..<85: return .solid
        default: return .strong
        }
    }
}
