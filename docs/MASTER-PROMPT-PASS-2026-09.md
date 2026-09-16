# Zoon — master-prompt engineering pass, September 2026

Against `Zoon_Ultimate_Claude_Code_Master_Prompt.md`, following its §56
implementation order. Written to that brief's §58 structure.

**Scope note, stated once.** This pass covers §56 items 1–17 plus 13–14 out of
order where they shared machinery. Items 18–41 — Personal Sensitivity Curves,
Restorative Windows, Shift Roster Planner, Awakening Inspector, Morning
Alertness, and the visual/motion/Watch/widget/performance passes — are **not
started**, and §M says so rather than this document implying otherwise.

**Nothing here was verified on hardware.** No physical iPhone, no Apple Watch,
no HealthKit store, no EventKit store, no microphone, no AlarmKit, no signed
archive. Every claim below rests on CI builds, the unit suite, and simulator
renders. See §M.

---

## A. Bugs fixed

### A1 — A Calendar commitment outlived the day it was on

```
File:       Shared/CalendarCommitment.swift, Zoon/Models/UserPreferences.swift,
            Zoon/Services/EventKitCommitmentReader.swift,
            Zoon/Views/ZoonTomorrowView.swift, Zoon/Views/TodayView.swift
Problem:    Tomorrow's first Calendar event was stored as an hour and a
            minute, and rebuilt as "tomorrow at that time" forever. Monday
            stores Tuesday's 8:30 meeting; Tuesday evening Wednesday has
            nothing, the read writes nothing, and 8:30 goes on moving wake and
            bedtime as a Wednesday commitment that does not exist.
Root cause: Two failures compounding. The persistence model threw away
            everything that made the record decidable — the instant, the day,
            the source — and the reader returned `CalendarCommitment?`, which
            cannot distinguish "no meeting tomorrow" (clear it) from "I could
            not look" (leave the manual time alone), so the caller only ever
            wrote on success.
Fix:        `StoredCommitment` keeps the instant, the opaque event identifier,
            the fetch time and the timezone. `CommitmentResolver.isStillValid`
            rejects a record that is in the past, on another day, past the
            14:00 morning cutoff, all-day, or older than fourteen hours
            unrefreshed. The reader reports `.read(nil)` separately from
            `.unavailable`, and both callers record the outcome including the
            empty one. Manual and Calendar commitments are separate models:
            a manual time is a standing intent and repeats, a Calendar event
            is a fact about one day.
Tests:      ZoonTests/CommitmentResolverTests.swift — 20 cases covering the
            brief's list: event exists, removed, moved, moved past the cutoff,
            none next day, all-day, stale read, future-stamped read, travel,
            permission revoked, manual coexisting with Calendar, persistence
            across relaunch, and data erasure.
```

### A2 — Today labelled Calendar commitments as manual

```
File:       Zoon/Views/TodayView.swift
Problem:    Today built a `.manual` event from the stored hour whatever the
            real source was, so a commitment read out of someone's calendar
            appeared on Today described as something they had typed in.
Root cause: A second construction of the same value, a consequence of A1's
            storage having no source field to carry.
Fix:        Both screens resolve once, through `preferences.commitment()`.
Tests:      Covered by A1's resolver tests; the `why` line's source wording is
            asserted directly.
```

### A3 — Every path had its own idea of which day "tomorrow" meant

```
File:       Shared/CalendarCommitment.swift (PlanningDay)
Problem:    `now + 1 day` at 1 AM skips past the morning seven hours away, so
            a late-night check planned for the night *after* the one the
            person had not yet slept.
Root cause: The EventKit predicate, the picker and the manual time each
            computed the day themselves.
Fix:        `PlanningDay.morning(after:)` is the single answer, with a 04:00
            late-night cutoff matching the boundary `SleepDayKey` already
            draws. Used by all four paths including the expiry check.
Tests:      CommitmentResolverTests — evening, after-midnight and
            after-cutoff cases.
```

### A4 — A default resting heart rate passed itself off as personal

```
File:       Shared/HeartRateZoneIntegrator.swift, Shared/StrainScore.swift,
            Zoon/Services/SleepDataCoordinator.swift,
            Zoon/Views/EnergyDetailView.swift
Problem:    The resting-HR lookup ended in `?? 60`. Karvonen zones are
            `(bpm − resting) / (max − resting)`, so that constant sits in both
            the numerator and the denominator of every reserve fraction, and
            the Load model was a population model in both terms while the UI
            described it as personal.
Root cause: `HRZoneProvenance` tracked the ceiling and nothing tracked the
            floor.
Fix:        `RestingHRProvenance` names the four sources and travels with the
            number; confidence is the weakest of coverage, ceiling and floor.
Tests:      ZoonTests/RestingHRProvenanceTests.swift — 16 cases.
```

