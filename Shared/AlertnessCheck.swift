import Foundation

/// The arithmetic behind the optional reaction-time check, and — more of the
/// file — the rules about when it is allowed to say anything.
///
/// **Improve, do not rebuild.** The check itself works: six trials, a median,
/// a lapse count, a self-rating. What it lacked was everything that decides
/// whether those numbers *mean* anything — the spread, the false starts, how
/// long the person had been awake, and the fact that reaction time improves
/// for the first few sessions whoever is taking it. This is that layer, kept
/// out of the view so it can be tested without tapping a circle.
///
/// **Practice is the trap this exists for.** Reaction time on a task like
/// this falls over the first few attempts because the person is learning the
/// task, not because they are sleeping better. An app that plotted session one
/// against session three would show a confident improvement it had caused
/// itself. `practiceSessions` are therefore excluded from every baseline, and
/// no trend is offered until enough sessions exist *after* them.
///
/// **One session is not a measurement of a person.** Reaction time swings with
/// time of day, caffeine, motivation, whether the phone was in a warm hand.
/// `comparison` refuses to say anything at all until there is a personal
/// baseline to say it against, and even then it compares like with like: a
/// check taken twenty minutes after waking and one taken six hours later are
/// not the same quantity, and averaging them would hide the thing the check is
/// for.
///
/// **Not a medical or fitness-for-duty instrument.** The existing screen
/// already says so; `bannedClaims` keeps the engine's own copy to it.
enum AlertnessCheck {

    /// The standard psychomotor-vigilance lapse threshold. Kept because it is
    /// the published convention rather than because this six-trial check is a
    /// PVT — it is not, and `lapseCaveat` says so wherever a lapse count is
    /// shown.
    static let lapseMilliseconds = 500.0

    /// Trials needed before a session is worth storing. Five leaves a median
    /// with something either side of it even if one trial is fumbled.
    static let minimumTrials = 5

    /// Sessions treated as learning the task rather than measuring anything.
    /// Three is the low end of what the reaction-time literature reports for
    /// this kind of simple task; taking the low end means excluding less real
    /// data, and the excluded sessions are still shown, just not counted.
    static let practiceSessions = 3

    /// Post-practice sessions needed before any comparison is offered.
    static let minimumBaselineSessions = 5

    /// How far apart two checks' time-since-waking may be and still be
    /// compared. Ninety minutes: sleep inertia clears over roughly the first
    /// hour, so a wider tolerance would compare across the steepest part of
    /// the curve.
    static let wakeWindowToleranceMinutes = 90.0

    /// A median difference smaller than this is inside the noise of a
    /// six-trial check and is not reported as anything.
    static let meaningfulDifferenceMilliseconds = 40.0

    /// Words this must never reach for. The check is a personal outcome
    /// recorded next to sleep history, not an assessment of anybody.
    static let bannedClaims = [
        "impair", "unsafe", "fit to drive", "safe to drive", "fitness for duty",
        "cognitive decline", "deficit", "abnormal", "test result", "diagnos"
    ]

    /// One completed check.
    struct Session: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var date: Date
        var medianMilliseconds: Double
        /// Interquartile range — how *consistent* the responses were. A steady
        /// 320 ms and a median of 320 ms built from 240 and 500 are the same
        /// median and not the same state, and the second is what a tired
        /// person looks like.
        /// Absent for a record written before the spread was measured. Not
        /// zero — a zero would claim a perfectly consistent run nobody
        /// observed.
        var iqrMilliseconds: Double?
        var lapses: Int
        /// Taps before the signal. Recorded rather than silently discarded:
        /// the brief asks for them, and a run of them says something a median
        /// built only from the valid trials cannot.
        var falseStarts: Int
        /// Absent for a record written before the trial count was kept.
        var trials: Int?
        /// Minutes between waking and taking the check, when the night is
        /// known. Absent rather than assumed — a check taken on a day with no
        /// recorded wake time is still a valid check, it just cannot be
        /// compared against one taken at a different point in the morning.
        var minutesSinceWaking: Double?
        var subjectiveAlertness: Int?

