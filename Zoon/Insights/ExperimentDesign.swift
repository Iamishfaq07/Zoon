import Foundation

/// How a trial is laid out over time, decided before it starts.
///
/// ## Why a before/after is the weakest thing that counts as an experiment
///
/// `GuidedExperiment.summarize` compares the fortnight before the trial with
/// the trial itself. Everything the person did differently in that second
/// fortnight is inside the estimate: the season changed, work got easier,
/// they started paying attention. A before/after cannot separate the
/// behaviour from the passage of time, because the behaviour and the time
/// are the same variable.
///
/// A crossover can. Going A then B then B then A, in an order fixed in
/// advance, puts each condition on both sides of the middle -- so a trend
/// that runs steadily through the trial adds the same amount to both arms
/// and cancels out of the difference. That is the entire point of AB/BA, and
/// it costs nothing but the order.
///
/// ## Assigned, not chosen
///
/// The schedule is generated when the trial is created and does not change.
/// This matters more than the design does. Somebody deciding each evening
/// whether tonight is an A night or a B night will, without meaning to, put
/// the easy nights in one arm -- and a trial whose assignment correlates
/// with how the day went is measuring the day. `schedule(startingOn:)`
/// produces every night's condition up front, and
/// `randomisedCrossover` draws its block order from a seed stored with the
/// experiment so the same trial always has the same plan.
///
/// ## What this does not do
///
/// It does not blind anybody, and it cannot. The person knows which arm they
/// are in, which is unavoidable for a behaviour they have to perform, and it
/// means expectation is inside every estimate here. It is why
/// `Analysis.caveat` says so and why none of this language ever reaches
/// "proves".
enum ExperimentDesign: String, Codable, CaseIterable, Sendable, Identifiable {

