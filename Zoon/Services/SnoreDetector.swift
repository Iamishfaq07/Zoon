import Foundation
import AVFoundation
import os

/// Estimates snoring, on-device, from the phone's microphone.
///
/// Apple's SoundAnalysis classifier is the primary snoring evidence when
/// the taxonomy includes `"snoring"`. The heuristic is corroboration and
/// the fallback. Raw audio is processed in ~100ms buffers and discarded.
@MainActor
@Observable
final class SnoreDetector {
    private let audioOwner = UUID()

    private(set) var isRunning = false
    private(set) var monitoredSeconds: Double = 0
    private(set) var snoreSeconds: Double = 0
    private(set) var heuristicSnoreSeconds: Double = 0
    private(set) var classifierSnoreSeconds: Double = 0
    private(set) var recentEvents: [SoundEvent] = []
    private(set) var lastBufferAt: Date?
    private(set) var classifierAvailable = false
    private(set) var classifierSupportsSnoring = false
    private(set) var classifierWindows: [SnoreClassificationWindow] = []

    private var engine = AVAudioEngine()
    private let soundClassifier = SoundEventClassifier()
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "SnoreDetector")
    private var tapInstalled = false
    private var cadence = SnoreCadenceTracker()
    private var lastBurst: TimeInterval?
    private var isInsideBurst = false
    private var tickAccumulator: TimeInterval = 0
    private let tickInterval: TimeInterval = 1.0
    private var sessionStartedAt: Date?
    var onPaused: (() -> Void)?
    var onResumed: (() -> Void)?
    private let burstThresholdRMS: Float = 0.02
    private let minimumLowFrequencyRatio: Float = 0.45

    var isAudioArriving: Bool {
        guard let lastBufferAt else { return false }
        return Date.now.timeIntervalSince(lastBufferAt) < 1.5
    }

    var sessionConfidence: SnoreMonitoringConfidence {
        SnoreEpisodeAggregator.confidence(
            classifierAvailable: classifierAvailable,
            classifierSupportsSnoring: classifierSupportsSnoring,
            monitoredSeconds: monitoredSeconds,
            lastBufferAge: lastBufferAt.map { Date.now.timeIntervalSince($0) },
            heuristicSeconds: heuristicSnoreSeconds,
            classifierSeconds: classifierSnoreSeconds
        )
    }

    var isAvailable: Bool {
        AVAudioApplication.shared.recordPermission != .denied
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start(resetAccumulators: Bool = true) throws {
        guard !isRunning else { return }

        try AudioSessionCoordinator.shared.acquire(
            audioOwner,
            recording: true,
            onInterrupt: { [weak self] in self?.pauseWithoutFinalizing() },
            onResume: { [weak self] in try? self?.resumeListening() },
            onReset: { [weak self] in try? self?.rebuildEngineAndRestart() }
        )

        if resetAccumulators {
            monitoredSeconds = 0
            snoreSeconds = 0
            heuristicSnoreSeconds = 0
            classifierSnoreSeconds = 0
            cadence = SnoreCadenceTracker()
            lastBurst = nil
            isInsideBurst = false
            tickAccumulator = 0
            recentEvents.removeAll()
            classifierWindows.removeAll()
            lastBufferAt = nil
            sessionStartedAt = .now
        }

        try installTapAndStartEngine()
        isRunning = true
        logger.info("Snore detection started")
    }

    func pauseWithoutFinalizing() {
        guard isRunning else { return }
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        isRunning = false
        onPaused?()
        logger.info("Snore detection paused without finalizing")
    }

    func resumeListening() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        try installTapAndStartEngine()
        isRunning = true
        onResumed?()
        logger.info("Snore detection resumed")
    }

    func rebuildEngineAndRestart() throws {
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        engine = AVAudioEngine()
        try AVAudioSession.sharedInstance().setActive(true)
        try installTapAndStartEngine()
        isRunning = true
        logger.info("Snore detection rebuilt after media-services reset")
    }

    func stop() -> SnoreStore.NightSummary? {
        guard isRunning || monitoredSeconds > 0 else { return nil }
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        AudioSessionCoordinator.shared.release(audioOwner)
        isRunning = false
        logger.info("Snore detection stopped")

        classifierSnoreSeconds = SnoreEpisodeAggregator.snoreSeconds(from: classifierWindows)
        if classifierAvailable, classifierSupportsSnoring {
            snoreSeconds = max(classifierSnoreSeconds, heuristicSnoreSeconds)
        } else {
            snoreSeconds = heuristicSnoreSeconds
        }

        guard monitoredSeconds > 0 else { return nil }
        let wakeInstant = Date()
        let zone = TimeZone.current
        var calendar = Calendar.current
        calendar.timeZone = zone
        return SnoreStore.NightSummary(
            date: calendar.startOfDay(for: wakeInstant),
            monitoredMinutes: monitoredSeconds / 60,
            snoreMinutes: snoreSeconds / 60,
            nightKey: NightKey.make(wakeInstant: wakeInstant, in: zone),
            timezoneIdentifier: zone.identifier
        )
    }

    private func installTapAndStartEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        soundClassifier.start(format: format) { [weak self] identifier, confidence, start, duration in
            Task { @MainActor [weak self] in
                self?.recordEvent(identifier: identifier, confidence: confidence, start: start, duration: duration)
            }
        }
        classifierAvailable = soundClassifier.isAvailable
        classifierSupportsSnoring = soundClassifier.supportsSnoring

        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
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
        tapInstalled = true
        do {
            try engine.start()
        } catch {
            removeTapIfNeeded()
            soundClassifier.stop()
            AudioSessionCoordinator.shared.release(audioOwner)
            throw error
        }
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func recordEvent(identifier: String, confidence: Double, start: TimeInterval, duration: TimeInterval) {
        classifierWindows.append(
            SnoreClassificationWindow(
                start: start,
                duration: duration,
                confidence: confidence,
                identifier: identifier
            )
        )
        classifierSnoreSeconds = SnoreEpisodeAggregator.snoreSeconds(from: classifierWindows)
        if classifierAvailable, classifierSupportsSnoring {
            snoreSeconds = max(classifierSnoreSeconds, heuristicSnoreSeconds)
        }

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

    private func process(energy: SnoreSignalAnalyzer.Energy, elapsed: Double) {
        monitoredSeconds += elapsed
        tickAccumulator += elapsed
        lastBufferAt = .now

        let qualifiesAsLowBurst = energy.broadbandRMS >= burstThresholdRMS
            && energy.lowFrequencyRatio >= minimumLowFrequencyRatio

        if qualifiesAsLowBurst && !isInsideBurst {
            let t = monitoredSeconds
            cadence.registerBurst(at: t)
            lastBurst = t
        }
        isInsideBurst = qualifiesAsLowBurst

        guard tickAccumulator >= tickInterval else { return }
        if cadence.isSnoring(at: monitoredSeconds) {
            heuristicSnoreSeconds += tickAccumulator
            if !(classifierAvailable && classifierSupportsSnoring && classifierSnoreSeconds > 0) {
                snoreSeconds = heuristicSnoreSeconds
            } else {
                snoreSeconds = max(classifierSnoreSeconds, heuristicSnoreSeconds)
            }
        }
        tickAccumulator = 0
        cadence.prune(now: monitoredSeconds)
    }
}
