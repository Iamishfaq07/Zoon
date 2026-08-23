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
                Label("Zoon", systemImage: "sparkles")
                    .font(Theme.label(11, weight: .bold))
                    .foregroundStyle(Theme.Metric.sleep)
                Text(message.text)
                    .font(Theme.text(14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                // The structured half of the answer: which number in
                // tonight's data it's actually grounded in, set apart from
                // the sentence itself rather than folded into the prose --
                // the redesign spec's ask for a coach that shows its work,
                // not just a paragraph.
                if let groundedIn = message.groundedIn, !groundedIn.isEmpty {
                    Label(groundedIn, systemImage: "number")
                        .font(Theme.text(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.neutral(0.06), in: Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(reason)
                .font(Theme.text(14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

#Preview("Coach Chat") {
    NavigationStack { CoachChatView(night: MockData.goodNight) }
        .zoonPreviewEnvironment()
}
