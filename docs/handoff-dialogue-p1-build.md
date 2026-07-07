# Build Handoff — NPC Dialogue, Phase 1 (The Spine)

**For:** Claude Code (build agent)
**Spec:** `generation/gdd-npc-dialogue.md` — the authoritative design. This handoff sequences its Phase 1 scope (§16) into one verifiable build session; the GDD is the source of truth for any detail not repeated here.
**Status of design:** Phase 1's mechanics are fully resolved — the §17 open questions that touch Phase 1 (offense/enticement trigger list, reaction-router naming drift) are noted below as build-time reconciliation items, not blockers.
**Author:** Advisor (design), authored during Wave-0 planning per `docs/master-build-plan-social-llm-stack.md` §3 rule of thumb (no ready handoff existed for Dialogue Phase 1). **Date:** 2026-07-07.

---

## 0. How to use this document

Phase 1 is **one build session** (unlike FF-1's four — the GDD's own phasing treats "Phase 1 — The spine" as a single unit). Follow the Build Session Protocol from `CLAUDE.md`. Every ACKS rule touched must cite `rules/*.xml` via `acks-raw-lookup`. If you find a genuine ambiguity the GDD doesn't resolve, note it `[NEEDS-OPUS-REVIEW]` in the build log rather than inventing a ruling.

**Do not build ahead of scope.** Phase 1's move catalog is exactly: `converse`, `ask_rumor` (stub pool — no live quest/rumor system yet, Wave 0 sequencing), `influence_diplomatic`/`influence_intimidate`/`influence_seduce`, `provoke`, `farewell`. Do **not** build `ask_question`, `offer_*`, `request_action`, `quest_*`, `persuade_ruler`, army-parley moves, or `use_ability` — those are Phase 2/3.

---

## 1. Shared preamble

1. Read `CLAUDE.md`.
2. `acks-build-log --for-task "npc dialogue phase 1"` (and `--last 1`, `--next-actions 3`, `--needs-review` if not already pulled this session).
3. Read `generation/gdd-npc-dialogue.md` §4 (Architecture), §5 (Move System), §6 (Adjudication), §8 (NPC Memory), §15 (Data Model), §16 (this phase).
4. `acks-conventions --for-task "new subsystem folder, SQLite migration, EventBus signal, repository CRUD, action vocabulary entry"`.
5. For every ACKS rule (reaction tables, influence tone tables, spokesperson rule, time ladder), cite via `acks-raw-lookup` — primary source is `rules/ax_reactions_and_influencing.xml` (referenced in-code as `ax_reactions`, already implemented for tone/table mechanics in `interaction_resolver.gd` — read it before writing new adjudication code; do not re-derive tables it already encodes).
6. Determinism: seeded RNG, banker's rounding on anything that rounds, no wall-clock.
7. Engine-first: fully playable on the mock/template provider — no LLM call required for correctness.

---

## 2. Scope for this session

**Goal.** Land the dialogue spine: session/screen shell, context builder, the six-move Phase-1 catalog, the memory data model (`npc_relationships`/`npc_memories`/`npc_issues` — land all three now per the full §8.1 model, even though `npc_issues` isn't consumed until Phase 3, matching the project's "land the whole approved data model in one pass" precedent from FF-1.0/Q-1), deterministic summarizer, time-ladder enforcement, the two Phase-1 entry points, and Tier-0 mock templates.

**GDD refs.** §4 (architecture, entry points, turn loop), §5.1–§5.4 (move anatomy, catalog subset, menu assembly, free-text rider — NOT §5.5/§5.6, those are Phase 3), §6.1–§6.4 + §6.7 (two-track model, designated speaker, time ladder, attitude gate, goading into combat — NOT §6.5/§6.6, those are Phase 3's per-issue/offense machinery, though the offense/enticement *trigger* for `provoke`'s own escalation is in-scope since `provoke` is a Phase-1 move), §8 (memory, all three tables), §13.1–§13.2 only as needed for `NpcReplyPlanner`'s deterministic (non-LLM) output shape feeding the Tier-0 templates, §15 (signals), §16 Phase 1 paragraph (exit test).

