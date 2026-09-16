import Foundation

/// The sequence of recorded events around one awakening.
///
/// Language is deliberately co-occurrence, never cause. A snore that ended
/// two minutes before an awake epoch is a neighbour on the timeline, not an
/// explanation. Missing streams are omitted, never fabricated.
///
/// **The §25 upgrade, and what made it possible.** This screen used to print
/// "Zoon doesn't read heart rate minute by minute yet" — accurate at the time,
/// because the only overnight series the app fetched was hourly, and an hourly
/// bucket cannot place a rise inside a four-minute awakening. Filling that gap
/// with the hourly series would have invented a precision the data did not
/// have. `binnedHeartRate` takes any bin width, so the fix was to go and get
/// the resolution rather than to relax the standard: `Series` below carries
/// five-minute bins across the night, and the rise is *derived* from them
/// instead of being handed in by a caller that had nowhere to get it.
///
/// **Every derived marker states what it is measured against.** A heart-rate
/// rise means a rise above this awakening's own preceding minutes, not above
/// a population figure and not above the night's average — the question is
/// whether something changed *here*, and the local baseline is the only
/// comparison that answers it.
enum AwakeningInspector {

    struct Marker: Identifiable, Hashable, Sendable {
        enum Kind: String, Sendable {
            case hrRise, awake, soundEnded, movement, stageResume, snore
        }
        let date: Date
        let kind: Kind
        let caption: String
        var id: String { "\(kind.rawValue)-\(date.timeIntervalSince1970)" }
    }

    struct Sequence: Hashable, Sendable {
        let awakeningStart: Date
        let awakeningMinutes: Double
        let markers: [Marker]
        let caveat: String
        let missingStreams: [String]
        /// The heart-rate bins inside the window, for a caller that wants to
        /// draw the trace rather than only the markers. Empty when there was
        /// no series to read, which is not the same as a flat one.
        var heartRateWindow: [Sample] = []
        /// Respiratory rate in the window against the rest of the night, when
        /// both were measured and the difference clears the noise. A sentence
        /// rather than a marker: a respiratory rate is a level over minutes,
        /// not an event at an instant.
        var respiratoryNote: String?
        /// Named wherever a movement marker appears, so the marker cannot be
        /// read as an accelerometer reading it is not.
        var movementProvenance: String?

        /// The window the markers and the trace live in.
        var window: DateInterval {
            DateInterval(
                start: awakeningStart.addingTimeInterval(-windowMinutes * 60),
                end: awakeningStart.addingTimeInterval(windowMinutes * 60)
            )
        }
    }

    /// How far either side of the awakening to look. The brief asks for
    /// ±10–15 minutes; twelve sits in the middle and divides evenly into the
    /// five-minute bins the series arrives in.
    static let windowMinutes = 12.0
    /// Sound events quieter than this are not called out, matching `SleepReplay`.
    static let minimumSoundConfidence = 0.6

    /// Bin width for every series this reads.
    ///
    /// One minute, not the five `RestorativeWindow` uses. The two are asking
    /// different questions: that one looks for a settled stretch of half an
    /// hour, this one has to place an event inside a ±12-minute window. At
    /// five minutes the window holds three bins before the awakening, which is
    /// not enough to be a baseline *and* a candidate — the rise could never
    /// fire at all. The cost is the same either way: `HKStatisticsCollectionQuery`
    /// buckets in its own store, so a finer request is not a heavier one.
    ///
    /// Overnight coverage at this width is sparse — a watch writes a heart
    /// rate every few minutes, not every minute — which is why `Sample.value`
    /// is optional and every gate counts readings rather than bins.
    static let binMinutes = 1

    /// How far a heart rate has to rise above the preceding minutes before it
    /// is worth a marker. Five beats: overnight heart rate drifts by a beat or
    /// two between readings in ordinary sleep, and a threshold under that would
    /// put a marker on every awakening whether or not anything happened.
    static let riseThresholdBpm = 5.0

    /// Readings of quiet sleep needed before the rise has something to be a
    /// rise *against*. Three, so the comparison is a median rather than a
    /// point — and counted in readings rather than in bins, because at this
    /// width most bins are empty.
    static let minimumBaselineBins = 3

    /// Active energy in one bin that reads as movement rather than as lying
    /// still. Overnight bins sit at or near zero, so this is deliberately low
    /// — and it is a proxy, which `movementProvenance` says out loud rather
    /// than letting the marker imply an accelerometer.
    static let movementKcalPerBin = 0.5

    /// A respiratory difference smaller than this is inside the noise of the
    /// measurement and is not reported.
    static let respiratoryDeltaThreshold = 1.0

