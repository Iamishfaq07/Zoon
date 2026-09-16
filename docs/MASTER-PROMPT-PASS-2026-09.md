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

### C6 — Restorative Windows (§23)

```
Purpose:      name the stretches of today where this person's physiology sat
              below their own usual figure for that hour.
Files:        Shared/RestorativeWindow.swift,
              Zoon/Views/Components/RestorativeWindowsCard.swift,
              Zoon/Services/SleepDataCoordinator.swift (refreshRestorativeWindows),
              Zoon/Services/HealthKitManager.swift (binnedActiveEnergy,
              binnedHeartRateVariability), Zoon/Views/EnergyDetailView.swift
Inputs:       five-minute heart rate, five-minute active energy, sparse HRV,
              DaytimeBaseline (per-three-hour-block median and MAD, quiet
              samples only), workouts + 90-minute buffer, sleep.
Gates:        all three the brief names -- movement low (150 kcal/hour pro
              rata, the same figure the baseline itself excludes on),
              coverage sufficient (60% of a run's bins carry a reading), heart
              rate favourable against the *comparable* personal baseline
              (-0.5 robust z inside the block's own spread). Minimum 15
              minutes.
Refusals:     no qualifying baseline block, no window -- a fixed bpm threshold
              across a day marks every morning and no evening, which is a
              clock reading. Degenerate block spread is refused rather than
              divided by. An absent movement reading is not a low one. The
              card renders nothing at all when the list is empty, because an
              empty list and an empty Health store are the same array.
HRV:          describes a window, never decides one. Most five-minute bins
              hold no SDNN reading, so a gate on it would reject almost every
              genuine window; absence is stated rather than implied away.
Language:     "Your physiology was relatively settled during this period." No
              "calm", "relaxed", "mindful" or "meditation" anywhere -- a
              settled autonomic state is not a settled mind.
Tests:        ZoonTests/RestorativeWindowTests.swift -- 20 cases. Green on the
              first run (#1507), after the thresholds and the run-splitting
              were simulated in Python first.
Limitations:  never seen with a real HealthKit store, so the five-minute
              series' real sparsity is unmeasured; no screenshot, because the
              simulator's store is empty and the card correctly renders
              nothing.
```

### C7 — Shift Roster Planner (§24)

```
Purpose:      plan the sleep around a work roster, for the people Zoon's
              circular-time machinery already serves better than most apps.
Files:        Shared/ShiftRoster.swift, Shared/ShiftPlan.swift,
              Zoon/Views/ShiftRosterView.swift,
              Zoon/Views/Components/ShiftPlanCard.swift,
              Zoon/Models/UserPreferences.swift, Zoon/Views/SettingsView.swift,
              Zoon/Views/ZoonTomorrowView.swift
Model:        the roster is stored as the rule the person entered -- start,
              length, repeating weekdays -- not as the dates it produces. A
              rule set up in March still generates the right days in
              September. Occurrences resolve in the local calendar, so a 22:00
              shift starts at 22:00 on both sides of a clock change; an
              instant would not. An occurrence belongs to the day it *starts*
              on, so a night shift is not counted under two days and planned
              around twice.
Classifying:  against this person's own habitual sleep, never the clock. An
              18:00-02:00 shift takes three hours off somebody who sleeps
              23:00-07:00 and nothing at all off somebody who sleeps
              03:00-11:00. The habit is SleepRunway.Habit, already built on
              the shifted circular scale, so the roster and the runway cannot
              disagree about when this person sleeps.
Scope:        one sleep need around one shift, not a need per calendar day the
              shift spans. A night worker's cycle is not a day, and slicing it
              at midnight asks for sixteen hours of sleep in thirty-six.
Shortfall:    comes from the *next* shift. A single shift leaves an unbounded
              window behind it and its shortfall is honestly zero; back-to-back
              nights are what squeeze it.
Caffeine:     CaffeineCutoff, anchored on the sleep that follows the shift,
              which for a night puts the cutoff mid-shift. Reused rather than
              re-derived, and it keeps its own refusal to print a time long
              past. The nap is deliberately not an anchor -- eight hours before
              a thirty-minute nap would land in the previous night.
Refusals:     no habit, no plan; a clock guess would be wrong for exactly the
              people this exists for. No schedule import: the brief allows one
              "where appropriate" and EventKit cannot tell a work calendar from
              any other, so guessing would produce a roster nobody entered. A
              shift over 16 hours or under 30 minutes is a typo and is not
              expanded. A shift with neither weekdays nor a date never happens
              rather than defaulting to every day.
Positioning:  the one thing the brief rules out. No fatigue score, no
              fitness-for-duty verdict, nothing about being safe to work or
              drive. `ShiftPlan.bannedPositioning` names those words and the
              tests hold every line to that list and to
              `DiagnosticLanguageGuard`, across six shift shapes.
Tests:        ZoonTests/ShiftRosterTests.swift (14) and ShiftPlanTests.swift
              (23). Green on the first run (#1513) after three real defects
              were caught by Python simulation rather than by CI -- see below.
Limitations:  no screenshot: the card only renders for somebody who keeps a
              roster, and the screenshot fixtures have none. The commute is a
              single figure nobody has measured. Never seen on a device.
```

