import SwiftUI

/// Ask about tonight, in your own words.
///
/// Pushed from the Sleep detail screen — the one place the app already has a
/// finished night to hand the model as context.
struct CoachChatView: View {

    let night: SleepNightFeatures

    @State private var chat = CoachChat()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

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
        .task { chat.start(nightSummary: night.summaryForLLM) }
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

    private func bubble(_ message: CoachChat.Message) -> some View {
        HStack {
            if message.role == .assistant { Spacer(minLength: 40) }
            Text(message.text)
                .font(Theme.text(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == .user ? Theme.Metric.sleep.opacity(0.25) : Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            if message.role == .user { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: Capsule())

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
}
