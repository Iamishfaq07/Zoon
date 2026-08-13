import Foundation

/// Your circadian window: when your body actually wants to sleep.
///
/// Oura calls this Body Clock, Garmin folds it into sleep coaching. The idea is
/// the same everywhere and it is genuinely useful: the best bedtime is not a
/// number from a magazine, it is the one your own rhythm has already settled
/// on, and the interesting information is *how far tonight's plan sits from
/// it*.
///
/// ## What this is and is not
///
/// This is an estimate of habitual timing from observed sleep midpoints. It is
/// **not** a measurement of circadian phase — that needs melatonin assays or
/// core body temperature, neither of which a watch provides. The naming here
/// stays deliberately behavioural ("your usual window") rather than
/// physiological ("your circadian phase"), because the second would be a claim
/// the data cannot support.
///
/// ## Why circular statistics
///
/// Clock times wrap. A naive mean of 23:40 and 00:20 is 11:00 — the middle of
/// the following day, and the exact opposite of the truth. Midpoints are
/// therefore averaged as unit vectors on a 24-hour circle and converted back,
/// which is the same treatment the bedtime consistency chart uses.
struct BodyClock: Codable, Hashable, Sendable {

    /// Habitual sleep midpoint, hours from midnight. Evening is negative:
    /// 03:30 is 3.5, 23:30 is −0.5.
    let midpoint: Double

    /// Spread of the midpoints, in hours. Small means a tight, predictable
    /// rhythm; large means the window below is a weak suggestion.
    let spreadHours: Double

    /// Nights this was computed from.
    let nightCount: Int

    /// Typical time asleep, minutes — sets the width of the window.
    let typicalDurationMinutes: Double

    /// Below this the window is guesswork. Two weeks is where a weekday /
    /// weekend pattern has been seen at least twice.
    static let minimumNights = 14

    var isEstimate: Bool { nightCount < Self.minimumNights }

    /// How tightly the rhythm holds.
    enum Stability: String, Codable, Sendable {
        case tight, typical, scattered

        var label: String {
            switch self {
            case .tight: "Tight"
            case .typical: "Typical"
            case .scattered: "Scattered"
            }
        }

        var detail: String {
            switch self {
            case .tight:
                "Your body clock is running to a schedule. Keep it."
            case .typical:
                "Normal night-to-night variation."
            case .scattered:
                "Your timing moves a lot. Anchoring wake time is the fastest way to settle it."
            }
        }
    }

    var stability: Stability {
        // Thresholds in hours of standard deviation around the midpoint.
        // Under 30 minutes is genuinely regular; beyond 90 the "window" is
        // wide enough that calling it a window oversells it.
        switch spreadHours {
        case ..<0.5: .tight
        case ..<1.5: .typical
        default: .scattered
        }
    }

    // MARK: - Window

    /// Ideal sleep-onset hour, as hours from midnight.
    var onsetHour: Double { midpoint - (typicalDurationMinutes / 60) / 2 }

    /// Ideal wake hour.
    var wakeHour: Double { midpoint + (typicalDurationMinutes / 60) / 2 }

    /// Resolves the window onto a concrete evening.
    ///
    /// Returns the onset and wake `Date`s for the night beginning on the
    /// evening of `date`.
    func window(for date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let midnight = calendar.date(
            bySettingHour: 0, minute: 0, second: 0, of: date
        ) else { return nil }

        let onset = midnight.addingTimeInterval(onsetHour * 3600)
        let wake = midnight.addingTimeInterval(wakeHour * 3600)
        guard wake > onset else { return nil }
        return DateInterval(start: onset, end: wake)
    }

    /// How far a proposed bedtime sits from the window's opening, in minutes.
    /// Positive means later than the body wants.
    func drift(of bedtime: Date, calendar: Calendar = .current) -> Double? {
        guard let window = window(for: bedtime, calendar: calendar) else { return nil }
        return bedtime.timeIntervalSince(window.start) / 60
    }

    // MARK: - Computation

    static func compute(nights: [SleepNightFeatures], calendar: Calendar = .current) -> BodyClock? {
        guard !nights.isEmpty else { return nil }

        // Midpoint of each night, mapped onto the 24-hour circle.
        var sumSin = 0.0
        var sumCos = 0.0
        var durations: [Double] = []
        var localCalendar = calendar

        for night in nights {
            let midpoint = night.bedtime.addingTimeInterval(
                night.wakeTime.timeIntervalSince(night.bedtime) / 2
            )
            // Each night's own timezone, not the caller's -- same reasoning
            // as SleepRegularity.midpoints: a historical bedtime's wall-clock
            // hour doesn't change because the user has since traveled.
            localCalendar.timeZone = night.timeZone
            let components = localCalendar.dateComponents([.hour, .minute], from: midpoint)
            let hours = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60

            let angle = hours / 24 * 2 * .pi
            sumSin += sin(angle)
            sumCos += cos(angle)
            durations.append(night.timeAsleepMinutes)
        }

        let n = Double(nights.count)
        let meanAngle = atan2(sumSin / n, sumCos / n)

        var hours = meanAngle / (2 * .pi) * 24
        if hours < 0 { hours += 24 }
        // Fold the small hours onto a signed scale so an evening midpoint
        // sorts before a morning one instead of wrapping to 23.
        if hours > 12 { hours -= 24 }

        // Circular standard deviation. R is the resultant length: 1 means every
        // night landed on the same clock time, 0 means they're spread evenly
        // around the day.
        let r = (sumSin * sumSin + sumCos * sumCos).squareRoot() / n
        let spread = r >= 1 ? 0 : (-2 * log(max(r, 1e-9))).squareRoot() / (2 * .pi) * 24

        let typical = durations.sorted()[durations.count / 2]

        return BodyClock(
            midpoint: hours,
            spreadHours: spread,
            nightCount: nights.count,
            typicalDurationMinutes: typical
        )
    }

    /// Formats an hours-from-midnight value as a clock time.
    static func formatted(hour: Double) -> String {
        var h = hour
        if h < 0 { h += 24 }
        let totalMinutes = Int((h * 60).rounded())
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        var components = DateComponents()
        components.hour = hours
        components.minute = minutes
        guard let date = Calendar.current.date(from: components) else { return "--:--" }
        return date.formatted(.dateTime.hour().minute())
    }
}
