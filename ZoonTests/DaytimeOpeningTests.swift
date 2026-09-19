import XCTest

/// A morning reading must not be spoken in the present tense.
///
/// At 14:10 the screen said "your body needs moderate output today", derived
/// entirely from `RecoveryScore.band` — which `RecoveryScore` documents as
/// scored from last night and not moving during the day. The number was never
/// wrong; the tense was.
final class DaytimeOpeningTests: XCTestCase {

    private func sentence(
        _ band: RecoveryScore.Band?,
        _ current: StressScore.Band?,
        name: String = ""
    ) -> String {
        DaytimeOpening.sentence(band: band, currentBand: current, name: name)
    }

    // MARK: - Tense

    /// The morning half is about the morning, and says so.
    func testTheMorningHalfIsInThePastTense() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            let line = sentence(band, .calm)
            XCTAssertTrue(line.contains("Morning Recovery was"), line)
        }
    }

    /// The exact phrasing the audit flagged, gone at every band.
    func testNoBandPrescribesTheDayFromLastNightAlone() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            for current in [StressScore.Band.calm, .elevated, .high, nil] {
                let line = sentence(band, current)
                for banned in [
                    "needs moderate output", "can take load today",
                    "asking for a light day", "primed", "harder session"
                ] {
                    XCTAssertFalse(
                        line.lowercased().contains(banned),
                        "\(banned) in: \(line)"
                    )
                }
            }
        }
    }

    /// The current half comes from a signal that actually moves, and is
    /// stated in the present.
    func testTheCurrentHalfIsInThePresentTense() {
        XCTAssertTrue(sentence(.moderate, .calm).contains("right now"))
        XCTAssertTrue(sentence(.moderate, .high).contains("right now"))
    }

    /// Two different afternoons after the same morning must not read the
    /// same. This is the whole point: the old line could not tell them apart.
    func testTheSameMorningReadsDifferentlyOnDifferentAfternoons() {
        XCTAssertNotEqual(sentence(.moderate, .calm), sentence(.moderate, .high))
    }

    // MARK: - Missing is not calm

    /// No quiet daytime readings is a real state, not a calm one.
    func testNoCurrentReadingSaysSoRatherThanReadingAsCalm() {
        let line = sentence(.moderate, nil)
        XCTAssertTrue(line.contains("not enough quiet daytime readings"), line)
        XCTAssertNotEqual(sentence(.moderate, nil), sentence(.moderate, .calm))
    }

    /// A withheld score does not acquire a band from the sentence.
    func testAWithheldScoreStatesNoMorningReading() {
        let line = sentence(nil, .calm)
        XCTAssertFalse(line.contains("Morning Recovery was"), line)
        XCTAssertTrue(line.contains("needs more physiological data"), line)
    }

    /// Even with the score withheld, a measured current reading is still
    /// worth stating — it was measured independently.
    func testAWithheldScoreStillReportsTheCurrentReading() {
        XCTAssertTrue(sentence(nil, .high).contains("well above your usual"))
    }

    func testAWithheldScoreAndNoCurrentReadingClaimsNothing() {
        let line = sentence(nil, nil)
        XCTAssertFalse(line.contains("Morning Recovery was"), line)
        XCTAssertFalse(line.contains("right now"), line)
    }

    // MARK: - Guidance needs both halves

    /// "A lighter day" is a claim about now. A morning score cannot make it
    /// alone, so it arrives only when the afternoon agrees.
    func testGuidanceIsWithheldWhenOnlyTheMorningWasLow() {
        XCTAssertNil(DaytimeOpening.guidance(band: .low, currentBand: .calm))
    }

    func testGuidanceArrivesWhenBothHalvesAgree() {
        XCTAssertNotNil(DaytimeOpening.guidance(band: .low, currentBand: .high))
        XCTAssertNotNil(DaytimeOpening.guidance(band: .low, currentBand: .elevated))
        XCTAssertNotNil(DaytimeOpening.guidance(band: .moderate, currentBand: .high))
    }

    /// A good morning does not license a hard session once the current
    /// reading has gone well above usual.
    func testAHighMorningDoesNotOverrideARaisedAfternoon() {
        XCTAssertNil(DaytimeOpening.guidance(band: .high, currentBand: .high))
        XCTAssertNil(DaytimeOpening.guidance(band: .high, currentBand: .elevated))
    }

    func testGuidanceIsWithheldWithoutACurrentReading() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            XCTAssertNil(DaytimeOpening.guidance(band: band, currentBand: nil))
        }
    }

    func testGuidanceIsWithheldWhenTheScoreIsWithheld() {
        XCTAssertNil(DaytimeOpening.guidance(band: nil, currentBand: .high))
    }

    /// No guidance anywhere prescribes training intensity.
    func testGuidanceNeverPrescribesASession() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            for current in [StressScore.Band.calm, .elevated, .high, nil] {
                guard let line = DaytimeOpening.guidance(band: band, currentBand: current) else { continue }
                for banned in ["harder session", "train", "primed", "workout", "intensity"] {
                    XCTAssertFalse(line.lowercased().contains(banned), "\(banned) in: \(line)")
                }
                XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(line), line)
                XCTAssertFalse(DiagnosticLanguageGuard.overclaimsCausation(line), line)
            }
        }
    }

    // MARK: - The name

    func testTheNameIsUsedWhenThereIsOneAndNotInventedWhenThereIsNot() {
        let named = sentence(.moderate, .calm, name: "Ishfaq")
        XCTAssertTrue(named.hasPrefix("Ishfaq, "), named)
        let anonymous = sentence(.moderate, .calm)
        XCTAssertFalse(anonymous.contains(","), anonymous)
        XCTAssertTrue(anonymous.hasPrefix("Morning Recovery"), anonymous)
    }

    func testAWhitespaceOnlyNameIsTreatedAsNoName() {
        XCTAssertEqual(sentence(.moderate, .calm, name: "   "), sentence(.moderate, .calm))
    }

    // MARK: - The accessibility form

    /// The full sentence is materially longer than the one it replaced, and
    /// at 19pt semibold scaled to the largest accessibility size that is a
    /// wall of text before the reader reaches the number. The compact form
    /// exists because the fix made the layout problem worse.
    func testTheCompactFormIsShorterThanTheFullOne() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            for current in [StressScore.Band.calm, .elevated, .high, nil] {
                let full = DaytimeOpening.sentence(band: band, currentBand: current, name: "Ishfaq")
                let compact = DaytimeOpening.sentence(
                    band: band, currentBand: current, name: "Ishfaq", length: .compact
                )
                XCTAssertLessThan(compact.count, full.count, "\(band) / \(String(describing: current))")
            }
        }
    }

    /// What goes is the connective tissue. Both facts have to survive, or the
    /// screen is back to narrating a morning score in the afternoon — which
    /// is the whole thing this type exists to stop.
    func testTheCompactFormStillCarriesBothHalves() {
        let compact = DaytimeOpening.sentence(band: .moderate, currentBand: .high, length: .compact)
        XCTAssertTrue(compact.contains("Morning Recovery was moderate"), compact)
        XCTAssertTrue(compact.lowercased().contains("now"), compact)
        XCTAssertTrue(compact.lowercased().contains("well above"), compact)
    }

    /// Two different afternoons must still read differently, compact or not.
    func testTheCompactFormStillDistinguishesAfternoons() {
        XCTAssertNotEqual(
            DaytimeOpening.sentence(band: .moderate, currentBand: .calm, length: .compact),
            DaytimeOpening.sentence(band: .moderate, currentBand: .high, length: .compact)
        )
    }

    /// A greeting costs a whole line at the largest sizes, before anything
    /// the reader came for.
    func testTheCompactFormDropsTheName() {
        let compact = DaytimeOpening.sentence(
            band: .moderate, currentBand: .calm, name: "Ishfaq", length: .compact
        )
        XCTAssertFalse(compact.contains("Ishfaq"), compact)
    }

    func testTheCompactFormStillWithholdsAScoreItDoesNotHave() {
        let compact = DaytimeOpening.sentence(band: nil, currentBand: .calm, length: .compact)
        XCTAssertFalse(compact.contains("Morning Recovery was"), compact)
    }

    /// Missing is still not calm in the short form either.
    func testTheCompactFormStillSaysWhenThereAreNoReadings() {
        let compact = DaytimeOpening.sentence(band: .moderate, currentBand: nil, length: .compact)
        XCTAssertTrue(compact.contains("not enough quiet readings"), compact)
        XCTAssertNotEqual(
            compact,
            DaytimeOpening.sentence(band: .moderate, currentBand: .calm, length: .compact)
        )
    }

    // MARK: - The minimal form, which the AX5 capture asked for

    /// `.compact` renders well at AX3 and fails at AX5 -- five lines, about
    /// half the display, with a clipped HRV row as the only driver above the
    /// fold. This tier is what the capture bought.
    func testTheMinimalFormIsShorterThanTheCompactOne() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            for current in [StressScore.Band.calm, .elevated, .high] {
                let compact = DaytimeOpening.sentence(
                    band: band, currentBand: current, length: .compact
                )
                let minimal = DaytimeOpening.sentence(
                    band: band, currentBand: current, length: .minimal
                )
                XCTAssertLessThan(
                    minimal.count, compact.count, "\(band) / \(current)"
                )
            }
        }
    }

    /// The half that goes is the half the ring is already stating a line
    /// below -- and the half that stays is the one the ring cannot carry,
    /// because the ring is Morning Recovery and Morning Recovery is not how
    /// today is going.
    func testTheMinimalFormDropsWhatTheRingAlreadySays() {
        let minimal = DaytimeOpening.sentence(band: .moderate, currentBand: .high, length: .minimal)
        XCTAssertFalse(minimal.contains("Morning Recovery"), minimal)
        XCTAssertTrue(minimal.lowercased().contains("now"), minimal)
        XCTAssertTrue(minimal.lowercased().contains("well above"), minimal)
    }

    /// Dropping a clause must not flatten two different afternoons into one
    /// line. If it did, the tier would have traded the defect back.
    func testTheMinimalFormStillDistinguishesAfternoons() {
        let lines = [StressScore.Band.calm, .elevated, .high, nil].map {
            DaytimeOpening.sentence(band: .moderate, currentBand: $0, length: .minimal)
        }
        XCTAssertEqual(Set(lines).count, lines.count, "\(lines)")
    }

    /// Two different mornings legitimately produce the same minimal line --
    /// that is the point, not a bug. The ring is what distinguishes them, and
    /// this asserts the tier is actually doing the dropping it claims to.
    func testTheMinimalFormLeavesTheMorningToTheRing() {
        XCTAssertEqual(
            DaytimeOpening.sentence(band: .low, currentBand: .calm, length: .minimal),
            DaytimeOpening.sentence(band: .high, currentBand: .calm, length: .minimal)
        )
    }

    /// With no band there is no ring reading to be redundant with, so the
    /// withheld-score explanation survives at every tier. Dropping it would
    /// leave an empty ring and nothing saying why.
    func testTheMinimalFormStillExplainsAWithheldScore() {
        let minimal = DaytimeOpening.sentence(band: nil, currentBand: .calm, length: .minimal)
        XCTAssertTrue(minimal.contains("Recovery needs more data"), minimal)
        XCTAssertTrue(minimal.lowercased().contains("around usual"), minimal)
        XCTAssertFalse(minimal.contains("Morning Recovery was"), minimal)
    }

    /// Missing is still not zero at the shortest tier. The wording is
    /// shorter than the compact form's -- naming the reason costs three lines
    /// at AX5 -- but it still says the load was not measured rather than
    /// implying it was fine.
    func testTheMinimalFormStillSaysWhenThereAreNoReadings() {
        let minimal = DaytimeOpening.sentence(band: .moderate, currentBand: nil, length: .minimal)
        XCTAssertTrue(minimal.contains("not measured yet"), minimal)
        XCTAssertNotEqual(
            minimal,
            DaytimeOpening.sentence(band: .moderate, currentBand: .calm, length: .minimal)
        )
    }

    // MARK: - The band copy it replaced

    /// `RecoveryScore.Band.guidance` is what the rest of the app reads. It
    /// used to prescribe a session off four overnight numbers.
    func testTheBandCopyDescribesSignalsRatherThanPrescribingTraining() {
        for band in [RecoveryScore.Band.low, .moderate, .high] {
            let guidance = band.guidance
            for banned in ["primed", "harder session", "train", "leave something in the tank"] {
                XCTAssertFalse(guidance.lowercased().contains(banned), "\(banned) in: \(guidance)")
            }
            XCTAssertTrue(
                guidance.lowercased().contains("signals"),
                "the band copy stopped naming what it is describing: \(guidance)"
            )
            XCTAssertFalse(DiagnosticLanguageGuard.containsBannedLanguage(guidance), guidance)
        }
    }

    /// Each band still says something different — the copy was softened, not
    /// flattened into one line.
    func testTheThreeBandsStillSayDifferentThings() {
        let all = [RecoveryScore.Band.low, .moderate, .high].map(\.guidance)
        XCTAssertEqual(Set(all).count, 3)
    }
}
