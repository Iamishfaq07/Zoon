import XCTest

/// Covers custom behaviours as first-class observations.
///
/// Before this they were labels for a feature that did not exist: a store, a
/// settings screen and a row of capsules on the journal that were not
/// tappable, recorded nothing, and were unknown to every engine. The storage
/// layer, as it happened, was already ready — `BehaviorObservationRecord`
/// keys on a `String` — so what was missing was an identity the rest of the
/// app could carry.
@MainActor
final class CustomBehaviorTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "com.zoon.sleep.tests.custom.\(UUID().uuidString)")!
    }

    // MARK: - Identity

    func testBuiltInIdentifiersAreUnchanged() {
        XCTAssertEqual(BehaviorTag.alcohol.behaviorID.identifier, BehaviorTag.alcohol.rawValue)
    }

    /// The point of keeping built-in identifiers bare: every observation row
    /// ever written still joins, so nothing migrates.
    func testEveryBuiltInRoundTrips() {
        for tag in BehaviorTag.allCases {
            XCTAssertEqual(BehaviorID(identifier: tag.rawValue), .builtIn(tag), tag.rawValue)
        }
    }

    func testACustomIdentifierRoundTrips() {
        let id = UUID()
        let behavior = BehaviorID.custom(id)
        XCTAssertTrue(behavior.identifier.hasPrefix(BehaviorID.customPrefix))
        XCTAssertEqual(BehaviorID(identifier: behavior.identifier), behavior)
        XCTAssertTrue(behavior.isCustom)
        XCTAssertNil(behavior.builtIn)
    }

    /// The two namespaces cannot collide: a tag raw value is a Swift case
    /// name and can never contain a colon.
    func testCustomAndBuiltInNamespacesCannotCollide() {
        for tag in BehaviorTag.allCases {
            XCTAssertFalse(tag.rawValue.contains(":"), tag.rawValue)
            XCTAssertFalse(tag.rawValue.contains("|"), tag.rawValue)
        }
        XCTAssertFalse(BehaviorID.custom(UUID()).identifier.contains("|"))
    }

    /// An identifier a future build wrote decays to "ignored" rather than
    /// failing the read.
    func testAnUnrecognisedIdentifierIsNil() {
        XCTAssertNil(BehaviorID(identifier: "somethingFromTheFuture"))
        XCTAssertNil(BehaviorID(identifier: "custom:not-a-uuid"))
    }

    func testIdentityEncodesAsAFlatString() throws {
        let behavior = BehaviorID.custom(UUID())
        let data = try JSONEncoder().encode(behavior)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "\"\(behavior.identifier)\""
        )
        XCTAssertEqual(try JSONDecoder().decode(BehaviorID.self, from: data), behavior)
    }

    // MARK: - The store

    func testCreationAndPersistence() {
        let defaults = makeDefaults()
        let store = CustomBehaviorStore(defaults: defaults)
        let created = store.add(name: "Magnesium")
        XCTAssertNotNil(created)

        let relaunched = CustomBehaviorStore(defaults: defaults)
        XCTAssertEqual(relaunched.behaviors.map(\.name), ["Magnesium"])
        XCTAssertEqual(relaunched.behaviors.first?.id, created?.id)
    }

    func testDuplicateNamesAreRefusedCaseInsensitively() {
        let store = CustomBehaviorStore(defaults: makeDefaults())
        XCTAssertNotNil(store.add(name: "Magnesium"))
        XCTAssertNil(store.add(name: "  magnesium "))
        XCTAssertEqual(store.behaviors.count, 1)
    }

    func testAnEmptyNameIsRefused() {
        let store = CustomBehaviorStore(defaults: makeDefaults())
        XCTAssertNil(store.add(name: "   "))
        XCTAssertTrue(store.behaviors.isEmpty)
    }

    func testDeactivatingKeepsTheDefinition() {
        let store = CustomBehaviorStore(defaults: makeDefaults())
        let behavior = store.add(name: "Prayer")!
        store.toggle(behavior)
        XCTAssertEqual(store.behaviors.first?.isActive, false)
        XCTAssertEqual(store.behaviors.count, 1)
    }

    func testDeleteEverythingLeavesNothingInDefaults() {
        let defaults = makeDefaults()
        let store = CustomBehaviorStore(defaults: defaults)
        store.add(name: "Magnesium")
        store.deleteAll()
        XCTAssertTrue(CustomBehaviorStore(defaults: defaults).behaviors.isEmpty)
        XCTAssertNil(defaults.data(forKey: "zoon.customBehaviors.v1"))
    }

    // MARK: - The catalogue

    func testDeactivatedSignalsStopBeingOfferedButStayAnalysable() {
        let active = CustomBehavior(name: "Magnesium")
        let retired = CustomBehavior(name: "Old habit", isActive: false)
        let catalog = BehaviorCatalog(custom: [active, retired])

        XCTAssertTrue(catalog.loggable.contains(active.behaviorID))
        XCTAssertFalse(catalog.loggable.contains(retired.behaviorID),
                       "a switched-off signal should stop being asked about")
        XCTAssertTrue(catalog.analysable.contains(retired.behaviorID),
                      "switching a prompt off must not retract the nights already logged")
    }

    /// A deleted definition leaves its observations behind — they are the
    /// person's data — so the catalogue has to be able to name an id it no
    /// longer holds. A bare UUID on screen is not a name.
    func testADeletedSignalStillGetsAName() {
        let catalog = BehaviorCatalog(custom: [])
        let label = catalog.label(for: .custom(UUID()))
        XCTAssertFalse(label.contains("-"), label)
        XCTAssertFalse(label.isEmpty)
    }

    func testBuiltInLabelsComeFromTheTag() {
        XCTAssertEqual(
            BehaviorCatalog.builtInOnly.label(for: .builtIn(.alcohol)),
            BehaviorTag.alcohol.label
        )
    }

    // MARK: - Observations and evidence

    private func observation(
        daysAgo: Int,
        answers: BehaviorAnswers,
        efficiency: Double,
        isWeekend: Bool = false
    ) -> JournalCorrelator.Observation {
        JournalCorrelator.Observation(
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            tags: [],
            answers: answers,
            recoveryPercent: 70,
            sleepPerformance: 80,
            deepMinutes: 80,
            remMinutes: 90,
            efficiency: efficiency,
            wakeCount: 2,
            isWeekend: isWeekend,
            sleepDebtMinutes: 30,
            bedtimeHour: -1,
            alcoholicBeverages: nil,
            lateCaffeineMg: nil,
            measuredTimeZoneShift: false
        )
    }

    private func answers(_ behavior: BehaviorID, _ state: BehaviorObservationState) -> BehaviorAnswers {
        BehaviorAnswers([behavior.identifier: state])
    }

    func testACustomAnswerResolvesThroughExposureState() {
        let behavior = BehaviorID.custom(UUID())
        let yes = observation(daysAgo: 0, answers: answers(behavior, .yes), efficiency: 90)
        let no = observation(daysAgo: 1, answers: answers(behavior, .no), efficiency: 90)
        let silent = observation(daysAgo: 2, answers: .none, efficiency: 90)

        XCTAssertEqual(yes.exposureState(for: behavior), .yes)
        XCTAssertEqual(no.exposureState(for: behavior), .no)
        XCTAssertEqual(silent.exposureState(for: behavior), .unknown)
    }

    /// A custom behaviour is exactly as known as the person said it was.
    /// There is no HealthKit sample for "magnesium" and no derived rule that
    /// could invent one, so none of the measured upgrades may apply to it.
    func testNoMeasuredUpgradeCanTouchACustomBehaviour() {
        let behavior = BehaviorID.custom(UUID())
        let night = JournalCorrelator.Observation(
            date: .now, tags: [.alcohol, .travelled], answers: .none,
            recoveryPercent: 70, sleepPerformance: 80, deepMinutes: 80, remMinutes: 90,
            efficiency: 90, wakeCount: 2, isWeekend: false, sleepDebtMinutes: 30,
            bedtimeHour: -1, alcoholicBeverages: 3, lateCaffeineMg: 120,
            measuredTimeZoneShift: true
        )
        XCTAssertEqual(night.exposureState(for: behavior), .unknown)
        XCTAssertEqual(night.exposureState(for: .alcohol), .yes)
    }

    /// The end-to-end claim: a custom behaviour logged enough times produces
    /// a matched-pair finding through the same engine as a built-in one.
    func testACustomBehaviourProducesAMatchedPairFinding() throws {
        let magnesium = CustomBehavior(name: "Magnesium")
        let catalog = BehaviorCatalog(custom: [magnesium])
        let id = magnesium.behaviorID

        var observations: [JournalCorrelator.Observation] = []
        for index in 0..<10 {
            observations.append(observation(
                daysAgo: index * 2, answers: answers(id, .yes), efficiency: 94
            ))
            observations.append(observation(
                daysAgo: index * 2 + 1, answers: answers(id, .no), efficiency: 82
            ))
        }

        let findings = JournalCorrelator().findings(from: observations, catalog: catalog)
        let finding = try XCTUnwrap(findings.first { $0.behavior == id })
        XCTAssertEqual(finding.label, "Magnesium")
        XCTAssertNil(finding.tag, "a custom behaviour has no built-in tag")
        XCTAssertGreaterThan(finding.delta, 0)

        // And it does not appear at all without a catalogue that names it,
        // which is what stops an engine analysing identities it cannot label.
        XCTAssertTrue(
            JournalCorrelator().findings(from: observations).isEmpty,
            "the default catalogue is built-ins only"
        )
    }

    /// Progress has to be visible before the threshold is cleared, or a
    /// diligently logged signal is silent in a way indistinguishable from
    /// never having been used.
    func testACustomBehaviourAppearsWhileStillLearning() throws {
        let prayer = CustomBehavior(name: "Prayer")
        let catalog = BehaviorCatalog(custom: [prayer])
        let observations = (0..<3).map { index in
            observation(daysAgo: index, answers: answers(prayer.behaviorID, .yes), efficiency: 90)
        }
        let learning = JournalCorrelator().stillLearning(from: observations, catalog: catalog)
        let row = try XCTUnwrap(learning.first { $0.behavior == prayer.behaviorID })
        XCTAssertEqual(row.loggedNights, 3)
        XCTAssertEqual(row.label, "Prayer")
    }

    /// The same counting fix for built-ins: `stillLearning` used to count the
    /// legacy tag set, which never held a custom identifier, so every custom
    /// signal sat at zero however often it had been logged.
    func testAnAnsweredBuiltInAlsoCountsTowardLearning() throws {
        let observations = (0..<3).map { index in
            observation(
                daysAgo: index,
                answers: BehaviorAnswers([BehaviorTag.magnesium.rawValue: .yes]),
                efficiency: 90
            )
        }
        let learning = JournalCorrelator().stillLearning(from: observations)
        XCTAssertNotNil(learning.first { $0.tag == .magnesium })
    }

    // MARK: - Backup

    /// Observations already travelled in the archive, because that record is
    /// identifier-keyed and carries custom rows without knowing it. The
    /// definitions did not, so a restore produced a history of answers about
    /// signals the app could no longer name.
    func testDefinitionsRestoreFromABackup() {
        let source = CustomBehaviorStore(defaults: makeDefaults())
        let magnesium = source.add(name: "Magnesium")!

        let restored = CustomBehaviorStore(defaults: makeDefaults())
        XCTAssertEqual(restored.importBehaviors(source.behaviors), 1)
        XCTAssertEqual(restored.behaviors.first?.id, magnesium.id,
                       "the identity is what the restored observations are keyed by")
    }

    func testRestoringTwiceDoesNotDuplicate() {
        let source = CustomBehaviorStore(defaults: makeDefaults())
        source.add(name: "Magnesium")

        let restored = CustomBehaviorStore(defaults: makeDefaults())
        restored.importBehaviors(source.behaviors)
        XCTAssertEqual(restored.importBehaviors(source.behaviors), 0)
        XCTAssertEqual(restored.behaviors.count, 1)
    }

    /// A definition on this device wins, the same rule every other importer
    /// follows -- and a name collision must not produce two rows the person
    /// cannot tell apart.
    func testAnExistingNameIsNotRestoredOverTheTopOfItself() {
        let source = CustomBehaviorStore(defaults: makeDefaults())
        source.add(name: "Magnesium")

        let device = CustomBehaviorStore(defaults: makeDefaults())
        device.add(name: "magnesium")
        XCTAssertEqual(device.importBehaviors(source.behaviors), 0)
        XCTAssertEqual(device.behaviors.count, 1)
    }
}
