# Build Handoff — Culture Emergence, Territory Gating, Expansion & Deforestation

**Audience:** Claude Code (build agent).
**Authority:** Implementation plan. Design lives in [`generation/gdd-culture-emergence-and-territory.md`](../generation/gdd-culture-emergence-and-territory.md); the conlang method in [`generation/gdd-hybrid-conlang-fusion.md`](../generation/gdd-hybrid-conlang-fusion.md). **This doc additionally specifies the expansion-constraint mechanics added 2026-06-28** (§5) — fold them back into the GDD when convenient.
**Status:** Draft v1 — phase order + new-mechanic specs. Tuning constants are PROVISIONAL (engineering decisions); the per-race territory rules, civ/clan inheritance, and ACKS constraints are fixed (see GDD §2, §3.4, §4).
**Last updated:** 2026-06-28

---

## 0. Before you start — build-session protocol

Per `CLAUDE.md`: read this file, then `acks-build-log` (`--last 1`, `--next-actions 3`, `--needs-review`, and `--for-task` for the phase you pick up); read `docs/acks_arbiter_design_brief_v11.md` and the two GDDs above; run `acks-conventions --for-task "<phase>"` before writing GDScript; use `acks-raw-lookup` for any ACKS rule (never read the rules corpus directly). Append a build-log entry at session end; update `docs/coding_conventions.md` if new patterns emerge. **Banker's rounding everywhere.** Godot 4 / GDScript / SQLite only. EventScheduler-first: new sim phases are scheduled events, not a state machine.

The systems map below is point-in-time (from a 2026-06-27 read); **verify function/column names against current code before hooking in.**

---

## 1. Current data state (what's already done)

- **Conlang naming kits — COMPLETE** in `data/conlang/`: 11 base kits (`culture_<base>.json`, `csv_id` BASE_01–11) + 55 hybrid kits (HYB_01–55). Bases are single-language (no `blend`, no `phonology.fusion_rules`); hybrids are deep-fused with `phonology.fusion_rules`. All carry the new title/alignment conventions (English display `ruler`/`domain` + `ruler_native`/`domain_native`, `alignment_allowed` = Lawful/Neutral/Chaotic, `worship_by_alignment` all three, `approved_foreign_terms_used`, `female_forms_display`/`female_forms_native`).
- **Critical distinction:** `data/conlang/*.json` are NAMING kits. `data/cultures/*.json` are the MECHANICAL+flavor kits the seeder actually loads (`mechanical.terrain.seed_biomes`, `civ_or_clan`, expansion scalars, etc.). The mechanical kits still reflect the old roster and need the Phase 1 sweep.
- **Old clean-member kits** (alani, cuchulan, hammuran, axsatran, abydosian, agrippan, achillean, yamataian, jinxian, tlanec, numinan, …) and the retired **Gundic** kit are still on disk — now redundant with the bases. Reconcile/retire in Phase 1.
- The GDD's foundational decisions are settled (base civ/clan defaults §3.2; merge drivers §3.3; first-order hybrids §3.5; biome/race gating §4 with all edge cases resolved; deforestation transitions §5).

---

## 2. Reuse map (GDD design → existing code hook)

| Mechanic | Hook (verify names) | Notes |
|---|---|---|
| Culture seeding | `engine/.../world/culture_seeder.gd` (`_select_cultures`, `_hex_matches_culture`, `_hex_matches_term`, `_place_homelands`) | biome-coverage greedy; `seed_biomes` + `coastal_start` |
| Expansion / border contest | `world/history_simulator.gd` (`_phase_expansion`, `_resolve_contest`); `sim_constants.gd` | terrain mult 1.5 seed / 1.15 affinity / 0.5 avoided / 1.0 neutral |
| Classification advance | `history_simulator._advance_classification`, `_demote_to_clanhold`; runtime `domains/classification_advancement.gd` | caps wilderness 2 000 / borderlands 4 000 / civilized 12 480 families per domain (RAW `acore_axioms_strongholds_and_domains.xml:158-175`) |
| Deforestation | `world/infrastructure_generator.gd` §9.4 `_deforest` (+ `setting_hexes.original_biome`) | currently ONE-SHOT at Layer 6; flips `woods/jungle↔clear` wholesale |
| Rivers | `setting_river_edges` (sim) / `hex_river_edges` (runtime); `width_category` ∈ stream/creek/river/major_river | first-class edge entities |
| Biome / terrain | `setting_hexes.biome` (clear/woods/jungle/swamp/desert), `biome_subtype` (forest_dense/forest_taiga/mountains_volcanic/mountains_glacial/clear_*), `elevation` (flat/hills/mountains), `water` ('' /ocean/lake) | |
| Race | culture record `mechanical.identity.race` (NOT per-hex); region race derived from dominant culture | |
| Assimilation / go-native / contiguity | `_assimilate_held_hexes`, `_phase_go_native`, §7.4d severed-realm split | merge branch hooks here (Phase 4) |

