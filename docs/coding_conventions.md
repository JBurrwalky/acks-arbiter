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

<!-- Updated 2026-04-02 to reflect D-4 dungeon/tactical grid system -->

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
│   │   ├── character_data.gd       # + runtime fields: modifiers, flags, damage_resistances
│   │   ├── condition_catalog.gd    # loads data/conditions/condition_catalog.json
│   │   ├── damage_resistance.gd    # per-entity immunity/resistance/vulnerability
│   │   ├── damage_types.gd         # static constants (PHYSICAL, FIRE, COLD, …)
│   │   ├── encounter_data.gd
│   │   ├── entity_flags.gd         # multi-source boolean state flags
│   │   ├── event_payload.gd
│   │   ├── hex_map_data.gd
│   │   ├── hex_terrain_data.gd
│   │   ├── inventory_item.gd       # + damage_type, material fields
│   │   ├── isometric_grid.gd       # static diamond-grid math (cell↔screen, neighbors, radius)
│   │   ├── modifier_container.gd   # per-entity facade over ModifierStacks
│   │   ├── modifier_stack.gd       # ordered modifier list for a single stat
│   │   ├── response_envelope.gd
│   │   ├── roll_result.gd
│   │   └── tactical_map_data.gd    # unified cell grid (dungeon + combat); TacticalMapData
│   └── subsystems/
│       ├── calendar/       # CalendarConstants, CalendarSeasons (pure static computation)
│       ├── characters/     # PowerRegistry, ClassRegistry, ProficiencyRegistry, ProficiencyEffectResolver,
│       │                   #   AbilityUtils, EncumbranceCalculator, CharacterGenerator
│       ├── exploration/    # HexMapController, DungeonMapController
│       ├── navigation/     # NavigationStack (not autoload; placed in Main.tscn)
│       ├── override/       # OverrideManager (dev-mode state manipulation)
│       ├── spells/         # SpellRegistry, RepertoireEngine, ActiveEffectTracker, SpellEffectRegistry
│       ├── combat/         # (planned)
│       ├── domain/         # (planned)
│       └── magic/          # (planned)
├── scenes/
│   ├── Main.tscn           # Root scene (instantiates all children)
│   ├── main_scene.gd       # Test harness wiring
│   ├── maps/               # hex_map.tscn, hex_map_renderer.gd,
│   │                       # dungeon_map.tscn, dungeon_map_renderer.gd
│   └── ui/
│       ├── override/       # override_panel.gd / .tscn
│       ├── dice/           # dice_prompt.gd / .tscn
│       ├── character_creation/  # 9-step PC creation wizard panels
│       └── components/     # Reusable UI: character_sheet_panel.gd
├── tests/                  # All test scripts + test_runner.tscn
├── db/
│   ├── schema.sql          # Canonical schema (update after every migration)
│   └── migrations/         # 001_initial_schema .. 017_dungeon_grid
├── data/
│   ├── classes/            # One JSON per ACKS class (25 files)
│   ├── powers/             # power_catalog.json (reusable power definitions)
│   ├── equipment/          # base_equipment.json (v2, weapons/armor/gear/clothing, ~130 items)
│   │                       # transport.json (mounts, vehicles, barding, livestock)
│   │                       # provisions_services.json (food, lodging, hireling/mercenary wages)
│   │                       # poisons.json (15 monster venoms + 8 plant toxins)
│   │                       # siege_weapons.json (ballista, catapults, shot)
│   │                       # maritime.json (12 vessel types)
│   │                       # All costs in copper pieces (cost_cp): 1gp=100cp, 1sp=10cp
│   ├── conditions/         # condition_catalog.json (27 ACKS conditions)
│   ├── proficiencies/      # proficiency_catalog.json (106 entries), general_proficiency_list.json (38 keys)
│   ├── spells/             # spell_catalog.json (231 entries), spell_list_indices.json, spell_effects.json
│   ├── test_hex_map.json   # Test hex map data (31-hex Ashford Vale)
│   └── test_dungeon.json   # Test dungeon data (Goblin Warrens, 2 levels)
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

