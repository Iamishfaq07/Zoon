import Foundation
import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class VoiceJournalRecorder {
    var transcript = ""
    var isRecording = false
    var error: String?
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private let audioOwner = UUID()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isRecording { stop(); return }
        // The screen promises audio is processed on this device; a recogniser
        // that can only run server-side would silently break that promise.
        guard let recognizer else { error = "Speech recognition isn't available for this language."; return }
        guard recognizer.supportsOnDeviceRecognition else { error = "On-device transcription isn't available for this language."; return }
        guard await requestPermissions() else { error = "Microphone and speech recognition access are required."; return }
        do {
            try AudioSessionCoordinator.shared.acquire(audioOwner, recording: true) { [weak self] in self?.stop() }
            let request = SFSpeechAudioBufferRecognitionRequest(); self.request = request
            request.requiresOnDeviceRecognition = true
            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }
            audioEngine.prepare(); try audioEngine.start(); isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in if let result { self?.transcript = result.bestTranscription.formattedString }; if error != nil { self?.stop() } }
            }
        } catch { self.error = error.localizedDescription; stop() }
    }
    func stop() { if audioEngine.isRunning { audioEngine.stop() }; audioEngine.inputNode.removeTap(onBus: 0); request?.endAudio(); task?.cancel(); request = nil; task = nil; AudioSessionCoordinator.shared.release(audioOwner); isRecording = false }
    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        return speech && mic
    }
}
