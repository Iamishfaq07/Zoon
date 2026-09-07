import XCTest

final class ExperimentDesignTests: XCTestCase {

    private let calendar = Calendar.current

    // MARK: - Never ask for more of a harm

    /// The rule the V10 spec states outright, and the defect that existed
    /// before it: the experiment picker offered "Doing more of it" for every
    /// behaviour, alcohol and nicotine included.
    func testNoHarmfulExposureCanBeTestedInTheIncreasingDirection() {
        for tag in [BehaviorTag.alcohol, .nicotine, .cannabis, .caffeineLate, .sleepAid] {
            XCTAssertEqual(tag.exposureControl, .reduceOnly, "\(tag.rawValue)")
            XCTAssertFalse(tag.testableDirections.contains(.pursue),
                           "\(tag.rawValue) must never be proposed as something to do more of")
            XCTAssertTrue(tag.testableDirections.contains(.avoid))
            XCTAssertNotNil(tag.refusal(for: .pursue))
            XCTAssertNil(tag.refusal(for: .avoid))
        }
    }

    /// Being unwell is not a condition anybody assigns themselves. Neither
    /// direction is offered, which is different from offering one.
    func testBehavioursNobodyChoosesAreNotTestableInEitherDirection() {
        for tag in [BehaviorTag.sick, .travelled, .stressfulDay] {
            XCTAssertEqual(tag.exposureControl, .notChosen, "\(tag.rawValue)")
            XCTAssertTrue(tag.testableDirections.isEmpty)
            XCTAssertNotNil(tag.refusal(for: .avoid))
            XCTAssertNotNil(tag.refusal(for: .pursue))
        }
    }

    /// The rule must not have quietly closed off ordinary choices too. If
    /// nothing were testable in both directions the picker would be empty and
    /// the safety rule would have eaten the feature.
    func testOrdinaryChoicesRemainTestableBothWays() {
        let both = BehaviorTag.allCases.filter { $0.testableDirections.count == 2 }
        XCTAssertGreaterThan(both.count, 10, "the safety rule should not empty the picker")
        XCTAssertTrue(both.contains(.readBeforeBed))
        XCTAssertTrue(both.contains(.coolRoom))
    }

    /// Every tag must land in exactly one state, so a tag added later cannot
    /// slip through with no rule applied to it.
    func testEveryBehaviourHasAnExposureRule() {
        for tag in BehaviorTag.allCases {
            switch tag.exposureControl {
            case .eitherDirection: XCTAssertEqual(tag.testableDirections.count, 2, "\(tag.rawValue)")
            case .reduceOnly: XCTAssertEqual(tag.testableDirections, [.avoid], "\(tag.rawValue)")
            case .notChosen: XCTAssertTrue(tag.testableDirections.isEmpty, "\(tag.rawValue)")
            }
        }
    }

    // MARK: - Designs and schedules

    func testEachDesignHasTheBlocksItsNameClaims() {
        XCTAssertEqual(ExperimentDesign.beforeAfter.blocks(seed: 1), [.with])
        XCTAssertEqual(ExperimentDesign.ab.blocks(seed: 1), [.without, .with])
        XCTAssertEqual(ExperimentDesign.ba.blocks(seed: 1), [.with, .without])
        XCTAssertEqual(ExperimentDesign.abba.blocks(seed: 1), [.without, .with, .with, .without])
    }

    /// Balanced, then shuffled. Four free draws land on a single arm about
    /// one time in eight, and an experiment with one arm is not one.
    func testARandomisedCrossoverAlwaysGetsTwoOfEachArm() {
        for seed in UInt64(0)..<50 {
            let blocks = ExperimentDesign.randomisedCrossover.blocks(seed: seed)
            XCTAssertEqual(blocks.count, 4)
            XCTAssertEqual(blocks.filter { $0 == .with }.count, 2, "seed \(seed)")
            XCTAssertEqual(blocks.filter { $0 == .without }.count, 2, "seed \(seed)")
        }
    }

    /// It must still actually shuffle -- a "randomised" design that returns
    /// one order for every seed is a fixed design with a misleading name.
    func testTheRandomisedOrderDependsOnTheSeed() {
        let orders = Set((UInt64(0)..<50).map { ExperimentDesign.randomisedCrossover.blocks(seed: $0) })
        XCTAssertGreaterThan(orders.count, 1)
    }