<!-- Confirmed 2026-03-27 across all engine files. Pure static class pattern added 2026-03-28 (CalendarSeasons, CalendarConstants). -->

| Script type | Use `class_name`? | Why |
|---|---|---|
| Autoload scripts | **Never** | Godot error: "hides an autoload singleton" |
| Shared types (`engine/shared_types/`) | **Always** | Enables typed references (`var r: RollResult`) |
| Subsystem managers (Node or RefCounted) | **Yes** | Enables typed instantiation: `var reg := SpellRegistry.new()` |
| Pure static/constants classes | **Yes** | Enables direct calls: `CalendarSeasons.get_season(day)` without instantiation |
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

**Pure static computation class** — when an entire class is nothing but constants and static functions (no instance variables, no `_ready()`), write it as a class with `class_name` but never instantiate it. Callers use the class name directly.

```gdscript
# calendar_seasons.gd — pure static class
class_name CalendarSeasons

const SPRING := "spring"
const SUMMER := "summer"

static func get_season(day_of_year: int) -> String:
    if day_of_year <= 91: return SPRING
    # ...

# calendar_constants.gd — pure constants class
class_name CalendarConstants

const VERNAL_EQUINOX_DAY := 46
const SUMMER_SOLSTICE_DAY := 137
```

```gdscript
# Callers — no instantiation, just use the class name
var season := CalendarSeasons.get_season(Timekeeping.get_day_of_year())
var equinox := CalendarConstants.VERNAL_EQUINOX_DAY
```

This pattern is preferred over autoloads for pure computation modules with no instance state. It avoids adding to the autoload list while still giving callers a clean global namespace. The canonical examples are `CalendarSeasons` and `CalendarConstants` in `engine/subsystems/calendar/`.

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
Combat, Exploration, Character, Domain, Magic, Damage, LLM/Narration, Persistence, Override system, Dice system.

---

## 5. Autoload Rules

### 5.1 The Six Autoloads

<!-- 2026-03-25: EventBus added. 2026-03-27: DiceSystem added (approved by Jedidiah — dice needed by every subsystem). 2026-03-27: Timekeeping added (approved by Jedidiah — clock consumed by session runner, domain, encounter, and condition subsystems). -->

Seven autoload singletons exist. This list requires **explicit approval from Jedidiah** to extend. The bar is "needed by every subsystem" — if only one or two callers use it, make it a scene-local node instead.

| Autoload | Responsibility | Lives in |
|----------|---------------|----------|
| `GameState` | Session state machine, dice mode, settings persistence | `engine/autoloads/game_state.gd` |
| `EventBus` | Cross-subsystem signal bus (40+ signals, all past-tense) | `engine/autoloads/event_bus.gd` |
| `CampaignRepository` | All SQLite read/write, migration runner, ID generation | `engine/autoloads/campaign_repository.gd` |
| `LLMManager` | Provider routing, request/response, token tracking (stub) | `engine/autoloads/llm_manager.gd` |
| `AudioRouter` | SFX/music playback, audio bus management (stub) | `engine/autoloads/audio_router.gd` |
| `DiceSystem` | Dice rolling (digital/physical/hybrid), override consumption, roll log | `engine/autoloads/dice_system.gd` |
| `Timekeeping` | Passive in-game clock, multi-party sync, dawn/dusk/day/month boundary signals | `engine/autoloads/timekeeping.gd` |

**Load order matters.** DiceSystem depends on GameState, EventBus, and CampaignRepository. Timekeeping depends on GameState (session_ended signal) and CampaignRepository (DB access) — both must be registered before it in `project.godot`.

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
| Subsystem with instance state, instantiated on demand | `class_name` RefCounted class, instantiated by the consumer (e.g., `SpellRegistry`, `ClassRegistry`, `RepertoireEngine`) |
| Pure computation (lookup tables, formulas, no instance state) | `class_name` class with only `const` and `static func` — see §3.9 |
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
├── 001_initial_schema.sql           # Tier 1 tables: campaigns, characters, parties, hex_maps, etc.
├── 002_override_log.sql             # override_log, game_snapshots, dungeon_entrances
├── 003_dice_roll_log.sql            # dice_rolls (session-only, capped at 200 rows)
├── 004_timekeeping.sql              # campaign_clock, party_clocks (Timekeeping autoload)
├── 005_characters_expanded.sql      # saves, movement, alignment, aging, languages, personality, powers
├── 006_spell_hook_infrastructure.sql # active_effects table; inventory_items.damage_type + material
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

