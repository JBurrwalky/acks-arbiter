# Setting Generation — End-to-End Build Handoff

**Document type:** Build handoff / implementation plan.
**Authority:** ARCHITECTURAL for the stage ordering and the interfaces it names (all of which are defined in the GDDs it cites — this document adds no new design). Where this document and a cited GDD disagree, **the GDD wins**; flag the discrepancy in the build log.
**Audience:** Claude Code build sessions.
**Prepared:** 2026-06-12 (Cowork advisor session with Jedidiah; see build_log.md Session 2026-06-12).
**Status of the design:** COMPLETE. Every pre-build design question for this pipeline has been resolved and recorded. Your job is to build it, not to redesign it.

---

## 1. Mission

Build the **pre-game setting-generation pipeline end-to-end**: from "New Campaign" in the main menu, through the 8-layer generation (`gdd-setting-generation.md` §3) with the history simulation at its core, to an approved, locked, persisted campaign world handed off to party creation.

**Definition of done (the end-to-end acceptance test):**

1. From MAIN_MENU, a player creates a campaign via Quick Start (name + map size + seed), watches (or skips) the history replay, reviews the world on the approval screen, approves, and lands at the PARTY_CREATION boundary (a stub scene is fine — party creation is not this build).
2. The full pipeline runs with the **mock LLM provider** (and with *no* provider) producing a complete, playable-data world — deterministic names, deterministic brief. LLM polish is an upgrade, never a dependency.
3. **Determinism:** the same seed + slider vector produces a bit-identical world (hash test, §9.1) across two runs and across editor/headless.
4. **Validation green** (`gdd-setting-generation.md` §11.1 checklist) on at least 3 seeds × Medium and Large maps.
5. The Stage-4 **calibration report** (§9.3) has been generated and flagged for Jedidiah's review.

---

## 2. Session boot — read order

Every session: follow the CLAUDE.md Build Session Protocol (build-log navigator first, conventions navigator before code, `acks-raw-lookup` for every rule reference). For this build specifically, the authoritative document set, in read order:

| # | Document | Version | Role |
|---|---|---|---|
| 1 | This document | — | Stage plan, constraints, decisions ledger |
| 2 | `generation/gdd-setting-generation.md` | rev 4 (2026-06-12) | The pipeline: 8 layers, §7.2 **sim output contract**, §11 validation/review |
| 3 | `generation/gdd-history-simulation.md` | **v0.5** | Layer 4 — the core. §3 tick loop, §7 polity lifecycle incl. §7.3.1 wars, §7.8 constants table, §12.1 cited ACKS tier tables |
| 4 | `generation/gdd-culture-catalog.md` | current | Layer 3 inputs: culture records, derived behaviors (§4), seeding (§6) |
| 5 | `generation/gdd-terrain-system.md` | current | Biome tags, movement costs (diffusion damping, terrain multipliers) |
| 6 | `generation/gdd-region-painting.md` | **v0.2** | Phase 1 after Layer 2; Phase 2 after Layers 4–5. All thresholds concrete |
| 7 | `generation/gdd-naming-conventions.md` | rev 8 | The kit model; runtime assembly (§13); bank build (Stage 5) |
| 8 | `generation/gdd-campaign-creation-ui.md` | v0.1 | The player front door (Stage 10) |
| 9 | `generation/gdd-dungeon-layout.md`, `gdd-poi-generation.md`, `gdd-quest-rumor-system.md` | Mar–May drafts | Layer-6 consumers — **do a consistency skim against §7.2 before Stage 7** (they predate the rework) |

Superseded — do not implement from: `gdd-name-generation.md` (→ naming-conventions), `gdd-cultural-religious-generation.md` §3–§4 (→ religion simplification), `gdd-religion-system.md` **§7 only** (banner; rest of that GDD is runtime material, not this build), `docs/acks-arbiter-build-plan.md` phase labels (deprecated).

---

## 3. What already exists

- **`data/cultures/*.json`** — all 65 culture records, validated (schema, scalars, enums, sphere sums). The sim's per-culture knobs live here.
- **`data/conlang/`** — 12 family base kits + 65 culture kits + README. Feature-word lexicons complete for region naming (2026-06-12 gap-fill: neck/narrows/waste/road/way/track; beastman races inherit from the Kazhur base).
- **`data/name_banks/` does NOT exist** — building it is Stage 5.
- **`rules/*.xml`** — sacred. Every citation you need is already pinned in the GDDs with line numbers.
- Test fixtures (`data/test_campaign_*.json`, `test_hex_map.json`) from earlier subsystem work — useful shapes to study, not contracts.
- The engine's existing autoloads/services (EventScheduler architecture, SQLite repositories, EventBus, map renderer, Management Notebook UI stack) per `docs/acks_arbiter_design_brief_v11.md` and `docs/coding_conventions.md`.

