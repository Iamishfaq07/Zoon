import Foundation
import AVFoundation

/// Narrates a wind-down breathing exercise entirely on-device.
///
/// `AVSpeechSynthesizer` rather than bundled audio files or a downloaded
/// voice model — no licensing, no download. Voice quality is the best
/// *installed* system voice (premium, then enhanced, then default).
@MainActor
@Observable
final class BreathingCoach: NSObject, AVSpeechSynthesizerDelegate {

    enum Phase: Equatable {
        case idle
        case arrive
        case inhale, hold, exhale, rest
        case quiet
        case finished
    }

    enum RuntimeState: Equatable {
        case idle
        case running
        case interrupted
        case resuming
        case pausedByUser
        case failed
        case completed
    }

    private(set) var phase: Phase = .idle
    /// 0...1 within the current phase, for the pacer animation.
    private(set) var phaseProgress: Double = 0
    private(set) var cyclesCompleted = 0
    private(set) var selectedVoiceName: String?
    private(set) var runtimeState: RuntimeState = .idle

    var totalCycles = 4
    var voiceEnabled = true
    var hapticsEnabled = false
    var voiceMode: WindDownGuidanceConfiguration.VoiceMode = .natural
    var includeArrive = false
    var closingPhrase: String? = WindDownGuidanceConfiguration.closeLine
    var voiceIdentifier: String?
    private let audioOwner = UUID()

    private let synthesizer = AVSpeechSynthesizer()
    private var timer: Timer?
    private var phaseStart: Date?
    private var phaseDuration: Double = 0
    private var pausedAt: Date?
    /// Latest phase cue waiting because a slower voice is still speaking.
    private var pendingCue: String?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Starts (or restarts) the exercise from cycle 0.
    func start(cycles: Int = 4) {
        stop()
        totalCycles = max(1, cycles)
        cyclesCompleted = 0
        voiceEnabled = voiceMode.usesVoice
        hapticsEnabled = voiceMode.usesHaptics || hapticsEnabled
        acquireAudioIfNeeded()
        runtimeState = .running
        if includeArrive {
            enter(.arrive, duration: WindDownGuidanceConfiguration.arriveSeconds, say: WindDownGuidanceConfiguration.arriveLine)
        } else {
            runCycle()
        }
    }

    /// Continues the current phase after a user pause or interruption.
    /// Shifts `phaseStart` by the pause duration so wall-clock remaining
    /// is preserved and phases are not skipped.
    func resume() {
        guard phase != .idle, phase != .finished else { return }
        acquireAudioIfNeeded()
        if let pausedAt, let start = phaseStart {
            phaseStart = start.addingTimeInterval(Date.now.timeIntervalSince(pausedAt))
        }
        pausedAt = nil
        runtimeState = .resuming
        restartTimer()
        runtimeState = .running
    }

    /// Continues from a reconstructed phase after process relaunch.
    func resume(cycles: Int, cyclesCompleted: Int, phaseName: String, remaining: TimeInterval) {
        stop()
        totalCycles = max(1, cycles)
        self.cyclesCompleted = max(0, min(totalCycles, cyclesCompleted))
        voiceEnabled = voiceMode.usesVoice
        hapticsEnabled = voiceMode.usesHaptics || hapticsEnabled
        acquireAudioIfNeeded()
        runtimeState = .running
        let next = phase(from: phaseName)
        guard next != .idle, next != .finished, next != .quiet else { return }
        enter(next, duration: max(0.2, remaining), say: cue(for: next))
    }

    func pause() {
        guard runtimeState == .running || runtimeState == .resuming else { return }
        pausedAt = .now
        timer?.invalidate()
        timer = nil
        pendingCue = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        runtimeState = .pausedByUser
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingCue = nil
        pausedAt = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        AudioSessionCoordinator.shared.release(audioOwner)
        phase = .idle
        phaseProgress = 0
        runtimeState = .idle
    }

    var remainingInPhase: TimeInterval {
        guard let start = phaseStart else { return 0 }
        return max(0, phaseDuration - Date.now.timeIntervalSince(start))
    }

    private func acquireAudioIfNeeded() {
        guard voiceEnabled else { return }
        do {
            try AudioSessionCoordinator.shared.acquire(audioOwner) { [weak self] in
                self?.pauseForInterruption()
            } onResume: { [weak self] in
                self?.resumeAfterInterruption()
            } onReset: { [weak self] in
                self?.resetAfterMediaServicesReset()
            }
        } catch {
            voiceEnabled = false
            runtimeState = .failed
        }
    }

