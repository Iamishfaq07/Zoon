import Foundation

/// Where each of last night's numbers actually came from.
///
/// `SensorTruth` grades a *kind* of number -- a wrist temperature is
/// measured, a REM minute-count is a model's guess -- and says the same
/// thing every night for everybody. `SourceCoverage` counts what a source
/// has written over a month. Neither answers the question someone asks while
/// looking at last night's card: *how did Zoon arrive at this one?*
///
/// That question has an answer, and until now it was only in the code. The
/// pieces were all stored -- who wrote each measurement
/// (`NightMeasurementSources`), whether time in bed was measured or
/// reconstructed (`timeInBedIsEstimated`), how many stage runs the session
/// was built from (`stageSegments`) -- and none of them were shown.
///
/// ## What this deliberately does not do
///
/// It never states a sample count it does not have. The physiology averages
/// come from `HKStatisticsQuery`, which returns a mean and the set of sources
/// that contributed but not how many samples each wrote. "5 samples" would
/// have to be invented, and a number invented on a screen whose entire
/// purpose is to be believed is worse than a blank. Where a real count exists
/// -- the stage segments a sleep session was assembled from, the asleep runs
/// an average was taken over -- it is stated and it is exact.
struct TonightsData: Sendable {

    struct Row: Identifiable, Hashable, Sendable {
        let quantity: SensorTruth.Quantity
        /// Already formatted for display. Empty when the night has no value.
        let value: String
        let provenance: SensorTruth.Provenance
        /// Who wrote it, by display name. Empty means unknown, which is not
        /// the same as nobody -- see `NightMeasurementSources`.
        let sourceNames: [String]
        /// The steps between the raw samples and the number, in order. Shown
        /// under "How Zoon got this".
        let derivation: [String]
        /// One sentence when there is something about *this* night worth
        /// saying, such as an estimated in-bed span.
        let note: String?
        /// How often this source provides the quantity at all, from
        /// `SourceCoverage`. Nil when there is too little history to say.
        let coverage: SourceCoverage.Availability?

        var id: String { quantity.rawValue }

        var hasValue: Bool { !value.isEmpty }
    }

    let rows: [Row]

    /// Rows worth showing: the ones with a value.
    var populated: [Row] { rows.filter(\.hasValue) }