### A5 — A fresh resting-HR reading lost to a day-old one

```
File:       Zoon/Services/SleepDataCoordinator.swift
Problem:    The chain reached for the previous night's measured value ahead of
            the current night's.
Root cause: Harmless while both were unlabelled; wrong once
            `.measuredDailyRestingHR` and `.historicalPersonalRestingHR` have
            to mean what they say.
Fix:        Most-recent-measurement-first, with every tier rejecting values
            outside 25–120 bpm — a corrupt sample in the reserve denominator
            does not produce a slightly wrong Load, it produces a nonsensical
            one.
Tests:      RestingHRProvenanceTests.
```

### A6 — A long-term trend contaminated the baseline it was measured against

```
File:       Shared/LongTermResilience.swift
Problem:    One window, its median, and the single latest reading compared
            against it. Three weeks of a genuinely lower resting heart rate
            drag the 90-day median down with them, so the longer a shift
            holds the less visible it becomes — exactly backwards. And
            "current" was one reading, the noisiest possible estimator,
            carrying a statement about a quarter of a year.
Root cause: No separation between the period being evaluated and the period
            it is evaluated against.
Fix:        Reference and recent windows, adjacent and half-open so a boundary
            reading belongs to one side only, both sides medians. Two gates:
            a practical threshold in the signal's own units and one MAD of the
            reference's own spread. Per-signal thresholds and sample floors.
Tests:      ZoonTests/LongTermResilienceTests.swift — rewritten, 20 cases.
```

### A7 — The clinician report did ordinary statistics on circular quantities

```
File:       Shared/SleepTimingSummary.swift, Shared/Statistics.swift,
            Zoon/Services/ClinicianReportGenerator.swift
Problem:    Bedtime and wake time were shifted at 18:00 and then fed to an
            ordinary median and an ordinary standard deviation. That works for
            a night sleeper and moves the discontinuity rather than removing
            it: two bedtimes twenty minutes apart either side of 18:00 came
            out twenty-four hours apart, which is where a shift worker's
            bedtimes live. On a document a clinician may act on.
Root cause: A linear representation chosen to make linear arithmetic work.
Fix:        `Statistics.circularMedian` (medoid, then the median of offsets
            from it), a signed `circularDifference`, and a MAD measurable
            about a caller-supplied centre. `SleepTimingSummary` lives in
            `Shared/` so the statistics are testable — the generator imports
            UIKit and draws into a graphics context, which had put the most
            correctness-sensitive part of the document out of reach.
Tests:      ZoonTests/SleepTimingSummaryTests.swift — 14 cases including the
            18:00 seam, a day sleeper, a DST transition and travel.
```

### A8 — The clinician report printed zero for "unknown"

```
File:       Zoon/Services/ClinicianReportGenerator.swift
Problem:    Every row ended `?? 0`, which prints `0m`, `00:00` or `0.0%`.
Root cause: A convenience default on a document where a plausible-looking
            zero is indistinguishable from a measurement.
Fix:        "Not available", plus sample counts on every section that lacked
            them, median mid-sleep, wake variability, and a declaration when
            the range spans more than one timezone.
Tests:      SleepTimingSummaryTests covers the empty-range rendering.
```

### A9 — Custom behaviours were labels for a feature that did not exist

```
File:       Zoon/Models/BehaviorID.swift, Zoon/Models/CustomBehavior.swift,
            Zoon/Insights/JournalCorrelator.swift,
            Zoon/Services/BehaviorObservationStore.swift,
            Zoon/Services/SleepDataCoordinator.swift, Zoon/Views/JournalView.swift
Problem:    A store, a settings screen and a row of journal capsules that were
            not tappable, recorded nothing, and were unknown to every engine.
Root cause: No identity the rest of the app could carry. The storage layer was
            already `String`-keyed and ready.
Fix:        `BehaviorID`, built-ins keeping their bare raw value so every row
            ever written still joins. The join key is generalised rather than
            duplicated through `exposureState`, the matched-pair engine,
            `stillLearning`, `testedNoEffect` and the observation store.
Tests:      ZoonTests/CustomBehaviorTests.swift — 20 cases.
```

### A10 — `stillLearning` counted the legacy tag set

