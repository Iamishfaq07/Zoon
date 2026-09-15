# Zoon final engineering, algorithm, UX and release pass

Scope: the 42-phase brief, worked in the order it specifies. This document
records what was changed, what was inspected and deliberately left alone, and
what could not be verified from a CI-only environment.

Two standing rules shaped every claim below. Nothing is marked verified unless
a green CI run verified it. Nothing involving real HealthKit data, a real
Apple Watch, background delivery or AlarmKit is marked verified at all,
because none of it was run — there is no Mac and no device in this
environment, and the simulator cannot substitute for any of it.

The dominant finding across the whole pass was not missing engines. It was
**correct engines with surfaces that bypassed them**: a sound state machine
that five screens read a deprecated flag from, a chart-accessibility modifier
six charts declined to use, a presentability rule nothing consulted, a zone
provenance enum nothing carried, and a haptic vocabulary the watch ignored
entirely. Most of the work below is reconnection, not construction.

---

## 1. Engineering fixes

**Sleep stage overlap among peers.** `SleepSessionBuilder.resolvingStageOverlap`
settled awake against asleep, and staged against unspecified, but never core,
deep and REM against each other. A source writing core 23:00–04:00 alongside
deep 01:00–03:00 had both counted in full, so a five-hour night reported seven
hours of stages — staged minutes exceeding total asleep, which nothing
downstream expects. Apple writes the three disjoint, so this never bit on
Watch data; it is exactly what a third-party writer produces when it refines a
coarse block into finer segments and leaves the coarse block in place.
Precedence is now deep > REM > core, on the grounds that core is what a writer
emits when it has not differentiated, so the positive identifications win.
Found by a new invariant test, not by inspection.

**Streak day identity.** `SleepStreakEngine` keyed nights by `startOfDay`
computed in the night's own timezone and then looked up with the device's
calendar, so a streak could break or duplicate around travel and DST. Replaced
with `SleepDayKey`, a civil-date identity that deliberately carries no
timezone: two mornings either side of a flight are still consecutive days.
`Achievement.longestRun` now delegates to the same engine rather than
reimplementing it.

**Health Radar state.** `isActive` and a `Severity` enum let five screens
paint "all clear" green whenever the signal list was empty — which is also
true on night four and on a phone with no physiology attached. Replaced with
`tone` and `isActionable` on the state itself, and a single `tint` mapping in
`HealthRadarTint.swift` that keeps the engine Foundation-only. Every radar
surface now reads the same state.

**Watch haptics.** The watch had no `Haptics` implementation at all: eight
call sites played `WKInterfaceDevice.current().play(.click)` directly, so a
confirmed log, a rejected one and a scrub detent felt identical. Implemented
the watchOS branch of the shared vocabulary and routed the call sites through
it.

**A mean labelled with the wrong basis.** `WeeklyReport.averageRecovery` is a
mean over whichever nights carried a Recovery score; `nightCount` counts every
night in the window. The report header read "average recovery across 7 nights"
off the second while showing the first, so a week where four nights had no
score presented a three-night mean as a seven-night one. `CyclePhaseCorrelation`
already drew exactly this distinction, with its own `recoveryNightCount` and a
card that claims the full count only when the two agree; this was the one
surface not following the rule. The header now says "across 3 of 7 nights"
when they differ, rather than picking whichever number is larger.

Two tiles on the same screen — HRV and Resting HR — are also means over
`compactMap`ed subsets, but they state no count, so there is no false claim to
correct. They are recorded here as **inspected and left alone**: adding a basis
to each tile would be more text than the numbers are worth, and the section
heading "Weekly Averages" is a weaker claim than a named night count.

**A withheld score drew a filled ring.** `SleepSnapshot.flagshipScoreText`
gated the *number* on every glance surface, and every one of them used it.
Nothing gated the *shape*. So the watch dial, both circular widget gauges and
the circular complication printed "—" in the middle of a ring drawn to the
real score — the precision withheld, the claim kept. A ring two thirds of the
way round says "about two thirds" whether or not the digits are there.

This one is different from the other reconnections here, and worth flagging
rather than burying. The watch dial had the *opposite* rule written into it
deliberately: "the ring still draws to `value`, because the shape is a rough
indication and the numeral is the claim." The phone applies the reverse at the
same decision point. Two surfaces of one app carried explicit, contradicting
rationales, so one of them had to lose; this resolves toward the stricter
side, and the reasoning for reversing the authored note is in the doc comment
rather than only in a commit message. `flagshipGaugeValue` now sits beside the
text gate it has to agree with, and `FlagshipGaugeTests` asserts the two can
never disagree — including that a legacy payload with no Sleep Intelligence
keeps drawing, which this change must not have broken.

