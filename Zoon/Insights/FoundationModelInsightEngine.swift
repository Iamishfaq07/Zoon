import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#else
// Without this framework the engine is a permanent pass-through to the rule
// engine, and nothing at runtime would tell you why. Same reasoning as the
// ActivityKit guard: the #if reports itself rather than failing silently.
#warning("FoundationModels unavailable: Apple Intelligence insights fall back to rules in this build.")
#endif

/// On-device language-model insights via Apple's Foundation Models framework.
///
/// This replaces what `LocalLLMInsightEngine` could only stub. Apple's framework
/// (iOS 26) exposes the ~3B model behind Apple Intelligence directly to apps,
/// which resolves every objection that kept the LLM layer unimplemented:
///
/// - **No download.** The model ships with the OS. No on-demand resource, no
///   several-hundred-megabyte first launch.
/// - **No network.** Inference is local, so the app's central promise survives
///   intact. There is still no networking code anywhere in this project.
/// - **No parser.** `@Generable` gives type-safe structured output. The
///   fence-stripping and `"null"`-string handling in `LocalLLMInsightEngine`
///   exist to survive a raw text model; here the framework guarantees the shape.
///
/// ## Compiling on older SDKs
///
/// The entire framework surface sits behind `#if canImport(FoundationModels)`,
/// so this file compiles on an Xcode without the iOS 26 SDK — it just becomes a
/// thin pass-through to the fallback engine. Runtime availability is checked
/// separately, because a device on iOS 18 running a binary built with the iOS 26
/// SDK must also degrade gracefully.
///
/// ## Why the rules still win by default
///
/// The rule engine can only say things the data supports; a language model will
/// produce a fluent, plausible mechanism whether or not one exists. This engine
/// is offered as a choice, not a default, and it falls back the moment the model
/// is unavailable or its output fails validation.
struct FoundationModelInsightEngine: SleepInsightEngine {

    let displayName = "Apple Intelligence"

