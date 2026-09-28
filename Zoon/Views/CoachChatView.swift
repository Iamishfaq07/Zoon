import SwiftUI

/// Ask about tonight, in your own words.
///
/// Pushed from the Sleep detail screen — the one place the app already has a
/// finished night to hand the model as context.
struct CoachChatView: View {

    let night: SleepNightFeatures
    /// A suggested question tapped from `CoachTabView`, sent automatically
    /// once the chat starts. `nil` for the plain "Start a conversation"
    /// entry point, which opens to an empty composer as before.
    var initialPrompt: String? = nil
    /// The chart point this conversation was opened from, when it was.
    /// Its `question` is asked automatically and its `context` seeds the
    /// session, so the first reply is about the point that was tapped rather
    /// than about the night in general.
    var chartQuestion: ChartQuestion? = nil
    /// Coach Tab uses today/trends. Sleep Detail uses the opened night.
    var contextMode: CoachContextMode = .today

    @Environment(SleepDataCoordinator.self) private var coordinator
    @Environment(UserPreferences.self) private var preferences
    @Environment(NapStore.self) private var naps
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chat = CoachChat()
    @State private var evidence: CoachEvidence?
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    /// Guards against re-sending `initialPrompt` if `.task` reruns on this
    /// same view instance (e.g. a state change that re-triggers it) --
    /// without this, a tapped suggestion could submit itself twice.
    @State private var hasSubmittedInitialPrompt = false
    /// Which assistant messages currently have their evidence chip expanded
    /// -- see `evidenceChip(_:messageID:)`.
    @State private var expandedEvidenceIDs: Set<UUID> = []
    /// Bumped to force a fresh read of `chat.unavailabilityReason` -- see
    /// the polling `.task(id:)` below.
    @State private var availabilityPollTick = 0
    /// True for a moment right after "Check again" is tapped. The check
    /// itself is a live property read, effectively instant -- with no state
    /// change to watch for, a report came back that tapping the button
    /// looked like it did nothing at all when the answer was still the same
    /// "still downloading." This gives the tap itself a visible response,
    /// independent of whatever the fresh answer turns out to be.
    @State private var isCheckingNow = false

