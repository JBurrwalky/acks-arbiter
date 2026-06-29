# Build Handoff — NPC Ruler AI (Behavior Planner)

**For:** Claude Code (build agent)
**Spec:** `generation/gdd-ruler-ai.md` (v0.3) — the authoritative design. This handoff sequences it into verifiable phases; the GDD is the source of truth for any detail not repeated here.
**Status of design:** Fully approved by Jedidiah. All §13 design questions resolved; the §10 tables and all §11 action-vocabulary entries are approved.
**Author:** Advisor (design). **Date:** 2026-06-28.

---

## 0. How to use this document

This is a **multi-session build**. Do the phases in order; each ends with passing headless tests and a `build_log.md` entry. Phase 0 is a hard prerequisite for everything (it builds the data the planner consumes). Phases 1–4 layer on top.

Each phase below has: **Goal · GDD refs · Files · Key interfaces · Acceptance bar · Model · a paste-ready prompt.** Paste one phase's prompt into a fresh build session, let it complete and go green, then move to the next.

**Do not redesign.** The GDD encodes Jedidiah's decisions. If you find a genuine ambiguity or a rule you can't cite, **stop and ask Jedidiah** — do not invent a rule or a contract. Every ACKS rule you touch must cite `rules/*.xml` via `acks-raw-lookup` (do not quote rules from memory).

---

## 1. Shared preamble (every phase begins with this)

Run the **Build Session Protocol** from `CLAUDE.md`:

1. Read `CLAUDE.md`.
2. `acks-build-log`: `--last 1`, `--next-actions 3`, `--needs-review`, and `--for-task "<this phase>"`. Do **not** read `build_log.md` directly (it is ~5 MB).
3. Read `docs/acks_arbiter_design_brief_v11.md`; skim `docs/document_map.md`.
4. Read the spec: `generation/gdd-ruler-ai.md` (whole). Load the named dependency GDDs only as needed: `gdd-npc-personality.md` (§8 formulas, §9 LLM contract), `gdd-realtime-scheduler.md` (scheduler), `gdd-stronghold-construction.md` (Phase 1), `gdd-army-warfare.md §4.3.3` (Phase 3).
5. `acks-conventions --for-task "<this phase>"` before writing code; update `docs/coding_conventions.md` if a new pattern emerges.
6. For any ACKS rule: `acks-raw-lookup` with citation (precedence Axioms → HFH → APC → L&E → DaW → ACore).
7. Implement in Godot-native terms; run focused headless tests; **append a `build_log.md` entry** at the end (template via `acks-build-log`; run `--lint` after).

**Hard constraints (from CLAUDE.md + design brief — do not violate):**

- **Determinism.** Every ruler decision is reproducible from (ruler state + domain state + a seeded RNG). The whole loop must pass with the **mock LLM** (`LLMManager` is a stub today). The LLM never decides anything.
- **Banker's rounding** (round half to even) everywhere a value is rounded.
- **No new autoload.** `RulerAI` and its sub-components are `RefCounted` services under `engine/subsystems/realm_ai/` (mirrors the Phase 7 `realm_ai/` precedent). `class_name` is allowed (only autoloads forbid it).
- **EventScheduler-first.** The ruler turn runs inside the existing monthly cadence; no polled loop, no per-party clock. `Timekeeping.get_total_rounds()` is "now."
- **SQLite is ground truth.** New tables get **sequential, versioned, non-destructive** migrations. godot-sqlite: `query(sql)` for no-arg (returns bool), `query_with_bindings(sql, array)` for parameterized; results in `db.query_result`; `query()` takes **no** second arg; path uses `user://`.
- **After adding new `.gd` files:** run `/c/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path . --import` once to refresh `.uid` / the global class cache before the test runner can preload them. Test command: `/c/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn`.
- **Naming:** PascalCase classes / snake_case files / past-tense snake_case signals / plural snake_case tables (per CLAUDE.md table).

