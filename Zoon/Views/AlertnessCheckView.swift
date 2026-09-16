import SwiftUI

struct AlertnessCheckView: View {
    private enum Phase { case intro, waiting, ready, tooSoon, rating, complete }

    @State private var store = AlertnessCheckStore()
    @State private var phase: Phase = .intro
    @State private var trial = 0
    @State private var reactions: [TimeInterval] = []
    /// Taps before the signal. The brief asks for these; the old version
    /// showed a "too soon" message and then forgot it happened.
    @State private var falseStarts = 0
    @State private var appearedAt: ContinuousClock.Instant?
    @State private var waitTask: Task<Void, Never>?
    @State private var subjective = 3
    /// What the engine was willing to say about the run just saved, which for
    /// the first several runs is deliberately that it is not saying anything.
    @State private var outcome: AlertnessCheck.Outcome?
    /// Set when a run was too short to store. The old screen showed a tick
    /// either way.
    @State private var wasNotSaved = false

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trials = 6

    var body: some View {
        ScrollView {
            CascadeStack(spacing: Theme.stackSpacing) {
                header
                testSurface
                if !store.sessions.isEmpty { history }
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
                .font(Theme.text(13)).foregroundStyle(Theme.inkSecondary)
            Text("Wellness information only. This is not a medical, neurological, driving, or fitness-for-duty test.")
                .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
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
                if wasNotSaved {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 54)).foregroundStyle(Theme.Metric.recoveryMid)
                    Text("Not saved").font(Theme.numeral(24))
                    Text("Too few responses to make a median worth keeping.")
                        .font(Theme.text(13)).foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54)).foregroundStyle(Theme.Metric.recoveryHigh)
                    Text("Saved on this device").font(Theme.numeral(24))
                    if let latest = store.sessions.first {
                        summary(latest)
                    }
                    // The engine's verdict, which for the first several checks
                    // is that it has none. Shown rather than hidden, because
                    // "not enough yet" is the honest answer and silence reads
                    // as an app that simply does nothing with this.
                    if let outcome {
                        Text(outcome.sentence)
                            .font(Theme.text(14))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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

    /// One saved check, as the figures the brief asks to track.
    private func summary(_ session: AlertnessCheck.Session) -> some View {
        VStack(spacing: 4) {
            Text("Median \(Int(session.medianMilliseconds.rounded())) ms")
                .font(Theme.text(13)).foregroundStyle(Theme.inkSecondary)
            // Each of these appears only when it was measured. A zero spread
            // or a zero false-start count on a record that never held one
            // would be a claim rather than a reading.
            if let iqr = session.iqrMilliseconds {
                Text("Spread \(Int(iqr.rounded())) ms")
                    .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
            }
            if session.lapses > 0 {
                Text("\(session.lapses.pluralized("lapse"))")
                    .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
            }
            if let note = AlertnessCheck.falseStartNote(session.falseStarts) {
                Text(note).font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
            }
            if let minutes = session.minutesSinceWaking {
                Text("\(SleepNightFeatures.formatMinutes(minutes)) after waking")
                    .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recent checks", subtitle: "Compare with your own history, not other people.", systemImage: "chart.xyaxis.line")
            ForEach(store.sessions.prefix(7)) { session in
                HStack {
                    Text(session.date, format: .dateTime.month(.abbreviated).day()).font(Theme.text(12))
                    Spacer()
                    Text("\(Int(session.medianMilliseconds.rounded())) ms")
                        .font(Theme.label(13, weight: .semibold)).monospacedDigit()
                    if let rating = session.subjectiveAlertness {
                        Text("· \(rating)/5").font(Theme.text(12)).foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
            if store.sessions.contains(where: { $0.lapses > 0 }) {
                Text(AlertnessCheck.lapseCaveat)
                    .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.glassCard()
    }

    private func begin() { trial = 0; reactions = []; falseStarts = 0; scheduleTrial() }
    private func scheduleTrial() {
        waitTask?.cancel(); phase = .waiting
        waitTask = Task {
            let delay = UInt64.random(in: 2_200_000_000...3_800_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            appearedAt = .now; phase = .ready; Haptics.tap()
        }
    }
    private func tooSoon() {
        waitTask?.cancel()
        falseStarts += 1
        phase = .tooSoon
        Haptics.warning()
    }
    private func recordTap() {
        guard let appearedAt else { return }
        // The clock is read once. This used to call `.now` twice -- once for
        // the seconds and once for the attoseconds -- so the two halves came
        // from two different instants, adding jitter to the one thing on this
        // screen that is actually a measurement.
        let elapsed = appearedAt.duration(to: .now).components
        reactions.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        trial += 1; Haptics.tap()
        if trial >= trials { phase = .rating } else { scheduleTrial() }
    }

    private func finish() {
        let saved = store.save(
            reactions: reactions,
            falseStarts: falseStarts,
            subjectiveAlertness: subjective,
            wakeTime: coordinator.state.context?.night.wakeTime
        )
        outcome = saved
        wasNotSaved = saved == nil
        phase = .complete
        if saved == nil { Haptics.warning() } else { Haptics.success() }
    }

    private func reset() {
        phase = .intro
        trial = 0
        reactions = []
        falseStarts = 0
        appearedAt = nil
        outcome = nil
        wasNotSaved = false
    }
}

#Preview { NavigationStack { AlertnessCheckView() }.zoonPreviewEnvironment() }
