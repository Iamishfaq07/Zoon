import Foundation
import AVFoundation
import os

/// Sleep sounds, synthesised in real time.
///
/// Every soundscape here is **generated**, not played back from a file. That's
/// unusual, and it's the right call for three reasons:
///
/// 1. **No assets.** A decent sleep-sound library is 50–200 MB of loops. This is
///    a few hundred lines of DSP and adds nothing to the download.
/// 2. **No loop seam.** Recorded ambience repeats every few minutes and, once
///    you notice the seam, you cannot un-notice it. Noise generated per-buffer
///    never repeats.
/// 3. **It fits the app's promise.** No network, no bundled media, nothing
///    phoning home for a stream.
///
/// The synthesis is deliberately simple — filtered noise, not physical modelling.
/// Brown noise for rumble, filtered and amplitude-modulated noise for rain and
/// waves. It sounds convincing at sleep volume, which is the only volume it will
/// ever be heard at.
@MainActor
@Observable
final class SoundscapeEngine {

    enum Sound: String, CaseIterable, Identifiable, Sendable {
        case brownNoise
        case pinkNoise
        case whiteNoise
        case rain
        case ocean
        case wind
        case fan

        var id: String { rawValue }

        var label: String {
            switch self {
            case .brownNoise: "Brown Noise"
            case .pinkNoise: "Pink Noise"
            case .whiteNoise: "White Noise"
            case .rain: "Rain"
            case .ocean: "Ocean"
            case .wind: "Wind"
            case .fan: "Fan"
            }
        }

        var detail: String {
            switch self {
            case .brownNoise: "Deep, low rumble. The most masking of the three noises."
            case .pinkNoise: "Balanced hiss. Often the most natural-sounding."
            case .whiteNoise: "Bright and flat. Best at masking sharp sounds."
            case .rain: "Steady rainfall with irregular gusts."
            case .ocean: "Slow swell, breaking roughly every ten seconds."
            case .wind: "Distant, shifting wind."
            case .fan: "Low motor hum with a soft rotational beat."
            }
        }

        var symbol: String {
            switch self {
            case .brownNoise: "waveform.path"
            case .pinkNoise: "waveform"
            case .whiteNoise: "waveform.badge.plus"
            case .rain: "cloud.rain.fill"
            case .ocean: "water.waves"
            case .wind: "wind"
            case .fan: "fan.fill"
            }
        }
    }

    // MARK: - Observable state

    private(set) var playing: Sound?
    var volume: Float = 0.6 {
        didSet { player?.volume = volume * fadeMultiplier }
    }

    /// Minutes until auto-stop. `nil` = no timer.
    private(set) var timerMinutes: Int?
    private(set) var remainingSeconds: Int = 0

    var isPlaying: Bool { playing != nil }

