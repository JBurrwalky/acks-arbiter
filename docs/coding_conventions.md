# Coding Conventions

Living reference for producing consistent GDScript, SQLite, and architecture patterns across all ACKS Arbiter sessions. Updated as patterns emerge during development — see `[PROVISIONAL]` tags for unconfirmed conventions.

This document **expands** on the naming table and architecture patterns in `CLAUDE.md`. Read both; do not treat this as a replacement.

---

## 1. Naming Conventions

### 1.1 Classes and Scene Names — PascalCase

Every GDScript class and `.tscn` scene uses PascalCase. Acronyms are capitalized only at the start.

```gdscript
# GOOD
class CombatManager
class HexMapRenderer
class LlmResponseValidator    # "LLM" lowered after first letter — reads as a word
class NpcPersonalityGenerator
class XpCalculator             # "XP" → "Xp" in PascalCase

# BAD
class combat_manager           # snake_case is for files, not classes
class LLMResponseValidator     # all-caps acronym mid-name hurts readability
class Hex_Map_Renderer         # mixed convention
```

### 1.2 GDScript Files — snake_case

One class per file. Filename matches the class name converted to snake_case.

```
# GOOD
combat_manager.gd          → class CombatManager
hex_map_renderer.gd        → class HexMapRenderer
llm_response_validator.gd  → class LlmResponseValidator

# BAD
CombatManager.gd           # PascalCase filenames
combat-manager.gd          # kebab-case
utils.gd                   # vague; what utilities?
helpers.gd                 # same problem
```

**Exception:** Test files use the `test_` prefix: `test_combat_manager.gd`.

### 1.3 Signals — Past-Tense Verbs, snake_case

Signals describe something that **already happened**. Never use imperative or present tense.

```gdscript
# GOOD
signal combat_started(encounter_id: int)
signal character_leveled_up(character_id: int, new_level: int)
signal domain_revenue_collected(domain_id: int, revenue: int)
signal turn_undead_attempted(cleric_id: int, result: String)

# BAD
signal start_combat()              # imperative — this is a method name, not a signal
signal on_combat_start()           # "on_" prefix is a listener convention, not an event name
signal combatStarted()             # camelCase
signal character_level_up()        # present tense — did it happen or is it a request?
```

**Signals that carry data:** Include typed parameters. Name parameters for what they contain, not what the listener should do with them.

```gdscript
# GOOD — signal tells you what happened and gives you the relevant data
signal spell_cast(caster_id: int, spell_name: String, targets: Array[int])

# BAD — parameter names describe listener behavior
signal spell_cast(update_ui: bool, play_animation: bool)
```

### 1.4 Database Tables — Plural snake_case

Tables are always plural nouns. Foreign key columns use `singular_id` format.

```sql
-- GOOD
CREATE TABLE characters (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE character_proficiencies (
    character_id INTEGER REFERENCES characters(id),
    proficiency_id INTEGER REFERENCES proficiencies(id)
);
CREATE TABLE domain_events (
    domain_id INTEGER REFERENCES domains(id),
    event_type TEXT NOT NULL
);

-- BAD
CREATE TABLE character (...);           -- singular
CREATE TABLE CharacterProficiency (...); -- PascalCase
CREATE TABLE char_profs (...);          -- abbreviated
```

**Column conventions:**
- Primary key: always `id INTEGER PRIMARY KEY`
- Foreign keys: `referenced_table_singular_id` (e.g., `character_id`, `domain_id`)
- Booleans: `is_` prefix (e.g., `is_active`, `is_dead`)
- Timestamps: `_at` suffix (e.g., `created_at`, `resolved_at`)
- Enums stored as TEXT, not integers — readability over micro-optimization

### 1.5 Constants — SCREAMING_SNAKE_CASE

```gdscript
# GOOD
const MAX_PARTY_SIZE := 8
const COMBAT_ROUND_SECONDS := 10
const XP_THRESHOLD_0TH_LEVEL := 500
const TERRITORY_CIVILIZED := "civilized"
const TERRITORY_BORDERLANDS := "borderlands"
const TERRITORY_WILDERNESS := "wilderness"

# BAD
const maxPartySize := 8        # camelCase
const Max_Party_Size := 8      # Mixed case
const MAXPARTYSIZE := 8        # No underscores
```

### 1.6 Autoload Singletons — PascalCase

Six autoloads exist (see Section 5). Reference them by their PascalCase name directly.

```gdscript
# GOOD
GameState.dice_mode
EventBus.dice_rolled.emit(result.to_dict())
CampaignRepository.get_character(char_id)
DiceSystem.roll_digital(20, 1, 2, "attack_throw")
LLMManager.request_narration(context)
AudioRouter.play_sfx("sword_clash")

# BAD
game_state.dice_mode   # autoloads are PascalCase
dice_system.roll(...)  # same
```

### 1.7 Action Vocabulary — snake_case Verbs

```gdscript
# GOOD
"attack_melee"
"move_to_hex"
"cast_spell"
"search_room"
"pick_lock"
"turn_undead"         # per ACKS 1e — never "rebuke_undead"

# BAD
"MeleeAttack"         # PascalCase
"ATTACK_MELEE"        # screaming — these are identifiers, not constants
"attack"              # too vague — melee or ranged?
```

### 1.8 Resource Files — Descriptive snake_case IDs

```
# GOOD
terrain_forest_icon.tres
token_pc_fighter.tres
ui_theme_main.tres

# BAD
forest.tres           # not descriptive enough
PCFighterToken.tres   # PascalCase for resources
```

