import Foundation
import AVFoundation
import SwiftUI

/// App-scoped Snore Check session. The live microphone must not depend on
/// one SwiftUI screen remaining on the stack.
@MainActor
@Observable
final class SnoreSessionController {
    static let shared = SnoreSessionController()

    enum State: Equatable, Sendable {
        case idle
        case preparing
        case listening
        case background
        case interrupted
        case resuming
        case failed(String)
        case stopped
    }

    private(set) var state: State = .idle
    private(set) var conflictMessage: String?
    private(set) var recoveredCheckpoint: SnoreCheckpoint?
    private let detector = SnoreDetector()
    private let store = SnoreStore()
    private let eventStore = SoundEventStore()
    /// Watches a resume until audio actually arrives; see `noteResumed`.
    private var resumeWatch: Task<Void, Never>?
    private var erasureObserver: NSObjectProtocol?

    /// What `start` returns when the microphone itself is refused, as opposed
    /// to a conflict with Zoon's own audio. Screens compare against this,
    /// never against the word "microphone": the conflict message contains it
    /// too, and matching the word sent people to Settings to fix a permission
    /// they had already granted.
    static let microphoneAccessNeeded = "Microphone access needed"

    init() {
        detector.onPaused = { [weak self] in self?.noteInterrupted() }
        detector.onResumed = { [weak self] in self?.noteResumed() }
        if let checkpoint = SnoreCheckpoint.load(), checkpoint.unexpectedEnd, checkpoint.monitoredSeconds > 30 {
            recoveredCheckpoint = checkpoint
            detector.restore(from: checkpoint)
        }
        // Delete Everything: the detector stops the microphone and forgets its
        // session; this forgets the recovered one too. Kept in memory, it was
        // written back by the next Start or by the card's Save button -- data
        // restored from before the erase.
        erasureObserver = NotificationCenter.default.addObserver(
            forName: DataErasure.didErase, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.resumeWatch?.cancel()
                self.recoveredCheckpoint = nil
                self.conflictMessage = nil
                self.state = .idle
                SnoreCheckpoint.clear()
            }
        }
    }

    var isRunning: Bool {
        switch state {
        case .listening, .background, .interrupted, .resuming, .preparing: true
        default: false
        }
    }

    var monitoredSeconds: Double { detector.monitoredSeconds }
    var snoreSeconds: Double { detector.snoreSeconds }
    var recentEvents: [SoundEvent] { detector.recentEvents }
    var lastBufferAt: Date? { detector.lastBufferAt }
    var isAudioArriving: Bool { detector.isAudioArriving }
    var classifierAvailable: Bool { detector.classifierAvailable }
    /// When sound classification stopped in the running session, if it has.
    var classifierPausedSince: Date? { detector.classifierFailedAt }
    var classifierSupportsSnoring: Bool { detector.classifierSupportsSnoring }
    var confidence: SnoreMonitoringConfidence { detector.sessionConfidence }
    var lastSummary: SnoreStore.NightSummary? { store.mostRecent }
    var storedEvents: [SoundEvent] { eventStore.recentEvents }
    var permissionDenied: Bool { !detector.isAvailable }
    var interruptionGaps: Int { detector.interruptionGaps }
    var monitoringGaps: [SnoreMonitoringGap] { detector.monitoringGaps }
    var fusedIntervals: [SnoreEvidenceFusion.Interval] { detector.fusedIntervals }

    func dismissRecoveredCheckpoint() {
        recoveredCheckpoint = nil
        SnoreCheckpoint.clear()
    }

    /// Converts a recovered checkpoint into a durable partial night summary.
    func saveRecoveredCheckpoint() {
        guard let checkpoint = recoveredCheckpoint else { return }
        store.record(summary(from: checkpoint))
        recoveredCheckpoint = nil
        SnoreCheckpoint.clear()
    }

    private func summary(from checkpoint: SnoreCheckpoint) -> SnoreStore.NightSummary {
        let zone = checkpoint.timezoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? TimeZone.current
        var calendar = Calendar.current
        calendar.timeZone = zone
        // The night the session belongs to, from when it started: an evening
        // start is the night ending the next morning, an after-midnight start
        // the night ending that morning. Neither the evening nor the moment
        // the app died is the night's day. The stored key is not trusted:
        // builds before this one wrote the evening's date into it.
        let night = SnoreNight.date(forSessionStartedAt: checkpoint.startedAt, in: zone)
        return SnoreStore.NightSummary(
            date: calendar.startOfDay(for: night),
            monitoredMinutes: checkpoint.monitoredSeconds / 60,
            snoreMinutes: checkpoint.snoreSeconds / 60,
            nightKey: NightKey.make(wakeInstant: night, in: zone),
            timezoneIdentifier: zone.identifier,
            isPartial: true,
            endedUnexpectedly: true,
            monitoringQuality: checkpoint.monitoringQuality?.rawValue,
            interruptionDurationMinutes: checkpoint.interruptionDuration / 60
        )
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard isRunning else { return }
        switch phase {
        case .background, .inactive:
            if state == .listening { state = .background }
        case .active:
            // A classifier that failed while the phone was locked can run
            // again in the foreground; the microphone never stopped.
            detector.restartClassifierIfNeeded()
            if state == .background {
                state = detector.isAudioArriving ? .listening : .interrupted
            }
            // An interruption that ended while Zoon was in the background can
            // fail to take the microphone back; the foreground is where it
            // can. Quietly: a failure here leaves the Resume button, not an
            // alert.
            if state == .interrupted {
                resume(userInitiated: false)
            }
        @unknown default:
            break
        }
    }

    var confidenceBreakdown: SnoreConfidenceBreakdown { detector.liveBreakdown }

    /// - Parameter intendedWindowSeconds: tonight's sleep window, which
    ///   coverage confidence is measured against. `nil` keeps the default.
    func start(
        soundscapePlaying: Bool,
        routineActive: Bool,
        intendedWindowSeconds: TimeInterval? = nil
    ) async -> String? {
        conflictMessage = nil
        if let intendedWindowSeconds, intendedWindowSeconds >= 3600 {
            detector.intendedWindowSeconds = intendedWindowSeconds
        }
        if soundscapePlaying || routineActive {
            let message = "Snore Check needs the microphone without Zoon audio playing. Stop Rain and Wind Down, then start Snore Check?"
            conflictMessage = message
            state = .failed(message)
            return message
        }
        guard detector.isAvailable else {
            state = .failed(Self.microphoneAccessNeeded)
            return Self.microphoneAccessNeeded
        }
        state = .preparing
        if recoveredCheckpoint != nil {
            saveRecoveredCheckpoint()
        }
        guard await detector.requestPermission() else {
            state = .failed(Self.microphoneAccessNeeded)
            return Self.microphoneAccessNeeded
        }
        do {
            try detector.start()
            recoveredCheckpoint = nil
            state = .listening
            return nil
        } catch {
            // Permission was granted a moment ago, so a failure here is the
            // audio system (another app holding the microphone, a route that
            // will not open), not a setting the person needs to change.
            let message = (error as NSError).domain == "ZoonAudio"
                ? error.localizedDescription
                : "Snore Check couldn't start the microphone. Close any app that may be using it, then try again."
            conflictMessage = message
            state = .failed(message)
            return message
        }
    }

    /// Starts listening again after an interruption that did not resume by
    /// itself: from the Resume button, or on returning to the foreground.
    ///
    /// Nothing used to do this. A call or Siri in the night that iOS did not
    /// hand back left the session paused until morning, reading "Listening
    /// interrupted" with no way on.
    @discardableResult
    func resume(userInitiated: Bool = true) -> Bool {
        guard state == .interrupted || state == .resuming else { return false }
        do {
            if detector.isRunning {
                // Running but silent: rebuild rather than stack a second tap.
                try detector.rebuildEngineAndRestart()
            } else {
                try detector.resumeListening()
            }
            noteResumed()
            return true
        } catch {
            state = .interrupted
            if userInitiated {
                conflictMessage = "Snore Check couldn't get the microphone back. Close any app that may be using it, then tap Resume."
            }
            return false
        }
    }

    /// Stops Sleep Sounds and Wind Down, then starts Snore Check.
    func stopAudioAndStart(soundscape: SoundscapeEngine) async -> String? {
        soundscape.stop()
        TonightRoutineController.shared.stop()
        conflictMessage = nil
        return await start(soundscapePlaying: false, routineActive: false)
    }

    func stop() {
        resumeWatch?.cancel()
        let events = detector.recentEvents
        if let summary = detector.stop() {
            store.record(summary)
            eventStore.record(events)
        }
        state = .stopped
    }

    func noteInterrupted() {
        resumeWatch?.cancel()
        if isRunning { state = .interrupted }
    }

    /// The engine is back; audio may take a moment to arrive.
    ///
    /// Shows "resuming" until the first buffers do, then "listening". It
    /// used to set "resuming" once and never look again, so every successful
    /// resume read "Trying to resume…" for the rest of the night. If audio
    /// never arrives the session is shown as interrupted, with Resume.
    func noteResumed() {
        guard isRunning else { return }
        resumeWatch?.cancel()
        guard !detector.isAudioArriving else {
            state = .listening
            return
        }
        state = .resuming
        resumeWatch = Task { [weak self] in
            for _ in 0..<10 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled, self.state == .resuming else { return }
                if self.detector.isAudioArriving {
                    self.state = .listening
                    return
                }
            }
            guard let self, !Task.isCancelled, self.state == .resuming else { return }
            self.state = .interrupted
        }
    }
}
