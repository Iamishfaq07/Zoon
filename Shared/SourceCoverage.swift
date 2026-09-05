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

    struct Entry: Identifiable, Hashable, Sendable {
        let quantity: SensorTruth.Quantity
        let nightsWithValue: Int
        let nightsConsidered: Int

        var id: String { quantity.rawValue }

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

        var providesEverything: Bool { missing.isEmpty }
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
        case .wristTemperature: night.wristTempDeltaC != nil
        default: false
        }
    }

    /// Measures what a source has actually written.
    ///
    /// - Parameters:
    ///   - nights: history in any order. Only nights whose `sourceName`
    ///     matches are counted -- a night from a different watch says nothing
    ///     about this one.
    ///   - sourceName: the source to measure, as HealthKit named it.
    ///   - bundleIdentifier: used only to name the source.
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
            .filter { $0.sourceName == sourceName && sourceName != nil }
            .sorted { $0.date < $1.date }
            .suffix(window)

        guard matching.count >= minimumNights else { return nil }

        let entries = observable.map { quantity in
            Entry(
                quantity: quantity,
                nightsWithValue: matching.filter { hasValue(quantity, in: $0) }.count,
                nightsConsidered: matching.count
            )
        }

        return Report(
            source: .identify(bundleIdentifier: bundleIdentifier, name: sourceName),
            nightsConsidered: matching.count,
            entries: entries
        )
    }
}
