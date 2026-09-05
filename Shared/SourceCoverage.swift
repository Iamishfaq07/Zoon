import Foundation

/// What a sleep source actually provides, measured rather than assumed.
///
/// ## The question this answers
///
/// `SensorTruth` says what kind of claim each number is -- measured,
/// calculated, estimated. It says nothing about whether *your* watch supplies
/// it. Those are different questions, and the second one decides how much of
/// Zoon works for a given person.
///
/// A watch that writes sleep and heart rate but no HRV is not broken and not
/// unsupported; it simply produces a Recovery score assembled from fewer
/// inputs. `RecoveryScore` already handles that correctly -- it renormalises
/// over the components that arrived and reports
/// `dataCompletenessPercent`. What was missing was anyone *saying* so. A
/// score quietly built from half its usual inputs looks exactly like one
/// built from all of them.
///
/// ## Why this is counted, not tabulated
///
/// The obvious implementation is a per-brand capability table. It would be
/// wrong within a release: capability varies by watch model, by firmware, by
/// which permissions the user granted in the vendor's own app, and by whether
/// they wore the thing. A table also fails silently -- it would describe a
/// metric the app never receives, which is precisely the sort of confident
/// unverified claim the rest of this codebase refuses to make.
///
/// Counting what arrived is true by construction, survives a firmware update
/// that adds a sensor, and needs no maintenance.
enum SourceCoverage {

    /// Nights needed before this will say anything at all.
    ///
    /// Below it, "absent" and "not yet synced" are indistinguishable, and
    /// telling someone their watch does not measure HRV because they
    /// installed the app yesterday would be worse than saying nothing.
    static let minimumNights = 7

    /// How much history to judge on. Long enough to survive a few nights of
    /// not wearing the watch, short enough to notice when something changes.
    static let window = 30

    /// Present on most nights, some nights, or none.
    enum Availability: String, Sendable, CaseIterable {
        /// Never once arrived in the window. The interesting case.
        case never
        /// Arrived on some nights. Usually means the watch was not worn, or
        /// the metric needs conditions (a long enough still period) that not
        /// every night meets.
        case sometimes
        /// Arrived on most nights. Working as intended.
        case usually

        var label: String {
            switch self {
            case .never: "Not provided"
            case .sometimes: "Some nights"
            case .usually: "Most nights"
            }
        }
    }

    /// Who wrote a quantity, as opposed to whether it arrived at all.
    ///
    /// The distinction this whole type exists for. A Garmin that records the
    /// sleep session and an Apple Watch worn the same night both write into
    /// the window Zoon averages over, and the average is right either way --
    /// but "your Garmin provides HRV" is then a claim about the wrong device.
    enum Attribution: Hashable, Sendable {
        /// Not enough nights carry provenance to say. Every night recorded
        /// before per-metric provenance existed lands here, and the honest
        /// response is to say nothing rather than to assume the sleep source
        /// wrote everything -- which is precisely the assumption that was
        /// wrong.
        case unknown
        /// This source wrote it on most attributed nights.
        case thisSource
        /// Another device wrote it on every attributed night.
        case anotherSource([String])
        /// Both contributed. Real on a wrist wearing two devices, or across a
        /// window in which one was replaced.
        case shared([String])
    }

    /// Attributed nights needed before naming a writer.
    ///
    /// Same figure as `minimumNights` and for the same reason: below it, one
    /// night of a second device left charging on the nightstand would be
    /// enough to reassign a metric to it.
    static let minimumAttributedNights = minimumNights

    struct Entry: Identifiable, Hashable, Sendable {
        let quantity: SensorTruth.Quantity
        let nightsWithValue: Int
        let nightsConsidered: Int
        /// Nights where a value arrived *and* HealthKit told us who wrote it.
        /// Zero for history recorded before provenance was captured.
        let nightsAttributed: Int
        /// Of `nightsAttributed`, the nights this source wrote it.
        let nightsFromThisSource: Int
        /// Every other writer seen, by display name, sorted and deduplicated.
        let otherSourceNames: [String]

        init(
            quantity: SensorTruth.Quantity,
            nightsWithValue: Int,
            nightsConsidered: Int,
            nightsAttributed: Int = 0,
            nightsFromThisSource: Int = 0,
            otherSourceNames: [String] = []
        ) {
            self.quantity = quantity
            self.nightsWithValue = nightsWithValue
            self.nightsConsidered = nightsConsidered
            self.nightsAttributed = nightsAttributed
            self.nightsFromThisSource = nightsFromThisSource
            self.otherSourceNames = otherSourceNames
        }

