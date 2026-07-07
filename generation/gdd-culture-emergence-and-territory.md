# GDD: Culture Emergence and Biome/Race Territory Gating

**Authority:** PROJECT-DESIGNED — engineering authority over algorithms, probabilities, and data shapes. The ACKS Constraints in §2 and the civ/clan inheritance rule in §3.4 are fixed by Jedidiah.
**Status:** Draft v0.3 — Part B (biome/race territory gating, §4) and the deforestation transitions (§5) are now fully specified and build-ready following the 2026-06-27 edge-case decisions (Q1, Q5–Q8 resolved). Part A foundational decisions also settled (civ/clan defaults; merge drivers; first-order hybrids; all 55 kits up front). Remaining open items in §9 are the Part A merge-probability shape and downstream cleanup; Part A is not yet a complete build spec.
**Depends on ACKS rules:** `rules/acore_axioms_strongholds_and_domains.xml:26-28` (Civilized / Borderlands / Wilderness domain-type definitions); `:158-160` (population-density maxima per classification — 125 / 250 / 780 families per 6-mile hex); `:166-175` (advancement thresholds — wilderness→borderlands at 2,000 families across 16 hexes; borderlands→civilized at 4,000); `:30` (elven fastnesses and dwarven vaults may only be built in wilderness, or in civilized/borderlands areas of their own race); `:102-104` (starting families per classification); `rules/acore-setting-construction-rules.xml:62` (default ~50 people/sq mi → 5,000 families per 24-mile hex).
**Depends on project GDDs:** [`gdd-setting-generation.md`](gdd-setting-generation.md) (seeding §6, expansion/war §7, infrastructure/deforestation §9); [`gdd-history-simulation.md`](gdd-history-simulation.md) (conquest substrate, demography, classification); [`gdd-naming-conventions.md`](gdd-naming-conventions.md) (the conlang kit system feeding hybrid naming); the culture catalog / `setting-lore` §5.x (culture roster).
**Modifiable by Claude Code:** Yes within constraints. All tuning, probabilities, transition curves, and data shapes are engineering decisions. The §2 ACKS Constraints, the §3.4 civ/clan inheritance rule, and the per-race territory rules in §4 are project-direction and may not be changed without Jedidiah's approval.
**Last updated:** 2026-06-27

---

## 1. Purpose and Scope

This GDD specifies three interlocking changes to the world-history simulation:

1. **A base/hybrid culture model (human only).** Instead of seeding every culture in the catalog, the simulation seeds only the **base cultures**. Hybrid cultures are no longer seeded — they *emerge* at runtime where two cultures meet, either through border friction or through conquest, when those cultures merge rather than displace one another.
2. **Biome + race territory gating.** The ceiling a culture can reach on a given hex (Wilderness / Borderlands / Civilized) is gated by the hex's biome and elevation *and* by the dominant culture's race (human / dwarf / elf). This layers on top of, and never raises above, the ACKS population-density classifications.
3. **Deforestation (and reforestation) as a biome-transition mechanic.** When a population pushes past a forested hex's biome ceiling, the biome itself transforms (dense forest → forest → cleared land), raising the ceiling. Elves invert this (reforestation).

In scope: the seeding change, the emergence/merge model, the civ/clan inheritance rule, the per-race gating tables, the deforestation transitions, and the data/contract changes they require. Out of scope (this draft): the full mechanical + naming authoring of all 55 hybrids (lazy/as-needed; see §3.6), the beastman tier (unchanged — remains wilderness-clamped), and demihuman seeding caps (unchanged unless §9 says otherwise).

The base/hybrid model applies to **human cultures only**. Demihuman (elf, dwarf) and beastman tiers seed as they do today.

---

## 2. ACKS Constraints

These come from the books and may NOT be changed:

- **Three territory classifications only: Civilized, Borderlands, Wilderness** (`rules/acore_axioms_strongholds_and_domains.xml:26-28`). Defined by proximity to a city/large town when newly established; no "Outlands" or other class.
- **Population-density maxima per classification** (`:158-160`): Wilderness ≤ 125 families per 6-mile hex; Borderlands ≤ 250; Civilized ≤ 780. (The sim's 24-mile/domain caps — wilderness 2,000, borderlands 4,000, civilized 12,480 — are these maxima aggregated over 16 six-mile hexes; `:166-175`.)
- **Advancement is population-gated** (`:166-175`): a domain advances Wilderness→Borderlands only when its hexes sit at the wilderness maximum across a full 16-hex domain (2,000 families), and Borderlands→Civilized at the borderlands maximum (4,000 families).
- **Race-restricted strongholds** (`:30`): "Elven fastnesses and dwarven vaults may only be built in wilderness areas, or in civilized/borderlands areas of their own race." This is the RAW anchor for race-gating territory: a demihuman can only hold developed (civ/borderlands) land among its own kind. The §4 gating generalizes this principle to where each race can *reach* each classification.
- **Banker's rounding** everywhere population, probability, or density is rounded (round half to even) — project-wide convention.

---

## 3. Base / Hybrid Culture Model (human only)

### 3.1 Seeding change — bases only

Today `culture_seeder.gd` runs a biome-coverage greedy selection over the full human catalog (`_select_cultures`), seeding a map-size-dependent subset. **New behavior:** the human seed pool is restricted to the **base cultures** (the eleven `BASE_*` rows of the culture rework: Thiodmark, Albawyn, Shinarur, Aryastan, Kemetra, Quirium, Hellaspol, Hinowa, Huaxia, Tollanaz, Manitland). The seeder still chooses *which* and *how many* bases to place per the existing greedy/coverage logic and `human_seed_points` cap, but no hybrid (`HYB_*`) culture is ever seeded.

Demihuman and beastman seeding are unchanged (demihumans first, per-race caps; beastmen residual).

### 3.2 Civilized vs Clanhold assignment per base culture

Each base culture is assigned a **Civilized** or **Clanhold** style. This drives the §3.4 inheritance rule and interacts with the existing clanhold→wilderness clamp. **Assignment — adopted 2026-06-27:**

| Base | Real-world analog | Proposed style |
|---|---|---|
| Thiodmark | Germanic | Clanhold |
| Albawyn | Celtic | Clanhold |
| Shinarur | Mesopotamian | Civilized |
| Aryastan | Persian | Civilized |
| Kemetra | Egyptian | Civilized |
| Quirium | Roman | Civilized |
| Hellaspol | Greek | Civilized |
| Hinowa | Japanese | Civilized |
| Huaxia | Chinese | Civilized |
| Tollanaz | Mesoamerican | Civilized |
| Manitland | Amerindian | Clanhold |

`mechanical.identity.civ_or_clan` already exists on culture records; this is a data assignment plus a settle of the historical "civ vs clan_confederation" inconsistency noted in the old Gundic kit.

### 3.3 Hybrid emergence — triggers and the merge-vs-displace branch

Two existing moments become emergence points. Each adds a probabilistic **merge-vs-displace** branch:

```
TRIGGER A — SHARED BORDER (sustained contact, no conquest)
  Two cultures hold adjacent hexes across a contested frontier.
  ROLL each affected frontier hex (or frontier zone) per tick:
    → DISPLACE: stronger side pushes; loser's culture-weight erodes
                (existing border-contest / assimilation path), OR
    → MERGE:    the contact hexes begin adopting the HYBRID culture
                HYB(A,B); a hybrid culture instance is synthesized and
                its weight grows along the seam.

TRIGGER B — CONQUEST (A annexes B's hexes, or vice versa)
  On held/annexed hexes, the existing assimilation path runs UNLESS a
  merge roll fires, in which case the held hexes convert toward HYB(A,B)
  instead of toward the conqueror.
```

This reuses the existing border-contest, assimilation, and go-native machinery (§6) and inserts the merge branch alongside the displace branch.

**Archetype gating (2026-06-30, naming workstream #3).** Which merges may produce which archetype is constrained so the static kits' fixed conqueror-assumption always holds (full spec in [`gdd-hybrid-conlang-fusion.md`](gdd-hybrid-conlang-fusion.md) §6.4): a **clan × civ** contact produces the Conquest hybrid **only when the CLAN is the winner/aggressor** (clan-over-civ); a **civ conquering a clan DISPLACES** — no merge, the clanhold scatters or is absorbed as subjects, no new people forms. **civ × civ** (Peer) and **clan × clan** (Confederated) merges are **symmetric** — either winner yields the same kit, so no gating. The conqueror is the clan parent (derived from `civ_or_clan`), so no new kit field is needed. This keeps the Conquest hybrid's people-name (the conqueror's people-ending) and its two-register deity usage (temples/nobles = conqueror, shrines/commoners = conquered) well-defined at runtime. Phase 4c's merge-vs-displace roll enforces this gate.

**Merge-probability drivers — decided 2026-06-27.** The chance a contact resolves as *merge* rather than *displace* is a function of:

- **Relative strength / size** — near-parity favors merge; a lopsided border favors displacement (the strong absorb the weak).
- **Alignment compatibility** — same/adjacent alignment favors merge; opposed alignments favor displacement.
- **Shared language family** — same conlang family (e.g. two Germanic-derived cultures) favors merge; distant families favor displacement.
- **A randomization term** — a stochastic factor so identical border conditions don't always resolve the same way.

Civ/clan compatibility was explicitly *excluded* as a driver (it governs the *outcome's* style via §3.4, not the merge/displace odds). The exact functional form and weights of these four inputs remain an engineering/tuning task — see §9, Q3.

### 3.4 Civ/Clan inheritance rule (FIXED)

When a hybrid HYB(A,B) is synthesized, its style is determined by its parents:

- **Clanhold + Clanhold → Clanhold hybrid.**
- **Any Civilized parent → Civilized hybrid** (Civ + Civ → Civ; Civ + Clan → Civ).

This is a fixed rule from Jedidiah. Consequence: Civilized "dominates" in hybridization. Worked example — **Brythald** (HYB_01 = Thiodmark[Germanic] × Albawyn[Celtic]): under the §3.2 adopted assignment both parents are Clanhold, so Brythald is **Clanhold** (decided 2026-06-27) — a Germanic clan-kingship over a Brittonic substrate, not a centralized feudal state. Its conlang kit's `government`/`civ_or_clan` are set accordingly.

### 3.5 Hybrid catalog — the 55 pairings

The culture rework defines a hybrid for **every pair of bases** (11 choose 2 = 55, `HYB_01`–`HYB_55`), each with a name, parent logic, and phonetic/grammar profile. When a merge fires between two bases, the engine looks up the hybrid by unordered parent pair. **Decided 2026-06-27: first-order only.** Only base × base produces a hybrid (the 55 in the CSV). A hybrid in contact with a third culture displaces or is displaced — it never forms a second-order hybrid. This keeps the hybrid space closed at exactly the 55 defined pairings.

### 3.6 Hybrid culture data shape

A hybrid is not in the seed pool but must exist as a culture instance once it emerges. **RESOLVED 2026-06-29 (Jedidiah) — STATIC authored hybrid kits, not runtime synthesis.** Every hybrid is a static `data/cultures/<id>.json` mechanical kit carrying `identity.culture_class = "hybrid"` (a third class beside `base`/`member`; the seeder's `bases_only` filter already excludes anything `!= "base"`, so hybrids never seed — they exist in the catalog only to be looked up when a merge emerges them) and `identity.culture_synthesis_parents = [base_a_id, base_b_id]`. The parent-pair → hybrid lookup is built at load time by scanning hybrid kits' `culture_synthesis_parents` (no separate definition-table file needed). The 9 hybrids the old system authored in full (HYB_16/19/21/22/35/43/49/50/55) are reused as-is (adjusted: `culture_class="hybrid"`, all-three alignment per §3.7, `culture_synthesis_parents` added); the other 46 are produced once by a build-time **ARCHETYPE generator** (`tools/generate_hybrid_kits.py`, Phase 4b) — NOT a mechanical average (averaging clusters hybrids toward a bland centroid; Jedidiah 2026-06-29). Each pair's archetype comes from the parents' civ/clan (§3.2): **Conquest Aristocracy** (clan×civ), **Peer Synthesis** (civ×civ, sub-flavored Hegemonic/Mercantile/Theocratic/Scholastic/Classical by the combined SECONDARY sphere — military is universally dominant), **Confederated Peoples** (clan×clan). Traits are SOURCED per-trait by cultural role + a directional "character push," with UNION on the repertoire (troops, NPC biases) and a lean-weighted sphere blend tilted by archetype; `civ_or_clan` by §3.4, alignment all-three. Validated against the 9 authored hybrids (8/9 within ~0.12 mean-abs-delta; the recipe reproduces authored `tamkari` (né sargonid) to 0.05). Output is committed + hand-tunable; flavor is templated (refine narratively). **This eliminates the "hybrid as a new runtime data shape" architectural risk** (see §9): a hybrid is an ordinary static catalog entry, identical in handling to a base except for the seed-exclusion flag.

Naming/conlang kits are authored **up front for all 55 hybrids** (decided 2026-06-27). The family theonym/morphology system supports this (each family base holds the morph-set its blends reflex from). **Brythald** (`data/conlang/culture_brythald.json`) is authored and replaces Gundic; the remaining **54** are a committed authoring project — to be produced as `data/conlang/culture_<id>.json` per the rework CSV's parent pairs and linguistic profiles, reflexing each parent family's theonym set. This is sizeable; recommend batching by parent family (e.g. all Germanic-× blends, then Celtic-×, etc.) as a follow-on work stream.

---

### 3.7 Culture-wide conventions (decided 2026-06-27)

These apply to every human culture (bases and hybrids):

- **Alignment — all three.** Every human culture allows Lawful, Neutral, and Chaotic. There is no per-culture alignment restriction; a culture's actual alignment is resolved at seed/runtime, and religion follows the standard alignment lens (Lawful venerates the Lawful powers and names the Chaotic as demons; Chaotic the reverse; Neutral honors ancestral and local powers, invoking the great powers situationally). This supersedes the earlier "provisional alignment" notes in the hybrid kits.
- **Titles displayed in English.** Ruler and domain titles shown in setting-generation output, domain lists, and the vassal tree/leaf displays are English (Baron/Barony, Marquis/March, Count/County, Duke/Duchy, Prince/Principality, King/Kingdom, Emperor/Empire). Each kit retains its conlang title as `ruler_native`/`domain_native`, used **only in NPC dialogue**, never in structural/UI displays (native titles across dozens of cultures would be too confusing in lists and trees).
- **Approved foreign-term exceptions.** A commonly-known foreign rulership/domain term may be used as the *display* title where iconic for that culture and tier, drawn from this approved list (none are mandatory): Marquis, Konig, Konigsreich, Reich, Doge, Pharaoh, Shah, Emir, Shogun, Daimyo, Archon, Tsar, Czar, Jarl, Imperator. Applied in the Germanic batch: Imperator (Quirgard, empire), Shah (Aryamark, kingdom), Pharaoh (Kemetric, kingdom), Shogun + Daimyo (Hinogard, kingdom + duchy), Archon (Hellmark, county), Jarl (the Norse-ruled duchies). Per-kit, the foreign terms used are listed in `title_ladder.approved_foreign_terms_used`. **Format conventions (set 2026-06-28 after a consistency pass):** that field is a list of strings `"<Term> (<tier>)"`, derived from the actual non-English tier rulers in ascending tier order (omit the field entirely if a kit has no foreign terms). The female DISPLAY form (`title_ladder.female_forms_display`, keyed by the display ruler) uses the well-known foreign feminine where one exists — Shah→Shahbanu, Imperator→Imperatrix, Archon→Archontissa — and the English tier-feminine otherwise (Shogun & Pharaoh → Queen; Daimyo & Jarl → Duchess; etc.). The conlang female forms live in `female_forms_native` for NPC dialogue.
- **Deities unchanged.** Each culture retains the canonical Agrippan pantheon from the setting lore, with deity names generated by the same per-family conlang morph method used in the first culture system — now cleaner because the defined base types give clear morphology lines (each hybrid reflexes its two parent families' canon-morphs).

Doc-sync note: the title-display and alignment rules are culture-wide and should also be reflected in `gdd-naming-conventions.md` and the setting-lore alignment section (follow-on).

---

## 4. Biome + Race Territory Gating

The classification a hex can reach is the **minimum** of (a) the ACKS population-gated classification it would otherwise earn, (b) an elevation ceiling, and (c) a biome cap — all read through the dominant culture's **race**. Gating never *raises* a classification above what population supports; it only caps it.

### 4.1 Engine biome/terrain vocabulary (mapping)

The design language ("dense forest", "taiga", "savanna"…) maps to the engine schema as follows (from `setting_hexes`):

| Design term | `biome` | `biome_subtype` | `elevation` |
|---|---|---|---|
| grassland / savanna / steppe | `clear` | `clear_grassland` / `clear_savanna` / `clear_steppe` | flat/hills |
| scrub | `clear` | `clear_scrub` | flat/hills |
| tundra | `clear` | `clear_tundra` | any |
| forest | `woods` | (none / plain) | any |
| taiga | `woods` | `forest_taiga` | any |
| dense forest | `woods` | `forest_dense` | any |
| jungle | `jungle` | — | any |
| swamp/marsh | `swamp` | — | any |
| desert | `desert` | `desert_badlands` (or none) | any |
| (mountains) | any | `mountains_volcanic` / `mountains_glacial` for those | `mountains` |

Note `forest`, `taiga`, and `dense forest` are all `biome = woods` distinguished by subtype — gating must key on **subtype**, not just biome. Likewise `tundra` is `clear` but must be capped separately from grassland.

### 4.2 Human gating

Effective cap = **min(elevation ceiling, biome cap, special-case cap)**.

**Elevation ceiling (humans):**

| Elevation | Ceiling |
|---|---|
| flat, hills | Civilized (no ceiling) |
| mountains | Borderlands |
| mountains_volcanic | Wilderness (may settle, never exceed) |
| mountains_glacial | **Not settled by humans** — hard exclusion (§4.6) |

**Biome cap (humans), with deforestation transitions:**

| Biome/subtype | Cap | On exceeding the cap |
|---|---|---|
| clear: grassland / savanna / steppe | Civilized | — |
| clear: tundra | Borderlands | hard cap |
| clear: scrub | Borderlands | hard cap |
| woods: forest | Borderlands | at Civ-pressure → **deforest to clear** (climate subtype, §5.3); reaches Civilized if cleared to grassland/savanna/steppe, but a **warm-arid forest clears to scrub and stays Borderlands** |
| woods: taiga | Borderlands | at Civ-pressure → **deforest to clear_steppe** → Civilized |
| woods: dense forest | Wilderness | at Borderlands-pressure → **deforest to forest** → Borderlands → (then per the forest row) |
| jungle | Wilderness | deforestable (30 ticks → clear, §5.4) then clear caps; reforests to jungle in 15 ticks |
| swamp | Wilderness | hard cap — hostile wetland; no drainage mechanic in v1 (could later mirror deforestation) |
| desert | Wilderness | UNLESS coastal or river-fronting → **Civilized** (the Nile/Mesopotamia cradle case) |

The "on exceeding the cap" column is the crux of the deforestation mechanic (§5.2): the cap is a **transition trigger** for transformable biomes and a **hard stop** otherwise.

### 4.3 Dwarf gating

Biome is irrelevant (dwarves live underground). Elevation only:

| Elevation | Cap |
|---|---|
| mountains (incl. volcanic / glacial) | Civilized |
| hills | Borderlands |
| flat | Wilderness |

This race-specifically overrides the human volcanic/glacial → Wilderness ceiling (dwarves reach Civilized in any mountain). Confirmed 2026-06-27.

### 4.4 Elf gating

| Terrain | Cap |
|---|---|
| forest / dense forest / taiga (`woods`, any subtype) | Civilized |
| jungle | Civilized |
| everywhere else (clear, desert, swamp, hills, flat) | Borderlands |
| non-forest / non-jungle mountains | Wilderness |

Forested or jungle mountains follow the forest rule (Civilized), since the wilderness cap is specified only for *non*-forest/jungle mountains. Elves **reforest** rather than deforest: an elf-held `clear` hex may convert to `woods` (existing inverse logic, §5), which then raises its elf cap from Borderlands to Civilized. Confirmed 2026-06-27.

### 4.5 Integration with the classification engine

The gating is a ceiling applied in `HistorySimulator._advance_classification()` (sim) and `classification_advancement.gd` (runtime). The existing clanhold→Wilderness clamp is a precedent for a hard ceiling. Proposed: compute an `effective_territory_cap(hex, dominant_race, civ_or_clan)` helper that returns the min-ceiling, and gate advancement against it. Clanhold cultures keep their existing Wilderness clamp; race/biome gating applies to civilized cultures and to demihumans.

### 4.6 Expansion preference & hard exclusions per race (decided 2026-06-28)

Gating (§4.2–4.4) sets the *ceiling* a race can reach on a hex; this sets the *order* a polity prefers to expand into terrain, and the terrain it will never take. Score a candidate frontier hex by **biome rank first, then elevation** — biome dominates, so a mountain-forest is preferred over a flat-desert ("easier to farm goats in a mountain forest than a desert"). This feeds the expansion-preference weighting (handoff §5.1); it is a *peaceful-expansion* preference — **war-making ignores it.**

- **Humans** — biome order best→worst: clear (grassland/savanna/steppe) → Forest/taiga → Jungle/swamp → desert; elevation flat > hills > mountains (secondary to biome). **Hard exclusion: never settle glacial mountains.** (Tundra/scrub rank just above desert — build-agent discretion.)
- **Elves** — biome order: Forest / Dense Forest / Jungle / taiga → clear; elevation irrelevant. **Hard exclusions: never swamp, desert, or glacial mountains** (cannot be forested).
- **Dwarves** — order: mountains → volcanic mountains → glacial mountains → hills (flat last); biome irrelevant. No hard exclusion.
- **Beastmen** — no preference, no exclusion: settle anywhere.

---

## 5. Deforestation and Reforestation

### 5.1 Reuse of the existing mechanic

`infrastructure_generator.gd §9.4 _deforest()` already flips `woods/jungle → clear` near non-elven settlements and `clear → woods` near elven settlements, storing `original_biome` for reversal. It runs **once at generation (Layer 6)** and flips wholesale. The new model **reuses this biome-flip + original_biome machinery** but (a) makes it **graduated** (dense→forest→clear, not woods→clear in one step) and (b) **retriggers it from territory-cap pressure** during the sim (and optionally at runtime), rather than only once at generation.

### 5.2 Graduated biome-transition model

Transitions fire when population pressure would push a hex past its current biome cap (§4.2):

```
dense forest (woods/forest_dense)  --[Borderlands pressure]-->  forest (woods)
forest (woods)                     --[Civilized pressure]----->  clear (climate band)
taiga (woods/forest_taiga)         --[Civilized pressure]----->  clear (cold band)
jungle                             --[develop pressure, 30 ticks]-->  clear (warm band, §5.3)
```

Each transition raises the hex's biome cap to the cap of the *resulting* biome, so the population that triggered the transition is then supported up to that new cap. This resolves the apparent contradiction in the spec ("forest may only reach borderlands" vs "if humans reach civilized levels in forest it deforests"): the forest cap is *borderlands until deforestation*, at which point the now-cleared hex carries the cap of the clear subtype it became.

**Terminal-at-Borderlands case.** The cleared subtype's own cap governs the result. Grassland, savanna, and steppe are Civilized-capped, so clearing temperate/warm-humid forest and taiga unlocks Civilized. But a **warm-arid forest clears to scrub**, which is Borderlands-capped (§4.2) — so that hex clears but never reaches Civilized; it is terminal at Borderlands. (Thematically: arid land cannot become a dense civilization without a river — the same logic as the desert exception.) Tundra is likewise Borderlands-capped, which is why taiga clears to steppe, not tundra.

### 5.3 Climate-band → cleared-biome mapping (decided 2026-06-27)

When forest/taiga deforests, the resulting `clear` subtype is chosen by the hex's climate band (Köppen-derived; already available from the geo/region painters):

| Deforested from | Climate band | → clear subtype | Resulting cap |
|---|---|---|---|
| forest | temperate | clear_grassland | Civilized |
| forest | warm / humid | clear_savanna | Civilized |
| forest | warm / arid | clear_scrub | Borderlands (terminal) |
| taiga | cold | clear_steppe | Civilized |
| jungle | warm / tropical | clear_savanna | Civilized |

Two consistency rules drive this table: (1) a cleared target must be the climate-appropriate clear subtype, and (2) the resulting cap is the *target subtype's* cap, not automatically Civilized. Taiga clears to **steppe, never tundra**, and warm-arid forest clears to **scrub** and stays Borderlands — both because tundra/scrub are Borderlands-capped (§4.2, §5.2).

### 5.4 Clearing & reforestation rates (decided 2026-06-28)

**Terminology.** "Dense Forest" = `woods` + `forest_dense`. **"Forest" = every other woodland subtype** (plain `woods`, `forest_taiga`, etc.) — all woodland *except* Dense Forest and Jungle. "Jungle" (`biome=jungle`) is deforestable but slow. "Clear" = the cleared end-state (climate subtype per §5.3).

Each forest/jungle-origin hex carries a `clearing_progress` counter (ticks toward the next transition; preserve `original_biome`). Transitions are stepwise and timed.

**Deforestation (human-driven)** — accrues while the hex is held by a human polity developing it past its current biome cap. Base **+1/tick**; **+2/tick** if adjacent to a settlement of **market class III or larger** (the bigger markets — classes I–III):
- **Dense Forest → Forest:** 20 ticks (then reset).
- **Forest (any non-dense woodland) → Clear:** 20 ticks.
- **Jungle → Clear:** 30 ticks (slower; clears to the warm-band subtype per §5.3).
- So Dense → Forest → Clear = 40 base ticks; Forest → Clear = 20; Jungle → Clear = 30 (each halved next to a class I–III settlement).

**Natural reforestation** — accrues while the hex has **no human population** (left or died), at **+1/tick**:
- Reverses an in-progress step's `clearing_progress` (un-clearing toward the fuller state).
- **Ceiling Forest, never Dense:** a hex reduced from Dense to Forest does not re-thicken to Dense naturally (caps at Forest); a partial Forest→Clear can fully recover to Forest.
- A fully **Clear** (was-forest) hex regrows **only if adjacent to a Forest hex**, Clear → Forest over 20 ticks (caps at Forest); isolated clear hexes stay clear.
- **Jungle:** a cleared was-jungle hex regrows **Clear → Jungle in 15 ticks** (faster than it cleared), provided it is **adjacent to a Jungle hex**.

**Elven reforestation** — when an elven polity works the hex, at **2× natural (+2/tick)**, **3× (+3/tick)** adjacent to any elven settlement:
- Elves may reforest **any hex in their settled territory, even a Clear hex with no forest/jungle neighbor** (no seed-source requirement).
- Ceiling: elves restore toward the hex's `original_biome`, **including back to Dense Forest and Jungle** (confirmed 2026-06-28 — the natural Forest-cap is a *natural*-only limit; elves are forest-masters).

Reuse `infrastructure_generator._deforest`'s biome-flip + `original_biome`, driven over time by the runtime `_phase_deforestation` (§5.1). Constants → `sim_constants`: `CLEAR_TICKS_STEP=20`, `CLEAR_TICKS_JUNGLE=30`, `REFOREST_TICKS_JUNGLE=15`, `CLEAR_RATE_NEAR_MARKET3=2`, `REFOREST_RATE_NATURAL=1`, `REFOREST_RATE_ELF=2`, `REFOREST_RATE_ELF_ADJ=3`.

---

## 6. Reuse Map — existing hooks → new logic

| New mechanic | Existing system to reuse | Hook |
|---|---|---|
| Base-only seeding | `culture_seeder.gd::_select_cultures` | Restrict human pool to `tier=human, base only`; keep greedy coverage + caps |
| Civ/clan style | `mechanical.identity.civ_or_clan` (exists) | Data assignment on 11 bases (§3.2) |
| Merge-vs-displace at border | `_phase_expansion` / `_resolve_contest` | Add merge roll alongside the displace outcome |
| Merge-vs-displace on conquest | `_assimilate_held_hexes`, `_phase_go_native` | Add merge branch; convert held hexes toward hybrid instead of conqueror |
| Hybrid synthesis | culture-instance creation + `synthesis_sources` | New `_phase_hybridization`; `culture_synthesis_parents` field |
| Territory gating | `_advance_classification`, `classification_advancement.gd`, clanhold→wilderness clamp | New `effective_territory_cap()` ceiling helper |
| Deforestation transitions | `infrastructure_generator.gd::_deforest`, `original_biome` | Generalize to graduated + runtime; new `_phase_deforestation` or fold into classification advancement |
| Cleared-biome climate match | region/geo painters (Köppen band) | Read band when choosing `clear` subtype |

The directive is to reuse these systems where possible but not be bound by them — notably, the merge model is genuinely new (no existing culture→third-culture path) and the hybrid instance is a new data shape (culture instances are currently per-realm, sourced from static catalog JSON).

---

## 7. Data model changes

- **Hybrid definition table** — built from the rework CSV: unordered parent-pair → `{hybrid_id, name, phonetic_profile, grammar_profile}`. Location TBD (`data/cultures/hybrids.json` or per-file). Mechanical traits blended from parents at synthesis time.
- **`culture_synthesis_parents`** on the culture instance / `setting_polities` — the two base `culture_id`s a hybrid descends from (generalizes `synthesis_sources`).
- **`civ_or_clan`** populated for all 11 base records (§3.2).
- **Seed-biome rewrite** for the base cultures — the gating in §4 will require revised `seed_biomes` for most bases so they seed and expand into terrain they can actually develop (data sweep; not in this GDD's logic but a required follow-on).
- **River / coastal adjacency** — needed for the desert exception (§4.2). Confirmed available: rivers are first-class edge entities (`setting_river_edges` at sim time, `hex_river_edges` at runtime; per `gdd-terrain-system.md §3.6`), so "fronts a river" = the hex is incident to a river edge. Coastal adjacency is derivable from `water = ocean`. No new field required; only the raised cap value is open (§9, Q8).
- **Deforestation persistence** — reuse `setting_hexes.biome` + `original_biome`; runtime transitions write here and log a `cultural_shift`-style event (or a new `biome_shift` event).

---

## 8. Implementation phasing (for Claude Code)

Ordered so each phase is independently testable against the mock provider and hand-authored content. **Full build sequencing, reuse map, contracts, and tests are in [`../docs/handoff_culture_emergence_build.md`](../docs/handoff_culture_emergence_build.md)** — that handoff also specifies the Phase-3 expansion-constraint mechanics (added 2026-06-28; to be merged into this GDD).

1. **Base-only seeding + civ/clan + stricter seed biomes.** Restrict the human seed pool to the 11 bases; assign `civ_or_clan` (§3.2); rewrite base seed-biomes so humans/elves seed only where they can develop (§4); reconcile/retire the old clean-member + Gundic kits. Lowest risk.
2. **Territory gating + graduated deforestation with time-cost.** `effective_territory_cap()` gates classification (sim + runtime); graduated transitions (§5.2–5.3); **deforestation is a timed cost** (per-hex clearing progress; dense forest slower than forest) driven by a runtime `_phase_deforestation`; reversibility.
3. **Expansion constraints & preferences (NEW — see handoff §5).** Cap-aware unfavorable-terrain avoidance; natural-borders preference (halt/slow at major rivers, mountain spines, coast; consolidate interior population before crossing); overseas expansion across short sea gaps (non-contiguous colonies — coordinate with §7.4d).
4. **Hybrid emergence.** New `_phase_hybridization`; hybrid definition table; merge-vs-displace roll at border + conquest; hybrid trait blending + `culture_synthesis_parents`. Highest architectural risk — Opus review.
5. **DEFERRED — clanhold migration (Völkerwanderung).** Build only after 1–4 are stable: clanholds migrate on local population saturation, triggering emergence at the destination. Design sketch in handoff §7; full GDD spec to follow.

---

## 9. Open Questions / Architectural Concerns

- **Q1 — Climate→cleared-biome mapping. RESOLVED 2026-06-27:** by band — temperate→grassland, warm-humid→savanna, warm-arid→scrub, taiga(cold)→steppe (§5.3). Resulting cap = the target subtype's cap, so warm-arid→scrub is terminal at Borderlands and taiga→steppe (not tundra) unlocks Civilized.
- **Q2 — Civ/clan assignment of the 11 bases. RESOLVED 2026-06-27:** §3.2 defaults adopted — Thiodmark (Germanic), Albawyn (Celtic), Manitland (Amerindian) = Clanhold; the other eight = Civilized. Brythald is therefore Clanhold.
- **Q3 — What governs merge vs. displace? DRIVERS DECIDED 2026-06-27:** relative strength/size, alignment compatibility, shared language family, and a randomization term (civ/clan compatibility *excluded*). **Still open (engineering):** the exact probability shape/weights, and whether merge is symmetric or one side can "win" the merge (asymmetric blend).
- **Q4 — Second-order hybrids? RESOLVED 2026-06-27:** first-order only for v1. Hybrids do not further combine; the hybrid space is closed at the 55 defined base×base pairings.
- **Q5 — Demihuman cap edge cases. RESOLVED 2026-06-27:** dwarves reach Civilized in every mountain incl. volcanic/glacial (biome irrelevant, overriding the human ceiling); elves reach Civilized in forested/jungle mountains (other mountains→Wilderness); elf reforestation (clear→woods) raises the elf cap, mirroring human deforestation.
- **Q6 — `clear_scrub` cap (humans). RESOLVED 2026-06-27:** Borderlands (hard cap).
- **Q7 — Swamp cap. RESOLVED 2026-06-27:** humans → Wilderness (hard, like jungle); elves → Borderlands ("everywhere else"); dwarves → by elevation (flat swamp → Wilderness). A future drainage mechanic could raise the human cap.
- **Q8 — Desert exception cap. RESOLVED 2026-06-27:** coastal or river-fronting desert → Civilized (the cradle case); "fronts a river" = the hex is incident to a `setting_river_edges`/`hex_river_edges` edge.
- **Q9 — Hybrid naming-kit scope. RESOLVED 2026-06-27:** author all 55 conlang kits up front. Brythald is done; the other 54 are a committed authoring project (recommend batching by parent family). This is the largest remaining content task.
- **Q10 — Deforestation reversibility. RESOLVED 2026-06-28 (see §5.4):** natural reforestation auto-runs on depopulation at +1/tick (ceiling Forest, never Dense; cleared hexes need a Forest neighbor; jungle regrows Clear→Jungle in 15 ticks with a Jungle neighbor); elven reforestation at 2×/3×, may restore any settled hex with no neighbor required, **including back to Dense Forest and Jungle (confirmed).**
- **Q11 — Gundic retirement.** `data/cultures/gundic.json` and `data/name_banks/gundic.json` still reference the retired Gundic culture (now Brythald). Per your instruction these were left untouched; Claude Code will need a migration/retirement pass so the two don't coexist. Flagging, not acting.
- **Q12 — Seeding determinism.** Base-only seeding with a much smaller pool (11 vs 65) changes map variety; with hybrids emerging dynamically, early-game maps will look more homogeneous and diverge over sim-time. Is that the intended feel, or should initial base diversity be boosted (more seed points)?
- **Concern — Hybrid as a new data shape. RESOLVED 2026-06-29 (Opus review + Jedidiah).** Avoided entirely: hybrids are STATIC authored `data/cultures/<id>.json` kits (`culture_class="hybrid"`, `culture_synthesis_parents` set), generated once at build time and loaded exactly like base kits — NOT synthesized at runtime. There is no sim-time mutation of the culture-instance set; emergence just looks a hybrid up by parent pair. The 9 old-system hybrid kits were recovered (they had been over-deleted by the member retirement) and the other 46 are produced by a build-time generator (§3.6).
- **Concern — `woods` subtype granularity.** Gating and deforestation both depend on distinguishing plain forest, taiga, and dense forest. Confirm the painters reliably set `forest_taiga` / `forest_dense` (and a clear "plain forest" state) so the transitions have well-defined source states.
