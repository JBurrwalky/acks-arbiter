# GDD: Savegame System

**Document type:** Game Design Document (project-designed, architecture)
**Authority:** PROJECT-DESIGNED — persistence and serialization engineering. Subordinate to [acks_arbiter_design_brief_v11.md](../docs/acks_arbiter_design_brief_v11.md). The two cross-system contracts introduced here — the `SessionState.flush_to_db()` hook (§5.3) and the context-aware loader branch (§5.6) — touch the session-runner state machine and require Jedidiah's sign-off before landing.
**Status:** Draft v1.4 — **Phases S-1, S-2, S-3 LANDED 2026-06-07.** S-1: faithful continuous save (per-party context + position, full-fidelity per-member dungeon restore, explored-state merge-on-load, context-aware loader, no-save-in-combat). S-2: named saves = **whole-DB capture (VACUUM INTO) + per-campaign-scoped restore (ATTACH)** — structurally complete (scope map covers all 135 tables, completeness-tested) AND **campaign-isolated** (loading one adventure never touches another; Jedidiah's choice). S-3: `save_to_slot`/`load_slot` + Save/Load panel + pause-menu entry. Verified net-zero new test failures (427 pass / 19 pre-existing); data layer covered by `tests/test_savegame_location.gd` + `tests/test_savegame_snapshot.gd`; UI + load-flow re-entry pending in-game acceptance. Design agreed 2026-06-06; follow-up rulings 2026-06-07 (per-member exact-cell restore; best-effort slot migration + warn; one unified save system, GM distinction retired; mid-combat save disallowed; **per-campaign slot isolation**).
**Implementing files:** `engine/autoloads/campaign_repository.gd` (S-1 location/settlement/per-entity-dungeon CRUD + `get_dungeon_entrance_for_dungeon_id`; S-2 `save_snapshot` (VACUUM INTO) / `restore_snapshot` + `_restore_campaign_from_slot` + `_campaign_scope_entries` + `_dungeon_ids_for_campaign` + `_shared_columns`/`_table_exists`/`_quote_cols`/`_placeholders` + `get_snapshot`/`delete_snapshot`/`prune`/`_wipe_save_slot_files`), `engine/shared_types/party_data.gd` (location fields), `engine/subsystems/session/session_state.gd` (`flush_to_db` + `is_in_combat` virtuals), `engine/subsystems/session/session_runner.gd` (location-type write, flush dispatch, combat guard, `save_to_slot`/`load_slot`/`_current_location_label`), `engine/subsystems/session/states/{wilderness,dungeon,settlement}_explore_state.gd`, `engine/subsystems/session/states/session_load_state.gd` (context-aware loader), `engine/subsystems/exploration/dungeon_map_controller.gd` (`_merge_persisted_cell_state` + `restore_entity_positions`), `scenes/ui/saveload/save_load_panel.gd` (S-3 UI), `scenes/ui/pause/pause_menu_overlay.gd`, `db/migrations/146_dungeon_entity_positions.sql`, `db/migrations/147_savegame_slot_metadata.sql`, `tests/test_savegame_location.gd`, `tests/test_savegame_snapshot.gd`.
**Depends on ACKS rules:** None. ACKS 1e does not specify computer savegames. The restore path must, however, preserve the project's clock invariants (§3).
**Depends on project GDDs:** [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md) (scheduled-event queue serialization, single shared timeline + order-lock semantics, combat-pause, context-as-entity-property); [gdd-dungeon-map-ui.md](gdd-dungeon-map-ui.md) (dungeon voxel grid + entity placement); [gdd-settlement-exploration-ui.md](gdd-settlement-exploration-ui.md) (settlement POI navigation, current-POI concept).
**Modifiable by Claude Code:** Yes within constraints. The two-layer model (§4), the `flush_to_db()` hook (§5.3), and the context-aware loader (§5.6) are architecture — change only with approval. All else (which repository functions, the table-registry contents, slot-UI layout) is engineering.
**Last updated:** 2026-06-07

---

## 1. Purpose

The game must be able to **stop and resume a campaign at the exact state the player left it** — including *where the party is*, not just who is in it and what they carry. Today the persistence layer records party roster, status, and inventory faithfully, and it restores the party's **wilderness hex** correctly, but it does **not** restore a party that was inside a dungeon or a settlement: on reload such a party is silently ejected to the overworld. This GDD specifies the work to make the save *true* (it records everything needed to resume) and *accurate* (the resumed state matches the saved state).

The design also adds the player-facing feature Jedidiah requested: **named, multi-slot manual saves** layered on top of a continuous autosave, so a player can keep several restore points per campaign — not only the single live state.

This is a meta/engineering system. It exists because the project's architecture is "the SQLite database *is* the save file" (write-through persistence), and that model was never completed for the **location/context** dimension of game state.

---

## 2. Background — current state (investigation 2026-06-06)

Recorded here so future readers understand what was fixed and why the columns already exist.

### 2.1 The architecture in place

There is no separate save file. The SQLite DB is written through continuously as the player acts; "loading a campaign" re-opens that DB and rebuilds the runtime. On top of that, `SessionRunner.save_session()` ([engine/subsystems/session/session_runner.gd](../engine/subsystems/session/session_runner.gd) line ~825) flushes the handful of things that live only in memory during a session. It is invoked from the **pause-menu "Save"** ([scenes/ui/pause/pause_menu_overlay.gd](../scenes/ui/pause/pause_menu_overlay.gd) `_on_save`) and from **quit** (`end_session()` → `save_session()`).

A **second, separate** mechanism also exists: `game_snapshots` + `CampaignRepository.save_snapshot()`/`restore_snapshot()`, fronted by the GM Override panel. It is a named-snapshot JSON blob capped at 10/campaign and is **incomplete** (captures 12 tables). It is the foundation for Part B but cannot be trusted as-is.

### 2.2 What already works

| State | Mechanism |
|---|---|
| Party roster, ability scores, HP, XP, class | `characters`, written ad-hoc |
| Inventory, equipment, spells, conditions | `inventory_items` / `character_spells` / `character_conditions` |
| Travel state (rations, exhaustion, camp, lost) | `party_state`, flushed via `PartyData.to_state_dict()` |
| **Wilderness hex position** | Written on every travel leg (`update_party_position`), restored on load (`_apply_party_hex_to_loaded_map`) |
| Campaign clock, weather, active spell effects | `Timekeeping`, `WeatherCache`, `active_effects` |
| Scheduled-event queue | `scheduled_events`, serialized per [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md) §2.2 |
| Dungeon explored cells, doors, fog | `voxel_map_cells`, **written** by `_save_dungeon_cell_states()` on clean dungeon exit |

### 2.3 The gaps (what this GDD fixes)

1. **Dungeon position is never restored.** `parties.dungeon_id/level/col/row` (migration 017) are written **once on entry only**, are **not read** by `PartyData.from_db()`, and the loader (`SessionLoadState.enter`) **unconditionally transitions to wilderness**.
2. **Settlement position is never even written.** `parties.settlement_id/settlement_node_id` (migration 019) have no writer and no call site.
3. **`current_location_type` is dead.** It defaults to `'wilderness'` and is only ever written by a party-copy helper — never set to `'dungeon'`/`'settlement'` during play. The DB therefore cannot say *which context* the party was in.
4. **Dungeon explored-state is write-only.** `load_dungeon()` builds the map purely from the entrance's static generated layout and **never reads `voxel_map_cells` back**, so re-entering a dungeon shows a pristine map (fog reset, doors shut). The save in §2.2 row 7 is wasted.
5. **Saving inside a dungeon flushes nothing dungeon-related.** `save_session()` only saves the hex map (and only when in wilderness); the voxel flush lives solely in the dungeon `exit()` path.
6. **Named snapshots are incomplete** (§2.1).

**Key consequence for scoping:** wilderness and settlement restore, plus the context-type fix, need **zero schema migrations** — those columns already exist and are simply unused. Only **one new migration** is required, for full-fidelity *per-member* dungeon restore (§5.2): the single `parties.dungeon_col/row` anchor cannot hold each member's individual cell, so a small per-entity position store is added. This is overwhelmingly "merely broken," not "missing."

---

## 3. ACKS Constraints / Project Invariants the restore must respect

ACKS 1e contributes no rules to savegames. But the restored state must not violate the project's clock and context invariants, which derive from [gdd-realtime-scheduler.md](gdd-realtime-scheduler.md):

- **Single shared timeline (amended per ruling 2026-06-11).** There is one world clock (`campaign_clock`; scheduler §1.2). Per-party clocks and the dungeon time-lock were removed — migration 154 dropped `party_clocks`. A save snapshots the world clock; restore reinstates it.
- **No lock state to serialize (ruled 2026-06-12).** There is no order-lock; a party's commitments are simply its pending events in `scheduled_events`, which already round-trip. A new order supersedes them via cancellation. No dedicated lock serialization exists — do not add any.
- **Combat is a turn-based sub-game with the scheduler globally paused** (scheduler §1.1). There is no stable mid-combat scheduler state to serialize cleanly → **saving is disallowed during combat** (§5.7).
- **Context is a property of the entity, not a global mode** (scheduler §1.3). The persisted `current_location_type` is therefore a *per-party* fact, consistent with split parties (§9).
- **Idempotency guards must survive reload.** `party_state.last_day_tick_round` and similar durable guards exist precisely so a reload does not double-fire a tick (scheduler §4.4). Save/restore must round-trip them unchanged (they already do; do not regress this).

No banker's-rounding surfaces in this system (no fractional game quantities are computed here).

---

## 4. Architecture: two complementary layers

```
Layer 1 — CONTINUOUS SAVE (the live DB = the autosave)
    write-through during play  +  save_session() flush on Save/Quit
    → exactly one living state per campaign
    → Part A makes this complete & faithful (incl. location/context)

Layer 2 — NAMED SNAPSHOTS (manual, multi-slot)
    a COMPLETE point-in-time copy of all campaign-scoped tables
    → many restore points per campaign
    → Part B completes the existing game_snapshots mechanism + UI
```

The two layers are deliberately distinct: Layer 1 is the always-current state the player returns to by default; Layer 2 is opt-in restore points. A manual "Save to slot" (Layer 2) first performs a Layer-1 flush so the live DB is current, then copies it into a slot.

---

## 5. Part A — Faithful continuous save

### 5.1 Persist `current_location_type` on every context transition

Centralize in `SessionRunner.transition_to_state()`. Maintain a map of **primary location states** → location type:

| State key | `current_location_type` |
|---|---|
| `wilderness` | `wilderness` (or `sea` when the party is waterborne) |
| `dungeon` | `dungeon` |
| `settlement` | `settlement` |
| `combat`, `encounter`, `camp`, `downtime` | **unchanged** (sub-contexts inherit the underlying location) |

When the new state is a primary-location state, write the type via a new `CampaignRepository.update_party_location_type(party_id, type)` (or fold it into the existing position writes). Sub-context states must **not** overwrite it, so that combat-in-a-dungeon still restores to the dungeon.

### 5.2 Position persistence per context

**Wilderness** — already correct (`update_party_position(party_id, map_id, q, r)` on each travel leg). No change beyond also stamping `current_location_type='wilderness'`.

**Dungeon (full fidelity — "Exact cell", per member).** Persist **each party entity's exact live voxel cell** `(col, row, level)`, not a single anchor (Jedidiah 2026-06-07: re-scattering from an anchor could yank members across large distances on reload — unexpected and disruptive). At the party level, keep `parties.dungeon_id` + `parties.dungeon_level` (for the loader and camera focus); the authoritative *placement* data is per entity.
- Storage: a small dedicated table keyed by entity (§7), populated from `_voxel_map.get_entity_pos(entity_id)` for every party entity id. A per-entity table (rather than columns on `party_members`) covers PCs, henchmen, **and** any trained creatures that entered the dungeon, matching the controller's `entity_id` model.
- Update `parties.dungeon_level` on ascend/descend.
- Write positions on **scheduler pause** (the game is real-time-*with-pause*; the player saves while paused, so pause-time writes capture live cells cheaply) and again inside the `flush_to_db()` save path (§5.3). Clear them on dungeon exit (mirror `clear_party_dungeon_position`).
- On restore, after `load_dungeon()` builds the map and merges explored state (§5.4), set **each** entity's position from the stored cells — `_voxel_map.set_entity_pos(entity_id, Vector3i(col,row,level))` — so the party stands exactly where it was. `_scatter_party_at_entry` is used **only** as the fresh-entry path (no stored positions) or as a fallback for an entity with no stored cell.

**Settlement.** Persist `settlement_id` + the current POI as `settlement_node_id`. Settlements expose `get_current_poi_id()` / `set_current_poi()`, which map directly onto the unused `settlement_node_id` column. New repo fn `update_party_settlement_position(party_id, settlement_id, node_id)`, called on settlement enter and on each `set_current_poi`. Clear on exit (mirror `clear_party_dungeon_position`).

### 5.3 The `flush_to_db()` state hook (replaces the hardcoded save block)

`save_session()` currently flushes the hex map only when `_current_state_key == "wilderness"`. Replace that special-case with a virtual on the state base class:

```
SessionState.flush_to_db() -> void          # default: no-op
  WildernessExploreState.flush_to_db()       # save hex map (fog / survey progress)
  DungeonExploreState.flush_to_db()          # save voxel cells (reuse _save_dungeon_cell_states)
                                             #   + write anchor cell/level + location_type
  SettlementExploreState.flush_to_db()       # write settlement + current POI
```

`save_session()` calls `_current_state.flush_to_db()`. This (a) fixes "saving inside a dungeon loses the explored map," (b) removes the wilderness-only coupling, and (c) puts the "what is dirty in this context" knowledge in the state that owns it. **This adds one method to the `SessionState` contract — additive, within the subsystem the project owns, but flagged for approval (§12).**

### 5.4 Make `load_dungeon()` merge persisted explored-state (close the write-only gap)

After building the `VoxelMapData` from the layout, overlay the persisted rows from `voxel_map_cells` for that dungeon (the repository already has `load_voxel_cells_for_map()` / `load_voxel_map()`). Without this step, full-fidelity restore would still drop the party into a pristine dungeon. Merge semantics: persisted `door_state` and `fog_state` override the freshly-generated defaults; structural fields (solidity/feature/floor) come from the layout.

### 5.5 `PartyData` carries the location fields

Add `dungeon_id`, `dungeon_level`, `dungeon_col`, `dungeon_row`, `settlement_id`, `settlement_node_id` to `PartyData` and populate them in `from_db()`. (`get_party()` already `SELECT *`s these columns — they are merely dropped today.) `to_state_dict()` is unaffected: position lives in the `parties` table, written by the dedicated position functions, not in `party_state`.

### 5.6 Context-aware loader

`SessionLoadState.enter()` keeps loading the campaign's top-level hex map (so exiting a dungeon/settlement returns to the correct hex), then **branches on the loaded party's `current_location_type`** instead of hardcoding wilderness:

```
1. load_session(campaign_id, party_id)         # restores roster, clocks, effects, event queue
2. load + wire the top-level hex map            # as today
3. match party.current_location_type:
     "wilderness" | "sea"  -> transition_to_state("wilderness")            # works today
     "dungeon"             -> build {entrance, level} from
                              dungeon_entrances[party.dungeon_id];
                              transition_to_state("dungeon", ctx);
                              after load + voxel merge, restore EACH entity's
                              exact cell from the per-entity store (§5.2)
     "settlement"          -> load settlement; transition_to_state("settlement",
                              {settlement_id, poi_id = party.settlement_node_id})
     (unknown / stale)     -> fall back to "wilderness" + warn
```

The dungeon context dict is assembled exactly the way `WildernessExploreState._on_dungeon_entry` builds it, fetching `dungeon_data` from the `dungeon_entrances` row for the saved `dungeon_id`.

### 5.7 Combat: no mid-combat save

Per §3, saving during combat is disallowed. Guard both entry points:
- `pause_menu_overlay._on_save()` and/or `save_session()` check the combat state (`_current_state_key == "combat"` or the dungeon overlay's `_in_combat`).
- When blocked, no-op and emit a `notification_requested` toast: *"Cannot save during combat."*
- Confirm whether the pause menu is even reachable in combat; if not, this is belt-and-suspenders.

### 5.8 What continuous save captures (target state)

| Dimension | Persisted | Restored | After Part A |
|---|---|---|---|
| Roster / status / inventory / spells | ✅ | ✅ | unchanged |
| Travel / camp state | ✅ | ✅ | unchanged |
| Wilderness hex + map id | ✅ | ✅ | + stamps `location_type` |
| Hex terrain / fog | ✅ (wilderness only) | ✅ | flushed via state hook regardless of context |
| Dungeon explored cells / doors / fog | ✅ (exit only) | ❌ → **✅** | flush on save + **merge on load** |
| Dungeon position (per-member cell/level) | entry-only → **live** | ❌ → **✅** | each entity's exact cell (new per-entity store) |
| Settlement position (id/POI) | ❌ → **✅** | ❌ → **✅** | new writer + loader branch |
| `current_location_type` | dead → **live** | ❌ → **✅** | transition-time write |
| World clock / event queue / effects | ✅ | ✅ | unchanged (per-party clocks removed 2026-06-11, migration 154) |
| Roaming (pre-combat) monsters | ❌ transient | ❌ | re-rolled on next check (documented) |
| Mid-combat state | ❌ | ❌ | saving disallowed (§5.7) |

---

## 6. Part B — Named multi-slot saves

### 6.1 Foundation — one unified save system (GM/Player distinction removed)

Jedidiah 2026-06-07: the old **GM-vs-Player** framing is out of date. There is **one** save system. The `game_snapshots` table + `save_snapshot`/`restore_snapshot` — formerly fronted only by the GM `OverrideManager` — are the unified save mechanism. `OverrideManager.save_session_snapshot`/`restore_session_snapshot`/`list_session_snapshots` are now thin pass-throughs to the same `CampaignRepository` API (no code change needed — they already delegate), so the override panel is "folded in" automatically; the player-facing Save/Load screen (§6.5) is the primary entry.

### 6.2 Completeness + isolation — whole-DB capture, per-campaign restore

A "true" save must capture **every** campaign-scoped table; a save must also be **isolated** (loading one adventure must not touch another — Jedidiah 2026-06-07). The implemented design splits those two concerns:

- **Save = whole-DB capture.** `VACUUM INTO 'user://saves/<id>.db'` copies the *entire* SQLite database. Structurally complete — it is *impossible* to miss a table. (The file holds all campaigns; restore reads back only the relevant one.)
- **Restore = per-campaign scoped copy.** `ATTACH` the slot file, then for each table DELETE this campaign's rows from `main` and INSERT this campaign's rows from `slot`, scoped per-table by `_campaign_scope_entries()`. Other campaigns are never touched. Column-intersection per table keeps it robust to minor schema drift. `game_snapshots` is excluded so the slot LIST survives a restore. No DB-connection reopen (godot-sqlite mishandles close/reopen — see `wipe_for_tests`).

**The scope map (`_campaign_scope_entries`) is the registry — kept honest by a completeness test.** Every one of the 135 tables is classified: 64 direct (`campaign_id = ?`), `campaigns` (`id = ?`), ~60 FK-children (scoped via a subquery to their campaign-scoped parent — including multi-hop and multi-parent OR cases like `inventory_items` and `strongholds`), the 7 dungeon-content tables (`dungeon_floors/rooms/doors`, `monster_groups`, `treasure_hoards`, `key_items`, `voxel_map_cells`), and 4 excluded (`schema_migrations`, `schema_sweep_markers`, `dice_rolls`, `game_snapshots`). The dungeon-content tables are the hard case the original registry couldn't handle: their `dungeon_id`/`map_id` lives **inside a JSON blob** (`dungeon_entrances.dungeon_data`) with no SQL path to a campaign, so they are scoped by a **computed dungeon-id list** (`_dungeon_ids_for_campaign`, parsed from the campaign's entrances). `test_savegame_snapshot.test_scope_map_covers_all_tables` asserts `(scope map ∪ excluded) == all tables`, so a NEW table fails the suite until it is classified — the only way the registry stays trustworthy as the schema grows.

**DELETE order matters.** A child's scope reads its parent's rows, so the scope list is ordered **deepest-first** (children deleted before parents); INSERT reads from the read-only `slot`, so it is order-agnostic.

Verified by `tests/test_savegame_snapshot.gd`: round-trips data through `voxel_map_cells` (dungeon-id-list scoped) and `dungeon_entity_positions` (party-FK scoped); `test_restore_is_campaign_isolated` proves restoring campaign A leaves campaign B's data intact; and the completeness test guards the whole map.

### 6.3 Autosave vs. manual slots

- **Autosave (Layer 1):** the live DB. `save_session()` on Save/Quit; "Continue" / "Load Campaign" loads it. Exactly one working state per campaign. No separate autosave *file* is written — the live DB is the autosave. (`slot_kind = 'autosave'` is reserved in the schema for a future periodic-autosave-file feature.)
- **Manual slots (Layer 2):** named whole-DB files + a `game_snapshots` metadata row. `SessionRunner.save_to_slot(label)` flushes the live state first (so the slot is current), then `save_snapshot`. `SessionRunner.load_slot(id)` restores then re-enters via the §5.6 context-aware loader.
- Slot cap: `CampaignRepository.MAX_SLOTS_PER_CAMPAIGN` (currently 20); oldest pruned (file + row).

### 6.4 Restore semantics

`restore_snapshot` runs inside a transaction and the live DB is left untouched on any failure. **Per-campaign isolation:** a restore replaces only the slot's campaign rows (scoped per §6.2); every other campaign in the DB is left exactly as it was — loading "Ashford Vale" never rolls back "Northern Reach". The slot's `campaign_id` (metadata) selects which campaign to restore and which to enter. Because the slot's rows are inserted into `main`'s *current* schema (column intersection), `main` is never downgraded — no migration step is needed; a slot older than the current schema is restored best-effort with a warning (§9). After restore, the session is **re-entered from scratch** via `transition_to_state("session_load", {campaign_id})` (the loaded session is torn down first by `end_session`), never patched in place.

### 6.5 UI

A single player-facing **Save / Load panel** (`scenes/ui/saveload/save_load_panel.gd`, `class_name SaveLoadPanel`), opened from the pause menu's "Save / Load…" entry (there is no separate GM snapshot UI):
- Lists slots: label, location label, timestamp; **Load** and **Delete** per slot.
- A name field + **Save New Slot** button (calls `SessionRunner.save_to_slot`).
- Loading closes the panel, unpauses, and calls `SessionRunner.load_slot` (restore + context-aware re-entry).
- "Continue" / "Load Campaign" on the main menu loads the live DB (autosave). *Follow-up:* surface named-slot Load from the main menu too (the engine `load_slot` already supports a fresh-boot load).

---

## 7. Data model

**Part A: one new migration** (for per-member dungeon restore). Everything else reuses existing columns:
- `parties.current_location_type` (base table), `current_map_id`, `current_hex_q/r` — exist.
- `parties.dungeon_id/dungeon_level/dungeon_col/dungeon_row` (migration 017) — exist; `dungeon_id`+`dungeon_level` used; `dungeon_col/row` optionally kept as leader/camera-focus cell.
- `parties.settlement_id/settlement_node_id` (migration 019) — exist; now written.
- `voxel_map_cells` (migration 036) — exists; now read back on load (§5.4).
- **New** per-entity dungeon position store (§5.2):

```
dungeon_entity_positions          -- live voxel cell per party entity, while in a dungeon
  party_id    TEXT NOT NULL REFERENCES parties(id)
  entity_id   TEXT NOT NULL       -- character_id or creature_id (controller entity id)
  dungeon_id  TEXT NOT NULL
  col         INTEGER NOT NULL
  row         INTEGER NOT NULL
  level       INTEGER NOT NULL
  PRIMARY KEY (party_id, entity_id)
```

Rows are written on pause / flush and **deleted on dungeon exit**. (Final table/column names are an engineering detail; a dedicated table is preferred over columns on `party_members` so non-character entities are covered.)

**Part B: migration 147** makes `game_snapshots` slot metadata (the actual state is a whole-DB file at `user://saves/<id>.db`):

```
game_snapshots
  + slot_kind     TEXT NOT NULL DEFAULT 'manual'   -- 'manual' | 'autosave' (reserved)
  + schema_version INTEGER NOT NULL DEFAULT 0      -- migration version at capture (§9)
  + location_label TEXT NOT NULL DEFAULT ''        -- denormalized for the slot list
```

`snapshot_data` now holds a small manifest (`{"format":"db_file_v1",...}`), not table rows. Save files live under `user://saves/`; `wipe_for_tests` clears them so test runs don't accumulate orphans.

---

## 8. Save / Load lifecycle

```
SAVE (continuous)                 SAVE TO SLOT                     LOAD
─────────────────                 ────────────                     ────
player hits Save / quits          flush continuous save  ───┐      pick source:
  └ guard: not in combat          (§5 path)                 │        Continue → live DB
  └ _current_state.flush_to_db()  then snapshot ALL          │        Slot N    → restore_snapshot
  └ flush party_state             campaign-scoped tables     │      tear down runtime
  └ flush active_effects          (registry, §6.2)           │      load_session(campaign, party)
  └ flush scheduled_events        write game_snapshots row   │      load top-level hex map
  └ position already written      prune to slot cap          │      branch on location_type (§5.6)
    incrementally (§5.2)                                      │      re-enter saved context
                                                             ─┘      (dungeon merges voxel state §5.4)
```

---

## 9. Edge cases & invariants

- **Mid-activity save/restore (amended 2026-06-11/12).** A party saved mid-activity resumes it after restore because its pending events round-trip via `scheduled_events` — no dedicated state to verify. The former per-party clock / time-lock restore requirements are void, and the brief-lived order-lock was also removed (the mechanism history is in `docs/handoff_multi_party_time.md`).
- **Split parties.** `current_location_type` and position are per-party. A campaign may have one party in a dungeon and another in town. The continuous save handles all parties; the loader restores the **active** party's context and must not assume a single global context. Snapshots capture all parties' rows.
- **Cross-scale hex maps (migration 119).** A party may be on a child/inset map. Wilderness restore already projects to ancestor maps via `parent_anchor`/footprint; preserve that. `current_map_id` is the source of truth for which map to load.
- **Stale/dangling references on restore.** If `dungeon_id` no longer resolves to a `dungeon_entrances` row (e.g. an old save), the loader falls back to wilderness with a warning rather than crashing (§5.6).
- **Schema/version skew for slots (resolved 2026-06-07: best-effort + warn).** A slot captured under an older schema may not restore cleanly after migrations. Stamp `schema_version` (§7); on load, if the slot is older than current, **run the relevant migrations best-effort against the restored data and proceed**, surfacing a non-blocking warning: *"This save predates a game update and may be incomplete or unstable."* Do not refuse the load. The warning fires only when a migration actually occurred (slot version < current).
- **Concurrent Claude Code / multi-process DB access.** Out of scope for gameplay save, but noted: the build environment sometimes runs concurrent sessions against the DB; saves are single-process at runtime.
- **Autosave atomicity.** A crash mid-`save_session()` could leave a partially flushed live DB. Wrap the continuous flush in a transaction so it commits all-or-nothing (the snapshot path already does).

---

## 10. Phasing & acceptance

| Phase | Scope | Migrations | Acceptance |
|---|---|---|---|
| **S-1** | Part A §5.1–5.8 | 1 (per-entity dungeon positions, §7) | Save in dungeon → quit → reload → **every** party member stands on the exact cell/level they occupied, with the explored map intact (no re-scatter). Same for settlements (at the saved POI). Wilderness unchanged. No save offered in combat. |
| **S-2** ✅ LANDED | Part B §6.2 — whole-DB capture (VACUUM INTO) + per-campaign scoped restore (ATTACH) + migration 147 | 1 | Round-trips registry-hard tables (`voxel_map_cells`, `dungeon_entity_positions`); restoring campaign A leaves B intact; scope map covers all 135 tables. `tests/test_savegame_snapshot.gd`. |
| **S-3** ✅ LANDED | Part B §6.3–6.5 — `save_to_slot`/`load_slot` + Save/Load panel + pause-menu entry | 0 | Player can create, name, list, load, and delete multiple slots from the pause menu; loading restores into the saved context. (Engine layer; UI verified in-game.) |

S-1 alone resolves the reported bug. Each phase ships with focused tests per the project testing convention; the bar is **net-zero new failures** against the current baseline (held at 19; suites 425 → 427 across S-1/S-2).

---

## 11. Affected files (for the implementing session)

- `engine/subsystems/session/session_runner.gd` — `save_session()` → `flush_to_db()` dispatch; `transition_to_state()` location-type write; combat-save guard.
- `engine/subsystems/session/states/session_load_state.gd` — context-aware loader (§5.6).
- `engine/subsystems/session/states/{wilderness,dungeon,settlement}_explore_state.gd` — `flush_to_db()` overrides; per-move/POI position writes.
- `engine/subsystems/session/states/session_state.gd` (base) — add `flush_to_db()` virtual.
- `engine/shared_types/party_data.gd` — location fields + `from_db()`.
- `engine/subsystems/exploration/dungeon_map_controller.gd` — `load_dungeon()` merges `voxel_map_cells` (§5.4).
- `engine/autoloads/campaign_repository.gd` — `update_party_location_type`, `update_party_settlement_position`, per-entity dungeon-position CRUD (`save_dungeon_entity_positions` / `load_…` / `clear_…`), expanded `save_snapshot`/`restore_snapshot` + `CAMPAIGN_SCOPED_TABLES` registry.
- `engine/subsystems/override/override_manager.gd` + `scenes/ui/override/override_panel.gd` — **retire** the GM-only snapshot wrappers/UI (§6.1); redirect any remaining caller to the unified API.
- `scenes/ui/pause/pause_menu_overlay.gd` — combat-save guard; (S-3) Save/Load entry.
- New: `db/migrations/NNN_dungeon_entity_positions.sql` (S-1); `scenes/ui/saveload/` Save/Load screen (S-3); `tests/test_save_snapshot_completeness.gd`, `tests/test_session_restore_context.gd`.

---

## 12. Open Questions / Architectural Concerns

### Resolved (2026-06-07)

- **Per-member dungeon cell restore → exact, no scatter.** Each entity's live cell/level is persisted and restored individually (§5.2, new per-entity table §7). Re-scatter is fresh-entry/fallback only.
- **Slot schema-version skew → best-effort migrate + warn** (§9). Never refuse the load; surface a non-blocking warning only when a migration actually ran.
- **GM vs. Player snapshot → one unified system** (§6.1). The Override-panel snapshot feature is folded in / retired; the GM/Player distinction is dropped.
- **Mid-combat save → disallowed for now** (§5.7). May be revisited if a clean mid-combat serialization is ever wanted.
- **Snapshot completeness + isolation → whole-DB capture, per-campaign restore** (§6.2). DECISION 2026-06-07: save = `VACUUM INTO` (structurally complete); restore = ATTACH + per-table copy scoped to the slot's campaign via `_campaign_scope_entries` (a registry kept honest by `test_scope_map_covers_all_tables`). The dungeon-content tables (JSON-buried `dungeon_id`) are scoped by a computed dungeon-id list. **Per-campaign isolation: loading one campaign never touches another** (Jedidiah's choice 2026-06-07; verified by `test_restore_is_campaign_isolated`).

