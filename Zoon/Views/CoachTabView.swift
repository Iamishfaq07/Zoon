import SwiftUI

/// The Coach tab: a proper home for `CoachChatView` rather than a screen with
/// no way in.
///
/// `CoachChatView` already existed — a working chat wired to
/// `FoundationModelInsightEngine`'s on-device model — but nothing in the app
/// ever navigated to it. This is that navigation, plus the suggested-question
/// entry point a cold chat screen needs: nobody opens a blank text field and
/// knows what a sleep coach can even answer.
struct CoachTabView: View {

    @Environment(SleepDataCoordinator.self) private var coordinator
    /// Bumped to force a fresh read of `CoachChat.unavailabilityReason` in
    /// `capabilityCard` -- see the polling `.task(id:)` below. Same fix as
    /// `CoachChatView`'s: that reason reads live system state, not anything
    /// `@Observable`-tracked, so without this the banner could keep saying
    /// "the on-device model is still downloading" long after it finished.
    @State private var availabilityPollTick = 0

    var body: some View {
        NavigationStack {
            Group {
                if let night = coordinator.state.context?.night {
                    landing(night)
                } else {
                    ContentUnavailableView(
                        "No night yet",
                        systemImage: "sparkles",
                        description: Text("Zoon needs last night's data before there's anything to ask about.")
                    )
                }
            }
            .nightBackground()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .zoonGlobalToolbar()
            .task(id: availabilityPollTick) {
                guard CoachChat.unavailabilityReason != nil, CoachChat.isTransientlyUnavailable else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                availabilityPollTick += 1
            }
        }
    }

    private func landing(_ night: SleepNightFeatures) -> some View {
        ScrollView {
            VStack(spacing: Theme.stackSpacing) {
                header
                NavigationLink {
                    CoachChatView(night: night)
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Start a conversation", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(Theme.label(15, weight: .semibold))
                            .foregroundStyle(Theme.Metric.sleep)
                        Text("Ask anything about last night in your own words.")
                            .font(Theme.text(12))
                            .foregroundStyle(.secondary)
                    }
                    .glassCard()
                }
                .buttonStyle(PressableStyle())

                suggestedQuestions(night)
                capabilityCard
            }
            .padding()
        }
    }

    /// What the coach can actually see, and whether it can answer at all.
    ///
    /// Two things this screen didn't say before. First, availability: the
    /// on-device model needs iOS 26, an eligible device, and Apple
    /// Intelligence switched on, and when any of those is missing the only
    /// way to find out was to tap a question and land on a dead-end screen.
    /// Saying so up front costs one card and saves that round trip.
    ///
    /// Second, context. "Ask anything about last night" is vague about what
    /// "anything" is grounded in, and a coach that quietly knows 30 nights of
    /// history reads very differently from one that knows one. Both counts
    /// come from data already loaded for this screen.
    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What Zoon can see", systemImage: "eye")

            if let reason = CoachChat.unavailabilityReason {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.Metric.recoveryMid)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Answered on this device. Nothing leaves your phone.", systemImage: "lock.fill")
                    .font(Theme.text(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Theme.cardStroke)

            contextRow(
                "\(coordinator.recentNights.count) night\(coordinator.recentNights.count == 1 ? "" : "s") of history",
                symbol: "bed.double.fill"
            )
            contextRow(
                "\(journalEntryCount) journal entr\(journalEntryCount == 1 ? "y" : "ies")",
                symbol: "square.and.pencil"
            )
        }
        .glassCard()
    }

    private var journalEntryCount: Int {
        coordinator.journal.allEntries().count
    }

    private func contextRow(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(Theme.text(11))
                .foregroundStyle(Theme.Metric.sleep)
                .frame(width: 16)
            Text(text)
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ask Zoon")
                .font(Theme.numeral(28))
            Text("Your sleep intelligence assistant")
                .font(Theme.text(13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Data-driven prompts rather than a fixed list — a night with low HRV
    /// surfaces a question about HRV, a night with a debt spike surfaces a
    /// question about debt.
    ///
    /// Each one is passed to `CoachChatView` as `initialPrompt` and sent
    /// automatically once the chat starts -- previously the question text
    /// went nowhere: the link opened a blank composer with nothing typed
    /// or sent, so tapping a suggestion looked identical to tapping "Start a
    /// conversation".
    private func suggestedQuestions(_ night: SleepNightFeatures) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Based on last night", systemImage: "wand.and.sparkles")
            ForEach(suggestions(for: night), id: \.self) { question in
                NavigationLink {
                    CoachChatView(night: night, initialPrompt: question)
                } label: {
                    HStack {
                        Text(question)
                            .font(Theme.text(13))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(Theme.text(11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .glassCard(padding: 14)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// Picks up to three prompts whose underlying signal actually moved last
    /// night, falling back to evergreen questions when nothing stands out --
    /// a night with nothing unusual shouldn't read as a screen with nothing
    /// to say.
    private func suggestions(for night: SleepNightFeatures) -> [String] {
        var picked: [String] = []

        if let hrv = night.avgHRV, let baseline = night.hrv7DayAvg, baseline > 0 {
            let deviation = (hrv - baseline) / baseline
            if abs(deviation) > 0.1 {
                picked.append(deviation < 0 ? "Why was my HRV low last night?" : "Why was my HRV higher than usual?")
            }
        }
        if let debt = night.sleepDebtMinutes, debt >= 45 {
            picked.append("Am I behind on sleep?")
        }
        if night.wakeCount >= 3 {
            picked.append("Why did I wake up so much?")
        }

        let evergreen = [
            "Should I train today?",
            "What hurt my sleep last night?",
            "What should I do tonight?"
        ]
        for question in evergreen where picked.count < 3 {
            if !picked.contains(question) { picked.append(question) }
        }
        return Array(picked.prefix(3))
    }
}

#Preview("Coach Tab") {
    CoachTabView().zoonPreviewEnvironment()
}
