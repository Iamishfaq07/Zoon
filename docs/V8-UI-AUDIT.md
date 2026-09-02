# Zoon V8 — UI Audit (pre-implementation)

Measured against `main` at `6b3a08b`. Numbers come from grepping the source,
not from memory: `.glassCard()` appears **149** times across 59 files; Today
alone stacks **14** independent cards on a full-data morning.

## Cross-cutting findings

| # | Finding | Evidence |
|---|---|---|
| 1 | Nearly every unit of content is wrapped in the same 24pt-radius glass card | 149 `.glassCard()` call sites; `TodayView` 7, `SleepDetailView` 8, `JournalView` 7 |
| 2 | Today is a vertical list of ~14 cards (~6 screens of scroll) | `TodayView.loadedContent`: hero, brief, check-in, recovery mode, stress, load, workouts, pulse, sleep strip, countdown, tonight, autopilot, personalization, energy, light coach, battery, radar, insight, footer |
| 3 | The same concept is drawn three ways on one screen | Sleep duration appears in the orb centre, `FloatingMetricCluster`, `SleepSummaryStrip`; tonight's bedtime appears in `BedtimeCountdownCard`, `TonightTimelineCard`, `AutopilotCard` |
| 4 | Energy is split across three cards with two different visual grammars | `EnergyForecastCard` (curve), `BodyBatteryCard` (chart + 3 stats), `dailyLoadRow` |
| 5 | Purple is the ground of everything | `Theme.background` bottom stop `(0.078, 0.063, 0.200)`, `heroGlow` `(0.35, 0.30, 0.95)` |
| 6 | Charts are mostly interactive already (good) | 9 of 10 chart files carry `chartXSelection`/`DragGesture`; `SoundscapeView` Canvas is the exception (decorative, fine) |
| 7 | Fixed-height text containers | `HealthPulseStrip` tiles, `AchievementsView` 26pt title rows, `EnergyForecastCard` 44pt horizon |
| 8 | Dynamic Type is capped app-wide | `zoonTypography()` → `.accessibility3` |
| 9 | Decorative motion is already restrained (good) | Only 3 `repeatForever` sites: onboarding, soundscape wave, `breathing()` for live sessions |
| 10 | Section headers use icon + title; the "kicker" editorial style exists only in `InsightCard` | `SectionHeader` (34 files) vs `InsightCard.kicker` |

## Screen classification

| Screen | Class | Why |
|---|---|---|
| **Today** | **REDESIGN** | 14 cards; verdict, brief, energy, tonight all fragmented; 6+ screens of scroll |
| **Sleep tab** (`SleepTabView`) | **RESTRUCTURE** | Opens with Sleep Need before Last Night; hypnogram is a 74pt preview inside a card |
| **Sleep detail** (`SleepDetailView`) | **RESTRUCTURE** | 8 cards; Need before hypnogram; story is a card of text rows |
| **Hypnogram** | **VISUALIZE** | Good Canvas + scrub; needs edge-to-edge size, overlay toggles, awakening zoom |
| **Insights** (`TrendsView`) | **RESTRUCTURE** | Hero + digest cards are good; `insightsHub` is a Settings-style link list; 4 stacked chart cards |
| **Coach tab** | **SIMPLIFY** | "What Zoon can see" capability card is a list; suggestions are plain text rows |
| **Coach chat** | **VISUALIZE** | Answers are prose; no data rendering |
| **Body Clock** | **KEEP / polish** | Already a 24h dial; add scrub-to-hour |
| **Body Signals** (`HealthRadarView`) | **VISUALIZE** | `BaselineLaneView` exists; needs LOW/NORMAL/HIGH labels and exact value |
| **Sleep Debt** | **VISUALIZE** | Number + chart; needs reservoir/arc metaphor |
| **Cause Finder** | **KEEP / polish** | `PairedDotPlot` exists; add connectors + animation |
| **Experiments** | **VISUALIZE** | Progress text; needs trial ribbon |
| **Zoon Twin** | **VISUALIZE** | Text output; needs what-if slider with uncertainty bands |
| **Sleep Map** | **VISUALIZE** | 3×3 grid; constellation is a later phase |
| **Evidence** | **VISUALIZE** | Rows; needs belief-history timeline |
| **Sensor Truth / Data Quality** | **VISUALIZE** | Rows; needs coverage matrix |
| **Journal** | **KEEP** | Input surface; cards are semantic groupings |
| **Settings / More** | **KEEP** | Genuinely a settings list |
| **Onboarding** | **REDESIGN** (later phase) | Begins with permissions |
| **Watch** | **SIMPLIFY** (later phase) | Reproduces phone metrics |
| **Widgets** | **KEEP** | Already glanceable |


