# Build Handoff — NPC Dialogue, Phase 2 (Transactions)

**For:** Claude Code (build agent)
**Spec:** `generation/gdd-npc-dialogue.md` — authoritative design. This handoff sequences the §16 "Phase 2 — Transactions" scope; the GDD is the source of truth for detail not repeated here.
**Depends on:** Dialogue Phase 1 (the spine — `DialogueSession`/`DialogueScreen`/move catalog/`NpcMemoryStore`/`DialogueAdjudicator`, all **landed** in Wave 0, migration 191). `InteractionResolver`, `ReputationSystem`, `henchman_lifecycle_manager.gd` (all built).
**Author:** Advisor (design), authored for Wave-1 planning per `docs/master-build-plan-social-llm-stack.md` §3. **Date:** 2026-07-07.

---

## 0. Scope and boundary

Phase 2 adds the **transaction** moves on top of the Phase-1 spine: `ask_question` + knowledge disclosure (§9.1), the Social Status Profile subsystem (§7) feeding the resolver + the §6.5 per-issue differential, hiring-through-dialogue (§11), the slander ledger (§11.4), the offer moves (`offer_bribe`/`offer_terms` — deferred from P1), and the Gather-Information dual path (§4.2). Boundary:
- **Quest adapters are NOT in this phase.** The five quest/rumor dialogue moves (`quest_ask`/`_accept`/`_decline`/`_turn_in`/`ask_rumor`→registries) are **Quest-Rumor Q-5** (Wave 2), which lands inside this phase's slot once the quest registries exist. Phase 1 already ships `ask_rumor` against a 4-entry stub pool; leave it stubbed — do NOT wire it to the real `RumorRegistry` (that's Q-5). The `quest_*` moves stay unbuilt here.
- **`request_action`, `persuade_ruler`, army-parley, `use_ability`/capability registry, NPC-side intent, lying/demeanor-beat** are all Phase 3 — do NOT build them.
- **Knowledge richness** depends on the npc-personality knowledge generator (`gdd-npc-personality.md` §6 / `docs/handoff-npc-personality-generators.md` RG-2) which is NOT built. Build the `ask_question` MECHANIC (the willingness gate, disclosure, lie-vs-refuse fork's refuse branch) against whatever `KnowledgeEntry` interface exists; if no knowledge storage exists yet, define the minimal read interface `ask_question` needs and tolerate sparse/empty knowledge (most NPCs simply know little until RG-2 lands). Do NOT build the knowledge GENERATOR. The lie *fabrication* half of §9.4 is Phase 3 — in Phase 2, `never`-willingness + attitude < Friendly yields a plain refusal, not a fabricated lie.

---

## 1. Shared preamble

Run the Build Session Protocol (`acks-build-log --for-task "dialogue hiring status profile knowledge"`, `--last 1`, `--needs-review`; `acks-conventions --for-task "dialogue subsystem, reputation, migration, EventBus signal"`; `acks-raw-lookup` for every RAW rule — reaction/status modifier lines `ax_reactions`, hiring `acore_equipment:670-690`, mercenary `daw_armies_recruitment`, sage/spellcasting fees `acore_equipment:967-978`).

**Hard constraints:**
- **Determinism**; **banker's rounding** via `MathUtils.bankers_round`; **no new autoload** (Phase-2 code is more RefCounted/static services under `engine/subsystems/dialogue/` + the existing `DialogueSession`/`DialogueAdjudicator`).
- **Everything on the mock/template provider** — no LLM call for correctness. Reply performance stays Tier-0 templates (`DialogueTemplateProvider`); the live performer is Phase 4.
- **Migrations:** Phase 2 likely needs **ZERO** — StatusProfile is computed-not-persisted (§7.3, "no new table"), the slander ledger reuses `reputation_entries` + NPC memories (§11.4), hiring reuses the henchman tables, and `npc_issues` (for negotiated terms) already landed in migration 191. If `ask_question` genuinely needs a knowledge table and none exists, use migration **195** (and 196 only if a second file is unavoidable) — those numbers ONLY (193/194 are FF-3's, 197 is Quest's). Prefer reading knowledge from `characters.personality` JSON over a new table if that's where the npc-personality GDD puts it — check first.
- **Shared-file discipline (parallel Wave-1 build).** Isolated worktree, concurrent with four siblings. Label any block you add to a shared file (`# --- Dialogue Phase 2 ---`). FF-3 and Quest siblings edit `event_bus.gd`, `campaign_repository.gd`, `db/schema.sql`, `domain_handlers.gd` — if Phase 2 touches any of those (probably only `event_bus.gd` for a hiring/knowledge signal, and only if a needed one doesn't already exist — `henchman_hired`/`specialist_hired`/`settlement_hiring_requested` already exist, reuse them), keep your addition in its own labeled block. Do NOT run the Godot suite/`--import`/any Godot process; do NOT edit `build_log.md`/`coding_conventions.md`/`document_map.md` — return a structured report.

---

## 2. Build order (one continuous session; internal phases)

**P2.a — Social Status Profile (§7).** `StatusProfileBuilder.build(party_id, speaker_id, npc_id, scene) -> StatusProfile` — computed at session open and on speaker change, NOT persisted (all inputs already persist). Assembles the §7.2 evidence struct: `believed_alignment`/`harm_evidence_tier` from `ReputationSystem.get_effective_score()` per scope PLUS this NPC's own memories (a personally-witnessed crime uses the −5, not the hearsay −2); `status_tier` from reputation tier + noble rank (realms/titles) + dress band (worn-equipment value) + entourage. Feed the dice-affecting evidence into `InteractionResolver` (the RAW modifier lines it already consumes — verify the resolver's `context`/`target` shape) and the `status_tier` into the §6.5 per-issue status-differential modifier (−1/tier when the NPC outranks on unrelated asks; +1/+2 when the party outranks). **Never** let `status_tier` touch the sacred tone-track tables — §6.5 Track-2 per-issue rolls only.

**P2.b — `ask_question` + knowledge disclosure (§9.1).** The move: `ask_question(topic)` gated by the NPC's willingness for that knowledge category — `freely` shares at Neutral+; `if_trusted` requires Friendly (or Cowed); `if_paid` spawns an `offer_terms` negotiation; `never` yields refusal (NOT a fabricated lie — that's Phase 3). Entry `accuracy` flows through unchanged (NPCs confidently share what they *believe*). Reads `KnowledgeEntry` records per the npc-personality §6 interface (or the minimal read interface you define if none exists — see §0). Emits a `knowledge_revealed`-style outcome; writes an NPC memory of the disclosure.