```
File:       Zoon/Insights/JournalCorrelator.swift
Problem:    It counted `observation.tags`, which has only ever held built-ins,
            so every custom signal sat at zero however diligently it had been
            logged — silence indistinguishable from never having used it, on
            the one screen whose job is to show progress.
Root cause: Surfaced by A9; the count was also slightly wrong for built-ins,
            since an explicit answer that never became a legacy tag did not
            count either.
Fix:        Counts answers.
Tests:      CustomBehaviorTests.
```

### A11 — A custom behaviour's withdrawn association could never be retracted

```
File:       Zoon/Services/SleepDataCoordinator.swift
Problem:    The retraction pass built its claim-ID lookup from
            `BehaviorTag.allCases`, so a custom behaviour's claim matched
            nothing, the guard skipped it, and its last "Association detected"
            would have stood in the evidence ledger permanently.
Root cause: Surfaced by A9. Precisely the failure the retraction pass exists
            to prevent.
Fix:        Built from the catalogue, keyed on `BehaviorID`.
Tests:      Not directly covered — see §M.
```

### A12 — Voice journal was a dead end

```
File:       Zoon/Views/JournalView.swift, Zoon/Views/VoiceJournalView.swift (deleted)
Problem:    Dictation lived on its own screen whose own copy admitted the
            ending: "the transcript stays here until you copy it into
            Journal."
Root cause: The parser that could have understood the transcript was behind a
            different button on a different screen.
Fix:        Speaking fills the same field typing does, feeding the same parser
            and the same confirmation step.
Tests:      Parser coverage in NaturalJournalTests; the unification is UI.
```

### A13 — The Coach never reached a tool

```
File:       Zoon/Insights/CoachChat.swift, Zoon/Insights/CoachToolRunner.swift,
            Zoon/Views/CoachChatView.swift
Problem:    `CoachToolCatalog` knew which utterances map to which tools and
            which need confirming. Nothing consulted it, so "what is my
            recovery" was answered by prose about numbers rather than by
            `RecoveryScore`.
Root cause: The catalogue shipped without a caller.
Fix:        Tools run before the model. Reads are computed by engines; writes
            become proposals with an explicit confirm.
Tests:      CoachToolCatalogTests extended with the confirmation contract.
```

### A14 — "Log coffee at 5" meant five in the morning

```
File:       Shared/CoachToolCatalog.swift
Problem:    A bare hour was taken at face value, so the brief's own example
            resolved to 05:00 and was recorded as `.caffeine` rather than
            `.caffeineLate` — understating the exposure that behaviour exists
            to capture. An existing test pinned `5 * 60`, which pinned the bug.
Root cause: One parser serving two call sites whose bare hours mean opposite
            halves of the day.
Fix:        A per-call-site default. Only 1–11 are ambiguous; an explicit
            meridiem always wins.
Tests:      CoachToolCatalogTests.
```

### A15 — Nap Learning had no control group

```
File:       Shared/NapLearning.swift, Zoon/Services/SleepDataCoordinator.swift
Problem:    Nap days were compared against a fixed 35% threshold or against
            other nap days, never against a day without a nap. The coordinator
            could not have supplied controls anyway — its observation builder
            skipped no-nap nights outright.
Root cause: The observation shape had no way to represent a control day.
Fix:        Matched no-nap controls, greedy and without replacement, weekday
            type and timezone as hard constraints.
Tests:      ZoonTests/NapLearningTests.swift — rewritten, 14 cases.
```

### A16 — Nap Learning mislabelled the group it measured

```
File:       Shared/NapLearning.swift
Problem:    Everything under thirty-five minutes was bucketed together and the
            group was called "your 20–30 minute naps". A five-minute doze and
            a deliberate half-hour are not the same event.
Root cause: One threshold standing in for a bucket boundary.
Fix:        Three duration buckets on the two places the physiology is
            commonly held to change, with phrasing that names the range
            actually measured.
Tests:      NapLearningTests.
```

### A17 — Nap Learning compared bedtimes linearly

```
File:       Shared/NapLearning.swift
Problem:    A raw hour band, so 23:50 and 00:10 scored as six hours apart.
Fix:        `Statistics.circularDifference`.
Tests:      NapLearningTests.
```

### A18 — Sleep Resilience used one tolerance for everyone