**Three defects the simulation caught before they cost a CI cycle**, all in
the first draft of `ShiftPlan`:

1. **The nap was unreachable.** With a 60-minute lead before leaving and a
   90-minute floor on a sleep window, the two conditions were mutually
   exclusive — every nap the code could describe was one it would never place.
   Restructured: what is left before a shift, when it is under a sleep cycle,
   *is* a nap and is named one.
2. **The shortfall was always zero**, because the post-shift window was
   unbounded and absorbed whatever the pre-shift window could not. It is now
   capped by the next shift, which is the only thing that can squeeze it.
3. **A doc comment was wrong about the code.** It claimed a 22:00 shift would
   not displace somebody who sleeps from 03:00; it displaces three of their
   eight hours. The threshold was right and the example was wrong, so the
   example changed rather than the threshold.

### C8 — Awakening Inspector, upgraded (§25)

Filed under features rather than bugs because the screen was not wrong — it was
honestly reporting a limitation, and the work was removing the limitation.

```
Purpose:      show a real ±12-minute context window around an awakening, with
              the layers the brief lists: stage, heart rate, movement, sound,
              respiratory.
Files:        Shared/AwakeningInspector.swift,
              Zoon/Views/Components/AwakeningInspectorCard.swift,
              Zoon/Services/HealthKitManager.swift (binnedRespiratoryRate),
              Zoon/Services/SleepDataCoordinator.swift (refreshAwakeningSeries),
              Zoon/Views/SleepDetailView.swift
What changed: the screen printed "Zoon doesn't read heart rate minute by
              minute yet" -- true when written, because the only overnight
              series fetched was hourly and an hourly bucket cannot place a
              rise inside a four-minute awakening. `binnedHeartRate` already
              took any bin width, so the fix was to go and get the resolution
              rather than to relax the standard. Heart rate, active energy and
              respiratory rate are now fetched across the night at one-minute
              bins, once per night rather than once per awakening.
Bin width:    one minute, not the five §23 uses. At five, a ±12-minute window
              holds three bins before the awakening -- not enough to be a
              baseline *and* a candidate, so the rise could never have fired.
              Found by simulation, before CI. Every gate counts readings
              rather than bins, because at this width most bins are empty.
Refusals:     the rise is measured against the awakening's own preceding
              minutes, never a population figure or the night's average -- a
              heart rate that runs high all night has not risen. Fewer than
              three readings behind a candidate means no rise rather than a
              guess. Movement is inferred from active energy and carries that
              provenance wherever it appears, because Zoon has no overnight
              motion stream. Breathing is a difference within this person's
              own night, never against a reference range.
Disclosure:   the trace sits behind a DisclosureGroup and is dropped entirely
              at accessibility sizes, where the markers carry every figure it
              does. Gaps are drawn as gaps -- joining across unmeasured
              minutes reads as a steady heart rate rather than as an absence.
Language:     the brief's sentence is unchanged: "These events occurred around
              the same time." Nothing claims cause.
Tests:        ZoonTests/AwakeningInspectorSeriesTests.swift (18). The four
              existing AwakeningInspectorTests are untouched -- the handed-in
              entry point still works and the derivation delegates to it, so
              the timeline, sounds and caveat live in one place.
Limitations:  never seen against a real HealthKit store, so the true overnight
              sparsity of a one-minute series is unmeasured. The movement
              proxy has never been checked against an actual motion reading.
              No screenshot of the expanded trace.
```

