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
