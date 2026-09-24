import AVFoundation
import XCTest

/// Audit §9.1 and §9.2: recorded beds loop without an audible join, and the
/// generated noise is deterministic, bounded and continuous across buffers
/// now that it is rendered off the main actor.
final class SeamlessAudioTests: XCTestCase {

    // MARK: - SeamlessLoop

    /// A sine whose period does not divide the length: played end to start
    /// as-is, the join is a jump no adjacent pair of frames inside it makes.
    private func sine(frames: Int, period: Double) -> [Float] {
        (0..<frames).map { Float(0.8 * sin(2 * Double.pi * Double($0) / period)) }
    }

    func testARawSineHasAnAudibleJoin() {
        let source = sine(frames: 10_000, period: 333.7)
        XCTAssertGreaterThan(
            SeamlessLoop.seamStep(source),
            SeamlessLoop.largestInteriorStep(source) * 5,
            "precondition: the unprocessed join is a click"
        )
    }

    func testTheLoopJoinIsNoLargerThanAStepInsideTheRecording() throws {
        let source = sine(frames: 10_000, period: 333.7)
        let loop = try XCTUnwrap(SeamlessLoop.make(source, crossfadeFrames: 1_000))
        XCTAssertLessThanOrEqual(
            SeamlessLoop.seamStep(loop),
            SeamlessLoop.largestInteriorStep(source) + 1e-3
        )
    }

    func testTheLoopIsTheRecordingOutsideTheCrossfade() throws {
        let source = sine(frames: 10_000, period: 333.7)
        let c = 1_000
        let loop = try XCTUnwrap(SeamlessLoop.make(source, crossfadeFrames: c))
        XCTAssertEqual(loop.count, source.count - c)
        for i in stride(from: 0, to: source.count - 2 * c, by: 97) {
            XCTAssertEqual(loop[i], source[i + c])
        }
    }

    func testTooShortToLoopIsRefusedNotMangled() {
        XCTAssertNil(SeamlessLoop.make([0.1, 0.2, 0.3], crossfadeFrames: 2))
        XCTAssertNil(SeamlessLoop.make([0.1, 0.2, 0.3], crossfadeFrames: 0))
        var samples: [Float] = [0.1, 0.2, 0.3]
        XCTAssertFalse(SeamlessLoop.makeInPlace(&samples, crossfadeFrames: 2))
        XCTAssertEqual(samples, [0.1, 0.2, 0.3])
    }

    /// Equal-power fading keeps a noise-like bed at the same loudness through
    /// the join instead of dipping, which would be heard every loop.
    func testLoudnessHoldsThroughTheCrossfade() throws {
        var generator = NoiseGenerator(seed: 7)
        let source = generator.render(.white, frames: 200_000).left
        let c = 40_000
        let loop = try XCTUnwrap(SeamlessLoop.make(source, crossfadeFrames: c))
        func rms(_ slice: ArraySlice<Float>) -> Double {
            (slice.reduce(0) { $0 + Double($1 * $1) } / Double(slice.count)).squareRoot()
        }
        let body = rms(loop[0..<(loop.count - c)])
        let fade = rms(loop[(loop.count - c)...])
        let decibels = 20 * log10(fade / body)
        XCTAssertLessThan(abs(decibels), 1.0, "crossfade changes loudness by \(decibels) dB")
    }

    /// Every bundled bed, decoded the way the engine decodes it. Before: the
    /// raw file's end-to-start step. After: the loop's. Printed for the audit
    /// report; asserted to be no larger than a step inside the loop.
    func testEveryBundledBedLoopsWithoutAClick() async throws {
        let soundsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Zoon/Sounds", isDirectory: true)
        var checked = 0
        for sound in SoundscapeEngine.Sound.allCases {
            guard let name = sound.fileName else { continue }
            let url = soundsDir.appendingPathComponent("\(name).mp3", isDirectory: false)
            guard let raw = Self.rawChannel(url) else {
                throw XCTSkip("Cannot read \(url.path) from the test process")
            }
            let decoded = await RecordedLoopLoader.decode(url: url)
            let loop = try XCTUnwrap(decoded?.channels.first, "\(name) did not decode")
            let before = SeamlessLoop.seamStep(raw)
            let after = SeamlessLoop.seamStep(loop)
            let interior = SeamlessLoop.largestInteriorStep(loop)
            print(String(format: "SEAM %@ before=%.4f after=%.4f interiorMax=%.4f", name, before, after, interior))
            XCTAssertLessThanOrEqual(after, interior, "\(name) join is larger than any step inside it")
            XCTAssertEqual(
                Double(raw.count - loop.count),
                (decoded?.sampleRate ?? 0) * SeamlessLoop.defaultCrossfadeSeconds,
                accuracy: 1,
                "\(name) loop should be the file minus one crossfade"
            )
            checked += 1
        }
        XCTAssertEqual(checked, SoundscapeEngine.Sound.allCases.filter { $0.fileName != nil }.count)
    }

