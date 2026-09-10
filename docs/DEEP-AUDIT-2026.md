# Zoon deep audit and product architecture — September 2026

This document records the repository state reviewed on branch `codex/deep-audit-release`. It distinguishes code-backed behavior from device or account work that cannot be proven in simulator CI.

## Executive finding

Zoon already has most of the feature breadth requested by the product brief. Its main release risk was semantic: several polished surfaces made different metrics look interchangeable or more precise than their inputs justified. The release branch fixes the confirmed P1 defects before changing hierarchy: old snapshots no longer invent Recovery 0, non-staged sleep no longer invents Deep/REM contribution, Recovery and Body Battery require personal evidence, Sleep Intelligence now measures the sleep period, and heuristic daytime/forecast metrics disclose their limits.

No open P0 code defect was found. Physical-device release gates remain mandatory.

## Current-state findings

### P1 — fixed on this branch

- **Absent legacy Recovery became a real-looking zero.** `Shared/SleepSnapshot.swift`, custom decoder and `canStateRecovery`. Old payloads lacked a presence signal, decoded to zero, and could pass the legacy confidence fallback. Fixed with `hasRecovery`, legacy-key detection, and migration tests.
- **Legacy SleepScore rewarded missing stages.** `Shared/SleepScore.swift`, component construction. Deep and REM inherited efficiency when stages were absent. Fixed by excluding unavailable components and renormalizing actual evidence.
- **Canonical sleep meaning overlapped Recovery.** `Shared/SleepIntelligenceScore.swift`, `compute`. Recovery and breathing were included in the sleep headline and also shown independently. Version 3 now uses Duration 40%, Continuity 30%, Regularity 20%, Timing 5%, and Stage Pattern 5%. Physiology does not change the sleep-period score.
- **Recovery baseline was fragile.** `Shared/RecoveryScore.swift`, `RecoveryBaseline.from`. Three samples and arithmetic means were sensitive to onboarding noise and outliers. Fixed with seven usable samples per metric, median baselines, and confidence steps at 7/14/30 nights.
- **Body Battery silently used 60 bpm.** `Zoon/Services/DayContextBuilder.swift` and `Shared/BodyBattery.swift`. Fixed by requiring a personal/nightly source, recording provenance, or returning overnight reserve only.
- **Daytime load used a sleep baseline.** `SleepDataCoordinator.refreshTodayStress()` and `StressScore`. Workouts, 30-minute recovery windows, and high-movement hours were already excluded, but the baseline remained overnight. The surface is now explicitly “Physiological Load — Experimental,” requires seven baseline nights, and states the overnight comparison on both summary and detail. A true numeric daytime stress score remains unsuitable until historical quiet, local-time-matched samples exist.
- **Sleep-debt copy overclaimed the heuristic.** `SleepDebtView`, phone/watch widgets, complications, and core modules. Primary UI now says “Sleep Shortfall,” avoids “owe/bank,” and describes a weighted planning estimate.
- **Energy Forecast implied exact measurement.** `Shared/EnergyForecast.swift` and `EnergyForecastCard`. It is now “Estimated Alertness,” publishes low/moderate confidence and 45/75-minute timing ranges.
- **Siri named the wrong score.** `Zoon/AppIntents/ZoonIntents.swift`. The response now calls `flagshipScore` Sleep Intelligence.
- **Watch dial geometry was duplicated and unbounded.** `ZoonWatch/WatchRootView.swift`. A single `ZoonWatchDial` derives diameter and stroke from available geometry, clamps trim, bounds center content, honors Reduce Motion and dimmed display, and exposes one VoiceOver label.
- **Today and Watch hierarchy were static.** `TodayView` now uses morning/day/evening/night scenes and content priorities. The Watch root is reduced to Now, Tonight, and Log, with active Nap promoted first.
- **Two advice feeds could duplicate the same signal.** `WorthNoticing` and `ProactiveZoonCard`. Today now builds one “For You” stream, removes the duplicate body-signal item, ranks by consequence, and caps output at three.

### P2 — implemented with conservative framing

- Force unwraps in production selection, date, interpolation, grouping, and matching paths were removed where ordinary data could reach them.
- App icon variants existed but used a flat generic crescent. Three abstract directions were evaluated, then product review selected a refined version of Zoon's established realistic crescent-and-stars identity. Opaque default, dark, and monochrome tinted appearances are implemented.
- Adaptive scene tokens already existed but Today did not use them. Today now uses `ZoonAmbientBackground` rather than a permanent star field.

