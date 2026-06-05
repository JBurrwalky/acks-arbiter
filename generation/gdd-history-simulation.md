# GDD: History Simulation

**Document type:** Game Design Document (project-designed engine, with explicit ACKS Constraints).
**Status:** Draft
**Version:** v0.1
**Authority:** PROJECT-DESIGNED — the simulation substrate, tick model, expansion/contest/collapse/migration algorithms, and all numeric parameters are engineering decisions. ACKS governs only (a) the *plausibility of the inputs* and (b) the *validity of the present-day output* that hands off to the runtime domain system (§2, §12).
**Depends on project GDDs:** `gdd-culture-catalog.md` (consumes the per-culture mechanical fields: `aggression`, `defense`, `size_exponent_bias`, `conquest`, `lifecycle`, `alignment`, `rigidity`, `road_propensity`, `sphere_weights`), `gdd-setting-generation.md` (consumes Layer 1–3 geography/climate/seed placement; **replaces** the static culture diffusion of §7.1 and the Voronoi borders of §6.2; produces the Layer 7 timeline and feeds the Layer 6 dungeon/POI seeds), `gdd-terrain-system.md` (biome tags), `gdd-dungeon-layout.md` and `gdd-poi-generation.md` (collapse emits ruins/dungeon and POI seeds), `gdd-region-painting.md` (future — consumes fallen-polity toponyms).
**Depends on ACKS rules:** `acore_axioms_strongholds_and_domains.xml` (domain morale; the Rebellious bandit/NPC-challenger mechanic; alignment- and religion-mismatch penalties; limits-of-growth caps; classification advancement; domain-growth racial modifiers — both the present-day handoff target and the grounding for collapse), `acore-setting-construction-rules.xml` (population density, territory classification, realm sizing — present-day validity), `ax_domains_of_chaos.xml` (beastman repopulation of depopulated regions).
**Replaces:** `gdd-setting-generation.md` §6.2 (static weighted-Voronoi borders) and §7.1 (static cultural diffusion). Those are superseded by this simulation.
**Blocks:** `gdd-setting-generation.md` Layer 4 rewrite; the naming half of `gdd-region-painting.md`.
**Modifiable by Claude Code:** All algorithms and parameters — yes, subject to the ACKS Constraints in §2.
**Last updated:** 2026-06-03

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
  2. WAR & CONQUEST  resolve contests; rewrite conquered substrate per conquest rules (§7.3, §6)
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

**Polity** — `{ id, culture_id, alignment, ruler (level/class), founded_tick, hexes[], capital_hex, liege_id?, vassal_ids[], civ_or_clan_state, economy_estimate }`. A polity has an **age** (current_tick − founded_tick) and **size** (len(hexes)).

**Hex substrate** — per 24-mile hex: `{ culture_weights{}, religion_weights{}, alignment_weights{}, population_band, territory_class, owner_polity_id? }`. These are exactly the weight vectors `gdd-setting-generation.md` §7.3 consumes; the sim writes them over time.

**Event record** — see §11.

---

## 6. Layer A: Culture Substrate

Each hex carries weight vectors that evolve:

- **Diffusion (slow):** each tick, a hex's culture weights bleed a small fraction into adjacent hexes, damped across biome and elevation barriers (mountains, major rivers, coast) per `gdd-terrain-system.md` movement costs. This is the *demographic* spread of a people independent of politics — much slower than political expansion.
- **Conquest rewrite:** when polity P holds a hex, the hex's culture/religion/alignment weights shift toward P at `effective_svg × ASSIMILATION_STEP` per tick, where `effective_svg` is computed from P's culture `conquest` base + modifiers (`gdd-culture-catalog.md` §4.4). Low svg = the conquered remain themselves (vassalage); high svg = they convert within a few generations (genocide/absorption).
- **Demography:** population bands grow toward the terrain caps (Wilderness/Borderlands/Civilized per `acore_axioms_strongholds_and_domains.xml`) when securely held, and shrink under war, collapse, or depopulation. Classification advances per the ACKS thresholds as hexes fill and urban settlements emerge.
- **Minimum floor:** every group retains the small presence floor of `gdd-setting-generation.md` §7.3 (traders, refugees) so no culture is ever truly zeroed from a region it once held — useful for the LLM ("a Keshite minority lingers in the old capital").

