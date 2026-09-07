# Zoon App Store release gates

This checklist records work that cannot be proven by simulator CI. Complete it
against the exact commit submitted to App Store Connect. Record device model,
OS version, Watch model, and pass/fail evidence for every run.

## iPhone and Apple Health

- [ ] Fresh install: permission education appears before the system sheet.
- [ ] Grant sleep only: Zoon remains useful and labels missing enhancements.
- [ ] Deny sleep: the app explains the empty state without claiming denial is known.
- [ ] Grant a limited history window: coverage and model maturity match the available period.
- [ ] Enable optional vitals later in Settings and verify the second request completes.
- [ ] Test no sleep, one night, 30 nights, and multiple years of data.
- [ ] Test missing HRV, temperature, stages, respiratory rate, and blood oxygen independently.
- [ ] Test two overlapping wearable sources and an explicit preferred source.
- [ ] Delete and edit Apple Health samples, then confirm Zoon reconciles stored nights.
- [ ] Confirm late-arriving HRV updates the correct night without duplicating it.
- [ ] Cross daylight-saving boundaries and east/west timezone travel.
- [ ] Verify naps and secondary sleep are counted once in the correct 24-hour day.

## Core interactions

- [ ] Complete onboarding with Health and notification access granted and denied.
- [ ] Open every Today destination, Why Score disclosure, and Tonight action.
- [ ] Scrub the hypnogram; select stages, awakenings, heart rate, breathing, and sound events.
- [ ] Play, pause, scrub, and finish Sleep Replay; open Night Detective from an event.
- [ ] Edit a historical night and verify the change persists after relaunch.
- [ ] Exercise journal YES, NO, UNKNOWN, edit, and delete paths.
- [ ] Create, start, log, finish, and review an experiment, including unknown adherence.
- [ ] Test every Trends range and comparison overlay with sufficient and insufficient data.
- [ ] Test Twin supported and unsupported scenarios and verify uncertainty changes.
- [ ] Test Travel add, edit, timezone change, and removal.
- [ ] Export CSV/PDF/JSON, restore an encrypted archive, and reject a corrupt archive.
- [ ] Delete all data and verify app, widgets, Watch, intents, reminders, audio, and snapshots clear.

## Alarm, notification, audio, and microphone

- [ ] Schedule, update, and cancel the wake alarm with permission allowed and denied.
- [ ] Verify alarm behavior in Silent mode, Sleep Focus, after force quit, and after reboot.
- [ ] Confirm the fallback behavior when stage/window sensing is unavailable.
- [ ] Start each sound scene, background and lock the phone, then stop from the app.
- [ ] Test timer completion, fade, phone call interruption, Bluetooth route change, and relaunch.
- [ ] Deny microphone access; then allow it and run a complete Snore Check session.
- [ ] Measure overnight audio battery use and verify no raw recording is retained.

## Apple Watch, complications, Smart Stack, and widgets

- [ ] Navigate Last Night, Today, Tonight, and Log pages on the smallest supported Watch.
- [ ] Quick-log caffeine, alcohol, nap, and feeling; verify phone receipt and deduplication.
- [ ] Start/end a nap on each device, including delayed WatchConnectivity delivery.
- [ ] Reboot phone and Watch and verify stale/fresh snapshot labels.
- [ ] Test every supported complication family with fresh, stale, and missing snapshots.
- [ ] Verify Smart Stack morning, daytime, evening, and active-nap relevance on device.
- [ ] Open every phone widget deep link and verify missing/stale snapshot handling.

## Accessibility and performance

- [ ] Complete VoiceOver navigation on onboarding, Today, Sleep, Trends, Journal, and More.
- [ ] Verify largest Dynamic Type, Bold Text, Increase Contrast, and Reduce Transparency.
- [ ] Verify Reduce Motion removes travel/scale without losing selection feedback.
- [ ] Confirm interactive targets remain at least 44 by 44 points.
- [ ] Profile refresh query count/duration with 30 nights and multiple years of history.
- [ ] Profile scrolling and animation on the oldest supported iPhone and Watch.
- [ ] Measure memory for hypnogram, Sleep Replay, Patterns, Sensor Truth, Twin, and reports.

## App Store Connect

- [ ] Use the final signed archive's Xcode privacy report to verify all four manifests.
- [ ] Publish a durable, mobile-readable privacy-policy URL and support URL.
- [ ] Complete privacy nutrition labels from observed behavior, not marketing assumptions.
- [ ] Confirm Health & Fitness category, age rating, wellness wording, and regulatory status.
- [ ] Verify microphone, Health, alarm, notification, and background-use review notes.
- [ ] Confirm there are no accounts, subscriptions, Restore Purchases, or account-deletion obligations.
- [ ] Review third-party licenses and the provenance/license of every bundled sound and image.
- [ ] Regenerate iPhone screenshots from the final commit; capture Watch surfaces separately.
- [ ] Remove placeholders, debug text, mock labels, and unavailable feature claims.
- [ ] Upload the exact tested build and retain this completed checklist with release evidence.
