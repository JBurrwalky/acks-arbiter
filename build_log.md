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

**Completed:** Completed the Planning Phase. The plan was as follows:
 Summary

  docs/document_map.md — A tabular index of all 63 XML rule files and 11 GDDs. Organized by source book (acore_, pc_,
  daw_, le_, ax_), with each file getting a one-line content summary and key topic keywords. Purpose: fast lookup when
  the agent needs to find which files to load for a task.

  docs/rule_system_map.md — An inverse index organized by game system (Combat, Characters, Domains, etc.), listing which
   XML files and GDDs each system needs, plus explicit "depends on" / "depended on by" relationships. Includes a
  high-traffic file cross-reference for blast radius awareness. Purpose: impact analysis and dependency tracking when
  implementing or modifying a subsystem.

  Key design decisions in the plan:

  - Table format for document_map (compact, scannable)
  - Bullet-list format for rule_system_map (structured but not prose-heavy)
  - 15 game systems identified as the taxonomy for rule_system_map
  - Only existing files indexed (the design brief references some GDDs that don't exist yet like gdd-name-generation.md
  — these would be noted separately)
  - High-traffic files section at the end of rule_system_map flags XML files used by 3+ systems (changing these has wide
   blast radius)

  The full plan with proposed structures is in the plan file. One note: I'll verify every file description by reading
  the actual XML/GDD headers during implementation, not just relying on the explorer's summaries.