## Today — card-by-card decision

| Current element | Decision | Destination |
|---|---|---|
| `heroSection` (orb + text beside) | Redesign | Full-width hero: greeting → orbit → duration → Sleep/Need/Debt row |
| `FloatingMetricCluster` (3 glass pills) | Restyle | Typographic three-column row, no pills, same links |
| `briefCard` (waterfall + tip) | Merge | Into **Morning Brief** (one insight, "Best move", "Why?" disclosure) |
| `InsightCard` | Merge | Into Morning Brief (headline source) |
| `MorningCheckInCard` | Keep | Only card on Today — it is an input control |
| `RecoveryModeCard` / enable link | Conditional | "Worth noticing" slot when active; enable link in footer |
| `StressCard` | Conditional | "Worth noticing" when not calm; always in Energy detail |
| `dailyLoadRow` | Relocate | Energy detail |
| `TodayWorkoutsCard` | Relocate | Energy detail |
| `HealthPulseStrip` | Keep, un-card | Sits on the page between hairlines |
| `SleepSummaryStrip` | Remove from Today | Already leads the Sleep tab; duplicate |
| `BedtimeCountdownCard` | Merge | Tonight timeline header ("Bed in 4h 12m") |
| `TonightTimelineCard` | Replace | `ZoonTimeline` (vertical, now-marker) |
| `AutopilotCard` | Merge | Bed node of Tonight carries the autopilot target + shift |
| `PersonalizationProgressCard` | Conditional | "Worth noticing" fallback when nothing else is notable |
| `EnergyForecastCard` | Replace | `EnergyHorizon` on the page; card kept in Energy detail |
| `LightCoachCard` | Conditional | "Worth noticing" slot; Energy detail |
| `BodyBatteryCard` | Relocate | Energy detail; current level shown in horizon readout |
| `HealthRadarCard` | Conditional | "Worth noticing" when active (already reachable from Pulse → Signals) |
| `footer` | Keep | Source + updated |

**Before:** 14–17 cards, ~6 screens. **After:** 1 card, ~2 screens.

## Colour decisions

* Ground: bottom stop moves from violet `(0.078, 0.063, 0.200)` to deep
  blue-black `(0.055, 0.070, 0.160)`; hero glow from indigo-violet to moon
  blue at lower opacity. Purple stays as the *sleep* accent, not the room.
* Light: middle/bottom stops move from lavender to cool white / blue-grey.
* New semantic families in `Theme.Family` (sleep, recovery, circadian,
  breathing, bodySignals, energy, attention, deviation) alias existing metric
  hues wherever one already carries that meaning, so nothing already drawn
  changes hue silently.

## What is deliberately *not* touched

* No algorithm in `Shared/` changes. Every new visual reads existing values
  (`SleepIntelligenceScore.Component`, `EnergyForecast.curveSamples`,
  `SleepAutopilot.Plan`, `HealthRadar`, `StressScore`, …).
* No feature is deleted. Relocations are listed above and in the final report.
* Deployment target stays iOS 18; Liquid Glass stays `#available`-gated.

---

# FINAL REPORT

## Screens redesigned

