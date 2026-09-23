# Release implementation tracker (Z01–Z21)

Working revision: branch `claude/check-this-out-t0epv2`. Every finding from the
2026‑09‑23 master prompt was checked against the **current** files before
anything changed. This environment has no Mac and no Xcode, so every build and
test result here comes from the repository's GitHub Actions `build.yml` run
(iOS Simulator build + `ZoonTests` + `ZoonUITests`; the watchOS job builds but
runs no tests). "Verified" means that workflow passed on a commit that
contains the change. Nothing below was tested on a physical device.

**CI status:** every item below, including all the tests named in this
file, passed the full `build.yml` run (iOS build + `ZoonTests` + `ZoonUITests`,
watchOS build) on **`42c0656`**, run 35837024213, and again with the Phase 3
additions on **`1f3ec8c`**, run 35841299860. Screenshots regenerated from that
build (commit `9441ba5`) show the Tonight card and the Tonight section giving
the same countdown ("Bed in 13h 45m"); the build before the fix showed 15h 38m
and 14h 26m on the same screen.

Status key: **fixed**: changed, with tests · **already correct**: the defect
isn't in this revision, with the evidence · **partial**: part done, the rest
listed · **open**: not started · **device gate**: needs real hardware.

## Phase 1 — release blocking

| ID | Status | Behaviour and files | Verification | Remaining device / product gate |
|---|---|---|---|---|
| Z01 | fixed | `DayContext.tonightPlanning` (`SleepPlanningInputs.asOfNow`) is built from the shortfall **with the latest night applied** (`SleepHistoryStore.currentBaseline`), **today's** strain and **today's** deduplicated naps. Last night's `SleepNeed` still assesses last night. Every tonight planner reads it: autopilot, episode, Tomorrow, runway, what‑if, coach, both nap coaches. The autopilot now gets the whole outstanding shortfall; before, it got `sleepNeed.debtMinutes` (already a 33% repayment of the debt carried into *last* night) and took 25% of that. Files: `Shared/SleepPlanningInputs.swift`, `Shared/SleepNeed.swift`, `Zoon/Models/DayContext.swift`, `Zoon/Services/DayContextBuilder.swift`, `SleepDataCoordinator.swift`, planner call sites. | `CurrentPlanningInputsTests`: 480 goal, zero prior debt, 180‑min night gives a 300‑min shortfall and a repayment capped at 30; a 60‑min nap moves tonight by exactly 60 once; today's strain is tonight's; non‑finite inputs are neutral. | Real Health nap plus manual nap on the same afternoon, to confirm the dedupe with live data. |
| Z02 | fixed | `Shared/ResolvedSleepEpisode.swift`: one episode with bed, wind‑down, chosen wake, obligation wake, target, source (manual plan / autopilot / usual wake), confidence, zone. Lifecycle upcoming → windingDown → overdue → completed, and **the explicit expiry is the episode's wake**. Built from wall‑clock components (DST‑safe). A manual plan wins for the night it covers; a weekday plan doesn't reach forward to claim next Monday. Used by the Tonight section, the tonight steps, the nap coach, Settings, reminders, the wake window, the morning brief and the alarm. `PlannedBedtimeResolver.tonightsOccurrence` and `DayContext.targetBedtime()` no longer roll a passed bedtime to tomorrow, or jump to the morning after next after midnight. `ZoonTomorrow` resolves the bed of the night that ends at the event wake. | `ResolvedSleepEpisodeTests`: 23:01 stays tonight (the old resolver really said tomorrow); at 02:00 the wake is this morning; expiry at wake; phases; LA spring‑forward (7 h night) and fall‑back (9 h); Kolkata cross‑midnight; day sleep after a night shift; manual 22:30–06:30 is what every surface gets; a Tuesday plan doesn't claim Wednesday; a one‑night override applies once; an impossible 06:00 wake stays at 06:00 with a 90‑min shortfall. **CI green on `c5b92e7`** (unit + UI). | Travel across zones with the app open. |
| Z02b | fixed | The snapshot's tonight label is the resolved episode's bed and wake (`ResolvedSleepEpisode.rangeLabel`, formatted on the phone in the episode's zone), so the Watch and widgets show the same times as the phone, manual plans included. Under a manual plan the note names the plan and any shortfall. | `ResolvedSleepEpisodeTests.testTheRangeLabelIsTheEpisodesTimes`. | Watch/complication capture after a plan change. |
| Z03 | fixed | `Shared/ReminderSchedule.swift`: every reminder is a **dated, one‑off** request (year/month/day/hour/minute + zone, `repeats: false`), queued `horizonNights = 7` ahead from the episode horizon. Identifiers are slots (`prefix.0…6`), so a reschedule replaces and never piles up, and the old fixed repeating identifiers are always cancelled (upgrade path). `RootView.reconcile` re‑queues notification slots on every refresh (a Thursday edit leaves tonight's date unchanged), and a **failed cancel keeps the old date and records `.failed`** instead of "off". Settings' alarm toggle stays on if the cancel fails, and its status names the day of the one dated alarm ("Opening Zoon sets the next one"). | `ReminderScheduleTests`: requests are dated; past dates dropped; duplicates collapse; bounded at 7; legacy IDs cancellable; a Tuesday‑only plan fires at its time on Tuesday only. **CI green on `c5b92e7`.** | **Device gate:** Tuesday‑only doesn't fire Wednesday; one‑night override fires once; reminders present after 48 h with the app unopened; permission revoke/regrant; reboot; DST; Silent/Focus behaviour of the *notification* (it isn't claimed to break through). AlarmKit is still one `.fixed` alarm for the next wake. Relative weekly AlarmKit schedules aren't implemented; if the app stays closed past a wake there's no alarm the next morning, and Settings says so. |
| Z04 | fixed (for this revision) | This revision has no `SnoreSessionController` or `SnoreCheckpoint`. The live session is a view‑owned `SnoreDetector`. The real gap: erasing while it listened left the mic running, and the screen's `SnoreStore` still had the erased summaries in memory, so stopping re‑persisted them all. `Shared/DataErasure.swift` announces an erase generation after persisted data is cleared; `SnoreDetector.discard()` stops capture **without producing a summary**; `SnoreStore` reloads on the notification and before any write from a stale generation; `SoundEventStore` forgets what it showed. Policy (already in place, now documented): erase resets onboarding, so Health import pauses until the person opts in again. Health data is never deleted, and the copy says so. Wake alarm, reminders, Watch receipts and Spotlight were already covered. | `DataErasureTests`: a store open across an erase can't write erased summaries back; an observing store forgets them; the generation only increases. | **Device gate:** erase mid‑capture actually stops the microphone (orange indicator goes off); erase after kill/relaunch. |
| Z05 | fixed | Archive format **6**: behaviour observations carry `quantity`, `unit`, `eventTime`, `intensity`; `alertnessSessions` added; `AlertnessCheckStore.importSessions` merges by id and skips impossible sessions. Older archives decode the new fields as absent (never zero). Store inventory: see "Persistent stores" below. | `ArchiveIntegrityTests`: detail and sessions round‑trip; a format‑5 archive imports them as absent; alertness import skips implausible sessions and doesn't duplicate. | Restore on a second device from a real export. |
| Z06 | fixed | `DataExporter.validationFailure` runs over the **whole** archive before any write: size (64 MB), counts, version, goal, night and episode intervals and minute ranges, duplicate nights/episodes/observations/alertness ids, zones, journal ratings and text length, snore totals, wrist temperature, observation detail, sound‑event confidence, alertness plausibility, setup validity. `importNights`/`importEpisodes` count rows **that reached disk** (per‑save tracking), and the restore message names rows that couldn't be saved. A reversed interval is also skipped at the store (it would trap in `DateInterval`). | `ArchiveIntegrityTests`: reversed episode, duplicate ids, 1e300 minutes/quantity, intensity 7, goal 1e12, alertness median 1e9 and subjective 9, snore > monitored, 50 001 episodes, oversized file, all rejected. | Persistence failure injection needs a SwiftData fault hook; partial accounting is implemented but not exercised by a test. |

## Phase 2 — calculation, evidence and integration

| ID | Status | Behaviour and files | Verification | Remaining |
|---|---|---|---|---|
| Z07 | already correct (this revision) | There's no `LocalSleepCorrection` here. Repairs are **exclusions** (`PersonalSetup.Repair.excluded`), applied by `applyLocalRepairs()` at the start of every publish and honoured by `SleepHistoryStore.historicalFeatures` (excluded nights never enter a later night's baseline or debt, line 157) and `baseline(for:)`. Undo recomputes on the next publish from the current repair list. | Existing repair tests; no new test. | If value‑editing corrections are added later, they have to go through `historicalFeatures`, not after it. |
| Z08 | fixed | `Shared/AwakeningPolicy.swift` is the one rule: observed awake only, after onset, fell back asleep after, ≥ 2 min. It's the rule the stored `wakeCount` already used (`SleepSession.meaningfulAwakeningThreshold` now *is* the policy constant). The hypnogram list (was 3 min, counted in‑bed and the final stretch) and the Sleep Story (was 3 min) both use it. | `AwakeningPolicyTests`: the 30 s + 2½ min + terminal 2 min fixture gives 1; in‑bed isn't an awakening; the story agrees; the builder threshold is the policy. | — |
| Z09 | fixed | `DayContext.overnightHeartRate`: 5‑minute bins from bed to wake, queried separately; daytime hourly HR stays with the battery. `Shared/OvernightSeries.swift` clips to the night; both hypnograms scale, draw, report availability (≥ 2 in‑night points) and scrub only within the night. Demo mode has a synthetic overnight series. | `OvernightSeriesTests`: daytime‑only isn't plottable and gives no scrub value; one in‑night point isn't a line; end points and gaps; non‑finite dropped. | Real overnight HR coverage from an Apple Watch night. |
| Z10 | fixed | Unstaged sleep keeps the Core **row** for shape but has its own neutral colour and the label "Asleep, stage not recorded" in the chart, scrub readout, proportion bar, legend and VoiceOver summary; in‑bed is "In bed", not Awake. Neither is added to Core. Legend reference ranges appear only on measured (`stageTrust.supportsStageFigures`), mostly staged (< 25% unstaged) nights. `CognitiveEnergyCurve` applies its stage nudge only with ≥ 75% stage coverage; an unstaged night had taken 15% off the whole day. | `CognitiveEnergyCurveTests.testADurationOnlyNightIsNotPenalised`. Chart rendering needs the screenshot run. | Hatched pattern for unknown (colour + label now; no pattern). |
| Z11 | fixed | `BodyBattery.build` integrates each bucket over the part between wake and now (a 07:00 bucket counts 50 min for a 07:10 wake; an in‑progress bucket counts to now). Unobserved hours contribute nothing. It records observed/elapsed daytime hours and `lastObservedAt`; confidence drops to moderate under half coverage and to low with none, and the note says which. | `BodyBatteryTests` (+4): pre‑wake bucket counted proportionally; a 5‑min partial bucket is 1/12 of the hour; a missing afternoon gives "4 of 12"; no data all day is low confidence. Existing fixtures now pass an explicit `now` (their samples were in the future relative to `.now`). | `HKStatistics` averages don't carry a sample count, so a bucket with one reading is still weighted by time, not samples. |
| Z12 | fixed | Outcomes store `baselineUsableCount`/`trialUsableCount`. When present, fewer than 7 usable values on either side, or no interval, means **inconclusive**. | `GuidedExperimentTests`: 14 logged / 1 measured is inconclusive; 14 measured per side with a clear shift is supported. | The notebook states measured vs logged nights on each side. |
| Z13 | fixed | The control pool is filtered per metric before matching. A zero comparison median is reported as an absolute difference (wake count only; for other metrics zero means unmeasured). "No Effect" is now "No Clear Link", with copy saying no association isn't evidence of no effect. | `JournalCorrelatorTests`: 0 → 3 awakenings is reported as "+3.0"; a nearest control missing the metric is skipped rather than losing every pair. | Cause Finder states how many behaviour × outcome pairs were compared, so a finding can be weighed against the number of places Zoon looked (`JournalCorrelator.comparisonCount`). No formal p‑value correction: these sample sizes can't support one. |
| Z14 | fixed | `Shared/Deadline.swift`: an exactly‑once continuation race; the operation runs unstructured, so a HealthKit callback that never fires can't hold the caller. Overlapping permission requests return immediately. | `DeadlineTests`: a never‑finishing operation times out within the bound; late completion ignored; errors pass through. | **Device gate:** leave each of the two Health sheets unanswered > 20 s, then accept/deny. |
| Z15 | fixed | `SleepDataCoordinator.selectSleepSource` is the one path from both Settings and Data Repair: it stores the name and bundle ID and clears the anchor so history is re‑arbitrated. Both pickers list HealthKit's writers (`HKSourceQuery`) merged with stored winners (`Shared/SleepSourceList.swift`). | `SleepSourceSelectionTests`. | **Device gate:** two overlapping writers, one never winning; progress/failure UI for the re‑sync isn't implemented. |
| Z16 | fixed (for this revision) | There's no checkpoint here, so the start‑keyed checkpoint doesn't exist. A second session on the same night now **adds to** the first (monitored and flagged minutes sum, later wake kept); it used to replace it. | `SnoreStoreTests.testTwoSessionsOnOneNightAddUp` (a replace‑expecting test was rewritten to the new rule, with the reason). | DST/zone shift mid‑session on device. |
| Z17 | fixed | `WatchActionEnvelope.behaviorNightDate` keeps a log made before 04:00 on the night in progress; the boundary is a parameter. Exact time and the Watch's own zone are kept. | `WatchQuickActionTests`: 01:00 Kolkata stays on that morning's night; the boundary moves. | An explicit last‑night/tonight choice in the Watch UI; shift‑specific boundaries from the phone. |
| Z18 | fixed | `Zoon/Insights/InsightCache.swift`: the key is the prompt plus instructions plus algorithm version; every `prepare` invalidates its night first, so a failure falls back to rules. Generated text is rejected if it states a number the prompt didn't contain (`GeneratedTextGrounding`), is length‑bounded, and is labelled low confidence with under a week of history. | `InsightCacheTests`. | On‑device Foundation Models run (iOS 26 eligible hardware). |
| Z19 | fixed | `SleepAutopilot.Plan.targetWakeMinutes` is capped at the obligation; `attainableSleepMinutes`, `shortfallMinutes`; the sentence states a shortfall beyond the deadband instead of an all‑clear. The episode keeps an impossible hard wake and reports the shortfall. | `SleepAutopilotTests`: midnight habit, 8 h target, 06:00 wake gives bed 23:40, wake 06:00, 1 h 40 m short. | — |
| Z20 | partial | `Shared/NeedModelEvaluation.swift`: an evaluation harness that pairs each night's reported shortfall with that morning's restedness rating, counts usable and missing nights, and reports Spearman correlation overall and per stratum (source, staging, shift, travel). It never changes a coefficient. Naming: `SleepNeed`'s 33%/90‑min term *assesses* a night; `SleepAutopilot`'s 25%/30‑min term *plans* one; `SleepPlanningInputs` keeps them from stacking (Z01 removed the one real double application). No coefficient changed. | `NeedModelEvaluationTests`: a tracking model correlates negatively; missing ratings are counted, not imputed; strata are separate; a constant rating gives no correlation rather than zero. | Wired to the journal's restedness ratings on "Where the numbers come from" (`SleepDataCoordinator.needModelEvaluation`), stratified by stage source and shift mode. Needs weeks of real ratings before any result means anything. Held‑out forecast error and alertness‑check pairing aren't built. |
| Z21 | partial | The screenshot pipeline (`screenshots.yml`) regenerates iPhone and Watch captures from the exact build and commits them to `docs/screenshots/`. A run on the new head was dispatched for this pass. Asset/licence ledger added (`docs/ASSET-LEDGER.md`): no bundled sound, the moon photograph or the icon has a recorded source or licence, so all are marked for human review. Not done: increased contrast, VoiceOver audit, 40 mm large text on Watch (`simctl ui content_size` is unsupported on watchOS). | Screenshot run results. | VoiceOver pass on device. |