### 1.9 Enums — PascalCase Type, SCREAMING_SNAKE_CASE Values

```gdscript
# GOOD
enum Territory { CIVILIZED, BORDERLANDS, WILDERNESS }
enum CombatProgression { FIGHTER, CLERIC, THIEF, MAGE }
enum CharacterTier { FULL, NAMED, TRANSIENT }

# BAD
enum territory { civilized, borderlands, wilderness }  # lowercase type
enum TERRITORY { Civilized, Borderlands, Wilderness }   # screaming type, mixed values
```

---

## 2. File Organization

### 2.1 Engine Directory Structure

<!-- Updated 2026-03-27 to reflect actual project state -->

```
acks-arbiter/               (Godot project root = repo root)
├── project.godot           # Autoload registrations, input map
├── engine/
│   ├── autoloads/          # Six global singletons (see §5.1)
│   │   ├── game_state.gd
│   │   ├── event_bus.gd
│   │   ├── campaign_repository.gd
│   │   ├── llm_manager.gd
│   │   ├── audio_router.gd
│   │   └── dice_system.gd
│   ├── shared_types/       # Cross-subsystem data shapes (class_name, RefCounted)
│   │   ├── action_payload.gd
│   │   ├── character_data.gd
│   │   ├── encounter_data.gd
│   │   ├── event_payload.gd
│   │   ├── hex_map_data.gd
│   │   ├── hex_terrain_data.gd
│   │   ├── inventory_item.gd
│   │   ├── response_envelope.gd
│   │   └── roll_result.gd
│   └── subsystems/
│       ├── exploration/    # HexMapController
│       ├── override/       # OverrideManager (dev-mode state manipulation)
│       ├── combat/         # (planned)
│       ├── character/      # (planned)
│       ├── domain/         # (planned)
│       └── magic/          # (planned)
├── scenes/
│   ├── Main.tscn           # Root scene (instantiates all children)
│   ├── main_scene.gd       # Test harness wiring
│   ├── maps/               # hex_map.tscn, hex_map_renderer.gd
│   └── ui/
│       ├── override/       # override_panel.gd / .tscn
│       └── dice/           # dice_prompt.gd / .tscn
├── tests/                  # All test scripts + test_runner.tscn
├── db/
│   ├── schema.sql          # Canonical schema (update after every migration)
│   └── migrations/         # 001_initial_schema, 002_override_log, 003_dice_roll_log
├── data/                   # Runtime JSON (test_hex_map.json)
├── rules/                  # SACRED XML rule summaries — never modify
├── generation/             # GDD markdown files — modifiable
└── docs/                   # Architecture docs, this file, maps
```

### 2.2 Where New Files Go

| Creating... | Goes in... |
|-------------|-----------|
| New subsystem logic | `engine/subsystems/<subsystem>/` |
| Data shape used by 2+ subsystems | `engine/shared_types/` |
| Data shape used by 1 subsystem only | Same directory as that subsystem |
| New autoload | **Stop.** Do you really need one? See Section 5. |
| Scene file (.tscn) | `scenes/<category>/` |
| UI controller script | `ui/` or co-located with its scene |
| Test file | `tests/` with `test_` prefix |
| SQL migration | `db/migrations/` |
| Runtime data (JSON) | `data/` |
| LLM context snippets | `llm_context/` |

### 2.3 One Class Per File

**Rule:** One public class per `.gd` file. Inner classes are acceptable for tightly coupled helpers that have no use outside the parent.

```gdscript
# GOOD — inner class that only this file uses
class_name CombatResolver

class _DamageRoll:
    var base: int
    var modifier: int
    var total: int

func resolve_attack(attacker_id: int, target_id: int) -> _DamageRoll:
    # ...
```

```gdscript
# BAD — CombatResolver and InitiativeTracker in the same file
# Split into combat_resolver.gd and initiative_tracker.gd
```

---

## 3. GDScript Style

### 3.1 Indentation and Formatting

- **Indentation:** Tabs (Godot default). Do not convert to spaces.
- **Line length:** Soft limit 100 characters. Break long lines at logical points.
- **Trailing whitespace:** None.
- **Blank lines:** One between methods. Two before `# ---` section dividers within a file.

### 3.2 Type Hints — Use Them

Type hints on all function parameters, return types, and exported variables. Local variables: use type hints when the type isn't obvious from the right-hand side.

```gdscript
# GOOD
func calculate_xp(base_xp: int, modifier: float) -> int:
    var adjusted := roundi(base_xp * modifier)  # type obvious from roundi()
    return adjusted

func get_character(character_id: int) -> CharacterData:
    var result: CharacterData = CampaignRepository.load_character(character_id)
    return result

@export var max_hp: int = 0
@export var character_name: String = ""

# BAD
func calculate_xp(base_xp, modifier):  # no type hints
    var adjusted = base_xp * modifier   # ambiguous type
    return adjusted
```

### 3.3 Banker's Rounding — Everywhere

All rounding in the entire project uses round-half-to-even. Godot's built-in `roundf()` uses this by default, but be explicit when it matters.

```gdscript
# GOOD — use snapped() or explicit banker's rounding
func bankers_round(value: float) -> int:
    # Godot's roundf() already does banker's rounding
    return roundi(value)

# GOOD — document why when the rounding matters mechanically
var hp_bonus := roundi(con_modifier * 0.5)  # banker's rounding per project convention

# BAD
var hp_bonus := int(con_modifier * 0.5)     # truncation, not rounding
var hp_bonus := ceili(con_modifier * 0.5)   # ceiling, not banker's
```

