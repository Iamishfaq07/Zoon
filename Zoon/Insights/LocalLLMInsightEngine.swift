import Foundation
import os

/// **Stub.** The intended home of on-device language-model reasoning.
///
/// This file compiles, runs, and ships today without any model present — it
/// simply delegates to its fallback. Everything below the `TODO` markers is the
/// integration surface, laid out so that dropping in MLX or Core ML is an
/// isolated change that touches nothing else in the app.
///
/// ## Why it's a stub and not a dependency
///
/// A bundled 1–3B parameter model adds hundreds of megabytes to the app and a
/// hard toolchain dependency, for a feature the rule engine already covers. The
/// rules are also *better* at the causal claims: they can only say things the
/// data supports, whereas a small model will happily invent a plausible-sounding
/// mechanism. The model earns its place when it can phrase things the rules
/// can't — not before.
///
/// ## Wiring it up
///
/// 1. Add a package dependency:
///    - **MLX Swift** — `https://github.com/ml-explore/mlx-swift-examples`, which
///      gives you `MLXLLM` and a loader for community-converted models.
///    - or **Core ML** — convert a model with `coremltools` and add the
///      `.mlpackage` to the app target.
/// 2. Implement `loadModel()` and `runInference(prompt:)` below.
/// 3. Flip `isModelAvailable` to reflect real state.
/// 4. Ship the model as an on-demand resource, not in the bundle — see SETUP.md.
///
/// ## The privacy line
///
/// Whatever goes in here **runs locally or does not ship**. `summaryForLLM` is
/// derived from health data; sending it to a hosted API would break the one
/// promise the app makes. There is no network code in this file and there must
/// never be.
struct LocalLLMInsightEngine: SleepInsightEngine {

    let displayName = "On-device model"

    /// Used whenever the model is unavailable or its output fails validation.
    ///
    /// Composition rather than optional-returning: the protocol guarantees an
    /// insight, and "the model didn't load" is not something the user should
    /// ever have to see.
    let fallback: any SleepInsightEngine

    private let logger = Logger(subsystem: "com.zoon.sleep", category: "LocalLLM")

    /// Whether a usable model is present.
    ///
    /// Hard-coded `false` until step 2 above is done. Keep it a computed check
    /// against real state (bundle presence, load success) rather than a
    /// constant once a model exists.
    var isModelAvailable: Bool { false }

    init(fallback: any SleepInsightEngine = RuleBasedInsightEngine()) {
        self.fallback = fallback
    }

    // MARK: - SleepInsightEngine

    func generate(
        for features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double,
        band: SleepIntelligenceScore.Band?
    ) -> SleepInsight {
        guard isModelAvailable else {
            // Note: not an error path. This is the shipping configuration.
            return fallback.generate(for: features, baseline: baseline, goalMinutes: goalMinutes, band: band)
        }

        // TODO: Replace with real inference once a model is wired up.
        //
        //   let prompt = buildPrompt(features: features, baseline: baseline, goalMinutes: goalMinutes)
        //   guard let raw = try? runInference(prompt: prompt),
        //         let insight = Self.parse(raw) else {
        //       return fallback.generate(for: features, baseline: baseline, goalMinutes: goalMinutes, band: band)
        //   }
        //   return insight
        //
        // The protocol is synchronous, which is deliberate for the rule engine
        // but wrong for inference. When you get here, widen the protocol to
        // `async` — every call site is already inside an async context, so the
        // change is mechanical.
        return fallback.generate(for: features, baseline: baseline, goalMinutes: goalMinutes, band: band)
    }

    // MARK: - Prompt construction

    /// Builds the full prompt. Implemented now because it's testable without a
    /// model, and because it documents the exact contract the model is held to.
    func buildPrompt(
        features: SleepNightFeatures,
        baseline: RollingBaseline,
        goalMinutes: Double
    ) -> String {
        """
        \(Self.systemInstruction)

        Sleep goal: \(Int(goalMinutes)) minutes per night.
        Nights of history available: \(baseline.sampleCount)

        Last night:
        \(features.summaryForLLM)

        Respond with JSON only.
        """
    }

    /// The behavioural contract. Two clauses matter most and should survive any
    /// rewrite: *don't invent causes*, and *stay out of diagnosis*. A small model
    /// left unconstrained will do both enthusiastically.
    static let systemInstruction = """
        You are a sleep coach reading one night of data from a wearable.

        Rules:
        - Reply with a single JSON object and nothing else. No markdown, no code fences.
        - Schema: {"summary": string, "likelyCause": string or null, "actionableTip": string}
        - "summary": one sentence, plain language, describing the night factually.
        - "likelyCause": only name a cause the numbers actually support. If nothing \
        in the data explains the night, use null. Do not guess.
        - "actionableTip": one specific thing to do tonight.
        - Never diagnose a medical condition. Never mention sleep apnea, insomnia, \
        or any other diagnosis by name.
        - Do not mention data you were not given.
        """

    // MARK: - Output validation

    /// Parses and validates a model response into the constrained struct.
    ///
    /// Implemented ahead of the model because output validation is the part
    /// people skip and then regret: a small model will return fenced markdown,
    /// prose before the JSON, or a null-shaped `"null"` string, and every one of
    /// those must degrade to the fallback rather than reaching the UI.
    static func parse(_ raw: String) -> SleepInsight? {
        // Strip code fences and any prose surrounding the object.
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"), start < end else { return nil }
        let jsonSlice = String(raw[start...end])

        guard let data = jsonSlice.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawInsight.self, from: data) else { return nil }

        let summary = decoded.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = decoded.actionableTip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty, !tip.isEmpty else { return nil }

        let combined = "\(summary) \(decoded.likelyCause ?? "") \(tip)"
        guard !DiagnosticLanguageGuard.rejects(combined) else { return nil }

        // Models like to emit the literal string "null" for an absent cause.
        let cause = decoded.likelyCause?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCause = (cause?.isEmpty == false && cause?.lowercased() != "null") ? cause : nil

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

    private struct RawInsight: Decodable {
        let summary: String
        let likelyCause: String?
        let actionableTip: String
    }

    // MARK: - Inference (unimplemented)

    /// TODO: Load the model. Called once, lazily, then cached for the process.
    ///
    /// MLX sketch:
    /// ```swift
    /// import MLXLLM
    /// let container = try await LLMModelFactory.shared.loadContainer(
    ///     configuration: ModelConfiguration(directory: modelURL)
    /// )
    /// ```
    /// Budget ~1–2 GB of peak memory for a 3B model at 4-bit. This must never
    /// run in the widget extension — its memory ceiling is far below that.
    private func loadModel() throws {
        throw LocalLLMError.notImplemented
    }

    /// TODO: Run generation and return raw text for `parse(_:)`.
    ///
    /// Constrain output hard: temperature ~0.3, a token cap around 200, and a
    /// stop sequence on the closing brace. Insight text is three short fields —
    /// letting it run long produces worse output, not more of it.
    private func runInference(prompt: String) throws -> String {
        throw LocalLLMError.notImplemented
    }
}

enum LocalLLMError: LocalizedError {
    case notImplemented
    case modelUnavailable
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .notImplemented: "On-device model inference is not implemented yet."
        case .modelUnavailable: "No on-device model is bundled with this build."
        case .invalidOutput: "The model returned output that didn't match the expected shape."
        }
    }
}
