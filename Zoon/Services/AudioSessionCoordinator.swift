import AVFoundation
import Foundation

/// Playback shares ownership; recording is exclusive to avoid classifying
/// synthesized sounds as room noise. Losing headphones never enables speakers.
///
/// Interruptions (a call, an alarm, Siri) pause owners; when the system says
/// the session may resume, each owner is asked to start again. A route change
/// that *removes* the output device is still a hard stop -- there is nowhere
/// to resume to -- and is not treated as a recoverable interruption.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    private var owners: [UUID: Owner] = [:]
    private var observers: [NSObjectProtocol] = []

    private struct Owner {
        var recording: Bool
        var stop: () -> Void
        var resume: (() -> Void)?
        var reset: (() -> Void)?
    }

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.interrupt() }
                return
            }
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            Task { @MainActor in self?.resumeInterrupted(shouldResume: options.contains(.shouldResume)) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.interrupt() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        })
    }

    func acquire(
        _ id: UUID,
        recording: Bool = false,
        onInterrupt: @escaping () -> Void,
        onResume: (() -> Void)? = nil,
        onReset: (() -> Void)? = nil
    ) throws {
        let others = owners.filter { $0.key != id }
        guard !others.values.contains(where: { $0.recording }) && (!recording || others.isEmpty) else {
            throw NSError(domain: "ZoonAudio", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Stop the active sound or recording before starting this session."])
        }
        let session = AVAudioSession.sharedInstance()
        if owners.isEmpty {
            try session.setCategory(recording ? .record : .playback,
                mode: recording ? .measurement : .default, options: recording ? [] : [.mixWithOthers])
            try session.setActive(true)
        }
        owners[id] = Owner(recording: recording, stop: onInterrupt, resume: onResume, reset: onReset)
    }

    func release(_ id: UUID) {
        guard owners.removeValue(forKey: id) != nil, owners.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func interrupt() {
        let callbacks = owners.values.map(\.stop)
        for stop in callbacks { stop() }
    }

    /// Media services restarted underneath us: every engine and node the
    /// owners held is gone, so there is nothing to resume to. Owners that
    /// distinguish this from a pause get their reset handler; the rest are
    /// interrupted as before.
    private func reset() {
        let callbacks = owners.values.map { $0.reset ?? $0.stop }
        for callback in callbacks { callback() }
    }

    private func resumeInterrupted(shouldResume: Bool) {
        guard shouldResume else { return }
        let callbacks = owners.values.compactMap(\.resume)
        for resume in callbacks { resume() }
    }
}