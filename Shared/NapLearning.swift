import Foundation

/// What this person's own naps have gone with, measured against comparable
/// days when they did not nap.
///
/// **What this replaced, and why all of it.** The first version compared nap
/// days against a fixed 35% threshold, or against *other nap days*, and never
/// against a day without a nap — so it had no control group at all and
/// reported associations it had not measured. It bucketed every nap under
/// thirty-five minutes together and then called the group "your 20–30 minute
/// naps", which is a label for a set it was not measuring: a five-minute doze
/// on the sofa and a deliberate half-hour are not the same event, and lumping
/// them makes the deliberate ones look like whatever the dozes did. And it
/// read bedtime as a raw hour, so 23:50 and 00:10 — ten minutes apart — fell
/// in different buckets and were scored as a six-hour difference.
///
/// **What it does instead.** Each nap day is matched to the most comparable
/// no-nap day available: same weekday type and timezone as hard constraints,
/// then nearest on previous-night sleep and outstanding shortfall. Bedtime is
/// compared circularly. The reported effect is the median of each pair's own
/// difference, which is what the typical pair actually showed rather than a
/// difference between two group medians that can cancel opposite movements
/// out.
///
/// It is observational and says so. A person who naps on the days they are
/// already exhausted will show naps alongside worse nights, and no amount of
/// matching on measured confounders fixes that.
enum NapLearning {

    /// One day, whether or not it contained a nap.
    ///
    /// The control arm is the whole point, so a day without a nap is an
    /// observation rather than a skipped row — which is what the shape this
    /// replaced could not express.
    struct Observation: Hashable, Sendable {
        struct Nap: Hashable, Sendable {
            /// Hours past local midnight, e.g. 14.5 for 14:30.
            let startHour: Double
            let minutes: Double
        }

        let date: Date
        /// The day's nap, when it had one. Multiple naps collapse to the
        /// longest — a day is a day, and two observations of one day would
        /// let it back its own comparison twice.
        let nap: Nap?
        /// That night's bedtime, in shifted minutes from midnight.
        let bedtimeMinutes: Double
        let latencyMinutes: Double?
        let nextAsleepMinutes: Double?
        /// Confounders. Optional: a day missing one can still be matched,
        /// just less tightly.
        let isWeekend: Bool
        let priorNightAsleepMinutes: Double?
        let shortfallMinutes: Double?
        let timeZoneIdentifier: String
    }

    /// How long the nap was.
    ///
    /// The boundaries are the two places the physiology is commonly held to
    /// change rather than round numbers: below roughly a quarter of an hour
    /// there is little consolidated sleep to speak of, and beyond roughly
    /// half an hour a nap starts reaching slow-wave sleep, which is where
    /// sleep inertia and a displaced night both come from. Naps between them
    /// are the deliberate short nap.
    enum Duration: String, Hashable, Sendable, CaseIterable {
        case brief, short, long

        static func forMinutes(_ minutes: Double) -> Duration {
            switch minutes {
            case ..<15: .brief
            case 15..<35: .short
            default: .long
            }
        }

        /// Written as a noun phrase so it reads inside a sentence: "your
        /// 15–35 minute naps before 3 PM", not "your 15–35 minutes naps".
        var phrase: String {
            switch self {
            case .brief: "naps under 15 minutes"
            case .short: "15–35 minute naps"
            case .long: "naps over 35 minutes"
            }
        }
    }

    enum Timing: String, Hashable, Sendable, CaseIterable {
        case early, late

        static func forHour(_ hour: Double) -> Timing {
            hour < lateAfternoonHour ? .early : .late
        }

        var label: String {
            switch self {
            case .early: "before 3 PM"
            case .late: "after 3 PM"
            }
        }
    }

    /// Where the afternoon stops being early.
    static let lateAfternoonHour = 15.0

    struct Bucket: Hashable, Sendable {
        let duration: Duration
        let timing: Timing
        /// "15–35 minute naps before 3 PM".
        var phrase: String { "\(duration.phrase) \(timing.label)" }
    }

    struct Finding: Hashable, Sendable, Identifiable {
        let bucket: Bucket?
        let sentence: String
        let sampleCount: Int
        /// Median of each pair's own bedtime difference, in minutes.
        /// Positive means later on the nap day.
        let medianBedtimeShiftMinutes: Double?
        let confidence: MetricConfidence

        var id: String {
            bucket.map { "\($0.duration.rawValue)-\($0.timing.rawValue)" } ?? "none"
        }
    }

    /// Matched pairs needed before a bucket is reported.
    static let minimumSamples = 6

    /// How far apart two bedtimes must sit before the difference is worth
    /// naming, in minutes.
    ///
    /// Twenty, matching `SleepAutopilot.maximumNightlyShift`: a shift smaller
    /// than the most a bedtime may deliberately move in one night is not
    /// something to report as an association.
    static let meaningfulShiftMinutes = 20.0