| Screen | Classification | What changed |
|---|---|---|
| Today | REDESIGN | Full-width hero (greeting → `LunarOrbit` → duration → Sleep/Need/Debt), Health Pulse strip, single Morning Brief, one `EnergyHorizon` replacing three energy cards, one Tonight timeline absorbing Autopilot, one conditional "Worth noticing" |
| Sleep tab / Sleep detail | RESTRUCTURE | Opens on **Last Night**, not Sleep Need; `HypnogramV4` is the hero; Sleep Story; typographic metric board; Need/Debt/naps/tools follow |
| Insights (`TrendsView`) | RESTRUCTURE | Sleep Health hero, `InsightsStream` ("what changed"), Sleep System as visual navigation, `DiscoveriesStream`; the Settings-style hub list is gone |
| Body Signals (`HealthRadarView`) | VISUALIZE | `ZoonBaselineLane` per signal with LOW / YOUR NORMAL / HIGH and exact value |
| Body Clock | VISUALIZE | `ZoonBodyClockOrbit`, scrub-to-hour |
| Sleep Debt | VISUALIZE | `LunarReservoir` |
| Cause Finder | VISUALIZE | `ZoonPairedPlot` — real matched pairs, dots then connectors |
| Experiments | VISUALIZE | `ZoonTrialRibbon` replaces "Logged N of M days" + progress capsule |
| Zoon Twin | VISUALIZE | `ZoonWhatIfLab` with two uncertainty bands |
| Patterns / Sleep Map | VISUALIZE | `ZoonConstellation` leads the screen |
| Evidence | VISUALIZE | `ZoonEvidenceLedger` belief history |
| Data Quality / Sensor Truth | VISUALIZE | `ZoonCoverageMatrix` |
| Coach | SIMPLIFY + VISUALIZE | Analytical categories on landing; `CoachDataAnswer` renders the app's own chart in answers |
| Onboarding | Partial | Infinite decorative pulse removed; value-first ordering was already correct |

## Components introduced

`ZoonHeroMetric`, `ZoonMetricRow`, `ZoonSectionHeader`, `ZoonEvidenceBadge`,
`LunarOrbit`, `EnergyHorizon`, `ZoonTimeline`, `HypnogramV4`,
`ZoonBaselineLane`, `ZoonBodyClockOrbit`, `LunarReservoir`,
`ZoonUncertaintyBand`, `ZoonTrialRibbon`, `ZoonPairedPlot`,
`ZoonCoverageMatrix`, `ZoonConstellation`, `ZoonEvidenceLedger`,
`ZoonWhatIfLab`, `ZoonChartScrubber` + `ScrubCursor`, `ZoonEmptyState`,
`MorningBrief`, `TonightSection`, `WorthNoticing`, `InsightsStream`,
`DiscoveriesStream`, `LastNightComponents`, `CoachDataAnswer`, plus
`ZoonMotion`-equivalent additions to `Motion` (`drawOnce`, `Motion.scrub`,
`Motion.respecting`) and `Haptics.scrubDetent` / `.milestone`.

## Cards removed / consolidated

`.glassCard()` uses in `Zoon/Views`: **147 → 135**, but the headline number
understates it — Today went from **14 cards to 1** (the Morning Check-In,
which is an input control and genuinely a container). The remaining
`glassCard` uses are concentrated in Journal, Settings, and tool screens
where a card is a real semantic grouping. Every new visualization sits
directly on the page via `pageSection()`.

## Interactive charts

`LunarOrbit` (scrub components), `EnergyHorizon` (24h scrub),
`HypnogramV4` (scrub + overlays + awakening zoom), `ZoonBodyClockOrbit`
(rotate to hour), `ZoonPairedPlot` (vertical pair scrub),
`ZoonWhatIfLab` (slider → band), `ZoonUncertaintyBand`,
`ZoonTrialRibbon` (tap day), `ZoonConstellation` (tap node / edge),
plus the pre-existing Swift Charts screens, which keep `chartXSelection`.

## New gestures

