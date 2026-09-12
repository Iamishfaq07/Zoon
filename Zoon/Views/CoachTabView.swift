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
    @Environment(UserPreferences.self) private var preferences
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
                    GatheringNights(
                        title: "No night yet",
                        message: "Zoon needs last night's data before there's anything to ask about.",
                        nights: 0,
                        needed: 1
                    )
                }
            }
            .stateTransition(coordinator.state.context?.night != nil)
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

    /// V8: not a chat landing page but an analytical one -- This week from
    /// Cause Finder, then Today, Trend, Discovery, Plan, then the open
    /// composer. The data-driven picker `suggestions(for:)` is unchanged;
    /// it feeds the Today slot.
    private func landing(_ night: SleepNightFeatures) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                    .entrance(0)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(categories(for: night).enumerated()), id: \.element.kicker) { index, category in
                        if index > 0 { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
                        NavigationLink {
                            CoachChatView(night: night, initialPrompt: category.question)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.kicker)
                                    .font(Theme.kicker)
                                    .tracking(1.0)
                                    .textCase(.uppercase)
                                    .foregroundStyle(category.tint)
                                HStack(alignment: .firstTextBaseline) {
                                    Text(category.question)
                                        .font(Theme.label(16, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.up.right")
                                        .font(Theme.text(12, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(category.kicker): \(category.question)")
                        .accessibilityHint("Ask Zoon")
                    }
                }
                // Cascaded as one block rather than per row: the rows are
                // separated by hairlines that are not themselves in the
                // ForEach body's animated view, so staggering the rows would
                // leave the dividers hanging in empty space.
                .entrance(1)

                NavigationLink {
                    CoachChatView(night: night)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Theme.Family.sleep)
                        Text("Ask something else in your own words")
                            .font(Theme.label(14, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.text(11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .entrance(2)

                engineCard
                    .entrance(3)

                capabilityCard
                    .entrance(4)
            }
            .padding()
        }
    }

    private struct Category {
        let kicker: String
        let question: String
        let tint: Color
    }

    /// This week's question is duration-only, from Cause Finder's strongest
    /// tag. Today's comes from the existing signal-driven picker; Trend,
    /// Discovery and Plan read the same history the Insights tab does.
    private func categories(for night: SleepNightFeatures) -> [Category] {
        let today = suggestions(for: night).first ?? "How did I sleep last night?"

        let nights = coordinator.recentNights
        let trend: String = nights.count >= 14 ? "What changed this month?" : "What's Zoon learning about my sleep so far?"

        let findings = JournalCorrelator().findings(from: coordinator.journalObservations())
        let week = WeeklyQuestion.make(
            strongestTag: findings.first?.tag.label,
            deltaMinutes: findings.first?.pairDeltaMedian
        )
        let discovery: String = {
            if let strongest = findings.first {
                return "Is \(strongest.tag.label.lowercased()) actually affecting me?"
            }
            return "Which of my habits might be affecting my sleep?"
        }()

        let plan: String = (night.sleepDebtMinutes ?? 0) >= 45
            ? "How should I catch up on sleep this week?"
            : "How should I prepare for tomorrow?"

        return [
            Category(kicker: "This week", question: week.question, tint: Theme.Family.sleep),
            Category(kicker: "Today", question: today, tint: Theme.Family.sleep),
            Category(kicker: "Trend", question: trend, tint: Theme.Family.recovery),
            Category(kicker: "Discovery", question: discovery, tint: Theme.Family.bodySignals),
            Category(kicker: "Plan", question: plan, tint: Theme.Family.circadian)
        ]
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
    /// Which engine answers, chosen here rather than buried in Settings.
    ///
    /// This picker lived in Settings, three screens away from the only place
    /// its effect is visible. Someone wondering why the coach sounds
    /// mechanical had no reason to look for it there, and someone who did
    /// find it got no hint that the choice might not be available to them at
    /// all.
    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Who answers", systemImage: "cpu")

            Picker(
                "Insight engine",
                selection: Binding(
                    get: { preferences.preferredEngine },
                    set: { coordinator.setEngine($0) }
                )
            ) {
                ForEach(UserPreferences.EngineChoice.shippingCases) { choice in
                    Text(choice.displayName).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            Text(preferences.preferredEngine.detail)
                .font(Theme.text(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The requirements, stated whichever engine is selected.
            //
            // Apple Intelligence is not a preference that works everywhere:
            // it needs hardware most iPhones in use do not have. Saying so
            // before it is picked is the difference between "I chose it and
            // nothing happened" and "I can't have this yet" -- and Rules is a
            // real answer on every device, not a consolation.
            Label(
                "Apple Intelligence needs iOS 26 or later on an iPhone 15 Pro, "
                    + "iPhone 16, or newer. Rules answers on any device.",
                systemImage: "info.circle"
            )
            .font(Theme.text(11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)

            // Why it cannot run here, when it cannot.
            if preferences.preferredEngine == .appleIntelligence,
               let reason = CoachChat.unavailabilityReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.Metric.recoveryMid)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Why a model that *can* run fell back anyway.
            if preferences.preferredEngine == .appleIntelligence,
               CoachChat.unavailabilityReason == nil,
               let reason = FoundationModelDiagnostics.shared.lastFailureReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.Metric.recoveryLow)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "What Zoon can see", systemImage: "eye")

            if let reason = CoachChat.unavailabilityReason {
                Label("Local answers are ready. Optional generated explanations: " + reason, systemImage: "checkmark.circle")
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
