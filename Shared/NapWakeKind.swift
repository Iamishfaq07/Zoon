import Foundation

/// How a nap wake was actually armed. AlarmKit and a Focus-silenced
/// notification are not the same promise.
enum NapWakeKind: String, Codable, Equatable, Sendable {
    case alarmKit
    case notification
    case unavailable

    var historyLabel: String {
        switch self {
        case .alarmKit: "AlarmKit armed successfully"
        case .notification: "Notification fallback · may be silenced by Focus"
        case .unavailable: "Wake unavailable"
        }
    }

    var shortLabel: String {
        switch self {
        case .alarmKit: "AlarmKit · Armed"
        case .notification: "Wake notification · May be silenced by Focus"
        case .unavailable: "No wake scheduled"
        }
    }

    var coachSentence: String {
        switch self {
        case .alarmKit:
            return "Wake alarm is armed and should ring through Silent and Focus."
        case .notification:
            return "Wake is a notification — Focus may silence it."
        case .unavailable:
            return "A wake could not be scheduled. Check Settings."
        }
    }
}

struct NapStartResult: Equatable, Sendable {
    let targetMinutes: Int
    let wake: NapWakeKind
}