---

## 7. Polity Lifecycle

### 7.1 Founding

At tick 0, each seed point (catalog §6.3) instantiates one small polity in wilderness, of its culture and drawn alignment. Demihuman seeds are founded here too (their golden age is the deep-history epoch, §9). As a polity grows past size thresholds it **spawns vassal domains** (governors/sub-rulers) rather than ruling all hexes directly — this is how the vassal chain and eventual realm tiers (barony → … → empire, ACKS domain tiers) *emerge* rather than being drawn.

### 7.2 Expansion

Each tick a polity P of size `N` (hexes) gets an expansion budget:

```
expansion_pressure(P) = aggression_P × G × ( N0 / (N + N0) ) ^ α
    G   = global growth constant (baseline hexes/tick)              [provisional]
    N0  = half-saturation size (small polities expand fast)         [provisional]
    α   = global size-exponent + culture.size_exponent_bias         (small → fast, large → slow)
```

This encodes your **size-based expansion exponent**: a young, small polity expands quickly; a sprawling empire crawls. Candidate hexes are the polity's frontier, ranked by the culture's per-terrain multiplier (catalog §4.1) so a people surges through its `seed_biomes` and stalls in `avoided` terrain. Each candidate, up to the budget:

- **Wilderness hex** → settle: claim it, seed the substrate with P's culture, possibly spawn a vassal domain.
- **Hex owned by polity Q** → contest (§7.3).

### 7.3 Border contest

```
atk = aggression_P × terrain_mult_P(hex) × power_factor(P)
def = defense_Q    × terrain_mult_Q(hex) × home_factor(Q, hex)     (home_factor > 1 near Q's capital / forts)
p_win = atk / (atk + def)                                          (seeded roll)
```

On a win the hex flips to P and its substrate begins rewriting per P's `effective_svg`. On a loss, no transfer (and optional attrition that nudges both polities' stability). `defense` being the catalog's resistance scalar, a high-`defense` culture (e.g. the Shidheans, the Sylvan elves) is very hard to push out of its terrain even when out-expanded.

### 7.4 Vassalage and realm tiers

When a polity's directly-held core exceeds a size/level threshold, additional conquered/settled territory is organized as **vassal domains** under sub-rulers, forming a realm. Realm tiers (and the ruler levels that hold them) follow the ACKS domain-tier framework referenced in `gdd-setting-generation.md` §2 (`acore_axioms_strongholds_and_domains.xml` / `acore-setting-construction-rules.xml`); the exact ruler-level→tier numbers are applied from those tables at the handoff (§12) — flagged for lookup (§17). Vassals matter for collapse: they are the natural successor states (§7.6).

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
```

- **f_size** is grounded in ACKS: larger domains are harder to control and strain vassal loyalty (`acore_axioms_strongholds_and_domains.xml`). Beyond a cohesion threshold, each additional tier multiplies risk.
- **f_overextension** uses the ACKS economic-viability rule (income must cover garrison, `gdd-setting-generation.md` §2): a realm that expanded faster than it can garrison is fragile.
- **temperament** is the single global multiplier the player slider moves (§13); the **default is moderate** — enough rise/fall to seed ruins and successor states without shredding the map.

A seeded roll vs `collapse_risk(P)` each tick determines whether P collapses this generation.

### 7.5.1 Realm economy and garrison (the overextension inputs)

`f_overextension` is not hand-waved — each tick it is computed from a lightweight **aggregate** realm ledger. The key design choice: this is **gp-value accounting, not unit-level troop simulation.** ACKS itself frames garrison as a gp-per-family spend (`acore_axioms_strongholds_and_domains.xml`, domain_expenses), so the macro-sim tracks a garrison *budget* against a garrison *need* and never models individual companies — troop composition is a runtime concern after handoff (`daw_*` tables are for play, not the 4,000-year sim). All figures below are ACKS monthly rates used as **relative magnitudes** per tick, not literal monthly gp.

**Income** (per realm R per tick), from domain_revenue:

```
income(R) = Σ_hex  families(hex) × ( land_value(hex) + 4 + 2 )     # Land (3–9, the hex's value) + Services 4 + Taxes 2, per family
          + tribute_in(R)                                          # from vassals
          − tribute_out(R)                                         # to liege, if any