---

## 3. Phase 1 — Base-only seeding, civ/clan, stricter seed biomes, kit reconciliation

**Goal:** the sim seeds only the 11 human bases, with terrain-correct seed biomes, and the kit data is reconciled to the new roster.

1. **Restrict the human seed pool** to the 11 bases (BASE_01–11) in `_select_cultures`. Demihuman (elf/dwarf) and beastman seeding unchanged. No `HYB_*` is ever seeded.
2. **Assign `civ_or_clan`** on the 11 base mechanical records (GDD §3.2): **clan** = Thiodmark (Germanic), Albawyn (Celtic), Manitland (Amerindian); **civ** = the other eight.
3. **Stricter seed biomes (humans/elves)** — derive each base's `seed_biomes` from the §4 race/biome cap table; seed only where the race can reach a developable classification:
   - **Humans** seed in `clear` grassland/savanna/steppe on flat/hills (Civ-capable) and `woods` plain forest / taiga (Borderlands). They must NOT seed in dense forest, jungle, desert, tundra, swamp, or glacial/volcanic mountains (Wilderness-capped), nor rely on mountains (Borderlands cap) as a primary seed.
   - **Elves** seed in forest / dense forest / taiga / jungle (Civ-capable); not non-forest as a primary seed.
   - **Dwarves** seed in mountains (Civ). (Unchanged in spirit; confirm against §4.3.)
   - Update `mechanical.terrain.seed_biomes` on each base record accordingly, and tighten `_hex_matches_term` so the loose `woods`→{forest,dense,taiga} collapse respects subtype.
4. **Kit reconciliation:** the new base naming-kits (`culture_<base>.json`) supersede the old clean-member naming-kits and Gundic. Decide the canonical naming-kit per culture, retire/redirect the redundant ones, and point the name-bank build step (`gdd-naming-conventions.md §13`) at the new kits. (The old kits were intentionally kept during authoring; this is the cleanup.)

**Files:** `culture_seeder.gd`; `data/cultures/*.json` (seed_biomes, civ_or_clan); name-bank build. **Tests:** only bases seed; humans never seed dense-forest/jungle/desert; elves favor forest; civ/clan correct. Low risk.

---

## 4. Phase 2 — Territory gating + graduated deforestation (with time-cost)

**Goal:** the §4 caps govern how far each hex can develop, and forest becomes farmland only by *clearing over time*.

1. **`effective_territory_cap(hex, dominant_race, civ_or_clan)`** = min(elevation ceiling, biome cap, special-case) per GDD §4.2–4.4. Gate `_advance_classification` (sim) and `classification_advancement.gd` (runtime) against it. Keep the existing clanhold→Wilderness clamp as a precedent.
2. **Graduated biome transitions** (GDD §5.2–5.3): dense forest→forest→clear (climate subtype: temperate→grassland, warm-humid→savanna, warm-arid→scrub [terminal at Borderlands], taiga→steppe); jungle/swamp hard-capped. Reuse `_deforest`'s biome-flip + `original_biome`.
3. **Deforestation as a timed cost (concrete — GDD §5.4):** per-hex `clearing_progress` counter; the transition is NOT instant. Terminology: "Forest" = all woodland except `forest_dense` and `jungle`. Human-driven clearing while a human polity develops the hex past its biome cap: **+1/tick, +2/tick adjacent to a market class III-or-larger settlement (classes I–III)**. **Dense Forest → Forest = 20 ticks; Forest → Clear = 20 ticks; Jungle → Clear = 30 ticks** (Dense→Clear = 40 base ticks; each halved near a big market). Drive via a runtime `_phase_deforestation` scheduled event (keep the Layer-6 `_deforest` for the *initial* map; add the runtime phase for ongoing clearing). Constants: `CLEAR_TICKS_STEP=20`, `CLEAR_TICKS_JUNGLE=30`, `CLEAR_RATE_NEAR_MARKET3=2`.
4. **Reforestation (concrete — GDD §5.4):** **Natural** (hex has no human population): reverse `clearing_progress` at **+1/tick**, ceiling **Forest never Dense**; a fully **Clear** (was-forest) hex regrows only if **adjacent to a Forest hex**; a cleared **was-jungle** hex regrows **Clear → Jungle in 15 ticks** with a Jungle neighbor. **Elven** (elven polity working the hex): **+2/tick, +3/tick adjacent to an elven settlement**; elves may reforest **any settled hex even with no neighbor**, and restore toward `original_biome` **including Dense Forest and Jungle (confirmed 2026-06-28)**. Constants: `REFOREST_RATE_NATURAL=1`, `REFOREST_RATE_ELF=2`, `REFOREST_RATE_ELF_ADJ=3`, `REFOREST_TICKS_JUNGLE=15`.

