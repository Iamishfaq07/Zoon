import Foundation
import AVFoundation
import os
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// Sleep sounds: generated noise plus bundled recorded loops.
///
/// Brown, pink and white stay **synthesised** so they never seam and add
/// nothing to the download. Weather, night and room beds are **recorded**
/// ~90s loops bundled on device — nothing is streamed, nothing phones home.
/// The loops are loudness-matched and crossfaded at the join.
///
/// Sleep onset still drops volume (and, for generated noise, high harmonics)
/// as overnight heart rate falls below resting.
@MainActor
@Observable
final class SoundscapeEngine {

    enum Sound: String, Codable, CaseIterable, Identifiable, Sendable {
        case brownNoise, pinkNoise, whiteNoise
        case rain, rainfall, window, tent, storm, thunder, drizzle, street
        case ocean, harbor, waterfall, wind, blizzard, stream, brook
        case forest, jungle, evening, garden, crickets, insects, pond, mountain
        case fan, fire, embers, purr

        var id: String { rawValue }

        enum Group: String, CaseIterable, Sendable {
            case noise, weather, night, room
            var label: String {
                switch self {
                case .noise: "Noise"
                case .weather: "Weather"
                case .night: "Night"
                case .room: "Room"
                }
            }
        }

        var group: Group {
            switch self {
            case .brownNoise, .pinkNoise, .whiteNoise: .noise
            case .rain, .rainfall, .window, .tent, .storm, .thunder, .drizzle, .street,
                 .ocean, .harbor, .waterfall, .wind, .blizzard, .stream, .brook: .weather
            case .forest, .jungle, .evening, .garden, .crickets, .insects, .pond, .mountain: .night
            case .fan, .fire, .embers, .purr: .room
            }
        }

        /// Bundled loop. `nil` means generated noise.
        var fileName: String? {
            switch self {
            case .brownNoise, .pinkNoise, .whiteNoise: nil
            default: rawValue
            }
        }

        /// Locate a recorded bed in the app bundle.
        ///
        /// Copy Bundle Resources of a yellow group copies files to the
        /// bundle **root**, not `Sounds/`. A folder reference would keep
        /// the subdirectory. Build 68 looked only in `Sounds/`, missed
        /// every file, and fell through to the noise generator — which is
        /// why Rain / Ocean / Wind still sounded synthesised after the
        /// recordings shipped.
        func recordedURL(in bundle: Bundle = .main) -> URL? {
            guard let name = fileName else { return nil }
            if let url = bundle.url(forResource: name, withExtension: "mp3", subdirectory: "Sounds") {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: "mp3") {
                return url
            }
            let fm = FileManager.default
            if let root = bundle.resourceURL {
                let nested = root.appendingPathComponent("Sounds", isDirectory: true)
                    .appendingPathComponent("\(name).mp3", isDirectory: false)
                if fm.fileExists(atPath: nested.path) { return nested }
                let flat = root.appendingPathComponent("\(name).mp3", isDirectory: false)
                if fm.fileExists(atPath: flat.path) { return flat }
            }
            return nil
        }

        var label: String {
            switch self {
            case .brownNoise: "Brown Noise"
            case .pinkNoise: "Pink Noise"
            case .whiteNoise: "White Noise"
            case .rain: "Rain"
            case .rainfall: "Shower"
            case .window: "Window"
            case .tent: "Tent"
            case .storm: "Storm"
            case .thunder: "Thunder"
            case .drizzle: "Drizzle"
            case .street: "Street"
            case .ocean: "Ocean"
            case .harbor: "Harbor"
            case .waterfall: "Falls"
            case .wind: "Wind"
            case .blizzard: "Blizzard"
            case .stream: "Stream"
            case .brook: "Brook"
            case .forest: "Forest"
            case .jungle: "Jungle"
            case .evening: "Evening"
            case .garden: "Garden"
            case .crickets: "Crickets"
            case .insects: "Insects"
            case .pond: "Pond"
            case .mountain: "Ridge"
            case .fan: "Fan"
            case .fire: "Fire"
            case .embers: "Embers"
            case .purr: "Purr"
            }
        }