```

`land_value` is the hex's 3–9 gp Land value; the sim may use a per-terrain constant set at map-gen rather than re-rolling per hex.

**Fixed overhead** (non-garrison obligations, domain_expenses): Liturgies + Maintenance + Tithes = **3 gp/family** flat.

**Garrison need**, from the garrison rules ("a ruler must spend at least 2gp per peasant family per month on troops"; "Borderlands domains commonly maintain 3gp per family; wilderness domains must maintain 4gp per family or base morale is reduced"):

```
garrison_need(R) = Σ_hex  families(hex) × base_rate(class(hex)) × frontier_mult(hex)
    base_rate:   civilized 2,  borderlands 3,  wilderness 4   (gp/family)
    frontier_mult > 1 for hexes bordering a rival polity or far from the capital     [provisional]
```

The frontier multiplier is the project-designed part: a realm with a long contested border or distant marches needs proportionally more garrison than its raw family count implies.

**Actual garrison** (the realm's per-tick policy):

```
affordable(R)      = income(R) − overhead(R)                       # what's left after fixed obligations
target_coverage(R) = f( culture.sphere_weights.military, ruler_quality )   # militarist → aim ≥1.0; mercantile/arcane → tolerate thin frontiers
garrison_spent(R)  = min( garrison_need(R) × target_coverage(R), max(affordable(R), 0) )
garrison_coverage  = garrison_spent(R) / garrison_need(R)
```

A militaristic culture reliably funds toward full coverage; a mercantile or arcane-leaning one tolerates thinner frontiers and is more prone to overextension. A strong ruler raises effective coverage during their reign.

**Adjustment across ticks is automatic, and is the whole point.** When a realm expands fast (§7.2), its garrison *need* spikes that same tick — more hexes, more frontier, newly-conquered restless provinces whose substrate hasn't assimilated — while its *income* lags, since new hexes are underpopulated and unproductive for generations. Coverage drops, overextension rises: the "bit off more than it can hold" failure mode emerges from the ledger with no scripting.

**Overextension factor** feeding §7.5:

```
solvency(R)        = income(R) − overhead(R) − garrison_need(R) × MIN_RATE_FRACTION
f_overextension(R) = 1 + w1 · max(0, 1 − garrison_coverage)        # under-garrisoned frontier
                       + w2 · max(0, −solvency(R)) / scale         # bankrupt: can't meet even minimum garrison