    // MARK: - Audio graph

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var timerTask: Task<Void, Never>?
    private var fadeMultiplier: Float = 1
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "Soundscape")

    private let sampleRate: Double = 44_100
    /// Five seconds per buffer. Long enough that scheduling overhead is
    /// negligible, short enough that stopping feels immediate.
    private let bufferSeconds: Double = 5

    // MARK: - Control

    func play(_ sound: Sound) {
        if playing == sound { stop(); return }
        stop()

        do {
            // `.playback` with `.mixWithOthers` so a soundscape doesn't kill a
            // podcast someone is already falling asleep to, and keeps running
            // when the screen locks.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 2
            ) else { return }

            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()

            player.volume = volume * fadeMultiplier
            player.play()

            self.engine = engine
            self.player = player
            self.playing = sound

            // Prime with a few buffers, then keep the queue topped up as each
            // one finishes. Scheduling one at a time would gap on a slow frame.
            for _ in 0..<3 { scheduleBuffer(sound, format: format) }
        } catch {
            logger.error("Audio start failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        playing = nil
        timerMinutes = nil
        remainingSeconds = 0
        fadeMultiplier = 1
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Auto-stop after `minutes`, with a fade over the final 60 seconds.
    ///
    /// The fade matters more than it sounds: an abrupt cut at the end of a sleep
    /// timer is itself capable of waking someone, which defeats the entire point.
    func setTimer(minutes: Int?) {
        timerTask?.cancel()
        timerMinutes = minutes
        fadeMultiplier = 1
        player?.volume = volume

        guard let minutes else {
            remainingSeconds = 0
            return
        }

        remainingSeconds = minutes * 60
        // Task{} started from a @MainActor method inherits that isolation, so
        // the properties below are reached synchronously — only the sleep
        // actually suspends.
        timerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self, self.remainingSeconds > 0 else { break }
                self.tick()
            }
            self?.stop()
        }
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds -= 1

        // Linear fade across the last minute.
        let fadeWindow = 60
        if remainingSeconds <= fadeWindow {
            fadeMultiplier = Float(remainingSeconds) / Float(fadeWindow)
            player?.volume = volume * fadeMultiplier
        }
    }

    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Synthesis

    private func scheduleBuffer(_ sound: Sound, format: AVAudioFormat) {
        guard let player, let buffer = makeBuffer(sound, format: format) else { return }

        player.scheduleBuffer(buffer) { [weak self] in
            // Completion fires on an audio thread; hop back before touching
            // any of this actor's state.
            Task { @MainActor [weak self] in
                guard let self, self.playing == sound else { return }
                self.scheduleBuffer(sound, format: format)
            }
        }
    }

    /// Generator state carried across buffers so filters don't click at seams.
    private var brownState: Float = 0
    private var pinkRows = [Float](repeating: 0, count: 7)
    private var lowpassState: Float = 0
    private var phase: Double = 0

    private func makeBuffer(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * bufferSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = frameCount
        let left = channels[0]
        let right = channels[1]

        for frame in 0..<Int(frameCount) {
            let white = Float.random(in: -1...1)
            var sample: Float

            switch sound {
            case .whiteNoise:
                sample = white * 0.25

            case .pinkNoise:
                // Voss-McCartney: sum of octave-spaced random rows. Cheaper and
                // more stable than an IIR pink filter.
                sample = pinkSample(white) * 0.16

            case .brownNoise:
                // Integrated white noise, leaked toward zero so it can't drift
                // into DC offset over a long session.
                brownState = (brownState + white * 0.02) * 0.995
                sample = brownState * 2.4

            case .rain:
                // Bright filtered noise plus sparse transients for droplets.
                let filtered = lowpass(white, coefficient: 0.55)
                let droplet = Float.random(in: 0...1) > 0.9992 ? white * 0.5 : 0
                sample = (filtered * 0.28 + droplet)

            case .ocean:
                // Brown-ish noise amplitude-modulated by a slow swell. ~11s
                // period, which is roughly real ocean and slow enough to breathe
                // with rather than count.
                brownState = (brownState + white * 0.02) * 0.995
                phase += 1 / (sampleRate * 11)
                if phase > 1 { phase -= 1 }
                let swell = Float(pow(sin(phase * 2 * .pi) * 0.5 + 0.5, 2.5))
                sample = brownState * 2.6 * (0.25 + swell * 0.9)

            case .wind:
                // Lowpassed noise with a slowly wandering cutoff.
                phase += 1 / (sampleRate * 7)
                if phase > 1 { phase -= 1 }
                let cutoff = Float(0.06 + 0.05 * (sin(phase * 2 * .pi) * 0.5 + 0.5))
                sample = lowpass(white, coefficient: cutoff) * 3.2

            case .fan:
                // Motor hum: heavily lowpassed noise with a shallow rotational
                // amplitude beat.
                phase += 1 / (sampleRate * 0.14)
                if phase > 1 { phase -= 1 }
                let beat = Float(0.88 + 0.12 * sin(phase * 2 * .pi))
                sample = lowpass(white, coefficient: 0.08) * 3.0 * beat
            }

            sample = max(-1, min(1, sample))

            // Slight stereo decorrelation. Identical channels image as a point
            // inside your head, which is fatiguing; a touch of difference makes
            // it sit around you instead.
            left[frame] = sample
            right[frame] = sample * 0.92 + Float.random(in: -0.02...0.02)
        }

        return buffer
    }

    private func pinkSample(_ white: Float) -> Float {
        var sum: Float = 0
        for row in 0..<pinkRows.count {
            // Each row updates half as often as the one before it.
            if Int.random(in: 0..<(1 << row)) == 0 {
                pinkRows[row] = Float.random(in: -1...1)
            }
            sum += pinkRows[row]
        }
        return (sum / Float(pinkRows.count)) + white * 0.1
    }

    private func lowpass(_ input: Float, coefficient: Float) -> Float {
        lowpassState += coefficient * (input - lowpassState)
        return lowpassState
    }
}