        var detail: String {
            switch self {
            case .brownNoise: "Deep, low rumble. Generated so it never seams."
            case .pinkNoise: "Balanced hiss. Generated so it never seams."
            case .whiteNoise: "Bright and flat. Generated so it never seams."
            case .rain: "Gentle overnight rain."
            case .rainfall: "Soft rainfall."
            case .window: "Drops on glass."
            case .tent: "Rain on canvas in a forest."
            case .storm: "Rain and distant thunder."
            case .thunder: "Rumble through a storm."
            case .drizzle: "Green-noise rain."
            case .street: "Midnight rain on pavement."
            case .ocean: "Waves on the coast."
            case .harbor: "Small waves on rocks."
            case .waterfall: "Close waterfall."
            case .wind: "Open desert air."
            case .blizzard: "Wind through a cold night."
            case .stream: "Running water."
            case .brook: "Long water bed."
            case .forest: "Frogs and crickets."
            case .jungle: "Calm storm in the trees."
            case .evening: "Birds, crickets, distant dogs."
            case .garden: "Soft wind, birds, crickets."
            case .crickets: "Night field."
            case .insects: "Night forest chorus."
            case .pond: "Water and night insects."
            case .mountain: "Wind on a high ridge."
            case .fan: "Machine hush."
            case .fire: "Campfire and night wind."
            case .embers: "Close crackle."
            case .purr: "A cat, close."
            }
        }

        var symbol: String {
            switch self {
            case .brownNoise: "waveform.path"
            case .pinkNoise: "waveform"
            case .whiteNoise: "waveform.badge.plus"
            case .rain, .rainfall, .drizzle: "cloud.rain.fill"
            case .window: "window.casement.closed"
            case .tent: "tent.fill"
            case .storm, .thunder, .jungle: "cloud.bolt.rain.fill"
            case .street: "building.2.fill"
            case .ocean, .harbor: "water.waves"
            case .waterfall, .stream, .brook: "drop.fill"
            case .wind, .blizzard, .mountain: "wind"
            case .forest, .garden: "tree.fill"
            case .evening, .pond: "moon.stars.fill"
            case .crickets, .insects: "ant.fill"
            case .fan: "fan.fill"
            case .fire, .embers: "flame.fill"
            case .purr: "cat.fill"
            }
        }
    }

    // MARK: - Observable state

    private(set) var playing: Sound?
    var volume: Float = 0.6 {
        didSet { applyOutputVolume() }
    }

    /// Minutes until auto-stop. `nil` = no timer.
    private(set) var timerMinutes: Int?
    private(set) var remainingSeconds: Int = 0

    var isPlaying: Bool { playing != nil && !wasInterrupted && !pausedByUser }

    /// True when the graph is actually producing audio.
    var isGraphAudible: Bool {
        if let filePlayer, filePlayer.isPlaying { return true }
        if let engine, let player, engine.isRunning, player.isPlaying { return true }
        return false
    }

    var timerCaption: String? {
        guard timerMinutes != nil, remainingSeconds > 0 else { return nil }
        return SoundscapeTimerPolicy.stopsInCopy(seconds: remainingSeconds)
    }

    // MARK: - Audio graph