    var body: some View {
        VStack(spacing: 0) {
            engineBanner
                .padding(.horizontal, 16)
                .padding(.top, 8)
            if chat.appleIntelligenceBecameReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Intelligence is ready. Start a new enhanced conversation?")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    HStack(spacing: 8) {
                        Button("Start enhanced conversation") {
                            chat.startEnhancedConversation()
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Keep current conversation") {
                            chat.dismissUpgradePrompt()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            transcript
            if let pending = chat.pendingAction {
                confirmation(pending)
            }
            composer
        }
        .nightBackground()
        .navigationTitle("Ask Zoon")
        .navigationBarTitleDisplayMode(.inline)
        // The composer owns the bottom edge; the floating tab bar sat on it.
        .hidesFloatingTabBar()
        .task {
            let frozen = CoachEvidence(night: night, history: coordinator.recentNights)
            evidence = frozen
            chat.evidence = frozen
            // Every number a tool answer contains comes from here. The model
            // is never asked for one, which is what makes "what is my
            // recovery" a `RecoveryScore` read rather than prose about one.
            let runner = CoachToolRunner(
                coordinator: coordinator, preferences: preferences, naps: naps
            )
            chat.runTool = { await runner.run($0) }
            chat.start(
                nightSummary: night.summaryForLLM,
                contextDigest: coordinator.coachContextDigest(),
                chartQuestion: chartQuestion,
                engine: preferences.preferredEngine,
                contextMode: chartQuestion == nil ? contextMode : .trend
            )
            // The chart's own question wins over a tapped suggestion: this
            // screen was opened *by* that point, and asking anything else
            // first would answer a question nobody asked.
            guard let prompt = chartQuestion?.question ?? initialPrompt, !hasSubmittedInitialPrompt else { return }
            hasSubmittedInitialPrompt = true
            await chat.send(prompt)
        }
        // A real report: this screen could show "the on-device model is
        // still downloading" and stay stuck on that message indefinitely --
        // `unavailabilityReason` reads live system state, not anything
        // `@Observable`-tracked, so nothing told this view to redraw once
        // the download actually finished. Polling only while the reason is
        // specifically the transient one (see `isTransientlyUnavailable`)
        // means a genuinely ineligible device or Apple Intelligence being
        // off doesn't spin forever for no reason -- it naturally stops
        // re-arming once the state resolves to something else or to
        // available.
        .task(id: availabilityPollTick) {
            // No session to open here: `CoachChat` builds one per question.
            chat.noteAvailabilityChange()
            guard chat.unavailabilityReason != nil, chat.isTransientlyUnavailable else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            availabilityPollTick += 1
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                CascadeStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty && !chat.isResponding {
                        starter
                    }
                    ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                        bubble(message, question: precedingQuestion(before: index))
                            .id(message.id)
                    }
                    if chat.isResponding {
                        ThinkingDots(reduceMotion: reduceMotion)
                            .id("thinking")
                    } else if chat.messages.last?.role == .assistant, chat.pendingAction == nil {
                        followUps
                    }
                }
                .padding()
            }
            .onChange(of: chat.messages.count) {
                guard let last = chat.messages.last else { return }
                withAnimation(reduceMotion ? nil : Motion.value) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    /// User turns stay a bubble -- that's the normal, expected shape for your
    /// own typed input. Zoon's answers deliberately aren't: the redesign spec
    /// singles out "Coach should not look like generic iMessage/ChatGPT
    /// bubbles" specifically for the app's *responses*, so those render as an
    /// editorial block (a small attribution label, plain text, no bubble
    /// shape) instead of a mirrored bubble on the opposite side.
    /// The user turn an answer is responding to, which is what decides
    /// whether a chart is relevant. Read from the transcript rather than
    /// asked of the model -- see `CoachDataAnswer`.
    private func precedingQuestion(before index: Int) -> String? {
        chat.messages[..<index].last { $0.role == .user }?.text
    }

    @ViewBuilder
    private func bubble(_ message: CoachChat.Message, question: String?) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(Theme.text(14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.Metric.sleep.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label(message.source == .appleIntelligence ? "Zoon · Apple Intelligence" : "Zoon",
                          systemImage: message.source == .appleIntelligence ? "apple.intelligence" : "sparkles")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Theme.Metric.sleep)
                    // Confidence, the third of the redesign spec's four
                    // structured elements -- computed by CoachChat.Message,
                    // not self-reported by the model
                    // (see its doc comment for why). "Recorded evidence" vs "General"
                    // rather than a numeric score: the only thing this can
                    // honestly claim to know is whether the answer is tied
                    // to one of your own numbers, not how right it is.
                    if let confidence = message.confidence {
                        StatusPill(
                            text: confidence == .grounded ? "Recorded evidence" : "General",
                            tint: confidence == .grounded ? Theme.Metric.sleep : Theme.inkSecondary
                        )
                    }
                    // Which stretch of time the answer is about (audit
                    // §17.6), so "last night" and "recent nights" answers
                    // are never mistaken for each other.
                    if let timeframe = message.timeframe {
                        Text(timeframe)
                            .font(Theme.label(11, weight: .semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .accessibilityLabel("About \(timeframe)")
                    }
                }
                // Direct Answer.
                Text(message.text)
                    .font(Theme.text(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // Chart. Rendered from the app's own engines when the
                // question was about a metric Zoon tracks, so an answer
                // about HRV shows the same baseline lane Body Signals
                // shows rather than describing it in words. Draws nothing
                // when the question wasn't about a tracked metric.
                if let question {
                    CoachDataAnswer(question: question, evidence: evidence ?? CoachEvidence(night: night, history: []))
                }
                // Evidence: which number in tonight's data (or the standing-
                // pattern digest) the answer is actually grounded in, set
                // apart from the sentence itself rather than folded into the
                // prose -- the redesign spec's ask for a coach that shows
                // its work. Tappable: reveals what "grounded" means here,
                // since the chip alone doesn't say why that number is the
                // evidence for this answer.
                if let groundedIn = message.groundedIn, !groundedIn.isEmpty {
                    evidenceChip(groundedIn, messageID: message.id)
                }
                // Best Action, the fourth structured field -- only shown
                // when the model actually produced one; most factual
                // questions ("why was my HRV low?") don't call for an
                // action, and an invented one would be worse than none.
                if let bestAction = message.bestAction, !bestAction.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.Metric.sleep)
                        Text(bestAction)
                            .font(Theme.text(12, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A tappable evidence chip -- toggles a one-line explanation of what
    /// "grounded" means for this answer, per message so two answers in the
    /// same transcript can be expanded independently.
    private func evidenceChip(_ text: String, messageID: UUID) -> some View {
        let isExpanded = expandedEvidenceIDs.contains(messageID)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                Haptics.tap()
                if isExpanded {
                    expandedEvidenceIDs.remove(messageID)
                } else {
                    expandedEvidenceIDs.insert(messageID)
                }
            } label: {
                Label("Why Zoon said this", systemImage: "list.bullet.rectangle")
                    .font(Theme.text(11, weight: .medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.neutral(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the recorded numbers this answer used")

            if isExpanded {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Only facts Zoon already computed. Not a diagnosis.")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.tap, value: isExpanded)
    }

    /// The confirm step for anything that changes something.
    ///
    /// A bar above the composer rather than buttons inside the transcript:
    /// the proposal is the one thing to act on, it must not scroll away, and
    /// the composer stays reachable so "actually, make it twenty minutes" is
    /// still possible — sending anything new discards the proposal, which is
    /// what stops a stale Confirm sitting under an unrelated question.
    private func confirmation(_ pending: CoachChat.PendingAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pending.prompt)
                .font(Theme.label(14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            // Stacked at accessibility sizes: two buttons side by side is
            // where a confirm and a cancel start wrapping into each other,
            // and those are the two words that must never be misread.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { confirmButtons }
                VStack(spacing: 10) { confirmButtons }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Metric.sleep.opacity(0.14))
        .overlay(alignment: .top) { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var confirmButtons: some View {
        Button("Cancel") {
            Haptics.tap()
            chat.cancelPendingAction()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)

        Button("Confirm") {
            Haptics.success()
            Task { await chat.confirmPendingAction() }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your sleep…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { submit() }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.neutral(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(inputFocused ? Theme.Metric.sleep.opacity(0.6) : Theme.cardStroke, lineWidth: 1)
                )

            Button {
                submit()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.inkSecondary : Theme.Metric.sleep)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.isResponding)
            // Without this VoiceOver reads the SF Symbol's name -- "arrow up
            // circle fill" -- which describes the glyph rather than what
            // pressing it does.
            .accessibilityLabel("Send")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isResponding else { return }
        input = ""
        Haptics.tap()
        Task { await chat.send(text) }
    }

    private func ask(_ question: String) {
        guard !chat.isResponding else { return }
        Haptics.select()
        Task { await chat.send(question) }
    }

    // MARK: - Engine, starters, follow-ups

    /// Which engine is answering, stated up front -- and when it is not
    /// Apple Intelligence, why not and what would change it.
    @ViewBuilder
    private var engineBanner: some View {
        let onModel = chat.conversationEngine == .appleIntelligence
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: onModel ? "apple.intelligence" : "cpu")
                .font(Theme.text(15, weight: .semibold))
                .foregroundStyle(onModel ? Theme.Metric.sleep : Theme.inkSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(onModel ? "Apple Intelligence · on this iPhone" : "Zoon's local answers")
                    .font(Theme.label(13, weight: .semibold))
                Text(engineDetail(onModel: onModel))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.neutral(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func engineDetail(onModel: Bool) -> String {
        if onModel {
            return "Written from your own numbers. Nothing leaves the phone."
        }
        if preferences.preferredEngine == .ruleBased {
            return "You chose Rules in Settings. Choose Apple Intelligence there for conversational answers."
        }
        return chat.unavailabilityReason.map { "\($0) Answers come from Zoon's rules until then." }
            ?? "Answers come from Zoon's rules."
    }

    /// Questions to start from, so an empty chat is an invitation rather
    /// than a blank field.
    private var starter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything about your sleep")
                .font(Theme.label(18, weight: .bold))
            Text("Zoon answers from your own nights and tonight's plan.")
                .font(Theme.text(13))
                .foregroundStyle(Theme.inkSecondary)
            FlowLayout(spacing: 8) {
                ForEach(Self.starterQuestions, id: \.self) { question in
                    suggestionChip(question)
                }
            }
        }
        .padding(.top, 8)
    }

    /// Three questions not yet asked, after each answer.
    private var followUps: some View {
        let asked = Set(chat.messages.filter { $0.role == .user }.map { $0.text.lowercased() })
        let pool = Self.followUpQuestions.filter { !asked.contains($0.lowercased()) }
        let offset = pool.isEmpty ? 0 : chat.messages.count % pool.count
        let picks = Array((pool[offset...] + pool[..<offset]).prefix(3))
        return VStack(alignment: .leading, spacing: 8) {
            Text("Ask next")
                .font(Theme.label(11, weight: .semibold))
                .foregroundStyle(Theme.inkSecondary)
            FlowLayout(spacing: 8) {
                ForEach(picks, id: \.self) { question in
                    suggestionChip(question)
                }
            }
        }
        .padding(.top, 4)
    }

    private func suggestionChip(_ question: String) -> some View {
        Button {
            ask(question)
        } label: {
            Text(question)
                .font(Theme.text(13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.Metric.sleep.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(Theme.Metric.sleep.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(chat.isResponding)
    }

    static let starterQuestions = CoachSuggestionProvider.chatStarters
    static let followUpQuestions = CoachSuggestionProvider.chatFollowUps

    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(Theme.inkSecondary)
            Text(reason)
                .font(Theme.text(14))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            // Only when waiting might actually help (see
            // `isTransientlyUnavailable`) -- a button that can't change
            // anything (device ineligible, Apple Intelligence off) would be
            // worse than none, since tapping it would look like it does
            // something and never does.
            if chat.isTransientlyUnavailable {
                // Apple Intelligence's on-device model download is a
                // multi-gigabyte OS-level process this app has no visibility
                // into or control over -- it can genuinely take a long time,
                // especially on cellular or a first-time setup. Saying so
                // plainly is more honest than a bare "Try again" that implies
                // the app itself might be able to resolve it faster.
                Text("This can take a while depending on your connection. Zoon checks automatically every few seconds.")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.inkTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Haptics.tap()
                    isCheckingNow = true
                    availabilityPollTick += 1
                    Task {
                        try? await Task.sleep(nanoseconds: 600_000_000)
                        isCheckingNow = false
                    }
                } label: {
                    if isCheckingNow {
                        Label("Checking…", systemImage: "arrow.clockwise")
                    } else {
                        Label("Check again", systemImage: "arrow.clockwise")
                    }
                }
                .font(Theme.label(13, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(Theme.Metric.sleep)
                .disabled(isCheckingNow)
            }
            Spacer()
        }
    }
}

/// Three dots that pulse while an answer is being written. Still when
/// Reduce Motion is on; the words say the same thing.
private struct ThinkingDots: View {
    let reduceMotion: Bool
    @State private var phase = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Theme.Metric.sleep)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.8 : (phase ? 1 : 0.3))
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                            value: phase
                        )
                }
            }
            Text("Zoon is thinking")
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(.vertical, 6)
        .onAppear { phase = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoon is writing an answer")
    }
}

#Preview("Coach Chat") {
    NavigationStack { CoachChatView(night: MockData.goodNight) }
        .zoonPreviewEnvironment()
}