### 3.4 Comments

Comments explain **why**, not **what**. Do not add comments to self-evident code. Do not add docstrings to trivial getters/setters.

```gdscript
# GOOD — explains a non-obvious rule
# ACKS: Fighters get cleave attacks equal to their level (ACore combat rules)
var cleave_attacks := character.level

# GOOD — explains a constraint
# Territory must be one of the three ACKS classifications — no "Outlands" or "Unsettled"
assert(territory in [Territory.CIVILIZED, Territory.BORDERLANDS, Territory.WILDERNESS])

# BAD — restates the code
# Set the level to 1
var level := 1

# BAD — stale comment
# Calculate damage with strength bonus
var damage := roll_dice(weapon.damage_dice)  # strength bonus removed in refactor
```

### 3.5 Method Ordering Within a File

<!-- Confirmed by hex_map_controller.gd, hex_map_renderer.gd, and campaign_repository.gd — 2026-03-25 -->

```
1. class_name / extends
2. Constants (const)
3. Enums (enum)
4. Signals (signal)
5. @export variables
6. @onready variables
7. Public variables
8. Private variables (prefixed _)
9. _ready(), _process(), _input() (lifecycle methods)
10. Public methods
11. Private methods (prefixed _)
12. Inner classes
```

### 3.6 Private Members — Underscore Prefix

```gdscript
# GOOD
var _internal_state: int = 0

func _calculate_modifier(score: int) -> int:
    return roundi((score - 10) / 2.0)

# BAD — no underscore on private members
var internal_state: int = 0  # is this part of the public API?
```

### 3.7 `class_name` Rules

<!-- Confirmed 2026-03-27 across all engine files -->

| Script type | Use `class_name`? | Why |
|---|---|---|
| Autoload scripts | **Never** | Godot error: "hides an autoload singleton" |
| Shared types (`engine/shared_types/`) | **Always** | Enables typed references (`var r: RollResult`) |
| Subsystem manager nodes | **Yes** | Lets parent scenes reference them by type |
| UI scene scripts (CanvasLayer, Node2D) | **No** | Only referenced via scene instantiation, never by code |
| Test scripts | **No** | Only instantiated by test_runner.tscn |

### 3.8 Coroutine (`await`) Patterns

<!-- Added 2026-03-27 after DiceSystem.player_roll() -->

GDScript marks a function as a **coroutine** if it contains `await` anywhere in its body — even branches that never execute the `await`. This has cascading consequences:

```gdscript
# If a function uses await internally, ALL callers must also await it.
# This propagates up the call chain.
var result := await DiceSystem.player_roll(20, 1, 2, "attack_throw", "Attack")

# Awaiting a signal with multiple parameters returns an Array:
var args: Array = await EventBus.player_roll_resolved
var roll_type: String     = args[0]
var raw_total: int        = args[1]
var was_player_entered: bool = args[2]

# Coroutines CANNOT be tested in synchronous test suites — test the
# underlying logic via synchronous helper methods (roll_digital, etc.) instead.
```

**Design rule:** Keep coroutines at system boundaries (DiceSystem, future SessionRunner). Internal subsystem logic should be synchronous — pass results via signals or return values, not by `await`-ing deep inside game logic.

### 3.9 Static Methods

Use static methods for pure functions that don't need instance state. Prefer them in utility contexts.

```gdscript
# GOOD — pure calculation, no state needed
static func ability_modifier(score: int) -> int:
    # ACKS ability modifier table
    match score:
        3: return -3
        4, 5: return -2
        6, 7, 8: return -1
        9, 10, 11, 12: return 0
        13, 14, 15: return 1
        16, 17: return 2
        18: return 3
    return 0

# BAD — static method that secretly needs instance state
static func get_current_hp():
    return GameState.active_character.hp  # accesses global state — make this an instance method
```

---

## 4. Signal Conventions

### 4.1 Declaration Location

Signals are declared at the top of the class that **emits** them, after constants and enums.

```gdscript
class_name CombatManager
extends Node

const ROUND_DURATION := 10

enum Phase { INITIATIVE, ACTION, MORALE, CLEANUP }

signal combat_started(encounter_id: int)
signal round_completed(round_number: int)
signal combatant_defeated(combatant_id: int, was_mortal_wound: bool)
signal combat_ended(encounter_id: int, outcome: String)
```

### 4.2 Connection Patterns

Connect signals in `_ready()` of the **listener**, not the emitter. Prefer `connect()` over the editor's signal panel for code-reviewability.

```gdscript
# GOOD — listener connects in its own _ready()
func _ready() -> void:
    CombatManager.combat_started.connect(_on_combat_started)
    CombatManager.combat_ended.connect(_on_combat_ended)

func _on_combat_started(encounter_id: int) -> void:
    # update UI...

# BAD — emitter reaching into listeners to connect
func _ready() -> void:
    combat_started.connect(ui_panel._on_combat_started)  # emitter shouldn't know about UI
```

### 4.3 When to Use Signals vs Direct Calls

| Use signals when... | Use direct method calls when... |
|---------------------|-------------------------------|
| Multiple listeners might care | Exactly one caller, one callee |
| Emitter shouldn't know about listeners | Caller needs a return value |
| Crossing subsystem boundaries | Within the same subsystem/class |
| The event is "something happened" | The call is "do this thing" |

