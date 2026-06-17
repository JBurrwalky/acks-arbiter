# GDD: History Simulation

**Document type:** Game Design Document (project-designed engine, with explicit ACKS Constraints).
**Status:** Draft
**Version:** v0.5
**Authority:** PROJECT-DESIGNED — the simulation substrate, tick model, expansion/contest/collapse/migration algorithms, and all numeric parameters are engineering decisions. ACKS governs only (a) the *plausibility of the inputs* and (b) the *validity of the present-day output* that hands off to the runtime domain system (§2, §12).
**Depends on project GDDs:** `gdd-culture-catalog.md` (consumes the per-culture mechanical fields: `aggression`, `defense`, `size_exponent_bias`, `conquest`, `lifecycle`, `alignment`, `rigidity`, `road_propensity`, `sphere_weights`), `gdd-setting-generation.md` (consumes Layer 1–3 geography/climate/seed placement; **emits the §7.2 output contract** consumed by its Layers 5–8; produces the Layer 7 timeline and feeds the Layer 6 dungeon/POI seeds), `gdd-terrain-system.md` (biome tags), `gdd-dungeon-layout.md` and `gdd-poi-generation.md` (collapse emits ruins/dungeon and POI seeds), `gdd-region-painting.md` (future — consumes fallen-polity toponyms).
**Depends on ACKS rules:** `acore_axioms_strongholds_and_domains.xml` (domain morale; the Rebellious bandit/NPC-challenger mechanic; alignment- and religion-mismatch penalties; limits-of-growth caps; classification advancement; domain-growth racial modifiers — both the present-day handoff target and the grounding for collapse), `acore-setting-construction-rules.xml` (population density, territory classification, realm sizing — present-day validity), `ax_domains_of_chaos.xml` (beastman repopulation of depopulated regions; conquest-and-annexation of existing domains), `daw_campaigning_armies.xml` (the conquest outcome framework only — occupy/conquer/vassalize/pillage, §7.3.1; its unit-level campaign machinery is for play, not the sim).
**Replaces:** the original static weighted-Voronoi borders and one-pass cultural diffusion of `gdd-setting-generation.md` (old numbering §6.2/§7.1). **Wired in 2026-06-12:** that GDD's §6–§7 now describe this sim, and its §7.2 holds the output contract this sim must emit.
**Blocks:** the naming half of `gdd-region-painting.md`.
**Modifiable by Claude Code:** All algorithms and parameters — yes, subject to the ACKS Constraints in §2.
**Last updated:** 2026-06-12

---

## 1. Purpose and Principle

### 1.1 Purpose

Take the fresh map (geography + climate from `gdd-setting-generation.md` Layers 1–2) and the cultures seeded onto it (selection/placement from `gdd-culture-catalog.md` §6), and **simulate ~4,000 years of history deterministically** to produce:

1. the **present-day political map** — realms, vassal chains, borders, capitals, settlements-by-emergence, alignments, and rulers — that becomes permanent campaign data; and
2. a structured **event log** — foundings, expansions, wars, conquests, schisms, migrations, collapses, depopulations — that drives the Layer-7 LLM timeline, the provenance of ruins and dungeons, fallen-polity region names, and rumor/quest seeds.

This is the engine the culture catalog was built to feed. It is what replaces the old single-pass Voronoi/diffusion model with an actual history.

### 1.2 Principle: simulate mechanically, narrate retroactively

Consistent with the project's core principle, **the simulation decides what happened; the LLM only narrates it afterward** (`gdd-setting-generation.md` Layer 7). Every fact — that the Sargonid Empire rose in the river valley, overreached, and shattered into four successor kingdoms in the third age — is produced mechanically here and logged. The LLM later explains *why* it felt inevitable; it cannot move or invent events.

### 1.3 Culture vs. polity (recap)

Per `gdd-culture-catalog.md` §1.2, the sim runs **two coupled layers**: the slow **culture substrate** (per-hex weights, which survives political collapse) and the faster **polities** (domains/realms that rise, expand, and fall). Conquest is the interface where a polity rewrites the substrate beneath it; depopulation is where a polity's fall drags the substrate down. Keeping these distinct is what makes "the empire fell but the people and language remain" expressible.

---

## 2. ACKS Constraints

The simulation is project-designed and does **not** run ACKS's monthly domain-morale economy across 4,000 years (that system is built for play, not multi-century macro-history, and would produce noise). ACKS instead binds the sim at its two ends:

**Inputs must be ACKS-plausible.** Founding an *independent* realm requires uninhabited wilderness/borderlands for everyone — civilized land needs a grant in exchange for fealty (`acore_axioms_strongholds_and_domains.xml`, domain classification & acquisition). This is why every culture seeds in wilderness (`gdd-culture-catalog.md` §6.3) and grows polities by expansion.

**The present-day output must be ACKS-valid** (§12 handoff):
- Population density and wilderness fraction per `acore-setting-construction-rules.xml`: a default settled region runs ~50 people/sq mi (~5,000 families per 24-mile hex), and a healthy principality-scale map leaves ~50% wilderness. The sim must not produce fully-settled maps.
- Per-hex maximums and classification thresholds per `acore_axioms_strongholds_and_domains.xml` limits-of-growth (Wilderness 125 / Borderlands 250 / Civilized 780 families per 6-mile hex; advancement requires the stated hex-count and urban thresholds).
- Realm sizes consistent with ruler tier; domains economically viable (income covers garrison).

**Collapse is grounded in ACKS even though abstracted.** The outcomes mirror the morale system's low-morale behavior in `acore_axioms_strongholds_and_domains.xml`: at *Rebellious* morale a domain's income drops to zero, it sheds 4d10 families per 1,000 per month, "one able-bodied man per family becomes a bandit," and "each month there is a cumulative 10% chance that an NPC challenger emerges from the bandits." That challenger is the canonical **successor-state seed** (§7.6); the family loss is the **depopulation** path. Religion change (−4 then −2 morale) and ruler/domain alignment mismatch (−1/−2) likewise inform §10.

**Beastman repopulation** of depopulated regions uses `ax_domains_of_chaos.xml` (clanholds always wilderness; ≤125 families/6-mile hex; per-race demographics), unchanged.

---

## 3. Architecture Overview

```
Map unit:   24-mile hex (the campaign-map resolution from setting-gen Layer 1)
Layer A:    Culture substrate — per-hex weight vectors (culture, religion, alignment)
Layer B:    Polities — domains/realms with ruler, alignment, size, age, vassals
Tick:       one generation ≈ 25 years
Span:       ~160 ticks (~4,000 years) from deep history to game-start
RNG:        per-subsystem seeded streams derived from the campaign seed (fully deterministic)
```

**Per-tick loop (ordered phases):**

```
for tick in 0 .. N_TICKS:
  1. EXPANSION       each polity attempts to claim wilderness / contest enemy hexes  (§7.2–7.3)
  2. WAR & CONQUEST  resolve contests; escalate to realm-scale wars — vassal transfer,
                     wholesale vassalization, annexation, pillage (§7.3–7.3.1); rewrite
                     conquered substrate per conquest rules (§6); vassal secession checks (§7.4)
  3. MIGRATION       displaced / pressured cultures relocate                          (§8)
  4. STABILITY       each polity rolls against the collapse curve                     (§7.5)
  5. COLLAPSE        apply rump / shatter / depopulate outcomes                       (§7.6)
  6. SUBSTRATE       diffuse culture/religion weights; apply assimilation             (§6)
  7. DEMOGRAPHY      grow/shrink populations toward terrain caps                      (§6.3)
  8. LOG             append all notable events with tags                             (§11)
```

Phase order matters: expansion/war happen before stability so a tick's overextension feeds that same tick's collapse check; substrate diffusion happens after political change so it reflects the new borders.

---

## 4. Time Model

- **Generation = 25 years** (one tick). Provisional; tunable.
- **Span ≈ 160 ticks ≈ 4,000 years**, anchored to the deep-history start in `gdd-setting-generation.md` §10/§14.
- **Epochs** map the ticks onto the setting-gen timeline layers so the event log slots directly into Layer 7:

| Epoch | Ticks (approx) | Years before game-start | Setting-gen layer |
|---|---|---|---|
| Deep history | 0–100 | 4,000–1,500 | bullet timeline (8–12 events) |
| Middle history | 100–148 | 1,500–300 | denser timeline (15–20 events) |
| Recent history | 148–160 | 300–0 | narrative (what living NPCs remember) |

The sim emits far more events than the timeline shows; Layer 7 selects the most significant per epoch for narration (§11.3).

---

## 5. Entities and State

**Culture instance** — a selected catalog culture (`gdd-culture-catalog.md`), with per-campaign jittered scalars and a chosen alignment (or weights). Spawns from a seed point (§6.3 of the catalog).

**Polity** — `{ id, culture_id, alignment, ruler (level/class), ruler_quality, founded_tick, fade_onset_tick?, hexes[], capital_hex, liege_id?, vassal_ids[], vassalized_by_war?, civ_or_clan_state, economy_estimate, garrison_coverage }`. A polity has an **age** (current_tick − founded_tick), **size** (len(hexes)), and a derived **tier_index** (§7.4).

**Hex substrate** — per 24-mile hex: `{ culture_weights{}, alignment_weights{}, population_band, territory_class, owner_polity_id? }`. These are exactly the weight vectors `gdd-setting-generation.md` §7.2 contracts; the sim writes them over time. **There is no religion vector** (simplified 2026-06-12): religious practice IS `alignment_weights`, and tradition flavor derives from `culture_weights` × the shared pantheon at runtime (§10).

**Event record** — see §11.

---

## 6. Layer A: Culture Substrate

Each hex carries weight vectors that evolve:

- **Diffusion (slow):** each tick, a hex redistributes `DIFFUSE_RATE = 0.02` (2%) of its culture-weight vector across passable edges, damped per edge by terrain (open 1.0; rough forest/hills 0.7; mountain or major-river crossing 0.25; sea-lane 0.1 — derived from `gdd-terrain-system.md` movement costs). This is the *demographic* spread of a people independent of politics — minorities seep a few hexes per dozen generations, much slower than political expansion.
- **Conquest rewrite:** when polity P holds a hex, the hex's culture/alignment weights lerp toward P at `effective_svg × ASSIMILATION_STEP` per tick, `ASSIMILATION_STEP = 0.5`, where `effective_svg` is computed from P's culture `conquest` base + modifiers (`gdd-culture-catalog.md` §4.4). At svg 1.0 a hex is ~88% converted in 3 ticks ("within a few generations"); at svg 0.2 absorption takes centuries — which also keeps fresh war-vassals secession-prone via `(1 − assimilation_progress)` (§7.4). Low svg = the conquered remain themselves (vassalage); high svg = genocide/absorption.
- **Demography:** logistic growth toward the territory-class cap when securely held: `ΔP = POP_GROWTH × P × (1 − P/cap)`, `POP_GROWTH = 0.10`/tick (doubling ≈ 180 years), × the owner's `fade_factor` (§7.7), halved in contested-front hexes. Caps per 24-mile hex = 16 × the 6-mile limits-of-growth: **wilderness 2,000 / borderlands 4,000 / civilized 12,480 families** (`acore_axioms_strongholds_and_domains.xml` lines 156–161). Newly settled hexes start at ~**500 families** ≈ the RAW wilderness starting population ((1d4+1)×10 per 6-mile hex × 16, lines 102–104). Classification advances per the cited thresholds (lines 165–176). **Urban emergence:** each realm allocates ~10% of its population as urban, capital first at 20% of the urban share, remainder to highest-population hexes (`acore-setting-construction-rules.xml` lines 163–164); a settlement record (with `emergence_tick`) is created when its allocation first crosses the smallest settlement class. (ACKS's monthly growth tables are play-scale; this logistic is the macro abstraction, anchored to the RAW caps and starting populations.)
- **Minimum floor:** every group retains the small presence floor of `gdd-setting-generation.md` §7.3 (traders, refugees) so no culture is ever truly zeroed from a region it once held — useful for the LLM ("a Keshite minority lingers in the old capital").

---

## 7. Polity Lifecycle

### 7.1 Founding

At tick 0, each seed point (catalog §6.3) instantiates one small polity in wilderness, of its culture and drawn alignment. Demihuman seeds are founded here too (their golden age is the deep-history epoch, §9). As a polity grows past its directly-held core (`CORE_MAX`, §7.4) it **spawns vassal domains** (governors/sub-rulers) rather than ruling all hexes directly — this is how the vassal chain and eventual realm tiers (barony → … → empire, ACKS domain tiers) *emerge* rather than being drawn.

### 7.2 Expansion

Each tick a polity P of size `N` (hexes) gets an expansion budget:

```
expansion_pressure(P) = aggression_eff(P) × G × ( N0 / (N + N0) ) ^ α
    aggression_eff(P)  = aggression_P × ascendancy(P) × fade_factor(P) × ruler_expansion(P)
    G   = 4.0   global growth constant (baseline hexes/tick)        [PROVISIONAL — §7.8 balance pass]
    N0  = 30    half-saturation size, in 24-mile hexes              [PROVISIONAL]
    α   = 1.0 + culture.size_exponent_bias  (catalog ±0.2)          (small → fast, large → slow)

    ascendancy(P)      = 1 + peak_strength  while age(P) ≤ A_PEAK (8 ticks); else 1.0   (catalog §4.4a)
                         (demihuman-tier polities: while tick < 0.375 × N_TICKS instead — §9)
    fade_factor(P)     = §7.7 (1.0 unless culture end_state = 'fading' and onset reached)
    ruler_expansion(P) = ×1.1 strong / ×1.0 average / ×0.9 weak     (§7.5 ruler quality)
```

Fractional budget carries across ticks in a **per-polity deterministic accumulator** (spend the integer part, bank the remainder — no rounding loss, no per-tick re-rolls). Magnitude check: an aggression-0.6 culture claims ~2 hexes/tick while small, ~0.55/tick at Kingdom scale (N=100) — reaching Kingdom size takes ~60–80 ticks, fitting the §4 epoch structure.

This encodes your **size-based expansion exponent**: a young, small polity expands quickly; a sprawling empire crawls. Candidate hexes are the polity's frontier, ranked by the culture's per-terrain multiplier (catalog §4.1) so a people surges through its `seed_biomes` and stalls in `avoided` terrain. Each candidate, up to the budget:

- **Wilderness hex** → settle: claim it, seed the substrate with P's culture, possibly spawn a vassal domain.
- **Hex owned by polity Q** → contest (§7.3).

### 7.3 Border contest

```
atk = aggression_eff_P × terrain_mult_P(hex) × power_factor(P, Q) × readiness(P)
def = defense_Q × fade_factor(Q) × terrain_mult_Q(hex) × home_factor(Q, hex) × readiness(Q)
p_win = atk / (atk + def)                                          (seeded roll)

power_factor(P, Q) = clamp( (N_P / N_Q)^0.3, 0.7, 1.5 )    # size advantage, strong diminishing returns
readiness(X)       = 0.5 + 0.5 × garrison_coverage(X)      # couples the §7.5.1 ledger into war
home_factor(Q,hex) = 1.75 capital hex · 1.4 ≤2 hexes from capital · 1.2 ≤4 hexes · 1.0 else
```

The readiness factor is what makes overextension *lethal* rather than merely risky: an under-garrisoned realm fights at a discount on both attack and defense, so it loses frontier wars, which shrinks income, which deepens overextension — the death spiral emerges from the coupling, unscripted. On a win the hex flips to P and its substrate begins rewriting per P's `effective_svg`. On a loss, no transfer; each failed contest adds **+0.005 to both polities' collapse risk** that tick (war weariness), capped at +0.05/tick per polity.

Hex contests are the **skirmish layer** — raids, border friction, creeping settlement. Sustained conflict escalates to realm-scale resolution (§7.3.1), so an aggressor is never forced to crawl hex-by-hex through a rival it has decisively beaten.

### 7.3.1 War escalation and realm-scale resolution (added 2026-06-12)

A tick is 25 years — long enough to contain an entire war. Wars therefore **escalate, resolve, and conclude within a single tick** (decided 2026-06-12); recurring wars across ticks emerge naturally from continued friction. No battles or units are simulated, consistent with §7.5.1: the **gp-value army budget is the army size**, and the outcome framework is taken from the DaW conquest rules (`daw_campaigning_armies.xml` lines 762–781: a domain is conquered when its strongholds/settlements are captured; the conqueror may assimilate it, *"add it to the conqueror's realm under a vassal or sub-vassal"*, or pillage it; pillaging *"reduces domain population and reduces stronghold value or urban investment"*, line 781).

**Escalation.** For each adjacent hostile pair (P attacker, Q defender), at most one war per tick, triggered by either:

```
(a) P directed ≥ WAR_THRESHOLD = 3 hex contests at Q this tick, or
(b) seeded roll < WAR_BASE × aggression_P × (1.5 if opposed alignment, else 1.0),  WAR_BASE = 0.10
```

**Strength and margin:**

```
strength(P) = garrison_spent(P) × (0.5 + aggression_P) × ruler_war(P) × ascendancy(P) × fade_factor(P)
              × front_attack_factor(P,Q) × multi_war(P)
strength(Q) = garrison_spent(Q) × (0.5 + defense_Q)   × ruler_war(Q) × ascendancy(Q) × fade_factor(Q)
              × front_defense_factor(Q,P) × multi_war(Q)

ruler_war           = ×1.15 strong / ×1.0 average / ×0.85 weak
front_attack_factor = avg terrain_mult_P over the contested front
front_defense_factor= avg (terrain_mult_Q × home_factor) over the contested front
multi_war           = 0.8 ^ (simultaneous wars beyond the first)

victory margin v = clamp01( strength_P / (strength_P + strength_Q) + U(−0.15, +0.15) )   (seeded)
```

**Outcome ladder** (each rung includes the ones below it):

- **v < 0.50 — defender holds.** All of P's contested hexes against Q fail this tick. Loser shock applies (below).
- **0.50 ≤ v < 0.65 — border victory.** The tick's contested frontier hexes flip to P (up to P's expansion budget) — the original §7.3 result.
- **0.65 ≤ v < 0.80 — decisive victory.** Border result **plus 1d3 of Q's frontier vassal domains transfer whole to P** (`liege_id` flip; least-assimilated, nearest-the-front first) — the DaW vassal/sub-vassal option. Transferred domains keep their substrate (assimilation proceeds at `effective_svg`) and carry alignment/culture-mismatch morale at handoff. If Q has no vassals, P instead takes double its hex budget (a deep raid).
- **v ≥ 0.80 AND capital reach — crushing victory: the whole polity falls.** *Capital reach* = Q's capital within `CAPITAL_REACH = 4` hexes of the war front, or Q already reduced below half its pre-war size — the abstraction of DaW's capture-the-strongholds requirement. Disposition is driven by `effective_svg(P→Q)` (catalog §4.4):
  - **svg ≤ 0.35 → wholesale vassalization.** Q becomes P's vassal intact: `Q.liege_id = P`, `vassalized_by_war = true`; Q keeps its culture, internal vassal chain, and substrate; tribute flows per `18gp × families^0.6` (§12.1D) through the §7.5.1 ledger. "The conquered remain themselves." Emits `vassalage`.
  - **svg ≥ 0.65 → annexation.** Q dissolves; its hexes join P's realm (organized as vassal domains per §7.4); substrate rewrites at `effective_svg`. The demihuman extinction-war case. Emits `conquest`.
  - **0.35 < svg < 0.65 →** vassalization, with assimilation proceeding at svg as normal.
  - **Pillage override:** if P fits the raider profile (`aggression ≥ 0.7`, svg ≤ 0.3, `clan`), a seeded 50% chance to **pillage instead of keep**: no territory or fealty changes; Q loses 20% population in front-region hexes and P books a one-time `tribute_in` credit of 0.5 × Q's tick income next tick. Emits `pillage`. This is the Vargari/steppe signature behavior, straight from the DaW pillage option.

**War shock (feeds §7.5 that same tick):** the war's loser takes +0.02 collapse risk; the winner +0.005 (victory is also expensive). Stacks with per-contest attrition under the same +0.05/tick cap.

**Natural feedbacks, no scripting:** wholesale vassalization spikes the winner's tier → `f_size` and garrison need jump → the triumphant empire is immediately more fragile, which is historically correct. The losers' shed/transferred domains are the same vassal entities that §7.6 later uses as successor states.

**Cost:** O(adjacent hostile pairs) per tick — strictly fewer than hex contests. Negligible. `defense` being the catalog's resistance scalar, a high-`defense` culture (e.g. the Shidheans, the Sylvan elves) is very hard to push out of its terrain even when out-expanded.

### 7.4 Vassalage and realm tiers

When a polity's directly-held core exceeds its threshold, additional conquered/settled territory is organized as **vassal domains** under sub-rulers, forming a realm. Realm tiers (and the ruler levels that hold them) follow the ACKS domain-tier framework referenced in `gdd-setting-generation.md` §2; the exact ruler-level→tier numbers are retrieved and cited in **§12.1**. Vassals matter for collapse: they are the natural successor states (§7.6).

