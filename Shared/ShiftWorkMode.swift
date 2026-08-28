import Foundation

/// How a person's sleep is scheduled, which decides whether "daytime" is a
/// useful signal about an episode at all.
///
/// This replaces a plain `isShiftWorkModeEnabled` Bool. The Bool could only
/// express "nights are inverted", and inverting a fixed 9am–6pm window is
/// still a fixed window — it just moves the assumption rather than removing
/// it. A rotating shift worker has no stable clock-time window in either
/// direction, and a biphasic sleeper has two legitimate blocks; both were
/// being told, in effect, that sleeping in daylight is suspicious.
///
/// The Bool survives as a derived value (`UserPreferences
/// .isShiftWorkModeEnabled`) because `SleepSnapshot` carries it across the
/// process boundary to the widgets and watch app under a documented
/// backward-compatibility contract. Widening that wire format is a separate,
/// riskier change than widening the app's own model, and nothing on the other
/// side of it needs more than "is this person on a standard schedule?".
enum ShiftWorkMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Main sleep happens at night. Daytime sleep is a nap.
    case standard
    /// Main sleep happens in the day. The night window is when naps occur.
    case night
    /// The schedule moves between cycles, so no clock-time window holds.
    case rotating
    /// A self-defined pattern — biphasic, split, or otherwise irregular.
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .night: "Night shift"
        case .rotating: "Rotating"
        case .custom: "Custom"
        }
    }

    var explanation: String {
        switch self {
        case .standard: "Main sleep at night. Sleep during the day is treated as a nap."
        case .night: "Main sleep during the day. Sleep at night is treated as a nap."
        case .rotating: "Your schedule moves. Zoon judges episodes by length, not clock time."
        case .custom: "An irregular or split pattern. Zoon judges episodes by length, not clock time."
        }
    }

    /// Whether a fixed clock-time window can meaningfully separate a nap from
    /// a main sleep block for this schedule.
    ///
    /// False for `rotating` and `custom`: there is no honest window to apply,
    /// so classification falls back to duration rather than penalising sleep
    /// for happening in daylight.
    var usesClockTimeWindow: Bool {
        switch self {
        case .standard, .night: true
        case .rotating, .custom: false
        }
    }

    /// Whether the standard daytime window should be read as "nap" (the
    /// default) or inverted. Only meaningful when `usesClockTimeWindow`.
    var treatsDaytimeAsNap: Bool { self == .standard }

    /// What the pre-V2 Bool meant. Anything other than a standard schedule
    /// counted as "shift work" to the widgets and watch.
    var isNonStandard: Bool { self != .standard }

    /// Migration from the Bool. `true` becomes `night`, which is what the
    /// Bool actually did — it inverted the window, and inverting the night
    /// window is the night-shift case.
    static func migrating(fromLegacyEnabled enabled: Bool) -> ShiftWorkMode {
        enabled ? .night : .standard
    }
}