    private var scenePlayers: [SoundscapeEngine] = []
    private var sceneLevels: [PersonalSetup.Layer] = []
    private var playbackGeneration = UUID()
    private let audioOwner = UUID()
    private(set) var deadline: Date?
    private(set) var interruptionMessage: String?
    private(set) var canResumeOnSpeaker = false
    /// Set when a recorded bed is selected but the mp3 is not in the bundle.
    /// Shown on Sleep Sounds so a miss is visible instead of fake noise.
    private(set) var loadError: String?
    private var crossfadeTask: Task<Void, Never>?
    private var retiringPlayers: [(AVAudioEngine, AVAudioPlayerNode)] = []
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var filePlayer: AVAudioPlayer?
    private var retiringFilePlayer: AVAudioPlayer?
    private var timerTask: Task<Void, Never>?
    private var fadeMultiplier: Float = 1
    /// 1 = full presence; drops toward 0.45 as overnight HR falls below
    /// resting, which is the sleep-onset cue this engine listens for.
    private var biometricAttenuation: Float = 1
    /// 1 = unfiltered; lower values strip high harmonics as sleep deepens.
    private var harmonicPresence: Float = 1
    private var pausedSound: Sound?
    private var currentScene: PersonalSetup.Scene?
    private var wasInterrupted = false
    private var pausedByUser = false
    private var watchdogTask: Task<Void, Never>?
    private var watchdogRecoveredGeneration: UUID?
    private var lastSuccessfulPlayback: Date = .distantPast
    private var remoteCommandsInstalled = false
    private let logger = Logger(subsystem: "com.zoon.sleep", category: "Soundscape")

    private let sampleRate: Double = 44_100
    /// Five seconds per buffer. Long enough that scheduling overhead is
    /// negligible, short enough that stopping feels immediate.
    private let bufferSeconds: Double = 5

    // MARK: - Control