```

Under-garrison nudges collapse risk; insolvency drives it hard — the macro analogue of the ACKS morale spiral, where failing the garrison requirement reduces morale and tips a domain toward *Rebellious* (`acore_axioms_strongholds_and_domains.xml`). The same ledger seeds the **present-day morale** at handoff (§12): a realm arriving chronically under-garrisoned in borderlands/wilderness carries the corresponding ACKS morale penalties (Borderlands −1, Wilderness −2) and forfeits the garrison morale bonuses.

**Cost:** the ledger is **O(hexes + vassal-edges) per tick** — one extra sum-over-hexes pass, the same order as substrate diffusion. Over ~160 ticks on a Huge map it is a low-millisecond addition (§14). It is *cheaper* than the expansion-frontier phase, not a new order of magnitude.

### 7.6 Collapse outcomes

On collapse, roll **severity** (seeded), scaled by `N`, `f_overextension`, and `collapse_proneness`:

- **Rump (minor):** P sheds its borderland/frontier hexes (the least-assimilated, farthest-from-capital first); core + capital survive as a smaller polity. Some shed hexes may become independent successors.
- **Shatter (major):** P fragments into **K successor polities**, where `K ≈ f(vassal_count, size)`. Successors are seeded, in priority order, from: existing vassal domains (governors declaring independence), then **NPC challengers risen from bandits** (the ACKS Rebellious mechanic, `acore_axioms_strongholds_and_domains.xml`), then the surviving rump around the capital. Each successor inherits P's culture; its alignment may **drift** (§10).
- **Depopulate (catastrophic):** the region loses most of its population (the ACKS family-loss path), its hexes revert toward **wilderness** classification, **beastmen spawn** per `ax_domains_of_chaos.xml`, and **ruins/dungeon seeds** are emitted carrying the fallen polity's provenance (culture, era, name) for `gdd-dungeon-layout.md` and the Layer-6 dungeon target. Survivors may form a **migrating band** (§8).

Severity is weighted by temperament and `collapse_proneness`: high-proneness cultures (demihumans) shatter and depopulate disproportionately, which is what fills the deep map with elven/dwarven ruins.

---

## 8. Migration

The sim models **whole-culture relocation**, not just contiguous expansion. Triggers:

- **Displacement:** a catastrophic collapse (§7.6) converts a fraction of the fallen culture's population into a migrating band.
- **Pressure:** a culture squeezed out of its homeland (sustained conquest losses, lost capital) may migrate rather than be assimilated, weighted by its `aggression`/`defense` profile.
- **Climate (optional/deferred):** if a future revision makes Layer-2 climate non-static, biome shift can trigger migration; for v1 climate is static and this trigger is off (§17).

A migration relocates a chunk of culture weight (and optionally a surviving polity) across the map to the nearest unclaimed region best matching the culture's `seed_biomes`, possibly crossing other territories. It founds a new seed there and logs a "the X migrated from A to B" event — the mechanical source of the "great migrations" the setting-gen timeline calls for, and the explanation for why a present-day people may sit far from its origin.

---

## 9. Demihuman Arc (emergent, heavily weighted toward the fall)

Demihumans are **not hard-scripted** to fall, but the sim is weighted so they almost always do, per the chosen design:

- **Golden age:** demihuman seeds found in the **deep-history epoch** and receive their high `lifecycle.peak_strength` as an expansion multiplier in early ticks — they become dominant forest (elf) and mountain/hill (dwarf) powers.
- **Weighted decline:** an **epoch bias** ramps demihuman `collapse_risk` upward after the deep-history peak, compounding with their high `collapse_proneness`. The combination makes a collapse-to-enclave by game-start overwhelmingly likely while leaving a small seeded chance that one demihuman realm endures larger into the present (the "emergent but heavily weighted" outcome).
- **Mutual extermination:** the catalog's `conquest` modifier `target_is_demihuman → 1.0` (softened −0.2 for shared alignment) makes elf–dwarf and rival same-race wars extinction-level, accelerating the fall and producing especially thorough ruins.
- **Result:** present-day demihumans are scattered, high-`defense` enclaves dug into their last fastnesses (and the ACKS slow-growth/own-race rules then keep them fallen at runtime, `gdd-culture-catalog.md` §8.3); their lost golden-age realms are a rich, reliable source of ancient ruins and dungeons.

---

## 10. Religion and Alignment During the Sim

- **Alignment drift:** on collapse (§7.6), a successor/rump may shift alignment. The result is bounded to the **culture's allowed set** and gated by `(1 − rigidity)` scaled by collapse severity (`gdd-culture-catalog.md` §4.5). High-rigidity peoples hold their alignment through the fall; low-rigidity peoples fragment ideologically.
- **Religion propagation is a deferred hook.** The substrate carries religion weights that conquest-genocide rewrites (§6), but the *spread model* (syncretist vs. exclusivist diffusion, schisms, conversion) belongs to the **religion-system rework** that `gdd-culture-catalog.md` §12 defers. Until that GDD lands, the sim treats religion as following alignment + conquest only, and logs schism/conversion events as stubs the rework will flesh out. **Flagged in §17.**

---

## 11. Event Log

### 11.1 Event schema

```
{ tick, year_before_start, type, polity_ids[], culture_ids[], hexes[], region_hint, severity, summary_key }
```

`type` ∈ `{ founding, expansion, war, conquest, vassalage, secession, schism, migration, collapse_rump, collapse_shatter, depopulation, golden_age, dynasty_change, alignment_drift }`. `summary_key` is a stable key the LLM narrates (no prose stored mechanically).

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

1. **Polities → ACKS domains/realms.** Each surviving polity becomes a realm; its directly-held core and vassal chain map to ACKS domain tiers. Assign **ruler level/class**: class biased by the culture's `sphere_weights` over a fighter-leaning baseline (`gdd-culture-catalog.md` §4.3); level sized to the domain tier per the ACKS tables (`acore_axioms_strongholds_and_domains.xml` / `acore-setting-construction-rules.xml`).
2. **Seed domain morale** from the present state: borderlands/wilderness penalties, ruler/population alignment mismatch (−1/−2), recently-conquered unassimilated provinces (low-svg substrate still distinct) — all per `acore_axioms_strongholds_and_domains.xml`, so the world *opens* with the right tensions.
3. **Finalize territory classification** (civilized/borderlands/wilderness) and settlement placement from the emerged population bands, validated against the limits-of-growth caps and the ~50% wilderness target.
4. **Emit Layer-6 seeds** (dungeons/lairs/POIs from the collapse/depopulation log) and the Layer-7 timeline.
5. **Validate** against §2; **lock** as canonical (`gdd-setting-generation.md` §11.3 post-approval lock). The sim never runs again for that campaign.

From here the runtime ACKS domain/morale/economic systems take over — including, for demihumans, the slow-growth rules that keep their enclaves fallen.

---

## 13. Player Parameters

| Parameter | Default | Effect |
|---|---|---|
| `history_length` | ~4,000 yr / 160 ticks | Deeper history = more rise/fall, more ruins, older world |
| `collapse_temperament` | **Moderate** | The §7.5 global multiplier — slider from Stable (few enduring realms, fewer ruins) to Turbulent (churning history, fragmented map, many dungeon sites) |
| `seed_points` | per catalog §6.1 | ~10 human, ≤3/demihuman race |
| `demihuman_presence` | on | Whether demihuman seeds are placed at all |
| `beastman_density` | 1.0 | Multiplier on post-collapse beastman repopulation (ties to `gdd-setting-generation.md` §6.5) |
| `migration_rate` | moderate | How readily displaced/pressured cultures relocate (§8) |

All have sensible defaults; a player who just wants to play skips them.

---

## 14. Determinism and Performance

- **Determinism:** all randomness draws from per-subsystem streams seeded off the campaign seed + tick + entity id, so the same seed reproduces the same history exactly (required for the post-approval lock and for regenerate-this-element). No wall-clock or hash-order dependence.
- **Performance:** ~160 ticks over a Large map (~1,200 hexes) with a handful-to-dozens of polities is cheap — every per-tick phase (expansion frontier, contests, substrate diffusion, and the realm economy/garrison ledger of §7.5.1) is O(active frontier) or O(hexes + vassal-edges). The economy ledger is one extra sum-over-hexes pass, not a new order of magnitude. Target: full sim well under a few seconds even on a Huge map; it runs once at campaign creation behind the existing progress bar.

---

## 15. Integration Points

**Inputs:** map + climate (`gdd-setting-generation.md` Layers 1–2); seeded, placed, jittered cultures (`gdd-culture-catalog.md` §6); all per-culture mechanical fields.

**Outputs:** the present-day political map and substrate weights (the rewritten Layer 4 result); ruin/dungeon and POI seeds with provenance (Layer 6 — `gdd-dungeon-layout.md`, `gdd-poi-generation.md`); the structured event log and significance ranking (Layer 7 — LLM timeline, setting brief, rumors/quests); fallen-polity `toponym` roots (`gdd-region-painting.md`).

**Replaces** the static `gdd-setting-generation.md` §6.2 (Voronoi borders) and §7.1 (culture diffusion); the Layer 4 rewrite will call this sim instead.

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
  - The Vargari, late and aggressive, raid the fractured Sargonid coast; one successor vassalizes them.
  - Borders settle into the present-day map: 5 human realms (2 Sargonid-successor, 1 Vargari-influenced,
    2 others), 1 surviving Sylvan enclave, beastman clanholds in the depopulated interior.

Handoff: polities → ACKS domains with ruler levels/classes and seeded morale; ~9 dungeon/ruin seeds with
         provenance; a Layer-7 timeline of ~35 ranked events. Locked as canonical.
```