    /// One binned reading. `value` is absent where the bin had no coverage,
    /// never zero — a zero heart rate is not a calm one.
    struct Sample: Hashable, Sendable {
        let date: Date
        let value: Double?

        init(date: Date, value: Double?) {
            self.date = date
            self.value = value
        }
    }

    /// The overnight series this reads, at `binMinutes`. Each is optional in
    /// practice: a night with no watch has none of them, and the inspector
    /// says which are missing rather than drawing an empty axis.
    struct Series: Hashable, Sendable {
        var heartRate: [Sample] = []
        var movement: [Sample] = []
        var respiratory: [Sample] = []

        init(heartRate: [Sample] = [], movement: [Sample] = [], respiratory: [Sample] = []) {
            self.heartRate = heartRate
            self.movement = movement
            self.respiratory = respiratory
        }

        var isEmpty: Bool { heartRate.isEmpty && movement.isEmpty && respiratory.isEmpty }
    }

    static func inspect(
        awakening: DateInterval,
        stages: [StageSegment],
        sounds: [SoundEvent] = [],
        heartRateRiseAt: Date? = nil,
        movementAt: Date? = nil
    ) -> Sequence {
        let start = awakening.start
        let minutes = max(0, awakening.duration / 60)
        let window = DateInterval(
            start: start.addingTimeInterval(-windowMinutes * 60),
            end: start.addingTimeInterval(windowMinutes * 60)
        )

        var markers: [Marker] = []
        if let heartRateRiseAt, window.contains(heartRateRiseAt) {
            markers.append(Marker(date: heartRateRiseAt, kind: .hrRise, caption: "Heart rate began increasing"))
        }
        markers.append(Marker(
            date: start,
            kind: .awake,
            caption: minutes >= 1
                ? "Awake for \(SleepNightFeatures.formatMinutes(minutes))"
                : "Brief awakening"
        ))
        if let movementAt, window.contains(movementAt) {
            markers.append(Marker(date: movementAt, kind: .movement, caption: "Movement detected"))
        }

        let nearbySounds = sounds.filter {
            $0.confidence >= minimumSoundConfidence && window.contains($0.date)
        }
        for sound in nearbySounds {
            let ended: Bool
            if sound.date < start {
                ended = true
            } else {
                ended = false
            }
            let kind: Marker.Kind = sound.identifier == "snoring" || sound.identifier == "snore"
                ? .snore : .soundEnded
            let caption = ended
                ? "\(sound.label) event ended"
                : "\(sound.label) event"
            markers.append(Marker(date: sound.date, kind: kind, caption: caption))
        }

        if let resume = stages.first(where: {
            $0.start >= awakening.end && SleepStage.asleepStages.contains($0.stage)
        }), window.contains(resume.start) || resume.start.timeIntervalSince(start) <= windowMinutes * 60 {
            markers.append(Marker(
                date: resume.start,
                kind: .stageResume,
                caption: "\(resume.stage.displayName) sleep resumed"
            ))
        }

        markers.sort { $0.date < $1.date }

        var missing: [String] = []
        if heartRateRiseAt == nil { missing.append("heart rate") }
        if movementAt == nil { missing.append("movement") }
        if sounds.isEmpty { missing.append("sound") }

        return Sequence(
            awakeningStart: start,
            awakeningMinutes: minutes,
            markers: markers,
            caveat: "These events occurred around the same time. Zoon does not claim that one caused the awakening.",
            missingStreams: missing
        )
    }

    /// Awake runs long enough to inspect, from a night's stage list.
    static func awakenings(in stages: [StageSegment], minimumMinutes: Double = 2) -> [DateInterval] {
        stages
            .filter { $0.stage == .awake && $0.minutes >= minimumMinutes }
            .map { DateInterval(start: $0.start, end: $0.end) }
    }
}

// MARK: - Deriving the layers from real series

extension AwakeningInspector {