### 6.8 Timekeeping Patterns

<!-- Added 2026-03-27 after Timekeeping autoload build -->

**Passive clock:** `Timekeeping` never ticks on its own. Only the session runner advances it by calling `advance_*()` or `advance_to_*()` methods. No background timer, no `_process()`.

**Advance methods emit boundary signals automatically:**

```gdscript
# GOOD — advance and let Timekeeping emit day_changed, month_changed, dawn, dusk as needed
Timekeeping.advance_hours(8)    # crosses midnight → day_changed fires automatically

# BAD — manually tracking time to decide whether to emit signals
_elapsed_hours += 8
if _elapsed_hours % 24 == 0:
    emit_signal("day_changed")   # reinventing what Timekeeping already does
```

**Boundary signals fire once per crossing, even for large advances:**

```gdscript
# advance_days(40) from start:
#   → 40 × day_changed (for each day 2–41)
#   → 1 × month_changed (at day 29 = month 2)
#   → 0 × year_changed (no full year crossed)
#   → 2-3 × dawn / dusk per day depending on start position
```

**Multi-party split:** `_elapsed_rounds` always equals the furthest-ahead party. Global boundary signals fire against this global clock, not per-party clocks.

```gdscript
# Correct split-party pattern
Timekeeping.register_party("alpha")
Timekeeping.register_party("beta")
Timekeeping.advance_party_hours("alpha", 3)   # global clock = 3h
Timekeeping.advance_party_hours("beta", 5)    # global clock = 5h, boundary signals for hours 4–5
Timekeeping.sync_parties()                    # alpha brought up to 5h (global); no new signals
```

**Eager DB save:** Every `advance_*()` call automatically writes to `campaign_clock` via `_auto_save()` if a campaign is loaded. The session runner does NOT need to call `save_state()` explicitly after each advance — only when explicitly restoring from a snapshot.

**Day-cycle configuration (dawn/dusk hours):** Dawn and dusk hours default to 6 and 20 so `is_daylight()` and the `dawn()`/`dusk()` signals work correctly before any seasons system exists. The future seasons/weather system changes them by calling `set_day_cycle()`, which persists immediately:

```gdscript
# Seasons system shortens the day for winter
Timekeeping.set_day_cycle(8, 16)   # dawn at 08:00, dusk at 16:00
# is_daylight(), dawn signal, and dusk signal all update automatically.

# Do NOT manipulate _dawn_hour / _dusk_hour directly from outside Timekeeping —
# set_day_cycle() is the only public write path and it handles persistence.
Timekeeping._dawn_hour = 8   # BAD — bypasses _auto_save()
```

**Day-of-year and seasons:** `get_day_of_year()` returns a 1–364 value reset at each year boundary. This is what `CalendarSeasons` functions expect.

```gdscript
# GOOD — feed get_day_of_year() into CalendarSeasons
var day := Timekeeping.get_day_of_year()
var season := CalendarSeasons.get_season(day)
var climate_season := CalendarSeasons.get_climate_season(day, "south")

# BAD — deriving day-of-year manually
var total_days := Timekeeping.get_total_days()
var day_of_year := total_days % 364 + 1   # duplicates logic, breaks encapsulation
```

**`season_changed` signal:** Fires at the same time as `day_changed` when the clock crosses into a new season (days 1, 92, 183, and 274 of the year). Consumers that need to react to season changes (domain simulation, weather system, LLM context) connect to this signal rather than inspecting the season on every `day_changed`.

