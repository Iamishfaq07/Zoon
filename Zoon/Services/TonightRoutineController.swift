import Foundation
import os
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor @Observable
final class TonightRoutineController {
    static let shared = TonightRoutineController()
    let breathing = BreathingCoach()
    private var audio: SoundscapeEngine?
    private var task: Task<Void, Never>?
    private(set) var active = false
    private(set) var guidance = WindDownGuidanceConfiguration()
    private(set) var stage: WindDownGuidanceConfiguration.Stage = .arrive
    private(set) var startedAt: Date?
    /// True when pause kept the breathing instance in place so Resume can
    /// continue the same cycle rather than reconstructing from elapsed.
    private var breathingPausedInPlace = false

    enum RunState: Equatable {
        case idle
        case playing
        case interrupted
        case pausedByUser
        case failed(String)
        case completed
    }

    private(set) var runState: RunState = .idle

    /// Starts a new routine from Arrive. Remaining seconds from a paused
    /// session still apply to the timer; breathing restarts only when the
    /// caller did not pause in place — use `resume(audio:)` for that.
    func start(audio: SoundscapeEngine) {
        begin(audio: audio, resumeProgress: false)
    }

    /// Continues from the paused remaining time and breathing phase.
    func resume(audio: SoundscapeEngine) {
        begin(audio: audio, resumeProgress: true)
    }

    private func begin(audio: SoundscapeEngine, resumeProgress: Bool) {
        let store = PersonalSetupStore.shared
        let config = store.value.routine
        let total = Double(config.minutes * 60)
        let remaining: TimeInterval
        if resumeProgress {
            remaining = store.value.session?.pausedSeconds
                ?? store.value.session?.remaining(at: .now)
                ?? total
        } else {
            remaining = total
        }
        let elapsed = max(0, total - remaining)
        let liveStart = Date.now.addingTimeInterval(-elapsed)
        store.value.session = .init(
            startedAt: liveStart,
            deadline: Date.now.addingTimeInterval(remaining),
            pausedSeconds: nil
        )
        self.audio = audio
        active = true
        runState = .playing
        startedAt = liveStart
        guidance = WindDownGuidanceConfiguration(
            routineDurationMinutes: config.minutes,
            guidedBreathingMinutes: config.guidedBreathingMinutes,
            voiceMode: config.voiceMode
        )
        stage = guidance.stage(elapsed: elapsed)
        if let scene = store.value.scenes.first(where: { $0.id == config.sceneID }) { audio.playScene(scene) }
        else { audio.play(.rain, toggle: false) }
        audio.setTimer(minutes: max(1, Int(ceil(remaining / 60))))
        breathing.voiceMode = config.voiceMode
        breathing.voiceEnabled = config.voiceMode.usesVoice
        breathing.hapticsEnabled = config.voiceMode.usesHaptics || config.haptics
        breathing.voiceIdentifier = config.voiceIdentifier
        breathing.closingPhrase = WindDownGuidanceConfiguration.closeLine
        if config.breathing {
            configureBreathing(elapsed: elapsed, resumeProgress: resumeProgress)
        }
        breathingPausedInPlace = false
        startPoll()
        startLiveActivity(startedAt: liveStart, endsAt: Date.now.addingTimeInterval(remaining))
    }

    func pause() {
        let store = PersonalSetupStore.shared
        if var session = store.value.session {
            session.pausedSeconds = session.remaining(at: .now)
            store.value.session = session
        }
        runState = .pausedByUser
        task?.cancel()
        task = nil
        breathing.pause()
        breathingPausedInPlace = breathing.runtimeState == .pausedByUser
        audio?.stop()
        audio = nil
        active = false
        endLiveActivity()
    }

    func stop() {
        stopResources()
        breathingPausedInPlace = false
        runState = .idle
        PersonalSetupStore.shared.value.session = nil
    }

    private func finish() {
        stopResources()
        breathingPausedInPlace = false
        runState = .completed
        PersonalSetupStore.shared.value.session = nil
    }

