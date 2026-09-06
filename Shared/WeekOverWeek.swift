import Foundation

/// This week against the week before it, with a bar for what counts as a
/// change.
///
/// ## The defect this replaces
///
/// Two screens computed these four comparisons independently, and both
/// reported *any* non-zero delta as a change with a good-or-bad colour on it.
/// One used `delta == 0` as its "no change" test, the other `abs(delta) < 1`.
/// Two seven-night averages are essentially never equal, so in practice every
/// number on both screens was always announced as an improvement or a
/// regression.
///
/// Simulated over two weeks drawn from the *same* distribution -- a person
/// whose sleep is not changing at all, where every reported change is by
/// construction noise -- the old rule announced a change 100% of the time on
/// every metric.
///
/// ## Why a threshold alone is not enough
///
/// The obvious fix is `TrendEngine.Metric.clearsThreshold`, which the app
/// already shares between `TrendEngine`, `ChangePointDetector` and
/// `ChartQuestion` precisely so one screen cannot call a move notable while
/// another calls it unremarkable.
///
/// On the same simulation that alone still fires 57% of the time on duration
/// and 53% on sleep debt. The reason is that `clearsThreshold` was never the
/// whole rule: `ChangePointDetector` applies it *and* requires the two levels
/// to separate by several standard errors. Borrowing the threshold without
/// the separation imports half the protection and reads as if it were all of
/// it.
///
/// So this applies both, and the pair takes the false-alarm rate to about 8%
/// -- roughly what a two-sided 95% test should give.
enum WeekOverWeek {

    /// Standard errors of separation required on top of the metric's own
    /// threshold.
    ///
    /// Lower than `ChangePointDetector.minimumEffect` (3.0) on purpose. That
    /// scans every metric for its best split point, so it is choosing a
    /// winner out of many correlated statistics and needs the extra margin.
    /// These four comparisons are fixed in advance and always the same four,
    /// so the conventional two-sided bar is the honest one here.
    static let minimumSeparation = 2.0

    /// Nights required on each side. A partial week compared against a full
    /// one is not a week-over-week comparison.
    static let weekLength = 7

    struct Change: Identifiable, Hashable, Sendable {
        /// Which shared threshold governs this comparison.
        let metric: TrendEngine.Metric
        let id: String
        let title: String
        /// The previous week's average, and this week's.
        let before: Double
        let after: Double
        /// Separation between the two weekly means, in standard errors of
        /// their difference. Carried so a caller can show *why* something is
        /// or is not being called a change.
        let separation: Double
        /// Whether the move cleared both bars.
        let isMeaningful: Bool
        /// Whether higher is better for this comparison. Not always the
        /// metric's own direction: bedtime *steadiness* is a spread, where
        /// smaller is better, while `TrendEngine.Metric.bedtime` is a time.
        let higherIsBetter: Bool

        var delta: Double { after - before }

        /// `nil` when the move did not clear the bars -- which is what the
        /// views render as neutral. A direction on a change that has not been
        /// shown to be one is the whole thing being fixed here, so this is
        /// deliberately not an "unchanged" case of a Bool.
        var isImprovement: Bool? {
            guard isMeaningful else { return nil }
            return higherIsBetter ? delta > 0 : delta < 0
        }
    }