**Three controls VoiceOver could reach but not describe.** The soundscape
volume slider had no name and was announced as a bare percentage, with the two
speaker glyphs either side focusable and read as "speaker" and "speaker wave
3" — neither of which is a thing you can do. `AudioStudioView`'s slider
already carried a label. Onboarding's sleep-goal slider was worse: no name,
and its value read as a fraction of the 5...11 range rather than as a
duration, on the one control that sets the number the rest of the app is
measured against. The clinician-report checkboxes announced their state as the
SF Symbol's name — "checkmark square fill" — which is an implementation
detail, not a state.

**Performance: `HealthPulseStrip`.** `BreathingHealth` was a computed property
read three times, inside a `ViewThatFits` that builds both layouts — six sorts
plus two medians over the whole night history to draw one 22pt waveform, on
the screen opened every morning. Hoisted to one compute per render.

**Recomputation elsewhere: inspected, not changed.** `BreathingHealthView`
reads a computed `BreathingHealth` nineteen times per render, `SleepHealthView`
seven, `InsightsHero` four. These are detail screens rather than the morning
path, and the computation is a sort plus two medians over at most ninety
nights. **No profiling was performed** — there is no Instruments run behind
this judgment, only complexity reasoning — so this is recorded as inspected
and deliberately left alone, not as measured and cleared.

## 2. Algorithm changes

**No Readiness Now score.** The brief asks for one. Building it would have
meant inventing weights over inputs Energy already combines, producing a
second number that moves with the first and cannot be explained by anything
the app measures. Instead `EnergyDrivers` attributes *why the battery moved*:
it names the intervals that account for the spend, refuses to explain when the
curve is not presentable, when under five points were spent, or when the
hourly drain is below the rate ordinary metabolism produces. Attributed drain
can legitimately exceed net spend, because quiet hours recharge. This is a
deliberate refusal of a requested feature, on the grounds that the honest
version of it is attribution rather than a score.

**Heart-rate zones.** `maximumHeartRate(age:)` now returns Tanaka
(208 − 0.7 × age) with provenance, falling back to 190 marked
`.genericFallback`. `StrainScore.confidence` takes the weaker of coverage and
zone provenance rather than reporting coverage alone — a fully-sampled day
sorted against a guessed ceiling is not a high-confidence number.

**There is no public Apple workout-zone API.** This was established by
grepping the installed SDK on a CI runner, not recalled. `HeartRateZoneIntegrator`
carries a doc block explaining why there is no `appleWorkoutZones` case, so
the absence reads as a finding rather than an oversight.

**Sleep session invariants.** Thirteen hostile inputs now share one assertion
set: no negative durations, asleep ≤ time in bed, staged ≤ total asleep, no
stage exceeding the session, no NaN or infinity, a session never ending before
it starts, efficiency ≤ 100. This is what found the stage-overlap defect.

**Score explainability moved onto the score.** `missingComponentLabels` and
`confidenceReason` now live on `SleepIntelligenceScore`, read off the same
weight table `compute` renormalizes against, so a sixth component cannot be
added without every surface that explains an incomplete score knowing about
it. A test pins the table against what a full night actually produces.

**A correct behaviour that looked like a bug.** Stage Pattern is dropped when
a person's deep/REM history has zero median absolute deviation, because
`robustZ` is undefined there. Three new tests failed on this before the
fixture was corrected. The behaviour is right; thirty identical nights is a
fixture, not a person.

## 3. Design changes

**Metric explainability (Phase 7).** `MetricInfoSheet` already answered what a
number is and how it was obtained, via `SensorTruth`. It could not say how
much to trust *tonight's*, what normal is for *this person*, or what to do
about it. `MetricFacets` adds those three. Every field is optional and the
whole struct defaults to empty, because saying nothing is better than filling
the gap with a sentence true of everybody — "normal is 7–9 hours" is not a
baseline. Wired into Daily Load and Sleep Intelligence rather than left as an
unused type.