---

## 17. Open Questions / Deferred

- **Functional-form tuning.** `G`, `N0`, `α`, the `f_size`/`f_age` shapes, contest `power/home` factors, and severity bands are all **provisional** and need a balance pass once the sim runs against real maps and the authored culture set.
- **Economy/garrison constants (§7.5.1).** The ledger is fully specified and grounded in ACKS rates, but `frontier_mult`, the `target_coverage` policy curve (from `sphere_weights.military` + ruler quality), `MIN_RATE_FRACTION`, and the overextension weights `w1`/`w2` are project-designed and need the same balance pass.
- **Ruler-level → domain-tier table.** The handoff (§7.4, §12) needs the exact ACKS ruler-level/domain-size numbers looked up and cited from `acore_axioms_strongholds_and_domains.xml` / `acore-setting-construction-rules.xml` before implementation. Flagged, not yet retrieved.
- **Religion propagation (§10)** — depends on the deferred religion-system rework (`gdd-culture-catalog.md` §12). The sim currently follows alignment + conquest only and logs schism/conversion stubs.
- **Climate-driven migration (§8)** — off for v1 (static Layer-2 climate); revisit if climate is made dynamic.
- **Successor-count distribution.** `K` for shatter events needs a concrete distribution tied to vassal count + size (provisional).
- **Inter-polity diplomacy.** v1 models only expansion/war/collapse; alliances, marriages, and tribute relationships beyond simple vassalage are deferred (the LLM may narrate flavor diplomacy atop the mechanical log).
- **Setting-generation Layer 4 rewrite** — the actual wiring of this sim into the pipeline (replacing §6.2/§7.1) is a separate edit to `gdd-setting-generation.md`.

