import Foundation

/// How Zoon speaks, in one place.
///
/// Audit §9.4: the night-replay narrator used the default rate and whatever
/// voice the system picked, while the breathing coach chose the best
/// installed voice and slowed down -- two voices for one app, one of them
/// brisk and robotic at bedtime. Both now take their voice and pacing from
/// here. Everything is on device: only voices already installed are
/// considered, and nothing is downloaded.
///
/// The choices are plain values so they can be tested without a synthesizer;
/// `SpeechVoices` (app target) maps them onto `AVSpeechSynthesisVoice`.
enum SleepSpeech {

    /// Pacing for one kind of speech.
    struct Profile: Equatable, Sendable {
        /// Multiple of the system's default rate. Below 1 is slower.
        let rateScale: Float
        let pitch: Float
        /// Silence before the first sentence.
        let leadIn: TimeInterval
        /// Silence after each sentence, so a summary isn't read as one breath.
        let sentencePause: TimeInterval

        /// Breathing cues: slow, a little low, short gaps (the cues are
        /// already spaced by the breathing phases).
        static let breathing = Profile(rateScale: 0.85, pitch: 0.92, leadIn: 0.15, sentencePause: 0.2)

        /// Reading a night back: slower than conversation and a clear pause
        /// between events, so each one lands.
        static let narration = Profile(rateScale: 0.9, pitch: 0.95, leadIn: 0.1, sentencePause: 0.45)

        /// Wind Down guidance between the breathing cycles: the slowest and
        /// lowest Zoon speaks, with a long rest after each sentence so a line
        /// of a body scan is followed by room to do what it says.
        static let windDown = Profile(rateScale: 0.78, pitch: 0.9, leadIn: 0.3, sentencePause: 1.4)
    }

    /// An installed voice, reduced to what choosing one needs.
    struct Voice: Equatable, Sendable {
        let identifier: String
        let name: String
        /// BCP-47, as the system reports it ("en-US").
        let language: String
        let quality: Quality
        /// A novelty voice ("Albert", "Bubbles", "Zarvox"), as the system
        /// flags it. Never chosen automatically.
        var isNovelty = false

        /// The Eloquence voices ("Eddy", "Flo", "Grandma", "Reed", ...) are a
        /// compact formant synthesiser: clear, and unmistakably robotic.
        /// The system does not flag them as novelty, so they are recognised
        /// by identifier.
        var isEloquence: Bool { identifier.contains(".eloquence.") }

        /// Whether this voice may be picked on the person's behalf.
        var isSuitableForBedtime: Bool { !isNovelty && !isEloquence }
    }

    enum Quality: Int, Comparable, Sendable {
        case standard = 1, enhanced, premium

        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .standard: "Default"
            case .enhanced: "Enhanced"
            case .premium: "Premium"
            }
        }
    }

    /// Voices for the user's language, best first: premium, then enhanced,
    /// then default; within a quality, the system's own default voice for the
    /// language (the one set in Settings > Accessibility > Spoken Content),
    /// then the user's own region; then by name, so the list does not
    /// reshuffle between launches.
    ///
    /// Novelty and Eloquence voices are left out. With no Enhanced or Premium
    /// voice installed, "by name" used to pick the alphabetically first
    /// standard voice, which for English is a novelty or Eloquence voice
    /// ("Albert", "Eddy") -- the robotic Wind Down people heard.
    static func ranked(_ voices: [Voice], localeIdentifier: String, systemDefaultIdentifier: String? = nil) -> [Voice] {
        let wanted = LanguageTag(localeIdentifier)
        return voices
            .filter { LanguageTag($0.language).language == wanted.language && $0.isSuitableForBedtime }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                let lhsDefault = lhs.identifier == systemDefaultIdentifier
                let rhsDefault = rhs.identifier == systemDefaultIdentifier
                if lhsDefault != rhsDefault { return lhsDefault }
                let lhsRegion = LanguageTag(lhs.language).region == wanted.region
                let rhsRegion = LanguageTag(rhs.language).region == wanted.region
                if lhsRegion != rhsRegion { return lhsRegion }
                return lhs.name < rhs.name
            }
    }

    /// The voice to speak with: the one the user picked if it is still
    /// installed (even a novelty voice -- that was their choice), otherwise
    /// the best installed voice for their language. `nil` leaves the choice
    /// to the system.
    static func choose(
        _ voices: [Voice],
        preferredIdentifier: String?,
        localeIdentifier: String,
        systemDefaultIdentifier: String? = nil
    ) -> Voice? {
        if let preferredIdentifier, let picked = voices.first(where: { $0.identifier == preferredIdentifier }) {
            return picked
        }
        return ranked(voices, localeIdentifier: localeIdentifier, systemDefaultIdentifier: systemDefaultIdentifier).first
    }

    /// Whether to suggest downloading a better voice: nothing better than a
    /// standard-quality voice is installed for the language. The download
    /// itself is in iOS Settings > Accessibility > Spoken Content > Voices;
    /// Zoon can only point there.
    static func shouldSuggestBetterVoice(_ voices: [Voice], localeIdentifier: String) -> Bool {
        (ranked(voices, localeIdentifier: localeIdentifier).first?.quality ?? .standard) == .standard
    }

    /// Splits text into sentences to be spoken with a pause after each.
    /// Whitespace-only pieces are dropped; text with no sentence end is one
    /// sentence.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { substring, _, _, _ in
            guard let trimmed = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            result.append(trimmed)
        }
        if result.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        }
        return result
    }

    /// "en_US", "en-US", "yue-Hant-HK" -> language and region.
    struct LanguageTag: Equatable {
        let language: String
        let region: String?

        init(_ identifier: String) {
            let parts = identifier.replacingOccurrences(of: "_", with: "-")
                .split(separator: "-")
                .map(String.init)
            language = parts.first?.lowercased() ?? ""
            // A region is two letters or three digits; a four-letter part is a script.
            region = parts.dropFirst().first { part in
                (part.count == 2 && part.allSatisfy(\.isLetter)) || (part.count == 3 && part.allSatisfy(\.isNumber))
            }?.uppercased()
        }
    }
}
