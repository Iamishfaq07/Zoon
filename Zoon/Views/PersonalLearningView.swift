import SwiftUI

/// The personal-learning features that need longitudinal evidence and may
/// honestly have nothing to show yet.
struct PersonalLearningView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @State private var resilience: [PersonalLearning.Resilience] = []
    @State private var circadian: PersonalLearning.CircadianResponse?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                unlockMap
                    .entrance(0)
                moodSection
                    .entrance(1)
                resilienceSection
                    .entrance(1)
                circadianSection
                    .entrance(2)
                NavigationLink { AlertnessCheckView() } label: {
                    Label("Take the optional alertness check", systemImage: "hand.tap.fill")
                        .font(Theme.label(14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }
                .buttonStyle(PressableStyle())
                .entrance(3)
            }.padding()
        }
        .nightBackground()
        .navigationTitle("Personal learning")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: coordinator.recentNights.count) { calculate() }
    }

    /// What the history unlocks, from the engines' own thresholds (audit
    /// §17.5). A ring for how much is open, then the path as a timeline.
    /// Each step used to carry its own sentence; only the one being worked
    /// towards does now, since that is the only one anyone acts on.
    private var unlockMap: some View {
        let nights = coordinator.recentNights.count
        let items = LearningUnlockMap.progress(nightCount: nights)
        let unlocked = items.filter { $0.state == .unlocked }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                UnlockRing(fraction: items.isEmpty ? 0 : Double(unlocked) / Double(items.count)) {
                    VStack(spacing: 0) {
                        Text("\(unlocked)")
                            .font(Theme.heading(24))
                            .monospacedDigit()
                        Text("of \(items.count)")
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .frame(width: 78, height: 78)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(nights) \(nights == 1 ? "night" : "nights") in")
                        .font(Theme.heading(20))
                    Text("Each night opens more.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(unlocked) of \(items.count) unlocked after \(nights) nights")

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.milestone.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        // The node, and the path down to the next one.
                        VStack(spacing: 0) {
                            Image(systemName: symbol(for: item.state))
                                .font(Theme.text(16, weight: .semibold))
                                .foregroundStyle(tint(for: item.state))
                                .frame(width: 22, height: 22)
                            if index < items.count - 1 {
                                Capsule()
                                    .fill(item.state == .unlocked ? Theme.Family.recovery.opacity(0.6) : Theme.neutral(0.12))
                                    .frame(width: 2)
                                    .frame(minHeight: 14, maxHeight: .infinity)
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.milestone.title)
                                    .font(Theme.label(14, weight: .semibold))
                                    .foregroundStyle(item.state == .unlocked || isNext(item.state) ? Theme.ink : Theme.inkSecondary)
                                Spacer(minLength: 8)
                                Text(stateLabel(item.state))
                                    .font(Theme.text(12, weight: isNext(item.state) ? .semibold : .regular))
                                    .monospacedDigit()
                                    .foregroundStyle(isNext(item.state) ? Theme.Family.sleep : Theme.inkTertiary)
                            }
                            if isNext(item.state) {
                                Text(item.milestone.detail)
                                    .font(Theme.text(12))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    // Sized to its content so the connector can stretch to
                    // the row's full height inside the scroll view.
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(item.milestone.title): \(stateLabel(item.state)). \(item.milestone.detail)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func isNext(_ state: LearningUnlockMap.State) -> Bool {
        if case .next = state { return true }
        return false
    }

    private func tint(for state: LearningUnlockMap.State) -> Color {
        switch state {
        case .unlocked: Theme.Family.recovery
        case .next: Theme.Family.sleep
        case .later: Theme.inkTertiary
        }
    }

    private func symbol(for state: LearningUnlockMap.State) -> String {
        switch state {
        case .unlocked: "checkmark.circle.fill"
        case .next: "circle.lefthalf.filled"
        case .later: "circle.dotted"
        }
    }

    /// Text as well as the symbol, so the state never rests on colour.
    private func stateLabel(_ state: LearningUnlockMap.State) -> String {
        switch state {
        case .unlocked: "Ready"
        case .next(let remaining), .later(let remaining): LearningUnlockMap.remainingCopy(remaining)
        }
    }

    /// Mood logged in Apple Health after full vs short nights. Needs
    /// Lifestyle Insights, the same opt-in as caffeine and daylight.
    @ViewBuilder private var moodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Mood and sleep",
                subtitle: "Logged mood after full and short nights.",
                systemImage: "face.smiling"
            )
            if !preferences.lifestyleInsightsEnabled {
                learningMessage("Turn on Lifestyle Insights in Settings to compare with the mood you log in Health.")
            } else if let link = coordinator.moodSleepLink {
                Text(link.sentence)
                    .font(Theme.label(14, weight: link.isReady ? .semibold : .regular))
                    .foregroundStyle(link.isReady ? Theme.ink : Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if link.isReady {
                    Text("Full: within 15 min of your need. Short: an hour under.")
                        .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                learningMessage("Log your daily mood in the Health app to start this comparison.")
            }
        }.glassCard()
    }

    @ViewBuilder private var resilienceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sleep resilience", subtitle: "How fast you bounce back after a disruption.", systemImage: "arrow.uturn.forward.circle")
            if resilience.isEmpty {
                learningMessage("Log two disruptions, like travel or a stressful day.")
            } else {
                ForEach(resilience) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.sentence).font(Theme.label(14, weight: .semibold))
                        Text("Typical of \(result.disruptions) disruptions. Back means two nights in range.")
                            .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
        }.glassCard()
    }

    @ViewBuilder private var circadianSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Circadian response", subtitle: "Your timing after morning daylight.", systemImage: "sun.horizon.fill")
            if let circadian {
                Text(circadian.sentence).font(Theme.label(15, weight: .semibold))
                Text("±\(circadian.uncertaintyMinutes) min · \(circadian.daylightNights) with daylight · \(circadian.comparisonNights) without")
                    .font(Theme.evidence).foregroundStyle(Theme.inkSecondary)
                Text("A link, not proof.")
                    .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
            } else {
                learningMessage("Log Morning daylight in the Journal on six yes and six no days.")
            }
        }.glassCard()
    }

    private func learningMessage(_ text: String) -> some View {
        Label(text, systemImage: "circle.dotted")
            .font(Theme.text(12)).foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func calculate() {
        let observations = coordinator.journalObservations()
        let disruptions = Set(observations.filter {
            $0.exposureState(for: .travelled) == .yes || $0.exposureState(for: .stressfulDay) == .yes
        }.map(\.date))
        resilience = PersonalLearning.resilience(nights: coordinator.recentNights, disruptionDates: disruptions)
        circadian = PersonalLearning.circadianResponse(observations: observations)
    }
}

#Preview { NavigationStack { PersonalLearningView() }.zoonPreviewEnvironment() }

/// A ring that fills to `fraction` once, with whatever sits in its middle.
private struct UnlockRing<Center: View>: View {
    let fraction: Double
    @ViewBuilder var center: Center
    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.neutral(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0.001, fraction * progress))
                .stroke(
                    AngularGradient(
                        colors: [Theme.Family.sleep, Theme.Family.recovery],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            center
        }
        .drawOnce(id: fraction, progress: $progress)
    }
}