## 4. Hard rules (non-negotiable)

1. **Never modify `rules/*.xml`.** One known data flaw is *documented and routed around*: `acore-setting-construction-rules.xml` `revenue_by_realm_type` personal-domain column disagrees with the RAW PDFs — do not consume that column; use `titles_of_nobility` values per `gdd-history-simulation.md` §12.1. Its stronghold-value column IS valid and used.
2. **Banker's rounding everywhere.** The sim does heavy arithmetic; build/reuse a single rounding utility.
3. **Determinism is a feature, not a nicety.** All randomness via per-subsystem seeded streams keyed `hash(campaign_seed, subsystem, tick, entity_id)` — no wall-clock, no hash-order iteration over dictionaries (sort keys before iterating), no float accumulation order dependence across platforms. The §9.1 hash test enforces this from Stage 0 onward.
4. **Engine-first, LLM-second.** Every stage completes and tests with the mock provider. Layer 7 and region-name polish are bounded upgrades with deterministic fallbacks.
5. **Three territory classifications** (Civilized/Borderlands/Wilderness), **four progression types**, **"turn undead"** — the CLAUDE.md terminology rules apply to all generated data and UI text.
6. Godot constraints per CLAUDE.md: no `class_name` in autoloads; godot-sqlite calling conventions; `user://` paths; run `--import` after adding `.gd` files before headless tests.

## 5. Decisions ledger — settled, do not re-litigate

These were decided with Jedidiah on 2026-06-12 (rationale in the GDD revision histories and build_log Session 2026-06-12). If implementation reveals a genuine defect in one, flag `[NEEDS-OPUS-REVIEW]` + a build-log note — don't silently change it:

| Decision | Where recorded |
|---|---|
| Religion is **derived, never simulated**: no religion_weights anywhere; practice = alignment_weights; flavor = culture × shared pantheon at runtime; nothing religious generated pre-game (not even deity names) | history-sim §10; setting-gen §7.3 |
| Wars resolve **within one tick**; army size = gp-value garrison budget; crushing gate = margin ≥ 0.80 + capital reach; disposition by effective_svg (≤0.35 vassalize / ≥0.65 annex / raider pillage) | history-sim §7.3.1 |
| f_size is the **tier multiplier** (1.35^tiers-above-County); tier keys on **realm families** | history-sim §7.5, §7.4 |
| Severity bands 0.50/0.85 with bias; shatter gated (vassals ≥ 2 or tier ≥ Duchy) | history-sim §7.6 |
| `fading` = post-peak compounding decay of inputs, **never** a collapse_risk term | history-sim §7.7 |
| Demihuman survival is **pure emergence** (no exemption); EPOCH_BIAS_MAX is the balance knob | history-sim §9 |
| Civ/clan transitions **deferred to v2** — start state holds all sim | history-sim §17 |
| Vassal domains tier-scaled (≤Principality 3 / Kingdom 4 / Empire 6 hexes); CORE_MAX 3 | history-sim §7.4 |
| MIN_RATE_FRACTION removed — solvency tests the RAW 2gp/family floor | history-sim §7.5.1 |
| Region names assemble from **kit recipes** (no per-category banks); fine regions **persist permanently**; **no 1.5-mile region pass** in v1; LLM polish top-8/min-0.75 with deterministic fallback | region-painting §5.1, §3.4, §5.3 |
| Campaign creation = Quick Start + Advanced; generation presented as **watchable epoch replay** (skippable); element-regen v1 = alignment re-roll / rename / dungeon-seed re-roll only | campaign-creation UI |

**Out of scope — do not build:** inter-polity diplomacy; climate-driven migration; religion propagation/deity-name generation (runtime rework owns it); civ/clan transitions; 1.5-mile region painting; exonyms; party/character creation (stub the handoff).

---

## 6. Build stages

Dependency-ordered. Each stage = one or more build sessions; end every session with a build-log entry per protocol. Don't start a stage until the prior stage's exit criteria pass (Stage 10 may start any time after Stage 4 fixes the replay-frame shape).

