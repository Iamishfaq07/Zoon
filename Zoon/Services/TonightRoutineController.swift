import Foundation

@MainActor @Observable
final class TonightRoutineController {
    static let shared = TonightRoutineController()
    let breathing = BreathingCoach()
    private var audio: SoundscapeEngine?
    private var task: Task<Void, Never>?
    private(set) var active = false

    func start(audio: SoundscapeEngine) {
        let store = PersonalSetupStore.shared
        let config = store.value.routine
        let seconds = store.value.session?.pausedSeconds ?? Double(config.minutes * 60)
        store.value.session = .init(startedAt: .now, deadline: Date.now.addingTimeInterval(seconds))
        self.audio = audio
        active = true
        if let scene = store.value.scenes.first(where: { $0.id == config.sceneID }) { audio.playScene(scene) }
        else { audio.play(.rain, toggle: false) }
        audio.setTimer(minutes: max(1, Int(ceil(seconds / 60))))
        breathing.voiceEnabled = config.voice
        breathing.hapticsEnabled = config.haptics
        if config.breathing { breathing.start() }
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, let session = store.value.session else { return }
                if session.remaining(at: .now) <= 0 { stop(); return }
                if !audio.isPlaying { pause(); return }
            }
        }
    }

    func pause() {
        let store = PersonalSetupStore.shared
        if var session = store.value.session {
            session.pausedSeconds = session.remaining(at: .now)
            store.value.session = session
        }
        stopResources()
    }

    func stop() {
        stopResources()
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
    }
}