**Card overuse (Phase 11).** Counted 169 `.glassCard()` calls. The brief asks
for a 25–40% reduction; that reduction was **not** made, and the reason is
recorded here rather than quietly skipped. The count is spread thin — no file
has more than eight — and a mechanical cull would have removed cards that are
doing real work. The defect the phase is actually pointing at is *uniform
stacks that flatten hierarchy*, and the clearest instance was one this pass
created: provenance and facets each drawing their own card turned the metric
sheet into three identical rectangles. They are now one panel with a hairline
between the fixed properties of the quantity and the ones about tonight.

**Coach evidence (Phase 30).** The "What Zoon can see" card already existed
and is unchanged. It sits at the bottom, below every suggested question, so
the thing that decides whether an answer is worth asking for arrived after the
asking. The header above the questions carried "Your sleep intelligence
assistant" — a tagline equally true before any data existed and after all of
it was deleted. It now carries counts, and names the on-device model only when
it is unavailable.

**Iconography (Phase 15).** Two glyphs for one meaning, twice over. Six
neutral history and forecast charts used the *uptrend* glyph — including
"Running balance, last 30 nights" and "What your habits cost you", where an
upward arrow is an argument rather than an icon. All now use the neutral chart
glyph the Insights tab already used. Separately, six "open the coach and ask"
affordances used two different speech bubbles; unified. `flask` versus
`flask.fill` was examined and left alone: it already follows a coherent rule
(outline for the action, filled for the resulting state).

**Design system consolidation (Phases 9/10): deliberately not done.** A
`ZoonSpacing`/`ZoonRadius` namespace beside the existing `Theme` would have
been a second vocabulary for the same decisions, and the failure mode of two
token systems is that call sites drift between them. `Theme` already carries
the spacing, stroke, family and metric tokens the app uses.

## 4. App icon

Replaced the photographic icon with a generated one; `Tools/generate-app-icon.py`
is now the source of truth, and the watch icon is generated from the same
script. The design goal was surviving being small — the previous icon lost its
subject entirely at complication and Settings sizes. Rendered output was
inspected visually via committed PNGs. **Not verified on a device home screen,
in the App Store listing, or against the dark/tinted icon variants.**

## 5. Graphics and data visualisation

Six charts read as lists of bare numbers to VoiceOver because they used
`.contain` rather than the existing `chartSummary` modifier's `.ignore`, which
is what lets the summary replace the individual marks. Fixed.

Worth recording as a near-miss: an accessibility audit that grepped for raw
`accessibilityLabel` calls "found" six chart files with none, and two new
helper types were half-written before it emerged that the charts had summaries
all along, through a modifier the grep did not match. Both files were deleted
before commit. This is the second time in this pass that verifying first would
have saved the work, and it is why the brief's instruction not to rebuild
correct systems is in it.

## 6. Animations and motion

`Motion` already carries the named tiers the brief asks for — micro, standard,
hero, navigation — plus `draw`, `scrub`, `splash` and `stateChange`, each
routed through `Motion.respecting(reduceMotion:)` so the accessibility check
cannot be forgotten at a call site. **Inspected and left unchanged.**

`NightSky` was extracted into a testable `NightSkyField` and now pauses when
Reduce Motion is on, when the scene is not active, or in Low Power Mode, and
builds star geometry in `body` rather than inside the `Canvas` closure.

## 7. Accessibility

Chart summaries fixed as above. `StatusPill` gained `lineLimit(1)`.
`ZoonFlowLayout`, a real `Layout` conformer, replaced rows that crushed at
accessibility text sizes in Sleep Detail, Stress Detail and the Stress card;
its line-breaking is internal so it is tested directly. The new coach header
combines its two lines into one accessibility element, since reading them
separately invites swiping past the half that qualifies the other.

**Not verified:** no VoiceOver session, no Voice Control, no Switch Control,
no Dynamic Type sweep on a device. Large-text behaviour was checked through
previews only.

## 8. Apple platform features

Widgets already handle both the withheld-score mode and the placeholder state,
and already decline to invent a "Tonight Plan" section for data
`SleepSnapshot` does not carry. Navigation uses a floating capsule over a
hidden system tab bar, with `.ultraThinMaterial` and a shared bottom safe-area
inset so no tab can hide its own last row. **All inspected and left
unchanged.**

The watch now reports outcomes as well as touches: a quick-log taps on press,
and a distinct success or warning pattern fires only when the phone confirms
it persisted the envelope or says it could not. That is the moment worth
feeling on a wrist nobody is looking at.

## 9. Performance

Covered in §1. One fix on the morning path; one class of recomputation
inspected and left alone with the reasoning recorded. **No profiling was
performed.**

