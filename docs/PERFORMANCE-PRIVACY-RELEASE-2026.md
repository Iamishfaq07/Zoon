# Performance, privacy and release review — September 2026

## Performance and concurrency findings

The coordinator is `@MainActor`, but HealthKit queries remain async and model work is grouped after query completion. The most material historic cost was rebuilding every night after every observer delivery. Current code uses anchored changes plus `SyncRange.Plan` and records debug-only metrics: refreshes, full/partial/skipped rebuilds, ranges, nights, episodes, changed samples, deletions and wall time.

Refresh coalescing uses `idle`, `refreshing`, and `refreshingWithPending`; overlapping callers await the shared task and one pending pass runs after the active pass. This avoids the previous dropped refresh and avoids unbounded duplicate cascades. HealthKit observer changes are acknowledged only after writes complete.

Static/local evidence from this branch:

- project generation and release trust audit complete in under one second on the Windows audit host;
- generated project includes 97 shared, 195 app, 9 widget, 3 Watch and 126 test source files;
- GitHub’s clean iOS Simulator build for commit `7b53186` completed in 4m42s with warnings treated as errors;
- project validation completes in about seven seconds in CI;
- no network SDK, analytics SDK, ad SDK or hosted model dependency appears in the project.

These are build and architecture measurements, not runtime performance. Instruments evidence remains a device gate. Record launch-to-first-useful-snapshot, HealthKit query count, nights rebuilt, refresh duration, Today scroll hitch rate, memory high-water marks, Watch launch, and overnight energy on oldest supported hardware. Compare 30-night and multi-year stores and sparse versus Series 12 data density.

## Privacy data flow

### HealthKit

- `HealthKitManager` requests `toShare: []`; Zoon is read-only by construction.
- Core sleep permission is separate from enhancement vitals. Menstrual flow and lifestyle inputs have contextual, feature-toggle requests.
- HealthKit read denial cannot be detected directly; empty-state copy does not claim that it can.
- Extracted local features keep source metadata for Sensor Truth and arbitration.

### Storage and transport

- SwiftData stores extracted nights, journal/behavior observations and evidence locally.
- App Group snapshots are shared only with Zoon extensions.
- WatchConnectivity transfers the derived snapshot and explicit quick-log actions to the paired Watch.
- Optional backup writes a passphrase-encrypted archive to the user’s iCloud Drive only after a direct action. The passphrase is not stored.
- Spotlight receives only feature names, descriptions and routing keywords.
- Exports are user initiated and visibly leave the sandbox through the share flow.

### Microphone and speech

- Snore Check analyzes short buffers in memory and persists only monitored/estimated-snore minutes; raw audio is not retained.
- Voice Journal requests speech authorization when enabled. Proposed interpretations require confirmation before they become behavior data.
- Real-device inspection must confirm interruption, background, denied-permission and cleanup behavior and verify no temporary audio file remains.

### Foundation Models

- Current app code imports Foundation Models only behind `canImport`, checks `SystemLanguageModel.default.availability`, and keeps a deterministic rule-based fallback.
- Numeric facts are assembled by Zoon code; the model phrases grounded evidence and output passes diagnostic-language guards.
- Current privacy copy is valid for the selected on-device `SystemLanguageModel` path. Do not silently swap to `PrivateCloudComputeLanguageModel` or a third-party provider. Either change requires explicit product choice, accurate network/PCC disclosure, entitlement review and regression tests.
- watchOS 27 Foundation Models are not adopted in the shipping compatibility path. Apple’s 2026 material separates on-device System Language Model availability from watch-specific network/PCC behavior, so final SDK/device verification is required before making an offline claim on Watch.

### Delete Everything

The coordinator deletion path must clear SwiftData rows, preferences, naps, snore summaries, snapshots, pending deep links, Spotlight entries, AI cache, temporary exports, reminders, Live Activities and the latest Watch context. Original Health data and an already-created user iCloud Drive archive are outside local deletion and are named in the product/privacy copy. The release checklist requires a post-delete inspection of each store and extension surface.

## App Store review checklist

- Health and microphone usage descriptions match the actual optional features.
- Four target privacy manifests must match Xcode’s final archive privacy report.
- Wellness wording avoids diagnosis, disease prediction, treatment and fitness-for-duty claims.
- Sleep Intelligence, Recovery, Sleep Shortfall, Physiological Load Experimental and Estimated Alertness have distinct names and confidence/provenance.
- No screen treats a missing score as zero.
- Screenshots must come from the exact release commit and show real or clearly marked sample data.
- Review notes should explain read-only HealthKit, local processing, optional microphone, AlarmKit fallback, Watch snapshot transfer and encrypted user-owned backup.
- Sound and image provenance/licenses require human review before upload.

## Release blockers requiring external evidence

1. A signed Release archive on the final Xcode/SDK and TestFlight installation.
2. Physical iPhone HealthKit import, background delivery, termination/reboot and denied/partial permission runs.
3. Physical WatchConnectivity offline/stale/delayed delivery and widget budget behavior.
4. Watch dial screenshots on 40/41/42/44/45/46/49 mm with accessibility text, Reduce Motion and Always-On.
5. Alarm, notification, Live Activity, audio route, microphone and battery tests.
6. Instruments measurements recorded above.
7. App Store Connect metadata, privacy answers, age rating, support/privacy URLs and final screenshot review.

Detailed step-by-step execution remains in `docs/APP-STORE-RELEASE-GATES.md`. These items cannot be truthfully marked complete by source review or simulator CI.
