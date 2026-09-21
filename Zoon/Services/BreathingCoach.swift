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

    private(set) var phase: Phase = .idle
    /// 0...1 within the current phase, for the pacer animation.
    private(set) var phaseProgress: Double = 0
    private(set) var cyclesCompleted = 0
    private(set) var selectedVoiceName: String?

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

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Starts (or restarts) the exercise.
    func start(cycles: Int = 4) {
        stop()
        totalCycles = max(1, cycles)
        cyclesCompleted = 0
        voiceEnabled = voiceMode.usesVoice
        hapticsEnabled = voiceMode.usesHaptics || hapticsEnabled
        if voiceEnabled {
            do { try AudioSessionCoordinator.shared.acquire(audioOwner) { [weak self] in self?.pauseForInterruption() } }
            catch { voiceEnabled = false }
        }
        if includeArrive {
            enter(.arrive, duration: WindDownGuidanceConfiguration.arriveSeconds, say: WindDownGuidanceConfiguration.arriveLine)
        } else {
            runCycle()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
        AudioSessionCoordinator.shared.release(audioOwner)
        phase = .idle
        phaseProgress = 0
    }

    private func pauseForInterruption() {
        timer?.invalidate()
        timer = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }
    }

    // MARK: - Cycle

    private func runCycle() {
        guard cyclesCompleted < totalCycles else {
            phase = .finished
            if let closingPhrase, !closingPhrase.isEmpty {
                speak(closingPhrase)
            }
            return
        }
        let line = voiceMode.cue(phase: "inhale", cycleIndex: cyclesCompleted)
        enter(.inhale, duration: WindDownGuidanceConfiguration.inhaleSeconds, say: line)
    }

    private func enter(_ next: Phase, duration: Double, say line: String) {
        phase = next
        phaseProgress = 0
        if hapticsEnabled { Haptics.tap() }
        phaseDuration = duration
        phaseStart = .now
        speak(line)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let start = phaseStart else { return }
        let elapsed = Date.now.timeIntervalSince(start)
        phaseProgress = min(1, elapsed / max(0.01, phaseDuration))
        guard elapsed >= phaseDuration else { return }

        switch phase {
        case .arrive:
            runCycle()
        case .inhale:
            enter(.hold, duration: WindDownGuidanceConfiguration.holdSeconds, say: voiceMode.cue(phase: "hold", cycleIndex: cyclesCompleted))
        case .hold:
            enter(.exhale, duration: WindDownGuidanceConfiguration.exhaleSeconds, say: voiceMode.cue(phase: "exhale", cycleIndex: cyclesCompleted))
        case .exhale:
            enter(.rest, duration: WindDownGuidanceConfiguration.restSeconds, say: "")
        case .rest:
            cyclesCompleted += 1
            runCycle()
        case .idle, .quiet, .finished:
            timer?.invalidate()
        }
    }

    private func speak(_ line: String) {
        guard voiceEnabled, !line.isEmpty else { return }
        if synthesizer.isSpeaking { return }
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = resolvedVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        utterance.pitchMultiplier = 0.92
        utterance.preUtteranceDelay = 0.15
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance)
    }

    func previewVoice() {
        speak("Get comfortable. Let your shoulders drop.")
    }

    func resolvedVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let voiceIdentifier, let match = voices.first(where: { $0.identifier == voiceIdentifier }) {
            selectedVoiceName = match.name
            return match
        }
        let locale = Locale.current.identifier
        let ranked = voices
            .filter { $0.language.hasPrefix(String(locale.prefix(2))) }
            .sorted { lhs, rhs in
                qualityRank(lhs) > qualityRank(rhs)
            }
        let chosen = ranked.first ?? AVSpeechSynthesisVoice(language: locale)
        selectedVoiceName = chosen?.name
        return chosen
    }

    private func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: 3
        case .enhanced: 2
        default: 1
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
}