### Stage 0 — Scaffolding & determinism harness
Generation subsystem skeleton under `engine/subsystems/generation/world/` (file names per setting-gen §12.3: `setting_generator.gd` orchestrator, `culture_seeder.gd`, `history_simulator.gd`, etc.). Seeded-stream RNG service. SQLite schema (sequential migration) for canonical setting data: hexes + substrate, polities + vassal chains, settlements, regions, event log, ruin/POI seeds, replay frames, campaign parameters + seed. The determinism harness: serialize-and-hash the full setting dataset; test runs the pipeline-so-far twice and compares.
**Exit:** migrations apply cleanly; hash test green on an empty pipeline; conventions consulted and any new patterns recorded.

### Stage 1 — Layers 1–2: geography & climate
Heightmap (FastNoiseLite, directional bias — no tectonics), continental shaping, elevation curve, hydrology (river graph is a first-class output — region painting and the sim both consume it), coastline, Köppen climate, biome tags per `gdd-terrain-system.md`.
**Exit:** setting-gen §15 worked example reproduced in character (Medium map, seed 42 — distributions, not exact hexes); hash test green; biome tags validate against the terrain-system enum.

### Stage 2 — Region painting Phase 1 (geometric detection)
Depends only on Stage 1. Continents, terrain clusters with sub-split, anomalies, coastal features, hydronym graph — all thresholds per region-painting §4.1–§4.6. Unnamed region records with membership, nesting, overlaps, significance scores (§3.3 — computable now except the culture/history context term, which defaults 0 until Stage 6 re-scores).
**Exit:** worked-example-style map (region-painting §10) produces the expected feature classes; region hex-membership invariants hold (fine-scale machinery NOT built here — it's lazy, at-play, and belongs to the hex-subdivision build).

### Stage 3 — Layer 3: culture seeding
Catalog selection (biome-coverage constraint satisfaction, phonemic adjacency, ≤3 per demihuman race), per-campaign jitter, alignment draws (even split / explicit weights), wilderness homeland seeding, baseline beastman clanholds from `ax_domains_of_chaos.xml` distribution tables. Loads `data/cultures/*.json` — treat the records as read-only inputs.
**Exit:** N seeds × maps place valid seed sets (every culture's seed biome satisfied, adjacency rule holds); deterministic.

### Stage 4 — Layer 4: the history simulation ⭐ the core
Implement `gdd-history-simulation.md` v0.5 in §3's phase order. Recommended sub-stage order, each with focused tests:
4a. Substrate + demography (§6) — diffusion, assimilation, logistic growth, classification advancement, urban emergence.
4b. Expansion + border contest (§7.2–§7.3) with the budget accumulator.
4c. Realm economy/garrison ledger (§7.5.1) — pure functions over the realm state; unit-test against hand-computed examples (ACKS rates per family are cited inline).
4d. Wars (§7.3.1) + vassalage/secession (§7.4) + internal vassal organization.
4e. Stability/collapse/severity/successors (§7.5–§7.6) + fading (§7.7) + demihuman epoch bias (§9).
4f. Migration (§8); beastman repopulation (§7.6).
4g. Event log (§11), replay frames (§15), present-day handoff (§12) with the §12.1 tables and morale seeding.
**Every constant comes from §7.8 — implement them as one data-driven config resource, not scattered literals** (the balance pass will retune them without code changes).
**Exit:** full 160-tick runs complete in seconds; hash test green; §12 handoff emits the complete §7.2 contract; the **calibration harness** (§9.3) runs and its report is written to the build log with `[NEEDS-REVIEW]` for Jedidiah.

### Stage 5 — Name-bank build tool
A dev-time tool (editor script or headless mode) that assembles **static name banks per culture** from the conlang kits per naming-conventions §13: kit inheritance resolution (family base → culture override; blends per their authored style), morphology assembly (compounds, patronymics, gendered endings), seed-stock incorporation, used-name dedup, validation (§14). Output to `data/name_banks/` as committed assets. LLM-assisted curation of the output is a later content pass — the deterministic assembly must stand alone.
**Exit:** banks generated for all 65 cultures; validation green; spot-check report (10 names per category per 5 cultures) in the build log for Jedidiah's register check.

### Stage 6 — Layer 5 + region painting Phase 2 (naming)
Runtime name assignment (table lookup + morphology assembly); region naming per region-painting §5 (recipe table, attribution, multilingual majors, historical/hydronym caps, collision qualifiers); road tiering + merged named-route records (§6.1); fallen-polity reaches from the event log; re-score region significance with the context term; settlement/realm/dynasty naming per naming-conventions §4/§6.3.
**Exit:** a generated world is fully named with zero LLM calls; per-culture register spot-check; caps verified (≤25% hydronym-derived, historical override count ≤ hexes/100).

### Stage 7 — Layer 6: infrastructure & content seeding
Per the rewritten setting-gen §9: settlements reconcile-don't-invent (§9.1); roads (§9.2 — feeds road tiering retroactively, so run before final road naming or iterate once); dungeons provenance-first with geometric top-up (§9.3); deforestation (§9.4); forts on sim-hot frontiers (§9.5); classification finalization, promotion-only (§9.6); POIs (§9.7) and quest/rumor seeds (§9.8) per their GDDs — **after the §2 consistency skim** of those three older GDDs (log any contract mismatches found; small ones fix inline, structural ones flag).
**Exit:** §11.1 validation items for settlements/roads/dungeons/classification green on 3 seeds.

### Stage 8 — Layer 7: LLM narrative (behind the provider wall)
Prompt assembly per setting-gen §10.2 (per-realm, per-culture, religious-tradition stubs, dungeon hooks, timeline from the significance-ranked log, setting brief), cached as campaign data. Mock provider returns deterministic template text; absent provider skips silently. Region-name polish (top-8) hooks in here too.
**Exit:** full pipeline with mock provider yields a complete brief + timeline; with a real provider config present (untested live is acceptable) the same code path assembles prompts; no stage blocks without a provider.

### Stage 9 — Layer 8: validation & lock
The complete §11.1 mechanical checklist as an automated validator with a human-readable failure report; the post-approval lock (canonical flag; downstream systems read-only); regenerate-whole-world; the three v1 element-regens.
**Exit:** validator green on 3 seeds × Medium/Large; lock semantics tested (no writes to canonical data after lock).

### Stage 10 — Campaign-creation UI
`gdd-campaign-creation-ui.md` in full: the four screens, replay playback from stored frames (pacing/speed/skip), parameter tabs bound to the config resource, review screen composing map renderer + side overlay, seed sharing, the EventBus signals (§8). May start after Stage 4 (frames exist); finishes last.
**Exit:** the §1 definition-of-done acceptance test passes end-to-end.

---

## 7. Testing & verification strategy

### 9.1 Determinism hash
From Stage 0: run pipeline twice per test seed, hash the serialized dataset, compare. Add per-layer sub-hashes so a divergence localizes. Run in the headless suite every session that touches generation.

### 9.2 Validation checklist
Setting-gen §11.1 is the spec. Build it as data-driven checks with per-check IDs so failures cite themselves.

### 9.3 Calibration harness (Stage 4)
Headless batch: ≥ 20 seeds × Large at default sliders, reporting distributions vs targets — realm-lifetime by tier (target: mid-tier ≈ 750 yr expected, empire ≈ 300 yr at scale — history-sim §7.5 calibration bullet); end-state realm count (5–10 on Large); wilderness fraction (~50%); ruins per epoch; demihuman enclave rate (should be ≈ universal collapse, rare survivors); migration count (a handful per history); war/vassalization/pillage event frequencies. Output a markdown report; flag `[NEEDS-REVIEW]` in the build log. **Do not self-tune beyond obvious order-of-magnitude bugs** — the balance pass is Jedidiah's call on the report.

### 9.4 Worked examples as fixtures
Setting-gen §15 (Layers 1–2), region-painting §10, history-sim §16 — encode each as a characterization test (assert the *kinds* of outcomes, not exact hexes).

## 8. Model usage & session hygiene

Per CLAUDE.md: **Sonnet** for implementing what the GDDs already specify (most of Stages 0–3, 5–7, 10); **Opus** for Stage 4 planning, the rules-interaction edges (morale seeding, tier assignment, the §12 handoff), the Stage-7 consistency skim verdicts, and any `[NEEDS-OPUS-REVIEW]` items. Every rule citation through `acks-raw-lookup` even though the GDDs pin line numbers — verify, don't trust transcription. Conventions via `acks-conventions --for-task` before each stage; new patterns (the config-resource approach, the hash harness, RLE encoding) get recorded in `docs/coding_conventions.md` as they're established.

**Open items you will encounter and should leave alone:** nemesis-graph sign-off (runtime religion); conlang curation flags (blend coinages, dwarven lexicon thinness — Stage 5 will surface them naturally in the spot-check report); the LLM provider settings wizard (separate design pass); `gdd-hex-subdivision.md` fine-region lazy painting (at-play feature, not this pipeline).

Godspeed. The design is done; make it real.
