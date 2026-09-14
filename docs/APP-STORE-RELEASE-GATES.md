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
- [ ] Specifically: a third-party writer that records a coarse asleep or core block and
      *also* writes finer deep/REM segments inside it without removing the coarse one.
      Apple writes the three stages disjoint, so this arrangement never occurs on Watch
      data and no simulator fixture produces it from real HealthKit. Staged minutes
      must not exceed total asleep. Resolved in `SleepSessionBuilder` and covered by
      `SleepSessionInvariantTests`, but the resolution has never run against a real
      third-party writer's samples.
- [ ] Active energy with both an iPhone and a Watch writing it: confirm Daily Load's
      estimate path does not double-count. `HKStatisticsQuery` with `.cumulativeSum`
      is queried across all sources deliberately, and whether HealthKit de-duplicates
      overlapping cumulative samples for this type was not established from the SDK in
      this pass. The exposure is bounded -- that path already reports low confidence --
      but the arithmetic is unverified.
- [ ] Delete and edit Apple Health samples, then confirm Zoon reconciles stored nights.
- [ ] Confirm late-arriving HRV updates the correct night without duplicating it.
- [ ] Cross daylight-saving boundaries and east/west timezone travel.
- [ ] Verify naps and secondary sleep are counted once in the correct 24-hour day.
- [ ] On a daylight-saving day specifically, check the planned bedtime in Today and the
      nap coach's "time until bed": both are wall-clock times and must not shift by an
      hour or land on the following day.

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

- [ ] Navigate the adaptive Now, Tonight, and Log pages on the smallest supported Watch.
- [ ] Verify the responsive dial on 40/41/42/44/45/46 mm and Ultra 49 mm cases, including accessibility text and Always-On.
- [ ] Quick-log caffeine, alcohol, nap, and feeling; verify phone receipt and deduplication.
- [ ] Quick-log with the phone out of range: the row must read Queued, not Saved, and must
      reach Saved once the phone reconnects. WatchConnectivity cannot be exercised in the
      simulator or in CI, so the acknowledgement round trip is logic-tested only and this
      is the first real test of it.
- [ ] Quick-log the same action twice and confirm the second is acknowledged as saved
      rather than left pending: the phone deduplicates it, which is a success from the
      wrist's point of view.
- [ ] Turn the phone off, quick-log, and confirm the row reports Not saved rather than
      spinning indefinitely.
- [ ] Feel the confirmation haptic, not just see the label. A quick-log taps on press,
      and the wrist plays a distinct success pattern only when the phone confirms it
      persisted the envelope (and a warning pattern when it says it could not). With
      the phone out of range, the press must feel the same and the confirmation must
      not arrive until the phone reconnects. This is the whole point of the haptic --
      it is what tells someone in the dark, not looking at the watch, that the log
      landed -- and it can only be checked on a real pair.
- [ ] Check the haptic vocabulary is distinguishable on the wrist: tap, success and
      warning are three different WatchKit patterns, and if they cannot be told apart
      through a sleeve at night the mapping is wrong regardless of what the code says.
- [ ] Start/end a nap on each device, including delayed WatchConnectivity delivery.
- [ ] Reboot phone and Watch and verify stale/fresh snapshot labels.
- [ ] Test every supported complication family with fresh, stale, and missing snapshots.
- [ ] Verify Smart Stack morning, daytime, evening, and active-nap relevance on device.
- [ ] Open every phone widget deep link and verify missing/stale snapshot handling.

## Accessibility and performance

- [ ] Complete VoiceOver navigation on onboarding, Today, Sleep, Trends, Journal, and More.
- [ ] Verify largest Dynamic Type, Bold Text, Increase Contrast, and Reduce Transparency.
- [ ] Verify Reduce Motion removes travel/scale without losing selection feedback.
- [ ] Confirm interactive targets remain at least 44 by 44 points. The metric info
      buttons are the known risk: a 13-point glyph with no explicit frame, repeated
      beside most metrics in the app. Their labels are fixed; the hit area needs a
      rendered check, because enlarging it blind would change the height of the
      compact rows they sit in.
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

## Not provable from this environment

Recorded rather than left implicit. Every item here needs a Mac with Xcode, a
paired device, or a product decision — none can be closed by simulator CI, and
none should be reported as done on the strength of a green build.

- **2026 HealthKit and watchOS SDK review.** Partly answered, and answered by
  asking the toolchain rather than from memory: a throwaway CI job grepped the
  installed iOS and watchOS SDKs (Xcode 26.6, iPhoneOS 26.5) for workout-zone
  APIs.

  Result: there is no public one. `HKWorkoutZone`, `HKWorkoutZonesSample` and
  `HKWorkoutZonesType` exist only in `HealthKit.tbd`, the linker stub listing
  every class in the shipped binary, next to plainly private ones such as
  `_HKDaemonPreferences` and `_HKEntitlements`. No public header, no
  `.swiftinterface`, no `.apinotes`, on either platform. Reading them would
  mean hand-declaring private interfaces, so Zoon keeps its own sample-aware
  integration and `HRZoneProvenance` records why the Apple case is absent.

  Still open: the rest of the SDK surface. A broader review — whether anything
  else Zoon derives itself now has a public API — wants the documentation and
  headers open on a Mac, not a grep.
- **Device validation of everything above.** The checklist is the record; a
  green CI run is not evidence for any line in it.

## Decisions still open

Two parts of the hardening pass stop at a product question rather than a
technical one. They are written down so they are not settled silently by
whichever implementation happens to land first.

- **Readiness during the day.** Morning Recovery grades the night and does not
  move after waking, which is now stated in the name and in the copy. If a
  live daytime readiness figure is wanted, it has to be decided whether it may
  *recover* during the day after rest or only decline — those are different
  metrics with different inputs, and the choice is not derivable from the data.
- **Daytime physiology baselines.** A time-of-day baseline needs a stated
  number of quiet days before it is trustworthy, and a stated exclusion window
  after a workout. Both are judgement calls about how cautious the app should
  be, not measurements.