**Files.**
- Migration `db/migrations/191_npc_dialogue_memory.sql` — **use exactly this number.** Land `npc_relationships`, `npc_memories` (+ its index), `npc_issues` verbatim per GDD §8.1's SQL (columns/CHECKs as written). Update `db/schema.sql` — append this block under a clearly-labeled `-- Dialogue subsystem (Phase 1)` comment so it doesn't collide textually with sibling Wave-0 tracks' appends to the same file.
- Shared types in `engine/shared_types/`: `npc_relationship_data.gd`, `npc_memory_data.gd`, `npc_issue_data.gd` — `to_dict`/`from_dict` round-trip, following `faction_data.gd`'s pattern.
- New subsystem `engine/subsystems/dialogue/`: `dialogue_session.gd` (`class_name DialogueSession`, RefCounted), `dialogue_context_builder.gd` (`class_name DialogueContextBuilder`), `dialogue_move_catalog.gd` (`class_name DialogueMoveCatalog`), `dialogue_adjudicator.gd` (`class_name DialogueAdjudicator`), `npc_reply_planner.gd` (`class_name NpcReplyPlanner` — deterministic outcome→plan only; no LLM call in Phase 1), `npc_memory_store.gd` (`class_name NpcMemoryStore`), `dialogue_template_provider.gd` (`class_name DialogueTemplateProvider`). No new autoload — these are RefCounted/static services constructed by callers, per §4.1.
- New scene `scenes/ui/dialogue/dialogue_screen.gd` (+ `.tscn`) — `DialogueScreen.open(session)` static entry, following `EncounterScreen`/`CombatController` precedent. Build AND verify this UI via the godot-ai MCP per project memory — but **do not run the headless Godot test runner or MCP project_run yourself in this build session**; the orchestrating session runs verification centrally after all Wave-0 tracks land (see §7 below). If you cannot avoid a quick `--check-only -s res://<file>` syntax check on a scene script, that is fine (no Godot process, no DB); do not go further than that.
- Data files: `data/dialogue/move_catalog.json` (six Phase-1 moves only, per §5.2's table rows for `converse`/`ask_rumor`/`influence_diplomatic`/`influence_intimidate`/`influence_seduce`/`provoke`/`farewell`), `data/dialogue/templates/*.json` (Tier-0 templates keyed by move/outcome/attitude/archetype per `DialogueTemplateProvider`).
- Repository plumbing in `engine/autoloads/campaign_repository.gd`: add a new clearly-labeled section **`# --- Dialogue subsystem (Phase 1): npc_relationships / npc_memories / npc_issues ---`** (do not interleave with the existing Phase G-1 faction/reputation section — Wave-0 sibling tracks are also editing that file concurrently in separate worktrees; keep your insertion textually distinct to minimize merge friction) with CRUD per the `get_<thing>`/`list_<things>`/`save_<thing>`/`delete_<thing>` convention (§6.2 of conventions). Register all three new tables in the campaign-purge cascade + `_via` chains — insert your entries as a distinct labeled block rather than interleaving with existing entries, for the same merge-friction reason.
- `engine/autoloads/event_bus.gd`: declare the four §15 signals (`dialogue_started`, `dialogue_ended`, `npc_agreement_reached`, `npc_memory_written`) in their own new labeled section (do not intermix with the faction/quest sections other Wave-0 tracks are concurrently adding).
- Action vocabulary: register the six Phase-1 moves as action vocabulary entries per project convention (`engine/shared_types/action_payload.gd` documents the `action_id` shape; check `acks-conventions --for-task "action vocabulary registration"` for the actual registry file — the GDD says moves are "registered as action vocabulary entries per project convention," verify the concrete registration site before writing, it may not be `action_payload.gd` itself).
- Entry-point wiring (Phase 1 scope is exactly two, per §16): 
  1. **Encounter parley** — `scenes/ui/encounter/encounter_screen.gd:200-213` (`_attempt_influence`/`_resolve_peacefully` stubs) retarget to `DialogueSession.begin(context.from_encounter(encounter_data))`; the encounter's already-rolled `EncounterData.reaction_roll`/`behavioral_disposition` seeds the session's initial attitude — **do not double-roll** (§6.1). Buttons stay; only the handler bodies change.
  2. **Settlement PoI Talk** — wire per `gdd-settlement-exploration-ui.md §4.1`'s Talk activity (currently listed but unbuilt per the master plan's verified-build-state table); verify its current stub location before writing (grep the settlement exploration state/handlers, not the dungeon context menu's unrelated `"talk"` option at `dungeon_context_menu_builder.gd:505` — that's a different, dungeon-scoped affordance, do not conflate).
- **`InteractionResolver` extension:** per §6.1's ruling, extend `_already_attitude_modifier` so Friendly grants +2 across all tones (currently only documented for the seduction stack, `ax_reactions:278-282`) — this is a small, cited, additive change to existing code, not a rewrite. **Reconcile the attitude vocabulary first:** `InteractionResolver`/`Attitude.shift_tier` currently encode a 5-state table (confirm exact states by reading `attitude.gd` or wherever `Attitude` lives); the dialogue GDD's `npc_relationships.attitude` CHECK constraint is 7-state (`hostile, unfriendly, neutral, indifferent, friendly, fearful, cowed`) per its two-track ruling. Determine whether `indifferent` is a genuinely new tier requiring `Attitude.shift_tier` to grow a state, or whether it maps onto an existing tier under a new name for dialogue's purposes — resolve this **before** writing `DialogueAdjudicator`, and note the resolution in the build log as an interface decision (other Wave-0/Wave-1 consumers will read it).

