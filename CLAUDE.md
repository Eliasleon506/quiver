# Quiver — Project Guide

Surf-board recommender: given the surf, your skill/body, and your wetsuit, it picks which board to
ride. Coverage spans the California Central Coast → Santa Barbara → Ventura, plus Costa Rica's
central Pacific (near Esterillos Oeste). iOS-native (SwiftUI + SwiftData, iOS 17+), local-only, free
conditions data (Open-Meteo Marine + Wind, NOAA NDBC buoys, NOAA Tides). Solo-dev, recommender-first.

> Formerly "myCoreLord". Renamed to **Quiver** (target/bundle id `com.eliasleon.quiver`) when the repo
> was published.

## Build / run / test — and the gotchas

- **XcodeGen-driven** (`project.yml`); the generated `Quiver.xcodeproj` references Swift files
  individually, so **a brand-new `.swift` file must be added to the project via a regen**:
  `xcodegen generate`. (xcodegen + gh are installed via Homebrew.)
- **Only iPhone 17-series simulators exist here** (no iPhone 15). Use:
  ```sh
  xcodebuild test -scheme Quiver -destination 'platform=iOS Simulator,name=iPhone 17'
  ```
- Run: open `Quiver.xcodeproj`, pick an iPhone 17 sim on iOS 17+, ⌘R. First launch walks
  onboarding (body metrics → skill quiz) → spot picker → "What to ride". Gear = profile;
  chart icon = the Forecast Accuracy dashboard.
- `LiveConditionsTests` hits the real APIs and is **skipped by default** (flip `runLive = true`).

## Layout

```
Quiver/
  QuiverApp.swift         App entry + SwiftData container
  Main/                   Root nav, RecommendationView ("What to ride")
  Onboarding/             Profile questions + skill quiz
  Spots/                  Spot list / picker + SpotsStore (decodes spots.json)
  Models/                 SwiftData entities + value types + enums
  Resources/spots.json    Seeded spots (36: Central Coast → Ventura, + Costa Rica)
  Conditions/             Open-Meteo + NDBC + NOAA Tides providers (ConditionsProvider protocol)
  Recommender/            The recommendation engine (see below)
  Backtest/               Forecast-accuracy harness (record → reconcile → summarize)
  Forecast/               7-day forecast view + per-day min-volume (ForecastVolume)
  Quiver/                 Board CRUD + standalone dimension recommender
  Support/                Units / formatting
QuiverTests/              XCTest suite (67 tests; RecommenderTests is the engine spec)
```

## Forecast-accuracy backtest (`Backtest/`)

Turns the app into its own forecast-verification harness. `BacktestRecorder` (needs a `ModelContext`)
**captures** each Open-Meteo wave prediction for future hours as a `ForecastRecord` @Model, then
**reconciles** it against the live NDBC buoy reading (already merged onto the same `ConditionsSnapshot`)
once that hour is within ±60 min — no extra network calls. `ForecastAccuracy.summarize` is a **pure**
function (MAE + signed bias in feet, period MAE) with unit tests in `ForecastAccuracyTests`. Surfaced
in `ForecastAccuracyView`, reached from the chart icon in `RootView`. Wired into
`RecommendationView.reload()`. `ForecastRecord.self` is registered in the `ModelContainer` in
`QuiverApp.swift`. Real error stats accrue only with repeated real-world use.

## Spot coverage & regions

`SpotRegion` (in `Models/Enums.swift`) is ordered north-to-south, international last: `centralCoast`
→ `sbNorth` → `sbSouth` → `venturaCounty` → `costaRicaCentralPacific`; `SpotsStore.grouped()` sections
the picker by that declaration order. Costa Rica spots set `ndbcBuoyId`/`tideStationId` to `null` —
`CompositeConditionsProvider` degrades to the global Open-Meteo feeds when they're absent (US-only
NDBC/NOAA are simply skipped).

## Recommendation engine (`Recommender/`) — as built

> **This rule engine is now the offline fallback / safety net.** `GeminiRecommender` is the primary
> brain (see "Gemini-primary engine" below); the rule pipeline runs instantly first, is what the
> Gemini path falls back to on any error, and supplies the danger/over-matched safety floor.

Rule-based, transparent, tunable. `Recommender.recommend(profile:spot:conditions:quiver:)` runs a
**strict gated pipeline**:

