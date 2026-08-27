import Foundation

/// What tomorrow night is likely to look like -- as a range, never as a
/// single number.
///
/// A bare point forecast ("you'll get 7h 10m") claims a precision no sleep
/// model has. The honest object is an interval wide enough to contain what
/// actually happens most of the time, and the width of that interval is the
/// most informative part of the whole forecast: a person whose nights land
/// between 6h and 8h has a different problem from one who lands between 7h
/// and 7h 20m, and a point estimate hides exactly that difference.
///
/// **This is a prediction interval, not a confidence interval**, and the two
/// are routinely conflated to the user's cost. A confidence interval covers
/// where the *average* night sits and shrinks toward nothing as history
/// accumulates; a prediction interval covers where *one more night* is
/// likely to land and stays roughly as wide as the person's life is
/// variable. Reporting the former as a forecast would tell someone with
/// wildly erratic sleep that tomorrow is nearly certain, purely because they
/// have logged a lot of nights.
///
/// Non-parametric on purpose: the interval is read off the person's own
/// recent values as empirical percentiles, with no assumption that nights
/// are normally distributed around a mean. Sleep duration in particular is
/// skewed -- there is a hard ceiling on how much most people sleep and a
/// long tail of very short nights -- and a symmetric mean +/- k*sigma band
/// would sit visibly wrong on both ends.
enum UncertaintyForecast {

    /// Nights required before a forecast is offered at all.
    ///
    /// Fourteen because the interval is read off empirical percentiles: the
    /// 10th and 90th of nine values are just the smallest and largest ones,
    /// which is not an interval so much as a restatement of the extremes.
    static let minimumNights = 14

    /// Window the forecast is drawn from. Deliberately shorter than the
    /// 30-night baselines elsewhere in the app: this predicts the near
    /// future, and a schedule change two months ago should stop colouring
    /// tomorrow long before it stops colouring a long-run baseline.
    static let window = 21

    /// Coverage of the reported interval. 80%, not 95%: a 95% band over
    /// noisy personal data is so wide it stops discriminating between a
    /// steady sleeper and an erratic one, which is the comparison this is
    /// for. Stated in the copy so the number is never mistaken for a
    /// guarantee.
    static let lowerPercentile = 10.0
    static let upperPercentile = 90.0

    struct Forecast: Hashable, Sendable {
        let metric: TrendEngine.Metric
        /// Middle of the person's recent nights -- the single most likely
        /// value, offered only alongside the interval.
        let typical: Double
        let lower: Double
        let upper: Double
        let nightsUsed: Int
        let confidence: MetricConfidence

        /// Width of the interval in the metric's own units. The headline
        /// number for "how predictable are my nights", and worth surfacing
        /// on its own.
        var spread: Double { upper - lower }

        /// Plain-language forecast. Leads with the range, not the midpoint.
        var sentence: String {
            "Tomorrow will most likely land between \(metric.formattedMagnitude(lower)) and "
                + "\(metric.formattedMagnitude(upper)) for \(metric.label), "
                + "typically around \(metric.formattedMagnitude(typical))."
        }

        /// The caveat that must travel with any forecast from this type.
        /// A forecast built purely from past nights knows nothing about what
        /// the person actually intends to do tomorrow.
        var caveat: String {
            "Based on your last \(nightsUsed) nights, and assuming tomorrow is an ordinary one. "
                + "It doesn't know your plans."
        }
    }

    // MARK: - Forecasting

    /// Forecasts one metric for the next night.
    ///
    /// - Returns: `nil` when there is too little history for an empirical
    ///   interval to mean anything. Deliberately nil rather than a wide
    ///   guess: a forecast presented with a huge interval still reads as a
    ///   forecast, and there is nothing to forecast from yet.
    static func forecast(
        metric: TrendEngine.Metric,
        nights: [SleepNightFeatures],
        minimumNights: Int = minimumNights
    ) -> Forecast? {
        let values = nights
            .sorted { $0.date < $1.date }
            .suffix(window)
            .compactMap(metric.value(from:))

        guard values.count >= minimumNights,
              let typical = Statistics.median(values),
              let lower = Statistics.percentile(values, lowerPercentile),
              let upper = Statistics.percentile(values, upperPercentile) else { return nil }

        return Forecast(
            metric: metric,
            typical: typical,
            lower: min(lower, upper),
            upper: max(lower, upper),
            nightsUsed: values.count,
            confidence: confidence(forNightCount: values.count)
        )
    }

    /// Every metric that has enough history, most predictable first.
    ///
    /// Sorted by *relative* spread rather than raw width so metrics in
    /// different units can be compared at all -- 40 minutes of duration
    /// spread and 40 bpm of heart-rate spread are not remotely the same
    /// amount of unpredictability.
    static func forecastAll(
        nights: [SleepNightFeatures],
        minimumNights: Int = minimumNights
    ) -> [Forecast] {
        TrendEngine.Metric.allCases
            .compactMap { forecast(metric: $0, nights: nights, minimumNights: minimumNights) }
            .sorted { relativeSpread($0) < relativeSpread($1) }
    }

    private static func relativeSpread(_ forecast: Forecast) -> Double {
        // Guarded against a typical value of zero, which is legitimate for
        // sleep debt on someone fully rested.
        forecast.spread / max(abs(forecast.typical), 1)
    }

    /// Confidence rises with how many nights back the interval, and stops
    /// rising well before "certain" -- the ceiling is `.high`, never a claim
    /// of precision the method cannot support.
    private static func confidence(forNightCount count: Int) -> MetricConfidence {
        switch count {
        case ..<minimumNights: .insufficient
        case minimumNights..<18: .low
        case 18..<21: .moderate
        default: .high
        }
    }
}