```
File:       Zoon/Views/Components/SleepResilienceCard.swift,
            Shared/SleepResilience.swift
Problem:    A flat twenty-five minutes as the width of everyone's typical
            band. A hyper-regular sleeper had almost nothing counted as a
            disruption; an erratic one had real ones swallowed. Both failures
            silent.
Fix:        `1.4826 × MAD` of that person's own durations, bounded at both
            ends for the two reasons above.
Tests:      ZoonTests/SleepResilienceTypedTests.swift.
```

### A19 — A `DeepLink.Destination` switch was left non-exhaustive

```
File:       Zoon/Views/RootView.swift
Problem:    Adding a Tomorrow destination. Caught by the compiler, recorded
            because it is the fourth switch over that enum and the pattern
            will recur.
```

---

## B. Algorithm changes

### B1 — Long-Term Resilience

```
Old behavior: median of one window; latest single reading compared against it;
              one 3% tolerance for every signal; "for N days" from a run-length
              counter over observations.
Problem:      A sustained shift contaminates its own reference, and the longer
              it holds the less visible it becomes. One reading is the noisiest
              possible estimator for a statement about ninety days. A 3%
              tolerance is 1.6 bpm of resting heart rate, 1.7 ms of HRV and
              0.45 breaths a minute — quantities that are not comparable, since
              overnight HRV routinely swings 20% night to night. The run-length
              counter asserted consecutive days whether or not the readings
              were consecutive.
New behavior: adjacent half-open reference and recent windows, both medians.
Formula:      referenceCenter = median(reference)
              referenceVariability = MAD(reference)
              recentCenter = median(recent)
              absoluteChange = recentCenter − referenceCenter
              relativeChange = absoluteChange / referenceCenter
              robustEffect = absoluteChange / referenceVariability
              reported when |absoluteChange| ≥ spec.practicalThreshold
                       and |robustEffect| ≥ 1
Confidence:   the thinner of the two windows' sampling densities, capped at
              moderate when the reference has no spread to judge against.
Edge cases:   flat reference (no scale — practical threshold decides alone,
              confidence capped); sparse sampling (reported as "8 readings
              spanning 19 days", never "for 8 days"); missing periods inside
              the reference; a trend that returned to baseline.
Tests:        LongTermResilienceTests.
```

### B2 — Load confidence

```
Old behavior: min(coverage, max-HR provenance).
Problem:      the resting rate — the other half of every Karvonen fraction —
              was untracked and defaulted to 60.
New behavior: min(coverage, ceiling provenance, floor provenance).
Note:         the brief's product has a fourth term for Apple workout zones.
              There is no public API to produce one (see D), so there is no
              term; a factor that is always 1 is not a factor. Combined as a
              minimum rather than a product because these are ordinal labels,
              not probabilities, and multiplying them would invent precision
              the inputs do not have.
Direction of  someone whose true resting rate is 48 scored against 60 has
error:        every reserve fraction understated, so Load reads too low. That
              is the same safe direction `maxInterpolationWindow` already
              chooses, which is why the fallback stays rather than being
              swapped for a different model on a guess. What changed is that
              it can no longer claim to be about them.
Tests:        RestingHRProvenanceTests.
```

### B3 — Clinician timing statistics

```
Old behavior: shift at 18:00, then ordinary median and ordinary SD.
Problem:      the seam moved rather than disappearing, and landed where shift
              workers live.
New behavior: circular median and circular MAD about that same centre, plus
              median mid-sleep computed from the real instants.
Tests:        SleepTimingSummaryTests.
```

### B4 — Nap Learning

```
Old behavior: nap days against a fixed proportion threshold, or against other
              nap days; one bucket under 35 minutes; linear bedtime hours.
New behavior: matched no-nap controls; three duration buckets × two timing
              buckets; circular bedtime difference; median of each pair's own
              difference; reported per bucket only above six matched pairs.
Limitation:   observational. Someone who naps on the days they are already
              exhausted will show naps alongside worse nights, and matching on
              measured confounders does not fix that. Said in the copy.
Tests:        NapLearningTests.
```

### B5 — Sleep Resilience band and disruption types

```
Old behavior: flat 25-minute band; one undifferentiated bounce-back.
New behavior: personal robust band, bounded; bounce-back split by trigger
              (short sleep, late schedule, travel) with the same outcome for
              all three — sleep length returning to this person's own usual,
              because a disruption is not over because the trip is over.
Tests:        SleepResilienceTypedTests.
```

---

## C. New features

### C1 — Sleep Opportunity vs Execution (§21)