● User approved Claude's plan
  ⎿  Plan saved to: ~\.claude\plans\peaceful-growing-crystal.md · /plan to edit
     Plan: Create document_map.md and rule_system_map.md

     Context

     These two files are referenced in CLAUDE.md as part of the Build Session Protocol (step 4) — they are read at the
     start of every build session. Their purpose is to let the build agent quickly identify which XML rule summaries and
      GDDs are relevant to the current task (step 5: "Load only those files. Never load the entire rules corpus."). They
      need to be well-crafted because they'll guide every future implementation session.

     The project currently has:
     - 63 XML rule files in rules/ (sacred, from ACKS rulebooks)
     - 11 GDD files in generation/ (project-designed, modifiable)
     - 1 design brief in docs/ (architectural)

     ---
     File 1: docs/document_map.md — File Index

     Purpose: Quick-reference index so the build agent knows what every file contains and can select the right ones for
     any task.

     Design principles:
     - Table format for fast scanning (one row per file)
     - Organized by source book (matching file prefixes: acore_, pc_, daw_, le_, ax_)
     - Each file gets: filename, one-line content summary, key topics/keywords for search
     - GDDs in a separate section with status and dependency callouts
     - Must fit in a single read without scrolling forever — concise descriptions only

     Proposed structure:

     # Document Map

     Quick-reference index of all rule summaries and design documents.
     Read this every session to identify which files to load for your current task.

     ## Source Precedence (highest first)
     Axioms (ax_) > HFH excerpted > Player's Companion (pc_) > Lairs & Encounters (le_) > Domains at War (daw_) > ACKS
     Core (acore_)

     ## Rules — ACKS Core (acore_*)
     [TABLE: File | Contents | Key Topics]
     26 rows covering: basics/characters, classes (core, demihuman, campaign), equipment,
     proficiencies, spellcaster rules, spell catalogs (A-I, K-W), combat, adventures/encounters,
     treasure/magic items, optional rules, strongholds/domains, setting construction,
     monster stocking, campaign play, hijinks, monster catalogs (7 alphabetical splits + dragons)

     ## Rules — Player's Companion (pc_*)
     [TABLE: File | Contents | Key Topics]
     9 rows covering: classes (4 files), equipment, proficiencies, followers,
     aging, custom spells, magic experimentation, spell catalogs (A-E, F-U)

     ## Rules — Domains at War (daw_*)
     [TABLE: File | Contents | Key Topics]
     7 rows covering: recruitment, campaigning, troop tables, equipment/construction,
     sieges, vagaries, pitched battle

     ## Rules — Lairs & Encounters (le_*)
     [TABLE: File | Contents | Key Topics]
     8 rows covering: monster characteristics, creation, parts, training,
     wilderness lairs, monster catalogs (7 files + dragons)

     ## Rules — Axioms Magazine (ax_*)
     [TABLE: File | Contents | Key Topics]
     10 rows covering: campaign play, codex/scroll magic, conditions, domain encounters,
     domains of chaos, henchman recruitment, mortal wounds, non-combatants,
     reactions/influencing, thief skills, venturer class

     ## Generation Design Documents (gdd-*)
     [TABLE: File | Contents | Status | Key Dependencies]
     11 rows covering all GDDs, each with its XML file dependencies listed

     ## Architecture Documents (docs/)
     Brief listing of design brief, this file, rule_system_map.md, coding_conventions.md

     ---
     File 2: docs/rule_system_map.md — System Dependencies

     Purpose: When working on a specific game system, tells the agent exactly which files provide the rules, which GDDs
     handle generation, and which other systems are connected. Prevents missing dependencies and enables impact
     analysis.

     Design principles:
     - Organized by game system (not by file) — this is the inverse of document_map
     - Each system section lists: rule files needed, GDDs involved, depends-on, depended-on-by
     - Includes a cross-reference matrix showing which systems share files
     - Compact format — bullet lists, not prose

     Proposed structure:

     # Rule System Map

     Maps game systems to their source files and cross-dependencies.
     Read this every session to understand which systems are affected by your current task.

     ## How to Use
     When working on system X:
     1. Load the XML files listed under that system
     2. Check "Depends on" for upstream systems that may constrain your work
     3. Check "Depended on by" for downstream systems you might break
     4. Load relevant GDDs if doing generation work

     ## Systems

     ### Character Creation & Classes
     - **Rule files:** acore_basics_and_characters, acore_core_classes, acore_demihuman_classes,
       acore_campaign_classes, pc_classes_1-4, ax_venturer_class
     - **GDDs:** gdd-henchman-class-selection (for henchman 0th→1st level)
     - **Depends on:** Proficiencies, Equipment
     - **Depended on by:** Combat, Magic, Domain Play, NPC Systems

     ### Combat & Conditions
     - **Rule files:** acore_combat_and_wounds, ax_conditions_catalog, ax_mortal_wounds_and_tampering
     - **GDDs:** gdd_combat_behavior_tags
     - **Depends on:** Characters, Equipment, Spells, Monsters
     - **Depended on by:** All exploration contexts (wilderness, dungeon, urban, sea)

     ### Spells & Magic
     - **Rule files:** acore_spellcaster_rules, acore_spell_catalog_a-i, acore_spell_catalog_k-w,
       pc_spell_catalog_a-e, pc_spell_catalog_f-u, pc_custom_spell_creation_rules,
       pc_magic_experimentation, ax_codex_and_scroll_magic
     - **Depends on:** Characters (caster classes)
     - **Depended on by:** Combat, Magic Research (campaign play)

     ### Equipment & Encumbrance
     - **Rule files:** acore_equipment, pc_equipment_catalog
     - **Depends on:** (none — foundational)
     - **Depended on by:** Characters, Combat, Exploration

     ### Proficiencies
     - **Rule files:** acore_proficiencies_rules_and_catalog, pc_proficiencies_catalog
     - **Depends on:** Characters (class proficiency lists)
     - **Depended on by:** Characters, Combat, Hijinks, NPC Systems

     ### Monsters & Encounters
     - **Rule files:** acore_monster_catalog_* (7 files), acore_monster_catalog_dragons,
       le_monster_catalog_* (7 files), le_monster_catalog_dragons,
       le_monster_characteristics_stats, le_monster_creation, le_monster_parts,
       le_monster_training_rules, acore_adventures_and_encounters,
       acore-monster-stocking-rules
     - **GDDs:** gdd-terrain-system (encounter table selection)
     - **Depends on:** Combat (monster stat blocks reference combat rules)
     - **Depended on by:** All exploration contexts, Dungeon Stocking, Setting Generation

     ### Wilderness & Hex Exploration
     - **Rule files:** acore_adventures_and_encounters, acore-monster-stocking-rules
     - **GDDs:** gdd-terrain-system, gdd-setting-generation
     - **Depends on:** Monsters & Encounters, Equipment (encumbrance → movement)
     - **Depended on by:** Domain Play (territory classification)

     ### Urban & Settlement
     - **Rule files:** acore-setting-construction-rules, acore-campaign-hijinks
     - **GDDs:** gdd-settlement-layout, gdd-settlement-stocking, gdd-npc-personality
     - **Depends on:** Equipment (market class), Characters (hiring)
     - **Depended on by:** Domain Play (urban population)

     ### Dungeon Exploration
     - **Rule files:** acore_adventures_and_encounters, acore-setting-construction-rules
     - **GDDs:** gdd-dungeon-layout, gdd-dungeon-factions, gdd-trap-generation
     - **Depends on:** Monsters & Encounters, Combat, Equipment (light sources, tools)
     - **Depended on by:** Treasure (dungeon stocking populates treasure)

     ### Domain Play (Strongholds, Realms, Population)
     - **Rule files:** acore_axioms_strongholds_and_domains, daw_equipment_and_construction,
       ax_domain_level_encounters, ax_domains_of_chaos
     - **GDDs:** gdd-stronghold-construction, gdd-setting-generation (demographics)
     - **Depends on:** Characters (domain owner), Wilderness (territory class), Urban (settlement)
     - **Depended on by:** Armies & Warfare

     ### Armies & Warfare
     - **Rule files:** daw_armies_recruitment, daw_campaigning_armies, daw_campaigns_troop_tables_summary,
       daw_equipment_and_construction, daw_sieges, daw_vagaries, daw_axioms_pitching_battle
     - **Depends on:** Domain Play (garrison, population), Characters (commander), Equipment (military)
     - **Depended on by:** (end-system — feeds narrative events back to domains)

     ### Treasure & Magic Items
     - **Rule files:** acore_treasure_and_magic_items_rules
     - **Depends on:** Monsters & Encounters (treasure types by monster)
     - **Depended on by:** Equipment (found items), Characters (XP from treasure)

     ### NPC Systems (Personality, Henchmen, Reactions)
     - **Rule files:** acore_equipment (hirelings/henchmen), pc_followers_tables_rules,
       ax_henchmen_recruitment_expanded, ax_reactions_and_influencing, ax_non_combatants
     - **GDDs:** gdd-npc-personality, gdd-henchman-class-selection
     - **Depends on:** Characters (CHA modifier, class), Equipment (wages)
     - **Depended on by:** Party management, Domain Play (NPC rulers)

     ### Campaign Play (Aging, Poisons, Research, Timekeeping)
     - **Rule files:** acore_aging_poisons_high-level-start_optional_rules, pc_aging_tables,
       acore-campaign-general-and-magic-research, ax_campaign_play
     - **Depends on:** Characters, Spells & Magic
     - **Depended on by:** Domain Play (monthly cycle), Session Runner (timekeeping)

     ### Setting & World Generation
     - **Rule files:** acore-setting-construction-rules, acore-monster-stocking-rules,
       acore_axioms_strongholds_and_domains (demographics)
     - **GDDs:** gdd-setting-generation, gdd-terrain-system
     - **Depends on:** Monsters & Encounters, Domain Play (demographics)
     - **Depended on by:** All exploration contexts, Settlements, Dungeons

     ### Thief Skills & Hijinks
     - **Rule files:** acore-campaign-hijinks, ax_thief_skill_update
     - **Depends on:** Characters (thief class), Proficiencies, Urban context
     - **Depended on by:** (end-system)

     ## File → System Cross-Reference (Selected High-Traffic Files)

     Files that appear in 3+ systems — changing these has wide blast radius:
     - `acore_basics_and_characters.xml` → Characters, Combat, all derived systems
     - `acore_combat_and_wounds.xml` → Combat, all exploration contexts, Monsters
     - `acore_adventures_and_encounters.xml` → Wilderness, Dungeon, Monsters, Encounters
     - `acore-setting-construction-rules.xml` → Settings, Settlements, Dungeons, Domains
     - `acore_equipment.xml` → Equipment, Characters, NPC hiring, Encumbrance
     - `acore_axioms_strongholds_and_domains.xml` → Domains, Setting Generation, Armies

     ---
     Verification

     After creating both files:
     1. Confirm every XML file in rules/ appears in document_map.md (count = 63)
     2. Confirm every GDD in generation/ appears in document_map.md (count = 11)
     3. Confirm every XML file appears in at least one system in rule_system_map.md
     4. Confirm no circular "depends on" chains (there shouldn't be — these are rule dependencies, not code
     dependencies)
     5. Cross-check GDD dependency lists against the GDD files themselves (each GDD names its own dependencies)

     ---
     Implementation Steps

     1. Read every XML file's first 10-20 lines to verify content descriptions are accurate
     2. Read every GDD file's header/dependency section to verify dependency lists
     3. Write docs/document_map.md with accurate per-file descriptions
     4. Write docs/rule_system_map.md with verified system-to-file mappings
     5. Run verification checks above
     6. Commit both files
**Known issues:** Claude servers hit major outages mid-task. Creation of the files never took place.

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
5. Build the dice subsystem: DiceSystem class, roll(sides, count, modifier), integration with GameState.dice_overrides.
6. Build the session runner state machine (campaign select to exploration loop).
