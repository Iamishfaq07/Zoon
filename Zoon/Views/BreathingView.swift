import SwiftUI
import UIKit

/// Guided wind-down breathing — 4-7-8, narrated on-device.
///
/// Before a session: what 4-7-8 is, one choice of guide (voice, minimal
/// cues, haptics or silent) and one of length. During it: the moon breathes
/// with the pacer, a ring fills through each phase, and the seconds left in
/// the phase count down in the middle. The guide choice used to sit beside
/// two toggles that said the same thing differently -- turning voice off and
/// tapping Begin spoke anyway, because the picker overrode the toggle, and
/// once haptics were on they could not be turned off again.
///
/// Pushed from the Sleep tab, so it supplies no `NavigationStack` of its own.
struct BreathingView: View {

    @State private var coach = BreathingCoach()
    @State private var breaths = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { coach.phase != .idle && coach.phase != .finished }

    /// One 4-7-8 breath with its pause, in seconds.
    private static let breathSeconds = WindDownGuidanceConfiguration.inhaleSeconds
        + WindDownGuidanceConfiguration.holdSeconds
        + WindDownGuidanceConfiguration.exhaleSeconds
        + WindDownGuidanceConfiguration.restSeconds

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            pacer

            VStack(spacing: 6) {
                Text(instruction)
                    .font(Theme.numeral(26))
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : Motion.value, value: coach.phase)

                if isRunning {
                    Text("Breath \(min(coach.cyclesCompleted + 1, coach.totalCycles)) of \(coach.totalCycles)")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                } else if coach.phase == .finished {
                    Text("\(coach.totalCycles) breaths done. Stay still for a moment, then let sleep come.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                } else {
                    Text("In for 4, hold for 7, out for 8. The long breath out slows your heart and tells your body it is time to rest.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                }
            }

            Spacer(minLength: 0)

            if isRunning {
                Text("The screen stays on while you breathe. Locking it pauses the guide.")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else {
                setup
            }

            Button {
                Haptics.tap()
                if isRunning {
                    coach.stop()
                } else {
                    begin()
                }
            } label: {
                Text(isRunning ? "Stop" : (coach.phase == .finished ? "Do it again" : "Begin"))
                    .font(Theme.label(16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [Theme.Metric.sleep, Theme.Metric.battery],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .foregroundStyle(.black)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nightBackground()
        .navigationTitle("Wind Down")
        .hidesFloatingTabBar()
        .navigationBarTitleDisplayMode(.inline)
        // Nothing plays between cues here -- no sound scene, unlike the
        // Tonight routine -- so once Auto-Lock fired, iOS suspended the app,
        // the coach's timer stopped, and the first "Slowly breathe in" never
        // came. The screen stays on for the session instead, rather than a
        // silent track keeping the app alive in the background.
        .onChange(of: isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = running
        }
        .onDisappear {
            coach.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// One control per decision: how to be guided, and for how long.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Guide")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Picker("Guide", selection: $coach.voiceMode) {
                    ForEach(WindDownGuidanceConfiguration.VoiceMode.allCases) { mode in
                        Text(mode.shortLabel)
                            .accessibilityLabel(mode.label)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(guideCaption)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Length")
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.inkSecondary)
                Picker("Length", selection: $breaths) {
                    Text("4 breaths · \(lengthLabel(4))").tag(4)
                    Text("8 breaths · \(lengthLabel(8))").tag(WindDownGuidanceConfiguration.maximumGuidedCycles)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal, 28)
    }

    private var guideCaption: String {
        switch coach.voiceMode {
        case .natural: "A calm voice talks you through each breath, with a tap on each change."
        case .minimal: "Just \"in\", \"hold\" and \"out\", with a tap on each change."
        case .hapticsOnly: "No voice. A tap on each change, for eyes closed and a quiet room."
        case .silent: "Nothing to hear or feel. Follow the moon."
        }
    }

    /// "2 min", "3½ min": the settling minute plus the breaths.
    private func lengthLabel(_ count: Int) -> String {
        let seconds = WindDownGuidanceConfiguration.arriveSeconds + Double(count) * Self.breathSeconds
        let halves = Int((seconds / 30).rounded())
        return halves % 2 == 0 ? "\(halves / 2) min" : "\(halves / 2)½ min"
    }

    private func begin() {
        coach.includeArrive = true
        coach.closingPhrase = WindDownGuidanceConfiguration.closeLine
        // The guide decides haptics. The coach keeps an explicit request
        // (the Tonight routine's setting) on top of the mode, so it starts
        // from off here, or a haptics session once chosen could never end.
        coach.hapticsEnabled = false
        coach.start(cycles: breaths)
    }

    private var instruction: String {
        switch coach.phase {
        case .idle: "4-7-8 breathing"
        case .arrive: "Get comfortable"
        case .inhale: "Breathe in"
        case .hold: "Hold"
        case .exhale: "Breathe out"
        case .rest: " "
        case .quiet: "Stay with the sound"
        case .finished: "Rest here"
        }
    }

    private var phaseTint: Color {
        switch coach.phase {
        case .inhale: Theme.Metric.battery
        case .hold: Theme.Metric.sleep
        case .exhale: Theme.Metric.respiratory
        default: Theme.Family.Moon.lit
        }
    }

    /// Whole seconds left in a counted phase, for the middle of the pacer.
    private var countdown: Int? {
        switch coach.phase {
        case .inhale, .hold, .exhale: max(1, Int(coach.remainingInPhase.rounded(.up)))
        default: nil
        }
    }

    /// The moon scales with the phase: largest at the top of an inhale,
    /// smallest after a full exhale -- the shape itself is the pacing cue,
    /// narration the backup for eyes-closed use. A ring around it fills
    /// through each phase in the phase's colour.
    private var pacer: some View {
        let scale: CGFloat = {
            switch coach.phase {
            case .idle, .arrive, .quiet, .finished: 0.7
            case .inhale: 0.65 + 0.35 * coach.phaseProgress
            case .hold: 1.0
            case .exhale: 1.0 - 0.35 * coach.phaseProgress
            case .rest: 0.65
            }
        }()

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [phaseTint.opacity(0.22), .clear],
                        center: .center, startRadius: 4, endRadius: 150
                    )
                )
            MoonFill(fill: 0.62, active: true, size: 176)
                .opacity(0.72)
                .scaleEffect(reduceMotion ? 0.85 : scale)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: scale)
            Circle()
                .stroke(Theme.neutral(0.10), lineWidth: 4)
                .padding(4)
            if isRunning, coach.phase != .rest {
                Circle()
                    .trim(from: 0, to: coach.phaseProgress)
                    .stroke(phaseTint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            }
            if let countdown {
                Text("\(countdown)")
                    .font(Theme.numeral(44))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : Motion.tap, value: countdown)
            }
        }
        .frame(width: 240, height: 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countdown.map { "\(instruction), \($0) seconds" } ?? instruction)
    }
}

#Preview("Breathing") {
    NavigationStack { BreathingView() }
}
