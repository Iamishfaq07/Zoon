import AVFoundation

@MainActor
final class OnDeviceNarrator: NSObject, AVSpeechSynthesizerDelegate {
    private let speech = AVSpeechSynthesizer()
    private let owner = UUID()
    override init() { super.init(); speech.delegate = self }
    func say(_ text: String) {
        stop()
        do {
            try AudioSessionCoordinator.shared.acquire(owner) { [weak self] in self?.stop() }
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speech.speak(utterance)
        } catch { return }
    }
    func stop() {
        speech.stopSpeaking(at: .immediate)
        AudioSessionCoordinator.shared.release(owner)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, !speech.isSpeaking else { return }
            AudioSessionCoordinator.shared.release(owner)
        }
    }
}
