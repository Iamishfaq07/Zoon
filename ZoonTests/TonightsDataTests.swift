import XCTest

/// Where each of last night's numbers came from.
///
/// The screen's job is to be believed, so the tests that matter most here are
/// the ones asserting it does *not* say things: no invented sample counts, no
/// guessed writer, no "measured" on a number this app calculated.
final class TonightsDataTests: XCTestCase {

    private let appleWatch = MeasurementSource(
        name: "Ishfaq's Apple Watch", bundleIdentifier: "com.apple.health.ABC"
    )
    private let garmin = MeasurementSource(
        name: "Garmin", bundleIdentifier: "com.garmin.connect.mobile"
    )

    private func row(
        _ quantity: SensorTruth.Quantity,
        in data: TonightsData,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TonightsData.Row {
        try XCTUnwrap(
            data.rows.first { $0.quantity == quantity },
            "no \(quantity.rawValue) row", file: file, line: line
        )
    }

    // MARK: - Time in bed: the spec's own example

    /// `timeInBedIsEstimated` has been stored since V5 and shown nowhere. For
    /// anyone on an Apple Watch alone it is always true, because the Watch
    /// writes no in-bed samples -- so the number most people see is a
    /// reconstruction and nothing said so.
    func testAnEstimatedTimeInBedSaysSoAndSaysWhy() throws {
        var night = Fixture.night()
        night.timeInBedIsEstimated = true

        let inBed = try row(.timeInBed, in: TonightsData.build(night: night))
        XCTAssertEqual(inBed.provenance, .inferred)
        let note = try XCTUnwrap(inBed.note)
        XCTAssertTrue(note.contains("did not provide"), note)
        XCTAssertTrue(note.contains("efficiency"), note)
    }

    func testAMeasuredTimeInBedMakesNoExcuses() throws {
        var night = Fixture.night()
        night.timeInBedIsEstimated = false

        let inBed = try row(.timeInBed, in: TonightsData.build(night: night))
        XCTAssertEqual(inBed.provenance, .derived)
        XCTAssertNil(inBed.note)
    }

    // MARK: - Who wrote it

    /// The provenance work exists so this screen can name the right device.
    /// A Garmin night with Apple Watch HRV must credit the Apple Watch.
    func testEachRowNamesTheDeviceThatActuallyWroteIt() throws {
        let night = Fixture.night(
            sourceName: garmin.name,
            sourceBundleIdentifier: garmin.bundleIdentifier,
            measurementSources: NightMeasurementSources([
                .sleepStages: [garmin],
                .hrv: [appleWatch]
            ])
        )
        let data = TonightsData.build(night: night)

        XCTAssertEqual(try row(.hrv, in: data).sourceNames, [appleWatch.name])
        XCTAssertEqual(try row(.timeAsleep, in: data).sourceNames, [garmin.name])
    }

    /// Nights recorded before provenance existed fall back to the sleep
    /// source rather than showing nothing -- it is the best guess available
    /// and it is what the app used to assume for everything.
    func testWithoutProvenanceItFallsBackToTheSleepSource() throws {
        let night = Fixture.night(sourceName: "Garmin")
        let data = TonightsData.build(night: night)
        XCTAssertEqual(try row(.hrv, in: data).sourceNames, ["Garmin"])
    }

    // MARK: - What it must not claim

    /// The one thing this screen cannot do honestly. Physiology averages come
    /// from HKStatisticsQuery, which returns a mean and the contributing
    /// sources but not a per-source sample count. "5 samples" would have to
    /// be invented, and an invented number on a trust screen is worse than a
    /// blank.
    func testNoRowClaimsASampleCountItCannotHave() {
        let night = Fixture.night(
            sourceName: "Apple Watch",
            measurementSources: NightMeasurementSources([.hrv: [appleWatch]])
        )
        for row in TonightsData.build(night: night).rows {
            for step in row.derivation {
                // Saying in-bed samples exist or don't is fine and true. A
                // *number* of them is what cannot be known: HKStatisticsQuery
                // returns a mean and its contributing sources, never a count.
                let words = step.lowercased().split(separator: " ").map(String.init)
                for (index, word) in words.enumerated() where word.hasPrefix("sample") {
                    let previous = index > 0 ? words[index - 1] : ""
                    XCTAssertNil(
                        Int(previous),
                        "\(row.quantity.rawValue) claims a sample count: \(step)"
                    )
                }
            }
        }
    }

    /// Wrist temperature is shown as a difference from baseline, which is
    /// this app's arithmetic over a reading -- not the reading. Labelling it
    /// "Measured" is the same confusion `wristTempMeasured` exists to keep
    /// out of source coverage.
    func testTheTemperatureDeltaIsNotPresentedAsAMeasurement() throws {
        let night = Fixture.night(wristTempDeltaC: 0.4)
        let temp = try row(.wristTemperature, in: TonightsData.build(night: night))
        XCTAssertEqual(temp.provenance, .derived)
        XCTAssertTrue(temp.derivation.contains { $0.contains("baseline") }, "\(temp.derivation)")
    }

    /// A working sensor with no baseline yet says exactly that, rather than
    /// being absent and looking like a watch that cannot measure temperature.
    func testAMeasuredTemperatureWithNoBaselineExplainsItself() throws {
        let night = Fixture.night(wristTempDeltaC: nil, wristTempMeasured: true)
        let temp = try row(.wristTemperature, in: TonightsData.build(night: night))
        XCTAssertFalse(temp.hasValue)
        XCTAssertNotNil(temp.note)
        XCTAssertTrue(try XCTUnwrap(temp.note).contains("week"), "\(temp.note ?? "")")
    }

    func testAWatchThatNeverMeasuresTemperatureGetsNoRow() {
        let night = Fixture.night(wristTempDeltaC: nil, wristTempMeasured: false)
        XCTAssertFalse(
            TonightsData.build(night: night).rows.contains { $0.quantity == .wristTemperature }
        )
    }

    // MARK: - Counts that are real

    /// Stage segments are stored, so the count is exact and worth stating.
    func testTheStageSegmentCountIsRealAndStated() throws {
        var night = Fixture.night()
        night.stageSegments = (0..<6).map { index in
            StageSegment(
                stage: .core,
                start: night.bedtime.addingTimeInterval(Double(index) * 3600),
                end: night.bedtime.addingTimeInterval(Double(index) * 3600 + 1800)
            )
        }
        let asleep = try row(.timeAsleep, in: TonightsData.build(night: night))
        XCTAssertTrue(asleep.derivation.contains { $0.contains("6 stage segments") }, "\(asleep.derivation)")
    }

    /// Averages are described by the number of asleep runs they were taken
    /// over, which is derivable from the stored timeline.
    func testPhysiologyNamesTheIntervalsItWasAveragedOver() throws {
        var night = Fixture.night()
        night.stageSegments = [
            StageSegment(stage: .core, start: night.bedtime, end: night.bedtime.addingTimeInterval(3600)),
            StageSegment(stage: .awake, start: night.bedtime.addingTimeInterval(3600), end: night.bedtime.addingTimeInterval(3900)),
            StageSegment(stage: .deep, start: night.bedtime.addingTimeInterval(3900), end: night.bedtime.addingTimeInterval(7200))
        ]
        let hrv = try row(.hrv, in: TonightsData.build(night: night))
        XCTAssertTrue(
            hrv.derivation.contains { $0.contains("2 asleep intervals") },
            "\(hrv.derivation)"
        )
    }

    /// Resting heart rate is a once-daily HealthKit figure, not an average
    /// over the night, and saying otherwise would be wrong in a way nobody
    /// could check.
    func testRestingHeartRateIsNotDescribedAsAnOvernightAverage() throws {
        let rhr = try row(.restingHeartRate, in: TonightsData.build(night: Fixture.night()))
        XCTAssertTrue(rhr.derivation.contains { $0.contains("daily resting heart rate") }, "\(rhr.derivation)")
        XCTAssertFalse(rhr.derivation.contains { $0.contains("Averaged") }, "\(rhr.derivation)")
    }

    // MARK: - Coverage

    func testCoverageIsCarriedThroughWhenThereIsEnoughHistory() throws {
        let nights = (1...20).map { Fixture.night(daysAgo: $0, sourceName: "Apple Watch") }
        let report = SourceCoverage.report(nights: nights, sourceName: "Apple Watch")
        let data = TonightsData.build(
            night: Fixture.night(sourceName: "Apple Watch"),
            coverage: report
        )
        XCTAssertEqual(try row(.hrv, in: data).coverage, .usually)
    }

    func testCoverageIsNilWithoutAReport() throws {
        let data = TonightsData.build(night: Fixture.night())
        XCTAssertNil(try row(.hrv, in: data).coverage)
    }

    /// A row with no value is not shown. `populated` is what the view walks.
    func testRowsWithoutValuesAreNotShown() {
        let night = Fixture.night(avgHRV: nil, wristTempDeltaC: nil)
        let data = TonightsData.build(night: night)
        XCTAssertFalse(data.populated.contains { $0.quantity == .hrv })
        XCTAssertTrue(data.populated.allSatisfy(\.hasValue))
    }
}