    func play(_ sound: Sound, toggle: Bool = true, preservingScene: Bool = false) {
        if playing == sound && toggle { stop(); return }
        if !preservingScene { currentScene = nil }
        pausedByUser = false

        let inherited = SoundscapeTimerPolicy.deadlineAfterSwitchingSound(currentDeadline: deadline)
        if inherited == nil {
            timerTask?.cancel()
            timerTask = nil
            deadline = nil
            timerMinutes = nil
            remainingSeconds = 0
            fadeMultiplier = 1
        } else {
            deadline = inherited
            remainingSeconds = SoundscapeTimerPolicy.remainingSeconds(deadline: inherited)
        }

        for layer in scenePlayers { layer.stop() }
        scenePlayers = []
        sceneLevels = []
        playbackGeneration = UUID()
        let oldEngine = engine
        let oldPlayer = player
        let oldFile = filePlayer
        filePlayer = nil
        crossfadeTask?.cancel()
        for (engine, player) in retiringPlayers { player.stop(); engine.stop() }
        retiringPlayers = []
        retiringFilePlayer?.stop()
        retiringFilePlayer = oldFile
        interruptionMessage = nil
        canResumeOnSpeaker = false
        loadError = nil

        do {
            // `.playback` with `.mixWithOthers` so a soundscape doesn't kill a
            // podcast someone is already falling asleep to, and keeps running
            // when the screen locks.
            try AudioSessionCoordinator.shared.acquire(audioOwner) { [weak self] in
                self?.pauseForInterruption()
            } onResume: { [weak self] in
                self?.resumeAfterInterruption()
            } onReset: { [weak self] in
                self?.stopAfterMediaServicesReset()
            } onRouteLost: { [weak self] in
                self?.pauseForRouteLoss()
            }

            if sound.fileName != nil {
                if let url = sound.recordedURL() {
                    let recorded = try AVAudioPlayer(contentsOf: url)
                    recorded.numberOfLoops = -1
                    recorded.volume = 0
                    recorded.prepareToPlay()
                    guard recorded.play() else {
                        loadError = "Couldn't start \(sound.label)."
                        AudioSessionCoordinator.shared.release(audioOwner)
                        return
                    }
                    oldPlayer?.stop()
                    oldEngine?.stop()
                    self.engine = nil
                    self.player = nil
                    self.filePlayer = recorded
                    self.playing = sound
                    lastSuccessfulPlayback = .now
                    watchdogRecoveredGeneration = nil
                    logger.info("Playing recorded bed \(sound.rawValue, privacy: .public) from \(url.lastPathComponent, privacy: .public)")
                    armWatchdog()
                    publishNowPlaying()
                    resumeInheritedTimerIfNeeded()
                    crossfadeTask = Task { [weak self] in
                        for step in 1...20 {
                            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                            guard let self else { return }
                            let fraction = Float(step) / 20
                            recorded.volume = volume * fadeMultiplier * biometricAttenuation * fraction
                            oldFile?.volume = volume * fadeMultiplier * biometricAttenuation * (1 - fraction)
                        }
                        oldFile?.stop()
                        self?.retiringFilePlayer = nil
                    }
                    return
                }
                logger.error("Recorded bed \(sound.rawValue, privacy: .public) missing from bundle; not synthesizing")
                loadError = "Couldn't load \(sound.label). The recording isn't in this build."
                oldPlayer?.stop()
                oldEngine?.stop()
                oldFile?.stop()
                self.engine = nil
                self.player = nil
                self.filePlayer = nil
                self.playing = nil
                AudioSessionCoordinator.shared.release(audioOwner)
                return
            }

            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 2
            ) else {
                AudioSessionCoordinator.shared.release(audioOwner)
                return
            }

            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()

            player.volume = 0
            player.play()

            self.engine = engine
            self.player = player
            self.playing = sound
            lastSuccessfulPlayback = .now
            watchdogRecoveredGeneration = nil
            oldFile?.stop()
            self.retiringFilePlayer = nil

            // Prime with a few buffers, then keep the queue topped up as each
            // one finishes. Scheduling one at a time would gap on a slow frame.
            for _ in 0..<3 { scheduleBuffer(sound, format: format) }
            armWatchdog()
            publishNowPlaying()
            resumeInheritedTimerIfNeeded()
            if let oldEngine, let oldPlayer { retiringPlayers = [(oldEngine, oldPlayer)] }
            crossfadeTask = Task { [weak self] in
                for step in 1...20 {
                    do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                    guard let self else { return }
                    let fraction = Float(step) / 20
                    player.volume = volume * fadeMultiplier * biometricAttenuation * fraction
                    oldPlayer?.volume = volume * fadeMultiplier * biometricAttenuation * (1 - fraction)
                }
                oldPlayer?.stop()
                oldEngine?.stop()
                self?.retiringPlayers = []
            }
        } catch {
            logger.error("Audio start failed: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    func playScene(_ scene: PersonalSetup.Scene) {
        guard let first = scene.layers.first,
              let sound = Sound(rawValue: first.sound), (1...3).contains(scene.layers.count) else { return }
        currentScene = scene
        play(sound, toggle: false, preservingScene: true)
        guard isPlaying else { return }
        sceneLevels = scene.layers
        volume = Float(first.level) / 3
        for layer in scene.layers.dropFirst() {
            guard let sound = Sound(rawValue: layer.sound) else { continue }
            let child = SoundscapeEngine()
            child.volume = Float(layer.level) / 3
            child.play(sound)
            scenePlayers.append(child)
        }
    }

    func updateSceneLevels(_ layers: [PersonalSetup.Layer]) {
        guard isPlaying, layers.count == sceneLevels.count,
              zip(layers, sceneLevels).allSatisfy({ $0.0.sound == $0.1.sound }) else { return }
        sceneLevels = layers
        volume = Float(layers[0].level) / 3
        for (index, player) in scenePlayers.enumerated() {
            player.volume = Float(layers[index + 1].level) / 3 * fadeMultiplier
        }
    }

    func stop() {
        for layer in scenePlayers { layer.stop() }
        scenePlayers = []
        sceneLevels = []
        crossfadeTask?.cancel()
        crossfadeTask = nil
        for (engine, player) in retiringPlayers { player.stop(); engine.stop() }
        retiringPlayers = []
        deadline = nil
        timerTask?.cancel()
        timerTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        filePlayer?.stop()
        filePlayer = nil
        retiringFilePlayer?.stop()
        retiringFilePlayer = nil
        playing = nil
        timerMinutes = nil
        remainingSeconds = 0
        fadeMultiplier = 1
        biometricAttenuation = 1
        harmonicPresence = 1
        pausedSound = nil
        wasInterrupted = false
        pausedByUser = false
        currentScene = nil
        canResumeOnSpeaker = false
        clearNowPlaying()
        AudioSessionCoordinator.shared.release(audioOwner)
    }

    /// Pause without releasing the session, so an interruption can resume
    /// the same sound rather than leaving the user with a silent night.
    private func pauseForInterruption() {
        guard let playing else { return }
        pausedSound = playing
        wasInterrupted = true
        interruptionMessage = "Playback paused. It will resume when the interruption ends, or tap a sound to start again."
        publishNowPlaying()
        player?.pause()
        filePlayer?.pause()
        for layer in scenePlayers {
            layer.player?.pause()
            layer.filePlayer?.pause()
        }
    }

    private func resumeAfterInterruption() {
        guard wasInterrupted else { return }
        wasInterrupted = false
        interruptionMessage = nil
        if playing != nil, player != nil || filePlayer != nil, restartEnginesIfNeeded() {
            player?.play()
            let fileOK = filePlayer.map { $0.play() } ?? true
            if let sound = playing, let format = player?.outputFormat(forBus: 0), filePlayer == nil {
                scheduleBuffer(sound, format: format)
            }
            for layer in scenePlayers {
                layer.player?.play()
                _ = layer.filePlayer?.play()
            }
            if fileOK {
                lastSuccessfulPlayback = .now
                publishNowPlaying()
                return
            }
        }
        restoreSelection()
    }

    private func restoreSelection() {
        if let scene = currentScene {
            playScene(scene)
        } else if let sound = pausedSound ?? playing {
            play(sound, toggle: false)
        }
    }

    private func pauseForRouteLoss() {
        pauseForInterruption()
        canResumeOnSpeaker = true
        interruptionMessage = "Headphones disconnected. Playback was paused to avoid switching to the speaker."
    }

    func resumeOnSpeaker() {
        canResumeOnSpeaker = false
        interruptionMessage = nil
        wasInterrupted = false
        pausedByUser = false
        restoreSelection()
    }

    func pauseForUser() {
        guard playing != nil || pausedSound != nil else { return }
        pausedSound = playing ?? pausedSound
        pausedByUser = true
        wasInterrupted = false
        interruptionMessage = nil
        player?.pause()
        filePlayer?.pause()
        for layer in scenePlayers {
            layer.player?.pause()
            layer.filePlayer?.pause()
        }
        publishNowPlaying()
    }

    func resumeFromPause() {
        guard pausedByUser else {
            resumeAfterInterruption()
            return
        }
        pausedByUser = false
        wasInterrupted = false
        if playing != nil, player != nil || filePlayer != nil, restartEnginesIfNeeded() {
            player?.play()
            _ = filePlayer?.play()
            for layer in scenePlayers {
                layer.player?.play()
                _ = layer.filePlayer?.play()
            }
            lastSuccessfulPlayback = .now
            publishNowPlaying()
            return
        }
        restoreSelection()
    }

    /// An interruption can stop an `AVAudioEngine` underneath its paused
    /// player node, and `play()` on a node whose engine is not running
    /// crashes. Restart any stopped engine first (this one and each scene
    /// layer's); `false` means the caller should rebuild via `play` instead.
    private func restartEnginesIfNeeded() -> Bool {
        for layer in scenePlayers {
            guard layer.restartEnginesIfNeeded() else { return false }
        }
        guard let engine, !engine.isRunning else { return true }
        do {
            try engine.start()
            return true
        } catch {
            logger.error("Could not restart engine after interruption: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Media services were reset: every engine and node is gone, so there is
    /// nothing to pause or resume. Tear down fully rather than sit in a
    /// "will resume" state that can never fire.
    private func stopAfterMediaServicesReset() {
        guard playing != nil || pausedSound != nil || currentScene != nil else { return }
        let scene = currentScene
        let sound = playing ?? pausedSound
        let savedDeadline = deadline
        stop()
        currentScene = scene
        pausedSound = sound
        deadline = savedDeadline
        interruptionMessage = "Audio was reset by the system. Tap a sound to start again."
        canResumeOnSpeaker = true
    }

    /// Sleep-onset cue: as overnight HR falls below resting, turn the
    /// soundscape down and strip high harmonics so it recedes with the
    /// body rather than staying a constant presence.
    ///
    /// A larger dip is a healthier overnight recovery signal; the
    /// attenuation is bounded so a noisy reading cannot mute the engine.
    func followHeartRate(currentBPM: Double, restingBPM: Double) {
        guard restingBPM > 0, isPlaying else { return }
        let dip = max(0, restingBPM - currentBPM)
        let progress = min(1, dip / 12)
        biometricAttenuation = Float(1 - 0.55 * progress)
        harmonicPresence = Float(1 - 0.7 * progress)
        applyOutputVolume()
        for (index, player) in scenePlayers.enumerated() where index + 1 < sceneLevels.count {
            player.volume = Float(sceneLevels[index + 1].level) / 3 * fadeMultiplier * biometricAttenuation
            player.harmonicPresence = harmonicPresence
        }
    }

    /// Auto-stop after `minutes`, with a fade over the final 60 seconds.
    ///
    /// The fade matters more than it sounds: an abrupt cut at the end of a sleep
    /// timer is itself capable of waking someone, which defeats the entire point.
    func setTimer(minutes: Int?) {
        timerTask?.cancel()
        timerMinutes = minutes
        deadline = minutes.map { Date.now.addingTimeInterval(Double(max(0, $0)) * 60) }
        fadeMultiplier = 1
        applyOutputVolume()

        guard let minutes else {
            remainingSeconds = 0
            fadeMultiplier = 1
            applyOutputVolume()
            publishNowPlaying()
            return
        }

        remainingSeconds = minutes * 60
        // Task{} started from a @MainActor method inherits that isolation, so
        // the properties below are reached synchronously — only the sleep
        // actually suspends.
        timerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self, self.remainingSeconds > 0 else { break }
                self.tick()
            }
            self?.stop()
        }
    }

    private func tick() {
        guard remainingSeconds > 0 else { return }
        remainingSeconds = max(0, Int(ceil(deadline?.timeIntervalSinceNow ?? 0)))

        // Linear fade across the last minute.
        let fadeWindow = 60
        if remainingSeconds <= fadeWindow {
            fadeMultiplier = Float(remainingSeconds) / Float(fadeWindow)
            applyOutputVolume()
            for (index, player) in scenePlayers.enumerated() {
                player.volume = Float(sceneLevels[index + 1].level) / 3 * fadeMultiplier * biometricAttenuation
            }
        }
    }

    var formattedRemaining: String {
        SoundscapeTimerPolicy.formattedRemaining(seconds: remainingSeconds)
    }

    private func resumeInheritedTimerIfNeeded() {
        guard deadline != nil, timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self, self.remainingSeconds > 0 else { break }
                self.tick()
            }
            self?.stop()
        }
    }

