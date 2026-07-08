# Build Handoff — Dialogue Phase 3 (The World Stage) + Quest-Rumor Q-5 (dialogue quest adapters)

**Authoring session:** 2026-07-08 (Opus recon). **Track B of Wave 2** in `docs/master-build-plan-social-llm-stack.md` §4.
**Model guidance:** Opus-leaning (request_action matrix, ruler-audience adjudication, army-parley evidence stacking, the deterministic lie engine); one build agent runs P3.0 → P3.4 + Q-5 sequentially. Q-5 is co-located here because it adds dialogue *moves* to the same catalog/dispatch files P3 touches — building both in one agent avoids a same-file merge conflict with a separate Q-5 track.

> **CRITICAL — do NOT run tests.** Parallel-wave build. No Godot headless, no godot-ai MCP, no test runner (concurrent Godot crashes on the shared `user://` DB). Syntax-check scene/subsystem scripts with `--check-only -s res://<file>` ONLY (single-shot). The orchestrator runs the full suite centrally after all Wave-2 agents finish. **Commit at the end and report the commit SHA.**

---

## 0. Shared preamble (read before writing code)

1. `CLAUDE.md` (authority; Godot/SQLite; banker's rounding via `MathUtils.bankers_round`; `class_name` NOT in autoloads; null-safe coercion — use the existing `_s(v, default)` helper pattern, NEVER `String(null)`).
2. `acks-conventions --for-task "dialogue request_action ruler audience army parley lying charm defection"` and §106–110 (Wave-0/1 dialogue conventions: two-track model, tone-scoped RAW modifiers, the P2 session-state shape).
3. `generation/gdd-npc-dialogue.md` — the authority. Implement: **§10 (Talking NPCs into Actions — the whole section)**, **§9.4 (Lying)**, **§5.5 (capability registry) + §5.6 (NPC-side intent policy & effects-vs-PCs, incl. charm defection)**, §6.5 (per-issue reactions — the resolution spine, already built by P2's `PerIssueResolver`), §13.11 (demeanor-beat channel). §16 Phase-3 line is the scope contract; §17 lists the PROJECT-CALL residuals.
4. `docs/handoff-quest-rumor-build.md` §7 (Q-5) + §10 (interface index).
5. RAW via `acks-raw-lookup`: charm "acts to protect its friend" `acore_spell_catalog_a-i_summary.xml:191`; reaction/parley `ax_reactions` (intimidation evidence lines :167-205, seduction :243-324, surprise-forces-least-favorable :68); friendly-monster cooperation `acore_adventures:957-962`.

### What is P3 vs P4 (do NOT overreach)

P3 delivers (per §16): `request_action` matrix; ruler audience + Seam-B packet; army pre-battle parley; post-combat surrender re-entry; **lying**; capability registry player-side, then **NPC-side intent policy + effects-vs-PCs including charm defection in the combat roster**. **All on the mock/template provider.**

**P4 (NOT this build)** owns: live LLM provider wiring, prompt assembly + validators, henchman interjections, LLM summarization, the capability test harness. P3 produces the *engine decisions* (which reply is a lie, which NPC move fires, what the demeanor beat is); P4 later makes the LLM *perform* them. Everything P3 builds must run fully on the deterministic template path — the lie content, the beat, the NPC move are all engine-authored here.

### Reuse, don't reinvent (P1/P2 built these)

- `dialogue_session.gd::submit_move(move_id, free_text, params) -> Dictionary` — the single dispatch entry. Add new move handlers here.
- `dialogue_move_catalog.gd` + `data/dialogue/move_catalog.json` — the data-defined move registry with the §5.3 gating layers. Add new move rows to the JSON; extend `eligible_moves` gating only where a new gate is needed (e.g., `request_action` needs `requestable_actions` non-empty; ruler/army moves gate on context flags).
- `per_issue_resolver.gd` (`PerIssueResolver`) — the §6.5 per-issue reaction roll (the resolution spine for EVERY `request_action`, parley demand, and ruler ask). **Reuse it; do not re-roll reactions by hand.**
- `npc_reply_planner.gd::plan_reply(npc_id, outcome) -> Dictionary` — extend for the lie decision + demeanor beat (do not fork).
- `interaction_resolver.gd` (`InteractionResolver`) — Track-1 tone (diplomatic/intimidation/seduction stacks) for parley demands that resolve as intimidation/diplomatic.
- `status_profile_builder.gd` / `StatusProfile` — evidence assembler feeding rolls (P2).
- `RulerStrategyReassessor.reassess(ruler_npc_id, trigger, ...)` + `apply_validated`/`consume_pending`/`validate_suggestion` (`engine/subsystems/realm_ai/ruler_strategy_reassessor.gd`) — **the Seam-B entry point for the ruler audience. Do NOT relax its validation** (strict-reject of unknown action keys is load-bearing).
- `RulerActionCatalog` — the valid `target_action_id` set for `persuade_ruler`.
- Army-warfare: `docs/handoff-army-warfare-seams.md` — `command_character_id`, the §6 pre-battle pause, battle/siege event owners. `event_bus.gd` already carries a `"parley"` collision choice (event_bus.gd:302) and a Phase-3 per-issue-grant signal stub (event_bus.gd:2116) — wire to those.
- `EventScheduler.cancel_all_for_owner()` — for dissuade/parley battle-event cancellation.
- `combat_roster.gd` + `combatant.gd` — where charm-defection side-switching lands (see P3.4).

### Migrations

`npc_memories` already carries the `deception_by_npc` + `deception_suffered` kinds (migration 191). `requestable_actions` is a **data-defined matrix** (JSON), charm defection is **in-memory combat state**, the Seam-B reassessor exists. **Therefore P3 + Q-5 should add ZERO migrations.** If you genuinely need one (e.g., a persisted charm-awareness flag, or a `requestable_actions` cache), assign it in the **198–200** range, doc-sync `db/schema.sql`, and register any new table.

---

## 1. Session map

| Session | Delivers | Key GDD |
|---|---|---|
| **Q-5** Quest adapters | the five quest/rumor moves wired to the registries (attitude-gated) | §9.1–§9.3, §11.1; quest-rumor §7 |
| **P3.0** `request_action` matrix | `requestable_actions` computation; the resolution template (attitude → per-issue → offer_terms → subsystem handoff → EventScheduler) | §10.1, §10.2 |
| **P3.1** Ruler audience (Seam B) | `persuade_ruler(packet)`; adjudication → `persuasion_strength`; dissuade/urge effects; wire to `RulerStrategyReassessor` | §10.3 |
| **P3.2** Army parley + surrender | `demand_surrender`/`demand_tribute`/`offer_passage`/`offer_terms` at collision; success-tier battle-event cancel/schedule; post-combat surrender re-entry | §10.4, §12.2, §16 |
| **P3.3** Lying | deterministic lie decision + engine-side fabrication; demeanor-beat + composure; `deception_by_npc` memory; deduction-not-a-die | §9.4, §13.11 |
| **P3.4** Capabilities + NPC intent | player-side capability registry; `NpcIntentPolicy` + NPC move vocab; effects-vs-PCs; **charm defection (combat-roster side-switch)** | §5.5, §5.6 |

---

## 2. Session Q-5 — Dialogue quest adapters

Wire the five moves to the already-built registries (Q-1/Q-4). **No adjudication in dialogue** — dialogue initiates; the registries own state. Add the move rows to `move_catalog.json` and handlers in `submit_move`.

- `quest_ask` → `QuestRegistry.offerable_quests(npc_id, party_id, attitude)` — **attitude-gated:** Friendly unlocks `personal`-posting; Neutral only `posted`/`broadcast` (§9.3).
- `quest_accept` → `QuestRegistry.accept(quest_id, pc_id, calendar_day)`; `quest_decline` → `QuestRegistry.decline(quest_id, party_id)`.
- `quest_turn_in` → `QuestRegistry.can_turn_in(quest_id)` then `disburse_reward(quest_id, recipient_pc_id, ...)` with **reward-recipient selection** (§9.6).
- `ask_rumor` → `RumorRegistry.share_for_npc(npc_id, party_id, attitude, topic?)` — one eligible rumor **per band**. (The Phase-1 `ask_rumor` stub-pool move exists; replace its stub body with the real registry call, keep the catalog gating.)
- Perform `questgiver_dialogue`/`completion_dialogue` through `plan_reply` (mock template). Emit the Q-1 signals (`quest_offered`/`quest_accepted`/`quest_turned_in`/`rumor_heard`).

**Note the background task:** a separate local session (`task_744ef743`) is fixing a Phase-1 `ask_rumor` resolution-key mismatch. If you touch `ask_rumor`, keep your change additive (swap the stub pool for `share_for_npc`); the orchestrator will reconcile if both land.

---

## 3. Session P3.0 — the `request_action` matrix

**`requestable_actions(npc)`** — computed from class, level, role, proficiencies (§10.1 v1 matrix): `cast_spell_for_hire`, `research_spell`/`craft_magic_item`, `perform_hijink(type)`, `sage_research(topic)`, `carry_message`/`broker_introduction`, `join_fight`, `trade_venture`, `ruler_action(action_id)` (§10.3), `commander_order(order_id)` (§10.4). Store the eligibility rules as a **data-defined matrix** (`data/dialogue/requestable_actions.json`) keyed by the class/role/proficiency predicate + the owning-subsystem handoff target + the RAW anchor.

**Resolution template (every row):** attitude gate (§6.4) → **`PerIssueResolver` per-issue reaction roll** (§6.5) with an `offer_terms` negotiation where payment applies → **deterministic handoff to the owning subsystem** → `EventScheduler` carries any deferred completion. Refusals persist in `npc_issues` and retry on the per-issue ladder. **Dialogue initiates; the owning subsystem executes and owns the outcome** — dialogue never resolves the spell/hijink/research itself.

**The two hard rules (§10.2, non-negotiable):** (1) every `request_action` id must exist in the registry — LLM-suggested actions are schema-validated and rejected if unknown; (2) persuasion applies *situational modifiers* and *event cancellations* only — it never rewrites `StrategicDisposition`, personality axes, or morale.

`request_action` surfaces in the menu only when `requestable_actions(npc)` is non-empty (extend `eligible_moves` with that gate).

---

## 4. Session P3.1 — persuading rulers (Seam B, concrete)

A ruler audience exposes **`persuade_ruler(packet)`**:
```gdscript
{ target_action_id: "call_to_arms",   # MUST exist in RulerActionCatalog
  direction: "dissuade" | "urge",
  persuasion_strength: float,          # 0.0–1.0, computed below
  terms: {...},                        # tribute, favors, hostages
  expires_after_months: 1 }            # temporary by rule 10.2
```

**Adjudication → strength (deterministic).** A fresh per-issue reaction roll (`PerIssueResolver`, the archetypal *extraordinary issue*) with relationship tone as modifier. `persuasion_strength` = issue-band base (accepts-with-enthusiasm 0.8 / accepts 0.6 / negotiable-then-agreed 0.4) + terms conceded (+0.1 per meaningful concession, capped) + ruler `crisis_response` (diplomatic +0.2, aggressive −0.2). Asking against kin/faith/realm interest fires the §6.6 offense triggers. Constants PROJECT CALL.

**Effects.**
- `dissuade`: matching scheduled events (`invasion_preparation`, `call_to_arms`) cancelled via `EventScheduler.cancel_all_for_owner()` if strength ≥ 0.6, else postponed; the action's utility gets a `×(1 − 0.7·strength)` situational modifier next scoring cycle; emit `ruler_strategy_reassessed(ruler_npc_id, "player_parley", changes)`.
- `urge`: **v1 supports urging only actions in the v1 catalog** (defensive/economic — e.g., urge a liege to garrison a threatened march). Urging *offensive war* is ruler-AI v2 — reserve the packet shape, refuse gracefully, and flag in the build log (§10.3, §17).

**Wire to Seam B:** route through `RulerStrategyReassessor.reassess(ruler_npc_id, "player_parley", ...)` / `apply_validated`. **Do NOT relax its validation** — an unknown `target_action_id` must be strict-rejected exactly as the existing Seam-B path rejects a bad bias key. The reassessor's one-turn pending semantics stand.

---

## 5. Session P3.2 — army parley + post-combat surrender

**Army parley (§10.4)** — construct from sacred parts (DaW has no envoy mechanic; corpus-confirmed gap).
- **When:** at army collision, after reaction/stance resolution and **before deployment** (`gdd-army-warfare.md §6` pre-battle pause), or a siege lull. **Never mid-battle** (`ax_reactions:7`). Enter via the existing `"parley"` collision choice (event_bus.gd:302).
- **Who:** the opposing `command_character_id` (a real NPC; RAW spokesperson rules both sides).
- **How:** each demand is a `PerIssueResolver` per-issue reaction. `demand_surrender`/`demand_tribute` resolve as **intimidation** (`InteractionResolver` intimidation stack) with the army context supplying RAW-priced evidence lines: outnumbering ratios from actual BR/unit counts (`ax_reactions:167-189`), commander Morale Score subtracting (`:181`), loss-of-face for proud commanders (`:193`), siege/terrain disadvantage (`:173,190`). `offer_passage`/`offer_terms` resolve as **diplomatic** with favors/authority lines. **Success tiers:** Cowed/Friendly-shift → army withdraws or accepts terms (battle events cancelled, tribute/withdrawal events scheduled); partial → parley ends, battle proceeds; roll of 2 → talks collapse, battle immediate.
- **Aftermath:** write commander memories, adjust `aggression_toward` inputs via the ruler seams, emit army-warfare signals. **Dialogue never touches battle math** (rule 10.2 — battle resolution stays deterministic per `gdd-army-warfare.md`).

**Post-combat surrender re-entry (§12.2, §16).** After combat ends with survivors who yield, re-enter dialogue with the surrender context (captor/captive roles, the §6 outcome). Reuse the combat→dialogue handoff P1 built for the parley entry; the surrender scene resolves ransom/terms as diplomatic per-issue rolls. Persistence guarantees per §12.3.

---

## 6. Session P3.3 — lying (deterministic; deduction, not a die)

**The NPC's decision to lie is deterministic** — extend `NpcReplyPlanner.plan_reply` to mark a reply as a lie when ANY: the asked fact is `willingness_to_share: never` and attitude < Friendly; `self_interest ≥ 8` and the truth costs them; the NPC is Hostile/Unfriendly/Fearful and the truth aids the party against them or their `in_group_loyalty` targets; an active `deception_by_npc` memory commits them to a prior lie (consistency).

**Lie fabrication is engine-side.** The lie packet carries the false content — a `misleading`/`false` accuracy-variant of the fact where one exists (reuse the rumor accuracy machinery), else a negation/deflection template. The performer instruction (P4) will be *"deliver this confidently as truth; do not hint."* Write a `deception_by_npc` memory with the lie's content so the NPC stays consistent forever after.

**Detection = the demeanor-beat channel (§13.11), not a roll (Jedidiah 2026-07-03).** Every reply carries a brief engine-authored behavioral beat (its mere presence is never a tell).
- **Composure** (deterministic, from existing axes): high `stress_reactivity` + high `expressiveness` leak; professional deceivers (assassin/thief/nightblade classes, spy/ruffian roles, venturers) get a composure bonus. Constants PROJECT CALL — no new traits.
- **When lying:** roll against composure (seeded, logged) — a leak makes the beat a lie-tell at graded intensity; a hold makes it composed.
- **When honest:** a personality-scaled noise roll can still emit lie-*like* beats (anxious innocents fidget) — the false-positive channel that makes it deduction.
- **No player-side roll in v1.** Exposure comes from the world-verification loop (a verified-false rumor traced to source, contradicting facts) → write `deception_suffered` (kind exists), StatusProfile harm-evidence, relationship consequences. WIS-clarity variant ships OFF.

---

## 7. Session P3.4 — capabilities + NPC-side intent (incl. charm defection)

**Player-side capability registry (§5.5).** The dialogue-usable abilities a PC can invoke mid-scene (spells/proficiencies with a social effect). Data-defined; each defines its dialogue effect. Gate by real availability (spell known + slot).

**`NpcIntentPolicy` (§5.6).** Each NPC turn (loop step 3b) MAY attach **one** NPC-side move, chosen deterministically from capability availability (real spell list/slots), axes, attitude/tone, open-issue stakes, context flags. Seeded, logged, **capped ≤1 NPC-initiated act per ~3 exchanges** (tunable). NPC move vocab (v1): `npc_use_ability(capability_id)`, `npc_offer(package)` (terms by personality/attitude), `npc_request(ask)` (favor ledger both directions), `npc_threaten` (intimidation stack). NPCs may arrive **pre-buffed** (encounter/PoI generation seeds active effects) so no hidden mid-scene rolls are needed.

**Effects-vs-PCs (§5.6 table).** The player controls PCs, so each capability defines its PC-side bite:
- **`charm_person` on a PC:** Save per RAW. On failure: hostile moves against the charmer are **blocked in the move menu**; and per RAW ("if the caster is attacked, the charmed creature acts to protect its friend," `acore_spell_catalog_a-i_summary.xml:191`) the charmed PC **defects to the charmer's side in the combat roster** (§12.1). **Compulsion ceiling:** NPCs can never compel a PC's affirmative act (the player may still refuse). Counterplay: switch designated speaker, Detect Magic, dispel, or wait out repeat saves.
- **`esp`:** the NPC learns **engine-known facts only** (declared moves this session, active quests, visible intentions) — never private plans (they don't exist as game state); grants a knows-your-mind per-issue bonus, flags free-text bluffs ineffective, writes real memories. Aware PCs get the RAW save.
- **`detect_evil`:** reveals only *actively hostile intent existing as game state* (a quest targeting this NPC, a planned ambush) — the RAW intentions-not-alignment limit.
- **Beneficial casting:** via `npc_offer` — real spell resolution on acceptance.

**Non-social casting mid-dialogue = combat:** session terminates with outcome `combat`, caster seeded as instigator.

**⚠️ CHARM DEFECTION — combat-roster side-switching (flagged to you at Phase 3 per §17).** This is the one place P3 needs a **combat-system capability**, not just a dialogue one. Inspect `engine/subsystems/combat/combat_roster.gd` + `combatant.gd` for how sides/teams are represented. If a combatant's side is mutable, implement a `combat_roster` method to move the charmed PC to the charmer's side for the encounter's duration (and restore on charm end). If the roster has NO side-switch support, **build the minimal capability** (a per-combatant `controlling_side` override that the turn/targeting logic honors) — additive, guarded, restore-on-expiry. Write the test that a charmed PC (a) loses hostile-vs-charmer menu options and (b) appears on the charmer's side in the roster, and reverts when charm ends. Record the exact combat interface you added in the build log so the combat-subsystem owner sees it.

**Transparency (Jedidiah 2026-07-03): complete mechanical transparency in pre-alpha** — all NPC casting, saves, effect states, intent-policy selections surface openly (dice log / visible UI states / debug channel). The concealment layer is designed-in but **ships OFF** (a per-capability visibility flag).

---

## 8. Acceptance bar (verify by reading code + `--check-only`, NOT by running tests)

Register new suites in `tests/test_runner.tscn` + `test_runner.gd` using **ext_resource ids starting at 540** (Track B's reserved block, to avoid colliding with Track A at 529).

- **Q-5:** each move calls the correct registry method + returns the contracted shape; `offerable_quests` attitude gate (Friendly vs Neutral); end-to-end turn-in + recipient selection on mock; `ask_rumor` one rumor per band; signals fire.
- **request_action:** matrix computes per class/role/proficiency; the resolution template runs attitude→per-issue→handoff; an unknown action id is rejected (rule 10.2); a deferred action schedules an `EventScheduler` completion; refusal persists in `npc_issues` and retries.
- **Ruler audience:** `persuade_ruler` computes strength deterministically; dissuade ≥0.6 cancels the scheduled event, <0.6 postpones; urge refuses an out-of-catalog offensive-war ask gracefully; unknown `target_action_id` strict-rejected by the reassessor.
- **Army parley:** `demand_surrender` stacks the RAW intimidation evidence lines from real BR/morale; success tier cancels battle events + schedules withdrawal; roll-of-2 collapses to immediate battle; post-combat surrender re-entry resolves ransom.
- **Lying:** lie decision fires on each §9.4 trigger; a `deception_by_npc` memory keeps the NPC consistent on re-ask; composure leak vs. hold is seeded/deterministic; honest false-positive beats occur; no player-side roll; exposure writes `deception_suffered`.
- **Charm defection:** save resolved; hostile-vs-charmer moves blocked; PC moves to charmer's side in `combat_roster` and reverts on charm end; compulsion ceiling holds (affirmative acts still refusable).
- **NPC intent:** ≤1 NPC-initiated act per ~3 exchanges; seeded/deterministic; mock provider performs every NPC move from templates.

---

## 9. Interfaces to record in the build-log entry

`persuade_ruler(packet)` shape + the `persuasion_strength` formula constants; `requestable_actions(npc)` + the `data/dialogue/requestable_actions.json` schema; the army-parley demand set + success-tier→battle-event mapping; the `NpcReplyPlanner` lie-packet + demeanor-beat shape; `NpcIntentPolicy` NPC-move vocab; **the exact `combat_roster` side-switch interface you added for charm defection** (flag prominently — the combat subsystem depends on it); new `move_catalog.json` rows; any new signal declared in `event_bus.gd` (a clearly-labeled `# --- Wave 2 Dialogue P3 ---` block); any migration (198–200).

**Commit** all work at the end (`git add -A && git commit -m "Wave 2 Dialogue P3 + Q-5 (worktree build)"`) and report the commit SHA + this interface list.