Ring scrub (orbit, body clock) · horizontal chart scrub (hypnogram, energy
horizon) · vertical pair scrub (paired plot, press-and-hold first so it
cannot steal the page's scroll) · tap-to-zoom on an awakening · tap node /
tap edge on the constellation · tap day on the trial ribbon.

## New animations, and why each exists

| Animation | Reason |
|---|---|
| Entry cascade (`Motion.Delay`) | Establishes reading order: background → hero → value → supporting |
| Orbit resolve, **once** | Shows the score arriving at its value; never rotates continuously |
| `drawOnce` graph reveal | Shows a series' direction; keyed on data identity so scrolling never replays it |
| Scrub highlight / dim | Shows which datum is selected |
| Paired-plot two-beat (dots, then connectors) | Separates "here are your nights" from "here is the relationship between them" |
| Baseline dot settle | Shows where today sits in the personal band |
| Uncertainty band width change | Shows confidence changing — the one thing a what-if must not fake |
| Ledger row reveal in date order | Shows a belief forming over time |
| Numeric text transitions | Counts a changed value rather than snapping |

All route through `Motion.respecting(reduceMotion:)`; with Reduce Motion on,
travel and scale become crossfade or instant, and **no interaction is lost**.

## Accessibility improvements

* App-wide Dynamic Type cap **removed** (`.accessibility3` → full
  `.accessibility5`); layouts fixed with `AdaptiveStack` / `ViewThatFits`
  instead of clamping text.
* Every new chart has a `chartSummary(label:summary:)` high-level VoiceOver
  summary plus a selected-value description — values and units, never
  "purple line".
* Evidence strength encoded by **dash pattern**, magnitude by **thickness**,
  coverage by **fill vs outline** — never colour alone; text labels always
  present.
* Constellation VoiceOver hints match what a tap actually does.
* Generous hit targets; whole-chart scrub surfaces.

## Dark / Light changes

Light mode designed independently, not inverted: `Theme.adaptiveMetric`
supplies per-appearance hues, `pageSection` uses hairlines rather than grey
cards, and Light captures of Today / Settings / Journal stay in the
screenshot regression set. The identity moved off blanket purple — purple is
now the *sleep* family only, with recovery emerald, circadian amber,
breathing aqua, body-signals lavender, energy blue→gold.

## Performance considerations

* Zero `.repeatForever` outside `BreathingModifier`, whose remaining uses are
  genuinely live (nap timer, sound session, snore check).
* `drawOnce` prevents off-screen rows re-animating on scroll.
* No `TimelineView`, particle systems, or simultaneous `Canvas` scenes.
* GPU-friendly properties only: opacity, scale, offset, shape trim.
* Constellation draws only the focused node's edges, so the graph never
  renders forty lines.

## Existing features relocated (old → new)

Battery / Energy / Forecast cards → one `EnergyHorizon` (+ `EnergyDetailView`) ·
Autopilot card → Tonight timeline · Stress / Daily Load / Vitals / Radar /
AI cards on Today → conditional "Worth noticing" or their own screens ·
Insights hub link list → `DiscoveriesStream` + Sleep System visual nav ·
`PairedDotPlot` → `ZoonPairedPlot` · `BaselineLaneView` → `ZoonBaselineLane`.

## Existing functionality preserved

Confirmed. No algorithm in `Shared/` changed. The one model-layer edit was
additive: `JournalCorrelator.Finding.pairDeltas` became a derived property
over a new `pairs: [Pair]` array, so the view can draw both ends of each
matched pair. Statistics, thresholds, and confidence rules are unchanged.

## Build results

`Build` workflow green on the branch: **Validate project file**, **Build app
and widget** (iOS + widget + Watch + Watch widget targets via the generated
pbxproj), **ZoonTests**, **ZoonUITests**, and **"Verify every source
compiled"** all passing.

## Real-device visual testing still required

CI renders the app in a booted Simulator (`iPhone 17 Pro`) and now captures
`evidence`, `patterns`, `sensorTruth` and largest-Dynamic-Type Today / Sleep
detail / Insights. Still **not** verified anywhere automated:

* Live Activities and the Watch app — the Simulator capture covers neither.
* Real haptics: `scrubDetent` intensity across orbit, hypnogram, ribbon and
  paired plot can only be judged on a device.
* Liquid Glass on iOS 26 hardware vs the `#available` material fallback.
* Smallest supported iPhone (SE) and the largest Pro Max at accessibility
  sizes together.
* Increased Contrast, Reduced Transparency, Bold Text.
* Scroll/animation profiling under Instruments on device (Today, hypnogram,
  constellation, what-if slider, body clock).
* True 1-year-history and night-shift datasets; mock data covers new-user,
  30-day, poor-night and empty states only.

## Phases not completed

**Phase 7 (Watch / Widgets / Onboarding) is only partially done.** Widgets
were classified KEEP and are unchanged; onboarding lost its infinite
animation but was not restructured into the three UNDERSTAND / LEARN / PLAN
scenes; and `WatchRootView` still mirrors phone metrics rather than being
rebuilt as three glanceable pages. These are stated here rather than
implied complete.
