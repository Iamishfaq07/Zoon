# Zoon algorithm specifications

These specifications describe shipping code on `codex/deep-audit-release`. Code is authoritative; version changes are required when a score’s meaning, weights, or normalization changes. All outputs are wellness information and must avoid diagnosis, causation, and fitness-for-duty claims.

## Shared contract

- Inputs retain unit and source metadata from HealthKit adapters.
- No missing physiological measurement is replaced with a favorable population default.
- Available components may be renormalized only when completeness/confidence is carried with the result.
- Baselines use prior nights only; the night being scored is excluded.
- Scores are clamped to their documented range and keep missing data missing.
- Every active score exposes drivers or components; historical snapshots retain their scoring version.

## Sleep episode and source arbitration

- **Purpose:** construct one non-overlapping main sleep and optional secondary episodes.
- **Inputs:** attributed `HKCategorySample` sleep intervals, source/device, stage, local time zone; manual naps are separate.
- **Window:** anchored HealthKit changes within the 90-day sync window; sessions are rebuilt from complete boundary ranges.
- **Rules:** normalize intervals, arbitrate overlapping writers, preserve stage/source provenance, prevent duplicate duration, classify the main block with shift-work-aware day boundaries.
- **Missing behavior:** no samples means no night; non-staged “asleep” remains valid without invented stages.
- **Tests:** `SleepSessionBuilderTests`, source arbitration/attribution tests, day-boundary, DST, nap-overlap, and incremental sync tests.
- **Allowed wording:** “Health recorded…” and exact source. **Disallowed:** asserting Watch wear or permission denial from an empty read.

## Duration, time in bed, efficiency, WASO, continuity

- **Purpose:** describe the observed sleep opportunity and fragmentation.
- **Inputs/units:** interval minutes; staged awake/asleep segments when present.
- **Rules:** duration is unioned asleep time; time in bed cannot be below sleep duration; efficiency is asleep ÷ opportunity × 100. WASO is awake time strictly between first and final asleep segment; non-staged data uses whole-session awake as a labeled proxy. Continuity blends efficiency 50%, WASO ratio 30%, awakening rate 20% through the anchor curves in `SleepIntelligenceScore`.
- **Missing behavior:** continuity is omitted when asleep duration is zero.
- **Tests:** score, session, wake-count, WASO, duplicate interval, and staged/non-staged tests.

## Sleep Intelligence v3

- **Question:** how solid was the sleep period itself?
- **Inputs:** sleep minutes, computed sleep need, efficiency/WASO/wake rate, regularity index, habitual midpoint, optional staged Deep/REM pattern.
- **Weights:** Duration 0.40; Continuity 0.30; Regularity 0.20; Timing 0.05; Stage Pattern 0.05.
- **Normalization:** piecewise-linear anchors in `Shared/SleepIntelligenceScore.swift`; included weights renormalize to one.
- **Baseline:** regularity and timing use the bounded habit window; timing drift is measured on the 24-hour circle; stage pattern requires at least five staged prior nights and robust z-scores.
- **Missing behavior:** unavailable components are excluded; `dataCompletenessPercent` and `MetricConfidence` disclose coverage, and confidence is insufficient below 70% completeness (Duration alone is never enough). Recovery, HRV, RHR, temperature and breathing do not affect this score.
- **Bands:** Poor <50; Fair 50–69; Good 70–84; Excellent ≥85.
- **Tests:** `SleepIntelligenceScoreTests`, `ScoreMeaningTests`, `FlagshipScoreTests`, `SleepVocabularyTests`.
- **Allowed:** “Sleep Intelligence,” “Duration held the night back.” **Disallowed:** “Your body is ready,” diagnosis, or claiming stages are directly measured by Zoon.

## Legacy SleepScore

- **Purpose:** compatibility display for old snapshots.
- **Inputs:** duration, efficiency, and staged Deep/REM only when actually present.
- **Missing behavior:** absent stages are excluded and remaining weights renormalize. They are never imputed from efficiency.
- **Tests:** `SleepScoreTests`, snapshot compatibility tests.

## Sleep Need and learned need

- **Question:** what planning target fits tonight?
- **Inputs:** user goal or qualified learned need, recent weighted shortfall, prior strain, naps, achieved minutes.
- **Rules:** learned need is conservative and history-gated; `SleepNeed` applies bounded adjustments and reports each contribution.
- **Missing behavior:** absent strain contributes nothing; absent learned history uses the explicit user goal, not a hidden demographic value.
- **Tests:** `SleepNeedTests`, `LearnedSleepNeedTests`, `SleepSufficiencyEngineTests`, `SleepAutopilotTests`.
- **Allowed:** “estimated need/target.” **Disallowed:** a clinical prescription.

## Recent Sleep Shortfall (`SleepDebtCalculator`)