    private func armWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                if Task.isCancelled { return }
                await self?.checkPlaybackHealth()
            }
        }
    }

    private func checkPlaybackHealth() {
        guard playing != nil, !wasInterrupted, !pausedByUser else { return }
        if timerMinutes != nil, remainingSeconds <= 0 { return }
        if isGraphAudible {
            lastSuccessfulPlayback = .now
            return
        }
        if watchdogRecoveredGeneration == playbackGeneration {
            markPlaybackFailed()
            return
        }
        watchdogRecoveredGeneration = playbackGeneration
        if let filePlayer {
            guard filePlayer.play(), filePlayer.isPlaying else {
                markPlaybackFailed()
                return
            }
            lastSuccessfulPlayback = .now
            return
        }
        if restartEnginesIfNeeded(), let player {
            player.play()
            if isGraphAudible {
                lastSuccessfulPlayback = .now
                return
            }
        }
        markPlaybackFailed()
    }

    private func markPlaybackFailed() {
        interruptionMessage = "Audio was interrupted by the system. Tap to resume."
        watchdogTask?.cancel()
        watchdogTask = nil
        playing = nil
        clearNowPlaying()
    }

    private func publishNowPlaying() {
        #if canImport(MediaPlayer)
        installRemoteCommandsIfNeeded()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: playing?.label ?? "Sleep Sounds",
            MPMediaItemPropertyArtist: "Zoon"
        ]
        info[MPNowPlayingInfoPropertyPlaybackRate] = (playing != nil && !wasInterrupted && !pausedByUser) ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    private func clearNowPlaying() {
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    private func installRemoteCommandsIfNeeded() {
        #if canImport(MediaPlayer)
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.stopCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.pausedByUser {
                self.resumeFromPause()
                return .success
            }
            if self.currentScene != nil {
                self.restoreSelection()
                return .success
            }
            if let sound = self.playing ?? self.pausedSound {
                self.play(sound, toggle: false)
                return .success
            }
            return .noActionableNowPlayingItem
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pauseForUser()
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }
        #endif
    }

    private func applyOutputVolume() {
        let v = volume * fadeMultiplier * biometricAttenuation
        player?.volume = v
        filePlayer?.volume = v
    }

    // MARK: - Synthesis

    private func scheduleBuffer(_ sound: Sound, format: AVAudioFormat) {
        guard let player, let buffer = makeBuffer(sound, format: format) else { return }

        let generation = playbackGeneration
        player.scheduleBuffer(buffer) { [weak self] in
            // Completion fires on an audio thread; hop back before touching
            // any of this actor's state.
            Task { @MainActor [weak self] in
                guard let self, self.playing == sound, self.playbackGeneration == generation else { return }
                self.scheduleBuffer(sound, format: format)
            }
        }
    }

    /// Generator state carried across buffers so filters don't click at seams.
    private var brownState: Float = 0
    private var pinkRows = [Float](repeating: 0, count: 7)
    private var lowpassState: Float = 0

    private func makeBuffer(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Recorded beds never share this generator. A missing file stops in
        // `play()` rather than becoming brown noise.
        guard sound.fileName == nil else { return nil }

        let frameCount = AVAudioFrameCount(sampleRate * bufferSeconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }

        buffer.frameLength = frameCount
        let left = channels[0]
        let right = channels[1]

        for frame in 0..<Int(frameCount) {
            let white = Float.random(in: -1...1)
            var sample: Float

            switch sound {
            case .whiteNoise:
                sample = white * 0.25

            case .pinkNoise:
                // Voss-McCartney: sum of octave-spaced random rows. Cheaper and
                // more stable than an IIR pink filter.
                sample = pinkSample(white) * 0.16

            case .brownNoise:
                // Integrated white noise, leaked toward zero so it can't drift
                // into DC offset over a long session.
                brownState = (brownState + white * 0.02) * 0.995
                sample = brownState * 2.4

            default:
                return nil
            }

            sample = max(-1, min(1, sample))
            if harmonicPresence < 0.999 {
                // Extra pole on top of each sound's own filter: as HR dips,
                // the remaining high-frequency content is stripped so the
                // soundscape recedes rather than staying bright at the
                // pillow.
                let coefficient = 0.08 + 0.45 * harmonicPresence
                sample = lowpass(sample, coefficient: coefficient)
            }

            // Slight stereo decorrelation. Identical channels image as a point
            // inside your head, which is fatiguing; a touch of difference makes
            // it sit around you instead.
            left[frame] = sample
            right[frame] = sample * 0.92 + Float.random(in: -0.02...0.02)
        }

        return buffer
    }

    private func pinkSample(_ white: Float) -> Float {
        var sum: Float = 0
        for row in 0..<pinkRows.count {
            // Each row updates half as often as the one before it.
            if Int.random(in: 0..<(1 << row)) == 0 {
                pinkRows[row] = Float.random(in: -1...1)
            }
            sum += pinkRows[row]
        }
        return (sum / Float(pinkRows.count)) + white * 0.1
    }

    private func lowpass(_ input: Float, coefficient: Float) -> Float {
        lowpassState += coefficient * (input - lowpassState)
        return lowpassState
    }
}