    private func pauseForInterruption() {
        pausedAt = .now
        timer?.invalidate()
        timer = nil
        pendingCue = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        runtimeState = .interrupted
    }

    private func resumeAfterInterruption() {
        guard runtimeState == .interrupted else { return }
        runtimeState = .resuming
        resume()
    }

    private func resetAfterMediaServicesReset() {
        synthesizer.delegate = self
        acquireAudioIfNeeded()
        switch runtimeState {
        case .running, .resuming, .interrupted:
            runtimeState = .interrupted
            resumeAfterInterruption()
        default:
            break
        }
    }

    // MARK: - Cycle

    private func runCycle() {
        guard cyclesCompleted < totalCycles else {
            phase = .finished
            runtimeState = .completed
            if let closingPhrase, !closingPhrase.isEmpty {
                speak(closingPhrase)
            }
            return
        }
        enter(.inhale, duration: WindDownGuidanceConfiguration.inhaleSeconds, say: cue(for: .inhale))
    }

    private func enter(_ next: Phase, duration: Double, say line: String) {
        phase = next
        phaseProgress = 0
        if hapticsEnabled { Haptics.tap() }
        phaseDuration = duration
        phaseStart = .now
        speak(line)
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard runtimeState == .running || runtimeState == .resuming else { return }
        guard let start = phaseStart else { return }
        let elapsed = Date.now.timeIntervalSince(start)
        phaseProgress = min(1, elapsed / max(0.01, phaseDuration))
        guard elapsed >= phaseDuration else { return }

        switch phase {
        case .arrive:
            runCycle()
        case .inhale:
            enter(.hold, duration: WindDownGuidanceConfiguration.holdSeconds, say: cue(for: .hold))
        case .hold:
            enter(.exhale, duration: WindDownGuidanceConfiguration.exhaleSeconds, say: cue(for: .exhale))
        case .exhale:
            enter(.rest, duration: WindDownGuidanceConfiguration.restSeconds, say: "")
        case .rest:
            cyclesCompleted += 1
            runCycle()
        case .idle, .quiet, .finished:
            timer?.invalidate()
        }
    }

    private func cue(for phase: Phase) -> String {
        switch phase {
        case .arrive: WindDownGuidanceConfiguration.arriveLine
        case .inhale: voiceMode.cue(phase: "inhale", cycleIndex: cyclesCompleted)
        case .hold: voiceMode.cue(phase: "hold", cycleIndex: cyclesCompleted)
        case .exhale: voiceMode.cue(phase: "exhale", cycleIndex: cyclesCompleted)
        default: ""
        }
    }

    private func phase(from name: String) -> Phase {
        switch name {
        case "arrive": .arrive
        case "inhale": .inhale
        case "hold": .hold
        case "exhale": .exhale
        case "rest": .rest
        case "quiet": .quiet
        case "finished": .finished
        default: .idle
        }
    }

    /// Do not silently skip the next phase cue if a slower Premium voice is
    /// still speaking. Queue the latest line; stale ones are replaced.
    private func speak(_ line: String) {
        guard voiceEnabled, !line.isEmpty else { return }
        if synthesizer.isSpeaking {
            pendingCue = line
            return
        }
        enqueue(line)
    }

    private func enqueue(_ line: String) {
        let voice = resolvedVoice()
        for utterance in SpeechVoices.utterances(for: line, profile: .breathing, voice: voice) {
            synthesizer.speak(utterance)
        }
    }

    func previewVoice() {
        speak("Breathe in slowly. Let your shoulders soften.")
    }

    /// The Wind Down voice if still installed, else the best installed voice
    /// for this language. Shared with the night narrator (`SpeechVoices`).
    func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let chosen = SpeechVoices.resolve(preferredIdentifier: voiceIdentifier)
        selectedVoiceName = chosen?.name
        return chosen
    }

    static func installedVoices() -> [AVSpeechSynthesisVoice] {
        SpeechVoices.installed()
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        SpeechVoices.qualityLabel(voice)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, let next = self.pendingCue else { return }
            self.pendingCue = nil
            self.enqueue(next)
        }
    }
}