```gdscript
# GOOD — signal across subsystem boundary
# CombatManager doesn't know or care who listens
signal combatant_defeated(combatant_id: int, was_mortal_wound: bool)
emit_signal("combatant_defeated", combatant_id, true)

# GOOD — direct call within subsystem
# CombatManager calling its own DamageCalculator
var damage := _damage_calculator.calculate(attacker, weapon, target)
```

### 4.4 Signal Payload Conventions

<!-- Added 2026-03-27 from EventBus patterns -->

Cross-subsystem signals pass **String IDs**, not object references. Complex data uses **Dictionary payloads** with keys documented immediately above the signal declaration.

```gdscript
# GOOD — String IDs, documented Dictionary payload
## [param outcome] keys:
##   result: String  — "victory", "defeat", "fled", "surrendered"
##   rounds: int     — number of rounds the combat lasted
signal combat_ended(encounter_id: String, outcome: Dictionary)

# GOOD — simple typed parameters for small payloads
signal hp_changed(character_id: String, old_hp: int, new_hp: int)

# BAD — passing object references across subsystem boundaries
signal combat_ended(encounter: EncounterData, outcome: CombatOutcome)
```

**EventBus signal groups** (keep signals organized under section headers):
Combat, Exploration, Character, Domain, Magic, LLM/Narration, Persistence, Override system, Dice system.

---

## 5. Autoload Rules

### 5.1 The Six Autoloads

<!-- 2026-03-25: EventBus added. 2026-03-27: DiceSystem added (approved by Jedidiah — dice needed by every subsystem). -->

Six autoload singletons exist. This list requires **explicit approval from Jedidiah** to extend. The bar is "needed by every subsystem" — if only one or two callers use it, make it a scene-local node instead.

| Autoload | Responsibility | Lives in |
|----------|---------------|----------|
| `GameState` | Session state machine, dice mode, settings persistence | `engine/autoloads/game_state.gd` |
| `EventBus` | Cross-subsystem signal bus (40+ signals, all past-tense) | `engine/autoloads/event_bus.gd` |
| `CampaignRepository` | All SQLite read/write, migration runner, ID generation | `engine/autoloads/campaign_repository.gd` |
| `LLMManager` | Provider routing, request/response, token tracking (stub) | `engine/autoloads/llm_manager.gd` |
| `AudioRouter` | SFX/music playback, audio bus management (stub) | `engine/autoloads/audio_router.gd` |
| `DiceSystem` | Dice rolling (digital/physical/hybrid), override consumption, roll log | `engine/autoloads/dice_system.gd` |

**Load order matters.** DiceSystem depends on GameState, EventBus, and CampaignRepository — it must be registered after them in `project.godot`.

### 5.2 Autoload Constraints

- **No `class_name`** in autoload scripts. Godot errors with "hides an autoload singleton."
- Autoloads are referenced by their registered name directly (e.g., `GameState.foo`).
- If you think you need a new autoload, you probably need a scene-local manager node instead.

```gdscript
# GOOD — game_state.gd (autoload)
extends Node
# NO class_name declaration here

var current_session_id: int = -1
var active_party: Array[int] = []

# BAD — game_state.gd with class_name
class_name GameState    # ERROR: "hides an autoload singleton"
extends Node
```

### 5.3 Alternatives to Autoloads

| Need | Solution |
|------|----------|
| Manager for one scene tree | Add a manager Node as child of that scene |
| Shared utility functions | Static methods in a regular class (no autoload needed) |
| Data shared between two subsystems | Define in `engine/shared_types/`, pass via signals or method args |
| Event bus for a subsystem | Local signal hub node within that subsystem's scene |

---

## 6. SQLite Patterns

### 6.1 godot-sqlite API

```gdscript
# GOOD — correct godot-sqlite usage
var db := SQLite.new()
db.path = "user://campaign.db"  # user:// not res://
db.open_db()

# query(sql) — no parameters; returns bool
db.query("SELECT * FROM characters ORDER BY name")

# query_with_bindings(sql, array) — parameterized; returns bool
# NEVER pass a second argument to query() — it only accepts 1.
var success := db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [character_id])
if success and db.query_result.size() > 0:
    var row: Dictionary = db.query_result[0]
    return row

# BAD
db.path = "res://campaign.db"                      # res:// is read-only in exports
var results = db.query(sql)                        # query() returns bool, not results
db.query("SELECT * FROM characters WHERE id = ?", [character_id])  # WRONG: query() only takes 1 arg
```

### 6.2 Repository Pattern

All database access goes through `CampaignRepository`. Subsystems never touch SQLite directly.

```gdscript
# GOOD — subsystem asks CampaignRepository
var character: Dictionary = CampaignRepository.get_character(char_id)

# BAD — subsystem opens its own database connection
var db := SQLite.new()
db.path = "user://campaign.db"
db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [char_id])
```

<!-- Confirmed by CampaignRepository — 2026-03-25 -->
<!-- Boolean DB fields are stored as INTEGER (0/1) and converted on read. The `save_<thing>` methods
     perform upsert (SELECT-then-INSERT-or-UPDATE). Methods that may fail return `bool`; methods that
     return an entity return `Dictionary` (null for not-found is represented by empty `{}`). -->

