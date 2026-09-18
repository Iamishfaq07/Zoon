import XCTest

/// Grading the stage breakdown, and the misgrade this type was written to
/// prevent.
final class StageTrustTests: XCTestCase {

    // MARK: - The ladder

    func testEachSourceGetsItsOwnLevel() {
        XCTAssertEqual(StageTrust.grade(priority: .appleWatch, hasStages: true), .watch)
        XCTAssertEqual(StageTrust.grade(priority: .thirdPartyWearable, hasStages: true), .wearable)
        XCTAssertEqual(StageTrust.grade(priority: .phoneOrManual, hasStages: true), .inferred)
    }

    /// No stages is not a quality grade. There is nothing to trust, whatever
    /// wrote the night, and an Apple Watch night with no breakdown must not
    /// come back `.watch` and imply staging that is not there.
    func testNoStagesOutranksTheSource() {
        for priority: SourcePriority? in [.appleWatch, .thirdPartyWearable, .phoneOrManual, nil] {
            XCTAssertEqual(
                StageTrust.grade(priority: priority, hasStages: false), .unstaged,
                "\(String(describing: priority)) with no stages"
            )
        }
    }

    /// A night from before the priority was carried knows only that something
    /// wrote stages. Guessing upward is the failure this type exists to stop,
    /// so the floor is the level that promises least.
    func testAnUnknownSourceDoesNotGetTheBenefitOfTheDoubt() {
        let graded = StageTrust.grade(priority: nil, hasStages: true)
        XCTAssertEqual(graded, .inferred)
        XCTAssertLessThan(graded, .wearable)
        XCTAssertFalse(graded.supportsStageFigures)
    }

    /// Stage minutes are presented as measurements only where something
    /// measured them. A schedule did not.
    func testOnlyMeasuredStagesAreShownAsFigures() {
        XCTAssertTrue(StageTrust.watch.supportsStageFigures)
        XCTAssertTrue(StageTrust.wearable.supportsStageFigures)
        XCTAssertFalse(StageTrust.inferred.supportsStageFigures)
        XCTAssertFalse(StageTrust.unstaged.supportsStageFigures)
    }

    func testTheLadderIsOrdered() {
        XCTAssertLessThan(StageTrust.unstaged, .inferred)
        XCTAssertLessThan(StageTrust.inferred, .wearable)
        XCTAssertLessThan(StageTrust.wearable, .watch)
    }

    // MARK: - The trap

    /// The whole reason the priority is carried instead of re-derived.
    ///
    /// An Apple Watch and an iPhone both write sleep under
    /// `com.apple.health`. Only `productType` separates them, and that string
    /// lives on the HealthKit sample -- not on `SleepNightFeatures`. Anything
    /// that tried to grade a night from the bundle identifier it holds would
    /// classify every Watch night as phone-or-manual and tell people their
    /// best stage data was their least trustworthy.
    ///
    /// This asserts the misclassification is real, so nobody later "simplifies"
    /// the plumbing away and reintroduces it.
    func testClassifyingWithoutTheHardwareStringMisgradesAppleWatch() {
        let withHardware = SourcePriority.classify(
            hardwareVersion: "Watch7,4",
            bundleIdentifier: "com.apple.health.ABCDEF",
            sourceName: "Ishfaq's Apple Watch"
        )
        XCTAssertEqual(withHardware, .appleWatch)

        // The same source, graded from only what a feature record holds.
        let withoutHardware = SourcePriority.classify(
            hardwareVersion: nil,
            bundleIdentifier: "com.apple.health.ABCDEF",
            sourceName: "Ishfaq's Apple Watch"
        )
        XCTAssertEqual(
            withoutHardware, .phoneOrManual,
            "if this ever returns .appleWatch the carried priority may be dropped"
        )

        XCTAssertEqual(StageTrust.grade(priority: withHardware, hasStages: true), .watch)
        XCTAssertEqual(StageTrust.grade(priority: withoutHardware, hasStages: true), .inferred)
    }