    /// On process relaunch, retain the remaining time but require an explicit resume.
    func reconcile() {
        let store = PersonalSetupStore.shared
        guard !active, var session = store.value.session else { return }
        let remaining = session.remaining(at: .now)
        if remaining <= 0 { store.value.session = nil }
        else { session.pausedSeconds = remaining; store.value.session = session }
        breathingPausedInPlace = false
    }

    private func configureBreathing(elapsed: TimeInterval, resumeProgress: Bool) {
        let position = guidance.guidedPosition(elapsed: elapsed)
        if resumeProgress, breathingPausedInPlace, breathing.phase != .idle, breathing.phase != .finished {
            breathing.resume()
            return
        }
        switch stage {
        case .arrive, .guided:
            breathing.includeArrive = position.phaseName == "arrive"
            if resumeProgress, elapsed > 1 {
                breathing.resume(
                    cycles: guidance.guidedCycles,
                    cyclesCompleted: position.cyclesCompleted,
                    phaseName: position.phaseName,
                    remaining: position.remaining
                )
            } else {
                breathing.includeArrive = true
                breathing.start(cycles: guidance.guidedCycles)
            }
        case .quiet, .close:
            breathing.stop()
        }
    }

    private func startPoll() {
        task?.cancel()
        let store = PersonalSetupStore.shared
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, let session = store.value.session else { return }
                if session.remaining(at: .now) <= 0 { self.finish(); return }
                if let start = self.startedAt {
                    let next = self.guidance.stage(elapsed: Date.now.timeIntervalSince(start))
                    if next != self.stage {
                        self.stage = next
                        self.updateLiveActivity(endsAt: session.deadline)
                        if next == .quiet || next == .close {
                            self.breathing.stop()
                        }
                    }
                }
                if let message = audio?.interruptionMessage, audio?.playing == nil {
                    self.runState = .failed(message)
                    return
                }
            }
        }
    }

    private func stopResources() {
        endLiveActivity()
        task?.cancel(); task = nil
        breathing.stop()
        audio?.stop(); audio = nil
        active = false
        startedAt = nil
    }

    // MARK: - Live Activity

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "TonightRoutine")

    /// What the Lock Screen calls the current stage.
    static func stageLabel(_ stage: WindDownGuidanceConfiguration.Stage) -> String {
        switch stage {
        case .arrive: "Arrive"
        case .guided: "Guided breathing"
        case .quiet: "Quiet"
        case .close: "Settling"
        }
    }

    /// Fire-and-forget, like the nap's: a routine that cannot show on the
    /// Lock Screen is still a working routine.
    private func startLiveActivity(startedAt: Date, endsAt: Date) {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = WindDownActivityAttributes.ContentState(endsAt: endsAt, stageLabel: Self.stageLabel(stage))
        let logger = logger
        // One task, in order: any activity left from a paused or earlier run
        // ends first, then the new one starts, so the ending can never catch
        // the activity just requested.
        Task {
            for activity in Activity<WindDownActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            do {
                _ = try Activity.request(
                    attributes: WindDownActivityAttributes(startedAt: startedAt),
                    content: .init(state: state, staleDate: endsAt.addingTimeInterval(120)),
                    pushType: nil
                )
            } catch {
                logger.error("Wind-down Live Activity request failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
    }

    private func updateLiveActivity(endsAt: Date) {
        #if canImport(ActivityKit)
        let state = WindDownActivityAttributes.ContentState(endsAt: endsAt, stageLabel: Self.stageLabel(stage))
        Task {
            for activity in Activity<WindDownActivityAttributes>.activities {
                await activity.update(.init(state: state, staleDate: endsAt.addingTimeInterval(120)))
            }
        }
        #endif
    }

    private func endLiveActivity() {
        #if canImport(ActivityKit)
        Task {
            for activity in Activity<WindDownActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    var remainingCaption: String? {
        guard let session = PersonalSetupStore.shared.value.session else { return nil }
        let seconds = Int(ceil(session.remaining(at: .now)))
        let minutes = max(1, seconds / 60)
        switch stage {
        case .arrive: return "Arrive · \(minutes) min left"
        case .guided: return "Guided · \(minutes) min left"
        case .quiet: return "Quiet · \(minutes) min left"
        case .close: return "Settling · \(minutes) min left"
        }
    }
}
