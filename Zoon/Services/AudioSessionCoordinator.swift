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
        var routeLost: (() -> Void)?
    }

    private(set) var lastMediaServicesResetSucceeded = true
    /// `false` when the last interruption ended but the session could not be
    /// reactivated after `InterruptionResumePolicy`'s attempts. Owners stay
    /// paused; a screen can offer to start again rather than show playing.
    private(set) var lastInterruptionResumeSucceeded = true
    private var resumeTask: Task<Void, Never>?

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
            Task { @MainActor in self?.routeLost() }
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
        onReset: (() -> Void)? = nil,
        onRouteLost: (() -> Void)? = nil
    ) throws {
        let others = owners.filter { $0.key != id }
        guard !others.values.contains(where: { $0.recording }) && (!recording || others.isEmpty) else {
            let message = recording
                ? "Stop Zoon's sleep audio before starting Snore Check so its own sound isn't classified as room audio."
                : "Stop the active recording before starting playback."
            throw NSError(domain: "ZoonAudio", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        let session = AVAudioSession.sharedInstance()
        if owners.isEmpty {
            try session.setCategory(recording ? .record : .playback,
                mode: recording ? .measurement : .default, options: recording ? [] : [.mixWithOthers])
            try session.setActive(true)
        }
        owners[id] = Owner(recording: recording, stop: onInterrupt, resume: onResume, reset: onReset, routeLost: onRouteLost)
    }

    func release(_ id: UUID) {
        guard owners.removeValue(forKey: id) != nil, owners.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func interrupt() {
        // A new interruption supersedes a resume still retrying.
        resumeTask?.cancel()
        resumeTask = nil
        let callbacks = owners.values.map(\.stop)
        for stop in callbacks { stop() }
    }

    /// Media services restarted underneath us: every engine and node the
    /// owners held is gone, so there is nothing to resume to.
    ///
    /// Restore category/mode and reactivate *before* asking owners to
    /// rebuild. Owners that reconstruct Soundscape / BreathingCoach / Snore
    /// against a dead session would start engines that cannot run. If this
    /// restore fails, owners are not told the session is healthy.
    private func reset() {
        guard !owners.isEmpty else { return }
        let recording = owners.values.contains(where: \.recording)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                recording ? .record : .playback,
                mode: recording ? .measurement : .default,
                options: recording ? [] : [.mixWithOthers]
            )
            try session.setActive(true)
            lastMediaServicesResetSucceeded = true
        } catch {
            lastMediaServicesResetSucceeded = false
            return
        }
        guard AudioSessionResetOrder.shouldNotifyOwners(sessionRestored: lastMediaServicesResetSucceeded) else {
            return
        }
        let callbacks = owners.values.map { $0.reset ?? $0.stop }
        for callback in callbacks { callback() }
    }

    /// Reactivates, with bounded retries, and only then asks owners to
    /// resume. See `InterruptionResumePolicy`.
    private func resumeInterrupted(shouldResume: Bool) {
        guard shouldResume, !owners.isEmpty else { return }
        resumeTask?.cancel()
        resumeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let resumed = await InterruptionResumePolicy.resume(
                sleep: { try? await Task.sleep(for: .seconds($0)) },
                shouldContinue: { !Task.isCancelled && !self.owners.isEmpty },
                activate: { try AVAudioSession.sharedInstance().setActive(true) },
                notify: {
                    let callbacks = self.owners.values.compactMap(\.resume)
                    for resume in callbacks { resume() }
                }
            )
            if !Task.isCancelled {
                self.lastInterruptionResumeSucceeded = resumed
            }
        }
    }

    /// Headphones unplugged: playback owners must not dump to speakers.
    /// Recording owners keep the built-in mic — overnight Snore Check should
    /// not end because a Bluetooth headset disconnected.
    private func routeLost() {
        let playback = owners.values.filter { !$0.recording }
        for owner in playback {
            (owner.routeLost ?? owner.reset ?? owner.stop)()
        }
    }
}