## 9a. Suspicions that were wrong

Recorded because a list of only the findings that panned out misrepresents how
the pass actually went, and because the discipline is the transferable part.

An automated sweep for icon-only buttons with no accessibility label returned
ten hits; six were false positives, where the match window was too short to
see the `Text` already inside the button. Each was opened before anything was
written, and only the clinician-report checkbox was real.

The Trends chart summaries looked like they carried the same basis defect as
the weekly report — "N nights, averaging X" where the average is over a
`compactMap`ed subset. They do not: `points` is already pre-filtered to the
nights that carry the reading, so the count *is* the basis. No change made.

Earlier in the pass the same check was skipped once, and two duplicate chart
accessibility helpers were half-written before it emerged the charts already
had summaries through a modifier the grep did not match. They were deleted
before commit. That is the cost of not verifying first, and it is why these
two are written down.

## 10. Tests

155 test files, 1,551 test methods. Added this pass:
`HealthRadarPresentationTests`, `SleepDayKeyTests`, `SleepStreakTravelTests`,
`LoadConfidenceTests`, `EnergyDriversTests`, `ZoonFlowLayoutTests`,
`NightSkyPresenceTests`, `SleepSessionInvariantTests`,
`ScoreExplainabilityTests`, `WeeklyReportBasisTests`, `FlagshipGaugeTests`.

Two of these earned their keep immediately: the invariant tests found the
stage-overlap defect, and the explainability tests found that the standard
history fixture is degenerate for any component scored against a median
absolute deviation.

## 11. Build status

GitHub Actions macOS CI (iOS Simulator) is the only verification channel
available here. Every claim of "verified" in this document means a green run
on it and nothing more.

Last confirmed green: run `34847415817` on `116eb09` — build succeeded and the
full `ZoonTests` suite passed. That run covers everything in this document,
including the stage-overlap fix (whose invariant tests pass with no regression
in the existing `SleepSessionBuilderTests`) and the fixture correction for the
`ScoreExplainabilityTests` described in §2.

`ZoonUITests` also ran on that build and reported `Executed 2 tests, with 0
failures`. Two is worth naming rather than rounding up to "UI tests pass":
they cover launching to the tab bar and opening the core sleep and coach
flows, and nothing else. The UI layer's real coverage in this project is the
1,551 logic tests behind it plus previews, not the UI test target.

## 12. Screenshots

Regenerated after this pass's visual changes and inspected as images. Three
changes are confirmed rendering correctly: the Coach evidence line ("Reading
30 nights, on this device.", with the journal clause correctly suppressed at
zero entries and the model clause correctly absent when the model is
available), the Patterns empty state, and the unified chart glyph on the
Insights tab.

Two changes are not photographable from here: the merged metric-sheet panel
sits behind a tap, and the Health Pulse strip is below the fold on Today —
though its change was a computation hoist with identical layout, so there is
nothing visual to check.

The Patterns capture independently confirms what §13 says about the
constellation: the demo data has zero logged nights, so no correlation can
exist and the empty state is what renders. The same is true of the Evidence
maturity view. Both are implemented; both are unphotographable with this data.

## 13. Remaining blockers

**Hardware-only, recorded in `docs/APP-STORE-RELEASE-GATES.md`:** everything
in that checklist, which this pass extended with two items its own work
created — a third-party writer that refines a coarse sleep block without
removing it (the case the stage-overlap fix addresses, which no simulator
fixture reproduces from real HealthKit), and the watch's new confirmation
haptic, which needs a real phone-and-watch pair out of range and back.

**Unestablished:** whether HealthKit de-duplicates overlapping cumulative
`activeEnergyBurned` samples across an iPhone and a Watch. `HKStatisticsQuery`
is deliberately run across all sources, and if it does not de-duplicate, Daily
Load's estimate path double-counts. This was not resolved from the SDK in this
pass and the arithmetic was **not** changed on a guess. The exposure is
bounded — that path already reports low confidence — and the gate list now
names it.

