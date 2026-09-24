import XCTest

/// Audit §9.4: one voice and pacing for everything Zoon says.
final class SleepSpeechTests: XCTestCase {

    private func voice(_ id: String, _ language: String, _ quality: SleepSpeech.Quality, name: String? = nil) -> SleepSpeech.Voice {
        SleepSpeech.Voice(identifier: id, name: name ?? id, language: language, quality: quality)
    }

    private lazy var installed = [
        voice("gb-standard", "en-GB", .standard),
        voice("us-enhanced", "en-US", .enhanced),
        voice("au-premium", "en-AU", .premium),
        voice("us-premium", "en-US", .premium),
        voice("fr-premium", "fr-FR", .premium),
        voice("yue-enhanced", "yue-HK", .enhanced)
    ]

    func testBestQualityFirstThenTheUsersRegion() {
        let ranked = SleepSpeech.ranked(installed, localeIdentifier: "en_US")
        XCTAssertEqual(ranked.map(\.identifier), ["us-premium", "au-premium", "us-enhanced", "gb-standard"])
    }

    func testOtherLanguagesAreNeverOffered() {
        let ranked = SleepSpeech.ranked(installed, localeIdentifier: "en_GB")
        XCTAssertFalse(ranked.contains { $0.identifier == "fr-premium" })
        XCTAssertFalse(ranked.contains { $0.identifier == "yue-enhanced" })
    }

    /// The old filter compared the first two characters, so "yue" matched
    /// nothing and "en" would have matched a hypothetical "eng" voice.
    func testThreeLetterLanguagesMatchWholeCodes() {
        let ranked = SleepSpeech.ranked(installed, localeIdentifier: "yue_Hant_HK")
        XCTAssertEqual(ranked.map(\.identifier), ["yue-enhanced"])
    }

    func testThePickedVoiceWinsWhileInstalled() {
        let chosen = SleepSpeech.choose(installed, preferredIdentifier: "gb-standard", localeIdentifier: "en_US")
        XCTAssertEqual(chosen?.identifier, "gb-standard")
    }

    func testAnUninstalledPickFallsBackToTheBestVoice() {
        let chosen = SleepSpeech.choose(installed, preferredIdentifier: "deleted-voice", localeIdentifier: "en_US")
        XCTAssertEqual(chosen?.identifier, "us-premium")
    }

    func testNoVoiceForTheLanguageLeavesItToTheSystem() {
        XCTAssertNil(SleepSpeech.choose(installed, preferredIdentifier: nil, localeIdentifier: "de_DE"))
    }

    func testLanguageTags() {
        XCTAssertEqual(SleepSpeech.LanguageTag("en_US"), SleepSpeech.LanguageTag("en-US"))
        XCTAssertEqual(SleepSpeech.LanguageTag("zh-Hans-CN").region, "CN")
        XCTAssertEqual(SleepSpeech.LanguageTag("zh-Hans").region, nil, "a script is not a region")
        XCTAssertEqual(SleepSpeech.LanguageTag("es-419").region, "419")
        XCTAssertEqual(SleepSpeech.LanguageTag("EN").language, "en")
    }

    // MARK: - Pacing

    func testEverySleepProfileIsSlowerThanConversation() {
        for profile in [SleepSpeech.Profile.breathing, .narration] {
            XCTAssertLessThan(profile.rateScale, 1)
            XCTAssertGreaterThan(profile.rateScale, 0.5, "slow, not slurred")
            XCTAssertLessThanOrEqual(profile.pitch, 1)
            XCTAssertGreaterThan(profile.sentencePause, 0)
        }
    }

    /// A night summary gets a clear pause between events.
    func testNarrationPausesLongerBetweenSentencesThanBreathingCues() {
        XCTAssertGreaterThan(SleepSpeech.Profile.narration.sentencePause, SleepSpeech.Profile.breathing.sentencePause)
    }

    func testANightSummaryIsSpokenOneEventAtATime() {
        let summary = "11:02 PM: Fell asleep. 1:40 AM: Awake for 6 minutes. 6:55 AM: Woke up."
        XCTAssertEqual(SleepSpeech.sentences(summary), [
            "11:02 PM: Fell asleep.",
            "1:40 AM: Awake for 6 minutes.",
            "6:55 AM: Woke up."
        ])
    }

    func testTextWithoutASentenceEndIsOneSentence() {
        XCTAssertEqual(SleepSpeech.sentences("  Breathe in  "), ["Breathe in"])
        XCTAssertEqual(SleepSpeech.sentences("   "), [])
        XCTAssertEqual(SleepSpeech.sentences(""), [])
    }
}
