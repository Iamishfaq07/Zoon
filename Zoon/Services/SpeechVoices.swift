import AVFoundation

/// `SleepSpeech` choices applied to the system synthesizer. Installed voices
/// only -- never a download.
@MainActor
enum SpeechVoices {

    static func installed(localeIdentifier: String = Locale.current.identifier) -> [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let byIdentifier = Dictionary(all.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        return SleepSpeech.ranked(all.map(describe), localeIdentifier: localeIdentifier)
            .compactMap { byIdentifier[$0.identifier] }
    }

    static func resolve(preferredIdentifier: String?, localeIdentifier: String = Locale.current.identifier) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        guard let chosen = SleepSpeech.choose(all.map(describe), preferredIdentifier: preferredIdentifier, localeIdentifier: localeIdentifier) else {
            return AVSpeechSynthesisVoice(language: localeIdentifier.replacingOccurrences(of: "_", with: "-"))
        }
        return all.first { $0.identifier == chosen.identifier }
    }

    static func qualityLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        describe(voice).quality.label
    }

    /// One utterance per sentence, paced by `profile`.
    static func utterances(for text: String, profile: SleepSpeech.Profile, voice: AVSpeechSynthesisVoice?) -> [AVSpeechUtterance] {
        let sentences = SleepSpeech.sentences(text)
        return sentences.enumerated().map { index, sentence in
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * profile.rateScale
            utterance.pitchMultiplier = profile.pitch
            utterance.preUtteranceDelay = index == 0 ? profile.leadIn : 0
            utterance.postUtteranceDelay = profile.sentencePause
            return utterance
        }
    }

    private static func describe(_ voice: AVSpeechSynthesisVoice) -> SleepSpeech.Voice {
        let quality: SleepSpeech.Quality = switch voice.quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
        return SleepSpeech.Voice(identifier: voice.identifier, name: voice.name, language: voice.language, quality: quality)
    }
}