    static func build(
        night: SleepNightFeatures,
        coverage: SourceCoverage.Report? = nil
    ) -> TonightsData {

        func availability(_ quantity: SensorTruth.Quantity) -> SourceCoverage.Availability? {
            coverage?.entries.first { $0.quantity == quantity }?.availability
        }

        func writers(_ quantity: SensorTruth.Quantity) -> [String] {
            night.measurementSources.sources(for: quantity)?.map(\.name)
                ?? night.sourceName.map { [$0] }
                ?? []
        }

        let asleepRuns = night.stageSegments.filter {
            SleepStage.asleepStages.contains($0.stage)
        }.count

        var rows: [Row] = []

        // --- Time asleep --------------------------------------------------
        var sleepDerivation = ["Apple Health sleep analysis"]
        if !night.stageSegments.isEmpty {
            sleepDerivation.append("\(night.stageSegments.count) stage segments")
        }
        sleepDerivation.append("Overlapping periods from the same source merged")
        sleepDerivation.append("\(SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)) asleep")
        rows.append(Row(
            quantity: .timeAsleep,
            value: SleepNightFeatures.formatMinutes(night.timeAsleepMinutes),
            provenance: SensorTruth.provenance(of: .timeAsleep),
            sourceNames: writers(.sleepStages),
            derivation: sleepDerivation,
            note: nil,
            coverage: availability(.sleepStages)
        ))

        // --- Time in bed --------------------------------------------------
        //
        // The example the V9 spec gives, and the one field on this screen
        // that was already stored and never surfaced. An Apple Watch alone
        // writes no in-bed samples, so for most people this number is a
        // reconstruction of the session's own boundaries -- which slightly
        // overstates sleep efficiency, as `timeInBedIsEstimated`'s doc
        // comment has said all along.
        rows.append(Row(
            quantity: .timeInBed,
            value: SleepNightFeatures.formatMinutes(night.timeInBedMinutes),
            provenance: night.timeInBedIsEstimated ? .inferred : .derived,
            sourceNames: writers(.sleepStages),
            derivation: night.timeInBedIsEstimated
                ? ["No explicit in-bed samples for this night",
                   "Estimated from the sleep session's own boundaries"]
                : ["In-bed samples written by the source",
                   "Overlapping periods merged"],
            note: night.timeInBedIsEstimated
                ? "Apple Health did not provide an explicit in-bed interval for this night, so Zoon estimated it from when sleep started and ended. That leaves out time spent lying awake before or after, so sleep efficiency reads slightly high."
                : nil,
            coverage: nil
        ))

        // --- Sleep stages -------------------------------------------------
        if night.hasStageBreakdown {
            rows.append(Row(
                quantity: .sleepStages,
                value: "\(Int(night.deepMinutes))m deep, \(Int(night.remMinutes))m REM",
                provenance: SensorTruth.provenance(of: .sleepStages),
                sourceNames: writers(.sleepStages),
                derivation: [
                    "\(night.stageSegments.count) stage segments from the source",
                    "Classified on the watch, not by Zoon"
                ],
                note: nil,
                coverage: availability(.sleepStages)
            ))
        }

        // --- Physiology ---------------------------------------------------
        //
        // Each of these is an average over the night's asleep intervals with
        // no source predicate -- which is why the writer is worth naming and
        // cannot be assumed to be whoever recorded the sleep.
        let physiology: [(SensorTruth.Quantity, Double?, (Double) -> String)] = [
            (.heartRate, night.avgHeartRate, { "\(Int($0)) bpm" }),
            (.restingHeartRate, night.restingHeartRate, { "\(Int($0)) bpm" }),
            (.hrv, night.avgHRV, { "\(Int($0)) ms" }),
            (.respiratoryRate, night.avgRespiratoryRate, { String(format: "%.1f br/min", $0) }),
            (.bloodOxygen, night.avgSpO2, { String(format: "%.0f%%", $0) })
        ]
        for (quantity, value, format) in physiology {
            guard let value else { continue }
            var derivation: [String] = []
            if quantity == .restingHeartRate {
                // Not an average over the night: HealthKit computes one
                // resting figure per day and this reads that day's.
                derivation.append("Apple Health's own daily resting heart rate")
            } else if asleepRuns > 0 {
                derivation.append("Averaged over \(asleepRuns) asleep \(asleepRuns == 1 ? "interval" : "intervals")")
            } else {
                derivation.append("Averaged over the night's asleep time")
            }
            rows.append(Row(
                quantity: quantity,
                value: format(value),
                provenance: SensorTruth.provenance(of: quantity),
                sourceNames: writers(quantity),
                derivation: derivation,
                note: nil,
                coverage: availability(quantity)
            ))
        }

        // --- Wrist temperature --------------------------------------------
        //
        // Reported as a delta, and the delta is Zoon's arithmetic rather than
        // a reading -- which is exactly the confusion `wristTempMeasured`
        // exists to keep out of source coverage, and worth saying here too.
        if let delta = night.wristTempDeltaC {
            rows.append(Row(
                quantity: .wristTemperature,
                value: String(format: "%+.1f°C", delta),
                provenance: .derived,
                sourceNames: writers(.wristTemperature),
                derivation: [
                    "Sleeping wrist temperature measured by the watch",
                    "Compared against your own baseline",
                    "Shown as the difference, not the reading"
                ],
                note: nil,
                coverage: availability(.wristTemperature)
            ))
        } else if night.wristTempMeasured {
            rows.append(Row(
                quantity: .wristTemperature,
                value: "",
                provenance: .measured,
                sourceNames: writers(.wristTemperature),
                derivation: [],
                note: "Measured last night, but Zoon needs about a week of readings before a difference from your own baseline means anything.",
                coverage: availability(.wristTemperature)
            ))
        }

        return TonightsData(rows: rows)
    }
}
