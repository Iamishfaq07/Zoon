# Zoon master prompt completion ledger

This ledger maps the final App Store audit prompt to repository evidence. “Built” means code and automated checks exist. “Device gate” means the repository contains the test procedure, but a signed build and physical Apple hardware are required to produce the evidence.

## Research, audit, and calculations

- **Built:** 2026 competitor and category review, feature-gap ranking, calculation audit, HealthKit/privacy review, interaction audit, design audit, Watch/widget review, and shipping report are captured in the Zoon release-review canvas and PR #284.
- **Built:** Cardiovascular Age is removed from the product surface; cycle context is conservative and history-gated; SRI and chronotype wording is user-safe; body-signal drift, energy, provenance, uncertainty, and permission rules are guarded by code and CI.
- **Built:** 1,184 unit tests, UI flows, all-source compilation checking, crash-log collection, generated-project validation, privacy manifests, and release trust checks run in CI.

## Product and interaction work

- **Built:** Morning in 3, the Sleep Intelligence orbit and explanation, Last Night hierarchy, interactive hypnogram, replay, event markers, beginner-first Patterns, visual Sensor Truth, evidence history, trend comparison overlays, and model-maturity states.
- **Built:** contextual Ask Zoon entry points for charts, the full night, and marked night events. Each receives structured measurements rather than a rendered-chart interpretation.
- **Built:** one-question journaling with an explanation of why the question matters.
- **Built:** Natural Journal text/dictation input with deterministic on-device parsing, editable proposals, and a required confirmation step. Generic caffeine is kept separate from explicitly late caffeine.
- **Built:** high-threshold proactive cards for sustained body-signal drift, material sleep debt, and major timing shifts. The surface renders nothing on ordinary days.
- **Built:** personal model health without a 0–100 score.
- **Built:** personal sleep-resilience estimates after repeated logged disruptions, requiring two consecutive nights back in range.
- **Built:** personal circadian-response learning from explicitly answered morning-daylight and no-daylight observations, with minimum samples, uncertainty, and non-causal language.
- **Built:** an optional local 20–30 second morning alertness check with reaction time, lapse count, subjective alertness, history, and non-diagnostic copy.

## Design, motion, sound, Watch, and widgets

- **Built:** single-purpose screen hierarchy, reduced card density, progressive disclosure, large-number typography, Lunar Orbit, provenance lanes, evidence timelines, uncertainty bands, comparison plots, and experiment ribbons.
- **Built:** purposeful, interruptible motion for score resolution, chart selection, replay, baseline/evidence transitions, body-clock scrubbing, forecasts, experiments, and current-time movement. Reduce Motion is respected.
- **Built:** soundscapes, saved audio scenes, audio-session coordination, nap wake sounds, alarm fallback architecture, and snore-check controls.
- **Built:** simple Watch Last Night/Today/Tonight/Log pages, quick logging, complications, stale-snapshot handling, and state-driven Smart Stack relevance including active naps.

## Deliberate exclusions required by the prompt

- **Smart alarm remains post-launch.** The prompt says not to add it before release unless termination, restart, Watch, battery, wake-window confidence, and missed-signal behavior are proven. Zoon keeps its deterministic system-alarm fallback and does not market it as a smart alarm.
- **Not added:** diagnosis, disease prediction, treatment claims, autonomous medical advice, broad nutrition tracking, social feeds, generic workout-platform scope, medical-record replacement, or a collection of new composite scores.

## External release evidence

- **Device gate:** iPhone HealthKit authorization/import, sparse/no-stage data, timezone and DST, background delivery, termination/reboot, alarm/audio/microphone, Watch sync/offline/stale data, complications, Smart Stack, battery, performance, VoiceOver, Dynamic Type, Reduce Motion, contrast, and touch targets.
- **Account gate:** signed Release archive, TestFlight device pass, App Store Connect metadata, screenshots, privacy answers, age rating, review notes, and submission.

The exact 78-step procedure is in `docs/APP-STORE-RELEASE-GATES.md`. These gates cannot be truthfully marked complete by simulator CI.