1. **Gate 1 — island shadowing** (`Gates.shadow`): compares swell direction to the spot's optimal
   window via `Spot.degreesOutsideWindow` (wrap-aware). In-window → full height; marginal 1–20°
   outside → ×0.5; blocked >20° → capped at 1 ft + "Swell Shadowed" advisory.
2. **Gate 2 — tide swamp**: spot `.lowToMid` and `tideHeightFt > 4.5` → "Tide Swamped" advisory,
   +5% volume, one-step board downgrade.
3. **Danger check**: Beginner/Novice in >5 ft, or Intermediate in >8 ft → "Above Skill Level".
4. **Wind**: onshore >12 kt (or ≥20 kt anywhere) → "Blown Out" (`BlownOutAdvisor.evaluate`).
5. **Volume** (`VolumeCalculator`): `V = weightKg × M_skill × M_cond × M_age × extra`, off the
   **shadow-adjusted** height. `M_cond` AND-logic (small `<3ft&<9s`→1.05–1.10, solid `>5ft&>12s`→
   0.92–0.97, else 1.0); `M_age` banded (`<40`=1.0, `40s`=1.04, `50s`=1.08, `60+`=1.12); `extra`
   stacks tide-swamp / soft-wave (+5% each) and blown-out (+7%) bumps. **Phase 2** adds a wet-weight
   penalty (`wetWeightPenaltyLb`) onto effective body weight — see "Phase 2 — dynamic wetsuit system".
6. **Board type** (`BoardTypeSelector`): height-primary matrix → tide downgrade → wave-character
   override. Three performance tiers: `.hpsb` (blade, k 0.565), `.shortboard` (daily driver, 0.585),
   `.allRounder` (hybrid, 0.605). Intermediate gets shortboard/allRounder, Advanced+ gets the blade.
7. **Wave-character override** (spot `waveCharacter`): `.softAndSlow` downgrades one tier (no HPSBs on
   mush) + 5% float; `.heavyHollow` upgrades one tier (flat rockers dig the nose); `.performancePoint`
   leaves baseline. Uses `BoardType.downgradeTier()` / `upgradeTier()`.
