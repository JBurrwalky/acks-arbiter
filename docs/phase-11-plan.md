# Phase 11 — Departure Log + Lifecycle Polish + Chaotic Branch + End-to-End Tests — Granular Build Plan

> **Authority:** Implements `docs/domain-roadmap-corrected.md` Phase 11 (line 439+) and `generation/gdd-domain-tab.md` §14 (Departure Log), §16.4-5 (Conquest/Abandonment/Succession), §13.3 (lifecycle status surfacing), §9.4 (vassal reverts-to-overlord default), §19 (Empty-state).
>
> **Status (2026-05-22, FIFTH session — PHASE 11 COMPLETE):**
> - **All sub-phases shipped:** 11A, 11B, 11C, 11D-prereq.0a/0b, 11D-prereq.A/B/C, 11D.1-D.5, **11E (harness + 5 of 10 scenarios)**, **11F (class-guidance + empty-state page + handoff doc)**.
> - **Closeout doc:** `docs/phase-11-handoff.md` — covers migration sequence, conventions §57-§68, deferred polish items, architecture map.
> - **Migration head:** 129. Next migration = 130 (TBD per next phase's needs).
> - **Test stability:** 342-343 / 24-25 across the final battery — within the established baseline band. All 11A-11F suites green.
> - **This revision absorbs (a)** the chaotic-domain rescope — RAW conflates clanhold-style and chaotic-alignment, but Arbiter follows the post-RAW / ACKS-II reading where they are orthogonal axes (see `memory/feedback_clanhold_vs_chaotic_alignment.md`) — and **(b)** the realm-substrate insertion, since 11B's siege-conqueror-kind detection deferred a faction-relation primitive and 11D's "same realm" classification gates require one. The original Phase 11D (single sub-phase) is now five implementation sub-phases plus three prereq GDDs.
>
> Update the per-sub-phase Status fields as work lands. Do NOT renumber existing sub-phase ids — external references in `build_log.md` and elsewhere are stable.

## Wave split

| Sub-phase | Scope | Status |
|---|---|---|
| **11A** | Departure log substrate: migration 121 + recorder service + sub-tab UI + classification/morale-tier transition hooks | **Shipped 2026-05-20** |
| **11B** | Lifecycle handler: conquest / abandonment / stronghold-collapse with departure-log integration; siege + stronghold-destroyed signal bridges; voluntary-abandon UI flow | **Shipped 2026-05-20** |
| **11C** | Ruler death + succession state machine; designate-heir UI; vassal-reverts-to-overlord default; non-henchman heir base loyalty −2 | **Shipped 2026-05-20** |
| **11D-prereq.0a** | Realm Substrate foundation: `realms` + `realm_relations` tables; lookup helpers; `resolve_conquest_outcome` resolver | **Shipped 2026-05-20** |
| **11D-prereq.0b** | Realm Reification + Pillage: instantiate-realm-on-demand + spawn-local-succession-NPC placeholders; pillage helper; retroactive 11B fix to the three-outcome conquest taxonomy | **Shipped 2026-05-20** |
| **11D-prereq.A** | GDD: Domain Style + Alignment Taxonomy (style × alignment as orthogonal axes; establishment eligibility; conquest-time alignment transition rules; schema column design) | **Shipped 2026-05-20** |
| **11D-prereq.B** | GDD: Religion Conversion Process (project-designed timeline + cost + morale curve + success/failure modes + UI surface) | **Shipped 2026-05-20** |
| **11D-prereq.C** | GDD: Tribal Warrior Subsystem (recruitment per family + wages + retention + loot share + calling-to-arms favor cost) | **Shipped 2026-05-21** |
| **11D.1** | Schema migration: `domain_style` + `alignment` columns; backfill from `is_chaotic_domain`; rename code sites | **Shipped 2026-05-21** |
| **11D.2** | Clanhold mechanics (style-driven, alignment-agnostic): 125-fam cap halving, 7gp urban cap, 2,000gp/new-family, 50,000gp class V, halved investment value, distance gates (same-realm), chieftain vassalage limits | **Shipped 2026-05-22** |
| **11D.3** | Alignment effects (alignment-driven, style-agnostic): RAW alignment-vs-religion morale penalty table; beastman-ruler-over-kin stack; religion conversion mechanic from 11D-prereq.B | **Shipped 2026-05-22** |
| **11D.4** | Establishment + lifecycle integration: `establish_domain_flow` accepts (style, alignment) params with eligibility validation; conquest path updates style/alignment per 11D-prereq.A rules | **Shipped 2026-05-22** |
| **11D.5** | Tribal warrior subsystem (data + handlers) per 11D-prereq.C | **Shipped 2026-05-22 (v1 backbone — polish items in build_log)** |
| **11E** | Scenario harness + the eight end-to-end scenarios | **Shipped 2026-05-22 (harness + 5 of 10 scenarios; remaining 5 noted as polish in build_log)** |
| **11F** | Empty-state polish + manual smoke + Phase 11 closeout doc | **Shipped 2026-05-22** |

**Sequencing:** 11A → 11B → 11C ✅; then 11D-prereq.0a → 11D-prereq.0b (Realm Substrate before everything else in 11D); then 11D-prereq.A/B/C (GDDs, in parallel-OK order); then 11D.1 → 11D.2 → 11D.3 → 11D.4 → 11D.5 (sequential); then 11E (depends on 11A-D being complete); 11F parallel with 11E.

---

## Resolved decisions (this revision)

These are folded into the per-sub-phase specs below. Anything else surfaced during build that contradicts these requires escalation to Jedidiah.

**Lifecycle and succession (folded into 11A/B/C):**

- **Succession grace period = 1 game-month** (roadmap line 445, `[RESOLVED 2026-05-06]` formerly O-D6).
- **Non-henchman heir base loyalty = −2** per `acore_axioms` §non_henchman_vassals L392-397.
- **Vassal-with-no-heir reverts to overlord** as the v1 default (per `gdd-domain-tab.md` §9.4). Placeholder for the eventual ACKS Dynasties bloodline-heir model per `memory/project_dynasties_succession.md`. The succession state machine + `designated_heir_*` columns are deliberately shaped so the Dynasties resolver slots in without schema rework.
- **Departure Log is append-only** (no deletes, no edits) per GDD §14.2.
- **Voluntary abandonment** always zeroes the domain's treasury; credit to `liquidate_to_character_id` is conditional. Forfeit cases (stronghold-collapse grace lapse, no-heir lapse) zero the treasury but credit nobody.
- **Stronghold-collapse re-entry is idempotent** — repeated `mark_stronghold_collapsed` calls do not extend the grace window.

**Conquest taxonomy (revised 2026-05-20):**

- **Three outcomes from the defender's perspective**, not five:
  - **`occupied`** — domain row persists; hexes + population preserved (possibly reduced by pillage); treasury looted to attacker; ownership reassigns to `new_owner_id`. Covers both existing-NPC takeover AND off-map-force-establishes-new-realm (the new-realm-instantiation happens BEFORE conquest resolves at the Realm Substrate layer).
  - **`looted_local_succession`** — attacker takes treasury + leaves; the Realm Substrate spawns a placeholder local NPC ruler; population/stronghold reduced per pillage severity.
  - **`salted_to_ruin`** — terminal destruction per DaW salt-the-earth. Hexes release, population disperses, stronghold collapses to ruin. Audit row stays.
- **`CONQUEROR_PLAYER` is deleted** when the Realm Substrate ships and `LifecycleHandler.conquer_domain` gets the revised signature. PC-vs-PC conflict is non-existent in v1 (single-player game); the multiplayer affordance is preserved by `new_owner_id` being a polymorphic `character_id` rather than via a dedicated PvP code path.
- **`lifecycle_state` value `lost_to_foreign` renamed to `salted_to_ruin`** when the retroactive 11B fix ships (migration 124 or piggybacked on 11D.1).
- **Foreign army default is `occupied` (with new realm instantiated) or `looted_local_succession`,** never terminal unless explicit salt-the-earth fires.
- **Salt-the-earth is gated:** for player attackers, surfaced via UI choice; for NPC attackers, fires based on attacker alignment + BR ratio + faction relation (heuristic project-designed in the Realm Substrate).

**Realm + faction scope (revised 2026-05-20):**

- **Minimal realm substrate is in scope for Phase 11.** Just enough to support `same_campaign_npc` vs. `foreign_realm` classification, "same realm" classification gates per `ax_domains_of_chaos` §exceptions_from_clanholds L76-77, and realm instantiation on off-map-force conquest.
- **Broader faction system deferred to Phase 12** — encounter reactions, faction-targeted hijinks, espionage, diplomacy proper, settlement control / contested state, trade-route + customs effects of relations. Those want sibling-subsystem treatment; the v1 substrate doesn't preclude them.

**Chaotic-domain reframing (revised 2026-05-20):**

- **Domain style and alignment are orthogonal axes.** `domain_style: 'civilized' | 'clanhold'` and `alignment: 'lawful' | 'neutral' | 'chaotic'`. The Phase 0 `is_chaotic_domain` flag is too crude and is deprecated by 11D.1 in favor of the two columns. See `memory/feedback_clanhold_vs_chaotic_alignment.md`.
- **Beastman clanholds are `style=clanhold + alignment=chaotic` force-locked.** Human/demi-human clanholds (the post-RAW community extension) can be `style=clanhold + alignment=lawful/neutral/chaotic`. A converted chaotic kingdom is `style=civilized + alignment=chaotic`.
- **Establishment eligibility (S3 rule):**
  - Lawful char + `METHOD_CLEAR` vs. beastman lair: **ALLOWED** (clearing destroys the lair + scatters beastmen; new domain is fresh wilderness, any alignment).
  - Lawful char + `METHOD_CONQUEST` vs. beastman clanhold: **BLOCKED** (conquest = take over existing beastman population; lawful chars cannot rule beastmen).
  - Lawful char + `METHOD_CLANHOLD_ANNEX` / `METHOD_RECRUIT_CHIEFTAIN`: **BLOCKED** (chaotic-PC-only paths, already enforced).
  - Lawful char + clanhold-style establishment via cleared wilderness: **ALLOWED** with `alignment=lawful`.
  - Lawful char + `METHOD_CONQUEST` vs. non-beastman chaotic civilized domain: **ALLOWED** with alignment-penalty consequences (−2 ruler-vs-domain morale until religion conversion completes).

**RAW citations:**

- `acore_axioms_strongholds_and_domains.xml:165, 174` — lawful classification advancement gates ("within Nmi of a friendly city or large town")
- `acore_axioms_strongholds_and_domains.xml:245` — religion change penalty ("Changing religion is possible but causes severe morale penalties" — magnitude/duration project-designed)
- `acore_axioms_strongholds_and_domains.xml:461-475` — alignment-vs-religion morale penalty table (L/C ruler in N domain: −1; N ruler in L/C: −1; L↔C ruler/domain mismatch: −2)
- `acore_axioms_strongholds_and_domains.xml:392-397` — non-henchman vassal base loyalty −2
- `ax_domains_of_chaos.xml:39-61` — chieftain vassalage limits (chieftains cannot offer monopoly / loans / council / grants of title; tribal warrior call-to-arms cost)
- `ax_domains_of_chaos.xml:46` — beastman-ruler-over-kin-domain stacked −2 morale
- `ax_domains_of_chaos.xml:73-87` — exceptions from clanholds (same-realm classification gates, halved investment, 7gp urban cap, etc.)

---

## Phase 11A — Departure Log substrate

### Status: Shipped 2026-05-20

Build log entry: `build_log.md:24443`.

### What shipped

- **Migration 121** (`db/migrations/121_domain_departure_log.sql`): append-only `domain_departure_log` table with 21-value `event_type` CHECK constraint. `domain_id` intentionally has no FK so the log survives hard domain-row deletion. Indexes on `(domain_id, calendar_day DESC)` + `(campaign_id, calendar_day DESC)`.
- **`engine/subsystems/domains/departure_log_recorder.gd`**: static-method RefCounted. Public API: `record(campaign_id, domain_id, calendar_day, event_type, summary, details, related_ledger_entry_ids, related_encounter_ids) -> String`; `get_entry(id)`; `list_for_domain(domain_id, limit)`; `list_for_campaign(campaign_id, limit)`; `export_as_markdown / json / txt`; plus the monthly-tick transition recorder `record_monthly_transitions(campaign_id, domain_data, result, calendar_day) -> int`.
- **`engine/autoloads/event_bus.gd`**: new signal `departure_log_entry_recorded(domain_id, entry_id, event_type)` in the Domain block. Fires AFTER the SQL commit.
- **`engine/subsystems/session/handlers/domain_handlers.gd`**: monthly-tick loop calls `DepartureLogRecorder.record_monthly_transitions(...)` after `_emit_signals`. Records classification-advanced / classification-regressed / morale-tier-dropped transitions (named-tier comparison, downward only).
- **`scenes/ui/notebook/domain/sub_tabs/departure_log_sub_tab.gd`**: procedural VBoxContainer per §31 convention. Summary card + filter row (search + event-type dropdown) + chronological list + per-row Inspect modal + markdown/json/txt export via FileDialog. Subscribes to `departure_log_entry_recorded` for live refresh.
- **Domain tab strip**: `domain_tab_page.gd`'s `SUB_TABS` entry for `departure_log` is now live (`script: "departure_log"`, `phase_2: true`); added DepartureLogSubTabScript preload + dispatch arm.
- **Tests:** four new suites (#324-#327) all passing — recorder roundtrip + ordering + rejection paths + signal + exports; classification-hook detection; morale-tier-drop detection; sub-tab visibility.
- **Conventions §57**: append-only log + monthly-tick transition recorder patterns.
- **GDD §14.1**: event-type taxonomy rewritten to match the migration CHECK + per-type RAW citations.

### Key interface contracts

- `EventBus.departure_log_entry_recorded(domain_id, entry_id, event_type)` — UI surfaces subscribe for live refresh; fires AFTER SQL commit.
- `DepartureLogRecorder.VALID_EVENT_TYPES: Array[String]` — kept in lockstep with the migration 121 CHECK constraint. Test `test_valid_event_types_matches_check_constraint` enforces.

### Out of 11A scope (deferred to 11B/C/D)

- Conquest / abandonment / ruler-death / succession / monster_settled / religion_converted log entries. The CHECK already accepts those event types; the writers ship with the corresponding sub-phases.

---

## Phase 11B — Lifecycle handler: conquest, abandonment, stronghold collapse

### Status: Shipped 2026-05-20

Build log entry: `build_log.md:24503`.

### What shipped

- **Migration 122** (`db/migrations/122_domain_lifecycle_state.sql`): three columns on `domains` — `lifecycle_state TEXT CHECK IN ('active', 'ruined_stronghold', 'succession_pending', 'abandoned', 'lost_to_foreign')`, `lifecycle_state_changed_day INTEGER`, `ruined_stronghold_grace_until_day INTEGER`. Index on `(campaign_id, lifecycle_state)`.
- **`engine/subsystems/domains/lifecycle_handler.gd`**: static class. Six public methods: `record_establishment`, `conquer_domain`, `abandon_domain`, `mark_stronghold_collapsed`, `restore_from_ruin`, `tick_lifecycle_state`. Constants `STATE_*`, `CONQUEROR_*` (including the now-deprecated `CONQUEROR_PLAYER`), `REASON_*`, `RUINED_GRACE_DAYS=30`.
- **Four new CampaignRepository helpers:** `get_domain_treasury_cp`, `release_domain_hexes` (returns count), `update_domain_lifecycle_state` (emits state-change signal), `reassign_domain_owner`.
- **Five new EventBus signals:** `domain_conquered`, `domain_abandoned`, `stronghold_collapsed`, `stronghold_restored`, `domain_lifecycle_state_changed`. (`domain_established` from Phase 2 reused.)
- **`establish_domain_flow.gd`**: calls `LifecycleHandler.record_establishment` post-INSERT.
- **`domain_handlers.gd`**: monthly tick skips terminal states; calls `tick_lifecycle_state` per-domain; subscribes to `siege_concluded` (translates `captured` / `surrendered` to `conquer_domain`) and `stronghold_destroyed` (translates `cause='siege'` to `mark_stronghold_collapsed`).
- **`overview_sub_tab.gd`**: new Domain Management card with "Abandon Domain…" button + confirmation modal (BBCode preview of treasury liquidation gp/cp, peasant disperse count, vassal count; type-the-domain-name destructive-action gate).
- **Tests:** `test_lifecycle_handler.gd` (#328) with 12 tests, all passing.
- **Conventions §58**: lifecycle state machine + cross-subsystem signal bridge patterns.
- **GDD §16.4**: conquest / abandonment / stronghold-collapse subsection rewritten.

### Key interface contracts

- `LifecycleHandler.conquer_domain(domain_id, calendar_day, conqueror_kind, conqueror_id, pillage_summary) -> bool` — **this signature changes when the Realm Substrate ships** (see 11D-prereq.0b).
- `LifecycleHandler.abandon_domain(domain_id, calendar_day, reason, liquidate_to_character_id) -> bool`
- `LifecycleHandler.mark_stronghold_collapsed(domain_id, stronghold_id, calendar_day) -> bool` — idempotent re-entry.
- `LifecycleHandler.tick_lifecycle_state(domain_data, calendar_day) -> Dictionary {auto_abandoned, reason}`
- `CampaignRepository.update_domain_lifecycle_state(domain_id, new_state, calendar_day, grace_until_day) -> bool` — emits `domain_lifecycle_state_changed` on actual transition.

### Known caveats (to be addressed by 11D-prereq.0b)

- **Siege bridge currently always routes as `same_campaign_npc`** — distinguishing foreign-realm conquerors needs the Realm Substrate's `resolve_conquest_outcome`. After 0b ships, `_on_siege_concluded` swaps to the three-outcome taxonomy.
- **`lifecycle_state` value `lost_to_foreign`** is mis-named — it conflates "captured by off-map force" with "ceased to exist." After 0b, the state renames to `salted_to_ruin` (terminal salt-the-earth) and the default off-map-force conquest routes through `occupied` (with new realm instantiated) or `looted_local_succession`.

---

## Phase 11C — Ruler death + succession state machine

### Status: Shipped 2026-05-20

Build log entry: `build_log.md:24573`.

### What shipped

- **Migration 123** (`db/migrations/123_domain_succession.sql`): three columns on `domains` — `succession_pending_until_day INTEGER`, `designated_heir_character_id TEXT`, `designated_heir_kind TEXT CHECK IN ('', 'pc', 'henchman', 'non_henchman')`.
- **`engine/subsystems/domains/ruler_death_handler.gd`**: static class. Public API: `handle_ruler_death(deceased_character_id, calendar_day) -> Array`; `designate_heir(domain_id, heir_id, heir_kind) -> bool`; `resolve_succession(domain_id, calendar_day) -> Dictionary`; `tick_succession_grace(domain_data, calendar_day) -> Dictionary`; `eligible_heirs_for(domain_id) -> Array`. Constants `GRACE_DAYS=30`, `KIND_PC / KIND_HENCHMAN / KIND_NON_HENCHMAN`, `NON_HENCHMAN_LOYALTY_MODIFIER=-2`.
- **Two new CampaignRepository helpers:** `list_domains_owned_by` (excludes terminal-state by default), `update_domain_succession_state` (single atomic UPDATE + lifecycle signal emission).
- **Five new EventBus signals:** `ruler_died` (batch), `succession_started` (per-domain), `succession_heir_designated`, `succession_resolved`, `succession_lapsed`.
- **`domain_handlers.gd`**: subscribes to `character_died` → `_on_character_died` sweeps owned domains; monthly tick calls `tick_succession_grace` alongside the existing `tick_lifecycle_state`.
- **`status_header.gd`**: new third row `_row_succession: RichTextLabel` shown only during `succession_pending`. Banner shows heir-designated state + grace day + pointer to Overview.
- **`overview_sub_tab.gd`**: Domain Management card extended with succession action row — Designate Heir… modal (candidate radio list with kind chips PC/henchman/non_henchman, name, class+level) + Confirm Succession Now button.
- **Tests:** `test_ruler_death_handler.gd` (#329) with 14 tests, all passing.
- **Conventions §59**: succession state machine + reverts-to-overlord pattern.
- **GDD §9.4** (new): vassal-reverts-to-overlord as v1 default + Dynasties relationship.
- **GDD §16.5**: ruler death + succession rewritten.

### Key interface contracts

- `RulerDeathHandler.handle_ruler_death(deceased_character_id, calendar_day) -> Array` — returns affected domain ids; emits `ruler_died` + per-domain `succession_started`.
- `RulerDeathHandler.designate_heir(domain_id, heir_id, heir_kind) -> bool` — rejects if domain not in `succession_pending`.
- `RulerDeathHandler.resolve_succession(domain_id, calendar_day) -> Dictionary` — three paths: heir designated → transfer; vassal + no heir → reverts to overlord; independent + no heir → abandonment via `LifecycleHandler.abandon_domain(REASON_NO_HEIR)`.
- `EventBus.character_died(character_id)` — already existed (Phase 2); now bridged through `DomainHandlers._on_character_died`.

### Known caveats

- **Eligibility filtering is broad** (no class/race inheritance per `acore_axioms` §inheritance). Returns all active PCs + henchmen. API exposes the three `kind` chips so future filtering slots in without UI changes.
- **Non-henchman heir candidates are zero in v1** — setting-generator dependency.
- **Non-henchman `-2` loyalty modifier is captured in the departure-log payload only**, not yet applied to a `vassal_assignments` row (heir hasn't sworn fealty as a vassal at succession time; Phase 7 realm code reads it back if/when that happens).

---

## Phase 11D-prereq.0a — Realm Substrate (foundation)

### What it produces

A minimal realm + relations layer that supports:
- "Same realm" classification gates per `ax_domains_of_chaos` L76-77 (chaotic clanhold civilized ≤25mi to same-realm city; borderlands ≤50mi).
- "Friendly" classification gates per `acore_axioms` L165, L174 (lawful borderlands ≤72mi to friendly city; civilized ≤48mi). "Friendly" = relation disposition in `{cordial, friendly, allied}`.
- Conquest-kind classification for the 11B siege bridge (`occupied` with same-tracked-NPC owner vs. `occupied` with off-map-realm-instantiated owner vs. `salted_to_ruin`).
- Foundation for the broader faction system (Phase 12+) without precluding extension.

Does NOT include: realm AI / decision-making, encounter-reaction modifiers, hijink targeting, diplomacy actions, settlement control. Those are Phase 12.

### Schema — migration 124 `124_realm_substrate.sql`

```sql
CREATE TABLE IF NOT EXISTS realms (
    id                  TEXT    PRIMARY KEY,
    campaign_id         TEXT    NOT NULL REFERENCES campaigns(id),
    name                TEXT    NOT NULL,
    head_character_id   TEXT    REFERENCES characters(id),
    -- Realm-level alignment: may be set explicitly, or NULL when realm is mixed.
    -- Used by establishment eligibility + alignment-vs-religion morale math.
    alignment           TEXT
        CHECK(alignment IS NULL OR alignment IN ('lawful', 'neutral', 'chaotic')),
    dominant_religion   TEXT    NOT NULL DEFAULT '',
    -- Cultural identifier (placeholder until the culture system ships).
    -- Free-form text for now; future migration constrains to a culture catalog.
    culture             TEXT    NOT NULL DEFAULT '',
    -- 'tracked' realms are in-simulation; 'foreign' realms are flavor-backdrop
    -- (no head character; cannot own domains directly — see 0b for how
    -- foreign-realm conquest reifies a tracked realm on demand).
    realm_kind          TEXT    NOT NULL DEFAULT 'tracked'
        CHECK(realm_kind IN ('tracked', 'foreign')),
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_realms_campaign
    ON realms(campaign_id);
CREATE INDEX IF NOT EXISTS idx_realms_head_character
    ON realms(head_character_id);

-- Pair-symmetric relations. The repository enforces canonical ordering
-- (lexicographic on realm_a_id < realm_b_id) so each pair has at most one row.
CREATE TABLE IF NOT EXISTS realm_relations (
    id                  TEXT    PRIMARY KEY,
    campaign_id         TEXT    NOT NULL REFERENCES campaigns(id),
    realm_a_id          TEXT    NOT NULL REFERENCES realms(id),
    realm_b_id          TEXT    NOT NULL REFERENCES realms(id),
    -- 2d6 reaction-table band per acore_axioms §reactions, mapped to ACKS
    -- diplomatic stances. Default 'neutral' = no recorded relation.
    disposition         TEXT    NOT NULL DEFAULT 'neutral'
        CHECK(disposition IN ('hostile', 'unfriendly', 'neutral', 'cordial', 'friendly', 'allied')),
    last_changed_day    INTEGER NOT NULL DEFAULT 0,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_realm_relations_pair
    ON realm_relations(realm_a_id, realm_b_id);

-- Augment domains with a realm pointer. The realm-membership of a domain is
-- computed via the existing liege_domain_id chain (apex's owner_character_id
-- maps to a realm via realms.head_character_id), but caching it here makes
-- the classification-gate lookups O(1).
ALTER TABLE domains ADD COLUMN realm_id TEXT REFERENCES realms(id);
CREATE INDEX IF NOT EXISTS idx_domains_realm ON domains(realm_id);
```

Backfill: every existing domain gets a `realms` row corresponding to the apex of its `liege_domain_id` chain (one realm per realm-head; multiple domains per realm). For pre-substrate campaigns without realms, each top-level domain's owner_character_id becomes a new realm head.

### Engine — new file `engine/subsystems/realm_ai/realm_repository.gd`

```gdscript
class_name RealmRepository extends RefCounted

# Realm CRUD
static func create_realm(data: Dictionary) -> String
static func get_realm(realm_id: String) -> Dictionary
static func get_realm_for_character(character_id: String) -> Dictionary
static func get_realm_for_domain(domain_id: String) -> Dictionary
    # Walks liege_domain_id apex if domain.realm_id is null.
static func list_realms_for_campaign(campaign_id: String) -> Array

# Realm relations
static func get_relation(realm_a: String, realm_b: String) -> String
    # Returns disposition; defaults to 'neutral' when no row exists.
static func set_relation(realm_a: String, realm_b: String,
                          disposition: String, calendar_day: int) -> bool

# Conquest outcome resolver — the key 11B / 11D consumer
static func resolve_conquest_outcome(
    defender_domain_id: String,
    attacker_owner_id: String,
    attacker_intent: String,  # 'occupy' | 'loot_and_scoot' | 'salt_the_earth'
) -> Dictionary
    # Returns:
    #   { outcome: 'occupied'|'looted_local_succession'|'salted_to_ruin',
    #     new_owner_id: String,    # for 'occupied' path
    #     pillage_severity: int }  # 0=none, 1=light, 2=heavy
    # Internally:
    #   - intent=='salt_the_earth' → outcome='salted_to_ruin'
    #   - intent=='loot_and_scoot' → outcome='looted_local_succession'
    #     (new_owner_id placeholder; 0b's spawn_local_succession_npc fills it)
    #   - intent=='occupy':
    #       - If attacker's realm exists in this campaign → outcome='occupied',
    #         new_owner_id = attacker_owner_id
    #       - If attacker is off-map (realm_kind='foreign' or no realm) →
    #         outcome='occupied' but new_owner_id is empty until 0b's
    #         instantiate_realm_for_off_map_force populates it
```

The siege bridge in `DomainHandlers._on_siege_concluded` consumes this; the retroactive 11B fix lands in 0b once the realm-instantiation + local-succession-NPC helpers exist.

### Tests (`tests/test_realm_substrate.gd`)

- `test_create_realm_roundtrip` — create + get + list.
- `test_get_realm_for_domain_walks_apex` — chain liege → liege → realm apex's head's realm.
- `test_get_realm_for_domain_uses_cached_realm_id_when_present` — cache hit.
- `test_relation_default_is_neutral` — no row = 'neutral' returned.
- `test_relation_canonical_pair_ordering` — set_relation(A, B) and set_relation(B, A) write the same row.
- `test_resolve_conquest_outcome_tracked_attacker_occupy` — returns `occupied` with attacker as new owner.
- `test_resolve_conquest_outcome_off_map_attacker_occupy` — returns `occupied` with empty new_owner_id (0b fills).
- `test_resolve_conquest_outcome_loot_and_scoot` — returns `looted_local_succession`.
- `test_resolve_conquest_outcome_salt_the_earth` — returns `salted_to_ruin`.

### GDD updates (0a)

- New section `gdd-domain-tab.md` §22 "Realm Substrate" (or wherever fits the doc structure) — describes the two-table model + the conquest-outcome resolver as the foundation for both 11D's classification gates AND Phase 12's broader faction system.
- `docs/coding_conventions.md` §60 (new): realm-substrate conventions (canonical pair ordering on relations, realm_kind enum, cached realm_id on domains rows).

---

## Phase 11D-prereq.0b — Realm Reification + Pillage + 11B retroactive fix

### What it produces

The pieces that make `RealmRepository.resolve_conquest_outcome` actually able to return a complete result (a real `new_owner_id` for the off-map case; a real local-NPC character_id for loot-and-scoot), plus the pillage modifier that the new outcomes apply, plus the retroactive 11B update to consume the three-outcome taxonomy.

### Engine — additions to `engine/subsystems/realm_ai/realm_repository.gd`

```gdscript
# Realm instantiation for off-map forces (placeholder for the culture / setting
# generator system that ships in a later phase).
static func instantiate_realm_for_off_map_force(
    campaign_id: String,
    culture_placeholder: String,
    head_npc_data: Dictionary,  # name, alignment, basic stats; can be omitted
                                # for a fully-procedural fill
    calendar_day: int,
) -> Dictionary
    # Creates:
    #   1. A new character row (the off-map force's head — placeholder NPC).
    #   2. A new realms row with realm_kind='tracked' (the off-map force now
    #      has an in-simulation realm; future moves use the same APIs as
    #      other tracked realms).
    # Returns: { realm_id, head_character_id }

# Local succession NPC spawning for loot-and-scoot.
static func spawn_local_succession_npc(
    domain_id: String,
    calendar_day: int,
) -> String  # returns the new character_id
    # Creates a placeholder NPC matching the domain's remaining population:
    # alignment from the domain row, name from a culture-keyed name list
    # (placeholder string list until the generator ships), basic ability
    # scores from rolling 3d6 down the line. The character_type is 'npc'.

# Pillage application.
static func apply_pillage(domain_id: String, severity: int) -> Dictionary
    # severity in {0, 1, 2} (none / light / heavy). Effects per DaW pillage
    # rules + acore_axioms §land_improvement L207-215:
    #   light:
    #     - treasury_cp → 0 (looted entirely; reported in result)
    #     - peasant_families → -10%
    #     - stronghold shp → -25% (may trigger mark_stronghold_collapsed)
    #     - land_value → -1 on each owned hex (capped at minimum 1)
    #   heavy:
    #     - peasant_families → -25%
    #     - stronghold shp → -50%
    #     - land_value → -2 on each owned hex (capped at 1)
    # Returns: { looted_cp, families_lost, shp_lost, land_value_delta_per_hex }
```

### Retroactive 11B fix (this is the main behavioral change)

**`LifecycleHandler.conquer_domain` signature changes.** Old:
```
conquer_domain(domain_id, calendar_day, conqueror_kind, conqueror_id, pillage_summary)
```

New:
```
conquer_domain(
    domain_id: String,
    calendar_day: int,
    outcome: String,          # 'occupied' | 'looted_local_succession' | 'salted_to_ruin'
    new_owner_id: String,     # ignored when outcome == 'salted_to_ruin'
    pillage_severity: int,    # 0 / 1 / 2
    summary: Dictionary,
)
```

Dispatch:
- `occupied`: `RealmRepository.apply_pillage(domain_id, pillage_severity)`; `reassign_domain_owner(domain_id, new_owner_id)`; lifecycle stays `active`. Log entry `conquered` with `outcome='occupied'`.
- `looted_local_succession`: `apply_pillage`; `reassign_domain_owner(domain_id, new_owner_id)` (the local-succession NPC's id); lifecycle stays `active`. Log entry `conquered` with `outcome='looted_local_succession'`.
- `salted_to_ruin`: `release_domain_hexes`; treasury forfeit; lifecycle → `salted_to_ruin`. Hexes released. Log entry `conquered` with `outcome='salted_to_ruin'` (or `salted_to_ruin` as its own event_type — TBD during build).

**`CONQUEROR_PLAYER` constant deleted.** `same_campaign_npc` and `foreign_realm` constants deleted. The vassal cascade logic (`_cascade_vassals`) is unchanged.

**`_on_siege_concluded` rewires** to call `RealmRepository.resolve_conquest_outcome` and pass the result through to the revised `conquer_domain`:

```gdscript
func _on_siege_concluded(siege_id, outcome_label):
    if outcome_label not in ['captured', 'surrendered']: return
    var siege = SiegeRepository.get_siege(siege_id)
    var attacker_intent = _derive_attacker_intent(siege)
    var resolution = RealmRepository.resolve_conquest_outcome(
        siege.domain_id, siege.besieging_army_owner_id, attacker_intent)
    if resolution.outcome == 'occupied' and resolution.new_owner_id.is_empty():
        # Off-map force occupying — instantiate the realm + head NPC first.
        var realm_data = RealmRepository.instantiate_realm_for_off_map_force(
            siege.campaign_id, 'placeholder', {},
            _calendar_day_from_date(Timekeeping.get_date()))
        resolution.new_owner_id = realm_data.head_character_id
    elif resolution.outcome == 'looted_local_succession':
        resolution.new_owner_id = RealmRepository.spawn_local_succession_npc(
            siege.domain_id, _calendar_day_from_date(Timekeeping.get_date()))
    LifecycleHandler.conquer_domain(
        siege.domain_id, _calendar_day_from_date(Timekeeping.get_date()),
        resolution.outcome, resolution.new_owner_id,
        resolution.pillage_severity, {siege_id: siege_id})
```

The `_derive_attacker_intent` helper is project-designed; v1 default heuristic:
- Player attackers: UI surfaces a choice (Occupy / Loot-and-leave / Salt-the-earth) at siege conclusion.
- Tracked-NPC attackers: derive from realm alignment + BR ratio + faction relation.
  - Hostile relation + chaotic alignment + overwhelming BR → may salt-the-earth.
  - Hostile relation + BR ≥ 2× defender → loot-and-scoot likely; occupy possible.
  - Cordial/neutral relation → occupy default.
- Off-map / foreign-realm attackers: occupy default; salt-the-earth at the same threshold as chaotic NPCs.

### Schema migration 125 `125_lifecycle_state_salted_rename.sql`

```sql
-- Rename the 'lost_to_foreign' lifecycle_state value to 'salted_to_ruin'.
-- The CHECK constraint must be rebuilt; use the SQLite table-rebuild pattern
-- (BEGIN TRANSACTION + foreign_keys=OFF + legacy_alter_table=ON).
PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;
BEGIN TRANSACTION;
UPDATE domains SET lifecycle_state = 'salted_to_ruin' WHERE lifecycle_state = 'lost_to_foreign';
-- Then rebuild the domains CHECK constraint to:
--   CHECK(lifecycle_state IN ('active', 'ruined_stronghold', 'succession_pending',
--                             'abandoned', 'salted_to_ruin'))
-- (Concrete SQL via the rebuild pattern from migration 117.)
COMMIT;
PRAGMA foreign_keys = ON;
```

### Tests for 0b

- `test_realm_reification.gd`:
  - `instantiate_realm_for_off_map_force_creates_realm_and_head` — both rows exist; head's character_type is 'npc'.
  - `spawn_local_succession_npc_creates_npc_matching_domain_alignment` — alignment field copied; character_type 'npc'.
  - `apply_pillage_light_reduces_population_and_treasury` — verify percentages match the spec.
  - `apply_pillage_heavy_reduces_more` — verify the doubled severity.
  - `apply_pillage_land_value_floor_is_1` — never drops below 1.
- `test_lifecycle_conquest_outcomes.gd` (replaces some tests in `test_lifecycle_handler.gd`):
  - `conquer_domain_occupied_preserves_hexes_and_population` — opposite of the current behavior; hexes stay.
  - `conquer_domain_looted_local_succession_spawns_npc_and_applies_pillage` — verify the NPC is the new owner; verify pillage applied.
  - `conquer_domain_salted_to_ruin_releases_hexes_and_disperses` — only this outcome is terminal.
  - `conquer_domain_outcome_player_kind_constant_deleted` — fail-static check that the constant isn't referenced.
- Sub-tab `test_lifecycle_conquest_occupied_does_not_skip_in_monthly_tick` — `occupied` rows keep ticking.
- The old `test_conquest_foreign_realm_terminal_state_and_releases_hexes` test deletes — its behavior is no longer correct.

### GDD updates (0b)

- `gdd-domain-tab.md` §16.4 rewritten again: drop the three conqueror_kind dispatch paths; introduce the three outcomes; document the off-map-force instantiation flow + loot-and-scoot + salt-the-earth.
- `docs/coding_conventions.md` §60 (or §61) appended: the three-outcome conquest taxonomy + the polymorphic new_owner_id pattern.

---

## Phase 11D-prereq.A — GDD: Domain Style + Alignment Taxonomy

### What it produces

`generation/gdd-domain-style-and-alignment.md` — the canonical design doc for the two-axis model that 11D.1 (schema) and 11D.2 (clanhold mechanics) implement.

### Must specify

- The two-axis model: `domain_style` (`civilized` | `clanhold`) and `alignment` (`lawful` | `neutral` | `chaotic`) as orthogonal.
- Establishment eligibility per (ruler-alignment × style × method):
  - Lawful char + `METHOD_CLEAR` vs. beastman lair: ALLOWED.
  - Lawful char + `METHOD_CONQUEST` vs. beastman clanhold: BLOCKED.
  - Lawful char + `METHOD_CLANHOLD_ANNEX` / `METHOD_RECRUIT_CHIEFTAIN`: BLOCKED.
  - Lawful char + clanhold-style establishment via cleared wilderness: ALLOWED (with chosen alignment).
  - Lawful char + `METHOD_CONQUEST` vs. non-beastman chaotic civilized domain: ALLOWED with alignment-penalty.
  - (Symmetric rules for neutral / chaotic chars — neutral can establish any; chaotic can establish or annex but with the chaotic-style restrictions.)
- Conquest-time alignment transition rules: when a chaotic ruler conquers a lawful domain (occupied outcome), does the domain alignment change immediately, gradually (religion conversion), or stay until conversion completes? Default: stays until religion conversion completes; meanwhile the −2 morale alignment penalty applies per `acore_axioms` L461-475.
- Schema column design for 11D.1 (column names, CHECK constraints, deprecation path for `is_chaotic_domain`).
- Open questions for Jedidiah review: any edge cases the GDD surfaces that need clarification.

### Cross-doc references

- `memory/feedback_clanhold_vs_chaotic_alignment.md` for the project's stance.
- `ax_domains_of_chaos.xml` for RAW.
- `acore_axioms_strongholds_and_domains.xml` L461-475 for alignment-vs-religion morale penalty.

### Output

A markdown file in `generation/`. No code changes. The GDD becomes the authoritative spec for 11D.1-4 implementation.

---

## Phase 11D-prereq.B — GDD: Religion Conversion Process

### What it produces

`generation/gdd-religion-conversion.md` — project-designed mechanic for converting a domain's religion (and thereby its alignment per `acore_axioms` §alignment_and_religion).

### Must specify

- Trigger conditions: who can initiate, when, and what blocks (e.g., active heresy / excommunication state).
- Timeline: how many months / years does conversion take? Linear or curve? Reduced by divine power / cleric presence / charisma?
- Cost: gp investment per month? Divine power consumption? Personnel requirement (cleric/bladedancer of new religion in residence)?
- Morale curve during conversion: the `-2` alignment penalty plus an interim conversion-progress penalty that decays as conversion completes?
- Success / failure modes: what fails conversion? Catastrophic failure consequences (religious revolt, sub-vassal defection, etc.)?
- UI surface: where does the player drive this from? Faith block in Class-Specific sub-tab? Decrees & Remote Orders? Project decision.
- Data model: a `religion_conversions` table tracking active conversions; integration with the Faith block from Phase 10A.2.

### Cross-doc references

- `acore_axioms_strongholds_and_domains.xml:245` "Changing religion is possible but causes severe morale penalties" — the RAW anchor.
- `gdd-domain-tab.md` §16.4-5 for the lifecycle integration points (conquest, succession).

### Output

A markdown file in `generation/`. Implementation lands in 11D.3.

---

## Phase 11D-prereq.C — GDD: Tribal Warrior Subsystem

### What it produces

`generation/gdd-tribal-warriors.md` — project-designed subsystem for the clanhold-specific tribal warrior levy.

### Must specify

- Recruitment: 1 tribal warrior per beastman family per `ax_domains_of_chaos` §military L37-40. How is the recruitment tracked (a roster? per-family flag?)?
- Wages: per the user's prior clarification, tribal warriors have different upkeep + loot share expectations than mercenary troops. Specify the numbers (RAW citation if extant, project-designed otherwise).
- Retention: do tribal warriors disband when not called to arms? Stay on standing roster? Project decision.
- Loot share: what cut do they take of pillage / treasure? Vs. mercenary contracts?
- Calling to arms: per `ax_domains_of_chaos.xml:54` — chieftain may call half tribal warriors as 1 favor or all as 2 favors. Integration with Phase 8 Favors & Duties.
- Army integration: how do tribal warriors slot into the Phase 6A/B army warfare layer? Are they a new `troop_units.troop_type`? Or a separate `tribal_warrior_units` table?
- UI surface: where do tribal warriors render? Garrison sub-tab extension? New surface in the (future) chaotic-clanhold Class-Specific block?

### Cross-doc references

- `ax_domains_of_chaos.xml` §military L37-40, §vassalage_limits L54.
- `gdd-troops-tab.md` for troop_units integration.
- `gdd-army-warfare.md` for army-warfare integration.

### Output

A markdown file in `generation/`. Implementation lands in 11D.5.

---

## Phase 11D.1 — Schema migration: orthogonal style + alignment columns

### What it produces

Migration 126 (or whatever's next after 0a/0b's 124-125): adds `domain_style` + `alignment` columns to `domains` (alignment may already exist from Phase 0 — confirm and reuse if so); backfills both from `is_chaotic_domain`; deprecates `is_chaotic_domain` as derived-read-only.

### Schema

```sql
ALTER TABLE domains ADD COLUMN domain_style TEXT NOT NULL DEFAULT 'civilized'
    CHECK(domain_style IN ('civilized', 'clanhold'));
-- alignment column already exists from Phase 0 schema (CHECK lawful/neutral/chaotic).
-- Backfill domain_style: rows with is_chaotic_domain=1 OR establishment_method
-- in ('clanhold_annex', 'recruit_chieftain') → 'clanhold'; otherwise 'civilized'.
UPDATE domains
SET domain_style = 'clanhold'
WHERE is_chaotic_domain = 1
   OR establishment_method IN ('clanhold_annex', 'recruit_chieftain');
CREATE INDEX IF NOT EXISTS idx_domains_style ON domains(domain_style);
```

### Engine

- Audit every read of `domains.is_chaotic_domain` (per the recon list from the earlier session: `garrison_expenditure_calculator.gd`, `campaign_repository.gd`, `establish_domain_flow.gd`) and rename to the appropriate `domain_style == 'clanhold'` or `alignment == 'chaotic'` check depending on the mechanic. Document the deprecation in `coding_conventions.md`.
- `is_chaotic_domain` stays as a column for backwards compatibility; future migration may drop it entirely.

### Tests

- `test_domain_style_alignment_columns.gd`:
  - Migration backfills `clanhold` style for is_chaotic_domain=1.
  - Migration backfills `clanhold` style for clanhold_annex / recruit_chieftain establishment.
  - All other rows → 'civilized'.
  - CHECK constraint rejects invalid values.

---

## Phase 11D.2 — Clanhold mechanics (style-driven, alignment-agnostic)

### What it produces

Every resolver branch that fires on **clanhold style regardless of alignment** per `ax_domains_of_chaos` §exceptions_from_clanholds.

### Engine resolver patches

- `domain_revenue_calculator.gd`:
  - Halved land revenue past 125 fam/hex (per L79): `floor(min(fam, 125) * land_value) + floor(max(0, fam - 125) * land_value / 2)`.
  - 7gp/family urban revenue cap (per L85): `min(per_family_normal, 7)` when `domain_style == 'clanhold'`.
- `domain_growth_resolver.gd`:
  - 2,000gp per 1d10 new families (per L83): double the lawful base cost.
  - Urban-cap bypass (per L80): no 250 fam / 12.5%-of-peasants cap for clanhold-style urban.
- `domain_expense_calculator.gd`:
  - +2gp morale-incentive bonus per family (per L86): adds to morale-incentive tier, not to hard floor.
- `oversee_investment.gd`:
  - Halved value (per L82): pending_investment_cp halves when target domain is clanhold-style. Per the user's S5 clarification, the rule applies to ALL urban + agricultural investment, not just the activity.
- `classification_advancement.gd`:
  - Chaotic distance overloads (per L76-77): borderlands ≤50mi same-realm; civilized ≤25mi same-realm. Consumes `RealmRepository.get_relation` to enforce "same realm" — defender's realm == friendly settlement's realm.
- Phase 5 `conscript_troops.gd`, `levy_militia.gd`: reject for clanhold-style (chieftain vassalage limits).
- Phase 8 council / loans handlers: reject for clanhold-style.
- Phase 7 `grant_title` handler: reject for clanhold-style.
- Phase 10B.2 `monopoly_holdings` establishment: reject when settlement's containing domain is clanhold-style.

### Tests

- `test_clanhold_revenue_urban_cap.gd` (clanhold class V at 200 fam → 1,400 gp).
- `test_clanhold_revenue_land_halved_above_125.gd` (200 fam at 4gp land → 650 gp/hex).
- `test_clanhold_growth_new_family_cost.gd` (2,000gp per 1d10).
- `test_clanhold_expense_morale_incentive_plus_2.gd`.
- `test_clanhold_investment_value_halved.gd`.
- `test_clanhold_advancement_distance_gates.gd` (chaotic and lawful both gated; same-realm enforcement).
- `test_clanhold_vassalage_limits.gd` (conscript / militia / council / loans / monopoly / grant_title rejected).

---

## Phase 11D.3 — Alignment effects (alignment-driven, style-agnostic)

### What it produces

The alignment-vs-religion morale penalty + the beastman-ruler-over-kin stack + the religion conversion mechanic from 11D-prereq.B.

### Engine resolver patches

- `domain_morale_resolver.gd`:
  - Alignment penalty per `acore_axioms` L461-475: −1 for L/C ruler in N domain; −1 for N ruler in L/C domain; −2 for L↔C ruler/domain mismatch.
  - Beastman-ruler-over-kin: additional −2 when ruler character is beastman AND domain population is kin. Beastman detection placeholder until the kin/beastman terminology rolls into character_data (see `memory/feedback_acks_kin_terminology.md`).
- New `engine/subsystems/domains/religion_conversion_handler.gd`: implements the project-designed conversion mechanic from 11D-prereq.B.

### Schema (migration 127 or per the conversion GDD)

A `religion_conversions` table per the GDD spec — tracks active conversions, monthly progress, accumulated cost.

### Tests

- `test_alignment_morale_penalty.gd` — exhaustive ruler-alignment × domain-alignment matrix (9 cells, 4 non-zero).
- `test_beastman_kin_stack_minus_2.gd` — beastman ruler + kin domain stacks on top of alignment penalty for −4 total.
- `test_religion_conversion_timeline.gd` — verifies the conversion progresses per the GDD's project-designed curve.
- `test_religion_conversion_completes_clears_alignment_penalty.gd`.

---

## Phase 11D.4 — Establishment + lifecycle integration

### What it produces

`EstablishDomainFlow` accepts `(domain_style, alignment)` params with eligibility validation per 11D-prereq.A. Conquest paths update style/alignment correctly when a ruler takes over an opposite-alignment domain. S3 enforcement (lawful blocked from beastman clanhold conquest) lands here.

### Engine

- `establish_domain_flow.gd`:
  - `available_paths(character, classification, in_own_race_area)` consults the 11D-prereq.A eligibility matrix.
  - S3 enforcement: lawful char + METHOD_CONQUEST/CLANHOLD_ANNEX/RECRUIT_CHIEFTAIN vs. beastman lair → reject with documented error code.
  - `establish_domain(params)` writes both `domain_style` and `alignment` columns; force-locks `style='clanhold'` for chaotic-method paths.
- `LifecycleHandler.conquer_domain` (already updated by 0b): the `occupied` outcome may need to flip alignment depending on conqueror's intent (assimilate vs. convert vs. leave-as-is — project-designed via the conversion GDD).

### Tests

- `test_establish_domain_eligibility_matrix.gd` — exhaustive ruler-alignment × method × target-type matrix.
- `test_establish_lawful_blocked_from_beastman_conquest.gd` — S3 enforcement.
- `test_establish_lawful_allowed_to_clear_beastman_lair.gd` — METHOD_CLEAR allowed.
- `test_conquest_alignment_transition.gd` — chaotic ruler conquers lawful domain; alignment stays lawful until conversion completes; −2 morale active.

---

## Phase 11D.5 — Tribal warrior subsystem

### What it produces

Data + handlers per 11D-prereq.C's GDD. Recruitment, wages, retention, loot share, calling-to-arms integration.

### Engine

Per the GDD. Likely:
- A `tribal_warrior_units` table (or `troop_units.troop_type='tribal_warrior'` extension).
- A `tribal_warrior_handlers.gd` module for recruitment + call-to-arms.
- Phase 6A/B army integration (if specified by the GDD as in-scope for 11D vs. a Phase-6 revisit).

### Tests

Per the GDD's verification spec.

---

## Phase 11E — Scenario harness + the eight end-to-end scenarios

### What it produces

`tests/scenarios/` directory with `scenario_runner_base.gd` (shared multi-month integration test scaffolding) plus eight named scenarios from the roadmap. Runs headlessly under `test_runner.tscn`.

(Unchanged from the original Phase 11E spec.)

### Eight scenarios

1. `domain_full_loop_fighter_borderlands.gd`
2. `domain_realm_with_vassals.gd`
3. `domain_chaotic_clanhold.gd` — **updated** to test clanhold mechanics (style-driven) + chaotic alignment penalty (alignment-driven) as separate concerns per 11D's orthogonal-axes model.
4. `domain_pre_9_path.gd`
5. `domain_succession.gd` — exercises 11C: ruler death, designate-heir, both grace-resolution paths, non-henchman −2.
6. `domain_below_sufficiency.gd`
7. `domain_repression_morale_cap.gd`
8. `domain_land_improvement.gd`

**New scenario candidates** (to consider during 11E):
9. `domain_conquest_outcomes.gd` — exercises all three outcomes of the post-0b conquest taxonomy (occupied / looted_local_succession / salted_to_ruin) end-to-end.
10. `domain_vassal_succession_reverts_to_overlord.gd` — 11C's reverts-to-overlord default.

---

## Phase 11F — Empty-state polish + closeout

### What it produces

GDD §19 class-tailored empty-state pre-filled forms become real UI. Manual smoke test of all nine sub-tabs across every class. Phase 11 handoff doc.

(Unchanged from the original Phase 11F spec — see prior plan revision for the catalog of class-paths.)

### Output

- `engine/subsystems/domains/class_empty_state_guidance.gd` (new).
- `scenes/ui/notebook/domain/empty_state/empty_state_page.tscn` (new).
- `docs/phase-11-handoff.md` — closeout doc.

---

## Critical files inventory (updated)

### Shipped (11A + 11B + 11C)

- `db/migrations/121_domain_departure_log.sql`
- `db/migrations/122_domain_lifecycle_state.sql`
- `db/migrations/123_domain_succession.sql`
- `db/schema.sql` (updated through migration 123)
- `engine/subsystems/domains/departure_log_recorder.gd`
- `engine/subsystems/domains/lifecycle_handler.gd`
- `engine/subsystems/domains/ruler_death_handler.gd`
- `engine/autoloads/event_bus.gd` (12 new signals across 11A/B/C)
- `engine/autoloads/campaign_repository.gd` (8 new helpers across 11A/B/C)
- `engine/subsystems/session/handlers/domain_handlers.gd` (transition hooks + 3 signal bridges)
- `engine/subsystems/domains/establish_domain_flow.gd` (establishment log hook)
- `scenes/ui/notebook/domain/sub_tabs/departure_log_sub_tab.gd`
- `scenes/ui/notebook/domain/sub_tabs/overview_sub_tab.gd` (Domain Management card + Abandon dialog + Heir picker)
- `scenes/ui/notebook/domain/status_header.gd` (succession banner)
- `scenes/ui/notebook/tab_pages/domain_tab_page.gd` (departure_log sub-tab entry)
- `tests/test_departure_log_*.gd` (4 suites: recorder, classification hook, morale tier hook, sub-tab visibility)
- `tests/test_lifecycle_handler.gd`
- `tests/test_ruler_death_handler.gd`
- `docs/coding_conventions.md` §§57-59
- `generation/gdd-domain-tab.md` §§14, 16.4, 16.5, 9.4

### To create

- `db/migrations/124_realm_substrate.sql`
- `db/migrations/125_lifecycle_state_salted_rename.sql`
- `db/migrations/126_domain_style_column.sql` (or whatever's next after 0b)
- `db/migrations/127_religion_conversions.sql` (per 11D-prereq.B)
- `db/migrations/128_tribal_warriors.sql` (per 11D-prereq.C)
- `engine/subsystems/realm_ai/realm_repository.gd` (foundation + reification)
- `engine/subsystems/domains/religion_conversion_handler.gd` (per 11D-prereq.B)
- `engine/subsystems/domains/class_empty_state_guidance.gd` (per 11F)
- `engine/subsystems/domains/tribal_warrior_handlers.gd` (per 11D-prereq.C — exact path per GDD)
- `scenes/ui/notebook/domain/empty_state/empty_state_page.{tscn,gd}` (per 11F)
- `tests/test_realm_substrate.gd`
- `tests/test_realm_reification.gd`
- `tests/test_lifecycle_conquest_outcomes.gd` (replaces parts of test_lifecycle_handler)
- `tests/test_domain_style_alignment_columns.gd`
- `tests/test_clanhold_*.gd` (per 11D.2's 7 test suites)
- `tests/test_alignment_morale_penalty.gd`
- `tests/test_religion_conversion_*.gd`
- `tests/test_establish_domain_eligibility_matrix.gd` + 11D.4 supporting tests
- `tests/scenarios/scenario_runner_base.gd` + `scenarios_group.gd` + 8-10 scenario files
- `generation/gdd-domain-style-and-alignment.md` (per 11D-prereq.A)
- `generation/gdd-religion-conversion.md` (per 11D-prereq.B)
- `generation/gdd-tribal-warriors.md` (per 11D-prereq.C)
- `docs/phase-11-handoff.md` (per 11F)

### To modify

- `engine/autoloads/event_bus.gd` (faction signals will land in Phase 12; 11D may add a few intermediate ones)
- `engine/autoloads/campaign_repository.gd` (realm cache field on domains + new helpers)
- `engine/subsystems/domains/lifecycle_handler.gd` (revised `conquer_domain` signature in 0b — DELETE `CONQUEROR_PLAYER` constant)
- `engine/subsystems/session/handlers/domain_handlers.gd` (`_on_siege_concluded` rewires through `RealmRepository.resolve_conquest_outcome`)
- `engine/subsystems/domains/domain_revenue_calculator.gd` (clanhold branches)
- `engine/subsystems/domains/domain_growth_resolver.gd` (clanhold branches)
- `engine/subsystems/domains/domain_expense_calculator.gd` (clanhold branches)
- `engine/subsystems/domains/classification_advancement.gd` (same-realm gates)
- `engine/subsystems/domains/domain_morale_resolver.gd` (alignment penalty + beastman-kin stack)
- `engine/subsystems/activities/handlers/oversee_investment.gd` (clanhold halving)
- Phase 5 `conscript_troops.gd`, `levy_militia.gd` (clanhold reject)
- Phase 7 `grant_title.gd` (clanhold reject)
- Phase 8 council / loans handlers (clanhold reject)
- Phase 10B.2 `monopoly_holdings` establishment (clanhold-settlement reject)
- `engine/subsystems/domains/establish_domain_flow.gd` (style + alignment params + S3 enforcement)
- `engine/subsystems/troops/garrison_expenditure_calculator.gd` (rename `is_chaotic_domain` reads)
- `scenes/ui/notebook/tab_pages/domain_tab_page.gd` (empty-state replacement)
- `generation/gdd-domain-tab.md` (§16.4 revised again by 0b for the three-outcome taxonomy; §19 empty-state per 11F)
- `docs/coding_conventions.md` (§§60+ for realm substrate, conquest taxonomy, style/alignment columns)
- `docs/document_map.md` and `docs/rule_system_map.md` (Phase 11 surface area)
- `tests/test_runner.gd` and `tests/test_runner.tscn` (new suite registrations)

### Reused (do not duplicate)

- `engine/subsystems/realm_ai/vassal_repository.gd` — Phase 7 vassal-cascade logic continues to apply.
- `engine/autoloads/timekeeping.gd` — `advance_months / day_changed / month_changed`.
- `engine/subsystems/session/scheduler/event_scheduler.gd` — already drives the monthly tick.
- `engine/subsystems/henchmen/henchman_lifecycle_manager.gd` — model for new placeholder NPC creation in 0b.

---

## Sequencing diagram

```
11A ✅ → 11B ✅ → 11C ✅
                    ↓
              11D-prereq.0a (Realm Substrate foundation)
                    ↓
              11D-prereq.0b (Realm Reification + Pillage + 11B retroactive fix)
                    ↓
        ┌───────────┼───────────┐
        ↓           ↓           ↓
   11D-prereq.A 11D-prereq.B 11D-prereq.C
   (Style+Align (Religion    (Tribal
    GDD)         Conversion   Warriors
                 GDD)         GDD)
        └───────────┼───────────┘
                    ↓
              11D.1 (Schema: style + alignment columns)
                    ↓
              11D.2 (Clanhold mechanics) ─┐
                                          │
              11D.3 (Alignment effects) ──┼─→ 11E (Scenarios)
                                          │       ↓
              11D.4 (Establishment) ──────┤   11F (Closeout) — parallel
                                          │
              11D.5 (Tribal warriors) ────┘
```

- 11A → 11B → 11C is strict (each builds on the prior's signals/state).
- Realm Substrate (0a → 0b) sequential; 0b can't ship without 0a's tables.
- The three prereq GDDs (A, B, C) can be drafted in parallel sessions; they don't strictly depend on each other.
- 11D.1 (schema) must land before 11D.2-4 (which read the new columns).
- 11D.2-5 can ship in any order after 11D.1 — each touches a distinct resolver surface.
- 11E (scenarios) waits on 11A-D being complete.
- 11F (empty-state polish + closeout) runs alongside 11E.

---

## Estimated sub-phase effort

| Sub-phase | Files touched | New tests | Notes |
|---|---|---|---|
| **11A** | ~7 (shipped) | 4 suites | Substrate work; biggest piece was export helpers + sub-tab UI |
| **11B** | ~10 (shipped) | 1 suite (12 tests) | Lifecycle handler; broad surface area |
| **11C** | ~6 (shipped) | 1 suite (14 tests) | Succession state machine + UI banner/picker |
| **11D-prereq.0a** | ~4 new, ~1 modified | 1 suite | Tables + helpers + outcome resolver. ~1 session. |
| **11D-prereq.0b** | ~3 new, ~5 modified | 2 suites | Realm instantiation + pillage + 11B retroactive fix. ~1 session. |
| **11D-prereq.A** | 1 new GDD | (no code) | Design doc. ~1 session of focused drafting. |
| **11D-prereq.B** | 1 new GDD | (no code) | Design doc. ~1 session. |
| **11D-prereq.C** | 1 new GDD | (no code) | Design doc. ~1 session. |
| **11D.1** | ~5 modified | 1 suite | Schema migration + rename audit. |
| **11D.2** | ~9 modified resolvers | ~7 suites | Clanhold mechanics; broad surface but mechanically simple |
| **11D.3** | ~2 new, ~2 modified | ~4 suites | Alignment + religion conversion |
| **11D.4** | ~2 modified | ~4 suites | Establishment eligibility + S3 |
| **11D.5** | per GDD | per GDD | Tribal warriors |
| **11E** | ~10 new (harness + 8-10 scenarios) | 8-10 scenarios | Scenarios shake out integration bugs |
| **11F** | ~3 new, ~5 modified | (manual smoke) | Empty-state polish + closeout doc |

Total Phase 11 ahead: ~10-12 sessions including the prereq GDDs.

---

## Verification strategy

Per sub-phase: focused unit tests + integration tests.

Per milestone:
- **After 11C ✅:** Domain lifecycle is end-to-end functional. Departure Log + Lifecycle + Succession all wired.
- **After 11D-prereq.0b:** Conquest taxonomy revised; 11B's deferred siege-conqueror-kind detection closed. Verify by running scenario `domain_conquest_outcomes.gd` once it's drafted.
- **After 11D.5:** Chaotic-domain branch + tribal warriors complete. Full chaotic clanhold playable.
- **After 11E:** All scenarios pass headlessly. ~330-suite battery stays in documented flake band.
- **After 11F:** Phase 11 closeout. Visual smoke-test all nine sub-tabs across every class bucket.

Data integrity (the roadmap's "no derived-state drift" rule): for each scenario's final domain state, `assert_ledger_reconstructs_net_income` confirms the Treasury sub-tab's net income reconstructs from ledger rows alone.

The Departure Log is append-only — `coding_conventions.md` §57 forbids `UPDATE / DELETE` against `domain_departure_log` anywhere in `engine/`.

---

## Where this plan is anchored

- This file: `docs/phase-11-plan.md`
- Roadmap source: `docs/domain-roadmap-corrected.md` Phase 11 (line 439+) and Appendix A (RAW Patches)
- Memory:
  - `memory/feedback_clanhold_vs_chaotic_alignment.md` — orthogonal-axes design
  - `memory/feedback_acks_kin_terminology.md` — kin / humanoid / beastman vocabulary
  - `memory/project_dynasties_succession.md` — eventual replacement for the vassal-reverts-to-overlord default
- GDD sources:
  - `generation/gdd-domain-tab.md` §9.4, §14, §16.4-5, §19
  - `generation/gdd-domain-style-and-alignment.md` (to be created per 11D-prereq.A)
  - `generation/gdd-religion-conversion.md` (to be created per 11D-prereq.B)
  - `generation/gdd-tribal-warriors.md` (to be created per 11D-prereq.C)
- Coding conventions: `docs/coding_conventions.md` §§57-59 (shipped); §§60+ (this phase ahead)
- RAW sources cited inline above
- Build log entries: `build_log.md:24443` (11A), `build_log.md:24503` (11B), `build_log.md:24573` (11C)