```
Purpose:      the number the app already showed says you were short and says
              nothing about what to do, because "short" has two causes needing
              opposite answers.
Architecture: Shared/SleepOpportunity.swift — an identity,
              need − asleep = (need − opportunity) + (opportunity − asleep).
Files:        Shared/SleepOpportunity.swift,
              Zoon/Views/Components/SleepOpportunityCard.swift,
              Zoon/Views/SleepDetailView.swift
User flow:    three rows and a sentence on Sleep Detail, where the night is
              already the subject.
Privacy:      no new data of any kind.
Tests:        ZoonTests/SleepOpportunityTests.swift — 15 cases.
Limitations:  refuses to attribute when time in bed was inferred rather than
              measured. Apple Watch alone does not report one, and an inferred
              window sits close to asleep time by construction, so the
              execution gap it produces is not a measurement — and it
              understates fragmentation, which is the direction that would
              make a continuity problem look like a scheduling one.
```

### C2 — 7-Day Sleep Runway (§19)

```
Purpose:      warn before insufficient sleep becomes unavoidable. Somebody
              with a 06:00 start on Thursday cannot fix Thursday on Wednesday
              evening.
Architecture: Shared/SleepRunway.swift. Wake per morning from a dated
              commitment, then a standing time for that kind of day, then the
              weekday habit, then the overall habit. Bedtime from the habit for
              the evening before. Opportunity is the distance between them.
Files:        Shared/SleepRunway.swift,
              Zoon/Views/Components/SleepRunwayCard.swift,
              Zoon/Services/EventKitCommitmentReader.swift (horizon read),
              Zoon/Views/ZoonTomorrowView.swift
User flow:    seven rows on Tomorrow, bar against a need mark, tap for why.
Privacy:      start times only, read live and never persisted — a second
              store keyed by day would be a second thing that can go stale,
              which is the bug A1 exists to prevent.
Tests:        ZoonTests/SleepRunwayTests.swift — 16 cases.
Limitations:  opportunity is a ceiling, not a forecast, and the caveat says
              so. Nothing predicts recovery, a score, or how anyone will feel.
```

### C3 — What-If Tonight (§20)

```
Purpose:      the question people have at 11pm — "what does an extra hour cost
              me?" — had no answer, despite the answer being subtraction.
Architecture: Shared/WhatIfTonight.swift. Offsets from the two ends computed by
              the engines that already own them.
Files:        Shared/WhatIfTonight.swift,
              Zoon/Views/Components/WhatIfTonightCard.swift,
              Zoon/Views/ZoonTomorrowView.swift
User flow:    two steppers and five consequence rows on Tomorrow.
Privacy:      none.
Tests:        ZoonTests/WhatIfTonightTests.swift — 16 cases, including one that
              asserts no Recovery, score or readiness claim appears anywhere in
              its output.
Limitations:  steppers rather than a drag surface — fifteen minutes is the
              resolution the underlying need is good to, and a stepper is
              operable with VoiceOver and Switch Control without a bespoke
              adaptor.
```

### C4 — Zoon Log (§15)

```
Purpose:      one place to log, three ways in.
Files:        Zoon/Views/JournalView.swift; Zoon/Views/VoiceJournalView.swift
              deleted.
User flow:    speak, type or tap; Zoon proposes; nothing is saved until
              confirmed.
Privacy:      on-device speech (`requiresOnDeviceRecognition`), audio never
              stored, parsing on-device.
Tests:        NaturalJournalTests, including six new custom-signal cases.
```

### C5 — Actionable Coach (§16)

```
Purpose:      finish the tool architecture that shipped without a caller.
Files:        Zoon/Insights/CoachToolRunner.swift, Zoon/Insights/CoachChat.swift,
              Zoon/Views/CoachChatView.swift
User flow:    reads answer immediately from engines; writes propose and wait.
Privacy:      tool answers never reach the model; nothing new is collected.
Tests:        CoachToolCatalogTests.
Limitations:  the confirmation UI is not covered by an automated test.
```

---

## D. Apple APIs used

Only APIs that compiled in CI against the installed SDK.

