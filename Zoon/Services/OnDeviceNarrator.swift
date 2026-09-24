import AVFoundation

/// Reads a night back aloud, on device.
///
/// One shared instance, so two screens can never talk over each other: a new
/// `say` replaces whatever is being read. Voice and pacing come from
/// `SleepSpeech.Profile.narration` and the voice picked in Wind Down (the
/// best installed voice when none is picked), the same voice the breathing
/// coach uses. Each sentence is its own utterance with a pause after it.
@MainActor
final class OnDeviceNarrator: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = OnDeviceNarrator()

    private let speech = AVSpeechSynthesizer()
    private let owner = UUID()
    /// The final sentence of the current reading. The audio session is held
    /// until it finishes or the reading is stopped.
    private var lastUtterance: ObjectIdentifier?

    override private init() {
        super.init()
        speech.delegate = self
    }

    /// `voiceIdentifier` overrides the Wind Down voice (for a preview).
    func say(_ text: String, voiceIdentifier: String? = nil) {
        stop()
        let preferred = voiceIdentifier ?? PersonalSetupStore.shared.value.routine.voiceIdentifier
        let utterances = SpeechVoices.utterances(
            for: text,
            profile: .narration,
            voice: SpeechVoices.resolve(preferredIdentifier: preferred)
        )
        guard let last = utterances.last else { return }
        do {
            try AudioSessionCoordinator.shared.acquire(owner) { [weak self] in self?.stop() }
        } catch {
            return
        }
        lastUtterance = ObjectIdentifier(last)
        for utterance in utterances { speech.speak(utterance) }
    }

    func stop() {
        lastUtterance = nil
        speech.stopSpeaking(at: .immediate)
        AudioSessionCoordinator.shared.release(owner)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let finished = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.lastUtterance == finished else { return }
            self.lastUtterance = nil
            AudioSessionCoordinator.shared.release(self.owner)
        }
    }
}
