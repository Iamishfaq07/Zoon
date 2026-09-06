import XCTest

/// What a watch actually provides, measured rather than assumed.
///
/// The rule these tests exist to hold: a capability claim must come from
/// counting what arrived. A brand table would let the app describe a metric
/// it never receives, which is the failure mode `SourceCoverage` exists to
/// prevent.
final class SourceCoverageTests: XCTestCase {

    /// A night from a named source, with the metrics a caller wants present.
    private func night(
        daysAgo: Int,
        source: String,
        staged: Bool = true,
        hrv: Double? = 55,
        restingHR: Double? = 54,
        respiratory: Double? = 14,
        spO2: Double? = 96,
        wristTemp: Double? = 0.1
    ) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: daysAgo,
            avgHRV: hrv,
            restingHeartRate: restingHR,
            avgRespiratoryRate: respiratory,
            wristTempDeltaC: wristTemp,
            avgSpO2: spO2,
            sourceName: source,
            staged: staged
        )
    }

    // MARK: - Not enough to say

    /// "Absent" and "you installed the app on Tuesday" are different claims,
    /// and only one of them is about the watch.
    func testTooFewNightsReportsNothing() {
        let nights = (0..<3).map { night(daysAgo: $0, source: "Garmin") }
        XCTAssertNil(SourceCoverage.report(nights: nights, sourceName: "Garmin"))
    }

    /// Nights from a different watch say nothing about this one.
    func testNightsFromAnotherSourceDoNotCount() {
        let mine = (0..<3).map { night(daysAgo: $0, source: "Garmin") }
        let theirs = (3..<20).map { night(daysAgo: $0, source: "Apple Watch") }
        XCTAssertNil(SourceCoverage.report(nights: mine + theirs, sourceName: "Garmin"))
    }

    // MARK: - Measuring what arrived

    /// The case the whole feature is for: a watch that supplies sleep and
    /// heart rate but never HRV.
    func testAMetricThatNeverArrivesIsReportedAsNeverProvided() throws {
        let nights = (0..<14).map { night(daysAgo: $0, source: "Garmin", hrv: nil) }
        let report = try XCTUnwrap(
            SourceCoverage.report(nights: nights, sourceName: "Garmin")
        )

        let hrv = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(hrv.availability, .never)
        XCTAssertEqual(hrv.nightsWithValue, 0)
        XCTAssertTrue(report.missing.contains { $0.quantity == .hrv })
        XCTAssertFalse(report.providesEverything)

        // And says nothing false about the ones that did arrive.
        let respiratory = try XCTUnwrap(
            report.entries.first { $0.quantity == .respiratoryRate }
        )
        XCTAssertEqual(respiratory.availability, .usually)
    }

    func testASourceProvidingEverythingHasNothingMissing() throws {
        let nights = (0..<14).map { night(daysAgo: $0, source: "Apple Watch") }
        let report = try XCTUnwrap(
            SourceCoverage.report(nights: nights, sourceName: "Apple Watch")
        )
        XCTAssertTrue(report.providesEverything, "missing: \(report.missing.map(\.quantity))")
    }

    /// A patchy metric is a wear-time story, not a capability. Calling it
    /// "most nights" would make an unreliable signal sound dependable.
    func testAPatchyMetricIsSometimesNotUsually() throws {
        let withHRV = (0..<5).map { night(daysAgo: $0, source: "Garmin") }
        let withoutHRV = (5..<14).map { night(daysAgo: $0, source: "Garmin", hrv: nil) }
        let report = try XCTUnwrap(
            SourceCoverage.report(nights: withHRV + withoutHRV, sourceName: "Garmin")
        )

        let hrv = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(hrv.availability, .sometimes)
        XCTAssertEqual(hrv.nightsWithValue, 5)
    }

    /// An undifferentiated "asleep" block is not a hypnogram. Counting it as
    /// stage coverage would promise a chart the person cannot be shown.
    func testUnstagedSleepDoesNotCountAsStageCoverage() throws {
        let nights = (0..<14).map { night(daysAgo: $0, source: "Garmin", staged: false) }
        let report = try XCTUnwrap(
            SourceCoverage.report(nights: nights, sourceName: "Garmin")
        )

        let stages = try XCTUnwrap(report.entries.first { $0.quantity == .sleepStages })
        XCTAssertEqual(stages.availability, .never)
    }

    // MARK: - Naming

    func testASourceIsNamedFromItsBundleIdentifier() throws {
        let nights = (0..<14).map { night(daysAgo: $0, source: "Garmin Connect") }
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: "Garmin Connect",
                bundleIdentifier: "com.garmin.connect.mobile"
            )
        )
        XCTAssertEqual(report.source, .garmin)
        XCTAssertEqual(report.source.possessivePhrase, "your Garmin")
    }

    // MARK: - Absent for different reasons

    /// A Garmin cannot write sleeping wrist temperature because HealthKit has
    /// no vendor-writable type for it. Reporting that as a gap in the watch
    /// would send someone hunting for a setting that does not exist.
    func testAppleOnlyMetricsAreSeparatedFromActionableGaps() throws {
        let nights = (0..<14).map {
            night(daysAgo: $0, source: "Garmin", hrv: nil, wristTemp: nil)
        }
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: "Garmin",
                bundleIdentifier: "com.garmin.connect.mobile"
            )
        )

        XCTAssertEqual(report.missingBecauseAppleOnly.map(\.quantity), [.wristTemperature])
        XCTAssertTrue(report.missingFromSource.contains { $0.quantity == .hrv })
        XCTAssertFalse(report.missingFromSource.contains { $0.quantity == .wristTemperature })
    }

    /// For an Apple source the same absence *is* actionable -- an Apple Watch
    /// that never wrote a wrist temperature is one that was not worn to bed,
    /// or is too old for the sensor.
    func testForAnAppleSourceTheSameGapStaysActionable() throws {
        let nights = (0..<14).map {
            night(daysAgo: $0, source: "Apple Watch", wristTemp: nil)
        }
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: "Apple Watch",
                bundleIdentifier: "com.apple.health.ABC"
            )
        )

        XCTAssertTrue(report.missingBecauseAppleOnly.isEmpty)
        XCTAssertTrue(report.missingFromSource.contains { $0.quantity == .wristTemperature })
    }

    // MARK: - Who actually wrote it (V10 item 1)

    private func source(_ name: String) -> MeasurementSource {
        MeasurementSource(name: name, bundleIdentifier: "com.\(name.lowercased()).health")
    }

    /// A night whose HRV was written by exactly these sources.
    private func hrvNight(daysAgo: Int, sleepSource: String, hrvWriters: [String]) -> SleepNightFeatures {
        Fixture.night(
            daysAgo: daysAgo,
            sourceName: sleepSource,
            sourceBundleIdentifier: "com.\(sleepSource.lowercased()).health",
            measurementSources: NightMeasurementSources([.hrv: hrvWriters.map(source)])
        )
    }

    private func hrvEntry(
        sleepSource: String = "Garmin",
        hrvWriters: [String],
        nights: Int = 10
    ) throws -> SourceCoverage.Entry {
        let history = (0..<nights).map {
            hrvNight(daysAgo: $0, sleepSource: sleepSource, hrvWriters: hrvWriters)
        }
        let report = try XCTUnwrap(SourceCoverage.report(
            nights: history,
            sourceName: sleepSource,
            bundleIdentifier: "com.\(sleepSource.lowercased()).health"
        ))
        return try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
    }

    func testOnlyTheTargetSourceWroteIt() throws {
        let entry = try hrvEntry(hrvWriters: ["Garmin"])
        XCTAssertEqual(entry.attribution, .thisSource)
        XCTAssertTrue(entry.otherSourceNames.isEmpty)
        XCTAssertEqual(entry.nightsSharedWithOthers, 0)
        XCTAssertEqual(entry.nightsExclusiveToThisSource, 10)
    }

    func testOnlyAnotherSourceWroteIt() throws {
        let entry = try hrvEntry(hrvWriters: ["Apple Watch"])
        XCTAssertEqual(entry.attribution, .anotherSource(["Apple Watch"]))
        XCTAssertTrue(entry.isSuppliedElsewhere)
    }

    /// **The regression.** Both devices wrote the HRV on every night. The
    /// previous implementation collected other writers only on nights the
    /// target wrote nothing, so this reported `.thisSource` -- "your Garmin
    /// provides HRV" about samples an Apple Watch also supplied.
    func testBothSourcesWroteItOnTheSameNights() throws {
        let entry = try hrvEntry(hrvWriters: ["Garmin", "Apple Watch"])
        XCTAssertEqual(entry.attribution, .shared(["Apple Watch"]))
        XCTAssertEqual(entry.nightsFromThisSource, 10)
        XCTAssertEqual(entry.nightsSharedWithOthers, 10)
        XCTAssertEqual(entry.nightsExclusiveToThisSource, 0)
        XCTAssertNotEqual(entry.attribution, .thisSource,
                          "a co-written metric must never read as this source's alone")
    }

    func testThreeWritersAreAllNamed() throws {
        let entry = try hrvEntry(hrvWriters: ["Garmin", "Apple Watch", "Oura"])
        XCTAssertEqual(entry.attribution, .shared(["Apple Watch", "Oura"]))
    }

    /// A second device worn only some nights is a different claim from one
    /// worn throughout, and the copy has to be able to tell them apart.
    func testPartialSharingIsCountedSeparately() throws {
        let both = (0..<6).map { hrvNight(daysAgo: $0, sleepSource: "Garmin", hrvWriters: ["Garmin", "Apple Watch"]) }
        let solo = (6..<10).map { hrvNight(daysAgo: $0, sleepSource: "Garmin", hrvWriters: ["Garmin"]) }
        let report = try XCTUnwrap(SourceCoverage.report(
            nights: both + solo, sourceName: "Garmin", bundleIdentifier: "com.garmin.health"
        ))
        let entry = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })

        XCTAssertEqual(entry.attribution, .shared(["Apple Watch"]))
        XCTAssertEqual(entry.nightsFromThisSource, 10)
        XCTAssertEqual(entry.nightsSharedWithOthers, 6)
        XCTAssertEqual(entry.nightsExclusiveToThisSource, 4)
        XCTAssertEqual(entry.attributionNote,
                       "Also written by Apple Watch on 6 of 10 attributed nights.")
    }

    func testFullSharingSaysEveryNight() throws {
        let entry = try hrvEntry(hrvWriters: ["Garmin", "Apple Watch"])
        XCTAssertEqual(entry.attributionNote,
                       "Also written by Apple Watch on every night Zoon could attribute.")
    }

    /// History recorded before per-metric provenance existed. Saying nothing
    /// is the correct output; assuming the sleep source wrote everything is
    /// the assumption that was wrong in the first place.
    func testNightsWithNoRecordedProvenanceSayNothing() throws {
        let history = (0..<10).map {
            Fixture.night(daysAgo: $0, sourceName: "Garmin", sourceBundleIdentifier: "com.garmin.health")
        }
        let report = try XCTUnwrap(SourceCoverage.report(
            nights: history, sourceName: "Garmin", bundleIdentifier: "com.garmin.health"
        ))
        let entry = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(entry.attribution, .unknown)
        XCTAssertNil(entry.attributionNote)
    }

    /// Too few attributed nights to name a writer: one night of a second
    /// device left charging on the nightstand must not reassign a metric.
    func testTooFewAttributedNightsStaysUnknown() throws {
        let attributed = (0..<3).map {
            hrvNight(daysAgo: $0, sleepSource: "Garmin", hrvWriters: ["Garmin", "Apple Watch"])
        }
        let bare = (3..<10).map {
            Fixture.night(daysAgo: $0, sourceName: "Garmin", sourceBundleIdentifier: "com.garmin.health")
        }
        let report = try XCTUnwrap(SourceCoverage.report(
            nights: attributed + bare, sourceName: "Garmin", bundleIdentifier: "com.garmin.health"
        ))
        let entry = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(entry.attribution, .unknown)
    }

    /// Two devices sharing a display name are still two devices. Matching
    /// prefers the bundle identifier precisely so a rename cannot merge them.
    func testSameDisplayNameDifferentBundlesAreDifferentSources() throws {
        let writers = [
            MeasurementSource(name: "Watch", bundleIdentifier: "com.apple.health"),
            MeasurementSource(name: "Watch", bundleIdentifier: "com.garmin.health")
        ]
        let history = (0..<10).map { index in
            Fixture.night(
                daysAgo: index,
                sourceName: "Watch",
                sourceBundleIdentifier: "com.garmin.health",
                measurementSources: NightMeasurementSources([.hrv: writers])
            )
        }
        let report = try XCTUnwrap(SourceCoverage.report(
            nights: history, sourceName: "Watch", bundleIdentifier: "com.garmin.health"
        ))
        let entry = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(entry.attribution, .shared(["Watch"]),
                       "the other bundle is a separate writer even under the same name")
        XCTAssertEqual(entry.nightsSharedWithOthers, 10)
    }
}
