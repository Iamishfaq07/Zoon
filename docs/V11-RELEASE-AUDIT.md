# Zoon V11 release audit

This build folds the V11 product brief into the existing local-first architecture. The release-facing surfaces now include:

- Adaptive Today and Morning Brief, with proactive context cards already available from the Today tab.
- Daily Sleep Story, Natural Journal V3 confirmation flow, personal learning, evidence, model health, Sensor Truth, and the body-clock modules.
- Trends V3 windows (7, 30, 90, 180, and 365 nights), a deterministic sleep fingerprint, and descriptive sleep eras.
- A typed local Chart Builder, custom behavior signals, and an opt-in on-device Voice Journal transcript flow.
- Watch, widgets, App Intents, exports/imports, privacy copy, accessibility labels, and release guardrails.

Smart Alarm and proactive notifications are implemented through the existing AlarmKit/local-notification paths, with explicit opt-in and truthful fallback messaging. The remaining release gates are real-device validation, HealthKit/notification permission review, App Store Connect metadata, and final icon/screenshot capture. These are platform operations rather than hidden feature flags and must be verified on an iPhone and Apple Watch before submission.

All calculations in the new fingerprint and eras surfaces are deterministic and local. They describe observed timing, duration, continuity, and available HRV data; they do not claim a diagnosis or infer a cause.
