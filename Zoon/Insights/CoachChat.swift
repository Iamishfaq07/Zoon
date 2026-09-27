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
        /// What stretch of time the answer is about ("Last night", "Recent
        /// nights"), shown above it. `nil` when that is not one span.
        var timeframe: String?

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

        /// Who wrote the words: Apple Intelligence, or Zoon's own local
        /// replies. Shown on the answer so the engine is never a guess.
        enum Source { case appleIntelligence, local }
        var source: Source

        init(id: UUID = UUID(), role: Role, text: String, groundedIn: String? = nil, bestAction: String? = nil, timeframe: String? = nil, source: Source = .local) {
            self.id = id
            self.role = role
            self.text = text
            self.groundedIn = groundedIn
            self.bestAction = bestAction
            self.timeframe = timeframe
            self.source = source
        }

        /// This answer, citing `evidence` when it did not cite anything itself.
        func citing(_ evidence: String?) -> Message {
            var copy = self
            if copy.groundedIn?.isEmpty ?? true { copy.groundedIn = evidence }
            return copy
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
    var runTool: (@MainActor (CoachToolCatalog.Call) async -> String?)?

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
        @Guide(description: "A direct, conversational answer to the question in two to four sentences, written for this person. Use numbers only when they appear in the supplied facts, copied exactly as written; never estimate, round or invent one.")
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
            bestAction: reply?.action,
            timeframe: reply?.timeframe
        ))
    }

    /// Executes the proposal the person just agreed to.
    ///
    /// Idempotent by construction: the pending action is cleared before the
    /// tool runs, so a double tap cannot log two coffees.
    func confirmPendingAction() async {
        guard let action = pendingAction else { return }
        pendingAction = nil
        let result = await runTool?(action.call)
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
        engine: UserPreferences.EngineChoice = .ruleBased,
        contextMode: CoachContextMode = .today
    ) {
        messages = []
        pendingAction = nil
        appleIntelligenceBecameReady = false
        preferredEngine = engine
        conversationEngine = Self.frozenEngine(preferred: engine)
        let framed: String
        switch contextMode {
        case .selectedNight:
            framed = "This conversation is about one recorded night.\n" + nightSummary
        case .trend:
            framed = "This conversation is about a selected trend period.\n" + nightSummary
        case .today:
            framed = "This conversation is about today, recent trends, and tonight — not one frozen night.\n" + nightSummary
        }
        pendingContext = Context(
            nightSummary: framed,
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

    /// Starts a *new* Apple Intelligence transcript. Does not attach a model
    /// to the current Rules conversation.
    func startEnhancedConversation() {
        guard appleIntelligenceBecameReady || preferredEngine == .appleIntelligence else { return }
        appleIntelligenceBecameReady = false
        conversationEngine = .appleIntelligence
        messages = []
        pendingAction = nil
        #if canImport(FoundationModels)
        session = nil
        ensureSession()
        #endif
        messages.append(Message(
            role: .assistant,
            text: "New conversation on Apple Intelligence. Ask about last night, Recovery, Energy, or tonight's plan."
        ))
    }

    func dismissUpgradePrompt() {
        appleIntelligenceBecameReady = false
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isResponding else { return }

        messages.append(Message(role: .user, text: trimmed))
        trimTranscriptIfNeeded()

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
            isResponding = true
            defer { isResponding = false }
            // The engine computes; the model, when there is one, answers the
            // question that was asked from what the engine computed. This
            // path used to return the tool's fixed text even with Apple
            // Intelligence on, so every question that touched a known topic
            // -- most of them -- got the same reply however it was put.
            guard let facts = await runTool?(call) else {
                messages.append(Message(
                    role: .assistant,
                    text: "I do not have that yet. \(call.kind.summary)"
                ))
                return
            }
            let grounded = evidenceID(for: call.kind)
            if let generated = await generate(for: trimmed, facts: facts) {
                messages.append(generated.citing(grounded))
            } else {
                messages.append(Message(role: .assistant, text: facts, groundedIn: grounded))
            }
            return
        case .unknown:
            pendingAction = nil
        }

        isResponding = true
        defer { isResponding = false }

        if let generated = await generate(for: trimmed, facts: nil) {
            messages.append(generated)
        } else {
            appendLocalAnswer(trimmed)
        }
    }

    /// An Apple Intelligence answer to `question`, or `nil` when there is
    /// no model for this conversation or the answer fails a check -- the
    /// caller then gives the local reply.
    ///
    /// - Parameter facts: what an engine computed for this question, handed
    ///   to the model as the facts to answer from. Every number the answer
    ///   contains must appear in these, in the conversation's facts, or in
    ///   the evidence catalog; anything else is a figure the model made up
    ///   and the whole answer is refused.
    private func generate(for question: String, facts: String?) async -> Message? {
        #if canImport(FoundationModels)
        guard conversationEngine == .appleIntelligence, isAvailable, #available(iOS 26.0, *),
              let session = session as? LanguageModelSession else { return nil }
        let catalogKeys = evidence?.catalog.keys.sorted().joined(separator: ", ") ?? "sleep, timing, hrv, heart, debt"
        let catalog = evidence?.promptCatalog ?? "None"
        var prompt = question
        if let facts {
            prompt += "\n\nFACTS ZOON COMPUTED FOR THIS QUESTION (answer from these; quote numbers exactly as written):\n\(facts)"
        }
        prompt += "\n\nEvidence catalog (only these IDs may be cited: \(catalogKeys)):\n\(catalog)"
        do {
            let response = try await session.respond(
                to: prompt,
                generating: ChatAnswer.self,
                // A little range, so two questions about the same night are
                // not answered in the same words. The facts, not the
                // sampling, decide what is said.
                options: GenerationOptions(temperature: 0.5)
            )
            let answer = response.content.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            let grounding = response.content.groundedIn.trimmingCharacters(in: .whitespacesAndNewlines)
            let bestAction = response.content.bestAction.trimmingCharacters(in: .whitespacesAndNewlines)
            let known = [pendingContext?.nightSummary, pendingContext?.contextDigest,
                         pendingContext?.chartContext, facts, catalog]
                .compactMap { $0 }.joined(separator: "\n")

            guard !answer.isEmpty,
                  CoachEvidence.numbersAreGrounded(answer + " " + bestAction, in: known),
                  !DiagnosticLanguageGuard.rejects("\(answer) \(grounding) \(bestAction)") else {
                logger.notice("Chat answer was empty, used an unsupplied number, or failed the diagnostic-language check")
                return nil
            }
            let cited: String?
            if grounding.isEmpty || grounding.lowercased() == "null" {
                cited = nil
            } else {
                // An unknown ID is dropped rather than failing a good answer:
                // the chip is supporting material, the answer stands alone.
                cited = evidence?.catalog[grounding]
            }
            return Message(
                role: .assistant,
                text: answer,
                groundedIn: cited,
                bestAction: bestAction.isEmpty || bestAction.lowercased() == "null" ? nil : bestAction,
                source: .appleIntelligence
            )
        } catch {
            logger.error("Chat generation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Drops older turns when the transcript would crowd current facts out
    /// of a small on-device context window. Keeps the latest 16 messages.
    private func trimTranscriptIfNeeded() {
        // Prefer current facts and the latest user turn over old chit-chat.
        // Character budget is a stand-in for token APIs that are not
        // available in every SDK this file compiles against.
        let maxChars = 8_000
        var kept: [Message] = []
        var used = 0
        for message in messages.reversed() {
            let cost = message.text.count
            if used + cost > maxChars, kept.count >= 4 { break }
            kept.append(message)
            used += cost
        }
        messages = kept.reversed()
    }

    private func evidenceID(for kind: CoachToolCatalog.Kind) -> String? {
        switch kind {
        case .getSleepScore, .getLastNightSummary, .getSleepDuration: evidence?.catalog["sleep"]
        case .getShortfall: evidence?.catalog["debt"] ?? evidence?.catalog["sleep"]
        case .getTonight, .getTomorrow: evidence?.catalog["timing"]
        case .getRecovery, .getEnergy, .getMovement, .getFatigueContext, .getTrainingContext,
             .getTrendSummary, .getMonthlyChange, .getBehaviorEvidence, .getLearningStatus,
             .getWeeklyPlan, .getCurrentPriority, .getPhysiologicalLoad, .getDailyLoad,
             .getForYourAge, .logCaffeine, .startNap, .prepareTomorrow, .setAlarm:
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
        Answer the question that was actually asked, in your own words, as a knowledgeable coach would -- not a summary of every number. Explain what the figure means for this person and why, compared with their own baseline where the facts give one.
        Build on earlier turns in this conversation instead of repeating them; do not reuse an earlier answer's wording.
        When FACTS ZOON COMPUTED FOR THIS QUESTION are supplied, they are the authority for that answer. Quote their numbers exactly; never round, convert or estimate.
        Keep answers to two to four sentences.
        Use one clear action only when the data actually supports one.

        CURRENT NIGHT FACTS:
        \(nightSummary)
        \(digestSection)\(chartSection)

        EVIDENCE IDS AVAILABLE FOR CITATION:
        sleep, timing, hrv, heart, debt
        """
    }
}
