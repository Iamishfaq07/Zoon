import Foundation

/// The sleep-timing block of a clinician report, computed on the circle.
///
/// Extracted out of the PDF generator so it can be tested: the generator
/// imports UIKit and draws into a graphics context, which puts it out of
/// reach of the test target, and timing statistics are exactly the part of
/// that document that most needs to be right.
///
/// **Why it is not ordinary median and SD.** Bedtime and wake time are
/// angles, not numbers. 23:50, 00:00 and 00:10 is a person going to bed at
/// almost exactly the same moment three nights running; read as the plain
/// numbers 1430, 0 and 10 it is a mean of 07:56 and a standard deviation of
/// thirteen and a half hours. The previous version dodged this by shifting
/// everything at or after 18:00 back by a day, which works for an ordinary
/// night sleeper and moves the discontinuity rather than removing it: two
/// bedtimes ten minutes apart either side of 18:00 still came out twenty-four
/// hours apart, and a shift worker or a night-shift week lands there.
///
/// A circular median and a circular MAD have no such seam anywhere on the
/// clock, which is what a document a clinician may read for a shift worker
/// requires.
struct SleepTimingSummary: Hashable, Sendable {

    /// How many nights carried usable timing. Reported, because a median of
    /// four nights and a median of ninety are not the same claim.
    let nightCount: Int
    /// Circular median bedtime, minutes since local midnight.
    let bedtimeMinutes: Double?
    let wakeMinutes: Double?
    /// The midpoint of each night's sleep period, circularly averaged. The
    /// standard chronotype marker, and more stable than either endpoint.
    let midSleepMinutes: Double?
    /// Circular MAD about the reported median, in minutes.
    let bedtimeVariabilityMinutes: Double?
    let wakeVariabilityMinutes: Double?
    /// Distinct timezones the nights were recorded in. More than one means
    /// the wall-clock times in this block span a travel period, which the
    /// document has to say rather than leave a clinician to infer.
    let timeZoneIdentifiers: [String]

    static func make(nights: [SleepNightFeatures]) -> SleepTimingSummary {
        // Each night in its own timezone. A report drawn after travelling
        // must not recompute historical bedtimes in the zone the phone
        // happens to be in now.
        func minutes(_ value: (SleepNightFeatures) -> Date) -> [Double] {
            nights.map { night in
                var calendar = Calendar.current
                calendar.timeZone = night.timeZone
                return Statistics.clockMinutes(value(night), calendar: calendar)
            }
        }

        let bedtimes = minutes(\.bedtime)
        let wakes = minutes(\.wakeTime)
        let midSleeps = nights.map { night -> Double in
            var calendar = Calendar.current
            calendar.timeZone = night.timeZone
            // From the real instants, not from the two clock readings: the
            // midpoint of a 23:40–07:10 night is 03:25, and reconstructing
            // that from 1420 and 430 without the date requires the circle
            // again. The dates already have it.
            let middle = night.bedtime.addingTimeInterval(
                night.wakeTime.timeIntervalSince(night.bedtime) / 2
            )
            return Statistics.clockMinutes(middle, calendar: calendar)
        }

        let bedtimeCentre = Statistics.circularMedian(bedtimes)
        let wakeCentre = Statistics.circularMedian(wakes)

        return SleepTimingSummary(
            nightCount: nights.count,
            bedtimeMinutes: bedtimeCentre,
            wakeMinutes: wakeCentre,
            midSleepMinutes: Statistics.circularMedian(midSleeps),
            bedtimeVariabilityMinutes: bedtimeCentre.flatMap {
                Statistics.circularMedianAbsoluteDeviation(bedtimes, around: $0)
            },
            wakeVariabilityMinutes: wakeCentre.flatMap {
                Statistics.circularMedianAbsoluteDeviation(wakes, around: $0)
            },
            timeZoneIdentifiers: Array(Set(nights.map(\.timeZone.identifier))).sorted()
        )
    }

    /// `HH:MM` for minutes since midnight, wrapping rather than clamping.
    static func clockLabel(_ minutes: Double) -> String {
        var wrapped = minutes.truncatingRemainder(dividingBy: 1440)
        if wrapped < 0 { wrapped += 1440 }
        let total = Int(wrapped.rounded())
        return String(format: "%02d:%02d", total / 60 % 24, total % 60)
    }

    /// The rows as the report prints them, in order.
    ///
    /// Missing values print an explicit "Not available" rather than `00:00`:
    /// on a document a clinician may act on, a plausible-looking zero is the
    /// worst possible rendering of "we do not know".
    var rows: [(label: String, value: String)] {
        var rows: [(String, String)] = [
            ("Nights with timing data", "\(nightCount)")
        ]
        func row(_ label: String, _ minutes: Double?, clock: Bool) {
            guard let minutes else {
                rows.append((label, "Not available"))
                return
            }
            rows.append((
                label,
                clock
                    ? Self.clockLabel(minutes)
                    : SleepNightFeatures.formatMinutes(minutes)
            ))
        }
        row("Median bedtime", bedtimeMinutes, clock: true)
        row("Median wake time", wakeMinutes, clock: true)
        row("Median mid-sleep", midSleepMinutes, clock: true)
        row("Bedtime variability (circular MAD)", bedtimeVariabilityMinutes, clock: false)
        row("Wake variability (circular MAD)", wakeVariabilityMinutes, clock: false)
        if timeZoneIdentifiers.count > 1 {
            rows.append((
                "Timezones in this range",
                "\(timeZoneIdentifiers.count) — times shown are each night's local clock"
            ))
        }
        return rows
    }
}
