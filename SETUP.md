# Setup

From clone to running on your iPhone. Should take about five minutes, most of it
waiting for Xcode.

## 0. Requirements

- **Xcode 15 or later.** The project uses the classic explicit-file-reference
  format (`objectVersion = 56`, compatibility Xcode 14), so it opens in anything
  current. Every source file is listed explicitly and target membership is
  already correct — including `Shared/`, which is compiled into both targets.
- **A physical iPhone running iOS 18+.** Non-negotiable for real data — see
  [Why a device](#why-a-device).
- An Apple ID in Xcode (a free one is fine for running on your own device).

## 1. Open it

```bash
git clone <this repo>
cd Zoon
open Zoon.xcodeproj
```

The project builds as-is. Two targets:

| Target | Product | Contains |
|---|---|---|
| `Zoon` | `Zoon.app` | `Zoon/` + `Shared/` |
| `ZoonWidgetExtension` | `ZoonWidgetExtension.appex` | `ZoonWidget/` + `Shared/` |

`Shared/` belongs to **both**. If Xcode ever loses that membership, select the
`Shared` folder in the navigator and tick both targets in the File Inspector.

## 2. Set your signing team

1. Select the project → target **Zoon** → **Signing & Capabilities**
2. Set **Team** to your Apple ID
3. Change **Bundle Identifier** from `com.zoon.sleep` to something unique to you,
   e.g. `com.yourname.zoon`
4. Repeat for the **ZoonWidgetExtension** target. Its identifier must stay
   prefixed by the app's — e.g. `com.yourname.zoon.ZoonWidget`

## 3. Add the HealthKit capability

This is the one step the checked-in project can't do for you: the entitlement is
tied to your team's provisioning profile.

1. Target **Zoon** → **Signing & Capabilities** → **+ Capability**
2. Add **HealthKit**
3. Leave *Clinical Health Records* **unchecked** — Zoon doesn't read them and
   requesting them triggers extra App Review scrutiny for nothing
4. Check **Background Delivery** if you want the app to process last night
   automatically each morning (recommended — see [Background delivery](#background-delivery))

The widget target does **not** need HealthKit. It never queries it.

## 4. Info.plist keys

**Already configured** — you don't need to add these by hand.

The project uses `GENERATE_INFOPLIST_FILE = YES`, so the usage description lives
in build settings rather than a checked-in plist. It's set on both Debug and
Release for the `Zoon` target as:

```
INFOPLIST_KEY_NSHealthShareUsageDescription = "Zoon reads your sleep, heart rate,
HRV, respiratory rate, blood oxygen and wrist temperature to explain how you
slept. Everything is processed on this device and never leaves it."
```

To change the wording: target **Zoon** → **Build Settings** → search
`NSHealthShareUsageDescription`. Or add a real `Info.plist` and set
`INFOPLIST_FILE`, in which case the key is:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Zoon reads your sleep, heart rate, HRV, respiratory rate, blood oxygen and wrist temperature to explain how you slept. Everything is processed on this device and never leaves it.</string>
```

> **`NSHealthUpdateUsageDescription` is deliberately absent.** That key is only
> required when an app requests *write* access. Zoon calls
> `requestAuthorization(toShare: [], read:)` — the share set is empty by
> construction, so it can never write to Health, and declaring a write purpose
> string it doesn't use would be claiming access it doesn't want.

**The app will crash on launch if the share key is missing.** That's HealthKit
being strict, not a bug — if you see `NSHealthShareUsageDescription must be set`,
check step 4.

## 5. Run

Select your iPhone as the destination and hit run. On first launch:

1. iOS presents the HealthKit permission sheet
2. Tap **Turn On All** (or at minimum enable **Sleep**)
3. The dashboard fills in within a second or two

### If you see "No sleep data yet"

Work through these in order:

- **Did you actually grant read access?** HealthKit never tells the app whether
  you did — Apple deliberately hides this so apps can't infer that you have data
  you're choosing not to share. Check **Settings → Health → Data Access &
  Devices → Zoon** and confirm Sleep is on. The empty-state screen has a button
  that takes you there.
- **Is there sleep data to read?** Open the Health app → Browse → Sleep. If it's
  empty, Zoon has nothing to show. Wear the watch to bed with Sleep Focus
  scheduled.
- **Only slept a couple of hours?** Sessions shorter than 2 hours are treated as
  naps and skipped. Change `minimumSessionDuration` in `SleepSessionBuilder` if
  you want to see them.

## Why a device

HealthKit sleep data doesn't exist in the Simulator, and there's no way to
inject a realistic night into it. Rather than leave the UI undevelopable, the app
detects this and falls back to `MockData`:

- **Simulator** — full mock dataset, every screen populated, 30 nights of
  deterministic history for the charts
- **Xcode Previews** — every view has a `#Preview` using
  `zoonPreviewEnvironment()`, backed by an in-memory SwiftData container
- **Device** — real HealthKit data

Mock nights are badged **Sample data** wherever they appear, including in the
widget. A screenshot from the Simulator can't be mistaken for a real night.

## Enable live widget data

**Optional.** Skip it and everything still builds and runs — the widget just
shows sample data.

The widget reads a small JSON snapshot the app writes. For the extension to see
that file, both targets need to share a container:

1. Target **Zoon** → **+ Capability** → **App Groups** → **+** → create
   `group.com.yourname.zoon`
2. Target **ZoonWidgetExtension** → **+ Capability** → **App Groups** → tick the
   *same* group
3. In `Shared/SleepSnapshot.swift`, set:
   ```swift
   static let identifier = "group.com.yourname.zoon"
   ```
4. Run the app once so it writes a snapshot, then add the widget

Settings → About → **Widget data** shows `Live` or `Sample only`, so you can
confirm it took.

Without an App Group, `AppGroup.containerURL` returns `nil` and the snapshot
falls back to the app's own Documents directory — the app works fully, the
extension just can't reach it.

## Background delivery

With the capability from step 3, `HKObserverQuery` +
`enableBackgroundDelivery(for:frequency:)` wake the app when new sleep data
lands, so last night is processed before you open the app.

Two things to know:

- **HealthKit clamps sleep updates to roughly hourly** regardless of the
  frequency you request. Expect "some time after you wake up", not "the instant
  the watch syncs". The app requests `.hourly` explicitly rather than pretending
  otherwise.
- **Without the capability it fails silently at the OS level.** Zoon logs it
  (subsystem `com.zoon.sleep`, category `HealthKit`) instead of swallowing it —
  filter Console.app on that subsystem if automatic updates aren't arriving. The
  app still refreshes whenever it comes to the foreground.

## Regenerating the project file

You shouldn't need to. If `project.pbxproj` ever gets mangled by a merge and
you'd rather regenerate than resolve a conflict by hand:

```bash
brew install xcodegen
xcodegen generate
```

`project.yml` describes the same two targets and the same build settings. After
regenerating you'll need to redo steps 2–3 — signing and capabilities aren't in
the spec, since they're specific to your team.

## Adding the local LLM later

`Insights/LocalLLMInsightEngine.swift` is the only file that needs to change.
Prompt construction and output validation are already written; `loadModel()` and
`runInference(prompt:)` are the two `TODO`s.

- **MLX** — add `https://github.com/ml-explore/mlx-swift-examples` as a package
  dependency, import `MLXLLM`, load a 4-bit community conversion. Budget 1–2 GB
  peak memory for a 3B model.
- **Core ML** — convert with `coremltools` and add the `.mlpackage` to the
  **app** target only.

Two things to get right:

- **Ship the model as an on-demand resource**, not in the bundle. A few hundred
  megabytes in the initial download for a feature the rule engine already covers
  is a bad trade.
- **Never load a model in the widget extension.** Its memory ceiling is far below
  what inference needs, and it will be killed. The extension reads a snapshot for
  exactly this reason.

The protocol is currently synchronous, which suits the rule engine and not
inference. When you get there, make `generate` `async` — every call site is
already in an async context, so it's a mechanical change.

## Project layout

```
Shared/       → both targets
Zoon/         → app target
ZoonWidget/   → widget target
```

When you add a new file, check its target membership in the File Inspector.
Anything in `Shared/` needs **both** boxes ticked; the existing five files are
already set up that way and are the pattern to copy.
