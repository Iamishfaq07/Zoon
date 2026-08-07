# Zoon Sleep

*Zoon* (زوٗن) means **moon** in Kashmiri.

A local-first iOS sleep app. It reads your Apple Watch sleep data from HealthKit
and turns it into plain-language, causal explanations — *why* last night went the
way it did, not just how many hours you got.

Everything happens on your phone. There is no account, no server, and no
networking code anywhere in the project.

---

## The privacy pitch

Sleep data is among the most intimate telemetry you generate. It reveals when you
are home, when you drink, when you're ill, when you're stressed, and who you
share a bed with. Most sleep apps upload all of it.

Zoon's position is simple: **that data has no reason to leave your device.**

| | |
|---|---|
| **No network calls** | The app contains no `URLSession`, no analytics SDK, no crash reporter. Your data can't leave because there's nowhere for it to go. |
| **Read-only HealthKit** | Zoon requests read permission only — `toShare:` is empty. It cannot write to or alter your Health data. |
| **On-device processing** | Feature extraction, scoring, and every insight are computed locally in Swift. |
| **Local storage** | History lives in a SwiftData store in the app's own container. Settings → *Delete All Sleep History* destroys it. |
| **No account** | Nothing to sign up for. Nothing to delete from someone else's database. |

This isn't a policy promise, it's an architectural one — you can verify it by
grepping the source for `URLSession`, or by running the app in Airplane Mode.
It behaves identically.

---

## What it does

**Dashboard** — last night's duration, sleep score, efficiency, HRV, and a
one-line causal read. Stage breakdown for Deep/REM/Core/Awake with typical-range
markers. Overnight vitals when your watch recorded them.

**Trends** — 7- and 30-day charts for duration vs goal, HRV, accumulated sleep
debt, and schedule consistency (the bedtime/wake-time chart is the one most
people find genuinely actionable).

**Insights** — a rule engine that makes *causal* claims when the data supports
one:

> Deep sleep was down 24% (56 min vs your usual 74). Your last workout ended
> about 1.2h before bed — hard training that close keeps core body temperature
> and adrenaline up, and deep sleep is the first thing to suffer.

and stays quiet when it doesn't. `likelyCause` is `nil` unless a rule actually
fired against real evidence.

**Widgets** — lock-screen and home-screen. Sleep debt as a "bank balance", plus
last night's score.

---

## Architecture

```
Shared/          Types used by both the app and the widget extension
  SleepNightFeatures    The boundary between raw HealthKit and everything else
  SleepScore            0–100 score, computed identically in both targets
  SleepInsight          Constrained output shape for any insight engine
  SleepSnapshot         Small JSON payload the app hands the widget
  MockData              Deterministic sample data for previews and Simulator

Zoon/
  Models/        SwiftData @Model row, user preferences
  Services/      HealthKit queries, session building, feature extraction,
                 persistence + rolling statistics, pipeline coordinator
  Insights/      SleepInsightEngine protocol + implementations
  Views/         SwiftUI screens and components

ZoonWidget/      WidgetKit extension. Reads the snapshot; never touches
                 HealthKit or SwiftData.
```

The data flow is one direction:

```
HealthKit samples
  → SleepSessionBuilder   (segment into nights, dedupe sources, merge overlaps)
  → FeatureExtractor      (join vitals, convert units, compute latency)
  → SleepNightFeatures    ← everything downstream consumes only this
  → SwiftData             (rolling history)
  → RollingBaseline       (7-day HRV, 14-day debt, bedtime consistency)
  → SleepInsightEngine    (causal explanation)
  → Views + widget snapshot
```

Raw `HKSample` arrays never escape `Services/`. That's what makes the whole UI
previewable on a laptop with no device attached.

### The insight engine is an extension point

```swift
protocol SleepInsightEngine {
    var displayName: String { get }
    func generate(for: SleepNightFeatures,
                  baseline: RollingBaseline,
                  goalMinutes: Double) -> SleepInsight
}
```

Two implementations ship:

- **`RuleBasedInsightEngine`** — complete and deterministic. Eleven rules, each
  with a priority; the strongest firing rule wins the causal slot. Thresholds are
  collected in one place so the engine's opinions are auditable.
- **`LocalLLMInsightEngine`** — a stub that delegates to a fallback engine. The
  prompt construction and output validation are already implemented (both are
  testable without a model); `loadModel()` and `runInference()` are marked
  `TODO` with MLX and Core ML integration notes. **No model is bundled and none
  is required to build or run.**

Adding a third engine means writing one conformance and nothing else.

---

## Requirements

- **Xcode 15+**, iOS 17+ deployment target, Swift 5.9+
- **A physical iPhone** for real data — HealthKit sleep data does not exist in
  the Simulator
- An Apple Watch worn overnight for stage breakdown, HRV, and blood oxygen
  (an iPhone alone can record sleep duration via Sleep Focus, and Zoon handles
  that case explicitly)

The Simulator and Xcode Previews fall back to `MockData`, so the entire UI is
developable without a device. Synthetic nights are badged **Sample data**
everywhere they appear — a health app must never show an invented number as if
it were measured.

See [SETUP.md](SETUP.md) for the HealthKit capability, Info.plist keys, and
running on device.

---

## Status

The rule-based pipeline is the shipping path and is complete. Known gaps:

- `LocalLLMInsightEngine` is a stub by design (see above).
- The widget shows live data only once an **App Group** is configured — this is
  optional so the project builds and runs with no developer-account setup. See
  SETUP.md → *Enable live widget data*.
- Background delivery requires the HealthKit background-delivery capability.
  Without it the app still refreshes on foreground; it just won't update by
  itself overnight.

## Not medical advice

Zoon makes correlational, consumer-wellness observations. It cannot diagnose any
condition, including sleep apnea, and it is deliberately written not to try — the
rules that touch blood oxygen, respiratory rate, and temperature carry an
explicit non-diagnostic note. If something here worries you, talk to a clinician.

## License

MIT — see [LICENSE](LICENSE).
