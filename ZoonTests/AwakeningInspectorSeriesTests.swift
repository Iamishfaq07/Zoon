import XCTest

/// The §25 layers: a heart-rate rise derived from a real overnight series, a
/// movement marker from active energy, and a respiratory note measured against
/// the rest of the same night.
///
/// The existing `AwakeningInspectorTests` cover the handed-in entry point and
/// are untouched — this is the derivation, and most of it is about what the
/// inspector refuses to derive.
final class AwakeningInspectorSeriesTests: XCTestCase {

    private let awakening = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A reading `minutes` before the awakening. Negative is earlier.
    private func at(_ minutes: Double) -> Date {
        awakening.addingTimeInterval(minutes * 60)
    }

    /// One reading per minute from −12 to 0, `nil` where the watch wrote
    /// nothing — which is what an overnight series actually looks like at
    /// this resolution.
    private func lead(_ values: [Double?]) -> [AwakeningInspector.Sample] {
        values.enumerated().map {
            AwakeningInspector.Sample(date: at(Double($0.offset) - 12), value: $0.element)
        }
    }

    private func interval(_ minutes: Double = 5) -> DateInterval {
        DateInterval(start: awakening, duration: minutes * 60)
    }

    // MARK: - The heart-rate rise

    func testARiseAboveThePrecedingMinutesIsFound() throws {
        let samples = lead([54, nil, 55, nil, 54, nil, 55, nil, 54, nil, 62, nil, 66])
        let rise = try XCTUnwrap(
            AwakeningInspector.heartRateRise(in: samples, before: awakening)
        )
        XCTAssertEqual(rise.date, at(-2))
        XCTAssertEqual(rise.deltaBpm, 8, accuracy: 0.001)
    }

    func testAFlatNightHasNoRiseInIt() {
        let samples = lead([55, nil, 55, nil, 55, nil, 56, nil, 55, nil, 56, nil, 57])
        XCTAssertNil(AwakeningInspector.heartRateRise(in: samples, before: awakening))
    }

    /// The comparison is local by design. A heart rate that is high all night
    /// has not risen, and a fixed threshold would mark every awakening for
    /// somebody whose overnight rate simply runs high.
    func testAHighButFlatHeartRateIsNotARise() {
        let samples = lead([78, nil, 78, nil, 79, nil, 78, nil, 79, nil, 78, nil, 79])
        XCTAssertNil(AwakeningInspector.heartRateRise(in: samples, before: awakening))
    }

    /// Two readings cannot establish what a rise would be a rise against.
    func testTooFewReadingsMeansNoRiseRatherThanAGuess() {
        let samples = lead([54, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 70])
        XCTAssertNil(AwakeningInspector.heartRateRise(in: samples, before: awakening))
    }

    func testAThresholdSizedRiseCounts() throws {
        let samples = lead([54, 55, 54, 59, 59, 59, 59, 59, 59, 59, 59, 59, 59])
        let rise = try XCTUnwrap(
            AwakeningInspector.heartRateRise(in: samples, before: awakening)
        )
        XCTAssertEqual(rise.deltaBpm, AwakeningInspector.riseThresholdBpm, accuracy: 0.001)
    }

    /// Readings from before the window are not a baseline for something
    /// inside it — the window is the context the brief asks for.
    func testReadingsOutsideTheWindowAreIgnored() {
        let outside = (1...10).map {
            AwakeningInspector.Sample(date: at(Double(-60 - $0)), value: 40)
        }
        let inside = [AwakeningInspector.Sample(date: at(-1), value: 70)]
        XCTAssertNil(AwakeningInspector.heartRateRise(in: outside + inside, before: awakening))
    }

    // MARK: - Movement

    func testMovementIsTheFirstBinThatClearsTheThreshold() throws {
        let samples = [
            AwakeningInspector.Sample(date: at(-6), value: 0),
            AwakeningInspector.Sample(date: at(-3), value: 0.1),
            AwakeningInspector.Sample(date: at(1), value: 2.0),
            AwakeningInspector.Sample(date: at(3), value: 3.0)
        ]
        let onset = try XCTUnwrap(
            AwakeningInspector.movementOnset(
                in: samples,
                window: DateInterval(start: at(-12), end: at(12))
            )
        )
        XCTAssertEqual(onset, at(1))
    }

    func testLyingStillIsNotMovement() {
        let samples = (-6...6).map {
            AwakeningInspector.Sample(date: at(Double($0)), value: 0)
        }
        XCTAssertNil(
            AwakeningInspector.movementOnset(
                in: samples, window: DateInterval(start: at(-12), end: at(12))
            )
        )
    }