```gdscript
# GOOD — connect once, react to season changes
func _ready() -> void:
    Timekeeping.season_changed.connect(_on_season_changed)

func _on_season_changed(new_season: String) -> void:
    _update_agricultural_phase(new_season)

# BAD — checking season on every day change
func _on_day_changed(_d, _m, _y) -> void:
    var season := CalendarSeasons.get_season(Timekeeping.get_day_of_year())
    if season != _last_season:  # manually tracking transitions the signal already handles
        _update_agricultural_phase(season)
        _last_season = season
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

<!-- Confirmed across all types — 2026-03-27, updated 2026-03-28 -->

**All shared types:**

| Type | Purpose | `from_dict` | `to_dict` |
|---|---|---|---|
| `ActionPayload` | Action vocabulary entry (actor, action, params) | Yes | No |
| `CharacterData` | PC/henchman/NPC stat block + runtime spell/effect state | Yes | Yes |
| `ConditionCatalog` | Loads condition_catalog.json; provides mechanical effect queries | No | No |
| `DamageResistance` | Per-entity immunity/resistance/vulnerability, source-tracked | No | No |
| `DamageTypes` | Static damage type constants (PHYSICAL, FIRE, COLD, …) | No | No |
| `EncounterData` | Encounter group descriptor | Yes | No |
| `EntityFlags` | Multi-source boolean state flags (can_fly, is_invisible, …) | No | No |
| `EventPayload` | Domain/exploration event | Yes | No |
| `HexMapData` | Hex map container with fog states | Yes | No |
| `HexTerrainData` | Terrain tags for a single hex | Yes | No |
| `InventoryItem` | Item with quantity, encumbrance, damage_type, material | Yes | Yes |
| `ModifierContainer` | Per-entity facade managing ModifierStacks for all stats | No | No |
| `ModifierStack` | Ordered modifier list for one stat; stacking/priority/floor/ceiling | No | No |
| `ResponseEnvelope` | LLM response wrapper | Static factories | No |
| `RollResult` | Resolved dice roll with all metadata | No | Yes |

**Serialisation rules:**
- Types persisted to DB **must** have `to_dict() -> Dictionary`. Booleans convert to 0/1 integers.
- Types constructed from DB rows or JSON **must** have `static func from_dict(data: Dictionary) -> ClassName` using `.get(key, default)` for resilience.
- Read-only runtime types (HexTerrainData, EncounterData) may omit `to_dict()`.
- All shared types use `class_name ClassName` and `extends RefCounted`.

**Runtime-only fields on persistent types:** Some shared types have both persistent fields (serialized via `to_dict`/`from_dict`) and runtime-only fields (never serialized). Runtime-only fields are rebuilt from active game state on load.

```gdscript
# CharacterData — persistent fields go through from_dict/to_dict
# Runtime-only fields are declared separately; from_dict does NOT touch them
var modifiers: ModifierContainer = ModifierContainer.new()   # runtime only
var flags: EntityFlags = EntityFlags.new()                   # runtime only
var damage_resistances: DamageResistance = DamageResistance.new()  # runtime only
var temp_hp: int = 0                                         # runtime only

# Comment in to_dict():
# Runtime-only fields (modifiers, flags, damage_resistances, temp_hp, mirror_images)
# are NOT included — they are rebuilt from active_effects on load.
```

The `active_effects` table is the source of truth for runtime state. On session load, the spell resolution system reads `active_effects`, reconstructs `modifiers`/`flags`/`damage_resistances`, and restores them to the correct `CharacterData` instances.

**Separately-loaded arrays on CharacterData:** Some arrays are not in `from_dict`/`to_dict` because they come from separate DB tables. After calling `from_dict()`, the caller makes a second query and assigns directly:

```gdscript
# proficiencies: loaded from character_proficiencies table, NOT via from_dict
var proficiencies: Array = []   # assigned after load via get_character_proficiencies()