        var id: String { quantity.rawValue }

        var attribution: Attribution {
            guard nightsAttributed >= SourceCoverage.minimumAttributedNights else { return .unknown }
            if nightsFromThisSource == 0 { return .anotherSource(otherSourceNames) }
            // Any other writer at all makes this shared. Not a threshold:
            // "your Garmin provides HRV" is already misleading on the nights
            // an Apple Watch supplied it, however few, and the exact counts
            // are on this struct for copy that wants to be more specific.
            return otherSourceNames.isEmpty ? .thisSource : .shared(otherSourceNames)
        }

        /// One sentence naming the other writer, or nothing when there is
        /// nothing honest to say.
        ///
        /// `nil` for `.unknown` on purpose. Silence is the correct output
        /// when provenance was never recorded -- the alternative is a line
        /// explaining that Zoon does not know, on a screen whose whole job is
        /// to be believed.
        var attributionNote: String? {
            switch attribution {
            case .unknown, .thisSource:
                return nil
            case .anotherSource(let names):
                guard !names.isEmpty else { return nil }
                return "Arriving from \(SourceCoverage.list(names)), not from this watch."
            case .shared(let names):
                guard !names.isEmpty else { return nil }
                return "Some nights from \(SourceCoverage.list(names))."
            }
        }

        /// Arrives reliably, but this source is not what produces it.
        var isSuppliedElsewhere: Bool {
            if case .anotherSource = attribution { return true }
            return false
        }

        var fraction: Double {
            nightsConsidered > 0 ? Double(nightsWithValue) / Double(nightsConsidered) : 0
        }

        var availability: Availability {
            if nightsWithValue == 0 { return .never }
            // Two thirds rather than a half: a metric arriving on 55% of
            // nights is a wear-time story, not a capability, and calling that
            // "most nights" would make a patchy signal sound dependable.
            return fraction >= (2.0 / 3.0) ? .usually : .sometimes
        }
    }

    struct Report: Sendable {
        let source: WearableSource
        let nightsConsidered: Int
        /// Every observable quantity, stages first: it is both the one most
        /// often absent and the one whose absence changes the app most, since
        /// a night with no stages has no hypnogram to show.
        let entries: [Entry]

        /// The ones that never arrived -- what someone actually wants to know.
        var missing: [Entry] { entries.filter { $0.availability == .never } }

        /// Missing because this source could never have supplied it.
        ///
        /// Kept apart from `missingFromSource` because the two need opposite
        /// copy. Sleeping wrist temperature is written by Apple's own
        /// pipeline and has no third-party equivalent in HealthKit, so
        /// telling a Garmin owner their watch "is not providing" it implies a
        /// setting they could go and switch on. There isn't one.
        var missingBecauseAppleOnly: [Entry] {
            guard !source.isApple else { return [] }
            return missing.filter { appleExclusive.contains($0.quantity) }
        }

        /// Missing in a way that might be worth acting on -- a permission in
        /// the vendor's own app, a feature switched off, a watch not worn.
        var missingFromSource: [Entry] {
            missing.filter { !(!source.isApple && appleExclusive.contains($0.quantity)) }
        }

        var provided: [Entry] { entries.filter { $0.availability != .never } }

        /// Arrives every night, from some other device. The case that used to
        /// be reported as "this source provides it" -- a Garmin credited with
        /// HRV an Apple Watch on the same wrist had written.
        var suppliedElsewhere: [Entry] { entries.filter(\.isSuppliedElsewhere) }

        var providesEverything: Bool { missing.isEmpty }
    }