        init(
            id: UUID = UUID(),
            date: Date,
            medianMilliseconds: Double,
            iqrMilliseconds: Double?,
            lapses: Int,
            falseStarts: Int,
            trials: Int?,
            minutesSinceWaking: Double? = nil,
            subjectiveAlertness: Int? = nil
        ) {
            self.id = id
            self.date = date
            self.medianMilliseconds = medianMilliseconds
            self.iqrMilliseconds = iqrMilliseconds
            self.lapses = lapses
            self.falseStarts = falseStarts
            self.trials = trials
            self.minutesSinceWaking = minutesSinceWaking
            self.subjectiveAlertness = subjectiveAlertness
        }
    }

    /// Builds a session from one run, or refuses.
    ///
    /// - Parameters:
    ///   - reactions: valid trials, in seconds.
    ///   - falseStarts: taps before the signal appeared.
    ///   - wakeTime: this morning's wake time, when a night was recorded.
    static func session(
        reactions: [TimeInterval],
        falseStarts: Int = 0,
        subjectiveAlertness: Int? = nil,
        wakeTime: Date? = nil,
        date: Date = .now,
        id: UUID = UUID()
    ) -> Session? {
        guard reactions.count >= minimumTrials else { return nil }
        let milliseconds = reactions.map { $0 * 1_000 }
        guard let median = Statistics.median(milliseconds),
              let q1 = Statistics.percentile(milliseconds, 25),
              let q3 = Statistics.percentile(milliseconds, 75)
        else { return nil }

        // Only a wake time earlier the same day means anything. A wake time in
        // the future, or one from days ago because no night has been recorded
        // since, would produce a number that looks like data.
        let sinceWaking = wakeTime.flatMap { wake -> Double? in
            let minutes = date.timeIntervalSince(wake) / 60
            return (0.0...1440.0).contains(minutes) ? minutes : nil
        }

        return Session(
            id: id,
            date: date,
            medianMilliseconds: median,
            iqrMilliseconds: max(0, q3 - q1),
            lapses: milliseconds.filter { $0 >= lapseMilliseconds }.count,
            falseStarts: max(0, falseStarts),
            trials: reactions.count,
            minutesSinceWaking: sinceWaking,
            subjectiveAlertness: subjectiveAlertness.map { min(5, max(1, $0)) }
        )
    }

    /// Why a comparison is not being offered, when it is not.
    enum Withheld: Hashable, Sendable {
        /// Still learning the task. Improvement here would be practice.
        case practice(remaining: Int)
        /// Past practice, but not enough sessions to have a baseline.
        case buildingBaseline(remaining: Int)
        /// A baseline exists, but none of it was taken at a comparable point
        /// after waking.
        case noComparableTimeOfMorning

        var sentence: String {
            switch self {
            case .practice(let remaining):
                return "Reaction time improves for the first few checks while you learn the task, "
                    + "so Zoon is not reading anything into these yet. "
                    + "\(remaining.pluralized("check")) to go."
            case .buildingBaseline(let remaining):
                return "Building your own baseline. "
                    + "\(remaining.pluralized("more check")) before Zoon compares one against it."
            case .noComparableTimeOfMorning:
                return "Your earlier checks were taken at a different point after waking, "
                    + "so this one has nothing comparable to sit against."
            }
        }
    }

    struct Comparison: Hashable, Sendable {
        let sentence: String
        let baselineSessions: Int
        let baselineMedian: Double
        let differenceMilliseconds: Double
        let confidence: MetricConfidence

        var isSlower: Bool { differenceMilliseconds > 0 }
    }

    enum Outcome: Hashable, Sendable {
        case withheld(Withheld)
        case compared(Comparison)

        var comparison: Comparison? {
            if case .compared(let comparison) = self { return comparison }
            return nil
        }

        var sentence: String {
            switch self {
            case .withheld(let reason): reason.sentence
            case .compared(let comparison): comparison.sentence
            }
        }
    }

    /// What, if anything, can be said about the most recent check.
    ///
    /// - Parameter history: every stored session including `latest`, any order.
    static func evaluate(latest: Session, history: [Session]) -> Outcome {
        let ordered = history.sorted { $0.date < $1.date }
        let earlier = ordered.filter { $0.id != latest.id && $0.date <= latest.date }

        // Practice first: the count that matters is how many have been taken
        // in total, because the learning happens whether or not a baseline
        // was being built at the time.
        let completed = earlier.count + 1
        if completed < practiceSessions {
            return .withheld(.practice(remaining: practiceSessions - completed))
        }

        let baselineCandidates = Array(earlier.dropFirst(practiceSessions))
        guard baselineCandidates.count >= minimumBaselineSessions else {
            return .withheld(
                .buildingBaseline(remaining: minimumBaselineSessions - baselineCandidates.count)
            )
        }

        // Like with like. A check twenty minutes after waking and one six
        // hours later are not the same quantity; sleep inertia alone moves
        // reaction time more than most of what this is looking for.
        let comparable: [Session]
        if let sinceWaking = latest.minutesSinceWaking {
            comparable = baselineCandidates.filter {
                guard let theirs = $0.minutesSinceWaking else { return false }
                return abs(theirs - sinceWaking) <= wakeWindowToleranceMinutes
            }
        } else {
            // No wake time for either side is still like with like: both are
            // simply "a check", and the tolerance cannot be applied to a
            // number nobody has.
            comparable = baselineCandidates.filter { $0.minutesSinceWaking == nil }
        }

        guard comparable.count >= minimumBaselineSessions else {
            return .withheld(.noComparableTimeOfMorning)
        }

        guard let baseline = Statistics.median(comparable.map(\.medianMilliseconds)) else {
            return .withheld(.noComparableTimeOfMorning)
        }

        let difference = latest.medianMilliseconds - baseline
        let confidence: MetricConfidence = comparable.count >= 10 ? .high : .moderate

        let sentence: String
        if abs(difference) < meaningfulDifferenceMilliseconds {
            sentence = "About the same as your own recent checks at this point after waking."
        } else if difference > 0 {
            sentence = "\(Int(difference.rounded())) ms slower than your own recent checks "
                + "at this point after waking."
        } else {
            sentence = "\(Int(abs(difference).rounded())) ms faster than your own recent checks "
                + "at this point after waking."
        }

        return .compared(
            Comparison(
                sentence: sentence,
                baselineSessions: comparable.count,
                baselineMedian: baseline,
                differenceMilliseconds: difference,
                confidence: confidence
            )
        )
    }

    /// Said wherever a lapse count appears.
    ///
    /// A lapse is defined against a ten-minute psychomotor vigilance task. Six
    /// trials is not one, so the count is a description of this run and not a
    /// measurement of vigilance, and printing it without saying so borrows the
    /// authority of an instrument this is not.
    static let lapseCaveat =
        "A lapse here means a response over half a second. The published threshold comes from a "
        + "ten-minute task; this one is six taps, so treat the count as a description of this "
        + "check rather than a measure of vigilance."

    /// Said wherever false starts appear, and only when there were any.
    static func falseStartNote(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(count.pluralized("tap")) before the signal. These are not in the median."
    }
}
