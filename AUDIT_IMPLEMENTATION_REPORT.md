# Audit implementation report (Deep Audit 2026)

What was changed in response to `Zoon_Claude_Code_Deep_Audit_2026.md`, how
it was verified, and what was not done and why. Baseline facts are in
[`AUDIT_BASELINE.md`](AUDIT_BASELINE.md).

This repository has no local Mac. Every build and test below ran in GitHub
Actions on the `macos-26` image with Xcode 26.6 (iOS/watchOS 26.5 SDKs). No
change was verified on a physical iPhone or Apple Watch; the device QA matrix
(audit §26) is open and listed under release blockers.

Branch: `claude/check-this-out-t0epv2`, from `main` at `12ddd69`.

## Result at a glance

| Area | Before | After |
|---|---|---|
| **Sleep Intelligence** | v3. Stage Pattern compared Deep/REM *minutes*, so a short night was penalised twice (Duration, then Stage Pattern). Stages from any source counted, against any source's history. An inferred time in bed was scored as a measured efficiency. A night 3 h short could still read "Good" if the other components were perfect. | v4. Stage Pattern compares *share of staged sleep*, only on stages `StageTrust` accepts, against the last 30 trusted nights **from the same kind of source**; omitted with fewer than 5. Estimated windows score WASO + awakening rate and say so. A transparent severity ceiling (60 min short → ≤84, 120 → ≤69, 180 → ≤49) with the uncapped sum stored and shown. v3 payloads decode unchanged. |
| **Shortfall** | One stored number, `sleepDebtMinutes`, was the shortfall *entering* a night. Coach read it as "after last night" and told people a 5½-hour night "did not add to your sleep debt". Type named `SleepDebtCalculator`; comments still said "14-day". | `RecentSleepShortfall`; three named figures (`shortfallBeforeNightMinutes`, `shortfallAddedByNightMinutes`, `shortfallThroughNightMinutes`) from one `step` function the history series also uses. Coach answers from the night's own added figure, and says it can't say when the night's need is unknown. Stale comments corrected. |
| **Coach** | The Apple Intelligence insight's `likelyCause` was free text: numbers were grounded, causes were not (it could name caffeine nobody logged). "Do I have sleep apnea?" contained "sleep" and was answered with last night's duration. No evaluation corpus. | The model returns a `driverID` chosen from the rules that actually fired tonight; the shown sentence is the rule's own; an unoffered id rejects the whole generation back to rules. Medical-condition questions get a fixed referral that neither diagnoses nor reassures. Answers show the span they are about. 22 questions × 5 night types evaluated on every CI run; diagnosis, unknown-evidence, invented-number and instruction-leak rates are required to be 0. |
| **Snore** | Confidence came from detector agreement only: 31 minutes of monitoring an 8-hour night could read "High confidence, no snoring", and the result card headlined it as "0% of the night". | Final confidence = min(detector, **coverage**), coverage = monitored ÷ intended window (tonight's sleep opportunity), less interruptions. Low coverage with no events says "No conclusion". The card's percentage is labelled "of monitored time" and sits beside monitored time, coverage, interruptions and quality. Coverage % stored with each night. |
| **Audio** | Recorded beds looped with `AVAudioPlayer.numberOfLoops = -1` under a comment claiming a crossfade that did not exist (audible click every ~87 s). Noise synthesised per-sample with system RNG **on the main actor**. Interruption resume ran `try? setActive(true)` then told every owner to resume regardless. Narrator used the default voice and rate. | Each bed decoded once off the main actor and turned into a seamless loop (2 s equal-power crossfade of tail into head), looped sample-accurately on `AVAudioPlayerNode`. Noise rendered by a `NoiseRenderer` actor with a deterministic SplitMix64 generator; main actor only schedules finished buffers. Resume retries activation 3× with backoff and notifies owners only on success. One speech profile and voice choice for narrator and breathing coach. |
| **HealthKit reads** | 16 `try? await healthKit…` in the coordinator (+4 in `FeatureExtractor`): access off, locked phone, unsupported type and query failure all looked like "no sample". | 0. Every read goes through `HealthRead`, returning `MetricFetchState` and recording the reason (category only, never the raw error) in `FetchDiagnostics`, cleared by the next success. Data Quality shows "What Zoon couldn't read" per source. Values unchanged: `nil` is still unknown. |
| **Persistence** | 10 `(try? context.fetch…) ?? []`. A failed lookup-before-insert **inserted a duplicate** night/episode/journal day/answer/revision. `isEmpty` answered "empty" on a read failure — the condition that lets sync accept an empty HealthKit fetch and prune. A backup taken during a read failure wrote a valid-looking partial archive. No versioned schema. | 0. Reads say found / absent / unreadable; an unreadable store is not empty; writers that cannot check for an existing row write nothing and mark the batch unpersisted (the HealthKit anchor stays, the night is retried); prune deletes nothing it cannot read; a backup gathered across any failed read is refused. `ZoonSchemaV1` + `ZoonMigrationPlan`, with a test that opens a store written the old unversioned way. |
| **UI / accessibility** | Accessibility audit logged and passed. No String Catalog. No long-string or right-to-left check. Sleep detail showed a different score from the Sleep tab for the same night. | A new kind of accessibility issue fails CI; known kinds are counted against a per-tab baseline. String Catalogs in app, widget and watch. A UI test launches with doubled-length strings and forced RTL and must reach every tab. Personal learning shows an "unlock map" built from the engines' own thresholds. Sleep detail shows the flagship score. |

## Baseline

See `AUDIT_BASELINE.md`. In short: `main` at `12ddd69`, CI run 35930540150
green; **2,449** unit tests and **3** UI tests, 0 failures; accessibility
audit **103** issue lines (106 on the first run with the pinned toolchain,
run 35994647333 — the demo night's labels are generated relative to the run
date); no Release build in CI; no Xcode 27 on any GitHub-hosted image.

## Bugs fixed

Each is a behaviour a person could have seen, with the commit that fixed it.

1. **Short nights penalised twice** by Sleep Intelligence (Duration and Stage Pattern). `01e9c53`
2. **Stage Pattern compared across vendors** — a change of watch read as a change in sleep. `01e9c53`
3. **Inferred time in bed scored as measured efficiency.** `01e9c53`
4. **A severely short night could headline as Good.** `01e9c53`
5. **Coach said a 5½-hour night "did not add to your sleep debt"** because it read the shortfall entering the night. `f2767bd`
6. **Coach answered "Do I have sleep apnea?" with last night's duration.** `2685afe`
7. **Apple Intelligence could name an unlogged cause** (free-text `likelyCause`). `2685afe`
8. **"High confidence, no snoring" from 31 minutes of an 8-hour night**, headlined "0% of the night". `d38c152`, `ea78c53`
9. **Audible click at every recorded-bed loop point.** `ec783cd`
10. **Noise synthesis on the main actor** (hundreds of thousands of RNG calls per 5 s buffer competing with the UI). `ec783cd`
11. **Owners told to resume on a dead audio session** after an interruption. `ec783cd`
12. **Night narration in the default voice at conversational speed; two screens could narrate over each other.** `18308a4`
13. **Duplicate rows on a failed store lookup** (nights, episodes, journal days, behaviour answers, evidence revisions). `d035b7f`
14. **An unreadable store read as empty**, licensing an empty-fetch prune. `d035b7f`
15. **Partial backups that looked complete.** `d035b7f`
16. **Unsynchronised `SoundEventClassifier`** under `@unchecked Sendable`: `stop()` could clear the analyzer and handler while the audio tap was mid-call. `a6934c4`
17. **Algorithm spec described v3 and named a test file that did not exist.** `0aa970a`
18. **Two scores for one night:** Sleep detail showed the legacy SleepScore (93) while the Sleep tab showed Sleep Intelligence (78). Found in the refreshed screenshots.
19. **"Light sleep sleep resumed"** (and "Asleep sleep resumed") in the awakening inspector. Found in the refreshed screenshots.

## Regressions caught during the work

Two failures introduced on this branch were caught by CI before anything
shipped, and are recorded because both are the kind of thing to watch for:

- **Launch hang (`d035b7f`, fixed in `749172c`).** Recording each store
  read's outcome mutated an `@Observable` property, and stores are read
  inside SwiftUI view bodies. An observable property's modify accessor
  registers an access before it mutates, so every such body came to depend
  on the log it wrote and re-rendered forever; all four UI tests timed out
  on their first query. Unit tests passed throughout. Recording now goes to
  unobserved storage and is published a turn later, only on change, with
  `withObservationTracking` tests pinning it.
- **Stage Pattern "ordinary night" test (`01e9c53`, fixed in `696475e`).**
  The v4 fixture put tonight exactly on the history median, which the curve
  treats as its best case; the test now uses a typical distance and a new
  test bounds the median night's bonus.

## Algorithm and version changes

| Item | Change | Version |
|---|---|---|
| `SleepIntelligenceScore` | Stage composition, trusted/same-source baseline, estimated-window continuity, severity ceiling | 3 → **4** (`currentVersion`); v3 payloads decode as v3 |
| `RecentSleepShortfall` (was `SleepDebtCalculator`) | Renamed; single `step` used by accessors and series; semantics unchanged numerically | — (no stored meaning changed) |
| `SnoreMonitoringConfidence` | `min(detector, coverage)`; `NightSummary.coveragePercent` added (optional, old summaries decode) | — |
| Insight generation | `GeneratedInsight.likelyCause: String` → `driverID: String` validated against offered drivers | Prompt contract; `InsightCache.algorithmVersion` unchanged because cached entries are keyed by the full instructions text, which changed |
| Persistence | `ZoonSchemaV1` (identical models) + `ZoonMigrationPlan` (no stages) | Schema 1.0.0 |
| Speech | `SleepSpeech.Profile.breathing` 0.85× rate / 0.92 pitch (as before); `.narration` 0.9× / 0.95 with 0.45 s sentence pauses (was default rate, no pauses) | — |

`docs/ALGORITHM-SPECS.md` documents v4 and the shortfall figures.

## Files

About 80 files changed since `12ddd69` across 19 commits (new files in **bold**):

- Scoring and semantics: `Shared/SleepIntelligenceScore.swift`, `Shared/RecentSleepShortfall.swift` (renamed), `Shared/SleepNightFeatures.swift`, `Shared/CoachEvidence.swift`, **`Shared/InsightDriver.swift`**, `Shared/SnoreEpisodeAggregator.swift`, **`Shared/LearningUnlockMap.swift`**
- Audio: **`Shared/NoiseGenerator.swift`**, `Shared/SessionRecoveryPolicy.swift`, `Zoon/Services/SoundscapeEngine.swift`, `Zoon/Services/AudioSessionCoordinator.swift`, **`Shared/SleepSpeech.swift`**, **`Zoon/Services/SpeechVoices.swift`**, `Zoon/Services/OnDeviceNarrator.swift`, `Zoon/Services/BreathingCoach.swift`, `Zoon/Services/SoundEventClassifier.swift`
- Reads and persistence: **`Shared/FetchState.swift`**, **`Zoon/Services/HealthFetchClassifier.swift`**, **`Zoon/Services/StoreRead.swift`**, `Zoon/Services/SleepDataCoordinator.swift`, `Zoon/Services/FeatureExtractor.swift`, `Zoon/Services/SleepHistoryStore.swift`, `Zoon/Services/JournalStore.swift`, `Zoon/Services/BehaviorObservationStore.swift`, `Zoon/Services/EvidenceLedgerStore.swift`, `Zoon/Services/PersistentStore.swift`
- Insights: `Zoon/Insights/FoundationModelInsightEngine.swift`, `Zoon/Insights/RuleBasedInsightEngine.swift`
- Snore: `Zoon/Services/SnoreDetector.swift`, `Zoon/Services/SnoreSessionController.swift`, `Zoon/Services/SnoreStore.swift`, `Zoon/Views/SnoreCheckView.swift`
- Views: `SleepIntelligenceCard`, `DataQualityView`, `MoreView` (backup guard), `PersonalLearningView`, `HypnogramV4`
- Localization: **`Zoon/Localizable.xcstrings`**, **`ZoonWidget/Localizable.xcstrings`**, **`ZoonWatch/Localizable.xcstrings`**
- CI and tools: `.github/workflows/build.yml`, **`Tools/select-xcode.sh`**, **`Tools/check-build-settings.py`**, `Tools/generate-pbxproj.py`
- Docs: **`AUDIT_BASELINE.md`**, this file, `docs/ALGORITHM-SPECS.md`

## Migrations

- **SwiftData:** no data migration. `ZoonSchemaV1` names the five models every shipped build has written; a store from an earlier build opens as V1 with nothing rewritten. `SchemaMigrationTests` writes a store with the old plain `Schema([...])`, one row of every model with `nightKey`, timezone, source name and bundle id, wrist temperature, journal tags/note, episode, behaviour answer and an evidence revision with `algorithmVersion`, reopens it through the plan, and checks each field. The rules for the first real stage (no deleted rows; provenance and versions preserved; destructive change only after a user-requested export) are written on `ZoonSchemaV1`.
- **Snore summaries:** `coveragePercent` is optional; older stored summaries decode with it absent and are shown without a coverage figure.
- **Sleep Intelligence:** stored v3 scores are not rescored in place.

## Tests added or changed

New test files (all run in CI on every push):

| File | What it pins |
|---|---|
| `SleepIntelligenceV4Tests` | composition vs duration; trust levels; source change; too little history; monotonic Duration/WASO/awakenings; missing-component confidence; severity table and ceiling-never-raises; estimated window; version/cap round-trip; v3 payload decodes as v3 |
| `ShortfallSemanticsTests` | before/added/through accessors; step equals series; Coach: short night after a clean run, modest short night, long night inherits, met need, unknown need, historical night uses its own figure, evidence labels; DST nights; answer timeframes (an older night is never "Last night") |
| `InsightDriverTests` | driver ids stable and ranked; selection resolves only offered ids; "none" tokens; prompt block |
| `CoachEvaluationCorpusTests` | 22 questions × 5 nights; four zero-rate gates; greetings; diagnosis referral; unlogged caffeine; missing HRV |
| `SnoreCoverageTests` | 31 min of 8 h is not high; 7 clean hours can be; interruptions lower coverage; final = weaker of two; no-snore on low coverage says no conclusion; never a medical finding; ratio bounded; result card: no "0%" on a short quiet session, share of monitored time, rows, older summaries |
| `SeamlessAudioTests` | sine seam before/after; loop equals recording outside the fade; too-short refused; loudness through the fade within 1 dB; **every bundled bed's join** (before/after printed); noise determinism, buffer continuity (two renders = one), range, DC drift, colour ordering, harmonic presence; render cost printed |
| `SessionRecoveryPolicyTests` (+3) | no resume on dead session; bounded attempts; late success resumes once with backoff; new interruption stops retries |
| `SleepSpeechTests` | voice ranking (quality, region, whole language codes incl. `yue`), picked voice honoured while installed, fallback, profiles slower than conversation, sentence splitting |
| `FetchStateTests` | state/issue mapping; unknown is never zero; log clears on success, one row per source, bounded; HKError classification; log code carries no message; `HealthRead` records and clears; store lookups found/absent; failed store read counted; backup refusal copy |
| `SchemaMigrationTests` | V1 equals the shipped schema; plan has one version and no stages; old unversioned store reopens with every field |
| `LearningUnlockMapTests` | thresholds are the engines' own constants; order; ties share "next"; nights not dates |

Changed, not deleted: `ScoreMeaningTests` and `ScoreExplainabilityTests`
(fixtures gained a watch source and varied composition — v4 needs spread to
measure; one test that expected the v3 double count now varies composition
at fixed duration; the "ordinary night" fixture moved from the exact median
to a typical distance, and a new test bounds the median night's bonus);
`SnoreEpisodeAggregatorTests` (sessions lengthened to 7 h so coverage is not
the limit); `RecentSleepShortfallTests` (file renamed to match its class).

UI tests: `testAccessibilityAudit` is now a gate;
`testLongStringsAndRightToLeftStillNavigate` is new.

Test counts and measured values from CI: see **CI results** below.

## CI results

**Final run: CI run 36005219698 on `2ab322e`, every job green** (Xcode 26.6,
iOS 26.5 simulator). The measured numbers below are what its audit-metrics
step printed; the strict-concurrency figures are from run 36002012278.

| Check | Result |
|---|---|
| Validate project file, deployment targets / Swift version / String Catalogs | pass |
| Build (watchOS Simulator) | pass |
| Build (iOS Release), warnings as errors | pass |
| `ZoonTests` | **2,573 tests, 0 failures** (baseline 2,449) |
| `ZoonUITests` | **4 tests, 0 failures**: launch, core flows, long strings + right to left, accessibility gate |
| Accessibility, known kinds per tab (found / baseline) | Today contrast 18/16, Dynamic Type 7/6, clipped 4/4; Sleep 22/22, 9/9, 4/4; Insights 7/7, 20/11; Coach 8/10, 17/17. No new kind of issue. |
| Strict concurrency probe | At the time of that run, **65** unique diagnostics (since brought to **0**; now an enforced gate) with `SWIFT_STRICT_CONCURRENCY=complete`: 17 `ZoonIntents.swift`, 12 `Motion.swift`, 3 each `WatchLink`, `SpotlightIndexer`, `SleepHistoryStore`, 2 `SleepFocusFilter`, 1 each in 8 files. By kind: 22 missing `Sendable` conformances, 19 global mutable statics, 12 main-actor calls from nonisolated contexts, 5 `sending` risks, 7 other. |

**Coach evaluation** (`COACH-EVAL`): 110 answers, diagnosis 0, unknown
evidence 0, invented number 0, instruction leak 0.

**Sleep Intelligence severity table** (`SI-v4`, all other components at
their best, Timing absent):

| Short of need | Uncapped | Shown | Band |
|---|---|---|---|
| 30 min | 97 | 97 | Excellent |
| 60 min | 92 | 84 | Good |
| 90 min | 85 | 84 | Good |
| 120 min | 77 | 69 | Fair |
| 180 min | 62 | 49 | Poor |
| 240 min | 58 | 49 | Poor |

**Recorded-bed joins** (`SEAM`, first channel, absolute sample step at the
loop point; "interior max" is the largest step anywhere inside the loop):

| Bed | Before | After | Interior max |
|---|---|---|---|
| storm | 0.1607 | 0.0075 | 0.2010 |
| drizzle | 0.1396 | 0.0037 | 0.3865 |
| purr | 0.1174 | 0.0010 | 0.1131 |
| fan | 0.1102 | 0.0017 | 0.0108 |
| blizzard | 0.1070 | 0.0040 | 0.0162 |
| waterfall | 0.0876 | 0.0215 | 0.1103 |
| wind | 0.0779 | 0.0147 | 0.0595 |
| street | 0.0661 | 0.0126 | 0.9930 |
| harbor | 0.0641 | 0.0198 | 0.2921 |
| rain | 0.0593 | 0.0534 | 0.8032 |
| mountain | 0.0567 | 0.0026 | 0.0286 |
| jungle | 0.0554 | 0.0099 | 0.5175 |
| brook | 0.0545 | 0.0395 | 0.2764 |
| stream | 0.0446 | 0.0030 | 0.2083 |
| insects | 0.0356 | 0.0309 | 0.2790 |
| ocean | 0.0342 | 0.0083 | 0.5156 |
| fire | 0.0316 | 0.0023 | 0.5575 |
| thunder | 0.0285 | 0.0007 | 0.2878 |
| window | 0.0243 | 0.0131 | 0.8021 |
| evening | 0.0218 | 0.0096 | 0.6304 |
| embers | 0.0165 | 0.0023 | 0.7145 |
| garden | 0.0151 | 0.0123 | 0.2761 |
| tent | 0.0146 | 0.0061 | 0.4933 |
| crickets | 0.0132 | 0.0798 | 0.4696 |
| forest | 0.0132 | 0.0031 | 0.3250 |
| rainfall | 0.0070 | 0.0013 | 0.7058 |
| pond | 0.0033 | 0.0369 | 0.2698 |

Every "after" is within the bed's own interior steps, which is the claim the
test enforces. The steady beds whose raw join was a click far larger than
anything inside them -- fan (0.110 against 0.011), blizzard (0.107 against
0.016), mountain, wind -- are the ones the change was for. Two beds (crickets,
pond) have a larger step after than before: their raw ends happened to line
up; after the change the join is an ordinary step inside the recording rather
than a coincidence at the file boundary, and is still well under their
interior maximum.

**Noise render cost** (`NOISE-RENDER`): 141–151 ms across two runs to render one 5-second
buffer on the CI simulator in a Debug build, now on the `NoiseRenderer`
actor rather than the main actor. Not a device figure.

## Screenshots

`docs/screenshots/` holds the 48 "before" captures from `screenshots.yml`.
`screenshots.yml` re-ran on this branch (it is triggered by edits to the
workflow, which pinning its runner made) and committed 46 refreshed captures
in `f8ee945`, built from `749172c`. They show the app launching and
rendering normally after the launch-hang fix. Comparing them with the
"before" set surfaced two pre-existing problems, both fixed after that
capture: the Sleep detail screen showed the legacy SleepScore (93) beside
the Sleep tab's Sleep Intelligence (78) for the same night, and the
awakening inspector read "Light sleep sleep resumed". The unlock map, Data
Quality's read-problems section, the snore result card and Coach timeframes
are newer than that capture and are not in it.

## Battery and performance

Not measured on a device. What can be said from CI:

- Noise rendering moved off the main actor; the per-buffer render cost on
  the CI simulator is printed by `SeamlessAudioTests` (see CI results).
  Simulator timing is not device timing.
- Recorded beds now hold one decoded loop in memory while playing (about
  30 MB for a 90 s stereo bed; a 3-layer scene up to ~90 MB), where
  `AVAudioPlayer` streamed the compressed file. Decoding happens once per
  selection, off the main actor. This trades memory for a click-free loop and
  should be checked on the oldest supported device.
- An 8-hour playback soak, CPU and energy impact (audit §9.2 "Measure") need
  Instruments on a device.

## Accessibility

- **Gate.** Any kind of audit issue the app has never had (missing label or
  description, small hit region, wrong trait, element detection) fails
  `testAccessibilityAudit` on any tab.
- **Known kinds are tracked, not capped.** Contrast, Dynamic Type and
  clipped-text findings are counted per tab against the baseline (Today
  16/6/4, Sleep 22/9/4, Insights 7/11/0, Coach 10/17/0) and printed as
  `A11Y-GATE` lines. They were first enforced as ceilings; the next run
  failed on unchanged code because Insights rendered a card the baseline run
  had not loaded (Dynamic Type 11 → 20) while Sleep's fell (9 → 3). A gate
  that fails at random gets ignored, so the numbers are a to-do list instead.
- The remaining Dynamic Type findings come from `.dynamicTypeSize(...)`
  clamps on rings, tiles and the tab bar and from containers whose text is
  already scalable; the contrast findings from secondary text on the dark
  theme. Listed for fixing, not fixed here (see below).
- New UI in this pass (Data Quality read problems, unlock map, snore result
  rows, Coach timeframe) carries state in text as well as symbol or colour
  and combines each row for VoiceOver. The long-string and right-to-left
  launch reaches every tab.

## Known limitations

- **No device verification.** Everything here is simulator- and unit-tested.
- **HealthKit hides read denial.** When read access is off, HealthKit usually
  returns *no data* rather than an error, by design. "No access" appears only
  when HealthKit reports it (e.g. authorization not determined); otherwise
  the honest state remains "Nothing recorded".
- **Seam test checks the join, not the texture.** A 2 s crossfade removes
  the click; a bed whose character changes over its 90 s can still be heard
  to restart by an attentive listener.
- **Contrast and Dynamic Type regressions are reported, not blocked.** A
  new instance of a known kind shows up as a higher `A11Y-GATE` count, not a
  red build.
- **String Catalogs are empty on disk.** Xcode fills them from
  `SWIFT_EMIT_LOC_STRINGS` on the next build in the IDE; command-line CI
  compiles but does not write them back.

## Not implemented, and why

| Audit item | Status | Reason |
|---|---|---|
| §4 pin Xcode 27 / iOS 27 simulator | Not possible | No GitHub-hosted image has Xcode 27 (`AUDIT_BASELINE.md`). `select-xcode.sh` will pick it up automatically; `ZOON_REQUIRE_XCODE_MAJOR=27` makes its absence fail. |
| §7.2 Foundation Models iOS 27 APIs, §7.3 Evaluations framework | Not adopted | Not in the installed SDK; the audit forbids inventing APIs. The deterministic path every answer falls back to is evaluated instead. |
| §11 split `SleepDataCoordinator` | Started | Coach context and the weekly report moved unchanged into `SleepDataCoordinator+CoachContext.swift` (~200 lines; coordinator now ~2,830). The derived-history section was left: moving it would mean exposing the history store to the whole app. Splitting sync and import needs device checks of sync. |
| §12 Swift 6 language mode | Stage 2 done, not flipped | Complete strict-concurrency checking went from 65 diagnostics to **0** and is now an enforced CI gate (Release job). Fixes: immutable intent metadata, `InferSendableFromCaptures` for key paths, `@MainActor` haptics, `Sendable` insight engines and rules, documented `nonisolated(unsafe)` for WatchConnectivity payloads, the HealthKit observer completion and one formatter. One unjustified `@unchecked Sendable` fixed; the other four are lock-guarded. Switching the targets to Swift 6 language mode is the remaining step. |
| §14 fix existing contrast / Dynamic Type findings | Baselined, not fixed | Fixing them blind (no screenshots in the loop) risks layout regressions at accessibility sizes; the gate stops new ones. |
| §15 translations, plurals/units audit | Infrastructure only | Catalogs, settings guard and a pseudolocalization + RTL test exist; translating needs the catalogs populated in Xcode first. |
| §17.1–17.4 UI redesign (native tab bar, Today hierarchy, hypnogram layers, Body Clock), §18 Sound Studio, §20 readiness, §21 room sound | Not done | Design work that needs looking at the result on a device; the audit orders it after P0/P1. |
| §17.5 unlock map | Done | Personal learning, from the engines' own thresholds. |
| §17.6 Coach | Partly done | Each local answer shows the time it is about ("Last night", "Night of …", "Recent nights", "Last N nights", "Tonight"); medical questions get a referral. Deep links from evidence chips, multiple chips per answer and deterministic suggested questions are not done. |
| §19 Snore results | Mostly done | The result card shows monitored time, % of the planned night covered, interruptions, monitoring quality and flagged time, and says "No conclusion" instead of "0%" when coverage is limited; the existing coverage card already draws the interruption gaps. Per-event confidence bands on a timeline are not done. |
| §19 optional audio snippets | Not done, deliberately | Product decision with consent and retention design; not a default. |
| §22 smart alarm | Nothing to change | Confirmed honest: Settings says the wake window is "not a live sleep-stage alarm"; nothing infers wake stage from HealthKit history. |
| §26 device QA matrix | Open | Requires hardware. |

## Release blockers

1. **Device QA (§26)** — at minimum: an overnight Soundscape soak with each
   kind of bed (listen for the loop point; watch memory on the oldest
   supported iPhone), a phone call and Siri during playback, AirPods removal,
   Snore Check across a full night with coverage shown, a HealthKit
   permission revoked mid-use (Data Quality should say so), and a store
   written by the current App Store build opened by this one.
2. **Populate the String Catalogs** by building once in Xcode, and review
   the extracted keys before any translation work.
3. **TestFlight** — dispatching the TestFlight workflow was refused by this
   environment's permissions (production deploy); it has to be run by
   someone with release rights.