**A test of mine that would have failed on correct copy.** The language sweep
initially checked every line for the word "caused", including the caveat — which
mentions cause precisely in order to disclaim it ("Zoon does not claim that one
caused the awakening"). The caveat is now asserted on its own terms and exempted
from the blanket sweep. A guard that fires on the sentence the brief asks for is
a broken guard, not a finding.

### C9 — Morning Alertness, improved (§26)

The brief says "improve, do not rebuild", and the check itself was fine: six
trials, a median, a lapse count, a self-rating. What it lacked was everything
that decides whether those numbers mean anything.

```
Purpose:      let six taps say something, but only once they have earned it.
Files:        Shared/AlertnessCheck.swift,
              Zoon/Services/AlertnessCheckStore.swift,
              Zoon/Views/AlertnessCheckView.swift
Added:        interquartile range, false starts, time since waking, trial
              count -- the four things §26 asks to track that were not kept.
              The spread matters most: a steady 305 ms and a 305 ms built from
              200 and 600 are the same median and not the same state.
Practice:     the trap the engine exists for. Reaction time falls over the
              first few attempts because the task is being learned, so an app
              plotting session one against session three reports an
              improvement it caused itself. The first three sessions are
              excluded from every baseline, and no comparison is offered until
              five more exist after them -- the first verdict lands on session
              nine. Simulated before writing the Swift; the first draft was
              off by one on the countdown.
Like with like: a check twenty minutes after waking is not compared against
              one six hours later. Sleep inertia moves reaction time more than
              most of what this is looking for, so a 90-minute tolerance
              applies and "nothing comparable" is a stated outcome rather than
              a silent average.
Withholding:  the screen says which of practice or baseline-building it is
              waiting for, and how many checks remain. Silence would read as
              an app that does nothing with this.
Bugs fixed:   (1) the reaction timer called `.now` twice, once for seconds and
              once for attoseconds, so the two halves came from different
              instants -- jitter in the one thing on that screen that is a
              measurement. (2) the store dropped runs under the trial minimum
              while the screen said "Saved on this device" either way; `save`
              now returns nil and the screen says "Not saved". (3) v1 records
              cannot be reconstructed, so migrated sessions carry *absent*
              fields rather than zeros -- a zero spread claims a perfectly
              consistent run and a zero false-start count claims there were
              none.
Lapses:       threshold stays at 500 ms because that is the published
              convention, and now carries `lapseCaveat`: six taps is not a
              ten-minute vigilance task, and printing the count bare borrows
              an authority this does not have.
Tests:        ZoonTests/AlertnessCheckTests.swift (25), plus three existing
              store tests carried onto the new API.
Limitations:  no screenshot -- the interesting states need nine stored
              sessions and the fixtures have none. Never run on a device, so
              the true tap latency of the hardware is unmeasured and is part
              of every figure here. `practiceSessions = 3` is the low end of
              what the literature reports; it is a judgement, not a
              measurement of this task.
```

**Two red runs, both mine, neither in the engine.** Run #1521: a fixture
argument out of order and a key-path map whose root could not be inferred once
the first error broke the array literal — the app target built clean, only
`ZoonTests` failed. Run #1523: renaming `AlertnessCheckStore.results` to
`sessions` broke three pre-existing tests in `NaturalJournalTests.swift`. **I
changed a type's public surface without grepping for its callers**, which is the
same sweep this pass did carefully for `Finding.tag` and skipped here. Green on
#1525.

A note on reading CI from this environment: `list_workflow_jobs` served stale
step data for ten minutes after the job finished, which made a 6m27s UI-test
step look like a twenty-minute hang. `get_workflow_job` against the job id
returns the true state. Worth knowing before diagnosing a stall that is not
happening.

### C10 — Personal Sensitivity Curves (§22)

§M carried this as blocked for most of the pass, and it is still blocked for
most behaviours. The brief's instruction for that case is to implement the
strongest defensible alternative and document the limitation, so this builds
the four dimensions that carry a real number and names the three it cannot.

```
Purpose:      move past binary behaviour labels wherever a dose or a time
              actually exists.
Files:        Shared/SensitivityCurve.swift, Shared/Statistics.swift
              (unpairedBootstrapCI),
              Zoon/Views/Components/SensitivityCurveCard.swift,
              Zoon/Services/SleepDataCoordinator.swift (sensitivityCurves),
              Zoon/Views/EvidenceView.swift
Built:        late caffeine in mg, last workout in hours before bed, nap
              duration in minutes, nap start hour. All four read a real
              quantity off a night or the nap store.
Refused:      caffeine *timing* (only the late total is stored, not each
              drink's clock time), light timing (daylight is a daily total),
              workout load (intensity is not carried on a night). Named in the
              app beside the curves, not only here -- a feature that silently
              covers half of what it was asked about reads as broken.
Method:       bands, not a fitted curve. A smooth line through a few dozen
              nights implies a resolution nobody has, and its shape between
              two sparse regions is the model talking. Each band needs 5
              nights; a curve needs 2 qualifying bands, because one group has
              nothing to be compared against.
Statistics:   `unpairedBootstrapCI` added. The existing paired bootstrap
              resamples a list of differences, valid only when each value is a
              difference between two observations of the same thing. The
              nights at 200 mg are different nights from those at 50 mg and
              there is no pairing; using the paired interval would have
              reported a band far narrower than the data supports.
The verdict:  three answers, where most apps ship two. Interval excludes zero
              -> association. Interval sits entirely inside the outcome's own
              practical threshold -> a meaningful difference has been *ruled
              out*, the brief's "little observed difference". Interval spans
              both -> uncertain, because calling that "no effect" claims a
              null nobody established.
Nap asymmetry: for duration a napless day is a real zero and is the control
              band; for timing it has no nap hour at all and drops out rather
              than being placed in one.
Surface:      on Evidence, as the brief asks. Intervals are folded away rather
              than dropped -- several bands will rest on five or six nights
              and hiding their width would leave the verdicts looking more
              certain than they are. Only an association is tinted; colouring
              "uncertain" would turn a statement about evidence into a verdict
              about the behaviour.
Tests:        ZoonTests/SensitivityCurveTests.swift (18).
Limitations:  no screenshot -- every curve needs five nights per band in two
              bands, and the screenshot fixtures have nothing like that, so
              the cards correctly render nothing. The band edges (100/200 mg,
              3/6 hours, 15/35 minutes) are conventional cup and nap scales,
              not measurements of this person. Never seen against a real
              HealthKit store.
```

**The storage change that would unblock the rest.** `BehaviorObservationRecord`
would need a `quantity`, a `unit` and an `eventTime`. With those, caffeine
timing and light timing become the same engine with different bands; without
them, any curve for those is drawn through a yes and a no.

**A flake, distinguished from a failure.** Run #1529 was red on
`ZoonUITests.testCoreSleepAndCoachFlowsOpen` with "Timed out while launching
application via Xcode" — not an assertion. Four things said infrastructure:
`testLaunchesToTabBar` passed exercising the same tabs, `ZoonTests` passed in
full, the failure was a launch timeout, and the commit touched only `Shared/`
files that had no caller in app code yet. Re-run and the following commit's run
(#1531) both passed the same test in 3m29s. Recorded rather than quietly
re-run, because "it was flaky" is the easiest thing in the world to say about a
real failure.

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

**Suite size.** 1,914 `func test…` methods across 180 files in `ZoonTests`,
plus 2 methods in `ZoonUITests`. Counted from source; the per-suite tally the
runner prints sits mid-log and is not reachable through the API (see K).

**Result on `ed5bb63`** — Build run #1501, job "Build (iOS Simulator)". Build
run #1503 on `dbc7531`, the head of this branch, is green on the same steps:

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

**Later reds, all in the seams rather than the arithmetic.** Every engine added
after this section was first written went green on its first run — the Python
pre-simulation caught three dead-constant bugs (§24's nap, §25's five-minute
bin, §26's practice countdown) before CI ever saw them. The two reds that did
happen, both on §26, were a fixture argument out of order and a rename I made
without grepping for its callers. The pattern is worth recording plainly: the
arithmetic has been the reliable part, and the joins around it have not.

**Not tested.** Nothing here ran on hardware. See M.

---

## K. Build

`xcodebuild` on `macos-latest`, iOS Simulator destination. Every verification
in this document is a 12–20 minute CI round trip; there is no local compile.

- **Build runs #1501 (`ed5bb63`), #1503 (`dbc7531`), #1507 (`d79e077`),
  #1513 (`9fac96b`), #1517 (`b718fab`), #1525 (`c295cfc`) and #1531
  (`7535a89`, the branch head): success.** Both jobs green — "Validate project
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
branch and both **re-rendered and confirmed** by screenshots run #96 on
`dbc7531`:

- **Evidence.** The "Where the numbers come from" row is an `HStack` whose
  default centre alignment floats its 14pt icon down beside the *subtitle*
  once the two lines wrap to eight, leaving the title it labels alone at the
  top. The icon now moves above the text at accessibility sizes.
- **Journal.** The day-picker chips are a hard `.frame(width: 46, height: 62)`.
  At AX5 both lines truncate to an ellipsis and the logged-dot overflows the
  bottom edge — a horizontal strip of identical `...` chips you cannot pick a
  day from. The box now grows with the text; the strip already scrolled.

After the fix, `evidence-largeText.jpg` shows the icon leading the row from
above with the chevron opposite it and both lines of text reading in full, and
`journal-largeText.jpg` shows "Wed 16", "Tue 15", "Mon 14" as distinguishable
chips scrolling horizontally.

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

§27 Movement Context refinement,
§29–§36 visual system, §37 Watch information architecture, §38–§39 Soundscapes
and Breathing, §40 Dawn theme, §41 motion pass, §42 splash audit, §43 NightSky
profiling, §44 widgets, §52 performance pass, §54 full visual regression
review.

Six corrections to an earlier draft of this list. §22 Personal Sensitivity
Curves, §23 Restorative Windows, §24 Shift Roster Planner, §25 Awakening
Inspector and §26 Morning Alertness are now implemented — see C6 through C10.
§22 is implemented only for the dimensions that carry a real quantity; C10
names the three it still cannot build and the storage change that would
unblock them. §28 Long-Term Resilience UI was listed as a gap and
is not one: `LongTermBaselineCard` reached `TrendsView` on `main` before this
pass began, and A6 rewrote the engine behind it rather than adding the
surface.

That §22 note is now C10's subject rather than a gap: the curve engine ships
for exactly the dimensions named there — naps, workout timing and caffeine
amount — and the app itself names the three it cannot build. The storage
change that would unblock those is a `quantity`, a `unit` and an `eventTime`
on `BehaviorObservationRecord`.

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
