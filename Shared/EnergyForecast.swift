import Foundation

/// A heuristic estimate of today's energy curve — RISE's daily circadian
/// schedule, Garmin Body Battery's forward-looking cousin.
///
/// This is explicitly **not** a measurement. Nothing on a wrist measures
/// circadian phase; that needs melatonin assays or core body temperature.
/// What this is: a simplified two-process model (Borbély's homeostatic
/// Process S building since wake, layered with the well-documented
/// mid-afternoon circadian dip as Process C) anchored to when you actually
/// woke up today, nudged by how much sleep debt you're carrying. Every
/// window is labelled "estimated" wherever it's shown, on purpose.
struct EnergyForecast: Codable, Hashable, Sendable {

    struct Window: Codable, Hashable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable {
            case morningRise, morningPeak, afternoonDip, eveningRise, windDown

            var label: String {
                switch self {
                case .morningRise: "Morning rise"
                case .morningPeak: "Peak focus"
                case .afternoonDip: "Afternoon dip"
                case .eveningRise: "Second wind"
                case .windDown: "Wind down"
                }
            }

            var symbol: String {
                switch self {
                case .morningRise: "sunrise.fill"
                case .morningPeak: "sun.max.fill"
                case .afternoonDip: "cloud.sun.fill"
                case .eveningRise: "sun.horizon.fill"
                case .windDown: "moon.fill"
                }
            }
        }

        let kind: Kind
        let time: Date
        var id: Date { time }
    }

    let windows: [Window]

    /// True whenever no personal `BodyClock` was available and the wind-down
    /// anchor fell back to a generic offset from wake -- still an estimate,
    /// but a less personalized one than usual.
    let isGenericWindDown: Bool

    static func compute(
        wakeTime: Date,
        sleepDebtMinutes: Double,
        windDownHour: Double?,
        calendar: Calendar = .current
    ) -> EnergyForecast {
        let debtHours = max(0, sleepDebtMinutes) / 60

        // Heavier debt blunts the morning peak's arrival only slightly and
        // pulls the afternoon dip earlier and deeper -- both well-supported
        // directions in sleep-restriction literature, kept here as a gentle,
        // bounded nudge rather than a large swing from one input.
        let morningRise = wakeTime.addingTimeInterval(30 * 60)
        let morningPeak = wakeTime.addingTimeInterval((3 + min(debtHours * 0.15, 1)) * 3600)
        let afternoonDip = wakeTime.addingTimeInterval((7 - min(debtHours * 0.3, 1.5)) * 3600)
        let eveningRise = wakeTime.addingTimeInterval(11 * 3600)

        let windDown: Date
        let isGeneric: Bool
        if let windDownHour {
            windDown = Self.resolve(hour: windDownHour, near: wakeTime, calendar: calendar)
            isGeneric = false
        } else {
            // No personal body clock yet: fall back to a generic ~15.5 hour
            // wake-to-winddown span, roughly the midpoint of typical adult
            // sleep-onset timing after a typical wake time.
            windDown = wakeTime.addingTimeInterval(15.5 * 3600)
            isGeneric = true
        }

        return EnergyForecast(
            windows: [
                Window(kind: .morningRise, time: morningRise),
                Window(kind: .morningPeak, time: morningPeak),
                Window(kind: .afternoonDip, time: afternoonDip),
                Window(kind: .eveningRise, time: eveningRise),
                Window(kind: .windDown, time: windDown)
            ],
            isGenericWindDown: isGeneric
        )
    }

    /// Resolves an hours-from-midnight value (evening negative, per
    /// `BodyClock`'s convention -- 23:30 is −0.5) onto the evening of the day
    /// `wakeTime` falls on, i.e. *tonight's* wind-down, not last night's.
    private static func resolve(hour: Double, near wakeTime: Date, calendar: Calendar) -> Date {
        let nextMidnight = calendar.startOfDay(for: wakeTime).addingTimeInterval(24 * 3600)
        return nextMidnight.addingTimeInterval(hour * 3600)
    }
}
