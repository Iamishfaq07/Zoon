import Foundation
import AVFoundation
import os

/// Estimates snoring, on-device, from the phone's microphone.
///
/// Two detectors hear the same buffers. `SnoreAcousticEngine` is Zoon's own:
/// it judges each sound against the room's quiet level, its shape and its
/// breathing rhythm, runs on the CPU, and keeps working with the screen
/// locked. Apple's SoundAnalysis classifier confirms it when it is running,
/// and vetoes it where it heard speech, music or a television. Raw audio is
/// processed in ~100ms buffers and discarded.
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
    /// When Apple's classifier stopped producing results in this session, if
    /// it has. The heuristic keeps listening; the classifier is rebuilt on the
    /// next chance (see `restartClassifierIfNeeded`).
    private(set) var classifierFailedAt: Date?
    /// Monitored seconds the classifier did not hear because it had failed.
    /// Quality is judged against the share of the night it did hear, so a
    /// night the primary detector missed cannot read "Strong".
    private(set) var classifierOutageSeconds: Double = 0

    /// Zoon's own detector: level against the room, shape, rhythm.
    private(set) var acoustics = SnoreAcousticEngine()
    /// Snoring episodes so far, fused from both detectors and merged. Kept
    /// current once a second for the live screen.
    private(set) var liveEpisodeCount = 0
    private(set) var sessionStartedAt: Date?

    private var engine = AVAudioEngine()
    private let soundClassifier = SoundEventClassifier()
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "SnoreDetector")
    private var tapInstalled = false
    private var tickAccumulator: TimeInterval = 0
    private let tickInterval: TimeInterval = 1.0
    private var epoch: SoundAnalysisEpoch?
    private var clock = SnoreSessionClock()
    /// Where the classifier heard speech, music or a television, merged.
    /// Memory only: never stored, never shown.
    private var vetoIntervals: [(start: TimeInterval, end: TimeInterval)] = []
    private var lastCheckpointAt: Date?
    private var openGapStartedAt: Date?
    private var sessionTimeZoneIdentifier: String = TimeZone.current.identifier
    /// An interruption gap stays open until the first valid buffer after a
    /// successful engine start. Closing it at `setActive` would mark the
    /// session as monitored through a failed resume.
    private var pendingGapClose = false
    var onPaused: (() -> Void)?
    var onResumed: (() -> Void)?
    private let eventCap = 80

    /// Sounds shown on the night's timeline.
    nonisolated static let displayIdentifiers: Set<String> = ["snoring", "cough", "coughing", "baby_cry_infant_cry", "baby_crying"]
    /// Sounds that are not snoring however rhythmic they are. Used only to
    /// drop the loudness engine's evidence where they were heard.
    nonisolated static let vetoIdentifiers: Set<String> = ["speech", "music", "singing", "television", "radio", "laughter", "whispering", "shout"]
    /// A veto needs a more confident label than a display event.
    nonisolated static let vetoConfidence = 0.6

    var isAudioArriving: Bool {
        guard let lastBufferAt else { return false }
        return Date.now.timeIntervalSince(lastBufferAt) < 1.5
    }

    var sessionConfidence: SnoreMonitoringConfidence {
        if let frozenQuality { return frozenQuality }
        return liveQuality
    }

    /// The sleep window this session is meant to cover, for coverage
    /// confidence. Set at start from tonight's plan; 8 hours otherwise.
    var intendedWindowSeconds: TimeInterval = SnoreCoverage.defaultIntendedWindowSeconds

    var liveQuality: SnoreMonitoringConfidence { liveBreakdown.final }

    /// Detector and coverage confidence separately, for the result screen.
    var liveBreakdown: SnoreConfidenceBreakdown {
        SnoreEpisodeAggregator.breakdown(
            classifierAvailable: classifierAvailable,
            classifierSupportsSnoring: classifierSupportsSnoring,
            monitoredSeconds: monitoredSeconds,
            lastBufferAge: lastBufferAt.map { Date.now.timeIntervalSince($0) },
            heuristicSeconds: heuristicSnoreSeconds,
            classifierSeconds: classifierSnoreSeconds,
            sessionEnded: !isRunning && monitoredSeconds > 0,
            interruptionDuration: monitoringGaps.reduce(0) { $0 + $1.duration },
            intendedWindowSeconds: intendedWindowSeconds,
            classifierActiveShare: classifierActiveShare
        )
    }

    /// Share of the monitored time Apple's classifier was actually running.
    var classifierActiveShare: Double {
        guard monitoredSeconds > 0 else { return 1 }
        return min(1, max(0, 1 - classifierOutageSeconds / monitoredSeconds))
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
        acoustics = SnoreAcousticEngine()
        liveEpisodeCount = 0
        clock = SnoreSessionClock()
        vetoIntervals.removeAll()
        tickAccumulator = 0
        recentEvents.removeAll()
        classifierWindows.removeAll()
        lastBufferAt = nil
        sessionStartedAt = .now
        sessionID = UUID()
        interruptionGaps = 0
        lastCheckpointAt = nil
        monitoringGaps = []
        openGapStartedAt = nil
        fusedIntervals = []
        frozenQuality = nil
        classifierFailedAt = nil
        classifierOutageSeconds = 0
        lastClassifierRestartAttempt = 0
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
        acoustics.finish()
        heuristicSnoreSeconds = acoustics.snoreSeconds
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
        let zone = TimeZone(identifier: sessionTimeZoneIdentifier) ?? .current
        let night = SnoreNight.date(forSessionStartedAt: sessionStartedAt ?? .now, in: zone)
        var calendar = Calendar.current
        calendar.timeZone = zone
        return SnoreStore.NightSummary(
            date: calendar.startOfDay(for: night),
            monitoredMinutes: monitoredSeconds / 60,
            snoreMinutes: snoreSeconds / 60,
            nightKey: NightKey.make(wakeInstant: night, in: zone),
            timezoneIdentifier: zone.identifier,
            isPartial: false,
            endedUnexpectedly: false,
            monitoringQuality: frozenQuality?.rawValue,
            interruptionDurationMinutes: monitoringGaps.reduce(0) { $0 + $1.duration } / 60,
            coveragePercent: liveBreakdown.coveragePercent,
            episodes: episodeRecords,
            startedAt: sessionStartedAt,
            endedAt: .now
        )
    }

    /// The session's snoring episodes as stored: wall-clock times, breath
    /// counts, loudness.
    var episodeRecords: [SnoreEpisodeRecord] {
        SnoreEpisodeRecord.make(fused: fusedIntervals, engineEpisodes: acoustics.allEpisodes, clock: clock)
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
        let now = Date.now
        epoch = SoundAnalysisEpoch.beginningNow(sessionElapsed: monitoredSeconds, now: now)
        clock.mark(session: monitoredSeconds, wall: now)
    }

    private func closeOpenGap() {
        guard let started = openGapStartedAt else { return }
        monitoringGaps.append(SnoreMonitoringGap(startedAt: started, endedAt: .now))
        openGapStartedAt = nil
    }

    /// Builds a fresh classifier request for `format`. A new analyzer's clock
    /// starts at zero, so the epoch that maps its results starts now too.
    private func startClassifier(format: AVAudioFormat) {
        soundClassifier.start(
            format: format,
            onEvent: { [weak self] identifier, confidence, start, duration in
                Task { @MainActor [weak self] in
                    self?.recordEvent(identifier: identifier, confidence: confidence, start: start, duration: duration)
                }
            },
            onFailure: { [weak self] in
                Task { @MainActor [weak self] in self?.classifierDidFail() }
            }
        )
    }

    private func classifierDidFail() {
        guard isRunning, classifierFailedAt == nil else { return }
        classifierFailedAt = .now
        logger.error("Sound classification stopped; continuing with the loudness pattern until it can restart")
    }

    /// Rebuilds a failed classifier while the microphone keeps running.
    ///
    /// Called when Zoon comes back to the foreground (where a classifier that
    /// failed at lock can run again) and, as a fallback, every
    /// `classifierRestartInterval` of monitoring. The engine and tap are left
    /// alone: only the SoundAnalysis request is replaced.
    ///
    /// `classifierAvailable` is deliberately left as it was: turning it off
    /// mid-session would switch fusion to the heuristic alone and discard the
    /// snoring the classifier did hear before it failed.
    func restartClassifierIfNeeded() {
        guard isRunning, classifierFailedAt != nil, tapInstalled else { return }
        lastClassifierRestartAttempt = monitoredSeconds
        startClassifier(format: engine.inputNode.outputFormat(forBus: 0))
        guard soundClassifier.isAvailable else { return }
        beginEpoch()
        classifierFailedAt = nil
        logger.info("Sound classification restarted")
    }

    private let classifierRestartInterval: TimeInterval = 5 * 60
    private var lastClassifierRestartAttempt: TimeInterval = 0

    private func installTapAndStartEngine(releaseOwnerOnFailure: Bool = true) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        startClassifier(format: format)
        classifierAvailable = soundClassifier.isAvailable
        classifierSupportsSnoring = soundClassifier.supportsSnoring
        classifierFailedAt = nil

        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        input.installTap(onBus: 0, bufferSize: 4800, format: format) { [weak self] buffer, time in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            // Measured here, on the audio thread; only these few numbers
            // cross to the main actor.
            let frame = SnoreSignalAnalyzer.frame(samples: samples, sampleRate: format.sampleRate)
            self?.soundClassifier.process(buffer, atFramePosition: time.sampleTime)
            Task { @MainActor [weak self] in
                self?.process(frame: frame)
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
        if Self.vetoIdentifiers.contains(identifier) {
            if confidence >= Self.vetoConfidence {
                noteVeto(start: sessionStart, end: sessionStart + max(0, duration))
            }
            return
        }
        guard Self.displayIdentifiers.contains(identifier) else { return }
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

    /// Merges a veto into the running list; classifier windows overlap, so
    /// most extend the last one.
    private func noteVeto(start: TimeInterval, end: TimeInterval) {
        guard end > start else { return }
        if let last = vetoIntervals.last, start <= last.end + 1.5 {
            vetoIntervals[vetoIntervals.count - 1].end = max(last.end, end)
        } else {
            vetoIntervals.append((start: start, end: end))
        }
    }

    private func process(frame: SnoreFrame) {
        // A buffer already queued when capture stopped belongs to no session.
        guard isRunning else { return }
        let elapsed = frame.duration
        if pendingGapClose,
           SnoreResumePolicy.shouldCloseGap(engineStarted: isRunning, receivedBuffer: true) {
            closeOpenGap()
            pendingGapClose = false
        }
        monitoredSeconds += elapsed
        tickAccumulator += elapsed
        lastBufferAt = .now
        if classifierFailedAt != nil {
            classifierOutageSeconds += elapsed
            if monitoredSeconds - lastClassifierRestartAttempt >= classifierRestartInterval {
                restartClassifierIfNeeded()
            }
        }

        acoustics.ingest(frame, endingAt: monitoredSeconds)

        guard tickAccumulator >= tickInterval else { return }
        heuristicSnoreSeconds = acoustics.snoreSeconds
        refreshFusion()
        tickAccumulator = 0
        maybeCheckpoint()
    }

    private func refreshFusion() {
        classifierSnoreSeconds = SnoreEpisodeAggregator.snoreSeconds(from: classifierWindows)
        let heuristic = acoustics.intervals
        if classifierAvailable, classifierSupportsSnoring {
            fusedIntervals = SnoreEvidenceFusion.fuse(
                classifier: SnoreEpisodeAggregator.mergedIntervals(from: classifierWindows),
                heuristic: heuristic,
                vetoes: vetoIntervals
            )
        } else {
            fusedIntervals = SnoreEvidenceFusion.fuse(classifier: [], heuristic: heuristic, vetoes: vetoIntervals)
        }
        snoreSeconds = SnoreEvidenceFusion.snoreSeconds(from: fusedIntervals)
        liveEpisodeCount = SnoreEpisodeRecord.make(
            fused: fusedIntervals, engineEpisodes: [], clock: clock
        ).count
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
            nightKey: SnoreNight.key(forSessionStartedAt: started, in: zone),
            monitoringQuality: unexpectedEnd ? liveQuality : frozenQuality ?? liveQuality,
            episodes: episodeRecords
        )
        checkpoint.save()
        lastCheckpointAt = checkpoint.lastCheckpoint
    }
}
