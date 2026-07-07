# Build Handoff — Faction Framework, Phase FF-1 (Registry & Stances)

**For:** Claude Code (build agent)
**Spec:** `generation/gdd-faction-framework.md` (v0.7) — the authoritative design. This handoff sequences its FF-1 phase into verifiable sessions; the GDD is the source of truth for any detail not repeated here.
**Status of design:** The **entire §4 data model is approved** (Jedidiah: §4.1–§4.7 on 2026-07-05, §4.8–§4.9 on 2026-07-06) — all migrations may be written. §14 items 1–10 and 12–14 are resolved; nothing in FF-1 waits on a ruling.
**Author:** Advisor (design). **Date:** 2026-07-06.

---

## 0. How to use this document

FF-1 is a **four-session build**. Do the sessions in order; each ends with passing headless tests and a `build_log.md` entry. FF-1.0 (schema) is a hard prerequisite for everything; FF-1.1–1.3 layer on top. FF-2 (organizations) has its own future handoff — do not start it from this document.

Each session below has: **Goal · GDD refs · Files · Key interfaces · Acceptance bar · Model · a paste-ready prompt.** Paste one session's prompt into a fresh build session, let it go green, then move on.

**Do not redesign.** The GDD encodes Jedidiah's decisions (14+ explicit rulings, 2026-07-04 → 07-06). If you find a genuine ambiguity or a rule you can't cite, **stop and ask Jedidiah**. Every ACKS rule you touch must cite `rules/*.xml` via `acks-raw-lookup` — note that `rules/acore_henchmen_monthly_fee_table.xml` and `rules/rulings_living_expenses_and_social_status.xml` are new (2026-07-06) and citable.

---

## 1. Shared preamble (every session begins with this)

Run the **Build Session Protocol** from `CLAUDE.md` (build-log navigator, design brief, conventions navigator, raw-lookup for rules; append a `build_log.md` entry at session end, `--lint` after).

**Hard constraints (do not violate):**

- **Determinism.** Every stance, drift step, and evaluation is reproducible from (world state + seeded RNG). Everything passes with the mock LLM; no LLM is called anywhere in FF-1.
- **Banker's rounding** everywhere a value rounds. ⚠ A shared banker's-rounding helper was **not found** in `engine/` during the 2026-07-06 audit — check `acks-conventions --for-task "rounding"`; if none exists, create one shared static helper, use it, and document it in conventions. Do not hand-roll it per call site.
- **No new autoloads.** New services are `RefCounted` under a new `engine/subsystems/factions/` folder (mirrors `realm_ai/`). `class_name` is fine outside autoloads.
- **SQLite is ground truth.** Migrations live in `db/migrations/`, sequential from **185** (latest existing: `184_siege_defender_posture.sql`). Non-destructive; godot-sqlite calling conventions per CLAUDE.md. New tables MUST also be added to `CampaignRepository`'s campaign-purge cascade (the table list near line ~5335 and the `_via` dependency entries near ~5408 — faction_memberships is already there as the pattern) and registered in the standard sites (`SettingRepository` / `CampaignRepository` / `SettingDatasetHasher`) as applicable.
- **After adding new `.gd` files:** run the `--import` pass before the headless test runner (commands in CLAUDE.md).
- **Naming per CLAUDE.md:** PascalCase classes, snake_case files, past-tense snake_case signals, plural snake_case tables.
- **Test baseline:** the last recorded full-suite baseline is 484 passed / 16 failed (2026-07-03, two-run flow, RID-leak exit tolerated). Re-establish the current baseline with `run_tests.sh`/`.ps1` before your first change; definition of done everywhere is **net-zero new failures**.

**Approved decisions to honor (do not relitigate):**

- One `factions` registry, three scopes (`realm`/`organization`/`warband`); realm-mirror rows are addresses, not economies (GDD §3.1, §5.1).
- **Authority split:** realm↔realm political state lives ONLY in `realm_relations` (+ `treaties`, FF-3); realm-mirror pairs are forbidden in `faction_stances` — enforce in the write API and lint-test it (§3.1).
- Stances are **lazily instantiated**; un-instantiated pairs use the default-stance function at read time (§3.2, §7.2).
- Secret stances are **discovery-only** — `true_stance` never reaches any UI or any LLM payload (§7.4, §10.2). FF-1 only creates the columns; keep the invariant in mind for accessors (no `true_stance` in any player-facing query path).
- `tribute` is NOT a treaty kind — RAW: ongoing tribute is vassalage (§4.3 comment block; Jedidiah 2026-07-05).
- Audit-first: §11.7 evaluation traces start in FF-1 (the stance evaluator), behind a debug flag.

