import XCTest

final class VitalsStatusTests: XCTestCase {

    private func sample(restingHeartRate: Double) -> VitalsSample {
        VitalsSample(
            date: .now, restingHeartRate: restingHeartRate, hrv: 55,
            respiratoryRate: 14.5, oxygenSaturation: 97, wristTemperatureDelta: 0,
            sleepMinutes: 450
        )
    }

    func testEvaluateHasNoBaselineBelowMinimumNights() {
        let history = (0..<(VitalsStatus.minimumNights - 1)).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(), history: history)
        XCTAssertFalse(status.hasBaseline)
    }

    func testEvaluateWithoutBaselineReadsAvailableValuesAsTypical() {
        // No baseline yet, but the metric has a current value -- state
        // should be .typical, not .unavailable, per the documented "value
        // == nil ? .unavailable : .typical" branch.
        let status = VitalsStatus.evaluate(features: Fixture.night(), history: [])
        let restingHR = status.metrics.first { $0.kind == .restingHeartRate }
        XCTAssertEqual(restingHR?.state, .typical)
    }

    func testEvaluateWithoutBaselineReadsMissingValuesAsUnavailable() {
        let status = VitalsStatus.evaluate(features: Fixture.night(avgSpO2: nil), history: [])
        let spo2 = status.metrics.first { $0.kind == .oxygenSaturation }
        XCTAssertEqual(spo2?.state, .unavailable)
    }

    func testEvaluateReadsTypicalWhenWithinTolerance() {
        // Baseline of steady 54 bpm, current night also 54 -- squarely typical.
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 54), history: history)
        let restingHR = status.metrics.first { $0.kind == .restingHeartRate }
        XCTAssertEqual(restingHR?.state, .typical)
    }

    func testEvaluateReadsAboveTypicalPastTheTolerance() {
        // Constant baseline (SD 0) means tolerance floors to
        // Kind.minimumTolerance (2.0 bpm for resting heart rate) -- a value
        // 10bpm above baseline should clear that easily.
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 64), history: history)
        let restingHR = status.metrics.first { $0.kind == .restingHeartRate }
        XCTAssertEqual(restingHR?.state, .aboveTypical)
    }

    func testEvaluateReadsBelowTypicalPastTheTolerance() {
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 44), history: history)
        let restingHR = status.metrics.first { $0.kind == .restingHeartRate }
        XCTAssertEqual(restingHR?.state, .belowTypical)
    }

    func testEvaluateMarksUnavailableWhenTonightsValueIsMissingDespiteBaseline() {
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(avgSpO2: nil), history: history)
        let spo2 = status.metrics.first { $0.kind == .oxygenSaturation }
        XCTAssertEqual(spo2?.state, .unavailable)
    }

    // MARK: - outliers / headline / detail

    func testHeadlineReportsBuildingWithoutBaseline() {
        let status = VitalsStatus.evaluate(features: Fixture.night(), history: [])
        XCTAssertEqual(status.headline, "Building your typical ranges")
    }

    func testHeadlineReportsAllTypicalWithNoOutliers() {
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 54), history: history)
        XCTAssertEqual(status.headline, "All vitals typical")
    }

    func testHeadlineCountsExactlyOneOutlierSingularly() {
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 90), history: history)
        XCTAssertEqual(status.headline, "1 vital outside your typical range")
    }

    func testOutliersFilterIsOutlierStatesOnly() {
        let history = (0..<VitalsStatus.minimumNights).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 90), history: history)
        XCTAssertTrue(status.outliers.allSatisfy { $0.state.isOutlier })
        XCTAssertTrue(status.outliers.contains { $0.kind == .restingHeartRate })
    }

    // MARK: - Evidence behind the baseline (V9 item 43, third disclosure tier)

    func testSampleCountReportsNightsBehindTheBaseline() {
        let history = (0..<12).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 54), history: history)
        let restingHR = status.metrics.first { $0.kind == .restingHeartRate }
        XCTAssertEqual(restingHR?.sampleCount, 12)
    }

    func testSampleCountIsPerMetricNotPerNight() {
        // Twelve nights of history, but only the resting heart rate is
        // present on all of them -- blood oxygen is missing throughout, so
        // its count must be 0 rather than inheriting the night count.
        let history = (0..<12).map { _ in
            VitalsSample(
                date: .now, restingHeartRate: 54, hrv: 55,
                respiratoryRate: 14.5, oxygenSaturation: nil, wristTemperatureDelta: 0,
                sleepMinutes: 450
            )
        }
        let status = VitalsStatus.evaluate(features: Fixture.night(), history: history)
        XCTAssertEqual(status.metrics.first { $0.kind == .restingHeartRate }?.sampleCount, 12)
        XCTAssertEqual(status.metrics.first { $0.kind == .oxygenSaturation }?.sampleCount, 0)
    }

    func testConfidenceRisesWithNights() {
        func confidence(nights: Int) -> MetricConfidence? {
            let history = (0..<nights).map { _ in sample(restingHeartRate: 54) }
            let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 54), history: history)
            return status.metrics.first { $0.kind == .restingHeartRate }?.confidence
        }
        XCTAssertEqual(confidence(nights: 3), .insufficient)
        XCTAssertEqual(confidence(nights: 10), .low)
        XCTAssertEqual(confidence(nights: 20), .moderate)
        XCTAssertEqual(confidence(nights: 40), .high)
    }

    func testConfidenceIsNeverHighWithoutABaseline() {
        // The floor `evaluate` enforces and the confidence banding must not
        // disagree: below the minimum there is no baseline, so no band above
        // "insufficient" is available to claim.
        let history = (0..<(VitalsStatus.minimumNights - 1)).map { _ in sample(restingHeartRate: 54) }
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 54), history: history)
        for metric in status.metrics {
            XCTAssertNil(metric.baseline)
            XCTAssertEqual(metric.confidence, .insufficient)
        }
    }

    func testMetricWithoutABaselineCarriesNoTypicalRange() {
        // The regression behind the "Still learning your normal" caption: a
        // metric reported as .typical with no baseline must not be able to
        // render a range, or the UI would describe a comparison it cannot
        // actually make.
        let status = VitalsStatus.evaluate(features: Fixture.night(restingHeartRate: 54), history: [])
        let restingHR = status.metrics.first { $0.kind == .restingHeartRate }
        XCTAssertEqual(restingHR?.state, .typical)
        XCTAssertNil(restingHR?.baseline)
        XCTAssertNil(restingHR?.formattedRange)
    }
}
