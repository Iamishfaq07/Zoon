# Zoon Privacy Policy

Effective: 28 September 2026

Zoon is a local-first sleep and recovery application. It does not require an account, does not contain advertising or third-party analytics, and does not send sleep, health, microphone, journal, or profile data to a Zoon server.

## Data Zoon reads

With permission, Zoon reads selected Apple Health categories used to produce sleep and recovery features, including sleep analysis, heart rate, resting heart rate, heart-rate variability, respiratory rate, oxygen saturation, sleeping wrist temperature, sleeping breathing disturbances and, where the Watch records them, sleep-apnea events, cardio fitness (VO2 max), workouts, and activity data (exercise minutes, active energy, steps, walking and running distance). It also reads date of birth, sex, height, weight and BMI, only to fill the optional profile that fits the recommended sleep range, heart-rate zones and "for your age" comparisons to the user; the age, sex and BMI it keeps are stored with the other preferences on the device and removed by Delete Everything. Menstrual-flow dates are requested separately and only when cycle tracking is enabled. Caffeine, alcohol, time in daylight, mindfulness sessions and daily mood logs (State of Mind) are requested separately and only when Lifestyle Insights is enabled; daily mood is compared with your own sleep on the device and is never sent anywhere.

Zoon requests read access only. It does not write or modify data in Apple Health.

## Calendar use

Calendar access is off by default. When "Use tomorrow's first commitment" is on in Tomorrow, Zoon reads the start time of the first event before 2 PM (all-day events excluded) on each of the next seven mornings, to arrange Tonight, Tomorrow and the week ahead. Only tomorrow's start time is kept on the device, with Calendar's opaque event identifier, when it was read, and the time zone; the other days are not stored. Event titles, attendees, locations and notes are not copied or stored. Turning Calendar off in Tomorrow deletes the kept time.

## Microphone use

Snore Check uses the microphone only while the user runs a monitoring session. Short audio buffers are analyzed in memory for low-frequency energy and cadence, and by Apple's on-device sound classifier. Audio, speech, and waveforms are not recorded or saved. What is retained on the device is a derived per-night summary -- monitored minutes, estimated snore minutes, monitoring quality, coverage and interruption time -- for up to the last 30 nights; while a session runs, a checkpoint of the same derived figures and snore time ranges is saved every few minutes so a crash does not lose the night; and up to 200 timestamped sound-event labels from the most recent session, each only a category (snoring, coughing or a baby crying), the time it was heard, and a confidence value. These are included in a JSON export and removed by Delete Everything.

Voice Journal uses Apple's speech recognizer with on-device recognition required, so dictated journal text is transcribed on the device and is not sent to Apple's servers by Zoon. Nothing is saved until the user confirms, and then only the observations they confirm are stored -- not the transcript and not the audio.

## Data stored on the device

Zoon can store: extracted nightly sleep features (with any corrections or exclusions the user makes) and secondary sleep episodes; journal tags, notes and morning check-in ratings; per-night behaviour answers with any amount, time or intensity; custom behaviour names; alertness-check results; naps; guided experiments and their outcomes; a history of the findings Zoon has recorded; derived snore summaries, a Snore Check crash checkpoint and sound-event labels; saved sleep plans, sound scenes, wind-down routine settings and a saved trip (destination time zone and dates); app preferences (including age, sex, BMI and the Calendar start time above); the reminder and alarm times Zoon scheduled; HealthKit synchronization state; and a small snapshot used by widgets, Siri/App Intents and a paired Apple Watch. Scheduled reminders, alarms and running Live Activities are held by iOS. Generated insight text and Coach conversations are kept only in memory.

When an App Group is configured, Zoon's database and the widget snapshot are kept in Zoon's App Group container, readable only by Zoon and its own extensions (the widgets read only the snapshot). A paired Watch receives the snapshot through Apple's WatchConnectivity framework.

Zoon adds its own screen names to the device's Spotlight search index so features such as the nap timer and sleep sounds can be opened from system search. Only screen names, descriptions, and search keywords are indexed. No sleep, health, journal, or profile data is placed in the Spotlight index.

## Retention, export, and deletion

Data remains on the user's devices until it is replaced by newer rolling data, deleted through Zoon, or removed by uninstalling the application. Like any app's data, Zoon's local store can be included in the user's own iOS device backup.

Delete Everything removes Zoon's local database (nights, secondary sleep episodes, finding history, journal entries and behaviour answers), preferences (including age, sex, BMI and the stored Calendar time), custom behaviours, alertness-check results, naps, experiments, saved plans, sound scenes, routine, trip and night corrections, snore summaries, the Snore Check checkpoint and sound-event labels, HealthKit sync state, widget snapshot files, pending deep links, Spotlight entries, the in-memory insight cache, temporary export files, scheduled reminders, wake and nap alarms, running Live Activities, and the latest Watch snapshot (the Watch deletes its copy when it next receives the update). It does not delete the original data in Apple Health, notifications already delivered, or an export the user has already shared elsewhere.

## Local export and import

Export and Import are in More → Your Data. Export writes a file on the device and hands it to the system share sheet; where it goes from there is the user's choice. JSON is the re-importable backup: nights, journal entries and behaviour answers, custom behaviours, naps, snore summaries and sound-event labels, experiments, finding history, alertness checks, saved plans and routines, and most preferences. CSV has one row per night. "Encrypt JSON backup" is on by default: the JSON is sealed with AES-GCM under a key derived from a passphrase of at least 10 characters with PBKDF2-HMAC-SHA256, with a fresh random salt and nonce for every file. The passphrase is never stored, and an encrypted file cannot be restored without it; with the toggle off the backup is plain JSON. CSV files, the Clinician Report PDF and the share images (last night, Weekly Wrapped, Month Recap) are never encrypted. Zoon has no iCloud container and no server; nothing is uploaded by Zoon itself.

## Tracking and collection

Zoon does not track users across apps or websites. Zoon does not sell personal data. Zoon does not collect data on a developer-operated server.

## Questions

Privacy questions and reports can be opened through the repository's [GitHub Issues](https://github.com/Iamishfaq07/Zoon/issues).
