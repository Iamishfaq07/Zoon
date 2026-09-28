import XCTest

/// Wind Down's spoken guidance: a thirty-minute routine is actually guided
/// for thirty minutes, lines never crowd each other, and nothing is said in
/// the silent modes.
final class WindDownScriptTests: XCTestCase {

    private func config(_ minutes: Int, guided: Int = 5, mode: WindDownGuidanceConfiguration.VoiceMode = .natural) -> WindDownGuidanceConfiguration {
        WindDownGuidanceConfiguration(routineDurationMinutes: minutes, guidedBreathingMinutes: guided, voiceMode: mode)
    }

    /// It used to be about a minute of voice and twenty-four of silence.
    func testAThirtyMinuteRoutineIsGuidedThroughout() {
        let cues = WindDownScript.cues(for: config(30))
        XCTAssertGreaterThanOrEqual(cues.count, 20)
        var previous = WindDownGuidanceConfiguration.arriveSeconds
        for cue in cues {
            XCTAssertLessThan(cue.at - previous, 4 * 60, "no gap longer than four minutes: \(cue.text)")
            previous = cue.at
        }
        XCTAssertEqual(cues.last?.text, WindDownScript.closing)
    }

    func testLinesNeverCrowdEachOther() {
        for minutes in [5, 10, 15, 20, 30, 45, 60] {
            let cues = WindDownScript.cues(for: config(minutes))
            for (earlier, later) in zip(cues, cues.dropFirst()) {
                XCTAssertGreaterThanOrEqual(later.at - earlier.at, WindDownScript.minimumGap, "\(minutes) min: \(later.text)")
            }
        }
    }

    func testEveryLineFallsInsideTheRoutine() {
        for minutes in [5, 10, 15, 20, 30] {
            let configuration = config(minutes)
            for cue in WindDownScript.cues(for: configuration) {
                XCTAssertGreaterThan(cue.at, WindDownGuidanceConfiguration.arriveSeconds)
                XCTAssertLessThanOrEqual(cue.at, configuration.routineSeconds - WindDownGuidanceConfiguration.closeSeconds)
            }
        }
    }

    func testTheBodyScanRunsFromTheFeetUp() {
        let texts = WindDownScript.cues(for: config(30)).map(\.text)
        guard let feet = texts.firstIndex(of: WindDownScript.bodyScan.first ?? ""),
              let face = texts.firstIndex(of: WindDownScript.bodyScan[11]) else {
            return XCTFail("a thirty-minute routine includes the full body scan")
        }
        XCTAssertLessThan(feet, face)
    }

    func testAShortRoutineStillClosesGently() {
        let cues = WindDownScript.cues(for: config(5))
        XCTAssertFalse(cues.isEmpty)
        XCTAssertEqual(cues.last?.text, WindDownScript.closing)
    }

    func testSilentModesSayNothing() {
        XCTAssertTrue(WindDownScript.cues(for: config(30, mode: .silent)).isEmpty)
        XCTAssertTrue(WindDownScript.cues(for: config(30, mode: .hapticsOnly)).isEmpty)
    }

    func testMinimalCuesAreFew() {
        let cues = WindDownScript.cues(for: config(30, mode: .minimal))
        XCTAssertLessThanOrEqual(cues.count, 3)
        XCTAssertEqual(cues.last?.text, WindDownScript.closingMinimal)
    }

    func testWithoutBreathingTheGuidanceStartsAfterArriving() {
        let cues = WindDownScript.cues(for: config(15), breathingEnabled: false)
        XCTAssertEqual(cues.first?.text, WindDownScript.transition)
        XCTAssertLessThan(cues.first?.at ?? .infinity, WindDownGuidanceConfiguration.arriveSeconds + 10)
    }

    func testTheScriptMakesNoMedicalClaims() {
        let all = [WindDownScript.pacedIntro, WindDownScript.transition, WindDownScript.closing]
            + WindDownScript.pacedReminders + WindDownScript.bodyScan + WindDownScript.visualisation + WindDownScript.presence
        for line in all {
            XCTAssertFalse(DiagnosticLanguageGuard.rejects(line), line)
        }
    }

    // MARK: - Voice

    private func voice(_ id: String, _ quality: SleepSpeech.Quality, novelty: Bool = false) -> SleepSpeech.Voice {
        SleepSpeech.Voice(identifier: id, name: id, language: "en-US", quality: quality, isNovelty: novelty)
    }

    /// With only standard voices installed, "by name" used to pick "Albert"
    /// (a novelty voice) or "Eddy" (Eloquence).
    func testNoveltyAndEloquenceVoicesAreNeverChosenAutomatically() {
        let installed = [
            voice("com.apple.speech.synthesis.voice.Albert", .standard, novelty: true),
            voice("com.apple.eloquence.en-US.Eddy", .standard),
            voice("com.apple.voice.compact.en-US.Samantha", .standard)
        ]
        let chosen = SleepSpeech.choose(installed, preferredIdentifier: nil, localeIdentifier: "en_US")
        XCTAssertEqual(chosen?.identifier, "com.apple.voice.compact.en-US.Samantha")
    }

    func testTheSystemDefaultVoiceWinsAmongEquals() {
        let installed = [
            voice("com.apple.voice.compact.en-US.Aaron", .standard),
            voice("com.apple.voice.compact.en-US.Samantha", .standard)
        ]
        let chosen = SleepSpeech.choose(
            installed, preferredIdentifier: nil, localeIdentifier: "en_US",
            systemDefaultIdentifier: "com.apple.voice.compact.en-US.Samantha"
        )
        XCTAssertEqual(chosen?.identifier, "com.apple.voice.compact.en-US.Samantha")
    }

    func testAnExplicitPickIsStillRespected() {
        let installed = [voice("com.apple.eloquence.en-US.Flo", .standard), voice("com.apple.voice.compact.en-US.Samantha", .standard)]
        let chosen = SleepSpeech.choose(installed, preferredIdentifier: "com.apple.eloquence.en-US.Flo", localeIdentifier: "en_US")
        XCTAssertEqual(chosen?.identifier, "com.apple.eloquence.en-US.Flo")
    }

    func testABetterVoiceIsSuggestedOnlyWhenNoneIsInstalled() {
        XCTAssertTrue(SleepSpeech.shouldSuggestBetterVoice([voice("a", .standard)], localeIdentifier: "en_US"))
        XCTAssertFalse(SleepSpeech.shouldSuggestBetterVoice([voice("a", .standard), voice("b", .enhanced)], localeIdentifier: "en_US"))
    }
}
