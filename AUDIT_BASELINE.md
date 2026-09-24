# Audit baseline (Deep Audit 2026, Phase 0)

Recorded before any change from `Zoon_Claude_Code_Deep_Audit_2026.md`, against
`main` at **`12ddd69`** ("Release pass: Z01–Z21 fixes, Phase 3 slices,
accessibility and schedule sync (#349)").

This repository is developed without a local Mac. Every build and test below
ran in GitHub Actions (`.github/workflows/build.yml`); nothing here was run on
a device.

## Toolchain

| Item | Baseline value | Source |
|---|---|---|
| Runner image | `macos-26-arm64` 20260907.0351.1, selected implicitly by `runs-on: macos-latest` | run 35930540150, job "Probe installed SDK" |
| Xcode | **26.6** (`/Applications/Xcode_26.6.app`) | same job: SDK paths |
| SDKs | iPhoneOS 26.5, WatchOS 26.5 | same job |
| Xcode 27 | **not used**; nothing pinned it | — |

The audit asks for Xcode 27. Phase 0 pins the runner image (`macos-26`) and
adds `Tools/select-xcode.sh`, which selects Xcode 27 when the image has it and
otherwise the newest installed Xcode, and writes the choice to each job
summary. Read from the first run with the script (run 35994647333, job "Probe
installed SDK"): the pinned `macos-26` image carries **Xcode 26.0 through
26.6 and no Xcode 27**, so the script selected Xcode 26.6 (iOS/watchOS 26.5
SDKs). Consequences recorded here rather than worked around:

- Xcode 27 cannot be pinned on GitHub-hosted runners today. The script will
  pick it up automatically once the image ships it; setting
  `ZOON_REQUIRE_XCODE_MAJOR=27` turns its absence into a failure.
- iOS 27 / watchOS 27 APIs (Foundation Models context/token APIs, Dynamic
  Profiles, Evaluations -- audit §7.2) cannot be compiled or checked against
  an installed SDK here, and the audit forbids inventing APIs, so they are
  not adopted in this pass.

## Build and test status at baseline

CI run **35930540150** on `12ddd69`, all jobs green:

| Job | Result |
|---|---|
| Validate project file (generator current, pbxproj parses, release trust audit) | pass |
| Probe installed SDK | pass |
| Build (watchOS Simulator), standalone `ZoonWatch` scheme | pass |
| Build (iOS Simulator), Debug, `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` | pass |
| `ZoonTests` | **2,449 tests, 0 failures** (36.9 s) |
| `ZoonUITests` | **3 tests, 0 failures** (214 s) |
| Apple accessibility audit (report-only) | **103** issue lines |
| Release build | **not built by CI** at baseline |

No failing test was hidden or skipped to reach this state.

## Project facts confirmed against the checkout

| Brief's claim | Confirmed value |
|---|---|
| ~129k Swift LOC, ~657 files | 129,183 lines in 657 files (Shared 33.8k/174, Zoon 55.8k/232, ZoonWatch 1.3k/3, ZoonWidget 1.5k/9, ZoonWatchWidget 0.9k/1, ZoonTests 35.7k/237, ZoonUITests 97/1) |
| `SleepDataCoordinator.swift` ~3,000 LOC | 3,007 |
| `HealthKitManager.swift` ~1,100 LOC | 1,102 |
| `SoundscapeEngine.swift` ~876 LOC | 876 |
| iOS 18 / watchOS 10 minimum | `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `WATCHOS_DEPLOYMENT_TARGET = 10.0` |
| `SWIFT_VERSION = 5.0` | yes; no `SWIFT_STRICT_CONCURRENCY` setting |
| iPhone-only | `TARGETED_DEVICE_FAMILY = 1` (watch targets 4) |
| No String Catalog | no `.xcstrings` anywhere |
| Sleep Intelligence version | `SleepIntelligenceScore.currentVersion = 3` |

## Counts later phases change

| Measure | Baseline |
|---|---|
| `try? await healthKit…` in `SleepDataCoordinator` | 16 |
| `(try? context.fetch …)` in app/shared code | 10 |
| `@unchecked Sendable` in app/shared/watch/widget code | 6 |
| Recorded sound beds looped with `numberOfLoops = -1` | 1 call site (all beds) |

## Screenshots

`docs/screenshots/` holds 48 captures produced by `screenshots.yml` from
earlier builds (iPhone light/dark/large text, Watch sizes). They are the
"before" set; the workflow regenerates them from the exact build after UI
changes.