8. **Dimensions** (`DimensionBuilder`): skill-scaled W/T → length clamp by height+type → rebalance
   W·T to preserve target volume → safety clamps (thickness 2.15–3.5", shortboard width 18.25–21.0",
   mid-length width ≥20.5"/thickness ≥2.5", **groveler/fish length ≥62"/5'2" + width 19.5–22.0"**) →
   snap. Prevents impossible dims (no 4'2" HPSB, no 5'0" groveler). **Longboards** ignore the volume
   target entirely — length steps by weight (`<150`→8'6", `150–190`→9'0", `>190`→9'6"), width/thickness
   locked to a plank range so volume falls out ~60 L+. **Mid-lengths/funboards** bump the target +20%
   before solving, then hit the width/thickness floor.
   Two entry points: `suggest(...)` (rule path, sizes to the rule volume range) and
   `suggestForTargetVolume(...)` (Gemini path, solves to Gemini's **exact** liter target + optional
   `dimPreferences`); both share the clamp/rebalance/snap chain.
9. **Advisory**: all triggered advisories collected; `AdvisoryFactory.resolve` returns only the single
   **highest-severity** one (danger > severe > info) for the UI banner. Mechanical effects (height
   cut, volume bump, downgrade) apply regardless of which advisory "wins" the banner.

`Spot` carries `waveCharacter` + `tidePreference` (seeded in `spots.json`); flat
`optimalSwellDirMin/MaxDeg` storage is kept for JSON + 360° wrap math.

### As-built deltas from the plan appendix below
- Advisory types (`AdvisorySeverity` / `Advisory` / `AdvisoryFactory`) live in
  **`Recommender/BlownOutAdvisor.swift`**, not a new `Advisory.swift` (avoids the xcodegen step).
- The pipeline uses a `Gates` enum + inline values rather than a `ResolvedConditions` struct.
- `spots.json` has **25** spots (the plan said 27).
- `BoardTypeSelector` uses contiguous **height-primary** bands (the 3–6 ft window splits on
  `period ≥ 12` = clean/powerful) rather than the plan's overlapping table — same intent, no gaps.
- Board-type/volume thresholds are tunable; tests assert **set membership** to survive tuning.

## Gemini-primary engine (Phase 1 swap) — current default

The rule pipeline above is now the **offline fallback / safety net only**. `GeminiRecommender`
(appended to `Recommender/Recommender.swift`) is the primary brain: via `gemini-2.5-flash` structured
output it owns the **board type, the exact target volume, the aesthetic dim intent, and the quiver
pick**.

- **Networking:** `GeminiClient` + `GeminiConfig` live in `Conditions/ConditionsProvider.swift` (reuse
  the `JSONFetcher` pattern). Key handling: `GeminiConfig` reads Info.plist `GEMINI_API_KEY` if present,
  else an in-source `devKey=""` constant — **empty key → Gemini skipped, pure rules** (keeps
  tests/offline deterministic). `GENERATE_INFOPLIST_FILE: YES`, so there is no checked-in Info.plist
  to edit.
- **Sizing (hybrid):** Gemini returns `targetVolumeLiters` (+ optional `dimPreferences`);
  `DimensionBuilder.suggestForTargetVolume(...)` solves W/T to that **exact** volume, then applies the
  same physical clamps as the rule path. Never clamped to a legacy baseline.
- **Safety layer** (`GeminiRecommender.map`, internal so it's unit-testable): rejects an undecodable
  `BoardType` (→ full fallback) and **re-asserts danger advisories** (over-matched / blown-out) even if
  Gemini omitted them. It never overrides Gemini's volume or type.
- **Grounding:** the legacy rule baseline is **NOT** shown to the LLM (no anchoring). The system prompt
  strictly obeys `spots.json` swell/wind/wave-character metrics; SB/Ventura geography is context only.
- **Feedback loop:** `RecFeedback` @Model + `RecSnapshot` (in `Models/Board.swift`, **registered in the
  `ModelContainer`** in `QuiverApp.swift`). 👍/👎 + optional comment in `RecommendationView`; the
  last 5 rows feed future prompts as a soft **"Surfer Preferences"** summary (`preferenceSummary`).
- **Forecast:** `ForecastView` uses **one batched** Gemini call for all 7 days; `ForecastVolume` is the
  offline fallback for the whole array.
- **Wiring:** `RecommendationView.reload()` shows the instant rule baseline, then async-swaps in
  Gemini; any thrown error (offline / timeout / parse / blank key) silently keeps the baseline and the
  `isAIGenerated` flag labels which engine produced the shown rec.
- **Tests:** `GeminiRecommenderTests` in `RecommenderTests.swift` (safety layer, exact-volume sizing,
  feedback round-trip, prompt contents) — all from canned JSON, **no network**.

## Phase 2 — dynamic wetsuit system

Cold SB/Ventura water → more rubber → more float, more paddle weight, less mobility. The engine now
bends the recommendation for it.

- **Inputs:** `ConditionsSnapshot.waterTempC`/`waterTempF` (Open-Meteo Marine `sea_surface_temperature`
  hourly param in `OpenMeteoMarineProvider`, threaded through `CompositeConditionsProvider`); owned-rubber
  flags on `UserProfile` (`hasSpringSuit`/`has32`/`has43`/`hasHoodBooties`, **defaulted** → SwiftData
  lightweight migration, no init change).
- **`Wetsuit` enum** (`Models/Enums.swift`): `springSuit`/`threeTwo`/`fourThree`/`fourThreeHoodBooties`
  with `warmthRank`, `wetWeightPenaltyLb` (spring +1 · 3/2 +3 · 4/3 +5 · 4/3+hood/booties +8 lb), and a
  `performanceNote` for the prompt.
- **`WetsuitSelector` + `WetsuitResolution`** (`Recommender/VolumeCalculator.swift`): infers the ideal
  suit from temp (**≥68 trunks · ≥62 spring · ≥58 3/2 · ≥52 4/3 · <52 4/3+hood/booties**), matches owned
  rubber (the `4/3+hood/booties` tier needs both a 4/3 **and** hood/booties), flags an under-rubbered
  gap, and returns `(ideal, selected, gap, penaltyLb)`. No temp → `.none` (penalty 0, identical to
  pre-Phase-2). NB: when the only owned suit is *warmer* than the ideal, it's selected as-is (no
  over-rubbered downgrade yet — known edge case).
- **Two consumers:** the penalty raises effective weight in `VolumeCalculator.targetVolume(wetWeightPenaltyLb:)`
  (rule fallback) **and** the suit + implications + gap go into the Gemini prompt (`buildPrompt(wetsuit:)`
  + a system-instruction line). `RecommendationView.reload()` resolves the suit once and passes it to
  both engines; the conditions card shows a water-temp + suit row.
- **Tests:** `WetsuitSelectorTests` (temp bands, owned-gear gap, penalty raises fallback volume, prompt
  carries suit context).

## Phase 3 — UI declutter

Recommendation screen (`Main/RecommendationView.swift`), no engine-behavior change:
- Rationale → one concise **"Why"** line at the top + the remainder behind a `DisclosureGroup`.
- Swell direction → one compact **`SwellCompassView`** glyph (arrow tinted by window alignment: accent
  in-window / orange marginal / red shadowed) — replaces the duplicated "SW (270°)" text.
- Shared **`DimensionLabel`** view dedupes the `L × W × T ≈ V` string across the rec card, the quiver
  card, and `Quiver/QuiverView` `BoardRow` (the non-view callers keep `DimensionSuggestion.display`).
- Advisory banner collapses to icon + title, tap to expand.
- **`ProfileEditorView`** + shared **`HeightStepper`** (combined feet/inches) in
  `Onboarding/ProfileQuestionsView.swift`, reached via a gear `ToolbarItem` in `RootView` → edits body
  metrics, skill, and the owned-wetsuit toggles.

---

# Appendix — Phase 1 Engine Upgrade Plan (Gemini spec integration)

> Original design doc that drove the engine upgrade. Kept for rationale; see "as-built deltas" above
> for where the implementation intentionally diverges. Also at `~/.claude/plans/ok-i-have-the-parsed-newell.md`.

## Context

The myCoreLord iOS app already has Phases 0–1 (and parts of 2–3) built: SwiftData models, conditions
providers, onboarding + skill quiz, spot picker, quiver, forecast, and a **modular rule-based
recommender** (`Recommender` orchestrating `VolumeCalculator`, `BoardTypeSelector`, `DimensionBuilder`,
`QuiverMatcher`, `BlownOutAdvisor`).

This change upgrades the recommendation engine from a simple decision table into a **spot-aware,
physics-gated shaper brain**, per Gemini's spec plus the three clarifying decisions captured below. The
goal: recommendations that respect island swell-shadowing, tide state, local wave character, surfer
skill *and* physically sane board dimensions — without regressing the existing module structure, the
wrap-aware swell math, or the single-banner advisory UI.

### Locked decisions from this pass
1. **Dimensions:** keep skill-scaled width/thickness, **add physical sanity clamps** as the final
   builder step (clamp length to height/type bounds, then rebalance W·T to still hit target volume,
   then clamp W/T to safety bounds). No more impossible 4'2" HPSBs.
2. **Board types:** split the performance category into **three distinct types** — `.hpsb` (pro blade),
   `.shortboard` (daily driver), `.allRounder` (forgiving hybrid). Adds two new `BoardType` cases.
3. **Advisories:** keep the **single structured banner**, but add an `AdvisorySeverity` priority system —
   the engine collects all triggered advisories and surfaces only the highest-severity one.

## What already exists (do not rebuild)

- `Recommender.recommend(profile:spot:conditions:quiver:)` pipeline and the five helper structs.
- `Spot` with `optimalSwellDirMin/MaxDeg`, `favorableWindDirMin/MaxDeg`, and wrap-aware
  `isSwellAligned` / `isWindFavorable` / `isAngleInRange` — keep the flat min/max JSON storage and the
  wrap math; do not switch to a raw `ClosedRange` that loses 360° wrapping.
- `ConditionsSnapshot` with `primarySwellHeightFt`, `primarySwellPeriodS`, `primarySwellDirDeg`,
  `tideHeightM`, `windSpeedKt/DirDeg`.
- `BoardType.shapeCoefficient` (k) — single source of k, consumed by both `Board.effectiveVolumeL`
  and `DimensionBuilder`. Keep this centralization.
- `spots.json` + `SpotsStore`.

## Changes by area

### A. Data model — `Spot` + `spots.json`
Add seeded `waveCharacter: WaveCharacter` (default `.performancePoint`) and
`tidePreference: TidePreference` (default `.allTides`). Add `optimalSwellDirDeg: ClosedRange<Double>`
convenience and `degreesOutsideWindow(_:)` (wrap-aware; 0 if inside, else angular distance to nearer
bound). New enums: `WaveCharacter {softAndSlow, performancePoint, heavyHollow}`,
`TidePreference {lowToMid, midToHigh, allTides}`. Seed every spot from its notes.

### B. `ConditionsSnapshot`
Add `tideHeightFt { tideHeightM * 3.28084 }`.

### C. Board types
Add `.shortboard` + `.allRounder`. Tuned `k`: hpsb 0.565 · shortboard 0.585 · allRounder 0.605 ·
groveler 0.635 · fish 0.635 · stepUp 0.58 · midLength 0.675 · funboard 0.675 · longboard 0.725 ·
gun 0.54. Update displayName + adjacency.

### D. Advisory system
`AdvisorySeverity {informational=1, severe=2, danger=3}` (Comparable); `Advisory {title, detail,
severity}`. Engine collects all, returns highest-severity only. Priority: Above Skill Level (danger) >
Blown Out (severe) > Swell Shadowed (info) > Tide Swamped (info). Mechanics decoupled from which
advisory shows.

### E. Pipeline (strict order)
Gate 1 shadowing → Gate 2 tide → danger check → wind blown-out → volume → board type (→ tide
downgrade → wave-character override) → dimensions (with clamps, using `profile.heightIn`) → resolve
advisory.

### F. Volume
`V = weightKg × M_skill × M_cond × M_age × extra`, using shadow-adjusted height. `M_cond` AND-logic:
small `<3ft & <9s` → 1.05–1.10; solid `>5ft & >12s` → 0.92–0.97; else 1.0. `M_age` banded:
`<40`=1.0, `40–49`=1.04, `50–59`=1.08, `60+`=1.12. Tide-swamp +5%; blown-out forgiving nudge.

### G. Board-type matrix
First-match, largest band first: onshore >12 kt → midLength/funboard; ≥8 ft & ≥13 s → gun (Adv/Exp);
5–8 ft & ≥12 s → stepUp (Int+); 4–6 ft & ≥12 s → shortboard/hpsb (Adv+ hpsb, Int shortboard);
3–5 ft & 9–11 s → allRounder/shortboard; 2–3 ft & <10 s → groveler/fish/allRounder; <2 ft →
longboard/midLength. Beginners routed to forgiving boards. Boundaries tunable.

### H. Wave-character overrides (via `downgradeTier()`/`upgradeTier()`)
`.softAndSlow` → downgrade one tier + 5% volume (no HPSBs on soft waves). `.performancePoint` →
unchanged. `.heavyHollow` → upgrade one tier; allow step-up from ≥5 ft; groveler/fish get the
"flat rockers will dig the nose" note. Tide downgrade reuses the same one-step map.

### I. Dimension clamps
Skill-scaled base W/T → length clamp `[Lmin,Lmax]` by type & height H (hpsb min(H−2,64)…H+4 ·
shortboard min(H−4,62)…H+2 · allRounder min(H−6,60)…H · groveler/fish min(H−6,62)…H+1 ·
stepUp H+2…H+8 · midLength/funboard 80…102 · longboard 102…120 · gun H+12…126) → if length clamped,
rebalance W·T (`scale = √(neededWT / W·T)`) to preserve target volume → safety clamps (thickness
2.15–3.5", longboard exempt on ceiling; shortboard-family width 18.25–21.0") → snap L ½", W ⅛", T 1/16".
> **Since superseded:** groveler/fish now floor at a hard **62" (5'2")** (`min(62, H+1)…H+1`) with a
> **19.5–22.0"** width clamp — kills the sub-5'2" stubby grovelers short surfers used to get. See the
> current "Dimensions" step (§8) above.

## Tests
Reconcile existing tests to the new matrix/age math (assert set membership, not single types). Add:
`testGoletaLocal_AverageConditions`, `testRinconDad_SmallConditions`,
`testIslandShadowing_BlockedSouthSwell`, `testTideSwamping`, plus focused tests for
`degreesOutsideWindow` (incl. wrap), dimension clamp/rebalance, and advisory priority.

## Verification
1. Unit tests green (`xcodebuild test … name=iPhone 17`).
2. JSON decode smoke: `SpotsStore.load()` decodes all spots with the new fields.
3. Simulator end-to-end: a `softAndSlow` spot (Sands) on a small day vs. a `heavyHollow` spot
   (Silver Strand) on a bigger day → board type shifts, single banner, plausible dims.
4. Manual shadowing: feed a ~190° south swell to a Rincon spot → "Swell Shadowed" + shrunken size +
   longboard/mid.

Native iOS app — no web preview; verification is the simulator + XCTest suite.
