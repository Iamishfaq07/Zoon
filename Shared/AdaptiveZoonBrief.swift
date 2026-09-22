import Foundation

/// One concise, phase-aware sentence. Not a score.
///
/// Today already has a morning brief built from `SleepInsight`. This is the
/// quieter line for day and evening: what is actually constrained *now*,
/// with optional why / confidence / data-used behind a tap. Missing inputs
/// lower the claim rather than becoming "typical".
enum AdaptiveZoonBrief {

    struct Result: Equatable, Sendable {
        let headline: String
        let why: String?
        let confidence: String
        let dataUsed: [String]
        let phase: ZoonAmbientBackground.Band
    }

    static func make(
        phase: ZoonAmbientBackground.Band,
        night: SleepNightFeatures,
        recoveryPercent: Int?,
        energy: Int?,
        load: Double?,
        tonightBedtime: Date?,
        now: Date = .now
    ) -> Result {
        switch phase {
        case .morning, .night:
            return morning(night: night, recoveryPercent: recoveryPercent)
        case .day:
            return day(night: night, energy: energy, load: load)
        case .evening:
            return evening(night: night, tonightBedtime: tonightBedtime, now: now)
        }
    }

    private static func morning(night: SleepNightFeatures, recoveryPercent: Int?) -> Result {
        let asleep = SleepNightFeatures.formatMinutes(night.timeAsleepMinutes)
        var data = ["sleep duration"]
        if let recoveryPercent {
            data.append("Morning Recovery")
            let physiology: String
            if recoveryPercent >= 70 {
                physiology = "overnight physiology stayed close to your baseline"
            } else if recoveryPercent >= 50 {
                physiology = "overnight physiology was mixed against your baseline"
            } else {
                physiology = "overnight physiology was quieter than your baseline"
            }
            let short = night.timeAsleepMinutes < 390
            let headline = short
                ? "Short night (\(asleep)), but \(physiology)."
                : "You were asleep \(asleep), and \(physiology)."
            return Result(
                headline: headline,
                why: "Duration is last night's recorded sleep. Recovery describes that night, not how you feel this afternoon.",
                confidence: night.timingProvenance == .locallyCorrected
                    ? "Locally corrected night"
                    : "Last night recorded",
                dataUsed: data,
                phase: .morning
            )
        }
        return Result(
            headline: "You were asleep \(asleep). Recovery is not ready to add a physiology read yet.",
            why: "A duration without Morning Recovery is still a record of the night, not a live capacity claim.",
            confidence: "Duration only",
            dataUsed: data,
            phase: .morning
        )
    }

    private static func day(night: SleepNightFeatures, energy: Int?, load: Double?) -> Result {
        if let energy, let load, load >= 8, energy <= 45 {
            return Result(
                headline: "Energy is dropping while today's Load is already high.",
                why: "Energy is a live reserve. Load is cardiovascular work so far today. Neither is Morning Recovery.",
                confidence: "Energy and Load both present",
                dataUsed: ["Energy", "Load"],
                phase: .day
            )
        }
        if let hours = night.lastWorkoutHoursBeforeBed, hours < 3, let energy, energy <= 50 {
            return Result(
                headline: "Energy is lower than usual after yesterday's late session.",
                why: "The workout timing is hours before last night's bedtime, not proof the session caused today's Energy.",
                confidence: "Association only",
                dataUsed: ["Energy", "workout timing"],
                phase: .day
            )
        }
        if let energy {
            return Result(
                headline: energy >= 55
                    ? "Energy is holding through the day."
                    : "Energy is lower than the top of your usual range.",
                why: "Energy is estimated from today's samples. Missing daytime heart rate would make this quieter, not 'typical'.",
                confidence: "Energy present",
                dataUsed: ["Energy"],
                phase: .day
            )
        }
        return Result(
            headline: "Daytime Energy is not available yet, so this is not a capacity claim.",
            why: nil,
            confidence: "Missing Energy",
            dataUsed: [],
            phase: .day
        )
    }

    private static func evening(night: SleepNightFeatures, tonightBedtime: Date?, now: Date) -> Result {
        if let bed = tonightBedtime {
            let minutes = bed.timeIntervalSince(now) / 60
            if minutes > 0 && minutes < 180 {
                let window = bed.formatted(date: .omitted, time: .shortened)
                let debt = night.sleepDebtMinutes ?? 0
                let extra = debt >= 45
                    ? " There is still a shortfall to protect."
                    : ""
                return Result(
                    headline: "Protecting the \(window) window is today's highest-value action.\(extra)",
                    why: "Tonight's plan is computed independently of last night's clocks. A local correction on last night does not rewrite tonight.",
                    confidence: tonightConfidence(night),
                    dataUsed: ["Tonight plan"] + ((night.sleepDebtMinutes ?? 0) >= 45 ? ["shortfall"] : []),
                    phase: .evening
                )
            }
        }
        if let debt = night.sleepDebtMinutes, debt >= 45 {
            return Result(
                headline: "Recent shortfall is \(SleepNightFeatures.formatMinutes(debt)). An earlier wind-down is the usual first move.",
                why: "Shortfall is unpaid sleep against your own need, not a medical claim about fatigue.",
                confidence: "Shortfall recorded",
                dataUsed: ["shortfall"],
                phase: .evening
            )
        }
        return Result(
            headline: "Keep tonight close to your usual window.",
            why: "No outstanding shortfall large enough to open the evening with.",
            confidence: "Low urgency",
            dataUsed: ["sleep duration"],
            phase: .evening
        )
    }

    private static func tonightConfidence(_ night: SleepNightFeatures) -> String {
        night.timingProvenance == .locallyCorrected
            ? "Tonight from plan · last night locally corrected"
            : "Tonight from plan"
    }
}
