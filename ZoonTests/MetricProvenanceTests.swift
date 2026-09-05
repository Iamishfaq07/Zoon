import XCTest

/// Per-metric provenance: which device actually wrote each number.
///
/// The bug these exist for is quiet and plausible-looking. Physiology is
/// averaged over the night's asleep intervals with no source predicate, so on
/// a wrist wearing a Garmin and an Apple Watch the HRV average is correct and
/// its attribution is not -- and `SourceCoverage` credited it to whichever
/// source wrote the sleep samples. Nothing about the screen looked wrong.
final class MetricProvenanceTests: XCTestCase {

    private let garmin = MeasurementSource(
        name: "Garmin", bundleIdentifier: "com.garmin.connect.mobile"
    )
    private let appleWatch = MeasurementSource(
        name: "Ishfaq's Apple Watch", bundleIdentifier: "com.apple.health.ABC123"
    )

    private func sources(
        hrvFrom hrv: MeasurementSource,
        everythingElseFrom other: MeasurementSource
    ) -> NightMeasurementSources {
        NightMeasurementSources([
            .hrv: [hrv],
            .heartRate: [other],
            .respiratoryRate: [other],
            .bloodOxygen: [other],
            .sleepStages: [other]
        ])
    }

    private func garminNights(
        _ count: Int,
        hrvWrittenBy hrvSource: MeasurementSource?,
        startingDaysAgo offset: Int = 1
    ) -> [SleepNightFeatures] {
        (0..<count).map { index in
            Fixture.night(
                daysAgo: offset + index,
                sourceName: garmin.name,
                sourceBundleIdentifier: garmin.bundleIdentifier,
                measurementSources: hrvSource.map {
                    sources(hrvFrom: $0, everythingElseFrom: garmin)
                } ?? .empty
            )
        }
    }

    // MARK: - Item 5: the metric arrives, from someone else

