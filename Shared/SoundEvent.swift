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

// MARK: - Episodes rather than moments

extension SoundEvent {

    /// A run of the same kind of sound, close enough together to be one
    /// thing that happened.
    ///
    /// `SoundAnalysis` classifies a short buffer at a time, so a person who
    /// snores for twenty minutes does not produce one snoring event -- they
    /// produce dozens, a second or two apart. Listed raw, that is a wall of
    /// identical rows reading "Snoring 01:41, Snoring 01:41, Snoring 01:42",
    /// which is the same information as "Snoring, 01:40-02:03, 23 minutes"
    /// and considerably harder to read.
    ///
    /// It is also misleading in a way a count cannot fix. Forty rows *look*
    /// like forty things that happened. They are one thing, sampled forty
    /// times, and the number is a property of the classifier's buffer size
    /// rather than of the night.
    struct Cluster: Identifiable, Hashable, Sendable {
        /// The taxonomy identifier every event in the run shares.
        let identifier: String
        let start: Date
        let end: Date
        /// How many classified moments went into it. Kept because it is real,
        /// shown sparingly: see the type doc on why it is not a count of
        /// events in the everyday sense.
        let count: Int
        /// The strongest moment in the run.
        ///
        /// Peak rather than mean, deliberately. A run's trailing edge is
        /// where the sound is fading and the classifier is least sure, so an
        /// average drags a confident detection down in proportion to how long
        /// it lasted -- which would make a long, obvious episode look less
        /// certain than a short one.
        let peakConfidence: Double

        var id: String { "\(identifier)-\(start.timeIntervalSince1970)" }

        var duration: TimeInterval { end.timeIntervalSince(start) }
        var minutes: Double { duration / 60 }

        /// True when the run is a single classified moment, or short enough
        /// that a duration would be noise.
        ///
        /// The distinction the view needs: a momentary cluster is shown as a
        /// time, and one with real extent as a span. Rendering "01:42-01:42,
        /// 0 minutes" is worse than rendering "01:42".
        var isMomentary: Bool { duration < SoundEvent.momentaryBelow }

        /// Borrowed from the event type so a cluster renders like the thing
        /// it is made of, including for identifiers this app has no curated
        /// name for.
        private var representative: SoundEvent {
            SoundEvent(date: start, identifier: identifier, confidence: peakConfidence)
        }

        var label: String { representative.label }
        var symbol: String { representative.symbol }
    }

    /// How long a silence has to be before two runs of the same sound are two
    /// episodes rather than one.
    ///
    /// Five minutes. Snoring pauses -- a turn over, a position change -- and
    /// stitching across those is the whole point; an hour of quiet in between
    /// is genuinely a second episode. The threshold is here rather than at a
    /// call site so it can be argued with in one place.
    static let clusterGap: TimeInterval = 5 * 60

    /// Below this, a cluster is reported as a moment rather than a span.
    static let momentaryBelow: TimeInterval = 30

    /// Groups `events` into episodes, in time order.
    ///
    /// Clustering is per identifier and then re-sorted, which is the part
    /// worth stating: a cough in the middle of a snoring run does **not**
    /// split the snoring. The two are different things happening in the same
    /// stretch of night, and interleaving them into one sequence would report
    /// three episodes where there were two.
    static func clusters(from events: [SoundEvent]) -> [Cluster] {
        var byIdentifier: [String: [SoundEvent]] = [:]
        for event in events {
            byIdentifier[event.identifier, default: []].append(event)
        }

        var clusters: [Cluster] = []
        for (identifier, group) in byIdentifier {
            let ordered = group.sorted { $0.date < $1.date }
            var start = ordered[0].date
            var end = ordered[0].date
            var count = 0
            var peak = 0.0

            func close() {
                clusters.append(
                    Cluster(
                        identifier: identifier, start: start, end: end,
                        count: count, peakConfidence: peak
                    )
                )
            }

            for event in ordered {
                if count > 0, event.date.timeIntervalSince(end) > clusterGap {
                    close()
                    start = event.date
                    count = 0
                    peak = 0
                }
                end = event.date
                count += 1
                peak = max(peak, event.confidence)
            }
            if count > 0 { close() }
        }

        return clusters.sorted { $0.start < $1.start }
    }
}