### P2/P3 — device or final-SDK gates

- Workout-zone APIs, menopause state, and watchOS 27 Foundation Models are beta SDK surfaces at this audit date. They are documented for adoption after final-SDK verification; core behavior does not depend on them.
- A context-matched daytime physiology baseline requires real-device density and coverage measurement before the app can remove the Experimental label.
- A “smart alarm” requires live, validated sensing through termination/restart and a deterministic AlarmKit fallback. Retrospective HealthKit stages cannot satisfy this. Zoon keeps the honest alarm path.
- Instruments, energy, microphone, notification delivery, background HealthKit, WatchConnectivity, and smallest-case visual evidence require physical devices.

## Feature inventory and dependency map

### Canonical questions

- **Sleep — “How solid was the sleep period?”** `SleepSessionBuilder` → `FeatureExtractor` → `SleepNightFeatures` → `SleepNeed`, `SleepRegularity`, `BodyClock`, `SleepIntelligenceScore` → Today hero, Sleep detail, Watch Last Night, widgets, Siri.
- **Recovery — “How prepared does my body appear?”** overnight HRV SDNN, RHR, temperature and sleep sufficiency → `RecoveryBaseline`/`RecoveryScore` → phone Recovery, Watch Now, complications, Health Pulse. Confidence and missing inputs travel with the result.
- **Tonight — “What should I do next?”** `SleepNeed`, `SleepAutopilot`, `BodyClock`, `LightCoach`, Caffeine Cutoff, naps and recent shortfall → `TonightSection`, routine, Watch Tonight, Tonight widget, bedtime intent.

### Existing product capabilities

- Sleep episode construction, source arbitration, staged/non-staged support, naps, manual repair, shift-work mode, DST/time-zone handling.
- Sleep duration, efficiency, latency, WASO, wake count, stage pattern, regularity/SRI, social jet lag, learned need and shortfall.
- Recovery, HRV status, vitals/Health Radar, breathing-disturbance classification, oxygen and temperature trends.
- Activity strain, workouts, physiological load, Body Battery-style reserve, alertness forecast and optional alertness check.
- Morning brief, daily story, Night Detective, correlations, behavior observations, custom behaviors, guided experiments, evidence history and model health.
- Journal text/dictation with local deterministic parsing and confirmation; local on-device Foundation Models coach/insight fallback on supported iPhone hardware.
- AlarmKit wake alarm with fallback, bedtime reminders, naps with Live Activity, breathing, snore summaries, soundscapes and saved mixes.
- Watch quick logging and snapshots; iPhone widgets; Watch complications and Smart Stack relevance.
- CSV/JSON/PDF export, encrypted user-initiated iCloud Drive backup, complete local deletion, no account, ads, analytics, or developer server.

### System surfaces

- Deep links: soundscapes, nap, sleep detail, breathing, snore check, report, settings, badges, journal, body clock, evidence, patterns, Sensor Truth.
- App Intents: Recovery, Last Night, Log Habit, Start Nap, Start Sounds, Tonight’s Bedtime.
- iPhone widgets: Last Night, Sleep Shortfall, Tonight, Badges, Soundscape controls.
- Watch complications: Last Night, Body Signals, Recovery, Sleep Shortfall, Tonight, Nap Timer, Badges, Circadian Phase.

## Product architecture

Today is an adaptive command center using one stable navigation shell:

```text
05:00–08:59  MORNING
Sleep Intelligence → asleep / need / shortfall → morning brief
→ one “what mattered” item → one action → optional check-in

09:00–16:59  DAY
Capacity now → confidence/provenance → For You (max 3)
→ estimated alertness horizon with Now → compact last-night facts → Tonight

17:00–20:59  EVENING
Tonight target → need / shortfall → one recommendation
→ For You → routine access → compact last-night facts

21:00–04:59  NIGHT
Tonight target / alarm → need / shortfall → quiet controls and provenance
```

The screen does not animate continuously. It re-evaluates the scene when presented or when normal app state changes. Morning-only check-in disappears later; charts and sharing are withheld at night.

Progressive disclosure is consistent: answer first, “Explore why” second, exact sources/baselines/confidence/version in the detail layer.

Long-term health remains a baseline-trends product: sleep consistency and sufficiency, HRV/RHR drift, respiratory stability, recovery resilience, circadian alignment, 30/90/180/365-night views. No biological-age or diagnostic score is shipped.

## Watch specification

The root order is active Nap when present, then Now, Tonight when available, and Log. Now chooses last-night sleep in the morning and capacity during the day; bedtime hours favor the quiet Tonight view.