    func testHRVWrittenByAnotherWatchIsNotCreditedToTheSleepSource() throws {
        let nights = garminNights(20, hrvWrittenBy: appleWatch)
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: garmin.name,
                bundleIdentifier: garmin.bundleIdentifier
            )
        )
        let hrv = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })

        // The value is there on every night -- that part was never wrong.
        XCTAssertEqual(hrv.availability, .usually)
        // But the Garmin did not produce it.
        XCTAssertEqual(hrv.attribution, .anotherSource([appleWatch.name]))
        XCTAssertTrue(hrv.isSuppliedElsewhere)
        XCTAssertEqual(
            hrv.attributionNote,
            "Arriving from \(appleWatch.name), not from this watch."
        )
        XCTAssertEqual(report.suppliedElsewhere.map(\.quantity), [.hrv])

        // Something the Garmin does write says nothing at all.
        let heartRate = try XCTUnwrap(report.entries.first { $0.quantity == .heartRate })
        XCTAssertEqual(heartRate.attribution, .thisSource)
        XCTAssertNil(heartRate.attributionNote)
    }

    func testAMetricWrittenByBothIsReportedAsShared() throws {
        var nights = garminNights(10, hrvWrittenBy: garmin)
        nights += garminNights(10, hrvWrittenBy: appleWatch, startingDaysAgo: 11)

        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: garmin.name,
                bundleIdentifier: garmin.bundleIdentifier,
                window: 40
            )
        )
        let hrv = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(hrv.attribution, .shared([appleWatch.name]))
        XCTAssertFalse(hrv.isSuppliedElsewhere)
        XCTAssertEqual(hrv.attributionNote, "Some nights from \(appleWatch.name).")
    }

    /// The claim this whole change exists to stop making.
    func testHistoryWithoutProvenanceSaysNothingRatherThanGuessing() throws {
        let nights = garminNights(20, hrvWrittenBy: nil)
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: garmin.name,
                bundleIdentifier: garmin.bundleIdentifier
            )
        )
        for entry in report.entries {
            XCTAssertEqual(
                entry.attribution, .unknown,
                "\(entry.quantity.rawValue) claimed a writer from history that recorded none"
            )
            XCTAssertNil(entry.attributionNote)
        }
        XCTAssertTrue(report.suppliedElsewhere.isEmpty)
    }

    /// Below the bar, one stray night must not reassign a metric.
    func testTooFewAttributedNightsStayUnknown() throws {
        var nights = garminNights(20, hrvWrittenBy: nil)
        nights += garminNights(
            SourceCoverage.minimumAttributedNights - 1,
            hrvWrittenBy: appleWatch,
            startingDaysAgo: 21
        )

        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: nights,
                sourceName: garmin.name,
                bundleIdentifier: garmin.bundleIdentifier,
                window: 40
            )
        )
        let hrv = try XCTUnwrap(report.entries.first { $0.quantity == .hrv })
        XCTAssertEqual(hrv.attribution, .unknown)
    }

    // MARK: - Item 6: identity is the bundle identifier, not the name

    func testARenamedWatchIsStillTheSameWatch() throws {
        // Same device, renamed halfway through the window. Matching on the
        // display name would split this into two sources of ten nights each,
        // both below the reporting threshold, and the screen would go blank
        // at the exact moment nothing about the data changed.
        let before = (1...10).map {
            Fixture.night(
                daysAgo: $0,
                sourceName: "Ishfaq's Apple Watch",
                sourceBundleIdentifier: appleWatch.bundleIdentifier
            )
        }
        let after = (11...20).map {
            Fixture.night(
                daysAgo: $0,
                sourceName: "Apple Watch Ultra",
                sourceBundleIdentifier: appleWatch.bundleIdentifier
            )
        }
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: before + after,
                sourceName: "Apple Watch Ultra",
                bundleIdentifier: appleWatch.bundleIdentifier
            )
        )
        XCTAssertEqual(report.nightsConsidered, 20)
    }

    func testTwoDevicesSharingADisplayNameAreNotMerged() throws {
        let mine = (1...15).map {
            Fixture.night(
                daysAgo: $0,
                sourceName: "Apple Watch",
                sourceBundleIdentifier: "com.apple.health.MINE"
            )
        }
        let theirs = (1...15).map {
            Fixture.night(
                daysAgo: $0,
                sourceName: "Apple Watch",
                sourceBundleIdentifier: "com.apple.health.THEIRS"
            )
        }
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: mine + theirs,
                sourceName: "Apple Watch",
                bundleIdentifier: "com.apple.health.MINE",
                window: 40
            )
        )
        XCTAssertEqual(report.nightsConsidered, 15)
    }

    func testNightsWithNoBundleIdentifierStillMatchByName() throws {
        // Everything stored before the extractor started passing the
        // identifier through. Stranding that history would empty the screen
        // for every existing install until a full re-sync.
        let legacy = (1...20).map { Fixture.night(daysAgo: $0, sourceName: "Garmin") }
        let report = try XCTUnwrap(
            SourceCoverage.report(
                nights: legacy,
                sourceName: "Garmin",
                bundleIdentifier: garmin.bundleIdentifier
            )
        )
        XCTAssertEqual(report.nightsConsidered, 20)
    }

    // MARK: - Item 7: the sensor, not the arithmetic

    func testANewInstallsTemperatureSensorIsNotReportedAsAbsent() throws {
        // Readings every night, no deltas: the baseline needs about a week of
        // history, so the first days of any install look exactly like this.
        // Judging the sensor by the delta called a working sensor missing.
        let nights = (1...20).map {
            Fixture.night(
                daysAgo: $0,
                wristTempDeltaC: nil,
                sourceName: "Apple Watch",
                wristTempMeasured: true
            )
        }
        let report = try XCTUnwrap(
            SourceCoverage.report(nights: nights, sourceName: "Apple Watch")
        )
        let temp = try XCTUnwrap(report.entries.first { $0.quantity == .wristTemperature })
        XCTAssertEqual(temp.availability, .usually)
        XCTAssertFalse(report.missing.contains { $0.quantity == .wristTemperature })
    }

    func testAWatchThatNeverMeasuresTemperatureStillReportsItMissing() throws {
        let nights = (1...20).map {
            Fixture.night(
                daysAgo: $0,
                wristTempDeltaC: nil,
                sourceName: "Apple Watch",
                wristTempMeasured: false
            )
        }
        let report = try XCTUnwrap(
            SourceCoverage.report(nights: nights, sourceName: "Apple Watch")
        )
        XCTAssertTrue(report.missing.contains { $0.quantity == .wristTemperature })
    }

    // MARK: - The record itself

    func testUnrecordedProvenanceIsUnknownAndNotDenial() {
        let recorded = NightMeasurementSources([.hrv: [appleWatch]])

        // Recorded, and not this source: a definite no.
        XCTAssertEqual(
            recorded.wasWritten(
                by: garmin.bundleIdentifier, orNamed: garmin.name, for: .hrv
            ),
            false
        )
        // Never recorded: no answer at all. Collapsing this into `false` is
        // exactly the mistake -- it would report every pre-provenance night as
        // proof the watch does not write the metric.
        XCTAssertNil(
            recorded.wasWritten(
                by: garmin.bundleIdentifier, orNamed: garmin.name, for: .bloodOxygen
            )
        )
        XCTAssertNil(recorded.sources(for: .bloodOxygen))
    }

    func testIdentityMatchesOnBundleIdentifierBeforeName() {
        let recorded = NightMeasurementSources([.hrv: [appleWatch]])
        // Renamed device, same identifier.
        XCTAssertEqual(
            recorded.wasWritten(by: appleWatch.bundleIdentifier, orNamed: "Renamed", for: .hrv),
            true
        )
        // No identifier to go on, so the name has to carry it.
        XCTAssertEqual(
            recorded.wasWritten(by: nil, orNamed: appleWatch.name, for: .hrv),
            true
        )
    }

    func testProvenanceSurvivesTheStorageRoundTrip() throws {
        let original = NightMeasurementSources([.hrv: [appleWatch], .heartRate: [garmin]])
        let data = try XCTUnwrap(original.encoded)
        XCTAssertEqual(NightMeasurementSources.decode(data), original)

        // An empty record stores nothing rather than an empty blob, so a
        // column that is nil and one that is an empty map cannot drift apart.
        XCTAssertNil(NightMeasurementSources.empty.encoded)
        XCTAssertEqual(NightMeasurementSources.decode(nil), .empty)
        XCTAssertEqual(NightMeasurementSources.decode(Data("not json".utf8)), .empty)
    }

    func testProvenanceSurvivesTheNightRoundTrip() throws {
        let night = Fixture.night(
            sourceName: garmin.name,
            sourceBundleIdentifier: garmin.bundleIdentifier,
            measurementSources: NightMeasurementSources([.hrv: [appleWatch]])
        )
        let decoded = try JSONDecoder().decode(
            SleepNightFeatures.self, from: JSONEncoder().encode(night)
        )
        XCTAssertEqual(decoded.measurementSources, night.measurementSources)
        XCTAssertEqual(decoded.sourceBundleIdentifier, garmin.bundleIdentifier)
        XCTAssertEqual(decoded.wristTempMeasured, night.wristTempMeasured)
    }

    func testNamesReadAsProse() {
        XCTAssertEqual(SourceCoverage.list([]), "")
        XCTAssertEqual(SourceCoverage.list(["Oura"]), "Oura")
        XCTAssertEqual(SourceCoverage.list(["Oura", "Garmin"]), "Oura and Garmin")
        XCTAssertEqual(
            SourceCoverage.list(["Oura", "Garmin", "Whoop"]),
            "Oura, Garmin and Whoop"
        )
    }
}