Repository methods follow this naming:
- `get_<thing>(id)` — single record by primary key
- `list_<things>(filters)` — multiple records with optional filters
- `save_<thing>(data)` — insert or update (upsert)
- `delete_<thing>(id)` — soft or hard delete (prefer soft delete with `is_active` flag)
- `count_<things>(filters)` — count query

### 6.3 Migration Files

Migrations live in `db/migrations/` with sequential zero-padded numbering. The migration runner (`CampaignRepository._run_migrations()`) parses the version from the filename prefix (e.g. `001_` → version 1), skips already-applied versions, and records each in `schema_migrations`.

```
db/migrations/
├── 001_initial_schema.sql       # Tier 1 tables: campaigns, characters, parties, hex_maps, etc.
├── 002_override_log.sql         # override_log, game_snapshots, dungeon_entrances
├── 003_dice_roll_log.sql        # dice_rolls (session-only, capped at 200 rows)
```

**Rules:**
- Migrations are **append-only** — never edit a committed migration.
- Each migration is a single `.sql` file with both the change and any data backfills.
- After writing a migration, update `db/schema.sql` to reflect the new state.
- Migrations must be **non-destructive** — never DROP TABLE without explicit approval.

```sql
-- GOOD — 002_add_domain_tables.sql
CREATE TABLE IF NOT EXISTS domains (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    owner_character_id INTEGER REFERENCES characters(id),
    territory_type TEXT NOT NULL CHECK(territory_type IN ('civilized', 'borderlands', 'wilderness')),
    population INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- BAD — destructive migration without approval
DROP TABLE characters;
CREATE TABLE characters (...);
```

### 6.4 Transactions

<!-- Confirmed by CampaignRepository.save_hex_map() — 2026-03-25 -->

```gdscript
# GOOD — wrap multi-statement operations in transactions
func save_character_with_proficiencies(char_data: Dictionary, proficiencies: Array) -> bool:
    db.query("BEGIN TRANSACTION")
    var success := db.query_with_bindings("INSERT INTO characters ...", [...])
    if not success:
        db.query("ROLLBACK")
        return false
    for prof in proficiencies:
        success = db.query_with_bindings("INSERT INTO character_proficiencies ...", [...])
        if not success:
            db.query("ROLLBACK")
            return false
    db.query("COMMIT")
    return true
```

### 6.5 Enum Storage

Store enums as human-readable TEXT, constrained by CHECK.

```sql
-- GOOD
territory_type TEXT NOT NULL CHECK(territory_type IN ('civilized', 'borderlands', 'wilderness'))
combat_progression TEXT NOT NULL CHECK(combat_progression IN ('fighter', 'cleric', 'thief', 'mage'))

-- BAD
territory_type INTEGER NOT NULL  -- 0=civilized, 1=borderlands... what was 2 again?
```

### 6.6 Primary Key Conventions

<!-- Added 2026-03-27 — confirmed in schema.sql -->

| Table category | Primary key type | Example |
|---|---|---|
| Entity tables (characters, campaigns, domains) | `TEXT PRIMARY KEY` | `id TEXT PRIMARY KEY` — hex string from `CampaignRepository.generate_id()` |
| Log/audit tables (override_log, dice_rolls) | `INTEGER PRIMARY KEY AUTOINCREMENT` | Sequential, auto-assigned |
| Join tables (party_members) | Composite `PRIMARY KEY (a_id, b_id)` | No separate id column |
| Spatial tables (hex_cells) | Composite `PRIMARY KEY (map_id, q, r)` | Coordinate-based natural key |

**ID generation:** `CampaignRepository.generate_id()` produces a collision-resistant hex string (not a proper UUID, but sufficient for single-player). All entity tables use these text IDs.

### 6.7 Settings Persistence

<!-- Added 2026-03-27 — GameState.save_settings() / load_settings() -->

Persistent user preferences (not game state) are stored in a Godot `ConfigFile` at `user://settings.cfg`. Game state belongs in SQLite; settings belong in ConfigFile.

```gdscript
# Pattern: section/key pairs
const _SETTINGS_PATH := "user://settings.cfg"

func save_settings() -> void:
    var config := ConfigFile.new()
    config.set_value("dice", "mode", dice_mode)
    config.save(_SETTINGS_PATH)

func load_settings() -> void:
    var config := ConfigFile.new()
    if config.load(_SETTINGS_PATH) != OK:
        return  # first launch — use defaults
    dice_mode = config.get_value("dice", "mode", DiceMode.HYBRID) as DiceMode
```

| Data | Where it goes | Why |
|---|---|---|
| Character HP, inventory, position | SQLite (CampaignRepository) | Game state — queryable, transactional |
| Dice mode, UI preferences | ConfigFile (`user://settings.cfg`) | User preference — survives across campaigns |
| Pending dice overrides | `GameState.dice_overrides` (in-memory Dictionary) | Ephemeral dev-mode state — not persisted |

---

## 7. Resource and Data Patterns

### 7.1 When to Use What

| Data type | Storage | Why |
|-----------|---------|-----|
| Persistent game state (characters, domains, inventories) | SQLite | Queryable, transactional, ground truth |
| Configuration and templates (class definitions, spell templates) | Godot Resources (`.tres`) or JSON in `data/` | Loaded at startup, read-only at runtime |
| Cross-subsystem data shapes | GDScript classes in `engine/shared_types/` | Type-checked, documented, importable |
| LLM system prompt fragments | Text files in `llm_context/` | Injected into context assembly |
| Runtime-generated data (setting, dungeon layouts) | SQLite (persisted) or in-memory (transient) | Depends on whether it survives session close |

