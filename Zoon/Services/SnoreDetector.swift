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
    private(set) var interruptionGaps = 0
    private(set) var monitoringGaps: [SnoreMonitoringGap] = []
    private(set) var sessionID = UUID()
    private(set) var fusedIntervals: [SnoreEvidenceFusion.Interval] = []
    private(set) var frozenQuality: SnoreMonitoringConfidence?

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
    private var epoch: SoundAnalysisEpoch?
    private var heuristicIntervals: [(start: TimeInterval, end: TimeInterval)] = []
    private var heuristicOpenStart: TimeInterval?
    private var lastCheckpointAt: Date?
    private var openGapStartedAt: Date?
    private var sessionTimeZoneIdentifier: String = TimeZone.current.identifier
    /// An interruption gap stays open until the first valid buffer after a
    /// successful engine start. Closing it at `setActive` would mark the
    /// session as monitored through a failed resume.
    private var pendingGapClose = false
    var onPaused: (() -> Void)?
    var onResumed: (() -> Void)?
    private let burstThresholdRMS: Float = 0.02
    private let minimumLowFrequencyRatio: Float = 0.45
    private let eventCap = 80

    var isAudioArriving: Bool {
        guard let lastBufferAt else { return false }
        return Date.now.timeIntervalSince(lastBufferAt) < 1.5
    }

    var sessionConfidence: SnoreMonitoringConfidence {
        if let frozenQuality { return frozenQuality }
        return liveQuality
    }

    var liveQuality: SnoreMonitoringConfidence {
        SnoreEpisodeAggregator.confidence(
            classifierAvailable: classifierAvailable,
            classifierSupportsSnoring: classifierSupportsSnoring,
            monitoredSeconds: monitoredSeconds,
            lastBufferAge: lastBufferAt.map { Date.now.timeIntervalSince($0) },
            heuristicSeconds: heuristicSnoreSeconds,
            classifierSeconds: classifierSnoreSeconds,
            sessionEnded: !isRunning && monitoredSeconds > 0,
            interruptionDuration: monitoringGaps.reduce(0) { $0 + $1.duration }
        )
    }

    private var erasureObserver: NSObjectProtocol?

    init(center: NotificationCenter = .default) {
        // Delete Everything stops the microphone and throws the session
        // away rather than finalizing it. A summary produced after the erase
        // would be data Zoon kept from before it.
        erasureObserver = center.addObserver(
            forName: DataErasure.didErase, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.discard() }
        }
    }

    /// Stops capture without producing a summary, and forgets the session.
    ///
    /// For erasure: the running or paused session must not be summarised
    /// or checkpointed back into the stores that were just cleared. Resets
    /// through `resetSession`, the same block `start` uses, so a field added
    /// to the session is cleared here too.
    func discard() {
        guard isRunning || monitoredSeconds > 0 || openGapStartedAt != nil else { return }
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        AudioSessionCoordinator.shared.release(audioOwner)
        isRunning = false
        resetSession()
        logger.info("Snore detection discarded")
    }

    /// Everything one listening session accumulates, back to empty, and the
    /// crash checkpoint cleared.
    private func resetSession() {
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
        heuristicIntervals.removeAll()
        heuristicOpenStart = nil
        lastBufferAt = nil
        sessionStartedAt = .now
        sessionID = UUID()
        interruptionGaps = 0
        lastCheckpointAt = nil
        monitoringGaps = []
        openGapStartedAt = nil
        fusedIntervals = []
        frozenQuality = nil
        sessionTimeZoneIdentifier = TimeZone.current.identifier
        pendingGapClose = false
        SnoreCheckpoint.clear()
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
            resetSession()
        }

        try installTapAndStartEngine(releaseOwnerOnFailure: true)
        beginEpoch()
        isRunning = true
        persistCheckpoint(unexpectedEnd: true)
        logger.info("Snore detection started")
    }

    func pauseWithoutFinalizing() {
        guard isRunning else { return }
        closeHeuristicIfNeeded(at: monitoredSeconds)
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        isRunning = false
        interruptionGaps += 1
        openGapStartedAt = .now
        pendingGapClose = false
        persistCheckpoint(unexpectedEnd: true)
        onPaused?()
        logger.info("Snore detection paused without finalizing")
    }

    func resumeListening() throws {
        try AVAudioSession.sharedInstance().setActive(true)
        try installTapAndStartEngine(releaseOwnerOnFailure: false)
        beginEpoch()
        pendingGapClose = openGapStartedAt != nil
        isRunning = true
        persistCheckpoint(unexpectedEnd: true)
        onResumed?()
        logger.info("Snore detection resumed")
    }

    func rebuildEngineAndRestart() throws {
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        isRunning = false
        engine = AVAudioEngine()
        try AVAudioSession.sharedInstance().setActive(true)
        try installTapAndStartEngine(releaseOwnerOnFailure: false)
        beginEpoch()
        pendingGapClose = openGapStartedAt != nil
        isRunning = true
        persistCheckpoint(unexpectedEnd: true)
        logger.info("Snore detection rebuilt after media-services reset")
    }

    func stop() -> SnoreStore.NightSummary? {
        guard isRunning || monitoredSeconds > 0 else { return nil }
        closeHeuristicIfNeeded(at: monitoredSeconds)
        removeTapIfNeeded()
        engine.stop()
        soundClassifier.stop()
        AudioSessionCoordinator.shared.release(audioOwner)
        isRunning = false
        logger.info("Snore detection stopped")

        refreshFusion()
        frozenQuality = liveQuality

        persistCheckpoint(unexpectedEnd: false)
        SnoreCheckpoint.clear()

        guard monitoredSeconds > 0 else { return nil }
        let wakeInstant = Date()
        let zone = TimeZone(identifier: sessionTimeZoneIdentifier) ?? .current
        var calendar = Calendar.current
        calendar.timeZone = zone
        return SnoreStore.NightSummary(
            date: calendar.startOfDay(for: wakeInstant),
            monitoredMinutes: monitoredSeconds / 60,
            snoreMinutes: snoreSeconds / 60,
            nightKey: NightKey.make(wakeInstant: wakeInstant, in: zone),
            timezoneIdentifier: zone.identifier,
            isPartial: false,
            endedUnexpectedly: false,
            monitoringQuality: frozenQuality?.rawValue,
            interruptionDurationMinutes: monitoringGaps.reduce(0) { $0 + $1.duration } / 60
        )
    }

    /// Restores derived-only state from a crash/kill. Does not resume listening.
    func restore(from checkpoint: SnoreCheckpoint) {
        sessionID = checkpoint.sessionID
        sessionStartedAt = checkpoint.startedAt
        monitoredSeconds = checkpoint.monitoredSeconds
        snoreSeconds = checkpoint.snoreSeconds
        heuristicSnoreSeconds = checkpoint.heuristicSeconds
        classifierSnoreSeconds = checkpoint.classifierSeconds
        classifierWindows = checkpoint.windows
        interruptionGaps = checkpoint.interruptionGaps
        monitoringGaps = checkpoint.gaps
        classifierAvailable = checkpoint.classifierAvailable
        frozenQuality = checkpoint.monitoringQuality
        sessionTimeZoneIdentifier = checkpoint.timezoneIdentifier ?? TimeZone.current.identifier
        isRunning = false
    }

    private func beginEpoch() {
        epoch = SoundAnalysisEpoch.beginningNow(sessionElapsed: monitoredSeconds, now: .now)
    }

    private func closeOpenGap() {
        guard let started = openGapStartedAt else { return }
        monitoringGaps.append(SnoreMonitoringGap(startedAt: started, endedAt: .now))
        openGapStartedAt = nil
    }

    private func installTapAndStartEngine(releaseOwnerOnFailure: Bool = true) throws {
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
            if releaseOwnerOnFailure {
                AudioSessionCoordinator.shared.release(audioOwner)
            }
            throw error
        }
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func recordEvent(identifier: String, confidence: Double, start: TimeInterval, duration: TimeInterval) {
        let sessionStart = epoch?.sessionTime(local: start) ?? (monitoredSeconds)
        let eventDate = epoch?.date(local: start) ?? sessionStartedAt?.addingTimeInterval(sessionStart) ?? .now
        classifierWindows.append(
            SnoreClassificationWindow(
                start: sessionStart,
                duration: duration,
                confidence: confidence,
                identifier: identifier
            )
        )
        refreshFusion()

        if let last = recentEvents.last,
           last.identifier == identifier,
           abs(eventDate.timeIntervalSince(last.date)) < 5 {
            return
        }
        recentEvents.append(SoundEvent(date: eventDate, identifier: identifier, confidence: confidence))
        compressEventsIfNeeded()
    }

    private func process(energy: SnoreSignalAnalyzer.Energy, elapsed: Double) {
        if pendingGapClose,
           SnoreResumePolicy.shouldCloseGap(engineStarted: isRunning, receivedBuffer: true) {
            closeOpenGap()
            pendingGapClose = false
        }
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
            if heuristicOpenStart == nil {
                heuristicOpenStart = max(0, monitoredSeconds - tickAccumulator)
            }
            heuristicSnoreSeconds += tickAccumulator
        } else {
            closeHeuristicIfNeeded(at: monitoredSeconds)
        }
        refreshFusion()
        tickAccumulator = 0
        cadence.prune(now: monitoredSeconds)
        maybeCheckpoint()
    }

    private func closeHeuristicIfNeeded(at t: TimeInterval) {
        guard let start = heuristicOpenStart else { return }
        if t > start {
            heuristicIntervals.append((start: start, end: t))
        }
        heuristicOpenStart = nil
    }

    private func refreshFusion() {
        classifierSnoreSeconds = SnoreEpisodeAggregator.snoreSeconds(from: classifierWindows)
        var heuristic = heuristicIntervals
        if let open = heuristicOpenStart {
            heuristic.append((start: open, end: monitoredSeconds))
        }
        if classifierAvailable, classifierSupportsSnoring {
            let fused = SnoreEvidenceFusion.fuse(
                classifier: SnoreEpisodeAggregator.mergedIntervals(from: classifierWindows),
                heuristic: heuristic
            )
            fusedIntervals = fused
            snoreSeconds = SnoreEvidenceFusion.snoreSeconds(from: fused)
        } else {
            fusedIntervals = heuristic.map {
                SnoreEvidenceFusion.Interval(start: $0.start, end: $0.end, source: .heuristic, confidence: 0.4)
            }
            snoreSeconds = heuristicSnoreSeconds
        }
    }

    private func compressEventsIfNeeded() {
        guard recentEvents.count > eventCap else { return }
        let clusters = SoundEvent.clusters(from: recentEvents)
        recentEvents = clusters.map { cluster in
            SoundEvent(date: cluster.start, identifier: cluster.identifier, confidence: 1)
        }
        if recentEvents.count > eventCap {
            recentEvents = Array(recentEvents.suffix(eventCap))
        }
    }

    private func maybeCheckpoint() {
        let now = Date.now
        if let lastCheckpointAt, now.timeIntervalSince(lastCheckpointAt) < SnoreCheckpoint.persistInterval {
            return
        }
        persistCheckpoint(unexpectedEnd: true)
    }

    private func persistCheckpoint(unexpectedEnd: Bool) {
        guard let started = sessionStartedAt, monitoredSeconds > 0 else { return }
        let compressed = SnoreEpisodeAggregator.mergedIntervals(from: classifierWindows).map {
            SnoreClassificationWindow(start: $0.start, duration: $0.end - $0.start, confidence: $0.confidence, identifier: "snoring")
        }
        var gaps = monitoringGaps
        if let open = openGapStartedAt {
            gaps.append(SnoreMonitoringGap(startedAt: open, endedAt: nil))
        }
        let zone = TimeZone(identifier: sessionTimeZoneIdentifier) ?? .current
        let wakeGuess = sessionStartedAt ?? .now
        let checkpoint = SnoreCheckpoint(
            sessionID: sessionID,
            startedAt: started,
            lastCheckpoint: .now,
            monitoredSeconds: monitoredSeconds,
            snoreSeconds: snoreSeconds,
            heuristicSeconds: heuristicSnoreSeconds,
            classifierSeconds: classifierSnoreSeconds,
            interruptionGaps: interruptionGaps,
            gaps: gaps,
            classifierAvailable: classifierAvailable,
            windows: compressed,
            unexpectedEnd: unexpectedEnd,
            timezoneIdentifier: zone.identifier,
            nightKey: NightKey.make(wakeInstant: wakeGuess, in: zone),
            monitoringQuality: unexpectedEnd ? liveQuality : frozenQuality ?? liveQuality
        )
        checkpoint.save()
        lastCheckpointAt = checkpoint.lastCheckpoint
    }
}
