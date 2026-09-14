import XCTest

/// The radar's state machine was correct; five phone surfaces were not using
/// it. Today, the detail view, the pulse strip, the intelligence grid and the
/// "For You" list each read `signals.isEmpty` (as `isActive`) or `severity`,
/// both of which are true of a clear fortnight, of night four, and of a phone
/// that records sleep but no physiology. Only the first is reassurance.
///
/// These pin the presentation surface every one of those screens now shares,
/// so a future screen cannot quietly decide an empty signal list looks green.
final class HealthRadarPresentationTests: XCTestCase {

    private func signal(_ kind: VitalsStatus.Kind) -> HealthRadar.Signal {
        HealthRadar.Signal(
            kind: kind, direction: .elevated, consecutiveNights: 3,
            recentMean: 60, baseline: 54
        )
    }

    private func radar(
        signals: [HealthRadar.Signal] = [],
        nights: Int,
        domains: Int
    ) -> HealthRadar {
        HealthRadar(signals: signals, nightCount: nights, domainsWithBaseline: domains)
    }

    /// Every state the radar can be in, for exhaustive sweeps below.
    private var everyState: [(name: String, radar: HealthRadar)] {
        [
            ("building", radar(nights: 4, domains: 4)),
            ("no signals recorded", radar(nights: 30, domains: 0)),
            ("too few domains", radar(nights: 30, domains: 1)),
            ("typical", radar(nights: 30, domains: 4)),
            ("watch", radar(signals: [signal(.hrv)], nights: 30, domains: 4)),
            ("notable", radar(
                signals: [signal(.hrv), signal(.restingHeartRate), signal(.wristTemperature)],
                nights: 30, domains: 4
            )),
        ]
    }

    // MARK: - Reassurance

    /// The heart of it: no phrasing that means "you're fine" may appear in a
    /// state that is not fine-or-otherwise-known.
    func testOnlyTypicalSpeaksReassuringly() {
        let reassuring = ["nothing unusual", "no sustained changes", "ok", "all clear", "typical"]
        for (name, radar) in everyState where !radar.state.isReassurance {
            let headline = radar.stateHeadline.lowercased()
            for phrase in reassuring {
                XCTAssertFalse(
                    headline.contains(phrase),
                    "\(name) said \"\(radar.stateHeadline)\", which reads as reassurance"
                )
            }
        }
        XCTAssertEqual(radar(nights: 30, domains: 4).stateHeadline, "Nothing unusual")
    }

    /// The detail paragraph used to gate on night count alone, so a
    /// phone-only user with a month of sleep read "Nothing has been drifting
    /// from your baseline" — a clean bill issued over an empty instrument.
    func testTheDetailParagraphDoesNotClearAnEmptyInstrument() {
        let phoneOnly = radar(nights: 30, domains: 0)
        XCTAssertFalse(
            phoneOnly.stateDetail.lowercased().contains("nothing has been drifting"),
            "no signals were being measured, so nothing could have drifted"
        )
        XCTAssertTrue(phoneOnly.stateDetail.lowercased().contains("no overnight body signals"))
    }

    func testAPartiallyCoveredUserIsToldHowManyDomainsAreMissing() {
        let detail = radar(nights: 30, domains: 1).stateDetail
        XCTAssertTrue(detail.contains("1 of the \(HealthRadar.minimumDomainsForTypical)"))
    }

    // MARK: - Colour

    /// Colour is a verdict. An indeterminate state painted green is the same
    /// false reassurance in another medium.
    func testIndeterminateStatesAreNeutrallyToned() {
        for (name, radar) in everyState where radar.state.isIndeterminate {
            XCTAssertEqual(radar.state.tone, .neutral, "\(name) was given a verdict colour")
        }
    }

    func testKnownStatesCarryTheirVerdictTone() {
        XCTAssertEqual(radar(nights: 30, domains: 4).state.tone, .good)
        XCTAssertEqual(radar(signals: [signal(.hrv)], nights: 30, domains: 4).state.tone, .caution)
        XCTAssertEqual(
            radar(
                signals: [signal(.hrv), signal(.restingHeartRate), signal(.wristTemperature)],
                nights: 30, domains: 4
            ).state.tone,
            .alert
        )
    }

    // MARK: - What counts as a notice

    /// "For You" and the Body Signals card gate on this. Neither reassurance
    /// nor "not yet" is something to raise as a notice.
    func testOnlyDriftingStatesAreActionable() {
        for (name, radar) in everyState {
            let expected = radar.signals.count > 0
            XCTAssertEqual(
                radar.state.isActionable, expected,
                "\(name) disagreed about whether it is worth raising"
            )
        }
    }

    func testASubtitleIsOfferedOnlyWhenSeveralSignalsMoved() {
        XCTAssertNil(radar(nights: 30, domains: 4).stateSubtitle)
        XCTAssertNil(radar(signals: [signal(.hrv)], nights: 30, domains: 4).stateSubtitle)
        XCTAssertNotNil(
            radar(
                signals: [signal(.hrv), signal(.restingHeartRate), signal(.wristTemperature)],
                nights: 30, domains: 4
            ).stateSubtitle
        )
    }

    // MARK: - The compact strip

    /// This is where "Signals — OK" came from: a count when there were
    /// signals, the word OK when there were none.
    func testTheCountLabelNeverPrintsANumberItCannotKnow() {
        XCTAssertEqual(radar(nights: 4, domains: 4).stateCountLabel, "—")
        XCTAssertEqual(radar(nights: 30, domains: 0).stateCountLabel, "—")
        XCTAssertEqual(radar(nights: 30, domains: 4).stateCountLabel, "0")
        XCTAssertEqual(radar(signals: [signal(.hrv)], nights: 30, domains: 4).stateCountLabel, "1")
    }

    func testEveryStateHasAShortLabelForAComplication() {
        for (name, radar) in everyState {
            XCTAssertFalse(radar.stateShortLabel.isEmpty, "\(name) had no short label")
            XCTAssertFalse(radar.stateHeadline.isEmpty, "\(name) had no headline")
            XCTAssertFalse(radar.stateDetail.isEmpty, "\(name) had no detail")
        }
    }
}