**Files:** new `effective_territory_cap` helper; `_advance_classification` + `classification_advancement.gd`; generalize `infrastructure_generator._deforest` + new `_phase_deforestation`; `sim_constants`; `setting_hexes` (clearing-progress column or a side table). **Tests:** caps enforced per race×biome; forest reaches Civ only after ~N clearing ticks; dense forest slower; jungle clears in 30 ticks; humans never settle glacial mountains; reforestation on collapse.

---

## 5. Phase 3 — Expansion constraints & preferences (NEW design, 2026-06-28)

This is the realism/polish layer over expansion. **Fold these specs into the GDD.**

### 5.1 Unfavorable-terrain avoidance
Strengthen the existing terrain weighting into a **cap-aware preference**: when scoring a frontier hex for expansion, multiply by a preference for the classification the culture's race could reach there (`effective_territory_cap`). Hexes where the culture would be Wilderness-capped get a strong negative weight — it expands toward developable land first. **Boxed-in escape valve:** if *all* available frontiers are unfavorable, allow expansion at a reduced rate so a polity is never hard-stuck.

The per-race biome/elevation **preference ORDER and hard exclusions are in GDD §4.6** — score **biome-rank first, then elevation** (biome dominates: a mountain-forest beats a flat-desert). Summary: **Humans** clear→Forest/taiga→jungle/swamp→desert, flat>hills>mtn, **never glacial mountains**; **Elves** Forest/Dense/Jungle/taiga→clear, elevation irrelevant, **never swamp/desert/glacial**; **Dwarves** mountains>volcanic>glacial>hills, biome irrelevant; **Beastmen** anywhere. **Peaceful expansion only — war-making ignores the preference and exclusions.** Hook: `_resolve_contest`/`_phase_expansion` frontier scoring; `sim_constants` weights.

### 5.2 Natural-borders preference (the polish pass)
Human polities prefer to **halt at natural borders** — **rivers** (ANY `setting_river_edges` present at the 24-mile sim scale; all are "major" enough there), **coastlines** (`water = ocean`), and **mountain spines** (best-effort: the ridge line / run of highest hexes through a range — if that is not cheaply detectable, **OMIT mountain gating** and rely on the §4.6 elevation/biome preferencing to approximate mountain-bounded realms; it will get close).
- Give each frontier *edge* a **`natural_border_resistance`** multiplier (high at river / coast / mountain-spine crossings) that heavily damps expansion across it.
- **Consolidate-before-expand:** while bounded by natural borders, a polity redirects its expansion budget into **internal population growth** until **saturation = ≥75% of its available hexes at ≥50% of their population cap** — measured against each hex's **current-biome cap** (the polity does NOT wait for deforestation to finish before seeking new space). At saturation, cross-border peaceful-expansion drive recovers. Realistic river-/coast-bounded realms fill before spilling over.
- **War-making is exempt:** invasions cross rivers, coasts, and mountains freely. The border resistance and the saturation gate apply to **peaceful expansion only.**
- Hook: `_phase_expansion` budget split; river + elevation data; per-hex current-biome caps. Constants: `NATURAL_BORDER_RESISTANCE_*`, `SATURATION_HEX_FRACTION=0.75`, `SATURATION_POP_FRACTION=0.50`.

### 5.3 Overseas expansion
Let coastal polities expand across water to non-adjacent coastal hexes (islands, far shores).
- **Requirement (the ONLY one):** the polity owns a **coastal settlement of any size**. No civ/tech/size gate, no hard distance cap. The target must be a coastal hex; a soft sea-crossing *cost* that grows with distance is an engineering nicety to keep it sane — not a requirement.
- Produces intentionally **non-contiguous** holdings (overseas colonies). **Coordinate with the §7.4d contiguity rule** so sea-linked colonies are NOT auto-severed — mark them as sea-linked. **Flag for Opus review** (touches the contiguity contract). Constants: `SEA_CROSS_COST` (soft, distance-scaled).

