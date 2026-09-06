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

    /// The widest coverage interval that still counts as having checked
    /// anything.
    ///
    /// This exists because "the interval straddles the target" is two very
    /// different situations wearing one answer, and the old code gave both
    /// the reassuring one.
    ///
    /// Straddling because the estimate is *tight* and centred near the target
    /// is a real result: coverage has been localised, and miscalibration
    /// worth caring about has been ruled out. Straddling because the estimate
    /// spans forty percentage points is not a result at all -- an interval
    /// that wide contains the target, and also contains badly overconfident
    /// and badly over-cautious, and calling it a match reports the width of
    /// the person's history as a property of the forecast.
    ///
    /// Twenty points, so a `matchesExpectation` means coverage has been
    /// placed within about ten points either side. That takes roughly seventy
    /// scored nights on the Wilson interval alone and more once the block
    /// bootstrap widens it -- which is the honest price of the sentence, not
    /// a bar set high for its own sake.
    ///
    /// Applies only to the straddling case. `tooConfident` and `tooCautious`
    /// are reached by *excluding* the target, and an exclusion is informative
    /// however wide the interval that managed it.
    static let decisiveWidth = 0.20

    /// What the ledger concluded.
    enum Verdict: String, CaseIterable, Sendable {
        /// Observed coverage is indistinguishable from what this estimator
        /// should produce -- and the estimate is tight enough for that to
        /// mean something. See `decisiveWidth`.
        case matchesExpectation
        /// The interval contained the night less often than it should. The
        /// forecast is claiming more precision than it has.
        case tooConfident
        /// The interval contained the night more often than it should. Not
        /// harmful, but wider than it needs to be.
        case tooCautious
        /// Enough scored nights to compute a coverage, not enough to rule
        /// anything out with it.
        ///
        /// Distinct from `notEnoughYet`, which is "there is no number".
        /// This is "there is a number, and it does not yet exclude anything",
        /// which is the state most people are in for their first few months
        /// and the state the previous version reported as a match.
        case stillLearning
        /// Too few scored nights to say anything.
        case notEnoughYet

        /// What this says, in the words the app uses for it.
        ///
        /// Deliberately about the *range*, not about "calibration". Nobody
        /// outside statistics reads "well calibrated" as anything but a
        /// grade, and this is not a grade -- it is whether the band Zoon
        /// draws around tonight has been containing nights as often as it
        /// claims to.
        var label: String {
            switch self {
            case .matchesExpectation: "Holding up"
            case .tooConfident: "Narrower than it should be"
            case .tooCautious: "Wider than it needs to be"
            case .stillLearning: "Still learning"
            case .notEnoughYet: "Not enough scored nights"
            }
        }

        /// One sentence on what to do about it, which for three of the five
        /// is nothing.
        var meaning: String {
            switch self {
            case .matchesExpectation:
                "Your nights have been landing inside Zoon's range about as often as it says they will."
            case .tooConfident:
                "Your nights land outside the range more often than it claims. Read the band as narrower than your real spread."
            case .tooCautious:
                "Your nights land inside the range more often than it claims. The band is safe, and roomier than it needs to be."
            case .stillLearning:
                "There are enough nights to measure how often the range holds, and not yet enough to tell a good range from a poor one."
            case .notEnoughYet:
                "Zoon has not scored enough nights to check its own range yet."
            }
        }

        /// Whether the sample actually ruled something out.
        ///
        /// True for the two exclusions and for a tight straddle, which has
        /// ruled out miscalibration; false for the two that only say the
        /// history is not long enough yet. A screen showing a verdict as a
        /// finding should be showing one of the first three.
        var isDecisive: Bool {
            self == .tooConfident || self == .tooCautious || self == .matchesExpectation
        }
    }

    /// What this feature is called where a person can see it.
    ///
    /// Not "Forecast Calibration". "Calibration" is a term of art that reads
    /// to everyone else as a device needing adjustment, and "forecast"
    /// promises a prediction about tonight -- which is the one thing this
    /// does not do. It grades the *range* Zoon has been drawing, against the
    /// nights that actually followed.
    static let title = "Recent Range Reliability"

    static let subtitle = "How often your nights have landed inside the range Zoon drew for them."

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

    // MARK: - Dependence

    /// Consecutive attempts are not independent, and Wilson assumes they are.
    ///
    /// Two things couple them. The forecasts themselves overlap: a 21-night
    /// window advanced by one night shares twenty of its twenty-one nights
    /// with the one before it, so neighbouring intervals are nearly the same
    /// interval. And sleep is serially correlated in its own right -- a rough
    /// fortnight is a rough fortnight, not fourteen coin flips.
    ///
    /// So `attempts` overstates how much independent evidence there is, and a
    /// Wilson interval computed from it is too narrow: it would report a
    /// precision the data does not contain, on the one screen whose entire
    /// job is to say how much to trust a number.
    ///
    /// A moving-block bootstrap resamples runs rather than individual nights,
    /// which preserves the local dependence instead of destroying it.
    /// Blocks are drawn from every overlapping window of `blockLength`, with
    /// replacement, until the resample is as long as the original.
    enum Dependence {

        /// Resamples per interval. A thousand is enough for percentile bounds
        /// at two decimal places and cheap on the numbers involved here --
        /// tens to low hundreds of attempts, not millions.
        static let resamples = 1_000

        /// Shortest and longest block. Below three there is not enough of a
        /// run left to carry any dependence; above seven a person with a
        /// couple of months of history has too few distinct blocks for the
        /// resample to vary at all.
        static let minimumBlockLength = 3
        static let maximumBlockLength = 7

        /// The usual n^(1/3) rule, clamped.
        ///
        /// It under-corrects here and it is worth saying so: the window
        /// overlap alone couples attempts up to twenty-one nights apart, and
        /// no block this short can represent that. Correcting it fully would
        /// need blocks so long that a sixty-night history yields three of
        /// them, which resamples to nothing useful. The residual error is
        /// therefore in the known direction -- still slightly too narrow --
        /// rather than in an unknown one.
        static func blockLength(attempts: Int) -> Int {
            guard attempts > 0 else { return minimumBlockLength }
            let rule = Int(pow(Double(attempts), 1.0 / 3.0).rounded())
            return min(maximumBlockLength, max(minimumBlockLength, rule))
        }

        /// Deterministic, so the same history always produces the same
        /// interval. A bootstrap seeded from the clock would move the numbers
        /// on this screen every time it was drawn, which reads as instability
        /// in the estimate rather than in the RNG.
        struct Generator: RandomNumberGenerator {
            private var state: UInt64
            init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
            mutating func next() -> UInt64 {
                state = state &+ 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }

        /// Moving-block bootstrap percentile interval for the hit rate.
        ///
        /// - Parameter outcomes: whether each attempt landed inside its own
        ///   interval, in chronological order. Order is the whole point --
        ///   shuffling these would destroy exactly the dependence being
        ///   measured.
        static func interval(
            outcomes: [Bool],
            resamples: Int = resamples
        ) -> (lower: Double, upper: Double) {
            let n = outcomes.count
            guard n > 0 else { return (0, 1) }
            let length = min(blockLength(attempts: n), n)
            let blockCount = n - length + 1
            let draws = Int((Double(n) / Double(length)).rounded(.up))

            // Seeded from the data: same history, same interval, and two
            // different histories do not share a resampling pattern.
            var generator = Generator(seed: outcomes.reduce(into: UInt64(n)) {
                $0 = $0 &* 31 &+ ($1 ? 1 : 0)
            })

            var rates: [Double] = []
            rates.reserveCapacity(resamples)
            for _ in 0..<resamples {
                var hits = 0
                var taken = 0
                for _ in 0..<draws {
                    let start = Int.random(in: 0..<blockCount, using: &generator)
                    for offset in 0..<length where taken < n {
                        if outcomes[start + offset] { hits += 1 }
                        taken += 1
                    }
                }
                rates.append(taken > 0 ? Double(hits) / Double(taken) : 0)
            }
            rates.sort()

            let lower = Statistics.percentile(rates, 2.5) ?? 0
            let upper = Statistics.percentile(rates, 97.5) ?? 1
            return (lower, upper)
        }

        /// The interval actually reported: the wider of Wilson and the
        /// bootstrap at each end.
        ///
        /// The bootstrap alone is wrong at the boundary. Thirty hits out of
        /// thirty makes every resample all-hits, so the interval collapses to
        /// a single point -- a *stronger* claim than the independence
        /// assumption it was meant to weaken, and a plainly false one:
        /// thirty for thirty is not proof that coverage is exactly 100%.
        /// Wilson is well behaved exactly there, being built for proportions
        /// near zero and one.
        ///
        /// Taking the wider end of each therefore gets both properties that
        /// matter: dependence can only ever widen the interval, and it can
        /// never collapse.
        static func combined(
            hits: Int,
            attempts: Int,
            outcomes: [Bool]
        ) -> (lower: Double, upper: Double) {
            let wilson = CalibrationLedger.wilsonInterval(hits: hits, attempts: attempts)
            guard outcomes.count > 1 else { return wilson }
            let block = interval(outcomes: outcomes)
            return (min(wilson.lower, block.lower), max(wilson.upper, block.upper))
        }
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
        // Kept in order, because the dependence between neighbouring attempts
        // is what the interval has to account for. A count cannot express it.
        var outcomes: [Bool] = []

        for index in sorted.indices {
            // The whole discipline of the thing: the forecast may see the
            // nights before `index` and nothing else. `prefix(index)` is
            // exclusive of `index`, which is what makes this honest.
            let past = Array(sorted.prefix(index))
            guard let forecast = UncertaintyForecast.forecast(metric: metric, nights: past),
                  let actual = metric.value(from: sorted[index])
            else { continue }

            attempts += 1
            let landedInside = actual >= forecast.lower && actual <= forecast.upper
            if landedInside { hits += 1 }
            outcomes.append(landedInside)
            // Per attempt, because early windows are shorter than late ones
            // and a shorter window has a lower expected coverage.
            expectedSum += expectedCoverage(windowSize: forecast.nightsUsed)
        }

        guard attempts > 0 else { return nil }

        let expected = expectedSum / Double(attempts)
        let bounds = Dependence.combined(hits: hits, attempts: attempts, outcomes: outcomes)

        return Result(
            metric: metric,
            attempts: attempts,
            hits: hits,
            expectedCoverage: expected,
            coverageLower: bounds.lower,
            coverageUpper: bounds.upper,
            verdict: verdict(
                attempts: attempts,
                bounds: bounds,
                expected: expected,
                minimumAttempts: minimumAttempts
            )
        )
    }

    /// Turns a scored coverage interval into what the app says about it.
    ///
    /// Separate from `backtest` so every branch can be exercised directly.
    /// Reached through a backtest, three of the five are only visible when a
    /// fixture happens to produce the right interval, and a branch tested by
    /// luck is a branch that stops being tested the day the fixture shifts.
    static func verdict(
        attempts: Int,
        bounds: (lower: Double, upper: Double),
        expected: Double,
        minimumAttempts: Int = minimumAttempts
    ) -> Verdict {
        // Order matters. The two exclusions are checked before the width bar,
        // because an exclusion is informative however wide the interval that
        // managed it -- an interval spanning forty points that still sits
        // entirely below the target has found something.
        if attempts < minimumAttempts { return .notEnoughYet }
        if bounds.upper < expected { return .tooConfident }
        if bounds.lower > expected { return .tooCautious }
        if bounds.upper - bounds.lower > decisiveWidth {
            // Straddling because the interval is too wide to exclude anything
            // -- it contains the target, and also contains badly overconfident
            // and badly over-cautious. Calling that a match reports the length
            // of the person's history as a property of the forecast.
            return .stillLearning
        }
        // Straddling with a tight interval is the real result: coverage has
        // been placed near the target, not merely failed to be excluded from
        // it.
        return .matchesExpectation
    }

    /// Every metric that could be scored, most-attempted first.
    static func backtestAll(nights: [SleepNightFeatures]) -> [Result] {
        TrendEngine.Metric.allCases
            .compactMap { backtest(metric: $0, nights: nights) }
            .sorted { $0.attempts > $1.attempts }
    }
}