**New EventBus signal this arc introduces in FF-1** (declare in `engine/autoloads/event_bus.gd`, one section, past-tense — the Phase-7/ruler sets it must not collide with are nearby, e.g. `ruler_action_taken` at ~:1327):
`faction_stance_changed(faction_a_id, faction_b_id, old_public, new_public)`. (The rest of GDD §11.6's signals arrive with their phases — declare on first use.)

---

## 2. Session map

| Session | Deliverable | Depends on | Model |
|---|---|---|---|
| **FF-1.0** | Full §4 schema migration(s) + shared-type extensions + repository CRUD + purge/hasher registration + `lookup.py` rulings tier | — | Sonnet |
| **FF-1.1** | Realm-mirror factions (materialization + lazy + backfill) + authority-split guard | 1.0 | Sonnet |
| **FF-1.2** | Default-stance function + stance read/write API (compute-on-read, decay) + political-audit scaffold | 1.0, 1.1 | Sonnet; flag stance-API semantics `[NEEDS-OPUS-REVIEW]` |
| **FF-1.3** | Ledger service + `realm_relations` drift writer + reputation propagation | 1.0–1.2 | **Opus** for the drift writer; Sonnet for the rest |

**Global definition of done (FF-1):** on a freshly materialized campaign — every tracked realm has exactly one realm-mirror faction; `get_stance(a,b)` answers for ANY faction pair (instantiated or default) deterministically; conquest/revolt/vagary events move `realm_relations` one band per cluster and 12 quiet months decay one band toward the structural default; a faction-affecting deed propagates to reputation at the §8.3 weights, awareness-gated; realm-mirror↔realm-mirror stance writes are rejected; with `debug_political_audit` on, every stance evaluation is reconstructible from the JSONL trace; identical seed → byte-identical audit stream; suite net-zero; `build_log.md` entry per session.

---

## 3. Session FF-1.0 — Schema, types, CRUD

**Goal.** Land the entire approved §4 data model in one pass so no later phase renumbers migrations, plus the repository plumbing.

**GDD refs.** §4.1–§4.9 (all approved — the columns and CHECK lists are normative), §3.1 (scopes), §14.13 note (new rules files).

**Files.**
- Migration(s) starting at `db/migrations/185_*.sql` (one file or a small sequence, per existing convention — look at `181`/`182` for the ALTER + CREATE style): `factions` ALTERs (§4.1 column list verbatim), `faction_memberships` ALTERs (§4.4), new tables `faction_stances` (§4.2 — directed pair, UNIQUE(faction_a_id, faction_b_id)), `treaties` (§4.3 — kind CHECK has NO 'tribute'), `faction_events` (§4.5), `faction_plots` + `faction_plot_members` (§4.6), `realm_petitions` (§4.8), `domain_tithe_shares` (§4.9). SQLite `ALTER TABLE ADD COLUMN` cannot add UNIQUE/PK constraints — the GDD's column defaults and CHECKs are ADD-COLUMN-compatible as written; where a CHECK can't ride an ALTER cleanly, enforce in the repository write path and note it.
- **PoI columns — do NOT add one.** Audit finding (2026-07-06): `settlement_pois.owner_faction_id` and dungeon `pois.faction_id` **already exist unused** in `db/schema.sql`. Reuse `owner_faction_id` as GDD §4.7's "controlling faction" (the GDD carries an errata note); document the reuse in conventions.
- Extend `engine/shared_types/faction_data.gd` (`FactionData`) with the §4.1 fields + to_dict/from_dict round-trip. New shared types **only** for what FF-1 consumes: `faction_stance_data.gd`, `faction_ledger_entry.gd`. (Treaty/plot/petition/tithe types arrive with FF-2/FF-3 — schema only now.)
- CRUD accessors in `CampaignRepository`'s existing "Reputation system (Phase G-1) — factions, memberships, scoped reputation" section (~line 6048): upsert/get faction, memberships, stance rows, ledger append/query. Add every new table to the campaign-purge cascade list + `_via` chains (~5335/~5408).
- Register in `SettingDatasetHasher` as applicable (campaign-runtime tables may be out of its scope — follow what `ruler_dispositions`/`ruler_ai_state` (migrations 181–182) did and match it).
- **Housekeeping (approved via GDD §14.13):** add a top-rank `("rulings_", "Rulings")` tier to `PRECEDENCE_PREFIXES` in `.claude/skills/acks-raw-lookup/scripts/lookup.py` so `rules/rulings_*.xml` outranks book extracts; verify with a lookup of "spending like a duke".

**Acceptance bar.** Migration applies clean on a fresh DB AND on a copy of an existing campaign DB (non-destructive); every §4 column/CHECK present exactly as specced (minus the documented PoI reuse); FactionData + new types round-trip; purge cascade deletes new tables' rows with the campaign; lookup.py shows `[Rulings]` precedence; suite net-zero.

**Paste-ready prompt:**
> Implement session FF-1.0 of the Faction Framework per `generation/gdd-faction-framework.md` §4 (ALL approved — §4.1–§4.9) and `docs/handoff-faction-ff1-build.md` §3. Run the Build Session Protocol first (`acks-build-log --for-task "faction schema migration"`, `acks-conventions --for-task "migration, shared types, repository CRUD"`). Write the migration(s) from 185 exactly per the GDD column lists (NO 'tribute' treaty kind; do NOT add a PoI column — reuse the existing `settlement_pois.owner_faction_id` / `pois.faction_id`, documenting the reuse). Extend FactionData; add FactionStanceData + FactionLedgerEntry shared types; add CRUD in CampaignRepository's Phase G-1 section; add all new tables to the campaign-purge cascade and dataset-hasher registration per the migration-181/182 precedent. Add the top-rank `rulings_` tier to acks-raw-lookup's lookup.py PRECEDENCE_PREFIXES. Tests: fresh + existing-DB migration, type round-trips, purge cascade, CHECK enforcement. Net-zero suite, then `build_log.md` entry.

---

## 4. Session FF-1.1 — Realm mirrors + authority split

**Goal.** Every realm gets an address in the faction id-space; the one rule that prevents dual truth gets enforced.

**GDD refs.** §5.1 (mirror semantics), §3.1 (scopes + authority split), §4.1 (`scope`, `realm_id`).

**Files.**
- `engine/subsystems/factions/faction_registry.gd` (`class_name FactionRegistry`, RefCounted/static): `ensure_realm_mirror(campaign_id, realm_id) -> String` — idempotent; builds the row from the `realms` columns (verified present: `name`, `head_character_id`, `alignment`, `dominant_religion`, `culture`, `realm_kind`): `scope='realm'`, `faction_type='realm'`, `realm_id`, `leader_npc_id=head_character_id`, `home_domain_id` = the sovereign's personal domain, `alignment`/`culture_id`/`religion_id` mapped from the realm row.
- Wire eager creation where tracked `realms` rows are minted — `setting_materializer.gd::_materialize_political_layer()` (≈ line 370) — and a lazy `ensure_realm_mirror` path for `realm_kind='foreign'` realms on first faction interaction. One-shot backfill for already-materialized campaigns (follow the disposition-backfill precedent from ruler-AI Phase 0).
- **Authority-split guard:** the stance write API (lands fully in FF-1.2; put the guard where the write lives) rejects any pair where BOTH factions have `scope='realm'`, with a logged error. Lint test: attempt the write, assert rejection + no row.

**Acceptance bar.** Fresh materialization → exactly one mirror per tracked realm, zero duplicates on re-run; foreign realm lazily mirrors on demand; backfill covers existing saves; mirror rows carry correct alignment/culture/religion; the forbidden-pair write is rejected; net-zero suite.

**Paste-ready prompt:**
> Implement session FF-1.1 per `generation/gdd-faction-framework.md` §5.1/§3.1 and `docs/handoff-faction-ff1-build.md` §4. Run the Build Session Protocol. Build `FactionRegistry.ensure_realm_mirror` (idempotent, mapped from the realms row), wire it into `setting_materializer.gd::_materialize_political_layer()` for tracked realms, add the lazy path for foreign realms and a one-shot backfill (disposition-backfill precedent). Implement and lint-test the authority-split rejection (no realm-mirror↔realm-mirror rows in faction_stances, ever). Tests: one-mirror-per-realm, idempotency, lazy creation, backfill, guard rejection. Net-zero suite; `build_log.md` entry.

---

## 5. Session FF-1.2 — Default-stance function + stance API + audit scaffold

**Goal.** Any two factions have a computable attitude; instantiated stances decay toward structure; every evaluation is auditable.

**GDD refs.** §7.2 (the function — shape normative, constants PROJECT CALL), §3.2 (lazy instantiation), §4.2 (row semantics), §5.6 final ¶ (decay rule), §11.7 (audit traces), §6.4 (the temple-rivalry type term — the co-aligned same-settlement temple case).

**Files.**
- `engine/subsystems/factions/default_stance_evaluator.gd` (static `evaluate(faction_a, faction_b, context) -> {score, band, terms}`): the §7.2 terms — alignment (+2/0/−3), religion (+2/+1/−3/0), culture (+1/0/−1), type-pair matrix, warband scale-term (inherit parent) — reading `factions` + `realms` columns landed in FF-1.0/1.1. Band thresholds per §7.2. `allied` never a default.
- Type-pair matrix as a data file `data/factions/stance_type_matrix.json` (follow the `data/activities/` catalog style); include the §7.2 examples (syndicate↔lawful org −2; same-family same-settlement temples −1; mercenary 0; brigand↔realm −3; knightly↔patron's-enemies −2) and mark every constant tunable.
- Stance API on `CampaignRepository` (or a thin `FactionStanceRepository` service backed by it, per GDD §11.6): `get_stance(a, b)` → instantiated row if present else `{public_stance: default_band, instantiated: false}`; `instantiate_stance(a, b, band, reason)`; `shift_stance(a, b, steps, reason)` (band arithmetic, clamped, emits `faction_stance_changed` on change). **Decay at read:** an instantiated row whose `last_evaluated_day` is ≥ 12 game-months old moves one band toward the current structural default before being returned (and persists the move + new `last_evaluated_day`). Deterministic — no RNG in FF-1.2.
- `engine/subsystems/factions/political_audit.gd`: static JSONL writer to a `user://` path behind a `debug_political_audit` flag (project-settings or a const per conventions — nearest precedent is the override_log/departure_log audit trails; a file-based JSONL trace is fine and savegame-free per §11.7). Every `evaluate()` and every stance mutation writes one record: inputs, per-term contributions, thresholds, output, caller tag.
- `true_stance` handling: accessors expose it ONLY via an explicitly named dev/audit method (`get_stance_full_for_audit`) — the ordinary `get_stance` never returns it (§7.4 invariant starts now).

**Acceptance bar.** Golden tests over the §7.2 matrix: co-aligned same-settlement temples land `neutral`-at-best with the rivalry term visible in the trace; nemesis-family temples `hostile`; warband inherits parent's stance; `allied` unreachable as default. Lazy read of an un-instantiated pair creates no row. Decay: an instantiated `hostile` row with structural default `neutral` reads back `unfriendly` after 12 quiet months (one band, persisted, exactly once). Audit: with the flag on, replaying the same seed/world yields byte-identical JSONL; with it off, zero file I/O. `get_stance` never contains `true_stance`. Net-zero suite. Mark the compute-on-read/decay semantics `[NEEDS-OPUS-REVIEW]` in the log.

**Paste-ready prompt:**
> Implement session FF-1.2 per `generation/gdd-faction-framework.md` §7.2/§3.2/§4.2/§11.7 and `docs/handoff-faction-ff1-build.md` §5. Run the Build Session Protocol. Build `DefaultStanceEvaluator` (terms + bands per §7.2; type-pair matrix as `data/factions/stance_type_matrix.json` with the GDD's example pairs; constants tunable), the stance API (`get_stance` compute-on-read with lazy non-instantiation, `instantiate_stance`, `shift_stance` emitting `faction_stance_changed`; 12-quiet-month one-band decay toward the structural default, persisted at read; ordinary reads NEVER return `true_stance` — dev access only via an explicit audit method), and the `political_audit` JSONL scaffold behind `debug_political_audit` (per-term traces for every evaluation and mutation). Golden tests: temple rivalry, nemesis hostility, warband inheritance, no-default-allied, decay-once, audit determinism, true_stance isolation. Flag stance-API semantics `[NEEDS-OPUS-REVIEW]`. Net-zero suite; `build_log.md` entry.

---

## 6. Session FF-1.3 — Ledger + `realm_relations` writer + reputation propagation

**Goal.** The stock-take's item 7 finally closes: relations move. Memory-with-decay lands, and deeds echo.

**GDD refs.** §4.5 (ledger kinds/expiry — `betrayal_executed` never expires), §5.6 final ¶ (the drift rule: one band per event cluster, event-driven only, 12-quiet-month decay toward structural default), §8.3 (reputation propagation weights + awareness gating), §11.7 (audit).

**Files.**
- `engine/subsystems/factions/faction_event_ledger.gd`: `record(campaign_id, day, actor_faction_id, target_faction_id, kind, magnitude, data)` → append `faction_events` row (expiry per kind; default 60 months; `betrayal_executed` NULL/never), update the target pair's `grievance_score` (decayed rolling sum over unexpired rows — recompute-on-write, banker's rounding), audit-trace it.
- `engine/subsystems/factions/realm_relations_drift.gd`: the long-missing **writer** for `realm_relations` (its `set_relation` at `engine/subsystems/realm_ai/realm_repository.gd:211` has no non-test caller — verified in the stock-take and still true). Event-driven only: subscribe to the existing signals/outcomes that exist TODAY — conquest resolution (the `resolve_conquest_outcome` path), `vassal_revolted`, `vagary_of_war_resolved` (alliance_offered / war_declared vagaries), pillage outcomes — and move the sovereign-pair disposition **one band per event cluster** (cluster = same pair, same calendar month) with ledger entries recorded alongside. Plus the quiet-decay: 12 months with no ledger traffic on the pair → one band toward the structural default (reuse `DefaultStanceEvaluator` on the two realm-mirror identities; `realm_relations` remains the storage — the mirrors are only identity inputs, per the authority split). Hook the decay check into the monthly tick AFTER the existing resolution chain — the verified ordering in `domain_handlers.gd::_handle_monthly_tick` is commerce (~:97) → syndicates (~:106) → venturers (~:111) → domain resolution (~:178) → RulerAI (~:203) → threat escalation (~:210); add the faction/relations maintenance slot after RulerAI's, before threat escalation, and keep it batch-style like `NpcSyndicateMonthlyResolver` (no auto_pause, no LLM).
- Reputation propagation (§8.3) in `engine/subsystems/reputation/reputation_system.gd`: when a deed writes a faction-scoped `reputation_entries` delta, propagate half-weight (banker's rounding) to factions with `allied`/`friendly` stance toward the target and inverted half-weight to `hostile` counterparties — **awareness-gated** (same settlement, same realm, or an instantiated stance row; no global telepathy). Distant awareness arrives via the rumor system in FF-2+ — do NOT build rumor plumbing now.
- Declare `faction_stance_changed` in `event_bus.gd` if FF-1.2 didn't.

**Acceptance bar.** `set_relation` now has production callers; a scripted conquest moves the pair exactly one band (a second event same pair+month does not double-move); vagary `alliance_offered`/`war_declared` and `vassal_revolted` each drift correctly with ledger rows; 12 quiet months decay one band toward the structural default and stop at it; `betrayal_executed` rows never expire and permanently floor `grievance_score` contributions; reputation propagation hits exact §8.3 weights with banker's rounding and never crosses the awareness gate; determinism (same seed/world → identical ledger + relations history + audit stream); net-zero suite. **Model: Opus for the drift writer** (cross-subsystem: it feeds `resolve_conquest_outcome`'s reader and sits in the monthly tick); Sonnet for ledger + propagation.

**Paste-ready prompt:**
> Implement session FF-1.3 per `generation/gdd-faction-framework.md` §4.5/§5.6/§8.3/§11.7 and `docs/handoff-faction-ff1-build.md` §6. Run the Build Session Protocol. Build `FactionEventLedger` (append + expiry + grievance recompute, `betrayal_executed` never expires), `RealmRelationsDrift` (the first production writer for `realm_repository.set_relation`: event-driven one-band-per-cluster drift from conquest outcomes, `vassal_revolted`, `vagary_of_war_resolved`, pillage; 12-quiet-month decay toward the DefaultStanceEvaluator structural default; monthly maintenance slot in `domain_handlers._handle_monthly_tick` after RulerAI's batch, no auto_pause, no LLM), and the §8.3 reputation propagation in `reputation_system.gd` (half-weight allied/friendly, inverted-half hostile, banker's rounding, awareness-gated — no rumor plumbing). Audit-trace all of it. Tests: one-band-per-cluster, each drift source, decay-to-default-and-stop, betrayal permanence, propagation weights + gating, end-to-end determinism. Use Opus for the drift writer; flag anything ambiguous `[NEEDS-OPUS-REVIEW]`. Net-zero suite; `build_log.md` entry.

---

## 7. After FF-1

- Confirm the §2 global definition of done end-to-end on a mixed campaign.
- Update `docs/coding_conventions.md`: the `factions/` service shape, the compute-on-read stance pattern, the JSONL audit pattern, the banker's-rounding helper, the PoI `owner_faction_id` reuse.
- Record in the build log, for FF-2 planning: the current shape of settlement stocking's criminal-syndicate seeds (name/territory/leader/style — FF-2 promotes them to faction rows) and where org-leader NPCs would mint via `ClassedNpcBuilder`.
- Forward work (do NOT build from this handoff): FF-2 organizations (needs its own handoff + the tithe-apportionment UI contract from GDD §6.4), FF-3 diplomacy/rebellion, FF-4 allegiance/ops, FF-5 dungeon tie-in; sibling GDD `gdd-npc-agency.md` (design not yet authored).

---

## 8. Quick interface index (verify against code before use)

- Schema: `db/schema.sql` — `factions` / `faction_memberships` / `reputation_entries` (~:1470–1500 region), `realm_relations` (pair-unique, six bands `hostile|unfriendly|neutral|cordial|friendly|allied`), `settlement_pois.owner_faction_id`, `pois.faction_id`, `realms` (has `alignment`, `dominant_religion`, `culture`, `realm_kind`, `head_character_id`).
- Migrations: `db/migrations/`, latest `184_siege_defender_posture.sql`; 181/182 are the ruler-AI precedent for ALTER+CREATE+registration style.
- Repositories: `CampaignRepository` (autoload; faction/G-1 section ~:6048; purge cascade ~:5335 + `_via` ~:5408); `engine/subsystems/realm_ai/realm_repository.gd` (`get_relation` ~:195, `set_relation` ~:211 — no non-test caller yet); `realm_graph.gd` (`is_allied` hard-false until FF-3).
- Monthly tick: `engine/subsystems/session/handlers/domain_handlers.gd::_handle_monthly_tick` — commerce ~:97 → `NpcSyndicateMonthlyResolver` ~:106 → venturers ~:111 → domain resolution ~:178 → `RulerAI.process_campaign_month` ~:203 → threat escalation ~:210.
- Signals: `engine/autoloads/event_bus.gd` (e.g. `ruler_action_taken` ~:1327); GameLog caller pattern for future narration: `game_log.gd::_on_ruler_action_taken`.
- Reputation: `engine/subsystems/reputation/reputation_system.gd`, `interaction_resolver.gd`, `hostile_enforcement.gd`.
- Types: `engine/shared_types/faction_data.gd` (`FactionData`), `character_data.gd` (`persistence_tier`: `full|named|transient`).
- NPC minting: `ClassedNpcBuilder.build_classed_npc(...)` (org leaders, FF-2).
- Tests: `tests/` + `res://tests/test_runner.tscn`; `run_tests.sh` / `run_tests.ps1` (two-run flow; RID-leak nonzero exit tolerated — the log summary is authoritative).
- New rules files (citable): `rules/acore_henchmen_monthly_fee_table.xml`, `rules/rulings_living_expenses_and_social_status.xml`.