### 7.2 Shared Type Definitions

Canonical data shapes live in `engine/shared_types/`. These are the contracts between subsystems.

<!-- Confirmed across all 9 types — 2026-03-27 -->

**All shared types:**

| Type | Purpose | `from_dict` | `to_dict` |
|---|---|---|---|
| `ActionPayload` | Action vocabulary entry (actor, action, params) | Yes | No |
| `CharacterData` | PC/henchman/NPC stat block | Yes | Yes |
| `EncounterData` | Encounter group descriptor | Yes | No |
| `EventPayload` | Domain/exploration event | Yes | No |
| `HexMapData` | Hex map container with fog states | Yes | No |
| `HexTerrainData` | Terrain tags for a single hex | Yes | No |
| `InventoryItem` | Item with quantity and encumbrance | Yes | Yes |
| `ResponseEnvelope` | LLM response wrapper | Static factories | No |
| `RollResult` | Resolved dice roll with all metadata | No | Yes |

**Serialisation rules:**
- Types persisted to DB **must** have `to_dict() -> Dictionary`. Booleans convert to 0/1 integers.
- Types constructed from DB rows or JSON **must** have `static func from_dict(data: Dictionary) -> ClassName` using `.get(key, default)` for resilience.
- Read-only runtime types (HexTerrainData, EncounterData) may omit `to_dict()`.
- All shared types use `class_name ClassName` and `extends RefCounted`.

```gdscript
# engine/shared_types/character_data.gd
class_name CharacterData
extends RefCounted

## Identity
var id: int = -1
var name: String = ""
var race: String = ""
var character_class: String = ""  # "class" is a reserved word in some contexts
var level: int = 0
var xp: int = 0
var tier: String = "transient"  # "full", "named", "transient"

## Ability Scores
var strength: int = 10
var intelligence: int = 10
var wisdom: int = 10
var dexterity: int = 10
var constitution: int = 10
var charisma: int = 10

## Derived Stats
var hp_max: int = 0
var hp_current: int = 0
var armor_class: int = 0
var attack_throw: int = 10
```

### 7.3 Data Shape Changes Are Contract Changes

If you modify a class in `shared_types/`, every subsystem that imports it may be affected. Treat shared type changes as cross-subsystem contract changes requiring approval (see Section 11).

---

## 8. Error Handling Patterns

### 8.1 Logging Format

All error logs include: **what was attempted**, **what failed**, **relevant state**.

```gdscript
# GOOD
push_error("CombatResolver: Failed to resolve attack. Attacker ID: %d, Target ID: %d, Weapon: %s. Error: %s" % [attacker_id, target_id, weapon_name, error_msg])

push_warning("LLMManager: Provider returned empty response. Provider: %s, Task: %s. Falling back to template." % [provider_name, task_type])

# BAD
push_error("Something went wrong")        # no context
push_error("Error in combat")             # which combat? what error?
print("failed")                           # print instead of push_error, no context
```

### 8.2 Error Propagation

<!-- Confirmed by CampaignRepository — 2026-03-25 -->

Functions that can fail return a typed result or use a success boolean pattern:

```gdscript
# GOOD — return null on failure with logged error
func get_character(character_id: int) -> CharacterData:
    var success := db.query_with_bindings("SELECT * FROM characters WHERE id = ?", [character_id])
    if not success or db.query_result.size() == 0:
        push_error("CampaignRepository: Character not found. ID: %d" % character_id)
        return null
    return _row_to_character(db.query_result[0])

# Caller checks
var character := CampaignRepository.get_character(id)
if character == null:
    # handle missing character
    return
```

### 8.3 LLM Failure Handling

LLM calls are never on the critical path. Every LLM call has a fallback.

```gdscript
# GOOD — LLM failure falls back to template
var narration := await LLMManager.request_narration(context)
if narration == null or narration.is_empty():
    push_warning("LLMManager: Narration request failed. Task: %s. Using template fallback." % context.task_type)
    narration = _template_fallback(context)

# BAD — LLM failure blocks gameplay
var narration := await LLMManager.request_narration(context)
assert(narration != null)  # crashes the game if LLM is down
```

### 8.4 Never Silently Swallow Errors

```gdscript
# GOOD
if not db.query(sql):
    push_error("CampaignRepository: Query failed. SQL: %s" % sql)
    return false

# BAD
db.query(sql)  # ignores the return value — was it successful?
```

---

## 9. Testing Patterns

### 9.1 File and Function Naming

```
tests/
├── test_combat_resolver.gd
├── test_xp_calculator.gd
├── test_campaign_repository_integration.gd
└── test_character_creation.gd
```

Test functions use `test_` prefix with a descriptive name:

```gdscript
# GOOD
func test_fighter_cleave_grants_extra_attacks_equal_to_level() -> void:
func test_mortal_wound_roll_applies_con_modifier() -> void:
func test_bankers_rounding_rounds_half_to_even() -> void:

# BAD
func test_combat() -> void:         # too vague
func test_1() -> void:              # meaningless
func fighter_cleave_test() -> void:  # missing test_ prefix
```

### 9.2 Test Framework — Plain `assert()` with `run_all_tests()`

<!-- Confirmed 2026-03-27 — no external test framework; plain GDScript assert. -->

No external test framework (no GdUnit4, no gut). Each test suite is a plain Node script with individual `test_*()` functions called from a `run_all_tests()` method. GDScript `assert()` aborts the calling script on failure.