| API | Where | Availability |
|---|---|---|
| `EKEventStore.requestFullAccessToEvents()` | `EventKitCommitmentReader` | iOS 17.0+, guarded |
| `EKEventStore.predicateForEvents(withStart:end:calendars:)` | horizon and single-day reads | — |
| `EKEvent.startDate` / `.endDate` / `.isAllDay` / `.eventIdentifier` | both reads | — |
| `SFSpeechRecognizer` + `supportsOnDeviceRecognition` | `VoiceJournalRecorder` | — |
| `SFSpeechAudioBufferRecognitionRequest.requiresOnDeviceRecognition` | same | — |
| `AVAudioEngine`, `AVAudioApplication.requestRecordPermission` | same | — |
| `HKQuantityType(.heartRate)`, `HKSampleQuery` | `HealthKitManager.heartRateSamples` | — |
| `UIGraphicsPDFRenderer` | clinician report | — |
| `CSSearchableItem` | Spotlight destinations | — |
| `LanguageModelSession`, `@Generable`, `@Guide` | `CoachChat`, behind `#if canImport(FoundationModels)` | iOS 26.0+, guarded |

**Not used, and why.** There is no public API for Apple's workout zones.
`HKWorkoutZone`, `HKWorkoutZonesSample` and `HKWorkoutZonesType` exist in
`HealthKit.tbd` alongside plainly private symbols, and are declared in no
public header, `.swiftinterface` or `.apinotes` on iOS or watchOS. Reading them
would mean hand-declaring private interfaces. `HRZoneProvenance` documents the
gap rather than pretending to fill it, and `StrainScore.confidence` has no
workout-zone term as a result.

---

## E. Design changes

| Screen | Before | Problem | After | Why |
|---|---|---|---|---|
| Tomorrow | plan sentence, horizon, time picker, calendar toggle | answered one night and offered no way to ask about a different one, or about the week | adds What-If Tonight and the 7-Day Runway, plus a getting-ready-time control | the 50-minute buffer was a constant making a claim about the person |
| Sleep Detail | headline, hypnogram, inspector, story, breakdown | said you were short, never which of the two causes | adds Opportunity and Execution above the breakdown | the two causes need opposite advice |
| Journal | "Say it naturally" card, a link to a separate voice screen, non-tappable custom capsules | dictation ended in a transcript nobody moved; custom signals recorded nothing | one Zoon Log card with inline dictation; custom capsules are tri-state controls | one place, one review step, one contract |
| Coach | every question to the model | prose about numbers instead of the numbers | tool answers first, confirmation bar for writes | deterministic engines are the source of truth |
| Energy detail | Load caveat named the ceiling only | a generic floor was invisible | names whichever of the two boundaries is binding, and says what would fix it | wearing the watch is the fix; Settings cannot help |
| Clinician PDF | `?? 0` rows, "Bedtime variability (SD)" | zeros read as measurements; SD on clock values | "Not available", circular MAD, sample counts, mid-sleep, timezone declaration | a clinician may act on it |

Screens **not** touched in this pass: Today, Trends, Patterns, Evidence,
Settings, Soundscapes, Breathing, Watch, widgets. §56 items 25–36.

---

## F. Graphics

- No new Canvas work, no shaders, no new assets, no asset removals.
- New vector components, all SwiftUI shapes: the Runway's bar-and-need-mark
  track, the Opportunity card's proportional bars.
- App icon unchanged. The brief (§36) endorses the current crescent direction
  and asks for no redesign.

---

## G. Animations

| Screen | Purpose | Trigger | Reduce Motion |
|---|---|---|---|
| Coach | the confirmation bar arrives from the bottom edge | a write proposal | uses the app's standard transition; no bespoke motion added |
| Runway | none — selection changes the detail text, nothing moves | tap | n/a |
| What-If | none — values recompute in place | stepper | n/a |

No looping, ambient or decorative motion was added anywhere in this pass.

---

## H. Accessibility

- **Dynamic Type.** `ViewThatFits` label/value reflow in the Runway, What-If,
  and typed-resilience rows; bars and tracks drop out entirely at accessibility
  sizes rather than competing for a width neither they nor the label can have.
  Large-text capture extended from three screens to nine, at AX5 and again at
  AX1. **Not yet reviewed against renders** — see §M.
- **VoiceOver.** Every new row is a combined element with a written label; the
  Runway names the weekday, the opportunity and the gap; the dictation control
  announces its state rather than its glyph.
- **Colour is never the only indicator.** A short runway day carries a signed
  number and a warning glyph; a short What-If row carries a minus sign; the
  dictation button's word changes from Speak to Stop.
- **Bold Text / Increase Contrast / Reduce Transparency.** Not re-verified in
  this pass.
- **Chart accessibility.** The new surfaces are rows and bars with written
  summaries rather than charts.

---

## I. Performance

No measured profiling was performed. Two observations, neither measured:

- `stillLearning` now evaluates `catalog.analysable × observations` rather than
  iterating the tag set — roughly 23 × N boolean resolutions per call, on a
  path several view bodies already call more than once per render. Not
  profiled.
