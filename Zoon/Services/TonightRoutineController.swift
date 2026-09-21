import Foundation

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

    enum RunState: Equatable {
        case idle
        case playing
        case interrupted
        case pausedByUser
        case failed(String)
        case completed
    }

    private(set) var runState: RunState = .idle

    func start(audio: SoundscapeEngine) {
        let store = PersonalSetupStore.shared
        let config = store.value.routine
        let seconds = store.value.session?.pausedSeconds ?? Double(config.minutes * 60)
        store.value.session = .init(startedAt: .now, deadline: Date.now.addingTimeInterval(seconds))
        self.audio = audio
        active = true
        runState = .playing
        startedAt = .now
        guidance = WindDownGuidanceConfiguration(
            routineDurationMinutes: config.minutes,
            guidedBreathingMinutes: config.guidedBreathingMinutes,
            voiceMode: config.voiceMode
        )
        stage = .arrive
        if let scene = store.value.scenes.first(where: { $0.id == config.sceneID }) { audio.playScene(scene) }
        else { audio.play(.rain, toggle: false) }
        audio.setTimer(minutes: max(1, Int(ceil(seconds / 60))))
        breathing.voiceMode = config.voiceMode
        breathing.voiceEnabled = config.voiceMode.usesVoice
        breathing.hapticsEnabled = config.voiceMode.usesHaptics || config.haptics
        breathing.includeArrive = true
        breathing.closingPhrase = WindDownGuidanceConfiguration.closeLine
        if config.breathing {
            breathing.start(cycles: guidance.guidedCycles)
        }
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, let session = store.value.session else { return }
                if session.remaining(at: .now) <= 0 { self.finish(); return }
                if let start = self.startedAt {
                    self.stage = self.guidance.stage(elapsed: Date.now.timeIntervalSince(start))
                }
                if let message = audio.interruptionMessage, audio.playing == nil {
                    self.runState = .failed(message)
                    return
                }
            }
        }
    }

    func pause() {
        let store = PersonalSetupStore.shared
        if var session = store.value.session {
            session.pausedSeconds = session.remaining(at: .now)
            store.value.session = session
        }
        runState = .pausedByUser
        stopResources()
    }

    func stop() {
        stopResources()
        runState = .idle
        PersonalSetupStore.shared.value.session = nil
    }

    private func finish() {
        stopResources()
        runState = .completed
        PersonalSetupStore.shared.value.session = nil
    }

    /// On process relaunch, retain the deadline but require an explicit resume.
    func reconcile() {
        let store = PersonalSetupStore.shared
        guard !active, var session = store.value.session else { return }
        let remaining = session.remaining(at: .now)
        if remaining <= 0 { store.value.session = nil }
        else { session.pausedSeconds = remaining; store.value.session = session }
    }

    private func stopResources() {
        task?.cancel(); task = nil
        breathing.stop()
        audio?.stop(); audio = nil
        active = false
        startedAt = nil
    }
}
