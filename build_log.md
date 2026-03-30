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