    /// "A", "A and B", "A, B and C" -- names read as prose, not as a
    /// comma-joined array.
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }

    /// Quantities no third-party source can write, whatever the hardware
    /// measures.
    ///
    /// `appleSleepingWristTemperature` is the whole list today. It is an
    /// Apple-authored HealthKit type with no vendor-writable equivalent, so
    /// its absence from a Garmin or an Oura is a property of HealthKit rather
    /// than of the watch.
    static let appleExclusive: Set<SensorTruth.Quantity> = [.wristTemperature]

    /// Quantities that can be checked against a stored night.
    ///
    /// Deliberately not every `SensorTruth.Quantity`: sleep need and sleep
    /// debt are Zoon's own arithmetic and arrive from no watch at all, so
    /// listing them here would invite the reader to blame their device for
    /// something the app computes.
    private static let observable: [SensorTruth.Quantity] = [
        .sleepStages, .heartRate, .restingHeartRate, .hrv,
        .respiratoryRate, .bloodOxygen, .wristTemperature
    ]

    private static func hasValue(
        _ quantity: SensorTruth.Quantity,
        in night: SleepNightFeatures
    ) -> Bool {
        switch quantity {
        // Staged, not merely asleep. A source that writes one undifferentiated
        // "asleep" block still fills `unspecifiedAsleepMinutes`, and counting
        // that as stage coverage would claim a hypnogram the person does not
        // have.
        case .sleepStages:
            night.coreMinutes + night.deepMinutes + night.remMinutes > 0
        case .heartRate: night.avgHeartRate != nil
        case .restingHeartRate: night.restingHeartRate != nil
        case .hrv: night.avgHRV != nil
        case .respiratoryRate: night.avgRespiratoryRate != nil
        case .bloodOxygen: night.avgSpO2 != nil
        // The raw reading, not the delta. `wristTempDeltaC` is this app's own
        // subtraction against a baseline that needs roughly a week of
        // history, so judging the sensor by it reported every new install's
        // working temperature sensor as "Not provided" for its first week --
        // a claim about Zoon's arithmetic dressed up as one about the watch.
        case .wristTemperature: night.wristTempMeasured
        default: false
        }
    }

    /// Measures what a source has actually written.
    ///
    /// Whether a stored night came from the source being measured.
    ///
    /// Bundle identifier first, display name only as a fallback. The name
    /// changes when someone renames their watch or switches the device
    /// language, and matching on it alone splits one watch's history into two
    /// sources at exactly the moment the app most wants continuity. A night
    /// with no recorded bundle identifier -- every row written before the
    /// extractor started passing one through -- still matches by name, so
    /// existing history is not stranded.
    private static func belongs(
        _ candidate: SleepNightFeatures,
        toSourceIdentified bundleIdentifier: String?,
        named sourceName: String?
    ) -> Bool {
        if let bundleIdentifier, !bundleIdentifier.isEmpty,
           let nightIdentifier = candidate.sourceBundleIdentifier, !nightIdentifier.isEmpty {
            return nightIdentifier == bundleIdentifier
        }
        guard let sourceName, !sourceName.isEmpty else { return false }
        return candidate.sourceName == sourceName
    }

    /// - Parameters:
    ///   - nights: history in any order. Only nights from this source are
    ///     counted -- a night from a different watch says nothing about this
    ///     one.
    ///   - sourceName: the source to measure, as HealthKit named it.
    ///   - bundleIdentifier: the source's stable identity. Used both to match
    ///     nights and to name the source; matching prefers it over the
    ///     display name -- see `belongs(_:toSourceIdentified:named:)`.
    /// - Returns: `nil` when fewer than `minimumNights` nights came from this
    ///   source, because "absent" and "too early to tell" are not the same
    ///   claim.
    static func report(
        nights: [SleepNightFeatures],
        sourceName: String?,
        bundleIdentifier: String? = nil,
        minimumNights: Int = minimumNights,
        window: Int = window
    ) -> Report? {
        let matching = nights
            .filter { belongs($0, toSourceIdentified: bundleIdentifier, named: sourceName) }
            .sorted { $0.date < $1.date }
            .suffix(window)

        guard matching.count >= minimumNights else { return nil }

        let entries = observable.map { quantity -> Entry in
            let withValue = matching.filter { hasValue(quantity, in: $0) }
            // Attribution is counted only over nights that both carry a value
            // and record who wrote it. A night with a value and no provenance
            // is not evidence either way, so it stays out of both the
            // numerator and the denominator rather than defaulting to the
            // sleep source -- that default is the bug.
            var attributed = 0
            var fromThisSource = 0
            var others: Set<String> = []
            for night in withValue {
                guard let wroteIt = night.measurementSources.wasWritten(
                    by: bundleIdentifier,
                    orNamed: sourceName,
                    for: quantity
                ) else { continue }
                attributed += 1
                if wroteIt {
                    fromThisSource += 1
                } else {
                    let names = night.measurementSources.sources(for: quantity)?.map(\.name) ?? []
                    others.formUnion(names)
                }
            }
            return Entry(
                quantity: quantity,
                nightsWithValue: withValue.count,
                nightsConsidered: matching.count,
                nightsAttributed: attributed,
                nightsFromThisSource: fromThisSource,
                otherSourceNames: others.sorted()
            )
        }

        return Report(
            source: .identify(bundleIdentifier: bundleIdentifier, name: sourceName),
            nightsConsidered: matching.count,
            entries: entries
        )
    }
}