**Approved decisions to honor (do not relitigate):**

- v1 scope = **Regional-LOD** autonomy, **manage-and-defend** (no offensive war/expansion), **diplomacy deferred**.
- LOD active set = full-tier rulers within the **6-mile play window + 10-six-mile-hex buffer**, gated on `persistence_tier == "full"` (the buffer never forces materialization).
- Backdrop realms **auto-stabilize** (GDD §8.4), they do not decay.
- `manage_stronghold` is **net-new engine work** (Phase 1) — no NPC-usable construction path exists today.

**New signals this build introduces** (past-tense; must NOT collide with the Phase-7 set `realm_title_changed` / `vassal_revolted` / `vassal_tribute_paid` / `vagary_of_war_resolved`):
`ruler_action_taken(ruler_npc_id, domain_id, action_id, outcome)`, `ruler_strategy_reassessed(ruler_npc_id, trigger, changes)`, `ruler_activated_for_lod(ruler_npc_id)`, `ruler_deactivated_for_lod(ruler_npc_id)`. Declare them in `EventBus` once (Phase 0 or first use).

---

## 2. Phase map

| Phase | Deliverable | Depends on | Model |
|---|---|---|---|
| **0** | `StrategicDisposition`/`RulerProfile` data layer + builder + generation wiring | — | Sonnet |
| **1** | Ruler action catalog + the new `manage_stronghold.gd` handler | 0 | Sonnet |
| **2** | Scorer + situational modifiers + monthly-tick integration + backdrop auto-stabilize | 0, 1 | Sonnet (Opus review of integration) |
| **3** | Crisis responder + LOD manager + `defensive_resistance` (replaces the extraction heuristic) | 0, 1, 2 | Opus for the extraction-resistance replacement; Sonnet for the rest |
| **4** | Determinative-AI → LLM contract (`RulerActionNarrator`, reassessment hook) + `ruler_ai_state` | 0–3 | Sonnet |

**Global definition of done:** a mixed campaign (PC domain + several NPC domains, some active, some backdrop) runs a monthly tick with **no `auto_pause` from NPC rulers, no LLM calls**; active rulers take disposition-driven actions; backdrop rulers only auto-stabilize; all phase tests green; `build_log.md` updated each phase.

---

## 3. Phase 0 — StrategicDisposition / RulerProfile data layer

**Goal.** Build the data the planner consumes. The 12-axis `NpcPersonality` is already live; this derives the strategic layer from it.

**GDD refs.** §4 (sub-phase 0), §10 (`ruler_dispositions` table — approved), and `gdd-npc-personality.md §8.2/§8.3` (the struct + exact formulas — reproduce verbatim).

**Files.**
- New migration (next sequential number) creating `ruler_dispositions` (PK `character_id`): the 7 strategic axis ints, the 8 weights (REAL), `crisis_response` (TEXT), and `aggression_toward` / `alliance_preference` as JSON TEXT. Register in the standard three sites (`SettingRepository` / `CampaignRepository` / `SettingDatasetHasher`) as applicable.
- `engine/shared_types/strategic_disposition.gd` (`class_name StrategicDisposition`) and a `RulerProfile` view (the 8 weights + crisis_response + the two dicts) — GDD §4.4.
- `engine/subsystems/realm_ai/strategic_disposition_builder.gd` (`class_name StrategicDispositionBuilder`): `static build(npc_personality: NpcPersonality, alignment: String) -> StrategicDisposition`.
- Repository read/write for the table (follow the existing repo pattern).
- Wire generation: where an NPC **ruler** is created (`NpcRulerGenerator`, role `"ruler"`; also confirm `ClassedNpcBuilder`/materialization ruler paths), build + persist its disposition. Add a one-shot backfill for rulers that already exist.

