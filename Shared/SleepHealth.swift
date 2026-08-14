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

    /// - Parameters:
    ///   - nights: does not need to be pre-filtered to the window -- this
    ///     filters by `window` itself, so callers can pass full history.
    ///   - morningFeelingsRawValues: `MorningFeeling.rawValue`s (1...5) for
    ///     nights in the window, if logged. Taken as raw `Int`s rather than
    ///     the enum itself so this type has no dependency on Journal model
    ///     types and stays testable in isolation.
    static func compute(
        window: Window,
        goalMinutes: Double,
        nights: [SleepNightFeatures],
        morningFeelingRawValues: [Int] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SleepHealth {
        let cutoff = calendar.date(byAdding: .day, value: -window.rawValue, to: now) ?? .distantPast
        let windowNights = nights.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }

        guard windowNights.count >= minimumNights else {
            return SleepHealth(
                window: window, score: nil, components: [],
                nightCount: windowNights.count, confidence: .insufficient
            )
        }

        var components: [Component] = []

        // Sufficiency: average sleep against the personal goal. Capped at
        // 100 -- sleeping well past goal isn't a deficiency in the other
        // direction, this component just has nothing more to say once
        // met.
        if let avgAsleep = Statistics.mean(windowNights.map(\.timeAsleepMinutes)) {
            let sufficiency = min(100, avgAsleep / max(goalMinutes, 1) * 100)
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

        // Estimated debt: the same exponential-decay model Sleep Debt
        // itself uses, inverted onto a 0...100 scale where zero debt is
        // 100. Three nights' worth of goal sleep is treated as "as bad as
        // this component usefully distinguishes" -- beyond that, more
        // debt doesn't make the underlying pattern any clearer.
        let debtSeries = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: windowNights.map(\.timeAsleepMinutes),
            goalMinutes: goalMinutes
        )
        if let finalDebt = debtSeries.last {
            let ceiling = max(goalMinutes * 3, 1)
            let debtScore = max(0, 100 - finalDebt / ceiling * 100)
            components.append(Component(id: "debt", label: "Sleep debt", score: debtScore))
        }

        // Breathing stability: inverted disturbance percentage, only when
        // at least half the window's nights actually measured it --
        // Watch-generation-gated, so many users will have none at all.
        let breathingValues = windowNights.compactMap(\.breathingDisturbances)
        if breathingValues.count * 2 >= windowNights.count,
           let avgDisturbance = Statistics.mean(breathingValues) {
            let breathingScore = max(0, 100 - avgDisturbance * 10)
            components.append(Component(id: "breathing", label: "Breathing stability", score: breathingScore))
        }

        // Subjective restfulness: self-reported Morning Check-In feeling,
        // only when logged at all. Never blended into any *nightly*
        // score elsewhere in the app (see MorningFeeling's own doc
        // comment) -- this is the one place an aggregate of it is
        // deliberately used, because a slow-moving, self-reported signal
        // averaged over weeks is a different, much sturdier thing than
        // folding one morning's mood into last night's measured score.
        if !morningFeelingRawValues.isEmpty,
           let avgFeeling = Statistics.mean(morningFeelingRawValues.map(Double.init)) {
            let restfulness = max(0, min(100, (avgFeeling - 1) / 4 * 100))
            components.append(Component(id: "restfulness", label: "Restfulness", score: restfulness))
        }

        let overall = Statistics.mean(components.map(\.score))
        let confidence: MetricConfidence = {
            switch components.count {
            case 0: .insufficient
            case 1..<3: .low
            case 3..<5: .moderate
            default: .high
            }
        }()

        return SleepHealth(
            window: window, score: overall, components: components,
            nightCount: windowNights.count, confidence: confidence
        )
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
