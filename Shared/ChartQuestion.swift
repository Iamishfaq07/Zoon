import Foundation

/// A point on a chart, described in types rather than pixels, so that
/// "ask about this" has something real to ask about.
///
/// The V9 spec is blunt about the mechanism: pass typed context, and do
/// **not** have the model scrape the chart image. That is not only a
/// robustness argument. A model reading a picture of a line has to guess
/// what the line is worth -- what the axis means, where the baseline sits,
/// how many nights it took to establish. Everything it would have to guess
/// is already computed here, so it is handed over instead.
///
/// The question that comes out is **deterministic**. Tapping the same point
/// twice asks the same thing, and what is asked can be read on screen before
/// anything is generated. A model that invented its own question from a
/// gesture would make the answer unauditable: you could not tell whether a
/// surprising reply came from the data or from a question you never asked.
struct ChartQuestion: Hashable, Sendable, Identifiable {

    /// Stable for a given point, so presenting a sheet keyed on it does not
    /// re-present when the surrounding view redraws.
    var id: String { "\(metric.rawValue)-\(selected.date.timeIntervalSince1970)" }

    /// One plotted night.
    struct Point: Hashable, Sendable {
        let date: Date
        let value: Double

        init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    let metric: TrendEngine.Metric
    let selected: Point
    /// The window the chart is showing, when it has one. Included so an
    /// answer can say "across the two weeks shown" without inventing a span.
    var range: DateInterval? = nil
    /// The plotted nights around the selection, in date order.
    var nearby: [Point] = []
    /// The user's own current baseline for this metric, and how many nights
    /// it rests on -- a value 12ms under a 4-night baseline is a much
    /// weaker statement than the same gap under a 30-night one, and the
    /// model cannot know which it is being shown unless told.
    var baseline: Double? = nil
    var baselineNightCount: Int = 0
    /// How the night itself went, one already-formed fact.
    var sleep: String? = nil
    /// What the user logged, what they did, and what their body was doing:
    /// each entry a complete fact, never a raw number needing interpretation.
    var journal: [String] = []
    var workouts: [String] = []
    var bodySignals: [String] = []

    // MARK: - The question

    /// Whether the selected value sits meaningfully off the user's baseline.
    ///
    /// Uses the metric's own `clearsThreshold`, the same rule `TrendEngine`
    /// and `ChangePointDetector` use to decide a shift is worth reporting.
    /// A separate threshold here would let the app call a night "low" on one
    /// screen and unremarkable on another.
    enum Deviation: Hashable, Sendable {
        case above, below, typical, unknown
    }

    var deviation: Deviation {
        guard let baseline, baselineNightCount > 0 else { return .unknown }
        let delta = selected.value - baseline
        guard metric.clearsThreshold(delta, previousMedian: baseline) else { return .typical }
        return delta > 0 ? .above : .below
    }

    /// The exact question that will be asked, shown to the user before it is
    /// sent so nothing is asked on their behalf that they cannot see.
    ///
    /// A deviation is described as *higher* or *lower*, never as *worse* or
    /// *better*. Which direction is good is already in `higherIsBetter` and
    /// belongs in the answer, not smuggled into the question -- asking "why
    /// was my sleep worse" pre-loads the reply with a judgement the data has
    /// not made yet.
    var question: String {
        let day = selected.date.formatted(.dateTime.month(.wide).day())
        switch deviation {
        case .above:
            return "Why was my \(metric.label) higher on \(day)?"
        case .below:
            return "Why was my \(metric.label) lower on \(day)?"
        case .typical, .unknown:
            return "What was going on with my \(metric.label) on \(day)?"
        }
    }

    // MARK: - The context

