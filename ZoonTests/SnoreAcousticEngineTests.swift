import XCTest

/// Zoon's own snore detector, fed synthetic frames: what a buffer of room
/// sound looks like after `SnoreSignalAnalyzer`, never audio.
final class SnoreAcousticEngineTests: XCTestCase {

    private let step: TimeInterval = 0.1

    private func frame(_ level: Double, low: Double = 0.8, zcr: Double = 400, periodic: Double = 0.6) -> SnoreFrame {
        SnoreFrame(duration: step, levelDB: level, lowRatio: low, zeroCrossingRate: zcr, periodicity: periodic)
    }

    /// A quiet bedroom: -60 dBFS, mostly hiss.
    private var quiet: SnoreFrame { frame(-60, low: 0.3, zcr: 3_000, periodic: 0.05) }

    /// Feeds `frame` for `seconds`, advancing the engine's clock `t`.
    private func feed(_ engine: inout SnoreAcousticEngine, _ frame: SnoreFrame, for seconds: Double, t: inout TimeInterval) {
        for _ in 0..<Int((seconds / step).rounded()) {
            t += step
            engine.ingest(frame, endingAt: t)
        }
    }

    /// `breaths` snores of `length` seconds, one every `period`, over `background`.
    private func breathe(
        _ engine: inout SnoreAcousticEngine,
        breaths: Int,
        period: Double,
        length: Double = 1.2,
        snore: SnoreFrame,
        background: SnoreFrame,
        t: inout TimeInterval
    ) {
        for _ in 0..<breaths {
            feed(&engine, snore, for: length, t: &t)
            feed(&engine, background, for: period - length, t: &t)
        }
    }

