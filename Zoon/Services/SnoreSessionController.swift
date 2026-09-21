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
    private let detector = SnoreDetector()
    private let store = SnoreStore()
    private let eventStore = SoundEventStore()

    init() {
        detector.onPaused = { [weak self] in self?.noteInterrupted() }
        detector.onResumed = { [weak self] in self?.noteResumed() }
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
    var classifierSupportsSnoring: Bool { detector.classifierSupportsSnoring }
    var confidence: SnoreMonitoringConfidence { detector.sessionConfidence }
    var lastSummary: SnoreStore.NightSummary? { store.mostRecent }
    var storedEvents: [SoundEvent] { eventStore.recentEvents }
    var permissionDenied: Bool { !detector.isAvailable }

    func handleScenePhase(_ phase: ScenePhase) {
        guard isRunning else { return }
        switch phase {
        case .background, .inactive:
            if state == .listening { state = .background }
        case .active:
            if state == .background {
                state = detector.isAudioArriving ? .listening : .interrupted
            }
        @unknown default:
            break
        }
    }

    func start(soundscapePlaying: Bool, routineActive: Bool) async -> String? {
        conflictMessage = nil
        if soundscapePlaying || routineActive {
            let message = "Stop Zoon's sleep audio before starting Snore Check so its own sound isn't classified as room audio."
            conflictMessage = message
            state = .failed(message)
            return message
        }
        guard detector.isAvailable else {
            state = .failed("Microphone access needed")
            return "Microphone access needed"
        }
        state = .preparing
        guard await detector.requestPermission() else {
            state = .failed("Microphone access needed")
            return "Microphone access needed"
        }
        do {
            try detector.start()
            state = .listening
            return nil
        } catch {
            let message = (error as NSError).domain == "ZoonAudio"
                ? error.localizedDescription
                : "Microphone access needed"
            conflictMessage = message
            state = .failed(message)
            return message
        }
    }

    func stop() {
        let events = detector.recentEvents
        if let summary = detector.stop() {
            store.record(summary)
            eventStore.record(events)
        }
        state = .stopped
    }

    func noteInterrupted() {
        if isRunning { state = .interrupted }
    }

    func noteResumed() {
        if isRunning { state = detector.isAudioArriving ? .listening : .resuming }
    }
}