### New findings

| ID | Priority | Finding | Status |
|---|---|---|---|
| Z22 | P1 | The same two defects Z02 fixed were visible in the committed renders from `10d5c82`: the Tonight plan card said "Bed in 15h 38m" (autopilot bed) and the Tonight section header "Bed in 14h 26m" (wake − need). | Fixed by Z02; confirm in the renders from the new head. |
| Z23 | P2 | Every current‑debt figure showed `night.sleepDebtMinutes`, the debt **carried into** last night, so the night just slept was ignored until the next night was written. The coach digest also sent a 33% repayment slice as the debt. | Fixed: `DayContext.shortfallNowMinutes` drives the Today arc, debt screen, nap card, energy forecasts, the Watch/widget snapshot and the coach digest; `ShortfallNowTests`. |
| Z24 | P2 | The Tonight plan note claimed "N minutes earlier than your habit" using the **repayment**, not the capped shift, and showed it under manual plans. | Fixed with Z02 (`TodayView.tonightSteps`). |
| Z25 | P3 | The coach digest built its own autopilot plan without the habitual wake, so it could quote a different shift from Today. | Fixed with Z01 (one `tonightAutopilotPlan`). |

## Phase 3 — product slices

| Feature | Status | Notes |
|---|---|---|
| One reliable sleep episode and status | partial | Episode, dated reminders and honest alarm state exist and drive Today, Settings and reminders. Missing: a compact status chip (last sync, source, scheduling state) and one tap from any time to the plan editor. |
| Editable seven‑day plan | partial | The runway's day detail now names the main constraint (`ScheduleFriction`) and has a per‑night "Reminders for this night" switch. A skipped night is dropped from the reminder and alarm horizon (`PersonalSetup.skippedReminderNights`, `SkippedNightTests`), the plan still shows it, and past skips are forgotten. Setting or locking a custom time per day isn't built. |
| Honest interactive night story | partial | Z08–Z10 make the stage, awakening and HR layers honest and spoken. Zoom isn't built. |
| Personal evidence card | partial | Usable N is now stored (Z12); UI disclosure pending. |
| Fast morning check | mostly present | Already in this revision: `MorningCheckInCard` is a one‑tap feeling plus four optional 1–5 questions (rested, energy, sleepiness, mood), skippable, editable, never blended into a score, and backed up with the journal. The forecast‑feedback half is the Z20 panel on "Where the numbers come from", which reads the optional *rested* answer. Not built: a prompt at a chosen time, and linking the reaction test from the card. |
| Shift/travel episode ownership | partial | Episode handles day sleep and zones; Z17 fixes after‑midnight logs. |
| Watch wake and quick controls | open | — |