    func testRhythmicSnoresMakeOneEpisode() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        breathe(&engine, breaths: 8, period: 4, snore: frame(-40), background: quiet, t: &t)
        engine.finish()
        XCTAssertEqual(engine.episodes.count, 1)
        let episode = try? XCTUnwrap(engine.episodes.first)
        XCTAssertGreaterThanOrEqual(episode?.events ?? 0, 6)
        XCTAssertEqual(episode?.duration ?? 0, 7 * 4 + 1.2, accuracy: 1.5)
        XCTAssertEqual(episode?.loudness, .moderate, "20 dB above the room")
    }

    /// The old detector's cadence cases, carried over: two, five and six
    /// seconds a breath are all snoring.
    func testTwoFiveAndSixSecondBreathingAllCount() {
        for (period, length) in [(2.0, 0.8), (5.0, 1.5), (6.0, 1.8)] {
            var engine = SnoreAcousticEngine()
            var t: TimeInterval = 0
            feed(&engine, quiet, for: 10, t: &t)
            breathe(&engine, breaths: 6, period: period, length: length, snore: frame(-42), background: quiet, t: &t)
            engine.finish()
            XCTAssertEqual(engine.episodes.count, 1, "\(period)s breathing")
        }
    }

    func testASingleCoughIsNotAnEpisode() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        feed(&engine, frame(-35), for: 0.4, t: &t)
        feed(&engine, quiet, for: 30, t: &t)
        engine.finish()
        XCTAssertTrue(engine.episodes.isEmpty)
        XCTAssertEqual(engine.snoreSeconds, 0)
    }

    func testHighPitchedRhythmicSoundIsNotSnoring() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        let hiss = frame(-40, low: 0.2, zcr: 6_000, periodic: 0.1)
        breathe(&engine, breaths: 8, period: 4, snore: hiss, background: quiet, t: &t)
        engine.finish()
        XCTAssertEqual(engine.candidateCount, 0)
        XCTAssertTrue(engine.episodes.isEmpty)
    }

    func testASoundLongerThanABreathIsNotACandidate() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        breathe(&engine, breaths: 5, period: 9, length: 5, snore: frame(-40), background: quiet, t: &t)
        engine.finish()
        XCTAssertEqual(engine.candidateCount, 0)
    }

    /// The fixed threshold this replaces (RMS 0.02, about -34 dBFS) could not
    /// hear this at all.
    func testQuietSnoringInAQuietRoomIsHeard() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        let silent = frame(-75, low: 0.3, zcr: 3_000, periodic: 0.05)
        feed(&engine, silent, for: 10, t: &t)
        breathe(&engine, breaths: 8, period: 4, snore: frame(-66), background: silent, t: &t)
        engine.finish()
        XCTAssertEqual(engine.episodes.count, 1)
        XCTAssertEqual(engine.episodes.first?.loudness, .quiet)
    }

    /// A fan that starts mid-night becomes the room, and snoring on top of it
    /// is still found. The old detector saw a fan as one sound that never
    /// ended, so it never found the start of another.
    func testAFanBecomesTheRoomAndSnoringAboveItIsStillHeard() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        let fan = frame(-45, low: 0.7, zcr: 900, periodic: 0.3)
        feed(&engine, fan, for: 90, t: &t)
        XCTAssertEqual(engine.floorDB ?? -120, -45, accuracy: 3)
        XCTAssertEqual(engine.candidateCount, 0, "a fan is not a snore")
        breathe(&engine, breaths: 8, period: 4, snore: frame(-34), background: fan, t: &t)
        engine.finish()
        XCTAssertEqual(engine.episodes.count, 1)
    }

    func testIrregularBurstsLikeSpeechAreNotAnEpisode() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        let word = frame(-40, low: 0.6, zcr: 1_200, periodic: 0.5)
        // Onset gaps of 0.9, 0.8, 3.9, 0.7, 5.8 seconds: never three in a row
        // at a breathing interval.
        for gap in [0.9, 0.8, 3.9, 0.7, 5.8, 0.6] {
            feed(&engine, word, for: 0.4, t: &t)
            feed(&engine, quiet, for: gap - 0.4, t: &t)
        }
        feed(&engine, quiet, for: 20, t: &t)
        engine.finish()
        XCTAssertTrue(engine.episodes.isEmpty)
    }

    func testIrregularIntervalsDoNotOpenAnEpisode() {
        var engine = SnoreAcousticEngine()
        let events = [0.0, 2.0, 9.0].map {
            SnoreSoundEvent(start: $0, end: $0 + 1, score: 0.8, peakAboveFloorDB: 15)
        }
        for event in events { engine.register(event) }
        XCTAssertFalse(engine.isInEpisode, "2 s then 7 s is not one breathing rhythm")
    }

    func testAMissedBreathKeepsTheEpisodeOpen() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        breathe(&engine, breaths: 5, period: 4, snore: frame(-40), background: quiet, t: &t)
        feed(&engine, quiet, for: 4, t: &t)
        breathe(&engine, breaths: 5, period: 4, snore: frame(-40), background: quiet, t: &t)
        engine.finish()
        XCTAssertEqual(engine.episodes.count, 1)
    }

    func testALongSilenceEndsTheEpisodeAndANewOneOpens() {
        var engine = SnoreAcousticEngine()
        var t: TimeInterval = 0
        feed(&engine, quiet, for: 10, t: &t)
        breathe(&engine, breaths: 6, period: 4, snore: frame(-40), background: quiet, t: &t)
        feed(&engine, quiet, for: 60, t: &t)
        XCTAssertFalse(engine.isInEpisode)
        breathe(&engine, breaths: 6, period: 4, snore: frame(-30), background: quiet, t: &t)
        engine.finish()
        XCTAssertEqual(engine.episodes.count, 2)
        XCTAssertEqual(engine.episodes.last?.loudness, .loud)
    }

    func testLoudnessBands() {
        XCTAssertEqual(SnoreLoudness(peakAboveFloorDB: 8), .quiet)
        XCTAssertEqual(SnoreLoudness(peakAboveFloorDB: 15), .moderate)
        XCTAssertEqual(SnoreLoudness(peakAboveFloorDB: 30), .loud)
        XCTAssertLessThan(SnoreLoudness.quiet, SnoreLoudness.loud)
    }
}