`ZoonWatchDial` geometry rules:

- diameter is `min(availableWidth, availableHeight)`;
- line width is `clamp(diameter × 0.065, 6, 12)`;
- trim is clamped to 0…1;
- one number and one short label occupy 70% × 48% of the dial;
- band/status stays outside;
- Reduce Motion resolves immediately; otherwise reveal lasts 350 ms;
- Always-On lowers track contrast and removes glow/shadow entirely;
- VoiceOver receives one combined description.

Visual sign-off matrix: 40/41/42/44/45/46 mm and Ultra 49 mm, default and accessibility text, Always-On, Reduce Motion, fresh/stale/missing snapshot. This matrix is a physical/simulator screenshot gate in `APP-STORE-RELEASE-GATES.md`.

## Design system and motion

- Scene families: Lunar Dawn, Day, Dusk, Night. Each has adaptive light/dark stops; only Night may show a low-density star field.
- Semantic families: Sleep indigo, Recovery mint, Circadian amber, Activity blue, Attention amber, Deviation coral, neutral evidence/missing-data gray.
- Large numbers use rounded monospaced numerals. Labels remain Dynamic Type text, reflow through `AdaptiveStack`, and do not rely on color alone.
- Cards group a real concept. Major heroes, section headers, compact rows, and charts remain open to reduce glass-card density.
- Graphics stay code-native: Lunar Orbit, hypnogram/stage river, energy horizon, uncertainty band, baseline range, readiness dial.
- Number updates use numeric transitions. Reveals use 250–450 ms ease/spring. No endless decorative motion. Reduce Motion and Reduce Transparency are first-class branches.
- Haptics confirm intentional logging, selection, alarms, and completed routines; passive refreshes remain silent.

## 2026 Apple SDK decisions

- HealthKit’s June 2026 update publicly documents `HKWorkoutZoneGroup`, preferred/custom zone configurations, and time-in-zone. Zoon should read completed-workout zones to improve load context when compiled with the final SDK, behind availability guards; it must keep the existing older-Watch fallback.
- HealthKit’s menopause state is a separate, preliminary point-in-time API. It belongs behind the existing opt-in cycle permission and must only adjust interpretation language, never diagnose.
- `SystemLanguageModel` documents watchOS 27 support and explicit availability states. Apple also documents Private Cloud Compute models separately. Zoon’s privacy promise permits only the on-device iPhone path today; a Watch model or PCC path requires new accurate disclosure and must never create numeric facts.
- Series 12/Ultra 4 advertise denser HR/HRV and Apple’s own updating Readiness. Apple’s proprietary score is not assumed available. Zoon should make aggregation coverage-aware and continue to support sparse older devices.

Primary references:

- https://developer.apple.com/documentation/Updates/HealthKit
- https://developer.apple.com/videos/play/wwdc2026/207/
- https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/menopausalstate
- https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
- https://developer.apple.com/documentation/Updates/FoundationModels
- https://developer.apple.com/watchos/whats-new/
- https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/

## Competitor sanity check

- Oura clearly separates Sleep, Readiness, and Activity and uses short/long balance windows. Zoon adopts the clear questions and retains transparent local formulas rather than cloning scores.
- WHOOP uses consistent overnight HRV context for Recovery. This supports Zoon’s decision to keep recovery physiology outside its sleep score and to avoid calling a waking-vs-sleep comparison definitive stress.
- Bevel emphasizes standardized HRV collection for comparable Recovery. Zoon’s source provenance and minimum usable samples follow the same trust principle.
- Sleep Cycle and Pillow market smart waking from live sessions. Their public feature descriptions do not make retrospective HealthKit stages a valid live signal. Zoon does not claim Smart Wake without a validated runtime.
- Apple Health/Sleep offers a legible sleep-specific result and evolving dynamic insights. Zoon’s differentiation is local-first evidence, explicit confidence, source arbitration, repair, experiments, and exact algorithm versions.

Competitor references:

- https://support.ouraring.com/hc/en-us/articles/360025589793-An-Introduction-to-Your-Readiness-Score
- https://ouraring.com/blog/readiness-score/
- https://support.whoop.com/s/article/Heart-Rate-Variability-HRV-Insights-WHOOP-Metrics
- https://help.bevel.health/en/articles/11258177
- https://support.sleepcycle.com/hc/en-us/articles/206704909-Sleep-Cycle-Freemium-vs-Premium-Features
- https://pillow.app/article/manual-sleep-tracking