    // MARK: - On a night

    func testANightExposesItsOwnTrust() {
        let watchNight = Fixture.night(daysAgo: 1, stageSourcePriority: .appleWatch)
        XCTAssertTrue(watchNight.hasStageBreakdown, "fixture should stage this night")
        XCTAssertEqual(watchNight.stageTrust, .watch)

        let typedIn = Fixture.night(daysAgo: 1, stageSourcePriority: .phoneOrManual)
        XCTAssertEqual(typedIn.stageTrust, .inferred)

        // Presence and provenance are different questions, and a night can
        // answer the first yes and the second badly.
        XCTAssertEqual(watchNight.hasStageBreakdown, typedIn.hasStageBreakdown)
        XCTAssertNotEqual(watchNight.stageTrust, typedIn.stageTrust)
    }

    /// Nights recorded before this field existed still load, and grade at the
    /// honest floor rather than crashing or claiming a source.
    func testAnOlderNightStillGrades() {
        let night = Fixture.night(daysAgo: 1)
        XCTAssertNil(night.stageSourcePriority)
        XCTAssertEqual(night.stageTrust, .inferred)
    }

    // MARK: - Surviving the store

    /// The assertion that makes the rest of this file mean anything.
    ///
    /// The priority is derived from the HealthKit sample's hardware string,
    /// which exists only at extraction. `SleepNightRecord` is what the app
    /// actually reads nights back from, so without a column for it every
    /// night on every screen would return `nil` and grade at the floor --
    /// a trust layer that compiles, passes its unit tests, and is a no-op in
    /// the app.
    func testThePrioritySurvivesTheRoundTrip() {
        let night = Fixture.night(daysAgo: 1, stageSourcePriority: .appleWatch)
        let record = SleepNightRecord(features: night)

        XCTAssertEqual(record.stageSourcePriority, .appleWatch, "not written")
        XCTAssertEqual(
            record.features().stageSourcePriority, .appleWatch,
            "written but not read back"
        )
        XCTAssertEqual(record.features().stageTrust, .watch)
    }

    /// A re-sync that cannot work out the source must not erase one already
    /// recorded -- the same rule the hypnogram follows, for the same reason.
    /// `nil` means this extraction did not know, not that the night changed
    /// hands.
    func testALossyResyncDoesNotEraseAKnownSource() {
        let record = SleepNightRecord(
            features: Fixture.night(daysAgo: 1, stageSourcePriority: .appleWatch)
        )
        record.update(from: Fixture.night(daysAgo: 1, stageSourcePriority: nil), absoluteWristTempC: nil)
        XCTAssertEqual(record.stageSourcePriority, .appleWatch, "a blank re-sync erased it")
    }

    /// And a re-sync that does know overwrites, so a night written before the
    /// column existed is corrected the first time it is refreshed rather than
    /// staying at the floor forever.
    func testAResyncThatKnowsFillsInAnOlderNight() {
        let record = SleepNightRecord(
            features: Fixture.night(daysAgo: 1, stageSourcePriority: nil)
        )
        XCTAssertEqual(record.features().stageTrust, .inferred)

        record.update(from: Fixture.night(daysAgo: 1, stageSourcePriority: .appleWatch), absoluteWristTempC: nil)
        XCTAssertEqual(record.features().stageTrust, .watch)
    }

    // MARK: - Wording

    /// The provenance lines describe the source, never the accuracy. Every
    /// level here is a consumer classifier, and none of them is a laboratory.
    func testProvenanceNeverClaimsAccuracy() {
        for trust in [StageTrust.unstaged, .inferred, .wearable, .watch] {
            let line = trust.provenance
            XCTAssertFalse(line.isEmpty, "\(trust)")
            for banned in ["accurate", "clinical", "validated", "precise", "proven"] {
                XCTAssertFalse(
                    line.lowercased().contains(banned),
                    "\(trust) claims \(banned): \(line)"
                )
            }
        }
    }
}