**Explicitly out of scope (do not build):** `ask_question`, `offer_bribe`/`offer_terms`/`offer_hire_*`, `request_action`, `quest_*` moves (Q-1 lands the registries this wave but the dialogue-side adapters are Q-5, Wave 2), `persuade_ruler`, army-parley moves, `use_ability`/capability registry, NPC-side intent policy (`NpcIntentPolicy` class may be stubbed/declared but not implemented), henchman interjections, lying/demeanor-beat machinery (§9.4/§13.11 — Phase 3), live LLM performance (Phase 4 — `NpcReplyPlanner` in Phase 1 only ever emits deterministic plans consumed by `DialogueTemplateProvider`, never `LLMManager.generate()`).

---

## 3. Acceptance bar

- Fresh migration applies clean on a new DB and a copy of an existing campaign DB (non-destructive); all three tables + index present exactly per §8.1's SQL.
- Shared types round-trip.
- `DialogueMoveCatalog.eligible_moves` correctly gates the six moves by attitude per §5.3's layered rules (Hostile NPCs see only `influence_*`/`provoke`/`farewell`).
- First-ever meeting from an encounter does not double-roll (uses `EncounterData.reaction_roll` as the initial interaction); a non-encounter first meeting calls `InteractionResolver.resolve_initial`.
- Repeat meetings load the persisted `npc_relationships` row and open mid-relationship.
- `provoke` shifts attitude one step toward Hostile per use (PROJECT CALL constant, documented); reaching Hostile drives NPC behavior to attack per `acore_adventures:952-954`, routing to combat handoff (stub the actual combat-handoff call if Phase 1's `DialogueSession` doesn't yet own real combat transition machinery — note what's stubbed).
- Time ladder enforced: attempts 1–2 resolve in-session; attempt 3+ schedules via `EventScheduler` per §6.3 (or is clearly stubbed with a documented TODO if `EventScheduler.schedule_after` wiring is judged out of scope for a mock-only Phase 1 — your call, document it).
- COMMIT writes the deterministic move-log summary (§8.2, template path — no LLM) to `npc_memories`, updates `npc_relationships.last_interaction_day`/attitude, emits `dialogue_ended`.
- Friendly +2 relationship modifier applies across all three tones post-extension.
- **Exit test (verbatim from §16):** meet a hermit twice — first meeting establishes attitude and is remembered on the second; goad him (`provoke`) until Hostile; he attacks (combat handoff fires); he's dead; a subsequent lookup shows no living relationship to resume — dead forever.
- Purge cascade deletes all three new tables' rows with the campaign.
- Suite net-zero — **but do not run the suite yourself.** Report readiness for central verification instead (§7).

---

## 4. What to report back (no local build_log.md or coding_conventions.md edits)

This session runs as part of a coordinated Wave-0 parallel build. **Do not append to `build_log.md` and do not edit `docs/coding_conventions.md` yourself** — a sibling process is writing to both files from other concurrent build tracks and will corrupt on concurrent writes. Instead, produce a structured end-of-session report (the orchestrating session will fold it into a single build-log entry and the conventions doc centrally) covering exactly the categories in the standard entry template: Task, Completed (files/functions), Decisions made (incl. the `indifferent`-tier reconciliation and any EventScheduler stub call), Interfaces defined or changed (exact signal signatures, method signatures, table/column shapes), Database changes (the migration file + its number), Tests added, Known issues (anything stubbed, anything `[NEEDS-OPUS-REVIEW]`), and suggested conventions-doc additions (the dialogue subsystem's service shape, the deterministic-summarizer pattern, the mock-only reply-planner contract).

---

## 5. Quick interface index (verify against code before use)

- `engine/subsystems/reputation/interaction_resolver.gd` — `resolve_initial(tone, target, context, rep_system, dice)`, `resolve_attempt_to_influence(tone, current_attitude, target, context, rep_system, previous_attempts, dice)`, `_already_attitude_modifier` (~:319, the extension point), `_is_charm_like` (~:391).
- `scenes/ui/encounter/encounter_screen.gd` — `_attempt_influence(tone)` ~:229, `_resolve_peacefully()` ~:265, button wiring ~:200-213.
- `engine/autoloads/event_bus.gd` — existing signals to consume: `combat_ended`, `combatant_downed` (witness-pass hooks land Phase 3, not needed yet); new signals to declare per §15.
- `engine/autoloads/campaign_repository.gd` — Phase G-1 faction/reputation section ~:6048 (sibling track's territory — do not edit inside it); purge cascade ~:5335, `_via` chains ~:5408 (insert your own labeled block near, not inside, the existing entries).
- `engine/shared_types/faction_data.gd` — the `to_dict`/`from_dict` pattern to mirror for the three new dialogue shared types.
- `characters` table — reused unchanged for `personality`, `npc_role`, `persistence_tier`, `day_of_death` (§15 "reused, unchanged" list).
- Migrations: latest on disk `186_armies_provenance.sql`; **this session uses `191_` exactly** (reserved — sibling Wave-0 tracks are using 187/188-190/192-195; do not use any other number even if it looks free from inside your worktree).
