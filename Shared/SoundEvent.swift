import Foundation

/// A single classified sound moment during an overnight listening session --
/// "what" and "when", not audio. See `SnoreDetector`'s privacy note: nothing
/// but this derived (identifier, time, confidence) triple survives past the
/// buffer it was measured in.
struct SoundEvent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    /// Apple's on-device SoundAnalysis taxonomy identifier (e.g. "snoring",
    /// "cough", "speech") -- stored raw rather than mapped into an enum up
    /// front, so a category this app doesn't have a curated label for is
    /// still kept (and still shown, humanized by `label`) instead of being
    /// silently dropped.
    let identifier: String
    let confidence: Double

    init(id: UUID = UUID(), date: Date = .now, identifier: String, confidence: Double) {
        self.id = id
        self.date = date
        self.identifier = identifier
        self.confidence = confidence
    }

    /// A human label for `identifier`: a curated name for the categories
    /// this app calls out specifically, a humanized fallback (underscores to
    /// spaces, capitalized) for everything else Apple's classifier can
    /// return -- the taxonomy has hundreds of identifiers, and only a few
    /// are meaningful in a bedroom context, but an unrecognized one should
    /// still read as *something* rather than vanish.
    var label: String {
        switch identifier {
        case "snoring": "Snoring"
        case "cough", "coughing": "Coughing"
        case "baby_cry_infant_cry", "baby_crying": "Baby crying"
        default: identifier.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var symbol: String {
        switch identifier {
        case "snoring": "moon.zzz.fill"
        case "cough", "coughing": "person.wave.2.fill"
        case "baby_cry_infant_cry", "baby_crying": "exclamationmark.bubble.fill"
        default: "waveform"
        }
    }
}