## 18. Revision History

- **2026-06-03 (rev 2):** Added §7.5.1 Realm economy and garrison — the concrete, ACKS-grounded ledger behind `f_overextension`: per-realm income (domain_revenue), fixed overhead, garrison need by territory class (civ 2 / border 3 / wild 4 gp/family) with a frontier multiplier, garrison policy driven by culture militarism + ruler quality, automatic tick-to-tick adjustment (expansion spikes need while income lags), and the overextension output. Confirmed it is aggregate gp-value accounting (not unit simulation), O(hexes)/tick, low-millisecond cost (§14). Cited `acore_axioms_strongholds_and_domains.xml` domain_revenue and domain_expenses/garrison. Updated §17 deferred constants.
- **2026-06-03:** Initial draft. Two-layer (substrate + polity) model on the 24-mile hex map; generation tick over ~4,000-year span aligned to setting-gen timeline epochs. Expansion with size-exponent; seeded border contest; whole-culture migration. Size+age+overextension collapse curve with moderate default + player temperament slider; rump/shatter/depopulate outcomes; successor seeding grounded in the ACKS Rebellious bandit/NPC-challenger mechanic; alignment drift bounded by rigidity; depopulation → wilderness + beastmen + ruins. Demihuman golden-age→enclave arc as emergent-but-heavily-weighted (epoch bias + high collapse_proneness + mutual genocide). Religion propagation deferred to the religion rework. Event log with significance selection feeding Layer 7, dungeon provenance, region toponyms, rumors. Present-day ACKS handoff and validation. Player parameters, determinism, integration points, worked example. ACKS constraints cited; ruler-tier table flagged for lookup.