- **Question:** how much recent weighted shortfall is present against the selected nightly target?
- **Units/rule:** minutes; each night adds `max(need − sleep, 0)` and prior state decays by about 0.933 per night. Surplus does not create banked credit.
- **Window semantics:** exponential recent weighting approximates a two-week balance; it is not a literal hour-for-hour physiological debt.
- **Missing behavior:** missing per-night need uses the documented goal used for that historical calculation; the UI marks the output estimated.
- **Tests:** `SleepDebtCalculatorTests`, `SleepAutopilotTests`, `SensorTruthTests`.
- **Allowed:** “recent sleep shortfall,” “planning estimate.” **Disallowed:** “you owe exactly 4.7 hours” or “one long sleep repays it.”

## Regularity, SRI, body clock, social jet lag

- **Purpose:** quantify timing stability and habitual midpoint.
- **Inputs:** local bedtime/wake intervals using each night’s recorded time zone.
- **Window:** bounded recent habit window; Regularity requires seven nights; Body Clock reports estimate status until its threshold.
- **Rules:** circular clock arithmetic prevents midnight discontinuities; SRI uses consecutive day comparisons and does not bridge missing days; social jet lag compares obligation/free-day midpoints when enough examples exist.
- **Missing behavior:** no zero-valued “regularity” is passed as measured evidence.
- **Tests:** `SleepRegularityTests`, `SleepRegularityIndexTests`, `BodyClockTests`, DST/time-zone and shift-work tests.

## Recovery

- **Question:** how prepared does the body appear for today?
- **Inputs:** nightly HealthKit HRV SDNN in milliseconds, true RHR, respiration and sleep sufficiency as defined in `RecoveryScore`. Wrist-temperature delta is not a Recovery input; it is surfaced through Vitals / Health Radar only.
- **Baseline:** per-metric median of a recent window; minimum seven usable samples per metric. Confidence is insufficient below 7 nights, low at 7–13, moderate at 14–29, high at 30+ and is further limited by component coverage.
- **Source continuity:** each nightly feature retains measurement provenance. A source switch is visible in Sensor Truth and must be considered before a trend claim.
- **Missing behavior:** unavailable inputs are excluded and confidence falls; sleep alone cannot create a stateable Recovery score.
- **Tests:** `RecoveryScoreTests`, `RecoveryBaselineTests`, `RecoveryConfidenceTests`, outlier and complication-band tests.
- **Allowed:** “appears lower than your baseline.” **Disallowed:** “ill,” “safe to train,” or comparison with another person’s HRV.

## Strain and workout load

- **Purpose:** summarize activity context used by sleep need and guidance.
- **Inputs:** workouts, active energy, duration, and available heart-rate context; output scale 0–21.
- **Missing behavior:** no workouts/energy yields missing or low-evidence context rather than invented exertion.
- **Estimate path:** without heart-rate zones, `StrainScore.estimate` maps active energy above a 250 kcal sedentary allowance (×0.07) plus exercise minutes (×0.15) through the same logarithmic curve as the zone path, flagged `isEstimate`. Anchors: 150 kcal/0 min → 0 (Light); 400 kcal/30 min → ≈9.6 (Moderate); 800 kcal/60 min → ≈13.5 (Strenuous); 1200 kcal/90 min → ≈15.3 (High).
- **2026 path:** completed-workout `HKWorkoutZoneGroup` time-in-zone can improve intensity context only behind iOS/watchOS 27 availability checks and with an older-device fallback.
- **Tests:** `StrainScoreTests`, workout summary/edge tests, multiple-workout and midnight cases.

## Physiological Load — Experimental (`StressScore`)

- **Question:** are today’s quiet HR/HRV samples shifted in the load direction?
- **Inputs:** average waking HR and HRV; workouts plus 30 minutes and active-energy hours ≥150 kcal/hour are removed.
- **Baseline:** currently overnight RHR/HRV; minimum seven baseline nights. This context mismatch is disclosed on every surface.
- **Normalization:** HR deviation maps around 0.5 across ±20%; inverse HRV deviation maps around 0.5 across ±35%; available components average and clamp to 0…100.
- **Missing behavior:** no live signal or no baseline returns nil. The UI says quiet data is unavailable; it never returns the former fake 50.
- **Promotion gate:** remove Experimental only after historical waking quiet samples are stored by local-time bucket with adequate coverage and real-device validation.
- **Tests:** `StressScoreTests`, `DateIntervalSubtractingTests` and HealthKit adapter tests.

## Body Battery / energy reserve

- **Purpose:** interpretable wellness reserve, not a sensor or Garmin-equivalent score.
- **Inputs:** overnight charge from Recovery/sleep sufficiency; daytime drain from hourly HR relative to a personal RHR and max HR.
- **Provenance:** `personalBaseline`, `nightlyRestingHeartRate`, `sleepingLowEstimate`, or `unavailable`.
- **Missing behavior:** no baseline returns one overnight reserve point and no fabricated daytime curve. Non-personal sources set `isEstimate` and display a reason.
- **Tests:** `BodyBatteryTests`, bounds and provenance cases.

## Estimated Alertness (`EnergyForecast` / `CognitiveEnergyCurve`)

