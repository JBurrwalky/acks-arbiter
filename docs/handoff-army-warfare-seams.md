# Build Handoff — Army Warfare Seams & Surfaces

**For:** Claude Code (build agent)
**Spec:** `generation/gdd-army-warfare.md` (authoritative for all warfare mechanics) + `generation/gdd-ruler-ai.md` (authoritative for the planner side of every seam). This handoff sequences the gap-closure work; the GDDs are the source of truth for any detail not repeated here.
**Status of design:** Approved by Jedidiah 2026-07-04 (four scope decisions recorded in §2 below).
**Author:** Advisor (design). **Date:** 2026-07-04.

---

## 0. Why this arc exists (the audit in one paragraph)

The warfare *substrate* is built and tested: composition, officers, marching, supply, the field-battle resolver, siege resolvers, casualties, pursuit, morale, `CallToArmsMuster`. The ruler-AI arc (Phases 0–4, complete) built its half of every seam. What is missing is the **connective tissue and the player-facing surface**: (1) extraction is a flat placeholder (`army_marcher._apply_marching_extraction` credits 100/50 gp per hex — no RAW yields, no cooldown, no resistance decision; the encamped `requisition_leg`/`loot_leg` activities do not exist at all); (2) `BattleDispatcher` has **zero production callers** and nothing listens to `armies_collided`, so the fully-built battle resolver is unreachable from normal play; (3) `FieldBattlePanel` is never instantiated into any scene; (4) `SiegeDispatcher` is reachable only from the threats sub-tab; (5) the three ruler-AI handoff items (build log 10.4) are open: `call_to_arms` recorded-not-routed, the §8.1 conflict hook (`extra_ruler_ids`) has no caller, `defensive_resistance` decisions are consumed by nothing; (6) armies have **no on-map presence** on the 6-mile regional map despite `armies.map_id/hex_q/hex_r` being live.

---

## 1. Shared preamble (every phase begins with this)

Run the **Build Session Protocol** from `CLAUDE.md`:

1. Read `CLAUDE.md`.
2. `acks-build-log`: `--last 1`, `--next-actions 3`, `--needs-review`, and `--for-task "<this phase>"`. Do **not** read `build_log.md` directly.
3. Read `docs/acks_arbiter_design_brief_v11.md`; skim `docs/document_map.md`.
4. Read the spec sections named in the phase (below). `gdd-army-warfare.md` is ~1,500 lines — load the cited sections, not the whole file, unless the phase says otherwise.
5. `acks-conventions --for-task "<this phase>"` before writing code; update `docs/coding_conventions.md` if a new pattern emerges.
6. For any ACKS rule: verify via `acks-raw-lookup` with citation (precedence Axioms → HFH → APC → L&E → DaW → ACore). The RAW line references in this document come from the GDDs; **re-verify them against `rules/*.xml` before implementing** — do not trust this handoff for rule content.
7. Implement in Godot-native terms; run focused headless tests; **append a `build_log.md` entry** at the end (`acks-build-log --lint` after).

**Hard constraints (from CLAUDE.md — do not violate):**

- **Determinism.** All NPC-vs-NPC resolution is silent and reproducible from state + seeded RNG. Mock LLM throughout; the LLM never decides anything.
- **Banker's rounding** everywhere a value is rounded.
- **No new autoloads.** New services are `RefCounted` under `engine/subsystems/armies/` (or `realm_ai/` where the phase says so).
- **EventScheduler-first.** All timed activity (7-day extraction legs, muster tranches) is scheduled events, mirroring the `travel_leg` pattern in `army_marcher.gd`.
- **SQLite is ground truth.** Sequential, versioned, non-destructive migrations. godot-sqlite: `query()` takes no second arg; `query_with_bindings` for params; results in `db.query_result`.
- **Unified-cp convention.** All persisted money is **cp** (the migration-114+ sweep). `gdd-army-warfare.md` predates the sweep and says `current_stockpile_gp`; the live column is `current_stockpile_cp`. RAW gp values convert at the boundary. **Known bug to fix in Phase B:** the extraction placeholder adds gp-denominated values directly into `current_stockpile_cp`.
- **After adding `.gd` files:** run `--headless --path . --import` once before the test suite. Test command: `/c/godot/Godot_v4.6.1-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn`.

**Approved decisions to honor (Jedidiah, 2026-07-04 — do not relitigate):**

1. **Full §4.3 extraction build** — RAW yields, cooldowns, family loss, combined ceiling, encamped legs, resistance wiring. No new placeholders.
2. **Wire `FieldBattlePanel` now** — player-involved battles pause and open the panel this arc.
3. **Army tokens are always visible** on the 6-mile map regardless of fog — player and NPC armies both. (Reconnaissance-driven visibility is a possible future refinement, not v1.)
4. **`withstand_siege` gets minimal real behavior** — wire to the existing siege path (defender posture, garrison defends from the stronghold); no new siege mechanics.

---

## 2. Phase map

| Phase | Deliverable | Depends on | Model |
|---|---|---|---|
| **A** ✅ **DONE 2026-07-04** | Battle/siege routing backbone: collision listener, `FieldBattlePanel` wiring, §8.1 conflict-hook caller (+ registered `ArmyMarcher`, wrote the missing `register_collision_listener` — see §3) | — | Opus |
| **B** ✅ **DONE 2026-07-04** | Extraction RAW core: full §4.3 (ExtractionResolver + encamped legs + marching rewrite + migration 183 ledger; UI orders now live — see §4) | — | Opus |
| **C** ✅ **DONE 2026-07-04** | Resistance seam: extraction flow ↔ §7.3 decision ↔ battle creation ↔ yield gate (`ExtractionResistanceRouter`; steps 4/5 flagged — see §5) | A, B | Opus |
| **D** ✅ **DONE 2026-07-04** | `call_to_arms` routing (→ `CallToArmsMuster` via `FavorsDutiesResolver.trigger_call_to_arms`) + `withstand_siege` (defender posture, migration 184) — both dispatch for real (see §6) | A | Opus |
| **E** ✅ **DONE 2026-07-04** | 6-mile map army layer: tokens, path overlay, context menu, supply gauge (built on the **3D** renderer — see §7) | — (parallel-safe) | ~~Sonnet~~ Opus |
| **F** ✅ **DONE 2026-07-04** | NPC siege initiation: `ThreatEscalationDriver` (challenger→siege/battle/pillage) + post-battle retreat→besiege (`BattleRetreatSiegeRouter`) — see §7½ | A, C, D | Opus |