    /// The same experiment must always have the same plan. A schedule that
    /// reshuffled on each read would let the assignment follow the data.
    func testTheSameSeedAlwaysProducesTheSameSchedule() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let first = ExperimentDesign.randomisedCrossover.schedule(startingOn: start, seed: 42)
        let second = ExperimentDesign.randomisedCrossover.schedule(startingOn: start, seed: 42)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(
            first.map(\.arm),
            ExperimentDesign.randomisedCrossover.schedule(startingOn: start, seed: 9).map(\.arm),
            "two seeds giving one order would mean the seed is not being used"
        )
    }

    func testAScheduleCoversEveryNightOfEveryBlockWithNoGaps() {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let schedule = ExperimentDesign.abba.schedule(startingOn: start, blockNights: 7, seed: 1)

        XCTAssertEqual(schedule.count, 28)
        XCTAssertEqual(Set(schedule.map(\.date)).count, 28, "no night may be assigned twice")
        for (previous, next) in zip(schedule, schedule.dropFirst()) {
            let days = calendar.dateComponents([.day], from: previous.date, to: next.date).day
            XCTAssertEqual(days, 1, "consecutive nights must be one calendar day apart")
        }
    }

    // MARK: - Reading a trial

    /// Builds a schedule and answers for it: `adherence` per block decides
    /// how many of that block's nights follow the plan.
    private func analyse(
        design: ExperimentDesign,
        blockNights: Int = 8,
        withValue: Double,
        withoutValue: Double,
        adherentPerBlock: Int = 8,
        unknownPerBlock: Int = 0,
        seed: UInt64 = 3
    ) -> ExperimentDesign.Outcome {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let schedule = design.schedule(startingOn: start, blockNights: blockNights, seed: seed)
        let byBlock = Dictionary(grouping: schedule, by: \.block)

        var states: [Date: JournalCorrelator.ExposureState] = [:]
        for (_, assignments) in byBlock {
            for (index, assignment) in assignments.sorted(by: { $0.date < $1.date }).enumerated() {
                if index < adherentPerBlock {
                    states[assignment.date] = assignment.arm == .with ? .yes : .no
                } else if index < adherentPerBlock + unknownPerBlock {
                    states[assignment.date] = .unknown
                } else {
                    states[assignment.date] = assignment.arm == .with ? .no : .yes
                }
            }
        }

        let arms = Dictionary(uniqueKeysWithValues: schedule.map { ($0.date, $0.arm) })
        return ExperimentDesign.analyse(
            schedule: schedule,
            value: { date in
                guard let arm = arms[date] else { return nil }
                // A tiny per-night wobble, so the medians are medians of real
                // spread rather than of one repeated number.
                let jitter = Double(calendar.component(.day, from: date) % 3) * 0.1
                return (arm == .with ? withValue : withoutValue) + jitter
            },
            exposure: { states[$0] ?? .unknown }
        )
    }

    func testAFullyAdheredCrossoverReportsTheDifferenceBetweenItsArms() throws {
        let outcome = analyse(design: .abba, withValue: 60, withoutValue: 52)
        guard case let .analysed(analysis) = outcome else {
            return XCTFail("fixture must analyse, got \(outcome)")
        }
        XCTAssertEqual(analysis.design, .abba)
        XCTAssertEqual(analysis.blocks.count, 4)
        XCTAssertEqual(analysis.difference, 8, accuracy: 0.5)
        XCTAssertEqual(analysis.adherence.nonAdherent, 0)
        XCTAssertEqual(analysis.adherence.unknown, 0)
        XCTAssertEqual(analysis.adherence.adherent, 32)
    }

    /// Two block pairs cannot support a bootstrap. Saying the interval is
    /// absent is the honest answer; producing one from two numbers would look
    /// like precision and be a restatement of the two numbers.
    func testAFourBlockTrialReportsNoIntervalAndSaysSo() throws {
        guard case let .analysed(analysis) = analyse(design: .abba, withValue: 60, withoutValue: 52) else {
            return XCTFail("fixture must analyse")
        }
        XCTAssertNil(analysis.interval)
        XCTAssertFalse(analysis.isDecisive, "no interval means nothing is decisive here")
        XCTAssertTrue(analysis.caveat.contains("not how precisely"))
    }

    /// The three counts must stay apart. A night that went the other way and
    /// a night nobody logged are different facts.
    func testAdherenceKeepsBrokenNightsAndUnloggedNightsApart() throws {
        guard case let .analysed(analysis) = analyse(
            design: .ab, blockNights: 12, withValue: 60, withoutValue: 52,
            adherentPerBlock: 8, unknownPerBlock: 2
        ) else {
            return XCTFail("fixture must analyse")
        }
        XCTAssertEqual(analysis.adherence.adherent, 16)
        XCTAssertEqual(analysis.adherence.unknown, 4)
        XCTAssertEqual(analysis.adherence.nonAdherent, 4)
        XCTAssertEqual(analysis.adherence.total, 24)
        XCTAssertEqual(analysis.adherence.sentence, "16 followed, 4 went the other way, 4 not logged")
    }

    /// A stretch that fell apart is named, not silently dropped or averaged
    /// over. Refusing is the answer.
    func testAStretchWithTooFewFollowedNightsStopsTheAnalysisByName() {
        let outcome = analyse(
            design: .ab, blockNights: 8, withValue: 60, withoutValue: 52, adherentPerBlock: 2
        )
        guard case let .unusable(reason) = outcome else {
            return XCTFail("a two-night stretch must not be read, got \(outcome)")
        }
        guard case let .blockTooThin(_, adherent, need) = reason else {
            return XCTFail("expected a thin-stretch refusal, got \(reason)")
        }
        XCTAssertEqual(adherent, 2)
        XCTAssertEqual(need, ExperimentDesign.minimumAdherentNights)
        XCTAssertFalse(reason.message.isEmpty)
    }

    func testAnEmptyScheduleIsRefusedRatherThanAnalysed() {
        let outcome = ExperimentDesign.analyse(schedule: [], value: { _ in nil }, exposure: { _ in .unknown })
        XCTAssertEqual(outcome, .unusable(.notStarted))
    }

    /// The before/after design has one assigned block, so its own caveat has
    /// to say that the comparison is history rather than a planned arm.
    func testBeforeAfterSaysItsComparisonWasNotPlanned() {
        XCTAssertFalse(ExperimentDesign.beforeAfter.isControlled)
        for design in ExperimentDesign.allCases where design != .beforeAfter {
            XCTAssertTrue(design.isControlled, "\(design.rawValue)")
        }
    }

    /// Every design must be describable to somebody deciding between them.
    func testEveryDesignExplainsItself() {
        for design in ExperimentDesign.allCases {
            XCTAssertFalse(design.label.isEmpty, "\(design.rawValue)")
            XCTAssertFalse(design.rationale.isEmpty, "\(design.rawValue)")
            XCTAssertGreaterThan(design.plannedNights(), 0)
        }
    }
}