**Tests:** cultures expand toward developable terrain first; realms halt/slow at major rivers & mountain spines and fill their interior before crossing; coastal civ founds an overseas colony across a short sea gap without the realm being flagged as severed.

---

## 6. Phase 4 — Hybrid emergence (merge-vs-displace)

Per GDD §3.3–3.6. At a sustained border contest and at conquest, roll **merge vs displace**; drivers (GDD §3.3, decided): relative strength/size, alignment compatibility, shared language family, plus a randomization term (NOT civ/clan compatibility). On **merge**, the contact-zone hexes adopt the hybrid culture `HYB(A,B)` (looked up by unordered parent pair, synthesized from the authored kit + parent trait-blend); on **displace**, the existing assimilation path runs. **First-order only** (no hybrid×hybrid). New: hybrid definition table, `culture_synthesis_parents` on the culture instance / `setting_polities`, `_phase_hybridization`, trait-blend from parents (civ/clan via §3.4). **Highest architectural risk** — culture instances are per-realm/static today; the synthesized-hybrid instance is a new data shape. **Get an Opus review before building.**

---

## 7. Phase 5 — DEFERRED: clanhold migration (Völkerwanderung)

**Build LAST — only after Phases 1–4 are built, tested, and stable.** Clanhold cultures, on **local population saturation** (all held territory at its §4 cap, no favorable expansion room, hemmed by natural borders), **migrate**: the polity (or a war-band budding off it) relocates to new territory, shedding/reducing its home holdings, and on arrival triggers the §3.3 border-contest/merge with whoever holds the destination — feeding the emergence model (mimics the Migration Period / Völkerwanderung). Depends on Phase 2 (caps/saturation), Phase 3 (avoidance + natural borders), and Phase 4 (emergence). **Design sketch only; a full GDD spec will follow once the core is stable** — do not build from this paragraph alone.

---

## 8. Cross-cutting

- **Data model additions:** `culture_synthesis_parents`; per-hex clearing-progress (column or side table); `natural_border_resistance` (computed, cacheable per edge); overseas sea-link marker; revised `seed_biomes` on the 11 bases; `effective_territory_cap` is computed (not stored, or cached). Migrations: sequential, versioned, non-destructive.
- **`sim_constants` (all PROVISIONAL):** clearing ticks (forest/dense), terrain-avoidance weights, natural-border resistance, saturation fraction, sea-crossing distance/cost, migration thresholds.
- **EventScheduler-first:** `_phase_deforestation`, `_phase_hybridization`, and (later) migration are scheduled events in the priority queue.
- **Conventions:** banker's rounding on all new math; ACKS 1e terms (Civilized/Borderlands/Wilderness; turn undead; fighter/cleric/thief/mage); update `coding_conventions.md` and `build_log.md` each session; mark complex rules-interactions `[NEEDS-OPUS-REVIEW]`.

---

## 9. Open questions / tuning (for Jedidiah)

- **Deforestation/reforestation: RESOLVED 2026-06-28** (§5.4) — including jungle (clear 30 ticks / regrow 15) and elf restoration to Dense Forest & Jungle (confirmed).
- **Expansion preference / exclusions: RESOLVED 2026-06-28** (GDD §4.6) — per-race biome→elevation ordering + hard exclusions; peaceful-expansion only.
- **Overseas: RESOLVED 2026-06-28** — only requirement is a coastal settlement of any size; no civ/distance/port gate (soft distance cost optional).
- **Natural borders: RESOLVED 2026-06-28** — any sim-scale river + coastlines are borders; mountain-spine is best-effort (ridge line) or omitted in favor of terrain preferencing; war ignores all of it.
- **Saturation: RESOLVED 2026-06-28** — ≥75% of a polity's hexes at ≥50% of current-biome cap; peaceful-expansion gate (not war).
- **Migration (Phase 5):** full spec still deferred — to be designed once Phases 1–4 are stable. (Reuses the saturation measure above as its trigger.)
- **Remaining tuning (engineering defaults OK):** `natural_border_resistance` magnitude (soft vs near-hard); soft `SEA_CROSS_COST` distance curve; clearing/reforest tick values if play-testing wants them changed.