**Internal organization rule (added 2026-06-12).** Grounded in "a ruler may only directly manage one domain… every other domain in the realm must be assigned to a vassal" (`acore_axioms_strongholds_and_domains.xml` lines 267–271): the directly-held **core** is the capital hex plus adjacent held hexes up to `CORE_MAX = 3` hexes total. Territory beyond the core accumulates into **internal vassal domains** of `VASSAL_SIZE` contiguous hexes, spawned as enough unassigned hexes exist. `VASSAL_SIZE` is **tier-scaled** (decided 2026-06-12): realm tier ≤ Principality → 3 hexes; Kingdom → 4; Empire → 6 — evaluated at spawn time; existing vassal domains are not resized. `vassal_count` therefore scales with realm size automatically, supplying the currency for decisive-war transfers (§7.3.1), shatter successors (§7.6, K's `vassals + 2` cap), secession, and the §12 vassal-chain decomposition. Internal vassal domains are lightweight records within the polity; **vassal polities** (war-vassalized, `liege_id` set) remain full polities.

**Tier determination (in-sim):** `tier_index` ∈ { Barony 0, March 1, County 2, Duchy 3, Principality 4, Kingdom 5, Empire 6 }, keyed on **overall realm families** per the titles table (§12.1A). The hex-count ranges (§12.1B) are a handoff-time sanity check only — early-sim realms are sparsely populated, so hex count alone would inflate tier. March/Barony sit below the 24-mile-hex sim resolution; they appear only inside the handoff vassal decomposition, never as sim polities.

**Vassal secession (added 2026-06-12).** Vassals acquired by war or culturally distinct from their liege (`vassalized_by_war`, or `culture_id ≠ liege.culture_id`) check for secession each tick the liege shows weakness (weak ruler quality, lost a war this tick, or `collapse_risk > 0.15`):

```
p_secede = BASE_SECEDE × (1 + alignment_mismatch) × (1 − assimilation_progress)
    BASE_SECEDE = 0.05;  alignment_mismatch = 1 if vassal and liege alignments differ, else 0
    assimilation_progress = avg weight of the liege's culture across the vassal's hexes
```

On success the vassal becomes independent (emits `secession`); renewed war between the two then arises naturally from §7.3.1 escalation. Same-culture, internally-spawned vassals (§7.1) do **not** run this check — they leave only through §7.6 collapse, which keeps healthy realms from fraying randomly. Empires thus erode at their least-assimilated edges first, which is the historically correct failure mode.

### 7.4b Genocide rebellions (added 2026-06-15)

Conquest assimilates conquered hexes toward the conqueror's culture (§6, `effective_svg × ASSIMILATION_STEP`), with no in-place resistance — so a runaway conqueror could erase the cultural map (seed 177621 large → one culture 89.5% of the land). A **genocide rebellion** is the brake: a culture being actively erased can revolt. Runs in a `_phase_rebellion` pass immediately after `_phase_war`, so an active revolt is an **internal front** — it adds `REBELLION_WAR_FRONTS` to the ruler's `war_count`, weakening every external war via the `MULTI_WAR_FACTOR` (an army suppressing a revolt can't fully campaign abroad), for exactly as long as the revolt persists.

**Ignition.** For each realm, group its still-erased subject-culture hexes (a minority culture ≥ `REBELLION_MIN_MINORITY_WEIGHT` whose hex hasn't yet converged to the owner) by culture. For each subject culture with no live revolt, ignite with `p = REBELLION_BASE × (1 + svg) × mismatch` (harder genocide and opposed alignment make revolt likelier). NOT guaranteed.

**Resolution.** A live revolt persists each tick (war penalty applying) until a `REBELLION_RESOLVE_CHANCE` roll fires; then a single margin roll picks one of four bands:

```
v = rebel_strength / (rebel_strength + suppression) + jitter
    rebel_strength = avg_minority_weight × mismatch × (1 + svg)        # how much of the people remain, how hard the erasure
    suppression    = ruler_war × (SUPPRESSION_BASE + military_sphere)
                     × MULTI_WAR_FACTOR^(other active revolts) × (1 − collapse_risk)   # a busy/weak ruler crushes less well
```
- **v ≥ `REBEL_BAND_MAJOR_SUCCESS` (0.75) — break away.** The contiguous subject hexes secede as a fresh realm of their culture (reasserting it on those hexes), joining an adjacent same-culture realm as a vassal if one borders them, else independent. Emits `rebellion_won`.
- **≥ `REBEL_BAND_MOD_SUCCESS` (0.55) — forced concession.** The sovereign's culture replacement on those hexes is blocked for `REBELLION_BLOCK_BASE + 1d3` ticks; the people stay subjects. Emits `rebellion_concession`.
- **≥ `REBEL_BAND_MOD_FAILURE` (0.30) — crushed.** The revolt ends; next tick's substrate resumes assimilation. Emits `rebellion_crushed`.
- **below 0.30 — extinction.** The revolt is put down and the culture is driven to its 0.001 floor on those hexes this tick; the survivors flee as a diaspora band (§8) that may refound the culture elsewhere. Emits `rebellion_extinguished`.

A two-way coupling falls out: a multi-front warlord suppresses revolts worse, and an active revolt makes that warlord worse at war. Knobs (all `[CALIBRATION]` in `SimConstants`) tune ignition rate, the band thresholds, the suppression baseline, and the war-front penalty. The active-revolt set and per-hex genocide blocks are transient sim state; only the emitted events persist (`setting_events`, migration 161 widened its `type` CHECK).

### 7.4c Beastman conquest — raze-and-retreat (added 2026-06-15)

Beastman clanholds (`is_beastman`, the ACKS low-density chaotic interior, `ax_domains_of_chaos`) are **never settled** by the realms that beat them, and **never settle** the realms they beat. Two rulings (Jedidiah, 2026-06-15) replace the generic annex-and-convert outcome:

- **#4 — Lawful/Neutral victors WIPE, don't annex.** When a Lawful or Neutral realm takes a beastman hex, the clanhold population is cleared to wilderness (`razed_pop_keep = 0`) and the victor **takes nothing**; the hex re-civilizes only later, by the victor's own organic expansion into the now-empty wilderness (`_settle_wilderness`) — never by flipping beastman families into the conqueror's culture in place ("beastmen don't become settlers"). RAW *does* let Lawful/Neutral realms retain a beastman population, but that is **slave-taking**, deferred to runtime; the macro-sim does not model slave populations. A **Chaotic** victor still keeps the hex (enslaving its people, RAW) — the raze rule is Lawful/Neutral-only.
- **Beastman attackers raid and withdraw.** A beastman attacker's decisive/crushing victory razes the front it overran (population destroyed) and retreats to its clanhold — it gains no territory; the vacated land refills by organic growth / re-seeding.

**Single chokepoint.** The raze rule is enforced inside `_flip_hex` — the *one* primitive every conquest hex-transfer routes through (expansion-phase border contest, war border-band, decisive-war deep-raid, crushing-war annex). So `loser.is_beastman ∧ ¬winner.is_beastman ∧ winner.alignment ≠ chaotic ⇒ raze` applies on **every** path, not only the crushing-war branch. (A beastman defender never reaches `_annex`: `_resolve_crushing` routes it to `_raze_realm`/`_vassalize` first.) Razing a clanhold's last hex destroys it (emits `razing`, migration 162); a partial raze just re-tiers the survivor under the clanhold cap.

### 7.4d Contiguity — foreign-land secession (added 2026-06-15)

A realm whose directly-held hexes are split into pieces reachable from the capital only **through foreign sovereign land** sheds the orphan pieces (#5). Each tick, after collapse, `_phase_contiguity` partitions every realm's own hexes into connected components:

- **Connectors:** land adjacency (shared edge); a **sea lane** between two of the realm's own coastal hexes within `sea_lane_range` (= 10 hexes ≈ 240 mi) — ocean/river separation never splits a realm, only foreign land does; and the realm's **own transitive vassal-chain hexes** (same-realm territory is passable, so a liege whose blocks are joined only through its vassal's land is not falsely dismembered — vassal hexes bridge but are never themselves shed).
- **Keep/shed:** the component holding the capital is kept (else the largest); each orphan ≥ `contiguity_min_secede_hexes` (2) **secedes** as a fresh same-realm-culture realm (joining an adjacent same-culture realm as a vassal if one borders it, emits `secession`), smaller orphans revert to wilderness. If the capital hex itself was already lost, the capital is repointed to the kept block's canonical anchor so home-factor / urban-emergence / core selection stay centered on real territory.

### 7.4e Significance floor — duchy realms and war-hordes (added 2026-06-17)

At the 24-mile setting scale only **historically significant** realms are modeled (Jedidiah ruling, 2026-06-17). Sub-significant holdings are not separate 24-mile polities; they are the absorbing realm's internal vassal decomposition (§7.4), materialized at the 6-mile handoff (the 6-mile map already represents baronies / scattered clanholds). This fixes hyper-fragmentation (a huge map produced ~575 polities, ~374 lone beastman clanholds + ~200 fragmented civilized realms), frees the name pools, and speeds every downstream layer (naming, infrastructure, narrative, handoff) — fewer entities throughout.

**The two floors.**
- **Civilized / demihuman realms: floor = Duchy.** A modeled realm should be tier ≥ Duchy (`DomainTierTable.DUCHY`, ≥20,000 overall families ≈ 2–3 contiguous civilized hexes — a single civilized 24-mile hex caps at 12,480 = County tier). Barony/March/County are inferred as vassals inside a duchy-sized realm.
- **Beastmen: cohering war-hordes only.** RAW (`ax_domains_of_chaos.xml`) explicitly allows a beastman realm — "a chieftain may establish a realm by founding additional clanholds … or by conquering and annexing an existing domain," and the wilderness-build procedure ends "organize the clanholds into one or more realms at the Judge's discretion." The sim is the Judge. A war-horde is a contiguous cluster of ≥ `beastman_horde_min_hexes` (3) clanhold hexes under the dominant clanhold's war-chief (each hex still wilderness, ≤ `cap_wilderness` families — a horde is still a clanhold, just aggregated). Smaller/isolated clanholds are **not** recorded at 24 miles — the 6-mile runtime fills empty wilderness with them.

**Consolidation phase (`_phase_consolidation`, every `consolidation_period` ticks) + a finalization sweep.** The orphan rule — "stray counties/marches/baronies that would survive the destruction of a higher realm quickly dissolve or merge into a larger confederation" — is a recurring sim mechanic, so the modeled count stays at duchy+/horde granularity throughout (not just relabeled at the end). A monotonic fixpoint (each merge removes one realm; a strict realm rank order `_outranks` = families, then hexes, then id, so no two realms absorb each other):

- **Civilized sub-floor sovereign →** merge into the strongest acceptable adjacent realm that outranks it (`_annex_realm`: hexes flip via the `_flip_hex` chokepoint, the realm dissolves, its war-vassals are freed). Acceptable = alive, civilized, non-opposed alignment; **cultural variance is allowed** (Jedidiah), but same-culture neighbours are **preferred** (builds same-culture duchies, dampens the dominant-culture snowball). A cluster of fragments thus accretes into its strongest local member, which crosses the Duchy floor and stops being a candidate.
- **Orphan (no adjacent merge target) →** at the finalization sweep, relocate its people to the nearest valid realm with `consolidation_migrate_loss` (25%) population loss (`_migrate_realm_into`): the survivors fill the destination's hexes to cap and then expand its border, and the orphan's land empties to wilderness (left for the 6-mile fill). During the sim an orphan waits (its smaller neighbours merge into it; it may yet grow).
- **Maturity gate:** during the sim only realms older than `consolidation_min_age` (8 ticks ≈ 200 yr) consolidate, so a fresh realm has room to grow to Duchy organically. The finalization sweep ignores the gate and also folds any remaining sub-Duchy **vassal** row into its liege (`_fold_subfloor_vassals`), guaranteeing every present-day polity is Duchy+ or a war-horde.
- **Beastman sub-threshold horde →** merge into an adjacent horde that outranks it (then clamp to `beastman_realm_max_hexes`), else — if truly isolated — dissolve to wilderness (chaotic raiders don't federate, so no migrate-to-join). A local-nucleus horde with smaller neighbours waits for them to merge in.

Consolidation is **silent** (no event — a soft administrative merge; the replay frames still show the borders change), so it adds no records and needs no event-type migration.

**Beastman territory is bounded** so hordes stay a frontier minority (durable multi-hex hordes are only front-razed, so unbounded they dominate large/deep maps). At **seed** (`CultureSeeder._place_beastmen`): per-hex clanhold presence is rolled as before, contiguous present-hexes are aggregated into hordes largest-first, each capped to `BEASTMAN_HORDE_MAX_HEXES` (8, densest cluster around the dominant clanhold), until a global budget `BEASTMAN_SEED_LAND_CAP` (15% of land) is spent; the rest is left empty. **Re-seed** (`_repopulate_beastmen`, the §7.6 renewal): on the scan cadence, grow war-hordes (up to the cap) in empty wilderness below the regional target, but only while modeled beastmen own less than `beastman_global_land_cap` (15%) of the land — tracked within the scan so a burst can't overshoot. The `beastman_realm_max_hexes` cap rose 3 → 8 to admit a multi-hex horde.

**Determinism:** sorted-id candidates, canonical neighbour/hex iteration, the strict `_outranks` order, no RNG. The handoff dependency (sub-floor holdings → 6-mile vassals/clanholds) belongs to the separate setting→runtime materialization; this change only ensures the 24-mile output cleanly omits them.

### 7.4f Go-native — conqueror adopts a developed subject (added 2026-06-17)

A sovereign realm that has come to **rule a large, more-developed foreign subject** has a per-tick chance to adopt that subject's culture — the conqueror "goes native" (Yuan→Chinese, Norman→English, the steppe khan who must become a bureaucrat to govern the empire he won). This is the counterpart to assimilation (§6): assimilation rewrites the *land's* substrate toward the ruling culture; go-native flips the *ruling* culture toward the land. Together with the §6/§7.4e resistance damping and the §7.4-clanhold rules they give the full set of post-conquest outcomes RAW allows (`daw_campaigning_armies.xml`: assimilate / vassalize / pillage): a horde that rules a civilization either **adopts** it (go-native fires — the civilization survives under a new dynasty) or, failing that, slowly **degrades** it (clan assimilation + the §7.4 clan-density collapse — "barbarians ruin the cities"). Both are historical; the dice choose.

**Prestige proxy = `developed`.** Each culture instance carries a civilization-level scalar `developed` (CultureSeeder threads `mechanical.class_kit_weights.developed`: 0 primitive / 0.7 developing / 0.9 advanced — the same scalar that picks developed-vs-primitive NPC gear). Demihuman culture files omit it but are advanced civilizations (default 0.9); beastmen are 0.0. "Adopt-up" uses this gradient directly.

**The check (`_phase_go_native`, runs after consolidation, before substrate).** For every alive, mature (`go_native_min_age`) **sovereign** (no liege — vassals follow their liege, they don't self-convert) that is **not a beastman** (chaotic raiders raze, they never assimilate up):

```
subject_share = mass(S) / Σ_c mass(c)   over the realm's OWN hexes,
                where mass(c) = Σ_hex culture_w[hex][c] × population_band[hex],
                and S = the dominant non-owner culture (mass-weighted, lexical tie-break)

eligible iff  subject_share ≥ go_native_min_share (0.4)  AND  developed(S) > developed(owner)
p_go_native   = go_native_base_rate (0.05) × subject_share × (developed(S) − developed(owner))
```

Mass-weighting (not hex count) means a populous foreign *core* counts for more than empty foreign marches — a realm whose heartland is the subject goes native, one whose distant frontier happens to be foreign does not. **Adopt-up only** (`gradient > 0`, no floor — Jedidiah 2026-06-17): you take on prestige, never sideways or down; a great civilization ruling a primitive subject imposes its own culture (the subject assimilates normally) rather than going native. At base 0.05 a steppe realm (dev 0) 70%-held by an urban civ (dev 0.9) flips with ≈3.2%/tick (~47% over 20 ticks ≈ 500 yr); an intra-civ developing→advanced adoption at 60% share is ≈0.6%/tick (~11%). Rolled per `(tick, polity)` on an independent `WorldGenRng` stream; flips are **collected then applied** so no realm's `subject_share` is perturbed mid-scan (order-independent, deterministic).

**On flip (`_apply_go_native`).** `culture_id` becomes the subject's; `is_beastman`/`is_clanhold` recompute from the new culture — a steppe/clan conqueror adopting a civilized subject **sheds clanhold status** and may now civilize its land and found cities (the "horde lord becomes a bureaucrat" path; if go-native never fires, the §7.4 clan rules instead collapse the conquered cities to clanhold density). From that tick assimilation pulls the realm's former homeland toward the adopted culture, and at handoff its rulers and realm name come from the new culture's kit. A **`cultural_shift`** event is emitted (`cultures = [from, to]`, `polities = [realm]`; significance 0.5), so the shift is visible in the replay timeline and narrated ("the Vargari Khanate took on the ways and customs of the Jinxian"). Migration 163 widens the `setting_events.type` CHECK; the narrative timeline renders it via `_EVENT_TEMPLATES["cultural_shift"]`.

**Scope (honest).** Go-native targets **low-development-conqueror** dominance — it converts a primitive culture that has conquered a civilization *into* that civilization, which is the least-plausible monoculture (a steppe culture painting a continent) and the richest flavor. It does **not** break a **high-development expansion** monoculture: a most-developed culture (e.g. jinxian, dev 0.9) never finds a more-developed subject to adopt, and expansion-driven dominance carries low `subject_share` (settled land, not ruled subjects). The direct fix for that case is the expansion-settling cultural reach (RAW `range_of_trade` falloff — Phase 5, future work), not go-native.

### 7.5 Stability and collapse curve

Each tick every polity rolls against a collapse risk. This is the heart of the sim and is **project-designed** (the catalog supplies the per-culture knobs):

```
collapse_risk(P) = BASE
                 × temperament                      (player slider, §13 — the "moderate" default ≈ 1.0)
                 × f_size(N)                         (rises as N exceeds a cohesion/viability threshold)
                 × f_age(A)                          (low when young, rises past a dynastic peak)
                 × f_overextension(P)                (rises when est. income < garrison need, or borders indefensible)
                 × (1 + collapse_proneness_P)        (catalog lifecycle; demihumans high)
                 × ruler_quality_factor              (a strong ruler suppresses risk for their reign)

BASE = 0.01;  result clamped to [0, 0.35] per tick.
```

- **f_size = TIER_RISK_MULT ^ max(0, tier_index − 2)**, `TIER_RISK_MULT = 1.35` (decided 2026-06-12): risk compounds per tier above County, the cohesion threshold — County 1.0, Duchy 1.35, Principality 1.82, Kingdom 2.46, Empire 3.32. Grounded in ACKS: larger domains are harder to control and strain vassal loyalty (`acore_axioms_strongholds_and_domains.xml`); the discrete tier form matches the cited tier table (§12.1) and the original "each additional tier multiplies risk" intent.
- **f_age:** ramps 0.4 → 1.0 over `A_PEAK = 8` ticks (200 years — a dynasty's run), then `1 + 0.15 × (A − A_PEAK)/A_PEAK`, capped at 2.5. Young polities still can fail (floor 0.4), old ones accumulate fragility slowly.
- **ruler_quality_factor:** quality redrawn every `REIGN_TICKS = 2` (≈ a 50-year reign): strong / average / weak at 25/50/25% → risk ×0.7 / ×1.0 / ×1.3. Quality also moves garrison `target_coverage` ±0.1 (§7.5.1) and expansion ×1.1/×0.9 (§7.2). Quality transitions emit `dynasty_change` events (§11).
- **f_overextension** uses the ACKS economic-viability rule (income must cover garrison, `gdd-setting-generation.md` §2): a realm that expanded faster than it can garrison is fragile. Concrete form in §7.5.1.
- **temperament** is the single global multiplier the player slider moves (§13); the **default is moderate** — enough rise/fall to seed ruins and successor states without shredding the map.
- **Calibration at defaults:** a healthy mid-tier realm runs ≈3%/tick → expected life ~30 ticks (~750 years); an aging, overextended empire ≈8%/tick → ~12 ticks (~300 years at empire scale). Historically plausible at Moderate = 1.0.
- **Fading cultures contribute no extra term here** — `end_state:'fading'` degrades a polity's *inputs* (aggression, defense, growth — §7.7), not its stability roll. A fading empire dies by a thousand border contests, not by its own collapse die.

A seeded roll vs `collapse_risk(P)` each tick determines whether P collapses this generation.

### 7.5.1 Realm economy and garrison (the overextension inputs)

`f_overextension` is not hand-waved — each tick it is computed from a lightweight **aggregate** realm ledger. The key design choice: this is **gp-value accounting, not unit-level troop simulation.** ACKS itself frames garrison as a gp-per-family spend (`acore_axioms_strongholds_and_domains.xml`, domain_expenses), so the macro-sim tracks a garrison *budget* against a garrison *need* and never models individual companies — troop composition is a runtime concern after handoff (`daw_*` tables are for play, not the 4,000-year sim). All figures below are ACKS monthly rates used as **relative magnitudes** per tick, not literal monthly gp.

**Income** (per realm R per tick), from domain_revenue:

```
income(R) = Σ_hex  families(hex) × ( land_value(hex) + 4 + 2 )     # Land (3–9, the hex's value) + Services 4 + Taxes 2, per family
          + tribute_in(R)                                          # from vassals (incl. war-vassalized polities, §7.3.1)
          − tribute_out(R)                                         # to liege, if any; rate per 18gp × families^0.6 (§12.1D)
```

`land_value` is the hex's 3–9 gp Land value (RAW: 3d3 per 6-mile hex, `acore_axioms_strongholds_and_domains.xml` line 46). v1 uses a **fixed per-terrain table** set at map-gen, within the RAW range: plains/river-valley 6, hills 5, forest 4, mountain/desert/tundra 3; +1 if river-adjacent, capped at 9. Deterministic, no per-hex rolls.

**Fixed overhead** (non-garrison obligations, domain_expenses): Liturgies + Maintenance + Tithes = **3 gp/family** flat.

**Garrison need**, from the garrison rules ("a ruler must spend at least 2gp per peasant family per month on troops"; "Borderlands domains commonly maintain 3gp per family; wilderness domains must maintain 4gp per family or base morale is reduced"):

```
garrison_need(R) = Σ_hex  families(hex) × base_rate(class(hex)) × frontier_mult(hex)
    base_rate:   civilized 2,  borderlands 3,  wilderness 4   (gp/family)
    frontier_mult = 1 + 0.5·(hex borders a rival polity or beastman-held wilderness)
                      + 0.25·(distance to capital > 6 hexes), capped at 1.75
```

The frontier multiplier is the project-designed part: a realm with a long contested border or distant marches needs proportionally more garrison than its raw family count implies.

**Actual garrison** (the realm's per-tick policy):

```
affordable(R)      = income(R) − overhead(R)                       # what's left after fixed obligations
target_coverage(R) = clamp( 0.7 + 0.6 × sphere_weights.military + ruler_delta, 0.5, 1.2 )
                     # ruler_delta = +0.1 strong / 0 average / −0.1 weak (§7.5)
                     # militarist (~0.5 military) → ≥1.0; mercantile/arcane (~0.15) → ~0.8, thin frontiers
garrison_spent(R)  = min( garrison_need(R) × target_coverage(R), max(affordable(R), 0) )
garrison_coverage  = garrison_spent(R) / garrison_need(R)
```

A militaristic culture reliably funds toward full coverage; a mercantile or arcane-leaning one tolerates thinner frontiers and is more prone to overextension. A strong ruler raises effective coverage during their reign.

**Adjustment across ticks is automatic, and is the whole point.** When a realm expands fast (§7.2), its garrison *need* spikes that same tick — more hexes, more frontier, newly-conquered restless provinces whose substrate hasn't assimilated — while its *income* lags, since new hexes are underpopulated and unproductive for generations. Coverage drops, overextension rises: the "bit off more than it can hold" failure mode emerges from the ledger with no scripting.

**Overextension factor** feeding §7.5:

```
min_garrison(R)    = Σ_hex families(hex) × 2                       # the RAW hard floor: "a ruler must spend at
                                                                   # least 2gp per peasant family per month on
                                                                   # troops" (acore_axioms_strongholds_and_domains.xml
                                                                   # line 226; 3/4gp rates are morale-safe rates, line 233)
solvency(R)        = income(R) − overhead(R) − min_garrison(R)
f_overextension(R) = clamp( 1 + w1 · max(0, 1 − garrison_coverage)             # under-garrisoned frontier
                              + w2 · max(0, −solvency(R)) / garrison_need(R),  # bankrupt: can't meet even the 2gp floor
                            1.0, 3.0 )
w1 = 1.0,  w2 = 2.0                                                [PROVISIONAL — §7.8 balance pass]
```

(The earlier `MIN_RATE_FRACTION` knob is **removed**: the 2gp floor is RAW, so the minimum is cited rather than tuned — one fewer free parameter.)

Under-garrison nudges collapse risk; insolvency drives it hard — the macro analogue of the ACKS morale spiral, where failing the garrison requirement reduces morale and tips a domain toward *Rebellious* (`acore_axioms_strongholds_and_domains.xml`). The same ledger seeds the **present-day morale** at handoff (§12): a realm arriving chronically under-garrisoned in borderlands/wilderness carries the corresponding ACKS morale penalties (Borderlands −1, Wilderness −2) and forfeits the garrison morale bonuses.

**Cost:** the ledger is **O(hexes + vassal-edges) per tick** — one extra sum-over-hexes pass, the same order as substrate diffusion. Over ~160 ticks on a Huge map it is a low-millisecond addition (§14). It is *cheaper* than the expansion-frontier phase, not a new order of magnitude.

### 7.6 Collapse outcomes

On collapse, roll **severity** (seeded; decided 2026-06-12):

```
S    = U(0,1) + bias
bias = 0.3 × max(0, tier_index − 2)/4          # bigger realms fall harder
     + 0.4 × (f_overextension − 1)             # overreach makes the fall worse
     + 0.6 × collapse_proneness                # catalog lifecycle; demihumans high
     + 0.1 × (temperament − 1)                 # player slider tilts severity slightly

Bands:  S < 0.50 → rump   ·   0.50 ≤ S < 0.85 → shatter   ·   S ≥ 0.85 → depopulate
Gate:   shatter requires vassal_count ≥ 2 or tier ≥ Duchy, else it degrades to rump.
        Depopulate is never gated — small enclaves can be erased outright.
```

Check at defaults: a healthy human duchy mostly rumps; an overextended demihuman realm (proneness ~0.8) carries bias ≈ +0.8 and almost always shatters or depopulates — exactly the §9 arc.

- **Rump (minor):** P sheds its borderland/frontier hexes (the least-assimilated, farthest-from-capital first); core + capital survive as a smaller polity. Some shed hexes may become independent successors.
- **Shatter (major):** P fragments into **K successor polities**: `K = clamp( 1d3 + max(0, tier_index − 3), 2, min(6, vassal_count + 2) )` — Duchy 2–3, Principality 2–4, Kingdom 3–5, Empire 4–6, converging at empire scale on the ACKS rule that each realm contains **4–6 realms of the next tier down** (`acore-setting-construction-rules.xml`, `political_divisions_of_realms`, lines 90–110). Successors are seeded, in priority order, from: existing vassal domains (governors declaring independence), then **NPC challengers risen from bandits** (the ACKS Rebellious mechanic, `acore_axioms_strongholds_and_domains.xml`), then the surviving rump around the capital. Each successor inherits P's culture; its alignment may **drift** (§10).
- **Depopulate (catastrophic):** the region loses most of its population (the ACKS family-loss path), its hexes revert toward **wilderness** classification, **beastmen spawn** per `ax_domains_of_chaos.xml` — after `BEASTMAN_DELAY = 2` ticks of silence, each empty hex has `0.25 × beastman_density` chance per tick to spawn clanholds rolled from the terrain's geographic-distribution table (lines 243–262; races by 1d100, ≤125 families/6-mile hex), becoming Chaotic chieftain polities in the normal loop — and **ruins/dungeon seeds** are emitted carrying the fallen polity's provenance (culture, era, name) for `gdd-dungeon-layout.md` and the Layer-6 dungeon target. Survivors may form a **migrating band** (§8).

Severity is weighted by temperament and `collapse_proneness`: high-proneness cultures (demihumans) shatter and depopulate disproportionately, which is what fills the deep map with elven/dwarven ruins.

**Clanhold cap and re-seed (added 2026-06-15; superseded by the §7.4e war-horde model 2026-06-17).** Beastman realms are held to the ACKS clanhold scale on every path:
- **#2 size cap.** A beastman realm holds at most `beastman_realm_max_hexes` (raised 3 → **8** for the §7.4e war-horde model — a horde spans the cohering cluster it was aggregated from), stays `wilderness` (never advances classification, founds no settlements — `_demote_to_clanhold` clamps any hex acquired out-of-band, e.g. a rebellion breakaway, to the wilderness cap), and **never shatters** on collapse. They do not run the expansion phase — they hold, raid, defend, and are pushed back by civilization (§7.4c). They are the scattered chaotic interior, not empire-builders.
- **#3 wilderness re-seed.** A **regional floor scan** runs every `beastman_scan_period` ticks: it sweeps empty wilderness and grows a **war-horde** (≥ `beastman_horde_min_hexes`, up to the cap) where a region (radius `beastman_region_radius`) sits below `beastman_region_target` — but only while modeled beastmen own less than `beastman_global_land_cap` of the land (§7.4e), so durable hordes stay a frontier minority instead of carpeting the interior over deep history. The crater fast-path was folded into this scan (the "let the ashes cool" `BEASTMAN_DELAY` still gates crater anchors). The interaction with §7.4c (Lawful/Neutral raze) makes the civilized frontier a live march: razed beastman hexes empty, re-seed regionally, and are razed or settled again. [CALIBRATION — `beastman_global_land_cap`/`beastman_region_target` govern the equilibrium beastman fraction; tune to taste. NOTE: aggregating beastmen into fewer hordes reduces the widespread-clanhold pressure that checked civ expansion, so it can exacerbate the parked large-map monoculture variance on snowball-prone seeds — see Known issues.]

**Generic "beastmen" sim culture (added 2026-06-15, §5.3).** At the 24-mile sim scale beastmen are ONE generic chaotic culture (`data/cultures/beastmen.json`, `culture_id="beastmen"`), not the ten per-race cultures — a beastman 24-mile hex is a mixed horde under a fragile war-chief, never a swathe of "orc land". The seeders still roll a per-terrain race (`beastman_distribution.json` `race_d100`) but keep it only as a per-clanhold **hint** (`pol["beastman_race"]`, in-memory): it drives the race-specific chieftain (`_assign_beastman_ruler`) and the realm-name flavor (a 1-hex "Orc warren" beside a "Goblin den"), NOT the sim culture identity. The ten race files remain as 6-mile flavor data. The intermingled per-6-mile-sub-hex race mix is materialized at the gameplay handoff (deferred), reusing the same distribution data. Because all beastmen now share one culture, secession/conquest can no longer federate them into chains blindly: beastman secession/breakaway stays independent (clanholds don't swear fealty), and a `_would_create_liege_cycle` guard on `_vassalize`/decisive-transfer prevents a realm from vassalizing its own transitive grand-liege (a latent `_same_realm`-shallowness the abstraction exposed).

### 7.7 End-state `fading` degradation

Wires in the `lifecycle.end_state = 'fading'` mechanic added to `gdd-culture-catalog.md` §3.1 (decided 2026-06-12):

- **Onset:** when a polity of a fading culture first satisfies `age > A_PEAK` **and** `tier_index ≥ 3` (Duchy) — the culture rises to real power first, then begins the long afternoon. Records `fade_onset_tick` on the polity. Polities that never reach Duchy never trigger it.
- **Rate:** `fade_factor(P) = FADE_RATE ^ (tick − fade_onset_tick)`, with `FADE_RATE = 0.985` — a compounding ≈ −1.5%/generation, reaching ×0.30 after 80 ticks (2,000 years). Global constant for v1, not per-culture. [PROVISIONAL — §7.8]
- **Applies to:** expansion (`aggression_eff`, §7.2), contest defense (§7.3), and demographic growth toward caps (§6). Non-fading cultures have `fade_factor = 1.0` everywhere.
- **Deliberately NOT applied to** `collapse_risk` (§7.5): per the catalog, a fading culture "grows progressively more open to conquest by its neighbors without necessarily collapsing on its own." Its worsening ledger still feeds `f_overextension` normally, and its weakening defense loses border contests — erosion, not implosion.
- **Alignment/religion (§10):** no special drift; fading degrades a polity's material strength, not its identity.

### 7.8 Consolidated tuning constants [PROVISIONAL — one balance pass pending, §17]

| Constant | Default | Where |
|---|---|---|
| `G` / `N0` / `α` | 4.0 hexes/tick / 30 hexes / 1.0 ± culture bias | §7.2 |
| `A_PEAK` | 8 ticks (200 yr) | §7.2, §7.5, §7.7 |
| power exponent / clamp | 0.3 / [0.7, 1.5] | §7.3 |
| `home_factor` | 1.75 / 1.4 / 1.2 / 1.0 | §7.3 |
| attrition per failed contest | +0.005 risk, cap +0.05/tick | §7.3 |
| `BASE` / risk clamp | 0.01 / [0, 0.35] | §7.5 |
| `TIER_RISK_MULT` | 1.35 | §7.5 |
| `f_age` ramp/slope/cap | 0.4→1.0 over A_PEAK; +0.15/A_PEAK per tick; cap 2.5 | §7.5 |
| ruler quality | 25/50/25% → risk ×0.7/1.0/1.3; coverage ±0.1; expansion ×1.1/0.9; `REIGN_TICKS` = 2 | §7.5 |
| `frontier_mult` | 1 + 0.5 (rival/beastman border) + 0.25 (capital dist > 6 hexes), cap 1.75 | §7.5.1 |
| `target_coverage` | clamp(0.7 + 0.6·military + ruler_delta, 0.5, 1.2) | §7.5.1 |
| `w1` / `w2` / overext cap | 1.0 / 2.0 / 3.0 | §7.5.1 |
| `land_value` table | plains/river 6 · hills 5 · forest 4 · mtn/desert/tundra 3 · +1 river-adj, cap 9 | §7.5.1 |
| severity bias weights | 0.3 tier / 0.4 overext / 0.6 proneness / 0.1 temperament | §7.6 |
| severity bands | rump < 0.50 ≤ shatter < 0.85 ≤ depopulate | §7.6 |
| `K` (shatter) | 1d3 + max(0, tier−3), clamp [2, min(6, vassals+2)] | §7.6 |
| `FADE_RATE` | 0.985/tick | §7.7 |
| `WAR_THRESHOLD` / `WAR_BASE` | 3 contested hexes / 0.10 (×1.5 opposed alignment) | §7.3.1 |
| war strength scalars | (0.5 + aggression) atk / (0.5 + defense) def; ruler_war ×1.15/0.85; multi_war 0.8^extra | §7.3.1 |
| margin jitter / bands | ±0.15 / 0.50 · 0.65 · 0.80 | §7.3.1 |
| decisive transfer | 1d3 frontier vassal domains | §7.3.1 |
| `CAPITAL_REACH` | 4 hexes (or Q below half pre-war size) | §7.3.1 |
| svg disposition | ≤0.35 vassalize / ≥0.65 annex / between: vassalize | §7.3.1 |
| pillage | gate: aggr ≥0.7, svg ≤0.3, clan; 50% chance; −20% front-region pop; +0.5× Q-income credit | §7.3.1 |
| war shock | loser +0.02 / winner +0.005 collapse risk | §7.3.1, §7.5 |
| `BASE_SECEDE` | 0.05 ×(1+mismatch)×(1−assimilation) | §7.4 |
| conversion-in-progress gate | conquered ≤2 ticks ago, different alignment, svg ≥ 0.5 → −2 morale seed | §10, §12 |
| `DIFFUSE_RATE` / edge damp | 0.02/tick; open 1.0 / rough 0.7 / mountain·river 0.25 / sea 0.1 | §6 |
| `ASSIMILATION_STEP` | 0.5 (lerp/tick at svg 1.0) | §6 |
| `POP_GROWTH` / settle start | 0.10/tick logistic / ~500 families per new 24-mi hex | §6 |
| hex caps (24-mi) | wilderness 2,000 / borderlands 4,000 / civilized 12,480 families | §6 |
| urban allocation | 10% of realm pop urban; capital 20% of that | §6 |
| `CORE_MAX` / `VASSAL_SIZE` | 3 hexes / tier-scaled: ≤Principality 3 · Kingdom 4 · Empire 6 | §7.4 |
| `MIGRANT_FRACTION` / pressure | 30% / 0.3 × slider × (0.5 + aggr − def), clamp [0.05, 0.6] | §8 |
| migration destination / speed | ≥3 contiguous unclaimed hexes at terrain_mult ≥ 1.15 / 10 hexes/tick | §8 |
| demihuman epoch bias | 1.0 → 3.0 over [0.375, 0.75] × N_TICKS, held; ascendancy until 0.375 × N_TICKS | §9 |
| temperament / migration sliders | 0.6/1.0/1.6 · 0/0.5/1.0/2.0 | §13 |
| `BEASTMAN_DELAY` / fill | 2 ticks / 0.25 × beastman_density per empty hex per tick | §7.6 |
| `REPLAY_CADENCE` | 4 ticks (100 yr) between replay frames | §15 |

---

## 8. Migration

The sim models **whole-culture relocation**, not just contiguous expansion. Triggers:

- **Displacement:** a catastrophic collapse (§7.6) converts `MIGRANT_FRACTION = 30%` of the fallen culture's population in the affected hexes into a migrating band.
- **Pressure:** a polity that lost its capital or >50% of its hexes within the last 2 ticks checks `p_migrate = 0.3 × migration_slider × (0.5 + aggression − defense)`, clamped [0.05, 0.6] — mobile, aggressive cultures relocate; stubborn, defensive ones stay and die in place.
- **Climate (optional/deferred):** if a future revision makes Layer-2 climate non-static, biome shift can trigger migration; for v1 climate is static and this trigger is off (§17).

**Mechanics (added 2026-06-12):** the band carries the migrating families and travels abstractly at `MIGRATION_SPEED = 10` hexes/tick toward the **nearest cluster of ≥ 3 contiguous unclaimed hexes** with `terrain_mult ≥ 1.15` (seed or secondary biome; ties broken by seed). If no destination exists anywhere, the band dissolves into the local substrate where it stops. **On arrival it founds a fresh polity** — `founded_tick` resets, so ascendancy (§7.2) applies anew: migrating peoples arrive vigorous, the Sea-Peoples/Anglo-Saxon pattern for free. The event log records "the X migrated from A to B" — the mechanical source of the "great migrations" the setting-gen timeline calls for, and the explanation for why a present-day people may sit far from its origin.

---

## 9. Demihuman Arc (emergent, heavily weighted toward the fall)

Demihumans are **not hard-scripted** to fall, but the sim is weighted so they almost always do, per the chosen design:

- **Golden age:** demihuman seeds found in the **deep-history epoch** and receive their high `lifecycle.peak_strength` as an expansion multiplier — and for demihuman-tier polities, **ascendancy runs until the epoch bias begins** (`0.375 × N_TICKS`, below) rather than the human `A_PEAK = 8` ticks, so the golden age actually spans the deep-history epoch. They become dominant forest (elf) and mountain/hill (dwarf) powers.
- **Weighted decline (concrete, 2026-06-12):** `epoch_bias(t)` multiplies demihuman-tier `collapse_risk`: 1.0 until `0.375 × N_TICKS`, ramping linearly to `EPOCH_BIAS_MAX = 3.0` at `0.75 × N_TICKS`, held thereafter (fractions of span, so `history_length` scales it). Compounding with high `collapse_proneness`, collapse-to-enclave by game-start is overwhelmingly likely. **Survival is purely emergent — no exemption mechanism (decided 2026-06-12):** whatever endures the full bias endures; at default constants a surviving demihuman *realm* (rather than enclave) will be vanishingly rare. `EPOCH_BIAS_MAX` is the tuning knob if the balance pass wants survivors to be more than a rounding error.
- **Mutual extermination:** the catalog's `conquest` modifier `target_is_demihuman → 1.0` (softened −0.2 for shared alignment) makes elf–dwarf and rival same-race wars extinction-level, accelerating the fall and producing especially thorough ruins.
- **Result:** present-day demihumans are scattered, high-`defense` enclaves dug into their last fastnesses (and the ACKS slow-growth/own-race rules then keep them fallen at runtime, `gdd-culture-catalog.md` §8.3); their lost golden-age realms are a rich, reliable source of ancient ruins and dungeons.

---

## 10. Religion and Alignment During the Sim

- **Alignment drift:** on collapse (§7.6), a successor/rump may shift alignment. The result is bounded to the **culture's allowed set** and gated by `(1 − rigidity)` scaled by collapse severity (`gdd-culture-catalog.md` §4.5). High-rigidity peoples hold their alignment through the fall; low-rigidity peoples fragment ideologically. **Fading cultures (§7.7) get no special treatment here** — if a fading polity does collapse, drift uses the normal rigidity gate.
- **Religion is derived, not simulated (simplified 2026-06-12, per Jedidiah).** Religion is entirely syncretic over the one shared pantheon (`gdd-setting-lore.md` §4); the only mechanically meaningful axis is Law/Neutral/Chaos. This is RAW, not just simplification: *"A domain's apparent alignment is determined by religious practice"* and *"shifting worship between gods of the same alignment does not count as changing religion for morale"* (`acore_axioms_strongholds_and_domains.xml` lines 466, 518). The sim therefore carries **no religion weights**: a hex's religious practice IS its `alignment_weights`; its tradition flavor (per-culture deity names, favored powers for temple dedications, culture-specific saints) derives at **runtime** from `culture_weights` × the shared pantheon (catalog `religion_hooks`; the saints system is runtime-TBD). `schism` events are emitted as narration tags when a collapse successor drifts alignment-family — same pantheon, new lens. The abandoned stance-taxonomy propagation model (`gdd-religion-system.md` §7) is superseded.
- **Handoff morale (religion side of §12):** ruler-vs-domain practice mismatch seeds the −1/−2 alignment penalties (lines 467–469). A domain conquered within the last 2 ticks by a different-alignment ruler with `effective_svg ≥ 0.5` (actively imposing practice) additionally seeds the ongoing **−2 conversion-in-progress** penalty (lines 519–520) [PROVISIONAL gate — §7.8].

---

## 11. Event Log

### 11.1 Event schema

```
{ tick, year_before_start, type, polity_ids[], culture_ids[], hexes[], region_hint, severity, summary_key }
```

`type` ∈ `{ founding, expansion, war, conquest, vassalage, secession, pillage, schism, migration, collapse_rump, collapse_shatter, depopulation, golden_age, dynasty_change, alignment_drift }`. `summary_key` is a stable key the LLM narrates (no prose stored mechanically).

### 11.2 Consumers

- **Layer-7 LLM timeline** (`gdd-setting-generation.md` §10) — selects significant events per epoch (§11.3) and narrates them, inventing named rulers/battles consistent with the log.
- **Ruin/dungeon provenance** — `depopulation` and `collapse_*` events tag the ruins/dungeon seeds they emit with the fallen polity's culture, era, and name, so a dungeon *is* "the throne-vault of the fallen Sargonids."
- **Region painting** — `toponym` roots of fallen polities become historical regional names (`gdd-region-painting.md`; `gdd-culture-catalog.md` §2 principle 8).
- **Rumors/quests** — recent-epoch events feed the rumor/quest seeding of `gdd-setting-generation.md` §9.8.

### 11.3 Significance selection

Each event gets a significance score (scale of polity, casualties, whether a capital/culture fell, downstream consequences). Layer 7 pulls the top-N per epoch to match the timeline densities in §4. The full log is retained as campaign data for context retrieval.

---

## 12. Present-Day Extraction and Handoff

At the final tick the sim freezes and converts to runtime campaign data:

1. **Polities → ACKS domains/realms.** Each surviving polity becomes a realm; its directly-held core and vassal chain map to ACKS domain tiers. Assign **ruler level/class**: class biased by the culture's `sphere_weights` over a fighter-leaning baseline (`gdd-culture-catalog.md` §4.3); level sized to the domain tier per the cited tables in **§12.1**.
2. **Seed domain morale** from the present state: borderlands/wilderness penalties, ruler/population alignment mismatch (−1/−2), recently-conquered unassimilated provinces (low-svg substrate still distinct) — all per `acore_axioms_strongholds_and_domains.xml`, so the world *opens* with the right tensions.
3. **Finalize territory classification** (civilized/borderlands/wilderness) and settlement placement from the emerged population bands, validated against the limits-of-growth caps and the ~50% wilderness target.
4. **Emit Layer-6 seeds** (dungeons/lairs/POIs from the collapse/depopulation log) and the Layer-7 timeline.
5. **Validate** against §2; **lock** as canonical (`gdd-setting-generation.md` §11.3 post-approval lock). The sim never runs again for that campaign.

From here the runtime ACKS domain/morale/economic systems take over — including, for demihumans, the slow-growth rules that keep their enclaves fallen.

### 12.1 Ruler-level → domain-tier reference (retrieved & cited 2026-06-12)

**A. Titles of nobility** — `acore_axioms_strongholds_and_domains.xml`, `<titles_of_nobility>`, lines 276–284 (ruler levels joined from `acore-setting-construction-rules.xml`, `demographics_of_leveled_characters`, lines 377–399):

| Title | `tier_index` | Personal domain (families) | Domains ruled | Overall realm (families) | Ruler level |
|---|---|---|---|---|---|
| Emperor | 6 | 12,500 | 5,461–55,987 | 2M–11.6M+ | 14 ("Empire") |
| King | 5 | 12,500 | 1,365–9,331 | 364K–2,000K | 12–13 ("Small kingdom" / "Kingdom") |
| Prince | 4 | 7,500 | 341–1,555 | 87K–322K | 10–11 ("Small principality" / "Principality") |
| Duke | 3 | 1,500 | 85–259 | 20K–52K | 9 ("Duchy or large city") |
| Count | 2 | 780 | 21–43 | 4,600–8,500 | 7–8 ("County or city" / "Large county or city") |
| Marquis | 1 | 320 | 5–7 | 960–1,280 | 5–6 ("Small march" / "March or large town") |
| Baron | 0 | 160 | 1 | 160 | 3–4 ("Small barony" / "Barony or village") |

**B. Realm sizes in 24-mile hexes** — `acore-setting-construction-rules.xml`, `realms_by_type`, lines 70–88: Empire 286–2,350+ · Kingdom 71–391 · Principality 18–65 · Duchy 4–11 · County 1–2 · March/Barony <1. Handoff sanity check only; in-sim tier keys on realm families (§7.4).

**C. Vassal decomposition** — `acore-setting-construction-rules.xml`, `political_divisions_of_realms`, lines 90–110: each realm contains **4–6 realms of the next tier down**. Used at handoff to decompose a realm's vassal chain down to the March/Barony tiers below sim resolution, and as the grounding for the §7.6 K-distribution.

**D. Tribute precision** — the family ranges above are quick-construction estimates. The sim always knows actual realm families, so tribute is computed precisely via `tribute_by_realm_families` or the optional formula `18gp × realm_families^0.6` (`acore_axioms_strongholds_and_domains.xml`, lines 299–350) (per Jedidiah, 2026-06-12).

**E. Stronghold value and revenue (corrected 2026-06-13).** `revenue_by_realm_type` (`acore-setting-construction-rules.xml`, lines 112–130) carried a transcription error that has now been corrected in the rules XML. The corrected `rulers_stronghold_value_gp` column is the **stronghold value used at handoff (§12.1)**:

| Title | Stronghold value (gp) | Personal domain (families) |
|---|---|---|
| Empire | 720,000+ | 12,500 |
| Kingdom | 480,000 | 12,500 |
| Principality | 360,000 | 7,500 |
| Duchy | 115,000 | 1,500 |
| County | 70,000 | 780 |
| March | 45,000 | 320 |
| Barony | 22,500 | 160 |

The correction also brought the table's personal-domain-families column into agreement with `titles_of_nobility` (§12.1A), so both tables now agree and the earlier "extraction variance / do not consume the personal-domain column" caveat is **retired**. (The previously-transcribed Principality 240K / Duchy 120K / County 60K stronghold values were the error.) The table's monthly-income columns (`domain_income_per_month_gp` / `urban_income_per_month_gp`) are realm-scale aggregates for quick construction; the sim instead computes income **per family** from `domain_revenue` (Land 3–9 + Services 4 + Taxes 2, §7.5.1), which is unchanged. `DomainTierTable.stronghold_value_for_tier()` carries the corrected values.

---

## 13. Player Parameters

| Parameter | Default | Effect |
|---|---|---|
| `history_length` | ~4,000 yr / 160 ticks | Short 80 / standard 160 / deep 240 ticks (2k/4k/6k yr). Epochs and the §9 demihuman fractions scale proportionally. Deeper = more rise/fall, more ruins, older world |
| `collapse_temperament` | **Moderate** | The §7.5 global multiplier: **Stable 0.6 / Moderate 1.0 / Turbulent 1.6** (also tilts severity, §7.6). Stable = few enduring realms, fewer ruins; Turbulent = churning history, fragmented map, many dungeon sites |
| `seed_points` | per catalog §6.1 | ~10 human, ≤3/demihuman race |
| `demihuman_presence` | on | Whether demihuman seeds are placed at all |
| `beastman_density` | 1.0 | Multiplier on post-collapse beastman repopulation (ties to `gdd-setting-generation.md` §6.5) |
| `migration_rate` | moderate | The §8 `migration_slider`: **off 0 / low 0.5 / moderate 1.0 / high 2.0** |

All have sensible defaults; a player who just wants to play skips them.

---

## 14. Determinism and Performance

- **Determinism:** all randomness draws from per-subsystem streams seeded off the campaign seed + tick + entity id, so the same seed reproduces the same history exactly (required for the post-approval lock and for regenerate-this-element). No wall-clock or hash-order dependence.
- **Performance:** ~160 ticks over a Large map (~1,200 hexes) with a handful-to-dozens of polities is cheap — every per-tick phase (expansion frontier, contests, substrate diffusion, and the realm economy/garrison ledger of §7.5.1) is O(active frontier) or O(hexes + vassal-edges). The economy ledger is one extra sum-over-hexes pass, not a new order of magnitude. Target: full sim well under a few seconds even on a Huge map; it runs once at campaign creation behind the existing progress bar.

---

## 15. Integration Points

**Inputs:** map + climate (`gdd-setting-generation.md` Layers 1–2); seeded, placed, jittered cultures (`gdd-culture-catalog.md` §6); all per-culture mechanical fields.

**Outputs:** the present-day political map and substrate weights (the rewritten Layer 4 result); ruin/dungeon and POI seeds with provenance (Layer 6 — `gdd-dungeon-layout.md`, `gdd-poi-generation.md`); the structured event log and significance ranking (Layer 7 — LLM timeline, setting brief, rumors/quests); fallen-polity `toponym` roots (`gdd-region-painting.md`); **replay frames** — a political-ownership snapshot (RLE owner-by-hex + stable polity palette) every `REPLAY_CADENCE = 4` ticks, ~40 frames per default run at tens-of-kilobytes total, persisted as campaign data for the campaign-creation history replay (`gdd-campaign-creation-ui.md` §5/§7).

**Output contract:** `gdd-setting-generation.md` §7.2 (wired 2026-06-12) specifies the exact data shapes Layers 5–8 consume — polities, hex substrate, settlements-by-emergence, event log, ruin seeds with provenance, fallen-polity toponyms. The sim must emit that contract; replaces the old static Voronoi/diffusion model.

---

## 16. Worked Example (abridged trace)

```
Seed (tick 0): Sargonid (human, plains, Lawful/Neutral even split → Lawful this run) on a great river;
               Vargari (human, coast/taiga, Neutral/Chaotic → Chaotic); a Sylvan elf seed in the deep forest.

Deep history (ticks 0–100):
  - Sylvans hit their golden age: high peak_strength + forest aggression → they dominate the woodland third
    of the continent, exterminating two early human bands that pushed into the trees (in-biome svg 0.9).
  - Sargonids expand down the river (size-exponent: fast while small), found vassal duchies, become an empire.

Middle history (ticks 100–148):
  - Sargonid empire overreaches (f_size + f_overextension high); a strong ruler holds it two generations,
    then a weak succession + a lost frontier war trips the collapse roll → SHATTER into 4 successors
    (3 from breakaway vassal duchies, 1 bandit-challenger kingdom). Two stay Lawful; one drifts Neutral
    (rigidity 0.8 held the rest). Emits: collapse_shatter event, a depopulated march → ruins seed
    ("the Drowned Vaults of Sargon"), and a migrating Sargonid band that resettles the coast.
  - Sylvan realm begins its weighted decline (epoch bias + collapse_proneness): elf–dwarf wars and human
    counter-pressure shatter it; depopulation emits several elven ruins. One small fastness endures.

Recent history (ticks 148–160):
  - The Vargari, late and aggressive, raid the fractured Sargonid coast (pillage outcomes, §7.3.1);
    one successor wins a crushing war and wholesale-vassalizes them (low svg → fealty, not absorption).
  - Borders settle into the present-day map: 5 human realms (2 Sargonid-successor, 1 Vargari-influenced,
    2 others), 1 surviving Sylvan enclave, beastman clanholds in the depopulated interior.

Handoff: polities → ACKS domains with ruler levels/classes and seeded morale; ~9 dungeon/ruin seeds with
         provenance; a Layer-7 timeline of ~35 ranked events. Locked as canonical.
```

---

## 17. Open Questions / Deferred

- **Balance pass.** All functional forms and constants are now concrete (2026-06-12; consolidated in §7.8) but remain **[PROVISIONAL]** pending a single tuning pass once the sim runs against real maps and the authored 65-culture set. Tuning targets: realm-lifetime distributions (§7.5 calibration), end-state map shape (~50% wilderness, 5–10 surviving realms on Large), ruin density per epoch, and the demihuman enclave rate.
- ~~**Religion propagation (§10)**~~ — **RESOLVED 2026-06-12 (simplified):** religion is derived from alignment + culture, never simulated; no religion weights, no propagation constants. Only the conversion-in-progress handoff gate (2 ticks / svg ≥ 0.5) joins the §7.8 balance pass.
- **Climate-driven migration (§8)** — off for v1 (static Layer-2 climate); revisit if climate is made dynamic.
- **Civ/clan transitions (catalog §4.7) — DEFERRED to v2 (decided 2026-06-12).** `civ_or_clan_state` holds its authored start value for the entire sim; no promotion or regression in v1. Accepted limitation: a long-settled clan empire still reads as "clan" in Layer-7 narration. The catalog's "the sim may promote" language describes v2 intent.
- **Inter-polity diplomacy.** v1 models only expansion/war/collapse; alliances, marriages, and tribute relationships beyond simple vassalage are deferred (the LLM may narrate flavor diplomacy atop the mechanical log).
- ~~**Setting-generation Layer 4 rewrite**~~ — **RESOLVED 2026-06-12:** wired into `gdd-setting-generation.md` (output contract §7.2; Layer 6 reconciliation §9.1/9.3/9.5/9.6; validation §11.1).

## 18. Revision History

- **2026-06-12 (v0.5, rev 2):** Added replay-frame emission to §15 outputs (`REPLAY_CADENCE = 4` ticks; RLE owner-by-hex + stable polity palette; §7.8 row) for the campaign-creation history replay (`gdd-campaign-creation-ui.md`).
- **2026-06-12 (v0.5):** **Constants session — the simulation core is now fully specified.** §6: DIFFUSE_RATE 0.02 with terrain edge-damping; ASSIMILATION_STEP 0.5; logistic demography (POP_GROWTH 0.10, 24-mi caps 2,000/4,000/12,480 per limits-of-growth lines 156–161, ~500-family settlement seed per RAW wilderness starting pop lines 102–104, classification per lines 165–176); urban emergence by the 10%/20% allocation rule (setting-construction lines 163–164) with emergence_tick. §7.4: internal organization rule — CORE_MAX 3 (axioms lines 267–271), tier-scaled VASSAL_SIZE (≤Principality 3 / Kingdom 4 / Empire 6, decided over flat sizes). §8 migration mechanics: MIGRANT_FRACTION 30%, pressure formula 0.3×slider×(0.5+aggr−def) (frequency confirmed as proposed), destination/speed rules, fresh-polity arrival with renewed ascendancy. §9: epoch bias 1.0→3.0 over [0.375, 0.75]×span; demihuman ascendancy extended to span the deep-history epoch; **pure emergence — no survival exemption** (decided; EPOCH_BIAS_MAX is the knob if balance wants survivors possible). §13 slider values (Stable 0.6/Moderate 1.0/Turbulent 1.6; migration 0/0.5/1.0/2.0; history 80/160/240 ticks with proportional scaling). §7.6 beastman respawn timing (DELAY 2 ticks, 0.25×density fill, ax lines 243–262). **Civ/clan transitions deferred to v2** (decided; §17). All constants added to §7.8. Design forks decided with Jedidiah 2026-06-12.
- **2026-06-12 (v0.4):** **Religion simplified per Jedidiah.** The stance taxonomy (syncretist/inclusivist/exclusivist) and propagation sim are abandoned holdovers; religion is entirely syncretic, the only axis is Law/Neutral/Chaos, names/flavor change per culture over the one shared pantheon, saints are runtime-TBD. Matches RAW (`acore_axioms_strongholds_and_domains.xml` lines 466, 518: practice determines apparent alignment; same-alignment worship shifts are not religion changes). Dropped `religion_weights` from the hex substrate (§5, §6) — religion derives from alignment_weights × culture_weights at runtime; nothing religious is generated pre-game, not even deity names (Layer 7 uses canonical lore names; per-culture renderings are runtime). §10 rewritten (derived religion + handoff morale mapping: −1/−2 mismatch per lines 467–469; provisional conversion-in-progress −2 seed for fresh different-alignment high-svg conquests per lines 519–520). §17 religion item resolved. Cross-edits: `gdd-setting-generation.md` §7.2/§7.3, supersession banner on `gdd-religion-system.md` §7.
- **2026-06-12 (v0.3):** **Realm-scale war resolution.** Jedidiah flagged that conquest was hex-crawl-only and victors came from per-hex rolls with no realm outcome. Added §7.3.1: hex contests reclassified as the skirmish layer; sustained friction escalates to one-tick wars (a tick = 25 years holds a whole war — decided over persistent war state). Strength = gp-value army budget (`garrison_spent`, the §7.5.1 ledger) × aggression/defense scalars × ruler/ascendancy/fade × front terrain × multi-war penalty; seeded margin with ±0.15 jitter. Outcome ladder: defender holds / border victory (old behavior) / decisive (1d3 frontier vassal domains transfer whole) / crushing (margin ≥0.80 + capital reach within 4 hexes) → svg-driven disposition: ≤0.35 wholesale vassalization (intact polity, tribute per §12.1D, `vassalized_by_war`), ≥0.65 annexation, raider-profile pillage override (50%; −20% front-region pop per the DaW pillage rule). War shock feeds §7.5 (loser +0.02/winner +0.005). Added §7.4 vassal secession (war-vassalized or culturally distinct vassals only; BASE_SECEDE 0.05 × mismatch × unassimilation, checked when the liege is weak). Grounded in `daw_campaigning_armies.xml` lines 762–789 (conquest definition, post-conquest assimilate/vassalize/pillage options) and `ax_domains_of_chaos.xml` lines 43, 100. Added `pillage` event type, `vassalized_by_war` polity field, §7.8 constants; updated §3 loop and §16 example. All four design forks decided with Jedidiah 2026-06-12.
- **2026-06-12 (v0.2, rev 2):** Layer 4 rewrite of `gdd-setting-generation.md` completed; updated this GDD's cross-references (header Replaces/Blocks, §15 output contract pointer, §17 rewrite item resolved). The sim's output is now bound to the §7.2 contract in that GDD.
- **2026-06-12 (v0.2):** Resolved §17 items 1–5 with Jedidiah (advisor session). (1) Retrieved and cited the ruler-level→domain-tier reference as new §12.1: titles_of_nobility (axioms lines 276–284), ruler levels (setting-construction lines 377–399), realm hex sizes (lines 70–88), 4–6 vassal fan-out (lines 90–110), precise tribute via `18gp × families^0.6` / tribute table (lines 299–350); flagged the `revenue_by_realm_type` personal-domain extraction variance (PDFs match titles values per Jedidiah). (2) Concrete functional forms: expansion defaults G=4/N0=30/α=1.0 with deterministic fractional accumulator and ascendancy/fade/ruler multipliers (§7.2); contest power_factor (N-ratio^0.3 clamped), readiness = 0.5+0.5×coverage coupling the ledger into war, discrete home_factor, failed-contest attrition (§7.3); tier-multiplier f_size (1.35^tiers-above-County, decided over continuous form), f_age ramp/slope, per-reign ruler quality, BASE=0.01 with calibration targets (§7.5). (3) Economy constants: frontier_mult, target_coverage curve, w1/w2; replaced MIN_RATE_FRACTION with the cited RAW 2gp/family floor (line 226); fixed per-terrain land_value table (§7.5.1). (4) Severity formula with bias weights, 0.50/0.85 bands, shatter gating; K-distribution converging on the cited 4–6 fan-out (§7.6). (5) Wired `end_state:'fading'` as new §7.7 (post-peak onset: age>A_PEAK and tier≥Duchy; FADE_RATE 0.985/tick on aggression/defense/growth; deliberately excluded from collapse_risk) with hooks in §5, §6, §7.2, §7.3, §7.5, §10. Added §7.8 consolidated constants table; in-sim tier determination keyed on realm families (§7.4). All constants [PROVISIONAL] pending the §17 balance pass.
- **2026-06-03 (rev 2):** Added §7.5.1 Realm economy and garrison — the concrete, ACKS-grounded ledger behind `f_overextension`: per-realm income (domain_revenue), fixed overhead, garrison need by territory class (civ 2 / border 3 / wild 4 gp/family) with a frontier multiplier, garrison policy driven by culture militarism + ruler quality, automatic tick-to-tick adjustment (expansion spikes need while income lags), and the overextension output. Confirmed it is aggregate gp-value accounting (not unit simulation), O(hexes)/tick, low-millisecond cost (§14). Cited `acore_axioms_strongholds_and_domains.xml` domain_revenue and domain_expenses/garrison. Updated §17 deferred constants.
- **2026-06-03:** Initial draft. Two-layer (substrate + polity) model on the 24-mile hex map; generation tick over ~4,000-year span aligned to setting-gen timeline epochs. Expansion with size-exponent; seeded border contest; whole-culture migration. Size+age+overextension collapse curve with moderate default + player temperament slider; rump/shatter/depopulate outcomes; successor seeding grounded in the ACKS Rebellious bandit/NPC-challenger mechanic; alignment drift bounded by rigidity; depopulation → wilderness + beastmen + ruins. Demihuman golden-age→enclave arc as emergent-but-heavily-weighted (epoch bias + high collapse_proneness + mutual genocide). Religion propagation deferred to the religion rework. Event log with significance selection feeding Layer 7, dungeon provenance, region toponyms, rumors. Present-day ACKS handoff and validation. Player parameters, determinism, integration points, worked example. ACKS constraints cited; ruler-tier table flagged for lookup.
