import XCTest

final class SensorTruthTests: XCTestCase {

    // MARK: - Propagation

    /// The rule that makes this more than a glossary. Sleep efficiency is
    /// straightforward arithmetic, which looks like the solid end of the
    /// scale -- until you notice one of the two numbers it divides is
    /// itself a model's output.
    func testArithmeticOnAnEstimateIsAnEstimate() {
        let fact = SensorTruth.fact(for: .sleepEfficiency)

        XCTAssertEqual(fact.declaredProvenance, .derived, "it really is just a division")
        XCTAssertEqual(fact.provenance, .inferred, "but one of its inputs is a guess")
        XCTAssertTrue(fact.isWeakenedByItsInputs)
        XCTAssertEqual(fact.weakenedBy, [.timeAsleep])
    }

    /// Sleep debt is arithmetic on two estimates, and propagation has to
    /// reach through `sleepNeed`, which is itself derived from time asleep.
    func testPropagationReachesThroughAnIntermediateQuantity() {
        let fact = SensorTruth.fact(for: .sleepDebt)

        XCTAssertEqual(fact.declaredProvenance, .derived)
        XCTAssertEqual(fact.provenance, .inferred)
        XCTAssertEqual(Set(fact.weakenedBy), [.timeAsleep, .sleepNeed])
    }

    /// A number read straight off a sensor has nothing to be dragged down
    /// by.
    func testAMeasuredQuantityKeepsItsProvenance() {
        for quantity in [SensorTruth.Quantity.heartRate, .hrv, .wristTemperature, .bloodOxygen] {
            let fact = SensorTruth.fact(for: quantity)
            XCTAssertEqual(fact.provenance, .measured, quantity.label)
            XCTAssertFalse(fact.isWeakenedByItsInputs, quantity.label)
            XCTAssertTrue(fact.weakenedBy.isEmpty, quantity.label)
        }
    }

    /// A quantity with no inputs must not be capped by an accidental
    /// default -- an empty input list means nothing constrains it.
    func testAQuantityWithNoInputsIsUncapped() {
        XCTAssertTrue(SensorTruth.Quantity.timeInBed.inputs.isEmpty, "precondition")
        XCTAssertEqual(SensorTruth.fact(for: .timeInBed).provenance, .derived)
    }

    /// The invariant, checked across everything rather than case by case:
    /// nothing is ever presented as a stronger kind of claim than its own
    /// declaration, or than the weakest thing it was built from.
    func testNoQuantityOutranksItsDeclarationOrItsInputs() {
        for quantity in SensorTruth.Quantity.allCases {
            let resolved = SensorTruth.provenance(of: quantity)
            XCTAssertLessThanOrEqual(resolved, quantity.declaredProvenance, quantity.label)
            for input in quantity.inputs {
                XCTAssertLessThanOrEqual(
                    resolved, SensorTruth.provenance(of: input),
                    "\(quantity.label) outranks its input \(input.label)"
                )
            }
        }
    }

    // MARK: - The classifications themselves

    /// The one the whole type exists for. A deep-sleep figure and a wrist
    /// temperature render in the same font, and only one of them was
    /// measured.
    func testSleepStagesAreAnEstimateAndSayWhy() {
        let fact = SensorTruth.fact(for: .sleepStages)

        XCTAssertEqual(fact.provenance, .inferred)
        XCTAssertTrue(fact.quantity.limit.lowercased().contains("sleep lab"), fact.quantity.limit)
        XCTAssertTrue(fact.quantity.limit.lowercased().contains("trend"), fact.quantity.limit)
    }

    /// Consumer pulse oximetry is measured, but the limit has to be stated
    /// plainly rather than left to the reader.
    func testBloodOxygenIsMeasuredButNotMedical() {
        XCTAssertEqual(SensorTruth.fact(for: .bloodOxygen).provenance, .measured)
        let limit = SensorTruth.Quantity.bloodOxygen.limit.lowercased()
        XCTAssertTrue(limit.contains("not a medical measurement"), limit)
        XCTAssertTrue(limit.contains("skin tone"), limit)
    }

