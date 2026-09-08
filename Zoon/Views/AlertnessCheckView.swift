import SwiftUI

struct AlertnessCheckView: View {
    private enum Phase { case intro, waiting, ready, tooSoon, rating, complete }

    @State private var store = AlertnessCheckStore()
    @State private var phase: Phase = .intro
    @State private var trial = 0
    @State private var reactions: [TimeInterval] = []
    @State private var appearedAt: ContinuousClock.Instant?
    @State private var waitTask: Task<Void, Never>?
    @State private var subjective = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trials = 6

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                header
                testSurface
                if !store.results.isEmpty { history }
            }
            .padding()
        }
        .nightBackground()
        .navigationTitle("Morning alertness")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { waitTask?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Optional 20–30 second check", systemImage: "hand.tap.fill")
                .font(Theme.label(15, weight: .semibold))
            Text("Tap when the moon changes. Zoon records reaction time, lapses, and how alert you feel as a personal outcome alongside your sleep history.")
                .font(Theme.text(13)).foregroundStyle(.secondary)
            Text("Wellness information only. This is not a medical, neurological, driving, or fitness-for-duty test.")
                .font(Theme.evidence).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder private var testSurface: some View {
        VStack(spacing: 18) {
            switch phase {
            case .intro:
                Image(systemName: "moon.circle.fill").font(.system(size: 64)).foregroundStyle(Theme.Metric.sleep)
                Text("Use this after waking, before caffeine, when you can sit safely.").font(Theme.text(14)).multilineTextAlignment(.center)
                Button("Begin check") { begin() }.buttonStyle(.borderedProminent)
            case .waiting:
                Text("Wait…").font(Theme.numeral(28))
                reactionButton(color: Theme.neutral(0.12)) { tooSoon() }
            case .ready:
                Text("Tap now").font(Theme.numeral(28)).foregroundStyle(Theme.Metric.recoveryHigh)
                reactionButton(color: Theme.Metric.recoveryHigh) { recordTap() }
            case .tooSoon:
                Text("Too soon — wait for the change").font(Theme.label(16, weight: .semibold))
                Button("Continue") { scheduleTrial() }.buttonStyle(.bordered)
            case .rating:
                Text("How alert do you feel?").font(Theme.label(18, weight: .semibold))
                Picker("Subjective alertness", selection: $subjective) {
                    Text("Very sleepy").tag(1); Text("Sleepy").tag(2); Text("Okay").tag(3); Text("Alert").tag(4); Text("Very alert").tag(5)
                }.pickerStyle(.wheel).frame(height: 120)
                Button("Save result") { finish() }.buttonStyle(.borderedProminent)
            case .complete:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(Theme.Metric.recoveryHigh)
                Text("Saved on this device").font(Theme.numeral(24))
                if let latest = store.results.first {
                    Text("Median \(latest.medianReactionMilliseconds) ms · \(latest.lapses) \(latest.lapses == 1 ? "lapse" : "lapses") · alertness \(latest.subjectiveAlertness)/5")
                        .font(Theme.text(13)).foregroundStyle(.secondary)
                }
                Button("Done") { reset() }.buttonStyle(.bordered)
            }

            if phase == .waiting || phase == .ready || phase == .tooSoon {
                ProgressView(value: Double(trial), total: Double(trials))
                    .accessibilityLabel("Trial \(min(trial + 1, trials)) of \(trials)")
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard()
        .animation(Motion.respecting(reduceMotion, Motion.tap), value: phase)
    }

    private func reactionButton(color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 150, height: 150)
                .overlay(Image(systemName: "moon.fill").font(.system(size: 48)).foregroundStyle(.white))
        }.buttonStyle(.plain).accessibilityLabel(phase == .ready ? "Tap now" : "Wait")
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent checks", subtitle: "Compare with your own history, not other people.", systemImage: "chart.xyaxis.line")
            ForEach(store.results.prefix(7)) { result in
                HStack {
                    Text(result.date, format: .dateTime.month(.abbreviated).day()).font(Theme.text(12))
                    Spacer()
                    Text("\(result.medianReactionMilliseconds) ms").font(Theme.label(13, weight: .semibold)).monospacedDigit()
                    Text("· \(result.subjectiveAlertness)/5").font(Theme.text(12)).foregroundStyle(.secondary)
                }
            }
        }.glassCard()
    }

    private func begin() { trial = 0; reactions = []; scheduleTrial() }
    private func scheduleTrial() {
        waitTask?.cancel(); phase = .waiting
        waitTask = Task {
            let delay = UInt64.random(in: 2_200_000_000...3_800_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            appearedAt = .now; phase = .ready; Haptics.tap()
        }
    }
    private func tooSoon() { waitTask?.cancel(); phase = .tooSoon; Haptics.warning() }
    private func recordTap() {
        guard let appearedAt else { return }
        reactions.append(Double(appearedAt.duration(to: .now).components.attoseconds) / 1e18 + Double(appearedAt.duration(to: .now).components.seconds))
        trial += 1; Haptics.tap()
        if trial >= trials { phase = .rating } else { scheduleTrial() }
    }
    private func finish() { store.save(reactions: reactions, subjectiveAlertness: subjective); phase = .complete; Haptics.success() }
    private func reset() { phase = .intro; trial = 0; reactions = []; appearedAt = nil }
}

#Preview { NavigationStack { AlertnessCheckView() }.preferredColorScheme(.dark) }