    private static func rawChannel(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
    }

    // MARK: - NoiseGenerator

    private let kinds: [NoiseGenerator.Kind] = [.white, .pink, .brown]

    func testTheSameSeedRendersTheSameNoise() {
        for kind in kinds {
            var a = NoiseGenerator(seed: 42)
            var b = NoiseGenerator(seed: 42)
            var c = NoiseGenerator(seed: 43)
            let first = a.render(kind, frames: 4_096)
            XCTAssertEqual(first.left, b.render(kind, frames: 4_096).left)
            XCTAssertNotEqual(first.left, c.render(kind, frames: 4_096).left)
        }
    }

    /// Filter state carries from one buffer to the next, so two five-second
    /// buffers are sample-for-sample one ten-second render: nothing at the
    /// boundary to hear.
    func testBuffersJoinExactlyAsOneContinuousRender() {
        for kind in kinds {
            for presence: Float in [1, 0.5] {
                var split = NoiseGenerator(seed: 9)
                var whole = NoiseGenerator(seed: 9)
                let a = split.render(kind, frames: 3_000, harmonicPresence: presence)
                let b = split.render(kind, frames: 3_000, harmonicPresence: presence)
                let joined = whole.render(kind, frames: 6_000, harmonicPresence: presence)
                XCTAssertEqual(a.left + b.left, joined.left, "\(kind) at presence \(presence)")
                XCTAssertEqual(a.right + b.right, joined.right, "\(kind) at presence \(presence)")
            }
        }
    }

    func testEverySampleIsInRange() {
        for kind in kinds {
            var generator = NoiseGenerator(seed: 3)
            let rendered = generator.render(kind, frames: 44_100 * 5)
            XCTAssertLessThanOrEqual(rendered.left.map(abs).max() ?? 2, 1, "\(kind)")
            XCTAssertLessThanOrEqual(rendered.right.map(abs).max() ?? 2, 1, "\(kind)")
        }
    }

    /// Leaked integration keeps brown noise centred over a long session.
    func testBrownNoiseDoesNotDriftIntoAnOffset() {
        var generator = NoiseGenerator(seed: 11)
        let minute = generator.render(.brown, frames: 44_100 * 60).left
        let mean = minute.reduce(0, +) / Float(minute.count)
        XCTAssertLessThan(abs(mean), 0.05)
    }

    /// The three colours are actually different: successive samples are
    /// more alike the darker the noise.
    func testDarkerNoiseIsSmoother() {
        func lagOneCorrelation(_ kind: NoiseGenerator.Kind) -> Double {
            var generator = NoiseGenerator(seed: 5)
            let x = generator.render(kind, frames: 100_000).left.map(Double.init)
            let mean = x.reduce(0, +) / Double(x.count)
            var numerator = 0.0
            var denominator = 0.0
            for i in 1..<x.count { numerator += (x[i] - mean) * (x[i - 1] - mean) }
            for value in x { denominator += (value - mean) * (value - mean) }
            return numerator / denominator
        }
        let white = lagOneCorrelation(.white)
        let pink = lagOneCorrelation(.pink)
        let brown = lagOneCorrelation(.brown)
        XCTAssertLessThan(abs(white), 0.05)
        XCTAssertGreaterThan(pink, white)
        XCTAssertGreaterThan(brown, pink)
    }

    /// Lower harmonic presence (the sleep-onset cue) removes high-frequency
    /// energy rather than just lowering volume.
    func testLowerPresenceStripsHighFrequencies() {
        func meanStep(_ presence: Float) -> Float {
            var generator = NoiseGenerator(seed: 13)
            let x = generator.render(.white, frames: 50_000, harmonicPresence: presence).left
            var total: Float = 0
            for i in 1..<x.count { total += abs(x[i] - x[i - 1]) }
            return total / Float(x.count - 1)
        }
        XCTAssertLessThan(meanStep(0.45), meanStep(1) * 0.6)
    }

    func testTheRandomSourceIsUniformInRange() {
        var random = NoiseGenerator.Random(seed: 1)
        var sum: Float = 0
        var lowest: Float = 0
        var highest: Float = 0
        for _ in 0..<100_000 {
            let value = random.signed()
            lowest = min(lowest, value)
            highest = max(highest, value)
            sum += value
        }
        XCTAssertGreaterThanOrEqual(lowest, -1)
        XCTAssertLessThan(highest, 1)
        XCTAssertLessThan(abs(sum / 100_000), 0.01)
    }

    /// For the report: how long one five-second buffer takes to render, now
    /// off the main actor. Not asserted -- simulator timing is not device
    /// timing.
    func testRenderCostIsReported() {
        var generator = NoiseGenerator(seed: 1)
        let start = Date()
        for kind in kinds { _ = generator.render(kind, frames: 44_100 * 5) }
        let milliseconds = Date().timeIntervalSince(start) * 1000 / Double(kinds.count)
        print(String(format: "NOISE-RENDER 5s buffer ms=%.1f", milliseconds))
    }
}
