import XCTest

/// Turning classified moments into things that happened.
///
/// `SoundAnalysis` classifies a short buffer at a time, so twenty minutes of
/// snoring arrives as several hundred events a second or two apart. The list
/// that produced was not merely long: forty rows *look* like forty things
/// that happened, when they are one thing sampled forty times, and the number
/// is a property of the classifier's buffer size rather than of the night.
final class SoundEventClusterTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// `count` events of one kind, `every` seconds apart, starting at
    /// `after` seconds past `base`.
    private func run(
        _ identifier: String,
        count: Int,
        every seconds: TimeInterval = 2,
        after offset: TimeInterval = 0,
        confidence: (Int) -> Double = { _ in 0.8 }
    ) -> [SoundEvent] {
        (0..<count).map { index in
            SoundEvent(
                date: base.addingTimeInterval(offset + Double(index) * seconds),
                identifier: identifier,
                confidence: confidence(index)
            )
        }
    }

    // MARK: - One thing, sampled many times

    func testTwentyMinutesOfSnoringIsOneEpisode() throws {
        let clusters = SoundEvent.clusters(from: run("snoring", count: 600))
        XCTAssertEqual(clusters.count, 1, "600 samples became \(clusters.count) rows")

        let episode = try XCTUnwrap(clusters.first)
        XCTAssertEqual(episode.minutes, 19.97, accuracy: 0.05)
        XCTAssertEqual(episode.count, 600)
        XCTAssertFalse(episode.isMomentary)
    }

    /// The threshold doing its job in the other direction: a real silence is
    /// a real break, and stitching across it would report one long episode
    /// where there were two.
    func testASilenceLongerThanTheGapStartsANewEpisode() {
        let events = run("snoring", count: 60)
            + run("snoring", count: 60, after: SoundEvent.clusterGap + 600)
        XCTAssertEqual(SoundEvent.clusters(from: events).count, 2)
    }

    /// A pause shorter than the gap -- turning over, changing position -- is
    /// the case the threshold exists to stitch across.
    func testAShortPauseDoesNotSplitAnEpisode() {
        let events = run("snoring", count: 60)
            + run("snoring", count: 60, after: SoundEvent.clusterGap - 60)
        XCTAssertEqual(SoundEvent.clusters(from: events).count, 1)
    }

    // MARK: - Different sounds are different things

    /// The reason clustering is per identifier rather than over one
    /// interleaved sequence. A cough in the middle of snoring is a separate
    /// thing happening in the same stretch of night; splitting the snoring
    /// around it would report three episodes where there were two.
    func testACoughInTheMiddleDoesNotSplitTheSnoring() throws {
        let events = run("snoring", count: 300)
            + [SoundEvent(date: base.addingTimeInterval(300), identifier: "cough", confidence: 0.95)]
        let clusters = SoundEvent.clusters(from: events)

        XCTAssertEqual(clusters.count, 2)
        let snoring = try XCTUnwrap(clusters.first { $0.identifier == "snoring" })
        XCTAssertEqual(snoring.count, 300, "the snoring run was split by the cough")
    }

    func testClustersComeBackInTimeOrder() {
        let events = run("cough", count: 3, every: 1, after: 900)
            + run("snoring", count: 30, after: 0)
        let starts = SoundEvent.clusters(from: events).map(\.start)
        XCTAssertEqual(starts, starts.sorted())
    }

    // MARK: - A moment is not a zero-length span

    /// "01:42 - 01:42, 0 minutes" is worse than "01:42", so a cluster with no
    /// real extent says so and the view renders it as a time.
    func testAnIsolatedEventIsAMomentRatherThanAnEmptySpan() throws {
        let clusters = SoundEvent.clusters(
            from: [SoundEvent(date: base, identifier: "baby_cry_infant_cry", confidence: 0.6)]
        )
        let moment = try XCTUnwrap(clusters.first)
        XCTAssertTrue(moment.isMomentary)
        XCTAssertEqual(moment.duration, 0)
        XCTAssertEqual(moment.count, 1)
        XCTAssertEqual(moment.label, "Baby crying", "a cluster must render like the events in it")
    }

    // MARK: - Confidence

    /// Peak rather than mean, and this is the case that decides it. A run's
    /// trailing edge is where the sound fades and the classifier is least
    /// sure, so an average drags a confident detection down in proportion to
    /// how long it lasted -- making a long, obvious episode look *less*
    /// certain than a short one.
    func testConfidenceIsThePeakNotTheAverage() throws {
        let fading = run("snoring", count: 100) { index in 0.95 - 0.5 * (Double(index) / 100) }
        let episode = try XCTUnwrap(SoundEvent.clusters(from: fading).first)

        let mean = fading.map(\.confidence).reduce(0, +) / Double(fading.count)
        XCTAssertEqual(episode.peakConfidence, 0.95, accuracy: 0.001)
        XCTAssertGreaterThan(episode.peakConfidence, mean + 0.2, "the mean would have reported this as marginal")
    }

    // MARK: - Edges

    func testNoEventsProduceNoClusters() {
        XCTAssertTrue(SoundEvent.clusters(from: []).isEmpty)
    }

    /// Events arrive from a store that makes no ordering promise, so the
    /// clustering sorts rather than assuming.
    func testUnorderedInputClustersTheSameAsOrderedInput() {
        let ordered = run("snoring", count: 40)
        let shuffled = ordered.reversed().map { $0 }
        XCTAssertEqual(
            SoundEvent.clusters(from: shuffled).map(\.count),
            SoundEvent.clusters(from: ordered).map(\.count)
        )
    }

    /// The identity has to survive a redraw, or a list keyed on it
    /// re-animates every row whenever the view updates.
    func testAClustersIdentityIsStableAcrossRecomputation() {
        let events = run("snoring", count: 40)
        XCTAssertEqual(
            SoundEvent.clusters(from: events).map(\.id),
            SoundEvent.clusters(from: events).map(\.id)
        )
    }
}