# After loading a character, apply proficiency effects to rebuild modifier state:
character.proficiencies = CampaignRepository.get_character_proficiencies(character.id)
var resolver := ProficiencyEffectResolver.new(proficiency_registry)
resolver.apply_proficiency_effects(character)
```

Proficiency modifiers live in the same `ModifierContainer` as spell modifiers. They use `source_id` prefix `"proficiency:<key>"` (or `"proficiency:<key>:<spec>"` for specializations). This prefix is what lets `ProficiencyEffectResolver` clear and rebuild only its own contributions without disturbing spell modifiers.

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

<!-- Confirmed 2026-03-27 — 19 roll types defined in OverrideManager and used by DiceSystem. 2026-03-28: starting_spell added (RepertoireEngine d12 starting repertoire rolls). -->

Roll types are snake_case strings identifying the mechanical purpose of a dice roll. Used by the override queue (GameState.dice_overrides) and the roll log (dice_rolls table). Canonical list defined in `override_manager.gd` header comment and mirrored in `override_panel.gd::ROLL_TYPES`.

**Player-facing rolls** (prompted in PHYSICAL/HYBRID mode — use `DiceSystem.player_roll()`):
`player_surprise_check`, `initiative`, `attack_throw`, `damage_roll`, `saving_throw_petrification`, `saving_throw_poison`, `saving_throw_blast`, `saving_throw_wands`, `saving_throw_spells`, `thief_skill_throw`, `proficiency_throw`, `mortal_wound_roll`, `tampering_with_mortality`

**GM/digital-only rolls** (never prompted — use `DiceSystem.roll_digital()`):
`encounter_check`, `monster_surprise_check`, `morale_check`, `reaction_roll`, `domain_event_roll`, `hijink_roll`, `starting_spell`

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
| Calendar | 13 months × 28 days = 364 days/year. Weeks = 7 days. Months stored as int 1–13. | Design brief |
| Time granularities | Round=10s, Minute=6 rounds, Turn=60 rounds (10 min), Hour=360 rounds, Day=8640 rounds. | ACKS Adventures |
| Dawn/dusk hours | Default dawn=6, dusk=20. `is_daylight()` = `hour >= dawn and hour < dusk`. Changed at runtime via `Timekeeping.set_day_cycle(dawn, dusk)` — the seasons/weather system calls this; defaults hold before that system is built. | Design brief |
| Seasons | 4 seasons × 91 days: Spring=days 1–91, Summer=92–182, Autumn=183–273, Winter=274–364. Use `Timekeeping.get_day_of_year()` (returns 1–364) and `CalendarSeasons.get_season()`. | `gdd-calendar-seasons.md` |
| Climate vs. calendar season | For weather, domain, and mechanical effects: call `CalendarSeasons.get_climate_season(day, hemisphere)`. Southern-hemisphere campaigns invert the climate mapping. Narrative/LLM may use `get_season()` for cultural season names. | `gdd-calendar-seasons.md` |
| Solstices and equinoxes | Fall at season midpoints, not boundaries. Constants in `CalendarConstants`: VERNAL_EQUINOX_DAY=46, SUMMER_SOLSTICE_DAY=137, AUTUMNAL_EQUINOX_DAY=228, WINTER_SOLSTICE_DAY=319. | `gdd-calendar-seasons.md` |
| Max party size | 8 PCs. | Design brief |
| Henchmen per PC | Determined by CHA modifier + 4. | `acore_basics_and_characters.xml` |
| Three character tiers | `full` (PCs), `named` (henchmen/recurring NPCs), `transient` (throwaway). | Design brief |
| Three character types | `pc`, `henchman`, `npc`. Stored as TEXT with CHECK constraint. | `db/schema.sql` |
| Encumbrance unit | 1/1000-stone (1000 units = 1 stone). Column: `encumbrance_units`. Standard item = 167 units (~1/6 stone); coin/gem = 1 unit; 1 stone = 1000 units exactly. Migration 014. | 2026-04-01 |
| Inventory slots | 15 valid values: `hands_main`, `hands_off`, `body`, `head`, `belt`, `feet`, `hands_worn`, `cloak`, `accessory_1`–`accessory_5`, `pack`, `mount`. Enforced by CHECK constraint (migration 013). | migrations 011/013 |
| Clothing encumbrance | Equipped clothing (`item_category = "clothing"`) and items in `accessory_N` slots weigh **0** — they are worn and do not encumber. Armor remains weighted even when worn. Items in `pack` always count. Logic in `EncumbranceCalculator.calculate_item_encumbrance()`. | 2026-04-01 |
| Clothing slot routing | Clothing items route to slots by `item_key` pattern, not a shared "body" catch-all: `belt_*`→`belt`, `boots/sandals`→`feet`, `gloves/gauntlets`→`hands_worn`, `hat/skullcap/veil`→`head`, `cloak_*`→`cloak`, everything else→`body`. Armor always routes to `body`. Logic in `cs_tab_equipment.gd:_determine_equip_slot()`. | 2026-04-01 |
| Fog of war states | `HIDDEN` → `EXPLORED` → `VISIBLE`. Never transition backwards. | `hex_map_data.gd` |
| Three dice modes | `DIGITAL`, `PHYSICAL`, `HYBRID` (default). Persisted in `user://settings.cfg`. | Design brief §8.4 |
| HD minimum | CON penalty cannot reduce any single hit die roll below 1. Apply `maxi(roll + con_mod, 1)` per die. | ACKS Core |
| Prime req minimum | Must have >= 9 in each prime requisite to qualify for a class. | ACKS Core |
| XP adjustment | Uses LOWEST prime requisite score: 16+ → +10%, 13-15 → +5%, 9-12 → 0%, 6-8 → -5%, 3-5 → -10%. | ACKS Core |
| Ability trade | 2 points from source → 1 point to prime req. Cannot lower CON, CHA, or another prime req. No score below 9. | ACKS Core |
| Saving throw order | petrification/paralysis, poison/death, blast/breath, staffs/wands, spells. | ACKS Core |
| Modular powers | Class abilities stored as reusable power definitions (`data/powers/`) referenced by ID. Class JSONs hold progression tables. Characters get stamped copies in `character_powers` table. | Phase C-1 design |
| Class data format | One JSON per class in `data/classes/`. ClassRegistry loads all on init. 25 classes total. | Phase C-1 |
| Class weapon/armor permission tags | `weapon_permissions` and `armor_permissions` in class JSONs may be **direct item_keys** (e.g. `"dagger"`, `"chain_mail"`) OR **semantic category tags**. Resolver lives in `equipment_shop_panel.gd:_get_restriction_warning()`. Semantic weapon tags: `"piercing_melee"/"slashing_melee"` = non-blunt melee; `"any_one_handed_melee"/"all_one_handed_melee_weapons"/"all_except_oversized"` = melee without `two_handed` tag; `"any_missile"/"all_missile_weapons"` = ranged or thrown; `"all_axes"/"all_hammers"/"all_flails"/"all_maces"` = item_key substring match. Armor tier tags: `"leather_or_lighter"` ≤ AC 2, `"chain_mail_or_lighter"` ≤ AC 4, `"banded_or_lighter"` ≤ AC 5. Short armor aliases (`"leather"`, `"hide"`, `"chain"`) are normalized to canonical item_keys. Mixed lists (semantic + item_keys) are supported — any matching entry permits the item. | 2026-04-01 |
| Class slot_type values | Proficiencies saved to DB must use `slot_type` of `"class"` or `"general"` (CHECK constraint). Bonus proficiencies from barbarian regional origins and witch traditions are class-granted and use `"class"`. Language proficiencies use `"general"`. | 2026-04-01 |
| Registries are RefCounted | `PowerRegistry`, `ClassRegistry`, `ProficiencyRegistry`, `SpellRegistry`, `RepertoireEngine`, `SpellEffectRegistry`, `ConditionCatalog` are instantiated by consumers, NOT autoloads. | Phase C-1/C-2 |
| Damage type strings | Always use `DamageTypes` constants (`DamageTypes.FIRE`), never raw strings (`"fire"`). Exception: `DamageTypes.UNTYPED` bypasses all immunity and resistance — use for guaranteed-landing damage. | Phase 0C |
| Modifier stacking | Modifiers in the same named `stacking_group` only apply the highest-value entry (ACKS: same bonus type does not stack). Empty `stacking_group` = stacks freely with all others. Always specify the group when the modifier has a bonus type (protection, morale, luck, etc.). | Phase 0A |
| Effective getters are mandatory | All code that reads a character stat must call `get_effective_*()` on `CharacterData`, never raw fields. Raw fields (`armor_class`, `attack_throw`, etc.) are the base value before spells/items. `get_effective_ac()` returns base + all active modifier stacks. | Phase 1A |
| CharacterData runtime state | `modifiers`, `flags`, `damage_resistances`, `temp_hp`, `mirror_images` are runtime-only. They are NOT in `to_dict()`/`from_dict()`. They are rebuilt from the `active_effects` table on session load. Do NOT serialize them. | Phase 1A |
| Conditions use ConditionCatalog | Never hardcode condition mechanical effects (ac_modifier, prevents_casting, etc.). Always query `ConditionCatalog` by condition key. Source of truth: `data/conditions/condition_catalog.json` (extracted from ax_conditions_catalog.xml — sacred). | Phase 0D |
| Active effects are source of truth | `active_effects` table is the persisted record of what spell effects are currently active. `ActiveEffectTracker` is the runtime view. On session load, the spell resolution engine reads `active_effects` and reconstructs runtime state. | Phase 2A |
| Proficiency effects are permanent | Proficiency modifiers/flags are permanent — they do NOT go through `ActiveEffectTracker`. Apply with `ProficiencyEffectResolver.apply_proficiency_effects(character)` after loading proficiencies. Call again after any proficiency change. The resolver is idempotent. | Phase proficiency |
| Proficiency compound keys | Class JSONs use compound keys like `"combat_trickery_disarm"` or `"fighting_style_missile"`. `ProficiencyRegistry` resolves these to the base catalog key by progressive prefix stripping. Always call `has_proficiency(key)` or `get_proficiency(key)` — never hard-code the lookup. | Phase proficiency |
| Proficiency source IDs | Proficiency modifiers use source IDs `"proficiency:<key>"` (unique/stacking proficiencies) or `"proficiency:<key>:<spec>"` (specialization proficiencies, e.g., `"proficiency:fighting_style:missile"`). Spell modifiers use `"spell:<key>"`. The prefixes prevent cross-system contamination in `ModifierContainer`. | Phase proficiency |
| Conditional proficiency effects | Proficiency effects with a `"condition"` field in the catalog are NOT applied at load time. The consuming system (combat, exploration, etc.) reads the catalog and evaluates the condition at runtime. Only unconditional effects are applied by `ProficiencyEffectResolver`. | Phase proficiency |

