import XCTest

/// The radar must distinguish "nothing is wrong" from "I cannot tell yet".
final class HealthRadarStateTests: XCTestCase {

    /// Four nights is not a clean bill of health. Before the state model,
    /// `signals.isEmpty` was read as reassurance and this user saw "Typical".
    func testFewNightsReportsBuildingBaselineNotTypical() {
        let radar = HealthRadar.detect(
            nights: (0..<4).map { Fixture.night(daysAgo: $0) }
        )
        guard case .buildingBaseline(let nights, let required) = radar.state else {
            return XCTFail("Expected buildingBaseline, got \(radar.state)")
        }
        XCTAssertEqual(nights, 4)
        XCTAssertEqual(required, HealthRadar.minimumBaselineNights)
        XCTAssertFalse(radar.state.isReassurance)
        XCTAssertTrue(radar.state.isIndeterminate)
        XCTAssertTrue(radar.stateHeadline.contains("4 of \(required)"))
    }

    /// Enough nights, but recorded by something that measures no physiology:
    /// nothing drifted because nothing was measured.
    func testNightsWithoutBodySignalsReportInsufficientSignals() {
        let nights = (0..<30).map {
            Fixture.night(
                daysAgo: $0,
                avgHRV: nil,
                restingHeartRate: nil,
                minHeartRate: nil,
                avgRespiratoryRate: nil,
                wristTempDeltaC: nil,
                avgSpO2: nil
            )
        }
        let radar = HealthRadar.detect(nights: nights)

        XCTAssertTrue(radar.signals.isEmpty, "Nothing to detect without inputs")
        guard case .insufficientSignals = radar.state else {
            return XCTFail("Expected insufficientSignals, got \(radar.state)")
        }
        XCTAssertFalse(radar.state.isReassurance,
                       "This is the false-reassurance case")
        XCTAssertEqual(radar.stateShortLabel, "No data")
    }

    /// The genuinely quiet case — and the only one allowed to reassure.
    func testStableHistoryWithSignalsReportsTypical() {
        let radar = HealthRadar.detect(
            nights: (0..<30).map { Fixture.night(daysAgo: $0) }
        )
        XCTAssertTrue(radar.signals.isEmpty)
        XCTAssertEqual(radar.state, HealthRadar.State.typical)
        XCTAssertTrue(radar.state.isReassurance)
        XCTAssertEqual(radar.stateShortLabel, "Typical")
    }

    /// Coverage is counted, and a stable history has domains behind it.
    func testDomainsWithBaselineAreCounted() {
        let radar = HealthRadar.detect(
            nights: (0..<30).map { Fixture.night(daysAgo: $0) }
        )
        XCTAssertGreaterThanOrEqual(
            radar.domainsWithBaseline, HealthRadar.minimumDomainsForTypical
        )
    }

    /// An archive written before coverage was recorded decodes to 0, which
    /// must route to the cautious state rather than to reassurance.
    func testLegacyRadarWithoutCoverageDoesNotReassure() throws {
        let payload = """
        { "signals": [], "nightCount": 30 }
        """
        let radar = try JSONDecoder().decode(
            HealthRadar.self, from: Data(payload.utf8)
        )
        XCTAssertEqual(radar.domainsWithBaseline, 0)
        XCTAssertFalse(radar.state.isReassurance)
    }
}
