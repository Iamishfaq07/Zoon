import Foundation

/// A glanceable name for "where in the day the body is", for the Smart Stack.
///
/// `BodyClock` already estimates habitual onset and wake from sleep
/// midpoints, and is careful not to call that circadian *phase* — phase is
/// melatonin. This type is a *schedule label* derived from those habitual
/// anchors plus the wall clock, which is what a complication can actually
/// show: "Peak focus", "Afternoon dip", "Wind down", "Sleep window".
///
/// It keys off the same hour table as `EnergyForecast`'s windows so the
/// complication and the phone's energy horizon cannot disagree about which
/// part of the day it is.
enum CircadianPhase: String, Codable, Sendable {
    case morningRise
    case peakFocus
    case afternoonDip
    case secondWind
    case windDown
    case sleepWindow

    var label: String {
        switch self {
        case .morningRise: "Morning rise"
        case .peakFocus: "Peak focus"
        case .afternoonDip: "Afternoon dip"
        case .secondWind: "Second wind"
        case .windDown: "Wind down"
        case .sleepWindow: "Sleep window"
        }
    }

    var symbol: String {
        switch self {
        case .morningRise: "sunrise.fill"
        case .peakFocus: "sun.max.fill"
        case .afternoonDip: "cloud.sun.fill"
        case .secondWind: "sun.horizon.fill"
        case .windDown: "moon.fill"
        case .sleepWindow: "moon.zzz.fill"
        }
    }

    /// - Parameters:
    ///   - now: the instant being labelled.
    ///   - wakeTime: last wake, if known.
    ///   - onsetHour: habitual sleep onset as hours-from-midnight (evening
    ///     negative, same convention as `BodyClock`).
    static func at(
        now: Date,
        wakeTime: Date?,
        onsetHour: Double?,
        calendar: Calendar = .current
    ) -> CircadianPhase {
        let hoursAwake: Double
        if let wakeTime, now > wakeTime {
            hoursAwake = now.timeIntervalSince(wakeTime) / 3600
        } else {
            hoursAwake = Double(calendar.component(.hour, from: now))
        }

        if let onsetHour {
            let currentHour = Self.hoursFromMidnight(now, calendar: calendar)
            let distance = abs(Self.circularDistance(currentHour, onsetHour))
            if distance <= 1.0 || hoursAwake >= 16 {
                return .sleepWindow
            }
        }

        switch hoursAwake {
        case ..<2: return .morningRise
        case ..<6: return .peakFocus
        case ..<9.5: return .afternoonDip
        case ..<13: return .secondWind
        case ..<16: return .windDown
        default: return .sleepWindow
        }
    }

    /// Hours from midnight, evening negative (23:30 → −0.5).
    static func hoursFromMidnight(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        var hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        if hour >= 18 { hour -= 24 }
        return hour
    }

    static func circularDistance(_ a: Double, _ b: Double) -> Double {
        var delta = a - b
        while delta > 12 { delta -= 24 }
        while delta < -12 { delta += 24 }
        return delta
    }
}