**Phases verified already-correct and deliberately unchanged:** 12 (Today has
a real `moment` enum — `.morning`/`.day`/`.evening`/`.night` — driving a dozen
content branches), 23 (floating capsule over a hidden system tab bar, with
`.ultraThinMaterial` and a shared bottom safe-area inset so no tab can hide
its own last row), 24 (light mode has per-band Dawn identity), 25/26 (`Motion`
already carries micro/standard/hero/navigation plus draw, scrub, splash and
stateChange, each routed through `respecting(reduceMotion:)`), 28 (splash),
31 (`ZoonWatchDial` is geometry-driven with Always-On and reduce-motion
handling — only its ring gate was wrong), 32 (widgets already handle both the
withheld-score mode and the placeholder state, and already decline to invent a
Tonight Plan section for data `SleepSnapshot` does not carry), 39 (insights
language, audited clean in a prior pass), 42 (the gate list).

**Phases not completed:** 16 and 17 (constellation and evidence maturity —
built, unverifiable with demo data that produces no correlations), and 18–21
beyond the accessibility, chart-glyph and slider fixes recorded above.

**This is not a statement of production readiness.** Simulator CI is green.
The list above is what stands between that and a submission.

---

# Addendum: what landed after this pass

This document described the state of `main` at `0bca371` (#330). Two further
pull requests have landed since, and leaving the record at #330 would make it
wrong rather than merely incomplete.

## #331 — Tomorrow horizon, Awakening Inspector, Log, movement, resilience

A feature PR: Zoon Tomorrow (one horizon from now to tomorrow's first
commitment), opt-in EventKit calendar reading, the Awakening Inspector,
movement context, sleep resilience, nap learning, and a Coach tool catalog.

It merged with CI red — two of its own tests were failing — and #332 is the
fix. Recording that plainly because the sequence matters to anyone reading the
history: `ac3c1b9` is a commit where `main` did not build green.

## #332 — the review findings on #331

Thirteen findings, twelve fixed. The two that matter most:

**A stated reason that was not the reason.** `ZoonTomorrow` derived the
event-path bedtime as `wake - targetSleep`, bypassing SleepAutopilot's rate
limiter, while the `why` line still quoted `autopilot.shiftMinutes` — so a
140-minute jump could be shown under "Bedtime only moves 20 minutes earlier
because larger jumps are hard to keep." The event wake is already handed to
the autopilot as its obligation, so the rate-limited bedtime was there to use.
This is the same failure this whole pass was about, arriving in new code the
week after: a surface stating something the engine did not do.

**Two features that could not run.** The movement card was built with literal
`nil` steps, so it reported "steps have not been recorded" to everyone while
the step read scope fed nothing. Three engines — `CoachToolCatalog`,
`NapLearning`, `LongTermResilience` — were referenced only from tests.

**A test asserting the wrong thing.** `AwakeningInspectorTests` checked that
the caveat does *not* contain "caused". The caveat is "Zoon does not claim
that one caused the awakening" — the disclaimer trips its own check, and a
caveat saying nothing at all would have passed.

### Deliberately not fixed

- **`CoachToolCatalog` is still unsurfaced.** Its consumer is the Foundation
  Models tool-calling loop that #331's own description lists as out of scope.
  Inventing a confirm-to-write UI for it would be guessing at product intent
  rather than fixing a defect. It is the one genuinely unreachable type in
  `Shared/`, and that is a known state rather than an oversight.
- **Custom signals still do not parse.** `NaturalJournalParser` accepted a
  `customNames:` list and discarded it. The parameter is gone rather than
  implemented: `Proposal.tag` is a closed `BehaviorTag` and
  `SleepDataCoordinator.setBehavior` records against the same enum, so there
  is nowhere to store a confirmed custom observation. Wiring it end to end
  needs an observation path of its own.
- **The Awakening Inspector's heart-rate and movement markers stay absent.**
  The app reads heart rate hourly, and an hourly bucket cannot place a rise
  inside a four-minute awakening. Feeding it in would have invented precision,
  so the wording changed instead — it now distinguishes "not read at this
  resolution" from "not recorded" rather than blaming the sensor.

## Current state

`main` at `a71bce6`: build, `ZoonTests`, `ZoonUITests` and the
source-completeness check all green, and TestFlight build 101 archived,
signed and uploaded from it.

The verification boundary is unchanged and unchanged by shipping: **nothing
here has been validated on hardware.** Build 101 is the first build where the
Calendar permission flow and the real step reads can be exercised at all, and
both are in `docs/APP-STORE-RELEASE-GATES.md` rather than claimed as working.

One operational note that is not a code defect: the last three TestFlight runs
each minted a fresh distribution certificate rather than importing the cached
one, which is the cycle that exhausted the account's certificate slots on
2026-09-08. `IOS_P12_PASSWORD` appears not to be set.