```gdscript
extends Node

func run_all_tests() -> void:
    test_d6_in_range()
    test_modifier_applied()
    test_override_consumed()
    # ... list every test function explicitly
    print("MyTests: all tests passed")  # only reached if no assert fired

func test_d6_in_range() -> void:
    var r := DiceSystem.roll_digital(6)
    assert(r.modified_total >= 1 and r.modified_total <= 6,
        "d6 result out of range: %d" % r.modified_total)
```

**Test runner:** `tests/test_runner.tscn` instantiates all suites as child nodes. `test_runner.gd` iterates suites, calls `run_all_tests()` on each, counts passes/failures. Exits with code 0/1 for CI (`godot --headless --path . res://tests/test_runner.tscn`).

**Limitation:** `assert()` aborts the suite on failure — the runner cannot catch individual assert failures or continue past them. The "all tests passed" print at the end of each suite is the success signal.

**Coroutine tests:** Functions containing `await` cannot be called from the synchronous `run_all_tests()` loop. Test the underlying synchronous helpers instead.

### 9.3 Unit vs Integration Tests

| Test type | Scope | Database | LLM | File suffix |
|-----------|-------|----------|-----|-------------|
| Unit | Single class/function | No (mock or in-memory) | No | `test_<thing>.gd` |
| Integration | Two+ subsystems or database | Yes (test database) | Mock provider | `test_<thing>_integration.gd` |
| Scenario | Full game loop segment | Yes (test database) | Mock provider | `test_scenario_<name>.gd` |

### 9.4 Mock LLM Provider in Tests

The mock provider returns deterministic template responses. All tests must pass with mock provider. If a test needs specific LLM output, configure the mock's response, don't call a real API.

```gdscript
# GOOD — test uses mock provider
func test_npc_dialogue_falls_back_to_template() -> void:
    LLMManager.set_provider(MockLlmProvider.new())
    var response := await LLMManager.request_narration(dialogue_context)
    assert_not_null(response)
    assert_true(response.length() > 0)
```

### 9.5 What to Assert

- **Assert behavior, not implementation.** Test what the function returns or what state changes, not how it internally works.
- **Assert ACKS rule compliance.** If a function implements an ACKS rule, the test should verify the rule is followed.
- **Assert boundary values.** Especially for banker's rounding, level thresholds, and domain population breakpoints.

---

## 10. Action Vocabulary and Roll Types

### 10.1 Action Vocabulary

[PROVISIONAL — full action vocabulary definition file not yet created. Actions are currently defined implicitly by the subsystems that handle them. A formal `action_vocabulary.gd` will be created when the session runner and combat systems are built.]

**Rules for when it's built:**
- Register actions when the subsystem that owns them is built — not speculatively.
- Every action is validated before execution by the rules engine.
- Unknown, malformed, or rule-violating actions are rejected with a logged error.
- Both UI clicks and text input resolve to the same action vocabulary entries.

### 10.2 Dice Roll Type Vocabulary

<!-- Confirmed 2026-03-27 — 19 roll types defined in OverrideManager and used by DiceSystem -->

Roll types are snake_case strings identifying the mechanical purpose of a dice roll. Used by the override queue (GameState.dice_overrides) and the roll log (dice_rolls table). Canonical list defined in `override_manager.gd` header comment and mirrored in `override_panel.gd::ROLL_TYPES`.

**Player-facing rolls** (prompted in PHYSICAL/HYBRID mode — use `DiceSystem.player_roll()`):
`player_surprise_check`, `initiative`, `attack_throw`, `damage_roll`, `saving_throw_petrification`, `saving_throw_poison`, `saving_throw_blast`, `saving_throw_wands`, `saving_throw_spells`, `thief_skill_throw`, `proficiency_throw`, `mortal_wound_roll`, `tampering_with_mortality`

**GM/digital-only rolls** (never prompted — use `DiceSystem.roll_digital()`):
`encounter_check`, `monster_surprise_check`, `morale_check`, `reaction_roll`, `domain_event_roll`, `hijink_roll`

**Adding a new roll type:** Add to both the `OverrideManager` header comment and the `ROLL_TYPES` array in `override_panel.gd`. The DiceSystem itself is type-agnostic — any string works as a roll_type.

---

## 11. Cross-Subsystem Boundaries

### 11.1 What Counts as a Contract

A **contract** is any interface that another subsystem depends on:

- Signal names and parameter types
- Public method signatures on autoloads
- Shared type class fields (`engine/shared_types/`)
- Database table schemas
- Action vocabulary entries
- LLM context assembly format

### 11.2 Contract Change Process

**Changing a contract requires explicit approval from Jedidiah.** This includes:
- Renaming a signal or changing its parameters
- Changing a public method signature on an autoload
- Adding/removing/renaming fields in a shared type
- Altering a database table schema (add via migration, never modify existing columns)
- Restructuring the action vocabulary format