    func testWhatSomeoneLoggedIsSelfReported() {
        XCTAssertEqual(SensorTruth.fact(for: .behaviourTags).provenance, .selfReported)
    }

    func testTimeAsleepIsAnEstimateNotAMeasurement() {
        XCTAssertEqual(SensorTruth.fact(for: .timeAsleep).provenance, .inferred)
    }

    // MARK: - Ordering

    func testProvenanceOrdersWeakestToStrongest() {
        XCTAssertLessThan(SensorTruth.Provenance.selfReported, .inferred)
        XCTAssertLessThan(SensorTruth.Provenance.inferred, .derived)
        XCTAssertLessThan(SensorTruth.Provenance.derived, .measured)
    }

    /// The numbers most in need of a caveat are the ones worth reading
    /// first.
    func testTheListLeadsWithTheSoftestClaims() {
        let provenances = SensorTruth.all.map(\.provenance)
        XCTAssertEqual(provenances, provenances.sorted())
        XCTAssertEqual(SensorTruth.all.first?.provenance, .selfReported)
        XCTAssertEqual(SensorTruth.all.last?.provenance, .measured)
    }

    func testOrderingIsStable() {
        XCTAssertEqual(SensorTruth.all.map(\.id), SensorTruth.all.map(\.id))
    }

    func testEveryQuantityAppearsExactlyOnce() {
        XCTAssertEqual(SensorTruth.all.count, SensorTruth.Quantity.allCases.count)
        XCTAssertEqual(Set(SensorTruth.all.map(\.id)).count, SensorTruth.all.count)
    }

    // MARK: - Filtering for one screen

    func testFactsForAScreenKeepTheSoftestFirstOrder() {
        let facts = SensorTruth.facts(for: [.hrv, .sleepStages, .heartRate])

        XCTAssertEqual(facts.count, 3)
        XCTAssertEqual(facts.first?.quantity, .sleepStages, "the estimate leads")
        XCTAssertEqual(facts.map(\.provenance), facts.map(\.provenance).sorted())
    }

    func testFactsForNothingIsEmpty() {
        XCTAssertTrue(SensorTruth.facts(for: []).isEmpty)
    }

    // MARK: - Copy

    /// A limit left blank would read as "no limit", which is never true of
    /// anything here.
    func testEveryQuantityStatesWhatItIsAndWhatItCannotTellYou() {
        for quantity in SensorTruth.Quantity.allCases {
            XCTAssertFalse(quantity.label.isEmpty, quantity.rawValue)
            XCTAssertFalse(quantity.whatItIs.isEmpty, quantity.rawValue)
            XCTAssertFalse(quantity.limit.isEmpty, quantity.rawValue)
        }
    }

    func testEveryProvenanceHasItsOwnWording() {
        let labels = SensorTruth.Provenance.allCases.map(\.label)
        let explanations = SensorTruth.Provenance.allCases.map(\.explanation)

        XCTAssertEqual(Set(labels).count, SensorTruth.Provenance.allCases.count)
        XCTAssertEqual(Set(explanations).count, SensorTruth.Provenance.allCases.count)
    }

    /// An estimate must never be described with the vocabulary of a
    /// measurement.
    func testTheEstimateWordingNeverClaimsAMeasurement() {
        let text = (SensorTruth.Provenance.inferred.label
            + " " + SensorTruth.Provenance.inferred.explanation).lowercased()

        XCTAssertTrue(text.contains("guess"), text)
        XCTAssertFalse(text.contains("measured"), text)
        XCTAssertFalse(text.contains("recorded"), text)
    }

    func testTheSentenceExplainsADowngradeWhenThereIsOne() {
        let downgraded = SensorTruth.fact(for: .sleepEfficiency).sentence
        let plain = SensorTruth.fact(for: .hrv).sentence

        XCTAssertTrue(downgraded.contains("Shown as an estimate because"), downgraded)
        XCTAssertFalse(plain.contains("Shown as an estimate"), plain)
        XCTAssertTrue(plain.contains(SensorTruth.Quantity.hrv.limit), plain)
    }
}
