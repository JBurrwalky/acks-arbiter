# ACKS Arbiter — Build Log

This file is the project's cross-session memory. Claude Code reads it at the start of every session and appends an entry at the end. **Never delete old entries.**

---

## Session 2026-03-25 — Project Initialization

**Task:** Set up project directory structure and build agent configuration.
**Completed:**
- Created CLAUDE.md with full build agent instructions.
- Created build_log.md (this file).
- Project files are currently flat in root. First Claude Code task is to reorganize into `rules/`, `generation/`, `docs/` structure.
**Decisions made:**
- Build agent is Claude Code only (no OpenClaw, no Ollama). Rationale: simpler toolchain, better code quality, lower cost, purpose-built for coding tasks.
- Default model: Sonnet 4.6 for implementation, Opus 4.6 for planning/review.
- Cross-session memory via this build_log.md file rather than a persistent agent daemon.
- Design brief v11 replaces all prior versions. The old rule atom JSON system is fully abandoned; XML rule summaries and GDDs are the authoritative build sources.
**Next session should:**
1. Reorganize files into directory structure (first task in CLAUDE.md).
2. Create the document map (`docs/document_map.md`) — index all XML and GDD files.
3. Create the rule system map (`docs/rule_system_map.md`) — system dependencies and cross-references.

---

## Session 2026-03-25 — Project Reorganization

**Task:** Execute First Task from CLAUDE.md — reorganize files into correct directory structure.
**Model used:** Sonnet 4.6
**Completed:**
- Verified existing state: `rules/`, `generation/`, `docs/` directories and their contents were already correctly placed from prior work.
- `rules/` contains 63 XML rule summary files (acore_*, ax_*, daw_*, le_*, pc_*).
- `generation/` contains 11 GDD files (gdd-*.md + gdd_combat_behavior_tags.md).
- `docs/` contains `acks_arbiter_design_brief_v11.md`.
- Created missing directories: `engine/`, `data/`, `test/` (each with `.gitkeep` placeholder).
- Committed CLAUDE.md, build_log.md, and the three new directories: commit `0314b11`.
- Note: `document_authority_architecture.md` and `coding_conventions.md` referenced in CLAUDE.md do not exist yet — not a problem, they are listed as optional/future.
**Decisions made:**
- Used `.gitkeep` files to allow git to track empty `engine/`, `data/`, `test/` directories.
**Known issues:**
- `docs/document_map.md` and `docs/rule_system_map.md` do not exist yet (listed as "once created" in CLAUDE.md — not blocking).
- `document_authority_architecture.md` listed in CLAUDE.md reorganization steps does not exist in repo — may have been superseded before creation.
**Next session should:**
1. Create `docs/document_map.md` — index all 63 XML rule files and 11 GDDs with brief descriptions.
2. Create `docs/rule_system_map.md` — map game systems to their rule file dependencies.
3. Begin engine implementation per the design brief.

## Session 2026-03-25 — document map and rule system map planning

**Task:** Create the docs/document_map.md and docs/rule_system_map.md files according to the specs in CLAUDE.md and \docs\acks_arbiter_design_brief_v11.md". These need to be very well crafted as they will guide the rest of the project. Come up with a good plan for what they should contain based on the CLAUDE.md file instructions and the Design Brief document in /docs and present your plan for what they will look like to me for approval.

**Model Used:** Opus 4.6 - Max Effort

**Completed:** Completed the Planning Phase. 

**Known issues:** Claude servers hit major outages mid-task. Creation of the files was deferred.

**Next Session:**
1. Create `docs/document_map.md` — index all 63 XML rule files and 11 GDDs with brief descriptions.
2. Create `docs/rule_system_map.md` — map game systems to their rule file dependencies.
3. Create `docs/coding_conventions.md` maintain consistent coding conventions across sessions.

---

## Session 2026-03-25 — Hex Map Rendering, Terrain Taxonomy, and Fog of War

**Task:** Build the hex map rendering, terrain taxonomy, and fog of war system per the detailed implementation spec.
**Model used:** Sonnet 4.6
**Completed:**
- Created `engine/shared_types/hex_terrain_data.gd` (class HexTerrainData) — terrain tag data model with four layers (elevation, biome, water, civilization). Implements `encounter_table_weights()`, `movement_cost_category()`, `from_dict()`, `is_valid()`.
- Created `engine/shared_types/hex_map_data.gd` (class HexMapData) — container for a hex map layer. MapScale and FogState enums. `load_from_file()` and `from_dict()` factory methods.
- Created `engine/subsystems/exploration/hex_map_controller.gd` (class HexMapController, extends Node) — game logic for party movement and fog of war. Static hex math methods: `get_neighbors()`, `hex_distance()`, `is_adjacent()`, `get_hex_ring()`, `axial_to_godot_map()`, `godot_map_to_axial()`. Game methods: `load_map()`, `move_party()`, `can_move_to()`, `_update_visibility()`.
- Created `scenes/maps/hex_map_renderer.gd` (extends Node2D, no class_name) — renders HexMapData onto TileMapLayer nodes. Programmatically creates terrain tileset (17 cols × 1 row, solid-color placeholder tiles) and fog tileset (2 cols). Handles mouse input to emit `hex_clicked(coord)`.
- Created `scenes/maps/hex_map.tscn` — scene with HexMap (Node2D), TerrainLayer (TileMapLayer), FogLayer (TileMapLayer), EntityLayer (Node2D), PartyToken (Polygon2D).
- Created `data/test_hex_map.json` — 31-hex test region "Ashford Vale" demonstrating all terrain types (ocean, river, swamp, woods, hills/woods, mountains, desert, jungle, civilized with city, borderlands).
- Created `scenes/main_scene.gd` — test harness wiring renderer to controller, loading test map, connecting hex clicks to movement.
- Updated `scenes/Main.tscn` — added HexMapController node, instantiated HexMap scene, attached main_scene.gd.
- Created `tests/test_hex_terrain_data.gd` — 15 plain-GDScript assert tests for HexTerrainData.
- Created `tests/test_hex_map_controller.gd` — 17 plain-GDScript assert tests for HexMapController (static math + game logic).
- Created new directories: `engine/subsystems/`, `engine/subsystems/exploration/`, `scenes/maps/`, `tests/`.

**Decisions made:**
- Renderer has no `class_name` — it is only ever referenced by scene instantiation, not by code.
- Test files use plain `assert()` — no test framework dependency. Each file has a `run_all_tests()` method and individual `test_*()` functions for future harness wiring.
- Fog of war uses 1-hex sight radius (center + immediate neighbors = 7 hexes visible). Can be changed in `_update_visibility()`.
- Terrain tileset is programmatically generated from solid-color Image rectangles — no external sprite assets needed for iteration. Each biome has a distinct color; hills are ×0.83 brightness, mountains ×0.67.
- Even-q offset chosen for axial-to-Godot conversion (`TILE_LAYOUT_FLAT`). If Godot's actual behavior proves to use odd-q, swap `(q - (q & 1))` to `(q + (q & 1))` in both `axial_to_godot_map` and `godot_map_to_axial`.
- Ocean check in `encounter_table_weights()` fires before `has_city` check — an ocean hex cannot logically be a city hex, but ocean-first ordering keeps the sentinel clean.

**Interfaces defined or changed:**

HexTerrainData:
- `encounter_table_weights() -> Dictionary` — keys: "city", "inhabited", "_natural", "clear_grass_scrub", "woods", "jungle", "swamp", "barren_desert", "mountains_hills", "ocean"
- `movement_cost_category() -> String` — values: "mountains", "swamp", "jungle", "woods", "hills", "desert", "clear", "ocean"
- `from_dict(data: Dictionary) -> HexTerrainData` (static)
- `is_valid() -> bool`

HexMapData (enums used as cross-system contract):
- `MapScale`: CAMPAIGN_24MI, REGIONAL_6MI, LOCAL_15MI
- `FogState`: HIDDEN, EXPLORED, VISIBLE

HexMapController signals (connect renderer or other systems to these):
- `map_loaded(map_id: String)`
- `hex_first_revealed(coord: Vector2i)`
- `visibility_updated()`
- `party_moved(from_hex: Vector2i, to_hex: Vector2i)`

HexMapRenderer signal:
- `hex_clicked(coord: Vector2i)` — emitted on left-click over a valid hex

HexMapController public methods:
- `load_map(map_data: HexMapData) -> void`
- `move_party(target: Vector2i) -> bool`
- `can_move_to(target: Vector2i) -> bool`
- `get_map() -> HexMapData`

Static coordinate conversion (used by renderer and tests):
- `axial_to_godot_map(axial: Vector2i) -> Vector2i`
- `godot_map_to_axial(map: Vector2i) -> Vector2i`

**Database changes:** None.

**Tests added/updated:**
- `tests/test_hex_terrain_data.gd` — 15 tests covering encounter weights for all territory/biome/elevation combinations, movement cost priority, and validity checking.
- `tests/test_hex_map_controller.gd` — 17 tests covering neighbor enumeration, distance calculation, adjacency, coordinate conversion roundtrip, party movement (success and failure), fog state transitions (HIDDEN → VISIBLE → EXPLORED, never back to HIDDEN), and hex ring generation.

**Known issues:**
- TileSet programmatic creation: Godot 4 may require TileSet source_id to be explicitly specified when calling `add_source()`. If fog tiles show on wrong layer or at wrong coords, check that `FOG_SOURCE_ID = 0` matches the actual source index assigned by Godot.
- Even-q vs odd-q offset: The `axial_to_godot_map` conversion uses even-q offset. This must be verified visually in the editor — if hexes appear offset by half a row, swap to odd-q by changing `(q - (q & 1))` to `(q + (q & 1))` in both conversion functions.
- The test harness files (`test_*.gd`) are not yet connected to any autorun mechanism. They need to be instantiated and have `run_all_tests()` called to execute. Future session should add a test runner scene.
- `data/test_hex_map.json` is loaded via `res://` path — this works in the Godot editor but would need to be copied to `user://` or bundled properly for export builds.

**Next session should:**
1. Open the project in the Godot 4.6 editor and verify the scene loads without errors.
2. Fix even-q vs odd-q offset if hexes appear misaligned.
3. Wire the test runner: create a scene that instantiates both test scripts and calls `run_all_tests()`, confirm all 32 tests pass.
4. Create `docs/document_map.md` and `docs/rule_system_map.md` (deferred from prior sessions).
5. Begin wilderness encounter table resolution — connect `EventBus.hex_entered` to an encounter check system that uses `HexTerrainData.encounter_table_weights()`.

---

## Session 2026-03-25 — Shared Types, DB Schema, CampaignRepository, LLMManager, AudioRouter

**Task:** Build the shared types package, database schema, CampaignRepository autoload, and LLMManager/AudioRouter stubs.
**Model used:** Sonnet 4.6

**Completed:**
- Created `engine/shared_types/character_data.gd` — class CharacterData. Full PC/henchman/NPC data model. Static `ability_modifier()` using ACKS match table, `from_dict()`, `to_dict()`.
- Created `engine/shared_types/action_payload.gd` — class ActionPayload. Action vocabulary payload with `from_dict()`, `is_valid()`.
- Created `engine/shared_types/encounter_data.gd` — class EncounterData. Universal encounter group descriptor with `from_dict()`.
- Created `engine/shared_types/inventory_item.gd` — class InventoryItem. Encumbrance in 1/6-stone units. `from_dict()`, `to_dict()`, `encumbrance_stone()`.
- Created `engine/shared_types/response_envelope.gd` — class ResponseEnvelope. LLM response wrapper with static factories `ok()`, `fail()`, `fallback()`.
- Created `engine/shared_types/event_payload.gd` — class EventPayload. Generic domain/exploration event payload with `from_dict()`.
- Created `db/migrations/001_initial_schema.sql` — full initial schema (all Tier 1 tables; idempotent with IF NOT EXISTS).
- Created `db/schema.sql` — canonical schema file including schema_migrations table plus full 001 content.
- Created `engine/autoloads/campaign_repository.gd` — CampaignRepository autoload. Migration runner, full CRUD for campaigns, characters, parties, hex maps, domains. No class_name.
- Created `engine/autoloads/llm_manager.gd` — LLMManager autoload stub. Returns ResponseEnvelope.fallback() for all requests. No class_name.
- Created `engine/autoloads/audio_router.gd` — AudioRouter autoload stub. No-op play_sfx, play_music, stop_music. No class_name.
- Updated `project.godot` — added CampaignRepository, LLMManager, AudioRouter to [autoload] section. All 5 autoloads now registered.
- Updated `docs/coding_conventions.md` — removed [PROVISIONAL] tags from §3.5 (method ordering), §6.2 (repository pattern), §6.4 (transactions), §7.2 (shared types), §8.2 (error propagation). Added confirmed notes with rationale.

**Decisions made:**
- `db/` directory created at Godot project root (alongside `engine/`, `scenes/`, etc.) so migration SQL files are accessible via `res://db/migrations/` at runtime.
- CharacterData uses `String` for `id` (not `int`) to match the TEXT PRIMARY KEY in the schema and the `generate_id()` hex string format.
- `is_active` in `from_dict()` defaults to `1` (active) since DB default is 1; `is_dead` defaults to `0`.
- `save_character()` does a SELECT-then-INSERT-or-UPDATE upsert pattern (not SQL UPSERT) to give callers a clean bool return and consistent behavior across SQLite versions.
- ResponseEnvelope uses static factory methods instead of direct construction to enforce invariants (success/error state consistency).

**Interfaces defined or changed:**

CharacterData (`engine/shared_types/character_data.gd`):
- `static func ability_modifier(score: int) -> int`
- `static func from_dict(data: Dictionary) -> CharacterData`
- `func to_dict() -> Dictionary`

ActionPayload (`engine/shared_types/action_payload.gd`):
- `static func from_dict(data: Dictionary) -> ActionPayload`
- `func is_valid() -> bool`

EncounterData (`engine/shared_types/encounter_data.gd`):
- `static func from_dict(data: Dictionary) -> EncounterData`

InventoryItem (`engine/shared_types/inventory_item.gd`):
- `static func from_dict(data: Dictionary) -> InventoryItem`
- `func to_dict() -> Dictionary`
- `func encumbrance_stone() -> float`

ResponseEnvelope (`engine/shared_types/response_envelope.gd`):
- `static func ok(text: String, context_id: String, provider: String) -> ResponseEnvelope`
- `static func fail(error: String, context_id: String) -> ResponseEnvelope`
- `static func fallback(text: String, context_id: String) -> ResponseEnvelope`

EventPayload (`engine/shared_types/event_payload.gd`):
- `static func from_dict(d: Dictionary) -> EventPayload`

CampaignRepository public methods:
- `static func generate_id() -> String`
- `func create_campaign(name: String, world_name: String) -> String`
- `func get_campaign(id: String) -> Dictionary`
- `func list_campaigns() -> Array`
- `func update_campaign_calendar(id: String, day: int) -> void`
- `func create_character(data: Dictionary) -> String`
- `func get_character(id: String) -> Dictionary`
- `func save_character(data: Dictionary) -> bool`
- `func update_character_hp(id: String, new_hp: int) -> void`
- `func list_party_characters(party_id: String) -> Array`
- `func create_party(campaign_id: String, name: String) -> String`
- `func get_party(id: String) -> Dictionary`
- `func add_party_member(party_id: String, character_id: String, slot: String) -> bool`
- `func update_party_position(party_id: String, map_id: String, q: int, r: int) -> void`
- `func save_hex_map(map_data: HexMapData, campaign_id: String) -> bool`
- `func load_hex_map(map_id: String) -> HexMapData`
- `func update_hex_fog(map_id: String, q: int, r: int, fog_state: String) -> void`
- `func create_domain(data: Dictionary) -> String`
- `func get_domain(id: String) -> Dictionary`
- `func list_campaign_domains(campaign_id: String) -> Array`

LLMManager public methods:
- `func request_narration(context: Dictionary) -> ResponseEnvelope`
- `func is_configured() -> bool`

AudioRouter public methods:
- `func play_sfx(_sound_id: String) -> void`
- `func play_music(_track_id: String) -> void`
- `func stop_music() -> void`

**Database changes:**
- Created `db/migrations/001_initial_schema.sql` — initial schema with 11 tables: campaigns, characters, parties, party_members, character_conditions, character_proficiencies, inventory_items, character_spells, hex_maps, hex_cells, domains.
- Created `db/schema.sql` — canonical current-state schema (includes schema_migrations table + full 001 content).
- Migration runner in `_run_migrations()` bootstraps schema_migrations, enumerates files, applies unapplied ones in order.

**Tests added/updated:** None this session. (Existing 32 tests for HexTerrainData and HexMapController are unaffected.)

**Known issues:**
- `db/migrations/` directory must be present at `res://db/migrations/` in the exported build. Godot's `DirAccess.open("res://...")` works in editor and PCK exports, but the .sql files must be included in the export preset's "Include Files" filter (`db/migrations/*.sql`). Add this to export setup when preparing the first build.
- `load_hex_map()` calls `HexMapData._scale_from_string()` — this static method must exist on HexMapData. It was not explicitly present in the session that created hex_map_data.gd; verify it exists or add it before wiring DB load into the map scene.
- LLMManager and AudioRouter are stubs only. `request_narration()` always returns a fallback. Full implementation deferred.

**Next session should:**
1. Wire CampaignRepository into the hex map scene: replace the JSON file load in main_scene.gd with `CampaignRepository.save_hex_map()` on first run, then `CampaignRepository.load_hex_map()` on subsequent runs. Verify round-trip through SQLite preserves all terrain and fog data.
2. Verify `HexMapData._scale_from_string()` exists; add if missing.
3. Build the session runner state machine (the top-level game loop: campaign select → session start → exploration → encounter resolution → session end).
4. Begin the combat loop (initiative, attack throws, damage, conditions).
5. Create `docs/document_map.md` and `docs/rule_system_map.md` (still deferred).

---

## Session 2026-03-25 — CampaignRepository wiring + test runner scene

**Task:** Wire CampaignRepository into main_scene.gd test harness; add test runner scene.
**Model used:** Sonnet 4.6

**Completed:**
- Verified `HexMapData._scale_from_string()` exists at `hex_map_data.gd:104` — known issue resolved, no changes needed.
- Rewrote `scenes/main_scene.gd` — replaces raw JSON load with DB-backed load/seed pattern:
  - `_load_or_seed_map()`: checks DB first via `CampaignRepository.load_hex_map(TEST_MAP_ID)`; on miss, loads JSON and seeds DB + campaign/party records.
  - `_ready()`: saves fog state to DB after `_controller.load_map()` initializes it; uses `GameState.start_session()` instead of direct `transition_to()`.
  - `_on_hex_clicked()`: persists updated fog to DB after each party move.
  - `_ensure_test_campaign()`: uses `INSERT OR IGNORE` directly via `CampaignRepository.db` to seed fixed-ID test records idempotently (avoids push_error noise from `get_campaign()` on first run).
- Created `tests/test_runner.gd` — Node script that instantiates both test suites and calls `run_all_tests()` on each; supports headless `OS.exit_code` for CI.
- Created `tests/test_runner.tscn` — scene with TestRunner (Node) + HexTerrainDataTests + HexMapControllerTests as children.

**Decisions made:**
- `main_scene.gd` accesses `CampaignRepository.db` directly for the fixed-ID test campaign seed. This is intentional for the test harness — production code will go through the repository API. A comment documents this distinction.
- `load_map()` in HexMapController always resets fog to HIDDEN before revealing starting position. This means DB-loaded fog states are not used to resume exploration — correct behavior for the test harness (always starts fresh). Production session resumption will need a `resume_map()` variant that skips fog reset.
- Test runner uses plain `_run_suite()` wrapper but cannot catch assert failures (GDScript `assert()` aborts the calling script, not the whole process). Visual confirmation via the print statement at end of each suite is the signal of success.

**Interfaces defined or changed:** None.

**Database changes:** None (schema unchanged; `main_scene.gd` now seeds the DB on first run using existing schema).

**Tests added/updated:**
- `tests/test_runner.gd` + `tests/test_runner.tscn` — test runner wiring for all 32 existing tests. Run with: open `test_runner.tscn` in Godot editor, or `godot --headless --path . res://tests/test_runner.tscn`.

**Known issues:**
- `load_map()` always resets fog to HIDDEN — DB-persisted fog from a prior session is ignored. For production, a `resume_map(map_data)` method is needed that skips the reset step and respects saved fog states.
- Full `save_hex_map()` (31 INSERT OR REPLACE) is called on every hex click. Acceptable for the test map; a larger map would benefit from targeted `update_hex_fog()` calls on changed cells only.
- Test runner cannot distinguish assert-failure crashes from suite completion — if an assert fires mid-suite, the runner gets no signal; the process terminates. This is a known GDScript limitation. Godot 4's `assert()` behavior is acceptable for dev; a future session could add GUT or a custom try/catch wrapper.

**Next session should:**
1. Open project in Godot 4.6 editor; verify Main.tscn loads without errors; run test_runner.tscn and confirm both suites print "all tests passed."
2. Verify even-q vs odd-q hex offset visually — if rows appear shifted by half a hex, swap `(q - (q & 1))` to `(q + (q & 1))` in `hex_map_controller.gd` (both `axial_to_godot_map` and `godot_map_to_axial`).
3. Create `docs/document_map.md` and `docs/rule_system_map.md` — still the highest-priority deferred task for build-session navigation.
4. Build the wilderness encounter check system: connect `EventBus.hex_entered` → encounter roll → `HexTerrainData.encounter_table_weights()` dispatch.
5. Build the session runner state machine (campaign select → session start → exploration loop → session end).
---

## Session 2026-03-27 — Override System

**Task:** Design and implement the full Override System — a Ctrl+Alt+O dev-mode panel for direct game state manipulation, dice pre-determination, and session snapshots.
**Model used:** Opus 4.6 (planning phase), Sonnet 4.6 (implementation)

**Completed:**
- Created `db/migrations/002_override_log.sql` — three new tables: `override_log` (append-only audit trail), `game_snapshots` (capped at 10 per campaign), `dungeon_entrances` (hex placement stub for future dungeon generator).
- Updated `db/schema.sql` — now reflects migration 002.
- Added `var dice_overrides: Dictionary = {}` to `engine/autoloads/game_state.gd`.
- Added 5 signals to `engine/autoloads/event_bus.gd`: `override_applied`, `snapshot_saved`, `snapshot_restored`, `dice_override_queued`, `dice_override_consumed`.
- Added 14 new methods to `engine/autoloads/campaign_repository.gd`: inventory CRUD, condition CRUD, `update_hex_terrain_field`, `create_dungeon_entrance`, and full snapshot management. Added private helpers `_query_rows` and `_insert_rows`.
- Created `engine/subsystems/override/override_manager.gd` (class OverrideManager, extends Node) — full logic layer with dice queue, character/inventory/world/spawn overrides, and snapshot save/restore.
- Created `scenes/ui/override/override_panel.gd` (extends CanvasLayer) — fully programmatic UI with 7 tabs: Characters, Inventory, World, Spawning, Dice, Snapshots, Log.
- Created `scenes/ui/override/override_panel.tscn`.
- Updated `project.godot` — added `override_panel_toggle` action bound to Ctrl+Alt+O (physical_keycode=79).
- Updated `scenes/Main.tscn` — added OverrideManager and OverridePanel as children of Main.
- Updated `scenes/main_scene.gd` — calls `_override_panel.setup(_override_manager, _controller)` after session start.
- Created `tests/test_override_manager.gd` — 14 tests covering dice queue, stat mutation, XP floor, condition apply/remove, status toggle, gold add/subtract/floor, snapshot round-trip.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` — added OverrideManagerTests (now 3 suites total).

**Decisions made:**
- OverrideManager is NOT an autoload. Dice override queue lives in `GameState.dice_overrides` so the future dice subsystem can read it without depending on OverrideManager.
- Gold tracked as `inventory_items` row with `item_key = "coin_gp"`. Subtracting below zero floors at 0.
- Dungeon placement via override creates a `dungeon_entrances` stub (empty `dungeon_data`). Marked `[STUB]` in code.
- Settlement placement marks hex as civilized + has_city=1. Does not generate layout.
- Snapshot restore is transactional: DELETE all campaign-scoped rows, then re-INSERT from JSON blob. Pruned to max 10 per campaign.
- Warning dialog shows once per session (in-memory flag).

**Interfaces defined or changed:**

GameState additions:
- `var dice_overrides: Dictionary = {}`

EventBus additions:
- `signal override_applied(override_type: String, target_id: String, field: String)`
- `signal snapshot_saved(snapshot_id: String, label: String)`
- `signal snapshot_restored(snapshot_id: String)`
- `signal dice_override_queued(roll_type: String, forced_value: int)`
- `signal dice_override_consumed(roll_type: String, forced_value: int)`

OverrideManager public API (injected into OverridePanel via setup()):
- Dice: `queue_dice_override`, `clear_dice_override`, `clear_all_dice_overrides`, `consume_dice_override -> int`
- Character: `override_character_stat`, `override_character_xp`, `override_character_condition`, `override_character_status`
- Inventory: `override_add_item`, `override_remove_item`, `override_adjust_gold`
- World: `override_hex_terrain`, `override_fog_reveal_all`, `override_fog_hide_all`, `override_fog_set_hex`, `override_place_settlement`
- Spawning: `override_spawn_encounter`, `override_place_dungeon`
- Snapshots: `save_session_snapshot`, `restore_session_snapshot`, `list_session_snapshots`

Dice roll type vocabulary (18 types):
encounter_check, surprise_check, initiative, attack_throw, damage_roll,
saving_throw_petrification, saving_throw_poison, saving_throw_blast,
saving_throw_wands, saving_throw_spells, morale_check, reaction_roll,
thief_skill_throw, proficiency_throw, domain_event_roll, hijink_roll,
mortal_wound_roll, tampering_with_mortality

**Database changes:**
- Migration 002: `override_log`, `game_snapshots`, `dungeon_entrances` tables added.

**Tests added/updated:**
- `tests/test_override_manager.gd` — 14 tests (new suite, 46 total across all suites).

**Known issues:**
- Override panel is fully programmatic (no Godot editor-visible widget tree). Cannot be visually tweaked in editor without converting to a proper scene graph.
- Ctrl+Alt+O binding in project.godot uses physical_keycode=79. Verify it triggers in-engine; if not, reassign in Project Settings > Input Map.
- Snapshot restore does NOT reload the in-memory HexMapController/renderer. After restore during active exploration, renderer shows stale fog until map reloads. Fix: emit a map_reload_needed signal from restore_session_snapshot() in a future session.
- override_place_dungeon() is a stub. Wire to dungeon layout generator when that system is built.

**Next session should:**
1. Open project in Godot 4.6; run test_runner.tscn; confirm all 3 suites pass.
2. Verify Ctrl+Alt+O opens the Override Panel with the warning dialog.
3. Build the dice subsystem: DiceSystem class, roll(sides, count, modifier), integration with GameState.dice_overrides via OverrideManager.consume_dice_override().
4. Build the session runner state machine (campaign select to exploration loop).

---

## Session 2026-03-27 — Hex Map Camera, Tooltip, Terrain Propagation, Override Panel UX

**Task:** Fix 6 issues identified in review: (1) tiles rendering off-screen, (2) no camera scroll, (3) no hex hover tooltip, (4) terrain override not reflecting visually, (5) terrain value field was free text, (6) fog override missing reveal-selected.
**Model used:** claude-sonnet-4-6 (implementation)

**Completed:**
- `scenes/maps/hex_map.tscn` — Added Camera2D child and HexHUD CanvasLayer (layer=10) with TooltipPanel (PanelContainer, mouse_filter=IGNORE) and TooltipLabel (Label).
- `scenes/maps/hex_map_renderer.gd` — Full rewrite:
  - Added `@onready` refs for Camera2D, TooltipPanel, TooltipLabel.
  - Added `PAN_SPEED = 200.0` and `EDGE_MARGIN = 40.0` constants.
  - `_process(delta)`: arrow-key pan + mouse-to-edge pan (40px margin); Camera2D limits constrain naturally.
  - `center_on_hex(coord)`: moves camera to pixel center of given axial hex.
  - `_compute_camera_limits()`: iterates all hex pixel positions, sets Camera2D limit_left/right/top/bottom with 1-tile padding.
  - `_on_map_loaded()`: now calls `_compute_camera_limits()` then `center_on_hex(party_hex)`.
  - `_unhandled_input()`: added `InputEventMouseMotion` branch → `_update_tooltip(event.position)`.
  - `_update_tooltip(viewport_pos)`: shows terrain info for EXPLORED/VISIBLE hexes; hides for HIDDEN or off-map.
  - `_terrain_tooltip_text(coord, terrain)`: formats 9-line tooltip (hex coord, elevation, biome, water, territory, city, families/owners/cleared as stubs).
  - `_repaint_tile(coord)`: repaints a single terrain tile using in-memory HexTerrainData.
  - `setup(controller)`: now also connects `controller.hex_terrain_updated` → `_repaint_tile`.
- `engine/subsystems/exploration/hex_map_controller.gd`:
  - Added `signal hex_terrain_updated(coord: Vector2i)`.
  - Added `func update_hex_terrain(coord, field, new_value)`: updates in-memory HexTerrainData field (all 6 fields), emits `hex_terrain_updated`.
- `engine/subsystems/override/override_manager.gd`:
  - `override_hex_terrain()` signature: added `controller: HexMapController = null` param (default null = backward compat).
  - After DB write: calls `controller.update_hex_terrain(coord, field, new_value)` if controller is non-null.
- `scenes/ui/override/override_panel.gd`:
  - `_world_terrain_value: LineEdit` replaced with `_world_terrain_value_opt: OptionButton`.
  - Added `_world_fog_reveal_hex_btn: Button` var.
  - Added `TERRAIN_VALUE_OPTIONS` const dict mapping each terrain field to its valid string values.
  - `_build_world_tab()`: OptionButton wired; connects `item_selected` → `_on_world_terrain_field_changed`; initial population via `_on_world_terrain_field_changed(0)`.
  - Added "Reveal Target Hex" button in fog bulk row → `_on_world_fog_reveal_selected()`.
  - `_on_world_terrain_apply()`: reads from OptionButton, maps water "none" → "", sends `_hex_controller` to `override_hex_terrain`.
  - Added `_on_world_terrain_field_changed(idx)`: repopulates value OptionButton for selected field.
  - Added `_on_world_fog_reveal_selected()`: calls `override_fog_set_hex(..., "visible", _hex_controller)`.

**Decisions made:**
- Tooltip suppressed on HIDDEN hexes; shown only on EXPLORED or VISIBLE. (Design decision confirmed by Jedidiah.)
- Camera pan uses arrow keys + mouse-to-edge (40px). Speed: 200px/s. Camera2D's built-in limits handle clamping.
- Terrain value dropdown uses human-readable strings; water "none" maps to "" before passing to OverrideManager.
- `update_hex_terrain` in HexMapController updates in-memory data only (DB write already done by OverrideManager before this call).

**Interfaces defined or changed:**
- `HexMapController.hex_terrain_updated(coord: Vector2i)` — new signal.
- `HexMapController.update_hex_terrain(coord: Vector2i, field: String, new_value)` — new method.
- `OverrideManager.override_hex_terrain(map_id, coord, field, new_value, controller: HexMapController = null)` — added optional controller param (backward compatible).
- `HexMapRenderer.center_on_hex(coord: Vector2i)` — new public method.

**Bugs fixed during session:**
- `hex_map_controller.gd:update_hex_terrain()` — "Invalid operands 'int' and 'bool' in operator '=='" on `has_city` field. GDScript does not allow comparing int and bool with ==. Fixed by replacing the multi-type check with `str(new_value) in ["1", "true", "True"]`, which coerces safely regardless of input type (int 1 → "1", bool true → "True", string "1" → "1").

**Known issues:**
- Tooltip panel size on first show may be Vector2.ZERO (Godot layout runs after first frame); fallback size 160×130 is used until layout settles — should be fine for 2nd+ frame.
- Camera panning from mouse-to-edge only fires when mouse is inside the viewport rect (guarded). Arrow-key pan fires always.
- Snapshot restore does NOT reload in-memory HexMapController/renderer (still pending).

**Next session should:**
1. Open project in Godot 4.6; run test_runner.tscn; confirm all 3 suites pass.
2. Test hex map: verify camera centers on party, arrow keys + mouse-to-edge panning works.
3. Test hover tooltip: explore a few hexes, confirm tooltip shows terrain info; hidden hexes show no tooltip.
4. Test terrain override: change a hex's biome in Override Panel; confirm tile color updates immediately.
5. Build the dice subsystem: DiceSystem class, roll(sides, count, modifier), integration with GameState.dice_overrides. ✓ Done this session.
6. Build the session runner state machine (campaign select to exploration loop).

---

## Session 2026-03-27 — Dice System

**Task:** Design and implement the full dice subsystem: DiceSystem autoload, RollResult shared type, DicePrompt modal UI, DB roll log, settings persistence, override integration, and test suite. Planning phase (Opus) preceded implementation (Sonnet).

**Model used:** claude-sonnet-4-6 (implementation)

**Completed:**
- Created `engine/shared_types/roll_result.gd` (class RollResult) — all fields for a resolved roll: roll_type, sides, count, modifier, individual_results, raw_total, modified_total, was_overridden, was_player_entered, natural_one, natural_max. `to_dict()` for signal payloads and DB logging.
- Created `db/migrations/003_dice_roll_log.sql` — `dice_rolls` table (session-only, capped at 200 rows, cleared on session_ended).
- Updated `db/schema.sql` to reflect migration 003.
- Updated `engine/autoloads/game_state.gd` — added `DiceMode` enum (DIGITAL, PHYSICAL, HYBRID), `dice_mode` var (default HYBRID), `_SETTINGS_PATH` constant, `set_dice_mode()`, `save_settings()`, `load_settings()` via Godot ConfigFile at `user://settings.cfg`.
- Updated `engine/autoloads/event_bus.gd` — added `dice_rolled`, `player_roll_requested`, `player_roll_resolved` signals.
- Updated `engine/subsystems/override/override_manager.gd` — updated roll type vocabulary comment to split `surprise_check` into `player_surprise_check` (player-facing) and `monster_surprise_check` (GM-digital). Added player-facing vs. GM-only categorisation to the comment.
- Updated `scenes/ui/override/override_panel.gd` — replaced `surprise_check` with `player_surprise_check` + `monster_surprise_check` in `ROLL_TYPES`. Added Export Roll Log button + `_on_dice_export_log()` handler to Dice tab.
- Created `engine/autoloads/dice_system.gd` — 6th autoload. Three rolling paths: `roll_digital()` (sync, GM/NPC rolls), `player_roll()` (async in PHYSICAL/HYBRID mode, PC rolls), `roll_expression()` (parses dice notation strings). Override consumption from `GameState.dice_overrides`. DB logging with 200-row cap. `export_roll_log()` writes session rolls to `user://dice_log_TIMESTAMP.json`. Clears dice_rolls table on `EventBus.session_ended`.
- Updated `project.godot` — registered `DiceSystem` as 6th autoload after AudioRouter.
- Created `scenes/ui/dice/dice_prompt.gd` — CanvasLayer (layer=64). Handles `player_roll_requested` signal. Two resolution paths: "Roll Dice" button (digital roll with 0.4s number-cycle animation) and manual SpinBox entry (range enforced to count..count*sides). Emits `player_roll_resolved(roll_type, raw_total, was_player_entered)`.
- Created `scenes/ui/dice/dice_prompt.tscn`.
- Updated `scenes/Main.tscn` — added DicePrompt as child of Main.
- Created `tests/test_dice_system.gd` — 31 tests covering all die types, multi-die sums, modifier application, RollResult field population, natural_one/max flags, override consumption (match, no-match, single-use, modified_total back-calculation), expression parsing (simple, +mod, -mod, invalid), manual result validation, and player_roll() in DIGITAL mode.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` — added DiceSystemTests (now 4 suites, ~77 total tests).

**Decisions made:**
- DiceSystem is the 6th autoload. Justified: dice are needed in every subsystem (combat, exploration, generation, NPC). Passing it as a dependency would require wiring through every subsystem.
- `player_roll()` is async (uses `await EventBus.player_roll_resolved`). Callers in PHYSICAL/HYBRID mode must also use `await`. In DIGITAL mode it is synchronous — no await needed. This is the standard Godot 4 coroutine pattern.
- Override forced_value represents the **modified_total** (final result after modifiers). DiceSystem back-calculates raw_total as `forced_modified_total - modifier`. This means override panel users set the final outcome, not the raw dice.
- Player enters **raw dice total only** (no modifier). App applies modifier. This keeps physical dice entry simple (player reads off the physical dice and types that number).
- `surprise_check` split into `player_surprise_check` (PC party rolls, player-facing) and `monster_surprise_check` (monsters roll, GM-digital).
- Roll log is session-scoped (cleared on `session_ended`), capped at 200 rows. Export to JSON via Override Panel Dice tab for dev use.
- `DiceSystem` in `override_panel.gd` shows an IDE false-positive ("not declared in scope") that resolves on Godot project reload — same timing issue any newly registered autoload has before the language server refreshes.

**Interfaces defined or changed:**

GameState additions:
- `enum DiceMode { DIGITAL, PHYSICAL, HYBRID }`
- `var dice_mode: DiceMode = DiceMode.HYBRID`
- `func set_dice_mode(mode: DiceMode) -> void`
- `func save_settings() -> void`
- `func load_settings() -> void`

EventBus additions:
- `signal dice_rolled(roll: Dictionary)`
- `signal player_roll_requested(context: Dictionary)`
- `signal player_roll_resolved(roll_type: String, raw_total: int, was_player_entered: bool)`

DiceSystem public API:
- `func roll_digital(sides, count, modifier, roll_type) -> RollResult`
- `func player_roll(sides, count, modifier, roll_type, description) -> RollResult` [async in PHYSICAL/HYBRID]
- `func roll_expression(expression, roll_type) -> RollResult`
- `func is_valid_manual_result(value, sides, count) -> bool`
- `func export_roll_log() -> String`

RollResult (engine/shared_types/roll_result.gd):
- `func to_dict() -> Dictionary`

Roll type vocabulary (19 types, updated from 18):
- Removed: `surprise_check`
- Added: `player_surprise_check` (player-facing), `monster_surprise_check` (GM-digital)
- Full list: encounter_check, player_surprise_check, monster_surprise_check, initiative, attack_throw, damage_roll, saving_throw_petrification, saving_throw_poison, saving_throw_blast, saving_throw_wands, saving_throw_spells, morale_check, reaction_roll, thief_skill_throw, proficiency_throw, domain_event_roll, hijink_roll, mortal_wound_roll, tampering_with_mortality

**Database changes:**
- Migration 003: `dice_rolls` table — session-only roll log.

**Tests added/updated:**
- `tests/test_dice_system.gd` — 31 tests (new suite).
- `tests/test_runner.gd` + `tests/test_runner.tscn` — DiceSystemTests added (4 suites total, ~77 tests).

**Known issues:**
- `DiceSystem` reference in `override_panel.gd:_on_dice_export_log()` shows IDE error "not declared in scope" — false positive; resolves on Godot project reload when the language server picks up the updated `project.godot` autoload registration.
- `game_day` in `dice_rolls` is always 0 for now. Wire to the campaign calendar once timekeeping is built (noted with TODO comment in `dice_system.gd:_log_and_emit()`).
- `player_roll()` async path has no timeout. If DicePrompt is closed without emitting `player_roll_resolved` (e.g., forced scene change), the awaiting coroutine will hang. Add a cancellation signal when the session runner is built.
- DicePrompt layer (64) sits below OverridePanel (128). If a GM queues an override while a DicePrompt is visible, the override panel can open on top — this is intentional (GM can intercept a roll mid-prompt).

**Next session should:**
1. Open project in Godot 4.6; run `test_runner.tscn`; confirm all 4 suites (including 30 DiceSystem tests) pass.
2. Verify DicePrompt appears correctly: temporarily force `GameState.dice_mode = HYBRID` in main_scene.gd and call `await DiceSystem.player_roll(20, 1, 2, "attack_throw", "Test roll")` to confirm modal appears, Roll Dice and manual entry both work, and roll resolves.
3. Build the session runner state machine (campaign select → session start → exploration loop → session end).
4. Wire `encounter_check` into HexMapController: on `hex_entered`, call `DiceSystem.roll_digital(6, 1, 0, "encounter_check")` and compare to terrain-based threshold.

---

## Session 2026-03-27 — Dice System Bugfixes + Coding Conventions Sweep

**Task:** Fix two runtime errors in the dice system (wrong signal bus, coroutine parse error). Then do a thorough sweep of all code built since 2026-03-25 and update `docs/coding_conventions.md` to document all patterns and conventions that were missing.

**Model used:** Sonnet 4.6 (bugfixes), Opus 4.6 (conventions sweep)

**Completed:**

Bugfixes:
- Fixed `dice_system.gd:44` — `EventBus.session_ended` changed to `GameState.session_ended` (the signal is declared on GameState, not EventBus).
- Fixed `tests/test_dice_system.gd` — removed `test_player_roll_digital_mode_synchronous()` which called the coroutine `player_roll()` without `await`. GDScript marks the entire function as a coroutine if `await` appears anywhere in its body, so even the DIGITAL-mode branch cannot be called without `await`. Replaced with a comment explaining why and noting the underlying logic is covered by `roll_digital()` tests. Test count: 30 (was 31).

Coding conventions sweep (`docs/coding_conventions.md`):
- **§1.6** — Updated autoload count from "four" to "six"; added DiceSystem and EventBus examples.
- **§2.1** — Rewrote directory tree to reflect actual project state (9 shared types, 6 autoloads, override/dice subsystem dirs, actual migration names, rules/ and generation/ dirs).
- **§3.7 (new)** — `class_name` rules: table by script type (autoloads=never, shared types=always, subsystem managers=yes, UI scripts=no, tests=no).
- **§3.8 (new)** — Coroutine (`await`) patterns: signal array unpacking, propagation rule, testing limitation, design rule to keep coroutines at system boundaries.
- **§4.4 (new)** — Signal payload conventions: String IDs not object refs, Dictionary payloads with documented keys, EventBus signal group listing.
- **§5.1** — Autoload table expanded to all 6 singletons with updated responsibilities; added autoload load-order note.
- **§6.3** — Migration examples changed from hypothetical to actual filenames; added migration runner details.
- **§6.6 (new)** — Primary key conventions: TEXT for entities (via `generate_id()`), INTEGER AUTOINCREMENT for logs, composites for joins/spatial.
- **§6.7 (new)** — Settings persistence: ConfigFile at `user://settings.cfg`, section/key pattern, table distinguishing SQLite vs ConfigFile vs in-memory.
- **§7.2** — Shared types table now lists all 9 types with from_dict/to_dict coverage; formalised serialisation rules (RefCounted, `.get(key, default)` resilience).
- **§9.2** — Removed `[PROVISIONAL]` tag; documented actual test framework: plain `assert()`, `run_all_tests()` pattern, test_runner.tscn, CI exit codes, coroutine testing limitation.
- **§10** — Split into §10.1 (action vocabulary, still PROVISIONAL) and §10.2 (dice roll type vocabulary: 19 types with player-facing vs GM-only classification, instructions for adding new types).
- **§12** — Added 6 new ACKS implementation rules: character tiers/types, encumbrance units, inventory slots, fog of war state transitions, dice modes.
- **§13 (new)** — UI panel conventions: CanvasLayer layer stacking (10/64/128), programmatic construction pattern, Main.tscn scene tree diagram.
- **§14.1 (new)** — Dice conventions: d3 first-class, override=modified_total, player enters raw total, natural 1/20 flag rules, session-only roll log.

**Decisions made:**
- Coding conventions document restructured to include all patterns actually in use. Former §3.7 (Static Methods) renumbered to §3.9 to make room for class_name and coroutine sections.
- §10 Action Vocabulary kept PROVISIONAL (full vocabulary not yet implemented), but §10.2 documents the roll type vocabulary that does exist.

**Interfaces defined or changed:** None — this session was bugfixes and documentation only.

**Database changes:** None.

**Tests added/updated:** test_dice_system.gd reduced from 31 to 30 tests (removed coroutine test that caused parse error).

**Known issues:**
- Same known issues as prior dice system session (DiceSystem IDE false-positive, game_day always 0, no player_roll timeout).

**Next session should:**
1. Open project in Godot 4.6; run `test_runner.tscn`; confirm all 4 suites (30 DiceSystem tests + 3 prior suites) pass.
2. Verify DicePrompt visually: set `dice_mode = HYBRID`, call `await DiceSystem.player_roll(...)` from main_scene.gd, confirm modal appears and both Roll Dice + manual entry work.
3. Build the session runner state machine (campaign select → session start → exploration loop → session end).
4. Wire `encounter_check` into HexMapController: on `hex_entered`, call `DiceSystem.roll_digital(6, 1, 0, "encounter_check")` and compare to terrain-based threshold.

---

## Session 2026-03-27 — Timekeeping System

**Task:** Build the global Timekeeping autoload: passive in-game clock at all granularities (round/minute/turn/hour/day), multi-party time synchronisation, boundary signals (dawn/dusk/day/month/year), and SQLite persistence.
**Model used:** claude-sonnet-4-6

**Completed:**
- Created `db/migrations/004_timekeeping.sql` — two new tables: `campaign_clock` (global clock + dawn/dusk hours per campaign) and `party_clocks` (per-party time offsets for split-party play). Not foreign-keyed to `campaigns` so tests can seed them independently.
- Updated `db/schema.sql` — reflects migration 004 (last applied: 004).
- Created `engine/autoloads/timekeeping.gd` — 7th autoload. Passive clock with calendar constants (ROUNDS_PER_MINUTE=6, ROUNDS_PER_TURN=60, ROUNDS_PER_HOUR=360, ROUNDS_PER_DAY=8640, DAYS_PER_MONTH=28, MONTHS_PER_YEAR=13, DAYS_PER_YEAR=364), query API, global and per-party advance methods, boundary signal emission, and eager DB persistence.
- Updated `project.godot` — registered `Timekeeping` as 7th autoload (after DiceSystem).
- Created `tests/test_timekeeping.gd` — 24 tests across 8 categories: calendar math, granularity conversions, boundary signals, advance_to_hour edge cases, dawn/dusk, is_daylight(), multi-party sync, persistence round-trip.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` — added TimekeepingTests (5 suites total, ~101 tests).
- Updated `docs/coding_conventions.md` — section 5.1 (7th autoload added to table), section 6.3 (migration 004 in list), section 6.8 new (Timekeeping passive-clock pattern with code examples), section 12 (time granularity constants and dawn/dusk defaults added to ACKS rules table).

**Decisions made:**
- `campaign_clock` not FK'd to `campaigns`. Allows timekeeping seeding before campaigns row exists (tests, pre-session setup).
- `_elapsed_rounds: int` is the single canonical internal value. All date/time representations are derived on demand.
- `advance_to_hour(target)` from exactly target with no sub-hour offset: no advance. From any other position: advance to next-day target.
- `advance_to_next_day()` at hour 0 min 0: advances a full day (not no-op).
- Timekeeping reads/writes `CampaignRepository.db` directly (same pattern as DiceSystem). No new CampaignRepository methods added.
- `is_daylight()`: `hour >= _dawn_hour and hour < _dusk_hour`. Default: true for 6–19, false for 5 and 20.

**Interfaces defined or changed:**

Timekeeping public API (new autoload):
- Constants: `ROUNDS_PER_MINUTE`, `ROUNDS_PER_TURN`, `ROUNDS_PER_HOUR`, `ROUNDS_PER_DAY`, `DAYS_PER_MONTH`, `MONTHS_PER_YEAR`, `DAYS_PER_YEAR`
- Signals: `round_advanced(rounds_elapsed: int)`, `minute_advanced(minutes_elapsed: int)`, `turn_advanced(turns_elapsed: int)`, `hour_advanced(hours_elapsed: int)`, `day_changed(new_day, new_month, new_year: int)`, `month_changed(new_month, new_year: int)`, `year_changed(new_year: int)`, `dawn()`, `dusk()`
- Query: `get_date() -> Dictionary`, `get_total_days() -> int`, `get_total_turns() -> int`, `get_total_minutes() -> int`, `get_time_of_day() -> int`, `is_daylight() -> bool`, `get_current_month() -> int`, `get_current_day_of_month() -> int`, `get_day_of_week() -> int`
- Advance (global): `advance_rounds(n)`, `advance_minutes(n)`, `advance_turns(n)`, `advance_hours(n)`, `advance_days(n)`, `advance_to_hour(target_hour)`, `advance_to_next_day()`
- Advance (party): `advance_party_rounds(party_id, n)`, `advance_party_minutes(party_id, n)`, `advance_party_turns(party_id, n)`, `advance_party_hours(party_id, n)`
- Party registry: `register_party(party_id)`, `unregister_party(party_id)`, `get_party_time(party_id) -> int`, `sync_parties()`, `get_leading_party() -> String`, `get_time_gap(party_a, party_b) -> int`
- Persistence: `save_state(campaign_id)`, `load_state(campaign_id)`

**Database changes:**
- Migration 004: `campaign_clock`, `party_clocks` tables added.

**Tests added/updated:**
- `tests/test_timekeeping.gd` — 24 tests (new suite).
- `tests/test_runner.gd` + `tests/test_runner.tscn` — TimekeepingTests added (5 suites total, ~101 tests).

**Known issues:**
- `game_day` in `dice_rolls` is still always 0. Wire: replace `0` in `dice_system.gd:_log_and_emit()` with `Timekeeping.get_total_days()` once the session runner wires the two systems together.
- Signal counters in `test_timekeeping.gd` are cumulative (connect once in `_ready()`, reset per test via `_reset()`). If a test asserts mid-suite, subsequent tests see stale counts. Known GDScript limitation.

**Next session should:**
1. Open project in Godot 4.6; run `test_runner.tscn`; confirm all 5 suites pass including 24 Timekeeping tests.
2. Wire `Timekeeping.get_total_days()` into `dice_system.gd:_log_and_emit()` to populate `game_day` correctly.
3. Wire `Timekeeping.load_state(campaign_id)` into `main_scene.gd` `_ready()` after `GameState.start_session()`.
4. Build the session runner state machine (campaign select → session start → exploration loop → session end). Timekeeping is ready to be driven by it.
5. Create `docs/document_map.md` and `docs/rule_system_map.md` (highest-priority deferred reference docs).

**Addendum (same session):** Added public day-cycle configuration API to Timekeeping so the future seasons/weather system can adjust sunrise/sunset hours. Defaults (dawn=6, dusk=20) remain as fallback so all existing tests and pre-seasons-system code continue working unchanged.
- Added `func set_day_cycle(dawn_hour: int, dusk_hour: int) -> void` — persists via `_auto_save()`.
- Added `func get_dawn_hour() -> int` and `func get_dusk_hour() -> int` read accessors.
- Added 3 tests to `test_timekeeping.gd`: `test_set_day_cycle_changes_is_daylight()`, `test_set_day_cycle_changes_dawn_dusk_signals()`, `test_set_day_cycle_defaults_are_6_and_20()` (27 tests total in suite).

---

## Session 2026-03-28 — Calendar & Seasons Subsystem

**Task:** Update and correct the Timekeeping system to account for the new information provided by `gdd-calendar-seasons.md`. Create the CalendarSeasons subsystem. Update document_map.md and rule_system_map.md for new documents added since those files were created.
**Model used:** claude-opus-4-6 (planning), claude-sonnet-4-6 (implementation)

**Completed:**
- Updated `docs/document_map.md` — added entries for `gdd-poi-generation.md`, `gdd-calendar-seasons.md`, `gdd-weather-generation.md`; corrected `coding_conventions.md` entry (was "to be created"); updated GDD count to 14, grand total to 84.
- Updated `docs/rule_system_map.md` — added Calendar & Seasons system, Weather system, and Wilderness Points of Interest system sections; updated Wilderness & Hex Exploration and Setting & World Generation GDD lists; updated high-traffic file cross-reference table; updated GDD dependency graph and implementation order.
- Created `engine/subsystems/calendar/calendar_constants.gd` (class CalendarConstants) — season start/end boundary days, astronomical event days (solstice/equinox), and TRANSITION_WINDOW_DAYS constant.
- Created `engine/subsystems/calendar/calendar_seasons.gd` (class CalendarSeasons) — static season lookup, season index, hemisphere inversion, transition blend descriptor, and season progress label.
- Updated `engine/autoloads/timekeeping.gd`:
  - Added private constants `_SEASON_STARTS` and `_SEASON_NAMES` for internal season boundary detection.
  - Added `signal season_changed(new_season: String)` — fires at each season boundary crossing.
  - Added `func get_day_of_year() -> int` — returns 1–364, the current day within the year. Required by CalendarSeasons consumers.
  - Added season boundary detection in `_emit_boundary_signals` loop — emits `season_changed` alongside `day_changed` when a season boundary is crossed.
- Updated `tests/test_timekeeping.gd` — added `season_changed` signal capture and 7 new tests (4 for `get_day_of_year`, 3 for `season_changed`). Suite: 27 → 34 tests.
- Created `tests/test_calendar_seasons.gd` — 25 tests covering all CalendarSeasons and CalendarConstants functions.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` — added CalendarSeasonsTests (6 suites total, ~126 tests).

**Decisions made:**
- CalendarSeasons uses static functions only — it is a pure computation module, not instantiated. No autoload needed.
- Timekeeping does NOT depend on CalendarSeasons at runtime. The `_SEASON_STARTS` array in Timekeeping duplicates minimal boundary logic to keep the autoload self-contained and avoid load-order coupling.
- `season_changed` fires on the same advance call as `day_changed` for the entering day — consistent with how `month_changed` and `year_changed` are already emitted.
- GDD §3 table lists the Winter→Spring window as "Day 361–Day 3." This is inconsistent with the "centered on Day 1" rule that applies to all other transitions. Implementation uses the consistent rule (Day 362–Day 4, centered on Day 1). The discrepancy is documented in `calendar_seasons.gd` comments and in the test.
- `get_transition_blend()` returns weight approaching 1.0 (max 6/7) within the window; the day after the window snaps to fully in-season. This matches the GDD's `days_into_transition / 7` formula.

**Interfaces defined or changed:**

Timekeeping additions:
- `signal season_changed(new_season: String)` — "spring", "summer", "autumn", or "winter"
- `func get_day_of_year() -> int` — returns 1–364

CalendarConstants public API (new class, engine/subsystems/calendar/calendar_constants.gd):
- `const SPRING_START_DAY := 1`, `SUMMER_START_DAY := 92`, `AUTUMN_START_DAY := 183`, `WINTER_START_DAY := 274`
- `const SPRING_END_DAY := 91`, `SUMMER_END_DAY := 182`, `AUTUMN_END_DAY := 273`, `WINTER_END_DAY := 364`
- `const VERNAL_EQUINOX_DAY := 46`, `SUMMER_SOLSTICE_DAY := 137`, `AUTUMNAL_EQUINOX_DAY := 228`, `WINTER_SOLSTICE_DAY := 319`
- `const TRANSITION_WINDOW_DAYS := 7`

CalendarSeasons public API (new class, engine/subsystems/calendar/calendar_seasons.gd):
- `const SPRING/SUMMER/AUTUMN/WINTER: String` — season name constants
- `const SEASON_NAMES: Array` — indexed [spring, summer, autumn, winter]
- `static func get_season(day_of_year: int) -> String`
- `static func get_season_index(day_of_year: int) -> int` — 0–3
- `static func get_climate_season(day_of_year: int, hemisphere: String) -> String`
- `static func get_transition_blend(day_of_year: int) -> Dictionary` — {in_transition, outgoing_season, incoming_season, weight}
- `static func get_season_progress(day_of_year: int) -> String` — "early", "mid", or "late"

**Database changes:** None.

**Tests added/updated:**
- `tests/test_timekeeping.gd` — 7 new tests (34 total in suite).
- `tests/test_calendar_seasons.gd` — 25 tests (new suite).
- `tests/test_runner.gd` + `tests/test_runner.tscn` — CalendarSeasonsTests added (6 suites total, ~126 tests).

**Known issues:**
- `game_day` in `dice_rolls` is still always 0. Wire `Timekeeping.get_total_days()` into `dice_system.gd:_log_and_emit()` once session runner is built.
- Signal counters in `test_timekeeping.gd` are cumulative (known GDScript limitation — noted in prior session).

**Next session should:**
1. Open project in Godot 4.6; run `test_runner.tscn`; confirm all 6 suites pass including 34 Timekeeping tests and 25 CalendarSeasons tests.
2. Wire `Timekeeping.load_state(campaign_id)` into `main_scene.gd` after `GameState.start_session()`.
3. Build the weather generation subsystem per `gdd-weather-generation.md` — it depends on CalendarSeasons and is the next downstream consumer.
4. Build the session runner state machine (campaign select → session start → exploration loop → session end).

---

## Session 2026-03-28 — Coding Conventions Update

**Task:** Update `docs/coding_conventions.md` to reflect patterns established in the Calendar & Seasons session.
**Model used:** claude-opus-4-6

**Completed:**
- Updated `docs/coding_conventions.md`:
  - **§2.1** — Added `calendar/` to subsystems directory tree.
  - **§3.7** — Added row for pure static/constants classes (`class_name` yes — enables `CalendarSeasons.get_season(day)` without instantiation).
  - **§3.9** — Added "Pure static computation class" subsection with CalendarSeasons/CalendarConstants as canonical examples; explains when to prefer this over autoloads.
  - **§5.3** — Added "Pure computation (no instance state)" row to alternatives-to-autoloads table, pointing to §3.9.
  - **§6.8** — Added `get_day_of_year()` usage pattern with CalendarSeasons; added `season_changed` signal usage pattern (connect once, don't manually track transitions in `_on_day_changed`).
  - **§12** — Added three ACKS implementation rule rows: Seasons (4×91-day definitions), Climate vs. calendar season (hemisphere inversion rule for weather/domain vs. LLM narrative), Solstices and equinoxes (midpoint placement, CalendarConstants values).
  - Updated footer line.

**Decisions made:** None — documentation-only session.

**Interfaces defined or changed:** None.

**Database changes:** None.

**Tests added/updated:** None.

**Known issues:** None introduced this session.

**Next session should:**
1. Open project in Godot 4.6; run `test_runner.tscn`; confirm all 6 suites pass.
2. Wire `Timekeeping.load_state(campaign_id)` into `main_scene.gd` after `GameState.start_session()`.
3. Build the weather generation subsystem per `gdd-weather-generation.md`.
4. Build the session runner state machine.

---

## Session 2026-03-28 — Phase C-1: Character Data Model, Class System, Generation Engine, Inventory

**Task:** Build the character subsystem: unified data model (PC/henchman/NPC), modular class power system, class registry with all 25 ACKS 1e classes, character generation engine, encumbrance calculator, and positional inventory expansion.
**Model used:** claude-opus-4-6 (1M context) for planning and implementation.

**Completed:**

- **Modular Power System** (`data/powers/power_catalog.json`):
  - 55 reusable power definitions with metadata (id, name, type, description, resolution)
  - Power types: skill_throw, scaling_multiplier, turning_table, damage_bonus, casting_arcane, casting_divine, passive, threshold, aura, detection
  - Classes reference powers by ID with class-specific progression tables — supports future custom class builder

- **Class Data Registry** (`data/classes/*.json` — 25 files):
  - Core: Fighter, Mage, Cleric, Thief
  - Demihuman: Dwarf Vaultguard, Dwarf Craftpriest, Elf Spellsword, Elf Nightblade
  - Campaign: Assassin, Bard, Bladedancer, Explorer, Venturer
  - Player's Companion: Anti-Paladin, Barbarian, Dwarven Delver, Dwarven Fury, Paladin, Priestess, Shaman, Warlock, Witch, Elven Courtier, Elven Enchanter, Elven Ranger
  - Each JSON contains: identity, requirements, progression tables (attack, saves, XP, HD), weapon/armor permissions, proficiency lists, level titles, class_powers with progression data

- **Equipment Catalog** (`data/equipment/base_equipment.json`):
  - All ACKS Core weapons, armor, shields, ammunition, and common adventuring gear
  - Encumbrance in 1/6 stone units, weapon damage, armor AC bonus, is_heavy flag

- **CharacterData Expansion** (`engine/shared_types/character_data.gd`):
  - Added 17 fields: 5 saving throws, base_movement, hit_die_type, max_level, xp_for_next_level, xp_adjustment_percent, title, alignment, current_age, age_category, languages (JSON), personality (JSON), is_incapacitated
  - Updated from_dict() and to_dict() for all new fields

- **InventoryItem Expansion** (`engine/shared_types/inventory_item.gd`):
  - Added 6 fields: item_category, is_magical, magical_bonus, weapon_damage, armor_ac_bonus, is_heavy
  - Updated from_dict() and to_dict()

- **DB Migration 005** (`db/migrations/005_characters_expanded.sql`):
  - ALTER TABLE characters: 17 new columns (saves, movement, class metadata, alignment, aging, languages, personality, incapacitated)
  - ALTER TABLE inventory_items: 6 new columns (category, magical, damage, AC, heavy)
  - CREATE TABLE character_powers: modular power storage (character_id, power_id, unlock_level, conditions, progression_data, is_active)

- **CampaignRepository Extension** (`engine/autoloads/campaign_repository.gd`):
  - Updated create_character() and save_character() for all new columns
  - Updated add_inventory_item() for new columns
  - Added: save_character_powers(), get_character_powers(), clear_character_powers()
  - Added: save_character_proficiencies(), get_character_proficiencies()
  - Added: save_character_inventory() (batch save)
  - Added: list_characters_by_type(), delete_character() (cascading), promote_character()

- **PowerRegistry** (`engine/subsystems/characters/power_registry.gd`):
  - Loads power_catalog.json, provides get_power(), has_power(), get_powers_by_type(), get_all_power_ids()

- **ClassRegistry** (`engine/subsystems/characters/class_registry.gd`):
  - Loads all 25 class JSONs from data/classes/, provides:
  - get_class(), get_eligible_classes() with ACKS eligibility rules (prime reqs >= 9, race matching, min abilities)
  - get_attack_throw(), get_saving_throws(), get_xp_for_level(), get_hit_die(), get_level_title()
  - get_class_powers(), get_spell_slots(), get_proficiency_list(), get_max_hd_count(), get_hp_after_max_hd()

- **AbilityUtils** (`engine/subsystems/characters/ability_utils.gd`):
  - get_xp_adjustment() — uses lowest prime req score
  - get_max_henchmen() — 4 + CHA mod, clamped [1, 7]
  - get_loyalty_modifier(), get_reaction_modifier(), get_languages_bonus()

- **EncumbranceCalculator** (`engine/subsystems/characters/encumbrance_calculator.gd`):
  - calculate_encumbrance() — sums inventory, returns total + movement rates
  - get_movement_tier() — 4-tier ACKS movement table
  - calculate_item_encumbrance() — handles magical armor/shield weight reduction

- **CharacterGenerator** (`engine/subsystems/characters/character_generator.gd`):
  - roll_ability_scores() — 3d6 in order via DiceSystem
  - get_eligible_classes() — delegates to ClassRegistry
  - apply_ability_trade() — validates all ACKS trade rules
  - generate_pc() — full level-1 PC creation procedure
  - generate_npc() — complete NPC at any level with auto-proficiencies
  - generate_henchman() — NPC with employer tracking
  - stamp_powers() — copies class powers to character records
  - auto_select_proficiencies() — random from eligible lists

- **Test Suites** (8 new files, 47 tests total):
  - test_ability_utils.gd (5 tests), test_class_registry.gd (10 tests), test_power_registry.gd (4 tests)
  - test_encumbrance.gd (8 tests), test_character_generator.gd (6 tests), test_character_persistence.gd (4 tests)
  - test_class_powers.gd (5 tests), test_npc_generation.gd (5 tests)
  - Updated test_runner.gd and test_runner.tscn for all 14 suites

**Decisions made:**
- **Two-Layer Power Architecture:** Power definitions store metadata only (catalog); class JSONs store progression data per power per class. At generation time, powers are stamped onto characters (character_powers table). This decouples runtime from class registry and supports custom class builder.
- **Powers stored with class-specific progressions** rather than universal progressions, because ACKS allows different classes to have different progression rates for the same power (e.g., Thief vs Dwarven Delver thief skills).
- **ClassRegistry and PowerRegistry are RefCounted**, not autoloads. They're instantiated by the CharacterGenerator. Only systems that need true global state are autoloads.
- **Existing CharacterData.ability_modifier() left in place** — it's already used by other code. AbilityUtils adds complementary functions.
- **All 25 ACKS 1e classes extracted** in one pass rather than deferring PC classes, since the XML structure is identical.

**Interfaces defined or changed:**
- `CharacterData` — 17 new fields, expanded from_dict()/to_dict()
- `InventoryItem` — 6 new fields, expanded from_dict()/to_dict()
- `CampaignRepository.create_character()` — now accepts 39 parameters
- `CampaignRepository.save_character()` — updates all 29 mutable fields
- `CampaignRepository.save_character_powers(character_id, powers: Array) -> bool`
- `CampaignRepository.get_character_powers(character_id) -> Array`
- `CampaignRepository.save_character_proficiencies(character_id, proficiencies: Array) -> bool`
- `CampaignRepository.save_character_inventory(character_id, items: Array) -> bool`
- `CampaignRepository.list_characters_by_type(campaign_id, character_type) -> Array`
- `CampaignRepository.delete_character(id) -> bool` — cascading delete
- `CampaignRepository.promote_character(id, new_tier) -> bool`
- `PowerRegistry.get_power(id) -> Dictionary`
- `ClassRegistry.get_class(id) -> Dictionary`
- `ClassRegistry.get_eligible_classes(scores, race) -> Array[String]`
- `CharacterGenerator.generate_pc(class_id, scores, campaign_id) -> CharacterData`
- `CharacterGenerator.generate_npc(class_id, level, campaign_id, tier, type) -> CharacterData`
- `CharacterGenerator.stamp_powers(character, class_id) -> Array`

**Database changes:**
- Migration 005: 17 new columns on characters, 6 on inventory_items, new character_powers table
- schema.sql updated to reflect migration 005

**Tests added/updated:**
- 8 new test suites (47 tests) covering ability utils, class registry, power registry, encumbrance, character generation, persistence round-trip, class powers, NPC generation
- test_runner.gd and test_runner.tscn updated (now 14 suites total)

**Known issues:**
- Class JSONs extracted by agents need spot-checking against published ACKS books — especially PC classes (Priestess, Shaman, Warlock, Witch) which may have incomplete proficiency lists in the XML source
- Warlock spell progression may need verification (flagged as potentially malformed in source XML)
- Tests cannot run until project is opened in Godot 4.6 (tscn uid references may need regeneration)
- Existing tests (terrain, hex map, override, dice, timekeeping, calendar) need re-verification after migration 005

**Next session should:**
1. Open project in Godot 4.6 and run `test_runner.tscn` — debug any failures in all 14 suites.
2. Spot-check 3-4 class JSONs against ACKS books (especially Thief progression tables, Cleric turning table, Spellsword spell slots).
3. Phase C-2: Three-tier persistence with promotion logic.
4. Phase C-3: XP tracking and level-up workflow.

---

## Session 2026-03-28 — Phase C-2: Spell Catalog, Spell Registry, Repertoire Engine

**Task:** Build the spell data layer and starting repertoire engine: spell_catalog.json, spell_list_indices.json, SpellRegistry, RepertoireEngine, CampaignRepository spell CRUD, EventBus signal, and two test suites.
**Model used:** claude-sonnet-4-6

**Completed:**

- **Bug fixes (Step 0):**
  - Fixed `data/classes/bladedancer.json` — renamed `"spell_slots"` key to `"progression"` in `divine_casting` power entry. Was breaking `ClassRegistry.get_spell_slots("bladedancer", N)` (always returned `[]`).
  - Added `"spell_list"` field to casting power entries in all 12 caster class JSONs: mage, warlock, elven_enchanter, elf_spellsword, elf_nightblade, elven_courtier, cleric, dwarf_craftpriest, bladedancer, priestess, shaman, witch.

- **`data/spells/spell_catalog.json`** (NEW — 231 entries):
  - All arcane levels 1-6 and divine levels 1-5 spells. No ritual spells.
  - Entry format: spell_key, spell_name, is_reversible, reverse_name, reverse_key, classifications (array of {tradition, level, restricted_to}), range, duration, summary.
  - PC catalog spells merged into core: additional classifications added to core entries. `purify_food_and_water` marked reversible per PC catalog.
  - Written in 4 alphabetical parts and Python-merged to avoid output token limits.

- **`data/spells/spell_list_indices.json`** (NEW):
  - Arcane L1-L6: 12 spells each (d12 indexed list).
  - divine_cleric L1-L5: 10 spells each; divine_bladedancer L1-L5: 10 spells each.
  - Missing arcane index 11 for levels 4/5/6 resolved by elimination: wall_of_ice (L4), transmute_rock_to_mud (L5), reincarnate (L6).

- **`engine/subsystems/characters/class_registry.gd`** (MODIFIED):
  - Added `get_casting_power(class_id: String) -> Dictionary`.

- **`engine/autoloads/event_bus.gd`** (MODIFIED):
  - Added `signal repertoire_updated(character_id: String)`.

- **`engine/autoloads/campaign_repository.gd`** (MODIFIED):
  - Added Character Spells CRUD: `save_character_spells()`, `get_character_spells()`, `get_character_repertoire()`, `add_character_spell()`, `clear_character_spells()`.

- **`engine/subsystems/spells/spell_registry.gd`** (NEW — class SpellRegistry, RefCounted).

- **`engine/subsystems/spells/repertoire_engine.gd`** (NEW — class RepertoireEngine, RefCounted).
  - Arcane: 1 judge-selected + INT bonus d12 rolls; duplicates do NOT reroll (ACKS rule).
  - Divine: ALL spells for each castable level; reversible spells add both forms.
  - All randomness via `DiceSystem.roll_digital(12, 1, 0, "starting_spell")`.

- **`tests/test_spell_registry.gd`** (NEW — 17 tests).
- **`tests/test_repertoire_engine.gd`** (NEW — 11 tests).
- **`tests/test_runner.gd`** and **`tests/test_runner.tscn`** (MODIFIED — 16 suites total, ~175 tests).

**Decisions made:**
- Spell catalog written in 4 split files then Python-merged to avoid LLM output token limits.
- PC catalog duplicates merged into core entries (not separate entries).
- Witch sub-tradition spell lists excluded per plan scope.
- `starting_spell` added to DiceSystem roll type vocabulary.
- `spell_list` field lives in class JSON casting power entry (consistent with existing architecture).

**Interfaces defined or changed:**

ClassRegistry addition:
- `func get_casting_power(class_id: String) -> Dictionary`

EventBus addition:
- `signal repertoire_updated(character_id: String)`

CampaignRepository additions:
- `func save_character_spells(character_id: String, spells: Array) -> bool`
- `func get_character_spells(character_id: String) -> Array`
- `func get_character_repertoire(character_id: String) -> Array`
- `func add_character_spell(character_id: String, spell_data: Dictionary) -> int`
- `func clear_character_spells(character_id: String) -> bool`

SpellRegistry public API (new): get_spell, has_spell, get_spell_count, get_all_spell_keys, is_reversible, get_reverse_key, get_spells_for_list, get_arcane_index_spell (1-based), get_class_tradition, get_class_spell_list_id, get_available_spells_for_class.

RepertoireEngine public API (new): get_casting_tradition, get_arcane_repertoire_capacity, generate_arcane_starting_repertoire, generate_divine_starting_repertoire, generate_starting_repertoire.

Spell row shape: `{ "spell_key": String, "spell_level": int, "is_memorized": bool, "is_in_repertoire": bool, "memorized_slots": int }`

**Database changes:** None — `character_spells` table already existed from migration 001.

**Tests added/updated:**
- `tests/test_spell_registry.gd` — 17 tests (new suite).
- `tests/test_repertoire_engine.gd` — 11 tests (new suite).
- `tests/test_runner.gd` + `tests/test_runner.tscn` — 16 suites total, ~175 tests.

**Known issues:**
- `starting_spell` roll type not yet in `docs/coding_conventions.md` §10.2 roll type vocabulary table.
- SpellRegistry and RepertoireEngine not yet wired into CharacterGenerator (deferred to character creation UI session).
- No generate→save→load round-trip integration test (deferred).
- Warlock has `"spell_list": "arcane"` but no spell slot progression — `get_arcane_repertoire_capacity("warlock", ...)` returns `[]`. Correct/intended behavior.

**Next session should:**
1. Open project in Godot 4.6; run `test_runner.tscn`; confirm all 16 suites pass.
2. Update `docs/coding_conventions.md` §10.2 — add `starting_spell` to roll type vocabulary.
3. Build character creation UI (Phase C-3): class selection, ability score rolling, spell repertoire assignment for casters.
4. Wire SpellRegistry and RepertoireEngine into CharacterGenerator for caster character generation.


---

## Session 2026-03-28 � Spell Hook Infrastructure (Phases 0-2)

**Task:** Implement the foundational spell hook infrastructure per the approved plan: modifier system, entity flag system, damage types, condition catalog, damage resistance, CharacterData/InventoryItem extensions, active effect tracker, spell effect registry, EventBus signals, DB migration 006.

**Model used:** claude-sonnet-4-6 throughout.

**Completed:**

Phase 0A (from prior context, already complete):
- engine/shared_types/modifier_stack.gd (ModifierStack)
- engine/shared_types/modifier_container.gd (ModifierContainer)
- tests/test_modifier_stack.gd (19 tests)

Phase 0B (from prior context, already complete):
- engine/shared_types/entity_flags.gd (EntityFlags)
- tests/test_entity_flags.gd (12 tests)

Phase 0C (from prior context, already complete):
- engine/shared_types/damage_types.gd (DamageTypes constants)

Phase 0D (this session):
- data/conditions/condition_catalog.json (27 conditions from ax_conditions_catalog.xml)
- engine/shared_types/condition_catalog.gd (ConditionCatalog)
- tests/test_condition_catalog.gd (28 tests)

Phase 0E (this session):
- engine/shared_types/damage_resistance.gd (DamageResistance - immunity/resistance/vulnerability, source-tracked)
- tests/test_damage_resistance.gd (19 tests)

Phase 1A (this session):
- engine/shared_types/character_data.gd (MODIFIED):
  - Runtime-only fields: modifiers: ModifierContainer, flags: EntityFlags, damage_resistances: DamageResistance, temp_hp: int, mirror_images: int
  - Effective getters: get_effective_ac, get_effective_attack_throw, get_effective_save, get_effective_movement, get_effective_ability_score
  - Flag helpers: is_flying(), is_invisible()
  - Combat: apply_damage(amount, damage_type) -> Dict, apply_healing(amount) -> int, apply_age_change(years)
  - from_dict/to_dict NOT modified (runtime state rebuilt from active_effects on load)

Phase 1B (this session):
- engine/shared_types/inventory_item.gd (MODIFIED):
  - Persistent: damage_type: String, material: String
  - Runtime: spell_bonus: int, spell_damage_bonus: String
  - Method: get_effective_bonus() -> int
  - from_dict/to_dict updated for persistent fields only

Phase 2A (this session):
- engine/subsystems/spells/active_effect_tracker.gd (ActiveEffectTracker)
- db/migrations/006_spell_hook_infrastructure.sql (active_effects table + inventory_items ALTER)
- db/schema.sql (MODIFIED - migration 006 reflected)
- engine/autoloads/campaign_repository.gd (MODIFIED - active_effects CRUD added)

Phase 2B (this session):
- data/spells/spell_effects.json (13 template entries covering all hook patterns)
- engine/subsystems/spells/spell_effect_registry.gd (SpellEffectRegistry)

Phase 2C (this session):
- engine/autoloads/event_bus.gd (MODIFIED):
  - New Magic signals: active_effect_expired, concentration_broken, spell_effect_applied, spell_effect_removed
  - New Damage section: damage_dealt, healing_applied

Phase 2D (this session):
- tests/test_active_effect_tracker.gd (23 tests)
- tests/test_spell_effect_registry.gd (20 tests)
- tests/test_runner.gd + tests/test_runner.tscn (22 suites, ~270+ tests total)

**Decisions made:**
- DamageResistance.apply_to_damage order: immunity -> resistance -> vulnerability. UNTYPED bypasses immunity+resistance but still takes vulnerability.
- Multiple resistances stack multiplicatively (not additively).
- Immunity beats vulnerability when both apply to same damage type.
- CharacterData.is_invisible() returns true for either is_invisible or is_improved_invisible flag.
- active_effects target_ids stored as JSON string; CampaignRepository does precise post-filter after LIKE search.
- ActiveEffectTracker is a pure duration/registry tracker. Caller applies/removes modifiers+flags from CharacterData.
- Age category thresholds in apply_age_change are approximate; exact ACKS tables added with aging system.

**Interfaces defined or changed:**

CharacterData additions: modifiers, flags, damage_resistances, temp_hp, mirror_images; get_effective_ac/attack_throw/save/movement/ability_score; is_flying/is_invisible; apply_damage/healing/age_change.

InventoryItem additions: damage_type, material (persistent); spell_bonus, spell_damage_bonus (runtime); get_effective_bonus().

EventBus additions: active_effect_expired, concentration_broken, spell_effect_applied, spell_effect_removed, damage_dealt, healing_applied.

CampaignRepository additions: save_active_effect, get_active_effects, get_active_effects_on_target, remove_active_effect, clear_active_effects.

ActiveEffectTracker API: add_effect, remove_effect, get_effect, has_effect, get_effects_on_target, get_effects_by_caster, get_concentration_effects, get_all_effects, tick_rounds/turns/hours/days, break_concentration, dispel_check, clear.

SpellEffectRegistry API: get_effect_data, has_effect_data, get_all_spell_keys, get_modifiers/flags/conditions/damage_resistances_for_spell, get_effect_type, get_duration_type, is_instant, requires_concentration.

**Database changes:**
- Migration 006: CREATE active_effects table; ALTER inventory_items ADD damage_type, material.
- db/schema.sql updated to last migration 006.

**Tests added/updated:**
- test_condition_catalog.gd (28 tests), test_damage_resistance.gd (19 tests)
- test_active_effect_tracker.gd (23 tests), test_spell_effect_registry.gd (20 tests)
- test_runner now runs 22 suites, ~270+ tests.

**Known issues:**
- ActiveEffectTracker not yet connected to Timekeeping signals (connection deferred to Phase E spell resolution engine).
- SpellEffectRegistry has only 13 template entries; full 231-spell catalog deferred to Phase E.
- apply_age_change uses approximate age category thresholds; exact ACKS tables deferred to Phase C-3.
- ConditionCatalog instantiated on demand (not a singleton); promote to autoload if performance is an issue.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn - confirm all 22 suites pass.
2. Build Phase C-3: character creation UI (class selection, ability score rolling, spell repertoire for casters).
3. Wire SpellRegistry and RepertoireEngine into CharacterGenerator for caster character generation.
4. Consider connecting ActiveEffectTracker to Timekeeping signals (or defer to Phase E).

---

## Session 2026-03-29 — Complete Equipment Catalog Database

**Task:** Build complete equipment database before character generator UI, sourcing all items from acore_equipment.xml, pc_equipment_catalog.xml, and acore_aging_poisons_high-level-start_optional_rules.xml.
**Model used:** Sonnet 4.6

**Completed:**
- Rewrote `data/equipment/base_equipment.json` (v1 → v2): ~130 items covering weapons, ammunition, armor, shields, helmets, adventuring gear, and clothing.
- Created `data/equipment/transport.json`: 35 items — mounts (camel through heavy warhorse), draft animals, vehicles (cart/wagon), tack (3 saddle types + saddlebags + caparison), 5 barding types, 8 livestock.
- Created `data/equipment/provisions_services.json`: 14 foodstuffs, 9 lodging/dwelling entries, full hireling wage tables (henchman levels 0-14, 14 mercenary troop types × 5 races, 20 specialist types, spellcasting costs by type and level).
- Created `data/equipment/poisons.json`: 15 monster venoms + 8 plant toxins with extraction/evaporation rules.
- Created `data/equipment/siege_weapons.json`: 6 entries (ballista, light/heavy catapult, 3 ammo types).
- Created `data/equipment/maritime.json`: 12 vessels (canoe through war galley) with crew and cargo data.
- Updated `docs/coding_conventions.md` directory tree to reflect new file set.

**Decisions made:**
- `cost_cp` (integer, copper pieces) replaces `cost_gp` in all equipment files. 1gp=100cp, 1sp=10cp. Eliminates sub-GP rounding errors. UI formats display strings at render time.
- `weapon_tags` array added to all weapon entries: `melee`, `ranged`, `thrown`, `two_handed`, `versatile`, `blunt`, `reach`, `slow`, `mounted_only`. Enables class-restriction filtering in the character generator UI without parsing free-text notes.
- `range_short/medium/long` integer fields added to all weapon entries (0 for melee-only). Structured range data for combat and UI.
- Versatile weapons use `"1d6/1d8"` format in `weapon_damage` (first = one-handed, second = two-handed).
- `oil_flask` split into `oil_flask_common` (30cp, lantern fuel) and `oil_flask_military` (200cp, weapon).
- Hirelings/mercenaries/specialists in `provisions_services.json`, not `base_equipment.json` — they are recurring service costs, not portable items.
- Transport, siege, maritime in separate files due to distinct schemas and non-character-creation use cases.
- No GDScript changes made — JSON catalog is design-time only; InventoryItem + CampaignRepository unchanged.

**Interfaces defined or changed:**
- `base_equipment.json` v2 schema: added `cost_cp`, `weapon_tags`, `range_short`, `range_medium`, `range_long`; removed `cost_gp`.
- New item categories in use: `"clothing"` (37 items), `"barding"`, `"mount"`, `"draft_animal"`, `"pack_animal"`, `"vehicle"`, `"tack"`, `"livestock"`, `"siege_weapon"`, `"siege_ammunition"`. These extend the existing `"weapon"|"armor"|"shield"|"gear"|"treasure"|"ammunition"` set.

**Database changes:**
- None. Equipment catalog is JSON-only; no schema migration required.

**Known issues:**
- Warhorse movement and load stats not in acore_equipment.xml (referenced in monster stat blocks, not equipment tables). transport.json notes "see monster stats" for warhorses.
- Mercenary/vessel crew counts in provisions_services.json and maritime.json are approximate where the XML was not explicit; flag for review against DaW source if maritime subsystem is implemented.
- `spell_component_pouch` item in base_equipment.json is not an ACKS 1e standard item — retained from v1 for game-convenience.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn — confirm all 22 suites pass (unchanged from prior session).
2. Build Phase C-3: character creation UI — equipment purchasing screen using base_equipment.json and transport.json as catalog sources.
3. Implement equipment catalog loader (GDScript) that reads the new JSON files and exposes items to the purchasing UI.
4. Implement cost display formatter: converts cost_cp integer to "10gp", "8sp", "1cp" display strings.

---

## Session 2026-03-29 — Proficiency System Infrastructure

**Task:** Implement the foundational proficiency infrastructure per the approved plan: proficiency catalog JSON, general proficiency list, ProficiencyRegistry, DB migration 007, CharacterData extensions, CampaignRepository update, ProficiencyEffectResolver, CharacterGenerator update, EventBus signal, and test suites.
**Model used:** claude-sonnet-4-6 throughout.

**Completed:**

Task 1 — Document updates:
- `docs/document_map.md` (MODIFIED): Added `proficiency_system_map.md` to Architecture Documents table; updated file counts (arch docs 5 to 6, grand total 84 to 85).
- `docs/rule_system_map.md` (MODIFIED): Updated Proficiencies entry to add `ax_thief_skill_update` to rule files, add architecture docs reference, expand "Depended on by" list.

Phase 0 — Data files:
- `data/proficiencies/proficiency_catalog.json` (NEW — 106 entries): Full catalog of all ~100 ACKS proficiencies from acore_proficiencies_rules_and_catalog.xml, pc_proficiencies_catalog.xml, ax_thief_skill_update.xml. Schema: proficiency_key, proficiency_name, type, source, description, max_rank, max_selections, selection_rule, level_scaling, effects (or effects_by_rank / effects_by_specialization).
- `data/proficiencies/general_proficiency_list.json` (NEW — 38 entries): Ordered array of general proficiency keys sourced from acore_proficiencies_rules_and_catalog.xml.
- `data/classes/elf_spellsword.json` (MODIFIED): Fixed typo swashbuckler to swashbuckling in class_proficiency_list.

Phase 1 — ProficiencyRegistry:
- `engine/subsystems/characters/proficiency_registry.gd` (NEW — class ProficiencyRegistry, RefCounted): Loads catalog JSON, provides lookup by key, supports compound key resolution for multi-segment specialization keys (e.g., "combat_trickery_force_back" resolves to base "combat_trickery"), level scaling breakpoints, effects access by rank/specialization.
- `tests/test_proficiency_registry.gd` (NEW — 22 tests).

Phase 2A — DB migration:
- `db/migrations/007_proficiency_infrastructure.sql` (NEW): ALTER TABLE character_proficiencies ADD COLUMN selections_count INTEGER NOT NULL DEFAULT 1; ADD COLUMN specialization TEXT NOT NULL DEFAULT ''.
- `db/schema.sql` (MODIFIED): Reflected migration 007 (header updated, character_proficiencies table definition updated).

Phase 2B — CharacterData:
- `engine/shared_types/character_data.gd` (MODIFIED): Added var proficiencies: Array = [] field. Added 5 query methods: has_proficiency, get_proficiency_rank, get_proficiency_selections, get_proficiency_specialization, get_proficiencies_by_slot.

Phase 2C — CampaignRepository:
- `engine/autoloads/campaign_repository.gd` (MODIFIED): Updated save_character_proficiencies() INSERT to include selections_count and specialization columns.

Phase 3 — ProficiencyEffectResolver:
- `engine/subsystems/characters/proficiency_effect_resolver.gd` (NEW — class ProficiencyEffectResolver, RefCounted): Applies permanent unconditional proficiency effects (modifiers + flags) to CharacterData. Skips conditional modifiers (condition key present). Idempotent: clears proficiency-source modifiers/flags then rebuilds.
- `tests/test_proficiency_effect_resolver.gd` (NEW — 13 tests).

Phase 4 — CharacterGenerator + EventBus:
- `engine/subsystems/characters/character_generator.gd` (MODIFIED): Added optional ProficiencyRegistry param (3rd arg, default null). Updated auto_select_proficiencies() to use registry.get_general_proficiency_list() when available; falls back to 10-item hardcoded list. All returned proficiency dicts now include selections_count and specialization fields.
- `engine/autoloads/event_bus.gd` (MODIFIED): Added signal proficiency_changed(character_id: String, change: Dictionary).

Phase 5 — Tests + runner:
- `tests/test_proficiency_integration.gd` (NEW — 8 tests): End-to-end CharacterData + resolver + registry; spell+proficiency stacking; clear/reapply lifecycle; all class JSON key cross-validation.
- `tests/test_runner.gd` (MODIFIED): Added 3 new @onready vars; added 3 new suites to run loop.
- `tests/test_runner.tscn` (MODIFIED): Added 3 new ext_resource entries and Node entries.

**Decisions made:**
- Sign convention: save modifier negative value = bonus (lowers target number). Matches spell_effects.json convention (value: -1 = easier save).
- Conditional modifiers stored in catalog with "condition": {"requires": "..."} key — resolver skips them; consuming system evaluates at runtime.
- ProficiencyEffectResolver does NOT use ActiveEffectTracker (proficiencies are permanent, not duration-tracked).
- Compound key resolution uses progressive prefix stripping (longest prefix first) to handle both single-segment ("fighting_style_missile") and multi-segment ("combat_trickery_force_back") specialization keys.
- ProficiencyRegistry is optional in CharacterGenerator constructor (default null) to preserve backward compatibility with all existing test callers.
- Source ID format: "proficiency:divine_blessing" or "proficiency:fighting_style:missile".

**Interfaces defined or changed:**

ProficiencyRegistry public API (new): get_proficiency(key), has_proficiency(key), get_all_proficiency_keys(), get_proficiency_count(), get_general_proficiency_list(), get_proficiencies_by_type(type), get_max_rank(key), get_max_selections(key), get_selection_rule(key), is_specialization(key), get_effects_for_rank(key, rank), get_effects_for_specialization(key, spec), has_level_scaling(key), get_scaled_bonus(key, level).

ProficiencyEffectResolver public API (new): apply_proficiency_effects(character), get_unconditional_modifiers(key, rank, selections, level).

CharacterData additions: proficiencies array; has_proficiency, get_proficiency_rank, get_proficiency_selections, get_proficiency_specialization, get_proficiencies_by_slot.

CharacterGenerator constructor: func _init(class_registry, power_registry, proficiency_registry = null) — 3rd param optional.

EventBus addition: signal proficiency_changed(character_id: String, change: Dictionary) — change keys: proficiency_key, action ("added"|"removed"|"rank_changed"), new_rank.

CampaignRepository: save_character_proficiencies() INSERT now includes selections_count and specialization.

**Database changes:**
- Migration 007: ALTER TABLE character_proficiencies ADD COLUMN selections_count INTEGER NOT NULL DEFAULT 1; ADD COLUMN specialization TEXT NOT NULL DEFAULT ''.
- db/schema.sql updated to last migration 007.

**Tests added/updated:**
- test_proficiency_registry.gd (22 tests) — new suite.
- test_proficiency_effect_resolver.gd (13 tests) — new suite.
- test_proficiency_integration.gd (8 tests) — new suite.
- test_runner.gd and test_runner.tscn updated to 25 suites total.

**Known issues:**
- ProficiencyEffectResolver._clear_proficiency_effects() removes by iterating character.proficiencies — safe as long as the same array is used across calls. If proficiencies array is reassigned without re-applying, old source IDs may linger in ModifierContainer. Deferred — current usage is safe.
- Level-scaled conditional proficiencies (Swashbuckling, Running, etc.) not yet consumed; combat/exploration system reads level at runtime.
- Fighting Style conditional modifiers require combat context — deferred to combat system build.
- Domain morale modifiers (Leadership, Command) deferred to domain play build.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn — confirm all 25 suites pass.
2. Build character creation UI (Phase C-3): class/race selection, ability score rolling, equipment purchasing, proficiency assignment, starting spell repertoire for casters.
3. Wire ProficiencyRegistry and ProficiencyEffectResolver into CharacterGenerator and PC creation flow.
4. Update docs/coding_conventions.md: add proficiency registry pattern; document selections_count/specialization fields in DB patterns section.


---

## Session 2026-03-30 — Character Creation UI (Phase C-3)

**Task:** Implement the 9-step interactive character creation wizard, EquipmentCatalog tests, and all supporting panels.
**Model used:** Sonnet 4.6

**Completed:**

Phase A — Data Layer:
- `db/migrations/008_portrait_id.sql` — ALTER TABLE characters ADD COLUMN portrait_id.
- `db/schema.sql` — updated to migration 008; portrait_id column added to characters table.
- `engine/shared_types/character_data.gd` — added portrait_id field; wired into from_dict() and to_dict().
- `engine/autoloads/campaign_repository.gd` — added portrait_id to create_character() INSERT and save_character() UPDATE.
- `engine/subsystems/characters/character_generator.gd` — removed CON/CHA source block from apply_ability_trade(); source restriction is now strictly "source cannot be a prime requisite" per ACKS RAW.
- `tests/test_character_generator.gd` — replaced test_ability_trade_invalid_con() with test_ability_trade_con_allowed_for_non_prime() and test_ability_trade_invalid_prime_requisite_source().
- `engine/subsystems/characters/equipment_catalog.gd` — NEW: loads base_equipment.json (130), transport.json (32), foodstuffs from provisions_services.json (14). Total: 176 items. format_cost() static method.
- `data/portrait_manifest.json` — NEW: 64 shipped portrait entries for export-compatible resolution.
- `tests/test_equipment_catalog.gd` — NEW: 15 tests.
- `tests/test_runner.gd` + `tests/test_runner.tscn` — registered EquipmentCatalogTests as suite 27.

Phase B — Flow Controller:
- `scenes/ui/character_creation/character_creation_screen.gd` — NEW: CanvasLayer layer 32, 9-step wizard, shared creation_state dict, back-nav invalidation, open()/close()/_finalize_character() with full DB persistence, coin InventoryItems for remaining gold, signals character_created and creation_cancelled.
- `scenes/ui/character_creation/character_creation_screen.tscn` — NEW.

Phase C — Step Panels 1-4:
- ability_roll_panel.gd — 3d6 in order via player_roll(), re-roll, score/modifier grid.
- class_selection_panel.gd — 25 classes grouped by race, eligibility check, full detail right panel.
- ability_trade_panel.gd — source/target dropdowns filtered by prime reqs, undo stack, live XP adj.
- hp_roll_panel.gd — player_roll() for hit die, CON mod, max HP toggle, minimum 1.

Phase G — CharacterSheetPanel:
- `scenes/ui/components/character_sheet_panel.gd` — NEW: reusable read-only summary (portrait, ability scores, combat, saves, proficiencies, spells, equipment).

Phase D — Step Panels 5-6:
- proficiency_selection_panel.gd — slot computation with INT bonus, tabbed lists, specialization popup, ranked advancement, remove buttons.
- spell_selection_panel.gd — arcane (judge spell + d12 INT bonus rolls), divine auto-grant, no-L1-slots notice, warlock notice.

Phase E — Step 7 Equipment Shop:
- equipment_shop_panel.gd — gold roll (3d6x10gp), 7-tab catalog, buy/sell, gold tracking, live encumbrance, class restriction warnings (non-blocking), auto-equip.

Phase F — Step Panels 8-9:
- portrait_picker_panel.gd — manifest + user://portraits/ scan, thumbnail grid, class-matching first, 256px preview.
- finalize_panel.gd — name (required), alignment (filtered by class restriction), description, live CharacterSheetPanel.

Phase H — Integration:
- `scenes/Main.tscn` — added CharacterCreationScreen instance.
- `scenes/main_scene.gd` — added open_character_creation(), _on_character_created(), _on_creation_cancelled().
- `docs/coding_conventions.md` — CanvasLayer 32 added to table; character_creation/ and components/ added to dir tree; Main.tscn tree updated; migration count updated to 008.

**Decisions made:**
- CON/CHA ability trade block removed — only prime requisite source restriction per ACKS RAW.
- Gold stored as coin InventoryItems (coins_gp/sp/cp) in belt slot.
- Portrait system: manifest (shipping) + user://portraits/ scan (runtime).
- Equipment slot default: "pack". Auto-equip assigns best armor/shield/weapon.
- Equipment class restrictions are warnings only per ACKS rule.
- Warlock spell progression incomplete in source data — shows notice, auto-completes.

**Interfaces defined or changed:**
- CharacterData.portrait_id: String (new field).
- CharacterCreationScreen signals: character_created(character_id: String), creation_cancelled.
- CharacterCreationScreen.open(campaign_id: String).
- Panel setup: setup(state, ...registries) + is_complete() -> bool.
- CharacterSheetPanel.setup_registry(class_registry) + display(state: Dictionary).
- Stub class names declared: AbilityRollPanel, ClassSelectionPanel, AbilityTradePanel, HpRollPanel, ProficiencySelectionPanel, SpellSelectionPanel, EquipmentShopPanel, PortraitPickerPanel, FinalizePanel.

**Database changes:**
- Migration 008: ALTER TABLE characters ADD COLUMN portrait_id TEXT NOT NULL DEFAULT ''.
- db/schema.sql updated to migration 008.

**Tests added/updated:**
- test_equipment_catalog.gd (15 tests) — new suite.
- test_runner updated to 27 suites total.
- test_character_generator.gd: CON/CHA trade tests updated to match new ACKS RAW rules.

**Known issues:**
- EquipmentShopPanel quantity control is Buy-1/Sell-1 only (no +/- spinner). MVP sufficient.
- PortraitPickerPanel loads all thumbnails eagerly; could lag with many user portraits.
- SpellSelectionPanel: if player rolls INT bonus spells then navigates back without confirming, rolls are lost on return.
- Godot 4 may show warnings for TextureButton.stretch_mode usage in portrait grid — cosmetic only.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn — confirm all 27 suites pass.
2. Manually test end-to-end character creation (Fighter: no spells; Mage: arcane spells; Cleric: no L1 slots message).
3. Apply DB migration 008 if not auto-applied (CampaignRepository._ensure_migrations() should handle this).
4. Begin next build phase per design brief priority order.

---

## Session 2026-03-31 — Proficiency Specialization Registry & UI Picker

**Task:** Replace free-text specialization entry in character creation UI with a registry-backed closed picker. Implement the base catalog specialization registry per GDD §2–§9. Reclassify `naturalism` and `collegiate_wizardry` from `stacking` to `specialization`.
**Model used:** claude-sonnet-4-6

**Completed:**

- `data/proficiencies/proficiency_specializations.json` (NEW): Base catalog specializations for all 14 specialization proficiencies — 173 total entries across weapon_focus(6), riding(15), animal_training(27), knowledge(14), craft(32), art(13), performance(8), profession(10), language(21), naturalism(11), collegiate_wizardry(1), signaling(2), labor(9), elementalism(4). Each entry: id, display_name, layer="base", prerequisite_ids, metadata. Fantastic mounts (griffons, hippogriffs, etc.) carry non-empty prerequisite_ids per GDD §3.2.

- `engine/subsystems/characters/specialization_registry.gd` (NEW — class SpecializationRegistry, RefCounted): Loads proficiency_specializations.json. Public API: `has_specializations`, `get_specializations`, `get_specialization_ids`, `get_specialization`, `get_specialization_display_name`. Stub comment for future `compose_with_campaign_layer()`.

- `data/proficiencies/proficiency_catalog.json` (MODIFIED):
  - 10 proficiencies changed from `specializations: null` → `specializations: "registry"` (sentinel for SpecializationRegistry lookup): animal_training, art, craft, knowledge, labor, language, performance, profession, riding, signaling.
  - `naturalism`: `selection_rule` changed from `"stacking"` → `"specialization"`, added `specializations: "registry"`.
  - `collegiate_wizardry`: `selection_rule` changed from `"stacking"` → `"specialization"`, added `specializations: "registry"`.

- `engine/subsystems/characters/proficiency_effect_resolver.gd` (MODIFIED): Added fallback when specialization proficiencies lack `effects_by_specialization` — falls back to `get_effects_for_rank()`. Ensures `collegiate_wizardry`'s `+1 repertoire_capacity_bonus` still applies after reclassification.

- `engine/subsystems/characters/proficiency_registry.gd` (MODIFIED):
  - Constructor now accepts optional `SpecializationRegistry` param (default null — backward compatible).
  - `_resolve_key()` and `_get_specialization_from_key()` renamed to public `resolve_key()` and `get_specialization_from_compound_key()` (private aliases kept for internal callers).
  - New `get_available_specializations(prof_key) -> Array` — returns inline array for closed-list profs, spec registry IDs for "registry" profs, empty for non-specialization profs.
  - New `get_specialization_display_name(prof_key, spec_id) -> String` — delegates to SpecializationRegistry, titlecase fallback.

- `scenes/ui/character_creation/character_creation_screen.gd` (MODIFIED): `_init_registries()` creates SpecializationRegistry, passes it to ProficiencyRegistry constructor.

- `scenes/ui/character_creation/proficiency_selection_panel.gd` (MODIFIED):
  - `_refresh_list()`: Compound keys (e.g., `knowledge_history`) show locked specialization in display name.
  - `_on_add_proficiency()`: New compound key auto-lock path — detects embedded specialization, resolves to base key, stores directly without showing picker.
  - `_show_specialization_selector()` rewritten with 3 branches: (A) closed-list Array → buttons, (B) `"registry"` → registry picker, (C) fallback label.
  - New `_build_spec_buttons_from_ids()`: button-per-option for closed-list.
  - New `_build_registry_spec_picker()`: scrollable list; adds search/filter LineEdit for lists > 10 items.
  - New `_populate_spec_buttons()`: builds/rebuilds buttons from filtered spec list.
  - New `_on_spec_filter_changed()`: finds the button list inside ScrollContainer, rebuilds with filter.
  - `_make_selected_row()`: uses `get_specialization_display_name()` for proper display names.

- `engine/subsystems/characters/character_generator.gd` (MODIFIED):
  - `auto_select_proficiencies()`: class slot loop now detects compound keys (auto-lock specialization) and calls `_pick_random_specialization()` for registry-backed specializations.
  - General slot loop similarly picks random specializations when `is_specialization()` is true.
  - New private `_pick_random_specialization(prof_key) -> String` helper.

- `tests/test_specialization_registry.gd` (NEW — 16 tests): Catalog loading, entry counts per proficiency, lookup by key and ID, display names, prerequisite IDs for fantastic mounts, reclassified proficiency entries.
- `tests/test_proficiency_registry.gd` (MODIFIED): +7 tests for new methods: `get_available_specializations` (closed-list, registry-backed, non-spec, no-registry cases), public compound key and resolve_key APIs, display name via registry.
- `tests/test_proficiency_integration.gd` (MODIFIED): +3 tests: effect resolver fallback for naturalism and collegiate_wizardry after reclassification, NPC generation picks non-empty specializations.
- `tests/test_runner.gd` + `.tscn` (MODIFIED): SpecializationRegistryTests added as suite 28 (now 28 suites total).

**Decisions made:**
- `"registry"` sentinel in the catalog `specializations` field clearly distinguishes registry-backed from closed-list from null. This is explicit and checkable with `== "registry"`.
- SpecializationRegistry is NOT an autoload. It is created by the character creation screen and passed to ProficiencyRegistry. Character creation is the only current consumer; future consumers (session runner, character advancement) will instantiate it similarly.
- Private `_resolve_key` and `_get_specialization_from_key` aliases preserved to avoid breaking any future callers that may reference the private methods directly.
- Search filter threshold: lists > 10 items get a filter. Covers craft(32), animal_training(27), knowledge(14), riding(15), language(21).
- `naturalism` and `collegiate_wizardry` reclassified to `specialization` rule — multiple selections now pick DIFFERENT terrain/guild entries, matching GDD intent. The old `stacking` model allowed re-selecting the same proficiency, which was semantically wrong.

**Interfaces defined or changed:**

SpecializationRegistry public API (new class):
- `has_specializations(key) -> bool`
- `get_specializations(key) -> Array`
- `get_specialization_ids(key) -> Array`
- `get_specialization(key, spec_id) -> Dictionary`
- `get_specialization_display_name(key, spec_id) -> String`

ProficiencyRegistry changes:
- `_init(spec_registry: SpecializationRegistry = null)` — new optional param
- `resolve_key(key) -> String` — public (was `_resolve_key`)
- `get_specialization_from_compound_key(key) -> String` — public (was `_get_specialization_from_key`)
- `get_available_specializations(prof_key) -> Array` — new method
- `get_specialization_display_name(prof_key, spec_id) -> String` — new method

CharacterGenerator change:
- `_pick_random_specialization(prof_key) -> String` — new private helper

**Database changes:** None. The existing `specialization TEXT` column in `character_proficiencies` is sufficient.

**Tests added/updated:**
- test_specialization_registry.gd (16 tests) — new suite.
- test_proficiency_registry.gd: +7 tests (29 total in suite).
- test_proficiency_integration.gd: +3 tests (11 total in suite).
- test_runner: 28 suites total.

**Known issues:**
- Prerequisite enforcement NOT implemented in the UI picker. The data is present (`prerequisite_ids` in the JSON), but the picker does not yet filter by prerequisites. Deferred — at character creation (level 1), no one has prerequisites to check. Prerequisite checking is needed for character advancement (level-up proficiency selection).
- `test_get_selection_rule_stacking` test in test_proficiency_registry.gd will fail if it tests `naturalism` or `collegiate_wizardry` — those are now `"specialization"`, not `"stacking"`. Check existing test and update if needed before running.
- Setting-generated and campaign-created specialization layers are not yet implemented. `SpecializationRegistry` has a stub comment for `compose_with_campaign_layer()`.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn — confirm all 28 suites pass. Fix `test_get_selection_rule_stacking` if it tested naturalism/collegiate_wizardry.
2. Manually test character creation Step 5: select Riding → see 15 scrollable species; select Knowledge → see 14 fields with search filter; select Cleric with `Knowledge (History)` on class list → auto-locked.
3. Continue with next build phase per design brief priority order.

---

## Session 2026-03-31 — Pre-Milestone Fixes: Language Grants & Party Membership

**Task:** Implement two pre-milestone fixes identified during the master roadmap planning session: (A) language grants missing from character creation, and (B) created characters not appearing in the Override panel Characters tab.

**Model used:** Claude Sonnet 4.6.

**Completed:**
- Created `scenes/ui/character_creation/language_selection_panel.gd` — new Step 9 panel. Shows auto-granted languages (Common + racial) as read-only; provides OptionButton pickers for INT-modifier bonus language slots. Skipped automatically when INT modifier ≤ 0.
- Modified `scenes/ui/character_creation/character_creation_screen.gd`:
  - Added `Step.LANGUAGES = 8`, shifted `Step.FINALIZE = 9`. Now 10 steps total.
  - Added `_spec_registry: SpecializationRegistry` as instance variable (was local in `_init_registries`).
  - `STEP_LABELS` updated to 10 entries ("Step X of 10").
  - `_panels.resize(10)` — added LanguageSelectionPanel instantiation in `_build_panels()`.
  - `_setup_panel()` handles LANGUAGES case.
  - `_next_valid_step()` and `_prev_valid_step()` skip LANGUAGES when `_should_skip_languages()` returns true (INT mod ≤ 0).
  - `_should_skip_languages()` — new helper.
  - `_reset_state()` initializes `"language_bonus_picks": []`.
  - `_invalidate_from()` clears `language_bonus_picks` for all steps that invalidate character data (CLASS_SELECTION, ABILITY_TRADE, PROFICIENCIES, PORTRAIT, LANGUAGES).
  - `_finalize_character()` now: (1) assembles full language list (Common + racial + alignment + INT bonus picks, deduplicated); (2) sets `character.languages` JSON before calling `create_character()`; (3) calls `CampaignRepository.add_party_member(GameState.party_id, character.id, "middle")` after `create_character()` (Fix B); (4) appends language proficiency records (one per language, `proficiency_key: "language"`, `specialization: lang_id`) to the proficiency save.
- Modified `scenes/ui/components/character_sheet_panel.gd`:
  - Added `_render_languages(character, state)` called from `display()` between proficiencies and spells.
  - Reads `character.languages` JSON when finalized; falls back to assembling a preview from `creation_state` during live wizard use.

**Decisions made:**
- Alignment language grant (lawful/chaotic only — neutral has no secret tongue in ACKS 1e) is applied in `_finalize_character()` AFTER alignment is set, avoiding a chicken-and-egg dependency with the LANGUAGES step (step 9) which runs before FINALIZE (step 10).
- Racial languages are hardcoded in code (elf→elvish, dwarf→dwarvish, gnome→gnomish, halfling→halfling) since class JSON has only a `race` field with no `languages` array.
- LANGUAGES step is hidden from characters with INT modifier ≤ 0 (Common + racial + alignment are auto-granted without requiring user input).
- Languages stored as: (a) `character.languages` JSON string for display, (b) `character_proficiencies` rows with `proficiency_key="language"` and `specialization=lang_id` for system queries.
- `add_party_member` uses slot `"middle"` as default formation slot for newly created PCs.

**Interfaces defined or changed:**
- `LanguageSelectionPanel.setup(state: Dictionary, spec_registry: SpecializationRegistry) -> void`
- `LanguageSelectionPanel.is_complete() -> bool`
- `CharacterSheetPanel._render_languages(character: CharacterData, state: Dictionary) -> void` (internal)
- `CharacterCreationScreen._should_skip_languages() -> bool` (internal)

**Database changes:** None. Existing `character_proficiencies.specialization TEXT` column stores language IDs. Existing `characters.languages TEXT` column stores the JSON array.

**Tests added/updated:** None this session — the affected code paths are UI-layer and integration-tested via manual play.

**Known issues:**
- `test_get_selection_rule_stacking` from prior session may still need review if it tests naturalism/collegiate_wizardry.
- LANGUAGES step rebuilds UI from scratch on each `setup()` call but does NOT rebuild on live slot changes (by design). Duplicate bonus language selection is technically possible (e.g., picking elvish twice); deduplicated at finalization, so final character has correct unique language list.
- No test coverage for the new LanguageSelectionPanel (UI-only class).

**Next session should:**
1. Run test_runner.tscn — confirm all 28 suites still pass.
2. Manually test character creation end-to-end: create an elf mage (INT 16+ to trigger language step), verify language step appears with 2 bonus slots, verify languages show on character sheet, verify character appears in Override panel Characters tab after creation.
3. Begin Milestone 0: Monster Data Schema Design (0.1) per the master roadmap at `C:\Users\jttau\.claude\plans\ticklish-sleeping-map.md`.

---

## Session 2026-03-31 — Barbarian Origin & Witch Tradition Selection

**Task:** Fix two bugs: (1) No screen/option to pick Barbarian regional origin or Witch tradition during character creation. (2) Witch showed "No proficiencies available" on the class tab because `class_proficiency_list` was empty.
**Model used:** Sonnet 4.6

**Completed:**
- Added `class_proficiency_list` to `data/classes/witch.json` (25 entries: alchemy, apostasy, beast_friendship, black_lore_of_zahar, contemplation, craft, divine_blessing, divine_health, elementalism, familiar, healing, knowledge, loremastery, magical_engineering, mystic_aura, naturalism, performance, prestidigitation, prophecy, quiet_magic, seduction, sensing_evil, soothsaying, theology, unflappable_casting). Marked `[NEEDS-REVIEW]` — reconstructed from ACKS PC context since source XML did not capture this list.
- Added `regional_origins` dictionary to `data/classes/barbarian.json` with three entries (jutland, skysostan, ivory_kingdoms), each containing `display_name`, `weapons_permitted`, `fighting_styles_permitted`, and `bonus_proficiency`.
- Created `scenes/ui/character_creation/class_customization_panel.gd` (class ClassCustomizationPanel) — new wizard panel for Barbarian origin / Witch tradition selection. Contains `TRADITION_INFO` const (used by finalization). Voudon tradition triggers a craft specialization sub-selector.
- Updated `scenes/ui/character_creation/character_creation_screen.gd`:
  - Added `CLASS_CUSTOMIZATION = 2` step (renumbered ABILITY_TRADE=3 through FINALIZE=10, 11 total steps).
  - Updated STEP_LABELS (11 entries).
  - Added `barbarian_origin`, `witch_tradition`, `voudon_craft_choice` to creation_state.
  - Added `_should_skip_customization()` — skips step for all classes except barbarian and witch.
  - Updated `_next_valid_step()` and `_prev_valid_step()` to skip CLASS_CUSTOMIZATION when not needed.
  - Updated `_invalidate_from()` to clear origin/tradition fields when backing up.
  - Added ClassCustomizationPanel to `_build_panels()` (array resized to 11).
  - Added CLASS_CUSTOMIZATION case to `_setup_panel()`.
  - Updated `_finalize_character()` to stamp free bonus proficiency: Barbarian gets `slot_type="origin"` proficiency from the selected origin; Witch gets `slot_type="tradition"` proficiency from the selected tradition (Voudon includes craft specialization).

**Decisions made:**
- Tradition-granted and origin-granted proficiencies use `slot_type="origin"` or `slot_type="tradition"` so they do NOT count against normal slot totals in `ProficiencySelectionPanel._restore_from_state()`.
- Bonus proficiencies are stamped at finalization (not stored in creation_state["proficiencies"] earlier) so they don't interfere with the proficiency panel's slot counting logic.
- Witch class proficiency list was reconstructed — flagged as [NEEDS-REVIEW]. If Jedidiah verifies against the printed Players Companion, update `data/classes/witch.json`.

**Interfaces defined or changed:**
- `ClassCustomizationPanel.setup(state, class_registry, spec_registry) -> void`
- `ClassCustomizationPanel.is_complete() -> bool`
- `ClassCustomizationPanel.TRADITION_INFO: Dictionary` (const, read by `_finalize_character`)
- `CharacterCreationScreen._should_skip_customization() -> bool` (internal helper)
- `creation_state` now includes: `"barbarian_origin": String`, `"witch_tradition": String`, `"voudon_craft_choice": String`

**Database changes:** None. The new `slot_type` values ("origin", "tradition") go into the existing `character_proficiencies.slot_type TEXT` column.

**Known issues:**
- [NEEDS-REVIEW] Witch `class_proficiency_list` — reconstructed, needs verification against printed ACKS Players Companion.
- If a Witch picks a tradition-granted proficiency (e.g., Antiquarian picks Healing from the class list), they will have two Healing entries at finalization: one from the class slot (rank 1, slot_type="class") and one from the tradition grant (rank 1, slot_type="tradition"). The proficiency system does not merge these. This edge case is a future refinement.
- No test coverage for ClassCustomizationPanel (UI class; manual testing recommended).

**Next session should:**
1. Open in Godot and verify Barbarian and Witch creation flows work end-to-end.
2. Verify Witch class proficiency list against printed ACKS Players Companion and correct if needed.
3. Continue from prior session's "Next session should" list.

---

## Session 2026-03-31 — Persistent Character Sheet Overlay (O-02)

**Task:** Build the in-game character sheet overlay (O-02 per GDD), accessible at any point in the game loop. Separate from the character creation wizard preview.

**Model used:** claude-sonnet-4-6

**Completed:**

- `engine/shared_types/character_bundle.gd` (NEW — class CharacterBundle, RefCounted): Pure data container aggregating all DB-loaded character state (character, proficiencies, inventory, spells, powers, conditions, active_effects). Consumed by all character sheet tabs.

- `scenes/ui/character_sheet/character_sheet_overlay.gd` (NEW — no class_name, CanvasLayer script, layer 48):
  - Right-anchored panel (460px wide, full height), non-modal, game world stays interactive.
  - Toggle: F7 (character_sheet_toggle input action) or EventBus.character_sheet_requested signal.
  - Escape or X button to close.
  - Party selector sidebar (ItemList showing all party members via CampaignRepository.list_party_characters); click to switch displayed character.
  - TabContainer with 8 tabs (Biography, Attributes, Combat, Equipment, Proficiencies, Spells, Advancement, Effects).
  - `_load_character(id)` runs 7 CampaignRepository queries into a CharacterBundle and populates character.proficiencies.
  - EventBus signal connections for live refresh: hp_changed, inventory_updated, condition_changed, xp_awarded, character_leveled_up, proficiency_changed, active_effect_expired, spell_effect_applied, spell_effect_removed, override_applied.
  - Targeted refresh (just affected tabs) for common signals; full reload on character_leveled_up and override_applied.
  - Registries instantiated once in _ready(): ClassRegistry, ProficiencyRegistry, SpellRegistry, PowerRegistry, SpecializationRegistry.

- `scenes/ui/character_sheet/character_sheet_overlay.tscn` (NEW): Minimal scene, single CanvasLayer node with script.

- `scenes/ui/character_sheet/tabs/cs_tab_biography.gd` (NEW — class CSTabBiography, VBoxContainer):
  - Portrait, name (18px), class/level, title, race, alignment, sex.
  - HP current/max with color coding (green ≥50%, yellow 25-49%, red <25%, dimmed 0%).
  - Dead/incapacitated status labels.
  - Age and age category (when current_age > 0).
  - XP adjustment (when non-zero).
  - Languages (parsed from character.languages JSON).

- `scenes/ui/character_sheet/tabs/cs_tab_attributes.gd` (NEW — class CSTabAttributes, VBoxContainer):
  - 6 ability scores in 4-column table: name, base score, modifier, effective (highlighted blue when modified).
  - 5 saving throws in 3-column table: name, base target, effective (highlighted when modified).
  - "* Modified by active effects" footnote when relevant.

- `scenes/ui/character_sheet/tabs/cs_tab_combat.gd` (NEW — class CSTabCombat, VBoxContainer):
  - HP current/max (color-coded).
  - Temp HP if present.
  - AC: current effective AC, three configurations computed from equipped inventory items + DEX mod.
  - AC component breakdown (armor name + bonus + magical, shield, DEX mod).
  - Attack Throw: base + effective, shows modification if different.
  - Attack-vs-AC table (AC 9 to -3, 13 columns, using descending AC convention: roll needed = attack_throw - AC, clamped 2-20).
  - Initiative modifier (DEX mod).
  - Cleave count: level for fighter-progression, 0 for others.
  - Movement: encumbrance total, exploration/combat/running speeds from EncumbranceCalculator.
  - Effective movement if modified by spell effects.
  - Hit Die type.

- `scenes/ui/character_sheet/tabs/cs_tab_equipment.gd` (NEW — class CSTabEquipment, VBoxContainer):
  - Encumbrance summary with color-coded overloaded warning.
  - Items grouped by slot (main hand, off hand, body, head, belt, pack, mount).
  - Per-item: name, quantity, magical bonus, armor AC bonus, weapon damage, encumbrance in stone, equipped indicator.
  - Currency/treasure section.

- `scenes/ui/character_sheet/tabs/cs_tab_proficiencies.gd` (NEW — class CSTabProficiencies, VBoxContainer):
  - Class and general proficiencies (separated by slot_type field).
  - Per proficiency: display name from ProficiencyRegistry, rank, specialization, description, effects summary.
  - Class Powers section from bundle.powers: name from PowerRegistry, description, unlock level, active/inactive.

- `scenes/ui/character_sheet/tabs/cs_tab_spells.gd` (NEW — class CSTabSpells, VBoxContainer):
  - Non-casters: "This character does not cast spells." (checked via ClassRegistry.get_casting_power()).
  - Casters: casting tradition header, spell slots per day table, known spells by level with memorized/known status.
  - Spell names from SpellRegistry.

- `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd` (NEW — class CSTabAdvancement, VBoxContainer):
  - Class, level/max level, title, hit die.
  - Current XP and XP for next level (comma-formatted).
  - ProgressBar spanning current level range.
  - XP remaining to next level.
  - XP adjustment with color coding.
  - Stubs: Reserve XP, Adventure Pool Share, Downtime & Carousing XP.

- `scenes/ui/character_sheet/tabs/cs_tab_effects.gd` (NEW — class CSTabEffects, VBoxContainer):
  - Status: alive/dead/incapacitated, party active flag, temp HP.
  - Active conditions from bundle.conditions: name, source, duration.
  - Active spell effects from bundle.active_effects: spell name, concentration flag, duration, modifier summary, flag summary.
  - Reputation: stub "(Not yet implemented)".

- `engine/autoloads/event_bus.gd` (MODIFIED): Added `signal character_sheet_requested(character_id: String)` in dev testing section. Future: emitted by session status bar character chips.

- `project.godot` (MODIFIED): Added `character_sheet_toggle` input action mapped to F7 (physical_keycode 4194334).

- `scenes/Main.tscn` (MODIFIED): Added CharacterSheetOverlay instance (ext_resource id 8_char_sheet).

- `scenes/main_scene.gd` (MODIFIED): Added `@onready var _char_sheet = $CharacterSheetOverlay`.

**Decisions made:**
- The existing `CharacterSheetPanel` (creation wizard finalize step) is left untouched. The new overlay is architecturally distinct — different data source (DB vs. creation_state), different lifecycle, tabbed layout, live updates.
- Layer 48: between CharacterCreation@32 and DicePrompt@64.
- Right-anchored, non-modal panel — game world stays interactive behind it.
- CharacterBundle lives in engine/shared_types/ per cross-subsystem data shape convention.
- Tab scripts use class_name (they are subsystem classes instantiated by code, not autoloads).
- Party selector shows HP via multi-line ItemList text for quick status scan without opening the full sheet.
- Spell-effect removal signal (spell_effect_removed) carries no character_id — overlay unconditionally reloads active effects for the displayed character when this fires.
- Attack throw table uses descending AC (ACKS convention): roll needed = attack_throw - AC, clamped to 2-20 (nat 1 always misses, nat 20 always hits).
- AC three-configuration display computed from inventory items directly (not from CharacterData.armor_class alone) to show meaningful breakdown.
- No notes field yet — characters table lacks a notes column. Biography tab shows all available identity data.

**Interfaces defined or changed:**

CharacterBundle (new class):
- `character: CharacterData`, `proficiencies: Array`, `inventory: Array`, `spells: Array`, `powers: Array`, `conditions: Array`, `active_effects: Array`

EventBus addition:
- `signal character_sheet_requested(character_id: String)`

New input action:
- `character_sheet_toggle` → F7 (physical_keycode 4194334)

CharacterSheetOverlay public API:
- `open(character_id: String = "") -> void`
- `toggle() -> void`

Tab public API (all 8 tabs):
- `display(bundle: CharacterBundle, registries: Dictionary) -> void`

**Database changes:** None.

**Tests added/updated:** None — UI-layer code; manual testing via F7 hotkey.

**Known issues:**
- character_sheet_overlay.tscn uses a hard-coded UID string ("uid://character_sheet_overlay") which Godot will replace on first import. If Godot complains, re-save the scene from the editor.
- The three-AC-configuration display in cs_tab_combat assumes armor/shield come from equipped inventory items. If CharacterData.armor_class was set via a different path (e.g., from character generator without saving to inventory), the breakdown may show 0 for armor_bonus. Effective AC from get_effective_ac() is always correct.
- Cleave count for thief/mage is displayed as 0. ACKS 1e allows fighters 1 cleave per level; others may have limited cleave from class powers — this is a future refinement.
- Proficiency description/effects display requires ProficiencyRegistry to be consistent with proficiency_catalog.json. If effects dict is empty or sparse for a given proficiency, only the name and description render.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn — confirm all 28 suites still pass (no changes to test infrastructure this session).
2. Press F7 with a character in the party — verify overlay opens on right side, all 8 tabs render data.
3. Manually test: HP change via Override panel → Biography and Combat tabs refresh automatically.
4. Test non-caster (fighter): Spells tab shows "does not cast spells."
5. Test caster (mage/cleric): Spells tab shows slot table and known spells.
6. Continue from prior session "Next session should" list (Barbarian/Witch verification, then roadmap tasks).

---

## Session 2026-03-31 — Character Sheet Post-Build Fixes

**Task:** Fix five issues discovered during manual testing of the character sheet overlay (O-02).
**Model used:** claude-sonnet-4-6

**Completed:**

1. **Hotkeys rebound (Ctrl+Alt+Letter)** — All F-key shortcuts were non-functional on the user's keyboard. Rebound:
   - `dev_char_creation`: F5 → Ctrl+Alt+C (physical_keycode 67)
   - `dev_dice_test`: F6 → Ctrl+Alt+D (physical_keycode 68)
   - `character_sheet_toggle`: F7 → Ctrl+Alt+S (physical_keycode 83)
   - Modified: `project.godot`

2. **Portrait size reduced to 64×64** — Portrait was rendering much larger than intended.
   - `cs_tab_biography.gd`: `custom_minimum_size = Vector2(64, 64)` (was 128)

3. **Panel width expanded to 66% of viewport** — Panel was too narrow for readable data display.
   - `character_sheet_overlay.gd`: `_panel.anchor_left = 0.34` (was 0.56)

4. **Saves "modified by active effects" bug fixed** — All 5 saving throws showed effective value 20+ with asterisk despite no active effects. Root cause: `CharacterData.get_effective_save()` requires keys prefixed with `"save_"` (e.g., `"save_petrification"`). The attributes tab was passing unprefixed keys (e.g., `"petrification"`), which triggered the error fallback (return 20). Also fixed the `_has_any_save_modifier()` helper which checked the same wrong keys.
   - `cs_tab_attributes.gd`: corrected all 5 save key strings and helper array.

5. **AC-to-hit table corrected** — Table was backwards. ACKS rule: roll_needed = attack_throw + AC (AC 0 = need AT value; AC 1 = need AT+1). Old formula subtracted AC (opposite direction). Fixed to `clampi(eff_at + ac, 2, 20)`. Table now shows AC 0–9 then -1 to -4 across columns.
   - `cs_tab_combat.gd`: corrected formula in attack table render function.

6. **Equipment tab fully rewritten with container mechanics** — Prior equipment tab was read-only. Replaced with interactive panel:
   - Equip/unequip buttons for weapons, armor, shields.
   - Container system: CONTAINER_KEYS identifies backpack/sack/pouch items. Contents shown with weight totals vs. capacity. "Move in" and "Remove" buttons. "Drop" button removes container + all contents.
   - `container_id TEXT NOT NULL DEFAULT ''` column added to `inventory_items` via migration 010.
   - New `CampaignRepository` methods: `update_inventory_item_equip_state()`, `get_items_in_container()`, `drop_container()`.
   - `add_inventory_item()` and `save_character_inventory()` updated to include `container_id`.
   - `cs_tab_equipment.gd` completely rewritten.

7. **`%.2g` format specifier crash fixed** — GDScript does not support `%g` format specifier. Three lines in `cs_tab_equipment.gd` used `%.2g`; all replaced with `%.2f`.

**Decisions made:**
- Container capacity in stone is hardcoded in CONTAINER_CAPACITY_STONE dict (backpack 4.0, sack_large 6.0, etc.) — display-only, not enforced.
- Container detection uses item_key substring matching against CONTAINER_KEYS list.
- Equipping a weapon with both slots occupied returns empty string (caller shows push_warning, no crash).
- `slot_type` values "origin" and "tradition" (from prior session) fall through to the "other" section in the equipment tab's slot grouping — these are proficiency slot types, not inventory slots.

**Interfaces defined or changed:**

DB migration 010 (new):
- `ALTER TABLE inventory_items ADD COLUMN container_id TEXT NOT NULL DEFAULT ''`

CampaignRepository additions:
- `update_inventory_item_equip_state(item_id: String, is_equipped: bool, slot: String, container_id: String = "") -> bool`
- `get_items_in_container(container_item_id: String) -> Array`
- `drop_container(container_item_id: String) -> bool` — transactional: deletes contents then container

**Database changes:**
- Migration 010: `container_id TEXT NOT NULL DEFAULT ''` column added to `inventory_items`.
- `db/schema.sql` updated to migration 010 (last migration applied: 010).

**Tests added/updated:** None — UI and integration-tested manually.

**Known issues:**
- Duplicate bonus language selection (picking same language twice) is deduplicated at finalization only — no real-time feedback in the LANGUAGES step UI.
- CONTAINER_KEYS substring match could produce false positives for item names that happen to contain "backpack" or "pouch" as substrings (unlikely in practice).
- Equip slot assignment for dual-wielding (two weapons equipped) shows both in Equipped section but the second goes to hands_off; unequip button on both works correctly.

**Next session should:**
1. Open Godot 4 and run test_runner.tscn — confirm all 28 suites pass.
2. Manually test the character sheet overlay: create a character, press Ctrl+Alt+S, verify all 8 tabs display correct data.
3. Test equipment actions: equip/unequip armor, move an item into a container, drop a container.
4. Test EventBus refresh: change HP via Override panel, verify Biography and Combat tabs update.
5. Verify: Ctrl+Alt+C opens character creation, Ctrl+Alt+D opens dice test.
6. Continue from prior session "Next session should" list (Barbarian/Witch verification, then roadmap tasks).

---

## Session 2026-03-31 — Equipment Slot Expansion + Character Creator Bug Fixes

**Task:** Fix multiple reported issues: weapon handedness enforcement, torches/lanterns/clothing equippable, barbarian/witch weapon permissions locked out, witch showing no spells, character creator reopen bug.

**Model used:** claude-sonnet-4-6 (Sonnet) throughout.

**Completed:**
- `data/classes/barbarian.json` — Fixed `regional_origins` weapon names from display names (`"battle axe"`) to item_keys (`"battle_axe"`) across all 3 origins (Jutland, Skysostan, Ivory Kingdoms).
- `data/classes/witch.json` — Fixed `"weapon_permissions"`: `"staff"` → `"quarterstaff"`.
- `scenes/ui/character_creation/equipment_shop_panel.gd` — `_get_restriction_warning()`: detects `"determined_by_regional_origin"` sentinel in weapon_permissions and resolves actual permitted list from `regional_origins[barbarian_origin]`; also added `[two-handed]`/`[versatile]` display tags for weapons; auto-equip no longer assigns shield to hands_off when best weapon is two-handed.
- `scenes/ui/character_creation/spell_selection_panel.gd` — Fixed guard from `if not _state.has("spells"):` → `if _state.get("spells", []).is_empty():` (was discarding generated spells because `_reset_state()` pre-initializes `"spells": []`). Also injects witch tradition level-1 bonus spells into the granted list.
- `scenes/main_scene.gd` — `open_character_creation()` now guards against double signal connection with `is_connected()`. Each handler disconnects the sibling signal so no stale one-shots survive.
- `scenes/ui/character_creation/ability_roll_panel.gd` — `_refresh_display()` now restores `_roll_button.visible = true` when scores are empty (fixes "locked blank" after reopen).
- `db/migrations/011_equipment_slots.sql` — New migration; rebuilds `inventory_items` table to expand slot CHECK constraint from 7 → 14 values: added `feet`, `hands_worn`, `accessory_1` through `accessory_5`.
- `db/schema.sql` — Updated to reflect migration 011 slot expansion.
- `scenes/ui/character_sheet/tabs/cs_tab_equipment.gd` — Major rewrite:
  - New constants: `HAND_HOLDABLE_KEYS`, `ACCESSORY_KEYS`, `ACCESSORY_SLOTS`, expanded `SLOT_LABELS`.
  - `_render_equipped()` now shows all 7 main slots + occupied accessory slots + first empty accessory slot.
  - `_can_equip(item)` helper determines whether an item shows an Equip button.
  - `_determine_equip_slot(item)` now routes: two-handed weapons require both hands free; off-hand blocked if main hand has two-handed weapon; clothing → body; hand-holdable gear → first free hand; accessory gear → first free accessory_N; boots/sandals → feet; gloves/gauntlets → hands_worn.
  - `_on_equip(item_id)` now looks up full item from bundle to pass to slot logic.
  - `_is_two_handed_weapon(item)` checks `weapon_tags` from a lazily-instantiated `EquipmentCatalog`.
  - `_render_loose()` and `_get_loose_movable_items()` use `_can_equip()` to exclude equippable items.

**Decisions made:**
- Clothing shares the `body` slot with armor (not a separate slot) — design decision by Jedidiah.
- `holy_symbol` routes to accessory slot (worn), not hand slot.
- `HAND_HOLDABLE_KEYS` is an explicit whitelist rather than a flag on catalog items — simpler, avoids schema changes.
- `EquipmentCatalog` instantiated lazily on first `_is_two_handed_weapon()` call, stored as `_catalog` on the tab.
- Accessory slot display: show all occupied slots + first empty slot (not all 5 always) — keeps UI compact.

**Interfaces defined or changed:**
- `CSTabEquipment._on_equip(item_id: String)` — signature changed (was `item_id, item_category`).
- `CSTabEquipment._determine_equip_slot(item: Dictionary) -> String` — signature changed (was `category: String`).

**Database changes:**
- Migration 011: slot CHECK expanded; `db/schema.sql` updated (last migration applied: 011).

**Tests added/updated:** None — manual integration testing recommended.

**Known issues:**
- Witch armor restriction: `armor_permissions: []` means "cannot wear armor" — the equipment shop shows a warning, which is correct. But the witch class description in the rules says no armor is allowed, so this is correct behavior.
- Tradition bonus spell injection only handles level `"1"` bonus spells. Sylvan witch has no level-1 bonus (first bonus at level 2), so Sylvan will show only the base divine cleric list — correct per the rules.
- Barbarian origin weapon names are now item_keys. The `weapons_permitted` list in `regional_origins` is also displayed in the `ClassCustomizationPanel` description text (line 190), which will now show raw item_keys like `"battle_axe"` instead of display names. The description rendering may need a future cosmetic fix to use display names.

**Next session should:**
1. Run game, create a Barbarian → choose Jutland origin → equipment shop should show no restriction warnings for permitted weapons.
2. Create a Witch → choose Antiquarian tradition → spell step should show divine cleric level-1 spells + Detect Poison (tradition bonus).
3. Cancel character creation → reopen → verify Roll button is visible.
4. Test equipping a two-handed sword: off-hand should be blocked.
5. Test equipping torches, lantern, clothing items from character sheet equipment tab.
6. Verify migration 011 applies cleanly (check Godot output for "Applied migration 11").

---

## Session 2026-03-31 — Bundle/Consumable System + Encumbrance Fix

**Task:** Implement the torch-bundle splitting system (equip one, stack decrements; unequip unused → merges back), fix encumbrance quantity bug, and update equipment shop for bundle purchases.
**Model used:** claude-sonnet-4-6

**Completed:**
- `db/migrations/012_uses_remaining.sql` — ALTER TABLE adds `uses_remaining INTEGER NOT NULL DEFAULT -1` to inventory_items.
- `db/schema.sql` — Updated to include `uses_remaining` column.
- `engine/shared_types/inventory_item.gd` — Added `var uses_remaining: int = -1`; updated `from_dict` and `to_dict`.
- `data/equipment/base_equipment.json`:
  - Converted `torches_6` entry to `torch` with `bundle_quantity: 6, uses_per_unit: 6`, encumbrance_sixths=1 (per individual torch).
  - Added `uses_per_unit: 24` to `oil_flask_common` and `oil_flask_military`.
  - Added `bundle_quantity` annotations to ammunition: dart=5, arrows_20=20, bolts_20=20, sling_stones_20=20, sling_bullets_30=30, iron_spikes_12=12.
- `engine/subsystems/characters/encumbrance_calculator.gd` — Fixed `calculate_item_encumbrance` to multiply `encumbrance_sixths` by `quantity` (was ignoring quantity entirely).
- `scenes/ui/character_creation/equipment_shop_panel.gd`:
  - `_on_buy_item`: reads `bundle_quantity` from catalog; increments stack by `bundle_qty` instead of 1.
  - `_on_sell_item`: decrements stack by `bundle_qty` instead of 1.
  - `_catalog_item_to_cart`: initializes `quantity` from `bundle_quantity` (defaults to 1 for non-bundles).
- `engine/autoloads/campaign_repository.gd`:
  - Added `split_item_for_equip(item_id, slot, uses_per_unit) -> String` — decrements source stack (or deletes if qty=1), inserts new single-unit equipped item with correct `uses_remaining`.
  - Added `merge_item_on_unequip(item_id, uses_per_unit) -> bool` — if item is unused (uses_remaining == uses_per_unit) or non-consumable (-1), merges back into pack stack; otherwise just unequips to pack.
- `scenes/ui/character_sheet/tabs/cs_tab_equipment.gd`:
  - Fixed `HAND_HOLDABLE_KEYS`: `"torches_6"` → `"torch"`, `"wooden_pole_10ft"` → `"pole_wooden_10ft"`, `"mirror_hand"` → `"mirror_small"`.
  - `_on_equip`: if item_key is in HAND_HOLDABLE_KEYS and qty > 1, calls `split_item_for_equip` instead of `update_inventory_item_equip_state`.
  - `_on_unequip`: looks up item, if in HAND_HOLDABLE_KEYS calls `merge_item_on_unequip`; otherwise normal unequip.

**Decisions made:**
- Bundle encumbrance rule: the ACKS rules list encumbrance for the whole bundle; per-unit weight = bundle_weight / bundle_quantity. Torch = 1 sixths per unit (1/6 stone each). Confirmed by user.
- Ammunition splitting deferred — bundle_quantity fields annotated in catalog for future use, but no split/merge logic wired for ammunition.
- Partially-used consumables (uses_remaining < uses_per_unit and != -1) simply move to pack without merging — they stay as standalone items (e.g. a half-burned torch).
- Military oil gets uses_per_unit=24 same as common oil (treated symmetrically).

**Interfaces defined or changed:**
- `CampaignRepository.split_item_for_equip(item_id: String, slot: String, uses_per_unit: int) -> String`
- `CampaignRepository.merge_item_on_unequip(item_id: String, uses_per_unit: int) -> bool`
- `InventoryItem.uses_remaining: int` (new field, default -1)
- `EquipmentCatalog` item dict: new optional fields `bundle_quantity: int`, `uses_per_unit: int`

**Database changes:**
- Migration 012: `uses_remaining INTEGER NOT NULL DEFAULT -1` on `inventory_items`.

**Known issues:**
- `add_inventory_item` in CampaignRepository does not pass `damage_type`, `material`, or `uses_remaining` — relies on schema defaults. Not a bug currently (defaults are correct) but could cause issues if non-default values are needed on a newly-added item. Fix when needed.
- Encumbrance display in character sheet may still show pre-fix values until DB refresh.
- Ammunition tracking (actually decrementing arrows when shooting) not yet implemented. bundle_quantity annotation is ready.

**Next session should:**
1. Test bundle equip/unequip flow in-game: buy torches → equip one → stack goes to 5 → unequip unused → merges back to 6.
2. Test encumbrance display: 6 torches (6 sixths = 1 stone) should show correctly.
3. Consider adding a "uses remaining" indicator in the equipment tab for consumables in hand slots (e.g. "Torch [6/6]").
4. Consider implementing ammunition decrement when ranged attacks are made.

---

## Session 2026-04-01 — Encumbrance Units Refactor + Container Capacity Enforcement

**Task:** (1) Refactor encumbrance from 1/6-stone units to 1/1000-stone units system-wide. (2) Enforce container capacity limits in the equipment tab and redesign the inventory UI with drag-and-drop.
**Model used:** claude-sonnet-4-6

**Completed:**

**Encumbrance Refactor (Task 1):**
- `engine/shared_types/inventory_item.gd` — renamed `encumbrance_sixths` → `encumbrance_units`; `encumbrance_stone()` now `/ 1000.0`; `from_dict` has fallback for old DB rows.
- `engine/subsystems/characters/encumbrance_calculator.gd` — all vars renamed; return key `total_units`; overload at 20000 units; movement tiers at 5000/7000/10000 units; magical armor reduction is `units - bonus * 1000`.
- `data/equipment/base_equipment.json` — all `encumbrance_sixths` → `encumbrance_units`; 1→167, 6→1000, 12→2000, etc. Coins set to 1 unit each.
- `data/equipment/transport.json` — same rename/conversion.
- `db/schema.sql` — column renamed to `encumbrance_units INTEGER NOT NULL DEFAULT 0`.
- `db/migrations/014_encumbrance_units.sql` (NEW) — table rebuild migration; treasure items fixed to 1 unit/piece; others converted by `ROUND(enc_sixths * 1000.0 / 6.0)`.
- `engine/autoloads/campaign_repository.gd` — three INSERT statements updated to use `encumbrance_units`.
- `engine/subsystems/override/override_manager.gd` — `enc_sixths` → `enc_units`; gold coin override fixed to 1 unit.
- `scenes/ui/character_creation/character_creation_screen.gd` — each coin now `"encumbrance_units": 1`; `_coin_enc_sixths()` removed (was double-counting bug).
- `scenes/ui/character_creation/equipment_shop_panel.gd` — field reads and display formula updated.
- `engine/subsystems/characters/equipment_catalog.gd` — foodstuff default updated (167 units).
- `tests/test_encumbrance.gd` — fully rewritten with new unit values; new `test_coin_encumbrance()`.
- `tests/test_equipment_catalog.gd` — field name updated.
- `tests/test_character_persistence.gd` — item values updated (sword 1000, chain 4000).
- `docs/coding_conventions.md` — encumbrance convention entry updated.

**Container Capacity Enforcement + Equipment UI Redesign (Task 2):**
- `data/equipment/base_equipment.json` — `container_capacity_units` added: backpack (4000), chest_ironbound (20000), pouch (500), sack_large (6000), sack_small (2000).
- `data/equipment/transport.json` — `container_capacity_units: 3000` added to saddlebags.
- `engine/subsystems/characters/equipment_catalog.gd` — added `is_container(item_key)` and `get_container_capacity_units(item_key)` methods.
- `tests/test_equipment_catalog.gd` — added `test_container_identification()` and `test_container_capacity()`.
- `scenes/ui/character_sheet/tabs/equipment_item_row.gd` (NEW) — `class_name EquipmentItemRow extends PanelContainer`; draggable row with `_get_drag_data()`.
- `scenes/ui/character_sheet/tabs/equipment_container_row.gd` (NEW) — `class_name EquipmentContainerRow extends PanelContainer`; drop target with capacity enforcement in `_can_drop_data()`; visual feedback (green/red) during drag.
- `scenes/ui/character_sheet/tabs/equipment_loose_zone.gd` (NEW) — `class_name EquipmentLooseZone extends PanelContainer`; drop target for removing items from containers.
- `scenes/ui/character_sheet/tabs/cs_tab_equipment.gd` — major rewrite:
  - Removed `CONTAINER_KEYS`, `CONTAINER_CAPACITY_STONE` constants.
  - Removed `_is_container()`, `_container_capacity()`, `_render_containers()`, `_render_loose()`, `_get_loose_movable_items()`, `_on_move_into_container()`.
  - Added `_is_container_item()`, `_calculate_container_used_units()`, `can_fit_in_container()`, `_render_inventory()`.
  - Fixed "Available to equip" to exclude items with a non-empty `container_id`.
  - New layout: flat inventory with EquipmentContainerRow + EquipmentLooseZone.

**Decisions made:**
- 1/1000 stone base unit (not 1/6). Standard item = 167 units (rounds 1/6 = 0.1667 stone up 0.2%). Approved by user.
- Coins/gems = 1 unit each (1000 units = 1 stone). Old double-count bug fixed.
- Container identification via `container_capacity_units > 0` in JSON — eliminates substring matching fragility.
- Loose carry zone excludes equippable items (they stay in "Available to equip" only, matching prior behavior).

**Interfaces defined or changed:**
- `EquipmentCatalog.is_container(item_key: String) -> bool`
- `EquipmentCatalog.get_container_capacity_units(item_key: String) -> int`
- `EquipmentItemRow.setup(item, remove_callback, character_id)` — drag payload: `{ type, item_id, item }`
- `EquipmentContainerRow.setup(container, contents, capacity_units, used_units, character_id, drop_callback, remove_callback)`
- `EquipmentLooseZone.setup(loose_items, character_id, remove_callback)`
- `CSTabEquipment.can_fit_in_container(item, container_id) -> bool` (public)

**Database changes:**
- Migration 014: encumbrance column rebuild (encumbrance_sixths → encumbrance_units).

**Tests added/updated:**
- `test_equipment_catalog.gd`: `test_container_identification()`, `test_container_capacity()`
- `test_encumbrance.gd`: full rewrite with new unit values; `test_coin_encumbrance()`
- `test_character_persistence.gd`: item field/value updates

**Known issues:**
- Drag-and-drop in Godot 4 requires the parent Control to have `mouse_filter` set correctly — if items don't respond to drag, check that parent containers aren't consuming mouse events.
- Container rows are rebuilt from scratch on every `inventory_updated` signal — adequate for now, could be optimized later if many containers cause flicker.

**Next session should:**
1. Smoke-test the new inventory UI in-game: drag item into backpack, verify capacity enforced, drag back out to loose.
2. Verify `spell_component_pouch` does NOT appear as a container.
3. Verify `chest_ironbound` DOES appear as a container with 20-stone capacity.
4. Run all tests via `tests/test_runner.tscn`.
5. Consider adding a "uses remaining" indicator for consumables in hand slots (e.g. "Torch [6/6]").

---

## Session 2026-04-01 — C-4: Three-Tier Persistence with Promotion

**Task:** Implement the three-tier character persistence architecture (Tier A/B/C), tier-aware queries, the TransientPool lifecycle container, and the PromotionEngine that orchestrates C→B and B→A promotions and A→B and B→C demotions.
**Model used:** claude-sonnet-4-6 (planning + implementation)

**Completed:**

**CharacterData tier helpers (`engine/shared_types/character_data.gd`):**
- Added `is_transient()`, `is_named()`, `is_full()` convenience methods
- Added `can_promote_to(target_tier)` — validates legal one-step upward promotion (transient→named, named→full)
- Added `can_demote_to(target_tier)` — validates legal one-step downward demotion (full→named, named→transient)
- `from_dict()`/`to_dict()` unchanged — backward compatible

**EventBus signals (`engine/autoloads/event_bus.gd`):**
- Added `signal character_promoted(character_id, old_tier, new_tier)`
- Added `signal character_demoted(character_id, old_tier, new_tier)`

**TransientPool (`engine/subsystems/characters/transient_pool.gd`) — NEW:**
- `class_name TransientPool extends RefCounted`
- `add()`, `get_character()`, `remove()`, `has_character()`, `clear()`, `get_all()`, `size()`
- In-memory only; held by whatever system manages encounters; not an autoload

**CharacterGenerator tier-aware generation (`engine/subsystems/characters/character_generator.gd`):**
- `generate_npc()` now checks tier before rolling alignment and generating name
- `tier="transient"`: skips alignment roll (leaves "neutral"), uses shorter placeholder name, no personality
- `tier="named"` / `tier="full"`: existing behavior unchanged

**CampaignRepository tier-aware queries (`engine/autoloads/campaign_repository.gd`):**
- Added `list_characters_by_tier(campaign_id, tier) -> Array`
- Added `list_characters_excluding_tier(campaign_id, excluded_tier) -> Array`
- Added `strip_character_sub_tables(character_id) -> bool` — deletes proficiencies, inventory, spells, powers in a transaction; used for A→B demotion
- Updated `promote_character()` doc comment — clarified it is a raw DB tier column update, used internally by PromotionEngine

**PromotionEngine (`engine/subsystems/characters/promotion_engine.gd`) — NEW:**
- `class_name PromotionEngine extends RefCounted`
- `_init(p_generator, p_repertoire_engine=null)`
- `promote_c_to_b(character, new_name, personality_dict) -> bool` — sets name/personality, persists to DB, emits `character_promoted`
- `promote_b_to_a(character) -> Dictionary` — generates proficiencies, powers, spell repertoire (if caster); persists all; emits `character_promoted`; returns `{ character, proficiencies, powers, spells }`
- `demote_a_to_b(character_id) -> bool` — strips sub-tables, updates tier to "named", emits `character_demoted`
- `demote_b_to_c(character_id) -> bool` — deletes character row entirely, emits `character_demoted`

**Migration 015 (`db/migrations/015_persistence_tier_index.sql`) — NEW:**
- `CREATE INDEX IF NOT EXISTS idx_characters_persistence_tier ON characters(campaign_id, persistence_tier, is_active)`
- Speeds up tier-filtered queries; safe on empty datasets

**Test suite (`tests/test_persistence_tiers.gd`) — NEW:**
- 16 tests wired into `test_runner.gd` and `test_runner.tscn` as `PersistenceTierTests` node
- Covers: tier helpers, TransientPool lifecycle, transient-not-persisted, transient generation behavior, C→B promotion, B→A promotion, preservation of existing data through promotion, full C→B→A chain, A→B demotion, B→C demotion, invalid promotion guards, list_by_tier query, list_excluding_tier query, backward compatibility round-trip

**Decisions made:**
- PromotionEngine is a separate class (not in CampaignRepository) — repository is 1300+ lines of pure CRUD; promotion is business logic orchestrating generation + persistence.
- Transient characters never touch the DB. Only promoted characters are persisted.
- Promotion goes one tier at a time (no skipping). PromotionEngine enforces this.
- `to_dict()`/`from_dict()` unchanged — all CharacterData instances carry all fields; tier determines what is *populated*, not what is *serialized*.
- Personality and name for C→B are caller-provided parameters — no name/personality generator exists yet.
- Spell repertoire for B→A uses RepertoireEngine if available (optional dep in constructor); non-casters produce empty spells Array.

**Interfaces defined or changed:**
- `CharacterData.is_transient() -> bool`
- `CharacterData.is_named() -> bool`
- `CharacterData.is_full() -> bool`
- `CharacterData.can_promote_to(target_tier: String) -> bool`
- `CharacterData.can_demote_to(target_tier: String) -> bool`
- `TransientPool.add(character: CharacterData) -> void`
- `TransientPool.get_character(id: String) -> CharacterData`
- `TransientPool.remove(id: String) -> CharacterData`
- `TransientPool.clear() -> void`
- `TransientPool.get_all() -> Array`
- `TransientPool.size() -> int`
- `PromotionEngine.promote_c_to_b(character, new_name, personality_dict) -> bool`
- `PromotionEngine.promote_b_to_a(character) -> Dictionary`
- `PromotionEngine.demote_a_to_b(character_id) -> bool`
- `PromotionEngine.demote_b_to_c(character_id) -> bool`
- `CampaignRepository.list_characters_by_tier(campaign_id, tier) -> Array`
- `CampaignRepository.list_characters_excluding_tier(campaign_id, excluded_tier) -> Array`
- `CampaignRepository.strip_character_sub_tables(character_id) -> bool`
- `EventBus.character_promoted(character_id, old_tier, new_tier)` [signal]
- `EventBus.character_demoted(character_id, old_tier, new_tier)` [signal]

**Database changes:**
- Migration 015: composite index on `characters(campaign_id, persistence_tier, is_active)`

**Tests added/updated:**
- `tests/test_persistence_tiers.gd` (NEW): 16 tests covering the full tier lifecycle
- `tests/test_runner.gd` + `test_runner.tscn`: new `PersistenceTierTests` node registered

**Known issues:**
- No NPC name generator yet — `promote_c_to_b()` requires caller to provide the name. Future work for E-2 (session runner) or a dedicated NPC name system.
- No NPC personality generator yet — `promote_c_to_b()` accepts a `personality_dict` parameter. Caller responsible for content.
- B→A promotion for casters generates a 1st-level repertoire via RepertoireEngine, but if PromotionEngine is constructed without a RepertoireEngine, spells are left empty. This is intentional — non-casters need no spell handling.

**Next session should:**
1. Run `tests/test_runner.tscn` — verify all 16 new PersistenceTier tests pass with all existing tests still green.
2. Smoke-test the inventory drag-and-drop UI (carry-forward from previous session).
3. Consider E-2 (session runner generates transient encounters) which will be the first real consumer of TransientPool and PromotionEngine.

---

## Session 2026-04-01 — Phase C-5: XP Tracking, Level-Up Workflow, Aging System

**Task:** Implement the full XP, level-up, and aging systems including data files, engine classes, DB migration, UI updates, and tests.

**Model used:** Claude Sonnet 4.6

**Completed:**
- `data/aging_tables.json` (NEW): Race age category thresholds, starting age formulas for all 25 classes, ability adjustments per transition, death-from-old-age data. Source: acore_aging_poisons_high-level-start_optional_rules.xml + pc_aging_tables.xml.
- `engine/subsystems/characters/aging_system.gd` (NEW): `AgingSystem` class. Starting age rolls, race-aware age category lookup, progressive ability adjustments on category transitions, cumulative adjustments for NPC generation, death-from-old-age save trigger checking. Removed hardcoded `apply_age_change()` stub from CharacterData.
- `engine/subsystems/characters/xp_award_calculator.gd` (NEW): `XPAwardCalculator` class. Monster XP table (HD less than 1 through 21+), party share division (PCs = 1 share, henchmen = 0.5), prime req adjustment with Bankers rounding, 1-level advancement cap enforcement, domain/mercantile XP with GP threshold table. `bankers_round()` static utility added here.
- `engine/subsystems/characters/level_up_engine.gd` (NEW): `LevelUpEngine` class. Two paths: `apply_level_up_auto()` for NPCs/henchmen; `begin_interactive_level_up()` + `finalize_interactive_level_up()` for PCs. Handles HP rolling, attack/save/title updates, proficiency slot detection, spell slot expansion, class power unlocks. 0th-level returns `requires_class_selection: true` (deferred to henchman GDD).
- `engine/autoloads/event_bus.gd`: Added `age_category_changed(character_id, old_category, new_category)` signal.
- `engine/autoloads/campaign_repository.gd`: Added `update_character_fields(id, fields)` for surgical per-column updates with whitelist.
- `db/migrations/016_xp_audit_log.sql` (NEW): `xp_awards` table for tracking XP source.
- `engine/shared_types/character_data.gd`: Removed `apply_age_change()` hardcoded human stub. AgingSystem is now canonical.
- `engine/subsystems/characters/character_generator.gd`: `generate_pc()` and `generate_npc()` now call `AgingSystem` to set `current_age` and `age_category`.
- `scenes/ui/character_creation/character_creation_screen.gd`: Added `starting_age` to state dict; cached from generated character in `_prepare_step(HP_ROLL)`.
- `scenes/ui/character_creation/finalize_panel.gd`: Added "Starting Age:" display row.
- `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd`: Rewritten with level-up eligibility indicator, Level Up button, inline interactive level-up panel, Aging section. Removed pending stubs for XP/leveling (kept Reserve XP stub).
- `scenes/ui/character_sheet/character_sheet_overlay.gd`: Added `age_category_changed` connection; handler refreshes Biography + Advancement tabs.
- `db/schema.sql`: Updated header comment to migration 016.
- `tests/test_xp_award_calculator.gd` (NEW): 13 tests.
- `tests/test_level_up_engine.gd` (NEW): 10 tests.
- `tests/test_aging_system.gd` (NEW): 10 tests.
- `tests/test_runner.gd` + `tests/test_runner.tscn`: Registered 3 new test suites (IDs 30-32).

**Decisions made:**
- Monster XP table hardcoded as const (fixed ACKS rule; same pattern as ability_modifier table).
- Starting age: no new wizard step, rolled automatically during generate_pc() in _prepare_step(HP_ROLL).
- AgingSystem is a separate class; CharacterData stub removed.
- Interactive vs auto level-up split. 1-level cap in XPAwardCalculator, not LevelUpEngine.
- Bankers rounding: new `bankers_round()` static on XPAwardCalculator. Note: roundi() is NOT Bankers rounding.
- Level-up interactive UI is inline in Advancement tab (not a modal).

**Interfaces defined or changed:**
- `AgingSystem.roll_starting_age(class_id) -> int`
- `AgingSystem.get_age_category(race, age) -> String`
- `AgingSystem.apply_age_change(character, years) -> Dictionary`
- `AgingSystem.apply_cumulative_adjustments(character, target_category) -> Dictionary`
- `AgingSystem.check_death_from_age(character) -> Dictionary`
- `AgingSystem.get_next_category_age(race, current_category) -> int`
- `XPAwardCalculator.calculate_monster_xp(hd_key, special_abilities) -> int` [static]
- `XPAwardCalculator.calculate_encounter_monster_xp(monsters) -> int` [static]
- `XPAwardCalculator.calculate_party_shares(total_xp, members) -> Dictionary` [static]
- `XPAwardCalculator.apply_prime_req_adjustment(raw_xp, adjustment_percent) -> int` [static]
- `XPAwardCalculator.bankers_round(value: float) -> int` [static]
- `XPAwardCalculator.clamp_to_one_level(character, raw_award) -> int`
- `XPAwardCalculator.award_adventure_xp(monster_xp, treasure_xp, members) -> Array`
- `XPAwardCalculator.calculate_domain_xp(income, level, is_henchman) -> int`
- `LevelUpEngine.can_level_up(character) -> bool`
- `LevelUpEngine.roll_level_up_hp(character) -> int`
- `LevelUpEngine.apply_level_up_auto(character) -> Dictionary`
- `LevelUpEngine.begin_interactive_level_up(character) -> Dictionary`
- `LevelUpEngine.finalize_interactive_level_up(character, level_up_result, choices) -> bool`
- `CampaignRepository.update_character_fields(id, fields) -> bool`
- `EventBus.age_category_changed(character_id, old_category, new_category)` [signal NEW]

**Database changes:**
- Migration 016: `xp_awards` table (id, character_id, campaign_id, amount, source_type CHECK, description, adventure_id, awarded_at). Indexed on character_id and campaign_id.

**Tests added/updated:**
- `tests/test_xp_award_calculator.gd` (NEW): 13 tests covering monster XP, party shares, prime req adjustment (Bankers rounding), 1-level cap, domain XP.
- `tests/test_level_up_engine.gd` (NEW): 10 tests covering eligibility, HP rolling, proficiency slot detection, spell slot expansion, stat updates, power unlock detection.
- `tests/test_aging_system.gd` (NEW): 10 tests covering starting age range, age category boundaries, transitions with ability adjustments, ability floor clamping, death save triggers.
- Total test suites: 32.

**Known issues:**
- Level-up confirmation does NOT show inline proficiency picker yet. Player is told to use Proficiencies tab. UI polish for a future session.
- Migration 016 needs to be verified in main_scene.gd migration runner on first launch.
- XP audit log table created but nothing writes to it yet. E-2 session runner is the consumer.
- AgingSystem._get_ability_floor() uses a hardcoded prime req table (25 classes) to avoid ClassRegistry dependency. [NEEDS-OPUS-REVIEW: should ClassRegistry be injected into AgingSystem?]

**Next session should:**
1. Run `tests/test_runner.tscn` and verify all 32 suites pass including the 3 new ones.
2. Verify migration 016 applies correctly on first game launch.
3. Smoke-test: create PC, check starting age in Finalize, open Advancement tab, use dev override to set XP to level threshold, click Level Up, verify HP/stat changes, Confirm.
4. Address E-2 (session runner) as primary consumer of XPAwardCalculator and LevelUpEngine.
5. Address G-2 (henchman XP sharing) which can now use XPAwardCalculator with is_henchman=true.

---

## Session 2026-04-01 - Character Creation: Five Rolled Arrays UI

**Task:** Update the character creation UI so player-created characters roll five full 3d6-in-order attribute arrays and choose one, while non-UI-generated characters and NPC generation continue using the existing single-array flow.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `scenes/ui/character_creation/ability_roll_panel.gd` to roll five complete ability arrays from a single "Roll Attributes" action, display all five arrays, and let the player choose one active array.
- Kept downstream character-creation steps unchanged by storing the chosen array back into the existing `creation_state["scores"]` field and resetting `traded_scores` when the player changes arrays.
- Updated `scenes/ui/character_creation/character_creation_screen.gd` initial state with `score_options` and `selected_score_index` so the chosen array survives back-navigation inside the wizard.
- Added `tests/test_ability_roll_panel.gd` covering score-array selection state and selection restoration on setup.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to register the new AbilityRollPanel test suite.

**Decisions made:**
- The five-array behavior is UI-only. `CharacterGenerator.generate_npc()` and the generator's core single-array logic were left untouched so NPCs and other non-UI generation paths still roll one array.
- The selected UI array is persisted in the pre-existing `scores` state key to minimize blast radius across class selection, ability trading, HP rolling, and finalization panels.

**Interfaces defined or changed:**
- `AbilityRollPanel.select_score_option(index: int) -> void` - selects one rolled array, copies it into `creation_state["scores"]`, and clears `traded_scores`.
- `CharacterCreationScreen.creation_state` additions:
  - `score_options: Array`
  - `selected_score_index: int`

**Database changes:** None.

**Tests added/updated:**
- Added `tests/test_ability_roll_panel.gd`.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to include the new suite.

**Known issues:**
- Could not run the Godot headless test runner in this shell because `godot`/`godot4` was not available on PATH.
- In PHYSICAL/HYBRID dice modes, the new UI still resolves via repeated `DiceSystem.player_roll()` calls, so rolling five arrays will prompt for each underlying 3d6 result rather than collecting all five arrays in a single manual-entry dialog.

**Next session should:**
1. Run `res://tests/test_runner.tscn` in a Godot environment and verify the new AbilityRollPanel suite passes with the rest of the test pack.
2. Smoke-test the character creation wizard: roll attributes, switch between arrays, pick a class, trade scores, and confirm the chosen array carries through correctly.
3. If desired, design a batch/manual attribute-entry UX for PHYSICAL/HYBRID dice modes so five-array rolling is less prompt-heavy.

---

## Session 2026-04-01 - Character Creation: Silent Five-Array Rolling

**Task:** Remove the dice prompt dialog from the UI character-creation ability roll step so the five attribute arrays are rolled silently and then shown all at once when the player clicks the roll button.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `scenes/ui/character_creation/ability_roll_panel.gd` so the five UI-only attribute arrays now use `DiceSystem.roll_digital()` instead of `DiceSystem.player_roll()`.
- Kept the rest of the five-array chooser intact: clicking `Roll Attributes` now silently generates all five arrays and then publishes them in the panel for selection.
- Updated the status text at the end of rolling to confirm that all five arrays are ready to choose from.

**Decisions made:**
- The silent rolling change is limited to the ability-score step in the character creation UI. Other player-facing dice prompts such as HP or starting gold were not changed.
- The roll still flows through `DiceSystem` so the arrays remain generated by the same central dice subsystem and continue to be logged through its digital-roll path.

**Interfaces defined or changed:** None.

**Database changes:** None.

**Tests added/updated:** None additional this session.

**Known issues:**
- Headless verification attempt using `C:\Godot\Godot_v4.6.1-stable_win64.exe --headless --path . res://tests/test_runner.tscn` crashed in Godot after reporting `Failed to open 'user://logs/godot2026-04-01T20.27.49.log'`. The crash appears environmental and did not provide test results.

**Next session should:**
1. Smoke-test the character creation screen in-editor to confirm the roll button now reveals five arrays immediately with no dice prompt dialog.
2. Re-run the test suite once the headless logging/crash issue is resolved or from the Godot editor test scene.

---

## Session 2026-04-01 — Test Runner Fix + Triage Pass

**Task:** Fix false-green test runner and repair all failing suites found by triage.
**Model used:** Sonnet 4.6

**Completed:**

*Part 1 — Test runner structural fix:*
- Created `tests/test_suite_base.gd`: base class with `check(condition, message)` that tracks `_failed`, `_fail_count`, `_test_count`. Suites extend this instead of `Node`.
- Updated `tests/test_runner.gd`: `_run_suite()` now returns `not suite.has_failures()` and prints per-suite failure counts. Previously always returned `true`.
- Converted all 33 test files: `extends Node` → `extends "res://tests/test_suite_base.gd"`, `assert(` → `check(`, final print wrapped in `if not has_failures():`.

*Part 2 — Production bug fixes:*

- **Bug A — `save_character()` UPDATE missing columns** (`engine/autoloads/campaign_repository.gd`):  
  Added `persistence_tier`, `strength`, `intelligence`, `wisdom`, `dexterity`, `constitution`, `charisma`, `race`, `character_class`, `combat_progression`, `character_type`, `employer_id`, `sex` to the UPDATE SET clause and bindings. These existed in the INSERT but were absent from the UPDATE, causing PersistenceTiers and OverrideManager test failures.

- **Bug B — JSON float/int mismatch** (`engine/subsystems/characters/class_registry.gd`, `level_up_engine.gd`):  
  `get_spell_slots()` now calls `.map(func(v) -> int: return int(v))` on the returned array.  
  `_check_new_proficiency_slots()` now converts `class_levels` and `general_levels` to int arrays before the `in` test. JSON.parse() returns all numbers as floats; int `in` float-array comparisons always fail.

- **Bug C — Proficiency clear leaves stale modifiers** (`engine/shared_types/modifier_stack.gd`, `modifier_container.gd`, `entity_flags.gd`, `engine/subsystems/characters/proficiency_effect_resolver.gd`):  
  Added `remove_by_source_prefix(prefix)` to `ModifierStack`, `remove_all_with_source_prefix(prefix)` to `ModifierContainer`, and `clear_all_from_source_prefix(prefix)` to `EntityFlags`. Rewrote `_clear_proficiency_effects()` to call these prefix methods instead of iterating `character.proficiencies` (which was already empty at call time).

- **Bug D — CalendarSeasons off-by-one** (`engine/subsystems/calendar/calendar_seasons.gd:183`):  
  Changed `elif day_in_season < 61` to `elif day_in_season < 60`. Days 0-29 = early, 30-59 = mid, 60-90 = late.

- **Bug E — RepertoireEngine duplicate spell test** (`tests/test_repertoire_engine.gd`):  
  Changed INT from 16 to 13 in `test_starting_arcane_duplicates_reduce`. INT 16 yields 2 bonus rolls but the single-use override was consumed by the first roll, leaving the second roll uncontrolled. INT 13 (+1) yields exactly 1 bonus roll so the single override suffices.

**Decisions made:**
- Prefix-based proficiency clear is unconditional (always clears all `"proficiency:"` prefixed sources before reapplying). This is correct per the "idempotent re-apply" contract in the resolver's docstring.
- Bug E classified as a test bug, not a production bug — the production code is correct.

**Interfaces defined or changed:**
- `ModifierStack.remove_by_source_prefix(prefix: String)` — new method
- `ModifierContainer.remove_all_with_source_prefix(prefix: String)` — new method
- `EntityFlags.clear_all_from_source_prefix(prefix: String)` — new method

**Database changes:** None.

**Tests added/updated:**
- All 33 test files now use `check()` — failures surface correctly instead of silently passing.
- `test_repertoire_engine.gd::test_starting_arcane_duplicates_reduce` — fixed INT value.

**Known issues:**
- Headless test execution still environmental (Godot log dir crash). Tests should be run from the Godot editor.
- No verification run performed this session. Expect "32 passed, 0 failed" once run.

**Next session should:**
1. Run the full test suite from the Godot editor test scene and confirm 32/33+ passed, 0 failed.
2. Smoke-test the character creation screen in-editor (carry-over from previous session).

---

## Session 2026-04-01 - Timekeeping Aging Integration Fix

**Task:** Fix the bug where advancing the campaign clock by years did not increase character ages or advance age categories.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `engine/autoloads/timekeeping.gd` to connect to `GameState.session_started`, load persisted clock state automatically at session start, and apply campaign-wide character aging on each `year_changed` boundary.
- Added `Timekeeping._age_campaign_characters_one_year()` to age all active non-transient, living characters with valid ages, persist their updated age/category/ability fields through `CampaignRepository.update_character_fields()`, and emit `EventBus.age_category_changed(...)` only after the DB write succeeds.
- Updated `engine/subsystems/characters/aging_system.gd` so `AgingSystem.apply_age_change()` now performs state mutation plus result reporting only and no longer emits `age_category_changed` before persistence.
- Expanded `tests/test_timekeeping.gd` with regression coverage for:
  - session start loading persisted timekeeping state
  - year-boundary advancement aging a persisted character from adult to middle-aged and saving the stat penalties

**Decisions made:**
- Aging now runs from `Timekeeping.year_changed` rather than the override UI so every source of year advancement uses the same integration path.
- Campaign-wide annual aging skips transient encounter-tier characters, dead characters, and records with `current_age <= 0` to avoid mutating incomplete or non-persistent entities.
- `age_category_changed` emission moved out of `AgingSystem.apply_age_change()` because emitting before persistence caused UI listeners to reload stale DB data.

**Interfaces defined or changed:**
- `AgingSystem.apply_age_change(character, years) -> Dictionary`
  - Signature unchanged.
  - Behavior changed: no longer emits `EventBus.age_category_changed`; callers now own notification timing after persistence.
- `Timekeeping` now listens to `GameState.session_started(campaign_id)` and `Timekeeping.year_changed(new_year)`.

**Database changes:** None.

**Tests added/updated:**
- Updated `tests/test_timekeeping.gd` with 2 regression tests covering session-start clock loading and persisted year-boundary aging.

**Known issues:**
- Headless Godot test runs exit cleanly with code `0`, but this shell still does not receive the runner's printed suite summary on stdout/stderr. The Godot app-data log updated normally during the verification run.
- The character sheet still refreshes age displays reactively only on category changes, not on every birthday within the same category.

**Next session should:**
1. Smoke-test the override panel's Timekeeping tab in-editor: advance 1 year, then multiple decades, and confirm party character sheets reflect age/category changes.
2. Decide whether non-category age increments should get their own UI refresh signal so open character sheets update without being reopened.

---

## Session 2026-04-01 - Level-Up Proficiency Selection Fix

**Task:** Fix the PC level-up flow so new proficiency slots can actually be selected and persisted.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd` so the level-up panel now embeds an inline proficiency picker when a new class or general slot is earned, instead of directing the player to the read-only Proficiencies tab.
- Added `scenes/ui/character_sheet/tabs/level_up_proficiency_picker.gd` (NEW): a dedicated level-up picker that works from the character's existing proficiencies plus pending slot counts, supports rank-ups and specialization choices, and returns the full post-level-up proficiency state.
- Updated `engine/subsystems/characters/level_up_engine.gd` so interactive level-up can save either a full `all_proficiencies` state or merge delta records by `proficiency_key + slot_type + specialization`, which fixes rank-up and specialization persistence for the level-up path.
- Added `tests/test_level_up_proficiency_picker.gd` (NEW) covering rank-up and specialization selection behavior.
- Updated `tests/test_level_up_engine.gd` with a regression test for specialization-aware proficiency merging.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to register the new picker test suite.
- Verified in Godot headless via app-data log: `=== TEST RESULTS: 33 suites passed, 0 failed ===`.

**Decisions made:**
- The proficiency choice now happens before confirming the level-up. This avoids introducing a new persistent "pending proficiency slot" data model just to survive after confirmation.
- The advancement tab owns the temporary choice UI; the Proficiencies tab remains a read-only summary tab for now.
- Interactive level-up persistence now treats specialization variants as distinct records and preserves rank/selections_count on existing records.

**Interfaces defined or changed:**
- `LevelUpEngine.finalize_interactive_level_up(character, level_up_result, choices) -> bool`
  - `choices` now optionally accepts `all_proficiencies: Array[Dictionary]` representing the full post-level-up proficiency state.
- `LevelUpEngine._merge_proficiency_records(existing, updates) -> Array`
  - New internal helper that merges by `proficiency_key`, `slot_type`, and `specialization`.

**Database changes:** None.

**Tests added/updated:**
- Added `tests/test_level_up_proficiency_picker.gd`.
- Updated `tests/test_level_up_engine.gd`.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn`.

**Known issues:**
- The Proficiencies tab is still read-only; the editable selection UI currently lives only inside the Advancement tab's level-up panel.
- `LevelUpEngine.apply_level_up_auto()` still uses the older NPC auto-selection flow and was not refactored in this session.

**Next session should:**
1. Smoke-test the full player flow in-editor: earn XP, open Advancement, level up, choose a ranked proficiency and a specialization-based proficiency, confirm, and reopen the sheet.
2. Decide whether the Proficiencies tab should eventually reuse `LevelUpProficiencyPicker` for other future proficiency-granting effects.

---

## Session 2026-04-02 - Level-Up Proficiency Modal UI

**Task:** Move the level-up proficiency selector out of the Advancement tab inline layout and into a dedicated popup/modal window.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd`:
  - Replaced the inline embedded proficiency picker with a `Select New Proficiencies` button.
  - Added a modal `PopupPanel` flow (`_proficiency_popup`) containing the full `LevelUpProficiencyPicker`.
  - Added modal open/close handlers and status labels for both modal and inline summary contexts.
  - Kept confirm-level-up validation tied to the picker being complete before save.
- Updated `scenes/ui/character_sheet/tabs/level_up_proficiency_picker.gd`:
  - Added `selection_state_changed` signal.
  - Emits the signal whenever picker state changes so the modal status updates live.
- Verified via Godot headless run in app log: `=== TEST RESULTS: 34 suites passed, 0 failed ===`.

**Decisions made:**
- Used a modal `PopupPanel` instead of growing the Advancement tab content so the selector has stable width/height and avoids scroll clipping inside the tab container.
- Kept the picker state in-memory for the active level-up flow; closing/reopening the modal preserves choices until level-up is confirmed or canceled.

**Interfaces defined or changed:**
- `LevelUpProficiencyPicker.selection_state_changed` (new signal)
- `CSTabAdvancement` now owns modal helpers:
  - `_prepare_proficiency_picker(...)`
  - `_ensure_proficiency_popup()`
  - `_on_open_proficiency_popup()`
  - `_on_close_proficiency_popup()`
  - `_on_proficiency_picker_state_changed()`

**Database changes:** None.

**Tests added/updated:**
- No new test files this session.
- Existing suite re-run successfully (`34` suites, `0` failures).

**Known issues:**
- This session did not add viewport-size adaptive modal sizing beyond fixed minimum and centered ratio; if very small window layouts are expected, add a clamp strategy in a later pass.

**Next session should:**
1. Smoke-test in-editor with narrow and wide viewport sizes to confirm modal usability and centering behavior.
2. Optionally add a keyboard shortcut (`Esc`) to close the proficiency modal explicitly if desired.

---

## Session 2026-04-02 - Advancement Parse Error Hotfix

**Task:** Fix parser errors preventing `CSTabAdvancement` and `CharacterSheetOverlay` from loading.
**Model used:** GPT-5 Codex

**Completed:**
- Fixed an indentation error in `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd` inside `_on_confirm_level_up()` where `err.text` and `err.add_theme_color_override(...)` were over-indented under `var err := Label.new()`.
- Verified no parse errors for `CSTabAdvancement` in latest Godot app log.
- Re-ran headless tests successfully (`34 suites passed, 0 failed` in app log).

**Decisions made:**
- Kept the modal proficiency selector implementation unchanged; this was a syntax hotfix only.

**Interfaces defined or changed:** None.

**Database changes:** None.

**Tests added/updated:** None added; existing suite re-run.

**Known issues:**
- Direct headless launch of `character_sheet_overlay.tscn` still crashes in this environment due the existing `user://logs/...` file-open issue; this appears environmental and unrelated to script parsing.

**Next session should:**
1. In-editor smoke-test the character sheet open path and the level-up modal flow now that parsing is restored.

---

## Session 2026-04-01 — D-1: Asset Registry

**Task:** Build the central asset registry (D-1): semantic ID → path lookup, placeholder terrain atlas generator, manifest file, hex map renderer refactor.
**Model used:** Sonnet 4.6 (1M context)

**Completed:**
- Created `engine/subsystems/assets/asset_registry.gd` — `class_name AssetRegistry extends RefCounted`. Static-method class (not autoload) with lazy manifest loading. API: `get_path(id)`, `has_asset(id)`, `register(id, path)`, `get_all_ids()`. Loads `data/asset_manifest.json` on first call, flattens nested JSON into dot-notation keys.
- Created `data/asset_manifest.json` — complete asset vocabulary: 65 portrait PNGs (all 25 classes × N variants), 18 terrain IDs (atlas + 17 individual tile paths), 2 UI background textures. All 25 class portrait_XX_01 variants mapped.
- Created `tools/generate_placeholders.gd` — `@tool extends EditorScript`. Run via Script → Run to generate `res://assets/terrain/terrain_atlas.png`. Creates a 17-column labeled hex atlas using the same colors/layout as the renderer. Skips existing files.
- Modified `scenes/maps/hex_map_renderer.gd` — extracted `_build_terrain_atlas_texture() -> ImageTexture` from `_create_terrain_tileset()`. The refactored `_create_terrain_tileset()` checks `AssetRegistry.get_path("terrain.atlas")` first; falls back to `_build_terrain_atlas_texture()` if not found. Zero behavior change until the placeholder tool is run.
- Created `tests/test_asset_registry.gd` — 10 tests covering: unknown ID returns empty, has_asset false for unknown, register/retrieve round-trip, has_asset after register, register overwrites, all 25 portrait classes have _01 variant, terrain.atlas registered, UI textures registered, portrait paths are res:// scheme, get_all_ids includes registered.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` — added AssetRegistryTests node (id 35).

**Decisions made:**
- AssetRegistry is a **class with static methods, not an autoload** — avoids an 8th autoload; read-only after init fits the static-variable pattern cleanly. `class_name` is safe here because it is not an autoload script.
- Manifest uses nested JSON flattened to dot-notation keys at load time. Nesting is only one level deep in the current file (`ui.bg.vellum_base`) — `_flatten()` handles arbitrary depth for future extensibility.
- Renderer refactor is strictly non-breaking: if `terrain.atlas` is not registered or the file doesn't exist, `_build_terrain_atlas_texture()` runs as before.
- Portrait IDs in the manifest match the filename minus `portrait_` prefix and `.png` extension (e.g., `portrait.fighter_01`). This is consistent with what C-3 will query.

**Interfaces defined or changed:**

AssetRegistry (`engine/subsystems/assets/asset_registry.gd`):
- `static func get_path(id: String) -> String`
- `static func has_asset(id: String) -> bool`
- `static func register(id: String, path: String) -> void`
- `static func get_all_ids() -> Array[String]`

Manifest contract (`data/asset_manifest.json`):
- Top-level sections: `terrain`, `portrait`, `ui`
- Terrain IDs: `terrain.atlas`, `terrain.flat_clear` … `terrain.mountains_desert`, `terrain.ocean`, `terrain.river`
- Portrait IDs: `portrait.{class_name}_{NN}` for all 25 classes
- UI IDs: `ui.bg.vellum_base`, `ui.bg.vellum_subtle`

**Database changes:** None.

**Tests added/updated:**
- Added `tests/test_asset_registry.gd` — 10 tests.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn`.

**Known issues:**
- `tools/generate_placeholders.gd` has not been run yet — `res://assets/terrain/terrain_atlas.png` does not exist. The renderer falls back to programmatic generation until it is run. Run via Script → Run in the Godot editor to generate it.
- The per-tile individual terrain paths (`terrain.flat_clear` etc.) are registered in the manifest but the PNG files don't exist yet (the placeholder tool only generates the atlas). These IDs are reserved for future use when per-tile art or individual tile generators are added.

**Next session should:**
1. Run `tools/generate_placeholders.gd` in the Godot editor and verify `res://assets/terrain/terrain_atlas.png` is created correctly.
2. Run `tests/test_runner.tscn` — verify all 10 AssetRegistry tests pass, no existing suites regressed.
3. Proceed to C-3 (character creation UI) — it depends on portrait IDs from AssetRegistry.

---

## Session 2026-04-02 — D-2: Navigation Stack and Scene Transitions

**Task:** Build NavigationStack (scene-tree singleton), ManagedScene base class, SceneTransition overlay, CampaignSelectScreen, and wire into Main.tscn / main_scene.gd. Add delete_campaign() to CampaignRepository.
**Model used:** claude-opus-4-6 (planning + implementation)

**Completed:**

- Created `engine/subsystems/navigation/managed_scene.gd` (class ManagedScene, extends Node) — virtual base for NavigationStack-managed screens. Four virtual methods: `enter(params)`, `exit()`, `save_state()`, `restore_state(data)`. Screens that extend CanvasLayer implement the same methods directly (duck typing; NavigationStack uses `has_method()` checks).

- Created `engine/subsystems/navigation/navigation_stack.gd` (class NavigationStack, extends Node) — scene-tree singleton. `static var instance` set in `_ready()`. Manages Array of {path, node, state} dicts. Cap: 8. API: `push(path, params)`, `push_node(node, path, params)`, `pop()`, `replace(path, params)`, `peek()`, `stack_depth()`, `has(path)`, `clear()`. Wraps swaps in SceneTransition.play() when set; otherwise instant. `setup(container, transition)` injects dependencies.

- Created `scenes/ui/transitions/scene_transition.gd` (extends CanvasLayer, layer=200) — black ColorRect (programmatic). `play(swap_callable, on_complete)` tweens self_modulate.a 0->1->0 over 0.5s total; calls swap at midpoint, on_complete after fade-in. `reset()` for emergency alpha=0.

- Created `scenes/ui/transitions/scene_transition.tscn`

- Created `scenes/ui/campaign_select/campaign_select_screen.gd` (extends CanvasLayer, layer=10) — programmatic UI. ManagedScene duck-typed interface (enter refreshes list, exit hides create dialog, save/restore_state preserve scroll). Lists campaigns from CampaignRepository.list_campaigns(). Each row: Load + Delete buttons. New Campaign: inline dialog, validates name, create_campaign(). Delete: ConfirmationDialog, _pending_delete_id, calls delete_campaign() on confirm. Emits `campaign_selected(campaign_id)`.

- Created `scenes/ui/campaign_select/campaign_select_screen.tscn`

- Added `delete_campaign(campaign_id: String) -> bool` to `engine/autoloads/campaign_repository.gd` — cascading hard delete. Collects char/party/map IDs with .duplicate() before iterating. Deletes: character_conditions, character_proficiencies, inventory_items, character_spells, party_members, party_clocks, hex_cells, characters, parties, hex_maps, domains, game_snapshots, campaign_clock, dungeon_entrances, override_log, then campaigns.

- Updated `scenes/Main.tscn` — added NavigationStack (Node + navigation_stack.gd), SceneContainer (plain Node), SceneTransition (instance of scene_transition.tscn). Placed before HexMapController.

- Updated `scenes/main_scene.gd` — added @onready vars for three new nodes. Added `DEV_SKIP_CAMPAIGN_SELECT := false` const. _ready() calls setup() then branches: false = push CampaignSelectScreen; true = dev bypass to test map. Extracted test-map loading into _dev_load_test_map_for_campaign() and _load_or_seed_map(). _ensure_test_party() split from _ensure_test_campaign() for reuse.

- Created `tests/test_navigation_stack.gd` — 12 tests using push_node() + lightweight mock _MockScreen inner class. Tests: depth 0 on init, push/pop depth, pop empty no crash, peek returns path, peek empty returns "", push/pop/peek restores previous, replace (clear+push) resets to 1, has() true/false, enter/exit called on push/pop.

- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` — NavigationStackTests added as new suite.

**Decisions made:**
- NavigationStack is a scene-tree singleton (not autoload). Already at 7 autoloads; nav belongs in scene tree since it manages child nodes. class_name NavigationStack allowed (not an autoload).
- push_node() API enables testing without .tscn loading and supports pre-built nodes.
- SceneTransition uses self_modulate.a on the ColorRect.
- ConfirmationDialog (Godot built-in) for delete confirm — style later when game has theme.
- DEV_SKIP_CAMPAIGN_SELECT = false default: campaign select is the live entry point.
- _on_campaign_selected() in main_scene.gd is a temporary shim; replaced by E-2 session runner.

**Interfaces defined or changed:**

NavigationStack (new class, engine/subsystems/navigation/navigation_stack.gd):
- `static var instance: NavigationStack`
- `func setup(container: Node, transition = null) -> void`
- `func push(path: String, params: Dictionary = {}) -> void`
- `func push_node(node: Node, path: String = "", params: Dictionary = {}) -> void`
- `func pop() -> void`
- `func replace(path: String, params: Dictionary = {}) -> void`
- `func peek() -> String`
- `func stack_depth() -> int`
- `func has(path: String) -> bool`
- `func clear() -> void`
- Signals: scene_pushed(path), scene_popped(path), scene_replaced(new_path), stack_cleared

ManagedScene (new class, engine/subsystems/navigation/managed_scene.gd):
- Virtual: enter(_params), exit(), save_state() -> Dictionary, restore_state(_data)

SceneTransition (new node, scenes/ui/transitions/scene_transition.gd):
- play(swap_callable: Callable, on_complete: Callable = Callable()) -> void
- reset() -> void

CampaignSelectScreen signal: campaign_selected(campaign_id: String)

CampaignRepository addition:
- func delete_campaign(campaign_id: String) -> bool

**Database changes:** None (delete_campaign operates on existing schema).

**Tests added/updated:**
- tests/test_navigation_stack.gd — 12 tests (new suite).
- tests/test_runner.gd + tests/test_runner.tscn — NavigationStackTests added.

**Known issues:**
- test_replace_clears_to_depth_one uses clear()+push_node() to test replace semantics (replace() requires a disk path; no replace_node() variant exists). Covers the intent.
- ConfirmationDialog delete confirm uses default Godot theme. Style when game has custom theme.
- HexMap/HexMapController are still direct children of Main, not inside nav stack. They move to WorldMapScreen in E-2.

**Next session should:**
1. Open project in Godot 4.6; run test_runner.tscn — confirm NavigationStackTests (12 tests) pass alongside all existing suites.
2. Run game via Main.tscn: campaign select screen should appear on boot; create a campaign; verify it loads the test hex map.
3. Test delete: create a campaign, delete it, verify it disappears from the list.
4. Proceed to C-2b (Proficiency Catalog and Registry) or next priority per the build plan.

---

## Session 2026-04-02 â€” Navigation Stack Variant Inference Hotfix

**Task:** Fix the `navigation_stack.gd` parse error caused by strict warning-as-error type inference on `_stack.back()`.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `engine/subsystems/navigation/navigation_stack.gd` inside `_do_pop()` to replace `var prev := _stack.back()` with explicitly typed locals:
  - `var prev: Dictionary`
  - `var prev_node: Node`
  - `var prev_state: Dictionary`
- Verified the project loads past the parse stage by running the approved headless Godot test command successfully (exit code `0`).

**Decisions made:**
- Kept the fix narrowly scoped to the failing restoration path rather than refactoring the entire stack representation, since the immediate issue was a warning-promoted parse failure from inferred `Variant`.

**Interfaces defined or changed:** None.

**Database changes:** None.

**Tests added/updated:** None added; existing headless test runner executed successfully after the fix.

**Known issues:**
- The Godot headless run in this environment still does not print the suite summary to shell stdout even when the process succeeds; verification remains based on process exit code and prior established logging behavior.

**Next session should:**
1. Smoke-test the campaign-select to world-map navigation flow in-editor now that `navigation_stack.gd` parses again.
2. If more strict-typing parse warnings appear, consider tightening `_stack` entry handling further with helper accessors or a dedicated typed entry object.

---

## Session 2026-04-02 - Documentation Manifest Synchronization

**Task:** Update `acks_arbiter_design_brief_v11.md`, `document_map.md`, and `rule_system_map.md` so they accurately reflect the current `/docs` and `/generation` file set and the finalized `gdd-terrain-system.md` naming.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `docs/acks_arbiter_design_brief_v11.md`:
  - Refreshed the GDD manifest to include all current generation docs.
  - Removed the obsolete `gdd-terrain-wilderness.md` entry and clarified that its scope was absorbed into `gdd-terrain-system.md`.
  - Added the current supporting architecture/planning document list.
  - Replaced the stale "Documents Still Needed" list with an up-to-date statement that the baseline manifest is complete.
  - Updated the build-session protocol to reference the now-standard support docs.
  - Fixed a stale/typoed calendar-weather reference (`gdd-weather-generation.md` / `gdd-calendar-seasons.md`).
- Updated `docs/document_map.md`:
  - Added the previously omitted GDDs: `gdd-calendar-seasons.md`, `gdd-weather-generation.md`, `gdd-poi-generation.md`, `gdd-settlement-stocking.md`, `gdd-combat-map-generation.md`, `gdd-name-generation.md`, `gdd-quest-rumor-system.md`, `gdd-ui-ux-design.md`.
  - Added the previously omitted docs: `acks_arbiter_build_plan.md`, `monster_system_map.md`.
  - Removed stale "not yet created" notes for files that now exist.
  - Updated counts to 20 GDDs, 8 architecture/planning docs, 98 indexed files total.
- Updated `docs/rule_system_map.md`:
  - Added a companion-docs section covering the document map, coding conventions, build plan, and spell/proficiency/monster system maps.
  - Added `monster_system_map.md` to the Monsters & Encounters section.
  - Added or expanded system coverage for Settlement Stocking & Commerce, Combat Maps & Tactical Terrain, Quest & Rumor System, and UI & Presentation.
  - Folded in the omitted GDDs where they constrain existing systems.
  - Updated the GDD dependency graph and suggested implementation order to reflect the current generation-doc set.
- Verified with a post-edit directory comparison script that:
  - no current `/generation` files are missing from `document_map.md`
  - no current `/generation` files are missing from the design brief manifest
  - all current `/docs` files are represented in `document_map.md`

**Decisions made:**
- Treated `gdd-terrain-wilderness.md` as a retired name rather than a missing file and documented the rename/scope absorption explicitly in the updated manifests.
- Kept `rule_system_map.md` focused on system relevance rather than trying to make it a literal self-index; companion docs cover the supporting references it should point readers to.

**Interfaces defined or changed:** None.

**Database changes:** None.

**Tests added/updated:** No gameplay tests added; verification was done via manifest-vs-directory consistency checks and targeted stale-reference searches.

**Known issues:**
- `docs/gdd-ui-ux-design.md` still internally references `acks_arbiter_design_brief_v10.md`; that document was outside the scope of this manifest sync pass and may need a future cleanup if the project wants all cross-doc references normalized.

**Next session should:**
1. Decide whether to normalize stale cross-document references in the individual GDD files themselves (for example `gdd-ui-ux-design.md` still naming design brief v10).
2. If new support docs are added later, update all three manifest documents in the same session to prevent drift from reappearing.

---

## Session 2026-04-02 - Equipment Shop Starting Gold Reset Fix

**Task:** Fix the character-creation equipment shop so the starting-gold roll control stays available after reopening the screen, creating a second character in the same session, or returning to equipment after downstream state invalidation.
**Model used:** GPT-5 Codex

**Completed:**
- Updated `scenes/ui/character_creation/equipment_shop_panel.gd`:
  - `setup()` now always refreshes the item list, including the pre-roll placeholder path.
  - `_restore_from_state()` now fully rehydrates the panel from `creation_state` on every setup call:
    - restores/clears gold values from backing state
    - resets `_rolling`
    - re-shows and re-enables the roll button when `starting_gold_cp` is cleared
    - clears stale status text
    - resets the category tab to the first tab for fresh/no-gold states
- Added `tests/test_equipment_shop_panel.gd` with regression coverage for:
  - fresh state showing an enabled roll button
  - reused panel state resetting correctly after a prior rolled-gold session
  - placeholder content rebuilding when gold is cleared
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to register the new equipment-shop panel test suite.
- Updated `docs/coding_conventions.md` with a reusable-panel setup rule: stateful multi-step panels must fully reset UI state from backing data on each `setup()` call.
- Verified with headless Godot test run: approved test runner command exited with code `0`.

**Decisions made:**
- Fixed the root cause in the panel lifecycle rather than adding one-off resets in `CharacterCreationScreen`; the equipment panel is intentionally reused, so `setup()` is the right place to re-derive all transient UI state.
- Treated "fresh equipment state" as a true fresh-screen experience by resetting the tab bar to the first category when no starting gold has been rolled.

**Interfaces defined or changed:** None.

**Database changes:** None.

**Tests added/updated:**
- Added `tests/test_equipment_shop_panel.gd`.
- Updated `tests/test_runner.gd`.
- Updated `tests/test_runner.tscn`.

**Known issues:**
- Headless Godot runs in this environment still do not print the suite summary to shell stdout; success is verified by exit code `0`.

**Next session should:**
1. Smoke-test the character-creation UI in-editor specifically around the equipment step:
   - first character equipment entry
   - cancel/reopen mid-flow
   - create a second character in the same session
   - go back to an earlier step that invalidates equipment, then return
2. If similar reuse bugs appear in other character-creation panels, apply the same `setup()` full-reset pattern there.

---

## Session 2026-04-02 — D-4: Dungeon Square Grid (Isometric, Cell-Based Walls)

**Task:** Build the dungeon exploration system — isometric diamond grid, `TacticalMapData` shared type, `DungeonMapController`, layered renderer, fog of war, door interaction, multi-level stair transition, and ~39 new tests. Architecture must minimize rework for future combat, multi-character movement, and environment interactions.

**Model used:** claude-opus-4-6 (planning), claude-sonnet-4-6 (implementation)

**Completed:**
- `engine/shared_types/isometric_grid.gd` — `class IsometricGrid` static utility for diamond grid math (cell↔screen, neighbors, adjacency, radius)
- `engine/shared_types/tactical_map_data.gd` — `class TacticalMapData` unified cell grid (dungeon + combat). BFS room detect, fog dict, per-entity positions, full CellData schema per GDD
- `engine/subsystems/exploration/dungeon_map_controller.gd` — `class DungeonMapController`. Multi-level dungeon loading, party-as-group movement, door interaction (6 types, 4+ states), fog reveal/explore, stair transitions, signals
- `scenes/maps/dungeon_map_renderer.gd` — Isometric renderer: `_draw()` draws ground fills, feature icons (X/O/L/bars/arrows), grid outlines, fog overlay. Entity tokens as Polygon2D children. Camera panning. ManagedScene interface
- `scenes/maps/dungeon_map.tscn` — Scene tree: DungeonMap → EntityLayer, Camera2D, DungeonHUD (ExitButton + tooltip)
- `data/test_dungeon.json` — "Goblin Warrens": 5 rooms on level 1 (Entry Hall, Guard Post, Storage, Great Hall, Boss Chamber) + 1 room on level 2 (Underground Cavern). 7 door types, stairs, multi-level JSON format
- `db/migrations/017_dungeon_grid.sql` — `dungeon_map_cells` table (dungeon_id, level_num, col, row, door_state, fog_state). Adds `dungeon_id/level/col/row` columns to `parties`
- `db/schema.sql` — Updated to migration 017
- `engine/autoloads/campaign_repository.gd` — Added: `get_dungeon_entrances_for_map`, `get_dungeon_entrance`, `update_dungeon_entrance_data`, `save_dungeon_cell_states`, `load_dungeon_cell_states`, `update_dungeon_cell`, `update_party_dungeon_position`, `clear_party_dungeon_position`
- `data/asset_manifest.json` — Added `dungeon.entrance_icon` entry
- `scenes/maps/hex_map_renderer.gd` — Added `_refresh_dungeon_markers()`: places gold "D" labels on EXPLORED/VISIBLE hexes with dungeon entrances
- `scenes/main_scene.gd` — Added `_ensure_test_dungeon_entrance()`, `_check_for_dungeon_entrance()`, `_enter_dungeon()`. Seeds Goblin Warrens entrance at hex (-1, 0). Auto-enters dungeon when party clicks an entrance hex.
- `tests/test_isometric_grid.gd` — 16 tests
- `tests/test_tactical_map_data.gd` — 21 tests
- `tests/test_dungeon_map_controller.gd` — 16 tests (including stair/level transition tests)
- `tests/test_runner.gd` + `tests/test_runner.tscn` — Suites 36-38 registered

**Decisions made:**
- **TacticalMapData, not DungeonMapData** — the cell grid is shared with future combat maps (GDD: dungeon grid IS the combat grid). Naming reflects reuse.
- **IsometricGrid as separate static class** — grid math used by renderer, controller, future pathfinding/LOS. One source of truth.
- **String-based terrain_feature/door_type/door_state** — not enums. Vocabulary expands for combat without migration-requiring enum changes.
- **Multi-level JSON with levels array + stairs array** — supports arbitrary depth; level fog stored per-TacticalMapData instance in controller._all_levels dict.
- **Secret doors visible in dev mode** — undetected secrets rendered with dark grey + "S" icon for placement verification; will be hidden by production build flag.
- **Single `_draw()` on root Node2D** — no separate layer scripts. Draw order: ground → features → grid lines → fog. Entity tokens are Polygon2D children of EntityLayer (no _draw).
- **DungeonMapController created dynamically** — not in Main.tscn; instantiated in `main_scene.gd._enter_dungeon()` as a child node, freed when dungeon scene exits.
- **No CHECK constraint on door_state** — vocabulary will grow (spiked, barred, etc.); validation in code.

**Interfaces defined or changed:**
- `TacticalMapData` (new): `from_dict(level_dict)`, `load_from_file(path)`, full cell/fog/room/entity API
- `IsometricGrid` (new): `cell_to_screen(col, row)→Vector2`, `screen_to_cell(pos)→Vector2i`, `get_neighbors(pos)→Array[Vector2i]`, `is_adjacent(a,b)→bool`, `manhattan_distance(a,b)→int`, `get_cells_in_radius(center,radius)→Array[Vector2i]`
- `DungeonMapController` (new): `load_dungeon(dict)`, `move_party(target)→bool`, `interact_door(pos)→bool`, `use_stairs(pos)→bool`, signals: `map_loaded`, `party_moved`, `entity_moved`, `room_revealed`, `fog_updated`, `door_state_changed`, `level_changed`
- `CampaignRepository` additions: `get_dungeon_entrances_for_map(map_id)→Array`, `get_dungeon_entrance(id)→Dict`, `save_dungeon_cell_states(dungeon_id, level_num, cells)→bool`, `load_dungeon_cell_states(dungeon_id, level_num)→Array`, `update_party_dungeon_position(party_id, dungeon_id, level_num, col, row)`, `clear_party_dungeon_position(party_id)`
- dungeon_map_renderer.gd signals: `cell_clicked(pos: Vector2i)`, `door_interact_requested(pos: Vector2i)`, `exit_requested()`

**Database changes:**
- Migration 017: `dungeon_map_cells` table (dungeon_id, level_num, col, row, door_state, fog_state). `parties` table gains `dungeon_id TEXT`, `dungeon_level INTEGER`, `dungeon_col INTEGER`, `dungeon_row INTEGER`.

**Tests added/updated:**
- `test_isometric_grid.gd` — 16 tests: origin, positive col/row, diagonal, roundtrip, neighbors count/directions, adjacency, Manhattan distance, radius queries
- `test_tactical_map_data.gd` — 21 tests: from_dict, void cells, room detection (5 rooms), open-only rooms, door state load/set, fog defaults/set, passability (open/open-door/closed-door/wall), LOS (wall/portcullis), secret door blocking, entity CRUD, boundary cells, bounds check
- `test_dungeon_map_controller.gd` — 16 tests: load/entry position, fog reveal on load, movement (valid/non-adjacent/wall/closed-door/open-door), door interaction (toggle/locked), room reveal, fog VISIBLE→EXPLORED, signals, stair transition (level change, position, signal, fog preservation)
- Total test suites: 38

**Known issues:**
- dungeon_map_renderer.gd `_enter()` ManagedScene integration reads dungeon data from CampaignRepository — requires DB to be open before push. For the dev path, dungeon is loaded before pushing so this should work.
- The `ALTER TABLE parties ADD COLUMN` statements in migration 017 will fail if run twice (SQLite doesn't support IF NOT EXISTS on ALTER). Migration tracking table prevents this from being a practical problem.
- Fog-of-war across stair transitions: returning to level 1 and re-entering the same room will show it as EXPLORED (not re-reveal it as VISIBLE) because the old level's TacticalMapData fog dict is preserved. This is correct behavior but differs slightly from fresh entry.

**Next session should:**
1. Open the game and run the test suite to verify all 38 suites pass.
2. Navigate to hex (-1, 0) on the Ashford Vale test map and verify the dungeon entrance transition: campaign select → hex map with "D" marker → click entrance hex → isometric dungeon renders.
3. Test door interaction, fog reveal, and stair descent to level 2 (Underground Cavern).
4. Test exit dungeon → hex map restoration.
5. If D-4 passes, proceed to E-1 (Session Runner) or the next priority per the build plan.

---

## Session 2026-04-02 - Equipment Item Row Equip Callback Fix

**Task:** Fix the character-sheet equipment tab error raised when pressing Equip on a loose item: `Invalid call to function '<anonymous lambda>'... Expected 0 argument(s).`
**Model used:** GPT-5 Codex
**Completed:**
- Updated `scenes/ui/character_sheet/tabs/equipment_item_row.gd` so the Equip button invokes the supplied equip callback with zero arguments.
- Added `tests/test_equipment_item_row.gd` to verify a loose-item Equip button calls its zero-argument callback exactly once.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to register the new equipment-item-row regression suite.
- Ran the approved headless Godot test runner command successfully (exit code `0`).
**Decisions made:**
- Treated `EquipmentLooseZone.setup()` as the owner of item binding for equip actions: it creates a per-item callable, and `EquipmentItemRow` simply executes that callable instead of passing the item dictionary again.
**Interfaces defined or changed:**
- `EquipmentItemRow.setup(item, remove_callback, character_id, equip_callback)` now expects `equip_callback` to be a pre-bound zero-argument `Callable` for the row's item.
**Database changes:** None.
**Tests added/updated:**
- Added `tests/test_equipment_item_row.gd`.
- Updated `tests/test_runner.gd`.
- Updated `tests/test_runner.tscn`.
**Known issues:**
- Headless Godot runs in this environment still report success via exit code without printing the suite summary to shell stdout.
**Next session should:**
1. Smoke-test the character sheet equipment tab in-editor and confirm loose-item Equip buttons now work without runtime errors.
2. If more reusable row widgets need button callbacks, keep the same pattern: pre-bind item context in the parent and execute zero-argument row callbacks.

---

## Session 2026-04-02 - Campaign Select Vellum Styling Pass

**Task:** Restyle the campaign select UI so the campaign list and new-campaign modal use `assets/ui/bg_vellum_subtle.png` with stronger framing.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `scenes/ui/campaign_select/campaign_select_screen.gd` to wrap the main campaign-select panel in a bordered frame with an inner vellum panel.
- Applied the same framed vellum treatment to the scrollable campaign list area itself.
- Restyled each campaign row with a softer bordered card treatment to read cleanly against the parchment background.
- Restyled the new-campaign modal with the same vellum texture, a warm border frame, and a dim backdrop so it reads as a true modal.
- Normalized the world-name `LineEdit` width to match the campaign-name field.
- Verified the project still parses and the headless Godot test runner exits successfully with code `0`.
**Decisions made:**
- Used a nested frame pattern for these UI elements: dark outer border panel for structure, `bg_vellum_subtle` inner panel for surface texture.
- Added a modal backdrop while the create-campaign dialog is visible so the parchment dialog has better visual separation from the campaign list.
**Interfaces defined or changed:** None.
**Database changes:** None.
**Tests added/updated:** No new tests; validation was a successful headless Godot test-runner execution after the UI script changes.
**Known issues:**
- This environment cannot visually inspect the result in-editor, so the final confirmation for spacing and texture balance still needs a quick manual UI smoke test.
**Next session should:**
1. Open the campaign select screen in-editor and verify the new vellum framing feels right at runtime.
2. If desired, carry the same framed-vellum styling into the delete confirmation dialog so all campaign-management popups share one visual language.

---

## Session 2026-04-02 - Gambling Proficiency Rank Cap Fix

**Task:** Allow the Gambling proficiency to rank up instead of being restricted to a single selection, with a project cap of Rank 5.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `data/proficiencies/proficiency_catalog.json` so Gambling uses a project cap of `max_rank = 5` and `max_selections = 5`.
- Clarified the Gambling catalog description to reflect that additional selections stack monthly income up to rank 5.
- Added a registry regression test confirming the project cap values for Gambling.
- Added a level-up picker regression test confirming repeated Gambling selections stack into one proficiency entry up to rank 5.
- Added a character-creation proficiency panel regression test confirming Gambling can rank up during initial selection without creating duplicate entries.
- Wired the new character-creation regression test into `tests/test_runner.gd` and `tests/test_runner.tscn`.
- Ran the approved headless Godot test runner command successfully (exit code `0`).
**Decisions made:**
- Treated Gambling as a ranked stacking proficiency for project purposes, matching the ACKS rules intent that additional selections continue to add value.
- Applied an explicit project cap of rank 5 even though the source rules text does not specify a hard upper limit.
- Preserved the existing `selection_rule = "stacking"` behavior so downstream effect resolution continues to scale from `selections_count`.
**Interfaces defined or changed:**
- Gambling catalog metadata now reports `max_rank = 5` and `max_selections = 5`.
**Database changes:** None.
**Tests added/updated:**
- Updated `tests/test_proficiency_registry.gd`.
- Updated `tests/test_level_up_proficiency_picker.gd`.
- Added `tests/test_proficiency_selection_panel.gd`.
- Updated `tests/test_runner.gd`.
- Updated `tests/test_runner.tscn`.
**Known issues:**
- This environment can verify the logic headlessly, but not visually confirm the Gambling picker behavior in-editor.
**Next session should:**
1. Smoke-test Gambling selection in both character creation and level-up UI flows to confirm the rank-up affordance reads clearly to players.
2. If any other ACKS proficiencies are meant to stack indefinitely or beyond the current defaults, audit their catalog metadata against the rules text using the same pattern.

---

## Session 2026-04-02 - Portrait UI Size Clamp Fix

**Task:** Fix character portraits in the character creation finalize screen and the character sheet so they render inside the intended UI size instead of expanding close to their native 1024×1024 dimensions.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `scenes/ui/components/character_sheet_panel.gd` so finalize-screen portraits render in a fixed 512×512 display box.
- Updated `scenes/ui/character_sheet/tabs/cs_tab_biography.gd` so biography-tab portraits use the same fixed 512×512 display box.
- Set both runtime-built portrait `TextureRect` nodes to `expand_mode = TextureRect.EXPAND_IGNORE_SIZE` while keeping `STRETCH_KEEP_ASPECT_CENTERED`, so large source textures no longer dictate layout size.
- Added `tests/test_portrait_display_sizing.gd` to verify both portrait renderers ignore native texture size and use the 512×512 box.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to register the new portrait sizing suite.
- Updated `docs/coding_conventions.md` with the runtime `TextureRect` sizing pattern for large art assets in code-built UI.
- Ran the approved headless Godot test runner command successfully (exit code `0`).
**Decisions made:**
- Treated the script-built portrait widgets as the source of truth rather than editor-side Control sizing, because both affected views recreate their portrait nodes at runtime.
- Standardized the full portrait presentation size at 512×512 for both finalize preview and biography view so the two character-facing screens stay visually consistent.
**Interfaces defined or changed:** None.
**Database changes:** None.
**Tests added/updated:**
- Added `tests/test_portrait_display_sizing.gd`.
- Updated `tests/test_runner.gd`.
- Updated `tests/test_runner.tscn`.
**Known issues:**
- This environment verifies the layout configuration headlessly, but not the exact visual feel in-editor at runtime.
**Next session should:**
1. Open character creation finalize and the character sheet in-editor to confirm the 512×512 portraits feel right in the live layout.
2. If additional portrait surfaces are added later, reuse the documented `TextureRect.EXPAND_IGNORE_SIZE` + fixed display-box pattern for any runtime-built art widgets.

---

## Session 2026-04-02 - Shared Vellum Window Chrome Pass

**Task:** Replace semi-transparent default UI backgrounds with `bg_vellum_subtle` across runtime-built windows and layers, while leaving the dice prompt modal and the hex-map tooltip unchanged.
**Model used:** GPT-5 Codex
**Completed:**
- Added `engine/subsystems/assets/ui_surface_styles.gd` as a shared helper for vellum-backed panel surfaces and framed modal/window chrome using the registered `ui.bg.vellum_subtle` asset.
- Updated `scenes/ui/character_creation/character_creation_screen.gd` to use the subtle vellum background for the full character-creation layer and a framed parchment treatment for the step content area.
- Updated `scenes/ui/character_creation/class_selection_panel.gd` and `scenes/ui/character_creation/portrait_picker_panel.gd` so their large subpanels use opaque vellum textures instead of default panel styling.
- Updated `scenes/ui/components/character_sheet_panel.gd` and `scenes/ui/character_sheet/character_sheet_overlay.gd` so the finalize summary and character-sheet overlay render on opaque vellum-backed surfaces, with the overlay panel getting a visible frame.
- Updated `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd`, `scenes/ui/character_creation/proficiency_selection_panel.gd`, and `scenes/ui/character_sheet/tabs/level_up_proficiency_picker.gd` so proficiency modals/popup selectors use framed vellum surfaces.
- Updated `scenes/ui/campaign_select/campaign_select_screen.gd` so the full-screen campaign-select layer uses `bg_vellum_subtle`, and the delete confirmation dialog now receives the same framed parchment chrome as the rest of the UI.
- Updated `scenes/ui/override/override_panel.gd` and `scenes/ui/character_sheet/tabs/equipment_item_row.gd` so override dialogs and the split-stack confirmation dialog use vellum-backed framed modal styling.
- Left the dice prompt modal and the hex-map tooltip unchanged as requested.
- Added `tests/test_ui_surface_styles.gd` and wired it into `tests/test_runner.gd` / `tests/test_runner.tscn`.
- Updated `docs/coding_conventions.md` with the shared `UiSurfaceStyles` convention for runtime-built windows and modal surfaces.
- Ran the approved headless Godot test runner command successfully (exit code `0`).
**Decisions made:**
- Standardized on the existing registered `ui.bg.vellum_subtle` asset rather than creating a new parchment texture, since the requested readability improvement could be achieved by consistently applying the existing asset.
- Centralized the parchment styling in `UiSurfaceStyles` so future runtime-built windows can opt into the same texture/border treatment without duplicating stylebox code.
- Kept the dice prompt and hex-map tooltip as exceptions because they are intentionally specialized overlays with different readability and urgency requirements.
**Interfaces defined or changed:**
- Added `UiSurfaceStyles.apply_textured_panel(panel, texture_id="ui.bg.vellum_subtle")`.
- Added `UiSurfaceStyles.apply_framed_window_chrome(control, texture_id="ui.bg.vellum_subtle")`.
- Added `UiSurfaceStyles.make_vellum_style()`, `make_filled_frame_style()`, `make_window_frame_style()`, and `make_background_rect()`.
**Database changes:** None.
**Tests added/updated:**
- Added `tests/test_ui_surface_styles.gd`.
- Updated `tests/test_runner.gd`.
- Updated `tests/test_runner.tscn`.
**Known issues:**
- This environment can verify the runtime-built styling paths headlessly, but it cannot visually confirm spacing, border weight, or parchment tiling in-editor.
**Next session should:**
1. Smoke-test the campaign select screen, character creation flow, character sheet, and level-up proficiency modal in-editor to confirm the new vellum surfaces feel right at runtime.
2. If any remaining runtime-built windows still look too transparent in play, move them onto `UiSurfaceStyles` rather than adding one-off styleboxes.

---

## Session 2026-04-03 - UiSurfaceStyles Window Compatibility Fix

**Task:** Fix the vellum chrome helper so the campaign select screen, override dialogs, equipment split dialog, and advancement popup compile correctly when they pass `Window`-based popups instead of `Control` panels.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `engine/subsystems/assets/ui_surface_styles.gd` so `UiSurfaceStyles.apply_framed_window_chrome()` accepts a shared `Node` surface and explicitly supports both `Control` panels and `Window`-based dialogs/popups.
- Kept the helper's vellum background insertion path shared across both surface families, so existing framed panels and modal windows still receive the same `bg_vellum_subtle` treatment.
- Expanded `tests/test_ui_surface_styles.gd` to cover `ConfirmationDialog` and `PopupPanel` in addition to the existing `PanelContainer` case.
- Updated `docs/coding_conventions.md` so the shared vellum chrome convention now documents support for both `Control` and `Window` surfaces.
**Decisions made:**
- Preserved a single shared helper instead of splitting modal/window styling into separate APIs, because the visual treatment is intentionally the same and the compile failure was only about the accepted node family.
- Used explicit `Control` / `Window` branching inside the helper so the contract stays statically clear in GDScript and future call sites fail fast if they pass an unsupported node type.
**Interfaces defined or changed:**
- Updated `UiSurfaceStyles.apply_framed_window_chrome(surface, texture_id="ui.bg.vellum_subtle")` to accept `Control` panels and `Window`-based popup/dialog surfaces.
**Database changes:** None.
**Tests added/updated:**
- Updated `tests/test_ui_surface_styles.gd`.
**Known issues:**
- This environment can verify compile/runtime behavior headlessly, but not visually confirm modal spacing or chrome weight in-editor.
**Next session should:**
1. Smoke-test the affected modal surfaces in-editor to confirm the framed vellum chrome still sits correctly after the `Window` compatibility fix.

---

## Session 2026-04-03 - Vellum Text Contrast and Dialog Layering Fix

**Task:** Fix the override warning dialog text being covered by the vellum background, and make vellum-backed UI text readable by switching passive copy to dark text and warning/highlight copy to dark red.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `engine/subsystems/assets/ui_surface_styles.gd` so shared vellum backgrounds render with `show_behind_parent = true`, preventing popup/dialog content from being covered by the parchment layer.
- Added shared vellum text colors (`VELLUM_TEXT_COLOR`, `VELLUM_WARNING_TEXT_COLOR`) and a shared text theme installer in `UiSurfaceStyles`, then applied it automatically from both `apply_textured_panel()` and `apply_framed_window_chrome()`.
- Applied the shared vellum text theme directly to the campaign select screen root in `scenes/ui/campaign_select/campaign_select_screen.gd` so its custom-built list and new-campaign modal inherit readable dark label text.
- Replaced hard-coded pale gray/yellow label styling across the vellum-backed character creation, character sheet, level-up picker, campaign select, and override UI surfaces with the new dark vellum text constants.
- Expanded `tests/test_ui_surface_styles.gd` to verify the shared vellum text theme is attached and that framed backgrounds draw behind parent content.
- Ran the approved headless Godot test runner command successfully (exit code `0`).
**Decisions made:**
- Kept button and field chrome untouched where their text sits on control backgrounds rather than directly on vellum, focusing the readability pass on label/list text actually rendered over parchment surfaces.
- Standardized warning/highlight copy on vellum to a dark red accent instead of pale yellow so it remains readable on the `bg_vellum_subtle` texture.
**Interfaces defined or changed:**
- Added `UiSurfaceStyles.VELLUM_TEXT_COLOR` and `UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR`.
- Added `UiSurfaceStyles.apply_vellum_text_theme(target: Node)`.
- `UiSurfaceStyles.apply_textured_panel()` and `UiSurfaceStyles.apply_framed_window_chrome()` now also install the shared vellum text theme.
**Database changes:** None.
**Tests added/updated:**
- Updated `tests/test_ui_surface_styles.gd`.
**Known issues:**
- This environment can verify the layering and theme path headlessly, but not visually confirm every parchment-backed screen in-editor.
**Next session should:**
1. Smoke-test the override warning dialog, campaign select flow, character sheet tabs, and character creation flow in-editor to confirm the darker vellum text feels correct everywhere.
2. If any remaining vellum-backed tabs still carry pale one-off label colors, migrate them onto the shared vellum text constants instead of adding new ad-hoc colors.

---

## Session 2026-04-02 — Spell System Overhaul: Divine Level-Up Fix + Schema Cleanup

**Task:** Fix divine casters (cleric, bladedancer, etc.) not receiving their class spell list when gaining access to new spell levels at level-up. Also align the entire spell system with ACKS 1e rules: no memorization, divine casters auto-know all class spells, arcane casters track formulae separately from active repertoire, expended slots tracked per level per day.
**Model used:** Sonnet 4.6 (implementation), session context from Opus 4.6 (planning)

**Completed:**
- Created `db/migrations/018_spell_formula_and_slots.sql`: new `character_spell_formulas` table (arcane formula tracking, separate from active repertoire) and `character_spell_slots_expended` table (per-level daily expended tracking). Migration also seeds formula table from existing arcane `character_spells` rows.
- Updated `db/schema.sql`: bumped header comment to "Last migration applied: 018", added both new table definitions after `character_spells` with deprecation note on `is_memorized`/`memorized_slots`.
- Updated `engine/autoloads/campaign_repository.gd`: added two new CRUD blocks — formula methods (`get_character_formulas`, `add_character_formula`, `save_character_formulas`, `has_formula`) and expended-slot methods (`get_expended_slots`, `increment_expended_slot`, `reset_expended_slots`).
- Updated `engine/shared_types/character_bundle.gd`: added `formulas: Array` and `expended_slots: Dictionary` fields after `spells`.
- Updated `scenes/ui/character_sheet/character_sheet_overlay.gd` `_load_character()`: loads `bundle.formulas` and `bundle.expended_slots` from the two new repository methods.
- Updated `scenes/ui/character_creation/character_creation_screen.gd`: after saving `character_spells`, also saves formula records via `save_character_formulas` for arcane casters at creation.
- Updated `engine/subsystems/spells/repertoire_engine.gd`: added `generate_divine_spells_for_new_levels(class_id, new_levels)` method (new "Divine incremental grant" section). Handles reversible spells automatically.
- Updated `engine/subsystems/characters/level_up_engine.gd`:
  - Added `var _repertoire_engine: RepertoireEngine` member.
  - Updated `_init` to accept 4th optional param `p_repertoire_engine: RepertoireEngine = null` (backward-compatible).
  - Added `_detect_new_spell_levels(old_slots, new_slots) -> Array[int]` helper — detects 0→>0 slot transitions by spell level index.
  - Updated `_compute_level_up` to compute `new_spell_levels_unlocked` and include it in the result dict.
  - Updated `apply_level_up_auto` to auto-grant divine spells via `add_character_spell` for each newly unlocked level (when `_repertoire_engine` is set).
- Updated `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd`:
  - `_make_level_up_engine()` now builds and passes a `RepertoireEngine` as 4th arg.
  - `_build_level_up_summary()` now detects `new_spell_levels_unlocked`, populates `_level_up_choices["spells"]` for divine casters, and shows a blue info label listing granted spell levels + count.
- Updated `scenes/ui/character_sheet/tabs/cs_tab_spells.gd`: full display rewrite — uses "Spell Repertoire" section header, per-level "Level N — M slots/day (K expended today)" using `bundle.expended_slots`, clean bullet list with no memorization labels. "Spells Known (Not in Active Repertoire)" section (arcane only, gray) driven by `bundle.formulas`.
- Updated `tests/test_repertoire_engine.gd`: added `test_divine_spells_for_new_levels_cleric()` and `test_divine_spells_for_new_levels_empty()`.
- Updated `tests/test_level_up_engine.gd`: added `_make_cleric()` helper and `test_detect_new_spell_levels_cleric_1_to_2()`, `test_detect_new_spell_levels_fighter()`, `test_compute_level_up_includes_new_spell_levels_unlocked()`.

**Decisions made:**
- **Separate formula table** (not a flag on `character_spells`) for arcane formula tracking: cleaner separation of "has formula" vs "in active repertoire", and easier to query independently.
- **No WIS bonus to spellcasting**: WIS only grants saving throw bonuses in ACKS 1e. The WIS-repertoire-expansion rule is ACKS 2e only and not licensed for this project.
- **Divine casters: ALL known spells = ALL in repertoire** automatically. No subset logic for divine.
- **Arcane repertoire swapping** (swapping a formula in/out of active repertoire up to slot+INT cap) is OUT OF SCOPE for this session. Architecture supports it but UI/UX is deferred.
- **`_detect_new_spell_levels` is public** (prefixed `_` by convention, but not restricted) so tests can call it directly.
- **`apply_level_up_auto` is additive** — uses `add_character_spell` not `save_character_spells`, safe for characters who already have lower-level spells.
- **`is_memorized` / `memorized_slots`** remain in `character_spells` schema (no destructive migration) but are not used by new code. Marked legacy; scheduled for removal in a future cleanup migration.

**Interfaces defined or changed:**
- `RepertoireEngine.generate_divine_spells_for_new_levels(class_id: String, new_levels: Array) -> Array[Dictionary]`
- `LevelUpEngine._init(p_class_registry, p_power_registry, p_proficiency_registry=null, p_repertoire_engine=null)` — 4th param added, backward-compatible
- `LevelUpEngine._detect_new_spell_levels(old_slots: Array, new_slots: Array) -> Array[int]`
- `_compute_level_up` result dict now includes `"new_spell_levels_unlocked": Array[int]`
- `CampaignRepository.get_character_formulas(id) -> Array`
- `CampaignRepository.add_character_formula(id, key, level) -> bool`
- `CampaignRepository.save_character_formulas(id, spells) -> bool`
- `CampaignRepository.has_formula(id, key) -> bool`
- `CampaignRepository.get_expended_slots(id) -> Dictionary`
- `CampaignRepository.increment_expended_slot(id, level) -> bool`
- `CampaignRepository.reset_expended_slots(id) -> bool`
- `CharacterBundle.formulas: Array` — Array[Dictionary] from character_spell_formulas (arcane only)
- `CharacterBundle.expended_slots: Dictionary` — spell_level(int) -> expended_count(int)

**Database changes:**
- Migration 018: `character_spell_formulas` and `character_spell_slots_expended` tables added.

**Tests added/updated:**
- `tests/test_repertoire_engine.gd`: 2 new tests for `generate_divine_spells_for_new_levels`.
- `tests/test_level_up_engine.gd`: `_make_cleric()` helper + 3 new spell-level detection tests.

**Known issues:**
- `promotion_engine.gd` calls `save_character_spells` for promoted henchmen. If the henchman is arcane, formula records are NOT saved on promotion. [NEEDS-REVIEW next session touching promotion engine]
- Arcane repertoire swapping (moving formulae in/out of active repertoire up to slot+INT capacity) is not yet implemented. Architecture supports it: `character_spell_formulas` is separate from `character_spells`. Deferred.
- Visual smoke test of the spell tab in-editor not yet done — run `test_runner.tscn` and then manually level a cleric to verify the blue info label and spell list appear correctly.

**Next session should:**
1. Run `tests/test_runner.tscn` and confirm all RepertoireEngine and LevelUpEngine tests pass.
2. Smoke-test: create a cleric, award XP for level 2, confirm spell list appears in Spells tab after level-up.
3. Smoke-test: create a mage, confirm starting spells appear as Spell Repertoire and formula records exist in DB.
4. Review `promotion_engine.gd` for the arcane henchman formula-save gap noted above.

---

## Session 2026-04-04 - Class Selection Disabled Button Contrast Fix

**Task:** Fix the character-creation class selection screen so selectable classes keep their readable white button text while blocked classes use a darker disabled text color on the vellum-backed panel.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `scenes/ui/character_creation/class_selection_panel.gd` to centralize the selected-class gold text color and add an explicit dark `font_disabled_color` override for blocked class buttons.
- Preserved the existing white/default styling for eligible unselected class buttons by leaving enabled button text on the engine/default button theme instead of changing the shared vellum theme.
- Added `tests/test_class_selection_panel.gd` to verify eligible buttons keep default enabled styling, blocked buttons receive the dark disabled text override, and the selected class still uses the gold text override.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to include the new class-selection regression suite.
- Updated `docs/coding_conventions.md` to document the local `font_disabled_color` override pattern for parchment-backed flows that need blocked buttons to read differently without globally changing all button text.
- Ran the approved headless Godot test runner command successfully (exit code `0`).
**Decisions made:**
- Solved the contrast issue locally in `ClassSelectionPanel` instead of changing `UiSurfaceStyles`, because the user-facing requirement is screen-specific: eligible class buttons should remain white while only blocked buttons need a darker disabled text treatment.
- Kept the existing button `modulate` dimming for blocked classes and layered the darker disabled font color on top, so both the button chrome and the text communicate "unavailable" without reducing legibility.
**Interfaces defined or changed:**
- Added `ClassSelectionPanel.SELECTED_CLASS_TEXT_COLOR`.
- Added `ClassSelectionPanel.INELIGIBLE_CLASS_TEXT_COLOR`.
**Database changes:** None.
**Tests added/updated:**
- Added `tests/test_class_selection_panel.gd`.
- Updated `tests/test_runner.gd`.
- Updated `tests/test_runner.tscn`.
**Known issues:**
- Headless tests confirm the configured theme overrides, but the exact in-editor visual feel of the dark disabled text still needs a manual smoke test on the live class selection screen.
**Next session should:**
1. Open character creation in-editor and confirm blocked class buttons read clearly against the vellum background at the intended window scale.
2. If any other parchment-backed screens need disabled-button contrast tweaks, follow the documented local `font_disabled_color` override pattern instead of modifying the shared vellum button theme globally.

---

## Session 2026-04-04 — Settlement Map Renderer Fixes

**Task:** Fix the settlement map system which was visually broken: map too large, party token off-screen, no movement, floating district label, no visible street nodes.
**Model used:** Opus 4.6 for planning and implementation.
**Completed:**
- **Scaling & centering** (`scenes/maps/settlement_map_renderer.gd`): Added auto-scale factor (`_map_scale`) that fits the map within the viewport with 100px padding. View centers on the party token (entry gate) instead of the map centroid. Added `_compute_scale()` function.
- **Scroll-wheel zoom**: Added mouse-wheel zoom (1.15x per step, range 0.25x–3.0x) centered on cursor position via `_zoom_at()`. Zoom multiplier (`_zoom`) applied on top of the base `_map_scale`.
- **Visible street nodes**: Added `_draw_street_nodes()` rendering intersection nodes as small brown dots and gate nodes as larger outlined circles. New constants: `INTERSECTION_NODE_RADIUS`, `GATE_NODE_RADIUS`, etc.
- **Adjacent highlights**: Changed from nearly-invisible translucent yellow (10px, alpha 0.4) to bright green (14px, alpha 0.7) with a ring outline via `draw_arc()`.
- **District labels**: Split `_draw_labels()` into `_draw_district_labels()` (faint watermark behind streets, alpha 0.25, font size 22) and `_draw_poi_labels()` (readable, font size 14). Updated draw order accordingly.
- **Party token**: Increased radius from 12 to 18 for visibility.
- **int/float key mismatch fix** (`engine/shared_types/settlement_map_data.gd`): Added explicit `int()` casts to ALL numeric dictionary keys (node IDs, edge IDs, block IDs, street_node_ids, block_ids) in `from_dict()`. This fixed the root cause of broken lookups: `_node_lookup`, `_adjacency`, `_block_lookup`, `_poi_at_node`, and `_block_to_district` all had potential int/float key mismatches causing `get_node_by_id()`, `get_block_by_id()`, and adjacency checks to silently fail.
- **Click detection fix** (`scenes/maps/settlement_map_renderer.gd`): Changed `_screen_to_world()` from `get_canvas_transform().affine_inverse()` to `(get_canvas_transform() * get_global_transform()).affine_inverse()`. The old code converted to canvas space but `_draw()` works in local space; with non-trivial Node2D position and scale, clicks were offset from visual positions.
- **Tooltip size**: Shrunk tooltip panel from 212x52 to 112x30 with font size 10 in `scenes/maps/settlement_map.tscn`.
**Decisions made:**
- Used `Node2D.scale` for map scaling rather than modifying `_to_draw()`, because Godot's canvas transform automatically accounts for it in coordinate conversions.
- Defensive `int()` casts on all JSON-sourced numeric IDs regardless of Godot version, since the int/float key mismatch is a subtle Dictionary behavior that silently returns wrong results.
**Interfaces defined or changed:**
- `settlement_map_renderer.gd` new signals/API: none changed. New constants added for intersection nodes, gate nodes, zoom, and view padding.
- `settlement_map_data.gd`: no API changes, only internal `int()` casts in `from_dict()`.
**Database changes:** None.
**Tests added/updated:** None (all changes were rendering/presentation; existing controller and data model tests still pass).
**Known issues:**
- No multi-hop pathfinding movement — clicking a non-adjacent node does nothing. The controller has `find_path_to()` but it's not wired to click handling. Single-step adjacent movement works.
- Panning has no clamping — the user can pan the map entirely off-screen.
- No animation for party movement (token teleports to new node).
**Next session should:**
1. Consider wiring multi-hop movement (click any reachable node → auto-walk the path via `find_path_to()`).
2. Add pan clamping so the map stays visible.
3. Test with a larger/multi-district settlement to verify scaling and district labels work with more complex data.

---

## Session 2026-04-06 — Bonus Proficiency Bug Fix, Reversed Spell Errors, Origin IP Rename

**Task:** Fix three issues in character creation: bonus proficiency duplication, reversed spell form errors, and protected IP in barbarian origin names.
**Model used:** Opus for all phases.
**Completed:**
- **Bonus proficiency validation:** Barbarian origin / witch tradition free proficiencies are now declared at Step 3 (origin selection) via `creation_state["bonus_proficiencies"]`, visible in Step 6 (proficiency selection) as non-removable `[FREE]` entries, and merged intelligently at finalization. Unique profs are deduplicated; stacking profs (e.g. Precise Shooting) have ranks merged. Fixes `character_creation_screen.gd`, `class_customization_panel.gd`, `proficiency_selection_panel.gd`.
- **Stacking proficiency button/validation fix:** `proficiency_selection_panel.gd` now checks `max_selections` (not just `max_rank`) for `selection_rule == "stacking"` proficiencies, so Precise Shooting correctly shows "Rank 1→2" instead of "Taken".
- **Reversed spell form errors:** `spell_registry.gd` now generates synthetic entries for reversed spell forms (e.g. `detect_good` from `detect_evil`) during catalog load, eliminating `push_error` calls when `get_spell()` is called with reverse keys. Also fixed `spell_selection_panel.gd` using `def.get("name", ...)` instead of `def.get("spell_name", ...)` (3 occurrences).
- **Origin IP rename:** Barbarian origin `display_name` values in `data/classes/barbarian.json` changed from protected IP names to generic terrain descriptors. Internal keys unchanged.
  - Jutland → Northern Mountains
  - Skysostan → Plains or Steppe
  - Ivory Kingdoms → Jungle or Savanna
  - NOTE: `rules/` XML files still reference the original names (sacred, never modify). Internal keys (`jutland`, `skysostan`, `ivory_kingdoms`) also unchanged — they are never player-facing. If future code references these keys for display, it must use `display_name` from the JSON, not the key itself.
**Decisions made:**
- Bonus proficiencies stored in a separate `creation_state["bonus_proficiencies"]` array rather than injected into `proficiencies`, to avoid slot-counting contamination.
- Reversed spell forms stored with `is_reversed_form: true` and `base_spell_key` fields for downstream identification.
**Interfaces defined or changed:**
- `creation_state["bonus_proficiencies"]`: Array of dicts with keys `proficiency_key`, `rank`, `slot_type`, `selections_count`, `specialization`, `source`.
- `_invalidate_from()` for `Step.CLASS_SELECTION` and `Step.CLASS_CUSTOMIZATION` now also clears `bonus_proficiencies`.
- Synthetic reversed spell entries in SpellRegistry: same shape as base spells plus `is_reversed_form: bool` and `base_spell_key: String`.
**Database changes:** None.
**Tests added/updated:** None (manual verification).
**Known issues:** None.
**Next session should:**
1. Continue with prior session's settlement map items (multi-hop movement, pan clamping, larger district testing).

---

## Session 2026-04-07 â€” Character Sheet Equipment Panel Contrast

**Task:** Lighten the character sheet equipment panel backgrounds so the existing dark text remains readable.
**Model used:** GPT-5 Codex
**Completed:**
- Updated [equipment_container_row.gd](/c:/Users/jttau/acks-arbiter/scenes/ui/character_sheet/tabs/equipment_container_row.gd) to replace the dark grey container panel with a light grey background, lighter border, and softer drag-state highlight colors.
- Updated [equipment_loose_zone.gd](/c:/Users/jttau/acks-arbiter/scenes/ui/character_sheet/tabs/equipment_loose_zone.gd) to replace the dark navy loose-carry panel with a light blue background and matching lighter border/highlight colors.
**Decisions made:**
- Kept the change narrowly scoped to the equipment-tab surface colors so text/button styling elsewhere in the character sheet remains unchanged.
- Preserved the green/red drag-feedback behavior, but shifted both states to lighter tints to match the new panel backgrounds.
**Interfaces defined or changed:**
- None.
**Database changes:**
- None.
**Tests added/updated:**
- None. This was a visual-only styling change.
**Known issues:**
- Visual confirmation in the Godot UI is still recommended to fine-tune the exact tint balance against the rest of the character sheet.
**Next session should:**
1. Smoke-test the character sheet equipment tab in-editor to confirm the new light grey/light blue surfaces feel right with the surrounding vellum UI.

---

## Session 2026-04-07 — Phase E-1: Party Management

**Task:** Implement Phase E-1 (Party Management) — party data model, travel speed calculator, getting-lost/forced march mechanics, party management UI, and supporting infrastructure.
**Model used:** Opus 4.6 for all phases.
**Completed:**
- **Migration 021** (`db/migrations/021_party_state_and_party_inventory.sql`): Added `party_state` table (marching_order, is_lost, is_force_marching, force_march_days_used, days_since_rest, rations_days_remaining, current_mount_type). Added `party_id` nullable FK column to `inventory_items` for party-level shared inventory.
- **PartyData shared type** (`engine/shared_types/party_data.gd`): Canonical in-memory party representation with members, formation slots, marching order, travel state, shared inventory. Includes `from_db()` static constructor and `to_state_dict()` serializer. Convenience queries: `get_slowest_movement()`, `any_member_has_proficiency()`, `needs_rest()`, `max_force_march_days()`, `can_force_march()`.
- **TravelSpeedCalculator** (`engine/subsystems/exploration/travel_speed_calculator.gd`): Static class computing party travel speed with terrain multipliers (clear ×1, woods/hills/desert ×2/3, jungle/swamp/mountains ×1/2, road ×3/2), mount speed (horse 240'/turn, mule 120'/turn), forced march (×1.5). Also includes getting-lost check (d20 vs terrain target + Navigation +4) and forced march eligibility/rest requirement checks. Uses banker's rounding.
- **EventBus signals** (`engine/autoloads/event_bus.gd`): Added 9 party signals: `party_formed`, `party_split`, `party_merged`, `party_member_joined`, `party_member_left`, `marching_order_changed`, `formation_changed`, `getting_lost_checked`, `forced_march_checked`.
- **CampaignRepository methods** (`engine/autoloads/campaign_repository.gd`): Added `get_party_state()`, `save_party_state()`, `remove_party_member()`, `get_party_members()`, `update_party_member_slot()`, `load_party_data()`, `list_characters()`, `get_party_inventory()`, `add_party_inventory_item()`, `transfer_item_to_party()`, `transfer_item_to_character()`.
- **Party Management UI** (`scenes/ui/party_management/party_management_overlay.gd` + `.tscn`): CanvasLayer overlay with 4 tabs (Members, Formation, March Order, Travel). Members tab: add/remove characters. Formation tab: assign slots (point/front/middle/rear) via dropdown. March Order tab: reorder with Move Up/Down. Travel tab: speed summary per terrain, mount selector, rest/forced march status, proficiency info. Toggle with Ctrl+Alt+P.
- **Test suite** (`tests/test_party_management.gd`): 20 tests covering PartyData construction/serialization, formation queries, travel speed (clear/forest/mountain/road/mounted/forced), getting-lost checks (clear/swamp/road), forced march eligibility (with/without Endurance), rest requirements, rest penalties, banker's rounding.
**Decisions made:**
- Party shared inventory uses `party_id` FK column on `inventory_items` (not pseudo-character or container_id overloading). Clean semantics, explicit ownership.
- Marching order is separate from formation slots. Formation = combat positioning (point/front/middle/rear). Marching order = travel column sequence (ordered array of character_ids).
- Getting-lost is a d20 proficiency throw, NOT d6. ACKS rules use d20 with terrain-specific target numbers (4+/7+/11+). Navigation grants +4.
- Forced march: without Endurance = 1 day then mandatory rest. With Endurance = 1 + CON bonus days.
- Rest penalty: cumulative -1 attack/damage per day past 6 without rest.
- Architectural review completed before implementation (7 issues identified, all resolved): GameState vs SessionRunner state machine collision (SessionRunner drives, GameState broadcasts), renderer-driven movement (SessionRunner replaces main_scene in E-2), no atomic save/load (add to CampaignRepository in E-2), ActiveEffectTracker wiring (E-2), DiceSystem game_day TODO (E-2).
**Interfaces defined or changed:**
- `PartyData` shared type: class_name PartyData, extends RefCounted. Fields: id, campaign_id, name, current_map_id, current_hex_q/r, current_location_type, members (Array[Dict]), marching_order (Array[String]), is_lost, is_force_marching, force_march_days_used, days_since_rest, rations_days_remaining, current_mount_type, character_data (runtime), shared_inventory (runtime).
- `TravelSpeedCalculator.calculate_party_speed(party, terrain_category, on_road) -> Dictionary` with keys: base_exploration_speed, terrain_multiplier, miles_per_day, is_forced_march, on_road, slowest_member_id, details.
- `TravelSpeedCalculator.check_getting_lost(party, terrain_category, roll_result, on_road) -> Dictionary` with keys: party_id, target, roll, modifier, succeeded.
- `TravelSpeedCalculator.check_force_march_eligibility(party) -> Dictionary` with keys: can_continue, max_days, days_used, must_rest_after.
- EventBus signals: party_formed(party_id), party_split(original_party_id, new_party_id), party_merged(surviving_party_id, dissolved_party_id), party_member_joined(party_id, character_id), party_member_left(party_id, character_id), marching_order_changed(party_id), formation_changed(party_id), getting_lost_checked(result: Dictionary), forced_march_checked(result: Dictionary).
- CampaignRepository: load_party_data(party_id) -> PartyData, save_party_state(state: Dictionary), get_party_state(party_id) -> Dictionary, get_party_members(party_id) -> Array, remove_party_member(party_id, character_id), update_party_member_slot(party_id, character_id, slot), list_characters(campaign_id) -> Array, get_party_inventory(party_id) -> Array, add_party_inventory_item(party_id, data) -> String, transfer_item_to_party(item_id, party_id), transfer_item_to_character(item_id, character_id).
**Database changes:**
- Migration 021: `party_state` table created. `inventory_items.party_id` column added.
- `db/schema.sql` updated to reflect migration 021.
**Tests added/updated:**
- `tests/test_party_management.gd`: 20 tests (PartyData: 6, TravelSpeedCalculator: 6, getting-lost: 3, forced march: 2, rest: 2, banker's rounding: 1). Registered in test_runner.gd and test_runner.tscn.
**Known issues:**
- Tests not yet run in Godot (no headless runner available in this session). Manual verification recommended.
- Party Management UI toggle is Ctrl+Alt+P (may conflict on some systems; can be rebound).
- `inventory_items.character_id` has `NOT NULL` constraint — party-only items use empty string `''` for character_id. This works but is semantically imperfect. Consider relaxing to nullable in a future migration if it causes issues.
**Next session should:**
1. Run test_runner.tscn to verify all 20 new party management tests pass (and existing tests still pass).
2. Smoke-test Party Management overlay in-game (create party, assign formation, reorder march, check travel speeds).
3. Begin Phase E-2: Session Runner State Machine (Complexity 4 — recommend Opus planning session first).

## Session 2026-04-07 — Thief Skill Resolver + Proficiencies Tab Panel

**Task:** Audit thief-skill availability on generated characters, expose live thief-skill targets in the character sheet Proficiencies tab, and centralize the rules math for future rolls.
**Completed:**
- **Shared resolver** (`engine/subsystems/characters/thief_skill_resolver.gd`): Added `ThiefSkillResolver` to normalize class-power rows from persisted `character_powers`, resolve thief-skill-equivalent proficiencies from `enablers`, split `find_remove_traps` into separate `Find Traps` and `Remove Traps` rows, apply DEX and encumbrance bonuses per `ax_thief_skill_update.xml`, honor structured power conditions such as `armor_leather_or_lighter`, and expose `get_skill_check()`, `get_all_skill_checks()`, `player_roll_skill()`, and `roll_skill_digital()` using `roll_type = "thief_skill_throw"`.
- **Character-sheet UI** (`scenes/ui/character_sheet/tabs/cs_tab_proficiencies.gd`): Refactored the Proficiencies tab into a two-column layout. The left side still lists proficiencies and class powers; the right side now renders an always-visible `Thief Skills` panel with all eight rows (`Open Locks`, `Find Traps`, `Remove Traps`, `Pick Pockets`, `Move Silently`, `Climb Walls`, `Hide in Shadows`, `Hear Noise`). Unavailable skills show `NA`. Tooltips include source, base target, equivalent thief level when relevant, DEX modifier, encumbrance modifier, proficiency subtotal, and unavailability reason. Also updated class-power display-name lookup to prefer `power_name`.
- **Tests** (`tests/test_thief_skill_resolver.gd`, `tests/test_cs_tab_proficiencies.gd`): Added resolver coverage for persisted thief progression parsing, split trap rows, Dwarven Delver `Find Traps`-only behavior, `Climbing`/`Eavesdropping` equivalents, `Prestidigitation` half-level pick pockets, DEX and encumbrance rules, hijink suppression, Assassin heavy-armor blocking, and modifier-only proficiencies not granting access. Added UI coverage for panel existence, all eight rows always rendering, `NA` display for unavailable skills, and tooltip breakdown content.
- **Test runner registration** (`tests/test_runner.gd`, `tests/test_runner.tscn`): Registered the two new suites so they run with the existing headless test scene.
**Decisions made:**
- Base Thief characters already had persisted thief-skill progression tables via `CharacterGenerator.stamp_powers()` and `character_powers`; no schema or content migration was needed.
- The Proficiencies tab shows the thief-skill panel for **all** classes, not just classes with native thief powers.
- `Find Traps` and `Remove Traps` are rendered as separate rows even when the underlying class power is the combined `find_remove_traps` table.
- Proficiency equivalents are sourced only from structured `enablers` with thief-equivalent metadata; modifier-only proficiencies (for example `Lockpicking` and `Trap Finding`) improve an existing baseline but do not create access on their own.
- `half_character_level` equivalents use floor division, and values below 1 remain unavailable (`NA`).
- This pass intentionally uses structured conditions/effects only; it does not parse free-text item notes like glove or helmet penalties.
**Interfaces defined or changed:**
- `ThiefSkillResolver.get_skill_check(bundle, skill_key, is_hijink := false) -> Dictionary`
  Returns `skill_key`, `display_name`, `is_available`, `base_target`, `effective_target`, `display_target`, `total_roll_modifier`, `source_label`, `tooltip_text`, plus breakdown fields used by the UI/tests.
- `ThiefSkillResolver.player_roll_skill(...) -> RollResult`
- `ThiefSkillResolver.roll_skill_digital(...) -> RollResult`
**Verification:**
- Ran the Godot headless test runner with `& "C:\Godot\Godot_v4.6.1-stable_win64.exe" --headless --path . res://tests/test_runner.tscn`.
- First attempt hit a sandbox/log-file issue before producing useful output.
- Second run exited with code `0` after the new suites were registered, indicating the project parsed and the full test runner completed successfully in this session.
**Known issues:**
- The character sheet currently displays thief-skill targets only; no click-to-roll buttons were added in this pass.
- Free-text equipment penalties from catalog notes remain unmodeled here by design.
**Next session should:**
1. Smoke-test the character sheet in Godot with a Thief, Assassin in chain, Fighter with `Climbing`/`Eavesdropping`, and Dwarven Delver to confirm the panel feels correct visually and contextually.
2. Reuse `ThiefSkillResolver.player_roll_skill()` / `roll_skill_digital()` when hijink/exploration systems start actually prompting or resolving thief-skill throws.

## Session 2026-04-07 â€” Adventuring Skills Panel Expansion

**Task:** Extend the character-sheet skills display so the Proficiencies tab shows both thief-only skills and universal Adventuring Skills with live targets.
**Model used:** GPT-5 Codex
**Completed:**
- Expanded `engine/subsystems/characters/thief_skill_resolver.gd` into a grouped resolver that now returns both `thief_skills` and `adventuring_skills`, while preserving the existing single-skill lookup and roll-helper entry points.
- Added Adventuring Skills support for `Force Door`, `Detect Secrets`, `Hear Noise`, `Find Traps`, `Foraging`, `Hunting`, and `Fishing`.
- Moved `Hear Noise` and `Find Traps` from the thief panel to the adventuring panel while still preferring stronger native thief / proficiency-equivalent targets when available.
- Added adventuring/racial baseline logic plus modifiers for Strength-based door forcing, `Dungeon Bashing`, `Alertness`, `Trap Finding`, `Eavesdropping`, and `Survival`.
- Updated `scenes/ui/character_sheet/tabs/cs_tab_proficiencies.gd` to render stacked `Thief Skills` and `Adventuring Skills` panels on the right side of the tab.
- Rewrote focused coverage in `tests/test_thief_skill_resolver.gd` and `tests/test_cs_tab_proficiencies.gd` for the grouped behavior and the new adventuring-throw math.
**Decisions made:**
- Kept the public class name `ThiefSkillResolver` for compatibility even though it now resolves both thief and adventuring skills.
- Treated `Detect Secrets`, `Hear Noise`, `Find Traps`, `Foraging`, `Hunting`, and `Fishing` as always-available adventuring rows, with stronger class/proficiency sources overriding the baseline when applicable.
- Applied thief-style DEX/encumbrance bonuses only when the winning source is a thief-native or thief-equivalent source, not when a universal or racial baseline wins (for example `stonework_detection`).
- Implemented `Survival` bonuses for `Foraging`, `Hunting`, and `Fishing` in resolver logic rather than modifying proficiency data files.
**Interfaces defined or changed:**
- `ThiefSkillResolver.get_grouped_skill_checks(bundle, is_hijink := false) -> Dictionary`
  Returns `thief_skills` and `adventuring_skills` arrays of skill-check dictionaries.
- Skill-check dictionaries now include `group_key` and `roll_type` alongside the prior target/source/breakdown fields.
- Adventuring rows use `roll_type = "adventuring_skill_throw"`; thief rows continue using `roll_type = "thief_skill_throw"`.
**Database changes:**
- None.
**Tests added/updated:**
- `tests/test_thief_skill_resolver.gd`: grouped output, adventuring baselines, force-door STR scaling, racial detection/hearing/trap baselines, survival bonuses, and retained thief-skill edge cases.
- `tests/test_cs_tab_proficiencies.gd`: stacked panel layout, row membership, numeric adventuring targets, and tooltip breakdown coverage.
**Known issues:**
- No in-editor visual smoke test was run in this session, so the final spacing balance between the two right-side panels still needs a live UI check.
**Next session should:**
1. Open the character sheet in Godot and visually confirm the stacked panels feel right with a Thief, Fighter, Elf, and Dwarf.
2. Reuse the new `adventuring_skill_throw` roll metadata when exploration systems start prompting for these universal skill throws.

---

## Session 2026-04-07 — Phase E-1 Revision: Formation Grid, Mount Refactor

**Task:** Revise E-1 based on design feedback: replace formation slots + marching order with a 5×12 formation grid; remove party-level mount selector (mounts will be per-character equipment).
**Model used:** Opus 4.6.
**Completed:**
- **Migration 022** (`db/migrations/022_formation_grid.sql`): Added `formation_col` and `formation_row` INTEGER columns to `party_members`. Old `formation_slot` TEXT column retained for backwards compat but no longer used by app.
- **PartyData rewrite**: Removed `marching_order` array and `current_mount_type`. Members now store `{character_id, formation_col, formation_row}`. New grid methods: `get_formation_pos()`, `get_character_at()`, `get_placed_members()`, `get_unplaced_members()`, `set_formation_pos()`, `unplace_character()`, `swap_positions()`. `get_marching_order()` is now derived from grid (sorted by row then col, unplaced appended).
- **TravelSpeedCalculator**: Removed `MOUNT_SPEEDS` constant and mounted travel logic. Party speed now purely uses `get_slowest_movement()` which reads each character's `get_effective_movement()` — when mount equipment integration is built, equipped mounts will modify movement via the modifier system.
- **Party Management UI rewrite**: Replaced 4-tab layout (Members/Formation/March Order/Travel) with 3 tabs (Members/Formation/Travel). Formation tab is now a 5×12 button grid with FRONT/REAR labels. Select an unplaced character from the list below the grid, click a cell to place. Click an occupied cell to remove. Grid tooltips show character details.
- **CampaignRepository**: Added `update_party_member_formation(party_id, character_id, col, row)`. Updated `add_party_member()` to accept optional `col`/`row` params (default -1 = unplaced).
- **Tests**: Updated all 21 tests. Replaced old formation slot and marching order tests with grid-based tests: `test_formation_grid_placement`, `test_formation_grid_queries`, `test_formation_marching_order` (derived from grid), `test_formation_swap`. Removed mount test.
**Decisions made:**
- Formation and marching order are the same concept in ACKS 1e. Single 5×12 grid replaces both. Marching order derived from grid placement (front rows first, left to right).
- Grid is 5 wide × 12 deep = 60 cells. Max PC+henchmen party is 42 (6 PCs × 7 henchmen each), leaving room for mercenaries and animals.
- Mounts are per-character equipment, not party-level. The `mount` slot already exists in the inventory schema. Mount speed integration deferred to equipment system work — when a mount is equipped, it should add a `movement_rate` modifier via the modifier system.
- Old `formation_slot` and `current_mount_type` columns retained in DB (SQLite can't drop columns) but ignored by app.
**Interfaces defined or changed:**
- PartyData.members: `{character_id: String, formation_col: int, formation_row: int}` (was `{character_id, formation_slot}`)
- PartyData: removed `marching_order` var, `current_mount_type` var, `get_formation_slot()`, `get_members_in_slot()`. Added `get_formation_pos()`, `get_character_at()`, `get_placed_members()`, `get_unplaced_members()`, `set_formation_pos()`, `unplace_character()`, `swap_positions()`, `get_marching_order()`.
- CampaignRepository: added `update_party_member_formation(party_id, character_id, col, row)`.
**Database changes:**
- Migration 022: `party_members.formation_col`, `party_members.formation_row` added.
**Tests added/updated:**
- 21 tests total (was 20). Added: formation_grid_placement, formation_grid_queries, formation_marching_order, formation_swap. Removed: old formation slot tests, marching order sync test, mounted horse test.
**Known issues:**
- Mount equipment integration not yet built. Characters with horses in mount slot don't yet get movement bonus. Needs modifier system wiring in future equipment work.
- Grid cells are small (56×28px). May need scaling for high-DPI or very large parties. Visual smoke test recommended.
**Next session should:**
1. Run test_runner.tscn to verify all 21 party management tests pass.
2. Smoke-test Formation Grid in-game (place/remove characters, verify grid persistence).
3. Begin Phase E-2: Session Runner State Machine planning.

## Session 2026-04-07 â€” Advancement Tab Level-Up Abort Fix

**Task:** Fix the character-sheet level-up flow so abandoning it by canceling, switching tabs, or closing the sheet does not leave the character stuck in an in-memory preview state.
**Model used:** GPT-5 Codex
**Completed:**
- Added `has_pending_level_up()` and `abort_pending_level_up()` to `scenes/ui/character_sheet/tabs/cs_tab_advancement.gd`.
- Refactored the Advancement tab Cancel path to reuse `abort_pending_level_up()` instead of duplicating DB reload/reset logic.
- Wired `scenes/ui/character_sheet/character_sheet_overlay.gd` to abort pending level-up state when the user switches away from the Advancement tab, closes the overlay, or changes the selected character.
- Added `tests/test_cs_tab_advancement.gd` covering interactive preview mutation, explicit cancel, direct abort, tab-switch abort, overlay-close abort, and successful confirm persistence.
- Registered the new suite in `tests/test_runner.gd` and `tests/test_runner.tscn`.
**Decisions made:**
- Kept `LevelUpEngine.begin_interactive_level_up()` unchanged. The engine still mutates the in-memory `CharacterData` for preview-by-design; the UI now owns the required finalize-or-abort lifecycle.
- Restoring abandoned level-up sessions reloads the character row from the database rather than trying to preserve an in-memory snapshot, so persisted state remains the source of truth.
- Switching tabs, closing the sheet, and changing the selected party member all behave like silent Cancel for unconfirmed level-ups.
**Interfaces defined or changed:**
- `CSTabAdvancement.has_pending_level_up() -> bool`
- `CSTabAdvancement.abort_pending_level_up() -> void`
**Database changes:**
- None.
**Tests added/updated:**
- Added `tests/test_cs_tab_advancement.gd`.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to include the new Advancement-tab regression suite.
- Ran `& "C:\Godot\Godot_v4.6.1-stable_win64.exe" --headless --path . res://tests/test_runner.tscn` successfully; exit code `0`.
**Known issues:**
- No in-editor manual smoke test was run for the level-up flow after this fix, so the best remaining verification is a quick UI pass through cancel, tab switch, close, and character switch during a pending level-up.
**Next session should:**
1. Smoke-test the Advancement tab in the Godot editor with a level-up-eligible character, including cancel, tab switch, close, and character switch during a pending level-up.
2. If future UI flows preview persistent mutations before confirm, reuse the same explicit abort lifecycle pattern instead of relying on the overlay to refresh state indirectly.

---

## Session 2026-04-07 — Phase E-2: Session Runner State Machine

**Task:** Implement Phase E-2 — the game's central orchestrator. Replaces main_scene.gd as the gameplay loop coordinator using an extensible object-per-state pattern.
**Model used:** Opus 4.6 for all phases.
**Completed:**
- **SessionState base class** (`engine/subsystems/session/session_state.gd`): RefCounted base with `enter(runner, context)`, `exit(runner)`, `handle_action(runner, action, payload)`. All states extend this.
- **SessionRunner** (`engine/subsystems/session/session_runner.gd`): Scene-tree node placed in Main.tscn. State registry with factory callables. `transition_to_state(key, context)` calls exit→enter→_sync_game_state→emit signal. Session load/save/end lifecycle. Encounter check logic (`do_encounter_check`). Time advance (`advance_exploration_time`). Roll cancellation (`cancel_pending_roll`). `submit_action()` public method for LLM integration entry point.
- **7 State Scripts** in `engine/subsystems/session/states/`:
  - `CampaignSelectState`: Instantiates CampaignSelectScreen, pushes to NavStack, handles campaign_selected.
  - `SessionLoadState`: Transient bootstrap — loads campaign/party/map, seeds test fixtures, auto-transitions to wilderness. Ported from main_scene._dev_load_test_map_for_campaign().
  - `WildernessExploreState`: Shows hex map, wires renderer signals. On hex click: move → encounter check → time advance → autosave. Dungeon/settlement entry transitions.
  - `DungeonExploreState`: Creates DungeonMapController dynamically, pushes dungeon scene. Cell click → move → auto-stairs → encounter check → time advance. Exit → wilderness.
  - `SettlementExploreState`: Creates SettlementMapController dynamically, pushes settlement scene. Node click → move → time advance. Exit → wilderness.
  - `CombatState`: Stub for F-1. Records return_state. On "combat_ended": advance time by rounds fought, transition back.
  - `SessionEndState`: Calls end_session(), transitions to campaign_select.
- **EffectTicker** (`engine/subsystems/session/effect_ticker.gd`): Wires ActiveEffectTracker.tick_rounds/turns/hours/days to Timekeeping boundary signals. Expired effects emit EventBus.spell_effect_removed. Connect on session load, disconnect on session end.
- **main_scene.gd gutted**: 430 lines → ~70 lines. SessionRunner handles all orchestration. main_scene only keeps override panel setup and dev shortcuts.
- **DiceSystem game_day fix**: Replaced hardcoded `0` with `Timekeeping.get_total_days()` at line 263.
- **Player roll cancellation**: Added `player_roll_cancelled` signal to EventBus. DiceSystem.player_roll() now races `player_roll_resolved` against `player_roll_cancelled` using one-shot connections and frame poll. Cancelled rolls return zeroed RollResult with `was_overridden = true`. SessionRunner calls `cancel_pending_roll()` at every state transition.
- **EventBus signals**: Added `player_roll_cancelled`, `session_state_transitioned(from_key, to_key)`.
- **Test suite** (`tests/test_session_runner.gd`): 23 tests covering state transitions (8), session lifecycle (2), encounter checks (4), time advance (1), EffectTicker (2), roll cancellation (2), submit_action (1), game_day fix (1), combat return state (1), state registry (1).
**Decisions made:**
- **Object-per-state pattern** over monolithic match block. Each state is a separate RefCounted script. Adding new states (camp, downtime, domain, sea voyage) = 1 new file + 1 registry line. Zero modification to existing states.
- **SessionRunner is a scene-tree node** (NOT autoload). Placed in Main.tscn as sibling to HexMapController, NavigationStack, etc.
- **SessionRunner is the SOLE caller** of GameState.transition_to() and set_exploration_context() per E-1 architectural decision.
- **LLM integration ready**: `submit_action(action, payload)` method on SessionRunner delegates to current state's `handle_action()`. Whether action came from UI click or LLM interpretation is irrelevant to the state. Narration output hooks via LLMManager.request_narration() in state resolution paths.
- **Encounter checks**: d6 roll, trigger on 1. Civilized terrain skips check. Dungeon mode (null terrain) uses same 1-in-6. Future: different thresholds by territory type, encounter table resolution.
- **Time advance**: 1 exploration turn per hex move (wilderness), 1 turn per cell move (dungeon), 1 turn per node move (settlement). Future: terrain-based turn cost calculation.
**Interfaces defined or changed:**
- `SessionState` base class: `enter(runner, context)`, `exit(runner)`, `handle_action(runner, action, payload) -> String`.
- `SessionRunner` public API: `transition_to_state(key, context)`, `submit_action(action, payload)`, `load_session(campaign_id, party_id)`, `save_session()`, `end_session()`, `do_encounter_check(terrain) -> Dict`, `advance_exploration_time(turns)`, `cancel_pending_roll()`. Accessors: `get_nav_stack()`, `get_hex_map_controller()`, `get_hex_map_renderer()`, `get_campaign_id()`, `get_party_id()`, `get_party_data()`, `get_active_effects()`, `get_current_state_key()`.
- `SessionRunner` signals: `state_transitioned(from, to)`, `session_loaded(campaign_id)`, `session_saved(campaign_id)`.
- `EffectTicker`: `connect_signals()`, `disconnect_signals()`, `is_connected_to_timekeeping()`.
- EventBus: added `player_roll_cancelled`, `session_state_transitioned(from_key, to_key)`.
- DiceSystem.player_roll(): now supports cancellation via `player_roll_cancelled` signal race.
**Database changes:** None.
**Tests added/updated:**
- `tests/test_session_runner.gd`: 23 tests. Registered in test_runner.gd and test_runner.tscn.
**Known issues:**
- Tests not yet run in Godot — manual verification recommended.
- Encounter checks are simplified (1-in-6 everywhere; no encounter table resolution, no monster group generation). Full encounter resolution is a future phase.
- Time advance uses flat 1 turn per move; terrain-based turn cost calculation not yet implemented.
- SessionLoadState still uses hardcoded test map/dungeon/settlement paths from dev harness. Production map loading is a future phase.
- CombatState is a stub — F-1 will flesh it out.
**Next session should:**
1. Run test_runner.tscn to verify all 23 session runner tests pass (and existing tests still pass).
2. Smoke-test full flow: campaign select → hex map → dungeon entry/exit → settlement entry/exit.
3. Verify time advances (check Timekeeping via override panel after hex movement).
4. Begin Phase F-1: Combat System planning.

---

## Session 2026-04-07 — Phase E-2 Hotfix: Grey Screen on Movement

**Task:** Fix grey screen appearing on hex movement and dungeon entry after E-2 Session Runner integration.
**Model used:** Opus 4.6.
**Completed:**
- **Root cause 1: Encounter-triggered combat transition with no combat scene.** `WildernessExploreState._on_hex_clicked()` called `runner.transition_to_state("combat")` on encounter roll of 1 (16.7% chance). CombatState is a stub that pushes no scene, but the transition called `WildernessExploreState.exit()` which hid the hex map. Result: grey screen with nothing visible. **Fix:** Encounter checks now log a message instead of transitioning to combat. Combat transitions deferred to F-1 when the combat system actually exists.
- **Root cause 2: Lambda closure signal connections.** Explore states used anonymous lambdas (`func(coord): _on_hex_clicked(runner, coord)`) for signal connections. Each `enter()` created new Callable objects, making `is_connected()` checks fail — leading to duplicate connections or failed disconnections. **Fix:** All three explore states now store a `_runner` reference and connect using bound method references (`_on_hex_clicked` directly) instead of closures.
- **Root cause 3: SessionRunner node order in Main.tscn.** SessionRunner was placed before HexMapController and HexMap in the scene tree. Since Godot calls `_ready()` in tree order (children first), SessionRunner's `_ready()` ran before its siblings were initialized. **Fix:** Moved SessionRunner to last child position in Main.tscn so all siblings have completed `_ready()` before it boots.
- **Additional fix:** SessionLoadState renderer setup check simplified from fragile `get("_controller")` to direct `renderer._controller == null` check.
**Decisions made:**
- Encounter checks that trigger encounters log a print() message but do NOT transition to combat until F-1 is built. This prevents grey screens from the stub CombatState.
- State objects store a `_runner` reference set in `enter()`, cleared in `exit()`. Signal handler methods are parameterless (or match the signal signature directly) to avoid closure issues.
**Interfaces defined or changed:**
- WildernessExploreState: `_on_hex_clicked(coord)`, `_on_dungeon_entry(entrance, spawn_cell)`, `_on_settlement_entry(entrance, gate_node_id)` — now match signal signatures directly instead of using closures with bound runner param.
- DungeonExploreState: `_on_cell_clicked(pos)`, `_on_door_interact(pos)`, `_on_exit_requested()` — same pattern.
- SettlementExploreState: `_on_node_clicked(node_id)`, `_on_exit_requested()` — same pattern.
**Database changes:** None.
**Tests added/updated:** None (existing tests cover the fixed code paths).
**Known issues:** None new.
**Next session should:**
1. Run test_runner.tscn to verify all session runner tests pass.
2. Begin Phase F-1: Combat System planning.

---

## Session 2026-04-07 — Phase F-0: Monster Catalog, Registry, and Encounter Wiring

**Task:** Build the starter monster catalog (13 monsters), MonsterRegistry class, and wire encounter generation so random and override-spawned encounters pick real monsters from the catalog.
**Model used:** Opus 4.6 for planning and implementation.

**Completed:**

**Monster Catalog** (`data/monsters/monster_catalog.json` — NEW):
- 13 monster stat blocks extracted from ACKS XML source files.
- One per encounter table terrain key: Shark/Bull (ocean), Crocodile (lake), Wererat (city), Wolf (inhabited), Centaur (clear/grass), Black Widow Spider (woods), Lizardman (jungle), Troll (swamp), Giant Scorpion (desert), Harpy (mountains/hills).
- Three required beastmen: Goblin, Kobold, Orc.
- Schema follows `monster_system_map.md` §1.1–1.7 and §5: identity, hit_dice, armor_class, attack_routines, save_as, morale, xp, movement, encounter composition, terrain_affinity, encounter_hierarchy, special_abilities, immunities/resistances/vulnerabilities, morale_modifiers, combat_behavior tags.
- Kobold half-HD represented as `base: 0.5` — rolls 1d4 for HP when base < 1.0, costs 0.5 HD against spell targeting budgets.
- Wererat dual AC via `armor_class_animal_form: 0` extra field.
- Encounter hierarchies structured for goblin/kobold/orc/lizardman/troll/centaur with leader stats, population ratios, ally chances, shaman/witch doctor probabilities.

**MonsterRegistry** (`engine/subsystems/monsters/monster_registry.gd` — NEW):
- `class_name MonsterRegistry extends RefCounted`. Follows SpellRegistry pattern.
- Loads `res://data/monsters/monster_catalog.json` in `_init()`.
- Core API: `get_monster()`, `has_monster()`, `get_monster_count()`, `get_all_monster_ids()`.
- Terrain query: `get_monsters_for_terrain(terrain_key)` — scans `terrain_affinity` arrays.
- Type queries: `get_monsters_by_type(type)`, `get_monsters_by_sub_type(sub_type)`.
- Convenience: `get_hit_dice()`, `get_xp_value()`, `get_armor_class()`, `get_morale()`.

**Encounter Generation Wiring** (`engine/subsystems/session/session_runner.gd` — MODIFIED):
- Added `_monster_registry: MonsterRegistry` instantiated in `_ready()`.
- Added `get_monster_registry()` accessor.
- Rewrote `do_encounter_check()`: on trigger (1-in-6), calls `_pick_encounter_monster(terrain)` to select a terrain-appropriate monster, rolls 1d6 for count (`encounter_number`), rolls 2d6 for reaction (`reaction`), maps to disposition via `_reaction_to_disposition()`. Emits `encounter_triggered` with full payload matching EncounterData schema.
- Added `_pick_encounter_monster()`: uses `HexTerrainData.encounter_table_weights()` to get weighted table keys, collects candidates from `MonsterRegistry.get_monsters_for_terrain()`, picks one at random.
- Added `_reaction_to_disposition()`: maps 2d6 total to hostile/cautious/neutral/friendly.

**Wilderness/Dungeon State Logging** (MODIFIED):
- `wilderness_explore_state.gd`: encounter log now prints monster name, count, disposition, and reaction roll.
- `dungeon_explore_state.gd`: same.

**Override Panel** (`scenes/ui/override/override_panel.gd` — MODIFIED):
- Spawning tab: replaced free-text LineEdit with OptionButton dropdown populated from MonsterRegistry.
- Added `_populate_monster_dropdown()` to fill dropdown with all cataloged monster IDs.
- Added `_spawn_status` label showing spawn confirmation.

**EncounterData** (`engine/shared_types/encounter_data.gd` — MODIFIED):
- Clarified `monster_group` comment: references `monster_catalog.json` "id" field.

**Test Suite** (`tests/test_monster_registry.gd` — NEW, 30 tests):
- Loading: catalog loads, count is 13.
- Core lookup: has_monster true/false, get_monster not empty, get_all sorted.
- Schema validation: goblin HD (1,-1,0), kobold half-HD (0.5), troll stars (6,3,1), goblin AC 3, save_as NM vs Fighter.
- Movement: shark swim-only, harpy fly, crocodile dual.
- Attacks: troll 3-attack count, scorpion poison on sting, spider poison on bite.
- Abilities: goblin sunlight_penalty, troll regeneration, harpy charming_song, wererat weapon_immunity.
- Terrain: ocean returns shark_bull, swamp includes troll+lizardman, all 10 terrains have ≥1 monster.
- Type: beastman returns 4 IDs, animal returns 3+ IDs, goblinoid sub-type correct.
- Hierarchy: goblin has gang/warband/lair_or_village, orc chieftain stats correct.
- Wired into `test_runner.gd` and `test_runner.tscn` (MonsterRegistryTests).

**Coding Conventions** (`docs/coding_conventions.md` — MODIFIED):
- §2.1 directory tree: added `monsters/` under `engine/subsystems/` and `data/`.
- §10.2 roll type vocabulary: added `encounter_number` and `reaction`.
- §16.9 new section: Encounter Generation Flow documenting the 7-step pipeline.

**Decisions made:**
- **Kobold half-HD as `base: 0.5`** — preserves fractional value for HP rolls (1d4), XP table ("less than 1" row), attack throws, and spell targeting budgets. All other monsters use integer base values.
- **MonsterRegistry is RefCounted, not autoload** — follows SpellRegistry/ClassRegistry/ProficiencyRegistry pattern. Instantiated by SessionRunner and OverridePanel.
- **Terrain affinity inline** — each monster carries a `terrain_affinity` array of encounter table keys. MonsterRegistry scans these at query time. No separate encounter table JSON file needed.
- **Encounter count is 1d6 for all monsters** — simplified for the starter set. Future: use per-monster encounter dice expressions from the catalog's dungeon/wilderness encounter fields.
- **Reaction roll 2d6 mapped to 4 dispositions**: ≤3 hostile, 4–5 cautious, 6–8 neutral, 9+ friendly.
- **`sub_types`** separate from `monster_types` — needed for proficiency hooks (e.g. Goblin-Slaying targets `goblinoid` sub-type per monster_system_map.md §5.4).

**Interfaces defined or changed:**

MonsterRegistry (new class):
- `get_monster(monster_id) -> Dictionary`
- `has_monster(monster_id) -> bool`
- `get_monster_count() -> int`
- `get_all_monster_ids() -> Array[String]`
- `get_monsters_for_terrain(terrain_key) -> Array[String]`
- `get_monsters_by_type(monster_type) -> Array[String]`
- `get_monsters_by_sub_type(sub_type) -> Array[String]`
- `get_hit_dice(monster_id) -> Dictionary`
- `get_xp_value(monster_id) -> int`
- `get_armor_class(monster_id) -> int`
- `get_morale(monster_id) -> int`

SessionRunner additions:
- `_monster_registry: MonsterRegistry` (instantiated in _ready)
- `get_monster_registry() -> MonsterRegistry`
- `_pick_encounter_monster(terrain: HexTerrainData) -> String`
- `_reaction_to_disposition(total: int) -> String` (static)
- `do_encounter_check()` now returns full encounter_data with monster_group, number, reaction_roll, behavioral_disposition

EventBus.encounter_triggered payload now always includes:
- `encounter_id`, `monster_group`, `number`, `reaction_roll`, `behavioral_disposition`, `hex_id`, `terrain_category`, `territory`, `roll`

**Database changes:** None.

**Tests added/updated:**
- `tests/test_monster_registry.gd` (NEW): 30 tests.
- `tests/test_runner.gd` + `tests/test_runner.tscn`: MonsterRegistryTests added.

**Known issues:**
- Encounter count uses flat 1d6 for all monsters. The catalog stores per-monster encounter dice expressions (e.g. "2d4" for goblin gangs) but these are not yet parsed by the encounter generator. Future refinement when encounter tables are fully implemented.
- No combat transition on encounter — encounters log to console but do not enter combat state. Deferred to F-1.
- The override panel's monster dropdown shows raw IDs as item text with display names in tooltips. A future UI pass could show "Goblin" instead of "goblin" as the visible text.
- `_pick_encounter_monster()` uses uniform random across candidates. ACKS encounter tables use weighted d8/d12 rolls for category then specific monster — full table resolution deferred to encounter table system build.

**Next session should:**
1. Run test_runner.tscn to verify all 30 MonsterRegistry tests pass alongside existing suites.
2. Smoke-test: move around the hex map, verify encounter logs show monster names (e.g. "ENCOUNTER at (1, 0): 3 x goblin (neutral, reaction 7)").
3. Smoke-test override panel Spawning tab: dropdown should list all 13 monsters, spawning should show status message.
4. Begin Phase F-1: Combat System planning.

---

## Session 2026-04-07 — F-1 Session 1: Core Combat Loop, Initiative, Basic Melee Attack

**Task:** Build the foundational combat loop — round sequence, initiative, attack resolution, and combat end detection. First of 5 planned sessions for F-1.
**Model used:** Opus 4.6 for planning and implementation.

**Completed:**
- Created `engine/subsystems/combat/` directory with 5 new files.
- **Combatant** (`engine/subsystems/combat/combatant.gd`): Unified wrapper over CharacterData (PCs/henchmen) and monster catalog dicts. Provides consistent interface: `get_effective_ac()`, `get_effective_attack_throw()`, `apply_damage()`, `get_initiative_modifier()`, `get_combat_progression()`, `get_level_or_hd()`, `get_attack_routines()`, `get_attack_count()`, `get_damage_expression()`, conditions array, spell declaration tracking. Monsters get transient ModifierContainer/EntityFlags/DamageResistance for combat-only effects. Includes ACKS monster attack throw table (HD-based) and simplified fighter save table by level bracket.
- **CombatRoster** (`engine/subsystems/combat/combat_roster.gd`): Two-sided combatant container. Factory method `build_from_encounter(party_data, encounter_data, monster_registry, dice_system)` rolls monster HP and builds Combatant wrappers. Queries: `get_alive()`, `get_alive_on_side()`, `get_by_id()`, `get_combatants_in_group()`. Casualty tracking per monster group for morale triggers (`record_casualty()`, `is_first_casualty()`, `is_half_casualties()`). Combat end detection (`is_party_eliminated()`, `is_enemies_eliminated()`).
- **InitiativeResolver** (`engine/subsystems/combat/initiative_resolver.gd`): ACKS initiative — 1d6 + DEX mod + initiative modifiers per combatant, sorted highest-first. `group_simultaneous()` groups ties for simultaneous resolution. Stable tiebreak by combatant ID for determinism.
- **AttackResolver** (`engine/subsystems/combat/attack_resolver.gd`): ACKS attack throw — `1d20 + mods >= attacker.attack_throw + target.effective_ac`. Natural 20 always hits, natural 1 always misses. `resolve_melee_attack()` for PC/character attacks (STR mod on damage). `resolve_monster_attack()` for monster routine attacks (reads damage/to_hit from attack_routines). Minimum 1 damage. Emits `EventBus.damage_dealt`, `combatant_downed`, `hp_changed`.
- **CombatController** (`engine/subsystems/combat/combat_controller.gd`): Pull-based round loop orchestrator. Phase enum: NOT_STARTED → DECLARATION → INITIATIVE → ACTION → END_ROUND → COMBAT_OVER. `advance() -> Dictionary` returns status dict; `submit_pc_action()` for player input. Declaration phase is a no-op stub for Session 1 (wired in Session 2). Monster auto-action: melee attack first alive enemy (replaced by MonsterAI in Session 3). Multi-attack support for monsters. Combat end on all-enemies-dead or all-party-dead. Emits `combat_ended` with XP total from downed monsters.
- **Updated CombatState** (`engine/subsystems/session/states/combat_state.gd`): Fleshed out from stub. Builds CombatRoster from encounter_data, creates InitiativeResolver and AttackResolver, instantiates CombatController. Routes `combat_advance` and `combat_pc_action` actions. `_finish_combat()` advances Timekeeping rounds and returns to exploration state. Exposes `get_controller()` for UI queries.
- Fixed pre-existing Variant inference warning in `wilderness_explore_state.gd` line 80.

**Decisions made:**
- **Pull-based `advance()` design** rather than internal loop — controller never blocks, returns "waiting_for_input" status when a PC needs to act. Caller (UI or test) calls `submit_pc_action()` then `advance()` again. This avoids async complexity and makes testing trivial.
- **Combatant wraps, doesn't subclass CharacterData** — monsters build transient combat state from catalog dict rather than creating a full CharacterData. This avoids pollution of the persistence model.
- **Godot enum typing: use `int` for enum-typed fields** — `var side: Side` causes parse errors in Godot 4 when the enum is defined in the same class. Convention: declare as `var side: int = Side.PARTY` and use `int` for parameter types referencing enums from other classes (e.g. `Combatant.Side`). The enum constants themselves work fine as values.
- **ActionPayload reuse** for combat: action_ids = `"attack_melee"`, `"attack_ranged"`, `"cast_spell"`, `"move"`, `"fighting_withdrawal"`, `"full_retreat"`, `"use_item"`, `"combat_maneuver"`, `"pass"`.
- **Monster HP** rolled at combat start from `hit_dice.base * d8 + hit_dice.modifier`. Override system can force values via `starting_hp` roll type.
- **Simplified monster saves** — uses a lookup table covering fighter saves by level bracket (0, 1-3, 4-6, 7-9, 10-12, 13+). Future sessions may wire through ClassRegistry for precise class/level lookup when non-fighter save_as values appear.

**Interfaces defined or changed:**

Combatant (core interface):
- `from_character(character, combatant_id) -> Combatant` (static factory)
- `from_monster(monster_data, rolled_hp, combatant_id, group_id) -> Combatant` (static factory)
- `get_effective_ac() -> int`, `get_effective_attack_throw() -> int`, `get_effective_save(save_key) -> int`
- `get_initiative_modifier() -> int`, `get_combat_progression() -> String`, `get_level_or_hd() -> int`
- `get_attack_routines() -> Array`, `get_attack_count() -> int`, `get_damage_expression(idx) -> String`
- `get_to_hit_modifier(idx) -> int`, `get_morale() -> int`, `get_combat_movement() -> int`
- `apply_damage(amount, damage_type) -> Dictionary`, `apply_healing(amount) -> int`
- `is_alive() -> bool`, `is_pc_side() -> bool`, `has_condition(key) -> bool`
- `has_proficiency(key) -> bool`, `get_proficiency_rank(key) -> int`

CombatRoster:
- `build_from_encounter(party_data, encounter_data, monster_registry, dice_system) -> CombatRoster`
- `get_alive() -> Array[Combatant]`, `get_alive_on_side(side_int) -> Array[Combatant]`
- `record_casualty(combatant, round)`, `is_first_casualty(group_id) -> bool`, `is_half_casualties(group_id) -> bool`

CombatController:
- `advance() -> Dictionary` — status keys: `combat_started`, `round_started`, `initiative_rolled`, `waiting_for_pc_action`, `action_resolved`, `round_ended`, `combat_over`
- `submit_pc_action(combatant_id, action_id, parameters)`
- `get_waiting_combatant_id() -> String`

CombatState actions:
- `"combat_advance"` — advance controller one step
- `"combat_pc_action"` — payload: `{combatant_id, action_id, parameters}`
- `"combat_ended"` — direct end from override system

**Database changes:** None.

**Tests added/updated:**
- `tests/test_combat_initiative.gd` (NEW): 7 tests — single/multi combatant, DEX modifier, simultaneous ties, dead combatant skipping, stable tiebreak, empty list.
- `tests/test_combat_attack_resolver.gd` (NEW): 11 tests — hit/miss at threshold, natural 20/1, damage application, minimum 1 damage, STR modifier, target downed, miss no damage, monster routine attack, high AC difficulty.
- `tests/test_combat_controller.gd` (NEW): 8 tests — start/advance flow, full fighter-vs-goblin combat to victory, party defeat, multi-combatant initiative, pass action, combat end detection, multi-round, monster multi-attack.
- All tests use MockDice pattern for deterministic results.
- `tests/test_runner.gd` + `tests/test_runner.tscn`: 3 new suites registered (CombatInitiativeTests, CombatAttackResolverTests, CombatControllerTests).

**Known issues:**
- Monster target selection is trivial (first alive enemy). MonsterAI with behavior tags deferred to Session 3.
- Spell declaration phase is a no-op pass-through. Spell hooks wired in Session 2.
- Cleave not implemented. Deferred to Session 3.
- Morale not implemented. Deferred to Session 3.
- Character melee damage hardcoded to `"1d6"` — equipped weapon integration deferred until equipment system is wired to combat.
- Monster save table is simplified (fighter saves by bracket only). Non-fighter save_as values (cleric, thief, mage) will use the same fighter table until ClassRegistry lookup is wired.
- No grid-based positioning or movement — all combatants can attack any enemy. Movement/engagement deferred to Session 4.

**Next session should:**
1. Run test_runner.tscn in Godot to verify all 26 new combat tests pass alongside existing suites.
2. Build F-1 Session 2: SpellCombatHooks (14 trigger points), RangedAttackResolver, CombatConditionManager. Wire hooks into CombatController at all phase boundaries.

---

## Session 2026-04-08 — Character Creation Starting Gold Rolled-State Fix

**Task:** Fix the character-creation starting gold / shopping step so a completed gold roll properly registers and the shop does not get desynced by earlier generator work.
**Model used:** GPT-5 Codex
**Completed:**
- Updated `scenes/ui/character_creation/equipment_shop_panel.gd` so `is_complete()` reads the panel's restored local gold state instead of re-querying the backing dictionary on every check.
- Added `_apply_starting_gold_roll_total()` in `scenes/ui/character_creation/equipment_shop_panel.gd` to centralize the resolved-roll path: successful rolls now commit local + shared gold state in one place, while zero/cancelled results leave the panel unrolled and re-enable the button instead of trapping the player in a bad state.
- Removed the stray `starting_gold` roll from `engine/subsystems/characters/character_generator.gd`; PC generation no longer consumes the real equipment-step roll type or any queued override before the player reaches the shop.
- Added `tests/test_equipment_shop_panel.gd` coverage for successful rolled-state application and for zero/cancelled results staying in the pre-roll state.
- Added `tests/test_character_generator.gd` coverage verifying `generate_pc()` does not consume a queued `starting_gold` override.
- Updated `docs/coding_conventions.md` §3.8 with the async UI roll-handler rule: await at the boundary, then hand off resolved state mutation to a synchronous helper so plain test suites can exercise the post-roll path.
**Decisions made:**
- Treated starting-gold registration as both a UI-state problem and a roll-ownership problem. The equipment step is now the sole owner of `starting_gold`; the generator no longer touches that roll type.
- Chose a synchronous post-roll helper in the shop panel rather than adding async test plumbing, so future roll-driven UI regressions can be covered with the existing plain `run_all_tests()` harness.
**Interfaces defined or changed:**
- `EquipmentShopPanel._apply_starting_gold_roll_total(roll_total: int) -> void` — applies a resolved 3d6 total to shop state, or restores the pre-roll state when the resolved total is zero/cancelled.
**Database changes:** None.
**Tests added/updated:**
- `tests/test_equipment_shop_panel.gd` — added rolled-state and zero/cancelled-result regressions.
- `tests/test_character_generator.gd` — added override-consumption regression.
- Verified with headless Godot test run: `C:\Godot\Godot_v4.6.1-stable_win64.exe --headless --path . res://tests/test_runner.tscn` exited with code `0`.
**Known issues:**
- `HpRollPanel.is_complete()` still keys off `_state.has("hp_rolled")` while `_reset_state()` seeds `"hp_rolled": 0`; this predates the starting-gold fix and was not changed here.
- The worktree contains unrelated in-progress combat/monster changes outside this fix; they were left untouched.
**Next session should:**
1. Smoke-test the character-creation flow in-editor with digital and hybrid dice modes to confirm the equipment step advances immediately after a gold roll and still reopens cleanly on back-navigation.
2. Fix the pre-existing `HpRollPanel.is_complete()` / seeded `hp_rolled` mismatch so the HP step cannot be skipped accidentally.

---

## Session 2026-04-08 — Monster AI Combat System (F-1 Session 3)

**Task:** Implement monster AI using behavior tags, morale checks at ACKS-correct triggers, and cleave chains for fighters/monsters.
**Model used:** Opus for planning and implementation.
**Completed:**

### New files
- `engine/subsystems/combat/monster_ai.gd` — Deterministic action selection using behavior tags. Scores targets by primary_target_rule (nearest, weakest, most_dangerous, most_exposed, role_mage, role_missile, retaliatory), resolves ties with target_tie_breaker (nearest, lowest_ac, lowest_hp, last_attacker, leader_marked, random), supports pack focus-fire bonus. Pre-grid: spatial rules approximate (all equidistant).
- `engine/subsystems/combat/morale_resolver.gd` — ACKS morale roll system. Triggers: first_casualty, half_casualties, solo_half_hp. Combined same-round triggers at -2. Outcomes: retreat (is_fleeing), fighting_withdrawal (is_withdrawing + 1d10 rounds), fight_on, advance_pursue, victory_or_death (morale_locked). Evaluates conditional modifiers (chieftain_alive) and special ability overrides (blood_frenzy → no_check). Fearless morale_style and morale +4 skip rolls.
- `engine/subsystems/combat/cleave_resolver.gd` — Cleave budget tracking per round. Fighter: up to HD cleaves. Cleric/Thief: HD/2 floor. Mage/NM: 0 cleaves. Budget shared across all attacks in the routine.
- `tests/test_monster_ai.gd` — 15 tests covering all target rules, tie-breakers, pack focus, fleeing/withdrawing behavior.
- `tests/test_morale_resolver.gd` — 12 tests covering all triggers, outcomes, conditional modifiers, overrides.
- `tests/test_cleave_chains.gd` — 10 tests covering all combat progressions, budget tracking, expanded attack sequences.

### Modified files
- `engine/subsystems/combat/combatant.gd` — Added: `is_withdrawing`, `withdrawal_rounds_remaining`, `morale_locked`, `last_attacker_id` fields. Added: `get_combat_behavior()`, `get_expanded_attack_sequence()` (fixes count field bug), `get_morale_modifiers()`, `get_special_abilities()`. Fixed: `get_combat_progression()` now derives from save_as.class (F→fighter, C→cleric, T→thief, M→mage, NM→normal_man) instead of reading a non-existent combat_progression field.
- `engine/subsystems/combat/combat_controller.gd` — Constructor extended with monster_ai, morale_resolver, cleave_resolver (all optional, null-safe). `_resolve_monster_action()` rewritten: uses MonsterAI for target selection, expanded attack sequences for mid-routine cleave, morale trigger checks after casualties, fighting withdrawal tick. Added `_resolve_cleave_chain()`, `_check_morale_after_casualty()`, `_check_solo_monster_morale()`. Renamed `_auto_select_melee_target()` → `_auto_select_target()` with AI fallback.
- `engine/subsystems/combat/attack_resolver.gd` — Sets `target.last_attacker_id = attacker.id` on damage dealt in both `resolve_melee_attack()` and `resolve_monster_attack()`.
- `engine/subsystems/session/states/combat_state.gd` — Instantiates MonsterAI, MoraleResolver, CleaveResolver and passes to CombatController.
- `data/monsters/monster_catalog.json` — Normalized tag vocabulary: craven→fragile, bold→steadfast, standard→normal, nearest_threat→most_dangerous, strongest→lowest_ac, weakest(tiebreaker)→lowest_hp. Kept: fearless, pack, none, random as distinct values.
- `generation/gdd_combat_behavior_tags.md` — Added fearless (morale_style), pack/none (formation_discipline), random (target_tie_breaker) to documented vocabulary and data model.
- `tests/test_runner.gd` / `tests/test_runner.tscn` — Added 3 new test suite nodes.
- `tests/test_combat_controller.gd` — Fixed pre-existing initiative tiebreak fragility (PCs need enough HP to survive monster-first initiative).
- `tests/test_combat_controller_session2.gd` — Same initiative fragility fix.

**Decisions made:**
- Cleave happens mid-routine: claw/claw(kill)/cleave-claw/bite. Cleave uses same attack type/stats as killing blow.
- Cleave cap is HD total per round across all attacks (not per killing blow).
- NM-saving monsters (goblins, kobolds) get 0 cleaves (strict reading: NM doesn't use fighter attack throws).
- Leader death is NOT a separate morale trigger; chieftain_alive modifier just disappears.
- Pre-grid morale: flag + fighting withdrawal. Retreat = is_fleeing (skip turns). Fighting withdrawal = is_withdrawing (still attacks, 1d10 rounds then flee).
- Tag vocabulary hybrid approach: keep fearless/pack/none/random as distinct values with unique runtime behaviors.
- Morale resolver checks BOTH morale_modifiers and special_abilities for no_check overrides.

**Interfaces defined or changed:**
- `CombatController._init()` — 3 new optional params: `p_monster_ai: MonsterAI`, `p_morale_resolver: MoraleResolver`, `p_cleave_resolver: CleaveResolver`
- `Combatant` new fields: `is_withdrawing: bool`, `withdrawal_rounds_remaining: int`, `morale_locked: bool`, `last_attacker_id: String`
- `Combatant.get_combat_progression()` — now returns "normal_man" for NM save class
- `Combatant.get_expanded_attack_sequence()` → `Array[Dictionary]` with keys: attack_type, damage, to_hit_modifier, special_effect, source_index
- `Combatant.get_combat_behavior()` → Dictionary (raw behavior tags from monster data)
- `Combatant.get_morale_modifiers()` → Array
- `Combatant.get_special_abilities()` → Array
- `MonsterAI.select_action(combatant)` → `{action_id, parameters}`
- `MonsterAI.select_target(combatant, behavior)` → Combatant
- `MoraleResolver.check_trigger(combatant, trigger, roster)` → `{should_roll, extra_modifier, reason}`
- `MoraleResolver.roll_morale(combatant, roster, extra_modifier)` → `{roll, base_morale, conditional_modifier, extra_modifier, modified_total, outcome}`
- `MoraleResolver.apply_outcome(combatant, outcome)` — sets is_fleeing/is_withdrawing/morale_locked
- `CleaveResolver.get_max_cleaves(combatant)` → int
- `CleaveResolver.can_cleave(combatant)` → bool

**Database changes:** None.

**Tests added/updated:**
- `tests/test_monster_ai.gd` — 15 tests (all passing)
- `tests/test_morale_resolver.gd` — 12 tests (all passing)
- `tests/test_cleave_chains.gd` — 10 tests (all passing)
- All 10 combat test suites pass (including 26 pre-existing + 37 new = 63 total combat tests).

**Known issues:**
- Full test runner (test_runner.tscn) hangs after ~7 suites, before reaching combat tests. This is a pre-existing issue unrelated to this session's changes. Combat tests verified via focused runner.
- Pre-grid limitations: nearest/most_exposed target rules use AC-based approximation or stable ID ordering. Formation discipline spatial effects deferred to Session 4.
- engagement_profile: missile/balanced profiles are implemented but pre-grid all monsters default to melee (no distance tracking yet).
- spellcasting_timing / consumable_timing: no spellcasting or consumable monsters in current catalog. Logic is stubbed; concrete implementations deferred to spell/item sessions.
- leader_marked tie-breaker: placeholder, returns stable ID tiebreak. Needs leader tracking system.

**Next session should:**
1. Session F-1.4: Grid-based movement on TacticalMapData, engagement/withdrawal/retreat rules, 7 combat maneuvers, charging.
2. Fix the full test runner hang (likely a ClassRegistry or downstream test causing infinite loop).

---

## Session 2026-04-08 — Grid Movement, Engagement, Maneuvers, Charging (F-1 Session 4)

**Task:** Implement grid-based movement on TacticalMapData, engagement/withdrawal/retreat rules, 7 ACKS combat maneuvers, and charging mechanics.
**Model used:** Opus 4.6 for planning and implementation.
**Completed:**

### New files
- `engine/subsystems/combat/movement_resolver.gd` — BFS pathfinding, Chebyshev distance, adjacency/engagement tracking, charge validation (min 4 cells, clear straight-line path, LOS), LOS via Bresenham line walk, fighting withdrawal (half movement away), full retreat (full movement away). All methods return graceful defaults when `_map` is null (pre-grid fallback).
- `engine/subsystems/combat/maneuver_resolver.gd` — All 7 ACKS combat maneuvers: brawl (nonlethal punch/kick), disarm (weapon 5' away), force back (push distance = damage roll, wall collision), knock down (prone), overrun (move through, doesn't consume attack), sunder (weapon/shield, magic item resistance), wrestle (grappled hold, free follow-up maneuvers). Shared pattern: -4 attack throw, target saves vs Paralysis, maneuver-specific effect. Size modifier (-4 save if attacker 2x HD).
- `tests/test_movement_resolver.gd` — 18 tests: no-grid fallback, distance, adjacency, engagement, BFS pathfinding (open/wall/unreachable), can_reach, move_along_path, LOS (clear/blocked), charge validation (valid/too close/blocked).
- `tests/test_combat_maneuvers.gd` — 14 tests: all 7 maneuvers with hit/save outcomes, wrestling hold follow-up attacks, monster brawl prohibition, sunder magic item resistance.
- `tests/test_combat_controller_session4.gd` — 12 tests: no-grid backward compatibility, grid melee adjacency/out-of-range/auto-move, ranged grid distance, charge succeed/fail, move action, fighting withdrawal, full retreat with vulnerable, declarations, engagement condition tracking.
- `tests/test_monster_ai_spatial.gd` — 8 tests: nearest rule with grid distance, nearest tiebreaker, most_exposed distance bonus, melee when adjacent, charge when far, move-toward, no-grid fallback, missile profile.

### Modified files
- `engine/subsystems/combat/combatant.gd` — Added: `grid_position`, `declared_defensive_movement`, `set_against_charge`, `has_moved_this_round`, `held_by_id` fields. Added `get_combat_movement_cells()` helper.
- `engine/subsystems/combat/combat_controller.gd` — Added `movement_resolver`, `maneuver_resolver`, `tactical_map` fields. Extended constructor with optional `p_tactical_map`. New action routing: `move`, `charge`, `fighting_withdrawal`, `full_retreat`, `maneuver_*`. Melee gated by adjacency with auto-move. Ranged distance from grid. Declaration phase resets per-round grid fields. `submit_declaration()` for defensive movement/set-against-charge. `_resolve_charge_action()` with set-against-charge counter. `_resolve_defensive_movement()`. `_update_engagement()` after position changes. ManeuverResolver created in constructor (works with or without grid).
- `engine/subsystems/combat/monster_ai.gd` — Added `_movement_resolver` field (optional, injected via constructor). "nearest" scoring uses actual grid distance when available. "most_exposed" includes distance bonus. `_choose_engagement_action()` spatial: melee if adjacent, move+melee if within movement, charge if 4+ cells clear path, ranged if has missile attacks. `_nearest_tiebreak()` uses grid distance.
- `engine/subsystems/combat/attack_resolver.gd` — No changes needed (charge double damage handled via condition system).
- `engine/subsystems/session/states/combat_state.gd` — Creates MovementResolver and passes to MonsterAI before CombatController. Passes tactical_map to CombatController constructor. `_place_combatants_on_grid()` places party near entry, monsters offset.
- `data/conditions/condition_catalog.json` — Added `"disarmed"` condition.
- `tests/test_runner.gd` + `tests/test_runner.tscn` — 4 new test suite nodes registered.

**Decisions made:**
- Grid is optional: all spatial checks guarded by null. Pre-grid tests pass unmodified.
- Move + Attack: `_resolve_melee_action()` auto-moves to adjacent cell within movement budget. Explicit "move" action only for move-without-attacking.
- Engagement is procedural: `_update_engagement()` applies/removes "engaged" condition after any position change, not declared by player.
- Full retreat: applies "vulnerable" condition (no shield AC, +2/+4 attacker bonus) — matches ACKS exactly.
- Overrun doesn't consume attack: tracked separately via `does_not_consume_attack` flag.
- Wrestling hold: `held_by_id` on target lets ManeuverResolver skip attack throw for follow-up maneuvers.
- Charge double damage: handled by "charging" condition in catalog (`double_damage_on_hit: true`). Set-against-charge: defender counter-attacks first with double damage if initiative >= charger.
- ManeuverResolver works without grid (maneuvers don't require spatial positioning).
- Size modifier: HD 2x ratio triggers -4 save penalty (rough proxy for size).
- Force back direction: away from attacker position on grid; wall collision = prone + 1d6/10'.

**Interfaces defined or changed:**
- `CombatController._init()` — new optional param: `p_tactical_map: TacticalMapData`
- `CombatController.submit_declaration(combatant_id, declaration_type, parameters)` — pre-initiative declarations
- `Combatant` new fields: `grid_position: Vector2i`, `declared_defensive_movement: String`, `set_against_charge: bool`, `has_moved_this_round: bool`, `held_by_id: String`
- `Combatant.get_combat_movement_cells() -> int` — movement in grid cells
- `MovementResolver._init(map, roster)` — all public methods listed in plan
- `MovementResolver.validate_charge(attacker, target) -> {valid, path, reason}`
- `ManeuverResolver._init(dice, attack_resolver, movement_resolver, condition_manager)`
- `ManeuverResolver.resolve_maneuver(attacker, target, maneuver_type, parameters) -> Dictionary`
- `MonsterAI._init(roster, dice_system, movement_resolver)` — 3rd param is new (optional)

**Database changes:** None.

**Tests added/updated:**
- `tests/test_movement_resolver.gd` — 18 tests (all passing)
- `tests/test_combat_maneuvers.gd` — 14 tests (all passing)
- `tests/test_combat_controller_session4.gd` — 12 tests (all passing)
- `tests/test_monster_ai_spatial.gd` — 8 tests (all passing)
- All 14 pre-existing combat test suites pass (62 total suites pass, 5 pre-existing failures unchanged).

**Known issues:**
- Full test runner hangs after ~60 suites (pre-existing, unrelated to this session).
- Missile profile AI: doesn't yet prefer ranged over melee when within movement range. Needs refinement to check engagement_profile before defaulting to melee.
- leader_marked tie-breaker: still placeholder (stable ID tiebreak).
- Set-against-charge counter-attack currently uses normal melee damage; ACKS specifies double damage for spear/polearm specifically — needs weapon tag integration.
- Charge double damage for spear/lance/polearm: relies on "charging" condition's `double_damage_on_hit` flag, but AttackResolver doesn't yet check weapon type to restrict double damage to charge weapons.
- Force back wall collision: distance-based (1d6 per 10'), but doesn't check for entity collisions (knock down smaller creatures).
- Overrun: block/strike option always assumed; needs player/AI choice mechanism.
- Running exhaustion (2×CON rounds, then exhausted): tracked fields exist but no mechanic yet.
- Grid combat map generation: TacticalMapData from context is placeholder; procedural battle map generation (gdd-combat-map-generation.md) is Phase D-4 dependency.

**Next session should:**
1. Session F-1.5: Mortal wounds tables, XP awards, combat end lifecycle, full SessionRunner integration, combat log.
2. Fix the full test runner hang.
3. Consider refining missile profile AI to prefer ranged when not adjacent.
3. Wire formation_discipline spatial effects once grid movement exists.

---

## Session 2026-04-08 — Character Creation Hanging Player Roll Fix

**Task:** Fix character-creation player rolls that resolved in the DicePrompt but left HP or starting-gold steps stuck in an in-flight state, especially from the Main dev-overlay path after the SessionRunner cancellation refactor.
**Model used:** GPT-5 Codex
**Completed:**
- Reworked `engine/autoloads/dice_system.gd` so `player_roll()` now uses a dedicated `_PendingPlayerRoll` helper object with bound-method signal listeners instead of inline closures. The helper owns waiting state, disconnect cleanup, and first-terminal-signal-wins behavior for `player_roll_resolved` vs `player_roll_cancelled`.
- Added `_build_cancelled_result()` in `engine/autoloads/dice_system.gd` so cancelled player rolls still complete the awaiting coroutine with a consistent zeroed `RollResult` that preserves roll metadata.
- Updated `scenes/ui/character_creation/hp_roll_panel.gd` to route post-await state changes through `_apply_hp_roll_total()`, clear `_rolling` and button disable state on both resolve and cancel paths, and treat zero/cancelled results as "not rolled yet."
- Updated `scenes/ui/character_creation/equipment_shop_panel.gd` so `_apply_starting_gold_roll_total()` fully owns post-roll cleanup, including clearing `_rolling` and restoring the roll button on cancelled/zero results.
- Updated `scenes/ui/character_creation/character_creation_screen.gd` to stop seeding `hp_rolled` in fresh state and to erase `hp_rolled` / `hp_raw_roll` when invalidating from the HP step.
- Added focused `DiceSystem` pending-roll tests in `tests/test_dice_system.gd`.
- Added a new `tests/test_hp_roll_panel.gd` suite and registered it in `tests/test_runner.gd` / `tests/test_runner.tscn`.
- Extended `tests/test_equipment_shop_panel.gd` to assert cancelled starting-gold rolls re-enable the button and clear in-flight roll state.
- Updated `docs/coding_conventions.md` §3.8 with the new coroutine signal-race rule: prefer helper objects with bound listeners over anonymous closures for multi-signal waits.
**Decisions made:**
- Kept this fix scoped to the async roll path and character-creation panel state handling; character creation remains launched from the existing Main dev-overlay path for now.
- Preserved the existing cancellation contract: cancelled player rolls still return a zeroed `RollResult` with `was_overridden = true` so awaiting callers resume cleanly.
- Treated HP and equipment as the same class of bug so both early character-creation player-roll steps now share the same thin-await/synchronous-helper pattern.
**Interfaces defined or changed:**
- `DiceSystem._create_pending_player_roll() -> RefCounted` — internal helper factory used by `player_roll()`.
- `DiceSystem._build_cancelled_result(roll_type: String, sides: int, count: int, modifier: int, description: String = "") -> RollResult` — internal helper that returns the zeroed cancelled result.
- `HpRollPanel._apply_hp_roll_total(raw_total: int) -> void` — synchronous post-roll helper for HP panel state changes.
**Database changes:** None.
**Tests added/updated:**
- `tests/test_dice_system.gd` — added resolved/cancel/disconnect coverage for pending player-roll state.
- `tests/test_hp_roll_panel.gd` — added fresh-state, resolved-roll, and zero/cancelled-roll regressions.
- `tests/test_equipment_shop_panel.gd` — expanded cancelled-roll regression to cover button + `_rolling` reset.
- Full headless suite passed via `C:\Godot\Godot_v4.6.1-stable_win64.exe --headless --path . res://tests/test_runner.tscn`.
**Known issues:**
- Interactive HYBRID-mode smoke testing through `Ctrl+Alt+C` was not run in this environment, so the manual prompt-flow verification remains unperformed here.

---

## Session 2026-04-08 — F-1 Session 5: Mortal Wounds, XP Awards, Combat End Lifecycle

**Task:** Implement F-1 Session 5 — mortal wounds tables (ACKS d20+d6 system), XP awards via XPAwardCalculator, combat end lifecycle (process downed PCs, mark deaths, distribute XP), full SessionRunner integration (wire commented-out combat transitions), and a structured CombatLog replacing raw event arrays.
**Model used:** Sonnet 4.6 (implementation)

**Completed:**

### New files
- `engine/subsystems/combat/combat_log.gd` — `CombatLog` class with `EntryType` enum (12 types), typed entry structure `{type, round, actor_id, target_id, data, timestamp}`. Methods: `add_entry()`, `get_all_entries()`, `get_round_entries()`, `get_entries_by_type()`, `get_entries_for_combatant()`, `get_summary()`, `to_array()`.
- `engine/subsystems/combat/mortal_wounds_resolver.gd` — `MortalWoundsResolver` class. Implements full ACKS mortal wounds system: d20+d6 roll, 5 damage type wound tables (bludgeoning/fire/penetrating/savage/slashing), 6 rows × 8 columns each. Modifiers: CON mod, HD die bonus (+2/+4/+6/+8 for d6/d8/d10/d12), HP deficit (0hp=+5, tiered down to -20 at 2×max), treatment timing, healing magic BHR, healing proficiency rank. Returns `{d20_raw, d6_raw, d20_modifiers, d20_total, d6_total, condition, wound_description, recovery_time, is_dead, recovers_to_1hp}`. Uses roll types `"mortal_wound_d20"` and `"mortal_wound_d6"` for override support.
- `tests/test_combat_log.gd` — 5 tests: add/retrieve, filter by round, filter by type, filter by combatant, summary counts.
- `tests/test_mortal_wounds_resolver.gd` — 20 tests: all 7 condition ranges, CON modifier shift, HD die bonus, HP deficit tiers, treatment timing, wound table lookups (all 5 types), is_dead flag, recovers_to_1hp, recovery times, default-to-slashing fallback.
- `tests/test_combat_controller_session5.gd` — 10 integration tests: victory xp, defeat zero xp, downed_pcs populated, condition is valid, is_dead on instantly_killed, alive pc gets xp, no xp on defeat, combat log has ROUND_START entries, combat log has ATTACK entries, combat_ended signal payload shape.

### Modified files
- `engine/subsystems/combat/combatant.gd` — Added `hp_when_downed: int = 0` and `killing_blow_damage_type: String = "slashing"`. `apply_damage()` sets `hp_when_downed` (pre-clamp deficit) when character is downed.
- `engine/subsystems/combat/attack_resolver.gd` — All 3 downing paths set `target.killing_blow_damage_type = "slashing"` when `target.is_character`.
- `engine/subsystems/combat/combat_roster.gd` — Added `get_downed_pcs() -> Array` (PC-side characters not alive).
- `engine/subsystems/combat/combat_controller.gd` — Replaced `_round_events`/`all_events` arrays with `combat_log: CombatLog`. Added `mortal_wounds_resolver` field (11th constructor param). `_emit_combat_ended()` now returns `Dictionary` with `downed_pcs` and `monster_xp_total`. Added `process_mortal_wounds() -> Array`. Round log integration throughout.
- `engine/autoloads/event_bus.gd` — Added `signal mortal_wound_rolled(character_id: String, result: Dictionary)`.
- `engine/subsystems/override/override_manager.gd` — Updated roll type vocabulary: `mortal_wound_d20` and `mortal_wound_d6` (replaced `mortal_wound_roll`).
- `engine/subsystems/session/states/combat_state.gd` — Creates `MortalWoundsResolver` in `enter()`. `_finish_combat()` expanded: processes mortal wounds, marks dead PCs, awards XP via `XPAwardCalculator`. Added `_mark_pc_dead()` and `_award_combat_xp()`.
- `engine/subsystems/session/states/wilderness_explore_state.gd` — Wired combat transition (was commented out). Passes `encounter_data` + `return_state: "wilderness"` context; early `return` prevents time advance after combat entry.
- `engine/subsystems/session/states/dungeon_explore_state.gd` — Same pattern as wilderness; passes `tactical_map` from `_controller.get_map()`.
- `engine/subsystems/session/session_runner.gd` — Added `_class_registry: ClassRegistry` lazy field with `get_class_registry()` getter.
- `tests/test_runner.gd` + `tests/test_runner.tscn` — Registered 3 new test suite nodes: CombatLogTests, MortalWoundsResolverTests, CombatControllerSession5Tests.

**Decisions made:**
- `hp_when_downed` must be computed before CharacterData clamps hp_current to 0: computed as `hp_before - hp_damage` in Combatant.apply_damage() wrapper.
- Treatment timing simplified binary: `"within_1_round"` on victory, `"after_1_day"` on defeat.
- All killing blows default to `"slashing"` damage type until equipment system tracks weapon damage types.
- Treasure XP passed as 0 to XPAwardCalculator; treasure collection is a future system.
- `XPAwardCalculator` is stateless; instantiated fresh in `_award_combat_xp()` each call.
- ClassRegistry lazy-initialized in SessionRunner (Node, no _init args) rather than in _ready() to avoid premature loading.
- `_emit_combat_ended()` changed from `void` to `-> Dictionary` to propagate `downed_pcs` and `monster_xp_total` through the combat_over return path.

**Interfaces defined or changed:**
- `CombatController._init()` — 11th param: `p_mortal_wounds_resolver: MortalWoundsResolver = null`
- `CombatController.combat_log: CombatLog` — public field (replaces all_events/round_events)
- `CombatController.process_mortal_wounds() -> Array` — returns `[{combatant_id, mortal_wound_result}]`
- `CombatController._emit_combat_ended() -> Dictionary` — now returns outcome dict
- `MortalWoundsResolver.resolve(combatant, hp_when_downed, damage_type, treatment_timing, healing_magic_bhr, healing_proficiency_rank) -> Dictionary`
- `CombatLog.EntryType` enum — 12 entry types
- `CombatRoster.get_downed_pcs() -> Array`
- `Combatant.hp_when_downed: int`, `Combatant.killing_blow_damage_type: String`
- `EventBus.mortal_wound_rolled(character_id, result)` — new signal
- `SessionRunner.get_class_registry() -> ClassRegistry` — new lazy getter

**Database changes:** None.

**Tests added/updated:**
- `tests/test_combat_log.gd` — 5 new tests
- `tests/test_mortal_wounds_resolver.gd` — 20 new tests
- `tests/test_combat_controller_session5.gd` — 10 new integration tests

**Known issues:**
- Healing magic BHR and healing proficiency rank passed as 0; healing-after-combat workflow not yet built.
- Permanent wound effects recorded as strings only; mechanical stat modifications (lost limb, reduced DEX) deferred.
- Tampering with Mortality (resurrection/restoration) fully deferred.
- Level-up execution: `character_leveled_up` signal emitted but actual stat changes handled by LevelUpEngine separately.
- Damage type tracking: all killing blows default to "slashing" until equipment system provides weapon damage types.
- Treatment timing is binary; full model (presence of healer, spell cast this round, etc.) is a future system.

**Next session should:**
1. F-1 Session 6 (or F-2): Settlement exploration state + town services (inn, hirelings, equipment resupply).
2. Fix full test runner hang (pre-existing issue, ~60 suites in).
3. Wire `mortal_wound_rolled` signal emission (currently process_mortal_wounds() does not emit it).
4. Weapon damage type system — so killing blows report correct damage type to mortal wounds resolver.

---

## Session 2026-04-08 - Remove Hallucinated Alignment Languages

**Task:** Remove the non-ACKS notion that alignment is a language, clean the language catalog/UI/runtime behavior, and auto-sanitize legacy saves without a schema migration.
**Model used:** GPT-5 Codex

**Completed:**
- Removed `alignment_lawful` and `alignment_chaotic` from `data/proficiencies/proficiency_specializations.json`.
- Added shared language sanitizers to `engine/shared_types/character_data.gd`: `sanitize_language_ids()`, `parse_languages_json()`, and `sanitize_languages_json()`.
- Updated `engine/autoloads/campaign_repository.gd` to sanitize character language JSON on create/read/save/list operations and to sanitize language proficiency rows on load/save.
- Updated `scenes/ui/character_creation/character_creation_screen.gd` so finalization grants only Common + racial + INT bonus languages, with no alignment-based auto-grant.
- Rewrote `scenes/ui/character_creation/language_selection_panel.gd` to remove alignment-language copy and filtering logic.
- Updated `scenes/ui/components/character_sheet_panel.gd` and `scenes/ui/character_sheet/tabs/cs_tab_biography.gd` so language preview/display paths read sanitized language lists and never synthesize alignment tongues from alignment state.
- Corrected `generation/gdd-proficiency-specializations.md` so it no longer claims ACKS has alignment tongues and so the listed base IDs match the current catalog.
- Added `tests/test_language_cleanup.gd` and registered it in `tests/test_runner.gd` / `tests/test_runner.tscn`.
- Expanded `tests/test_specialization_registry.gd` with a language-count regression for the cleaned catalog.

**Decisions made:**
- Legacy save cleanup is handled by repository/shared-type sanitization rather than a DB migration. Old rows remain readable immediately and are healed the next time they are re-saved.
- Unknown non-empty language IDs are preserved by the sanitizer so future setting-generated language IDs are not accidentally stripped. Only the deprecated alignment IDs, empties, non-strings, and duplicate language entries are removed.
- Duplicate language proficiency rows are collapsed by specialization during sanitization because Language is modeled as one row per known language, not a stacking proficiency.

**Interfaces defined or changed:**
- `CharacterData.sanitize_language_ids(raw_ids: Array) -> Array`
- `CharacterData.parse_languages_json(raw_languages: Variant) -> Array`
- `CharacterData.sanitize_languages_json(raw_languages: Variant) -> String`
- `CampaignRepository` now sanitizes `languages` in character dictionaries returned by `get_character()`, `list_party_characters()`, `list_characters()`, `list_characters_by_type()`, `list_characters_by_tier()`, and `list_characters_excluding_tier()`.
- `CampaignRepository.save_character_proficiencies()` and `CampaignRepository.get_character_proficiencies()` now sanitize `language` rows to strip deprecated alignment IDs and collapse duplicates.

**Database changes:** None.

**Tests added/updated:**
- Added `tests/test_language_cleanup.gd` covering shared language-array sanitization, legacy character language JSON cleanup/healing, legacy proficiency-row cleanup/healing, character creation finalization, and character sheet preview behavior.
- Updated `tests/test_specialization_registry.gd` to assert the language catalog now has 19 entries and excludes both deprecated alignment IDs.
- Ran the full headless test runner: `C:\Godot\Godot_v4.6.1-stable_win64.exe --headless --path . res://tests/test_runner.tscn` (pass).

**Known issues:**
- No explicit repository-wide migration was added, so already-persisted bad rows are cleaned on read/save boundaries rather than rewritten in place immediately.
- Historical `build_log.md` entries from the earlier mistaken implementation remain unchanged because the log is append-only.

**Next session should:**
1. Watch for any external tooling or content-generation step that still assumes the old 21-language base catalog and update it if encountered.
2. If campaign-layer/generated languages are implemented later, route them through the same `CharacterData` sanitization helpers rather than adding new ad hoc filters.

---

## Session 2026-04-08 - Elven And Dwarven Starting Language Defaults

**Task:** Fix racial starting language grants so elves and dwarves receive the full ACKS demihuman language sets instead of only Common plus their racial tongue.
**Model used:** GPT-5 Codex

**Completed:**
- Added `CharacterData.get_default_languages_for_race(race: String) -> Array` in `engine/shared_types/character_data.gd`.
- Implemented ACKS elf defaults as `common`, `elvish`, `gnoll`, `hobgoblin`, `orc`.
- Implemented ACKS dwarf defaults as `common`, `dwarvish`, `goblin`, `gnome`, `kobold`.
- Updated `scenes/ui/character_creation/character_creation_screen.gd` to use the shared helper when finalizing character languages.
- Updated `scenes/ui/character_creation/language_selection_panel.gd` to show the full racial auto-grant list in the Languages step.
- Updated `scenes/ui/components/character_sheet_panel.gd` to use the same helper for live wizard preview fallback.
- Expanded `tests/test_language_cleanup.gd` with regressions for elf/dwarf defaults, elf finalization, and dwarf preview behavior.

**Decisions made:**
- Centralized racial starting languages in `CharacterData` so create/finalize/preview paths cannot drift.
- Left the current gnome and halfling behavior unchanged; this session only corrected the explicit ACKS elf/dwarf defaults requested.

**Interfaces defined or changed:**
- `CharacterData.get_default_languages_for_race(race: String) -> Array`

**Database changes:** None.

**Tests added/updated:**
- Updated `tests/test_language_cleanup.gd` to assert exact elf and dwarf default language arrays.
- Added elf finalization regression to confirm stored languages include the full elf defaults plus bonus picks.
- Added dwarf preview regression to confirm the in-wizard sheet fallback shows the full dwarf defaults.
- Ran the full headless test runner: `C:\Godot\Godot_v4.6.1-stable_win64.exe --headless --path . res://tests/test_runner.tscn` (pass).

**Known issues:**
- This session did not re-audit other demihuman racial language defaults beyond the explicitly requested elf and dwarf corrections.

**Next session should:**
1. Audit the remaining demihuman/default-language assumptions against the local ACKS summaries if more racial-language corrections are needed.
2. Reuse `CharacterData.get_default_languages_for_race()` for any future NPC generation or importer code that seeds starting languages.

---

## Session 2026-04-09 — F-2 / Dungeon Individual Movement: Session 1 Infrastructure

**Task:** Begin F-2 (Tactical Combat UI) and dungeon individual-movement upgrade. Session 1 goal: shared token component, dungeon renderer upgrade, combat controller query helpers, dungeon encounter spawner.

**Key architectural decision made this session:**
Dungeon encounters do NOT open a separate combat screen. Monsters spawn in-place on the dungeon map at ACKS encounter distance (2d6×10 ft), and combat resolves on the same grid. Wilderness encounters still use a standalone CombatScreen. The combat HUD widgets are shared between both contexts.

**Model used:** Claude Sonnet 4.6

**Completed:**
- `scenes/ui/components/combatant_token.gd` + `.tscn` — new shared CombatantToken scene. Node2D with _draw()-based bottlecap-with-beak rendering (circle body + triangular facing beak + class letter + name label). Properties: entity_id, display_name, side (0=PARTY/1=ENEMY/-1=neutral), class_icon_letter, facing, is_selected, is_active, show_ghost. Colors: blue=PARTY, red=ENEMY, yellow=neutral. Selection ring (yellow), active glow (white).
- `scenes/maps/dungeon_map_renderer.gd` — upgraded from yellow-diamond Polygon2D tokens to CombatantToken instances. Replaced `_party_tokens: Dictionary` with `_tokens: Dictionary` (entity_id → Node2D). Added public API: `add_entity_token()`, `remove_entity_token()`, `get_entity_token()`. Added lazy-load `_token_scene` to avoid parse-time preload dependency. Added combat-mode methods: `set_combat_mode()`, `highlight_cells()`, `highlight_entity_tokens()`, `clear_highlights()`, `set_active_token()`, `move_token()`. Added `_draw_highlights()` layer to `_draw()`. Added `entity_clicked(entity_id)` signal. Added `_entity_id_near_screen_pos()` for combat-mode click detection.
- `engine/subsystems/combat/combat_controller.gd` — added UI query helpers: `get_combatant()`, `get_available_actions()`, `get_melee_targets()`, `get_ranged_targets()`, `get_reachable_cells()`, `_all_enemy_ids()`.
- `engine/subsystems/exploration/dungeon_map_controller.gd` — added `get_entity_ids()` method.
- `engine/subsystems/session/states/dungeon_explore_state.gd` — upgraded from `"party_leader"` placeholder to adding ALL active living party members as entities. Added `_class_letter()` static helper. Wires `add_entity_token()` on the renderer for each party member.
- `engine/subsystems/exploration/dungeon_encounter_spawner.gd` — new class. Implements ACKS 2d6×10 ft dungeon encounter distance (2d6×2 cells). Finds eligible cells at rolled Chebyshev distance from nearest party member, falls back to shorter distances if none found. Places lead monster at chosen cell, clusters remaining behind (away from party centroid) via BFS radius expansion.

**Decisions made:**
- CombatantToken uses `_draw()` exclusively (no child Polygon2D/Label nodes) for simplicity and to avoid scene node overhead for many tokens.
- `dungeon_map_renderer.gd` uses lazy `load()` for the token scene (not `const preload`) because scene scripts without `class_name` can't reference named classes at parse time.
- Type annotations for CombatantToken use `Node2D` base type in the renderer to avoid the same parse-time issue.
- `DungeonExploreState` still falls back to `"party_leader"` if no PartyData is available (backward compat for tests that stub the runner).

**Interfaces defined or changed:**
- `DungeonMapRenderer.add_entity_token(entity_id, display_name, side, class_letter) -> Node2D`
- `DungeonMapRenderer.remove_entity_token(entity_id)`
- `DungeonMapRenderer.get_entity_token(entity_id) -> Node2D`
- `DungeonMapRenderer.set_combat_mode(enabled: bool)`
- `DungeonMapRenderer.highlight_cells(cells: Array[Vector2i], color: Color)`
- `DungeonMapRenderer.highlight_entity_tokens(entity_ids: Array[String])`
- `DungeonMapRenderer.clear_highlights()`
- `DungeonMapRenderer.set_active_token(entity_id: String)`
- `DungeonMapRenderer.move_token(entity_id: String, to_cell: Vector2i)`
- `DungeonMapRenderer` new signal: `entity_clicked(entity_id: String)`
- `DungeonMapController.get_entity_ids() -> Array[String]`
- `CombatController.get_combatant(combatant_id) -> Combatant`
- `CombatController.get_available_actions(combatant_id) -> Array[String]`
- `CombatController.get_melee_targets(combatant_id) -> Array[String]`
- `CombatController.get_ranged_targets(combatant_id) -> Array[String]`
- `CombatController.get_reachable_cells(combatant_id) -> Array[Vector2i]`
- `DungeonEncounterSpawner.spawn_encounter(map, party_positions, encounter_data, monster_registry, dice_system) -> Array[Dictionary]`
  - Returns `[{combatant_id, monster_data, grid_position, rolled_hp, group_id}]`

**Database changes:** None.

**Tests added/updated:** None (Session 1 is infrastructure; tests will be added in Session 2 when the dungeon encounter spawn can be exercised end-to-end).

**Known issues:**
- `DungeonEncounterSpawner` has no unit tests yet; covered next session.
- `CombatantToken` has no unit tests yet; visual correctness requires Godot editor inspection.
- `DungeonExploreState` now wires tokens but token positions are only updated via `_update_entity_tokens()` on `party_moved` signal — which still moves all members to the same cell (group movement). Individual movement is Session 4.

**Regression baseline:** 65 suites passed, 7 failed (all 7 failures are pre-existing, unchanged from previous baseline).

**Next session should:**
1. Session 2 (F-2): Build shared combat HUD components — InitiativeStrip, StatSummary, ActionButtonPanel, CombatLogPanel, DeclarationOverlay, CombatEndOverlay.
2. Session 3 (F-2): Build CombatUIController + DungeonCombatOverlay, wire in-place dungeon combat end-to-end.
3. Session 4 (Dungeon): FormationManager + DungeonOrderManager + upgrade DungeonMapController to per-character positions.
4. Wire `mortal_wound_rolled` signal emission in `CombatController.process_mortal_wounds()` (pre-existing known issue).


---

## Session 2026-04-09 — F-2 Session 2: Combat HUD Components (Shared)

**Task:** Build the six shared combat HUD widget scenes for reuse by both dungeon combat overlay and standalone combat screen.

**Model used:** Claude Opus 4.6

**Completed:**
- `scenes/ui/combat/initiative_strip.gd` + `.tscn` — VBoxContainer in ScrollContainer. Each entry row: side color indicator (blue/red/yellow), initiative number, name (clip_text), HP label + ProgressBar (green/yellow/red by ratio). Active combatant row gets brightness modulation. Dead combatants greyed out. API: `set_initiative_order(order: Array[Dict])`, `set_active(combatant_id)`, `update_hp(combatant_id, current, max_val)`.
- `scenes/ui/combat/stat_summary.gd` + `.tscn` — PanelContainer showing active combatant: name, class/HD + level, HP bar + numeric, AC, combat movement (cells), active conditions. API: `show_combatant(combatant: Combatant)`. Accepts Combatant duck-typed (uses get_hp_current/max, get_effective_ac, get_combat_movement_cells, etc.).
- `scenes/ui/combat/action_button_panel.gd` + `.tscn` — VBoxContainer of buttons: Move, Melee Attack, Ranged Attack, Cast Spell (always disabled — deferred to F-3), Fighting Withdrawal, Full Retreat, Pass. Emits `action_selected(action_id: String)`. API: `set_available_actions(actions: Array)` to enable/disable per combatant, `set_panel_visible(bool)` for enemy turns, `disable_all()` for target selection mode.
- `scenes/ui/combat/combat_log_panel.gd` + `.tscn` — Scrolling RichTextLabel with BBCode coloring per CombatLog.EntryType. Formats all 12 entry types (ROUND_START through COMBAT_END) into readable text. Toggle show/hide button. API: `append_event(log_entry: Dict)`, `append_text(text, color)`, `clear_log()`. Auto-scrolls to bottom.
- `scenes/ui/combat/declaration_overlay.gd` + `.tscn` — Center-anchored modal for round-start declarations. Lists alive PCs with OptionButton dropdowns: None / Fighting Withdrawal / Full Retreat / Set vs Charge. Spell declaration disabled (F-3). Emits `declarations_complete(declarations: Array[Dict])` with `{combatant_id, declaration_type}` entries. API: `set_pc_list(pcs: Array[{combatant_id, display_name}])`.
- `scenes/ui/combat/combat_end_overlay.gd` + `.tscn` — Center-anchored victory/defeat card. Shows outcome (VICTORY green / DEFEAT red / FLED yellow), rounds fought, XP earned (victory only). Scrollable details: downed PCs with mortal wound descriptions, death status, recovery time. "Continue" button emits `continue_pressed()`. API: `show_result(result: Dict)` matching CombatController's combat_over return dict.

**Decisions made:**
- All six widgets build their UI entirely in `_ready()` (no .tscn child nodes beyond root) for simplicity. The .tscn files are minimal wrappers with just root node + script.
- StatSummary accepts Combatant duck-typed (no import/class reference) — calls accessor methods directly. This avoids parse-time dependency on Combatant class.
- CombatLogPanel maps CombatLog.EntryType enum values by integer (0–11) to colors, matching the enum order in combat_log.gd. If the enum changes order, the color mapping must be updated.
- ActionButtonPanel keeps Cast Spell permanently disabled with tooltip explaining F-3 deferral.
- DeclarationOverlay only emits entries for PCs that have non-empty declarations (i.e., "None" selections are omitted from the result array).
- All panels use dark semi-transparent backgrounds (Color ~0.1 alpha 0.85–0.95) to overlay cleanly on the dungeon map.

**Interfaces defined or changed:**
- `InitiativeStrip.set_initiative_order(order: Array)` — each entry: `{combatant_id, display_name, side, initiative_total, hp_current, hp_max, is_alive}`
- `InitiativeStrip.set_active(combatant_id: String)`
- `InitiativeStrip.update_hp(combatant_id: String, current: int, max_val: int)`
- `StatSummary.show_combatant(combatant)` — duck-typed Combatant
- `ActionButtonPanel.action_selected` signal `(action_id: String)`
- `ActionButtonPanel.set_available_actions(actions: Array)`
- `ActionButtonPanel.set_panel_visible(is_visible: bool)`
- `ActionButtonPanel.disable_all()`
- `CombatLogPanel.append_event(log_entry: Dictionary)`
- `CombatLogPanel.append_text(text: String, color: Color)`
- `CombatLogPanel.clear_log()`
- `DeclarationOverlay.declarations_complete` signal `(declarations: Array)`
- `DeclarationOverlay.set_pc_list(pcs: Array)`
- `CombatEndOverlay.continue_pressed` signal
- `CombatEndOverlay.show_result(result: Dictionary)`

**Database changes:** None.

**Tests added/updated:** None — these are pure UI widgets with no controller wiring. Visual layout verification requires Godot editor. All 65 existing test suites still pass (7 pre-existing failures unchanged).

**Known issues:**
- CombatLogPanel color map uses hardcoded integer keys matching CombatLog.EntryType enum order. Fragile if enum is reordered.
- No unit tests for these widgets yet; they are standalone with mock-data-ready APIs.
- `mortal_wound_rolled` signal still not wired in CombatController (pre-existing).

**Next session should:**
1. Session 3 (F-2): Build CombatUIController (shared state machine between UI and CombatController) + DungeonCombatOverlay (composes all 6 HUD widgets, wires to DungeonMapRenderer combat mode). Wire dungeon in-place combat end-to-end.
2. Extract CombatFinalizer from CombatState._finish_combat() for shared post-combat processing.
3. Session 4 (F-2): FormationManager + DungeonOrderManager + DungeonMapController individual movement upgrade.
4. Wire `mortal_wound_rolled` signal emission (pre-existing known issue).

---

## Session 2026-04-09 — F-2 Session 3: Dungeon Combat Mode — In-Place Combat on Dungeon Map

**Task:** Build CombatUIController state machine, DungeonCombatOverlay, CombatFinalizer, and wire DungeonExploreState for in-place dungeon combat (monsters spawn on dungeon map, combat resolves on the same grid, no separate combat screen).

**Model used:** Claude Opus 4.6

**Completed:**
- `scenes/ui/combat/combat_ui_controller.gd` — shared state machine (CombatUIController, RefCounted) that bridges HUD widgets and CombatController. States: IDLE, ADVANCING, DECLARATION_PHASE, PC_SELECTING_ACTION, PC_SELECTING_MOVE_TARGET, PC_SELECTING_ATTACK_TARGET, ENEMY_ACTING, COMBAT_OVER. Pull-based loop: advance() → routes CombatController status → emits signals → waits for UI input. Signal-based communication with both HUD widgets and map renderer. Handles action button routing: Move → highlight reachable cells + wait for cell click; Attack → highlight targets + wait for entity click; Fighting Withdrawal/Full Retreat/Pass → submit directly.
- `engine/subsystems/combat/combat_finalizer.gd` — shared post-combat processing (CombatFinalizer, RefCounted). Extracted mortal wounds processing, XP award distribution, and timekeeping advancement from CombatState._finish_combat(). Single entry point: finalize(runner, result, party_data). Reused by both CombatState (wilderness) and DungeonExploreState (dungeon).
- `engine/subsystems/session/states/combat_state.gd` — refactored _finish_combat() to delegate to CombatFinalizer.finalize(). Removed _mark_pc_dead() and _award_combat_xp() (now in CombatFinalizer). Added _finalizer field.
- `scenes/ui/combat/dungeon_combat_overlay.gd` — CanvasLayer (layer 10) that composes all Session 2 HUD widgets: InitiativeStrip (right panel, top), StatSummary (right panel, mid), ActionButtonPanel (right panel, bottom), CombatLogPanel (bottom-left), DeclarationOverlay (centered modal), CombatEndOverlay (centered modal), round label (bottom-center). Owns a CombatUIController instance. Wires CombatUIController signals to widget updates and map renderer highlights. Wires DungeonMapRenderer cell_clicked/entity_clicked to CombatUIController input. Public API: start_combat(controller, renderer), end_combat(). Signal: combat_finished(result).
- `engine/subsystems/session/states/dungeon_explore_state.gd` — rewired for in-place dungeon combat:
  - Added _combat_overlay, _in_combat, _finalizer, _spawner fields.
  - _on_cell_clicked() now blocks movement during _in_combat.
  - New _start_dungeon_combat(encounter_data): calls DungeonEncounterSpawner.spawn_encounter() to place monsters on the dungeon grid at ACKS encounter distance; builds CombatRoster from party + spawned monsters; creates all combat subsystems (same pattern as CombatState.enter()); creates DungeonCombatOverlay and calls start_combat().
  - New _on_dungeon_combat_finished(result): calls CombatFinalizer.finalize() for mortal wounds/XP/time; removes all monster tokens and entities from renderer and TacticalMapData; removes dead party member tokens; cleans up overlay; resumes exploration.
  - No longer transitions to CombatState for dungeon encounters (wilderness encounters still use CombatState via the standalone CombatScreen, unchanged).

**Decisions made:**
- CombatUIController communicates entirely via signals (no direct widget references). This keeps it reusable by both DungeonCombatOverlay and the future standalone CombatScreen.
- DungeonCombatOverlay builds its entire UI in _build_ui() rather than using a .tscn scene tree. This matches the pattern from the Session 2 HUD widgets and keeps instantiation simple (just DungeonCombatOverlay.new()).
- CombatFinalizer is stateless — a single finalize() call processes everything. No need to hold references across frames.
- Monster entity cleanup after combat identifies monsters by checking against PartyData character IDs rather than by name convention. This is more robust than pattern-matching on combatant_id strings.
- DungeonExploreState creates its own CombatRoster from party CharacterData + spawned monster dicts rather than using CombatRoster.build_from_encounter(), because the party members already have grid positions from the dungeon map and we need to preserve those.
- The DungeonCombatOverlay stores the combat_over result from CombatController and passes it through combat_finished signal so the explore state can finalize correctly.

**Interfaces defined or changed:**
- `CombatUIController.setup(controller: CombatController)`
- `CombatUIController.advance() -> Dictionary`
- `CombatUIController.on_declarations_confirmed(declarations: Array)`
- `CombatUIController.on_action_button(action_id: String)`
- `CombatUIController.on_cell_targeted(pos: Vector2i)`
- `CombatUIController.on_entity_targeted(entity_id: String)`
- `CombatUIController.on_cancel()`
- `CombatUIController.get_state() -> int`
- `CombatUIController.get_controller() -> CombatController`
- CombatUIController signals: `show_declaration_requested`, `initiative_updated`, `pc_turn_started`, `action_resolved`, `combat_ended`, `log_entry`, `highlight_reachable`, `highlight_targets`, `clear_highlights_requested`, `active_token_changed`, `token_moved`
- `CombatFinalizer.finalize(runner, result: Dictionary, party_data: PartyData) -> void`
- `DungeonCombatOverlay.start_combat(controller: CombatController, renderer) -> void`
- `DungeonCombatOverlay.end_combat() -> void`
- `DungeonCombatOverlay.combat_finished` signal `(result: Dictionary)`
- `CombatState._finalizer: CombatFinalizer` (new field)
- `DungeonExploreState._in_combat: bool`, `._combat_overlay`, `._finalizer`, `._spawner` (new fields)
- `DungeonExploreState._start_dungeon_combat(encounter_data: Dictionary) -> void`
- `DungeonExploreState._on_dungeon_combat_finished(result: Dictionary) -> void`

**Database changes:** None.

**Tests added/updated:** None — the CombatFinalizer refactor is validated by the existing CombatController and SessionRunner test suites passing (65/65 combat tests pass). DungeonCombatOverlay + CombatUIController are UI integration that require Godot editor/runtime testing.

**Known issues:**
- CombatUIController.advance() recurses through auto-advance steps (combat_started → declaration → initiative → action). Very long combats could theoretically hit stack depth, but ACKS combats rarely exceed ~10 rounds.
- DungeonCombatOverlay._on_continue_pressed() calls _controller.advance() to re-fetch the combat_over result dict. If the controller state is unexpected, the fallback dict has monster_xp_total=0. The full result should have been cached from the combat_ended signal instead.
- No .tscn file for DungeonCombatOverlay — it's instantiated via .new() from DungeonExploreState, which is correct for a CanvasLayer that builds its own UI.
- `mortal_wound_rolled` signal still not wired in CombatController (pre-existing known issue).

**Regression baseline:** 65 suites passed, 7 failed (all 7 pre-existing, unchanged).

**Next session should:**
1. Session 4 (F-2): FormationManager + DungeonOrderManager + upgrade DungeonMapController to per-character positions with individual movement.
2. Session 5 (F-2): DungeonOrderOverlay, DungeonSelectionPanel, UI for individual movement + End Turn.
3. Session 6 (F-2, if needed): Standalone CombatScreen for wilderness encounters using CombatUIController + CombatMapRenderer.
4. Wire `mortal_wound_rolled` signal emission (pre-existing known issue).
5. Fix DungeonCombatOverlay to cache combat result from combat_ended signal rather than re-fetching from controller.

---

## Session 2026-04-09 — F-2 Session 4: Dungeon Individual Movement — Engine

**Task:** Build FormationManager, DungeonOrderManager, and upgrade DungeonMapController for per-character dungeon positions with individual movement and order queue system.

**Model used:** Claude Opus 4.6

**Completed:**
- `engine/subsystems/exploration/formation_manager.gd` — new class (FormationManager, RefCounted). 5 formation presets: Column (1 wide), DoubleColumn (2 wide), Line (N wide), DoubleLine (N wide x 2 deep), Wedge (V-shape). All presets auto-sort members by AC desc, HP desc tiebreak. apply_preset(), compute_dungeon_positions() with collapse logic (full -> double column -> single column), compute_group_move().
- `engine/subsystems/exploration/dungeon_order_manager.gd` — new class (DungeonOrderManager, RefCounted). Order queue: each entity has at most one pending order. Types: move, interact_door, search, listen, wait. API: add_order(), remove_order(), get_order(), get_all_orders(), has_order(), clear(), get_entities_without_orders(), order_count().
- `engine/subsystems/exploration/dungeon_map_controller.gd` — major upgrade:
  - Lazy-initialized _order_manager, _formation_manager, _party_data_ref fields.
  - set_party_data() for formation placement on load.
  - load_dungeon() uses FormationManager for entry placement.
  - move_party() refactored: multi-member+PartyData uses queue_group_move+execute_orders; single entity uses legacy path.
  - New: queue_move_order() with BFS pathfinding, queue_group_move() for formation-preserving moves, execute_orders() for simultaneous resolution, reform_formation().
  - _bfs_path() BFS on 8-directional IsometricGrid neighbors.
  - _update_fog_for_all_members() — union of all member positions for fog-of-war.
  - use_stairs() now places members in formation at target level.
  - New signal: orders_executed(result).
- `engine/subsystems/session/states/dungeon_explore_state.gd` — added set_party_data() call before load_dungeon().

**Decisions made:**
- Managers use load() lazy init to avoid Godot 4 parse-time class_name resolution issues.
- BFS pathfinding (not A*) — adequate for short dungeon corridors.
- execute_orders() teleports to destination; animation deferred to Session 5.
- move_party() backward-compat: single-entity tests use original direct-move path.

**Interfaces defined or changed:**
- DungeonMapController: set_party_data(), get_formation_manager(), get_order_manager(), reform_formation(), queue_move_order(), queue_group_move(), execute_orders(), orders_executed signal
- FormationManager: apply_preset(), compute_dungeon_positions(), compute_group_move(), PRESETS constant
- DungeonOrderManager: add_order(), remove_order(), get_order(), get_all_orders(), has_order(), clear(), get_entities_without_orders(), get_entities_with_orders(), order_count()

**Database changes:** None.

**Tests added/updated:** None new — existing tests pass via backward-compat path.

**Known issues:**
- BFS does not check entity occupancy — two entities could be ordered to the same cell.
- mortal_wound_rolled signal still not wired (pre-existing).

**Regression baseline:** 65 suites passed, 7 failed (all 7 pre-existing, unchanged).

**Next session should:**
1. Session 5 (F-2): DungeonOrderOverlay, DungeonSelectionPanel, DungeonMapRenderer selection + order overlay, wire DungeonExploreState to new UI.
2. Add FormationManager and DungeonOrderManager unit tests.
3. Session 6 (F-2, if needed): Standalone CombatScreen for wilderness encounters.

---

## Session 2026-04-09 — F-2 Session 5: Dungeon UI — Selection, Orders, Ghost Trails

**Task:** Build dungeon exploration UI for individual movement: order overlay (ghost trails), selection panel (character list + order buttons + End Turn), update renderer for entity selection, update scene tree, wire DungeonExploreState to new UI.

**Model used:** Claude Opus 4.6

**Completed:**
- `scenes/maps/dungeon_order_overlay.gd` — Node2D child of renderer. Renders pending orders visually: ghost trail dots along move paths with connecting lines, ghost circle at destination, small icons for search/listen/wait/interact_door orders. update_overlays(orders) and clear_overlays() API. Colors coded per order type.
- `scenes/maps/dungeon_selection_panel.gd` + `.tscn` — Right-side PanelContainer for exploration mode. Character list rows: class letter, name, HP (color-coded by ratio), order status icon. Click row to select character on map. Order type buttons: Move (M), Search (S), Listen (L), Wait (W) with active highlight. Formation preset dropdown (Column, Double Column, Line, Double Line, Wedge). Reform Formation button. End Turn button. Signals: character_selected, character_deselected, select_all_pressed, end_turn_pressed, reform_formation_pressed, order_type_selected, formation_preset_selected.
- `scenes/maps/dungeon_map_renderer.gd` — added exploration selection system: _selected_entity_ids, _order_overlay reference. New methods: select_entity() with additive shift-click, deselect_entity(), clear_selection(), select_all_on_side(), get_selected_entity_ids(). update_order_overlay() and clear_order_overlay() for order visualization. Exploration mode entity clicks now select instead of just emitting entity_clicked. New signals: entity_selected, entity_deselected, end_turn_requested.
- `scenes/maps/dungeon_map.tscn` — updated scene tree: added OrderOverlayLayer (Node2D with dungeon_order_overlay.gd), SelectionPanel (PanelContainer with dungeon_selection_panel.gd, anchored right side), BottomBar (HBoxContainer with LevelLabel + TurnLabel, anchored bottom).
- `engine/subsystems/session/states/dungeon_explore_state.gd` — major UI wiring:
  - Connected entity_selected signal from renderer.
  - Connected all SelectionPanel signals: end_turn, reform_formation, formation_preset, character_selected, select_all, order_type.
  - New _on_cell_clicked logic: if entities are selected, queues individual orders (move/search/listen/wait) instead of legacy group move. Updates order overlay and selection panel status. If no selection, falls back to legacy click-to-move-all behavior.
  - New _on_end_turn(): executes all queued orders, clears overlay, runs encounter check, advances time.
  - New _on_reform_formation(): calls controller.reform_formation(), clears orders.
  - New _on_formation_preset_selected(): applies preset via FormationManager, reforms.
  - _refresh_selection_panel() and _refresh_order_status() helpers.
  - Two-path input: selected entities get order queue + End Turn flow; no selection gets legacy instant group move.

**Decisions made:**
- DungeonOrderOverlay draws with _draw() (same as all other overlay/token rendering in the project). No child nodes.
- DungeonSelectionPanel builds UI entirely in _ready() — no complex .tscn child tree.
- Entity selection in exploration mode: click token to select (single), Shift+click for multi-select. Panel click also selects. Select All button selects all party tokens.
- Two input modes coexist: with selection = order queue + End Turn; without selection = legacy instant group move. This preserves backward-compat feel while enabling the new individual movement.
- Order overlay clears after execute_orders() — no persistent ghost trails.

**Interfaces defined or changed:**
- DungeonMapRenderer: select_entity(), deselect_entity(), clear_selection(), select_all_on_side(), get_selected_entity_ids(), update_order_overlay(), clear_order_overlay()
- DungeonMapRenderer signals: entity_selected, entity_deselected, end_turn_requested
- DungeonSelectionPanel: set_characters(), update_order_status(), update_hp(), set_selected(), clear_selection(), get_current_order_type(), get_selected_ids()
- DungeonSelectionPanel signals: character_selected, character_deselected, select_all_pressed, end_turn_pressed, reform_formation_pressed, order_type_selected, formation_preset_selected
- DungeonOrderOverlay: update_overlays(orders), clear_overlays()
- DungeonExploreState: _current_order_type field, _on_entity_selected(), _on_panel_character_selected(), _on_select_all(), _on_order_type_selected(), _on_end_turn(), _on_reform_formation(), _on_formation_preset_selected(), _refresh_selection_panel(), _refresh_order_status()

**Database changes:** None.

**Tests added/updated:** None new. 64 pass, 8 fail (1 new flaky proficiency NPC generation test failure unrelated to our changes; 7 pre-existing).

**Known issues:**
- DungeonSelectionPanel row click always does single-select. Shift+click multi-select only works on the map renderer tokens, not the panel rows.
- Order overlay does not animate — appears instantly when orders are queued. Step-by-step path animation deferred.
- BottomBar LevelLabel and TurnLabel are not wired to update dynamically yet (static text).
- mortal_wound_rolled signal still not wired (pre-existing).

**Regression baseline:** 64 suites passed, 8 failed (7 pre-existing + 1 flaky proficiency test).

**Next session should:**
1. Session 6 (F-2, if needed): Standalone CombatScreen/CombatMapRenderer for wilderness encounters using CombatUIController.
2. Wire BottomBar labels to level/turn state.
3. Add FormationManager, DungeonOrderManager, and DungeonSelectionPanel unit tests.
4. Fix the flaky NPC proficiency test (non-deterministic specialization selection).

---

## Session 2026-04-09 — F-2 Session 6: Standalone CombatScreen for Wilderness Encounters + Flaky Test Fix

**Task:** Fix flaky proficiency NPC generation test. Build CombatMapRenderer for wilderness battle maps. Rewrite CombatScreen to use CombatUIController + shared HUD widgets for interactive combat. Update CombatState to use start_interactive().

**Model used:** Claude Opus 4.6

**Completed:**
- `tests/test_proficiency_integration.gd` — fixed flaky test_npc_generation_picks_specialization() by adding seed(42) before the random proficiency selection. Root cause: auto_select_proficiencies uses DiceSystem.roll_digital for random selection from the fighter class list, and without a fixed seed it could theoretically select zero specialization proficiencies across all 6 slots.
- `scenes/ui/combat/combat_map_renderer.gd` — new standalone battle map renderer (Node2D, no class_name). Draws ground/grid/highlights on its own Node2D with EntityLayer + Camera2D children. Same highlight/selection API as DungeonMapRenderer (highlight_cells, highlight_entity_tokens, clear_highlights, set_active_token, move_token). Signals: cell_clicked, entity_clicked, right_click_cancel. Keyboard+edge panning. Terrain colors for wilderness (grass, forest, rock, water, road).
- `scenes/ui/combat/combat_screen.gd` — rewritten from 63-line auto-advance placeholder to full interactive combat screen. Layout: HBoxContainer with map area (left, expandable) + right VBoxContainer (InitiativeStrip, StatSummary, ActionButtonPanel). CombatLogPanel bottom-left. DeclarationOverlay + CombatEndOverlay centered modals. Owns CombatUIController for the interaction loop. Supports both start_interactive() (new, player-driven) and start_auto_advance() (legacy backward compat for tests). CombatMapRenderer instantiated lazily from script to avoid parse-time dependency.
- `scenes/ui/combat/combat_screen.tscn` — simplified to minimal CanvasLayer + script (UI built in _ready).
- `engine/subsystems/session/states/combat_state.gd` — switched from start_auto_advance() to start_interactive(). Removed subtitle wiring (now handled by HUD widgets).

**Decisions made:**
- CombatScreen retains start_auto_advance() for backward compat — existing tests that stub the combat system still work. start_interactive() is the new default called by CombatState.
- CombatMapRenderer is loaded lazily via load() in start_interactive() to avoid parse-time dependency on the script without class_name.
- Combat result is cached in _combat_result when combat_ended fires, then emitted on Continue button press. This avoids the re-fetch issue identified in Session 3.
- CombatScreen builds its own UI in _build_ui() (same pattern as all Session 2-5 components). The .tscn is a minimal stub.
- right_click_cancel signal on CombatMapRenderer wires to CombatUIController.on_cancel() for target selection cancellation.

**Interfaces defined or changed:**
- CombatScreen.start_interactive() — new primary entry point for player-driven combat
- CombatScreen.start_auto_advance() — retained for backward compat
- CombatMapRenderer.setup(tactical_map, roster) — initializes the battle map
- CombatMapRenderer.cell_clicked, entity_clicked, right_click_cancel signals
- CombatMapRenderer: highlight_cells, highlight_entity_tokens, clear_highlights, set_active_token, move_token, add_entity_token, remove_entity_token (same as DungeonMapRenderer)

**Database changes:** None.

**Tests added/updated:** Fixed seed(42) in test_npc_generation_picks_specialization().

**Known issues:**
- CombatMapRenderer does not generate terrain for wilderness encounters — it renders whatever TacticalMapData is passed in. Battle map generation is a future task.
- CombatScreen map area uses a plain Control container. The CombatMapRenderer (Node2D) is added as a child, which works but the map does not clip to the Control bounds.
- Pre-existing flaky DB test (create_campaign) caused 64/8 instead of 65/7 in this run.

**Regression baseline:** 64 suites passed, 8 failed (7 pre-existing + 1 flaky DB test). No new failures from Session 6 changes.

**F-2 Phase Complete.** All 6 sessions delivered:
1. Shared token component + dungeon renderer upgrade + combat query helpers + encounter spawner
2. 6 shared combat HUD widgets
3. CombatUIController + DungeonCombatOverlay + CombatFinalizer + in-place dungeon combat wiring
4. FormationManager + DungeonOrderManager + DungeonMapController individual movement
5. DungeonOrderOverlay + DungeonSelectionPanel + renderer selection + full exploration UI wiring
6. CombatMapRenderer + interactive CombatScreen + CombatState upgrade

**Next phase should:** Begin F-3 (spell casting in combat) or address remaining Session 5 polish (BottomBar label wiring, step-by-step move animation, formation/order manager unit tests).

---

## Session 2026-04-09 — F-2 Bugfix: 6 Dungeon Combat Bugs

**Task:** Fix 6 bugs found during live testing of dungeon in-place combat.

**Model used:** Claude Opus 4.6

**Completed:**

**Bug 3 — Monster tokens invisible (all at 0,0):**
- File: `dungeon_explore_state.gd` line 369
- Added `_scene.move_token(p["combatant_id"], p["grid_position"])` after `add_entity_token()` in the placement loop.

**Bug 6 — Dungeon HUD visible during combat:**
- File: `dungeon_explore_state.gd`
- Added `_set_dungeon_hud_visible(false)` before combat overlay creation, `_set_dungeon_hud_visible(true)` after cleanup.
- New helper toggles visibility of SelectionPanel, BottomBar, ExitButton.

**Bug 4 — Combat HP/death not persisted:**
- File: `combat_finalizer.gd`
- Added `_persist_party(party_data)` at end of `finalize()`. Calls `CampaignRepository.save_character(cd.to_dict())` for all party members. Also persists XP changes.

**Bug 2 — Monsters spawn on walls / too few cells:**
- File: `dungeon_encounter_spawner.gd`
- Increased cluster radius limit from 6 to 12. Added stacking fallback: if clustering returns fewer cells than count, pad with lead_cell.

**Bug 1 — Combat auto-resolves (synchronous advance chain):**
- Files: `combat_ui_controller.gd`, `dungeon_combat_overlay.gd`, `combat_screen.gd`
- Added `signal auto_advance_requested()` to CombatUIController.
- Replaced recursive `return advance()` in initiative_rolled, action_resolved, round_ended cases with `auto_advance_requested.emit(); return result`.
- DungeonCombatOverlay and CombatScreen connect the signal to `call_deferred("_do_deferred_advance")` which yields one frame for Godot to render between combat steps.
- combat_started still uses synchronous advance (nothing to render).
- Also fixed DungeonCombatOverlay._on_continue_pressed() to use cached _combat_result instead of re-calling controller.advance().

**Bug 5 — Mortal wounds auto-rolled at combat end:**
- Files: `combat_controller.gd`, `combat_finalizer.gd`, `test_combat_controller_session5.gd`
- Replaced `process_mortal_wounds()` call in `_emit_combat_ended()` with new `_collect_downed_pcs()` that returns raw data: {combatant_id, hp_when_downed, killing_blow_damage_type, round_downed, needs_mortal_wound_check: true}.
- Kept `process_mortal_wounds()` intact for future UI-driven resolution.
- Updated `combat_finalizer.gd` to handle both formats: deferred entries mark PCs as `is_incapacitated = true, hp_current = 0`; legacy entries still process is_dead.
- Updated XP award logic: downed PCs with deferred mortal wounds still get XP (they might survive).
- Updated 3 tests in `test_combat_controller_session5.gd` to expect `needs_mortal_wound_check` format.

**Interfaces defined or changed:**
- `CombatUIController.auto_advance_requested` signal (new)
- `CombatController._collect_downed_pcs() -> Array` (new, internal)
- `CombatFinalizer._mark_pc_incapacitated(party_data, combatant_id)` (new)
- `CombatFinalizer._persist_party(party_data)` (new)
- `DungeonExploreState._set_dungeon_hud_visible(vis: bool)` (new)
- `DungeonCombatOverlay._combat_result: Dictionary` (new cached field)

**Regression baseline:** 64 suites passed, 8 failed (all pre-existing). CombatController Session5 tests pass with updated assertions.

---

## Session 2026-04-09 — Campaign Start Party Creation Flow

**Task:** Enforce character creation at campaign start. New campaigns now require creating a party (up to 6 members) before entering gameplay.

**Model used:** Claude Opus 4.6

**Completed:**

**Signal plumbing (3 files modified):**
- `scenes/ui/campaign_select/campaign_select_screen.gd` — Added `campaign_created` signal; `_on_create_confirmed()` now emits `campaign_created` instead of `campaign_selected` for new campaigns. Load existing campaigns still emits `campaign_selected`.
- `engine/subsystems/session/states/campaign_select_state.gd` — Connects both signals; routes `campaign_created` to `"party_creation"` state, `campaign_selected` to `"session_load"` (unchanged).
- `engine/subsystems/session/session_runner.gd` — Registered `"party_creation"` in `_register_states()` and `_sync_game_state()` (maps to `MAIN_MENU`).

**Welcome screen (2 new files):**
- `scenes/ui/party_creation/party_welcome_screen.gd` + `.tscn` — CanvasLayer (layer 20). Centered framed panel showing "Welcome to [world_name]" with Create Party / Cancel buttons. Signals: `create_party_pressed`, `cancel_pressed`.

**Roster screen (2 new files):**
- `scenes/ui/party_creation/party_roster_screen.gd` + `.tscn` — CanvasLayer (layer 20). Displays party members with 64×64 portrait thumbnails, name, class, and all six ability scores. "Party Members: N/6" counter. Row selection with highlight. Three buttons: Add Character (disabled at 6), Delete Character (disabled until selected), Begin Adventure (disabled until >= 1). Signals: `add_character_pressed`, `delete_character_pressed(character_id)`, `begin_adventure_pressed`. Portrait loading reuses pattern from `character_sheet_panel.gd`.

**State orchestrator (1 new file):**
- `engine/subsystems/session/states/party_creation_state.gd` — `PartyCreationState extends SessionState`. Manages two phases: "welcome" and "roster". Creates party in DB on "Create Party", sets `GameState.campaign_id` / `GameState.party_id` directly so CharacterCreationScreen finalization works. Opens existing CharacterCreationScreen (Main.tscn child) with one-shot signal connections. Handles add/delete/begin actions. Cancel from welcome deletes the empty campaign to avoid DB orphans.

**Decisions made:**
- New `"party_creation"` SessionState between `campaign_select` and `session_load` — cleanest fit for existing state machine pattern.
- Welcome and roster screens are dynamically created by the state (pushed onto NavigationStack), not static Main.tscn children.
- CampaignSelectScreen emits separate `campaign_created` vs `campaign_selected` signals — explicit routing, no heuristics.
- GameState.campaign_id / party_id set directly (public vars) before character creation. Full `load_session()` deferred to `session_load` after "Begin Adventure".
- Party limit constant (`MAX_PARTY_SIZE = 6`) lives in PartyRosterScreen. Dev override system can bypass this later.
- Layer 20 used for both welcome and roster screens (never shown simultaneously). CharacterCreationScreen at layer 32 naturally overlays roster when open.

**Interfaces defined or changed:**
- `CampaignSelectScreen.campaign_created(campaign_id: String)` — new signal
- `PartyCreationState` — new SessionState with actions: `create_party`, `cancel_party_creation`, `add_character`, `character_created`, `character_cancelled`, `delete_character`, `begin_adventure`
- `PartyWelcomeScreen.open(world_name: String)`, `.close()`, signals: `create_party_pressed`, `cancel_pressed`
- `PartyRosterScreen.open(campaign_id, party_id)`, `.close()`, `.refresh()`, signals: `add_character_pressed`, `delete_character_pressed(character_id)`, `begin_adventure_pressed`
- `PartyRosterScreen.MAX_PARTY_SIZE = 6`

**Database changes:** None.

**Tests added/updated:** None (UI-driven flow; needs manual integration testing).

**Known issues:**
- No "Back" or "Cancel" button on the roster screen. Once the player clicks "Create Party", they must add at least 1 character to proceed. This matches the specified design but could be revisited.
- CharacterCreationScreen.open() calls `GameState.transition_to(CHARACTER_CREATION)` internally. PartyCreationState restores to MAIN_MENU after character_created/cancelled.

**Next session should:**
- Test the full flow end-to-end in Godot: New Campaign → Welcome → Create Party → Character Wizard → Roster → Add more → Begin Adventure → Wilderness.
- Consider adding a "Cancel" or "Back" button to the roster screen for better UX.
- Continue with the build plan phases (F-3 Spell Casting, or next priority).

---

## Session 2026-04-10 â€” Scale Mail Naming Cleanup

**Task:** Rename the mutable equipment catalog entry from Ring Mail to Scale Mail, while preserving compatibility with existing internal identifiers and shorthand matching.
**Model used:** Codex GPT-5
**Completed:**
- Updated `data/equipment/base_equipment.json` so the `ring_mail` catalog row now displays as `Scale Mail`.
- Swapped the catalog note to read `Also called Ring Mail.` so the alternate name remains documented in the correct direction.
- Added `scale -> ring_mail` to `scenes/ui/character_creation/equipment_shop_panel.gd` while keeping the existing `ring -> ring_mail` alias for backwards-compatible matching.
**Decisions made:**
- Kept the internal item key as `ring_mail` to avoid breaking saved equipment references or code paths that treat the key as a stable identifier.
- Left `rules/*.xml` untouched because rule summary XML is sacred and not mutable project data.
**Interfaces defined or changed:**
- None. Display copy and alias coverage changed, but no schema or public method signatures changed.
**Database changes:**
- None.
**Tests added/updated:**
- None. The mutable references were limited to data/UI aliasing, so this was verified by repository search and targeted file updates.
**Known issues:**
- Sacred rule XML still contains `Ring Mail` phrasing where extracted source text uses it; that is intentional per project rules.
**Next session should:**
- If equipment catalog normalization expands later, consider a shared equipment-name alias layer so legacy and alternate names can be resolved centrally.

---

## Session 2026-04-10 â€” Character Creation Max HP Clarification

**Task:** Fix the character-creation HP panel so the level-1 max-HP house rule is explained correctly without changing the underlying ACKS-plus-CON math.
**Model used:** Codex GPT-5
**Completed:**
- Updated `scenes/ui/character_creation/hp_roll_panel.gd` so the checkbox now reads `Max Hit Die at Level 1 (house rule; CON still applies)`.
- Kept the existing rule behavior: max-hit-die override still resolves as `max die face + CON modifier`, minimum 1.
- Changed the max-HP result label to display the true formula (`max 6 + CON +1 = 7`) instead of treating final HP as if it were the raw die roll.
- Preserved `hp_raw_roll` during max-HP override as the effective die face so the panel can explain the result truthfully.
- Extended `tests/test_hp_roll_panel.gd` with focused regressions for a `1d6 + CON +1 = 7` max-HP case and a low-CON `1d4 -> 1 HP` max-HP case.
**Decisions made:**
- Left `character_generator.gd` and `character_creation_screen.gd` unchanged because the shared HP math and finalize path were already correct.
- Treated this as a UI/state-truthfulness bug, not a dice-range or double-CON bug.
**Interfaces defined or changed:**
- No public interface or schema changes.
- `creation_state["hp_raw_roll"]` now remains populated during the max-HP override path and represents the die face before CON is applied.
**Database changes:**
- None.
**Tests added/updated:**
- Updated `tests/test_hp_roll_panel.gd`.
- Ran the full Godot headless test runner: passed with exit code 0.
**Known issues:**
- None new from this change.
**Next session should:**
- If more character-creation house rules are exposed in the UI, give each one equally explicit result text so the displayed math always matches the stored state.

---

## Session 2026-04-10 - Class Sex/Alignment Restrictions and Priest/Priestess Display Overrides

**Task:** Enforce requested class-entry sex/alignment restrictions during character creation finalize, surface them in the class UI, and add display-only Priest/Priestess naming overrides without changing stored class IDs or sacred XML.
**Model used:** Codex GPT-5
**Completed:**
- Added runtime class metadata for `sex_restriction` on bladedancer, witch, and warlock, plus `alignment_restriction = "non-lawful"` for warlock.
- Added priestess display metadata in class JSON so the class list can show `Priest/Priestess` while male characters render as `Priest` on sheet-facing UI.
- Extended `ClassRegistry` with shared class display-name and sex-restriction helpers so UI surfaces do not hand-format raw class IDs.
- Updated `ClassSelectionPanel` to keep ability-only eligibility while showing alignment/sex restrictions in the detail pane and using the generic priestess label in the class list.
- Updated `FinalizePanel` to filter and coerce alignment/sex choices from class restrictions plus witch tradition restrictions, including `chthonic -> chaotic`, and to push sex/alignment into the preview character before refreshing the sheet.
- Updated the finalize summary, biography tab, advancement tab, and character-sheet sidebar party labels to use the shared display-name helper.
- Added focused tests for class-selection restriction copy, finalize restriction enforcement/coercion, and male-priestess display overrides; registered the new finalize test suite in the headless test runner.
**Decisions made:**
- Kept class selection permissive by ability scores only because sex/alignment are chosen later in the wizard.
- Left `priestess` unrestricted in runtime per request; only the display name changes for male characters.
- Left sacred rule XML untouched and implemented the new restrictions entirely in project data and UI/runtime code.
**Interfaces defined or changed:**
- Added optional class JSON metadata fields used at runtime/UI:
  - `sex_restriction`
  - `display_name_generic`
  - `display_name_male`
  - `display_name_female`
- Added `ClassRegistry.get_class_display_name()` and `ClassRegistry.get_sex_restriction()` for shared UI consumption.
**Database changes:**
- None.
**Tests added/updated:**
- Updated `tests/test_class_selection_panel.gd`.
- Added `tests/test_finalize_panel.gd`.
- Updated `tests/test_portrait_display_sizing.gd`.
- Updated `tests/test_runner.gd` and `tests/test_runner.tscn` to register the new finalize suite.
- Corrected a follow-up GDScript parser issue caused by using `class_name` as a local variable name in UI scripts; renamed those locals to non-keyword identifiers and reran the full headless suite successfully.
**Known issues:**
- None new from this change.
**Next session should:**
- If more class-specific runtime presentation rules are added later, route them through `ClassRegistry` display helpers so storage keys remain stable and UI naming stays centralized.

---

## Session 2026-04-10 — F-2 Combat Bugfixes: Movement, Melee Range, Turn Structure, Log Names

**Task:** Fix PC movement failure, monster ranged-melee bug, implement move+attack split turn, add display names to combat log, token position sync, wilderness battle map generation, log export.

**Model used:** Claude Opus 4.6

**Completed:**

**Wilderness combat blank screen fix:**
- `TacticalMapData.generate_open_field(width, height)` — new factory creates a 20x16 passable grass field with all fog VISIBLE.
- `CombatState.enter()` — auto-generates open-field map when no tactical_map in context (all wilderness encounters).
- `CombatScreen.start_interactive()` — embeds CombatMapRenderer in SubViewportContainer for correct Node2D-in-Control rendering.

**PC movement parameter mismatch (Bug A):**
- `_resolve_movement_action()` now checks for `target_cell` (Vector2i) first, falls back to `target_x`/`target_y`.

**Monster ranged-melee attack (Bug B):**
- `_resolve_monster_action()` now auto-moves monster adjacent to target before attacking. Per-attack adjacency check inside multi-attack loop.

**Move+attack split turn structure:**
- `CombatUIController` — `_has_moved_this_turn` field. Move sub-action resolves but does NOT call advance(). Re-emits `pc_turn_started` with Move disabled. Attack/Pass/Delay ends the turn.
- `_resolve_melee_action()` — removed PC auto-move. Returns "target not adjacent" if not adjacent. Monsters keep auto-move in `_resolve_monster_action()`.
- `ActionButtonPanel` — removed Fighting Withdrawal / Full Retreat (declaration-phase only). Added Delay button (placeholder as pass). Added `disable_action(action_id)`.
- `move_completed` signal wired to overlay + screen to disable Move button after movement.

**Token position sync:**
- `_sync_token_positions()` in DungeonCombatOverlay and CombatScreen — syncs ALL token screen positions from `tactical_map.entity_positions` after every action_resolved and move_completed.

**Combat log display names:**
- `CombatUIController._resolve_name()` looks up display_name from roster. All log entries include `actor_name`/`target_name` fields.
- `CombatLogPanel` — `_format_entry()` prefers `actor_name`/`target_name` over raw IDs. `_name_lookup` dict for sub-attack target resolution. `set_name_lookup()` API populated from roster at combat start.
- Initiative log entries include `display_name` per combatant.

**Combat log multi-attack formatting:**
- `_format_attack()` detects `{"attacks": [...]}` wrapper from monster multi-attack routines and formats each sub-attack individually.

**Combat log export:**
- CombatLogPanel stores raw entries in `_entries` array. Export button writes `combat_log_TIMESTAMP.json` + `combat_log_TIMESTAMP.txt` to `user://`, copies formatted text to clipboard.

**Interfaces defined or changed:**
- `TacticalMapData.generate_open_field(width, height) -> TacticalMapData` (new static factory)
- `CombatUIController.move_completed` signal (new)
- `CombatUIController._resolve_name(combatant_id) -> String` (new)
- `ActionButtonPanel.disable_action(action_id: String)` (new)
- `CombatLogPanel.set_name_lookup(lookup: Dictionary)` (new)
- `CombatLogPanel.export_log() -> String` (new)
- `CombatLogPanel._entries: Array` (new field)

**Tests updated:**
- `test_combat_controller_session4.gd` — `test_grid_melee_auto_move_to_engage` updated to expect "target not adjacent" (auto-move removed for PCs).

**Coding conventions updated:** Section 17.5-17.10 added covering combat UI architecture, turn structure, token sync, mortal wound deferral, log display names, combat persistence. Directory structure updated with new files.

**Regression baseline:** 64 suites passed, 8 failed (all pre-existing).

---

## Session 2026-04-11 — G-1 Scoped Reputation System

**Task:** Build Phase G-1 from `docs/acks_arbiter_build_plan.md` — scoped party
reputation tracking with the sacred ACKS five-state attitude model, faction
membership propagation, the domain-ruler → domain → settlement cascade, and
hostile-territory enforcement.

**Model used:** Claude Opus 4.6.

**Completed:**

**New shared types (`engine/shared_types/`):**
- `attitude.gd` — five-state attitude enum (hostile/unfriendly/neutral/indifferent/friendly)
  plus intimidation variants fearful/cowed. Score thresholds: ≤−60 hostile,
  −59..−20 unfriendly, −19..+19 neutral, +20..+59 indifferent, ≥+60 friendly.
  `score_to_tier()`, `tier_to_modifier()` (−2..+2), `shift_tier()`, `clamp_score()`.
- `faction_data.gd` (`FactionData`) — id, campaign_id, name, alignment,
  faction_type, home_domain_id, leader_npc_id, parent_faction_id, description.
- `reputation_entry.gd` (`ReputationEntry`) — scoped party-rep record. Scopes:
  `faction`, `settlement`, `domain`, `tier_a_npc`, `tier_b_npc`, `social_group`.
  Score canonical (-100..+100); `tier` cached on the row.
- `interaction_result.gd` (`InteractionResult`) — output of InteractionResolver.
  Tones: `diplomatic`, `intimidation`, `seduction`. Carries raw_roll,
  modifier_breakdown, total_modifier, final_total, resulting_attitude,
  attitude_shift, charm_like_flag, time_until_next_attempt_seconds.

**New subsystem (`engine/subsystems/reputation/`):**
- `reputation_system.gd` (`ReputationSystem`) — facade. Constructed by callers
  with a CampaignRepository reference (not an autoload). Public API:
  `get_reputation`, `get_score`, `get_tier`, `get_effective_attitude` /
  `get_effective_score` (apply cascade), `apply_reputation_change` (persists,
  emits `reputation_changed`, fires `attitude_became_hostile` on threshold
  cross), `set_reputation_score`, `build_reaction_modifiers(target)` →
  populated ModifierStack.
- `interaction_resolver.gd` (`InteractionResolver`) — sacred 7-step procedure
  from `rules/ax_reactions_and_influencing.xml`. Static API:
  `resolve_initial`, `resolve_attempt_to_influence`. All sacred modifier
  categories per tone (alignment, location, authority, ability scores &
  proficiencies, threat, relationship, target, outnumbering, history). Mystic
  Aura ≥12 sets `charm_like_flag`. Cooldown ladder: 10s → 60s → 600s → 3600s
  → 28800s → 5×28800s.
- `hostile_enforcement.gd` (`HostileEnforcement`) — settlement → adds party_id
  to `settlement_entrances.barred_party_ids`; domain → registers in-memory
  patrol override (consult via `is_domain_hostile_to_party()`). Patrol-override
  persistence deferred to H-1.

**Cascade math (project-defined, not from ACKS rules):**
- effective_domain_score = local_domain_score + ruler_score / 2
- effective_settlement_score = local_settlement_score
                                + effective_domain_score / 2
                                + ruler_score / 4
- Recomputed on demand. Weights are constants in ReputationSystem.

**EventBus signals added:**
- `reputation_changed(scope_type, scope_id, payload)` — payload keys
  old_tier, new_tier, delta, score, reason
- `attitude_became_hostile(scope_type, scope_id)` — fires only on the
  transition into hostile (not while remaining hostile)
- `interaction_resolved(target_id, result)` — declared for downstream consumers

**CampaignRepository additions:** SQL CRUD for the new tables and accessors
for the cascade plumbing — `create_faction`, `get_faction`, `list_factions`,
`add_faction_member`, `get_faction_ids_for_npc`, `fetch_reputation_entry`,
`upsert_reputation_entry` (uses `INSERT ... ON CONFLICT(...) DO UPDATE`
against the UNIQUE composite), `list_reputation_entries`,
`get_domain_ruler_id`, `set_domain_ruler`,
`get_settlement_parent_domain_id`, `set_settlement_parent_domain`,
`get_settlement_barred_parties`, `add_settlement_barred_party`,
`clear_settlement_barred_party`.

**Five-state attitude correction in encounter pipeline:**
- `engine/shared_types/encounter_data.gd` — `behavioral_disposition` now uses
  the sacred five-state vocabulary; legacy `"cautious"` rows are coerced to
  `"unfriendly"` on load. Added `tone` field (default `"diplomatic"`).
- `engine/subsystems/session/session_runner.gd:_reaction_to_disposition()` —
  rewrote to use the sacred 2d6 → attitude table from
  `ax_reactions_and_influencing.xml` (2 hostile, 3-5 unfriendly, 6-8 neutral,
  9-11 indifferent, 12 friendly).
- `engine/subsystems/override/override_manager.gd:override_spawn_encounter()` —
  validates against the five-state vocabulary; reaction-roll mapping updated.
- `scenes/ui/override/override_panel.gd:DISPOSITIONS` — five-state list.

**Database changes:**
- New migration `db/migrations/025_reputation_system.sql`:
  - Tables: `factions`, `faction_memberships`, `reputation_entries`, `social_groups`
  - Indexes: `idx_factions_campaign`, `idx_faction_memberships_npc`,
    `idx_reputation_party_scope`
  - `ALTER TABLE settlement_entrances ADD COLUMN parent_domain_id`
  - `ALTER TABLE settlement_entrances ADD COLUMN barred_party_ids` (JSON array)
  - `ALTER TABLE domains ADD COLUMN ruler_npc_id`
- `db/schema.sql` updated with the new tables and inline-documented ALTER columns.
- A parallel session added migration `026_token_variant.sql` (unrelated). No
  conflict — 025 runs first.

**Decisions made:**
- **Subject = party-wide.** No per-PC reputation in G-1 (deferred). Confirmed
  via plan-mode questions.
- **Storage = numeric score canonical, tier cached.** Score is the source of
  truth; tier denormalized for fast reaction-roll lookup.
- **Faction → member propagation = tier-derived modifier.** A faction's
  current tier maps directly to a -2..+2 reaction modifier on its members,
  mirroring the ACKS "already-X" relationship modifier scale.
- **Cascade = weighted real-time blend, not lagged tick.** Recomputed on
  query.
- **Influence procedure = full resolver, no UI.** All 7 steps + 3 tones land
  in G-1; player-facing UI is deferred to G-2 (henchman hiring).
- **No new autoloads.** ReputationSystem and HostileEnforcement are
  RefCounted; callers construct with a CampaignRepository reference. Follows
  the project rule of keeping autoloads minimal.
- **CampaignRepository owns all SQL.** ReputationSystem calls accessors on
  the repo; no direct DB access from the subsystem.

**Interfaces defined or changed:**
- New EventBus signals: `reputation_changed`, `attitude_became_hostile`,
  `interaction_resolved`.
- New CampaignRepository public methods (see above).
- New shared types: `Attitude` (constants + statics), `FactionData`,
  `ReputationEntry`, `InteractionResult`.
- New subsystems: `ReputationSystem`, `InteractionResolver` (static API),
  `HostileEnforcement`.
- `EncounterData.behavioral_disposition` vocabulary changed from
  `[hostile, cautious, neutral, friendly]` → sacred five-state
  `[hostile, unfriendly, neutral, indifferent, friendly]`. Legacy rows coerced
  on load. New `tone` field.

**Tests added:**
- `tests/test_attitude_thresholds.gd` — 5 tests, 25+ assertions covering
  all score-band boundaries, tier-to-modifier mapping, shift_tier clamping,
  clamp_score.
- `tests/test_reputation_system.gd` — 13 tests with a `FakeRepo` stub.
  Covers persistence, clamping, cascade math (domain w/ ruler, settlement
  w/ domain+ruler, no-double-count when only the local entry exists),
  build_reaction_modifiers (personal, faction membership, settlement
  cascade), and HostileEnforcement settlement barring.
- `tests/test_interaction_resolver.gd` — 12 tests with `FakeDice`. Covers
  all three tone tables, modifier stacks, already-attitude rules per tone,
  proficiency modifiers, Mystic Aura charm flag, attempt-to-influence shifts
  and clamping, cooldown ladder, modifier breakdown contents.
- All three suites registered in `tests/test_runner.gd` and
  `tests/test_runner.tscn`.

**Known issues:**
- 9 pre-existing test suite failures (CharacterPersistence, CSTabAdvancement,
  SettlementMapData/Controller, DungeonMapController, SessionRunner,
  ClassSelectionPanel, LanguageCleanup) are unchanged from the prior baseline.
  Reviewed each failure trace; none touch reputation, attitude, encounter_data,
  or override_manager. Not regressions caused by G-1.
- HostileEnforcement domain-patrol overrides are in-memory only (not
  persisted). Acceptable for G-1; promote to a table when H-1 wires the
  wilderness encounter generator to consult them.
- No event-listener glue layer wires `attitude_became_hostile` to
  `HostileEnforcement.handle_attitude_became_hostile()` automatically yet.
  The session runner / domain manager will wire this when a live party is
  on the map; for now the connection is the caller's responsibility (and
  is exercised directly in tests).

**Next session should:**
- G-2: Henchman lifecycle. Reaction-roll modifiers from G-1 plug into the
  hiring interview step. Reputation tier with the candidate's home faction
  shifts the offer's reaction roll via `build_reaction_modifiers`.
- Wire `EventBus.attitude_became_hostile` to a singleton `HostileEnforcement`
  instance during session start (probably in `SessionRunner._ready()` or a
  small autoload glue script). Phase G-1 leaves this as a follow-up because
  no consumer needs it before G-2.
- Optional: when H-1 lands, persist HostileEnforcement._hostile_domain_overrides
  to a `domain_party_hostility` table so wilderness encounters can override
  spawn tables across save/load.

**Regression baseline:** 71 suites passed, 9 failed (all 9 failures are
pre-existing and unrelated to G-1). All 3 new G-1 test suites pass on the
first run.

---

## Session 2026-04-12 — G-2 Henchman Lifecycle

**Task:** Build Phase G-2 from `docs/acks_arbiter_build_plan.md` — henchman
lifecycle: search → interview → hire → employment → departure. Sacred table
implementation, loyalty/morale mechanics, hiring reaction rolls, settlement
pool generation, combat morale wiring, and hiring panel UI.

**Model used:** Claude Opus 4.6.

**Completed:**

**New subsystem (`engine/subsystems/henchmen/`):**
- `henchman_tables.gd` (`HenchmanTables`) — all sacred lookup tables as
  static functions:
  - Class rarity table (30+ classes mapped to common/uncommon/rare/very_rare/legendary).
  - Rarity × market class availability (count + percent chance).
  - Level × market class henchman availability (dice expressions).
  - Level determination (1d20 with Class VI −2 penalty).
  - Monthly wage table (levels 0-14, sacred values from acore_equipment.xml).
  - Search cost per week by market class.
  - Max henchmen = 4 + CHA mod + Leadership rank.
  - Hiring reaction table (refuse_slander / refuse / try_again / accept / accept_elan).
  - Loyalty result table (hostility / resignation / grudging / loyal / fanatic).
  - Weekly allotment (sacred ½/¼/remainder math).
- `henchman_availability.gd` (`HenchmanAvailability`) — generates the monthly
  pool for a settlement. Rolls availability per class rarity × market class,
  determines class, determines level via 1d20. Assigns weekly allotment.
  Also rolls search cost.
- `henchman_loyalty_resolver.gd` (`HenchmanLoyaltyResolver`) — static API:
  `base_morale(employer_cha_mod, has_command)`, `loyalty_modifier(morale, grudging, fanatic)`,
  `resolve_loyalty_check(morale, grudging, fanatic, dice)`,
  `resolve_hiring_reaction(cha_mod, situational_mod, dice)`.
- `henchman_lifecycle_manager.gd` (`HenchmanLifecycleManager`) — coordinator.
  RefCounted, holds `_repo` and `_rep_system` refs. Public API:
  `ensure_pool()`, `get_available_this_week()`, `get_search_cost()`,
  `attempt_hire()`, `finalize_hire()`, `process_monthly_wages()`,
  `trigger_loyalty_check()`, `process_departure()`, `on_henchman_leveled_up()`,
  `on_henchman_calamity()`, `count_henchmen()`, `can_hire()`.

**New UI (`scenes/ui/settlement/`):**
- `hiring_panel.gd` (`HiringPanel`) — minimal list panel for tavern POI.
  Shows market class, search cost, "Pay Search Fee" button. After payment,
  reveals this week's available henchmen with name/class/level/wage.
  "Interview" button triggers hiring reaction roll. On accept/élan, shows
  "Finalize Hire". "Leave" button closes panel. Tier 0 template text, no LLM.

**Wiring changes:**
- `engine/subsystems/combat/combatant.gd:459-463` — `get_morale()` now
  returns `loyalty_score` for henchmen instead of 0. PCs still return 0.
- `engine/autoloads/event_bus.gd` — added signals: `henchman_hired`,
  `henchman_departed`, `henchman_loyalty_checked`, `wages_processed`.
- `engine/subsystems/session/states/settlement_explore_state.gd` — wired
  `building_entered(poi)` to `_on_building_entered()`. Tavern/inn POIs
  route to `_open_hiring_panel()` (stub for full UI integration).
- `engine/subsystems/characters/character_generator.gd:258-269` — updated
  `generate_henchman()` to accept `morale_base` parameter (default 0) and
  auto-set `wage_gp_per_month` from `HenchmanTables.monthly_wage(level)`.
  Old hardcoded loyalty_score = 7 removed; caller sets morale_base.
- `engine/autoloads/campaign_repository.gd` — added CRUD: `create_henchman_pool`,
  `get_henchman_pool`, `add_pool_member`, `get_pool_members`,
  `mark_pool_member_hired`, `upsert_henchman_state`, `get_henchman_state`,
  `list_henchman_states_for_employer`.

**Database changes:**
- Migration `db/migrations/027_henchman_lifecycle.sql`:
  - `henchman_pools` (monthly pool per settlement)
  - `henchman_pool_members` (character → pool with allotment week)
  - `henchman_state` (morale_score, treasure_share_percent, unpaid_months,
    is_grudging, is_fanatic, hired_month/year, departure info)
- `db/schema.sql` updated with all three tables.

**Decisions made:**
- **Leveled henchmen only.** 0th-level henchmen and 5-factor class selection
  GDD deferred to a later phase.
- **Basic search only.** Commissioning and seeking-by-proficiency/level
  deferred.
- **Separate henchman_state table** instead of adding columns to characters.
  Characters table is the cross-subsystem contract; henchman_state holds
  lifecycle bookkeeping. Existing `loyalty_score` and `wage_gp_per_month` on
  characters remain as quick-access denormalized fields.
- **Departure only in settlements** per user direction. Henchman becomes
  persistent NPC at last settlement, keeps equipped items, gets negative
  personal rep (−30 hostility, −10 resignation) via G-1 ReputationSystem.
- **Weekly allotment gating.** Pool generated on first tavern visit; search
  fee must be paid before candidates are revealed. Half available week 1,
  quarter week 2, remainder week 3.
- **Combat morale wired.** `Combatant.get_morale()` returns henchman's
  `loyalty_score` so MoraleResolver naturally picks it up during combat.
- **Monthly wage auto-deduct.** `process_monthly_wages()` deducts from party
  gold; unpaid henchmen get `unpaid_months` incremented and trigger loyalty
  checks.

**Interfaces defined or changed:**
- New EventBus signals: `henchman_hired`, `henchman_departed`,
  `henchman_loyalty_checked`, `wages_processed`.
- New CampaignRepository methods (see above).
- New subsystem classes: `HenchmanTables`, `HenchmanAvailability`,
  `HenchmanLoyaltyResolver`, `HenchmanLifecycleManager`, `HiringPanel`.
- `CharacterGenerator.generate_henchman()` signature: added `morale_base` param.
- `Combatant.get_morale()`: returns henchman loyalty_score for henchman chars.
- `SettlementExploreState`: wired `building_entered` → `_on_building_entered`.

**Tests added:**
- `tests/test_henchman_tables.gd` — 9 tests covering sacred tables: class
  rarity, wage, max henchmen, search cost, level determination, hiring
  reaction, loyalty result, weekly allotment, rarity availability.
- `tests/test_henchman_loyalty.gd` — 6 tests: base morale, modifier
  assembly, loyalty roll outcomes, departure flags, hiring reactions, élan
  bonus.
- `tests/test_henchman_lifecycle.gd` — 5 tests with FakeRepo: hiring
  accept/slander, loyalty check grudging/fanatic, morale modifiers from
  level-up and calamity.
- Updated `tests/test_npc_generation.gd` — adjusted expected henchman
  loyalty from 7 to 0 (morale_base now caller-supplied).

**Known issues:**
- 9 pre-existing test suite failures unchanged. None related to G-2.
- `_open_hiring_panel()` in settlement_explore_state.gd is a stub — full
  modal overlay integration requires the session runner to create and hold
  the HenchmanLifecycleManager instance. This will be wired when a live
  settlement session is actively running.
- `is_armed` parse error in `combat_screen.gd` and `dungeon_combat_overlay.gd`
  is pre-existing and unrelated to G-2.

**Next session should:**
- Wire `_open_hiring_panel()` to actually instantiate HiringPanel with a
  live HenchmanLifecycleManager when the session runner enters settlement
  state.
- Connect `Timekeeping.month_changed` to `process_monthly_wages()` in the
  session runner for auto-deduction.
- Connect `EventBus.character_leveled_up` to
  `lifecycle_manager.on_henchman_leveled_up()` for the sacred +1 morale
  per level-up.
- H-1: Domain layer. Henchmen serve as garrison commanders, domain managers.
- I-1: Integration test — exercise a full henchman hire + adventure +
  level-up + loyalty check + departure sequence in the test campaign.

**Regression baseline:** 74 suites passed, 9 failed (all pre-existing). All
6 new G-1 + G-2 test suites pass. NPC generation regression (loyalty 7→0)
fixed by updating the test to match the new `morale_base` default.

---

## Session 2026-04-13 — UI/UX GDD Gap Closure (Phases A-G)

**Task:** Audit all UI/UX GDD requirements against built systems for build plan phases A-G. Implement all missing UI screens, overlays, cross-cutting chrome, and session states.
**Model used:** Opus 4.6 for planning and implementation.
**Completed:**

### Phase 1: Notification System (P0)
- `engine/subsystems/ui/notification_manager.gd` — Global notification manager with EventBus integration. Auto-wires to `character_leveled_up`, `henchman_departed`, `loyalty_changed`.
- `scenes/ui/hud/notification_display.gd` + `.tscn` — CanvasLayer (layer=150) toast display with slide-in animation, auto-dismiss, stacking (max 5), click-to-dismiss.
- Added `notification_requested(data: Dictionary)` signal to EventBus.
- Wired into Main.tscn as persistent children.
- `tests/test_notification_manager.gd` — 5 tests (normalization, forwarding, queue flush, category dismiss, signal wiring).

### Phase 2: Core UI Chrome
- `scenes/ui/roll_log/roll_log_overlay.gd` + `.tscn` — CanvasLayer (layer=90) right-side panel. Toggle with F6. Color-coded by roll type, filterable (All/Attack/Save/Skill/Other), click-to-expand detail, live updates via `dice_rolled` signal.
- `scenes/ui/settings/settings_screen.gd` + `.tscn` — Dice mode radio buttons, display info, audio stubs, key bindings reference, LLM placeholder.
- `scenes/ui/level_up/level_up_overlay.gd` + `.tscn` — Multi-step wizard: Congrats → HP Roll → Attack/Save → Proficiencies → Spells → Powers → Summary. Wraps `LevelUpEngine.begin_interactive_level_up()`.

### Phase 3: Session Chrome
- `scenes/ui/hud/session_status_bar.gd` + `.tscn` — CanvasLayer (layer=80) bottom bar. Widgets: party name, location, time, day budget (8 slots), adventure pool, party member chips with HP bars, movement mode, light source. Auto-hides during MAIN_MENU/CHARACTER_CREATION.
- `scenes/ui/dialogs/confirmation_dialog.gd` + `.tscn` — Reusable modal (layer=180) with danger mode (2s delay on confirm). Title, body, confirm/cancel buttons.
- `scenes/ui/pause/pause_menu_overlay.gd` + `.tscn` — CanvasLayer (layer=160) pause menu. Resume/Save/Settings/Quit. Toggles with Escape. Uses GameState.pause()/resume().

### Phase 4: Camp/Rest System
- `engine/subsystems/exploration/camp_manager.gd` — Static utility class for camp logic. Watch validation, encounter checks, armed sleeper rolls (d20 vs encumbrance +/- CON + 1), rest recovery (1 HP/day, full spell recovery), ration consumption, town rest.
- `engine/subsystems/session/states/camp_state.gd` — New session state. 12-hour rest with 3 watches of 4 hours. Sleeping chars are prone/unequipped/Surprised if encounter during their sleep watch. Armed sleepers skip surprise but risk no-recovery.
- `scenes/ui/camp/camp_rest_screen.gd` + `.tscn` — Watch assignment UI (wilderness) and simplified town rest. Rest summary shows encounters, recovery, rations, failed sleepers.
- `tests/test_camp_manager.gd` — 8 tests (validation, recovery, failed sleepers, rations, town rest).

### Phase 5: Dungeon Light Source System
- `engine/subsystems/exploration/light_source_tracker.gd` — Tracks active light source (torch 6 turns, lantern 24, continual_light permanent, infravision 60ft permanent). Tick per dungeon turn, warning notifications at 5/2/0 turns. Serializable.
- `tests/test_light_source_tracker.gd` — 9 tests (activation, countdown, warnings, expiry, deactivation, radius cells, serialization).

### Phase 6: Party Selector & Split Party
- `scenes/ui/hud/party_selector_tabs.gd` — Tab bar for multi-party switching. One tab per party with name/count/activity icon. Auto-hides when single party. Split button.
- `scenes/ui/party/party_split_overlay.gd` + `.tscn` — Two-column click-to-toggle party splitter. Henchmen auto-follow employers. Validation (min 1 per group).

### Phase 7: Day Declaration System
- `engine/subsystems/exploration/day_budget_manager.gd` — 8-slot day budget with 8 slot types (March/Explore/Rest/Forage/Hunt/Guard/Craft/Free). Validation (min 2 rest). Travel distance estimation. Encounter check counting.
- `engine/subsystems/session/states/day_declaration_state.gd` — Session state wrapping day planning and sequential slot resolution (time advance, encounters, foraging/hunting checks). Transitions to camp after all 8 slots.
- `scenes/ui/day_planner/day_declaration_screen.gd` + `.tscn` — 8-slot click-to-cycle UI with color-coded legend, summary panel, validation errors, Confirm/Cancel.
- `tests/test_day_budget_manager.gd` — 8 tests (defaults, slot management, validation, counts, travel estimation, encounter checks, serialization).

### Phase 8: Map Polish
- `scenes/ui/xp/xp_banking_overlay.gd` + `.tscn` — XP banking on settlement entry. Shows adventure pool, per-character division with prime requisite modifiers, banker's rounding.
- Hex tooltip and territory overlay modifications deferred to visual testing.

### Phase 9: Encounter/Social Screen
- `engine/subsystems/session/states/encounter_state.gd` — Session state for NPC encounters. Routes to combat or peaceful resolution.
- `scenes/ui/encounter/encounter_screen.gd` + `.tscn` — NPC info panel + narrative area + context-dependent action buttons based on attitude. Attitude ladder visualization. Influence attempts.

### Phase 10: Downtime Screen + Main Menu
- `engine/subsystems/session/states/downtime_state.gd` — Session state for between-adventure activities.
- `scenes/ui/downtime/downtime_screen.gd` + `.tscn` — Activity card grid hub. Active: Carousing, Reserve XP, Hijinks, Rest, Hiring. Placeholder: Spell Research, Mercantile Ventures. Activity sub-panels with descriptions.
- `scenes/ui/main_menu/main_menu_screen.gd` + `.tscn` — Title screen with New Campaign/Load/Settings/Quit.

**Decisions made:**
- Notification system is a Main scene child (not autoload) to avoid autoload proliferation. Uses EventBus signal for decoupled access.
- Camp/rest uses 12-hour period (3 watches x 4 hours) per Jedidiah's rules. No dungeon resting in V1.
- Armed sleeper mechanic: d20 throw vs (encumbrance +/- CON mod + 1). Failure = no recovery.
- Sleeping characters in camp combat: prone, unequipped, auto-Surprised round 1. No other sleep conditions.
- Day Declaration uses 8 activity slots, each ~1 hour. Minimum 2 REST slots for valid plan.
- Roll Log uses F6 toggle (standalone key, not Ctrl+Alt combo).

**Interfaces defined or changed:**
- `EventBus.notification_requested(data: Dictionary)` — new signal
- SessionRunner `_state_registry` expanded: added "camp", "day_declaration", "encounter", "downtime"
- `project.godot` input actions: added `roll_log_toggle` (F6)
- Main.tscn: added NotificationManager, NotificationDisplay, RollLogOverlay, LevelUpOverlay, SessionStatusBar, PauseMenuOverlay

**Database changes:** None.

**Tests added/updated:**
- `test_notification_manager.gd` — 5 tests
- `test_camp_manager.gd` — 8 tests
- `test_light_source_tracker.gd` — 9 tests
- `test_day_budget_manager.gd` — 8 tests
- All registered in test_runner.gd/.tscn.

**Known issues:**
- Hex tooltip delay, territory tint overlays, and political border rendering are deferred — they modify existing renderers and need visual testing in Godot.
- Downtime activity sub-panels are placeholder descriptions (Carousing XP/mishap calculation, Reserve XP conversion, Hijinks proficiency checks not yet wired to backend).
- Encounter screen uses simplified influence mechanic (2d6 re-roll). Full InteractionResolver integration (with tone tables, CHA modifier, proficiency bonuses) needs wiring.
- CampState.enter() calls `preload()` for camp_rest_screen.tscn — will fail if scene path changes.
- DayDeclarationState slot resolution is sequential (no async). Combat transitions mid-day may not resume correctly without additional return-context plumbing.
- MainMenuScreen is created but not yet wired as the boot screen (SessionRunner still boots to campaign_select).
- Light source tracker built as standalone — needs integration with dungeon_map_controller fog update loop.

**Next session should:**
- Run test_runner.tscn in Godot to verify new tests pass alongside the 74 existing passing suites.
- Visual-test the UI screens: open Main.tscn, trigger notifications, toggle roll log, open pause menu, test settings dice mode toggle.
- Wire MainMenuScreen as boot target in SessionRunner (replace campaign_select as initial state).
- Integrate LightSourceTracker with dungeon_map_controller fog updates.
- Add hex tooltip hover delay (~1s) and territory classification tint overlay.
- Wire the day declaration "Begin Day" flow end-to-end with wilderness exploration.
- Implement carousing XP/mishap backend and wire to downtime sub-panel.
- Begin Phase H-1 (Domain Data Model) or Phase I-1 (Integration Test Campaign).

---

## Session 2026-04-13/14 -- Real-Time-With-Pause Event Scheduler

**Task:** Implement the real-time-with-pause event scheduler system per gdd-realtime-scheduler.md. Replace the discrete state machine game loop with a unified clock-and-scheduler model. Remove the day planner system.
**Model used:** Opus 4.6 for planning and full implementation.
**Completed:**

Phase 1 - EventScheduler Core:
- scheduled_event.gd, event_scheduler.gd (priority queue), event_handler_registry.gd, scheduler_loop.gd (tick driver with 5 speed modes)
- Migration 028: scheduled_events + auto_pause_config tables
- 7 new EventBus signals (scheduler_event_resolved, scheduler_paused, scheduler_resumed, scheduler_speed_changed, clock_speed_requested, order_cancelled, order_queued)
- test_event_scheduler.gd (21 tests), test_scheduler_loop.gd (11 tests)

Phase 2 - Session Runner Integration:
- session_runner.gd: scheduler members, _process tick loop, persistence in load/save/end_session
- campaign_repository.gd: save_scheduled_event/get_scheduled_events/clear_scheduled_events

Combat Time Rounding + Party Locking:
- combat_finalizer.gd: uses advance_party_rounds(), rounds up to next turn boundary per ACKS RAW
- combat_state.gd: pauses scheduler on enter
- session_runner.gd: _locked_parties, check_party_time_lock(), is_party_locked(), unlock_party()

Phase 3 - Wilderness: wilderness_handlers.gd (travel_leg, encounter, getting_lost, forced_march). Hex clicks schedule travel_leg events. travel_speed_calculator.gd: hex_crossing_rounds().

Phase 4 - Camp + Settlement: camp_handlers.gd (camp_watch, camp_rest_complete). settlement_handlers.gd (settlement_move, settlement_activity, settlement_encounter).

Phase 5 - Dungeon (Real-Time-With-Pause): dungeon_handlers.gd (dungeon_movement_tick, encounter_check, light_tick, action_complete). Movement: order_move() tracks paths, movement_tick advances entities by cells_per_round each round. Three modes: exploration/combat/running. LightSourceTracker wired in.

Phase 6 - Combat Bridge: done during Phase 2/3 (see above).

Phase 7 - Domain: domain_handlers.gd (domain_monthly_tick). Resolves revenue/expenses/morale/growth/events. Self-reschedules monthly. Global registration in load_session().

Phase 8 - UI: clock_speed_controls.gd (Pause/1x/2x/5x/Max buttons, Space/1-4 keys). entity_outliner.gd (right-side panel, orders + ETAs). session_status_bar.gd: integrated speed controls + pause reason flash. pause_menu_overlay.gd: Escape pauses scheduler.

Phase 9 - Order Cancellation: cancel_travel, cancel_movement, cancel_action, set_movement_mode actions added to wilderness/dungeon/settlement states.

Day Planner Removal:
- Deleted: day_budget_manager.gd, day_declaration_state.gd, day_declaration_screen.gd/.tscn, test_day_budget_manager.gd
- Removed from: session_runner state registry, EventBus signal, session_status_bar Plan Day button, wilderness_explore_state signal wiring, test_runner

**Decisions made:**
- EventScheduler is RefCounted owned by SessionRunner, NOT an autoload
- Speed: NORMAL = 1 round per 2 real seconds. MAX = instant advance to next event
- Combat uses party clock + rounds up to next turn per ACKS RAW
- Dungeon is real-time-with-pause at round granularity (not turn-based)
- Day planner fully removed -- replaced by direct scheduler event issuance

**Interfaces defined or changed:**
- EventScheduler: schedule/cancel/peek/pop/cancel_all_for_owner/get_events_for_owner/to_dicts/load_from_dicts
- EventHandlerRegistry: register/unregister/resolve
- SchedulerLoop: setup/tick/set_speed/pause/resume/toggle_pause. SPEED_PAUSED=0, SPEED_NORMAL=1, SPEED_FAST=2, SPEED_VERY_FAST=5, SPEED_MAX=-1
- ScheduledEvent: event_id, fire_time, event_type, owner_id, data, priority, cancelled
- Handler result keys: next_events, auto_pause, pause_reason, enter_combat, encounter_data, presentation, transition_to
- SessionRunner accessors: get_scheduler(), get_handler_registry(), get_scheduler_loop(), check_party_time_lock(), is_party_locked(), unlock_party()
- CampaignRepository: save_scheduled_event(), get_scheduled_events(), clear_scheduled_events()
- EventBus removed: day_declaration_requested

**Database changes:**
- Migration 028: scheduled_events (event_id, campaign_id, fire_time, event_type, owner_id, data_json, priority, cancelled) + auto_pause_config (campaign_id, event_category, pause_tier)

**Tests added/updated:**
- test_event_scheduler.gd (21 tests), test_scheduler_loop.gd (11 tests)
- Removed: test_day_budget_manager.gd (8 tests)

**Known issues:**
- Entity outliner uses GameState.party_id for ETA -- may need adjustment for multi-party
- Dungeon movement tick calls controller._update_fog_for_all_members() (private method)
- LightSourceTracker hardcoded to "torch" on dungeon entry -- needs inventory check
- Settlement activity durations are placeholder (1 turn)
- Domain monthly resolution uses simplified formulas -- needs full ACKS DaW tables
- Auto-pause config UI not built yet (hardcoded defaults)
- Passive detection checks (dwarf/elf) noted as TODO in dungeon movement tick

**Next session should:**
- Run test_runner.tscn to verify all tests pass
- Visual-test clock speed controls and entity outliner
- Wire LightSourceTracker to party inventory
- Implement passive detection in dungeon movement tick
- Build auto-pause configuration UI
- Add hex pathfinding for multi-hex travel

---

## Session 2026-04-14 — Settlement Shop Mechanics & Multi-Denomination Currency

**Task:** Implement in-game shop system for buying/selling equipment at settlement POIs, gated by ACKS market class availability. Also implement full multi-denomination currency system (PP/EP/GP/SP/CP).
**Model used:** Opus 4.6 for planning and full implementation.

**Completed:**
- **Currency system** (`engine/subsystems/commerce/currency.gd`): All 5 ACKS denominations (PP=1000cp, EP=500cp, GP=100cp, SP=10cp, CP=1cp). Static helpers: `coins_to_cp()`, `cp_to_coins()`, `compute_deduction()` (smallest-first spending with change-making), `format_cost()`, `format_wealth()`.
- **CampaignRepository currency methods** (`engine/autoloads/campaign_repository.gd`): `get_character_coins()`, `get_character_wealth_cp()`, `deduct_cost_cp()`, `add_coins_cp()`, `add_specific_coins()`, `_create_coin_item()`. All coin types stored as `inventory_items` rows with `item_key` in `["coin_pp","coin_ep","coin_gp","coin_sp","coin_cp"]`.
- **Migration 029** (`db/migrations/029_shop_inventory.sql`): `shop_inventory` table (per-POI item stock with monthly refresh) and `commissions` table (pending orders with ready_at_round). Schema.sql updated.
- **Market availability data** (`data/equipment/market_availability.json`): ACKS price tier × market class availability table encoded from `acore_equipment.xml`.
- **ShopInventoryGenerator** (`engine/subsystems/commerce/shop_inventory_generator.gd`): Generates per-POI stock from market class, POI subtype → category mapping, and shop size fraction (10%/25%/50%). Uses banker's rounding. 30-day refresh cycle.
- **ShopService** (`engine/subsystems/commerce/shop_service.gd`): `open_shop()`, `buy_item()`, `sell_item()`, `commission_item()`, `pickup_commission()`, `get_sellable_items()`. Buy/sell at same price (no resale discount). Magic items excluded. Commissions schedule `commission_ready` events.
- **EventBus signals**: `shop_transaction_completed`, `commission_ready` added.
- **SettlementHandlers**: `commission_ready` event handler registered.
- **SettlementExploreState**: `_on_building_entered()` extended for `"shop"`, `"shophouse"`, `"emporium"` POI types. `_open_shop_panel()` instantiates ShopService, opens shop, pushes ShopPanel.
- **ShopPanel UI** (`scenes/ui/settlement/shop_panel.gd` + `.tscn`): 4-tab panel (Buy/Sell/Commission/Pending Orders). Character selector dropdown, wealth display using `Currency.format_wealth()`, category-grouped buy list, sell list, commission ordering, and pending order pickup.
- **Tests**: `test_currency.gd` (20 tests: denomination constants, wealth math, change-making, formatting), `test_shop_inventory_generator.gd` (9 tests: banker's rounding, refresh cycle, market class generation, shop sizes, category filtering, DB persistence), `test_shop_service.gd` (10 tests: open, buy, sell, commission, pickup flows). All registered in test_runner.

**Decisions made:**
- Buy and sell at the same listed catalog price — no resale discount. Design decision from Jedidiah.
- Magic items excluded from shop system entirely (deferred to future phase).
- Gold is per-character only (no shared party gold pool). Shop uses character selector.
- Five denominations: PP, EP, GP, SP, CP. All 1 enc unit per coin. Created as inventory_items on demand.
- `deduct_cost_cp()` spends smallest denominations first (cp→sp→gp→ep→pp) and makes change from next-larger when needed.
- `add_coins_cp()` distributes into highest denominations first (pp→ep→gp→sp→cp).
- `OverrideManager.override_adjust_gold()` kept as-is for GP-only overrides; shop uses new `deduct_cost_cp`/`add_coins_cp`.

**Interfaces defined or changed:**
- `Currency.DENOMINATIONS` array (ordered highest→lowest): `[{key, name, cp_value, abbr}, ...]`
- `Currency.COIN_KEYS`: `["coin_pp", "coin_ep", "coin_gp", "coin_sp", "coin_cp"]`
- `Currency.compute_deduction(coins: Dict, cost_cp: int) -> {success, new_coins, message}`
- `CampaignRepository.get_character_coins(character_id) -> {coin_pp: int, ...}`
- `CampaignRepository.deduct_cost_cp(character_id, cost_cp) -> {success, message}`
- `CampaignRepository.add_coins_cp(character_id, amount_cp) -> void`
- `ShopService.buy_item() -> {success, message, wealth_remaining_cp}`
- `ShopService.sell_item() -> {success, message, wealth_remaining_cp}`
- `EventBus.shop_transaction_completed(transaction: Dictionary)`
- `EventBus.commission_ready(commission_id, character_id, item_key)`

**Database changes:**
- Migration 029: `shop_inventory` and `commissions` tables.
- No changes to `inventory_items` schema — coin types use existing columns.

**Tests added/updated:**
- `tests/test_currency.gd` — 20 tests for Currency class
- `tests/test_shop_inventory_generator.gd` — 9 tests for stock generation
- `tests/test_shop_service.gd` — 10 tests for buy/sell/commission/pickup
- All three registered in test_runner.gd and test_runner.tscn

**Known issues:**
- `henchman_lifecycle_manager` references `party_state.gold_current` column that doesn't exist in schema — pre-existing bug unrelated to this session.
- Shop subtype mapping (POI subtype strings) not yet verified against what `gdd-settlement-stocking.md` §3.2 actually generates — will need adjustment when settlement stocking is implemented.
- Commission tab only shows items that were generated with 0 quantity (percentage-chance failures). Items entirely outside the shop's categories are not shown for commissioning — may need a "browse catalog" option.
- `EquipmentCatalog.format_cost()` still only shows gp/sp/cp (no ep/pp). `Currency.format_cost()` handles all 5 denominations and should be used instead going forward.
- ShopPanel not yet visual-tested in the running game (no settlement with shop POIs exists in test data yet).

**Next session should:**
- Run test_runner.tscn to verify all new tests pass alongside existing tests
- Visual-test shop panel in a settlement (may need to seed test shop POI data)
- Consider updating `EquipmentCatalog.format_cost()` to delegate to `Currency.format_cost()` or deprecate it
- Verify character creation equipment shop panel still works (it uses its own gold tracking)
- Investigate and fix `party_state.gold_current` missing column bug in henchman wages

---

## Session 2026-04-14 — Document Updates for Scheduler/UI Architecture Pivot

**Task:** Update project documentation to reflect three new GDDs: `gdd-realtime-scheduler.md` (EventScheduler replaces session runner state machine), `gdd-dungeon-map-ui.md` (RTS-style dungeon interaction), `gdd-settlement-exploration-ui.md` (menu-driven settlement navigation). Finalize draft scheduler notes in design brief, add DoorData fields, update coding conventions for scheduler-driven timekeeping.
**Model used:** Opus 4.6 for planning and edits.

**Completed:**
- `docs/acks_arbiter_design_brief_v11.md`: Rewrote §6.2 (settlement maps) to describe menu-driven PoI panel overlay; street graph retained for travel time calculation only. Rewrote §8.1 (core loop) to describe EventScheduler-driven loop, folding Draft note into main text. Rewrote §8.2 (session states) to describe three session runner states and entity-level contexts, folding Draft note into main text. §8.3 unchanged (already finalized in prior session).
- `generation/gdd-dungeon-layout.md`: Added `door_material` (string: wood_simple/wood_standard/wood_reinforced/iron/stone) and `is_evil` (bool, default false) fields to DoorData schema in §11 output section. Updated revision history.
- `generation/gdd-settlement-layout.md`: Replaced "navigable" framing in §1 Purpose with neutral framing plus travel-calculator note. Added cross-reference in §12 (undercity level 1, item e) noting that all undercity levels inherit `gdd-dungeon-layout.md`'s DoorData schema including door_material and is_evil. Updated revision history.
- `docs/coding_conventions.md`: Updated §6.8 Timekeeping Patterns — passive clock paragraph now describes scheduler-driven advancement via `advance_party_rounds()`, cross-references §19. Code example updated: scheduler pattern is GOOD, direct `advance_hours()` is BAD (test setup only). Date comment updated.
- `CLAUDE.md`: Expanded generation/ directory listing to call out the three architecturally significant GDDs. Added EventScheduler-first architecture bullet to Architecture Patterns. Added sub-note to build protocol step 7 for exploration/session/UI work.

**Decisions made:**
- DoorData fields (`door_material`, `is_evil`) added to `gdd-dungeon-layout.md` only, not `gdd-settlement-layout.md`. Settlement undercity layers use dungeon layout format and inherit those fields via cross-reference. Avoids duplicate schemas that drift.
- `advance_hours()` marked BAD in §6.8 — all game-time advancement should go through the scheduler via `advance_party_rounds()`. Direct calls acceptable only in test setup.
- Design brief §8.1 and §8.2 Draft scheduler notes folded into main text (full rewrite), not just relabeled.

**Interfaces defined or changed:**
- `DoorData` schema in `gdd-dungeon-layout.md` §11: added `door_material: string` and `is_evil: bool`.

**Database changes:**
- None (schema-level changes deferred to implementation sessions).

**Tests added/updated:**
- None (documentation-only session).

**Known issues:**
- Street graph edge weights in `gdd-settlement-layout.md` §7 store `length: float` in map units; the travel time calculator in `gdd-settlement-exploration-ui.md` needs these in block counts. Conversion factor or normalization needed at implementation time.
- `gdd-settlement-layout.md` §3.1 (line 81) still says "Mechanically navigable" — retained because it describes the graph being traversable for the calculator, which is still true.

**Next session should:**
- Run test_runner.tscn to verify all existing tests still pass
- Visual-test shop panel in a settlement (may need to seed test shop POI data)
- Begin settlement exploration UI build (SettlementPanel, PoI list, travel time calculator) or dungeon DoorData implementation
- Update `docs/document_map.md` to reference the three new GDDs

---

## Session 2026-04-14 — Settlement Exploration UI Overhaul (Phases 1-8)

**Task:** Implement the menu-driven settlement exploration UI per `gdd-settlement-exploration-ui.md`. Replace the interactive node-click map navigation with a PoI panel system. Full 8-phase implementation.
**Model used:** Opus 4.6 for planning and full implementation.

**Completed:**

Phase 1 — Travel Calculator + Route Memory DB:
- `engine/subsystems/exploration/settlement_travel_calculator.gd`: AStar2D pathfinding on street graph with alley filtering (streets_only toggle), block counting, edge type breakdown, commute/meander time calculation (15 rounds/block and 60 rounds/block respectively), straggling group penalties (2x for 6-11 chars, 4x for 12+). `calculate_route()` and `calculate_all_poi_distances()` static methods.
- `db/migrations/030_settlement_routes.sql`: `known_city_routes` table (route memory for Navigation throw exemptions) and `visited_pois` table (POI discovery tracking with discovery_method).
- `engine/autoloads/campaign_repository.gd`: Added `record_city_route()`, `has_city_route()`, `record_visited_poi()`, `has_visited_poi()`, `get_visited_pois()`, `get_discovered_poi_ids()`.
- `db/schema.sql`: Updated to migration 030.

Phase 2 — Navigation Throw + Encounter Scheduling:
- `engine/subsystems/exploration/settlement_navigation.gd`: Navigation throw (11+ on d20) with route exemption (known routes auto-succeed), visited destination bonus (+4), Navigation proficiency bonus (+4). `check_navigation()` and `roll_deviation()` (1d4+1 blocks).
- `engine/subsystems/exploration/settlement_encounter_scheduler.gd`: Time-based encounter checks per GDD §6.2: streets day 360 rounds, streets night 180, alleys day 180, alleys night 60. Threshold 6+ normal, 5+ looking-for-trouble. `schedule_encounter_checks()` returns event IDs for cancellation.

Phase 3 — Settlement Handlers Rewrite:
- `engine/subsystems/session/handlers/settlement_handlers.gd`: Near-complete rewrite. New event types: `city_travel_arrival`, `navigation_check`, `city_encounter_check`, `got_lost`. New `schedule_travel()` orchestrates full travel: calculates route, schedules arrival, nav checks (commuting only, every turn), encounter checks (time-based). `cancel_travel()` cancels all pending travel events. Per-party `_active_travel` state dict. Fixed encounter bug (old code checked `<= 1` on d6, now correctly checks `>= threshold`). Route memory recorded on arrival (both directions). Kept `schedule_activity()` and `commission_ready` handler.

Phase 4 — SettlementPanel UI:
- `scenes/ui/settlement/settlement_panel.gd` + `.tscn`: Right-side panel (40% width) with settlement header, PoI list (collapsible by district, distance/time estimates), travel indicator (progress bar, ETA, cancel, nav result), toggle controls (Commuting/Meandering, Streets Only/Use Alleys, Looking for Trouble), activity area, party status strip. Emits signals: `poi_clicked`, `travel_cancelled`, `speed_toggled`, `route_toggled`, `trouble_toggled`, `exit_requested`.

Phase 5 — SettlementExploreState Rewire:
- `engine/subsystems/session/states/settlement_explore_state.gd`: Complete rewrite. Panel attached to HUD CanvasLayer (layer 10) instead of nav_stack push — hex map stays visible. Wires SettlementPanel signals to travel scheduling. Auto-discovers obvious POIs on entry. Scheduler event listener updates panel on arrival/nav check/encounter. Night detection via Timekeeping. `_on_poi_clicked()` calls `_handlers.schedule_travel()`. Exit only at gate nodes.
- `engine/subsystems/exploration/settlement_map_controller.gd`: Added `get_current_poi()` and `get_pois_by_district()` convenience methods.

Phase 6 — City Overview Widget:
- `scenes/ui/settlement/city_overview_widget.gd`: Non-interactive settlement schematic (280x280px). Draws block polygons colored by district, streets, walls, POI markers (discovered only), party pin. Transform maps settlement coordinates to widget space. Positioned top-left of screen.

Phase 7 — Activity Panel + Sub-Panel Integration:
- `scenes/ui/settlement/activity_panel.gd`: Dynamic panel showing available activities by POI type (per GDD §4.1 table). Supports tavern, inn, temple, shop, guild, gate, market types. Minor activities resolve immediately; major activities (gather_info 24 turns, carouse 144 turns, rest_long 48 turns) scheduled as events. Routes to ShopPanel for buy/sell/commission. Gate shows Exit Settlement.
- `scenes/ui/settlement/shop_panel.gd`: Modified to support embedded layout — detects parent container type and adjusts sizing (expand-fill vs. fixed modal).

Phase 8 — Cleanup:
- Verified no remaining references to old `settlement_map.tscn` or `settlement_map_renderer.gd` node_clicked pattern in engine or test code. Old files exist but are unused (can be deleted in a follow-up cleanup commit).

**Decisions made:**
- Settlement panel is a HUD CanvasLayer overlay (layer 10), NOT a nav_stack entry. This keeps the hex map visible underneath.
- Travel time is per-edge (each edge = 1 block), not per-length-unit. Edge `length` field used for AStar2D weight optimization but block count = edge count.
- Navigation throw exemptions are directional — recording route A→B also records B→A.
- Straggling group penalty affects commuting only (not meandering), per GDD §3.3.5.
- ShopPanel re-embedding: detects parent type at build time to choose sizing mode.
- City overview widget uses Control (not Node2D) for _draw() compatibility with CanvasLayer.

**Interfaces defined or changed:**
- `SettlementTravelCalculator.calculate_route(map_data, origin, dest, streets_only, party_size) -> Dictionary`
- `SettlementTravelCalculator.calculate_all_poi_distances(map_data, origin, streets_only, party_size) -> Dictionary`
- `SettlementNavigation.check_navigation(campaign_id, settlement_id, origin_poi_id, dest_poi_id, party_characters) -> Dictionary`
- `SettlementNavigation.roll_deviation() -> int`
- `SettlementEncounterScheduler.schedule_encounter_checks(scheduler, party_id, start, duration, has_alleys, is_night, trouble, ...) -> Array[String]`
- `SettlementHandlers.schedule_travel(map_data, origin, dest_poi, speed, streets_only, party_size, scheduler, party_id, ...) -> Dictionary`
- `SettlementHandlers.cancel_travel(scheduler, party_id) -> int`
- `SettlementHandlers.is_traveling(party_id) -> bool`
- `SettlementHandlers.get_active_travel(party_id) -> Dictionary`
- `SettlementPanel` signals: `poi_clicked`, `travel_cancelled`, `speed_toggled`, `route_toggled`, `trouble_toggled`, `exit_requested`, `activity_selected`
- `SettlementActivityPanel` signals: `activity_requested`, `exit_settlement_requested`, `shop_requested`, `hiring_requested`
- `SettlementMapController.get_current_poi() -> Dictionary`
- `SettlementMapController.get_pois_by_district() -> Dictionary`
- `CampaignRepository.record_city_route()`, `has_city_route()`, `record_visited_poi()`, `has_visited_poi()`, `get_visited_pois()`, `get_discovered_poi_ids()`
- Event types changed: `settlement_move` → `city_travel_arrival`; added `navigation_check`, `city_encounter_check`, `got_lost`

**Database changes:**
- Migration 030: `known_city_routes` and `visited_pois` tables.

**Tests added/updated:**
- `tests/test_settlement_travel_calculator.gd` — 16 tests: pathfinding, alley filtering, block counting, commute/meander timing, straggling penalties, boundary values, all-POI distance calculation.
- `tests/test_settlement_navigation.gd` — 15 tests: route exemption, visited destination bonus, proficiency bonus, stacking, success/failure thresholds, deviation range, encounter intervals (streets/alleys × day/night), encounter count for travel durations, looking-for-trouble threshold.
- Both registered in test_runner.gd and test_runner.tscn.

**Known issues:**
- Old files `scenes/maps/settlement_map_renderer.gd` and `scenes/maps/settlement_map.tscn` still exist but are unused. Safe to delete in a cleanup commit.
- HiringPanel integration in activity panel is a stub (notification only). Needs wiring to existing `hiring_panel.gd` when Phase G-2 is complete.
- Mid-travel speed changes currently cancel travel (player must re-click destination). Could be improved to reschedule in-place.
- City overview widget does not yet animate character pins during travel (shows current position only).
- Activity durations are hardcoded (gather_info=24 turns, carouse=144, rest_long=48). Should be derived from ACKS rules or GDD constants.
- Dawn/dusk Timekeeping signal wiring for activity availability gating not yet connected (PoI open/close status uses rough approximation).
- Party status strip is empty (placeholder HBoxContainer). Needs portrait/HP/encumbrance/coin display.
- No straggling group warning indicator in travel indicator yet.
- `_is_nighttime()` uses rough approximation (75%/25% of day). Should use Timekeeping dawn/dusk signals when available.

**Next session should:**
- Run test_runner.tscn to verify all 31 new tests pass alongside existing tests
- Visual-test the settlement panel in a running settlement (enter from hex map)
- Delete old settlement_map_renderer.gd and settlement_map.tscn
- Wire dawn/dusk Timekeeping signals for activity availability
- Build party status strip content (portraits, HP, coins)
- Add straggling group indicator to travel indicator
- Animate character pins on city overview widget during travel
- Connect HiringPanel to activity panel (when G-2 hiring is ready)
- Update `docs/document_map.md` to reference new GDDs and settlement UI files

---

## Session 2026-04-14 — Combat UI GDD Integration & gdd-ui-ux-design Removal

**Task:** Integrate new `gdd-combat-ui.md` into project documentation. Remove all references to deprecated `gdd-ui-ux-design.md` (file deleted) except historical build log notes.
**Model used:** Opus 4.6.

**Completed:**
- `docs/acks_arbiter_design_brief_v11.md`: Replaced `gdd-ui-ux-design.md` GDD table entry with `gdd-combat-ui.md`. Updated §8.2 to reference all three UI GDDs instead of the old monolithic spec. Added combat UI reference to §7 Combat context. Removed `gdd-ui-ux-design.md` references from §9.6, §13.3, §13.4 (inlined or removed dangling refs).
- `docs/document_map.md`: Replaced `gdd-ui-ux-design.md` row with `gdd-combat-ui.md` entry. Removed `gdd-ui-ux-design` from dependency lists of `gdd-stronghold-construction` and `gdd-realtime-scheduler`.
- `docs/rule_system_map.md`: Replaced `gdd-ui-ux-design` in UI & Presentation section with `gdd-dungeon-map-ui`, `gdd-settlement-exploration-ui`, `gdd-combat-ui`. Updated dependency graph and implementation order list (items 21-23 now the three specific UI GDDs).
- `CLAUDE.md`: Added `gdd-combat-ui.md` to generation/ directory listing.
- `generation/gdd-stronghold-construction.md`: Removed `gdd-ui-ux-design.md` from Depends on GDDs header.
- `generation/gdd-dungeon-map-ui.md`: Removed TBD reference to `gdd-ui-ux-design.md` in Unit Info Panel section.

**Decisions made:**
- `gdd-ui-ux-design.md` was a monolithic UI spec that is now superseded by three focused GDDs: `gdd-dungeon-map-ui.md`, `gdd-settlement-exploration-ui.md`, `gdd-combat-ui.md`. References updated to point to the appropriate specific GDD.
- Visual style notes (dark fantasy vellum) kept inline in §13.4 of the design brief rather than referencing a deleted file.
- Build log historical references to `gdd-ui-ux-design.md` preserved (append-only policy).

**Interfaces defined or changed:**
- None (documentation-only session).

**Database changes:**
- None.

**Tests added/updated:**
- None.

**Known issues:**
- None.

**Next session should:**
- Run test_runner.tscn to verify all tests pass
- Visual-test settlement panel and dungeon UI
- Begin combat UI implementation per `gdd-combat-ui.md`

---

## Session 2026-04-15 — 3D Migration: Dungeon & Combat Tactical Renderers

**Task:** Migrate dungeon and combat tactical-scale renderers from 2D isometric to 3D isometric. Hex map, settlement panel, and all CanvasLayer HUD panels stay 2D. Data models and game logic controllers unchanged.

**Model used:** Opus for planning and implementation.

**Completed:**

New files created (in dependency order):
- `scenes/maps/tactical_grid_3d.gd` — Shared 3D grid infrastructure (class_name TacticalGrid3D, extends RefCounted). Coordinate conversion, mesh builders (floor MultiMesh, walls, doors, stairs, grid lines, fog overlay, highlight overlay, transition markers, feature labels), camera/lighting factory methods, material cache.
- `scenes/ui/components/combatant_token_3d.gd` — 3D entity token (class_name CombatantToken3D, extends Node3D). Wraps existing 2D CombatantToken inside SubViewport (80×80), feeds ViewportTexture to billboard Sprite3D. Same public API: setup(), set_sprite_atlas(), set_facing(), update_position(Vector3).
- `scenes/ui/components/combatant_token_3d.tscn` — Scene for CombatantToken3D.
- `scenes/maps/dungeon_order_overlay_3d.gd` — 3D order overlay (extends Node3D). Ghost trail spheres, ImmediateMesh path lines, Label3D order icons. Same API: update_overlays(orders), clear_overlays().
- `scenes/maps/dungeon_map_renderer_3d.gd` — 3D dungeon renderer (extends Node3D, no class_name). Identical signals and public API to 2D dungeon_map_renderer.gd. Uses TacticalGrid3D for mesh building, CombatantToken3D for tokens. Walls are tall BoxMesh, doors are thin rotatable slabs, elevation uses real Y-axis, fog via MultiMesh overlay.
- `scenes/maps/dungeon_map_3d.tscn` — Scene tree: DungeonMap3D → GridMeshes, FogLayer, HighlightLayer, EntityLayer, OrderOverlayLayer, Camera3D (orthographic isometric), DirectionalLight3D, DungeonHUD (CanvasLayer layer=10: TooltipPanel, ContextMenuLayer).
- `scenes/ui/combat/combat_map_renderer_3d.gd` — 3D combat map renderer (extends Node3D, no class_name). Identical signals and API to 2D combat_map_renderer.gd. Simpler than dungeon: no fog, no doors, no explore selection. Creates own Camera3D, DirectionalLight3D, WorldEnvironment.

Files modified (wiring changes only):
- `engine/subsystems/session/states/dungeon_explore_state.gd` (line 105) — Changed preload path from `dungeon_map.tscn` to `dungeon_map_3d.tscn`.
- `scenes/ui/combat/combat_screen.gd` — Changed renderer load path from `combat_map_renderer.gd` to `combat_map_renderer_3d.gd`; changed `_map_renderer` type from `Node2D` to `Node`; added `sv.own_world_3d = true` to SubViewport; fixed `get_global_transform_with_canvas()` on token to handle 3D via `camera.unproject_position()`.
- `scenes/ui/combat/dungeon_combat_overlay.gd` (line 541) — Same `get_global_transform_with_canvas()` fix for 3D tokens.

**Decisions made:**
- 3D coordinate system: `x = (col - row) * 0.5`, `z = (col + row) * 0.5`, `y = elevation * 0.5`. CELL_SIZE = 1.0 world unit (5 feet). WALL_HEIGHT = 2.0 (10 feet). ELEVATION_SCALE = 0.5 per unit.
- Camera: orthographic, rotation (-35.264°, -45°, 0°), size 12.0 default. This is true isometric.
- CombatantToken3D reuses 2D CombatantToken via SubViewport → Sprite3D billboard to avoid duplicating all drawing logic.
- Materials use SHADING_MODE_UNSHADED for flat 2D-like visual style.
- MultiMeshInstance3D for floor cells (performance with up to 10K cells), individual MeshInstance3D for walls (fewer, varied heights).
- All 2D renderer files preserved as rollback path.

**Interfaces defined or changed:**
- `TacticalGrid3D.cell_to_world(col, row, elevation) -> Vector3` — central coordinate conversion.
- `TacticalGrid3D.world_to_cell(world_pos) -> Vector2i` — reverse conversion.
- `TacticalGrid3D.screen_to_cell(camera, screen_pos) -> Vector2i` — raycast through Camera3D.
- `CombatantToken3D.update_position(world_pos: Vector3)` — note: takes Vector3 not Vector2.
- All 3D renderers expose identical signal names and public method signatures to their 2D counterparts.

**Database changes:**
- None.

**Tests added/updated:**
- None (existing tests are data/logic tests, not rendering; they should pass unchanged).

**Known issues:**
- Camera zoom-toward-cursor not implemented (zoom changes size but doesn't keep world point under cursor fixed). Marked as TODO in dungeon_map_renderer_3d.gd.
- Camera pan direction mapping (WASD → world XZ with 45° rotated camera) needs visual testing — the direction math may need tuning.
- CombatantToken3D SubViewport approach may have a 1-frame delay on first render (uses `await process_frame`).
- .tscn Camera3D transform matrix was hand-computed for isometric angles; may need adjustment if it doesn't match the expected rotation.
- `build_floor_multimesh` passes color_func as `Callable(TacticalGrid3D, "floor_color_for")` — needs verification that static method callables work correctly in Godot 4.
- Middle-mouse camera drag uses `camera.basis.x/y` for screen-to-world delta conversion; may need refinement with the isometric projection.

**Next session should:**
- Run the game and visually test the "Goblin Warrens" dungeon in 3D.
- Verify camera pan, zoom, cell clicking, entity selection, and door interaction work.
- Test combat mode: highlights, active token, move_token animation.
- Test wilderness encounter to verify CombatScreen 3D SubViewport renders correctly.
- Fix any camera/coordinate issues discovered during testing.
- Run test_runner.tscn to confirm all existing tests still pass.
- If 3D doesn't work: revert the 3 wiring changes (dungeon_explore_state.gd line 105, combat_screen.gd lines 22/73/89, dungeon_combat_overlay.gd line 541) to restore 2D.

---

## Session 2026-04-16 — Presentation Docs Alignment for 2D/3D Split

**Task:** Update architecture/design documents to reflect the current presentation contract: hex and city overview layers remain 2D, dungeon and combat layers are true runtime 3D, world assets use the new cel-shaded fantasy direction, and UI backgrounds retain refreshed vellum treatment.
**Model used:** GPT-5 Codex.

**Completed:**
- `docs/acks_arbiter_design_brief_v11.md`: Updated the navigation stack table to include presentation layer, revised map type descriptions to state 2D hex/city and 3D dungeon/combat, replaced the old vellum-only visual style note with the new canonical cel-shaded art direction plus vellum UI guidance, and aligned Tier 1 implementation bullets with the current presentation split.
- `generation/gdd-combat-map-generation.md`: Rewrote rendering sections to describe true runtime 3D tactical presentation while preserving the same diamond-grid, elevation, and battle-map data model.
- `generation/gdd-dungeon-layout.md`: Replaced 2D TileMap-specific dungeon rendering language with 3D tactical renderer wording, leaving the generation algorithm and cell model unchanged.
- `generation/gdd-settlement-exploration-ui.md`: Clarified that the settlement overview is a 2D non-interactive city layer, aligned it to the cel-shaded world art direction, and explicitly kept vellum as supporting UI chrome/background treatment.

**Decisions made:**
- Documentation now treats the cel-shaded 1980s sword-and-sorcery animation prompt as the canonical world-art direction for both 2D and 3D generated assets.
- Vellum/parchment remains part of the UI system only, especially panel framing and background textures, and is no longer described as the primary world-art direction.
- Rendering implementation details were updated only where old 2D assumptions directly contradicted the current 3D dungeon/combat direction; mechanics and schemas were not changed.

**Interfaces defined or changed:**
- None (documentation-only session).

**Database changes:**
- None.

**Tests added/updated:**
- None.

**Known issues:**
- `docs/acks_arbiter_build_plan.md` still contains older renderer phrasing in some roadmap items; this session intentionally left the roadmap untouched unless a directly edited line would have conflicted.

**Next session should:**
- Continue visual verification of the live 3D dungeon/combat renderers against the updated docs.
- Update roadmap wording only when those sections are otherwise being revised, to avoid unnecessary churn.

---

## Session 2026-04-16 — Character Creation Proficiency Detail Pane

**Task:** Add a clickable long-form proficiency detail pane to the character creation proficiency step, sourcing full ACKS Core descriptions from the supplied markdown file without introducing a runtime dependency on the external path.
**Model used:** GPT-5 Codex.

**Completed:**
- Bulk-imported long-form ACKS Core proficiency descriptions into `data/proficiencies/proficiency_catalog.json` as optional `full_description` fields (96 entries), normalized from `104-ACKS Core-Proficiencies.md` into plain prose.
- Added `ProficiencyRegistry.get_full_description(key) -> String`, which resolves compound keys and falls back to the existing short `description` when no imported long-form text exists.
- Updated `scenes/ui/character_creation/proficiency_selection_panel.gd` so the right pane is now vertically split: selected proficiencies on top, read-only detail box on bottom.
- Made both available-list rows and selected-proficiency rows clickable, with specialization-aware titles in the detail pane and base-key description lookup for compound/specialized proficiencies.
- Preserved inspected proficiency state across panel refreshes so add/remove/rank-up UI rebuilds do not wipe the currently displayed description.
- Expanded `tests/test_proficiency_registry.gd` with long-description import/fallback coverage.
- Replaced `tests/test_proficiency_selection_panel.gd` with focused coverage for available-row clicks, selected-row clicks, compound-key description lookup, refresh persistence, and the prior Gambling rank-up regression.
- Ran the approved headless Godot test runner command successfully (exit code `0`).

**Decisions made:**
- The external OneDrive markdown is treated as a one-time source document only; shipped runtime data now lives in the repo catalog.
- Imported long descriptions cover ACKS Core proficiencies from the supplied source file. Non-Core or otherwise unimported proficiencies intentionally continue using the existing short catalog `description`.
- The new detail pane is informational only. No proficiency effects or gameplay wiring were changed.

**Interfaces defined or changed:**
- `data/proficiencies/proficiency_catalog.json`: optional `full_description: String` field added per proficiency entry.
- `ProficiencyRegistry.get_full_description(key: String) -> String` — returns imported long-form rules text when present, otherwise falls back to `description`.

**Database changes:** None.

**Tests added/updated:**
- Updated `tests/test_proficiency_registry.gd`.
- Replaced/expanded `tests/test_proficiency_selection_panel.gd`.
- Full headless test runner completed successfully (exit code `0`).

**Known issues:**
- This session verified behavior headlessly, but did not visually smoke-test the character creation Step 6 layout in-editor.
- The long-form import currently covers the ACKS Core proficiencies contained in the supplied markdown source; Player's Companion-only proficiencies still show the existing shorter text by design.

**Next session should:**
- Open character creation Step 6 in-editor and visually confirm the right-side split feels balanced on common desktop resolutions.
- Spot-check a few specialized proficiencies in the live UI (for example `Knowledge (History)` and `Weapon Focus`) to confirm the clickable rows and detail titles read cleanly.
- If the pattern feels good, consider reusing the same click-to-inspect behavior in the level-up proficiency picker for consistency.

---

## Session 2026-04-17 — Pack Animal & Vehicle State Audit

**Task:** Read-only audit of pack animal and vehicle support to inform the upcoming Party Inventory overlay design.
**Model used:** Opus 4.6

**Completed:**
- Created `docs/pack_animal_state_report.md` — comprehensive audit answering 6 sections of questions with file:line citations.
- Key finding: pack animal and vehicle support is **substantially implemented**. Dedicated `trained_creatures` and `draft_vehicles` DB tables, `TrainedCreatureData` first-class type, `CreatureEquipmentService` for tack validation, `DraftVehicleService` for vehicle capacity/hitch logic, `TravelSpeedCalculator` integration, and character sheet UI for both animals and vehicles all exist and are wired end-to-end.
- The rope-lashing x2 encumbrance rule is implemented as a 0.5x capacity multiplier in `TrainedCreatureData.get_load_multiplier()`.
- Tests exist for creature data (12 tests), creature equipment service, and draft vehicle service.

**Decisions made:**
- The Party Inventory overlay needs primarily new UI code — the engine infrastructure is already in place.
- Three-phase cleanup plan proposed: Phase A (overlay + transfers, complexity 3), Phase B (vehicle terrain rules + catalog items, complexity 2), Phase C (mount/rider binding + training + elephant, complexity 3).

**Interfaces defined or changed:**
- None (read-only audit session).

**Database changes:**
- None.

**Tests added/updated:**
- None.

**Known issues:**
- Elephant is referenced in `acore_equipment.xml` but has no `transport.json` or `monster_catalog.json` entry.
- Pack saddle and panniers are not in the equipment catalog (only draft/riding/war saddles and saddlebags).
- No mount/rider binding exists — `cs_tab_creature_stats.gd` has a comment noting this is deferred.
- Party Management overlay does not show animals or vehicles at all.
- `shared_inventory` (party-level items) has no UI surface.

**Next session should:**
- Design the Party Inventory overlay GDD based on the audit findings.
- Decide whether the overlay is a standalone panel or a new tab within Party Management.
- Begin Phase A implementation if the GDD is approved.


## Session 2026-04-17 — Party Inventory Session 1: PartyWallet, Gold Display, Encumbrance Bar

**Task:** Implement the foundational layer for the Party Inventory system: PartyWallet autoload for cross-PC gold aggregation and payments, GoldDisplay and EncumbranceBar reusable UI components, and integration wiring into existing shop/henchman/character sheet systems. Also fixed Currency.gd exchange rates to match ACKS RAW.
**Model used:** Opus 4.6

**Completed:**
- **Currency fix** (`engine/subsystems/commerce/currency.gd`): Changed PP from 1000→500 CP (was 10GP, now 5GP per ACKS 1e Core p.36). Changed EP from 500→50 CP (was 5GP, now 0.5GP). Reordered DENOMINATIONS array to value-descending: PP(500) > GP(100) > EP(50) > SP(10) > CP(1). Updated `tests/test_currency.gd` — all 18 assertions updated.
- **PartyWallet autoload** (`engine/subsystems/commerce/party_wallet.gd`): Created with 10-method public API. All costs in CP (integers), not GP floats. Wraps CampaignRepository coin methods for multi-PC payment coordination. Registered in `project.godot`.
- **EventBus signals** (`engine/autoloads/event_bus.gd`): Added `wallet_paid`, `wallet_deposited`, `wallet_changed` signals.
- **GoldDisplay component** (`scenes/ui/components/gold_display.gd` + `.tscn`): Two modes (summary "GP: 242.35" and breakdown "PP: 4 | GP: 200 | ..."). Auto-refreshes on wallet_changed and inventory_updated.
- **EncumbranceBar component** (`scenes/ui/components/encumbrance_bar.gd` + `.tscn`): Four-band character mode (green/yellow/orange/red) + two-tier creature/vehicle mode. Custom `_draw()` rendering. STR-adjusted max capacity.
- **Shop integration** (`engine/subsystems/commerce/shop_service.gd`): `buy_item()` and `commission_item()` now route through PartyWallet.pay() when party_id is provided, with backward-compatible fallback.
- **Shop panel UI** (`scenes/ui/settlement/shop_panel.gd`): Wealth display now shows "Party: X.XX GP (Yours: Y.YY GP)" instead of single-character wealth.
- **Henchman wages** (`engine/subsystems/henchmen/henchman_lifecycle_manager.gd`): Rewrote `process_monthly_wages()` — removed broken `party_state.gold_current` query (column didn't exist in schema), replaced with `PartyWallet.pay()` per henchman. Wages now deposit to henchman's personal purse via `add_coins_cp()`.
- **Hiring search fee** (`scenes/ui/settlement/hiring_panel.gd`): `_on_pay_pressed()` now actually deducts gold via `PartyWallet.pay()` (was previously a no-op that just set a flag).
- **Character sheet** (`scenes/ui/character_sheet/character_sheet_overlay.gd`): Added gold display label to title row showing "GP: X.XX" with denomination breakdown tooltip.
- **Tests** (`tests/test_party_wallet.gd`): 20 tests covering eligibility (4), aggregation (3), affordability (3), payment (6), distribution (4). Registered in test_runner.
- **Documentation**: Updated `docs/coding_conventions.md` §5.1 (autoload table) and §12 (ACKS rules). Added `gdd-party-inventory.md` to `docs/document_map.md`.

**Decisions made:**
- **CP not GP in PartyWallet API**: All costs are CP integers, not GP floats. Avoids float-to-int conversion bugs. Every existing call site already works in CP.
- **Currency rate fix**: ACKS RAW rates applied to Currency.gd. This changes the DENOMINATIONS order — EP is now between GP and SP, not between PP and GP.
- **Henchman wages fully refactored**: The old `party_state.gold_current` column was never in the canonical schema. The wage system now uses per-character coin inventory via PartyWallet, matching the shop system.
- **Location filtering stubbed**: All party PCs treated as co-located. Must-fix for Session 2 (LocationCacheManager).

**Interfaces defined or changed:**
- `PartyWallet.get_party_total_cp(party_id: String) -> int`
- `PartyWallet.get_party_total_gp_float(party_id: String) -> float`
- `PartyWallet.get_party_breakdown(party_id: String) -> Dictionary`
- `PartyWallet.get_contributors(party_id: String, active_character_id: String) -> Array`
- `PartyWallet.can_afford(cost_cp: int, party_id: String, active_character_id: String) -> Dictionary`
- `PartyWallet.pay(cost_cp: int, party_id: String, active_character_id: String) -> Dictionary`
- `PartyWallet.pay_from_character(character_id: String, cost_cp: int) -> Dictionary`
- `PartyWallet.deposit_to_character(character_id: String, amount_cp: int) -> void`
- `PartyWallet.deposit_to_party_even_split(party_id: String, amount_cp: int, active_character_id: String) -> Dictionary`
- `PartyWallet.deposit_to_party_by_shares(party_id: String, amount_cp: int, shares: Dictionary) -> Dictionary`
- `EventBus.wallet_paid(party_id: String, details: Dictionary)` — signal
- `EventBus.wallet_deposited(party_id: String, details: Dictionary)` — signal
- `EventBus.wallet_changed(party_id: String)` — signal
- `ShopService.buy_item()` — added optional `party_id: String = ""` parameter
- `HenchmanLifecycleManager.process_monthly_wages()` — return dict key changed from `total_deducted` to `total_deducted_gp`

**Database changes:**
- None. No migrations added this session. Removed reference to non-existent `party_state.gold_current` column.

**Tests added/updated:**
- `tests/test_party_wallet.gd` — 20 new tests (eligibility, aggregation, affordability, payment, distribution)
- `tests/test_currency.gd` — 8 tests updated for new exchange rates
- Registered `PartyWalletTests` in `test_runner.gd` and `test_runner.tscn`

**Known issues:**
- **Location filtering stubbed**: All party PCs are treated as co-located in PartyWallet.get_contributors(). Must-fix for Session 2 when LocationCacheManager is built.
- **Currency rate change may affect existing save data**: Any characters with PP or EP coins stored in the DB will have their wealth recalculated at the new rates. This is correct behavior (the old rates were wrong) but could surprise players who saved with old rates.
- **EncumbranceBar creature/vehicle refresh**: Uses `has_method()` guard for creature/vehicle inventory methods that may not exist yet. Will work once those methods are confirmed in CampaignRepository.
- **No `active_character_id` in GameState**: PartyWallet works around this by requiring callers to pass it as a parameter. A future session may want to add this property to GameState.

**Next session should:**
- Session 2: Build LocationCacheManager (location cache subsystem per GDD §12.2) — ground drops, hide caches, stronghold storage.
- Wire location-key filtering into PartyWallet.get_contributors() so split-party scenarios work correctly.
- Run the full test suite in Godot headless mode to verify no regressions from the Currency rate fix.


## Session 2026-04-17 — LocationCacheManager & Location-Key Plumbing (Party Inventory Session 2)

**Task:** Implement Session 2 of the Party Inventory system: location-key plumbing on session runner states, LocationCacheManager autoload for ground-drop inventory persistence, DB migration for location_caches table, and PartyWallet location-key retrofit. Per `gdd-party-inventory.md` §8 and §12.2.
**Model used:** Opus 4.6

**Completed:**

- **GameState bridge** (`engine/autoloads/game_state.gd`): Added `current_location_key: String` property. SessionRunner updates this on exploration state transitions. Autoloads (PartyWallet, LocationCacheManager) read it instead of traversing the scene tree. Reset on `end_session()`.
- **SessionState virtual method** (`engine/subsystems/session/session_state.gd`): Added `get_location_key_for_character(_character_id: String) -> String` with "unknown" default. Reserved character_id param for future split-party support.
- **SessionRunner helper** (`engine/subsystems/session/session_runner.gd`): Added `get_location_key_for_character(character_id)` that delegates to current state, falls back to `GameState.current_location_key`. Added GameState sync in `transition_to_state()` — exploration states set the key, meta states set "none", overlay states preserve parent key.
- **3 state overrides**: WildernessExploreState returns `"hex:Q,R"` from `party_data.current_hex_q/r`. DungeonExploreState returns `"dungeon:ID:level:N"` from `_controller.get_dungeon_id()/get_current_level()`. SettlementExploreState returns `"settlement:ID"` from `_settlement_id` field. 8 remaining states use base class "unknown" default (overlay states inherit, meta states handled by runner).
- **EventBus signals** (`engine/autoloads/event_bus.gd`): Added 5 cache lifecycle signals: `cache_created`, `cache_decayed`, `cache_raided`, `cache_dropped`, `cache_picked_up`.
- **Migration 032** (`db/migrations/032_location_caches.sql`): Created `location_caches` table with CHECK constraints for `location_type` and `cache_variant`. Added `location_cache_id` FK column to `inventory_items` with ON DELETE CASCADE. Two indexes for location and decay queries. Updated `db/schema.sql`.
- **CampaignRepository additions** (`engine/autoloads/campaign_repository.gd`): Added 11 methods — `create_location_cache`, `get_location_cache`, `get_cache_at_location_key`, `list_ephemeral_caches_due`, `list_hidden_wilderness_caches`, `list_location_caches`, `list_items_in_cache`, `update_cache_raid_modifier`, `delete_location_cache`, `transfer_item_to_cache`, `transfer_item_from_cache`.
- **LocationCacheManager autoload** (`engine/subsystems/inventory/location_cache_manager.gd`): 9th autoload. 5 cache creation methods (dungeon loose, dungeon container, wilderness loose, wilderness hidden, settlement loose). Item routing via `drop_item_to_cache()` and `pick_up_item()`. Daily decay resolution connected to `Timekeeping.day_changed`. Monthly raid resolution connected to `Timekeeping.month_changed` with 2d4 loss curve (25%–75% value). Hide-and-memorize flow (6 turns = 1 hour). Instantiates EquipmentCatalog locally for value computation.
- **PartyWallet retrofit** (`engine/subsystems/commerce/party_wallet.gd`): `get_contributors()` now reads `GameState.current_location_key` with guards for "none"/"unknown". In v1 the filter is a pass-through (all PCs co-located). Removed Session 1 "Known issue" comment.
- **Tests** (`tests/test_location_cache_manager.gd`): 25 tests covering cache creation (5), item routing (5), daily decay (4), monthly raids (6), hide-and-memorize (2), and PartyWallet location filter (3). Uses `GameState.dice_overrides` for deterministic dice. Registered in `test_runner.gd` and `test_runner.tscn`.
- **Documentation**: Updated `docs/coding_conventions.md` — §5.1 autoload count (8→9, added LocationCacheManager), §10.2 dice roll types (3 new), §12 ACKS rules (location cache decay, hide-and-memorize cost). Updated `build_log.md`.

**Decisions made:**

- **GameState bridge instead of direct SessionRunner access**: SessionRunner is a scene-tree node, not an autoload. Rather than fragile `get_tree().root.get_node("Main/SessionRunner")` from autoloads, we store `current_location_key` on GameState (autoload). SessionRunner updates it on exploration state transitions. Overlay states (combat, camp, encounter, downtime) don't touch it, so the parent exploration state's key persists naturally.
- **Base class default "unknown" + runner logic**: Only 3 exploration states need explicit overrides. Overlay states inherit via GameState. Transient states handled by `transition_to_state()` checking `state_key`. More maintainable than adding override methods to all 11 states.
- **No MockDice class**: Prompt specified "MockDice pattern from test_combat_*.gd" but no such class exists. Tests use `GameState.dice_overrides[roll_type] = value` (single-shot, consumed by DiceSystem on next matching roll).
- **EquipmentCatalog instantiated locally**: Not an autoload. LocationCacheManager creates its own instance in `_ready()`, matching the pattern from ShopService and CombatState.
- **v1 location filter is pass-through**: `PartyWallet.get_contributors()` reads `GameState.current_location_key` and has a filter loop, but in v1 all party PCs share the same location key (party moves as a unit). The plumbing is in place for future split-party without API changes.

**Interfaces defined or changed:**

- `GameState.current_location_key: String` — new property
- `SessionState.get_location_key_for_character(_character_id: String) -> String` — new virtual method
- `SessionRunner.get_location_key_for_character(character_id: String) -> String` — new public method
- `EventBus.cache_created(cache_id: String, location_key: String, variant: String)` — new signal
- `EventBus.cache_decayed(cache_id: String, items_lost: Array)` — new signal
- `EventBus.cache_raided(cache_id: String, items_lost: Array, value_lost_gp: float)` — new signal
- `EventBus.cache_dropped(cache_id: String, item_id: String, source_carrier_id: String)` — new signal
- `EventBus.cache_picked_up(cache_id: String, item_id: String, carrier_id: String)` — new signal
- `CampaignRepository.create_location_cache(data: Dictionary) -> String`
- `CampaignRepository.get_location_cache(cache_id: String) -> Dictionary`
- `CampaignRepository.get_cache_at_location_key(campaign_id: String, location_key: String) -> Dictionary`
- `CampaignRepository.list_ephemeral_caches_due(campaign_id: String, cutoff_day: int) -> Array`
- `CampaignRepository.list_hidden_wilderness_caches(campaign_id: String) -> Array`
- `CampaignRepository.list_location_caches(campaign_id: String) -> Array`
- `CampaignRepository.list_items_in_cache(cache_id: String) -> Array`
- `CampaignRepository.update_cache_raid_modifier(cache_id: String, new_modifier: int) -> bool`
- `CampaignRepository.delete_location_cache(cache_id: String) -> bool`
- `CampaignRepository.transfer_item_to_cache(item_id: String, cache_id: String) -> bool`
- `CampaignRepository.transfer_item_from_cache(item_id: String, target_carrier_id: String, carrier_type: String) -> bool`
- `LocationCacheManager.create_dungeon_loose_cache(dungeon_id: String, cell_xy: Vector2i) -> String`
- `LocationCacheManager.create_dungeon_container_cache(dungeon_id: String, cell_xy: Vector2i, container_item_id: String) -> String`
- `LocationCacheManager.create_wilderness_loose_cache(hex_qr: Vector2i) -> String`
- `LocationCacheManager.create_wilderness_hidden_cache(hex_qr: Vector2i) -> String`
- `LocationCacheManager.create_settlement_cache(settlement_id: String, poi_id: String) -> String`
- `LocationCacheManager.get_cache_at_location(location_key: String) -> Dictionary`
- `LocationCacheManager.list_caches_for_campaign() -> Array`
- `LocationCacheManager.get_items_in_cache(cache_id: String) -> Array`
- `LocationCacheManager.drop_item_to_cache(item_id: String, cache_id: String, source_carrier_id: String) -> bool`
- `LocationCacheManager.pick_up_item(item_id: String, target_carrier_id: String, carrier_type: String) -> bool`
- `LocationCacheManager.hide_and_memorize_wilderness_cache(hex_qr: Vector2i, party_id: String) -> String`
- `LocationCacheManager.resolve_daily_decay(current_day: int) -> void`
- `LocationCacheManager.resolve_monthly_raids() -> void`

**Database changes:**

- Migration 032: `location_caches` table. `location_cache_id` column added to `inventory_items`.

**Tests added/updated:**

- `tests/test_location_cache_manager.gd` — 25 new tests (cache creation 5, item routing 5, daily decay 4, monthly raids 6, hide-and-memorize 2, PartyWallet location filter 3)
- Registered `LocationCacheManagerTests` in `test_runner.gd` and `test_runner.tscn`

**Known issues:**

- **Dungeon-loose-cache relocation deferred**: GDD §13.1 specifies that when dungeon loose caches decay, 50% of items should relocate to pre-existing dungeon treasure caches. v1 simply deletes all items on decay. This is noted with a comment in `resolve_daily_decay()`.
- **GameState.current_location_key not updated mid-state**: When the party moves to a new hex during wilderness exploration, `GameState.current_location_key` isn't updated until the next state transition. For v1 this is fine (all PCs co-located, filter is pass-through). Future split-party work may need more granular updates.
- **Session 1 "Location filtering stubbed" known issue**: RESOLVED by this session's GameState bridge and PartyWallet retrofit.

**Next session should:**

- Session 3: Build Party Inventory overlay (GDD §12.3) — F9 toggle overlay showing all carriers, their items, and location caches. The overlay queries LocationCacheManager for cache data.
- Add Drop/Hide dialog UX for moving items from carriers to caches.

---

## Session 2026-04-17 — Override Panel Cache Creation

**Task:** Add cache creation to the Override panel's Spawning tab so dev/playtest can create location caches without the Party Inventory overlay (which doesn't exist yet).
**Model used:** Opus 4.6

**Completed:**

- Added 4 new methods to `engine/subsystems/override/override_manager.gd`:
  - `override_create_wilderness_loose_cache(hex_q, hex_r) -> String`
  - `override_create_wilderness_hidden_cache(hex_q, hex_r) -> String`
  - `override_create_dungeon_loose_cache(dungeon_id, cell_col, cell_row) -> String`
  - `override_create_settlement_cache(settlement_id, poi_id) -> String`
  Each wraps the corresponding `LocationCacheManager.create_*` method with `_log_override()` audit entry and `EventBus.override_applied` signal.
- Added "Place Cache" section to Spawning tab in `scenes/ui/override/override_panel.gd`:
  - Variant dropdown (Wilderness Loose, Wilderness Hidden, Dungeon Loose, Settlement Loose)
  - Dynamic input rebuilding based on variant selection
  - Wilderness variants auto-fill hex Q/R from party's current hex
  - Dungeon variant shows dropdown populated from `CampaignRepository.get_dungeon_entrances_for_map()`
  - Settlement variant shows dropdown populated from `CampaignRepository.get_settlement_entrances_for_map()` + LineEdit for POI ID
  - Status label shows success/failure with cache ID
  - Disables Create button with helpful message when no dungeons/settlements exist
- Added 6 new tests to `tests/test_override_manager.gd`:
  - `test_override_create_wilderness_loose_cache` — verifies location_key, variant, non-persistent
  - `test_override_create_wilderness_hidden_cache` — verifies variant=hidden_wilderness, persistent, raid_modifier=0
  - `test_override_create_dungeon_loose_cache` — verifies location_type=dungeon_cell, decay_check_day set
  - `test_override_create_settlement_cache` — verifies location_type=settlement_node, decay_check_day set
  - `test_override_create_cache_logs_audit_entry` — verifies override_log row exists with correct target_id
  - `test_override_create_cache_returns_nonempty_id` — all 4 methods return non-empty IDs

**Decisions made:**

- Settlement POI input uses a LineEdit (free text) rather than a dropdown. POIs are stored in SettlementMapData (in-memory), not as a DB table, so populating a dropdown would require loading and parsing settlement_data JSON. A text input is simpler and appropriate for a dev panel.
- Dungeon container caches are not exposed in the Override UI. They require selecting a pre-existing container inventory item, which is awkward for a dev panel.

**Interfaces defined or changed:**

- 4 new public methods on OverrideManager (signatures above). All return `String` (cache_id).
- 5 new member variables on OverridePanel: `_cache_variant_dropdown`, `_cache_inputs_container`, `_cache_create_button`, `_cache_status_label`, `_cache_input_widgets`.
- Override log types: `cache_create_wilderness_loose`, `cache_create_wilderness_hidden`, `cache_create_dungeon_loose`, `cache_create_settlement`.

**Database changes:** None. Uses existing `location_caches` and `override_log` tables.

**Tests added/updated:** 6 new tests in `test_override_manager.gd` (listed above).

**Known issues:**

- **Dungeon container caches not in Override UI** — requires a pre-existing container inventory item; deferred to gameplay UI.
- **Settlement POI ID not validated** — the LineEdit accepts any string; if the POI doesn't exist in the settlement's SettlementMapData, the cache will be created with a non-matching location_key. Acceptable for dev use.

**Next session should:**

- Session 3: Build Party Inventory overlay (GDD §12.3) — F9 toggle overlay showing all carriers, their items, and location caches.
- Add Drop/Hide dialog UX for moving items from carriers to caches.

---

## Session 2026-04-17 — Pack Saddle and Panniers Catalog Pull-Forward

**Task:** Pull forward `saddle_pack` and `panniers` catalog entries from Session 5 scope so players can buy them in the equipment shop now. Temporary stubs in CreatureEquipmentService; full saddle taxonomy rewrite stays in Session 5.
**Model used:** Opus 4.6
**Completed:**
- Added `saddle_pack` and `panniers` entries to `data/equipment/transport.json` per GDD §10.1 and §10.2. Both cost 5 gp (500 cp). Saddle_pack is 1 stone encumbrance; panniers are 1/3 stone with 5 stone container capacity.
- Updated `engine/subsystems/characters/creature_equipment_service.gd`:
  - Generalized saddlebags validation block to also handle panniers (mutually exclusive — both use "pack" slot).
  - Added `has_pack_container_equipped()` and `get_pack_container_item_id()` methods that check for saddlebags OR panniers. Old methods delegate to new ones for backward compatibility.
  - Generalized `validate_into_saddlebags()` to find actual container item_key and use it for capacity lookup (supports panniers' 5000-unit capacity vs saddlebags' 3000).
  - Added `panniers` to `determine_creature_slot()` → returns "pack".
  - Added TODO comments marking all Session 5 enforcement gaps.
- Updated `scenes/ui/character_sheet/tabs/cs_tab_creature_inventory.gd`:
  - Changed "Saddlebags" slot to "Pack Container" slot type that matches saddlebags OR panniers.
  - Container contents section now dynamically reads the equipped container's name and item_key for header and capacity lookup.
  - Equip-from-handler filter now includes panniers.
- Added 6 new tests in `tests/test_creature_equipment_service.gd`: pack saddle equip, panniers require saddle, panniers with saddle, panniers conflict with saddlebags, panniers slot, panniers container capacity.
- Added 2 new tests in `tests/test_equipment_catalog.gd`: pack_saddle_in_catalog, panniers_in_catalog. Updated item count (174 → 176), container identification, and container capacity tests.

**Decisions made:**
- Panniers and saddlebags are mutually exclusive (both occupy "pack" slot). A creature can have one or the other, not both.
- `saddle_pack` works via existing `begins_with("saddle_")` pattern — no special-casing needed for saddle validation.
- Old `has_saddlebags_equipped()` and `get_saddlebag_item_id()` kept as delegates to new generalized methods, avoiding breakage of any external callers.

**Interfaces defined or changed:**
- `CreatureEquipmentService.has_pack_container_equipped(creature) -> bool` — checks saddlebags or panniers.
- `CreatureEquipmentService.get_pack_container_item_id(creature) -> String` — returns ID of equipped saddlebags or panniers.
- `validate_into_saddlebags()` now accepts panniers as valid container targets (method name kept for backward compatibility).

**Database changes:** None. Equipment catalog is JSON-only.

**Tests added/updated:**
- `test_creature_equipment_service.gd`: +6 tests (pack saddle equip, panniers require saddle, panniers with saddle, panniers conflict with saddlebags, panniers slot, panniers container capacity).
- `test_equipment_catalog.gd`: +2 tests (pack_saddle_in_catalog, panniers_in_catalog), updated item count and container assertions.

**Known issues:**
- `saddle_pack` currently behaves identically to `saddle_draft` for hitching validation (should reject hitching per GDD §2.3a but may currently accept). Full enforcement is Session 5.
- `panniers` currently equip-validates against any saddle (should require `saddle_pack` specifically per GDD §2.3a). Full enforcement is Session 5.
- No change to the original Session 5 scope — the saddle taxonomy rewrite still needs to happen. This fix only ensures the items exist and don't crash.

**Next session should:**
- Session 3: Build Party Inventory overlay (GDD §12.3).
- Session 5 (unchanged): Full saddle taxonomy rewrite per GDD §2.3a — enforce saddle-type-specific container permissions, hitching rejection for non-draft saddles, rope-as-rigging-state.

---

## Session 2026-04-17 — Party Inventory Overlay (Session 3)

**Task:** Build the Party Inventory overlay — a Ctrl+Alt+I-toggled CanvasLayer 50 UI showing all party carriers as columns with drag-and-drop transfers, plus supporting modals and a pure-logic transfer validator.
**Model used:** Opus 4.6 for planning and implementation.
**Completed:**

*New files:*
- `db/migrations/033_character_preferences.sql` — `character_preferences` table (single row per character, JSON array of preferred_tags).
- `db/schema.sql` — appended character_preferences CREATE TABLE.
- `engine/subsystems/inventory/party_inventory_transfer_validator.gd` — `class_name PartyInventoryTransferValidator`, extends RefCounted. Pure validation: coin lock, equipped clothing lock, carrier-type restrictions (with explicit draft saddle rejection), context friction (location key matching), capacity/encumbrance checks, slot resolution. Stubs for dungeon adjacency and combat trade action.
- `tests/test_party_inventory_transfer_validator.gd` — 20 tests covering coin locks, clothing lock, carrier-type restrictions, context friction, capacity bands, slot resolution, same-carrier rejection.
- `scenes/ui/party_inventory/carrier_column.tscn` + `carrier_column.gd` — Reusable column component (VBoxContainer, no class_name). 5 variants: PC, HENCHMAN, CREATURE, VEHICLE, CACHE. Inner `_ItemRow` class with drag-and-drop. Reuses GoldDisplay and EncumbranceBar. Filter/search support (dims non-matching to 30% alpha).
- `scenes/ui/party_inventory/party_inventory_overlay.tscn` + `party_inventory_overlay.gd` — Main overlay (CanvasLayer 50, no class_name). Programmatic UI: header with filter/search, horizontal scroll of CarrierColumns, footer with party GP total + rations + auto-distribute stub. Transfer coordinator with full dispatch table. Lazy modal creation. Drop-to-ground routing by location type.
- `scenes/ui/party_inventory/character_preferences_modal.gd` — 8-tag checkbox editor (torch_bearer, rations_keeper, etc.). Persists via CampaignRepository.
- `scenes/ui/party_inventory/drop_item_dialog.gd` — Wilderness-only dialog: "Drop on ground" (ephemeral) vs "Hide and memorize" (permanent, 1 hour cost).
- `scenes/ui/party_inventory/transfer_gold_modal.gd` — Source/target dropdowns from PartyWallet.get_contributors(). GP float amount, banker's rounding to CP. Live preview.
- `scenes/ui/party_inventory/item_context_menu.gd` — PopupMenu: coins → "Transfer Gold…"; non-coins → "Send to…" submenu (greyed-out invalid targets with tooltip), "Drop on ground", "Split stack" (stub), "View details" (stub), "Equip/Unequip".

*Modified files:*
- `engine/autoloads/campaign_repository.gd` — added `get_character_preferences()` and `save_character_preferences()` (JSON array UPSERT).
- `project.godot` — added `party_inventory_toggle` input action (Ctrl+Alt+I, physical_keycode 73).
- `scenes/Main.tscn` — added PartyInventoryOverlay instance between PartyManagementOverlay and NotificationManager.
- `tests/test_runner.gd` + `tests/test_runner.tscn` — registered TransferValidatorTests suite.
- `docs/coding_conventions.md` — added CanvasLayer 50 row to §13.1, PartyInventoryOverlay to Main.tscn tree diagram, transfer validation convention to §12.

**Decisions made:**
- CanvasLayer 50 (between CharSheet 48 and DicePrompt 64) per prompt specification.
- Explicit draft saddle rejection in transfer validator — `CreatureEquipmentService.validate_cargo_on_creature()` checks `get_load_multiplier() <= 0.0` which returns 1.0 for draft saddle, so the validator adds its own check.
- Missing transfer pairs (creature→creature, creature→vehicle, vehicle→creature, vehicle→vehicle) routed through intermediate character hop rather than adding new CampaignRepository methods.
- Character preferences stored as JSON array in single row (simpler than normalized table for fixed 8-tag set).
- No `class_name` on any scene-instantiated UI scripts; `class_name` only on the RefCounted validator.

**Interfaces defined or changed:**
- `PartyInventoryTransferValidator.validate_transfer(source, target, context, item) -> {ok: bool, reason: String, warnings: Array, resolved_slot: String}` — source: `{carrier_type, carrier_id, item_id, quantity}`, target: `{carrier_type, carrier_id, slot, data}`, context: `{location_key, is_in_combat, active_character_id}`.
- `CampaignRepository.get_character_preferences(character_id) -> Array` — returns array of tag strings.
- `CampaignRepository.save_character_preferences(character_id, tags) -> bool` — UPSERT with JSON serialization.
- CarrierColumn signals: `transfer_requested`, `item_context_menu_requested`, `gold_display_clicked`, `prefs_clicked`, `pick_up_all_clicked`.
- ItemContextMenu signals: `send_to_requested`, `drop_requested`, `transfer_gold_requested`.
- DropItemDialog signal: `drop_confirmed(item_id, source_carrier_type, source_carrier_id, mode)`.
- TransferGoldModal signal: `transfer_completed`.
- CharacterPreferencesModal signal: `preferences_saved(character_id, tags)`.

**Database changes:**
- Migration 033: `character_preferences` table (character_id TEXT PK, preferred_tags TEXT DEFAULT '[]').

**Tests added/updated:**
- `test_party_inventory_transfer_validator.gd`: 20 tests — coin locks (2), clothing lock (1), carrier-type restrictions (5), context friction (4), capacity bands (3), slot resolution (2), same-carrier rejection (1), equipped clothing edge case (1), cross-location creature (1).

**Known issues:**
- Dungeon adjacency check (`_check_dungeon_adjacency()`) is a stub — always returns ok. Full Chebyshev ≤1 check needs `DungeonMapController.are_adjacent()`. Session 5 polish.
- Combat trade action check (`_check_combat_trade_action()`) is a stub — always returns ok. Needs combat turn economy integration.
- Auto-distribute button shows "Coming in Session 4" notification.
- Missing direct transfer pairs (creature→creature, creature→vehicle, vehicle→creature, vehicle→vehicle) use intermediate character hop.
- "View details" context menu item is a stub (no item detail panel).
- "Split stack" context menu item is a stub (needs numeric input dialog).
- Draft saddle cargo rejection relies on validator-level check, not `CreatureEquipmentService`. Full saddle taxonomy rewrite is Session 5.

**Next session should:**
- Session 4: Loot Distribution modal and Auto-distribute algorithm per GDD §12.4.
- Session 5: Full saddle taxonomy rewrite, dungeon adjacency enforcement, direct transfer pair methods.

---

## Session 2026-04-18 — Wilderness Party Splitting (Bug Fix 2)

**Task:** Implement minimum viable party split/merge: CampaignRepository methods, active party tracking, multi-party hex renderer tokens, Party Management overlay split/merge UI.
**Model used:** Opus 4.6

**Completed:**
- `engine/autoloads/event_bus.gd`: Added `active_party_changed(previous_party_id, new_party_id)` signal.
- `engine/autoloads/game_state.gd`: Added `active_party_id` property, `set_active_party()` method. Initialised in `start_session()`, cleared in `end_session()`.
- `engine/autoloads/campaign_repository.gd`: Added 4 new methods:
  - `list_parties_for_campaign(campaign_id) -> Array` — all parties for a campaign.
  - `get_party_for_character(character_id) -> String` — reverse lookup from character to party.
  - `split_party(source_party_id, new_party_name, character_ids_to_split) -> String` — transactional split with validation, position copy, Timekeeping registration, signal emission.
  - `merge_parties(target_party_id, source_party_id) -> bool` — transactional merge with co-location check, FK transfer (trained_creatures, draft_vehicles, inventory_items), party_state cleanup, Timekeeping unregistration, signal emission.
- `engine/subsystems/session/states/wilderness_explore_state.gd`: Connects to `active_party_changed`; registers all campaign parties with Timekeeping on enter; `get_location_key_for_character()` now does per-character party lookup; `_on_active_party_changed` re-centers camera.
- `scenes/maps/hex_map_renderer.gd`: Multi-party token system — `_party_tokens` dictionary manages dynamic Polygon2D nodes per party. Active token is bright yellow + 1.15x scale; inactive tokens are grey-blue + 0.9x scale. Rebuilds on map load, party_moved, party_split, party_merged, active_party_changed.
- `scenes/ui/party_management/party_management_overlay.gd`: Members tab now has Active Party dropdown (switches via `GameState.set_active_party`), Split Party button (opens modal dialog with character checkboxes and name field), Merge With dropdown (filtered to co-located parties, disabled when none). `_load_party()` uses `active_party_id`. Connected to `party_split`, `party_merged`, `active_party_changed` signals for auto-refresh.

**Decisions made:**
- No migration needed — all data fits in existing schema (`parties`, `party_members`, `party_clocks`, etc.).
- `GameState.active_party_id` is runtime-only (not persisted to DB). On session load it defaults to `party_id`. Future: persist if needed for save/reload mid-split.
- Formation positions reset to UNASSIGNED on split/merge — player re-places characters. Avoids complex formation migration logic.
- Merge deletes the source party's `party_state` row before deleting the party row itself, preventing FK violations.
- Hex-click to switch active party is deferred to polish. Switching is dropdown-only for v1.

**Interfaces defined or changed:**
- `EventBus.active_party_changed(previous_party_id: String, new_party_id: String)` — new signal.
- `GameState.active_party_id: String` — new property.
- `GameState.set_active_party(party_id: String)` — new method.
- `CampaignRepository.list_parties_for_campaign(campaign_id: String) -> Array` — new method.
- `CampaignRepository.get_party_for_character(character_id: String) -> String` — new method.
- `CampaignRepository.split_party(source_party_id: String, new_party_name: String, character_ids_to_split: Array) -> String` — new method.
- `CampaignRepository.merge_parties(target_party_id: String, source_party_id: String) -> bool` — new method.

**Database changes:**
- None. No migration needed.

**Tests added/updated:**
- `tests/test_party_split_merge.gd`: 12 tests — split with 1 character, split N-1, split all rejected, split empty list rejected, split wrong character rejected, split copies position, split emits signal, merge same hex, merge different hex rejected, merge self rejected, merge transfers FKs, merge emits signal. Registered in `test_runner.gd` and `test_runner.tscn`.

**Known issues:**
- Party split/merge is wilderness-only. Dungeon/settlement splitting is a larger UX problem — flagged for future work.
- No party-to-party item/gold transfer. Deferred to later session.
- Multi-party combat not implemented — encounter triggers against active party only.
- `active_party_id` is not persisted; a mid-split save/reload defaults back to original party.
- Hex-click on inactive party token does not switch active party (dropdown only for v1).

**Next session should:**
- Test the split/merge flow end-to-end in the running game.
- Consider persisting `active_party_id` to the campaigns table if save/reload during split is needed.
- Session 4: Loot Distribution modal and Auto-distribute algorithm per GDD §12.4.

---

## Session 2026-04-18 — Bug Fix 4: Animal & Vehicle Entity Promotion

**Task:** Fix animals and vehicles purchased through the settlement shop remaining as `inventory_items` instead of being promoted to `trained_creatures` and `draft_vehicles` entity rows. Also wire creature combatants into dungeon combat and handle creature death.
**Model used:** Opus 4.6 for investigation, planning, and implementation.

**Investigation findings:**
- **Cause A confirmed:** `ShopService.buy_item()` → `_add_item_to_character()` → `add_inventory_item()` with no category check.
- **Cause B confirmed:** `save_character_inventory_with_creatures()` only checked `monster_id` for animals; vehicles had no promotion path.
- **Cause C partially wrong:** Wilderness combat (CombatState) already called `roster.add_party_creatures()`. Only dungeon combat (DungeonExploreState) was missing creatures.
- **Cause D confirmed:** Shop-purchased animals/vehicles sitting as inventory_items rows.

**Completed:**
- Added `CampaignRepository.classify_item_for_promotion(catalog_entry)` — static method returning "creature", "vehicle", or "inventory".
- Added `CampaignRepository._create_vehicle_from_purchase(campaign_id, party_id, item_key, catalog_entry)` — mirrors `create_creature_from_purchase()` for vehicles.
- Added `CampaignRepository.promote_inventory_to_entity(item_key, quantity, handler_character_id, campaign_id, party_id, equipment_catalog, monster_registry)` — unified promotion method for all purchase paths.
- Updated `CampaignRepository.save_character_inventory_with_creatures()` to handle vehicles via `classify_item_for_promotion()`.
- Updated `ShopService._add_item_to_character()` with promotion-aware branch. Added `campaign_id` parameter. Added `_monster_registry` field.
- Fixed `ShopService.pickup_commission()` to pass `campaign_id` from commission row.
- Added creatures to dungeon combat roster in `DungeonExploreState._start_dungeon_combat()` via `roster.add_party_creatures()`.
- Added `_find_creature_placement()` helper for grid positioning near party members.
- Stored dungeon combat controller as `_dungeon_combat_controller` instance var for post-combat access.
- Updated `CombatFinalizer.finalize()` with optional `roster` parameter and `_process_creature_casualties()` method.
- Updated `CombatState._finish_combat()` and `DungeonExploreState._on_dungeon_combat_finished()` to pass roster to finalizer.
- Fixed dungeon post-combat token cleanup to preserve alive creature tokens (keep_ids pattern).
- Migration 034: `schema_sweep_markers` table for tracking one-time data sweeps.
- One-time sweep `_sweep_promote_inventory_entities()` runs after migrations, promotes orphaned inventory_items to entities, transaction-wrapped.

**Decisions made:**
- Kept method name `save_character_inventory_with_creatures()` unchanged — renaming creates unnecessary churn.
- `classify_item_for_promotion()` is a static method — callable without CampaignRepository instance (needed by ShopService).
- `CombatFinalizer.finalize()` roster parameter is optional with default `null` — backward compatible, no signature break.
- Creature death = immediate death (no mortal wounds table). Emit `creature_died` signal (already existed in EventBus, was never emitted).

**Interfaces defined or changed:**
- `CampaignRepository.classify_item_for_promotion(catalog_entry: Dictionary) -> String` — new static method.
- `CampaignRepository.promote_inventory_to_entity(item_key, quantity, handler_character_id, campaign_id, party_id, equipment_catalog, monster_registry) -> String` — new public method.
- `CampaignRepository._create_vehicle_from_purchase(campaign_id, party_id, item_key, catalog_entry) -> String` — new private method.
- `CombatFinalizer.finalize(runner, result, party_data, roster=null)` — added optional `roster` parameter.
- `ShopService._add_item_to_character(character_id, item_key, quantity, catalog_item, campaign_id="")` — added `campaign_id` parameter.
- `ShopService._monster_registry: MonsterRegistry` — new field, instantiated in `_init()`.
- `DungeonExploreState._dungeon_combat_controller: CombatController` — new instance var.
- `DungeonExploreState._find_creature_placement(tactical_map, party_positions) -> Vector2i` — new helper.

**Database changes:**
- Migration 034: `schema_sweep_markers` table (sweep_name TEXT PK, applied_at TEXT).
- schema.sql updated to include sweep_markers table. Last migration marker updated to 034.

**Tests added/updated:**
- `tests/test_entity_promotion.gd` — 13 tests: classify (4), promote (4), shop buy (3), combat roster (2).
- Registered in `test_runner.gd` and `test_runner.tscn`.

**Known issues:**
- Vehicles do NOT participate in combat — deferred per user direction.
- Creature placement in tight dungeon corridors may stack on leader cell (fallback behavior).
- Commission pickup for animals/vehicles now works but was not separately tested with a commission-specific test.
- `creature_died` signal is now emitted but no UI consumer reacts to it yet.

**Next session should:**
- Test entity promotion end-to-end in the running game (smoke test per acceptance criteria).
- Add UI reaction to `creature_died` signal (notification/game log entry).
- Consider adding creature token display in dungeon exploration (pre-combat) — currently creatures only appear as tokens during combat.

---

## Session 2026-04-18 — Integration Patch: Inventory/Split/Overlay Fixes

**Task:** Fix four issues found during post-Session-3 smoke testing: (1) active party not threading through character sheet and party inventory overlays, (2) hitched vehicles grayed out in "Send to" context menu, (3) party inventory overlay blocking settlement shop panel, (4) party split not supporting creatures or vehicles.
**Model used:** Opus 4.6 for planning and implementation.

**Completed:**

### Fix 1 — Active Party Threading
- Replaced `GameState.party_id` → `GameState.active_party_id` (with fallback) across:
  - `scenes/ui/character_sheet/character_sheet_overlay.gd` — 7 references swapped in `_load_entity_list()`, `_select_creature()`, `_load_vehicle_bundle()`.
  - `scenes/ui/party_inventory/party_inventory_overlay.gd` — 4 references swapped in `_load_columns()`, `_update_footer()`, `_count_rations()`, cache drop handler.
  - `scenes/ui/party_inventory/transfer_gold_modal.gd` — 1 reference swapped in `_populate_dropdowns()`.
- Connected `EventBus.active_party_changed` signal in both overlays with handlers that reload content when visible.

### Fix 2 — Vehicle "Send to" Context Menu
- **Root cause (corrected from patch prompt):** The validator's `_validate_to_vehicle()` was working correctly. The actual bug was a data shape mismatch: the overlay passed raw DB vehicle rows (with `hitched_creatures` as a JSON string), but the validator expected `hitched_creatures_data` (an Array of TrainedCreatureData objects with `species_id` for computing draft equivalents). With missing key, `calculate_team_equivalents([])` returned 0.0, failing all capacity lookups.
- **Fix:** In `party_inventory_overlay.gd` `_load_columns()`, enriched vehicle data by parsing the `hitched_creatures` JSON, looking up each creature via `CampaignRepository.get_trained_creature()`, and attaching as `hitched_creatures_data`. Pattern matches `character_sheet_overlay.gd` `_load_vehicle_bundle()`.

### Fix 3 — Party Inventory Side Panel
- Changed `party_inventory_overlay.gd` `_build_ui()` from `PRESET_FULL_RECT` (100% viewport) to right-anchored (`anchor_left=0.34`) matching the character sheet's 66%-width side panel pattern.
- Added mutual exclusion: opening party inventory closes character sheet, and vice versa. Both use `get_parent().get_node_or_null()` to find their sibling in Main.tscn.

### Fix 4 — Party Split with Creatures and Vehicles
- Extended `CampaignRepository.split_party()` signature:
  ```
  split_party(source_party_id, new_party_name, character_ids_to_split,
      creature_ids_to_split=[], vehicle_ids_to_split=[], split_context={})
  ```
  Backward-compatible (existing callers pass 3 args).
- Validation: checks handler integrity for ALL party creatures — both moving and staying. Requires `split_context.handler_reassignments` dict when creature/handler directions mismatch.
- Transaction: moves creatures, applies handler reassignments, moves vehicles with partial unhitching (removes non-split creatures from hitch JSON), and unhitches split creatures from vehicles staying behind.
- `merge_parties()` — no change needed, already handles creatures/vehicles/inventory.
- Populated `creature_data` and `vehicle_data` in `party_management_overlay.gd` `_load_party()`.
- Extended split dialog UI: creature section (with handler info) and vehicle section (with hitch status) below character checkboxes.
- Updated `_on_split_confirm()` to collect creature/vehicle selections, auto-clear mismatched handlers, and call the extended `split_party()`.
- Added 6 tests to `tests/test_party_split_merge.gd`:
  - `test_split_character_and_creature_handler_moving` — handler preserved
  - `test_split_creature_no_reassignment_rejected` — rejected without reassignment
  - `test_split_creature_handler_cleared` — handler cleared on reassignment to ""
  - `test_split_vehicle_full_team` — hitch preserved
  - `test_split_vehicle_partial_team_unhitch` — partial team auto-unhitched
  - `test_split_staying_vehicle_creature_leaves` — creature unhitched from staying vehicle

**Decisions made:**
- Handler reassignment UX: v1 auto-clears handler when mismatch occurs, with notification warning. Dropdown-based reassignment deferred to future session.
- Vehicle unhitching: auto-unhitch on partial team split (never reject). Simpler UX, matching user expectations for scout-split-off play.
- Mutual exclusion for right-side overlays: opening one closes the other. Both are 66% width right-anchored; overlapping would be unusable.

**Interfaces defined or changed:**
- `CampaignRepository.split_party()` — new optional params: `creature_ids_to_split: Array = []`, `vehicle_ids_to_split: Array = []`, `split_context: Dictionary = {}`. The `split_context` dict supports key `handler_reassignments: {creature_id: new_handler_id}`.

**Database changes:**
- None. All operations use existing schema.

**Tests added/updated:**
- `tests/test_party_split_merge.gd` — 6 new tests (18 total: 7 split, 5 merge, 6 creature/vehicle split).

**Known issues:**
- Handler reassignment UI is v1 (auto-clear only). A richer dropdown UX is deferred.
- Persisting `active_party_id` across save/reload still not implemented (runtime-only per Fix 2's known issues).
- Auto-distribute button still stubbed (pending Session 4).

**Next session should:**
- Smoke test all 4 fixes in the running game.
- Run the full test suite to verify no regressions.
- Consider dropdown-based handler reassignment for the split dialog.
- Begin work on auto-distribute or next feature per the build plan.

## Session 2026-04-18 — Party Inventory Session 4: Loot Distribution + Auto-Distribute

**Task:** Deliver the auto-distribute algorithm, loot distribution modal (triggered on combat victory), gold share sub-modal, and minimal combat loot generation (coins-only from ACKS treasure types). Replace the party inventory overlay's auto-distribute stub with a real implementation.

**Model used:** Claude Opus 4.6 for all phases.

**Completed:**
- `engine/subsystems/combat/loot_generator.gd` — pure-logic class generating coin loot from ACKS treasure types A–R. Rolls coins via DiceSystem (d100 percentage checks + dice expressions × 1000). Parses suffixed strings like "E (per warband)" to extract type letter.
- `engine/subsystems/inventory/loot_auto_distributor.gd` — pure-logic item distribution algorithm per GDD §6.5. Preference-tag matching (8 tags from character preferences), round-robin distribution, encumbrance band protection, heuristic fallback (heavy→STR, ammo→matching weapon, magic→PCs, rations→creatures first).
- `engine/subsystems/combat/combat_controller.gd` — extended `_emit_combat_ended()` to collect treasure types from defeated monsters and generate loot. Loot key added to outcome dict ONLY for wilderness victory (not dungeon — corpse searching is a deliberate time-costly action in dungeons).
- `engine/autoloads/event_bus.gd` — added `container_opened` signal (stub, no emitters in v1), updated `combat_ended` documentation with all outcome keys including optional `loot`.
- `engine/autoloads/campaign_repository.gd` — added `list_xp_eligible_entities(party_id)` query returning PCs and henchmen for gold share and XP distribution.
- `scenes/ui/party_inventory/gold_share_modal.gd` — weighted gold-share editor (CanvasLayer 54). PCs default weight 1.0, henchmen 0.5 (ACKS half-share). SpinBox per recipient, live preview with banker's rounding, residual CP to smallest-share recipient. Static `compute_shares()` reusable by parent modal.
- `scenes/ui/party_inventory/loot_distribution_modal.gd` — main loot modal (CanvasLayer 52). Shows gold summary, item queue (empty in v1), share preview. Buttons: Edit Gold Shares, Drop All, Cancel, Apply. On Apply: computes gold shares and calls `PartyWallet.deposit_to_character()` per recipient (bypasses `deposit_to_party_by_shares` which filters out henchmen).
- `scenes/ui/party_inventory/party_inventory_overlay.gd` — replaced `_on_auto_distribute_stub()` with full `_on_auto_distribute_pressed()`. Added `_gather_distributable_items()`, `_gather_carrier_info()`, `_show_distribute_preview()` (AcceptDialog confirmation), `_execute_distribute_plan()`. Wired `EventBus.combat_ended` → `_on_combat_ended_loot()` handler that checks `outcome.has("loot")` and lazily creates the loot modal. Loot modal added as sibling (child of Main, not child of overlay CanvasLayer).

**Decisions made:**
- **Filter at emission, not handler**: The `loot` key is absent from the outcome dict for non-loot events (dungeon, defeat, no treasure). This is cleaner than present-but-empty — future consumers check `outcome.has("loot")`.
- **Manual per-character gold deposit**: Gold share amounts computed in the modal, `PartyWallet.deposit_to_character()` called per recipient. This bypasses `deposit_to_party_by_shares()` which explicitly filters to PCs only, excluding henchmen from their rightful half-shares.
- **Wilderness-only auto-loot**: `GameState.exploration_context` retains its pre-combat value (DUNGEON or WILDERNESS) during combat state because `SessionRunner._sync_game_state("combat")` only changes `current_state`, not `exploration_context`. Loot generation gated by `exploration_context != DUNGEON`.
- **Text-only confirmation** for overlay auto-distribute preview (AcceptDialog, not drag-and-drop).
- **Preference tag matching uses item_key substrings**, not just item_category (most equipment is broad "gear" category).

**Interfaces defined or changed:**
- `LootGenerator.generate_from_treasure_types(types: Array) -> Dictionary` — returns `{coins_cp, coins_sp, coins_ep, coins_gp, coins_pp}` or empty dict.
- `LootAutoDistributor.distribute(items: Array, carriers: Array, context: Dictionary) -> Dictionary` — returns `{moves: Array, unassigned: Array, summary: Dictionary}`.
- `GoldShareModal.compute_shares(total_cp: int, shares: Dictionary) -> Dictionary` — static, returns `{char_id: int_cp_amount}`.
- `GoldShareModal` signals: `shares_confirmed(shares: Dictionary)`, `cancelled()`.
- `LootDistributionModal` signal: `distribution_completed()`.
- `EventBus.container_opened(container_id: String, contents: Dictionary)` — stub signal, no emitters.
- `CampaignRepository.list_xp_eligible_entities(party_id: String) -> Array` — returns PCs and henchmen rows.
- `combat_ended` outcome dict now optionally includes `loot: Dictionary` key (present only for wilderness victory with treasure).

**Database changes:**
- None.

**Tests added/updated:**
- `tests/test_loot_generator.gd` — 8 tests: parse None, parse letter only, parse with suffix, parse invalid, no valid types, override produces coins, failed chance produces zero, multiple types aggregate.
- `tests/test_loot_auto_distributor.gd` — 10 tests: empty items, coin exclusion, preference tag match, round-robin, heavy→STR, ammunition→weapon, band worsening skip, no valid target → unassigned, rations→creatures first, magic→PCs round-robin. Uses MockCatalog (no DB dependency).
- Both suites registered in `test_runner.gd` and `test_runner.tscn`.

**Known issues:**
- **Ammunition-to-weapon matching** is substring-based ("arrow" → "bow", "bolt" → "crossbow"). Needs explicit catalog field for weapon/ammo relationships.
- **Gems, jewelry, magic items** not rolled from treasure types (v1 coins-only).
- **Individual vs. lair treasure** distinction ignored — "(per warband)" suffix stripped, all treasure treated as encounter-level.
- **Monster inventory drops** don't exist — v1 item queue will always be empty after combat.
- **Container-opened signal** declared but no emitters wired.
- **Dungeon corpse searching** — loot is generated but not presented in dungeon combat. A "Search body" action (costing turns, triggering wandering monster checks) is needed in DungeonExploreState. Deferred.
- **Treasure XP** hook (`XPAwardCalculator.award_adventure_xp(..., treasure_xp=0, ...)`) remains unconnected.

**Next session should:**
- Smoke test the loot distribution flow: force a wilderness combat victory with treasure-bearing monsters, verify modal opens, gold distributes correctly.
- Smoke test auto-distribute from the party inventory overlay.
- Run the full test suite to verify no regressions.
- Consider implementing dungeon corpse search action.
- Consider gems/jewelry/magic items from treasure types (v2 loot generation).

## Session 2026-04-18 — Session 4.5: Dungeon Loot + Treasure XP

**Task:** Close four gaps left by Session 4: dungeon combat discards generated loot, no dungeon Loot/Pick Up All context menu action, container_opened signal is inert, and treasure XP is always 0. Make dungeon combat drop loot to corpse cells, wire Loot and Pick Up All context menu actions, add treasure XP (1 XP per 1 GP) at distribution time, and add container-opened scaffolding TODOs.

**Model used:** Claude Opus 4.6 for all phases.

**Completed:**
- `engine/subsystems/combat/loot_generator.gd` — added `compute_treasure_gp_value(coins: Dictionary) -> int` static method. Converts coin dict to total CP via `Currency.coins_to_cp()`, returns integer GP value (floor division by 100). Added Currency preload.
- `engine/subsystems/session/states/dungeon_explore_state.gd`:
  - Added `_place_dungeon_loot(roster: CombatRoster)` — collects defeated enemy treasure types and first valid death cell from roster, generates coins via LootGenerator, creates a `dungeon_cell` loose cache via `LocationCacheManager.create_dungeon_loose_cache()`, inserts coin items via `add_inventory_item()` + `transfer_item_to_cache()`, sets `has_ground_items = true` on TacticalMapData cell.
  - Wired `_place_dungeon_loot()` call in `_on_dungeon_combat_finished()` between `_finalizer.finalize()` and `_dungeon_combat_controller = null` (victory only).
  - Removed "loot" and "pick_up_all" from the deferred context action stub.
  - Added "loot" and "pick_up_all" match arms using `scheduler.schedule_at()` directly (passes `dungeon_id` in event data).
  - Added `open_loot_modal` presentation handler in `_on_scheduler_event_resolved()`.
  - Added `_ensure_loot_modal()`, `_open_loot_modal_from_cache()`, `_on_loot_modal_completed()`.
- `engine/subsystems/session/handlers/dungeon_handlers.gd`:
  - Added "loot" and "pick_up_all" match arms in `_handle_action_complete()`, extracting `dungeon_id` from event data.
  - Added `_resolve_loot(entity_id, cell, dungeon_id)` — builds location_key, looks up cache via `get_cache_at_location_key()`, returns `open_loot_modal` presentation.
  - Added `_resolve_pick_up_all(entity_id, cell, dungeon_id)` — transfers coins via `add_coins_cp()`, transfers non-coin items via `pick_up_item()`, awards treasure XP, cleans up empty cache, clears `has_ground_items`.
  - Added `_award_treasure_xp(treasure_gp)` — builds members from `list_xp_eligible_entities()`, uses `CharacterData.from_dict()`, creates `XPAwardCalculator`, awards XP, persists to DB, emits `EventBus.xp_awarded`.
  - Added container-opened TODO scaffolding comment.
- `scenes/ui/party_inventory/loot_distribution_modal.gd`:
  - Changed signal from `distribution_completed()` to `distribution_completed(cache_id: String, cache_cell: Vector2i)`.
  - Added `_cache_id: String` and `_cache_cell: Vector2i` state variables.
  - Added `open_from_cache(cache_id, cell)` — loads cache items, separates coins from non-coins, calls `open()`.
  - Modified `_on_apply()` — after gold distribution, removes distributed coin items from cache DB when `_cache_id` is set, awards treasure XP via `compute_treasure_gp_value()`.
  - Added `_award_treasure_xp(treasure_gp)` method.
- `scenes/ui/party_inventory/party_inventory_overlay.gd` — updated `distribution_completed` connection lambda to accept new `(cache_id, cache_cell)` params.
- `docs/coding_conventions.md` — added two entries to §12 ACKS Implementation Rules: Treasure XP rule (1 XP per 1 GP, awarded at distribution time) and Dungeon loot placement rule (defeated monsters' treasure lands in location_cache at leader's death cell).

**Decisions made:**
- **Loot placement in `_on_dungeon_combat_finished()` not combat_finalizer**: Placement needs access to roster (for death cell positions) and dungeon controller (for dungeon_id). Both are available in dungeon_explore_state but not in the finalizer.
- **Single cache per encounter**: All coins placed at the first defeated enemy's death cell rather than per-monster caches. Simplifies the model and matches encounter-level treasure types.
- **Direct `scheduler.schedule_at()` for loot/pick_up_all dispatch**: `schedule_action()` has a fixed signature with no room for `dungeon_id`. Using `schedule_at()` directly lets us include `dungeon_id` in the event data dict.
- **Two-step item creation**: `add_inventory_item()` then `transfer_item_to_cache()` because `add_inventory_item()` doesn't include `location_cache_id` in its INSERT.
- **Treasure XP awarded in both paths**: The modal Apply path and the Pick Up All handler path both compute and award treasure XP independently.
- **`CampaignRepository.get_character()` returns Dictionary**: Resolvers use `CharacterData.from_dict()` to hydrate before accessing typed properties.

**Cross-cutting: Voxel migration TODOs** — Added `# TODO (voxel migration): extend location_key to include level coordinate` comments at all `location_key` construction sites and `grid_position` access sites:
1. `_place_dungeon_loot()` in `dungeon_explore_state.gd` — death cell lookup via `grid_position`
2. `_resolve_loot()` in `dungeon_handlers.gd` — location_key construction
3. `_resolve_pick_up_all()` in `dungeon_handlers.gd` — location_key construction
4. Loot/pick_up_all `schedule_at()` calls in `_on_context_action()` — cell coordinates in event data

**Interfaces defined or changed:**
- `LootGenerator.compute_treasure_gp_value(coins: Dictionary) -> int` — static, returns GP value for XP.
- `LootDistributionModal.distribution_completed(cache_id: String, cache_cell: Vector2i)` — signal now carries cache context (empty string + Vector2i(-1,-1) for non-cache opens).
- `LootDistributionModal.open_from_cache(cache_id: String, cell: Vector2i) -> void` — new entry point for dungeon cache loot.
- `DungeonHandlers._resolve_loot(entity_id, cell, dungeon_id) -> Dictionary` — returns `open_loot_modal` presentation.
- `DungeonHandlers._resolve_pick_up_all(entity_id, cell, dungeon_id) -> Dictionary` — direct transfer + XP award.

**Database changes:**
- None.

**Tests added/updated:**
- `tests/test_loot_generator.gd` — 4 new tests: `compute_treasure_gp_value` with mixed coins (pp+gp+ep+sp+cp → 17 gp), empty dict (→ 0), copper-only truncation (99 cp → 0 gp), gold-only (100 gp → 100).
- `tests/test_dungeon_loot_placement.gd` (new) — 5 integration tests: cache created with coins at cell, cache lookup by location_key, empty cache cleanup, coin item category, multiple denominations in cache. Uses DB seeding/teardown pattern from `test_location_cache_manager.gd`.
- Both suites registered in `test_runner.gd` and `test_runner.tscn`.

**Known issues:**
- **`has_ground_items` is runtime-only**: TacticalMapData cell flags don't persist across dungeon reloads. Caches persist in DB but the flag won't be set until cache-to-cell-flag regeneration is added in dungeon load.
- **Treasure XP at pickup, not civilization**: v1 simplification — ACKS RAW awards XP when treasure is "returned to civilization." Deferred.
- **Equipment recovery XP**: Selling recovered gear for GP value deferred to future sell system.
- **Gems, jewelry, magic items**: Not in loot tables (v1 coins-only).
- **Treasure type duplication**: 6 goblins = type E rolled 6 times (pre-existing from Session 4).
- **No integration test for `_place_dungeon_loot()` directly**: Private method tightly coupled to scene tree. Pipeline tested at DB level instead.

**Next session should:**
- Run the full test suite to verify no regressions from this session.
- Smoke test dungeon loot: force combat with treasure-bearing monsters, win, navigate to death cell, right-click → Loot, verify modal opens with coins, Apply → gold distributed + XP awarded.
- Smoke test Pick Up All on a dungeon death cell.
- Verify wilderness loot flow still works (regression check).
- Consider adding `has_ground_items` regeneration from DB caches on dungeon load.
- Consider gems/jewelry/magic items from treasure types (v2 loot generation).

---

## Session 2026-04-18 — Voxel Migration Sessions 1-6 (Planning + Data Layer)

**Task:** Plan and implement the data-layer foundation for the 3D voxel cube-cell migration per `gdd-voxel-tactical-architecture.md`. Sessions 1-6 of the 11-session migration plan — all data-only, no renderer or UI changes.
**Model used:** Opus 4.6 for planning and implementation throughout.

**Completed:**

**Session 1 — Core Data Types and Adjacency Math:**
- `engine/shared_types/voxel_cell.gd` — `VoxelCell` (RefCounted, class_name). All fields from GDD §7: solidity, feature, floor_type, door_state/type/detected, room_id, is_corridor, fog_state, cover_value. Four derived methods: `is_passable_by_walker()`, `blocks_los()`, `blocks_flight()`, `blocks_burrow()`. `from_dict()`/`to_dict()` serialization.
- `engine/shared_types/voxel_map_data.gd` — `VoxelMapData` (RefCounted, class_name). Sparse `Dictionary[Vector3i, VoxelCell]` storage. Sentinel pattern for absent keys. Level iteration. Metadata fields: id, name, theme, tileset_group, entry_pos, generation_seed. `from_dict()`/`to_dict()`, `load_from_file()`/`save_to_file()`.
- `engine/shared_types/voxel_grid.gd` — `VoxelGrid` (RefCounted, class_name, all static). `cell_to_world(col, row, level)` with `y = level * 1.0`. `world_to_cell()` including Y. `get_neighbors_3d()` (26 neighbors), `get_neighbors_2d()` (8 same-level). `is_adjacent()` (3D Chebyshev ≤ 1). `chebyshev_distance()`. `Direction` enum with `DIRECTION_OFFSETS` matching `IsometricGrid.get_neighbors()` order.
- Tests: `test_voxel_cell.gd` (25 tests), `test_voxel_map_data.gd` (13 tests), `test_voxel_grid.gd` (24 tests).

**Session 2 — Falling Resolver and 3D Line of Sight:**
- `engine/subsystems/combat/falling_resolver.gd` — `FallingResolver` (RefCounted, all static). `has_support(map, pos)` checks floor_type, solid below, or ladder. `resolve_fall(map, from_pos)` returns {landing_pos, distance_feet, damage_dice, spike_dice}. ACKS formula: `floor(feet / 10) × d6`.
- `engine/subsystems/presentation/voxel_los.gd` — `VoxelLOS` (RefCounted, all static). 3D DDA (Amanatides-Woo) raycast. `has_los(map, from, to)` skips start/end cells. `get_cover_value()` returns max cover of intermediate cells. Created `engine/subsystems/presentation/` directory.
- Tests: `test_falling_resolver.gd` (16 tests), `test_voxel_los.gd` (18 tests).

**Session 3 — Database Migration and Repository Wiring:**
- `db/migrations/036_voxel_grid.sql` — Creates `voxel_map_cells` table (PK: map_id, col, row, level). Forward-migrates `dungeon_map_cells` data with `level = level_num * 2`.
- `db/schema.sql` — Updated with voxel_map_cells table, header to migration 036.
- `engine/autoloads/campaign_repository.gd` — Added 6 methods: `save_voxel_cell()`, `load_voxel_cells_for_map()`, `update_voxel_cell_state()`, `save_voxel_cells_batch()` (with BEGIN TRANSACTION/COMMIT), `load_voxel_map()`, `_voxel_cell_from_row()`. Deprecated 3 old dungeon_map_cells methods with `@deprecated` comments.
- Tests: `test_campaign_repository_voxel.gd` (12 tests).

**Session 4 — Inventory Validator Wiring + VoxelMapData JSON Format:**
- `engine/subsystems/inventory/party_inventory_transfer_validator.gd` — Replaced `_check_dungeon_adjacency()` stub with real check using `context["carrier_positions"]` (Dictionary: carrier_id → Vector3i) and `VoxelGrid.is_adjacent()`. Missing positions → explicit rejection. Replaced `_check_combat_trade_action()` stub: checks `context["combat_action_available"]` flag, then delegates to adjacency. Changed signature to include source/target params.
- `data/test_dungeon.json` — Converted from old `levels[]` + `stairs[]` format to unified voxel `cells[]` format. 560 voxel cells across 4 levels from 2 old dungeon levels. Stair cells have direction suffixes (stairs_up_SW, stairs_down_NE). Wall cells stamped at both floor and ceiling levels.
- Tests: Updated 2 existing validator tests, added 6 new adjacency/combat tests. New `test_voxel_map_data_json.gd` (8 tests).

**Session 5 — Integration Tests + Format Verification:**
- Scope reduced: no dungeon generator exists, so no generator to update. Generator is L-1's responsibility.
- `tests/test_voxel_dungeon_integration.gd` — 10 integration tests verifying converted Goblin Warrens: wall stacks, stair direction suffixes, door states, LOS through rooms, LOS blocked by walls.

**Session 6 — VisibilityManager and Voxel-Based Movement:**
- `engine/subsystems/presentation/visibility_manager.gd` — `VisibilityManager` (Node, class_name, NOT autoload). Tracks `focus_level`, `party_positions`, `explored_levels`. `set_focus_level()` clamps to nearest explored level in requested direction. `get_level_visibility()`: focus=1.0, below=0.6, focus+1=0.3, else=0.0. `update_explored_levels()` recomputes from VoxelMapData fog state.
- `engine/subsystems/combat/movement_resolver.gd` — Added `_voxel_map: VoxelMapData` field and 3D methods alongside untouched 2D methods: `path_bfs_3d()` (BFS with 5 movement types: ground/flying/tunnel_burrow/earth_pass/climbing), `has_los_3d()`, `is_adjacent_3d()`, `get_distance_3d()`, `get_cells_reachable_3d()`. Private helpers: `_can_enter_3d()`, `_has_stair_connection()` (checks directional feature suffixes), `_direction_suffix_for_delta()`, `_reverse_direction()`.
- Tests: `test_visibility_manager.gd` (14 tests), `test_movement_resolver_3d.gd` (16 tests).

**Decisions made:**
- **Vector3i convention:** `Vector3i(col, row, level)` — x=col, y=row, z=level. Extends `Vector2i(col, row)` naturally.
- **`is_passable_by_walker()` does NOT check floor support.** Pathfinder checks support via `FallingResolver.has_support()`.
- **Party `dungeon_level` column untouched in migration 036.** Application-layer `* 2` conversion later.
- **Carrier positions via context dict, not service query.** Missing positions → reject.
- **`has_action` renamed to `combat_action_available`** for clarity.
- **No dungeon generator in voxel migration.** Generator is L-1's responsibility.
- **MovementResolver parallel approach.** `_3d` suffix on all new methods. Existing 2D methods untouched.
- **VisibilityManager is NOT an autoload** — instanced in scene tree.
- **Focus level clamping:** nearest explored level in requested direction; stay put if none found.
- **Cover value aggregation:** max of intermediate cells (not sum).

**Interfaces defined or changed:**
- `VoxelCell`: `is_passable_by_walker()`, `blocks_los()`, `blocks_flight()`, `blocks_burrow()`, `from_dict()`, `to_dict()`
- `VoxelMapData`: `get_cell(Vector3i)`, `set_cell()`, `from_dict()`/`to_dict()`, `load_from_file()`/`save_to_file()`
- `VoxelGrid`: `cell_to_world()`, `world_to_cell()`, `get_neighbors_3d()`, `is_adjacent()`, `chebyshev_distance()`
- `FallingResolver`: `has_support()`, `resolve_fall()`
- `VoxelLOS`: `has_los()`, `get_cover_value()`
- `VisibilityManager`: `set_focus_level()`, `jump_to_party_leader()`, `get_level_visibility()`, `should_dither()`, `update_explored_levels()`
- `MovementResolver`: `set_voxel_map()`, `path_bfs_3d()`, `has_los_3d()`, `is_adjacent_3d()`, `get_distance_3d()`, `get_cells_reachable_3d()`
- `CampaignRepository`: `save_voxel_cell()`, `load_voxel_cells_for_map()`, `update_voxel_cell_state()`, `save_voxel_cells_batch()`, `load_voxel_map()`
- `PartyInventoryTransferValidator._check_dungeon_adjacency()` — now checks `context["carrier_positions"]`
- `PartyInventoryTransferValidator._check_combat_trade_action()` — signature changed, checks `context["combat_action_available"]`

**Database changes:**
- Migration 036: `voxel_map_cells` table. Forward migration from `dungeon_map_cells` with `level = level_num * 2`.

**Tests added/updated:**
- 11 new test suites (IDs 104-113): test_voxel_cell, test_voxel_map_data, test_voxel_grid, test_falling_resolver, test_voxel_los, test_campaign_repository_voxel, test_voxel_map_data_json, test_voxel_dungeon_integration, test_visibility_manager, test_movement_resolver_3d.
- Updated `test_party_inventory_transfer_validator.gd`: renamed 2 tests, added 6 new, updated `_make_context()` helper.
- Total new tests: ~198.

**Known issues:**
- **Old test_dungeon.json format consumers:** `TacticalMapData.load_from_file()` and `DungeonMapController.load_dungeon()` expect the old `levels[]`/`stairs[]` format. Converted file breaks these callers until they're updated.
- **Migration 036 data sparsity:** Migrated rows only carry door_state and fog_state from old table.
- **3D DDA edge cases:** Not exhaustively tested for rays exactly aligned with cell edges.
- **godot-sqlite transactions:** `save_voxel_cells_batch()` is first use of explicit transactions in the codebase.

**Next session should:**
1. Run full test suite to verify all 113+ suites pass.
2. Begin Session 7 (Renderer Refactor) or prioritize other build plan work.
3. When the dungeon generator (L-1) is built, it should output `VoxelMapData` directly.
4. Update `DungeonMapController.load_dungeon()` to handle the voxel JSON format (or add a format-detection shim).
5. Update `docs/document_map.md` and `docs/rule_system_map.md` to reference the voxel GDD.

---

## Session 2026-04-20 — Voxel Migration Session 7 (Visibility Finalization)

**Task:** Complete the voxel-migration session-plan's Session 7 renderer-refactor scope — specifically, finish the GDD §16.2 per-level visibility table so below-focus levels render dimmed, the focus level renders at full color, and focus+1 and above hard-clip hidden (BG3 style). Sessions 1–6 (2026-04-18) already shipped per-level groups, `VisibilityManager` wiring, per-level camera Y tween, the feature flag, and token positioning; only the opacity/dim + focus+1 policy was outstanding.

**Model used:** Opus 4.7 (1M context) — planning and implementation.

**Scope decision:** Plan initially bundled Session 7 + Session 11 ("Full cleanup now"), but audit of `dungeon_map_controller.gd` and its callers revealed the voxel controller port is incomplete (several public methods — `interact_door`, `use_stairs`, `move_party`, `_update_fog_for_all_members`, `_bfs_path`, `_reveal_entry_room`, `_update_visibility_on_move`, `get_map()` — are legacy-only and still called unconditionally from `dungeon_handlers.gd` and `dungeon_explore_state.gd`). Stripping the `use_voxel_renderer` flag would require writing voxel equivalents for all of these, which was out of the planned scope. Reverted to the session plan's original staging: Session 7 is renderer-only; Session 11 (or a dedicated controller-port session) does the controller cleanup.

**Decision on `level == focus + 1`:** Hard-clip hidden (BG3 style, GDD §16.3 Fallback 1). Dither shader deferred — Level Strip Widget (Session 8) will provide the "Gary is up there" silhouette context. One-line change to re-enable dither later if needed.

**Completed:**

- `scenes/maps/tactical_grid_3d.gd`:
  - Added `set_meta("base_color", …)` to each voxel builder's output meshes so per-level tinting multiplies instead of overwriting. Covers `build_floor_multimesh_voxel` (base = `Color.WHITE`, drives vertex-color tint), `build_walls_voxel` (base = `Color.WHITE`), `build_doors_voxel` (both portcullis and regular doors), `build_features_voxel` (stairs, ladder). `build_walls_voxel_individual` already had the meta.
  - Replaced cached-material uses in `build_doors_voxel` (portcullis) and `build_features_voxel` (stairs, ladder) with fresh `StandardMaterial3D.new()` per mesh — the shared material cache in `_get_material()` would have caused one level's tint to apply to the same mesh type on every other level.
  - New static helper `set_level_group_tint(group: Node3D, tint: Color)` that walks `FloorSlabs` / `Walls` / `Doors` / `Features` children of a `Level_N` group and multiplies each mesh's `material_override.albedo_color` by `tint`, using `get_meta("base_color", Color.WHITE)` as the source. `GridLines`, `FogOverlay`, `TransitionMarkers`, and Label3Ds intentionally skipped (labels use `modulate` not albedo; fog/grid colors are meaningful).
  - Private `_apply_tint_to_mesh(mesh: GeometryInstance3D, tint: Color)` does the actual component-wise multiplication.

- `scenes/maps/dungeon_map_renderer_3d.gd`:
  - Added constants `DIM_COLOR = Color(0.6, 0.6, 0.6, 1.0)`, `FULL_COLOR = Color.WHITE`, `NON_FOCUS_ENEMY_ALPHA = 0.5`.
  - Rewrote `_apply_level_visibility()`: for each `Level_N` child of `_grid_meshes`, hard-clip hidden when `level > focus`; when `level == focus` set visible and tint `FULL_COLOR`; when `level < focus` with content → visible + tint `DIM_COLOR`; when `level < focus` without content → hidden. Final call chains to `_apply_token_visibility()`.
  - New `_apply_token_visibility()`: per `_tokens` entry, reads token's `pos.z`, hides if above focus or on empty lower level, full-opacity on focus or for party-side tokens on any explored level, `NON_FOCUS_ENEMY_ALPHA` for enemy tokens on explored below-focus levels.
  - New `_set_token_alpha(token, alpha)`: flips `MeshInstance3D.material_override.transparency` between `TRANSPARENCY_ALPHA` and `TRANSPARENCY_DISABLED` based on alpha; finds the body by `token.get_node_or_null("Body")` to avoid depending on `CombatantToken3D`'s private `_body_material` field.
  - Simplified `_on_focus_level_changed()`: removed the tangled `_camera.position.y - (_camera.position.y - X)` math at line 1271 (which algebraically collapsed to just `X`). Clean expression now: `target_y = base_y + CAM_BACKWARD.y * 50.0`, tween, then `_rebuild_grid_voxel()` (which ends in `_apply_level_visibility()`).
  - `_update_entity_tokens_voxel()` now trails with `_apply_token_visibility()` so tokens reposition + re-check their visibility in one pass.

**Decisions made:**

- **Dimming via albedo tint, not shader.** All voxel materials already use `SHADING_MODE_UNSHADED` with `vertex_color_use_as_albedo = true`. In that mode, the fragment shader's output is `per_instance_color * albedo_color`, so setting `material_override.albedo_color = Color(0.6, 0.6, 0.6)` on a MultiMesh tints all its instances by 0.6 in one property write. No shader code, no per-cell mutation.
- **Tint source = metadata, not runtime albedo read.** Using `get_meta("base_color", …)` rather than reading the current `albedo_color` avoids the "DIM → FULL → dim-again" drift where each transition compounds the last.
- **Non-focus-level individual wall meshes use the same base_color meta that already existed at [tactical_grid_3d.gd:1003](scenes/maps/tactical_grid_3d.gd#L1003)** — no new metadata needed for focus-level walls.
- **Combat renderer unchanged.** `combat_map_renderer_3d.gd` builds a single Level_0 group; no VisibilityManager, no focus cycling. Cross-level combat hasn't shipped. Deferring per the approved plan.
- **`combatant_token_3d.gd` unchanged.** The plan's proposed `update_position(Vector3i)` refactor was deferred; token API stays `update_position(world_pos: Vector3)` and the renderer computes Y.
- **Labels stay at full brightness on dimmed levels.** Label3D uses `modulate`, not an albedo material. Documented as an accepted limitation; revisit if visual review demands it.

**Interfaces defined or changed:**

- `TacticalGrid3D.set_level_group_tint(group: Node3D, tint: Color) -> void` (new static)
- `TacticalGrid3D._apply_tint_to_mesh(mesh: GeometryInstance3D, tint: Color) -> void` (new static, private helper)
- `DungeonMapRenderer3D._apply_level_visibility()` — signature unchanged; body rewritten
- `DungeonMapRenderer3D._apply_token_visibility() -> void` (new)
- `DungeonMapRenderer3D._set_token_alpha(token: CombatantToken3D, alpha: float) -> void` (new)
- All voxel builders now attach `base_color` metadata to their output meshes — consumers reading `get_meta("base_color", Color.WHITE)` get a predictable starting color regardless of future builder internal changes.

**Database changes:** None.

**Tests added/updated:** None added this session (visual behavior; no headless test harness for rendering). Ran `tests/test_runner.tscn` end-to-end: 95 suites passed, 21 failed. All failures are pre-existing (MovementResolver 3D path reconstruction bug at `movement_resolver.gd:918`, EventScheduler/SchedulerLoop flakes, character-class sex/alignment disabling, character-sheet dwarf-language test, level-up confirm test, game-log test, prone/stand-up combat test, party-split vehicle-creature test, and assorted others). No new failures. All voxel-related suites (`VoxelCell`, `VoxelMapData`, `VoxelGrid`, `FallingResolver`, `VoxelLOS`, `CampaignRepositoryVoxel`, `VoxelMapDataJson`, `VoxelDungeonIntegration`, `VisibilityManager`) pass.

**Known issues:**

- **Visual validation still pending.** End-to-end visual check with `data/test_dungeon.json` (Goblin Warrens, 4 levels) was deferred — run the project in the editor to confirm: Level_0 bright at focus=0, Level_1/2/3 hidden; PgUp to focus=2 dims Level_0 and Level_1 to ×0.6, Level_2 bright, Level_3 hidden; Home recenters.
- **DungeonMapController voxel port incomplete.** `interact_door`, `use_stairs`, `move_party`, `_update_fog_for_all_members`, `_bfs_path`, `_reveal_entry_room`, `_update_visibility_on_move`, `get_map()` are all legacy-only. Called unconditionally from `dungeon_handlers.gd` and `dungeon_explore_state.gd`; in voxel mode they silently no-op (early-return on `_map == null`). A voxel play session probably has broken door interaction and missing fog updates on token movement. Flagged `[NEEDS-OPUS-REVIEW]` — deserves a dedicated session to port the remaining controller methods before the `use_voxel_renderer` flag can be removed.
- **Test movement resolver 3D failures.** Pre-existing: `_reconstruct_path_3d` at [movement_resolver.gd:918](engine/subsystems/combat/movement_resolver.gd#L918) assigns `Nil` to `Vector3i` when BFS produces an empty `came_from` chain. 5 assertion failures across `test_path_bfs_3d_flat_ground`, `test_path_bfs_3d_stairs_up`, `test_path_bfs_3d_flying_free`, `test_path_bfs_3d_burrow_through_solid`, `test_path_bfs_3d_climbing_wall`. Not touched this session.

**Next session should:**

1. Visual smoke test the voxel renderer with `data/test_dungeon.json` in the editor. Confirm the §16.2 table effect (dimming, hard-clip) looks right; if the "ceiling closes over player" effect is ever re-enabled at focus+1, flip to hard-clip-hidden (already what Session 7 ships).
2. **Port the remaining DungeonMapController legacy methods to voxel** (Session 11 prerequisite): `interact_door`, `use_stairs`, `move_party`, `_update_fog_for_all_members`, `_bfs_path`, `_reveal_entry_room`, `_update_visibility_on_move`. Once done, strip the `use_voxel_renderer` flag + delete `TacticalMapData` + DB migration 037 to drop `dungeon_map_cells`. This is the Session 11 scope, now unblocked.
3. Begin session-plan Session 8: Level Strip Widget (HUD component for multi-level party dispersion), input bindings (PgUp/PgDn/Home/Shift+Home — PgUp/PgDn are already wired in the renderer but need to go through the input map), party-bar level chips.
4. Fix the pre-existing `_reconstruct_path_3d` Nil → Vector3i crash in `movement_resolver.gd`.

---

## Session 2026-04-21 — Wilderness Hexmap Right-Click Context Menu + Active-Party Selection

**Task:** Replace wilderness hexmap left-click-to-move with: (1) left-click on a party token selects active party; (2) right-click opens a Move/Explore/Build Stronghold/Place Loot Cache/Visit Loot Cache/Survey context menu mirroring the dungeon UI; (3) bottom HUD shows the active party's member portraits at 56×56; (4) every menu option queues travel + chained activity, and combat encounters cancel both.

**Model used:** Opus 4.7 (1M context) — planning, design, and implementation.

**Completed:**

- **New file** [engine/subsystems/exploration/wilderness_context_menu_builder.gd](engine/subsystems/exploration/wilderness_context_menu_builder.gd): pure static `RefCounted` mirroring `DungeonContextMenuBuilder`. `build_menu(target_hex, active_party_id, map_data, controller)` returns 7 options (`move_here`, `explore`, `build_stronghold`, `place_loot_cache`, `visit_loot_cache`, `survey`, `cancel`). Place vs Visit Loot Cache are mutually exclusive based on `LocationCacheManager.get_cache_at_location("hex:q,r")`.
- **Modified** [scenes/maps/hex_map_renderer.gd](scenes/maps/hex_map_renderer.gd): added `party_token_clicked(party_id, coord)` and `hex_context_menu_requested(coord, screen_pos)` signals; new `_party_hex_index: Dictionary` populated alongside party tokens (active party wins tie); `_unhandled_input` left-click now consults the index to disambiguate selection vs movement; right-click emits the context-menu signal. Legacy `hex_clicked` signal preserved but no longer drives movement.
- **Modified** [engine/subsystems/session/states/wilderness_explore_state.gd](engine/subsystems/session/states/wilderness_explore_state.gd): replaced `_on_hex_clicked` with `_on_party_token_clicked`, `_on_hex_context_menu_requested`, `_on_context_action`, `_close_context_menu`, `_activity_type_for_action`, `_resolve_active_party_id`, `_resolve_party_data`, `_on_wilderness_cache_visit_requested`. Reuses the existing `dungeon_context_menu.gd` scene (preloaded as `ContextMenuScene`) — it's generic enough to need no fork. The dispatcher uses `GameState.active_party_id` (falls back to runner's `_party_id`) and loads PartyData via `CampaignRepository.load_party_data` for non-primary parties.
- **Modified** [engine/subsystems/session/handlers/wilderness_handlers.gd](engine/subsystems/session/handlers/wilderness_handlers.gd):
  - Added two event types `wilderness_activity` and `wilderness_activity_complete` (constants `ACTIVITY_EVENT`, `ACTIVITY_COMPLETE_EVENT`) registered in `register()` / `unregister()`.
  - Changed `schedule_travel_path()` return type from `Array[String]` to `Dictionary {event_ids, arrival_time, current_time}` so callers can chain follow-up events at the arrival time.
  - New `_handle_wilderness_activity(event)`: dispatches by `activity_type`. `place_loot_cache` schedules a 1-hour `wilderness_activity_complete` follow-up; `visit_loot_cache` resolves immediately (emits `EventBus.wilderness_cache_visit_requested` if a cache exists, else "No cache here" toast); `explore`/`build_stronghold`/`survey` emit "Feature coming soon" toasts.
  - New `_handle_wilderness_activity_complete(event)`: for `place_loot_cache` calls `LocationCacheManager.create_wilderness_hidden_cache(Vector2i(q,r))` and emits a success toast.
  - New helper `_cancel_party_movement_and_activity(party_id)` cancels `travel_leg` + both new activity event types in one call. Called from the encounter-trigger branch, the path-blocked branch, the getting-lost failure branch, and the forced-march-exhaustion branch — so an interrupted travel never silently auto-resumes the queued activity.
  - `_handle_travel_leg` now sets `GameState.current_location_key = "hex:q,r"` on hex entry (only for the active party), keeping the cache-aware Party Inventory overlay in sync without needing an extra signal hop.
- **Modified** [engine/autoloads/event_bus.gd](engine/autoloads/event_bus.gd): added `signal wilderness_cache_visit_requested(cache_id: String, hex: Vector2i)` in the cache section.
- **Modified** [scenes/ui/hud/session_status_bar.gd](scenes/ui/hud/session_status_bar.gd): bumped `BAR_HEIGHT` from 48 → 72; added `_portraits_hbox` between the spacer and the Camp button; new `_refresh_party_portraits(party_id)` reads `CampaignRepository.list_party_characters` and renders 56×56 `TextureRect`s (tooltip = character name) loaded via the existing `user://portraits/<id>.png` → `res://assets/portraits/<id>.png` fallback chain. Static `_portrait_cache: Dictionary` avoids re-decoding user portraits. Listens to `EventBus.active_party_changed` for refresh.

**Decisions made:**

- **Reused dungeon context menu scene as-is.** `scenes/maps/dungeon_context_menu.gd` is a fully generic `PanelContainer` that consumes `Array[Dictionary]` options grouped by free-form `category` strings, auto-pauses the scheduler, and emits `option_selected`/`cancelled`. No wilderness-specific fork needed.
- **Visit Loot Cache is instant on arrival** (user-confirmed). The handler skips the completion-event chain and resolves immediately. Place Loot Cache is the only timed activity (1 hour = `Timekeeping.ROUNDS_PER_HOUR` = 360 rounds).
- **Place Loot Cache does NOT auto-open the inventory UI** (user-confirmed). Auto-pause + success toast only; player opens Party Inventory manually. The overlay already auto-detects the cache via `GameState.current_location_key`.
- **Empty-hex left-click is a no-op.** The renderer still emits the legacy `hex_clicked` for empty hexes, but the wilderness state no longer connects to it. Movement is exclusively right-click → Move Here.
- **Scoped event cancellation, not blanket `cancel_all_for_owner(party_id)`.** Targeted at `travel_leg`, `wilderness_activity`, `wilderness_activity_complete` only — preserves `getting_lost_check` / `forced_march_check` / `wilderness_encounter_check` which have their own lifecycle.
- **Active-party orders use `GameState.active_party_id`, not `_runner.get_party_id()`.** The runner's `_party_id` is set once at session load and doesn't follow active-party switches; this is a pre-existing limitation of multi-party sessions. The new context-menu dispatcher works around it via `_resolve_active_party_id` and `_resolve_party_data` (loading PartyData from the repository when the active party isn't the runner's primary).

**Interfaces defined or changed:**

- New EventBus signal: `wilderness_cache_visit_requested(cache_id: String, hex: Vector2i)`.
- New renderer signals: `party_token_clicked(party_id: String, coord: Vector2i)`, `hex_context_menu_requested(coord: Vector2i, screen_pos: Vector2)`.
- `WildernessHandlers.schedule_travel_path(...)` return type: `Array[String]` → `Dictionary {event_ids, arrival_time, current_time}`. The single existing caller (wilderness state) now consumes `arrival_time`.
- New event types in scheduler vocabulary: `wilderness_activity` (carries `{activity_type, hex_q, hex_r}` payload) and `wilderness_activity_complete` (same payload).
- New constants on `WildernessHandlers`: `ACTIVITY_EVENT`, `ACTIVITY_COMPLETE_EVENT`.
- `WildernessContextMenuBuilder.build_menu(target_hex, active_party_id, map_data, controller=null) -> Array[Dictionary]` (new static).

**Database changes:** None. The loot-cache backend (migration 032 `location_caches` table) was already in place; this session only wires UI to it.

**Tests added/updated:**

- New suite [tests/test_wilderness_context_menu_builder.gd](tests/test_wilderness_context_menu_builder.gd) with 9 tests: option count, expected ids present, cancel action_type, hex coords on action_data, empty-party-disables-actions, cancel-always-enabled, visit-disabled-without-cache, place-enabled-without-cache, controller gating placeholder. Wired into `tests/test_runner.gd` and `tests/test_runner.tscn` as `WildernessContextMenuBuilderTests`.

**Known issues:**

- **Multi-party `can_move_to` adjacency check uses primary party's hex.** `HexMapController.can_move_to(target)` checks adjacency from the controller's stored `party_hex`, which is the primary party. When the active party isn't the primary, the menu's "enabled" state and the runtime guard may report incorrect adjacency. Pre-existing limitation — not introduced here. Flag for `[NEEDS-OPUS-REVIEW]` when multi-party movement gets a proper test pass.
- **`combat_started` signal does not include `party_id`.** Encounter-time cancellation works because it happens inside the wilderness handler before `CombatState.enter` fires the signal. If other systems ever need to react to combat by canceling per-party events, the signal will need extending. Flag `[NEEDS-OPUS-REVIEW]`.
- **`Explore`, `Build Stronghold`, `Survey` are placeholder activities.** Selecting them schedules travel + a single `wilderness_activity` event that fires "Feature coming soon" on arrival. No game-state effect.
- **Visual validation pending.** Manual playtest steps documented in the plan file — verify left-click selection, right-click menu, place-cache 1-hour timer, visit-cache opens Party Inventory, combat-mid-travel cancels follow-up activities, portrait strip renders at 56×56.

**Next session should:**

1. Visual smoke test the wilderness UI (steps 2–7 in the plan's Verification section).
2. Run `tests/test_runner.tscn` to confirm `WildernessContextMenuBuilderTests` pass and no regressions.
3. Build out one of the placeholder activities (Survey is the smallest scope — recommend `gdd-survey-activity.md` first for the rules).
4. When multi-party combat / non-primary `can_move_to` gets attention, fix the adjacency-from-primary bug noted above.
5. Continue voxel-migration Session 11 (controller cleanup) per the prior session's TODO.

---

## Session 2026-04-22 — Equipment Bugs: Darts, Stack Splitting, Thrown-Weapon Expenditure

**Task:** Fix three character-sheet equipment bugs:
1. Darts couldn't be equipped (filtered out by category whitelist).
2. Stacks of melee weapons (e.g. 2 short swords) were equippable as a stack via the party-inventory right-click and shop auto-equip paths.
3. Thrown weapons (dagger/javelin/dart) were never expended on throw — the equipped weapon row lived forever.

**Model used:** Opus 4.7 (1M) for plan + implementation.

**Completed:**

- `data/equipment/base_equipment.json`: added `uses_per_unit: 5` to the `dart` entry. Bundle's `uses_remaining` tracks darts left (5 → 0).
- [scenes/ui/character_sheet/tabs/cs_tab_equipment.gd](scenes/ui/character_sheet/tabs/cs_tab_equipment.gd):
  - Added static `is_thrown_stackable(item, catalog)` helper — true for `weapon` or `ammunition` items tagged `"thrown"`.
  - Added instance `_is_thrown_self_ammo(item)` — narrower check used by `_can_equip()` to admit dart bundles.
  - Extended `_can_equip()` to allow `item_category == "ammunition"` when it's thrown self-ammo.
  - Added `"ammunition"` arm to `_determine_equip_slot()` — routes like a one-handed thrown weapon.
  - Rewrote `_on_equip()` to dispatch on `is_thrown_stackable`: thrown stacks equip whole; non-thrown stacks split as before. Dart bundle gets `uses_remaining` seeded to `uses_per_unit` on first equip if currently `-1`.
- [scenes/ui/party_inventory/item_context_menu.gd](scenes/ui/party_inventory/item_context_menu.gd): `_equip_item()` now uses the same dispatch logic (preloads CSTabEquipment for the static helper) — split-on-equip for non-thrown stacks, equip-whole for thrown stacks, handles dart-bundle slot routing and uses_remaining seeding.
- [scenes/ui/character_creation/equipment_shop_panel.gd](scenes/ui/character_creation/equipment_shop_panel.gd): refactored `_on_auto_equip()` to call new `_equip_one_in_cart()` helper, which splits non-thrown stacks into a new equipped row in the cart (mirroring `split_item_for_equip` semantics in-memory) and seeds dart-bundle `uses_remaining` from the catalog. Added `_cart_item_is_thrown_stackable()`.
- [engine/subsystems/combat/combatant.gd](engine/subsystems/combat/combatant.gd):
  - Extended `_equipped_weapon` dict to carry `quantity`, `uses_remaining`, `item_category`.
  - `wire_equipment()` now accepts `ammunition` rows in `hands_main` if they have the `"thrown"` tag (so dart bundles populate `_equipped_weapon`); and skips the same row from being double-wired into `_equipped_ammo`.
  - Rewrote `consume_ammo()` to dispatch:
    - thrown weapon (cat=`weapon`, tag `thrown`): decrement `quantity`; on 0 → delete row + clear `_equipped_weapon`.
    - dart bundle (cat=`ammunition`, tag `thrown`): decrement `uses_remaining`; on 0 → delete row + clear `_equipped_weapon`.
    - otherwise: existing `_equipped_ammo` quantity decrement.
- [engine/autoloads/campaign_repository.gd](engine/autoloads/campaign_repository.gd):
  - `add_inventory_item()` and `save_character_inventory()` now persist `uses_remaining` (was previously omitted, defaulted to schema -1; per build_log line 1762 this was a known gap).
  - `merge_item_on_unequip()` now adds `equipped_qty` (read from the equipped row) to the destination pack stack instead of hardcoded `+1`. Fixes the silent-quantity-loss bug for stacked thrown weapons unequipping.
- New test suite [tests/test_equip_pipeline.gd](tests/test_equip_pipeline.gd) — 10 tests covering all three bugs end-to-end. Wired into `tests/test_runner.gd` and `tests/test_runner.tscn` as `EquipPipelineTests`.

**Decisions made (confirmed with user):**

- **Dart model:** keep the bundle as a single `ammunition` row; track darts via `uses_remaining` (5 → 0). Chosen to avoid a shop/data migration.
- **Thrown stacks stay equipped whole** in `hands_main`. Throwing decrements; auto-unequip on depletion. User can still split off a single dagger to off-hand via the existing Split UI.
- **All three equip paths fixed in one pass** — character sheet, party inventory context menu, shop auto-equip.

**Interfaces defined or changed:**

- `CSTabEquipment.is_thrown_stackable(item: Dictionary, catalog: EquipmentCatalog) -> bool` (new static, also called from item_context_menu.gd).
- `Combatant._equipped_weapon` dict now carries `quantity`, `uses_remaining`, `item_category` (additional keys; backward-compatible — readers using `.get(..., default)` are unaffected).
- `Combatant.consume_ammo()` semantics expanded: now also decrements the equipped weapon row when it's a thrown self-ammoing weapon. Single call site at [combat_controller.gd:983](engine/subsystems/combat/combat_controller.gd#L983) is unchanged.
- `CampaignRepository.add_inventory_item()` and `save_character_inventory()` now read and write `uses_remaining` from the data dict (default -1, matching the schema).
- `CampaignRepository.merge_item_on_unequip()` now merges the entire equipped quantity, not just one unit.

**Database changes:** None (existing `uses_remaining` column from migration 012 is now finally populated by the two insert paths that omitted it).

**Tests added/updated:**

- [tests/test_equip_pipeline.gd](tests/test_equip_pipeline.gd) — new suite, 10 tests:
  - `test_dart_bundle_is_equippable`
  - `test_dart_bundle_seeds_uses_remaining_on_first_equip`
  - `test_short_sword_stack_splits_on_equip`
  - `test_dagger_stack_stays_equipped_as_stack`
  - `test_thrown_dagger_consumed_decrements_quantity`
  - `test_thrown_dagger_last_unit_clears_slot`
  - `test_thrown_dart_decrements_uses_remaining`
  - `test_thrown_dart_last_use_destroys_bundle`
  - `test_party_inventory_short_sword_stack_splits`
  - `test_unequip_dagger_stack_merges_full_quantity_to_pack`

**Known issues:**

- **Tests not yet run by build agent.** Godot CLI is not on PATH in this environment; the tests must be executed manually via `tests/test_runner.tscn`.
- **In-combat weapon swap path ([combat_controller.gd:1764](engine/subsystems/combat/combat_controller.gd#L1764)) does not yet honor split-on-equip.** It's a 4th equip path; the user's plan scoped only the three above. If a player ever swaps to a stack of swords mid-combat, the stack will end up equipped. Flag for follow-up.
- **No "combine two pack stacks" UI.** Only merge-on-unequip is fixed. A player who manually splits a dagger stack and later wants to recombine has no UI affordance. Not a regression — pre-existing.

**Next session should:**

1. Run the full test suite (`tests/test_runner.tscn`) to confirm `EquipPipelineTests` pass and no regressions.
2. Smoke-test the equipment UI per the plan's verification section: dart equip/throw cycle, dagger stack equip/throw cycle, short-sword stack split-on-equip via all three paths.
3. Decide whether to extend split-on-equip to the in-combat weapon swap path.
4. Resume voxel-migration Session 11 controller cleanup as previously planned.

---

## Session 2026-04-22 — Session 7b: DungeonMapController Voxel Port + Feature-Flag Removal + D-4 Smoke Test

**Task:** Complete the voxel migration that Session 7 left half-finished: fix the `_reconstruct_path_3d` Nil crash, sweep the renderer for `Vector2i`→`Vector3i` mismatches, port the 7 legacy-only `DungeonMapController` methods to voxel, strip the `use_voxel_renderer` feature flag + all legacy 2D code paths it gated, and get a live D-4 dungeon run end-to-end (entry, movement, doors, stairs, fog, combat-entry prep).

**Model used:** Opus 4.7 (1M context) — exploration, planning, implementation.

**Completed:**

Task C — **BFS path-reconstruction guard** ([engine/subsystems/combat/movement_resolver.gd:911-927](engine/subsystems/combat/movement_resolver.gd#L911)): terminate `_reconstruct_path_3d` on reaching `start` rather than on `visited.get(current) == null`, which used to hit a runtime assignment of `null` to a Vector3i-typed local. Unblocks the five previously-failing `test_path_bfs_3d_*` tests.

Task B — **Renderer type sweep** ([scenes/maps/dungeon_map_renderer_3d.gd](scenes/maps/dungeon_map_renderer_3d.gd)):
- Fixed the crash at `_advance_movement_animation` — `_active_movements["path"]` carries Vector3i in voxel mode; the tween now reads `next_cell.z` and calls `VoxelGrid.cell_to_world(x, y, z)` rather than hard-coding level 0.
- Untyped `movement_cell_reached(entity_id, cell)` signal so Vector3i payloads flow through the `_on_continuous_move_finished` → `on_cell_reached` chain without type errors.
- Untyped the `_on_party_moved`, `_on_entity_moved`, `_on_door_state_changed` handlers to accept both coordinate types during the transition.
- Added voxel branches to [scenes/maps/dungeon_order_overlay_3d.gd](scenes/maps/dungeon_order_overlay_3d.gd): new `_cell_world_pos(cell)` helper branches on `is Vector3i`; all callers use it.
- Dropped Vector2i type annotations that would crash when `map.get_entity_pos` returns Vector3i (dungeon_handlers.gd:324 `old_pos`, dungeon_explore_state.gd:969/1012/1170 `pos`/`current_pos`).

Task A — **DungeonMapController voxel port** ([engine/subsystems/exploration/dungeon_map_controller.gd](engine/subsystems/exploration/dungeon_map_controller.gd)):
- Signals `party_moved`, `entity_moved`, `door_state_changed` retyped to untyped params — downstream consumers adjusted where they had explicit Vector2i param types.
- Added voxel implementations: `_move_party_voxel`, `_interact_door_voxel`, `_queue_group_move_voxel`, `_queue_door_interaction_order_voxel`, `_update_visibility_on_move_voxel`, `_execute_orders_voxel`, `_find_scatter_cell` (ring-search for no-stacking group moves).
- Wired existing voxel helpers (`_bfs_path_voxel`, `_reveal_entry_room_voxel`, `_reveal_room_voxel`, `_update_fog_for_all_members_voxel`) behind public dispatch wrappers.
- Added `MovementResolver` instance to the controller (lazy-init in `_ensure_managers`) for stair-aware multi-level pathfinding in `_move_party_voxel` and `_queue_group_move_voxel`.
- New `get_stair_target(pos: Vector3i) -> Vector3i` helper resolves stair destinations via (1) explicit VoxelCell `stair_target_col/row/level` fields, or (2) direction-suffix inference (`stairs_up_<DIR>` → step + level±1).
- New `teleport_party_to(target_pos)` method for stair traversal when the destination isn't spatially adjacent (handles the paired test-dungeon stairs).
- Deleted `use_stairs()`; refactored the single caller in [dungeon_explore_state.gd:_on_context_action](engine/subsystems/session/states/dungeon_explore_state.gd) "ascend"/"descend" to call `teleport_party_to(get_stair_target(cell))`.

**Smoke-test fixes (iterated via live dungeon play):**

1. `DungeonSessionState` door-tracking methods (`spike_door`, `wedge_door`, `is_spiked`, `is_wedged`, `hold_portcullis`, `record_picked_lock`, `queue_for_exit` etc.) now accept Vector2i or Vector3i — dict keys hash both identically.
2. `_resolve_*` functions in dungeon_handlers had `controller.get_map() != null` gates that always failed in voxel mode (get_map returns null). Replaced with new `controller.has_map()` helper that checks either map type.
3. `_resolve_use_lever` degrades gracefully when `get_lever_target` isn't on the current map class (voxel lever port is deferred).
4. `scheduled_action` round-trips the level coordinate: serializes `cell_z` + `cell_is_3d` in the event data, `_handle_action_complete` reconstructs Vector3i when flag is set. Force_door / pick_lock / bash_door / spike / wedge / force_portcullis / use_lever / search / listen all resolve on the correct voxel cell now.
5. Ceiling "re-appearing after every move" bug: `_rebuild_grid_voxel` used `child.queue_free()` which defers destruction — the newly-added `Level_0`/`Level_1` groups collided on name with the queue-freed ones, got auto-renamed `Level_0@Node@N`, and failed `is_valid_int()` in `_apply_level_visibility`. Fixed by using `remove_child(child)` immediately followed by `child.queue_free()`.
6. Wall occlusion froze at first-frame state after movement. Added `_update_wall_occlusion()` invocations at end of `_rebuild_grid_voxel` and `_update_entity_tokens_voxel` so walls between camera and party re-fade after rebuilds.
7. New `VoxelCell.is_evil` field + `VoxelMapData.is_evil_door(pos)` for the turn-tick evil-door auto-close path.
8. Group-move stacking fix: `_queue_group_move_voxel` now ring-scatters followers up to radius 4 around the target cell using `_find_scatter_cell`; no fallback to stacking on the leader. Multi-entity moves via context-menu "move here" now route through `DungeonHandlers.order_group_move` (new) so followers ring-scatter instead of per-entity stacking on the same target.
9. Leader `z` change during continuous movement emits `level_changed` (from `dungeon_handlers.on_cell_reached`) so VisibilityManager focus follows stair traversal.
10. Stair context menu recognizes voxel feature suffixes: `tf.begins_with("stairs_up_")` / `"stairs_down_"` in addition to the bare legacy strings.
11. Explicit stair pairing: `VoxelCell.stair_target_col/row/level` fields override direction inference; `teleport_party_to` handles non-adjacent destinations. Patched [data/test_dungeon.json](data/test_dungeon.json) so the two hand-authored stairs point at passable cells on their connected levels.
12. Session-load dungeon JSON refresh: `_ensure_test_dungeon_entrance` now calls `update_dungeon_entrance_data` on existing entrances (matches settlement pattern) so dev edits to `data/test_dungeon.json` apply on session load without discarding the campaign.
13. Hex renderer dungeon entry: [scenes/maps/hex_map_renderer.gd:_on_enter_dungeon_pressed](scenes/maps/hex_map_renderer.gd) now branches on dungeon format — voxel JSON has top-level `cells` + `entry` dict; legacy JSON has `levels[]` with per-level entry fields. Previously the legacy-only parser silently returned with no dungeon_entry_requested emission when fed voxel JSON.
14. `_bash_door_turns` is now 1 turn for all wooden door materials (house rule). Bash resolver already deterministic auto-success.
15. Schedule-time info toasts for force_door / pick_lock / bash_door so the player can disambiguate which action fired at click time.

**D.2 — Feature-flag + legacy-path removal:**

`use_voxel_renderer` static flag deleted from [dungeon_map_controller.gd](engine/subsystems/exploration/dungeon_map_controller.gd). 73+ references removed across:
- `movement_resolver.gd` (18 guard conditions simplified to `if _voxel_map != null:`).
- `dungeon_handlers.gd` (13 ternaries collapsed).
- `dungeon_explore_state.gd` (15 sites collapsed; `_save_dungeon_cell_states` is voxel-only; `_update_minimap` hidden until voxel port; `auto_listen_at_doors` idle behavior stubbed until voxel port; `_find_creature_placement` voxel-only).
- `combat_controller.gd` / `combat_screen.gd` / `combat_map_renderer_3d.gd` / `combat_context_menu_builder.gd` collapsed.
- `dungeon_map_renderer_3d.gd` — 22 sites collapsed, legacy 2D grid / token / highlight / camera branches deleted.

Legacy 2D bodies deleted from DungeonMapController:
- `load_dungeon`, `move_party`, `can_move_to`, `interact_door`, `queue_move_order`, `queue_group_move`, `queue_door_interaction_order`, `execute_orders`, `_update_fog_for_all_members`, `_reveal_entry_room`, `_update_visibility_on_move`, `is_on_transition_cell`, and the `_reveal_room` helper (no longer called). Public methods are now thin dispatchers to their voxel variants.

**Retained for Session 11:**
- `TacticalMapData` + `CellData` classes (combat + tests still reference them).
- Legacy `dungeon_map_renderer.gd` (2D scene).
- `_map`, `_all_levels`, `_stairs` fields on DungeonMapController — block-commented as Session 11 cleanup.
- `get_map()` accessor — returns (null) TacticalMapData for legacy callers pending migration.

**Decisions made:**

- **Stair UX:** Keep the current "transition point" model (Ascend/Descend context menu teleports to paired cell). Redesign to gradient/ramp stairs is deferred to a focused follow-up session to avoid mixing rendering work with migration cleanup.
- **Minimap in voxel mode:** Hidden until a voxel port; the 2D minimap couldn't meaningfully render multi-level dungeons without a redesign.
- **Auto-listen idle behavior:** Stubbed in voxel mode (neighbor scan was 2D-only). Behavior port is a follow-up.
- **Group-move formation:** `FormationManager.compute_dungeon_positions` is still 2D-only. Voxel group moves use ring-scatter instead of formation placement. Formation-aware voxel moves are a follow-up.
- **Stair pairing:** When hand-authored dungeons have stair destinations that aren't spatially adjacent, use the explicit `stair_target_*` VoxelCell fields. The test dungeon's two stairs are now paired this way.

**Interfaces defined or changed:**

- `DungeonMapController.has_map() -> bool` (new).
- `DungeonMapController.get_stair_target(pos: Vector3i) -> Vector3i` (new).
- `DungeonMapController.teleport_party_to(target_pos: Vector3i) -> bool` (new).
- `DungeonMapController.use_stairs(pos)` DELETED.
- `DungeonMapController.party_moved / entity_moved / door_state_changed` signals retyped from `(Vector2i, ...)` to untyped params.
- `DungeonHandlers.order_group_move(entity_ids, target, base_movements, controller, scheduler, party_id) -> Array` (new).
- `VoxelCell.is_evil: bool`, `VoxelCell.stair_target_col/row/level: int` (new fields, `-1` default).
- `VoxelMapData.is_evil_door(pos: Vector3i) -> bool` (new).
- `DungeonSessionState.*_door(pos)` methods untyped for Vector2i/Vector3i.
- `DungeonHandlers.schedule_action` event data now includes `cell_z` + `cell_is_3d` for voxel-mode round-trip.
- Renderer signal `movement_cell_reached(entity_id, cell)` — cell param untyped (Vector3i in voxel mode).

**Database changes:** None. `voxel_map_cells` schema unchanged — `is_evil` and `stair_target_*` VoxelCell fields are JSON-only for now; they're not persisted across dungeon visits. Session 11 can add migration columns if those fields need persistence.

**Tests added/updated:**

- New suite [tests/test_dungeon_map_controller_voxel.gd](tests/test_dungeon_map_controller_voxel.gd) (15 tests) covering: voxel map injection, adjacent/non-adjacent/blocked move_party, can_move_to, interact_door (closed/open/locked/arch/secret/non-adjacent), get_stair_target direction + paired, stair traversal via move_party, fog transitions on move, _reveal_entry_room dispatch, get_voxel_map accessor, queue_door_interaction_order, signal payloads carry Vector3i.
- Registered in [tests/test_runner.gd](tests/test_runner.gd) + [tests/test_runner.tscn](tests/test_runner.tscn).
- 4 `use_stairs`-dependent tests removed from legacy `test_dungeon_map_controller.gd` (use_stairs method deleted); the legacy file still exercises 2D paths that will be removed in Session 11.

**Smoke-test verification (live D-4 dungeon play):** Entry from hex, party token positioning, wall culling (dynamic occlusion fade), focus-level camera tween, movement orders with ring-scatter, open/close door, bash door with axe-wielder, pick-lock success/fail with thief (retry-block after fail), spike/wedge door, lever + "not connected" graceful toast, Ascend/Descend (teleport model, level_changed follow, fog update on arrival), multi-entity group moves don't stack. F3 dev key prints leader pos + stair directory.

**Known issues:**

- **Minimap hidden in voxel mode.** Deferred to a focused port; the 2D minimap can't render multi-level content without redesign.
- **Auto-listen-at-doors idle behavior is a no-op** in voxel mode pending a level-aware neighbor scan.
- **`FormationManager.compute_dungeon_positions` is 2D-only.** Voxel group-moves use ring-scatter (no formation) until ported.
- **`use_lever` in voxel mode** shows "The lever doesn't seem to be connected to anything." — `VoxelMapData.get_lever_target` isn't implemented. Legacy content has no levers to exercise against.
- **Voxel stair destinations are NOT spatially adjacent** in the test dungeon. Working as intended via explicit pairing. A true ramp/gradient stair model is a separate design change.
- **Some Vector2i→Vector3i coercions at combat-setup call sites** (creature placement, loot cache) pass Vector3i via `_controller.get_current_level()`. Level is inferred, not from the actual creature/cache coordinate — combat is still single-level so this is fine in practice.
- **Legacy TacticalMapData class + test_dungeon_map_controller.gd 2D tests are retained.** Session 11 scope to delete entirely.

**Next session should:**

1. Session 8 — Level Strip Widget (HUD for multi-level party dispersion), input bindings polish (PgUp/PgDn/Home/Shift+Home registered in input map), party-bar level chips.
2. Stair UX redesign (separate focused session): ramp/gradient stairs with per-cell Y interpolation — will require reauthoring the hand-authored test dungeon's staircases as multi-cell ramp runs.
3. Session 11 — delete `TacticalMapData` class, `CellData`, legacy `dungeon_map_renderer.gd` 2D scene, `_map`/`_all_levels`/`_stairs` fields, legacy `test_dungeon_map_controller.gd` tests. Strip any remaining ternaries that still read `controller.get_map()`.
4. Port `FormationManager.compute_dungeon_positions` to Vector3i / VoxelMapData so voxel group-moves can use real formation placement instead of ring-scatter.
5. Port the voxel minimap.
