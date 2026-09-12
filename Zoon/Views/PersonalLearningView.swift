import SwiftUI

/// The personal-learning features that need longitudinal evidence and may
/// honestly have nothing to show yet.
struct PersonalLearningView: View {
    @Environment(SleepDataCoordinator.self) private var coordinator
    @State private var resilience: [PersonalLearning.Resilience] = []
    @State private var circadian: PersonalLearning.CircadianResponse?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.stackSpacing) {
                introduction
                resilienceSection
                circadianSection
                NavigationLink { AlertnessCheckView() } label: {
                    Label("Take the optional alertness check", systemImage: "hand.tap.fill")
                        .font(Theme.label(14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard()
                }.buttonStyle(PressableStyle())
            }.padding()
        }
        .nightBackground()
        .navigationTitle("Personal learning")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: coordinator.recentNights.count) { calculate() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("What Zoon is learning about your response")
                .font(Theme.numeral(25))
            Text("These are observational summaries from your own history. Zoon withholds them until there is enough repeated data and never treats them as medical conclusions.")
                .font(Theme.text(13)).foregroundStyle(Theme.inkSecondary)
        }.glassCard()
    }

    @ViewBuilder private var resilienceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Sleep resilience", subtitle: "How quickly your recent range returned after repeated disruptions.", systemImage: "arrow.uturn.forward.circle")
            if resilience.isEmpty {
                learningMessage("Log at least two travel, stressful, or major timing disruptions. Zoon also needs five earlier nights and two stable nights after each one.")
            } else {
                ForEach(resilience) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.sentence).font(Theme.label(14, weight: .semibold))
                        Text("Median across \(result.disruptions) supported disruptions; recovery requires two consecutive nights in range.")
                            .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
        }.glassCard()
    }

    @ViewBuilder private var circadianSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Circadian response", subtitle: "Your timing after morning daylight, compared with explicitly logged no-daylight mornings.", systemImage: "sun.horizon.fill")
            if let circadian {
                Text(circadian.sentence).font(Theme.label(15, weight: .semibold))
                Text("Approximate uncertainty ±\(circadian.uncertaintyMinutes) minutes · \(circadian.daylightNights) daylight nights · \(circadian.comparisonNights) comparison nights")
                    .font(Theme.evidence).foregroundStyle(Theme.inkSecondary)
                Text("This is an association. Other differences between those days may explain it.")
                    .font(Theme.evidence).foregroundStyle(Theme.inkTertiary)
            } else {
                learningMessage("Answer Morning daylight in the Journal on at least six yes and six no days. Zoon will stay quiet if the difference is small.")
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

struct ProactiveZoonCard: View {
    let items: [PersonalLearning.ProactiveItem]

    var body: some View {
        if let first = items.first {
            NavigationLink { PersonalLearningView() } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Worth checking", systemImage: "bell.badge.fill")
                        .font(Theme.kicker).foregroundStyle(Theme.Family.attention)
                    Text(first.title).font(Theme.label(16, weight: .semibold))
                    Text(first.detail).font(Theme.text(12)).foregroundStyle(Theme.inkSecondary)
                    Text(first.action).font(Theme.label(12, weight: .semibold)).foregroundStyle(Theme.Family.sleep)
                }.frame(maxWidth: .infinity, alignment: .leading).glassCard()
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens personal learning details")
        }
    }
}

#Preview { NavigationStack { PersonalLearningView() }.zoonPreviewEnvironment() }
