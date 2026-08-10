import Foundation
import AVFoundation

/// Narrates a wind-down breathing exercise entirely on-device.
///
/// `AVSpeechSynthesizer` rather than bundled audio files or a downloaded
/// voice model — no licensing, no download, and no departure from the app's
/// standing rule that nothing is fetched over a network. The trade-off is
/// honest: a system voice reads as more mechanical than a professionally
/// recorded meditation. That's the cost of staying inside "ships with no
/// content and needs nothing added."
@MainActor
@Observable
final class BreathingCoach: NSObject {

    enum Phase: Equatable {
        case idle
        case inhale, hold, exhale, rest
        case finished
    }

    private(set) var phase: Phase = .idle
    /// 0...1 within the current phase, for the pacer animation.
    private(set) var phaseProgress: Double = 0
    private(set) var cyclesCompleted = 0

    /// 4-7-8 breathing: inhale 4s, hold 7s, exhale 8s. A well-established
    /// pattern for calming rather than an invented one — the timings are the
    /// entire technique, so getting them right matters more than usual.
    private let inhaleSeconds: Double = 4
    private let holdSeconds: Double = 7
    private let exhaleSeconds: Double = 8
    private let restSeconds: Double = 2

    var totalCycles = 4

    private let synthesizer = AVSpeechSynthesizer()
    private var timer: Timer?
    private var phaseStart: Date?
    private var phaseDuration: Double = 0

    /// Starts (or restarts) the exercise.
    func start(cycles: Int = 4) {
        stop()
        totalCycles = cycles
        cyclesCompleted = 0
        speak("Let's begin. Find a comfortable position, and breathe with me.")
        runCycle()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        synthesizer.stopSpeaking(at: .immediate)
        phase = .idle
        phaseProgress = 0
    }

    // MARK: - Cycle

    private func runCycle() {
        guard cyclesCompleted < totalCycles else {
            phase = .finished
            speak("Well done. Rest here as long as you like.")
            return
        }
        enter(.inhale, duration: inhaleSeconds, say: "Breathe in")
    }

    private func enter(_ next: Phase, duration: Double, say line: String) {
        phase = next
        phaseDuration = duration
        phaseStart = .now
        speak(line)

        timer?.invalidate()
        // 20Hz tick is smooth enough for a slow-moving pacer and cheap enough
        // to run for the several minutes a session lasts.
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let start = phaseStart else { return }
        let elapsed = Date.now.timeIntervalSince(start)
        phaseProgress = min(1, elapsed / phaseDuration)
        guard elapsed >= phaseDuration else { return }

        switch phase {
        case .inhale: enter(.hold, duration: holdSeconds, say: "Hold")
        case .hold: enter(.exhale, duration: exhaleSeconds, say: "Breathe out")
        case .exhale:
            enter(.rest, duration: restSeconds, say: "")
        case .rest:
            cyclesCompleted += 1
            runCycle()
        case .idle, .finished:
            timer?.invalidate()
        }
    }

    private func speak(_ line: String) {
        guard !line.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: line)
        // Slower and a touch lower than the default — the point is to sound
        // like the pace being asked for, not to sound urgent.
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate + 0.05
        utterance.pitchMultiplier = 0.92
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }
}