    /// Active energy is not an accelerometer, and the sequence says so
    /// wherever the marker appears rather than letting it imply one.
    func testAMovementMarkerCarriesItsProvenance() throws {
        var series = AwakeningInspector.Series()
        series.movement = [AwakeningInspector.Sample(date: at(1), value: 2.0)]
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: series
        )
        XCTAssertTrue(sequence.markers.contains { $0.kind == .movement })
        let provenance = try XCTUnwrap(sequence.movementProvenance)
        XCTAssertTrue(provenance.contains("active energy"), provenance)
    }

    func testNoMovementMeansNoProvenanceLineEither() {
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: AwakeningInspector.Series()
        )
        XCTAssertNil(sequence.movementProvenance)
    }

    // MARK: - Respiratory context

    func testBreathingIsComparedWithTheRestOfTheSameNight() throws {
        let inside = [at(-3), at(-1), at(2)].map {
            AwakeningInspector.Sample(date: $0, value: 16.4)
        }
        let outside = (1...6).map {
            AwakeningInspector.Sample(date: at(Double(-30 * $0)), value: 14.0)
        }
        let note = try XCTUnwrap(
            AwakeningInspector.respiratoryNote(
                inside + outside,
                window: DateInterval(start: at(-12), end: at(12))
            )
        )
        XCTAssertTrue(note.contains("2.4 breaths a minute higher"), note)
        XCTAssertTrue(note.contains("rest of the night"), note)
    }

    func testASmallBreathingDifferenceIsInsideTheNoiseAndIsNotReported() {
        let inside = [at(-3), at(-1)].map {
            AwakeningInspector.Sample(date: $0, value: 14.3)
        }
        let outside = (1...6).map {
            AwakeningInspector.Sample(date: at(Double(-30 * $0)), value: 14.0)
        }
        XCTAssertNil(
            AwakeningInspector.respiratoryNote(
                inside + outside, window: DateInterval(start: at(-12), end: at(12))
            )
        )
    }

    func testNoBreathingReadingsMeansNoNoteRatherThanAZero() {
        XCTAssertNil(
            AwakeningInspector.respiratoryNote(
                [], window: DateInterval(start: at(-12), end: at(12))
            )
        )
    }

    // MARK: - The sequence as a whole

    func testTheDerivedRiseSaysHowFarItRose() throws {
        var series = AwakeningInspector.Series()
        series.heartRate = lead([54, nil, 55, nil, 54, nil, 55, nil, 54, nil, 62, nil, 66])
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: series
        )
        let marker = try XCTUnwrap(sequence.markers.first { $0.kind == .hrRise })
        XCTAssertEqual(marker.caption, "Heart rate rose 8 bpm above the preceding minutes")
    }

    /// A series that arrived and held no rise is not a missing stream. The
    /// old screen apologised for data it had, because "handed nothing" and
    /// "found nothing" were the same state.
    func testASeriesWithNoRiseIsNotReportedAsAMissingStream() {
        var series = AwakeningInspector.Series()
        series.heartRate = lead([55, nil, 55, nil, 55, nil, 56, nil, 55, nil, 56, nil, 57])
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: series
        )
        XCTAssertFalse(sequence.markers.contains { $0.kind == .hrRise })
        XCTAssertFalse(sequence.missingStreams.contains("heart rate"))
    }

    func testAnAbsentSeriesIsStillReportedAsMissing() {
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: AwakeningInspector.Series()
        )
        XCTAssertTrue(sequence.missingStreams.contains("heart rate"))
        XCTAssertTrue(sequence.missingStreams.contains("movement"))
    }

    func testTheTraceCarriesOnlyTheWindow() {
        var series = AwakeningInspector.Series()
        series.heartRate = lead([54, 54, 55, 54, 55, 54, 55, 54, 55, 62, 63, 64, 66])
            + [AwakeningInspector.Sample(date: at(-90), value: 50)]
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: series
        )
        XCTAssertEqual(sequence.heartRateWindow.count, 13)
        XCTAssertFalse(sequence.heartRateWindow.contains { $0.date == self.at(-90) })
    }

    /// The one sentence the brief pins exactly, and the one it forbids.
    func testTheCaveatStillSaysCoOccurrenceAndNeverCause() throws {
        var series = AwakeningInspector.Series()
        series.heartRate = lead([54, nil, 55, nil, 54, nil, 55, nil, 54, nil, 62, nil, 66])
        series.movement = [AwakeningInspector.Sample(date: at(1), value: 2.0)]
        let sequence = AwakeningInspector.inspect(
            awakening: interval(), stages: [], series: series
        )

        // The caveat is checked on its own, and deliberately not by the
        // causation guard: it is the one line that *mentions* cause, in order
        // to disclaim it, and a blanket "must not contain caused" would fail
        // on exactly the sentence the brief asks for.
        XCTAssertTrue(sequence.caveat.contains("occurred around the same time"), sequence.caveat)
        XCTAssertTrue(sequence.caveat.contains("does not claim"), sequence.caveat)

        let claims = sequence.markers.map(\.caption) + [sequence.movementProvenance ?? ""]
        for line in claims {
            XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
            XCTAssertFalse(line.lowercased().contains("caused"), line)
            XCTAssertFalse(line.lowercased().contains("woke you"), line)
        }
    }
}
