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
}
