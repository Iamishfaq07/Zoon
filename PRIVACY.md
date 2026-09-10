# Zoon Privacy Policy

Effective: 10 September 2026

Zoon is a local-first sleep and recovery application. It does not require an account, does not contain advertising or third-party analytics, and does not send sleep, health, microphone, journal, or profile data to a Zoon server.

## Data Zoon reads

With permission, Zoon reads selected Apple Health categories used to produce sleep and recovery features, including sleep analysis, heart rate, resting heart rate, heart-rate variability, respiratory rate, oxygen saturation, sleeping wrist temperature, breathing disturbances, workouts, and activity data. Menstrual-flow dates are requested separately and only when cycle tracking is enabled.

Zoon requests read access only. It does not write or modify data in Apple Health.

## Microphone use

Snore Check uses the microphone only while the user runs a monitoring session. Short audio buffers are analyzed in memory for low-frequency energy and cadence, and by Apple's on-device sound classifier. Audio, speech, and waveforms are not recorded or saved. What is retained on the device is a derived nightly monitored-minutes and estimated-snore-minutes summary, plus up to 200 timestamped sound-event labels from the most recent session -- each one is only a category identifier (for example "snoring" or "cough"), the time it was heard, and a confidence value. These labels are included in a JSON export and are removed by Delete Everything.

Voice Journal uses Apple's speech recognizer with on-device recognition required, so dictated journal text is transcribed on the device and is not sent to Apple's servers by Zoon. The transcript is shown for confirmation before anything is saved; the audio is not stored.

## Data stored on the device

Zoon can store extracted nightly sleep features, journal tags and notes, custom behaviour names the user has added, alertness-check results, naps, derived snore summaries and sound-event labels, app preferences, generated insight cache, HealthKit synchronization state, and a small snapshot used by widgets, Siri/App Intents, and a paired Apple Watch.

When App Groups and Watch connectivity are configured, derived snapshots are shared only among Zoon's own app extensions and the user's paired Watch through Apple's system frameworks.

Zoon adds its own screen names to the device's Spotlight search index so features such as the nap timer and sleep sounds can be opened from system search. Only screen names, descriptions, and search keywords are indexed. No sleep, health, journal, or profile data is placed in the Spotlight index.

## Retention, export, and deletion

Data remains on the user's devices until it is replaced by newer rolling data, deleted through Zoon, or removed by uninstalling the application.

Delete Everything removes Zoon's local sleep and journal database rows, preferences, custom behaviour names, alertness-check results, naps, snore summaries and sound-event labels, widget snapshot files, pending deep links, Spotlight search entries, on-device insight cache, temporary export artefacts, reminders, live activities, and the latest Watch snapshot context. It does not delete the original data in Apple Health, and it cannot reach an export file the user has already shared elsewhere.

## Local export and import

Export and Import live in More → Data. Export writes a file on the device -- JSON (complete, re-importable, including the stores listed above) or CSV (one row per night) -- and hands it to the system share sheet; where it goes from there is the user's choice. When the "Encrypt JSON backup" toggle is on, the JSON is sealed with AES-GCM using a key derived from the user's passphrase with PBKDF2 (a fresh random salt and nonce for every file). The passphrase is never stored, and an encrypted file cannot be restored without it. When the toggle is off the export is plain, unencrypted JSON. Zoon has no iCloud container and no server; nothing is uploaded by Zoon itself.

## Tracking and collection

Zoon does not track users across apps or websites. Zoon does not sell personal data. Zoon does not collect data on a developer-operated server.

## Questions

Privacy questions and reports can be opened through the repository's [GitHub Issues](https://github.com/Iamishfaq07/Zoon/issues).
