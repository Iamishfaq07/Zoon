import Foundation

/// Grades Zoon's own past claims against the nights that followed.
///
/// ## The missing rung
///
/// `EvidenceNotebook` ranks a claim by *how it was found* -- a pre-specified
/// experiment beats a matched-pair association beats an observed change beats
/// one night. That ordering is about method, and it is fixed before any
/// outcome is known.
///
/// Nothing ranked a claim by *whether it turned out to be right*. Three
/// separate files say so in prose -- `UncertaintyForecast` ("no calibration
/// against what actually happened next"), `BreathingHealth` ("nothing in this
/// app ever calibrated it against anything"), `ClinicianReportGenerator`
/// ("presented an uncalibrated..."). This is the first thing here that
/// checks.
///
/// ## Backtested, not recorded
///
/// The obvious implementation stores each prediction as it is made and scores
/// it the next morning. That produces nothing at all until weeks after
/// install, and silently loses every night already on the device.
///
/// This instead walks the history: for each night, it rebuilds the forecast
/// **from the nights before it only**, then checks whether that night landed
/// inside. No storage, an answer on the first run, and the no-lookahead rule
/// is the one property the tests guard hardest -- a backtest that peeks is
/// not a backtest, and it fails in the flattering direction.
enum CalibrationLedger {

    /// Scored attempts needed before this will draw any conclusion.
    ///
    /// Coverage is a proportion, and a proportion from a handful of trials is
    /// mostly noise: at 15 attempts the 95% interval spans roughly 40
    /// percentage points. Below this the honest output is "not yet", which
    /// `Verdict.notEnoughYet` says plainly rather than dressing up a coin
    /// flip as a finding.
    static let minimumAttempts = 15

    /// What the ledger concluded.
    enum Verdict: String, Sendable {
        /// Observed coverage is indistinguishable from what this estimator
        /// should produce. The common and correct answer for most people.
        case matchesExpectation
        /// The interval contained the night less often than it should. The
        /// forecast is claiming more precision than it has.
        case tooConfident
        /// The interval contained the night more often than it should. Not
        /// harmful, but wider than it needs to be.
        case tooCautious
        /// Too few scored nights to say anything.
        case notEnoughYet
    }

    struct Result: Identifiable, Sendable {
        let metric: TrendEngine.Metric
        /// Nights that had a forecast to be scored against.
        let attempts: Int
        /// Nights that landed inside their own interval.
        let hits: Int
        /// What this estimator should achieve, given the window sizes it
        /// actually ran on. **Not** the nominal 80%: see `expectedCoverage`.
        let expectedCoverage: Double
        /// 95% Wilson bounds on `observedCoverage`.
        let coverageLower: Double
        let coverageUpper: Double
        let verdict: Verdict

        var id: String { metric.rawValue }
        var observedCoverage: Double {
            attempts > 0 ? Double(hits) / Double(attempts) : 0
        }
    }

    // MARK: - What "calibrated" actually means here

    /// The coverage a **correctly behaving** interval achieves at this window
    /// size, which is not the 80% its 10th-to-90th label implies.
    ///
    /// `Statistics.percentile` interpolates at `rank = p/100 * (n - 1)`. For a
    /// 21-night window that puts the two bounds exactly on the 3rd and 19th
    /// smallest values, and the chance that a fresh draw falls between the
    /// k-th and m-th order statistics of n samples is `(m - k) / (n + 1)` --
    /// here 16/22, or 72.7%. Not 80%.
    ///
    /// The difference is not academic. Scoring against 80% would mark a
    /// perfectly well-behaved sleeper as overconfident, for everyone, forever
    /// -- the ledger's central verdict inverted by an off-by-a-definition.
    ///
    /// Distribution-free, because the bounds are ranks: a Monte Carlo over
    /// normal and lognormal nights lands on the same number, so this needs no
    /// assumption about the shape of anyone's sleep.
    ///
    /// Slightly conservative when the ranks interpolate rather than landing on
    /// a value (a 14-night window measures ~0.70 against 0.693 predicted).
    /// Under a percentage point, and far inside the Wilson interval at any
    /// sample size this feature will ever see.
    static func expectedCoverage(windowSize: Int) -> Double {
        guard windowSize > 1 else { return 0 }
        let span = (UncertaintyForecast.upperPercentile - UncertaintyForecast.lowerPercentile) / 100
        return span * Double(windowSize - 1) / Double(windowSize + 1)
    }

    /// Wilson score interval for a proportion.
    ///
    /// Not the textbook normal approximation, which at these sample sizes
    /// produces bounds below zero and above one and is badly wrong near the
    /// extremes -- exactly where a miscalibrated forecast would sit.
    static func wilsonInterval(hits: Int, attempts: Int, z: Double = 1.96) -> (lower: Double, upper: Double) {
        guard attempts > 0 else { return (0, 1) }
        let n = Double(attempts)
        let p = Double(hits) / n
        let denominator = 1 + z * z / n
        let centre = (p + z * z / (2 * n)) / denominator
        let margin = z * ((p * (1 - p) / n + z * z / (4 * n * n)).squareRoot()) / denominator
        return (max(0, centre - margin), min(1, centre + margin))
    }

    // MARK: - Backtest

    /// Scores every night that had enough history behind it to be forecast.
    ///
    /// - Parameter nights: history in any order; sorted internally.
    /// - Returns: `nil` when no night could be scored at all.
    static func backtest(
        metric: TrendEngine.Metric,
        nights: [SleepNightFeatures],
        minimumAttempts: Int = minimumAttempts
    ) -> Result? {
        let sorted = nights.sorted { $0.date < $1.date }
        guard sorted.count > UncertaintyForecast.minimumNights else { return nil }

        var attempts = 0
        var hits = 0
        var expectedSum = 0.0

        for index in sorted.indices {
            // The whole discipline of the thing: the forecast may see the
            // nights before `index` and nothing else. `prefix(index)` is
            // exclusive of `index`, which is what makes this honest.
            let past = Array(sorted.prefix(index))
            guard let forecast = UncertaintyForecast.forecast(metric: metric, nights: past),
                  let actual = metric.value(from: sorted[index])
            else { continue }

            attempts += 1
            if actual >= forecast.lower && actual <= forecast.upper { hits += 1 }
            // Per attempt, because early windows are shorter than late ones
            // and a shorter window has a lower expected coverage.
            expectedSum += expectedCoverage(windowSize: forecast.nightsUsed)
        }

        guard attempts > 0 else { return nil }

        let expected = expectedSum / Double(attempts)
        let bounds = wilsonInterval(hits: hits, attempts: attempts)

        let verdict: Verdict
        if attempts < minimumAttempts {
            verdict = .notEnoughYet
        } else if bounds.upper < expected {
            verdict = .tooConfident
        } else if bounds.lower > expected {
            verdict = .tooCautious
        } else {
            // The interval straddles the target: this sample cannot tell the
            // two apart, so the ledger does not pretend it can.
            verdict = .matchesExpectation
        }

        return Result(
            metric: metric,
            attempts: attempts,
            hits: hits,
            expectedCoverage: expected,
            coverageLower: bounds.lower,
            coverageUpper: bounds.upper,
            verdict: verdict
        )
    }

    /// Every metric that could be scored, most-attempted first.
    static func backtestAll(nights: [SleepNightFeatures]) -> [Result] {
        TrendEngine.Metric.allCases
            .compactMap { backtest(metric: $0, nights: nights) }
            .sorted { $0.attempts > $1.attempts }
    }
}