A, B, and E are mutually independent and can be built in any order (E can even run in parallel in a worktree). C requires A + B. D requires A. F comes last — it consumes A's routing, C's resistance seam, and D's withstand_siege posture.

**Global definition of done:** an NPC army marching-loots across an NPC domain triggers a disposition-driven resistance decision; a resisted extraction produces a silent field battle whose outcome gates the yield; a player-involved collision pauses the scheduler and opens `FieldBattlePanel`; a besieged active-LOD ruler's `withstand_siege` action is a real dispatch; `call_to_arms` issues real muster calls; every army on the regional map renders a token; all suites green at the net-zero-new-failures bar; `build_log.md` updated each phase.

---

## 3. Phase A — Battle/siege routing backbone

**STATUS: DONE 2026-07-04 (Opus; suite 486/16 net-zero on two runs, MCP-verified).** See `build_log.md` 2026-07-04 and conventions §95. The "Current state" below under-described the work; the corrections shaped the build.

**⚠ CORRECTIONS (verified against code 2026-07-04 — this section named several things that did not exist):**
- **`BattleDispatcher.register_collision_listener()` / `unregister_collision_listener()` DID NOT EXIST** — named only in the class doc-comment + the §9 index. They were WRITTEN (static `.connect()` of `armies_collided` → a static `_on_armies_collided` that supplies `Timekeeping.get_calendar_day()` — the signal carries no day). The dispatch decision tree + resolvers are untouched.
- **`ArmyMarcher.register()` was called by NO production code** — the `army_travel_leg` handler was never in the live registry, so armies never completed marches AND `armies_collided` never fired in play. It is now registered at `SessionRunner.load_session` (this also makes Phase E marches actually resolve). "Follow `ArmyMarcher.register`'s pattern" (step 1) was misleading: that registers a *scheduler* handler, whereas the collision listener is an EventBus `.connect()`.
- **`field_battle_panel.tscn` DID NOT EXIST** and the panel builds its whole UI in code — created a 1-node scene (root `CanvasLayer` + script, `layer=90`), instantiated as a sibling of SessionRunner under Main.
- **Scheduler pause/resume was unwired end-to-end** and the silent-path **§7.6 world-log was unwired** — both built (not "verify"). `resolve_silently` (not `resolve_battle_silently`); `continue_battle` returns a dict and the panel drives synchronously.

**What was built (deltas from the plan below):** SessionRunner **owns** the scheduler pause/resume (keeps the panel UI-only) and keys it to the paused `battle_id` — a synchronous silent NPC-vs-NPC battle (the collision detector can emit several `armies_collided` in one loop) must not resume the clock out from under an open player panel. The immediate LOD sync lives in **SessionRunner** (on `battle_started`/`siege_started`), NOT inside the static `BattleDispatcher`/`SiegeDispatcher` — coupling them to `realm_ai` risks the forbidden decision-tree edits. `ConflictParticipants` returns raw NPC ids; `RulerLodManager._is_full_tier_npc` is the sole gate (named-tier bandit/challenger opponents dropped). `GameLog` subscribes `battle_concluded` → re-queries `BattleRepository` → a `combat` world-log line (§7.6, silent + player). **Acceptance bar met** (headless: `tests/test_battle_routing.gd`; the scheduler-paused + panel-visible parts are the MCP/manual checklist).

**Goal.** Make the already-built battle machinery reachable: collisions become battles, player battles open the UI, and conflicts feed the ruler-AI LOD hook.

**Spec refs.** `gdd-army-warfare.md` §4.7 (collision → battle), §6.11 (silent vs interactive paths), §7.4 (battle panel); `gdd-ruler-ai.md` §8.1–8.2 (conflict hook).

**Current state (verified 2026-07-04).**
- `ArmyCollisionDetector.detect_at_hex` (called from `army_marcher.gd:304` inside `_handle_army_travel_leg`) emits `EventBus.armies_collided` — **no listener exists**.
- `BattleDispatcher.dispatch_collision` and `register_collision_listener` (`engine/subsystems/armies/battle_dispatcher.gd`) have **no engine-side callers** — the only production callers are the player-choice buttons in `scenes/ui/notebook/domain/sub_tabs/encounters_threats_sub_tab.gd` (bandit/challenger dispatch, ~lines 599/633). Nothing routes march-time collisions.
- `scenes/ui/battle/field_battle_panel.gd` self-wires to `battle_pause_for_player` in `_ready()` but **nothing instantiates it** — no `.tscn` references it, no code `add_child`s it.
- `SiegeDispatcher.dispatch_new_siege` is called only from `scenes/ui/notebook/domain/sub_tabs/encounters_threats_sub_tab.gd` (lines 603, 636).
- `RulerLodManager.sync(campaign_id, scheduler, extra_ruler_ids, calendar_day)` — `extra_ruler_ids` is always `[]` (sole caller: `domain_handlers._handle_monthly_tick`).