    /// The §25 entry point: the same sequence, with the heart-rate rise, the
    /// movement marker and the respiratory note derived from overnight series
    /// rather than handed in.
    ///
    /// Delegates to `inspect` for everything that has not changed, so the
    /// timeline, the sound handling and the caveat stay in one place and
    /// cannot drift between the two entry points.
    static func inspect(
        awakening: DateInterval,
        stages: [StageSegment],
        sounds: [SoundEvent] = [],
        series: Series
    ) -> Sequence {
        let window = DateInterval(
            start: awakening.start.addingTimeInterval(-windowMinutes * 60),
            end: awakening.start.addingTimeInterval(windowMinutes * 60)
        )

        let rise = heartRateRise(in: series.heartRate, before: awakening.start)
        let movement = movementOnset(in: series.movement, window: window)

        let sequence = inspect(
            awakening: awakening,
            stages: stages,
            sounds: sounds,
            heartRateRiseAt: rise?.date,
            movementAt: movement
        )

        let trace = series.heartRate
            .filter { window.contains($0.date) }
            .sorted { $0.date < $1.date }
        let movementProvenance = movement == nil
            ? nil
            : "Movement is inferred from active energy, not from a separate motion reading."

        // `inspect` reports a stream missing when it was handed nothing. Here
        // the distinction is finer: a series that arrived but held no rise is
        // not a missing stream, it is a stream that said nothing happened, and
        // conflating the two would have the screen apologise for data it has.
        var missing = sequence.missingStreams
        if !series.heartRate.isEmpty { missing.removeAll { $0 == "heart rate" } }
        if !series.movement.isEmpty { missing.removeAll { $0 == "movement" } }

        return Sequence(
            awakeningStart: sequence.awakeningStart,
            awakeningMinutes: sequence.awakeningMinutes,
            markers: sequence.markers.map { marker in
                // The derived rise can say how much it rose by, which the
                // handed-in one never could.
                guard marker.kind == .hrRise, let rise else { return marker }
                return Marker(
                    date: marker.date,
                    kind: .hrRise,
                    caption: "Heart rate rose \(Int(rise.deltaBpm.rounded())) bpm above the preceding minutes"
                )
            },
            caveat: sequence.caveat,
            missingStreams: missing,
            heartRateWindow: trace,
            respiratoryNote: respiratoryNote(series.respiratory, window: window),
            movementProvenance: movementProvenance
        )
    }

    struct Rise: Hashable, Sendable {
        let date: Date
        let deltaBpm: Double
    }

    /// The first bin in the run-up to the awakening whose heart rate sits
    /// `riseThresholdBpm` above the median of the quiet bins before it.
    ///
    /// The baseline is the bins inside the window *preceding* the candidate,
    /// not the whole night: a heart rate that is high all night has no rise in
    /// it, and one that climbs three beats from an unusually low trough is not
    /// a rise either. Both are the same question — did something change here —
    /// and only a local comparison answers it.
    static func heartRateRise(in samples: [Sample], before awakeningStart: Date) -> Rise? {
        let lead = samples
            .filter {
                $0.date >= awakeningStart.addingTimeInterval(-windowMinutes * 60)
                    && $0.date <= awakeningStart
            }
            .sorted { $0.date < $1.date }

        // Walked by bin but gated on readings: at one-minute bins most of the
        // lead is empty, and a candidate is only testable once three real
        // readings sit behind it.
        for index in lead.indices {
            guard let value = lead[index].value else { continue }
            let baselineValues = lead[..<index].compactMap(\.value)
            guard baselineValues.count >= minimumBaselineBins,
                  let baseline = Statistics.median(baselineValues)
            else { continue }
            let delta = value - baseline
            if delta >= riseThresholdBpm {
                return Rise(date: lead[index].date, deltaBpm: delta)
            }
        }
        return nil
    }

    /// The first bin in the window whose active energy clears
    /// `movementKcalPerBin`.
    ///
    /// Active energy is a proxy and is labelled as one wherever it is shown.
    /// Zoon has no overnight accelerometer stream of its own, and inventing a
    /// motion reading out of a calorie figure without saying so is exactly the
    /// borrowed precision this screen already refuses elsewhere.
    static func movementOnset(in samples: [Sample], window: DateInterval) -> Date? {
        samples
            .filter { window.contains($0.date) }
            .sorted { $0.date < $1.date }
            .first { ($0.value ?? 0) >= movementKcalPerBin }?
            .date
    }

    /// Respiratory rate inside the window against the rest of the night.
    ///
    /// Reported as a difference in this person's own night, never against a
    /// reference range: a respiratory rate outside a population band is a
    /// clinical observation, and this screen does not make those.
    static func respiratoryNote(_ samples: [Sample], window: DateInterval) -> String? {
        let inside = samples.filter { window.contains($0.date) }.compactMap(\.value)
        let outside = samples.filter { !window.contains($0.date) }.compactMap(\.value)
        guard inside.count >= 2, outside.count >= minimumBaselineBins,
              let here = Statistics.median(inside),
              let rest = Statistics.median(outside)
        else { return nil }

        let delta = here - rest
        guard abs(delta) >= respiratoryDeltaThreshold else { return nil }

        let direction = delta > 0 ? "higher" : "lower"
        let magnitude = String(format: "%.1f", abs(delta))
        return "Breathing rate around this awakening was \(magnitude) breaths a minute "
            + "\(direction) than the rest of the night."
    }
}