## Persistent stores (Z05 inventory)

| Store | In backup | Notes |
|---|---|---|
| `SleepNightRecord` (SwiftData) | yes (`nights`, wrist temps) | features + stage segments + source priority |
| `SleepEpisodeRecord` | yes (`episodes`) | |
| `EvidenceRevisionRecord` | yes (`evidenceHistory`) | |
| `BehaviorObservationRecord` | yes, with detail from format 6 | |
| Journal | yes | |
| Naps (`NapStore`) | yes | |
| Snore summaries | yes | no audio ever stored |
| Sound events | yes (latest session) | |
| Experiments | yes | |
| Alertness sessions | yes from format 6 | |
| Custom behaviours | yes | |
| `PersonalSetup` | yes (routine session cleared on restore) | |
| Preferences | yes (selected fields) | |
| `ScheduleStateStore`, `AnchorStore`, `InsightCache`, `WatchActionReceiptStore`, snapshot files, Spotlight | no, by design | regenerated or device‑specific |

## How to verify locally (needs macOS + Xcode)

```bash
python3 Tools/generate-pbxproj.py
python3 Tools/validate-pbxproj.py Zoon.xcodeproj/project.pbxproj
python3 Tools/release-audit.py
git diff --check
xcodebuild test -project Zoon.xcodeproj -scheme Zoon -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild build -project Zoon.xcodeproj -scheme ZoonWatch -destination 'generic/platform=watchOS Simulator'
```

**Release recommendation:** not App Store‑ready. P1 code fixes are in, but the
Z03 alarm/notification device gate, the Z04 microphone check and the Z14
permission‑sheet check haven't been run on hardware, and Z20/Z21 are open.