    /// Used whenever the model is unavailable, unsupported, or its output
    /// fails validation. The protocol guarantees an insight; "the model didn't
    /// load" is not something a user should ever have to read.
    let fallback: any SleepInsightEngine

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "FoundationModel")

    init(fallback: any SleepInsightEngine = RuleBasedInsightEngine()) {
        self.fallback = fallback
    }

    // MARK: - Availability

    /// Why the model can't be used right now, or `nil` if it can.
    ///
    /// Surfaced in Settings so the option explains itself rather than silently
    /// doing nothing — "Apple Intelligence isn't enabled on this device" is a
    /// far better experience than a toggle that appears to work and doesn't.
    var unavailabilityReason: String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            return "Needs iOS 26 or later."
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use this."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again shortly."
        case .unavailable:
            return "The on-device model isn't available right now."
        }
        #else
        return "This build was compiled without the Foundation Models framework."
        #endif
    }

    var isAvailable: Bool { unavailabilityReason == nil }

    // MARK: - SleepInsightEngine

    /// Synchronous by protocol, which inference is not.
    ///
    /// Rather than widen `SleepInsightEngine` to `async` — and force every call
    /// site and the rule engine to become async for no benefit — generation runs
    /// ahead of time via `prepare(for:)` and lands in a cache. This call reads
    /// the cache, or falls back. That keeps the fast, deterministic path
    /// genuinely fast and confines the asynchrony to the one engine that needs it.
    func generate(
        for features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) -> SleepInsight {
        if let cached = InsightCache.shared.value(for: features.date) {
            return cached
        }
        return fallback.generate(for: features, baseline: baseline, goalMinutes: goalMinutes)
    }

    /// Runs inference and caches the result. Call before `generate`.
    ///
    /// Returns `true` when a model-generated insight is now available.
    @discardableResult
    func prepare(
        for features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) async -> Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), isAvailable else { return false }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let prompt = Self.prompt(features: features, baseline: baseline, goalMinutes: goalMinutes)

            let response = try await session.respond(
                to: prompt,
                generating: GeneratedInsight.self,
                options: GenerationOptions(
                    // Low temperature on purpose. This is a constrained
                    // three-field summary of measured data, not creative
                    // writing — variety here reads as unreliability.
                    temperature: 0.3
                )
            )

            guard let insight = Self.validate(response.content) else {
                logger.notice("Model output failed validation; falling back to rules")
                return false
            }

            InsightCache.shared.store(insight, for: features.date)
            return true
        } catch {
            logger.error("Generation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
        #else
        return false
        #endif
    }

    // MARK: - Prompt

    /// The behavioural contract.
    ///
    /// Two clauses matter most and should survive any rewrite: *don't invent
    /// causes*, and *stay out of diagnosis*. A small model left unconstrained
    /// will do both enthusiastically, and the second is the one that could
    /// actually harm someone.
    static let instructions = """
        You are a sleep coach reading one night of data from a wearable.

        Rules:
        - "summary": one sentence, plain language, describing the night factually.
        - "likelyCause": only name a cause the numbers actually support. If nothing \
        in the data explains the night, leave it empty. Do not guess.
        - "actionableTip": one specific thing to do tonight.
        - Never diagnose a medical condition. Never mention sleep apnea, insomnia, \
        or any other diagnosis by name.
        - Do not mention data you were not given.
        - Keep every field under 240 characters.
        """

    static func prompt(
        features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) -> String {
        """
        Sleep goal: \(Int(goalMinutes)) minutes per night.
        Nights of history available: \(baseline.sampleCount)

        Last night:
        \(features.summaryForLLM)
        """
    }

    // MARK: - Validation

    #if canImport(FoundationModels)
    /// The shape the model is constrained to produce.
    ///
    /// `@Guide` descriptions are part of the prompt the framework builds, so
    /// they carry real weight — this is where per-field constraints belong,
    /// not only in the instructions block.
    @available(iOS 26.0, *)
    @Generable
    struct GeneratedInsight {
        @Guide(description: "One factual sentence describing how the night went. No advice here.")
        var summary: String

        @Guide(description: "The most likely driver, only if the data supports one. Empty string if nothing does.")
        var likelyCause: String

        @Guide(description: "One concrete, specific thing to do tonight.")
        var actionableTip: String
    }

    /// Converts a generation into the app's insight type, rejecting anything
    /// that slipped past the constraints.
    ///
    /// Guided generation guarantees the *shape*, not the *content* — a model can
    /// still return an empty summary or a diagnosis, and both must reach the
    /// fallback rather than the screen.
    @available(iOS 26.0, *)
    static func validate(_ generated: GeneratedInsight) -> SleepInsight? {
        let summary = generated.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = generated.actionableTip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, !tip.isEmpty else { return nil }

        // Backstop on the diagnosis rule. The instructions forbid it; this makes
        // it structural rather than a request the model may or may not honour.
        let combined = "\(summary) \(generated.likelyCause) \(tip)".lowercased()
        for term in bannedTerms where combined.contains(term) {
            return nil
        }

        let cause = generated.likelyCause.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCause = cause.isEmpty || cause.lowercased() == "null" ? nil : cause

        return SleepInsight(
            summary: summary,
            likelyCause: cleanedCause,
            actionableTip: tip,
            // Generated text never claims high confidence. The rules can prove
            // their claims; a model cannot.
            confidence: .medium,
            source: .localLLM
        )
    }

    /// Diagnostic language this app must never produce.
    private static let bannedTerms = [
        "apnea", "apnoea", "insomnia", "narcolepsy", "diagnos",
        "disorder", "syndrome", "disease", "you should see a doctor"
    ]
    #endif
}

/// Small in-memory cache keyed by night.
///
/// Deliberately not persisted: a model-generated insight is cheap to regenerate
/// and shouldn't outlive the process, and caching generated health text to disk
/// invites it drifting out of sync with the data it describes.
///
/// Lock-guarded rather than actor-isolated, because `SleepInsightEngine.generate`
/// is synchronous and non-isolated — a `@MainActor` cache could not be read from
/// it without making the whole protocol async, which the rule engine has no
/// reason to pay for.
final class InsightCache: @unchecked Sendable {

    static let shared = InsightCache()

    private var storage: [Date: SleepInsight] = [:]
    private let lock = NSLock()

    private init() {}

    func value(for date: Date) -> SleepInsight? {
        lock.lock()
        defer { lock.unlock() }
        return storage[date]
    }

    func store(_ insight: SleepInsight, for date: Date) {
        lock.lock()
        defer { lock.unlock() }
        storage[date] = insight
        // One night is all that's ever read back; anything older is dead weight.
        if storage.count > 4 {
            for key in storage.keys.sorted().prefix(storage.count - 4) {
                storage.removeValue(forKey: key)
            }
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