**Does NOT require approval:**
- Adding a new signal (doesn't break existing listeners)
- Adding a new public method (doesn't break existing callers)
- Adding a new field with a default value to a shared type
- Adding a new database column with a default (via migration)
- Adding a new action vocabulary entry

### 11.3 Documenting Dependencies

When a subsystem depends on another, document it in the subsystem's top-level script:

```gdscript
# engine/subsystems/combat/combat_manager.gd
#
# Dependencies:
#   - GameState (autoload): reads active_party, current encounter
#   - CampaignRepository (autoload): loads character data, saves combat results
#   - CharacterData (shared_type): character stat blocks
#   - EncounterData (shared_type): encounter descriptors
#
# Signals emitted:
#   - combat_started(encounter_id: int)
#   - combat_ended(encounter_id: int, outcome: String)
#   - combatant_defeated(combatant_id: int, was_mortal_wound: bool)
#
# Signals consumed:
#   - GameState.encounter_triggered → starts combat
```

### 11.4 The Build Log Is the Memory

When you define or change any contract, record it in `build_log.md` under "Interfaces defined or changed." This prevents naming drift across sessions. Be exact — write the signal signature, not just "added a signal."

---

## 12. ACKS-Specific Implementation Rules

These are not coding style — they are mechanical rules that must be followed in all game logic.

| Rule | Details | Defined in |
|------|---------|-----------|
| Banker's rounding | `roundi()` everywhere. No `int()` truncation, no `ceili()`. | CLAUDE.md |
| Four combat progressions | `fighter`, `cleric`, `thief`, `mage`. Never `crusader` (ACKS II only). | CLAUDE.md |
| Three territory types | `civilized`, `borderlands`, `wilderness`. Never `outlands` or `unsettled`. | CLAUDE.md |
| Turn undead | Always "turn undead," never "rebuke undead." | CLAUDE.md, ACKS 1e |
| 0th-level threshold | 500 XP to advance from 0th to 1st level. | `acore_basics_and_characters.xml` |
| Calendar | 13 months x 28 days. Weeks = 7 days. | Design brief |
| Max party size | 8 PCs. | Design brief |
| Henchmen per PC | Determined by CHA modifier + 4. | `acore_basics_and_characters.xml` |
| Three character tiers | `full` (PCs), `named` (henchmen/recurring NPCs), `transient` (throwaway). | Design brief |
| Three character types | `pc`, `henchman`, `npc`. Stored as TEXT with CHECK constraint. | `db/schema.sql` |
| Encumbrance unit | 1/6-stone (6 units = 1 stone). Column: `encumbrance_sixths`. | `acore_equipment.xml` |
| Inventory slots | `hands_main`, `hands_off`, `body`, `head`, `belt`, `pack`, `mount`. | Design brief |
| Fog of war states | `HIDDEN` → `EXPLORED` → `VISIBLE`. Never transition backwards. | `hex_map_data.gd` |
| Three dice modes | `DIGITAL`, `PHYSICAL`, `HYBRID` (default). Persisted in `user://settings.cfg`. | Design brief §8.4 |

---

## 13. UI Panel Conventions

<!-- Added 2026-03-27 from OverridePanel and DicePrompt patterns -->

### 13.1 CanvasLayer Stacking

UI panels that overlay the game use CanvasLayer nodes with explicit layer assignments. Higher numbers draw on top.

| Layer | Purpose | Example |
|---|---|---|
| 0 | Normal game content | Default |
| 10 | Map HUD (tooltips, coordinates) | HexHUD in hex_map_renderer.gd |
| 64 | Modal prompts (dice rolls, dialogs) | DicePrompt |
| 128 | Developer override panel | OverridePanel |

When adding a new overlay, pick a layer between the closest existing values. The override panel should always be the topmost layer (so the GM can intervene at any time).

### 13.2 Programmatic UI Construction

Dev-mode UI panels (OverridePanel, DicePrompt) build all widgets in `_build_ui()` called from `_ready()`. This avoids editor-only layouts and keeps the panel definition in one file.

```gdscript
# Pattern: CanvasLayer + programmatic children
extends CanvasLayer

func _ready() -> void:
    layer = 64
    visible = false       # hidden until activated
    _build_ui()
    EventBus.some_signal.connect(_on_some_signal)

func _build_ui() -> void:
    # ... create all Controls as children
```

**No `class_name`** on these scripts — they are only referenced via scene instantiation in Main.tscn, never by code.

### 13.3 Scene Tree — Main.tscn

<!-- Updated 2026-03-27 -->

```
Main (Node, script: main_scene.gd)
├── HexMapController (Node, script: hex_map_controller.gd)
├── HexMap (instance of hex_map.tscn)
├── OverrideManager (Node, script: override_manager.gd)
├── OverridePanel (instance of override_panel.tscn)
└── DicePrompt (instance of dice_prompt.tscn)
```

`main_scene.gd` wires the controller to the renderer and the override panel to the manager in `_ready()`. Subsystem managers are plain Node children — not autoloads.

---

## 14. ACKS-Specific Implementation Rules (continued)

### 14.1 Dice Conventions

| Rule | Details |
|---|---|
| d3 is first-class | Roll `randi_range(1, 3)` directly. Do not roll d6 and divide. |
| Override = modified total | A forced override value represents the final result (with modifiers). DiceSystem back-calculates raw_total. |
| Player enters raw total | When using physical dice, the player enters the sum of dice only. The app applies modifiers. |
| Natural 1 / natural 20 | Only flagged on single-die d20 rolls (`count == 1`). Multi-die rolls never set these flags. |
| Session-only roll log | `dice_rolls` table cleared on `GameState.session_ended`. Capped at 200 rows (oldest auto-pruned). |

---

*Last major update: 2026-03-27 — Sweep of all code built since 2026-03-25. Updated autoload list (6), directory tree, shared types table, test framework, roll type vocabulary, CanvasLayer layering, coroutine patterns, primary key conventions, settings persistence, UI panel patterns, dice conventions.*