- The Runway's EventKit horizon read runs once per appearance of Tomorrow and
  is not persisted.

---

## J. Tests

Run on the GitHub Actions macOS runner, iOS Simulator, scheme `Zoon`. There is
no Mac and no local toolchain in this environment, so this is the only place
any Swift in this branch has ever been compiled or executed.

**Suite size.** 1,796 `func test…` methods across 174 files in `ZoonTests`,
plus 2 methods in `ZoonUITests`. Counted from source; the per-suite tally the
runner prints sits mid-log and is not reachable through the API (see K).

**Result on `ed5bb63`** — Build run #1501, job "Build (iOS Simulator)":

| Step | Outcome |
| --- | --- |
| Build app and widget | success (3m 03s) |
| Run ZoonTests | success (5m 18s) |
| Run ZoonUITests | `** TEST SUCCEEDED **`, `Executed 2 tests, with 0 failures` (3m 42s) |
| Verify every source compiled | success — every Swift file under `Shared`, `Zoon`, `ZoonWidget`, `ZoonWatch`, `ZoonWatchWidget` appears in the build log |
| Summarise errors | `Build succeeded.`, no failing-test block emitted |

The failure block that step prints is unconditional when any `error:`,
`Test Case … failed` or `fatal error` line exists in `test.log` or
`uitest.log`. It printed nothing, and the job's shell runs under `-e`, so a
non-zero `xcodebuild` would have failed the step. Green here means the suite
ran and passed, not that it was skipped.

**Tests added this pass** (~180 assertions): `CommitmentResolverTests` (20
cases), `RestingHRProvenanceTests` (16), `SleepTimingSummaryTests` (14),
`CustomBehaviorTests` (20), `SleepOpportunityTests` (15), `SleepRunwayTests`
(16), `WhatIfTonightTests` (16), `SleepResilienceTypedTests`,
`NewSurfaceLanguageTests`.

**Reds this pass, and what they were.** Four red runs, every one a real defect
rather than a flake:

1. A 20-argument `SleepNightFeatures(...)` hand-rolled in
   `SleepTimingSummaryTests` was missing two arguments, so `ZoonTests` did not
   compile and **the entire suite silently never ran**. Rewritten through
   `Fixture.night`.
2. A type-checker timeout from four inline products inside that same
   initializer call. Bound to typed locals.
3. `CoachToolCatalogTests` asserted `5 * 60` for "log coffee at 5", pinning a
   product bug: a bare afternoon hour parsed as 05:00 and recorded `.caffeine`
   rather than `.caffeineLate`. Both the parser and the test were wrong; both
   fixed (A14).
4. Nine assertions in the pre-existing `LoadConfidenceTests` /
   `LoadProvenanceTests` after `StrainScore.compute` gained a
   `restingProvenance` parameter defaulting to `.genericFallback` — callers
   that had never looked at a resting rate were recorded as having looked and
   found nothing. The default is now `nil`.

One of my own assertions was wrong rather than the code: a nap test meant to
check the bedtime shift printed in minutes matched `"h "`, which occurs inside
"with bedtimes". It now asserts the magnitude.

**Not tested.** Nothing here ran on hardware. See M.

---

## K. Build

`xcodebuild` on `macos-latest`, iOS Simulator destination. Every verification
in this document is a 12–20 minute CI round trip; there is no local compile.

- **Build run #1501, `ed5bb63`: success.** Both jobs green — "Validate project
  file" (ubuntu) and "Build (iOS Simulator)" (macos).
- `project.pbxproj` is generated. `Tools/generate-pbxproj.py` was re-run and
  `Tools/validate-pbxproj.py` plus `Tools/release-audit.py` pass: 1,768
  objects, root object resolves, no dangling references, schemes resolve, all
  `Info.plist`s complete. Final counts — 125 shared sources, 221 app, 9 widget,
  3 watch, 1 watch extension, 174 test sources.
- Warnings: the job's warning block is only emitted on a red build, so no
  warning inventory was captured for the green run. Not claimed as zero.

**A workflow change this pass, because the logs were unreadable.** The GitHub
API serves job logs from the end under a cap of roughly 13–20k characters, and
the mid-job "Summarise tests" step falls off the back of that window. The
`test.log` artifact is also unreachable from this environment — the agent proxy
returns `CONNECT tunnel failed, response 403` for
`productionresultssa2.blob.core.windows.net`. Three red runs were diagnosed by
guessing before the final `Summarise errors` step was changed to reprint every
failing assertion; the fourth was read straight off the log. The proxy was not
worked around, and TLS verification was not disabled.