---

## 13. UI Panel Conventions

<!-- Added 2026-03-27 from OverridePanel and DicePrompt patterns -->

### 13.1 CanvasLayer Stacking

UI panels that overlay the game use CanvasLayer nodes with explicit layer assignments. Higher numbers draw on top.

| Layer | Purpose | Example |
|---|---|---|
| 0 | Normal game content | Default |
| 10 | Map HUD (tooltips, coordinates) | HexHUD in hex_map_renderer.gd |
| 32 | Full-screen wizard flows | CharacterCreationScreen |
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

### 13.3 Reusable Panel Setup Must Fully Reset UI State

<!-- Added 2026-04-02 after EquipmentShopPanel state-reset bug fix -->

Panels reused across a multi-step flow (for example character-creation steps that persist in the scene tree and receive repeated `setup(state, ...)` calls) must treat `setup()` as a full UI rehydration pass, not a delta update.

- Recompute button visibility and `disabled` state from backing data every time `setup()` runs.
- Clear stale transient UI text (`status_label`, warnings, in-progress flags) when the backing state no longer supports it.
- Refresh both the "complete" and "incomplete" content paths so placeholder text replaces stale rows when prerequisite state is cleared.
- If a fresh state should look like a fresh screen, reset tab/selection widgets there rather than relying on node construction to do it once.