**P2.c — The offer moves (§5.2, deferred from P1).** `offer_bribe(amount/item)` — applies the Bribery-style +1..+3 modifier to the NEXT influence attempt this session (`ax_reactions:96`), gold escrowed, memory `bribed`, reputation-risk hook. `offer_terms(package)` — sets the ±1 situational modifier and the recorded terms on the dependent move (hire, `if_paid` knowledge, a future request_action, parley demand — for Phase 2, the live dependents are hire + `if_paid` knowledge), persisted to `npc_issues.terms` (table exists). These feed the per-issue reaction resolution (§6.5), which also lands here as the Track-2 resolver if Phase 1 didn't already build it (check — Phase 1 built the tone track; §6.5 per-issue may be new).

**P2.d — Hiring through dialogue (§11).** Wrap the existing `henchman_lifecycle_manager.gd` pipeline (`ensure_pool` → `get_available_this_week` → `attempt_hire` → `finalize_hire`) as an interview:
- `offer_hire_henchman` fires `attempt_hire` with the interview's accumulated situational modifier (±1 from `offer_terms`), Try-Again loops through further negotiation dialogue (not a modal), Accept → `finalize_hire` (existing party-membership/wages/equipment), Accept-with-élan + Refuse-and-slander flavor from the reply planner.
- `offer_hire_specialist` / `offer_hire_mercenary` — specialists at flat fees (dialogue adds value for NAMED specialists: sages/engineers/spellcasters + faith surcharges `acore_equipment:975-978`); mercenaries market-scale (reaction per company `daw_armies_recruitment:89-90`, negotiate a captain whose unit follows his contract, friendly-band recruitment `acore_adventures:960-962`). Routine specialist/bulk-mercenary hires keep their existing panel flow — dialogue is the value-add scene, not a replacement.
- `hireable_as` computed from `characters.npc_role` + class/level + context (§11.4): pool candidates → `henchman`; specialist kinds; soldier-types → `mercenary`; friendly encounter monsters → `henchman`/`mercenary`. Employed/hostile/higher-status NPCs are ineligible.