---

## L. Screenshots

Screenshots run #95 on `ed5bb63`: success. The workflow commits its output to
`docs/screenshots/` on the branch (`391da9a`), which is the only reason these
were readable at all — the artifact upload is behind the same blocked blob
host as `test.log`.

**Coverage.** 43 renders. The large-text pass was widened this session from 3
screens to 9 at AX5 (`accessibility-extra-extra-extra-large`): Today, Sleep
detail, Trends, Patterns, Coach, Evidence, Journal, Settings, Tomorrow — plus
AX1 (`accessibility-medium`) for Today and Trends, and `tomorrow` added to the
default-size loop.

**What the AX5 renders showed.** Two real layout defects, both fixed in this
branch and **both still unverified** — confirming them needs another
screenshots run:

- **Evidence.** The "Where the numbers come from" row is an `HStack` whose
  default centre alignment floats its 14pt icon down beside the *subtitle*
  once the two lines wrap to eight, leaving the title it labels alone at the
  top. The icon now moves above the text at accessibility sizes.
- **Journal.** The day-picker chips are a hard `.frame(width: 46, height: 62)`.
  At AX5 both lines truncate to an ellipsis and the logged-dot overflows the
  bottom edge — a horizontal strip of identical `...` chips you cannot pick a
  day from. The box now grows with the text; the strip already scrolled.

The other seven AX5 screens and both AX1 screens hold: text wraps rather than
clips, nothing overlaps, and content continuing under the tab bar is ordinary
scroll-view behaviour rather than a defect.

**One defect found and deliberately not fixed.** On Today, the recovery radar's
markers collide with the ring's centre type at middling scores — the HRV marker
lands on "RECOVERY" and the heart marker on the percent sign. This is **not** an
accessibility regression; it is present at the default text size
(`today-day.jpg`) and predates this pass. A marker's distance from the centre
*is* its value, so the markers cannot be moved aside without changing what the
chart says, and every fix that keeps them in place (a scrim, a text shadow) is a
colour-scheme judgement that cannot be checked from here without spending
another full screenshots cycle per attempt — and the app has a light mode. It is
recorded here rather than guessed at.

**Never rendered.** No Watch screen, no complication, no widget on a home
screen, no light-mode render of the two fixed screens, and no device capture of
anything. The simulator's HealthKit store is empty, so every screenshot is mock
data.

---

## M. Remaining limitations

### Not implemented from the brief

§22 Personal Sensitivity Curves, §23 Restorative Windows, §24 Shift Roster
Planner, §25 Awakening Inspector upgrade, §26 Morning Alertness, §27 Movement
Context refinement, §28 Long-Term Resilience UI, §29–§36 visual system, §37
Watch information architecture, §38–§39 Soundscapes and Breathing, §40 Dawn
theme, §41 motion pass, §42 splash audit, §43 NightSky profiling, §44 widgets,
§52 performance pass, §54 full visual regression review.

§22 additionally needs storage that does not exist: `BehaviorObservationRecord`
holds yes/no/unknown with no `quantity`, `unit` or `eventTime`, so a dose- or
time-resolved curve can only be built today for naps (NapStore has real
start/end), workouts (`lastWorkoutHoursBeforeBed`) and caffeine amount
(`lateCaffeineMg`). A curve for anything else would be invented.

### Hardware never exercised

No physical iPhone. No Apple Watch — no Watch layout, complication, Quick Log
acknowledgement, Always-On or disconnected-sync behaviour was run. No real
HealthKit store: every HealthKit path is exercised only through mock data and
the simulator's empty store. No real EventKit store, so A1's fix is verified by
unit tests over its resolver and **not** by a Calendar permission prompt or a
real event on a real device. No microphone, so on-device dictation has never
transcribed anything. No AlarmKit. No App Intents or Siri invocation. No
widget or complication rendered on a home screen. No background delivery. No
signed archive, no TestFlight build from this branch.

### Known gaps in coverage

- A11 (custom-behaviour retraction) has no direct test.
- The Coach confirmation UI has no automated test; the catalogue's contract
  does.
- `SleepOpportunity`'s "lower than usual" gate, the Runway's habit fallback and
  the nap matcher are all tested at the engine level and have never been seen
  on screen.

### Not production ready

This branch has not been archived, signed, submitted, or run on a device. The
statement "production ready" is not supported by the evidence in this document
and is not made.
