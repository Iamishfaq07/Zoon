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
        let id = UUID()
        let role: Role
        let text: String
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
        do {
            let response = try await session.respond(
                to: trimmed,
                options: GenerationOptions(temperature: 0.4)
            )
            messages.append(Message(role: .assistant, text: response.content))
        } catch {
            logger.error("Chat generation failed: \(error.localizedDescription, privacy: .public)")
            messages.append(Message(
                role: .assistant,
                text: "Couldn't generate a response just then. Try asking again."
            ))
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
