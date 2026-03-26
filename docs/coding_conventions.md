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

Only four autoloads exist (see Section 5). Reference them by their PascalCase name directly.

```gdscript
# GOOD
GameState.current_session_id
CampaignRepository.get_character(char_id)
LLMManager.request_narration(context)
AudioRouter.play_sfx("sword_clash")

# BAD
game_state.current_session_id  # autoloads are PascalCase
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

```
acks-arbiter/         (Godot project root — inside the repo)
├── engine/
│   ├── autoloads/              # Only the four global singletons
│   │   ├── game_state.gd
│   │   ├── campaign_repository.gd
│   │   ├── llm_manager.gd
│   │   └── audio_router.gd
│   ├── shared_types/           # Cross-subsystem data shape definitions
│   │   ├── character_data.gd
│   │   ├── action_payload.gd
│   │   ├── encounter_data.gd
│   │   ├── map_metadata.gd
│   │   └── response_envelope.gd
│   └── subsystems/
│       ├── combat/             # Combat resolution, conditions, morale
│       ├── exploration/        # Dungeon, wilderness, settlement, sea procedures
│       ├── character/          # Creation, stats, XP, leveling, henchmen, aging
│       ├── domain/             # Strongholds, followers, domain events, monthly cycle
│       └── magic/              # Spellcasting, spell research, magic items
├── scenes/
│   ├── maps/                   # Map display scenes (hex, dungeon, settlement, battle)
│   ├── ui/                     # UI panel scenes
│   └── combat/                 # Combat-specific visual scenes
├── ui/                         # UI controller scripts and theme resources
├── tests/                      # All test scripts
├── db/
│   ├── schema.sql              # Canonical schema (always reflects current state)
│   └── migrations/             # Versioned migration files
├── data/                       # Clean runtime JSON
├── llm_context/                # Stripped rule summaries for LLM system prompts
└── assets/
    ├── sprites/
    ├── audio/
    ├── fonts/
    └── placeholders/           # Generated stub assets
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

### 3.7 Static Methods

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

---

## 5. Autoload Rules

### 5.1 The Five Autoloads

<!-- 2026-03-25: EventBus added per explicit session request -->

Only five autoload singletons exist. This list is **closed** — do not add new autoloads without explicit approval from Jedidiah.

| Autoload | Responsibility | Lives in |
|----------|---------------|----------|
| `GameState` | Current session state, active party, timekeeping | `engine/autoloads/game_state.gd` |
| `EventBus` | Cross-subsystem signal bus (all past-tense signals) | `engine/autoloads/event_bus.gd` |
| `CampaignRepository` | All SQLite read/write, migration runner | `engine/autoloads/campaign_repository.gd` |
| `LLMManager` | Provider routing, request/response, token tracking | `engine/autoloads/llm_manager.gd` |
| `AudioRouter` | SFX/music playback, audio bus management | `engine/autoloads/audio_router.gd` |

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

Migrations live in `db/migrations/` with sequential numbering:

```
db/migrations/
├── 001_initial_schema.sql
├── 002_add_domain_tables.sql
├── 003_add_character_conditions.sql
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

<!-- Confirmed by CharacterData, InventoryItem, ActionPayload, EncounterData, ResponseEnvelope, EventPayload — 2026-03-25 -->
<!-- Types persisted to DB add `to_dict() -> Dictionary` (booleans → 0/1 integers). Types that are
     read-only at runtime (HexTerrainData, EncounterData) may omit `to_dict()`. All types have a
     `static func from_dict(data: Dictionary) -> ClassName` factory using `.get(key, default)` for
     resilience. -->

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

### 9.2 Test Structure

[PROVISIONAL — confirm test framework during first test implementation. Godot 4 has GdUnit4 and gut as popular options.]

Each test follows arrange-act-assert:

```gdscript
func test_xp_threshold_for_0th_level_henchman_is_500() -> void:
    # Arrange
    var henchman := CharacterData.new()
    henchman.level = 0
    henchman.xp = 499

    # Act
    var can_level := XpCalculator.can_level_up(henchman)

    # Assert
    assert_false(can_level)

    # Act — at threshold
    henchman.xp = 500
    can_level = XpCalculator.can_level_up(henchman)

    # Assert
    assert_true(can_level)
```

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

## 10. Action Vocabulary Registration

[PROVISIONAL — confirm file location and format during first action vocabulary implementation]

### 10.1 Definition Location

Action vocabulary definitions live in a single canonical file:
`engine/shared_types/action_vocabulary.gd`

### 10.2 Action Definition Structure

Each action specifies:

```gdscript
# Proposed structure — confirm during implementation
var ACTION_ATTACK_MELEE := {
    "id": "attack_melee",
    "display_name": "Melee Attack",
    "category": "combat",
    "parameters": {
        "attacker_id": TYPE_INT,
        "target_id": TYPE_INT,
        "weapon_id": TYPE_INT,
    },
    "preconditions": ["attacker_alive", "target_in_melee_range", "weapon_equipped"],
    "effects": ["damage_roll", "possible_cleave"],
    "context_tags": ["combat", "melee"],
}
```

### 10.3 Registration Rules

- Register actions when the subsystem that owns them is built — not speculatively.
- Every action is validated before execution by the rules engine.
- Unknown, malformed, or rule-violating actions are rejected with a logged error.
- Both UI clicks and text input resolve to the same action vocabulary entries.
- The LLM references this vocabulary in system prompts for input interpretation.

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

---

*Last major update: 2026-03-25 — Initial creation from CLAUDE.md and design brief v11.*