**Key interfaces / rules.**
- Implement the helpers and the eight weight formulas + `crisis_response` **exactly** as in `gdd-npc-personality.md §8.3` (`u`, `inv`, `mot`, `clamp01`, `orthodoxy_term`). Inputs come from the existing `NpcPersonality.axes` dict + `motivation_primary/secondary`; **`alignment` comes from the character record** (the `orthodoxy_term` needs it).
- Relational dicts **degrade gracefully**: `aggression_toward` seeds from `RealmRepository.get_relation()` bands + the revenge bump; `alliance_preference` is computed but dormant in v1; both empty when relations/§5 are absent.

**Acceptance bar.**
- **Golden test:** the `gdd-npc-personality.md §8.3` Lawful-baron worked example reproduces `military_weight = 0.846`, `oppression_weight = 0.801`, `diplomatic_weight = 0.078` (to the GDD's stated precision).
- Disposition persists and round-trips (to_dict/from_dict; DB write/read).
- Every NPC ruler has a disposition after generation + backfill.
- No rule cited that isn't in `rules/*.xml`.

**Paste-ready prompt:**
> Implement Phase 0 of the NPC Ruler AI per `generation/gdd-ruler-ai.md` §4/§10 and `gdd-npc-personality.md §8`. First run the Build Session Protocol (CLAUDE.md), including `acks-build-log --for-task "StrategicDisposition ruler profile"` and `acks-conventions --for-task "new table, shared type, generation wiring"`. Build: the approved `ruler_dispositions` table (sequential migration, registered in the standard three sites), `StrategicDisposition`/`RulerProfile` shared types, and `StrategicDispositionBuilder.build(npc_personality, alignment)` reproducing the §8.3 formulas **verbatim** (u/inv/mot/clamp01/orthodoxy_term, the 8 weights, crisis_response). Wire disposition generation into the NPC ruler creation path and add a backfill for existing rulers. Relational dicts degrade gracefully. Add the golden unit test (Lawful baron → military 0.846, oppression 0.801, diplomatic 0.078) plus persistence round-trip tests. Run headless tests green, then append a `build_log.md` entry. Do not invent any ACKS rule; cite `rules/*.xml` via acks-raw-lookup for anything you reference.

---

## 4. Phase 1 — Action catalog + `manage_stronghold` handler

**Goal.** The action vocabulary a ruler picks from, including the one net-new handler.

**GDD refs.** §5 (catalog + the `manage_stronghold` build note), §11 (action-vocabulary registration — approved), §2.2/§2.3/§2.7 (the RAW the actions reduce to).

**Files.**
- `engine/subsystems/realm_ai/ruler_action_catalog.gd` (`class_name RulerActionCatalog`): `static available_for(ruler, domain, world_state) -> Array` returning precondition-gated candidates, each with `action_id`, `base_value`, and governing weight per the §5 tables.
- Register the new composite intents in the action vocabulary / `ActivityCatalog`: `raise_garrison`, `hold`, `defensive_resistance` (stub here; logic lands Phase 3), and `manage_stronghold`.
- **New** `engine/subsystems/activities/handlers/manage_stronghold.gd` (`static on_complete(state, _runner) -> Dictionary`), resolving `owner_character_id → domains.id` exactly like `administer_domain.gd`. Three modes (build / upgrade / repair):
  - **build/upgrade (abstract fast path):** deduct gp from the domain treasury, `CampaignRepository.update_stronghold(id, {cp_value, shp, garrison_capacity})` toward the territory minimum, then `StrongholdRepository.recompute_sufficiency_after_change(domain_id)`.
  - **repair/restore:** raise shp/cp_value above threshold for the post-siege rebuild cost (RAW: full construction cost for the un-repaired half), then `LifecycleHandler.restore_from_ruin(domain_id, stronghold_id, calendar_day)` if the domain is in `ruined_stronghold`.
  - Register it in `domain_handlers_registration.gd`.
- `raise_garrison` composite: wrap the existing `conscript_troops` / `levy_militia` / `hire_mercenaries` handlers to bring garrison spend up to the 2/3/4 gp/family minimum (respect clanhold blocks on militia/conscript).

**Key interfaces.** Existing handlers are `static on_complete(state, _runner) -> Dictionary`, keyed on `state.character_id → owner_character_id`. Reuse `administer_domain.gd`, `oversee_investment.gd`, `issue_decree.gd`, `train_troops.gd`, `repress_population.gd` as-is by setting `state.character_id` to the NPC ruler. Stronghold writers: `CampaignRepository.create_stronghold/update_stronghold`, `StrongholdRepository.recompute_sufficiency_after_change`, `LifecycleHandler.restore_from_ruin/mark_stronghold_collapsed`. Minimums per `acore_axioms_strongholds_and_domains.xml:87-98`; rate/cost per `daw_equipment_and_construction.xml:747-779` + `ax_campaign_play.xml:843-846`.

**Acceptance bar.**
- Precondition gating: `train_troops` blocked without Manual of Arms / not at stronghold; `levy_militia`/`conscript` blocked for clanhold; `repress_population` blocked when militia in force.
- `manage_stronghold` raises an under-minimum stronghold toward sufficiency and lifts the −1/−2/−3 base-morale penalty; the repair mode restores a `ruined_stronghold` domain to active.
- All actions are reachable for an NPC owner (set `state.character_id` = NPC ruler) — no PC assumption leaks in.

**Model.** Sonnet. (The `manage_stronghold` handler is the only genuinely new mechanic; keep it to the abstract fast path per the GDD.)

**Paste-ready prompt:**
> Implement Phase 1 of the NPC Ruler AI per `generation/gdd-ruler-ai.md` §5/§11 (and §2.7 + `gdd-stronghold-construction.md §18` for the stronghold action). Run the Build Session Protocol first. Build `RulerActionCatalog.available_for(...)` (precondition-gated candidates with base_value + governing weight per §5), register the approved composite intents (`raise_garrison`, `hold`, `defensive_resistance` stub, `manage_stronghold`), and create the **new** `manage_stronghold.gd` handler (`on_complete(state,_runner)`, owner_character_id-keyed, build/upgrade/repair modes via the abstract value-record fast path: deduct gp → `update_stronghold` → `recompute_sufficiency_after_change`; `restore_from_ruin` for the ruin case). Implement `raise_garrison` by wrapping the existing conscript/levy/mercenary handlers to the 2/3/4 gp/family minimum. Add precondition-gating tests and a stronghold build+repair test. Cite `rules/*.xml` for every rule. Green tests, then `build_log.md` entry.

---

## 5. Phase 2 — Scorer + monthly-tick integration + auto-stabilize

**Goal.** The deterministic decision loop, hooked into the monthly tick; backdrop realms auto-stabilize.

**GDD refs.** §6 (scoring + §6.2 modifiers incl. stronghold-state), §3.2 (monthly-tick hook), §3.3 + §8.4 (auto-stabilize).

**Files.**
- `engine/subsystems/realm_ai/ruler_action_scorer.gd` (`class_name RulerActionScorer`): `utility = base_value × relevant_weight × Π situational_modifier`; argmax (top-2..3 for large realms); per-(ruler, calendar_month) seeded RNG tie-break; banker's rounding. Implement the §6.2 modifier tables (morale tier, treasury, garrison state, **stronghold state**, threat).
- `engine/subsystems/realm_ai/ruler_ai.gd` (`class_name RulerAI`): `static process_campaign_month(campaign_id, calendar_day, active_set) -> Array` — for each active-set NPC-owned domain, run candidates → score → execute the winning action's handler (Phase 1) → emit `ruler_action_taken`. Mirror `NpcSyndicateMonthlyResolver.process_campaign_month` (stateless static, batch, no UI interrupt).
- `engine/subsystems/realm_ai/ruler_backdrop_stabilizer.gd` (or a method on `RulerAI`): the §8.4 cheap pass for non-active NPC domains.
- Integrate in `engine/subsystems/session/handlers/domain_handlers.gd::_handle_monthly_tick`: after the per-domain `_resolve_domain_month` → `_save_domain` loop (it already produces the `result` dict with revenue/morale_tier/threats/challenger_summary), call `RulerAI.process_campaign_month(...)` for active rulers and the stabilizer for backdrop ones. Branch on `owner_character_id ≠ PC`. **No `auto_pause` for NPC rulers.** Mutations land before `_save_domain` persists.

**Key interfaces.** The per-domain `result` dict from `_resolve_domain_month` is the scorer's input. Use `RealmAggregator.aggregate(ruler_character_id)` for "how big am I". `NPCChallengerEmergence.process_monthly_tick` already fires on the tick — read its summary as a threat input (full crisis handling is Phase 3).

**Auto-stabilize (§8.4) is, for backdrop domains only:** treat garrison as funded to minimum for the morale roll (suppress the −1/gp-short penalty), treat the ruler as administering (+1 morale-roll modifier), floor neglect morale at Apathetic (0), apply player-caused effects (pillage −4, occupation −1/mo) in full, take **no** discretionary action. All PROJECT CALL constants live in one place, tunable.

**Acceptance bar.**
- Scorer determinism: identical (ruler, domain, seed) → identical choice across runs.
- Worked-example scenario: a Turbulent-morale domain with an oppressive ruler → planner raises garrison then represses; morale trends up over a few months.
- Backdrop auto-stabilize: a neglected off-camera domain holds at/above Apathetic; a player-pillaged one still takes −4.
- Full monthly batch over a mixed campaign runs with **no `auto_pause`, no LLM**; active rulers act, backdrop only stabilize.

**Model.** Sonnet to implement; **flag the `domain_handlers.gd` integration for Opus review** (cross-subsystem boundary, the scoring heart). Mark any open judgment `[NEEDS-OPUS-REVIEW]` in the log.

**Paste-ready prompt:**
> Implement Phase 2 of the NPC Ruler AI per `generation/gdd-ruler-ai.md` §6, §3.2, §3.3, §8.4. Run the Build Session Protocol (`acks-build-log --for-task "ruler monthly turn scorer domain_handlers"`). Build `RulerActionScorer` (utility = base × weight × Π situational-modifiers from §6.2 incl. stronghold-state; argmax/top-2-3; per-ruler-per-month seeded RNG; banker's rounding), `RulerAI.process_campaign_month(...)` (mirroring `NpcSyndicateMonthlyResolver`), and the §8.4 backdrop auto-stabilize pass. Integrate into `domain_handlers.gd::_handle_monthly_tick` after `_resolve_domain_month`/`_save_domain`, branching on NPC ownership, emitting `ruler_action_taken`, with **no auto_pause for NPC rulers and no LLM calls**. Add determinism, worked-example, auto-stabilize, and mixed-batch tests. Flag the integration `[NEEDS-OPUS-REVIEW]`. Green tests, `build_log.md` entry.

---

## 6. Phase 3 — Crisis responder + LOD manager + extraction-resistance replacement

**Goal.** Threat handling, the regional activation model, and the disposition-driven extraction-resistance decision that replaces the army-warfare placeholder.

**GDD refs.** §7 (crisis posture, §7.2 challenger, §7.3 extraction-resistance, §7.4 stronghold loss), §8 (LOD: §8.1 tiers + materialization safety, §8.2 promote/demote, §8.4 reference). `gdd-army-warfare.md §4.3.3` (the placeholder being replaced).

**Files.**
- `engine/subsystems/realm_ai/ruler_crisis_responder.gd`: maps `crisis_response` → action biases (GDD §7.1); routes challenger-emergence (§7.2) and stronghold-loss/ruin (§7.4, prioritize `manage_stronghold`).
- `defensive_resistance` logic — **replace** `engine/subsystems/army_warfare/extraction_resistance_heuristic.gd`'s flat 50% rule with the §7.3 disposition-modulated `threshold_ratio`, **reusing its existing vassal-federation + per-vassal loyalty machinery** (RealmGraph + VassalRepository). Keep the `vassal_revolted` emission. At neutral disposition it must reproduce the 50% anchor (regression test).
- `engine/subsystems/realm_ai/ruler_lod_manager.gd` (`class_name RulerLodManager`): compute the active set = `persistence_tier == "full"` rulers whose domain is within the **6-mile window + 10-six-mile-hex buffer** (use `RegionZoomIn` window bounds), plus any in a player-relevant conflict. Promotion/demotion (build disposition on promotion if uncached; cancel scheduled events on demotion via `cancel_all_for_owner`); emit `ruler_activated_for_lod` / `ruler_deactivated_for_lod`. **The buffer must never promote a `named`/abstract ruler** — it only widens the active set among already-`full` rulers.

**Acceptance bar.**
- `crisis_response` 4-quadrant mapping correct at the 5/6 boundary.
- `defensive_resistance`: neutral disposition = 50%-BR regression anchor; `aggressive`/`cautious` shift the threshold per §7.3; federation + loyalty rolls unchanged.
- LOD promote/demote emit the right signals and seed/cancel events; **a `named`/abstract ruler in the buffer is never promoted** (materialization-safety test).
- A `ruined_stronghold` domain → planner prioritizes `manage_stronghold` before the 30-day grace lapses.

**Model.** **Opus for the extraction-resistance replacement** (RAW-touching, cross-subsystem — it supersedes a documented placeholder; review carefully and cite the resistance/occupation RAW). Sonnet for the LOD manager and crisis wiring.

**Paste-ready prompt:**
> Implement Phase 3 of the NPC Ruler AI per `generation/gdd-ruler-ai.md` §7 and §8 (and `gdd-army-warfare.md §4.3.3`). Run the Build Session Protocol. Build `RulerCrisisResponder` (§7.1 posture biases; §7.2 challenger routing; §7.4 stronghold-loss → prioritize `manage_stronghold`). **Replace** `extraction_resistance_heuristic.gd`'s flat-50% rule with the §7.3 disposition-modulated threshold, reusing its vassal-federation + loyalty machinery and keeping `vassal_revolted`; neutral disposition must regression-match 50%. Build `RulerLodManager` (active set = `persistence_tier=='full'` rulers within the 6-mile window + 10-hex buffer; promote/demote with signals + event seed/cancel; the buffer never promotes a `named`/abstract ruler). Add crisis-mapping, extraction-resistance (neutral + shifted), LOD-signal, materialization-safety, and stronghold-ruin tests. Use Opus for the extraction-resistance replacement; cite `rules/*.xml`. Green tests, `build_log.md` entry.

---

## 7. Phase 4 — Determinative-AI → LLM contract

**Goal.** The narration + reassessment seam, fully mock-correct.

**GDD refs.** §9 (Seam A narration, Seam B reassessment), §10 (`ruler_ai_state`).

**Files.**
- `engine/subsystems/realm_ai/ruler_action_narrator.gd`: assembles the §9.1 `ruler_action_narration` context Dictionary and calls `LLMManager.request_narration(context)`. When `is_configured()` is false (always today), return the **deterministic template** for that `action_id` (mock compositional-flavor / fragment-bank path per `gdd-npc-personality.md §9.3`). `is_fallback`-safe.
- Seam B reassessment hook: optional `request_narration({task_type: "ruler_strategy_reassessment", ...})` triggered when a player action crosses a significance threshold; **validate** the returned structured suggestion against the action vocabulary (reject unknown/malformed/rule-violating per design brief §9.1); a valid suggestion enters the scorer **only as a situational modifier**, never executes directly. No-op under mock. Emit `ruler_strategy_reassessed`.
- New migration: `ruler_ai_state` (one row per active ruler): LOD tier, `last_strategic_turn_day`, last-action id, optional small narration cache. Register in the standard sites.

**Acceptance bar.**
- With the stub, `ruler_action_taken` narration returns a deterministic `is_fallback` template — no crash, no variance.
- Reassessment is a no-op under mock; validation rejects malformed suggestions; a valid one only nudges the scorer.
- The full loop still passes with the mock provider end-to-end.

**Model.** Sonnet.

**Paste-ready prompt:**
> Implement Phase 4 of the NPC Ruler AI per `generation/gdd-ruler-ai.md` §9/§10. Run the Build Session Protocol. Build `RulerActionNarrator` (Seam A: assemble the §9.1 `ruler_action_narration` context, call `LLMManager.request_narration`, return the deterministic per-`action_id` template when not configured — mock-correct, `is_fallback`-safe). Add the Seam B reassessment hook (validated structured suggestion → situational-modifier only; no-op under mock; emit `ruler_strategy_reassessed`). Add the `ruler_ai_state` table (sequential migration, registered). Tests: stub narration is deterministic/no-variance; reassessment no-op + validation rejects malformed; full loop green on mock. `build_log.md` entry.

---

## 8. After all phases

- Confirm the **global definition of done** (§2): mixed-campaign monthly tick, no NPC `auto_pause`, no LLM, active rulers act, backdrop stabilize, all tests green.
- Update `docs/coding_conventions.md` with any new patterns (the `RulerAI` service shape, the composite-intent handler pattern, the LOD activation pattern).
- Leave a `[NEEDS-OPUS-REVIEW]` note for: the scorer integration (Phase 2) and the extraction-resistance replacement (Phase 3) if not already reviewed.
- Forward work (separate GDDs, do **not** build now): `gdd-ruler-diplomacy.md` (alliances/treaties, `expansion_weight`/`diplomatic_weight`), `gdd-dynasties.md` (heirs/bloodline/succession-by-inheritance).

---

## 9. Quick interface index (for convenience — verify against code)

- Monthly hook: `domain_handlers.gd::_handle_monthly_tick` → `_resolve_domain_month` (per-domain `result` dict) → `_save_domain`. Batch model: `NpcSyndicateMonthlyResolver.process_campaign_month`.
- Scheduler: `EventScheduler.schedule_at(fire_time, event_type, owner_id, data, priority)`, `cancel_all_for_owner(owner_id, event_type)`, `has_event_for_owner(...)`; self-reschedule via the handler `next_events` return; `ScheduledEvent.PRIORITY_ENVIRONMENTAL`.
- Existing action handlers (all `static on_complete(state,_runner)`, owner_character_id-keyed): `administer_domain`, `oversee_investment`, `issue_decree`, `conscript_troops`, `levy_militia`, `hire_mercenaries`/`solicit_mercenaries`, `train_troops`, `repress_population`, `call_to_arms` (heavy lifting in `CallToArmsHandler.issue_call`).
- Realm AI: `RealmRepository.get_relation/set_relation`, `RealmAggregator.aggregate`, `RealmGraph.apex_for_domain/is_allied`, `VassalRepository`, `ExtractionResistanceHeuristic.evaluate` (to be generalized), `NPCChallengerEmergence.process_monthly_tick`.
- Strongholds: `CommissionPipeline.start_commission` (timed path), `CampaignRepository.create_stronghold/update_stronghold`, `StrongholdRepository.recompute_sufficiency_after_change`, `LifecycleHandler.restore_from_ruin/mark_stronghold_collapsed`, `DomainStocker.stock_stronghold`.
- Personality/LLM: `NpcPersonality` (`characters.personality` JSON; `axes`, `motivation_*`, `deviant_axes()`), `PersonalityAxes`, `ResponseEnvelope` (`ok/fail/fallback`, `is_fallback`), `LLMManager.request_narration(context)` (stub: reads `task_type`, returns `fallback`).
