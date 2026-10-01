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
    /// Capture only: the `-zoonAsk` question, pushed as a chat once a night
    /// has loaded. See `LaunchOptions.coachQuestion`.
    @State private var launchQuestion: String?
    @State private var askedAtLaunch = false

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
            .onChange(of: coordinator.state.context != nil, initial: true) { _, hasNight in
                guard hasNight, !askedAtLaunch, let question = LaunchOptions.coachQuestion else { return }
                askedAtLaunch = true
                launchQuestion = question
            }
            .navigationDestination(item: $launchQuestion) { question in
                if let night = coordinator.state.context?.night {
                    CoachChatView(night: night, initialPrompt: question)
                }
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
                                Label(category.kicker, systemImage: category.symbol)
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
                                        .foregroundStyle(Theme.inkTertiary)
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
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .foregroundStyle(Theme.Family.sleep)
                        Text("Ask something else in your own words")
                            .font(Theme.label(14, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(Theme.text(11, weight: .semibold))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(14)
                    .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .entrance(2)

                // What the coach is working from, as real entry points.
                // These answer "why does it say that", which is a question
                // about the coach -- so they belong on the coach's own tab,
                // not at the bottom of the charts tab.
                // Five tiles for five screens became two tiles for the two
                // hubs that now hold them.
                ExploreGrid(title: "How Zoon knows you") {
                    ExploreTile(
                        title: "Your patterns",
                        subtitle: "What goes with your nights",
                        symbol: "checkmark.seal.fill",
                        tint: Theme.Family.recovery
                    ) { PatternsHub(initial: .proven) }

                    ExploreTile(
                        title: "Your data",
                        subtitle: "What Zoon has to go on",
                        symbol: "square.stack.3d.up.fill",
                        tint: Theme.Family.bodySignals
                    ) { DataHub() }
                }
                .entrance(3)

                engineCard
                    .entrance(4)
            }
            .padding()
        }
    }

    private struct Category {
        let kicker: String
        let question: String
        let tint: Color
        var symbol: String = "sparkles"
    }

    /// This week's question is duration-only, from Cause Finder's strongest
    /// tag. Today's comes from the existing signal-driven picker; Trend,
    /// Discovery and Plan read the same history the Insights tab does.
    private func categories(for night: SleepNightFeatures) -> [Category] {
        let today = suggestions(for: night).first ?? "How did I sleep last night?"

        let nights = coordinator.recentNights
        let trend: String = nights.count >= 14 ? "What changed this month?" : "What's Zoon learning about my sleep so far?"

        let findings = JournalCorrelator().findings(from: coordinator.journalObservations(), catalog: coordinator.behaviorCatalog)
        let week = WeeklyQuestion.make(
            strongestTag: findings.first?.label,
            deltaMinutes: findings.first?.pairDeltaMedian
        )
        let discovery: String = {
            if let strongest = findings.first {
                return "Is \(strongest.label.lowercased()) actually affecting me?"
            }
            return "Which of my habits might be affecting my sleep?"
        }()

        // The shortfall now, last night included -- see
        // `DayContext.shortfallNowMinutes`.
        let plan: String = (coordinator.state.context?.shortfallNowMinutes ?? night.sleepDebtMinutes ?? 0) >= 45
            ? "How should I catch up on sleep this week?"
            : "How should I prepare for tomorrow?"

        return [
            Category(kicker: "This week", question: week.question, tint: Theme.Family.sleep, symbol: "calendar"),
            Category(kicker: "Today", question: today, tint: Theme.Family.sleep, symbol: "sun.max"),
            Category(kicker: "Trend", question: trend, tint: Theme.Family.recovery, symbol: "chart.line.uptrend.xyaxis"),
            Category(kicker: "Discovery", question: discovery, tint: Theme.Family.bodySignals, symbol: "magnifyingglass"),
            Category(kicker: "Plan", question: plan, tint: Theme.Family.circadian, symbol: "moon.stars")
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
    /// Who answers and what it can see, as one card.
    ///
    /// These were two cards, and on a phone without Apple Intelligence the
    /// same reason appeared three times: as an info line and a warning in
    /// the first, and again in the second. One picker, one status line, one
    /// row of counts.
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
            .adaptiveSegmentedStyle()

            Text(preferences.preferredEngine.detail)
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            statusLine

            HStack(spacing: 16) {
                contextRow("\(coordinator.recentNights.count.pluralized("night"))", symbol: "bed.double.fill")
                contextRow("\(journalEntryCount.pluralized("journal entry", "journal entries"))", symbol: "square.and.pencil")
            }
        }
        .glassCard()
    }

    /// The one line that says whether answers stay on the phone, or why the
    /// chosen engine is not the one answering.
    @ViewBuilder
    private var statusLine: some View {
        if preferences.preferredEngine == .appleIntelligence, let reason = CoachChat.unavailabilityReason {
            Label("Rules is answering. \(reason)", systemImage: "exclamationmark.triangle")
                .font(Theme.text(12))
                .foregroundStyle(Theme.Metric.recoveryMid)
                .fixedSize(horizontal: false, vertical: true)
        } else if preferences.preferredEngine == .appleIntelligence,
                  let reason = FoundationModelDiagnostics.shared.lastFailureReason {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(Theme.text(12))
                .foregroundStyle(Theme.Metric.recoveryLow)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Answered on this device. Nothing leaves your phone.", systemImage: "lock.fill")
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ask Zoon")
                .font(Theme.heading(28))
            // Was "Your sleep intelligence assistant", which is a tagline:
            // true of the screen before any data existed and after all of it
            // was deleted. `capabilityCard` states the evidence base
            // properly, but it sits at the bottom, below every question --
            // so the one thing that decides whether an answer is worth
            // asking for arrived after the asking. This is the short form of
            // it, in the space the tagline was wasting.
            Text(evidenceLine)
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The two lines are one statement, and VoiceOver reading "Ask Zoon"
        // and the evidence line as separate elements invites swiping past
        // the half that qualifies the other.
        .accessibilityElement(children: .combine)
    }

    /// What the coach is actually reading from, in one line.
    ///
    /// Counts, not adjectives. "Reading 42 nights" is checkable against the
    /// card at the bottom of this screen; "your sleep intelligence
    /// assistant" is not checkable against anything.
    private var evidenceLine: String {
        let nights = coordinator.recentNights.count
        let history = "Reading \(nights) night\(nights == 1 ? "" : "s")"
        let entries = journalEntryCount
        let journal = entries > 0
            ? " and \(entries) journal entr\(entries == 1 ? "y" : "ies")"
            : ""
        // Named only when it is not available. When everything works, the
        // sentence is about the data, and a reassurance nobody asked for is
        // noise on a screen whose whole job is the next tap.
        let model = CoachChat.unavailabilityReason == nil
            ? ""
            : ". Generated explanations unavailable — answers are the local ones"
        return history + journal + ", on this device" + model + "."
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
        if let debt = coordinator.state.context?.shortfallNowMinutes ?? night.sleepDebtMinutes, debt >= 45 {
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
