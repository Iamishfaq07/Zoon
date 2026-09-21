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
        /// The specific number(s) from tonight's data an assistant answer is
        /// grounded in -- e.g. "HRV 42ms vs your 7-day average of 58ms" --
        /// shown as its own element below the answer rather than folded into
        /// the prose. `nil` for user turns, and for an assistant answer that
        /// isn't tied to one specific figure.
        var groundedIn: String?
        /// One concrete next step the answer supports -- e.g. "Consider an
        /// earlier bedtime tonight." `nil` for user turns and for an answer
        /// that didn't call for one (most factual questions don't).
        var bestAction: String?

        /// Whether this answer is tied to a specific number from the user's
        /// own data, or is a general statement. Deliberately **not** the
        /// model's own self-assessment -- `FoundationModelInsightEngine`
        /// already establishes why a generated confidence claim can't be
        /// trusted (see its `validate(_:)`: "Generated text never claims
        /// high confidence. The rules can prove their claims; a model
        /// cannot."). This is the same principle applied to chat: computed
        /// structurally from whether `groundedIn` is actually present,
        /// never asked of the model.
        enum Confidence { case grounded, general }

        var confidence: Confidence? {
            guard role == .assistant else { return nil }
            return (groundedIn?.isEmpty == false) ? .grounded : .general
        }

        init(id: UUID = UUID(), role: Role, text: String, groundedIn: String? = nil, bestAction: String? = nil) {
            self.id = id
            self.role = role
            self.text = text
            self.groundedIn = groundedIn
            self.bestAction = bestAction
        }
    }

    /// A tool call that will change something, waiting for a yes.
    ///
    /// Held rather than executed. `CoachToolCatalog` has always said which
    /// kinds need confirming; nothing consulted it, so the catalogue decided
    /// nothing and no utterance had ever reached a tool at all.
    struct PendingAction: Identifiable, Sendable {
        let id: UUID
        let call: CoachToolCatalog.Call
        let prompt: String

        init(call: CoachToolCatalog.Call) {
            self.id = UUID()
            self.call = call
            self.prompt = call.confirmationPrompt ?? call.kind.summary
        }
    }

    /// Frozen for this transcript. Rules stays Rules even if Apple
    /// Intelligence finishes downloading mid-chat.
    private(set) var conversationEngine: UserPreferences.EngineChoice = .ruleBased
    private(set) var preferredEngine: UserPreferences.EngineChoice = .ruleBased
    /// True when the user asked for Apple Intelligence, this chat started on
    /// Rules because the model was not ready, and the model has since become
    /// available. The UI offers a new conversation; this one does not switch.
    private(set) var appleIntelligenceBecameReady = false

    var evidence: CoachEvidence?
    private(set) var messages: [Message] = []
    private(set) var isResponding = false
    private(set) var pendingAction: PendingAction?

    /// Runs a tool against the real engines. Supplied by the view layer,
    /// which owns them.
    ///
    /// A closure rather than a reference to the coordinator, so this type
    /// stays testable and so the one rule that matters is enforceable by
    /// construction: every number in a tool answer comes from here, and the
    /// model is never asked for one. Returning `nil` means the tool had
    /// nothing to report, which is a real answer -- Recovery before a night
    /// has been scored, a Tomorrow plan that does not exist yet -- and is
    /// said plainly rather than handed to the model to phrase around.
    var runTool: (@MainActor (CoachToolCatalog.Call) -> String?)?

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

    /// The shape a chat answer is constrained to produce -- see
    /// `FoundationModelInsightEngine.GeneratedInsight` for the same pattern
    /// applied to the nightly insight. `@Guide` descriptions carry real
    /// weight here since they're part of the prompt the framework builds.
    @available(iOS 26.0, *)
    @Generable
    struct ChatAnswer {
        @Guide(description: "Two short sentences explaining the supplied data. Do not state any quantities, numbers, dates, durations or percentages; the app renders those from its evidence catalog.")
        var answer: String

        @Guide(description: "Return exactly one evidence ID from the supplied catalog (sleep, timing, hrv, heart, debt). Never write a value or invent an ID. Empty if no evidence applies.")
        var groundedIn: String

        @Guide(description: "One concrete next step the user could take, only if the answer actually supports one -- e.g. 'Consider an earlier bedtime tonight.' Empty string if the answer doesn't call for an action (most factual questions don't).")
        var bestAction: String
    }
    #endif

    /// Why the coach can't answer, or `nil` when it can.
    ///
    /// Static because it reads no instance state, and because the Coach
    /// landing screen needs the answer *before* anyone opens a chat -- it
    /// warns up front rather than letting someone tap a question and land on
    /// a dead-end screen. Constructing a `CoachChat` just to ask would mean
    /// allocating a session holder per render for a question that doesn't
    /// need one.
    static var unavailabilityReason: String? {
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

    var unavailabilityReason: String? { Self.unavailabilityReason }

    var isAvailable: Bool { unavailabilityReason == nil }

    /// Whether the current unavailability might resolve on its own without
    /// the user leaving this screen -- the on-device model finishing a
    /// download in the background -- as opposed to device ineligibility or
    /// Apple Intelligence being off, which need the user to act elsewhere
    /// (a different device, or the Settings app) before anything changes.
    /// `CoachChatView` uses this to decide whether polling for a status
    /// change is worth doing at all.
    static var isTransientlyUnavailable: Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        if case .unavailable(.modelNotReady) = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    var isTransientlyUnavailable: Bool { Self.isTransientlyUnavailable }

    private func appendLocalAnswer(_ question: String) {
        let reply = evidence?.reply(to: question)
        messages.append(Message(
            role: .assistant,
            text: reply?.text ?? "Choose a recorded night to explore its sleep, timing, HRV, or resting heart rate.",
            groundedIn: reply?.evidence,
            bestAction: reply?.action
        ))
    }

    /// Executes the proposal the person just agreed to.
    ///
    /// Idempotent by construction: the pending action is cleared before the
    /// tool runs, so a double tap cannot log two coffees.
    func confirmPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        let result = runTool?(action.call)
        messages.append(Message(
            role: .assistant,
            text: result ?? "I could not do that."
        ))
    }

    /// Discards it. Nothing was done, and the transcript says so rather than
    /// going quiet, which would leave the proposal reading as accepted.
    func cancelPendingAction() {
        guard pendingAction != nil else { return }
        pendingAction = nil
        messages.append(Message(role: .assistant, text: "Cancelled. Nothing was changed."))
    }

    /// Starts a new session with tonight's numbers -- and, when there's
    /// enough history for one, `SleepDataCoordinator.coachContextDigest()`'s
    /// standing-pattern summary -- as context the model already has, so the
    /// first question doesn't have to restate them.
    /// - Parameter engine: the user's picker. Frozen for this transcript.
    /// - Parameter chartContext: `ChartQuestion.context` when the
    ///   conversation was opened from a point on a chart. Typed facts, never
    ///   an image of the chart: everything a model would have to guess from
    ///   a picture -- what the axis means, where the baseline sits, how many
    ///   nights it rests on -- is already computed and is handed over.
    func start(
        nightSummary: String,
        contextDigest: String? = nil,
        chartContext: String? = nil,
        engine: UserPreferences.EngineChoice = .ruleBased
    ) {
        messages = []
        pendingAction = nil
        appleIntelligenceBecameReady = false
        preferredEngine = engine
        conversationEngine = Self.frozenEngine(preferred: engine)
        pendingContext = Context(
            nightSummary: nightSummary,
            contextDigest: contextDigest,
            chartContext: chartContext
        )
        #if canImport(FoundationModels)
        session = nil
        if conversationEngine == .appleIntelligence {
            ensureSession()
        }
        #endif
    }

    /// Rules never opens a model. Apple Intelligence opens one only if it is
    /// available at conversation start. A later download does not attach a
    /// session to this transcript.
    static func frozenEngine(preferred: UserPreferences.EngineChoice) -> UserPreferences.EngineChoice {
        switch preferred {
        case .ruleBased, .localLLM:
            return .ruleBased
        case .appleIntelligence:
            return unavailabilityReason == nil ? .appleIntelligence : .ruleBased
        }
    }

    /// What a session needs to be built, kept so one can be built later.
    ///
    /// The model is often unavailable at the moment this screen opens --
    /// `.modelNotReady` while iOS is still downloading it -- and becomes
    /// available minutes later. Holding the context is what makes that
    /// recoverable without reopening the screen and losing the conversation.
    private struct Context {
        let nightSummary: String
        let contextDigest: String?
        let chartContext: String?
    }

    private var pendingContext: Context?

    /// Opens a model session if this conversation froze on Apple Intelligence
    /// and one is not already open. Never called for Rules. Never called to
    /// upgrade a Rules transcript after the model finishes downloading.
    func ensureSession() {
        #if canImport(FoundationModels)
        guard conversationEngine == .appleIntelligence else { return }
        guard session == nil, isAvailable, #available(iOS 26.0, *),
              let context = pendingContext else { return }
        session = LanguageModelSession(
            instructions: Self.instructions(
                nightSummary: context.nightSummary,
                contextDigest: context.contextDigest,
                chartContext: context.chartContext
            )
        )
        logger.notice("Opened a language model session")
        #endif
    }

    /// Poll from the view. If this chat is Rules because the model was not
    /// ready, surface a prompt to start a *new* conversation — do not switch.
    func noteAvailabilityChange() {
        guard preferredEngine == .appleIntelligence,
              conversationEngine == .ruleBased,
              Self.unavailabilityReason == nil else { return }
        appleIntelligenceBecameReady = true
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(Message(role: .user, text: trimmed))

        switch CoachIntentRouter.classify(trimmed) {
        case .greeting:
            pendingAction = nil
            messages.append(Message(role: .assistant, text: CoachIntentRouter.greetingReply()))
            return
        case .capabilities:
            pendingAction = nil
            messages.append(Message(role: .assistant, text: CoachIntentRouter.capabilitiesReply()))
            return
        case .thanks:
            pendingAction = nil
            messages.append(Message(role: .assistant, text: CoachIntentRouter.thanksReply()))
            return
        case .farewell:
            pendingAction = nil
            messages.append(Message(role: .assistant, text: CoachIntentRouter.farewellReply()))
            return
        case .cancel:
            if pendingAction != nil {
                cancelPendingAction()
            } else {
                pendingAction = nil
                messages.append(Message(role: .assistant, text: CoachIntentRouter.cancelReply()))
            }
            return
        case .tool(let call):
            pendingAction = nil
            if call.kind.requiresConfirmation {
                let action = PendingAction(call: call)
                pendingAction = action
                messages.append(Message(role: .assistant, text: action.prompt))
                return
            }
            if let answer = runTool?(call) {
                messages.append(Message(
                    role: .assistant,
                    text: answer,
                    groundedIn: evidenceID(for: call.kind)
                ))
                return
            }
            messages.append(Message(
                role: .assistant,
                text: "I do not have that yet. \(call.kind.summary)"
            ))
            return
        case .unknown:
            pendingAction = nil
        }

        isResponding = true
        defer { isResponding = false }

        #if canImport(FoundationModels)
        guard conversationEngine == .appleIntelligence else {
            appendLocalAnswer(trimmed)
            return
        }

        guard isAvailable, #available(iOS 26.0, *), let session = session as? LanguageModelSession else {
            appendLocalAnswer(trimmed)
            return
        }

        do {
            let catalogKeys = evidence?.catalog.keys.sorted().joined(separator: ", ") ?? "sleep, timing, hrv, heart, debt"
            let response = try await session.respond(
                to: trimmed + "\nEvidence catalog (only these IDs may be cited: \(catalogKeys)):\n" + (evidence?.promptCatalog ?? "None"),
                generating: ChatAnswer.self,
                options: GenerationOptions(temperature: 0)
            )
            let answer = response.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let grounding = response.content.groundedIn.trimmingCharacters(in: .whitespacesAndNewlines)
            let bestAction = response.content.bestAction.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !answer.isEmpty, CoachEvidence.allowsGeneratedProse(answer + " " + bestAction), !DiagnosticLanguageGuard.rejects("\(answer) \(grounding) \(bestAction)") else {
                logger.notice("Chat response was empty or failed the diagnostic-language check; using the local reply")
                appendLocalAnswer(trimmed)
                return
            }

            let cited: String?
            if grounding.isEmpty || grounding.lowercased() == "null" {
                cited = nil
            } else if let value = evidence?.catalog[grounding] {
                cited = value
            } else {
                logger.notice("Chat cited unknown evidence ID \(grounding, privacy: .public); using the local reply")
                appendLocalAnswer(trimmed)
                return
            }

            messages.append(Message(
                role: .assistant,
                text: answer,
                groundedIn: cited,
                bestAction: bestAction.isEmpty || bestAction.lowercased() == "null" ? nil : bestAction
            ))
        } catch {
            logger.error("Chat generation failed: \(error.localizedDescription, privacy: .public)")
            appendLocalAnswer(trimmed)
        }
        #else
        appendLocalAnswer(trimmed)
        #endif
    }

    private func evidenceID(for kind: CoachToolCatalog.Kind) -> String? {
        switch kind {
        case .getSleepScore: evidence?.catalog["sleep"]
        case .getShortfall: evidence?.catalog["debt"] ?? evidence?.catalog["sleep"]
        case .getTonight, .getTomorrow: evidence?.catalog["timing"]
        case .getRecovery, .getEnergy, .getMovement, .logCaffeine, .startNap, .prepareTomorrow, .setAlarm:
            nil
        }
    }

    /// Same behavioural contract as `FoundationModelInsightEngine.instructions`
    /// — no invented causes, no diagnosis — extended to hold across a whole
    /// conversation rather than one generation, and now over two data
    /// sources rather than one: tonight's own numbers, and (when there's
    /// enough history to build one) `contextDigest`'s standing patterns --
    /// this week vs last, the current regularity read, whatever Cause Finder
    /// has actually found. Without the digest, "has my recovery been
    /// improving?" had no honest answer available at all; the instructions
    /// below tell the model which questions each source can and can't settle.
    private static func instructions(
        nightSummary: String,
        contextDigest: String?,
        chartContext: String? = nil
    ) -> String {
        let digestSection = contextDigest.map {
            """


            LONGITUDINAL PATTERNS — use this for questions about trends, habits, or "usually"/"lately"; last night's facts above are still the only source for anything about last night specifically:
            \($0)
            """
        } ?? ""

        let chartSection = chartContext.map {
            """


            The user tapped a specific point on a chart. This is that point,
            described in full -- it is the only description of it you have,
            and every figure in it was measured, so do not restate it as an
            estimate or add figures of your own:
            \($0)
            """
        } ?? ""

        return """
        You are Zoon's on-device sleep coach.

        Answer conversational small talk conversationally. Greetings are greetings — never a sleep analysis.

        For health data, use only the facts below. Never invent a number, a cause, a comparison, a score, a bedtime, or a duration you were not given. If a question needs a source you don't have, say so plainly.

        Distinguish last night's facts from longer-term patterns. The CURRENT NIGHT FACTS section is the only source for last night. LONGITUDINAL PATTERNS are for "lately" / "usually" / trends.

        Never diagnose a medical condition. Never mention sleep apnea, insomnia, or any other diagnosis by name.
        Do not make a single metric prescribe the whole day.
        Keep answers to two or three sentences.
        Use one clear action only when the data actually supports one.

        CURRENT NIGHT FACTS:
        \(nightSummary)
        \(digestSection)\(chartSection)

        EVIDENCE IDS AVAILABLE FOR CITATION:
        sleep, timing, hrv, heart, debt
        """
    }
}