### Approved + landed (S-1, 2026-06-07)

- **`SessionState.flush_to_db()` contract — APPROVED, landed.** Added as an additive virtual (default no-op); overridden by wilderness/dungeon/settlement states. `SessionRunner.save_session()` dispatches to it.
- **`SessionState.is_in_combat()` contract — APPROVED, landed.** Small additive virtual (default false) so the no-save-in-combat guard also covers in-place dungeon combat (which keeps the "dungeon" state key). Reused by `SessionRunner.is_in_combat()`.
- **Context-aware loader branch — APPROVED, landed.** `SessionLoadState` now branches on `current_location_type`; falls back to wilderness with a warning on an unresolvable dungeon/settlement.

### Landed (S-2 + S-3, 2026-06-07)

- **Whole-DB capture + per-campaign restore** — `save_snapshot`=VACUUM INTO; `restore_snapshot`=ATTACH + `_restore_campaign_from_slot` (per-table copy scoped by `_campaign_scope_entries`, deepest-first DELETE); migration 147 slot metadata; `get_snapshot`/`delete_snapshot`/`prune` manage files. Completeness + isolation tested in `tests/test_savegame_snapshot.gd`.
- **`SessionRunner.save_to_slot(label)` / `load_slot(id)`** — slot save (flush-then-snapshot) and load (restore-then-`session_load` re-entry).
- **`SaveLoadPanel`** (`scenes/ui/saveload/save_load_panel.gd`) + pause-menu "Save / Load…" entry.
- **OverrideManager fold-in** — no change required; its wrappers already delegate to the unified `CampaignRepository` API (now producing file slots).

### Still open

- **Save-slot files hold all campaigns (size).** The slot *file* is a whole-DB copy (restore reads back only the relevant campaign), so each slot is the full DB size (~MBs). Fine for desktop; revisit only if slot files get large enough to matter.
- **Main-menu named-slot Load.** `load_slot` already supports a fresh-boot load; only the pause-menu entry is wired. Add a main-menu "Load Slot" surface as a small follow-up.
- **Reconcile pre-existing failing tests.** The baseline carries 19 failures (verified unchanged across S-1/S-2), some named around "snapshot/restore," "timekeeping save/load," "location_cache." Triage separately.
- **State-machine / load-flow integration test coverage.** The CampaignRepository data layer is unit-tested (`test_savegame_location.gd`, `test_savegame_snapshot.gd`); the `flush_to_db` hooks, context-aware loader, and `save_to_slot`/`load_slot` re-entry are validated by in-game acceptance (§10), not yet by an automated SessionRunner integration test (the harness can't spin up controllers headlessly).
- **Windows file-lock after ATTACH/DETACH.** Deleting a slot immediately after restoring it can occasionally fail to remove the file on Windows (handle not yet released); the row is still deleted. Rare in practice; `wipe_for_tests` clears the saves dir for test hygiene.
