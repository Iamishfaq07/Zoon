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

Zoon borrows the metrics that each of the big platforms does best, and computes
all of them locally.

### Today
- **Recovery %** (Whoop-style) — HRV and resting HR against *your own* 30-day
  baseline, plus sleep performance and respiratory stability. Shows its working:
  every input is broken out with its deviation from baseline.
- **Strain 0–21** (Whoop-style) — heart-rate-zone load on a logarithmic scale, so
  16→18 reads as much harder than 8→10. Paired with recovery, because strain
  alone is a vanity metric.
- **Body Battery** (Garmin-style) — an energy reserve that charges overnight and
  drains hour by hour with heart rate. The most legible number in the app.
- **Vitals** (Apple Health iOS 18-style) — six overnight metrics checked against
  your personal typical range, flagging outliers without ever implying diagnosis.
- **HRV Status** (Garmin-style) — the last week against a 90-day baseline:
  balanced, unbalanced, low, or poor.

### Sleep
- **Hypnogram** — the full stage timeline, drawn in `Canvas` with connective
  risers so the night reads as one continuous trace.
- **Sleep Need** (Whoop-style) — baseline + debt payback + yesterday's strain −
  nap credit, as a stacked bar against what you actually slept.
- **Sleep sounds** — seven soundscapes **synthesised in real time**: brown, pink
  and white noise, rain, ocean, wind, fan. No audio files, no download, no loop
  seam. Sleep timer fades over the final minute rather than cutting.
- **Naps** — timer with sleep-architecture-aware presets; logged naps credit
  against tonight's need.
- **Bedtime countdown** — the time to be asleep by, derived from your own wake
  pattern and tonight's need.
- **Chronotype** (Fitbit-style) — lion, bear, wolf, or dolphin from habitual
  timing.

### Trends & Journal
- 7/30-day charts for duration, HRV, accumulated debt, and schedule consistency
  (bedtimes plotted with circular statistics, so 23:50 and 00:10 sit next to each
  other rather than a day apart).
- **Journal** (Whoop-style) — 23 tagged behaviours across four categories, and a
  correlation engine that reports what actually tracks with better nights. It
  refuses to call anything a pattern without enough tagged *and* untagged nights,
  and it says "pattern", never "cause".
- **Weekly report** (Whoop/Garmin-style) — averages, week-over-week trends,
  narrative highlights, best and worst night.

### Everything else
- Lock-screen and home-screen **widgets**
- **Streaks** and goal-met counts, kept modest — a streak that punishes one bad
  night is actively harmful in a sleep app
- **Export** to JSON (complete, re-importable) or CSV (one row per night)
- Insight engine written as a protocol with a complete rule-based implementation
  and a local-LLM stub

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
