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

    @Environment(SleepDataCoordinator.self) private var coordinator
    @State private var chat = CoachChat()
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
            if let reason = chat.unavailabilityReason {
                unavailable(reason)
            } else {
                transcript
                composer
            }
        }
        .nightBackground()
        .navigationTitle("Ask Zoon")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chat.start(nightSummary: night.summaryForLLM, contextDigest: coordinator.coachContextDigest())
            guard let initialPrompt, !hasSubmittedInitialPrompt else { return }
            hasSubmittedInitialPrompt = true
            await chat.send(initialPrompt)
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
            guard chat.unavailabilityReason != nil, chat.isTransientlyUnavailable else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            availabilityPollTick += 1
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if chat.messages.isEmpty {
                        Text("Ask anything about last night — \"why was my HRV low?\", \"should I train today?\"")
                            .font(Theme.text(13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    ForEach(chat.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if chat.isResponding {
                        HStack(spacing: 6) {
                            ProgressView().tint(.secondary)
                            Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: chat.messages.count) {
                guard let last = chat.messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    /// User turns stay a bubble -- that's the normal, expected shape for your
    /// own typed input. Zoon's answers deliberately aren't: the redesign spec
    /// singles out "Coach should not look like generic iMessage/ChatGPT
    /// bubbles" specifically for the app's *responses*, so those render as an
    /// editorial block (a small attribution label, plain text, no bubble
    /// shape) instead of a mirrored bubble on the opposite side.
    @ViewBuilder
    private func bubble(_ message: CoachChat.Message) -> some View {
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
                    Label("Zoon", systemImage: "sparkles")
                        .font(Theme.label(11, weight: .bold))
                        .foregroundStyle(Theme.Metric.sleep)
                    // Confidence, the third of the redesign spec's four
                    // structured elements -- computed by CoachChat.Message,
                    // not self-reported by the model
                    // (see its doc comment for why). "Grounded" vs "General"
                    // rather than a numeric score: the only thing this can
                    // honestly claim to know is whether the answer is tied
                    // to one of your own numbers, not how right it is.
                    if let confidence = message.confidence {
                        StatusPill(
                            text: confidence == .grounded ? "Grounded" : "General",
                            tint: confidence == .grounded ? Theme.Metric.sleep : .secondary
                        )
                    }
                }
                // Direct Answer.
                Text(message.text)
                    .font(Theme.text(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
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
                            .font(.caption2)
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
                Label(text, systemImage: "number")
                    .font(Theme.text(11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.neutral(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what this evidence means")

            if isExpanded {
                Text("The number above is the specific figure this answer is based on -- not a general statement.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isExpanded)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.neutral(0.06), in: Capsule())

            Button {
                let text = input
                input = ""
                Haptics.tap()
                Task { await chat.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Theme.Metric.sleep)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.isResponding)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(reason)
                .font(Theme.text(14))
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.tertiary)
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

#Preview("Coach Chat") {
    NavigationStack { CoachChatView(night: MockData.goodNight) }
        .zoonPreviewEnvironment()
}
