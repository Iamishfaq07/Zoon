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
    var id: String { "\(subject.rawValue)-\(selected.date.timeIntervalSince1970)" }

    /// The two metric vocabularies this app has, and the only two.
    ///
    /// `ChartQuestion` used to take a `TrendEngine.Metric` directly, which
    /// meant "ask about this point" could only ever be offered on the six
    /// series that type knows. The vitals screen charts seven, and only two
    /// of them overlap -- so five of a person's body signals had a chart they
    /// could scrub and nothing they could ask about it.
    ///
    /// Deliberately an enum over the existing types rather than a struct of
    /// copied labels and thresholds. Each vocabulary already owns its own
    /// rule for what counts as notable, and those rules are genuinely
    /// different: `TrendEngine` uses a fixed per-metric threshold shared with
    /// `ChangePointDetector`, while `VitalsStatus` uses a tolerance derived
    /// from the person's own spread. Flattening both into one number here
    /// would have quietly replaced two considered rules with a third
    /// invented one.
    enum Subject: Hashable, Sendable {
        case trend(TrendEngine.Metric)
        case vital(VitalsStatus.Kind)

        var rawValue: String {
            switch self {
            case let .trend(metric): "trend:\(metric.rawValue)"
            case let .vital(kind): "vital:\(kind.rawValue)"
            }
        }

        /// Lower-cased, because it is always read mid-sentence: "why was my
        /// resting heart rate higher on 3 May?". `VitalsStatus.Kind.label` is
        /// title-cased for panel headings, which is the wrong register here.
        var label: String {
            switch self {
            case let .trend(metric): metric.label
            case let .vital(kind): kind.label.lowercased()
            }
        }

        /// A reading, as the person would read it off the axis.
        func formatValue(_ value: Double) -> String {
            switch self {
            case let .trend(metric):
                // Bedtime is the exception `formattedMagnitude` cannot serve:
                // its values are signed minutes from midnight (negative for
                // the evening, per `Statistics.circularMinutesFromMidnight`),
                // so formatting one as a duration prints an 11pm bedtime as
                // "-1h 0m".
                guard case .bedtime = metric else { return metric.formattedMagnitude(value) }
                let wrapped = (value.truncatingRemainder(dividingBy: 1440) + 1440)
                    .truncatingRemainder(dividingBy: 1440)
                return String(format: "%02d:%02d", Int(wrapped) / 60, Int(wrapped) % 60)
            case let .vital(kind):
                return kind.format(value)
            }
        }

        /// A *difference*. Unlike `formatValue`, a bedtime gap is a duration
        /// -- "40m earlier" -- not a clock time. A vital's units are the same
        /// either way, so it formats identically.
        func formatMagnitude(_ value: Double) -> String {
            switch self {
            case let .trend(metric): metric.formattedMagnitude(value)
            case let .vital(kind): kind.format(value)
            }
        }
    }

    /// One plotted night.
    struct Point: Hashable, Sendable {
        let date: Date
        let value: Double

        init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// What the charted series is, and whose rule decides whether a point
    /// is notable.
    let subject: Subject
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
    /// How far from `baseline` this subject has to sit before it is outside
    /// typical, when the subject's own rule is a tolerance rather than a
    /// threshold.
    ///
    /// Only `.vital` uses it: `VitalsStatus` derives a tolerance from the
    /// person's own spread rather than applying a fixed number, so the figure
    /// has to travel with the question instead of being recomputed here from
    /// a different rule. `nil` for a `.trend` subject, which carries its
    /// threshold in the metric itself.
    var tolerance: Double? = nil
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
    /// Each subject is judged by the rule its own screen uses, never by a
    /// rule invented here. A `.trend` metric uses `clearsThreshold`, shared
    /// with `TrendEngine` and `ChangePointDetector`; a `.vital` uses the
    /// tolerance `VitalsStatus` derived from the person's own spread.
    ///
    /// The alternative -- one threshold for everything -- is what would let
    /// the app call a reading notable on one screen and unremarkable on
    /// another, which is the thing this indirection exists to prevent rather
    /// than a cost of it.
    enum Deviation: Hashable, Sendable {
        case above, below, typical, unknown
    }

    var deviation: Deviation {
        guard let baseline, baselineNightCount > 0 else { return .unknown }
        let delta = selected.value - baseline

        let isNotable: Bool
        switch subject {
        case let .trend(metric):
            isNotable = metric.clearsThreshold(delta, previousMedian: baseline)
        case .vital:
            // No tolerance means the vitals engine had too little history to
            // establish one. That is "we cannot say", not "unremarkable".
            guard let tolerance, tolerance > 0 else { return .unknown }
            isNotable = abs(delta) > tolerance
        }

        guard isNotable else { return .typical }
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
            return "Why was my \(subject.label) higher on \(day)?"
        case .below:
            return "Why was my \(subject.label) lower on \(day)?"
        case .typical, .unknown:
            return "What was going on with my \(subject.label) on \(day)?"
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
            "Metric: \(subject.label)",
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

    /// A reading, as the user would read it off the axis. See
    /// `Subject.formatValue`.
    func formatted(_ value: Double) -> String { subject.formatValue(value) }

    /// A *difference*. See `Subject.formatMagnitude`.
    func formattedMagnitude(_ value: Double) -> String { subject.formatMagnitude(value) }
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

        var question = ChartQuestion(subject: .trend(metric), selected: Point(date: night.date, value: value))
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

    /// The question for one point on a vital's own trend.
    ///
    /// Takes the baseline and tolerance rather than deriving them, because
    /// `VitalsStatus` has already computed both from the person's history
    /// with rules of its own -- a minimum night count per vital, and a
    /// tolerance in standard deviations. Recomputing here from the handful of
    /// points a chart happens to be showing would produce a second, weaker
    /// answer to a question the app has already answered properly.
    ///
    /// Returns `nil` when there is nothing plotted to ask about.
    static func forVital(
        _ kind: VitalsStatus.Kind,
        selected: Point,
        in points: [Point],
        baseline: Double?,
        tolerance: Double?,
        baselineNightCount: Int
    ) -> ChartQuestion? {
        guard points.contains(where: { $0.date == selected.date }) else { return nil }
        let others = points.filter { $0.date != selected.date }

        var question = ChartQuestion(subject: .vital(kind), selected: selected)
        question.range = others.isEmpty
            ? nil
            : DateInterval(
                start: min(selected.date, others.map(\.date).min() ?? selected.date),
                end: max(selected.date, others.map(\.date).max() ?? selected.date)
            )
        // Same reasoning as `forNight`: the immediate neighbours, not the
        // whole window. A month pasted into a prompt is the same context with
        // the points that matter buried in it.
        question.nearby = Array(
            others
                .sorted {
                    abs($0.date.timeIntervalSince(selected.date))
                        < abs($1.date.timeIntervalSince(selected.date))
                }
                .prefix(4)
        )
        question.baseline = baseline
        question.tolerance = tolerance
        question.baselineNightCount = baselineNightCount
        return question
    }
}