    /// Everything above, as the lines the model is given.
    ///
    /// Only facts that exist are written. An absent baseline produces no
    /// baseline line rather than an empty or zero one: a model shown
    /// "Baseline: 0" will use the zero.
    var context: String {
        var lines: [String] = [
            "Metric: \(metric.label)",
            "Selected night: \(selected.date.formatted(.dateTime.year().month().day()))",
            "Selected value: \(formatted(selected.value))"
        ]

        if let range {
            lines.append("Chart shows: \(range.start.formatted(.dateTime.month().day())) to \(range.end.formatted(.dateTime.month().day()))")
        }

        if let baseline, baselineNightCount > 0 {
            lines.append("Their baseline: \(formatted(baseline)) over \(baselineNightCount) night\(baselineNightCount == 1 ? "" : "s")")
            let delta = selected.value - baseline
            let direction = delta > 0 ? "above" : "below"
            lines.append("This night is \(formattedMagnitude(abs(delta))) \(direction) that baseline")
        } else {
            // Stated rather than omitted. Silence about the baseline reads
            // as "unremarkable"; this says the comparison could not be made.
            lines.append("No established baseline yet for this metric")
        }

        if !nearby.isEmpty {
            let listed = nearby
                .sorted { $0.date < $1.date }
                .map { "\($0.date.formatted(.dateTime.month().day())) \(formatted($0.value))" }
                .joined(separator: ", ")
            lines.append("Nearby nights: \(listed)")
        }

        if let sleep { lines.append("That night's sleep: \(sleep)") }
        if !journal.isEmpty { lines.append("Logged that day: \(journal.joined(separator: ", "))") }
        if !workouts.isEmpty { lines.append("Activity that day: \(workouts.joined(separator: ", "))") }
        if !bodySignals.isEmpty { lines.append("Body signals: \(bodySignals.joined(separator: ", "))") }

        return lines.joined(separator: "\n")
    }

    // MARK: - Formatting

    /// A reading of this metric, as the user would read it off the axis.
    ///
    /// Bedtime is the exception `TrendEngine.formattedMagnitude` cannot
    /// serve: its values are signed minutes from midnight (negative for the
    /// evening, per `Statistics.circularMinutesFromMidnight`), so formatting
    /// one as a duration would print an 11pm bedtime as "-1h 0m".
    func formatted(_ value: Double) -> String {
        switch metric {
        case .bedtime:
            let wrapped = (value.truncatingRemainder(dividingBy: 1440) + 1440)
                .truncatingRemainder(dividingBy: 1440)
            let hour = Int(wrapped) / 60
            let minute = Int(wrapped) % 60
            return String(format: "%02d:%02d", hour, minute)
        default:
            return metric.formattedMagnitude(value)
        }
    }

    /// A *difference* in this metric. Unlike `formatted`, a bedtime gap is a
    /// duration -- "40m earlier" -- not a clock time.
    func formattedMagnitude(_ value: Double) -> String {
        metric.formattedMagnitude(value)
    }
}

// MARK: - Building one from a charted window

extension ChartQuestion {

    /// The question for one night of a charted series.
    ///
    /// The baseline is the median of the *other* nights on screen. Two
    /// deliberate choices there: the selected night is excluded, because a
    /// value compared against a baseline it is itself part of is compared
    /// against a slightly dragged version of itself; and the window is the
    /// one being looked at, so the comparison the model is given is the
    /// comparison the eye is already making.
    ///
    /// Returns `nil` when the metric has no value on the selected night --
    /// there is nothing to ask about a point that was never plotted.
    static func forNight(
        _ night: SleepNightFeatures,
        metric: TrendEngine.Metric,
        in nights: [SleepNightFeatures],
        journal: [String] = [],
        workouts: [String] = [],
        bodySignals: [String] = []
    ) -> ChartQuestion? {
        guard let value = metric.value(from: night) else { return nil }

        let others = nights
            .filter { $0.date != night.date }
            .compactMap { other -> Point? in
                guard let value = metric.value(from: other) else { return nil }
                return Point(date: other.date, value: value)
            }

        var question = ChartQuestion(metric: metric, selected: Point(date: night.date, value: value))
        question.range = others.isEmpty
            ? nil
            : DateInterval(
                start: min(night.date, others.map(\.date).min() ?? night.date),
                end: max(night.date, others.map(\.date).max() ?? night.date)
            )
        // Only the immediate neighbours. A whole month pasted into a prompt
        // is not more context, it is the same context with the two nights
        // that matter buried in it.
        question.nearby = Array(
            others
                .sorted { abs($0.date.timeIntervalSince(night.date)) < abs($1.date.timeIntervalSince(night.date)) }
                .prefix(4)
        )
        question.baseline = Statistics.median(others.map(\.value))
        question.baselineNightCount = others.count
        question.sleep = night.formattedTimeAsleep + " asleep"
        question.journal = journal
        question.workouts = workouts
        question.bodySignals = bodySignals
        return question
    }
}
