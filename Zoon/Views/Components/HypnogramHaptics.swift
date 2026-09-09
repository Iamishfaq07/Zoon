import CoreHaptics
import Foundation

/// Stage-coloured haptics for the interactive hypnogram.
///
/// Deep is a heavy low rumble, REM is a rapid high-frequency pattern, Core
/// is a mid thump, Awake is a sharp click. Failures are silent: a missing
/// haptic engine (Simulator, Reduce Motion, older hardware) must not change
/// what the chart shows.
@MainActor
final class HypnogramHaptics {

    private var engine: CHHapticEngine?
    private var lastStage: SleepStage?
    private var lastPlay: Date = .distantPast

    init() {
        engine = try? CHHapticEngine()
        try? engine?.start()
        engine?.stoppedHandler = { [weak self] _ in
            Task { @MainActor in
                try? self?.engine?.start()
            }
        }
        engine?.resetHandler = { [weak self] in
            Task { @MainActor in
                try? self?.engine?.start()
            }
        }
    }

    /// Plays when the scrubber crosses into a new stage. Debounced so a
    /// fast drag does not queue a chord.
    func play(for stage: SleepStage, now: Date = .now) {
        guard stage != lastStage else { return }
        guard now.timeIntervalSince(lastPlay) > 0.04 else { return }
        lastStage = stage
        lastPlay = now
        guard let engine else { return }

        let sharpness: Float
        let intensity: Float
        let duration: TimeInterval
        let pulseCount: Int
        switch stage {
        case .deep:
            sharpness = 0.15
            intensity = 0.9
            duration = 0.18
            pulseCount = 1
        case .rem:
            sharpness = 0.85
            intensity = 0.55
            duration = 0.04
            pulseCount = 3
        case .core, .unspecified:
            sharpness = 0.4
            intensity = 0.5
            duration = 0.08
            pulseCount = 1
        case .awake, .inBed:
            sharpness = 1.0
            intensity = 0.7
            duration = 0.03
            pulseCount = 1
        }

        var events: [CHHapticEvent] = []
        for index in 0..<pulseCount {
            let relative = TimeInterval(index) * (duration + 0.03)
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                    ],
                    relativeTime: relative
                )
            )
            if stage == .deep {
                events.append(
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.7),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0,
                        duration: 0.22
                    )
                )
            }
        }

        guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return }
        let player = try? engine.makePlayer(with: pattern)
        try? player?.start(atTime: CHHapticTimeImmediate)
    }

    func stop() {
        lastStage = nil
    }
}