- **Purpose:** rough wake-relative outlook, never a circadian-phase measurement.
- **Inputs:** wake time, estimated shortfall, optional Body Clock; the richer cognitive curve can use HRV ratio, overnight HR dip, sleep stages and shortfall when present.
- **Rules:** fixed broad rise/peak/dip/second-wind/wind-down anchors with bounded nudges. Display windows are ±45 minutes with a personal body clock and ±75 minutes otherwise.
- **Confidence:** moderate with qualified Body Clock, low with generic wind-down.
- **Missing behavior:** absent physiology is neutral and named in the richer curve’s missing-input list; the simple forecast stays visibly heuristic.
- **Tests:** `EnergyForecastTests`, `CognitiveEnergyCurveTests`, `BodyClockAgendaTests`.

## HRV status and Vitals / Health Radar

- **Purpose:** report sustained personal-baseline drift without diagnosing its cause.
- **Inputs:** HRV, RHR, respiratory rate, SpO2, wrist temperature, sleep duration and Apple breathing classification.
- **Baseline:** robust personal history, per-signal availability and repeated-night rules. HRV status compares the most recent seven nights (including tonight) against a baseline of up to 90 nights that excludes that comparison week; the balanced range is at least ±5% of the baseline mean. Health Radar activates on multi-signal or sustained change rather than a single noisy value.
- **Missing behavior:** each signal remains unavailable independently. Raw breathing percentage does not invent a clinical threshold.
- **Tests:** `HRVStatusTests`, `VitalsStatusTests`, `HealthRadarTests`, `BreathingHealthTests`.

## Breathing disturbance and apnea summaries

- **Purpose:** display Apple’s public sleep-breathing measurement and classification conservatively.
- **Rule:** Apple’s `HKAppleSleepingBreathingDisturbancesClassification` decides elevated/not-elevated when present. Unclassified raw percentages are trends only; Zoon does not invent severity cutoffs.
- **Missing behavior:** unclassified and unavailable are distinct from not elevated. The respiratory-rate baseline and its deviation require at least seven prior nights with a reading.
- **Tests:** `BreathingHealthTests`, Sensor Truth and report tests.
- **Allowed:** “Apple classified repeated nights as elevated; review in Health.” **Disallowed:** apnea diagnosis.

## Naps and day boundaries

- **Purpose:** add verified secondary sleep once, adjust remaining need, and drive a timer/Live Activity.
- **Rules:** HealthKit and manual naps are reconciled; overlaps with main sleep do not double duration; shift-work day ownership follows the configured schedule; running timers use absolute start/end instants.
- **Tests:** `NapStoreTests`, `SleepDaySummaryTests`, overlap, stale timer and deep-link tests.

## Caffeine cutoff, daylight and cycle context

- **Purpose:** optional planning context.
- **Inputs:** body-clock/target timing and explicit HealthKit lifestyle permissions; menstrual-flow permission is requested separately.
- **Rules:** cutoff is general guidance, not a metabolism measurement. Cycle output is descriptive, history-gated and non-diagnostic.
- **2026 gate:** menopausal state may refine wording only after final API validation and separate explicit consent.
- **Tests:** `CaffeineCutoffTests`, `LifestyleInsightsTests`, `CyclePhaseTests`.

## Behavior associations, experiments and evidence

- **Question:** what is associated with different outcomes in this person’s history?
- **Inputs:** explicit yes/no/unknown behavior observations paired with comparable nights; journal free text is parsed into editable proposals before confirmation.
- **Rules:** matched comparisons control weekday/shortfall/bedtime; unknown is never no; minimum matched pairs and bootstrap confidence gates apply. Guided experiments distinguish adherence from observation and preserve protocol/version in `EvidenceLedger`.
- **Missing behavior:** insufficient samples return no claim.
- **Tests:** `JournalCorrelatorTests`, `GuidedExperimentTests`, `ExperimentEvidenceTests`, `EvidenceLedgerTests`, Natural Journal tests.
- **Allowed:** “associated with,” sample size, interval. **Disallowed:** “caused,” treatment advice.

## Forecast uncertainty and calibration

- **Purpose:** show a range and test whether Zoon’s past ranges contained actual outcomes.
- **Rules:** robust history intervals, explicit nights-used count, moving-block bootstrap for overlapping nightly forecasts, and calibration states based on Wilson-style uncertainty.
- **Missing behavior:** no interval until history qualifies.
- **Tests:** `UncertaintyForecastTests`, `CalibrationLedgerTests`, context forecast and property-bound tests.

## Validation plan

Automated properties include score bounds, component weights summing to one, no fabricated improvement from missing inputs, interval de-duplication, snapshot schema migration, robust-outlier resistance, DST/time-zone arithmetic and stale-snapshot behavior. Device validation must add source-switch cohorts, Series 12 dense-sampling aggregation, sparse older-Watch cohorts, shift workers, travel, low-power nights, workout-after-wake, and repeated alertness check-ins. Any recalibration changes the relevant algorithm version and requires before/after backtests.
