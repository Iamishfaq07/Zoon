import Foundation
import AVFoundation
import os

/// Estimates snoring, on-device, from the phone's microphone.
///
/// ## What this is not
///
/// Not a trained classifier — Zoon bundles no ML model and downloads
/// nothing, so there is no "this sound is a snore" network to ask. What runs
/// here is a heuristic: periodic low-frequency energy bursts, a rough proxy
/// for the amplitude pattern snoring produces. It will miss snores and will
/// occasionally flag other repetitive low sounds (a fan, someone's breathing
/// against a pillow). Every screen that shows a snore-minutes number says
/// "estimate" next to it for exactly this reason — the app's standing rule
/// is to never present an invented or unreliable number as a measured one,
/// and a heuristic result is closer to invented than to measured.
///
/// ## What never happens
///
/// Raw audio is processed in ~100ms buffers and **discarded immediately**
/// after each buffer's energy is measured. Nothing is written to disk,
/// nothing is buffered beyond the current tick. What survives the session is
/// a per-night minute count (see `SnoreStore`) and, since `SoundEventClassifier`
/// was added, a short list of *categorized* moments -- "snoring" or
/// "coughing" and a timestamp, from Apple's on-device sound classifier
/// running on the same buffers, never audio itself (see `SoundEventStore`).
/// This is the one feature in Zoon that asks for a new, more sensitive
/// permission than everything else combined, and the privacy design here is
/// deliberately stricter than the rest of the app's already-strict baseline:
/// a partner or roommate's voice must never be capturable even in principle,
/// because they never consented to anything -- which is exactly why the
/// classifier is deliberately never asked about speech, only about sounds
/// tied to the user's own sleep (see `SoundEventClassifier`).
@MainActor
@Observable
final class SnoreDetector {

    private(set) var isRunning = false
    private(set) var monitoredSeconds: Double = 0
    private(set) var snoreSeconds: Double = 0
    /// Categorized sound events recognized so far this session -- see
    /// `SoundEventClassifier`. Same tap, same session, second observer.
    private(set) var recentEvents: [SoundEvent] = []

    private let engine = AVAudioEngine()
    private let soundClassifier = SoundEventClassifier()
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "SnoreDetector")

    // MARK: - Heuristic state
    //
    // A snore reads as a burst of low-frequency energy roughly every 2-6
    // seconds, sustained for several breaths. Single loud spikes (a door, a
    // cough) don't repeat on that cadence and are rejected; this is what
    // separates "one loud sound" from "a snoring pattern" without needing a
    // trained model.

    private var burstTimestamps: [Date] = []
    private let burstThresholdRMS: Float = 0.02
    private let minimumLowFrequencyRatio: Float = 0.45
    private let minBurstGap: TimeInterval = 1.2
    private let maxBurstGap: TimeInterval = 6.0
    private var lastBurst: Date?
    private var isInsideBurst = false
    private var tickAccumulator: TimeInterval = 0
    private let tickInterval: TimeInterval = 1.0

    var isAvailable: Bool {
        AVAudioApplication.shared.recordPermission != .denied
    }

    /// Requests microphone access. Returns `true` only on an explicit grant —
    /// same shape as `BedtimeReminder.requestAuthorization`, asked for at the
    /// moment the user starts a session, never at launch.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        monitoredSeconds = 0
        snoreSeconds = 0
        burstTimestamps.removeAll()
        lastBurst = nil
        isInsideBurst = false
        tickAccumulator = 0
        recentEvents.removeAll()

        soundClassifier.start(format: format) { [weak self] identifier, confidence in
            Task { @MainActor [weak self] in
                self?.recordEvent(identifier: identifier, confidence: confidence)
            }
        }

        // ~100ms buffers: short enough that nothing meaningful survives one
        // tick, long enough for a stable RMS reading.
        input.installTap(onBus: 0, bufferSize: 4800, format: format) { [weak self] buffer, time in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let energy = SnoreSignalAnalyzer.energy(
                samples: samples,
                sampleRate: format.sampleRate
            )
            let bufferSeconds = Double(buffer.frameLength) / format.sampleRate
            self?.soundClassifier.process(buffer, atFramePosition: time.sampleTime)
            Task { @MainActor [weak self] in
                self?.process(energy: energy, elapsed: bufferSeconds)
            }
        }

        try engine.start()
        isRunning = true
        logger.info("Snore detection started")
    }

    func stop() -> SnoreStore.NightSummary? {
        guard isRunning else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        soundClassifier.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
        logger.info("Snore detection stopped")

        guard monitoredSeconds > 0 else { return nil }
        return SnoreStore.NightSummary(
            date: Calendar.current.startOfDay(for: .now),
            monitoredMinutes: monitoredSeconds / 60,
            snoreMinutes: snoreSeconds / 60
        )
    }

    /// Collapses repeats of the same category within a short window into the
    /// one event they actually are -- a several-second snore or cough spans
    /// many ~1-second analysis windows, and without this it would register
    /// as a dozen near-identical events instead of one.
    private func recordEvent(identifier: String, confidence: Double) {
        if let last = recentEvents.last,
           last.identifier == identifier,
           Date.now.timeIntervalSince(last.date) < 5 {
            return
        }
        recentEvents.append(SoundEvent(identifier: identifier, confidence: confidence))
        if recentEvents.count > 200 {
            recentEvents.removeFirst(recentEvents.count - 200)
        }
    }

    // MARK: - Processing

    private func process(energy: SnoreSignalAnalyzer.Energy, elapsed: Double) {
        monitoredSeconds += elapsed
        tickAccumulator += elapsed

        let qualifiesAsLowBurst = energy.broadbandRMS >= burstThresholdRMS
            && energy.lowFrequencyRatio >= minimumLowFrequencyRatio

        // Register the leading edge once. Updating `lastBurst` for every loud
        // 100 ms buffer makes a one-second snore continually reset its own gap,
        // so no later burst can ever satisfy the 1.2-second cadence floor.
        if qualifiesAsLowBurst && !isInsideBurst {
            let now = Date.now
            if let last = lastBurst {
                let gap = now.timeIntervalSince(last)
                if gap >= minBurstGap && gap <= maxBurstGap {
                    burstTimestamps.append(now)
                } else if gap > maxBurstGap {
                    burstTimestamps = [now]
                }
            } else {
                burstTimestamps = [now]
            }
            lastBurst = now
        }
        isInsideBurst = qualifiesAsLowBurst

        // Three or more bursts on a snore-like cadence counts the elapsed
        // second as snoring. Requiring a run of bursts, not a single one, is
        // what keeps a single cough or a slammed door from registering.
        guard tickAccumulator >= tickInterval else { return }
        if burstTimestamps.count >= 3 {
            snoreSeconds += tickAccumulator
        }
        tickAccumulator = 0
        // Bursts older than the max gap no longer support an ongoing pattern.
        let cutoff = Date.now.addingTimeInterval(-maxBurstGap)
        burstTimestamps.removeAll { $0 < cutoff }
    }

}
