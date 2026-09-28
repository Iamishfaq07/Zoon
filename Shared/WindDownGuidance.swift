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

        /// For the four-way segmented control, where the full labels do not
        /// fit on a phone and the first one truncated to "Natural voi...".
        var shortLabel: String {
            switch self {
            case .natural: "Voice"
            case .minimal: "Minimal"
            case .hapticsOnly: "Haptics"
            case .silent: "Silent"
            }
        }

        var usesVoice: Bool {
            self == .natural || self == .minimal
        }

        var usesHaptics: Bool {
            self == .hapticsOnly || self == .natural || self == .minimal
        }

        /// The spoken cue for one phase of one cycle.
        ///
        /// Every cycle is paced. Cues used to stop after the second cycle,
        /// leaving the rest of the breathing in silence with only a circle on
        /// a screen that is usually locked at bedtime -- part of why Wind
        /// Down felt too short and unguided. There are at most
        /// `maximumGuidedCycles` cycles, so this is never more than a few
        /// minutes of cues.
        func cue(phase: String, cycleIndex: Int) -> String {
            switch self {
            case .silent, .hapticsOnly:
                return ""
            case .minimal:
                switch phase {
                case "inhale": return "In."
                case "hold": return "Hold."
                case "exhale": return "Out."
                default: return ""
                }
            case .natural:
                if cycleIndex == 0 {
                    switch phase {
                    case "inhale": return "Slowly breathe in through your nose."
                    case "hold": return "Hold gently."
                    case "exhale": return "Now breathe out slowly, all the way."
                    default: return ""
                    }
                }
                // Alternate the wording so eight cycles do not sound like one
                // recording played eight times.
                let even = cycleIndex % 2 == 0
                switch phase {
                case "inhale": return even ? "Breathe in." : "In, slowly."
                case "hold": return even ? "Hold." : "And hold."
                case "exhale": return even ? "Breathe out." : "Let it all go."
                default: return ""
                }
            }
        }
    }

    enum Stage: String, Sendable, Equatable, Codable {
        case arrive
        case guided
        case quiet
        case close
    }

    /// Position inside 4-7-8 guidance, reconstructed from wall-clock elapsed
    /// rather than a Timer tick count.
    struct GuidedPosition: Equatable, Sendable {
        var cyclesCompleted: Int
        var phaseName: String
        var remaining: TimeInterval
    }

    /// 4-7-8 plus a 2-second rest: the whole technique, not an invention.
    static let inhaleSeconds: Double = 4
    static let holdSeconds: Double = 7
    static let exhaleSeconds: Double = 8
    static let restSeconds: Double = 2
    static var cycleSeconds: Double { inhaleSeconds + holdSeconds + exhaleSeconds + restSeconds }

    static let arriveSeconds: TimeInterval = 45
    static let closeSeconds: TimeInterval = 20
    static let minimumQuietSeconds: TimeInterval = 30

    static var reservedSeconds: TimeInterval { arriveSeconds + closeSeconds + minimumQuietSeconds }

    static func maxGuidedMinutes(routineMinutes: Int) -> Int {
        let available = Double(min(120, max(5, routineMinutes))) * 60 - reservedSeconds
        return max(2, min(15, Int(available / 60)))
    }

    init(
        routineDurationMinutes: Int = 30,
        guidedBreathingMinutes: Int = 5,
        voiceMode: VoiceMode = .natural
    ) {
        self.routineDurationMinutes = min(120, max(5, routineDurationMinutes))
        let cap = Self.maxGuidedMinutes(routineMinutes: self.routineDurationMinutes)
        self.guidedBreathingMinutes = min(cap, max(2, guidedBreathingMinutes))
        self.voiceMode = voiceMode
    }

    var routineSeconds: TimeInterval { Double(routineDurationMinutes) * 60 }

    var usesHaptics: Bool { voiceMode.usesHaptics }
    var usesVoice: Bool { voiceMode.usesVoice }

    /// 4-7-8's own guidance is about four cycles, and no more than eight.
    /// Filling ten minutes with it meant 28 cycles in a row, which the
    /// technique does not recommend and which feels like a drill; the minutes
    /// after the cycles are slow paced breathing instead
    /// (`pacedBreathingSeconds`, spoken by `WindDownScript`).
    static let maximumGuidedCycles = 8

    var guidedCycles: Int {
        let budget = actualGuidedBudget
        return max(1, min(Self.maximumGuidedCycles, Int(budget / Self.cycleSeconds)))
    }

    /// The guided-breathing minutes the person chose, in seconds.
    var actualGuidedBudget: TimeInterval {
        Double(guidedBreathingMinutes) * 60
    }

    /// The 4-7-8 part: whole cycles only. Display this, not a rounded-up
    /// count that overruns the stage.
    var actualGuidedSeconds: TimeInterval {
        Double(guidedCycles) * Self.cycleSeconds
    }

    /// The rest of the chosen guided minutes after the 4-7-8 cycles: slow
    /// breathing at the person's own pace, with spoken reminders.
    var pacedBreathingSeconds: TimeInterval {
        max(0, actualGuidedBudget - actualGuidedSeconds)
    }

    func stage(elapsed: TimeInterval) -> Stage {
        if elapsed < Self.arriveSeconds { return .arrive }
        let guidedEnd = Self.arriveSeconds + actualGuidedSeconds + pacedBreathingSeconds
        if elapsed < guidedEnd { return .guided }
        if elapsed < max(guidedEnd, routineSeconds - Self.closeSeconds) { return .quiet }
        return .close
    }

    /// Maps wall-clock elapsed onto the current 4-7-8 phase so Resume does
    /// not restart from Arrive / cycle 1.
    func guidedPosition(elapsed: TimeInterval) -> GuidedPosition {
        if elapsed < Self.arriveSeconds {
            return GuidedPosition(
                cyclesCompleted: 0,
                phaseName: "arrive",
                remaining: Self.arriveSeconds - elapsed
            )
        }
        let intoGuidance = elapsed - Self.arriveSeconds
        let totalGuided = actualGuidedSeconds
        if intoGuidance >= totalGuided {
            return GuidedPosition(cyclesCompleted: guidedCycles, phaseName: "quiet", remaining: 0)
        }
        let cycleIndex = min(guidedCycles - 1, Int(intoGuidance / Self.cycleSeconds))
        let intoCycle = intoGuidance - Double(cycleIndex) * Self.cycleSeconds
        if intoCycle < Self.inhaleSeconds {
            return GuidedPosition(cyclesCompleted: cycleIndex, phaseName: "inhale", remaining: Self.inhaleSeconds - intoCycle)
        }
        if intoCycle < Self.inhaleSeconds + Self.holdSeconds {
            return GuidedPosition(
                cyclesCompleted: cycleIndex,
                phaseName: "hold",
                remaining: Self.inhaleSeconds + Self.holdSeconds - intoCycle
            )
        }
        if intoCycle < Self.inhaleSeconds + Self.holdSeconds + Self.exhaleSeconds {
            return GuidedPosition(
                cyclesCompleted: cycleIndex,
                phaseName: "exhale",
                remaining: Self.inhaleSeconds + Self.holdSeconds + Self.exhaleSeconds - intoCycle
            )
        }
        return GuidedPosition(
            cyclesCompleted: cycleIndex,
            phaseName: "rest",
            remaining: max(0.2, Self.cycleSeconds - intoCycle)
        )
    }

    static let arriveLine = "Get comfortable. Let your shoulders drop and allow your breathing to settle."
    /// No "Well done" — the user is trying to sleep.
    static let closeLine = ""
}