    static func findings(from days: [Observation]) -> [Finding] {
        let napDays = days.filter { $0.nap != nil }
        let controls = days.filter { $0.nap == nil }

        guard napDays.count >= minimumSamples else {
            return [Finding(
                bucket: nil,
                sentence: "Zoon has \(napDays.count) logged nap day\(napDays.count == 1 ? "" : "s"). Associations with tonight start after \(minimumSamples).",
                sampleCount: napDays.count,
                medianBedtimeShiftMinutes: nil,
                confidence: .insufficient
            )]
        }
        guard controls.count >= minimumSamples else {
            return [Finding(
                bucket: nil,
                sentence: "Zoon needs days without a nap to compare against, and has \(controls.count) so far.",
                sampleCount: controls.count,
                medianBedtimeShiftMinutes: nil,
                confidence: .insufficient
            )]
        }

        var findings: [Finding] = []

        for duration in Duration.allCases {
            for timing in Timing.allCases {
                let bucket = Bucket(duration: duration, timing: timing)
                let exposed = napDays.filter { day in
                    guard let nap = day.nap else { return false }
                    return Duration.forMinutes(nap.minutes) == duration
                        && Timing.forHour(nap.startHour) == timing
                }
                guard exposed.count >= minimumSamples else { continue }
                guard let pairs = matchedPairs(exposed: exposed, controls: controls),
                      pairs.count >= minimumSamples,
                      let median = Statistics.median(pairs.map(\.bedtimeShiftMinutes))
                else { continue }

                findings.append(Finding(
                    bucket: bucket,
                    sentence: sentence(bucket: bucket, shift: median),
                    sampleCount: pairs.count,
                    medianBedtimeShiftMinutes: median,
                    confidence: pairs.count >= 12 ? .moderate : .low
                ))
            }
        }

        guard !findings.isEmpty else {
            return [Finding(
                bucket: nil,
                sentence: "Your naps have not yet grouped into a kind Zoon has enough comparable days to say anything about. It will keep watching.",
                sampleCount: napDays.count,
                medianBedtimeShiftMinutes: nil,
                confidence: .low
            )]
        }
        // Largest movement first, and a bucket that moved nothing is still
        // worth showing: "made no difference" is the answer most people are
        // actually looking for.
        return findings.sorted { abs($0.medianBedtimeShiftMinutes ?? 0) > abs($1.medianBedtimeShiftMinutes ?? 0) }
    }

    // MARK: - Internals

    private struct Pair: Hashable {
        /// Circular difference, nap day minus matched day. Positive is later.
        let bedtimeShiftMinutes: Double
    }

    /// Greedy nearest-neighbour matching without replacement, so a handful of
    /// conveniently similar control days cannot back several nap days at once
    /// and inflate the count.
    private static func matchedPairs(
        exposed: [Observation],
        controls: [Observation]
    ) -> [Pair]? {
        var pool = controls
        var pairs: [Pair] = []

        for day in exposed.sorted(by: { $0.date < $1.date }) {
            guard let (index, distance) = bestMatch(for: day, in: pool), distance < 3.0 else {
                continue
            }
            let control = pool[index]
            pairs.append(Pair(
                // Circular, so a 23:50 nap-day bedtime against a 00:10
                // control is twenty minutes earlier rather than twenty-three
                // hours and forty minutes.
                bedtimeShiftMinutes: Statistics.circularDifference(
                    day.bedtimeMinutes, control.bedtimeMinutes
                )
            ))
            pool.remove(at: index)
        }
        return pairs.isEmpty ? nil : pairs
    }

    private static func bestMatch(
        for day: Observation,
        in pool: [Observation]
    ) -> (index: Int, distance: Double)? {
        var best: (index: Int, distance: Double)?
        for (index, candidate) in pool.enumerated() {
            // Hard: a weekend day is not comparable to a working one, and a
            // day in another timezone is a travel day whatever else it was.
            guard day.isWeekend == candidate.isWeekend else { continue }
            guard day.timeZoneIdentifier == candidate.timeZoneIdentifier else { continue }

            // A confounder that cannot be compared is charged a fixed penalty
            // rather than skipped -- the same rule `JournalCorrelator` applies
            // and for the same reason: skipping it makes a candidate Zoon
            // knows *less* about score better, so the matcher preferentially
            // picks the days it understands least.
            var distance = 0.0
            distance += gap(day.priorNightAsleepMinutes, candidate.priorNightAsleepMinutes, scale: 90)
            distance += gap(day.shortfallMinutes, candidate.shortfallMinutes, scale: 90)

            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best
    }

    private static func gap(_ lhs: Double?, _ rhs: Double?, scale: Double) -> Double {
        guard let lhs, let rhs else { return 1 }
        return abs(lhs - rhs) / scale
    }

    private static func sentence(bucket: Bucket, shift: Double) -> String {
        guard abs(shift) >= meaningfulShiftMinutes else {
            return "Your \(bucket.phrase) have usually been followed by bedtimes close to your normal window."
        }
        let direction = shift > 0 ? "later" : "earlier"
        let magnitude = SleepNightFeatures.formatMinutes(abs(shift))
        return "Your \(bucket.phrase) have been associated with bedtimes about \(magnitude) \(direction) than on comparable days without one. An association in your own data, not a cause."
    }
}
