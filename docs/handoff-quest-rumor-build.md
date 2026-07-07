# Build Handoff — Quest & Rumor System (Q-1 … Q-6)

Companion to [`generation/gdd-quest-rumor-system.md`](../generation/gdd-quest-rumor-system.md) **v1.0a** and [`docs/master-build-plan-social-llm-stack.md`](master-build-plan-social-llm-stack.md) (Wave 2, the long pole). This handoff turns the GDD's §18 Build Phasing into ready-to-run build sessions. The GDD is authoritative on mechanics; this doc is authoritative on build order, file targets, and acceptance.

---

## 0. How to use this document

- One **session** per numbered heading (Q-1 … Q-6). Q-2 may split into a design-calibration pass (Opus) and an implementation pass (Sonnet) — noted inline.
- Each session lists **Goal**, **GDD refs** (read these — the § is normative on mechanics), **Files** (verified against the codebase 2026-07-07 — re-check line numbers before use; they drift), **Acceptance bar**, and a **Paste-ready prompt**.
- Run sessions in order. Q-1 is the foundation; Q-3/Q-4 parallelize after Q-1; Q-5 and Q-6 are the last wiring and wait on their cross-system deps (Dialogue P2, Faction FF-2).
- **Every session runs the Build Session Protocol** (§1) and ends **net-zero on the full suite** with a `build_log.md` entry.
- **Everything ships on the mock provider.** No phase needs a live LLM for correctness (Q-6's narration rides `_wrap`/dialogue templates on mock).

---

## 1. Shared preamble (every session begins with this)

1. Read `CLAUDE.md`.
2. Run the Build Session Protocol context pulls: `acks-build-log --last 1`, `--next-actions 3`, `--needs-review`, and `--for-task "quest rumor <this session's subject>"`. Do NOT read the full `build_log.md`.
3. Read `generation/gdd-quest-rumor-system.md` (the §§ this session cites) and this handoff's session section.
4. `acks-conventions --for-task "<migration / repository CRUD / monthly-tick batch / EventBus signal / etc.>"` before writing code.
5. For any ACKS rule, use `acks-raw-lookup` (`scripts/lookup.py`) with citation + precedence. The GDD's citations are the starting set (carousing/spying/venturer, Monster XP table, treasure→XP `:585`/`:596`, domain/tithe rules). **Never** invent a rule — if the GDD flags an Open Question, respect its default and note it.
6. Determinism is law: seeded RNG (the world-gen `WorldGenRng` for setting-gen; documented seed strings for runtime), **banker's rounding** on every value that rounds, no wall-clock, no un-seeded `randi()`.
7. Engine-first: the phase must be fully playable/testable on the **mock provider**; the deterministic result is the ground truth and the LLM only ever narrates prose columns.

**Cross-cutting build notes (apply throughout):**

- **Migrations:** `db/migrations/`; latest on disk is `186_armies_provenance.sql`, so this arc starts at **`187_`**. FF-1 (faction) and the npc-personality generators (`docs/handoff-npc-personality-generators.md`) also claim numbers from 187 — **take the next free number at build time and reconcile**; never renumber a landed migration. `db/schema.sql` is the full-schema snapshot — update it alongside each migration (note: it has pre-existing drift, e.g. `game_log_entries` is absent; do not treat it as authoritative over the migration history).
- **FK ordering:** `quests.questgiver_faction_id` FKs `factions(id)`. If FF-1's faction schema has landed, enforce the FK; otherwise declare the column **nullable-without-FK** and add the constraint in a later migration once FF-1 lands (GDD §12 migration-ordering note). Do not block Q-1 on FF-1.
- **Repository home:** `engine/autoloads/campaign_repository.gd` — the CRUD for the new tables goes in (or beside) its **"Reputation system (Phase G-1) — factions, memberships, scoped reputation"** section (~line 6048), matching the faction/syndicate precedent. Register every new table in the campaign-purge cascade + `_via` chains (~line 5408) exactly as migrations 181/182 and the faction tables did.
- **No new autoload.** The system is repositories + pure services + a monthly pass + a signal-driven watcher (GDD §3.1, §4.1 placement).

---

## 2. Session map

| Session | Deliverable | Depends on | Model |
|---|---|---|---|
| **Q-1** | §12 migrations (seed + runtime tables) + `QuestRegistry`/`RumorRegistry` CRUD/queries + pure `RewardValuator` + EventBus signal declarations | — (FF-1 only if enforcing the faction FK) | Sonnet |
| **Q-2** | `QuestSeeder` setting-gen pass replacing `_seed_quests_DEFERRED`; questgiver minting; quest-sourced rumor emission; seed→materialize wiring; PoI-rumor-seed ingestion | Q-1; settlement stocking, PoI `rumor_seeds`, `sim_polities` income (all built) | **Opus** (calibration) → Sonnet (impl) |
| **Q-3** | Rumor delivery: reaction-share, carousing hook, venturer-rumormonger hook, notice-board read, reliability signal, monthly decay + invalidation | Q-2; hijink/carousing system (built); Dialogue P1 *or* standalone Gather-Info verb | Sonnet |
| **Q-4** | `QuestCompletionWatcher` over existing signals; turn-in + reward disbursement (all types); failure/expiry/abandon; Unified-Log `quest` entries | Q-1; combat/lair/exploration signals (built); **O-Q1 XP ruling** | Sonnet (Opus for domain-grant/vassalage path) |
| **Q-5** | Wire the five dialogue moves to the registries; attitude-gated `offerable_quests`; `quest_turn_in` reward flow in dialogue | Q-2, Q-4; **Dialogue P2** (the adapter slot) | Sonnet |
| **Q-6** | `create_faction_quest` + `faction_goal` completion polling + faction-ledger write + `advances_faction_goal`; `_wrap("quest"/"rumor")` prose; Quests-tab data binding | Q-4, Q-5; **Faction FF-2** (`post_job`, org treasury); Live-LLM L-1 (optional — mock suffices) | Sonnet (Opus for faction-goal predicate mapping) |

**Global definition of done (Q-1…Q-6):** on a freshly generated world — the seeder mints 3–8 quests per standard region, each with a solvent questgiver, a resolvable completion, and a quest-sourced rumor; identical seed → byte-identical mechanical quest/rumor columns (prose columns excluded from the hash, GDD §10.3); a player can hear a rumor (carouse/board/ask), travel, satisfy a completion, turn in, and receive the reward + XP-per-`xp_eligible`; rumors decay and invalidate on source destruction; save/load mid-quest restores exact state; a dead questgiver's quests fail cleanly; the whole loop runs on the mock provider; suite net-zero each session; `build_log.md` entry per session.

**Gating decision before Q-4:** resolve GDD **§16 O-Q1** (does quest gold grant XP?). The build defaults `xp_eligible = true`; if Jedidiah rules quest gold is "business" (no XP), flip the default — no reward-math change, but decide before the disbursement path is tested.

---

## 3. Session Q-1 — Schema, registries, and the reward valuator

**Goal.** Land the entire §12 data model in one pass (so no later phase renumbers migrations), the two repositories' CRUD/query surface, the pure reward valuator, and the EventBus signal declarations — the foundation every other phase builds on. Zero LLM, zero generation.

**GDD refs.** §12 (tables — column lists normative), §3.1 (services/placement), §4.1 (rumor runtime fields), §6.6 (quest fields), §8 (RewardValuator formulas — §8.1 gold, §8.2 `xp_eligible`, §8.3 tone, §8.5 recovery, §8.6 affordability, §8.7/§8.8 domain-grant equivalent), §11.6 (the twelve signals), §10.3 (determinism + hasher treatment).

**Files.**
- Migration(s) from `db/migrations/187_*.sql` (per the §1 reconcile note): seed tables `setting_quests`, `setting_rumors` (GDD §12 seed-layer column lists); runtime tables `quests`, `quest_rewards`, `domain_grants`, `rumors`, `rumor_settlement_pool` (GDD §12 runtime lists). Honor the FK-ordering note for `quests.questgiver_faction_id`. Update `db/schema.sql`.
- Shared types (follow the `engine/shared_types/` pattern used by `faction_data.gd`): `quest_data.gd`, `quest_reward_data.gd`, `domain_grant_data.gd`, `rumor_data.gd` with `to_dict`/`from_dict` round-trips.
- `engine/subsystems/quests/quest_registry.gd` (`class_name QuestRegistry`) and `engine/subsystems/quests/rumor_registry.gd` (`class_name RumorRegistry`) — CRUD + query surfaces per GDD §3.1 (QuestRegistry: status transitions, availability queries by settlement/questgiver/hex, disbursement orchestration; RumorRegistry: eligible-pool queries, acquisition marking, promotion, freshness). Back them with `CampaignRepository` accessors added in the Phase-G-1 section (~:6048).
- `engine/subsystems/quests/reward_valuator.gd` (`class_name RewardValuator`, pure/static) — §8.1 formula, ±10% variance, 25/100-gp banker's rounding, §8.3 Motivation tone nudge, §8.5 recovery, §8.6 affordability clamp, §8.8 domain gp-equivalent, `xp_eligible` default true.
- `engine/autoloads/event_bus.gd` — declare the twelve signals verbatim from GDD §11.6 (`quest_discovered`, `quest_offered`, `quest_accepted`, `quest_declined`, `quest_completion_ready`, `quest_turned_in`, `quest_failed`, `quest_expired`, `quest_abandoned`, `rumor_heard`, `rumor_verified`, `rumor_expired`).
- Register all new tables in the purge cascade + `_via` chains (~:5408). Add mechanical columns to `SettingDatasetHasher` per the §10.3 / O-Q10 treatment (canonical = mechanical; excluded = `*_placeholder`/`narrated_placeholder` prose) — match the `setting_narrative` lock/hasher precedent.
- After adding new `.gd` files, run the one-time `--headless --path . --import` pass before the test runner (project memory).

**Acceptance bar.** Migration applies clean on a fresh DB and on a copy of an existing campaign DB (non-destructive); every §12 column present; shared types round-trip; `RewardValuator` unit tests pass (each `threat_type` formula, variance bounds, banker's/25-100 rounding, affordability clamp, tone nudge, `xp_eligible` default, domain gp-equivalent) — GDD §15 unit list; purge cascade deletes new rows with the campaign; hasher includes mechanical columns and excludes prose; the twelve signals exist; suite net-zero.

**Paste-ready prompt:**
> Implement session Q-1 of the Quest & Rumor system per `generation/gdd-quest-rumor-system.md` §12/§3.1/§8/§11.6/§10.3 and `docs/handoff-quest-rumor-build.md` §3. Run the Build Session Protocol (`acks-build-log --for-task "quest rumor schema"`, `acks-conventions --for-task "migration, shared types, repository CRUD, EventBus signals, deterministic hasher"`). Write migration(s) from the next free number (187+; reconcile with FF-1/npc-personality if they landed) for the §12 seed + runtime tables (honor the `questgiver_faction_id` FK-ordering note — nullable-no-FK if FF-1 hasn't landed), update `db/schema.sql`, add the `quest_data`/`quest_reward_data`/`domain_grant_data`/`rumor_data` shared types, build `QuestRegistry` + `RumorRegistry` CRUD/queries backed by `CampaignRepository`'s Phase-G-1 section, the pure `RewardValuator` (§8 formulas, banker's rounding, `xp_eligible` default true), declare the twelve §11.6 EventBus signals, register purge cascade + hasher treatment (§10.3/O-Q10). Tests: fresh + existing-DB migration, type round-trips, the full §15 RewardValuator unit list, purge cascade, hasher canonicalization. Net-zero suite; `build_log.md` entry.

---

## 4. Session Q-2 — Questgiver minting + seeding (closes the long-pole blocker)

**Goal.** Replace the `_seed_quests_DEFERRED` no-op with the real setting-gen pass: mint questgivers with Motivation + income, generate quests over the world's threats, emit the quest-sourced rumor, and wire seed→materialize. This is the phase that makes the world stop being a linear loop. **Opus for the generation calibration** (questgiver economics, density, determinism), then Sonnet for the mechanical wiring.

**GDD refs.** §6 (§6.2 questgiver minting, §6.3 eligibility, §6.4 runtime pass, §6.8 quest-sourced rumor), §3.2 (seed→materialize two-phase; stub table names), §7 (taxonomy — every quest maps to a resolvable completion), §8.6 (affordability against `sim_polities` income), §4.2 (rumor accuracy on the emitted rumor), §5 (notice-board placement, `market_class ≥ IV`), §13 (density: ~1 quest per 4 eligible threats, 3–8/region), Appendix C (the worked example — reproduce it as an integration fixture).

**Files.**
- `engine/subsystems/generation/world/infrastructure_generator.gd` — replace the body of **`_seed_quests_DEFERRED` (line ~116, called at ~85)** with the real pass (rename to `_seed_quests`; keep the call site). It already documents the intended inputs (`:101` — `setting_poi_seeds.rumor_seeds`, event/ruin seeds). Use `WorldGenRng` for determinism.
- New `engine/subsystems/quests/quest_seeder.gd` (`class_name QuestSeeder`, static) — scan threats (dungeons, lairs, brigand-held settlements, `sim_events` war/pillage, PoIs), find a candidate questgiver per §6.2/§6.3, roll the density gate, build the quest via `RewardValuator`, write `setting_quests` + the §6.8 `setting_rumors` row.
- Questgiver minting: mint from the settlement-stocking population via `ClassedNpcBuilder` (the faction/ruler precedent), stamping Motivation (`gdd-npc-personality.md`) + an income handle from `sim_polities`. (If the npc-personality knowledge/relationship generators land first, coordinate; they are independent but adjacent.)
- PoI rumor-seed ingestion: read the already-emitted `rumor_seeds` (`poi_generator.gd:273`, materialized onto `pois.rumor_seeds` by `setting_materializer.gd`; parsed pattern at `narrative_generator.gd:329`) into `setting_rumors`.
- Seed→materialize: extend the setting-materializer path that already copies seed rows to runtime (the `pois` precedent at `setting_materializer.gd`) to copy `setting_quests`/`setting_rumors` → runtime `quests`/`rumors` verbatim (mechanical columns), placeholders intact.

**Acceptance bar.** `_seed_quests_DEFERRED` no longer a no-op; a fixture region (2 dungeons + 3 lairs + 1 brigand town + N PoIs) yields 3–8 quests, each with a solvent questgiver (affordability §8.6), a resolvable completion (§7), and a quest-sourced rumor; PoI `rumor_seeds` flow into `setting_rumors`; seed→materialize copies mechanical columns byte-for-byte with placeholders intact; **determinism** — identical seed → identical quest/rumor set (byte-equal mechanical columns); the Appendix-C worked example reproduces (ogre bounty 200 gp, ~36% band); suite net-zero.

**Paste-ready prompt:**
> Implement session Q-2 per `generation/gdd-quest-rumor-system.md` §6/§3.2/§7/§8.6/§13/Appendix C and `docs/handoff-quest-rumor-build.md` §4. Run the Build Session Protocol. Replace `infrastructure_generator.gd::_seed_quests_DEFERRED` (~:116) with the real `QuestSeeder` pass (new `engine/subsystems/quests/quest_seeder.gd`): scan threats, mint questgivers with Motivation + `sim_polities` income via `ClassedNpcBuilder`, roll the density gate (~1 per 4 eligible threats, target 3–8/region), value rewards via `RewardValuator`, write `setting_quests` + the §6.8 quest-sourced `setting_rumors`, ingest PoI `rumor_seeds` (from `poi_generator`/`setting_materializer`), and wire seed→materialize into runtime `quests`/`rumors`. Use `WorldGenRng`; banker's rounding. Tests: the §15 seeding integration fixture (solvent giver, resolvable completion, quest-sourced rumor each), determinism (same seed → byte-equal mechanical columns), seed→materialize verbatim copy, and the Appendix-C worked example. Net-zero suite; `build_log.md` entry. Use Opus for the generation-calibration reasoning; flag anything ambiguous `[NEEDS-OPUS-REVIEW]`.

---

## 5. Session Q-3 — Rumor delivery (the retail + wholesale channels)

**Goal.** Make rumors reachable: reaction-share on conversation, the carousing pool, venturer rumormongering, the notice board, the reliability cue, and the monthly decay + source-invalidation pass. After this, players hear about the world.

**GDD refs.** §4.3 (channels — a: reaction-share, b: carousing, c: the Gather-Information verb, venturer), §4.4 (reliability vs. accuracy), §4.5 (decay), §4.6 (invalidation), §5 (notice board read; `market_class ≥ IV`), §2 constraints (carousing `acore-campaign-hijinks.xml:130-172`, spying `:174-180`, venturer `ax_venturer_class.xml:172-177` — cite, don't reinvent), §10.1 (the monthly tick order).

**Files.**
- `RumorRegistry.share_for_npc(npc_id, party_id, attitude, topic?)` (started in Q-1) — the per-band reaction-share (§4.3c); marks `known_to_party`; emits `rumor_heard`.
- Carousing hook: wire into the carousing/hijink resolution surface (verify: `engine/subsystems/activities/activity_time_cost_executor.gd`, `engine/subsystems/session/handlers/settlement_handlers.gd`, `engine/subsystems/session/states/settlement_explore_state.gd`, `engine/subsystems/characters/thief_skill_resolver.gd`) — on a carouse Hear-Noise success, draw a weighted rumor (unheard ×3, quest ×2) instead of/alongside gold per GDD §4.3b + O-Q6.
- Venturer rumormonger hook: the `ax_venturer_class` 1d4-rumors path — wire alongside the venturer monthly/urban-revisit surface (`engine/subsystems/venturer/`).
- Notice board read: the settlement PoI "Post Notices"/board surface (`gdd-settlement-exploration-ui.md`); reveals 1d4 quests + 1d3 public rumors with no throw, gated `market_class ≥ IV` (the seeding stub already uses this at `infrastructure_generator.gd:103`).
- Reliability cue: expose `reliability` on the read APIs for the Quests-tab Rumors sub-tab (display only; O-Q3 governs whether it's shown).
- Monthly pass: add `RumorRegistry.decay_pass(campaign_id)` + invalidation, slotted into `DomainHandlers._handle_monthly_tick` (`engine/subsystems/session/handlers/domain_handlers.gd:89`) as a batch step in the §10.1 order (after world-change resolution, before board refresh), matching the `NpcSyndicateMonthlyResolver.process_campaign_month` batch style (no `auto_pause`, no LLM).

**Acceptance bar.** A caroused Hear-Noise success returns a weighted rumor (unheard×3/quest×2), marked known, `rumor_heard` emitted; the board reveals quests + public rumors with no throw, gated at Market Class IV; venturer path yields 1d4 rumors once/month; reliability is exposed but orthogonal to accuracy (a `false`-but-`credible` and `true`-but-`dubious` case tested); the monthly decay ages `current`→`stale` after 1d6 months (seeded), persistent rumors never decay, and source destruction invalidates immediately; determinism on the decay pass; suite net-zero.

**Paste-ready prompt:**
> Implement session Q-3 per `generation/gdd-quest-rumor-system.md` §4.3–§4.6/§5/§10.1 and `docs/handoff-quest-rumor-build.md` §5. Run the Build Session Protocol; cite carousing/spying/venturer RAW via `acks-raw-lookup`. Build `RumorRegistry.share_for_npc` (per-band reaction-share), the carousing-pool hook (weighted draw on Hear-Noise success — verify the carousing surface in `activity_time_cost_executor.gd`/`settlement_handlers.gd`/`thief_skill_resolver.gd`), the venturer rumormonger hook, the notice-board read (no-throw reveal, `market_class ≥ IV`), the reliability cue on read APIs, and `RumorRegistry.decay_pass` slotted into `DomainHandlers._handle_monthly_tick` in the §10.1 order (batch style, no auto_pause/LLM). Tests: weighted carouse draw, board reveal + market gate, venturer 1d4, reliability⊥accuracy, decay-to-stale + persistence + invalidation, determinism. Net-zero suite; `build_log.md` entry.

---

## 6. Session Q-4 — Completion, turn-in, and lifecycle (the spine)

**Goal.** Detect completion against real signals, disburse rewards (all types, XP per the ruling, domain level-9 gate), and handle failure/expiry/abandon — with Unified-Log entries at each beat. **Resolve O-Q1 (quest-gold XP) before this session.** Opus for the domain-grant/vassalage disbursement path.

**GDD refs.** §9 (§9.4 completion watcher + the signal-mapping table, §9.5 turn-in, §9.6 recipient selection, §9.7 failure/expiry/abandon), §8.2 (`xp_eligible` + item sold-unused rule, `:592`/`:596`), §8.8 (domain-grant conditions: secure territory, legitimate giver, vassalage, level-9+ or held-in-trust), §16 O-Q1/O-Q4/O-Q14.

**Files.**
- `engine/subsystems/quests/quest_completion_watcher.gd` (`class_name QuestCompletionWatcher`) — subscribe to the **verified** EventBus signals and flip `is_complete` per GDD §9.4's mapping (all in `engine/autoloads/event_bus.gd`): `lair_cleared(party_id, result)` :271 → `clear_lair`; `combat_ended(encounter_id, outcome)` :37 + `characters.day_of_death` → `clear_dungeon`/`kill_target`; `combatant_downed(combatant_id, attacker_id)` :48 → `kill_target`; inventory-changed → `retrieve_item`/`deliver_item`; `hex_entered(hex_id)` :82 / `poi_discovered(party_id, result)` :276 → `escort_npc`/`scout_hex`; monthly check → `hold_territory`; faction predicate → `faction_goal` (Q-6). Idempotent (re-fire is a no-op once complete); ignore backdrop quests. Emit `quest_completion_ready`.
- Turn-in + disbursement in `QuestRegistry.disburse_reward(quest_id, recipient_pc_id)` (§9.5/§9.6): gold → PC, +1 XP/gp if `xp_eligible`; item → inventory, XP only if later sold-unused; **domain → the vassalage flow with the level-9 gate / held-in-trust (§8.8)** [Opus]; political favor → recorded on the sheet. Emit `quest_turned_in`. Support the unaccepted-completion path (§9.5, O-Q4 attitude gate).
- Failure/expiry/abandon (§9.7): expiry via the monthly decay pass (`expires_day`); `failed` via the dead-questgiver filter + impossible-objective checks; `abandoned` via the Quests-tab. Emit `quest_failed`/`quest_expired`/`quest_abandoned`.
- Unified-Log: emit `category:"quest"` entries through the standard `log_entry_added` (`event_bus.gd:1030`) path at each material beat (`gdd-unified-log-panel.md` §4.5).

**Acceptance bar.** Each `completion_type` flips `is_complete` exactly once on its mapped signal and is idempotent on re-fire; backdrop quests ignored; turn-in disburses per type with XP per `xp_eligible`; the domain path enforces level-9/held-in-trust and writes vassalage; the unaccepted path honors the O-Q4 attitude gate; expiry/failure/abandon transition + emit correctly; a dead questgiver fails its quests; **save/load mid-quest** (accepted, complete-not-turned-in, expired) restores exact state; determinism; suite net-zero.

**Paste-ready prompt:**
> Implement session Q-4 per `generation/gdd-quest-rumor-system.md` §9/§8.2/§8.8/§16 and `docs/handoff-quest-rumor-build.md` §6. Confirm the O-Q1 XP ruling first (default `xp_eligible=true`). Run the Build Session Protocol. Build `QuestCompletionWatcher` over the verified EventBus signals (`lair_cleared`:271, `combat_ended`:37, `combatant_downed`:48, `hex_entered`:82, `poi_discovered`:276 — mapping per §9.4; idempotent; backdrop-ignored; emits `quest_completion_ready`), the turn-in/`disburse_reward` flow (all reward types, XP per `xp_eligible`, item sold-unused rule, domain level-9 gate + held-in-trust vassalage [use Opus for this path], unaccepted-completion O-Q4 gate; emits `quest_turned_in`), failure/expiry/abandon transitions, and `category:"quest"` Unified-Log entries via `log_entry_added`. Tests: per-signal completion + idempotency, disbursement per type, domain gate, unaccepted path, failure/expiry/abandon, dead-questgiver fail, save/load mid-quest, determinism. Net-zero suite; `build_log.md` entry.

---

## 7. Session Q-5 — Dialogue quest adapters (the Dialogue-P2 slice)

**Goal.** Wire the five dialogue moves to the registries so quests and rumors flow through conversation. **This is the quest-adapter slice the master plan defers until quest-rumor exists — it lands inside Dialogue Phase 2, so it requires the dialogue subsystem to be built.**

**GDD refs.** §11.1 (the five moves and their exact calls/return contracts), §9.1 (discovery/acquisition), §9.6 (recipient selection in the turn-in flow), §4.3c (`ask_rumor` per-band share). Cross-doc: `gdd-npc-dialogue.md` §5.2 (move catalog), §9.1–§9.3 (knowledge/rumor/quest hooks), §13 (reply planner consumes `questgiver_dialogue`/`completion_dialogue`/`narrated_text`).

**Files.**
- The dialogue move handlers (in `engine/subsystems/dialogue/…`, built by Dialogue P1–P2) call the registry contract from GDD §11.1: `quest_ask`→`QuestRegistry.offerable_quests(npc_id, party_id, attitude)` (attitude-gated: Friendly unlocks `personal`-posting; Neutral only `posted`/`broadcast`); `quest_accept`→`accept`; `quest_decline`→`decline`; `quest_turn_in`→`can_turn_in` then `disburse_reward` (recipient selection); `ask_rumor`→`RumorRegistry.share_for_npc`. Emit the Q-1 signals.
- No adjudication in dialogue (GDD §11.1): dialogue initiates; the registries own state.

**Acceptance bar.** Each move calls the correct registry method and returns the contracted shape; `offerable_quests` respects the attitude gate; `quest_turn_in` runs the recipient-selection + disbursement end-to-end **on the mock template provider**; `ask_rumor` yields one eligible rumor per band; signals fire; suite net-zero. (Build only when Dialogue P2 exists; otherwise the registry contract from Q-1/Q-4 is already the stable target and this session waits.)

**Paste-ready prompt:**
> Implement session Q-5 per `generation/gdd-quest-rumor-system.md` §11.1/§9.1/§9.6 and `gdd-npc-dialogue.md` §5.2/§9.1–§9.3/§13, and `docs/handoff-quest-rumor-build.md` §7. (Prerequisite: Dialogue Phase 2 built.) Run the Build Session Protocol. Wire the five dialogue moves to the registries per §11.1 (`quest_ask`→attitude-gated `offerable_quests`; `quest_accept`/`quest_decline`; `quest_turn_in`→`can_turn_in`+`disburse_reward` with recipient selection; `ask_rumor`→`share_for_npc`), keeping all adjudication in the registries. Tests (mock provider): attitude-gated offering (Friendly vs Neutral), end-to-end turn-in + reward recipient, per-band rumor share, signal emissions. Net-zero suite; `build_log.md` entry.

---

## 8. Session Q-6 — Faction post_job bridge + LLM narration (completes both downstream slices)

**Goal.** The `post_job` faction bridge, `faction_goal` completion polling, the faction-ledger write on turn-in, the `advances_faction_goal` accessor, the setting-gen prose via `_wrap`, and the Quests-tab data binding. **Requires Faction FF-2 (`post_job`, org treasury); Live-LLM L-1 is optional — the mock template path suffices.**

**GDD refs.** §11.2 (the faction bridge — `create_faction_quest`, `faction_goal` polling, ledger write, `advances_faction_goal`), §7.9 (faction-goal quest shaping from `goal_primary`), §11.5 (LLM narration — `_wrap("quest"/"rumor")` + dialogue-performed runtime prose), §11.4 (Quests-tab binding). Cross-doc: `gdd-faction-framework.md` §6.5 (`post_job`), §6.6 (org treasury affordability), §4.5 (ledger), §10.3 (`FactionActionNarrator`); `gdd-live-llm-integration.md` §15 (`setting_narrative:quest`/`:rumor` reserved kinds).

**Files.**
- `QuestRegistry.create_faction_quest(faction_id, front_npc_id, goal, terms)` — mints a `faction_goal`-or-typed quest with `questgiver_faction_id` set, reward drawn against the org treasury (faction §6.6), and a `faction_goal_id` when the success is a faction predicate.
- `faction_goal` completion in `QuestCompletionWatcher` (from Q-4) — poll the faction layer's goal state (faction §6.6) keyed by `faction_goal_id`.
- Turn-in ledger write: on `quest_turned_in` for a faction quest, write a `patronage_granted`/`aided` `faction_events` entry (faction §4.5); optionally decorate via the faction's `FactionActionNarrator` (a Seam-A clone).
- `QuestRegistry.advances_faction_goal(issue, faction_id) -> bool` — the dialogue status-differential relevance check (faction §6.5).
- Narration: `narrative_generator.gd::_wrap` (verified at `narrative_generator.gd:371`) called with `kind="quest"`/`"rumor"` to fill `setting_narrative:quest`/`:rumor` (reserved, migration 159); runtime prose rides the dialogue `npc_dialogue_reply` call (Q-5) or the mock template. **Contract:** LLM fills only the prose columns; deterministic placeholder is the final text on failure/absence.
- Quests-tab data binding (`gdd-quests-tab.md`): the tab reads `quests`/`rumors` and renders Active/Available/Completed/Failed/Rumors sub-tabs (display only; no generation).

**Acceptance bar.** `post_job` mints a solvent faction quest against the org treasury; `faction_goal` completion polls faction state and fires once; `quest_turned_in` writes the faction ledger; `advances_faction_goal` returns correctly for a goal-advancing issue; `_wrap("quest"/"rumor")` fills prose on mock with the deterministic placeholder as fallback; Quests-tab binds and renders; determinism; suite net-zero. (Build only when FF-2 exists.)

**Paste-ready prompt:**
> Implement session Q-6 per `generation/gdd-quest-rumor-system.md` §11.2/§7.9/§11.5/§11.4, `gdd-faction-framework.md` §6.5/§6.6/§4.5, and `docs/handoff-quest-rumor-build.md` §8. (Prerequisite: Faction FF-2 built; Live-LLM L-1 optional.) Run the Build Session Protocol. Build `create_faction_quest` (org-treasury-gated mint with `questgiver_faction_id`/`faction_goal_id`), `faction_goal` completion polling in `QuestCompletionWatcher`, the turn-in `faction_events` ledger write, `advances_faction_goal`, `_wrap("quest"/"rumor")` prose (mock-first, placeholder fallback), and the Quests-tab data binding. Use Opus for the faction-goal predicate mapping. Tests (mock): post_job mint + treasury gate, faction_goal completion fires once, ledger write on turn-in, advances_faction_goal, _wrap prose + placeholder fallback, Quests-tab render. Net-zero suite; `build_log.md` entry.

---

## 9. After Q-6

- Confirm the §2 global definition of done end-to-end on a generated world (the full-loop smoke: hear → travel → clear → turn in → reward + XP → rumor stale → log entries).
- Update `docs/coding_conventions.md`: the `quests/` service shape (repositories + pure valuator + signal-driven watcher + monthly batch pass), the seed→materialize pattern for quest/rumor rows, the `xp_eligible` disbursement convention, and the reward-valuation banker's-rounding buckets.
- Update `docs/master-build-plan-social-llm-stack.md` §9 to mark quest-rumor **built** and unblock the Dialogue-P2 quest slice (Q-5) and FF-2 `post_job` slice (Q-6) as delivered.
- Feed the build log, for consumers: the final `offerable_quests`/`share_for_npc`/`create_faction_quest`/`advances_faction_goal` signatures and the twelve signal names (so Dialogue and Faction wire against the real shapes).
- Forward work (do NOT build from this handoff): multi-stage quests (O-Q8), construction quests (O-Q9, needs stronghold-construction), the reward-multiplier retune after playtest (O-Q2).

---

## 10. Quick interface index (verify against code before use)

- **Registries:** `QuestRegistry` (`engine/subsystems/quests/quest_registry.gd`), `RumorRegistry` (`…/rumor_registry.gd`). Key methods: `offerable_quests(npc_id, party_id, attitude)`, `accept`, `decline`, `can_turn_in`, `disburse_reward(quest_id, recipient_pc_id)`, `create_faction_quest(faction_id, front_npc_id, goal, terms)`, `advances_faction_goal(issue, faction_id)`; `RumorRegistry.share_for_npc(npc_id, party_id, attitude, topic?)`, `decay_pass(campaign_id)`.
- **Services:** `QuestSeeder` (setting-gen), `QuestCompletionWatcher` (signal-driven), `RewardValuator` (pure/static).
- **Seeding stub replaced:** `engine/subsystems/generation/world/infrastructure_generator.gd:116` (`_seed_quests_DEFERRED`, call site ~:85).
- **PoI rumor seeds:** `poi_generator.gd:273`; `setting_repository.gd:56` (`POI_SEED_COLUMNS`); materialized by `setting_materializer.gd`; parsed pattern `narrative_generator.gd:329`.
- **Monthly tick host:** `engine/subsystems/session/handlers/domain_handlers.gd:89` (`_handle_monthly_tick`); batch pattern `process_campaign_month(campaign_id, calendar_day, …)` (`NpcSyndicateMonthlyResolver` precedent).
- **Completion signals (`engine/autoloads/event_bus.gd`):** `combat_ended`:37, `combatant_downed`:48, `hex_entered`:82, `settlement_entered`:111, `lair_cleared`:271, `poi_discovered`:276, `log_entry_added`:1030.
- **New signals (declare in `event_bus.gd`):** `quest_discovered`, `quest_offered`, `quest_accepted`, `quest_declined`, `quest_completion_ready`, `quest_turned_in`, `quest_failed`, `quest_expired`, `quest_abandoned`, `rumor_heard`, `rumor_verified`, `rumor_expired`.
- **Narration:** `narrative_generator.gd:371` (`_wrap(kind, subject_id, template_body, context)`).
- **Repository:** `engine/autoloads/campaign_repository.gd` — Phase-G-1 section ~:6048 (CRUD home); purge cascade + `_via` ~:5408.
- **Migrations:** `db/migrations/`, latest `186_armies_provenance.sql` → start at `187_` (reconcile with FF-1/npc-personality).
