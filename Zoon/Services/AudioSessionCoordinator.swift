import AVFoundation
import Foundation

/// Playback shares ownership; recording is exclusive to avoid classifying
/// synthesized sounds as room noise. Losing headphones never enables speakers.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()
    private var owners: [UUID: (recording: Bool, stop: () -> Void)] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.interrupt() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.interrupt() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interrupt() }
        })
    }

    func acquire(_ id: UUID, recording: Bool = false, onInterrupt: @escaping () -> Void) throws {
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
        owners[id] = (recording, onInterrupt)
    }

    func release(_ id: UUID) {
        guard owners.removeValue(forKey: id) != nil, owners.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func interrupt() {
        let callbacks = owners.values.map(\.stop)
        for stop in callbacks { stop() }
    }
}