**P2.e — Slander ledger (§11.4).** Refuse-and-slander writes a `reputation_entries` delta scoped to the settlement (−1 toward that adventurer's hiring reactions in that town/region, `acore_equipment:683-685`) PLUS an NPC memory — reuse `ReputationSystem`, no new table.

**P2.f — Gather Information dual path (§4.2).** The settlement Gather-Information entry point resolves EITHER as a short DialogueSession with a generated Tier-C interlocutor OR as a menu-level quick-resolve (player choice, §14). Build the dialogue-session path + the quick-resolve fork. NOTE: the *rumor-delivery* mechanics of Gather Information (the 1-hour activity, reaction roll, rumor surfaced) are **Quest-Rumor Q-3** (Wave 1, sibling track) — coordinate: Phase 2 builds the dialogue ENTRY/dual-path shell; Q-3 owns the rumor payload. Wire the shell to call whatever rumor interface exists (stub-tolerant, like Phase 1's `ask_rumor`).

---

## 3. Acceptance bar

- `StatusProfileBuilder.build` returns the full §7.2 struct; personally-witnessed harm uses the −5 (not hearsay −2); `status_tier` drives the §6.5 differential and NEVER the sacred tone tables; recomputes on speaker change; persists nothing.
- `ask_question`: each willingness tier behaves per §9.1 (`freely`/`if_trusted`/`if_paid`/`never`); `never` + attitude < Friendly refuses (no fabricated lie); accuracy flows through; a memory is written. Works against sparse/empty knowledge without crashing.
- `offer_bribe` applies +1..+3 to the next influence attempt (escrow + memory + reputation hook); `offer_terms` sets ±1 on the dependent move and persists to `npc_issues.terms`.
- Hiring: `offer_hire_henchman` runs the full `attempt_hire`→Try-Again-loop→`finalize_hire` through dialogue; specialist/mercenary paths gate correctly; ineligibility rules hold; Refuse-and-slander writes the settlement-scoped `reputation_entries` −1 + a memory.
- Gather Information offers both the session and quick-resolve forks; the rumor payload is stub-tolerant (real payload is Q-3).
- Exit test (extend the Phase-1 hermit test or add a sibling): interview and hire a henchman through a full negotiation (offer_terms sweetener → Try Again → Accept → party membership), then have a second NPC refuse-and-slander and confirm the settlement hiring penalty + memory landed.
- Save/load mid-interview restores the negotiation state (`npc_issues`). Determinism.
- **Do NOT run the suite** — write + register the suites (4-edit pattern), leave execution to the orchestrator.

---

## 4. Report back (structured — no local build_log/conventions edits)

Return: files created/modified, migrations used (ideally none; 195 only if a knowledge table proved unavoidable — say why), completed summary, decisions (esp. where knowledge storage lives + the §6.5 Track-2 resolver's shape if new this phase), interfaces defined (StatusProfile struct, `StatusProfileBuilder.build`, the new move handlers + their return contracts, any new signal), database changes, tests added (registered, unexecuted), known issues + `[NEEDS-OPUS-REVIEW]`, and proposed conventions additions (StatusProfile assembler pattern; the hire-through-dialogue wrapper; offer-move situational-modifier accumulation).

## 5. Quick interface index (verify against code before use)

- `engine/subsystems/dialogue/` (Phase 1, landed): `dialogue_session.gd` (`begin`/`submit_move`/`close`), `dialogue_move_catalog.gd` (`eligible_moves` — add the new moves' eligibility), `dialogue_adjudicator.gd` (`resolve` — add the new moves' resolution), `npc_reply_planner.gd`, `npc_memory_store.gd` (`write_memory`), `dialogue_template_provider.gd` (add Tier-0 templates for the new outcomes), `data/dialogue/move_catalog.json` + `data/dialogue/templates/tier0.json`.
- `engine/subsystems/reputation/interaction_resolver.gd` — `resolve_attempt_to_influence(tone, current_attitude, target, context, rep_system, previous_attempts, dice)` (feed StatusProfile evidence via `target`/`context`); `engine/subsystems/reputation/reputation_system.gd` (`get_effective_score` for believed_alignment/harm tier; slander deltas).
- `henchman_lifecycle_manager.gd`: `ensure_pool` / `get_available_this_week` / `attempt_hire` / `finalize_hire`. Signals (exist): `henchman_hired`, `specialist_hired`, `settlement_hiring_requested`, `henchman_loyalty_checked`.
- Tables (exist): `npc_relationships`/`npc_memories`/`npc_issues` (migration 191 — `npc_issues.terms` for negotiated packages), `reputation_entries` (slander), `characters` (`personality` JSON — likely knowledge home; `npc_role`; noble rank via realms/titles).
- Entry points: settlement PoI Talk + hiring interview (`settlement_hiring_requested` flow) + Gather Information (`gdd-settlement-exploration-ui.md`). Migration 191 is the latest dialogue migration; do not renumber it.
