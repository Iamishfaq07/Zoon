import Foundation

/// The named moments of one day, in the order they happen.
///
/// The Body Clock dial is already scrubbable, and the centre already says
/// what an hour *is* -- asleep, in the usual window, awake. What it could
/// not do is name the moments themselves. "Awake" is true of fourteen hours
/// of the day and tells the reader nothing about which one their finger is
/// on.
///
/// This is the list the V9 spec asks for: wake, the morning light window,
/// the energy peak, the afternoon dip, wind-down. Kept out of the view
/// because it decides *when* each of those is, which is a claim about the
/// day rather than a drawing of it.
///
/// ## Nothing here is invented
///
/// Every moment comes from an engine that already exists and is already
/// shown elsewhere: wake and the usual window from `BodyClock`, the energy
/// marks from `EnergyForecast`, and the light window from `LightCoach`'s
/// own 90-minute definition rather than a second one that could disagree
/// with the advice the Light card gives.
enum BodyClockAgenda {

    struct Moment: Identifiable, Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case wake
            case lightWindow
            case energy
            case usualBedtime
        }

        /// Wall-clock hours from midnight, 0..<24.
        let hour: Double
        let kind: Kind
        let label: String
        let symbol: String
        /// What this moment is for, one sentence. Shown on selection, not
        /// in the list -- the list is times and names.
        let detail: String

        var id: String { "\(kind.rawValue)-\(label)-\(hour)" }
    }

    /// The morning light window's length, taken from `LightCoach` rather
    /// than restated. A second copy of this number would let the dial and
    /// the Light card disagree about when the window closes.
    static let lightWindowMinutes = LightCoach.morningWindowMinutes

    /// A finger within this much of a moment is on it. Half an hour is
    /// about one dial tick's worth of finger, and a moment estimated to the
    /// minute would be false precision anyway.
    static let selectionToleranceMinutes = 30.0

    /// - Parameters:
    ///   - bodyClock: the personal window, for wake and usual bedtime.
    ///   - energyMarks: whichever `EnergyForecast` windows the caller is
    ///     already drawing, so the list and the dial can never disagree
    ///     about which marks exist.
    static func moments(
        bodyClock: BodyClock,
        energyMarks: [EnergyForecast.Window],
        calendar: Calendar = .current
    ) -> [Moment] {
        let wake = wrapped(bodyClock.wakeHour)
        var moments: [Moment] = [
            Moment(
                hour: wake,
                kind: .wake,
                label: "Wake",
                symbol: "sunrise",
                detail: "The middle of your recent wake times, not an alarm."
            ),
            Moment(
                hour: wrapped(bodyClock.wakeHour + lightWindowMinutes / 60),
                kind: .lightWindow,
                label: "Best light window",
                symbol: "sun.max",
                detail: "Outdoor light in the \(Int(lightWindowMinutes)) minutes after waking does the most to anchor tonight's timing."
            )
        ]

        for mark in energyMarks {
            moments.append(Moment(
                hour: wrapped(hourOfDay(mark.time, calendar: calendar)),
                kind: .energy,
                label: mark.kind.label,
                symbol: mark.kind.symbol,
                detail: detail(for: mark.kind)
            ))
        }

        moments.append(Moment(
            hour: wrapped(bodyClock.onsetHour),
            kind: .usualBedtime,
            label: "Usual bedtime",
            symbol: "bed.double",
            detail: "The middle of your recent sleep onsets, estimated from timing rather than measured."
        ))

        // Ordered by the clock, so the list reads as a day. Sorting by hour
        // rather than by kind means an unusually late wake sits where it
        // actually falls instead of always first.
        return moments.sorted { $0.hour < $1.hour }
    }

    /// The moment a dial fraction is on, or `nil` when the finger is
    /// somewhere unremarkable.
    ///
    /// Returning `nil` rather than the nearest moment regardless of distance
    /// is the point: most of the day is not a named moment, and labelling
    /// 3pm as "afternoon dip" because it is the closest thing on the list
    /// would be a claim the forecast never made.
    static func moment(atFraction fraction: Double, in moments: [Moment]) -> Moment? {
        let hour = fraction * 24
        let tolerance = selectionToleranceMinutes / 60
        return moments
            .filter { circularHourDistance($0.hour, hour) <= tolerance }
            .min { circularHourDistance($0.hour, hour) < circularHourDistance($1.hour, hour) }
    }

    /// Where on the dial a moment sits, 0...1.
    static func fraction(of moment: Moment) -> Double {
        moment.hour / 24
    }

    // MARK: - Clock helpers

    /// Hours from midnight, wrapped into 0..<24. `BodyClock` uses a signed
    /// convention where an 11pm onset is -1, which is correct arithmetic and
    /// wrong as a clock reading.
    static func wrapped(_ hour: Double) -> Double {
        var h = hour.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }
        return h
    }

    static func hourOfDay(_ date: Date, calendar: Calendar = .current) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }

    /// Distance in hours around a 24-hour clock, so 23:30 and 00:30 are one
    /// hour apart rather than twenty-three.
    static func circularHourDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(wrapped(a) - wrapped(b))
        return min(diff, 24 - diff)
    }

    private static func detail(for kind: EnergyForecast.Window.Kind) -> String {
        switch kind {
        case .morningRise: "Alertness climbing after waking."
        case .morningPeak: "Estimated best stretch for demanding work."
        case .afternoonDip: "A normal trough, not a sign anything went wrong."
        case .eveningRise: "A late lift that can push bedtime later than intended."
        case .windDown: "Estimated start of the slide toward sleep."
        }
    }
}