    /// The four comparisons, in a fixed order.
    ///
    /// - Parameter nights: full history, oldest first. The last 14 are used.
    static func compare(
        nights: [SleepNightFeatures],
        goalMinutes: Double
    ) -> [Change] {
        let current = Array(nights.suffix(weekLength))
        let previous = Array(nights.dropLast(weekLength).suffix(weekLength))
        guard current.count == weekLength, previous.count == weekLength else { return [] }

        var changes: [Change] = []

        changes.append(
            change(
                metric: .duration, id: "sleep", title: "Time asleep",
                previous: previous.map(\.timeAsleepMinutes),
                current: current.map(\.timeAsleepMinutes),
                higherIsBetter: true
            )
        )

        let previousHRV = previous.compactMap(\.avgHRV)
        let currentHRV = current.compactMap(\.avgHRV)
        if previousHRV.count >= 2, currentHRV.count >= 2 {
            changes.append(
                change(
                    metric: .hrv, id: "hrv", title: "HRV",
                    previous: previousHRV, current: currentHRV,
                    higherIsBetter: true
                )
            )
        }

        // A spread, not a level -- so `higherIsBetter` is false, and the
        // threshold borrowed is `.bedtime`'s. Twenty minutes is the amount of
        // bedtime movement this app treats as meaningful, and a twenty-minute
        // change in how much bedtime moves is the same size of statement.
        //
        // Each week is one number rather than seven, so there is no spread of
        // spreads to separate. The threshold carries this one alone, which is
        // the honest position: the sampling distribution of a standard
        // deviation from seven values is not something this comparison knows.
        let previousSpread = bedtimeSpreadMinutes(previous)
        let currentSpread = bedtimeSpreadMinutes(current)
        changes.append(
            Change(
                metric: .bedtime, id: "bedtime", title: "Bedtime steadiness",
                before: previousSpread, after: currentSpread,
                separation: 0,
                isMeaningful: TrendEngine.Metric.bedtime.clearsThreshold(
                    currentSpread - previousSpread, previousMedian: previousSpread
                ),
                higherIsBetter: false
            )
        )

        let series = SleepDebtCalculator.debtSeries(
            timeAsleepMinutesOldestFirst: nights.map(\.total24hAsleepMinutes),
            goalMinutesOldestFirst: nights.map { $0.sleepNeedBaselineMinutes ?? goalMinutes }
        )
        if series.count >= weekLength * 2,
           let now = series.last,
           let weekAgo = series.dropLast(weekLength).last {
            // Debt is a running total read at two instants, not two samples of
            // seven, so it has no standard error either -- and unlike the
            // others it is cumulative, so a real change in sleep shows up here
            // as a trend rather than as noise. The threshold alone is the
            // right rule for it.
            changes.append(
                Change(
                    metric: .sleepDebt, id: "debt", title: "Sleep debt",
                    before: weekAgo, after: now,
                    separation: 0,
                    isMeaningful: TrendEngine.Metric.sleepDebt.clearsThreshold(
                        now - weekAgo, previousMedian: weekAgo
                    ),
                    higherIsBetter: false
                )
            )
        }

        return changes
    }

    /// One comparison between two weeks of nightly values.
    private static func change(
        metric: TrendEngine.Metric,
        id: String,
        title: String,
        previous: [Double],
        current: [Double],
        higherIsBetter: Bool
    ) -> Change {
        let before = mean(previous)
        let after = mean(current)
        let delta = after - before
        let separation = separation(previous: previous, current: current)

        return Change(
            metric: metric, id: id, title: title,
            before: before, after: after,
            separation: separation,
            isMeaningful: metric.clearsThreshold(delta, previousMedian: before)
                && separation >= minimumSeparation,
            higherIsBetter: higherIsBetter
        )
    }

    /// Difference between the two weekly means, in standard errors of that
    /// difference.
    ///
    /// Returns 0 when either week has no spread at all, which makes the
    /// comparison fail the bar rather than pass it on a divide-by-zero.
    static func separation(previous: [Double], current: [Double]) -> Double {
        guard previous.count > 1, current.count > 1 else { return 0 }
        let error = (variance(previous) / Double(previous.count)
            + variance(current) / Double(current.count)).squareRoot()
        guard error > 0 else { return 0 }
        return abs(mean(current) - mean(previous)) / error
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Population variance -- these are the whole week, not a sample of it.
    private static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let m = mean(values)
        return values.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(values.count)
    }

    /// Standard deviation of bedtime in minutes, with evening times shifted
    /// so they do not wrap around midnight.
    ///
    /// Each night in its own timezone: a historical bedtime's wall-clock hour
    /// does not change because the person has since travelled. Same reasoning
    /// as `DayContextBuilder.shiftedBedtimeHour` and `BodyClock.compute`.
    static func bedtimeSpreadMinutes(_ week: [SleepNightFeatures]) -> Double {
        var calendar = Calendar.current
        let minutes = week.map { night -> Double in
            calendar.timeZone = night.timeZone
            return Statistics.circularMinutesFromMidnight(night.bedtime, calendar: calendar)
        }
        guard minutes.count > 1 else { return 0 }
        return variance(minutes).squareRoot()
    }
}
