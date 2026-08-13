import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#else
#warning("FoundationModels unavailable: the coach chat will show its unavailable state in this build.")
#endif

/// A conversation about tonight's data, not a single generated line.
///
/// `FoundationModelInsightEngine` produces one fixed-shape insight per night.
/// This is the other half of what Oura's Advisor and Whoop's coach do: a
/// place to ask a follow-up. "Why was my HRV low?" or "should I train today?"
/// in your own words, answered from the same numbers already on screen —
/// nothing new is sent anywhere, because there's still nowhere for it to go.
///
/// Same gating as `FoundationModelInsightEngine`, same reason: the whole
/// surface sits behind `#if canImport(FoundationModels)` so the file compiles
/// on any SDK, and runtime availability is checked separately for a device
/// that doesn't support Apple Intelligence even on iOS 26.
@MainActor
@Observable
final class CoachChat {

    struct Message: Identifiable, Sendable {
        enum Role { case user, assistant }
        let id: UUID
        let role: Role
        var text: String

        init(id: UUID = UUID(), role: Role, text: String) {
            self.id = id
            self.role = role
            self.text = text
        }
    }

    private(set) var messages: [Message] = []
    private(set) var isResponding = false

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "CoachChat")

    #if canImport(FoundationModels)
    // `@Observable`'s macro synthesises accessors for every stored property,
    // and it cannot do that for one individually marked `@available` — the
    // synthesized code would need to be conditionally available while the
    // class itself isn't, which the compiler rejects outright. Boxing the
    // iOS-26-only type behind `Any?` sidesteps the property needing its own
    // availability annotation; the cast at each use site is where the real
    // `#available` check still lives.
    private var session: Any?
    #endif

    var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return "Needs iOS 26 or later." }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in Settings to use this."
        case .unavailable(.modelNotReady): return "The on-device model is still downloading. Try again shortly."
        case .unavailable: return "The on-device model isn't available right now."
        }
        #else
        return "This build was compiled without the Foundation Models framework."
        #endif
    }

    var isAvailable: Bool { unavailabilityReason == nil }

    /// Starts a new session with tonight's numbers as context the model
    /// already has, so the first question doesn't have to restate them.
    func start(nightSummary: String) {
        messages = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            session = LanguageModelSession(instructions: Self.instructions(nightSummary: nightSummary))
        }
        #endif
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(Message(role: .user, text: trimmed))
        isResponding = true
        defer { isResponding = false }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), let session = session as? LanguageModelSession else {
            messages.append(Message(role: .assistant, text: unavailabilityReason ?? "Not available."))
            return
        }

        // Streamed rather than a single `respond(to:)` await: a Foundation
        // Models generation can take a few seconds, and a bubble that fills
        // in as it's written reads as "thinking out loud" the way the other
        // on-device coaches in this category do, instead of a long pause
        // followed by a paragraph appearing all at once. The bubble is only
        // added to `messages` once the first token arrives, so `isResponding`
        // (and the "Thinking…" row it drives in CoachChatView) still owns the
        // gap before generation starts producing anything.
        var assistantIndex: Int?
        do {
            let stream = session.streamResponse(to: trimmed, options: GenerationOptions(temperature: 0.4))
            for try await partial in stream {
                let content = partial.content
                if let index = assistantIndex {
                    messages[index].text = content
                } else if !content.isEmpty {
                    messages.append(Message(role: .assistant, text: content))
                    assistantIndex = messages.count - 1
                }
            }

            // Same backstop FoundationModelInsightEngine applies to the
            // nightly insight: the instructions forbid diagnostic language,
            // but that's a request the model may not honour on every turn,
            // and a chat has many more turns than one fixed-shape generation
            // to get it wrong on. A failed check here can't fall back to a
            // rules engine the way the nightly insight can -- there's no
            // rule-based conversation to hand off to -- so it shows a plain
            // refusal instead of the raw response. Checked once, on the
            // final accumulated text, rather than on every partial snapshot:
            // a half-generated sentence can trip the guard on words it would
            // never end up containing once complete.
            if let index = assistantIndex, DiagnosticLanguageGuard.rejects(messages[index].text) {
                logger.notice("Chat response failed the diagnostic-language check; not shown")
                messages[index].text = "I can't help with that one -- ask me something about tonight's numbers instead."
            } else if assistantIndex == nil {
                messages.append(Message(
                    role: .assistant,
                    text: "Couldn't generate a response just then. Try asking again."
                ))
            }
        } catch {
            logger.error("Chat generation failed: \(error.localizedDescription, privacy: .public)")
            let failureText = "Couldn't generate a response just then. Try asking again."
            if let index = assistantIndex {
                messages[index].text = failureText
            } else {
                messages.append(Message(role: .assistant, text: failureText))
            }
        }
        #else
        messages.append(Message(role: .assistant, text: unavailabilityReason ?? "Not available."))
        #endif
    }

    /// Same behavioural contract as `FoundationModelInsightEngine.instructions`
    /// — no invented causes, no diagnosis — extended to hold across a whole
    /// conversation rather than one generation.
    private static func instructions(nightSummary: String) -> String {
        """
        You are a sleep coach. The user is asking about one specific night,
        summarised below. Answer only from this data — never invent a number,
        a cause, or a comparison you weren't given.

        Never diagnose a medical condition. Never mention sleep apnea, insomnia,
        or any other diagnosis by name. If asked something the data can't
        answer, say so plainly rather than guessing.

        Keep answers to two or three sentences. This is a quick check-in, not
        an essay.

        Tonight's data:
        \(nightSummary)
        """
    }
}