    /// One block of the behaviour, compared with the fortnight before it.
    /// What V1 does; kept because it is the only design that works when
    /// somebody has already started.
    case beforeAfter
    /// A block without, then a block with.
    case ab
    /// A block with, then a block without. Worth offering because somebody
    /// already doing the thing should not have to stop, start and stop again
    /// to take part.
    case ba
    /// Without, with, with, without. The order that cancels a steady trend.
    case abba
    /// Four blocks in an order drawn from the experiment's own seed, before
    /// the trial starts.
    case randomisedCrossover

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beforeAfter: "Before and after"
        case .ab: "Two stretches"
        case .ba: "Two stretches, other way round"
        case .abba: "Four stretches"
        case .randomisedCrossover: "Four stretches, shuffled"
        }
    }

    /// What it buys, in a sentence a person can act on.
    var rationale: String {
        switch self {
        case .beforeAfter:
            "Compares the stretch before you started with the stretch after. Simplest, and the least able to tell your change apart from everything else that changed."
        case .ab:
            "A stretch without, then a stretch with. Clearer than before-and-after, because both stretches are planned."
        case .ba:
            "A stretch with, then a stretch without -- the same test, starting from what you already do."
        case .abba:
            "Without, with, with, without. If something in your life is drifting steadily through the trial, this order cancels it out of the answer."
        case .randomisedCrossover:
            "Four stretches in an order Zoon fixes before you start, so neither of you can put the easy weeks in one half."
        }
    }

    // MARK: - Arms

    enum Arm: String, Codable, Hashable, Sendable {
        /// The behaviour is not being performed.
        case without
        /// The behaviour is being performed.
        case with

        var label: String { self == .with ? "With" : "Without" }
    }

    /// The blocks, in order. `beforeAfter` has one planned block: its
    /// comparison stretch is history, not a block anybody was assigned.
    func blocks(seed: UInt64) -> [Arm] {
        switch self {
        case .beforeAfter: [.with]
        case .ab: [.without, .with]
        case .ba: [.with, .without]
        case .abba: [.without, .with, .with, .without]
        case .randomisedCrossover: Self.shuffledBlocks(seed: seed)
        }
    }

    /// Two of each, in an order drawn from `seed`.
    ///
    /// Two of each rather than four free draws: a free draw produces all-with
    /// or all-without about one time in eight, and an experiment with one arm
    /// is not one. Balanced-then-shuffled keeps the randomisation and removes
    /// the outcome that wastes six weeks.
    static func shuffledBlocks(seed: UInt64) -> [Arm] {
        var generator = SeededGenerator(seed: seed)
        var blocks: [Arm] = [.without, .without, .with, .with]
        blocks.shuffle(using: &generator)
        return blocks
    }

    /// Whether both arms are assigned by this design, rather than one of them
    /// being read off the past.
    var isControlled: Bool { self != .beforeAfter }

    // MARK: - Scheduling

    /// One night, and which arm it belongs to.
    struct Assignment: Hashable, Sendable, Identifiable {
        let date: Date
        let arm: Arm
        /// Which block of the design it falls in, from zero.
        let block: Int

        var id: Date { date }
    }

    /// Every night of the trial, decided now.
    ///
    /// - Parameter blockNights: nights per block. Defaults to
    ///   `GuidedExperiment.minimumPeriodNights`, the floor that engine
    ///   already enforces on any window it will summarise -- a block shorter
    ///   than that produces a median nobody should read.
    func schedule(
        startingOn start: Date,
        blockNights: Int = GuidedExperiment.minimumPeriodNights,
        seed: UInt64,
        calendar: Calendar = .current
    ) -> [Assignment] {
        let arms = blocks(seed: seed)
        var assignments: [Assignment] = []
        var day = calendar.startOfDay(for: start)

        for (index, arm) in arms.enumerated() {
            for _ in 0..<blockNights {
                assignments.append(Assignment(date: day, arm: arm, block: index))
                // Through the calendar, never by adding 86,400 seconds: a
                // trial that runs across a clock change would otherwise start
                // landing an hour into the previous day and quietly reassign
                // its own nights.
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            }
        }
        return assignments
    }

    /// How long the whole thing takes, in nights.
    func plannedNights(blockNights: Int = GuidedExperiment.minimumPeriodNights, seed: UInt64 = 0) -> Int {
        blocks(seed: seed).count * blockNights
    }

    // MARK: - Adherence

    /// What actually happened on the nights of one arm.
    ///
    /// Three counts, not one rate. The spec asks for adherent, non-adherent
    /// and unknown kept apart, and they are three different facts: a night
    /// that went the other way is evidence the trial was not followed; a
    /// night nobody logged is evidence of nothing at all. Collapsing them
    /// into "83% adherent" throws away which of the two happened.
    struct Adherence: Hashable, Sendable {
        var adherent = 0
        var nonAdherent = 0
        var unknown = 0

        var total: Int { adherent + nonAdherent + unknown }

        /// Out of every assigned night, not out of the logged ones. A night
        /// that was never logged is a night the trial cannot show was
        /// followed, which is what this number is for.
        var rate: Double? {
            guard total > 0 else { return nil }
            return Double(adherent) / Double(total)
        }

        var sentence: String {
            "\(adherent) followed, \(nonAdherent) went the other way, \(unknown) not logged"
        }
    }

    /// Nights required in each arm before the arm is analysed at all.
    static let minimumAdherentNights = GuidedExperiment.minimumPeriodNights

    /// Block pairs needed before an interval is offered. Three, because a
    /// bootstrap over two numbers resamples two numbers.
    static let minimumBlockPairsForInterval = 3

    // MARK: - Analysis

    /// One arm's block, after the fact.
    struct BlockResult: Hashable, Sendable, Identifiable {
        let block: Int
        let arm: Arm
        let adherence: Adherence
        /// Median outcome over the arm's *adherent* nights. nil when there
        /// were too few of them -- see `minimumAdherentNights`.
        let median: Double?

        var id: Int { block }
    }

    enum Unusable: Hashable, Sendable {
        case notStarted
        case blockTooThin(block: Int, adherent: Int, need: Int)
        case oneArmOnly

        var message: String {
            switch self {
            case .notStarted:
                "This trial has not produced enough logged nights yet."
            case let .blockTooThin(block, adherent, need):
                "Stretch \(block + 1) has \(adherent) night\(adherent == 1 ? "" : "s") that followed the plan and needs \(need). "
                    + "Zoon will not read a stretch that thin."
            case .oneArmOnly:
                "Only one side of this trial produced usable nights, so there is nothing to compare it against."
            }
        }
    }

    /// The interval as a named type rather than a tuple: a tuple cannot be
    /// given `Hashable` or `Sendable` conformance, and `Analysis` needs both.
    struct Interval: Hashable, Sendable {
        let lower: Double
        let upper: Double
    }

    struct Analysis: Hashable, Sendable {
        let design: ExperimentDesign
        let blocks: [BlockResult]
        /// With minus without, over the whole trial. Positive means the
        /// outcome was higher on the nights the behaviour was performed --
        /// higher, not better; which of those it is depends on the metric.
        let difference: Double
        /// nil when there were fewer than `minimumBlockPairsForInterval`
        /// pairs of blocks. Stated as absent rather than filled with a
        /// bootstrap over two numbers, which would look like an interval and
        /// be a restatement of the two numbers.
        let interval: Interval?

        var adherence: Adherence {
            blocks.reduce(into: Adherence()) { total, block in
                total.adherent += block.adherence.adherent
                total.nonAdherent += block.adherence.nonAdherent
                total.unknown += block.adherence.unknown
            }
        }

        /// True only when an interval exists and excludes no change. Without
        /// an interval there is no such thing as decisive here, and saying so
        /// is the honest answer for a four-block trial.
        var isDecisive: Bool {
            guard let interval else { return false }
            return interval.lower > 0 || interval.upper < 0
        }

        var caveat: String {
            var lines = [
                "You knew which stretch you were in, so what you expected to happen is inside this result too. "
                    + "Nothing here removes that."
            ]
            if interval == nil {
                lines.append(
                    "With this many stretches Zoon can report the difference but not how precisely it is known. "
                        + "Read it as what happened, not as how much it would happen again."
                )
            }
            if design == .beforeAfter {
                lines.append(
                    "Both stretches were not planned: the comparison is the time before you started, "
                        + "so anything else that changed at the same time is in here as well."
                )
            }
            return lines.joined(separator: " ")
        }
    }

    enum Outcome: Hashable, Sendable {
        case analysed(Analysis)
        case unusable(Unusable)
    }

    /// Reads a finished or running trial against the schedule it was given.
    ///
    /// - Parameters:
    ///   - schedule: the assignments made when the trial started. Nights not
    ///     in it are not part of the trial, however they were logged.
    ///   - value: the outcome for one night, or nil when it has none.
    ///   - exposure: whether the behaviour actually happened that night --
    ///     the journal's own yes/no/unknown, not a guess.
    static func analyse(
        schedule: [Assignment],
        value: (Date) -> Double?,
        exposure: (Date) -> JournalCorrelator.ExposureState,
        calendar: Calendar = .current
    ) -> Outcome {
        guard !schedule.isEmpty else { return .unusable(.notStarted) }

        let grouped = Dictionary(grouping: schedule, by: \.block)
        var results: [BlockResult] = []

        for block in grouped.keys.sorted() {
            let assignments = grouped[block] ?? []
            guard let arm = assignments.first?.arm else { continue }

            var adherence = Adherence()
            var adherentValues: [Double] = []

            for assignment in assignments {
                switch (exposure(assignment.date), arm) {
                case (.yes, .with), (.no, .without):
                    adherence.adherent += 1
                    if let value = value(assignment.date) { adherentValues.append(value) }
                case (.unknown, _):
                    adherence.unknown += 1
                default:
                    adherence.nonAdherent += 1
                }
            }

            results.append(
                BlockResult(
                    block: block,
                    arm: arm,
                    adherence: adherence,
                    median: adherentValues.count >= minimumAdherentNights
                        ? Statistics.median(adherentValues)
                        : nil
                )
            )
        }

        // A block whose adherent nights never reached the floor stops the
        // analysis by name, so the person is told which stretch let go rather
        // than being shown a blank.
        if let thin = results.first(where: { $0.median == nil }) {
            return .unusable(
                .blockTooThin(
                    block: thin.block,
                    adherent: thin.adherence.adherent,
                    need: minimumAdherentNights
                )
            )
        }

        let withMedians = results.filter { $0.arm == .with }.compactMap(\.median)
        let withoutMedians = results.filter { $0.arm == .without }.compactMap(\.median)
        guard !withMedians.isEmpty, !withoutMedians.isEmpty else { return .unusable(.oneArmOnly) }

        guard let withMedian = Statistics.median(withMedians),
              let withoutMedian = Statistics.median(withoutMedians) else {
            return .unusable(.oneArmOnly)
        }

        // Pair each `with` block with the `without` block nearest it in time,
        // so a difference is taken inside a stretch of the person's life
        // rather than across the whole trial. This is what makes the ABBA
        // order worth anything: its pairs straddle the middle in opposite
        // directions, so a steady drift enters one pair positively and the
        // other negatively and leaves the median of the pairs alone.
        var differences: [Double] = []
        for withBlock in results where withBlock.arm == .with {
            guard let median = withBlock.median else { continue }
            let nearest = results
                .filter { $0.arm == .without && $0.median != nil }
                .min { abs($0.block - withBlock.block) < abs($1.block - withBlock.block) }
            if let nearest, let other = nearest.median {
                differences.append(median - other)
            }
        }

        let interval: Interval? = differences.count >= minimumBlockPairsForInterval
            ? Statistics.pairedBootstrapCI(deltas: differences)
                .map { Interval(lower: min($0.lower, $0.upper), upper: max($0.lower, $0.upper)) }
            : nil

        return .analysed(
            Analysis(
                design: designOf(results),
                blocks: results,
                difference: withMedian - withoutMedian,
                interval: interval
            )
        )
    }

    /// Recovers which design a set of block results came from, so an analysis
    /// can carry it without the caller having to pass it twice and risk the
    /// two disagreeing.
    private static func designOf(_ results: [BlockResult]) -> ExperimentDesign {
        let arms = results.sorted { $0.block < $1.block }.map(\.arm)
        switch arms {
        case [.with]: return .beforeAfter
        case [.without, .with]: return .ab
        case [.with, .without]: return .ba
        case [.without, .with, .with, .without]: return .abba
        default: return .randomisedCrossover
        }
    }
}