**Build.**
1. **Collision listener registration.** Call `BattleDispatcher.register_collision_listener()` during session activation (beside the other handler registrations `SessionRunner` performs — follow `ArmyMarcher.register`'s pattern) and unregister on session end. Verify the dispatcher's silent path posts its outcome to the unified log per §7.6.
2. **`FieldBattlePanel` instantiation.** Create `scenes/ui/battle/field_battle_panel.tscn` (root `CanvasLayer` with the existing script) and instantiate it into the session UI tree wherever the other session-scoped panels live (inspect the session scene; follow the departure-modal / battle-adjacent panel precedent). Confirm the scheduler pauses on `battle_pause_for_player` and resumes on battle conclusion — the dispatcher's header says Phase 6A part 2 owed this pause wiring; it was never done.
3. **§8.1 conflict-hook caller (stateless design).** Add a small static helper (suggested: `engine/subsystems/realm_ai/conflict_participants.gd`, `ConflictParticipants.active_ruler_ids(campaign_id) -> Array`) that queries **non-concluded** `field_battles` and `sieges` rows for player-involved conflicts and returns the opposing NPC ruler ids. `domain_handlers._handle_monthly_tick` passes the result into `RulerLodManager.sync(..., extra_ruler_ids, ...)` each tick; `BattleDispatcher`/`SiegeDispatcher` additionally trigger an immediate `sync` with those ids when a player-involved conflict is created, so the opposing ruler is promoted the moment the fight starts, not at month end. Statelessness (re-derive from conflict rows) means no new persistence and no save/load reconciliation.

**Acceptance bar.** A hand-authored test: two NPC armies collide on a march → exactly one silent battle resolves and logs; a PC-involved collision → `field_battles` row, scheduler paused, panel visible; a player-involved battle promotes the opposing ruler through the full-tier gate (a `named`-tier ruler must NOT be promoted — §8.1 materialization safety); conflict conclusion demotes on the next sync via the normal grace path. Net-zero new suite failures.

**Paste-ready prompt.**
> Run the shared preamble from docs/handoff-army-warfare-seams.md §1, then execute Phase A (§3): register the BattleDispatcher collision listener at session activation, create and instantiate field_battle_panel.tscn with scheduler pause/resume wiring, and add the stateless ConflictParticipants helper feeding RulerLodManager.sync's extra_ruler_ids from live player-involved conflicts (immediate sync on conflict creation + every monthly tick). Do not modify BattleDispatcher's decision tree or the resolvers. Tests per §3 acceptance bar.

---

## 4. Phase B — Extraction RAW core (full §4.3)

**STATUS: DONE 2026-07-04 (Opus; suite 487/16 net-zero, RAW-verified, adversarial-reviewed).** See `build_log.md` 2026-07-04 and conventions §96. The §4 line-refs were accurate this time; the design deltas are below.

**Key decisions (RAW/design pass):**
- **Yield input = `domains.peasant_families`** (the per-hex `domain_hexes.families` column is 0 at runtime — M2b-1 deferral). The "100-family domain → 4000 gp" bar confirms the whole-domain count.
- **Per-domain `domain_extraction_ledger` (migration 183)** owns BOTH the 6-month requisition cooldown AND the 60 gp/family combined ceiling — the per-army `requisition_cooldowns_json` (inert) can't enforce cross-army per-domain limits. The ceiling resets each 6-month period (`period_anchor`; the "until population recovery" proxy).
- **Movement-halving (RAW L344) was documented-but-unapplied** — `compute_army_daily_miles` gained `extraction_mode` → ×0.5. The gp-into-cp unit bug is fixed (resolver credits cp via `XPAwardCalculator.bankers_round(gp × families × 100)`).
- **Marching pro-rate = base rate ÷ distinct leg domains** ({from,to}); requisition friendly-only, loot any. Encamped current-then-adjacent via `HexMapController.get_neighbors`, first eligible domain.
- **Resistance is a stubbed `ExtractionResolver._resistance_hook_phase_c` (returns true)** — the Phase-C call site (build item 4).
- **UI enabled:** flipped `PHASE_B_EXTRACTION_AVAILABLE=true`; the Phase-E extraction orders are live, gated on real eligibility (friendly + cooldown + ceiling via `ExtractionResolver.preview`); `execute_action` gained an `extraction_scheduler` param (encamped orders → `ExtractionScheduler.begin_*`).
- **Review-caught:** a supply-less army (bandit/challenger) must not charge a domain for an uncreditable yield (resolve guards the supply row up front); `preview()` must gate identically to `resolve()` (independent cooldown vs ceiling-period clocks).

**Goal.** Replace the extraction placeholder wholesale with the RAW subsystem: encamped Requisition/Loot activities, RAW-correct marching extraction, yields, cooldowns, family loss, and the combined ceiling. (The resistance decision is Phase C — this phase computes and credits; C gates.)

**Spec refs.** `gdd-army-warfare.md` §4.3 (whole — the requisition/loot rules block around lines 584–625), the state-machine notes for `requisitioning`/`looting` (lines ~149–152), and the scheduler contracts (lines ~1363–1365). RAW: `daw_campaigning_armies.xml` §requisition_and_looting L324–347 — requisition 40 gp/family, once per domain per 6 months (L327–330); loot 20 gp/family with 1 family lost per 20 gp (L334–336); combined 60 gp/family ceiling (L338); marching extraction single-hex-or-pro-rated (L343) with movement halved (L344); encamped current-then-adjacent geography (L345–346). **Re-verify every line via `acks-raw-lookup` before coding.**

**Current state (verified 2026-07-04).**
- `army_marcher._apply_marching_extraction` (lines ~321–344): flat 100 gp (requisition) / 50 gp (loot) per leg-hex, credited **as if cp** into `current_stockpile_cp` (unit bug), no domain lookup, no cooldown, no family loss, no ceiling.
- `requisition_leg` / `loot_leg` events: **do not exist anywhere in engine/**.
- `armies.state` values `'requisitioning'`/`'looting'`: schema CHECK only — nothing ever sets them.
- `army_supply_state.requisition_cooldowns_json`: column exists (`army_repository.gd:48`), **nothing reads or writes it**.

**Build.**
1. **Extraction resolver** (suggested: `engine/subsystems/armies/extraction_resolver.gd`, static): given (domain, mode, requested amount, calendar_day) → RAW yield in cp, cooldown check/stamp, family decrement for loot, per-domain 60 gp/family combined-ceiling enforcement (track per-domain extraction totals — decide persistence with the schema, likely a small `domain_extraction_ledger` table or columns on domains; migration required either way for ceiling tracking across armies). Banker's rounding at the gp→cp boundary.
2. **Encamped legs.** `requisition_leg` and `loot_leg` 7-day scheduled events mirroring `travel_leg`'s register/handle/cancel pattern in `army_marcher.gd` (a sibling service is fine — suggested `extraction_scheduler.gd`); set/clear `armies.state`; current-then-adjacent hex geography; credit on completion via the resolver; emit past-tense signals (suggested: `army_requisition_completed`, `army_loot_completed` — check EventBus for existing names first).
3. **Marching extraction rewrite.** `_apply_marching_extraction` delegates to the resolver: resolve which domain(s) own the leg hexes, apply single-hex-or-pro-rated allocation (L343), verify movement-halving for extraction legs is actually applied to leg duration (audit `ArmyMarcher.march_army` — there is NO `begin_march`; leg duration is computed there from `daily_miles`), stamp cooldowns on the domains actually extracted. Fix the gp/cp unit bug.
4. **Do not** wire resistance here — leave a clearly-marked call site for Phase C.

**Acceptance bar.** Golden tests: a 100-family domain yields exactly 4,000 gp-worth of cp on requisition and stamps its 6-month cooldown; a second requisition inside the window is rejected; loot on the same domain yields ≤ 20 gp/family, costs 1 family per 20 gp, and the domain's combined total can never exceed 60 gp/family until population recovery; marching pro-rate splits correctly across two domains with banker's rounding; encamped legs run 7 game-days, set and clear army state, and survive save/load mid-leg. Net-zero new failures.

**Paste-ready prompt.**
> Run the shared preamble from docs/handoff-army-warfare-seams.md §1, then execute Phase B (§4): build the RAW extraction resolver + encamped requisition_leg/loot_leg scheduled activities + the marching-extraction rewrite per gdd-army-warfare.md §4.3, re-verifying daw_campaigning_armies.xml L324–347 via acks-raw-lookup. Fix the gp-into-cp unit bug. Add ceiling-tracking persistence via a migration. Leave the resistance call site stubbed with a comment for Phase C. Tests per §4 acceptance bar.

---

## 5. Phase C — The resistance seam (extraction ↔ ruler-AI ↔ battle)

> ✅ **DONE 2026-07-04 (Opus; suite 488/16 net-zero on two consecutive runs; adversarial-reviewed, 4 confirmed bug-classes fixed).** NEW `engine/subsystems/armies/extraction_resistance_router.gd` (`ExtractionResistanceRouter`, static) is the seam: `should_proceed(domain,army,mode,day)` is the body `ExtractionResolver._resistance_hook_phase_c` delegates to. Flow: friendly short-circuit → per-day episode cache → player-domain GUARD (block + notify; step 4 flagged) → NPC owner `ExtractionResistanceHeuristic.evaluate` (§7.3, reused not re-derived) → on resist, materialise a defender levy (personal + responding-vassal garrisons) → `BattleDispatcher.dispatch_collision` → **gate the yield on the outcome** (silent = synchronous; interactive = block-this-attempt). Levy demobilised after a silent battle. Plus a `dispatch_collision` re-entrancy guard (`already_battling`) so the marcher's post-arrival collision re-scan can't duplicate the resistance battle, and a `reset_episode_cache()` on `SessionRunner.load_session`. Tests: `tests/test_extraction_resistance_router.gd` (id 491, 10 tests). Conventions §97. **Two items FLAGGED for Jedidiah, NOT implemented (build items 4 & 5 below):**
> - **Step 5 (lord-vassal henchman-morale) — RESOLVED via `acks-raw-lookup` RAW sweep (2026-07):** the henchman-morale roll is a **favors-&-duties** mechanic — it fires on *demanding duties / changing tribute* (`acore_axioms_strongholds_and_domains.xml:289` "changing a vassal's tribute always triggers a Henchman Loyalty roll"; `:352-355` duties beyond the safe limit; call-to-arms full-garrison = two duties `daw_armies_recruitment.xml:660`; taxing vassals `:707-708`), NOT on requisition/loot. RAW attaches **no** morale roll to extraction (the sole built-in lever is the domain leader's universal right to resist looting by battle, `daw_campaigning_armies.xml:342`; army-presence domain-morale penalties are enemy-scoped only, `acore:487-488`, and pillage's −4 is conquest-gated, `daw:812`). So the "looting a vassal triggers a henchman-morale roll" premise — which came from **GDD §4.3.3** (now corrected there; this note's earlier claim that §4.3.3 "has no such note" was wrong) — is **not RAW-grounded**, and the router's friendly-domain short-circuit is **RAW-faithful, not an omission**. **Jedidiah design call — RESOLVED 2026-07-06: NO bespoke consequence.** Looting a friendly vassal stays unopposed and self-punishing; no henchman roll, no alignment tick, no special vassal-resistance path. The RAW-faithful friendly short-circuit is final. (Declined options: alignment shift by analogy to enslaving-own-families `daw_armies_recruitment.xml:586`, or honoring the `:342` battle-resistance right vs one's liege.)
> - **Step 4 (player-as-defender resist surface):** the v1 guard blocks the auto-yield + emits a notification; a **persistent** threat-row needs a new `domain_threats.kind` (the CHECK enum + threats sub-tab render only 4 kinds) and a resist-choice modal that doesn't exist. Per this spec's own "stop and ask Jedidiah rather than inventing a modal", both are deferred to 10.4 (NPC marching extraction — the trigger — is also 10.4, so this path isn't reachable in play yet).

**Goal.** Close build-log item 10.4's core: an extraction against a domain triggers the domain owner's resistance decision, and a resist becomes a real battle whose outcome gates the yield. This is the integration test `gdd-ruler-ai.md` §12 demands: "Hostile army extracting → defensive_resistance federates vassals and resolves — outcome routes to army-warfare battle resolution."

**Spec refs.** `gdd-army-warfare.md` §4.3.3 (resistance; RAW L341–342: the domain leader may resist requisition or loot by fighting a battle; the lord-vassal henchman-morale note there is **superseded** — the RAW sweep found it not RAW-grounded, see the Step-5 note above); `gdd-ruler-ai.md` §7.3 (the disposition-modulated threshold — **already built**: `RulerCrisisResponder.resistance_threshold` + generalized `ExtractionResistanceHeuristic.evaluate`).

**Current state.** `DefensiveResistanceHandler` produces `{will_resist, evaluation}` + a ledger row and stops. Nothing calls it from the extraction flow; `will_resist == true` never musters an army or creates a battle. The heuristic computes federated BR but materializes nothing.

**Build.**
1. **Decision hook in the extraction flow.** Before crediting any extraction against a domain not owned by the extracting army's realm (use the existing friendly-territory predicate), resolve the domain owner and obtain the resistance decision: NPC owners route through `ExtractionResistanceHeuristic.evaluate` with the §7.3 opts (`RulerDispositionRepository.get_disposition`, `defending_own_stronghold=false`); the decision is cached per (domain, army, extraction episode) so a pro-rated march doesn't re-roll per hex.
2. **Materialize the response force.** On resist: create a defender army from the personal-domain garrison + committed federated vassal garrisons (follow `CallToArmsMuster._create_lord_call_army`'s creation pattern; loyalty rolls and `vassal_revolted` emission stay inside the existing heuristic machinery — do not duplicate them). Place it at the extraction hex.
3. **Route to battle.** `BattleDispatcher.dispatch_collision(extractor, defender, hex, day)` — silent for NPC-vs-NPC, interactive (Phase A wiring) when the player is involved. **Outcome gates the yield:** extractor wins → extraction proceeds (and the defender army disperses back to garrisons per the resolver's outcome handling); defender wins → extraction blocked for that episode; apply the resolver's normal casualty/retreat consequences. No new battle mechanics.
4. **Player as defender.** When an NPC army extracts from the **player's** domain, do not auto-decide: surface it through the existing threat/notification path (threat row + unified log + auto_pause per the player-domain convention) so the player chooses resistance via the existing threats sub-tab flow. If no clean surface exists for the "resist?" choice, **stop and ask Jedidiah** rather than inventing a new modal.
5. **Lord-vassal case.** ~~A lord's army looting its own vassal's domain: run the henchman-morale roll before the vassal's resistance commitment~~ — **RESOLVED (see the Step-5 note above): the RAW sweep confirmed the henchman-morale roll is a favors-&-duties mechanic, NOT a loot one, so no roll is run.** The friendly-domain short-circuit is RAW-faithful; any bespoke lord-loots-vassal consequence is a narrowed Jedidiah design call, not a required RAW step.

**Acceptance bar.** Integration tests: aggressive-disposition NPC ruler resists at 30% BR and a silent battle fires whose loser's extraction is blocked/permitted accordingly; cautious ruler declines at exactly 50% (regression anchor intact — the untouched `ExtractionResistanceHeuristic` suites must stay green); pro-rated march triggers at most one decision per domain per episode; player-domain extraction pauses and surfaces a threat without auto-resolving. Net-zero new failures.

**Paste-ready prompt.**
> Run the shared preamble from docs/handoff-army-warfare-seams.md §1, then execute Phase C (§5): wire the Phase-B extraction flow to the §7.3 resistance decision (existing heuristic + disposition opts — do NOT reimplement), materialize the federated response army on resist, route it through BattleDispatcher, and gate the yield on the outcome. Player-defender extraction surfaces via the existing threat path and pauses; ask Jedidiah if no clean resist-choice surface exists. Use Opus. Tests per §5 acceptance bar.

---

## 6. Phase D — `call_to_arms` routing + `withstand_siege` minimal behavior

> ✅ **DONE 2026-07-04 (Opus; suite 489/16 net-zero; adversarial-reviewed, 2 confirmed bugs fixed).** `RulerAI._execute` now dispatches both: `call_to_arms` routes each vassal through the NEW public `FavorsDutiesResolver.trigger_call_to_arms` (which delegates to the existing `_apply_obligation` — reusing obligation creation + the cumulative safe-total loyalty machinery, not re-implementing it) into `CallToArmsMuster.issue_call` at the RAW-minimum 50% magnitude, merging vassals into one lord army; `withstand_siege` sets `defender_posture='hold_fast'` on EVERY active siege on the domain (migration 184 added the column; the siege resolver's voluntary `sally` branch refuses a `hold_fast` defender — the ONLY place it reads the posture; blockade/reduction/assault unchanged) and cancels the ruler's marching orders at each siege hex. `_NO_DISPATCH` is now just `["hold"]`; a `scheduler` is threaded `process_campaign_month → _take_turn → _execute` (from `_runner.get_scheduler()`) for tranche/march events. Both return `{dispatched:true, ...}`. Tests: `tests/test_ruler_dispatch_phase_d.gd` (id 492, 8 tests). Conventions §98. **Note:** the `withstand_siege` "hold, no sortie" posture is PROJECT-DESIGNED — `daw_sieges.xml` does not forbid a defender sortie — sanctioned as this spec's "minimal per Jedidiah's decision"; the 50% call magnitude is RAW-minimum (crisis-posture magnitude scaling deferred).

**Goal.** Close the remaining two ruler-AI dispatch stubs.

**Spec refs.** `gdd-ruler-ai.md` §5.3 (both actions); `rules/acore_axioms_strongholds_and_domains.xml:352-391` (favors & duties), `:286-397` + `acore_equipment.xml:795-840` (loyalty constraints — re-verify); `daw_sieges.xml` for defender conduct (re-verify via `acks-raw-lookup`).

**Current state.** `RulerAI._dispatch` returns `{"summary": "call_to_arms: routing lands with Phase 3", "dispatched": false}` (`ruler_ai.gd:276-279`); `withstand_siege` sits in `_NO_DISPATCH` (`ruler_ai.gd:35`). `CallToArmsMuster.issue_call(obligation_id, lord_id, vassal_id, calendar_day, magnitude_pct, scheduler, lord_army_id_override)` is fully built (tranches, muster periods by title, `call_to_arms_state` persistence) and routed today only through `FavorsDutiesResolver`.

**Build.**
1. **`call_to_arms` dispatch.** In `RulerAI._dispatch`, route through the favors-and-duties layer: for each of the ruler's vassals in muster range, create/locate the duty obligation row the way `FavorsDutiesResolver` does (the planner *triggers* duties, it does not re-implement the table — `gdd-ruler-ai.md` §2.5), then `CallToArmsMuster.issue_call(...)` with a defensive magnitude (PROJECT CALL; suggest 50% default, crisis-posture-scaled — document the constant). Respect loyalty: duties beyond the safe total trigger the existing cumulative loyalty-check machinery — reuse, don't duplicate. The mustered force should merge toward the ruler's defense (use `lord_army_id_override` when a defender army from Phase C already exists).
2. **`withstand_siege` dispatch.** Remove from `_NO_DISPATCH`; new handler behavior (minimal per Jedidiah's decision): when the ruler's domain has a non-concluded siege, set the defender's posture on the siege row (garrison defends from inside the stronghold; no sortie), cancel any marching orders for the ruler's own armies at that hex, and let the **existing** siege resolvers do everything else. Inspect `siege_resolver.gd`/`siege_repository.gd` for the defender-side hooks that already exist; if the siege rows have no defender-posture concept at all, add the minimal column via migration and have the resolvers read it only where they already branch on defender behavior. Do not add new siege mechanics (no new repair/sortie systems — `manage_stronghold` already covers repair).
3. Both actions' outcomes must be real dispatch dicts (`dispatched: true`, structured summary) so Seam-A narration and the `ruler_action_taken` log line carry engine truth.

**Acceptance bar.** A besieged active ruler with vassals: `call_to_arms` creates real `call_to_arms_state` rows with correct tranche scheduling and loyalty checks fire beyond the safe total; `withstand_siege` sets defender posture and the siege proceeds through the existing resolver unchanged; both emit `ruler_action_taken` with `dispatched: true`. The §7.1 crisis biases already prioritize these actions — verify the end-to-end pick under a fielded threat. Net-zero new failures.

**Paste-ready prompt.**
> Run the shared preamble from docs/handoff-army-warfare-seams.md §1, then execute Phase D (§6): route RulerAI's call_to_arms through the favors-and-duties layer into CallToArmsMuster.issue_call (reuse loyalty machinery; 50% defensive magnitude default, documented), and give withstand_siege minimal real dispatch (defender posture on the existing siege row; no new siege mechanics). Re-verify loyalty and siege RAW via acks-raw-lookup. Tests per §6 acceptance bar.

---

## 7. Phase E — 6-mile map army layer (tokens, paths, orders)

**STATUS: DONE 2026-07-04 (Opus; suite 485/16 net-zero, MCP-verified).** Details in `build_log.md` 2026-07-04 and conventions §94. The build corrected the renderer assumption this section originally carried — see the correction below.

**⚠ RENDERER CORRECTION (verified against code 2026-07-04 — this section originally named the wrong renderer).** The LIVE regional (6-mile) renderer is **`scenes/maps/hex_map_renderer_3d.gd` (a `Node3D`)**, NOT the 2D `hex_map_renderer.gd`. `project.godot` `rendering/wilderness_hex_mode="heightmap_3d"` makes `SessionRunner._maybe_swap_wilderness_3d()` rename + `queue_free()` the 2D `HexMap` at boot and swap in the 3D scene (renamed `HexMap`, at `Main/WorldViewport/WorldSubViewport/HexMap`). The 2D `hex_map_renderer.gd` + `HexMapLandmarkIcons` are **DEAD CODE** under the live flag. The army layer was therefore built as a **3D overlay on the live renderer** (Node3D markers at `WildernessHexMath.axial_to_world(coord)` + `_hex_height`), NOT a Node2D layer mirroring `hex_map_landmark_icons.gd`. **Any later phase (A/F) that instantiates a UI panel into "the session UI tree" or touches the wilderness map uses the 3D renderer.**

**Goal.** Armies exist on the map. Build the on-map army presence the GDD promises: "An army on the wilderness hex map has a token, a path overlay, a current order, and a supply gauge."

**Spec refs.** `gdd-army-warfare.md` §7.1 state-badge palette (line ~1226: assembling gray, encamped blue, marching amber, requisitioning green, looting dark-red, besieging purple, battling red, withdrawing orange, disbanded strikethrough); §7.3 on-map tokens (line ~1254: rendered at `armies.hex_q/hex_r`, 40px vs the 28px party token, unit-count badge, state-color border, selected army shows an animated dashed path overlay along the planned `travel_leg` path); §7.3 context-menu order table (lines ~1256–1271) and §4.3.4 eligibility tooltips (lines ~615–625).

**What was built** (files enumerated in `build_log.md` 2026-07-04):
1. **`ArmyMapPresence`** (`engine/subsystems/armies/army_map_presence.gd`, RefCounted / static, headless-tested) — the pure-logic token model the renderer renders: `list_tokens_for_map(map_id)` (non-`disbanded` + positioned armies; **fog ignored** — always visible per Jedidiah 2026-07-04, player AND NPC), `composition` (unit-count / BR / troops), `is_player_owned` (PC or PC-henchman — stricter than the siege PC-associate predicate, which also counts NPC vassals), `border_color_for_state` (§7.1 palette), `supply_gauge` (weeks + green/amber/red bands). The `scenes/` renderer is a thin layer over this so the headless suite exercises the gating logic.
2. **3D overlay** in `hex_map_renderer_3d.gd`: an `_army_root` Node3D layer (alongside `_token_root`); tokens = state-color border disc + owner-tint cylinder + billboarded `Label3D` count badge; `signal army_token_clicked(army_id, coord)`; left-click selection (scale-up highlight); `set_army_path_overlay` animated dashed segment (the single in-flight `army_travel_leg`, read from the live `EventScheduler.get_events_for_owner(army_id)` — there is NO stored multi-hex route); co-located armies fan out + cycle on repeated clicks. **Signal-driven refresh, no polling**: `army_formed`/`army_disbanded`/`battle_concluded`/`armies_collided`/`army_supply_cut` → rebuild; `army_arrived_at_hex` → rebuild + clear stale path; `order_queued` filtered to `event_type == "army_travel_leg"` → rebuild (the ONLY hook for the encamped→marching recolor — there is no `army_state_changed` signal).
3. **Context menu** (`scenes/ui/troops/army_marching_context_menu.gd`, `ArmyMarchingContextMenu`, headless-tested) — full §7.3 order set with eligibility + disabled-state tooltips: March / Forced / Cautious gated on hex ADJACENCY (armies move one 6-mile hex per leg); the extraction orders (March+Requisition, March+Loot, Requisition-here, Loot-here) are DISABLED behind `PHASE_B_EXTRACTION_AVAILABLE=false` with a Phase-B tooltip until Phase B lands — **flip that flag when Phase B's resolver + `requisition_leg`/`loot_leg` land**. Dispatches via `ArmyMarcher.march_army(army_id, dest_q, dest_r, current_time, scheduler, march_mode, extraction_mode)` — **NOTE: there is NO `begin_march`** (the real entry point is `march_army`; `march_mode ∈ normal|forced|cautious`, `extraction_mode ∈ none|requisition|loot`, the leg carries the extraction mode) — and `ArmyDisbander.disband`. NPC armies: read-only inspect via `army_detail_panel.display(army_id, read_only=true)`.
4. **Supply gauge** (`scenes/ui/components/army_supply_gauge.gd`) on selection — `current_stockpile_cp` vs weekly cost as a weeks-of-supply green/amber/red `_draw()` bar (`Currency.format_cost` at the UI boundary).

**Acceptance bar (met).** 485/16 net-zero; `ArmyMapPresence` + menu builder + read-only detail panel headless-tested; a godot-ai MCP smoke confirmed the 3D renderer loads and `_rebuild_armies` runs clean on a real campaign; an adversarial review found + fixed 2 logic defects (co-located-army index collapse; stale NPC inspect panel on re-select). Token visual/interaction items (render, move-on-arrival, path-when-selected, state-border tracking, menu gating, NPC inspect, always-visible-over-fog) are the manual checklist in the build log — they need a campaign with a fielded army (which Phases A–F naturally produce).

**Original paste-ready prompt (COMPLETE — corrected for the record).**
> Run the shared preamble from docs/handoff-army-warfare-seams.md §1, then execute Phase E (§7): build the army-token layer as a **3D overlay on the LIVE renderer `scenes/maps/hex_map_renderer_3d.gd`** (40px tokens, unit-count badge, §7 state-color borders, always visible regardless of fog per Jedidiah 2026-07-04), selection + animated path overlay, the player-army context menu with GDD eligibility gating/tooltips, and the supply gauge on selection. Signal-driven refresh, no polling. Split the pure-logic token model + menu builder into headless-testable RefCounted classes (the scenes/ layer is not loaded by the suite). Tests + manual checklist per §7 acceptance bar.

---

## 7½. Phase F — NPC siege initiation (threat escalation driver)

> ✅ **DONE 2026-07-04 (Opus; suite 490/16 net-zero; adversarial-reviewed, 3 confirmed fixes).** **Route 1** — NEW `engine/subsystems/domains/threat_escalation_driver.gd` (`ThreatEscalationDriver`, static) runs in the monthly tick after RulerAI, for each active-LOD NPC ruler's personal domain: fields an `npc_challenger` via `materialize_challenger_as_army`, routes the defender's accept/refuse through `ExtractionResistanceHeuristic.evaluate` (§7.3), and mirrors the threats-sub-tab dispatch (accept → `SiegeDispatcher.dispatch_new_siege` / `BattleDispatcher.dispatch_collision`; refuse → RAW `morale_penalty=4` pillage), idempotent via `payload_json`. Guards fall out of iterating `active_ruler_ids` (NPC/active-LOD only; player + backdrop excluded) + only `npc_challenger` (bandit swarms never siege, §4.10.4). **Route 2** — NEW `engine/subsystems/armies/battle_retreat_siege_router.gd` (`BattleRetreatSiegeRouter`, static): FIXED `RetreatResolver._find_friendly_stronghold_at` (was a dead placeholder → now detects a co-located stronghold, so `retreated_into_stronghold` fires); `_resolve_post_battle_state` emits `battle_loser_retreated_into_stronghold`; a SessionRunner-owned router decides — player victor → `siege_decision_required` (no auto-siege), NPC victor → heuristic (supply ≥ 2 weeks AND hostile-unless-friendly) → `dispatch_new_siege`. New signals `threat_escalated` / `battle_loser_retreated_into_stronghold` / `siege_decision_required`; GameLog surfaces `threat_escalated`. Tests: `tests/test_phase_f_npc_siege.gd` (id 493, 8). Conventions §99. **Flagged:** the player-victor Besiege/Encamp/March-on MODAL is deferred (the signal + notification fire; the player besieges via existing UI); `materialize_challenger_as_army` yields a unit-less challenger army (pre-existing gap → an NPC domain with any garrison always accepts). **This completes the army-warfare-seams arc (A-F).**

**Goal.** NPC armies gain their organic routes into sieges, per the new spec at `gdd-army-warfare.md` **§4.10** (added 2026-07-04 — read it in full; it is the authority for this phase).

**Spec refs.** `gdd-army-warfare.md` §4.10 (whole). RAW: `acore_axioms_strongholds_and_domains.xml:623-634` (challenger offers battle; refusal → pillage −4); `daw_axioms_pitching_battle.xml:563-575` (retreat into stronghold; victor may besiege); `daw_campaigning_armies.xml:764-776` (conquest motive). Re-verify all via `acks-raw-lookup`.

**Current state (verified 2026-07-04).** `materialize_challenger_as_army` / `materialize_swarm_as_army` are called only from the player threats sub-tab; NPC-domain challenger threat rows emerge but sit unfielded forever; no battle-outcome path offers the victor a siege.

**Build.**
1. **`ThreatEscalationDriver`** (`engine/subsystems/domains/threat_escalation_driver.gd`, static, seeded per (threat, calendar_month)): runs in the monthly tick **after** `RulerAI.process_campaign_month`, **only** for NPC-owned domains in the ruler-AI active-LOD set. Per §4.10.2: field unfielded challengers → resolve the defender's accept/refuse via the existing §7.3 resistance evaluate → accept dispatches through `SiegeDispatcher`/`BattleDispatcher` mirroring the threats-sub-tab pattern; refuse stamps `morale_penalty = 4` and re-offers monthly. Bookkeeping in the threat row's `payload_json`.
2. **Route 2 post-battle hook.** In the battle-conclusion path: loser with a friendly stronghold/settlement in the hex may retreat into it; then player victor gets the Besiege / Encamp / March-on prompt (decision-required, auto-pause per §4.9.3); NPC victor besieges iff live hostile intent + ≥2 weeks supply (§4.10.3 heuristic — constants documented and tunable).
3. **Signal** `threat_escalated(threat_id, domain_id, stage)` in EventBus; unified-log lines for each stage; escalation sieges/battles feed `ConflictParticipants` like any other conflict.
4. **Guards:** never run for player domains (their UI choice stands), never for backdrop domains, never as a ruler-planner action (§4.10.1 scope guard — ruler-AI v1 stays defense-only). Bandit swarms never initiate sieges (§4.10.4).

**Acceptance bar.** Hand-authored scenario: an active-LOD NPC domain at Rebellious morale spawns a challenger → next monthly tick fields it and the aggressive-disposition defender accepts (silent siege via the simplified path when a stronghold exists; field battle otherwise); a cautious defender below threshold refuses and takes the −4 pillage penalty, re-offered next month; a backdrop domain's challenger stays unfielded; a player-domain challenger is untouched by the driver; post-battle retreat into a stronghold offers the player victor the prompt and the NPC victor besieges only when the intent+supply heuristic passes. Net-zero new failures.

**Paste-ready prompt.**
> Run the shared preamble from docs/handoff-army-warfare-seams.md §1, then execute Phase F (§7½): implement gdd-army-warfare.md §4.10 — the ThreatEscalationDriver (active-LOD NPC domains only, after RulerAI in the monthly tick; challenger fielding, §7.3-driven accept/refuse, RAW pillage on refusal) and the post-battle retreat-into-stronghold → victor-may-besiege route with the player prompt and the NPC intent+supply heuristic. Re-verify the RAW citations via acks-raw-lookup. Honor every §4.10.1/§4.10.4 scope guard. Tests per acceptance bar.

---

## 8. After all phases

> ✅ **ARC COMPLETE 2026-07-04.** All six phases (A-F) + the capstone landed (final suite 491/16 net-zero).

- ✅ **Ran the ruler-AI §12 integration scenario end-to-end** (hostile army extracting → resistance → battle → outcome) — `tests/test_ruler_ai_capstone.gd` (id 494): the vassal federation is DECISIVE (a lord below threshold alone resists only via the federated vassal), resolves as a real `field_battles` battle, and the outcome gates the loot yield; a control lord without a vassal concedes.
- ✅ **build-log 10.4 is fully closed** — 10.4.1 extraction routing (Phase B), 10.4.2 call_to_arms routing (Phase D), 10.4.3 §8.1 conflict hook (Phase A), 10.4.4 resistance seam (Phase C), 10.4.5 §12 integration (capstone) all landed. Noted in the build log.
- ✅ **Conventions pass:** new signal names, the extraction-episode concept, the defender-posture column, the ConflictParticipants pattern, and the Phase F escalation patterns are in `docs/coding_conventions.md` §94-99.
- **Flag for Jedidiah** (decision items, not build tasks):
  - ~~GDD money-column names~~ — DONE 2026-07-04 (unified-cp alignment pass, `gdd-army-warfare.md` §11).
  - ~~NPC-initiated sieges~~ — SPEC'D 2026-07-04 as `gdd-army-warfare.md` §4.10 / Phase F above. Remaining Jedidiah call from that spec: should NPC-domain **bandit swarms** ever escalate to sieges the way the player threats UI allows? (§4.10.4 default: no.)
  - Heroic foray still resolves via the silent simulator (v1 design choice per §6.3) — revisit when the combat UI arc reaches it.
  - Reconnaissance-driven army visibility (fog refinement over the always-visible v1 rule) — future design if wanted.

## 9. Quick interface index (verify against code before relying on it)

- `BattleDispatcher.dispatch_collision(army_a_id, army_b_id, hex_q, hex_r, calendar_day, dice_roller=Callable()) -> {battle_id, mode, outcome}`; `register_collision_listener()` / `unregister_collision_listener()`.
- `SiegeDispatcher.dispatch_new_siege(besieging_army_id, stronghold_id, defending_army_id, calendar_day, scheduler, weeks_of_warning=0, site="") -> {siege_id, mode}`.
- `CallToArmsMuster.issue_call(obligation_id, lord_id, vassal_id, calendar_day, magnitude_pct=50, scheduler=null, lord_army_id_override="") -> state_id`.
- `ExtractionResistanceHeuristic.evaluate(domain_id, attacker_army_id, calendar_day, dice=null, opts={disposition, defending_own_stronghold}) -> {will_resist, available_br, attacker_br, threshold_ratio, ...}`.
- `DefensiveResistanceHandler.on_complete(state, _runner) -> {summary, will_resist, evaluation}`.
- `RulerLodManager.sync(campaign_id, scheduler=null, extra_ruler_ids=[], calendar_day=-1) -> {active, promoted, demoted}` — full-tier gate is inviolable.
- `RulerAI._dispatch` — the `call_to_arms` stub at `ruler_ai.gd:276-279`; `_NO_DISPATCH` at `:35`.
- `army_marcher.gd` — `EVENT_ARMY_TRAVEL_LEG`, `register/unregister`, `_handle_army_travel_leg`, `_apply_marching_extraction` (placeholder, lines ~321–344).
- EventBus army/battle/siege signal block: `event_bus.gd` ~1202–1564 (`armies_collided` :1227, `battle_pause_for_player` :1270).
