import Foundation

/// How long spoken 4-7-8 guidance actually lasts, and which stage a
/// Tonight routine is in.
///
/// Default BreathingCoach used to run 4 cycles (~84 seconds) even when the
/// routine was 30 minutes. That is the "Wind Down is too short" bug.
struct WindDownGuidanceConfiguration: Equatable, Sendable, Codable {
    var routineDurationMinutes: Int
    var guidedBreathingMinutes: Int
    var voiceMode: VoiceMode

    enum VoiceMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case natural
        case minimal
        case hapticsOnly
        case silent

        var id: String { rawValue }

        var label: String {
            switch self {
            case .natural: "Natural voice"
            case .minimal: "Minimal cues"
            case .hapticsOnly: "Haptics only"
            case .silent: "Silent visual"
            }
        }

        var usesVoice: Bool {
            self == .natural || self == .minimal
        }

        var usesHaptics: Bool {
            self == .hapticsOnly || self == .natural || self == .minimal
        }

        func cue(phase: String, cycleIndex: Int) -> String {
            switch self {
            case .silent, .hapticsOnly:
                return ""
            case .minimal:
                if cycleIndex >= 2 { return "" }
                switch phase {
                case "inhale": return "In."
                case "hold": return "Hold."
                case "exhale": return "Out."
                default: return ""
                }
            case .natural:
                if cycleIndex == 0 {
                    switch phase {
                    case "inhale": return "Slowly breathe in."
                    case "hold": return "Hold gently."
                    case "exhale": return "Now breathe out."
                    default: return ""
                    }
                }
                if cycleIndex < 2 {
                    switch phase {
                    case "inhale": return "Breathe in."
                    case "hold": return "Hold."
                    case "exhale": return "Breathe out."
                    default: return ""
                    }
                }
                return ""
            }
        }
    }

    enum Stage: String, Sendable, Equatable {
        case arrive
        case guided
        case quiet
        case close
    }

    /// 4-7-8 plus a 2-second rest: the whole technique, not an invention.
    static let inhaleSeconds: Double = 4
    static let holdSeconds: Double = 7
    static let exhaleSeconds: Double = 8
    static let restSeconds: Double = 2
    static var cycleSeconds: Double { inhaleSeconds + holdSeconds + exhaleSeconds + restSeconds }

    static let arriveSeconds: TimeInterval = 45
    static let closeSeconds: TimeInterval = 20

    init(
        routineDurationMinutes: Int = 30,
        guidedBreathingMinutes: Int = 5,
        voiceMode: VoiceMode = .natural
    ) {
        self.routineDurationMinutes = min(120, max(5, routineDurationMinutes))
        let guidedCap = min(self.routineDurationMinutes, max(2, guidedBreathingMinutes))
        self.guidedBreathingMinutes = guidedCap
        self.voiceMode = voiceMode
    }

    var routineSeconds: TimeInterval { Double(routineDurationMinutes) * 60 }

    var guidedCycles: Int {
        let budget = Double(guidedBreathingMinutes) * 60
        return max(1, Int((budget / Self.cycleSeconds).rounded()))
    }

    func stage(elapsed: TimeInterval) -> Stage {
        if elapsed < Self.arriveSeconds { return .arrive }
        let guidedEnd = Self.arriveSeconds + Double(guidedBreathingMinutes) * 60
        if elapsed < guidedEnd { return .guided }
        if elapsed < max(0, routineSeconds - Self.closeSeconds) { return .quiet }
        return .close
    }

    static let arriveLine = "Get comfortable. Let your shoulders drop and allow your breathing to settle."
    /// No "Well done" — the user is trying to sleep.
    static let closeLine = ""
}
