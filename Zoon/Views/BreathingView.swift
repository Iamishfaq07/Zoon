import SwiftUI

/// Guided wind-down breathing — 4-7-8, narrated on-device.
///
/// Pushed from the Sleep tab, so it supplies no `NavigationStack` of its own.
struct BreathingView: View {

    @State private var coach = BreathingCoach()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool { coach.phase != .idle && coach.phase != .finished }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)

            pacer

            VStack(spacing: 6) {
                Text(instruction)
                    .font(Theme.numeral(26))
                    .contentTransition(.opacity)
                    .animation(Motion.value, value: coach.phase)

                if isRunning {
                    Text("Cycle \(min(coach.cyclesCompleted + 1, coach.totalCycles)) of \(coach.totalCycles)")
                        .font(Theme.text(13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                if isRunning { coach.stop() } else { coach.start() }
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
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { coach.stop() }
    }

    private var instruction: String {
        switch coach.phase {
        case .idle: "4-7-8 breathing"
        case .inhale: "Breathe in"
        case .hold: "Hold"
        case .exhale: "Breathe out"
        case .rest: " "
        case .finished: "Well done"
        }
    }

    /// Circle scales with the phase: largest at the top of an inhale, smallest
    /// after a full exhale — the shape itself is the pacing cue, narration is
    /// the backup for eyes-closed use.
    private var pacer: some View {
        let scale: CGFloat = {
            switch coach.phase {
            case .idle: 0.7
            case .inhale: 0.7 + 0.3 * coach.phaseProgress
            case .hold: 1.0
            case .exhale: 1.0 - 0.35 * coach.phaseProgress
            case .rest: 0.65
            case .finished: 0.7
            }
        }()

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.Metric.sleep.opacity(0.5), .clear],
                        center: .center, startRadius: 4, endRadius: 140
                    )
                )
            Circle()
                .stroke(Theme.Metric.sleep.opacity(0.5), lineWidth: 1.5)
        }
        .frame(width: 220, height: 220)
        .scaleEffect(scale)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.1),
            value: scale
        )
    }
}

#Preview("Breathing") {
    NavigationStack { BreathingView() }
}
