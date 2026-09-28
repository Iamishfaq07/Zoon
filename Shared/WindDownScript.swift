import Foundation

/// What Wind Down says around its breathing: the part that makes a thirty
/// minute session a guided one.
///
/// It used to say one sentence on arrival and breathing cues for two cycles,
/// then nothing: a thirty-minute routine was about a minute of voice and
/// twenty-four minutes of silence, which is what "too short, weak pacing"
/// meant. This fills the time the way a good sleep meditation does -- paced
/// breathing, a body scan from the feet up, a short visualisation, then only
/// occasional quiet reminders, and a soft close -- scaled to whatever length
/// the person chose, with deliberate silence between lines rather than a
/// stream of talk.
///
/// Timed from the routine's own start, not from the screen, so it keeps its
/// place with the phone locked and after a resume. Pure and deterministic:
/// the same routine always says the same things at the same moments, which
/// is also what makes it testable. No medical claims: it is relaxation
/// guidance, not treatment.
enum WindDownScript {

    struct Cue: Equatable, Sendable {
        /// Seconds from the routine's start.
        let at: TimeInterval
        let text: String
    }

    /// Nothing may be spoken closer than this to the previous line, so one
    /// sentence always finishes (with its pause) before the next begins.
    static let minimumGap: TimeInterval = 15

    static func cues(for configuration: WindDownGuidanceConfiguration, breathingEnabled: Bool = true) -> [Cue] {
        guard configuration.usesVoice else { return [] }
        let minimal = configuration.voiceMode == .minimal
        let arrive = WindDownGuidanceConfiguration.arriveSeconds
        let breathEnd = breathingEnabled ? arrive + configuration.actualGuidedSeconds : arrive
        let guidedEnd = breathingEnabled ? arrive + configuration.actualGuidedSeconds + configuration.pacedBreathingSeconds : arrive
        let closeStart = configuration.routineSeconds - WindDownGuidanceConfiguration.closeSeconds

        var cues: [Cue] = []

        // Slow breathing after the 4-7-8 cycles, for the rest of the chosen
        // guided minutes.
        if breathingEnabled, guidedEnd - breathEnd >= minimumGap {
            cues.append(Cue(at: breathEnd + 3, text: minimal ? pacedIntroMinimal : pacedIntro))
            if !minimal {
                cues += spaced(pacedReminders, from: breathEnd + 3 + 30, to: guidedEnd - minimumGap, every: 30, cycling: true)
            }
        }

        let quietStart = guidedEnd + 3
        let quietEnd = closeStart - 5
        if quietEnd - quietStart >= minimumGap {
            cues.append(Cue(at: quietStart, text: transition))
            if !minimal {
                var cursor = quietStart + 20
                let length = quietEnd - cursor

                // Body scan: most of the first part of the quiet time. Lines
                // are dropped evenly rather than crammed when time is short.
                let scanBudget = max(0, length * 0.55)
                let scanCount = min(bodyScan.count, Int(scanBudget / 18))
                if scanCount >= 3 {
                    let lines = evenlyChosen(bodyScan, count: scanCount)
                    let gap = min(40, max(18, scanBudget / Double(lines.count)))
                    for (index, line) in lines.enumerated() {
                        cues.append(Cue(at: cursor + Double(index) * gap, text: line))
                    }
                    cursor += Double(lines.count) * gap
                }

                // A short visualisation when there is room for it.
                if quietEnd - cursor >= 150 {
                    for (index, line) in visualisation.enumerated() {
                        cues.append(Cue(at: cursor + Double(index) * 32, text: line))
                    }
                    cursor += Double(visualisation.count) * 32
                }

                // Then only an occasional presence, so the person is not left
                // wondering whether the session stopped, but never a stream.
                cues += spaced(presence, from: cursor + 90, to: quietEnd - 30, every: 170, cycling: true)
            }
        }

        if closeStart > (cues.last?.at ?? 0) + minimumGap {
            cues.append(Cue(at: closeStart, text: minimal ? closingMinimal : closing))
        }
        return cues.sorted { $0.at < $1.at }
    }

    // MARK: - Script

    static let pacedIntro = "Let the counting go now. Keep breathing slowly, in for about four, and out for a little longer."
    static let pacedIntroMinimal = "Now breathe slowly, at your own pace."
    static let pacedReminders = [
        "Breathe in, and a long, slow breath out.",
        "Let each breath out be a little longer than the breath in.",
        "In through the nose, and out, slowly.",
        "Nothing to force. Just slow, easy breaths."
    ]

    static let transition = "Let your breathing return to its own rhythm. There's nothing you need to do now."

    static let bodyScan = [
        "Bring your attention to your feet. Let them grow heavy.",
        "Your ankles and calves. Let them soften.",
        "Your knees, and the long muscles of your thighs. Let them rest.",
        "Your hips and lower back. Let the bed hold all of your weight.",
        "Your belly, rising and falling on its own.",
        "Your chest. Each breath a little slower than the last.",
        "Your hands. Let your fingers uncurl.",
        "Your arms, heavy and warm, sinking down.",
        "Your shoulders. Let them fall away from your ears.",
        "Your neck. Let it lengthen and release.",
        "Your jaw. Let your teeth part a little.",
        "Your face. Soften the space between your eyebrows.",
        "Your whole body now, heavy, warm and still."
    ]

    static let visualisation = [
        "Picture a quiet place where you feel safe. Perhaps a beach at dusk, or a forest after rain.",
        "Notice the colours there, softening as the light fades.",
        "Notice the sounds, slow and steady, asking nothing of you.",
        "You can stay here for as long as you like."
    ]

    static let presence = [
        "If your mind wanders, that's fine. Come back to the breath, gently.",
        "Nothing to fix, and nothing to solve tonight.",
        "Let the next breath carry you a little deeper.",
        "Heavy and warm. Just resting."
    ]

    static let closing = "Stay just like this, and let sleep come when it's ready. Goodnight."
    static let closingMinimal = "Goodnight."

    // MARK: - Layout

    /// `lines` from `from`, one every `every` seconds, while they fit before
    /// `to`. With `cycling`, the lines repeat in order.
    private static func spaced(_ lines: [String], from: TimeInterval, to: TimeInterval, every: TimeInterval, cycling: Bool) -> [Cue] {
        guard !lines.isEmpty, every > 0 else { return [] }
        var cues: [Cue] = []
        var at = from
        var index = 0
        while at <= to, cycling || index < lines.count {
            cues.append(Cue(at: at, text: lines[index % lines.count]))
            index += 1
            at += every
        }
        return cues
    }

    /// `count` items spread evenly across `lines`, first and last included.
    static func evenlyChosen(_ lines: [String], count: Int) -> [String] {
        guard count < lines.count else { return lines }
        guard count > 1 else { return Array(lines.prefix(count)) }
        let step = Double(lines.count - 1) / Double(count - 1)
        return (0..<count).map { lines[Int((Double($0) * step).rounded())] }
    }
}