### 13.4 Scene Tree — Main.tscn

<!-- Updated 2026-03-27 -->

```
Main (Node, script: main_scene.gd)
├── HexMapController (Node, script: hex_map_controller.gd)
├── HexMap (instance of hex_map.tscn)
├── OverrideManager (Node, script: override_manager.gd)
├── OverridePanel (instance of override_panel.tscn)
├── DicePrompt (instance of dice_prompt.tscn)
└── CharacterCreationScreen (instance of character_creation_screen.tscn, CanvasLayer 32)
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

---

## 13. Tactical Grid Conventions (D-4+)

<!-- Added 2026-04-02 for dungeon grid and future combat maps -->

### 13.1 CellData Schema

Cells are stored as `Dictionary` in `TacticalMapData._cells` keyed by `Vector2i(col, row)`. String-based fields allow the vocabulary to grow across dungeon/combat/stronghold contexts without schema migrations.

| Field | Type | Notes |
|---|---|---|
| `terrain_feature` | String | `"open"`, `"rock"`, `"wall_stone"`, `"wall_wood"`, `"door"`, `"door_locked"`, `"door_secret"`, `"portcullis"`, `"stairs_up"`, `"stairs_down"` (combat extends with `"tree"`, `"boulder"`, etc.) |
| `passable` | bool | Derived from terrain_feature + door_state; do not set manually — use `set_door_state()` |
| `blocks_los` | bool | Derived; portcullis blocks movement but NOT LOS |
| `elevation` | int | 0-30 (each unit = 2.5 ft); 0 for flat dungeon levels |
| `surface_type` | String | `"stone"`, `"dirt"`, `"wood"` — drives tile variant |
| `door_state` | String | `""` (not a door), `"open"`, `"closed"`, `"locked"`, `"stuck"` |
| `door_type` | String | `""`, `"arch"`, `"unlocked"`, `"locked"`, `"trapped"`, `"secret"`, `"portcullis"` |
| `door_detected` | bool | For secret doors: false until found by search check |
| `room_id` | int | -1 for corridors, walls, void |
| `is_corridor` | bool | True for corridor cells vs room cells |
| `cover_value` | int | 0-4 (future combat ranged modifier) |

**Never add a CHECK constraint on `door_state`** — vocabulary expands (spiked, barred, etc.). Validate in code.

### 13.2 Isometric Grid Math

`IsometricGrid` (static class, `engine/shared_types/isometric_grid.gd`) is the canonical source for diamond-grid math. `CELL_W=64, CELL_H=32, HALF_W=32, HALF_H=16`.

```
screen_x = (col - row) * 32
screen_y = (col + row) * 16
```

All coordinate conversion, adjacency, and radius queries must go through `IsometricGrid`. Never inline diamond math in renderer or controller code.

### 13.3 FogState Transitions

```
HIDDEN → VISIBLE   (room entered for the first time; all room cells + boundary revealed)
VISIBLE → EXPLORED (party leaves room; room cells dim)
EXPLORED → VISIBLE (party re-enters room)
```

Fog is stored per-`TacticalMapData` instance. Multi-level dungeons store each level separately in `DungeonMapController._all_levels: Dictionary` (int → TacticalMapData).

### 13.4 Dungeon JSON Format

Multi-level dungeons use a `levels` array + `stairs` array at the top level:
```json
{
  "id": "...", "name": "...", "theme": "...", "tileset_group": "...",
  "levels": [{"level": 1, "grid_width": N, "grid_height": N, "entry_col": C, "entry_row": R, "cells": [...]}],
  "stairs": [{"from_level": 1, "from_col": C, "from_row": R, "to_level": 2, "to_col": C, "to_row": R}]
}
```

`TacticalMapData.load_from_file()` handles both single-level and multi-level formats (reads `levels[0]`). `DungeonMapController.load_dungeon()` handles all levels.

### 13.5 Secret Door Dev Visibility

During D-4 development, undetected secret doors (`door_detected = false`) are rendered with a **dark grey fill + white "S" icon** instead of looking identical to walls. This is intentional dev-mode behavior to allow placement verification. A `DEV_SHOW_SECRET_DOORS` constant in the renderer (or a future build flag) will hide this in production.

### 13.6 Multi-Level Controller Pattern

`DungeonMapController` is NOT an autoload. Instantiate dynamically in `main_scene.gd._enter_dungeon()`, add as child, call `load_dungeon()`, then pass to the dungeon scene via `setup(controller)`. The controller is freed when the dungeon scene is popped from NavigationStack (via `queue_free` on the scene's `exit()`).

*Last major update: 2026-04-02 — D-4 dungeon grid. Updated directory tree (§2.1), migration list to 017, maps/ entry, added §13 (tactical grid conventions).*
