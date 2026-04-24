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

Eight autoloads exist (see Section 5). Reference them by their PascalCase name directly.

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

### 1.10 Avoid Reserved Keyword Identifiers

Do not use GDScript keywords or parser-significant identifiers as local variable names, parameter names, or fields when there is a clear alternative. In particular, avoid names like `class`, `class_name`, and other script-header keywords even in inner scope, because they can trigger misleading parse failures that make unrelated classes appear unresolved.

```gdscript
# GOOD
var class_display_name := class_registry.get_class_display_name(class_id, sex)
var stored_class_key := character.character_class

# BAD
var class_name := class_registry.get_class_display_name(class_id, sex)
var class := character.character_class
```

<!-- Updated 2026-04-07: Godot 4 enum typing constraint -->

**Godot 4 enum typing constraint:** Do NOT use an enum type as a variable type annotation when the enum is defined in the same class or referenced across classes. Godot 4's parser rejects `var side: Side = Side.PARTY` and `param: Combatant.Side`. Use `int` instead and assign the enum constant as the default value. The enum constants themselves (`Side.PARTY`, `Combatant.Side.ENEMY`) work fine as values.

```gdscript
# GOOD — use int for the type, enum constant for the value
enum Side { PARTY, ENEMY }
var side: int = Side.PARTY

func get_alive_on_side(target_side: int) -> Array:
    ...

# BAD — causes parse error in Godot 4
var side: Side = Side.PARTY                       # parse error
func get_alive_on_side(target_side: Combatant.Side):  # parse error
```

---

## 2. File Organization

### 2.1 Engine Directory Structure

<!-- Updated 2026-04-02 to reflect D-4 dungeon/tactical grid system -->

```
acks-arbiter/               (Godot project root = repo root)
├── project.godot           # Autoload registrations, input map
├── engine/
│   ├── autoloads/          # Nine global singletons (see §5.1)
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
│   │   ├── hex_overlay_data.gd
│   │   ├── hex_terrain_data.gd
│   │   ├── inventory_item.gd       # + damage_type, material fields
│   │   ├── isometric_grid.gd       # static diamond-grid math (cell↔screen, neighbors, radius)
│   │   ├── modifier_container.gd   # per-entity facade over ModifierStacks
│   │   ├── modifier_stack.gd       # ordered modifier list for a single stat
│   │   ├── response_envelope.gd
│   │   ├── roll_result.gd
│   │   ├── voxel_cell.gd           # 5' cube cell for 3D voxel grid; VoxelCell
│   │   ├── voxel_grid.gd           # static 3D grid math (cell↔world, 26-neighbor adjacency); VoxelGrid
│   │   └── voxel_map_data.gd       # sparse 3D voxel storage (Dictionary[Vector3i, VoxelCell]); VoxelMapData
│   └── subsystems/
│       ├── calendar/       # CalendarConstants, CalendarSeasons (pure static computation)
│       ├── characters/     # PowerRegistry, ClassRegistry, ProficiencyRegistry, ProficiencyEffectResolver,
│       │                   #   AbilityUtils, EncumbranceCalculator, CharacterGenerator
│       ├── navigation/     # NavigationStack (not autoload; placed in Main.tscn)
│       ├── override/       # OverrideManager (dev-mode state manipulation)
│       ├── spells/         # SpellRegistry, RepertoireEngine, ActiveEffectTracker, SpellEffectRegistry
│       ├── monsters/       # MonsterRegistry (loads data/monsters/monster_catalog.json)
│       ├── combat/         # Combatant, CombatRoster, InitiativeResolver, AttackResolver, CombatController,
│       │                   # SpellCombatHooks, RangedAttackResolver, CombatConditionManager,
│       │                   # MonsterAI, MoraleResolver, CleaveResolver, CombatFinalizer,
│       │                   # MovementResolver (2D + 3D voxel methods), ManeuverResolver,
│       │                   # MortalWoundsResolver, CombatLog, FallingResolver
│       ├── exploration/    # HexMapController, DungeonMapController, DungeonEncounterSpawner,
│       │                   # FormationManager, DungeonOrderManager
│       ├── presentation/   # VisibilityManager (focus level + per-level opacity), VoxelLOS (3D DDA raycast)
│       ├── domain/         # (planned)
│       └── magic/          # (planned)
├── scenes/
│   ├── Main.tscn           # Root scene (instantiates all children)
│   ├── main_scene.gd       # Test harness wiring
│   ├── maps/               # hex_map.tscn, hex_map_renderer.gd,
│   │                       # dungeon_map_3d.tscn, dungeon_map_renderer_3d.gd,
│   │                       # dungeon_order_overlay.gd, dungeon_selection_panel.gd
│   └── ui/
│       ├── override/       # override_panel.gd / .tscn
│       ├── dice/           # dice_prompt.gd / .tscn
│       ├── combat/         # CombatScreen, CombatMapRenderer, CombatUIController,
│       │                   # DungeonCombatOverlay, InitiativeStrip, StatSummary,
│       │                   # ActionButtonPanel, CombatLogPanel, DeclarationOverlay,
│       │                   # CombatEndOverlay
│       ├── character_creation/  # 9-step PC creation wizard panels
│       └── components/     # Reusable UI: character_sheet_panel.gd, combatant_token.gd
├── tests/                  # All test scripts + test_runner.tscn
├── db/
│   ├── schema.sql          # Canonical schema (update after every migration)
│   └── migrations/         # 001_initial_schema .. 036_voxel_grid
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
│   ├── monsters/           # monster_catalog.json (13 starter monsters; F-0)
│   ├── test_hex_map.json   # Test hex map data (31-hex Ashford Vale)
│   └── test_dungeon.json   # Test dungeon data (Goblin Warrens, voxel format)
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

<!-- Updated 2026-04-08 after character-creation starting-gold regression fix -->

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

**UI roll-handler rule:** When a Control method awaits `DiceSystem.player_roll()`, keep the awaited method thin and move post-roll state mutation into a synchronous helper. This lets plain `run_all_tests()` suites cover the resolved state path without adding async-only test harness code.

**Signal-race rule:** When a coroutine needs to wait on multiple terminal signals, use a dedicated helper object with bound-method listeners instead of anonymous closures so the waiting state, disconnect cleanup, and first-signal-wins behavior stay testable and deterministic.

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
Combat, Exploration, Character, Domain, Magic, Damage, LLM/Narration, Persistence, Override system, Dice system, Commerce/Economy.

---

## 5. Autoload Rules

### 5.1 The Nine Autoloads

<!-- 2026-03-25: EventBus added. 2026-03-27: DiceSystem added (approved by Jedidiah — dice needed by every subsystem). 2026-03-27: Timekeeping added (approved by Jedidiah — clock consumed by session runner, domain, encounter, and condition subsystems). 2026-04-17: PartyWallet added (Session 1). LocationCacheManager added (Session 2). -->

Nine autoload singletons exist. This list requires **explicit approval from Jedidiah** to extend. The bar is "needed by every subsystem" — if only one or two callers use it, make it a scene-local node instead.

| Autoload | Responsibility | Lives in |
|----------|---------------|----------|
| `GameState` | Session state machine, dice mode, settings persistence, `current_location_key` bridge | `engine/autoloads/game_state.gd` |
| `EventBus` | Cross-subsystem signal bus (45+ signals, all past-tense) | `engine/autoloads/event_bus.gd` |
| `CampaignRepository` | All SQLite read/write, migration runner, ID generation | `engine/autoloads/campaign_repository.gd` |
| `LLMManager` | Provider routing, request/response, token tracking (stub) | `engine/autoloads/llm_manager.gd` |
| `AudioRouter` | SFX/music playback, audio bus management (stub) | `engine/autoloads/audio_router.gd` |
| `DiceSystem` | Dice rolling (digital/physical/hybrid), override consumption, roll log | `engine/autoloads/dice_system.gd` |
| `Timekeeping` | Passive in-game clock, multi-party sync, dawn/dusk/day/month boundary signals | `engine/autoloads/timekeeping.gd` |
| `PartyWallet` | Gold aggregation and auto-deduction across party PCs. Wraps CampaignRepository coin methods. | `engine/subsystems/commerce/party_wallet.gd` |
| `LocationCacheManager` | Location-scoped inventory caches (loose/locked/hidden). Decay and raid resolution. | `engine/subsystems/inventory/location_cache_manager.gd` |

**Load order matters.** DiceSystem depends on GameState, EventBus, and CampaignRepository. Timekeeping depends on GameState (session_ended signal) and CampaignRepository (DB access) — both must be registered before it in `project.godot`. PartyWallet depends on CampaignRepository, EventBus, and GameState. LocationCacheManager depends on CampaignRepository, EventBus, GameState, Timekeeping, and DiceSystem — all must be registered before it.

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

<!-- Added 2026-03-27 after Timekeeping autoload build; updated 2026-04-14 for scheduler-driven advancement -->

**Passive clock:** `Timekeeping` never ticks on its own. The EventScheduler (via `SchedulerLoop`) advances it by calling `Timekeeping.advance_party_rounds()` as the clock reaches each event's timestamp. No background timer, no `_process()`. Direct `advance_hours()` calls from the session runner are superseded by scheduler-driven advancement — see §19 (Event Scheduler Conventions) for the full pattern.

**Advance methods emit boundary signals automatically:**

```gdscript
# GOOD — scheduler advances time to the next event timestamp
# (SchedulerLoop handles this automatically via advance_party_rounds)
var delta = next_event.fire_time - Timekeeping.get_party_rounds(party_id)
Timekeeping.advance_party_rounds(party_id, delta)
# Boundary signals (day_changed, month_changed, dawn, dusk) fire automatically

# BAD — direct advance_hours() bypasses the scheduler
Timekeeping.advance_hours(8)  # only acceptable in test setup, not game code

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
| `HexOverlayData` | River/road edge overlay data for a single hex | Yes | Yes |
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

<!-- Confirmed 2026-03-27 — 19 roll types defined in OverrideManager and used by DiceSystem. 2026-03-28: starting_spell added (RepertoireEngine d12 starting repertoire rolls). 2026-04-07: encounter_number and reaction added (SessionRunner encounter generation). -->

Roll types are snake_case strings identifying the mechanical purpose of a dice roll. Used by the override queue (GameState.dice_overrides) and the roll log (dice_rolls table). Canonical list defined in `override_manager.gd` header comment and mirrored in `override_panel.gd::ROLL_TYPES`.

**Player-facing rolls** (prompted in PHYSICAL/HYBRID mode — use `DiceSystem.player_roll()`):
`player_surprise_check`, `initiative`, `attack_throw`, `damage_roll`, `saving_throw_petrification`, `saving_throw_poison`, `saving_throw_blast`, `saving_throw_wands`, `saving_throw_spells`, `thief_skill_throw`, `proficiency_throw`, `mortal_wound_roll`, `tampering_with_mortality`

**GM/digital-only rolls** (never prompted — use `DiceSystem.roll_digital()`):
`encounter_check`, `encounter_number`, `monster_surprise_check`, `morale_check`, `reaction`, `reaction_roll`, `domain_event_roll`, `hijink_roll`, `starting_spell`, `cache_raid_roll`, `cache_raid_loss`, `cache_decay_timer`

- `cache_raid_roll` — 1d100 vs accumulated monthly modifier (hidden wilderness caches)
- `cache_raid_loss` — 2d4 for loss percentage curve (25%–75% value)
- `cache_decay_timer` — 1d4 or 1d7 for ephemeral cache decay day offset

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

Example for a subsystem that wraps another autoload:

```gdscript
# engine/subsystems/commerce/party_wallet.gd
#
# Dependencies:
#   - CampaignRepository (autoload): coin read/write, character queries
#   - EventBus (autoload): emits wallet_paid, wallet_deposited, wallet_changed
#   - Currency (subsystem): coins_to_cp conversion
#   - CharacterData (shared_type): character_type filtering
#
# Signals emitted (via EventBus):
#   - wallet_paid(party_id: String, details: Dictionary)
#   - wallet_deposited(party_id: String, details: Dictionary)
#   - wallet_changed(party_id: String)
#
# Signals consumed:
#   - (none — callers invoke methods directly)
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
| Equip-time stack handling | All equip paths (character sheet, party-inventory right-click, shop auto-equip) must dispatch on `CSTabEquipment.is_thrown_stackable(item, catalog)`. Thrown weapons and dart bundles (item_category `weapon`/`ammunition` with `"thrown"` tag) keep their full stack in the slot — throwing decrements them in combat. Everything else splits one unit off the stack (via `CampaignRepository.split_item_for_equip()`) so only a single item ends up equipped. | 2026-04-22 |
| Thrown self-ammo expenditure | `Combatant.consume_ammo()` (called from `combat_controller._resolve_ranged_action`) dispatches by equipped weapon: thrown weapon (cat `weapon`, tag `thrown`) decrements `_equipped_weapon["quantity"]`; dart bundle (cat `ammunition`, tag `thrown`) decrements `_equipped_weapon["uses_remaining"]`; otherwise decrements the separate `_equipped_ammo` row. Empty rows are deleted and `_equipped_weapon` is cleared, leaving the slot vacant. `wire_equipment()` populates `_equipped_weapon` for both `weapon` and thrown-tagged `ammunition` rows in `hands_main`, and skips re-wiring the same row into `_equipped_ammo`. | 2026-04-22 |
| Fog of war states | `HIDDEN` → `EXPLORED` → `VISIBLE`. Never transition backwards. | `hex_map_data.gd` |
| Hex edge numbering | 0–5 clockwise from North. 0=N, 1=NE, 2=SE, 3=S, 4=SW, 5=NW. Flat top = North. Opposite edge = `(n+3) % 6`. Display compass names in UI, use numeric internally. | `hex_overlay_data.gd` |
| Hex water types | `water` field: `""` (none), `"ocean"`, `"lake"`. Rivers are **overlays** (edge-to-edge), not full-hex terrain. One river + one road per hex max. | `hex_terrain_data.gd`, migration 020 |
| Three dice modes | `DIGITAL`, `PHYSICAL`, `HYBRID` (default). Persisted in `user://settings.cfg`. | Design brief §8.4 |
| HD minimum | CON penalty cannot reduce any single hit die roll below 1. Apply `maxi(roll + con_mod, 1)` per die. | ACKS Core |
| Prime req minimum | Must have >= 9 in each prime requisite to qualify for a class. | ACKS Core |
| XP adjustment | Uses LOWEST prime requisite score: 16+ → +10%, 13-15 → +5%, 9-12 → 0%, 6-8 → -5%, 3-5 → -10%. | ACKS Core |
| Ability trade | 2 points from source → 1 point to prime req. Cannot lower CON, CHA, or another prime req. No score below 9. | ACKS Core |
| Saving throw order | petrification/paralysis, poison/death, blast/breath, staffs/wands, spells. | ACKS Core |
| Modular powers | Class abilities stored as reusable power definitions (`data/powers/`) referenced by ID. Class JSONs hold progression tables. Characters get stamped copies in `character_powers` table. | Phase C-1 design |
| Class data format | One JSON per class in `data/classes/`. ClassRegistry loads all on init. 25 classes total. | Phase C-1 |
| Optional class display/restriction metadata | Class JSONs may include runtime-only UI metadata such as `sex_restriction`, `display_name_generic`, `display_name_male`, and `display_name_female`. Keep `class_id` as the canonical stored key and resolve display copy through `ClassRegistry` helpers instead of rewriting saved class IDs. | 2026-04-10 |
| Class weapon/armor permission tags | `weapon_permissions` and `armor_permissions` in class JSONs may be **direct item_keys** (e.g. `"dagger"`, `"chain_mail"`) OR **semantic category tags**. Resolver lives in `equipment_shop_panel.gd:_get_restriction_warning()`. Semantic weapon tags: `"piercing_melee"/"slashing_melee"` = non-blunt melee; `"any_one_handed_melee"/"all_one_handed_melee_weapons"/"all_except_oversized"` = melee without `two_handed` tag; `"any_missile"/"all_missile_weapons"` = ranged or thrown; `"all_axes"/"all_hammers"/"all_flails"/"all_maces"` = item_key substring match. Armor tier tags: `"leather_or_lighter"` ≤ AC 2, `"chain_mail_or_lighter"` ≤ AC 4, `"banded_or_lighter"` ≤ AC 5. Short armor aliases (`"leather"`, `"hide"`, `"chain"`) are normalized to canonical item_keys. Mixed lists (semantic + item_keys) are supported — any matching entry permits the item. | 2026-04-01 |
| Class slot_type values | Proficiencies saved to DB must use `slot_type` of `"class"` or `"general"` (CHECK constraint). Bonus proficiencies from barbarian regional origins and witch traditions are class-granted and use `"class"`. Language proficiencies use `"general"`. | 2026-04-01 |
| Registries are RefCounted | `PowerRegistry`, `ClassRegistry`, `ProficiencyRegistry`, `SpellRegistry`, `RepertoireEngine`, `SpellEffectRegistry`, `ConditionCatalog` are instantiated by consumers, NOT autoloads. | Phase C-1/C-2 |
| Damage type strings | Always use `DamageTypes` constants (`DamageTypes.FIRE`), never raw strings (`"fire"`). Exception: `DamageTypes.UNTYPED` bypasses all immunity and resistance — use for guaranteed-landing damage. | Phase 0C |
| Modifier stacking | Modifiers in the same named `stacking_group` only apply the highest-value entry (ACKS: same bonus type does not stack). Empty `stacking_group` = stacks freely with all others. Always specify the group when the modifier has a bonus type (protection, morale, luck, etc.). | Phase 0A |
| Effective getters are mandatory | All code that reads a character stat must call `get_effective_*()` on `CharacterData`, never raw fields. Raw fields (`armor_class`, `attack_throw`, etc.) are the base value before spells/items. `get_effective_ac()` returns base + all active modifier stacks. | Phase 1A |
| CharacterData runtime state | `modifiers`, `flags`, `damage_resistances`, `temp_hp`, `mirror_images` are runtime-only. They are NOT in `to_dict()`/`from_dict()`. They are rebuilt from the `active_effects` table on session load. Do NOT serialize them. | Phase 1A |
| Conditions use ConditionCatalog | Never hardcode condition mechanical effects (ac_modifier, prevents_casting, etc.). Always query `ConditionCatalog` by condition key. Source of truth: `data/conditions/condition_catalog.json` (extracted from ax_conditions_catalog.xml — sacred). | Phase 0D |
| Entity promotion | Animals (catalog `monster_id` present + category ≠ `livestock`) promote to `trained_creatures`. Vehicles (`item_category == "vehicle"`) promote to `draft_vehicles`. Livestock remains `inventory_items`. Every purchase path must route through `CampaignRepository.promote_inventory_to_entity()` — direct `add_inventory_item()` for an animal or vehicle is a bug. | `pack_animal_state_report.md` §1 |
| Active effects are source of truth | `active_effects` table is the persisted record of what spell effects are currently active. `ActiveEffectTracker` is the runtime view. On session load, the spell resolution engine reads `active_effects` and reconstructs runtime state. | Phase 2A |
| Proficiency effects are permanent | Proficiency modifiers/flags are permanent — they do NOT go through `ActiveEffectTracker`. Apply with `ProficiencyEffectResolver.apply_proficiency_effects(character)` after loading proficiencies. Call again after any proficiency change. The resolver is idempotent. | Phase proficiency |
| Proficiency compound keys | Class JSONs use compound keys like `"combat_trickery_disarm"` or `"fighting_style_missile"`. `ProficiencyRegistry` resolves these to the base catalog key by progressive prefix stripping. Always call `has_proficiency(key)` or `get_proficiency(key)` — never hard-code the lookup. | Phase proficiency |
| Proficiency source IDs | Proficiency modifiers use source IDs `"proficiency:<key>"` (unique/stacking proficiencies) or `"proficiency:<key>:<spec>"` (specialization proficiencies, e.g., `"proficiency:fighting_style:missile"`). Spell modifiers use `"spell:<key>"`. The prefixes prevent cross-system contamination in `ModifierContainer`. | Phase proficiency |
| Conditional proficiency effects | Proficiency effects with a `"condition"` field in the catalog are NOT applied at load time. The consuming system (combat, exploration, etc.) reads the catalog and evaluates the condition at runtime. Only unconditional effects are applied by `ProficiencyEffectResolver`. | Phase proficiency |
| Currency exchange rates | 1 PP = 5 GP = 500 CP; 1 GP = 10 SP = 100 CP; 1 EP = 5 SP = 50 CP; 1 SP = 10 CP. Order by value descending: PP > GP > EP > SP > CP. ACKS 1e Core p.36. | `currency.gd`, ACKS Core |
| Party gold aggregation | `PartyWallet` autoload wraps `CampaignRepository` coin methods to coordinate payments across PCs. Henchmen, creatures, and vehicles are never wallet contributors. Location filtering via `GameState.current_location_key` (v1: all PCs co-located). | `gdd-party-inventory.md` §3 |
| Gold float display | `GP: 242.35` summary format using `total_cp / 100.0`. PP and EP fold into the float at ACKS rates. Breakdown format `PP: 4 | GP: 200 | EP: 0 | SP: 20 | CP: 35` ordered by value descending. | GDD §3.2 |
| Encumbrance bands | Character: green ≤5000, yellow 5001–7000, orange 7001–10000, red 10001–max, flashing red over max (max = 20000 + STR_mod × 1000). Creature: green ≤ normal, red overload, rejected past max. | GDD §5 |
| Location caches | Ephemeral variants (dungeon/wilderness/settlement loose) decay per 1d7 days or 1d4 weeks. Persistent variants (locked container, hidden-memorized) don't decay. Hidden wilderness caches gain +1% monthly raid risk; raids use 2d4 curve (25%–75% value) and reset the modifier. | `gdd-party-inventory.md` §8 |
| Hide-and-memorize cost | 1 hour party time (6 turns via `Timekeeping.advance_party_turns`). No proficiency check. | GDD §8.3 |
| Transfer validation | All inventory transfers route through `PartyInventoryTransferValidator` (RefCounted, `class_name`). Returns `{ok, reason, warnings, resolved_slot}`. Coin transfers are blocked ("use Transfer Gold modal"). Equipped clothing is immovable. Cross-location transfers rejected. Draft-saddle creatures reject cargo (explicit check — `CreatureEquipmentService` doesn't catch this). Dungeon adjacency and combat trade action are stubs for v1. | `gdd-party-inventory.md` §4 |
| Party split/merge | Splits create a new party at the same hex via `CampaignRepository.split_party()`. Merges require co-location (same hex, same map) via `CampaignRepository.merge_parties()`. Timekeeping is synced on merge via `sync_parties()`. `GameState.active_party_id` tracks which party the player controls; switch via `GameState.set_active_party()`. Wilderness-only for v1. | `coding_conventions.md` §15.5, 2026-04-18 |
| Treasure XP | 1 XP per 1 GP of recovered coins, gems, jewelry, or special treasure. Awarded at the moment of distribution (modal Apply or Pick Up All). Equipment excluded until sell-for-XP system exists. Wired via `XPAwardCalculator.award_adventure_xp(monster_xp=0, treasure_xp=N, members)`. v1 simplification: XP awards on pickup, not "return to civilization." | `acore_adventures_and_encounters.xml`, 2026-04-18 |
| Dungeon loot placement | Defeated dungeon monsters' treasure lands in a `location_cache` at the leader's death cell (variant `"loose"`, `location_type = "dungeon_cell"`). Cache decay rules per GDD §8.2 apply. The cell flag `has_ground_items` enables the existing Loot/Pick Up All context menu options. The dungeon Loot action opens `LootDistributionModal.open_from_cache()`. | `gdd-party-inventory.md` §8, `gdd-dungeon-map-ui.md` §3.4, 2026-04-18 |

---

## 13. UI Panel Conventions

<!-- Added 2026-03-27 from OverridePanel and DicePrompt patterns -->

### 13.1 CanvasLayer Stacking

UI panels that overlay the game use CanvasLayer nodes with explicit layer assignments. Higher numbers draw on top.

| Layer | Purpose | Example |
|---|---|---|
| 0 | Normal game content | Default |
| 5 | Gameplay overlays (combat) | CombatScreen |
| 10 | Campaign select / map HUD | CampaignSelectScreen, HexHUD |
| 20 | Pre-game flow screens | PartyWelcomeScreen, PartyRosterScreen |
| 32 | Full-screen wizard flows | CharacterCreationScreen |
| 46 | Persistent party sidebar | PartyManagementOverlay |
| 48 | Character sheet sidebar | CharacterSheetOverlay |
| 50 | Party inventory overlay | PartyInventoryOverlay |
| 52 | Loot distribution modal | LootDistributionModal |
| 54 | Gold share modal | GoldShareModal |
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

### 13.4 Runtime TextureRect Sizing

<!-- Added 2026-04-02 after portrait native-size regressions in runtime-built UI -->

When a runtime-built UI creates a `TextureRect` for portrait or illustration assets, do not rely on `custom_minimum_size` alone to constrain display size. `TextureRect` will still honor the texture's native dimensions unless the expand mode is configured explicitly.

- For a fixed portrait box, set `expand_mode = TextureRect.EXPAND_IGNORE_SIZE`.
- Set an explicit display box with `custom_minimum_size` (for example `Vector2(512, 512)` for full character portraits or `Vector2(96, 96)` for thumbnails).
- Pair fixed-box portraits with `stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED` so oversized or non-square art scales to fit without distortion.
- Use this pattern in code-built panels where editor-side resizing will be recreated on each `setup()` or `display()` refresh.

### 13.5 Shared Vellum Window Chrome

<!-- Updated 2026-04-04 after class-selection button contrast fix -->

Runtime-built windows, overlays, and modal popups should use the shared `UiSurfaceStyles` helper instead of ad-hoc semi-transparent defaults.

- Use `UiSurfaceStyles.apply_textured_panel(panel)` for opaque parchment-backed `PanelContainer` surfaces that do not need a separate border frame.
- Use `UiSurfaceStyles.apply_framed_window_chrome(surface)` for modal windows and overlay panels that need both the `ui.bg.vellum_subtle` background and a visible frame border; `surface` may be either a `Control` panel or a `Window`-based popup/dialog.
- These helpers also install the shared vellum text theme on the styled surface: passive text on parchment-backed labels/list items should default to `UiSurfaceStyles.VELLUM_TEXT_COLOR` (dark near-black), while parchment-backed warning or highlight copy should use `UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR` (dark red) instead of pale yellow/gray callouts.
- Do not globally darken `Button` text on vellum surfaces just to solve a single screen's contrast issue. If a specific parchment-backed flow needs blocked buttons to read differently, override that control's `font_disabled_color` locally and leave enabled button text on the engine/default chrome.
- Vellum background `TextureRect` nodes added by the helper must draw with `show_behind_parent = true` so built-in dialog content is never covered by the parchment layer.
- Prefer the registered asset ID `ui.bg.vellum_subtle` via `AssetRegistry` rather than hard-coded file paths when applying parchment textures.
- Exceptions are explicit: the dice prompt modal and the hex-map tooltip keep their specialized styling unless design changes call them out separately.

### 13.5.5 Reusable UI Components (`scenes/ui/components/`)

<!-- Added 2026-04-17 — GoldDisplay and EncumbranceBar from Party Inventory Session 1 -->

Small, self-contained display widgets live in `scenes/ui/components/`. Each is a `.gd` + `.tscn` pair with no `class_name` (instantiated via scene, not script reference). They auto-refresh on relevant EventBus signals and expose a public API for setup and mode switching.

| Component | Base node | Purpose | Signals consumed |
|-----------|-----------|---------|-----------------|
| `GoldDisplay` | HBoxContainer | Coin display in summary (`GP: 242.35`) or breakdown (`PP: 4 | GP: 200 | …`) mode | `wallet_changed`, `inventory_updated` |
| `EncumbranceBar` | Control (`_draw()`) | Colored capacity bar with ACKS four-band or two-tier rendering | `inventory_updated` |

**Conventions for new components in this folder:**
- Expose `setup_*()` or `set_source()` for initial configuration, `refresh()` for manual update.
- Connect to EventBus signals in `_ready()`, disconnect in `_exit_tree()`.
- Keep display logic self-contained — no cross-subsystem writes, only reads.
- Use `_draw()` for custom rendering that needs color bands, tick marks, or non-rectangular shapes.

### 13.6 Scene Tree — Main.tscn

<!-- Updated 2026-04-09 -->

```
Main (Node, script: main_scene.gd)
├── NavigationStack (Node, script: navigation_stack.gd)
├── SceneContainer (Node)
├── SceneTransition (instance of scene_transition.tscn)
├── HexMapController (Node, script: hex_map_controller.gd)
├── HexMap (instance of hex_map.tscn)
├── OverrideManager (Node, script: override_manager.gd)
├── OverridePanel (instance of override_panel.tscn, CanvasLayer 128)
├── DicePrompt (instance of dice_prompt.tscn, CanvasLayer 64)
├── CharacterCreationScreen (instance of character_creation_screen.tscn, CanvasLayer 32)
├── CharacterSheetOverlay (instance of character_sheet_overlay.tscn, CanvasLayer 48)
├── PartyManagementOverlay (instance of party_management_overlay.tscn, CanvasLayer 46)
├── PartyInventoryOverlay (instance of party_inventory_overlay.tscn, CanvasLayer 50)
└── SessionRunner (Node, script: session_runner.gd)  ← MUST be last child
```

`main_scene.gd` wires the controller to the renderer and the override panel to the manager in `_ready()`. Subsystem managers are plain Node children — not autoloads.

**Dynamically managed screens** (not in Main.tscn — created by SessionState objects, pushed onto NavigationStack):
- CampaignSelectScreen (CanvasLayer 10) — by CampaignSelectState
- PartyWelcomeScreen (CanvasLayer 20) — by PartyCreationState
- PartyRosterScreen (CanvasLayer 20) — by PartyCreationState

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

## 13. Tactical Grid Conventions (Voxel)

<!-- Rewritten 2026-04-23 (12b) — voxel-only. The prior 2D `TacticalMapData` / `CellData`
     schema was deleted with the 12b cleanup sweep; historical entries for that model
     live in build_log.md sessions around 2026-04-02 (D-4). -->

The authoritative GDD for the tactical grid is [generation/gdd-voxel-tactical-architecture.md](generation/gdd-voxel-tactical-architecture.md). This section summarizes the conventions the codebase enforces.

### 13.1 Core types

All in `engine/shared_types/`:

| Type | Role |
|---|---|
| `VoxelCell` | Single 5' cube cell. Fields: `solidity`, `feature`, `floor_type`, `door_state/type/detected`, `fog_state` (String), `room_id`, `is_corridor`, `cover_value`, `stair_target_col/row/level`, `is_evil`. Derived methods: `is_passable_by_walker()`, `blocks_los()`, `blocks_flight()`, `blocks_burrow()`. |
| `VoxelMapData` | Sparse `Dictionary[Vector3i, VoxelCell]` storage. Absent keys return a fresh sentinel (air/open/none/hidden). Methods: `get_cell()`, `set_cell()`, `set_cell_field()`, `get_all_positions()`, `get_all_cells()`, `get_levels()`, `is_passable()`, `get_entities_at()`, `get_entity_pos()`, `set_entity_pos()`, `from_dict()` / `to_dict()`, `load_from_file()` / `save_to_file()`, `generate_open_field(w, h)` (wilderness combat factory). Metadata: `id`, `name`, `theme`, `tileset_group`, `entry_pos`, `generation_seed`. |
| `VoxelGrid` | Static 3D math. `cell_to_world(col, row, level)` (world `y = level * 1.0`), `world_to_cell()`, `get_neighbors_3d()` (26 neighbors), `get_neighbors_2d()` (8 same-level neighbors), `is_adjacent()` (3D Chebyshev ≤ 1), `chebyshev_distance()`, `get_cells_in_radius_3d(center, radius)`. `Direction` enum + `DIRECTION_OFFSETS` for stair compass suffixes. |

`IsometricGrid` retains two complementary roles:

1. **Screen-space math** — `CELL_W`, `CELL_H`, `HALF_W`, `HALF_H`, `cell_to_screen()`, `screen_to_cell()`. Used by 2D renderers and camera positioning.
2. **Pure-math 2D-flat helpers** — `chebyshev_distance(Vector2i, Vector2i) -> int`, `get_neighbors(Vector2i) -> Array[Vector2i]`, `get_cells_in_radius(Vector2i, int) -> Array[Vector2i]`. No map coupling; these are geometry-only utilities used by voxel code paths that operate on a single level where Vector2i is the natural shape (internal MovementResolver retreat/adjacency helpers, combat UI 2D-projected distance display, combat context-menu move-distance checks).

For **map-aware** 3D operations — adjacency against a VoxelMapData, multi-level distance, stair-aware pathing — use `VoxelGrid.is_adjacent()` / `chebyshev_distance()` / `get_neighbors_3d()` / `get_cells_in_radius_3d()` and `MovementResolver.path_bfs_3d()`.

The legacy 2D `TacticalMapData` cell grid and its `_all_levels` dictionary model are gone; there is no 2D map type any more. `IsometricGrid` has no map-awareness at all — it's pure geometry.

### 13.2 Vector3i convention

`Vector3i(col, row, level)` — x=col, y=row, z=level. This differs from world-space `Vector3` where y=up; always convert via `VoxelGrid.cell_to_world()` / `world_to_cell()`.

Entity positions everywhere (combatant `grid_position`, `VoxelMapData.entity_positions` values, `MovementResolver.*_3d` return types, renderer signals, party-position snapshots) are `Vector3i`. The 2D-signature wrappers on `MovementResolver` (`get_grid_position`, `find_path`, `has_line_of_sight`, etc.) project to `Vector2i(col, row)` internally — they're kept for legacy callers in combat_controller that haven't been migrated but they're thin wrappers over the voxel primitives.

### 13.3 Adjacency

3D Chebyshev distance ≤ 1 (26 neighbors). Single predicate for melee engagement, inventory transfers, and area effects: `VoxelGrid.is_adjacent(a, b)`. Same cell returns false; same level + adjacent cols/rows returns true; cross-level adjacency (e.g. standing on a stair) is true when both level and x/y deltas are ≤ 1.

### 13.4 Support and level transitions

`FallingResolver.has_support(map, pos)` — floor_type != "none" OR solid cell below OR ladder feature. Ground walkers need support; flyers do not.

Ground-walker level changes: level diff 0 = free, level diff 1 requires a stair/ramp feature with matching compass direction suffix (e.g., `stairs_up_N`, `ramp_SE`), level diff 2+ = blocked.

### 13.5 Movement modes

On `MovementResolver`'s 3D primitives:

- `"ground"` — passable + supported + stair for level changes
- `"flying"` — any non-blocking-flight cell, no support needed
- `"tunnel_burrow"` — solid is passable (air blocks burrowing)
- `"earth_pass"` — same pathing as tunnel_burrow
- `"climbing"` — air cell adjacent to at least one solid cell

Primary 3D methods on `MovementResolver`: `path_bfs_3d`, `has_los_3d`, `is_adjacent_3d`, `get_distance_3d`, `get_cells_reachable_3d`, `walk_direction_3d` (straight-line push/overrun for maneuvers — encapsulates the same reachability rules as path_bfs_3d for per-step checks).

### 13.6 Fog states

String-typed per cell: `"hidden"`, `"explored"`, `"visible"`. No CHECK constraint on the SQL schema; validate in code.

Transitions:

```
hidden → visible    (room entered for the first time; all room cells + boundary revealed)
visible → explored  (party leaves room; room cells dim)
explored → visible  (party re-enters room)
```

### 13.7 VisibilityManager

Tracks `focus_level`, `explored_levels`, `party_positions`. Per-level render opacity (default): focus = 1.0, below = 0.6, focus+1 = 0.3 (wall-dither, floors hidden), else = 0.0. Combat is single-level today (no VisibilityManager in the combat renderer); multi-level combat will plug it in.

### 13.8 Voxel JSON format

```json
{
  "id": "...", "name": "...", "theme": "...", "tileset_group": "...",
  "entry": {"col": 3, "row": 3, "level": 0},
  "cells": [
    {"col": 3, "row": 3, "level": 0, "solidity": "air", "feature": "open", "floor_type": "stone", "fog_state": "visible"}
  ],
  "transition_cells": [{"col": 0, "row": 0, "level": 0, "label": "Exit"}]
}
```

### 13.9 Inventory adjacency

`party_inventory_transfer_validator.gd` checks `context["carrier_positions"]` (Dictionary: carrier_id → Vector3i) via `VoxelGrid.chebyshev_distance(a, b) <= 1` (same-cell allowed). Combat mode also requires `context["combat_action_available"] == true`.

### 13.10 DB persistence

`voxel_map_cells` (migration 036, PK `(map_id, col, row, level)`) stores all VoxelCell fields. The legacy `dungeon_map_cells` table was dropped by migration 039 (12b) after the `@deprecated` CampaignRepository methods (`save_dungeon_cell_states` etc.) were removed. Voxel persistence methods: `save_voxel_cells_batch()`, `load_voxel_cells_for_map()`, `update_voxel_cell_state()`.

### 13.11 Secret door dev visibility

Undetected secret doors (`door_detected = false`) are rendered with a dark grey fill + white "S" icon instead of looking identical to walls. Dev-mode aid for placement verification; a future build flag will hide this in production.

### 13.12 DungeonMapController pattern

`DungeonMapController` is NOT an autoload. Instantiate dynamically in `DungeonExploreState.enter()`, add as child of the runner, call `load_dungeon()`, then pass to the dungeon scene via `setup(controller)`. The controller is freed when the dungeon scene is popped from NavigationStack.

*Last major update: 2026-04-23 — 12b voxel-only rewrite. Deleted TacticalMapData / CellData model; `IsometricGrid` demoted to screen-space helper.*

---

## 15. Party & Formation Conventions (E-1)

<!-- Added 2026-04-07 for party management and formation grid -->

### 15.1 Formation Grid

Party formation uses a **5-column × 12-row** grid (`PartyData.GRID_COLS`, `PartyData.GRID_ROWS`). Row 0 is the **front** of the formation; row 11 is the **rear**. Column 0 is leftmost.

- Members with `formation_col = -1, formation_row = -1` are **unplaced** (in the party but not on the grid).
- **Marching order** is derived from the grid: sorted by row ascending (front first), then column ascending (left first). Unplaced members are appended at the end. There is no separate marching order data structure.
- The grid doubles as the **battlemap spawn template** — when combat starts, characters spawn at their grid positions.
- Max party size is 42 (6 PCs + 7 henchmen each), fitting comfortably in the 60-cell grid with room for mercenaries and animals.

### 15.2 Mounts and Travel Speed

Mounts are **per-character equipment** using the existing `mount` inventory slot, not a party-level setting. When mount equipment integration is built:

- Equipping a mount adds a `movement_rate` modifier via the modifier system (source_type = `"item"`, stacking_group = `"mount"`).
- `CharacterData.get_effective_movement()` then returns the mounted speed.
- `PartyData.get_slowest_movement()` naturally returns the correct party speed — no special mount logic needed at the party level.

### 15.3 Travel Speed Calculation

`TravelSpeedCalculator` is a static class. Key rules:

| Rule | Implementation |
|---|---|
| Party moves at slowest member | `PartyData.get_slowest_movement()` |
| Terrain multipliers | Clear ×1, Woods/Hills/Desert ×2/3, Jungle/Swamp/Mountains ×1/2 |
| Road travel | ×3/2 of base, overrides terrain penalty |
| Forced march | ×1.5 distance, 12h day instead of 8h |
| Rest requirement | 1 day rest per 6 travel days (skipped with Endurance proficiency) |
| Rest penalty | Cumulative -1 attack/damage per day past 6 without rest |
| Getting lost | d20 proficiency throw vs terrain target; Navigation proficiency +4 |
| Banker's rounding | All mile calculations use banker's rounding per project convention |

### 15.3a Wilderness Navigation (Hex A*)

<!-- Added 2026-04-23 for the wilderness right-click "Move Here" multi-hex path. -->

`HexMapController.find_path(from, to) -> Array[Vector2i]` is the canonical hex pathfinder for wilderness Move Here orders and any future automated party motion across hexes.

| Concern | v1 rule |
|---|---|
| Algorithm | A* over passable hex neighbors |
| Heuristic | `hex_distance(a, b)` (admissible) |
| Step cost | Uniform 1 per step — terrain multipliers are a future concern |
| Passability | `HexMapController.is_hex_passable(coord)` — currently false only for `water == "ocean"` and `water == "lake"`. Add new conditions here, never inline at call sites. |
| Fog of war | Ignored — pathing through HIDDEN hexes is allowed. The journey reveals them. |
| Same-hex query | `find_path(c, c)` returns `[c]`, never `[]`. Distinguishes "no path" from "in place". |
| No path | Returns `[]`. Callers should surface a "No Route" toast, not silently no-op. |
| Path shape | Includes both endpoints. Travel-leg schedulers strip the first cell (the party already stands on it) before queueing. |

Right-click "Move Here" is **not** gated on adjacency. The wilderness context menu builder asks for passability only; the dispatcher uses `find_path` and lets it report unreachable targets. Mirrors the dungeon UI principle (gdd-dungeon-map-ui.md §3.1: never disable a click whose intent is clear — let execution reject if it must).

### 15.4 SQLite Null Coalescing

SQLite returns `null` for NULL column values. `Dictionary.get("key", default)` returns `null` (not the default) when the key exists with a null value. Use `PartyData._str()` / `PartyData._int()` helpers, or guard explicitly:

```gdscript
# WRONG — returns null if column is SQL NULL
var name: String = row.get("name", "fallback")

# RIGHT — coalesces null to fallback
var v = row.get("name", "fallback")
var name: String = v if v != null else "fallback"
```

This pattern applies to any shared type's `from_db()` / `from_dict()` when reading nullable SQL columns.

### 15.5 Party EventBus Signals

| Signal | Parameters | When emitted |
|---|---|---|
| `party_formed` | `party_id` | New party created |
| `party_split` | `original_party_id, new_party_id` | Party divided (CampaignRepository.split_party) |
| `party_merged` | `surviving_party_id, dissolved_party_id` | Parties reunited (CampaignRepository.merge_parties) |
| `active_party_changed` | `previous_party_id, new_party_id` | Player switched active party (GameState.set_active_party) |
| `party_member_joined` | `party_id, character_id` | Character added to party |
| `party_member_left` | `party_id, character_id` | Character removed from party |
| `formation_changed` | `party_id` | Grid positions changed |
| `getting_lost_checked` | `result: Dictionary` | Daily navigation check rolled |
| `forced_march_checked` | `result: Dictionary` | Forced march endurance check |

---

## 16. Session Runner Conventions (E-2)

<!-- Added 2026-04-07 for session runner state machine -->

### 16.1 Object-per-State Pattern

The session runner uses an **object-per-state pattern**: each gameplay state is a separate `RefCounted` script extending `SessionState`. SessionRunner holds a registry of state factories and delegates lifecycle to the active state object.

**Adding a new state:**
1. Create `engine/subsystems/session/states/new_state.gd` extending `SessionState`.
2. Add one line to `SessionRunner._register_states()`: `"new_key": func(): return NewState.new()`.
3. No existing state code is modified.

**State interface:**
```gdscript
func enter(runner, context: Dictionary) -> void   # wire signals, show UI
func exit(runner) -> void                          # disconnect signals, clean up
func handle_action(runner, action: String, payload: Dictionary) -> String
  # returns next state key ("" to stay)
```

### 16.2 SessionRunner as Sole GameState Driver

**SessionRunner is the ONLY code that calls `GameState.transition_to()` and `GameState.set_exploration_context()`.** This is enforced by convention, not by code. Other systems that need to know the current state listen to `GameState.state_changed` or `EventBus.session_state_transitioned`.

### 16.3 State ↔ GameState Mapping

| SessionRunner state key | GameState.State | GameState.ExplorationContext | Scheduler active? |
|---|---|---|---|
| `campaign_select` | MAIN_MENU | NONE | No |
| `party_creation` | MAIN_MENU | NONE | No |
| `session_load` | (transient) | (transient) | No |
| `wilderness` | EXPLORATION | WILDERNESS | Yes — travel_leg events |
| `dungeon` | EXPLORATION | DUNGEON | Yes — movement_tick, encounter_check, light_tick |
| `settlement` | EXPLORATION | SETTLEMENT | Yes — settlement_move, settlement_activity |
| `combat` | COMBAT | (unchanged) | Paused — combat runs its own time loop |
| `camp` | EXPLORATION | (unchanged) | Yes (MAX speed) — camp_watch events |
| `encounter` | EXPLORATION | (unchanged) | Paused |
| `downtime` | DOWNTIME | NONE | Yes |
| `session_end` | (handled by end_session) | (cleared) | Cleared |

The `day_declaration` state was removed (2026-04-14). Activities are now issued directly as scheduler events in real-time.

### 16.4 LLM Integration Points

Both UI clicks and LLM-interpreted actions resolve through the same path:
```
SessionRunner.submit_action(action_key, payload)
  → _current_state.handle_action(self, action_key, payload)
```
State objects don't know or care whether an action came from the UI or the LLM. The action vocabulary validation layer sits between LLMManager and `submit_action()`.

### 16.5 EffectTicker Lifecycle

`EffectTicker` bridges `ActiveEffectTracker.tick_*()` to `Timekeeping` boundary signals. It is:
- Created in `SessionRunner._ready()` with an empty `ActiveEffectTracker`.
- Connected via `connect_signals()` during `load_session()`.
- Disconnected via `disconnect_signals()` during `end_session()`.

Do NOT connect ActiveEffectTracker to Timekeeping signals from any other location.

### 16.6 Player Roll Cancellation

`DiceSystem.player_roll()` async path races `player_roll_resolved` against `player_roll_cancelled`. SessionRunner emits `player_roll_cancelled` at every state transition boundary (inside `transition_to_state()` before calling `exit()`). Cancelled rolls return a zeroed `RollResult` with `was_overridden = true` — callers should check this flag if they need to distinguish real rolls from cancellations.

### 16.7 Signal Connections in State Objects — No Closures

**Never use anonymous lambdas/closures for signal connections in state objects.** Closures create a new `Callable` each time, which breaks `is_connected()` / `disconnect()` checks and causes duplicate connections or orphaned handlers.

```gdscript
# WRONG — closure creates new Callable each enter(), can't disconnect reliably
func enter(runner, context):
    renderer.hex_clicked.connect(func(c): _on_hex_clicked(runner, c))

# RIGHT — store runner reference, connect bound method directly
var _runner = null
func enter(runner, context):
    _runner = runner
    renderer.hex_clicked.connect(_on_hex_clicked)
func _on_hex_clicked(coord: Vector2i) -> void:
    _runner.get_hex_map_controller().move_party(coord)
```

State objects store a `_runner` reference set in `enter()` and cleared in `exit()`.

### 16.8 Scene Tree Node Order in Main.tscn

**SessionRunner MUST be the last child of Main.** Godot calls `_ready()` in tree order (children before parent, siblings in declaration order). SessionRunner's `_ready()` resolves sibling references and boots the state machine — all siblings must have completed their own `_ready()` first.

### 16.9 Encounter Generation Flow

<!-- Added 2026-04-07 for F-0 monster catalog integration -->

`SessionRunner.do_encounter_check(terrain)` is the single entry point for random encounter generation:

1. Roll 1d6 (`encounter_check`). Trigger on 1. Civilized terrain always skips.
2. Use `HexTerrainData.encounter_table_weights()` to get weighted terrain table keys.
3. Collect candidate monsters from `MonsterRegistry.get_monsters_for_terrain()` across all relevant tables.
4. Pick one at random.
5. Roll 1d6 for encounter count (`encounter_number`).
6. Roll 2d6 for reaction (`reaction`), mapped to disposition via `_reaction_to_disposition()`.
7. Emit `EventBus.encounter_triggered(encounter_data)` with the full payload.

The override panel's Spawning tab bypasses steps 1–6 and emits `encounter_triggered` directly with user-chosen monster, count, and disposition.

Both paths produce the same payload shape: `{encounter_id, monster_group, number, reaction_roll, behavioral_disposition, hex_id, terrain_category, territory}`.

---

## 17. Combat Subsystem Conventions (F-1)

<!-- Added 2026-04-07 for F-1 combat loop session 1 -->

### 17.1 Pull-Based Combat Controller

CombatController is a RefCounted class (not a Node) that uses a **pull-based state machine**. The caller advances combat by calling `advance() -> Dictionary` repeatedly. The controller never blocks or runs an internal loop.

**Advance loop pattern (from UI or test harness):**
```gdscript
var result := controller.advance()
match result["status"]:
    "waiting_for_pc_action":
        # Show UI, collect player choice, then:
        controller.submit_pc_action(id, action_id, params)
        result = controller.advance()  # resolve the action
    "combat_over":
        # Handle victory/defeat
    _:
        # Continue advancing
```

This design avoids async complexity and makes tests trivial — no coroutines, no signal waits.

### 17.2 Combatant Wrapper Pattern

`Combatant` wraps either a `CharacterData` (for PCs/henchmen) or a monster catalog `Dictionary` (from MonsterRegistry). It does NOT subclass CharacterData. Monster combatants build transient `ModifierContainer`, `EntityFlags`, and `DamageResistance` objects for combat-only effects.

**Why wrapping, not subclassing:** Monsters are not persisted to the `characters` table. Creating a full CharacterData for each goblin would pollute the persistence model and waste fields. The wrapper provides the same combat-relevant interface without the identity/persistence baggage.

### 17.3 Combat Action Vocabulary

Combat actions reuse the `ActionPayload` pattern. CombatState routes these action keys:

| Action Key | Payload | Notes |
|-----------|---------|-------|
| `combat_advance` | `{}` | Advance controller one step |
| `combat_pc_action` | `{combatant_id, action_id, parameters}` | Submit PC's chosen action |
| `combat_ended` | `{result, rounds}` | Direct end (from override system) |

Inner action_ids used by CombatController:
`"attack_melee"`, `"attack_ranged"`, `"cast_spell"`, `"move"`, `"fighting_withdrawal"`, `"full_retreat"`, `"use_item"`, `"combat_maneuver"`, `"pass"`

### 17.4 MockDice Pattern for Combat Tests

Combat tests inject a `_MockDice` inner class that mimics DiceSystem's `roll_digital()` and `roll_expression()` APIs with forced values. This provides deterministic outcomes without touching GameState or autoloads.

```gdscript
class _MockDice:
    extends RefCounted
    var _forced_value: int
    func _init(forced: int) -> void:
        _forced_value = forced
    func roll_digital(sides, count, modifier, _roll_type) -> RollResult:
        # Returns a RollResult with forced value
    func roll_expression(_expression, _roll_type) -> RollResult:
        # Returns a RollResult with forced value
```

All combat subsystem classes accept the dice system via constructor injection, making them fully testable in isolation.

### 17.5 Combat UI Architecture (F-2)

<!-- Added 2026-04-10 for F-2 tactical combat UI -->

**Two combat contexts, shared HUD widgets:**

| Context | Renderer | Overlay/Screen | When |
|---------|----------|----------------|------|
| Dungeon | DungeonMapRenderer (combat mode) | DungeonCombatOverlay (CanvasLayer 10) | Dungeon encounter — monsters spawn in-place |
| Wilderness | CombatMapRenderer (standalone Node2D) | CombatScreen (CanvasLayer 5) | Wilderness encounter — generated open-field map |

Both contexts compose the same HUD widgets: InitiativeStrip, StatSummary, ActionButtonPanel, CombatLogPanel, DeclarationOverlay, CombatEndOverlay. Both own a `CombatUIController` (RefCounted) that bridges HUD widgets to CombatController.

**CombatUIController is signal-based, not node-based.** It extends RefCounted, not Node, so it cannot call `call_deferred()` directly. The overlay/screen (which ARE Nodes) connect the `auto_advance_requested` signal and handle deferral.

**Deferred auto-advance pattern:** Enemy turns and phase transitions emit `auto_advance_requested` instead of recursively calling `advance()`. The host node connects this to `call_deferred("_do_deferred_advance")`, yielding one frame for Godot to render between steps.

### 17.6 Combat Turn Structure (ACKS)

<!-- Added 2026-04-10 -->

A PC turn has two sub-actions: **optional move first, then optional attack/action**.

- Move does NOT end the turn. After move resolves, the action panel re-appears with Move disabled.
- Attack (melee or ranged) ends the turn (unless cleave triggers).
- Pass or Delay ends the turn.
- PCs must move adjacent before melee attacking — no auto-move on attack. The controller returns "target not adjacent" if the PC hasn't moved first.
- Monsters DO auto-move in `_resolve_monster_action()` — they don't have a separate move/attack UI.

Fighting Withdrawal and Full Retreat are declaration-phase actions (pre-initiative), not mid-turn buttons.

### 17.7 Token Position Sync

After any action that changes grid positions (movement, force-back, etc.), the overlay/screen must call `_sync_token_positions()` to update all CombatantToken screen positions from `tactical_map.entity_positions`. This is NOT automatic — the combat engine updates the data model but the renderer must be explicitly told.

### 17.8 Mortal Wounds (Deferred)

<!-- Added 2026-04-10 -->

Mortal wounds are NOT auto-rolled at combat end. `_emit_combat_ended()` calls `_collect_downed_pcs()` which returns `{needs_mortal_wound_check: true, hp_when_downed, killing_blow_damage_type, round_downed}`. CombatFinalizer marks these PCs as `is_incapacitated = true, hp_current = 0`. The actual mortal wound roll happens later when another character inspects the downed unit (future UI). `process_mortal_wounds()` is retained for direct test calls and future UI-driven resolution.

### 17.9 Combat Log Display Names

The CombatLogPanel displays combatant display names (not raw IDs) by:
1. CombatUIController adds `actor_name`/`target_name` fields to every log entry via `_resolve_name()`.
2. CombatLogPanel has a `_name_lookup: Dictionary` (set via `set_name_lookup()`) for resolving IDs in sub-attack results (multi-attack monsters).
3. `_format_entry()` prefers `actor_name`/`target_name` over `actor_id`/`target_id`.
4. JSON export retains both ID and name fields for programmatic debugging.

### 17.10 Combat Persistence

`CombatFinalizer.finalize()` calls `_persist_party()` which saves all party CharacterData to the database via `CampaignRepository.save_character(cd.to_dict())`. This persists HP changes, XP awards, is_dead, is_incapacitated, etc. after every combat.

## 18. Reputation and Reaction System

<!-- Added 2026-04-11 (Phase G-1) -->

### 18.1 Five-State Attitude is Sacred

Per `rules/ax_reactions_and_influencing.xml`, NPC dispositions use **five states**: `hostile`, `unfriendly`, `neutral`, `indifferent`, `friendly`. Intimidation tone substitutes `fearful` (9-11) and `cowed` (12) at the upper end of its result table.

The four-state simplification (`hostile`/`cautious`/`neutral`/`friendly`) used in pre-G-1 code is **gone**. `EncounterData._coerce_disposition()` translates legacy `"cautious"` rows on load. New code must validate against the five-state vocabulary.

The 2d6 → attitude table is sacred:

| Total | Diplomatic / Seduction | Intimidation |
|---|---|---|
| 2 | hostile | hostile |
| 3-5 | unfriendly | unfriendly |
| 6-8 | neutral | neutral |
| 9-11 | indifferent | fearful |
| 12 | friendly | cowed |

### 18.2 Reputation Score is Canonical, Tier is Cached

Reputation rows store an `int score` in the band `[-100, +100]` and a `String tier` denormalized for fast lookup. When mutating, always go through `ReputationEntry.apply_delta()` (or `ReputationSystem.apply_reputation_change()`), which clamps the score and recomputes the tier in one place.

Score → tier thresholds (defined as constants in `Attitude`):

| Score | Tier |
|---|---|
| ≤ -60 | hostile |
| -59..-20 | unfriendly |
| -19..+19 | neutral |
| +20..+59 | indifferent |
| ≥ +60 | friendly |

Tier → reaction modifier: -2 / -1 / 0 / +1 / +2.

### 18.3 Cascade Lives in ReputationSystem, Not in the Schema

The domain-ruler → domain → settlement cascade is **computed at query time**, never stored. Cascade weights are constants in `ReputationSystem` (`RULER_DOMAIN_WEIGHT_*`, `DOMAIN_SETTLEMENT_WEIGHT_*`, `RULER_SETTLEMENT_WEIGHT_*`) so they can be tuned in one place.

Effective settlement score formula:

```
effective_settlement = local_settlement
                       + effective_domain / 2
                       + ruler_score / 4
```

The `build_reaction_modifiers(target)` helper avoids double-counting: if the target dictionary supplies a `settlement_id`, the domain branch is skipped (the settlement cascade already includes the domain contribution).

### 18.4 Reputation Subsystems Don't Get Their Own DB Connections

Per existing convention, only `CampaignRepository` opens SQLite. `ReputationSystem` and `HostileEnforcement` are `RefCounted` classes that take a CampaignRepository reference in their constructor and call accessor methods on it (`fetch_reputation_entry`, `upsert_reputation_entry`, `get_domain_ruler_id`, etc.). **Do not add new autoloads for reputation features** — wire them into the session runner / domain manager during construction.

### 18.5 Henchman Lifecycle Subsystem

<!-- Added 2026-04-12 (Phase G-2) -->

Henchman lifecycle classes live in `engine/subsystems/henchmen/`. All are `RefCounted` (no autoloads). `HenchmanTables` is pure static data (sacred tables, no DB/dice). `HenchmanAvailability` and `HenchmanLoyaltyResolver` are pure-math classes that accept a `dice` parameter for testability. `HenchmanLifecycleManager` is the coordinator; callers construct it with `CampaignRepository` and (optionally) `ReputationSystem` references.

**Morale vs loyalty:** `loyalty_score` on `CharacterData` is the quick-access combat morale field (consumed by `Combatant.get_morale()`). `henchman_state.morale_score` is the canonical lifecycle score (tracks grudging/fanatic flags, unpaid months). These should stay in sync — `on_henchman_leveled_up()` and `on_henchman_calamity()` update both.

**Pool generation:** Henchman pools are generated on first tavern visit per settlement per month, cached in `henchman_pools` + `henchman_pool_members`. Pool characters are real `characters` rows with `character_type = 'henchman'` and `employer_id = ''` until hired.

### 18.6 Reaction Modifiers Use the Existing ModifierStack

Reputation modifiers, proficiency bonuses, and the sacred ACKS modifier categories (alignment, location, authority, threat, etc.) all stack via the existing `ModifierStack`. Each contribution is added with a labeled `source_id` and a `stacking_group` so the breakdown is auditable in test logs and (later) in LLM context assembly. Never roll up a final integer and add it as one anonymous modifier — preserve the per-source breakdown.

---

## 19. Event Scheduler Conventions

<!-- Added 2026-04-14 for real-time-with-pause scheduler system -->

### 19.1 Architecture Overview

The game operates on a **real-time-with-pause** model. An `EventScheduler` priority queue holds future events keyed to absolute game-time timestamps (elapsed rounds). A `SchedulerLoop` ticks every frame during active gameplay, advances the party clock to the next event, resolves it via an `EventHandlerRegistry`, and repeats. The player controls clock speed (Pause/1x/2x/5x/Max).

**Core classes (all `RefCounted`, owned by SessionRunner — NOT autoloads):**

| Class | File | Role |
|---|---|---|
| `ScheduledEvent` | `engine/subsystems/session/scheduled_event.gd` | Data class for a single queued event |
| `EventScheduler` | `engine/subsystems/session/event_scheduler.gd` | Sorted priority queue |
| `EventHandlerRegistry` | `engine/subsystems/session/event_handler_registry.gd` | Maps event_type → handler Callable |
| `SchedulerLoop` | `engine/subsystems/session/scheduler_loop.gd` | Frame-tick driver, speed control, auto-pause |

### 19.2 Event Handler Contract

Every handler is a `Callable` with signature `func(event: ScheduledEvent) -> Dictionary`. The return dict may contain:

| Key | Type | Effect |
|---|---|---|
| `next_events` | `Array[Dictionary]` | Follow-up events to schedule (each has fire_time, event_type, owner_id, data, priority) |
| `auto_pause` | `bool` | Pause the scheduler after this event |
| `pause_reason` | `String` | Human-readable reason shown in the status bar |
| `enter_combat` | `bool` | Suspend scheduler, transition to CombatState |
| `encounter_data` | `Dictionary` | Passed to CombatState if enter_combat is true |
| `presentation` | `Dictionary` | Data for UI notification/display |
| `transition_to` | `String` | Session state key to transition to |

**The scheduler does not know about event semantics.** Handlers are registered by exploration states in `enter()` and unregistered in `exit()`. Domain handlers are registered globally in `load_session()`.

### 19.3 Handler File Pattern

Each exploration context has a handler class in `engine/subsystems/session/handlers/`:

| File | Events handled |
|---|---|
| `wilderness_handlers.gd` | `travel_leg`, `wilderness_encounter_check`, `getting_lost_check`, `forced_march_check` |
| `dungeon_handlers.gd` | `dungeon_movement_tick`, `dungeon_encounter_check`, `dungeon_light_tick`, `dungeon_action_complete` |
| `settlement_handlers.gd` | `settlement_move`, `settlement_activity`, `settlement_encounter` |
| `camp_handlers.gd` | `camp_watch`, `camp_rest_complete` |
| `domain_handlers.gd` | `domain_monthly_tick` |

Handler classes are `RefCounted`, take a `runner` (SessionRunner) in `_init()`, and expose `register(registry)` / `unregister(registry)` methods. State objects create and own their handler instance.

### 19.4 Priority Tiebreaker Rules

When multiple events share the same timestamp, resolve in this order (lower number = first):

| Priority | Constant | Category |
|---|---|---|
| 0 | `PRIORITY_ENVIRONMENTAL` | Weather, dawn/dusk, season, light ticks |
| 10 | `PRIORITY_SCHEDULED_CHECK` | Wandering monster rolls, encounter checks |
| 20 | `PRIORITY_ARRIVAL` | Travel arrival, search complete, construction done |
| 30 | `PRIORITY_CONSEQUENCE` | Combat start, trap trigger, domain event |

Within the same priority tier, alphabetical `owner_id` breaks ties.

### 19.5 Time Advancement Rules

- **Always use the party clock:** `Timekeeping.advance_party_rounds(party_id, n)`, not global `advance_rounds()`.
- **Combat rounds up to the next turn:** After combat, `CombatFinalizer` advances the party clock by rounds fought, then rounds up to the next turn boundary (ACKS RAW: combat < 1 turn consumes a full turn).
- **Party locking:** If a party's clock is ahead of the global clock (e.g., after combat rounding or dungeon exit), the party is locked from new orders until the world catches up. `SessionRunner.is_party_locked(party_id)` checks this.
- **Dungeon time is independent:** The dungeon party's clock runs asynchronously from the overworld. On dungeon exit, the party may be time-locked.

### 19.6 Dungeon Real-Time-With-Pause Model

*(Updated 2026-04-14: context menu system replaces selection panel)*

Dungeon exploration is real-time at round granularity. The primary interaction model is RTS-style:

- **Left-click** selects entities; Shift+click multi-selects; click empty cell deselects.
- **Right-click** opens a dynamic context menu (auto-pauses the scheduler). Menu options are built by `DungeonContextMenuBuilder.build_menu()` based on cell state, selected entities, fog, and character abilities.
- **Context menu dispatch** routes through `DungeonExploreState._on_context_action()` to existing handler/controller methods.
- **Control groups** (Ctrl+1-9 assign, 1-9 recall) stored in `DungeonSessionState` per dungeon visit.
- **Idle behaviors** (hold, follow, auto-listen, auto-search, guard, hide) are per-entity, set via context menu.
- A `dungeon_movement_tick` event fires every round, advancing all moving entities by their `cells_per_round` rate.
- Movement modes: exploration (1/3 combat speed), combat (full), running (2x). Mode change takes effect on the next tick.
- The scheduler auto-pauses when all movement completes, on encounters, light expiry, and action completion.
- Combat transitions to turn-based on the same diamond grid, then returns to real-time on combat end.
- **Evil doors** auto-close on turn tick (every 60 rounds) unless wedged open. Controlled by `is_evil` field on `VoxelCell`.

**Key files (dungeon UI):**
- `engine/subsystems/exploration/dungeon_context_menu_builder.gd` — Pure logic: builds menu options from game state.
- `scenes/maps/dungeon_context_menu.gd` — UI popup scene for the context menu.
- `engine/subsystems/exploration/dungeon_session_state.gd` — Per-visit state: control groups, idle behaviors, action queues.
- `scenes/maps/dungeon_unit_info_panel.gd` — Left-side selected entity details.
- `scenes/maps/dungeon_control_group_bar.gd` — Bottom bar with group slots [1]-[9].
- `scenes/maps/dungeon_notification_log.gd` — Scrolling colored event log.
- `scenes/maps/dungeon_minimap.gd` — Top-right schematic minimap (toggle: M key).

**Removed (2026-04-14):** `SelectionPanel` (order type radio buttons M/S/L/W), `BottomBar` (LevelLabel/TurnLabel), standalone `ExitButton`, `door_interact_requested` signal, `end_turn_requested` signal. These are replaced by the context menu system. The files `dungeon_selection_panel.gd` and `.tscn` are orphaned and can be deleted.

### 19.7 Day Planner System (Removed)

The `DayDeclarationState`, `DayBudgetManager`, and day declaration screen were removed on 2026-04-14. Activities are now issued directly as scheduler events. Do not reference day_declaration or day_budget in new code. The `day_declaration_requested` EventBus signal no longer exists.


## 20. Character Token 3D Conventions (2026-04-23)

PC / henchman combatants render as GLB character-model tokens through `scenes/ui/components/character_token_3d.gd`. Enemies, monsters, and PCs whose class has no registered GLB render through the existing cylinder token `scenes/ui/components/combatant_token_3d.gd`. Both scenes expose the same public API so renderers never branch on token type.

### 20.1 File Layout for Character Models

```
assets/tokens/characters/
  <class_id>_<variant>_<sex>.glb    # e.g., fighter_def_male.glb
```

- `variant` is one of `def`, `alt1`, `alt2`, `alt3`.
- `sex` is `male` or `female`.
- Use underscores only; never hyphens. Legacy hyphen-separated files must be renamed before import.
- Textures must be embedded in the GLB (Blender's "Copy" or "Embed" export option). No sibling `.bin` / `.png` files.

### 20.2 Registry — Add New Models Without Touching Renderers

`scenes/ui/components/character_model_registry.gd` is a static `RefCounted` script (no autoload). Adding a new placeholder model:

1. Drop the GLB into `assets/tokens/characters/`.
2. Append its stem to the `_FILES` array.
3. Done — character creation picks it up automatically via `get_available_variants(class_id, sex)`, and renderers instantiate it via `has_any_model(class_id, sex)` at token creation.

Scale is resolved by class first, then sex (`_SHORT_CLASSES`, `_MEDIUM_CLASSES`, male / female defaults). The scale is in world units (= meters). If a new class needs a non-default height, add it to the override list in the registry — do not hard-code heights anywhere else.

### 20.3 Procedural Animation Over Skeletal

Token motion is driven by `Tween` on the outer `Node3D`, not by an `AnimationPlayer` inside the GLB. This applies to sliding, turning, lunging, and falling. Rationale: the placeholder meshes are static, and tween-driven motion is deterministic and inspectable.

If you add a new animation state (e.g., cast, stagger), follow the pattern in `character_token_3d.gd`: kill any prior tween via stored handle, guard with `is_inside_tree()` so pre-tree setup falls through to direct assignment, and keep durations in module-level constants (`MOVE_DURATION`, `ATTACK_OUT_DURATION`, etc.).

### 20.4 Node Structure

```
CharacterToken3D (Node3D)       # the thing renderers position
├── ModelPivot   (Node3D)       # pivots for downed rotation; Y-rotation for facing
│   └── ModelHolder (Node3D)    # scale applied here; holds the instanced GLB
├── SelectionRing (MeshInstance3D)
├── ClassLetter   (Label3D)
└── NameLabel     (Label3D)
```

Downed animation hinges at mid-height by pre-offsetting `ModelHolder.position.y` to half the model height, rotating `ModelPivot` 90 ° about X, and concurrently tweening `ModelPivot.position.y` down to put the lying model flat on the floor. Do NOT rotate `ModelHolder` for facing — that would break the downed pivot math.

### 20.5 Renderer Integration Checklist

When instantiating tokens:

- Call `CharacterModelRegistry.has_any_model(class_id, sex)` to decide which scene to instantiate. Unknown class or no-model means the cylinder fallback.
- Pass `sex` through from `CharacterData.sex` — this is an optional param on `add_entity_token()` defaulting to `"male"` for monster / unnamed-entity cases.
- Procedural animations route through thin forwarders on the renderer: `play_token_attack(entity_id, target_world_pos)`, `play_token_downed(entity_id)`, `play_token_revive(entity_id)`. These are safe to call on cylinder tokens (they `has_method`-guard internally).

### 20.6 Character Creation Wizard

The `TOKEN_SELECTION` step sits between `PORTRAIT` and `LANGUAGES`. It is skipped automatically via `_should_skip_token_selection()` when the class has no registered GLBs for any sex. The panel:

- Owns `creation_state["sex"]` (writes it on toggle; honors `ClassRegistry.get_sex_restriction`).
- Writes `creation_state["token_variant"]`.
- Instantiates exactly one preview `CharacterToken3D` inside a `SubViewport` and frees it before loading the next — never batch-loads variants.

The `FinalizePanel` sex toggle still works as an override (same class restrictions).


## 21. Heraldry Subsystem (2026-04-23)

The heraldry builder lives in `engine/subsystems/heraldry/` and paints per-party heraldic shields that replace the wilderness party tokens. Full design in `generation/gdd-heraldry-builder.md`.

### 21.1 Canonical Type

`HeraldryDescriptor` (`engine/shared_types/heraldry_descriptor.gd`) is the sole contract between DB, UI, and renderer. Mutations flow `UI editor → descriptor → CampaignRepository.save_heraldry → EventBus.heraldry_changed → renderer refresh`. Colors persist as `#RRGGBB` hex strings; the static `color_from_hex` / `color_to_hex` helpers convert at the boundary.

### 21.2 Registries

Five registries follow the established `class_name X extends RefCounted` + `_init()` catalog-load pattern:

- `ShieldShapeRegistry` — code-defined `const` dictionary. Seven v1 shape_ids: `heater`, `kite`, `round`, `norman`, `tower`, `horsehead`, `swiss`. Each carries a silhouette polygon in normalized `Vector2(0..1)` coordinates. No PNG dependencies.
- `ChargeRegistry` — JSON-backed from `data/heraldry/charges.json` (~760 white-silhouette PNG charges).
- `FieldDivisionRegistry` / `OrdinaryRegistry` — code-defined `const` dictionaries; geometry as normalized polygons.
- `TincturePalette` — seven named heraldic colors plus the `is_low_contrast(Color, Color)` luminance predicate for the soft rule-of-tincture warning.
- `PresetLibrary` — loads the starter preset catalog; used for backfill + the editor's "Reset" dropdown.

No autoloads. Instantiate on demand and cache within the renderer / editor.

**Shape vocabulary is closed.** Any legacy `shape_id` outside the seven names above is remapped in migration 039 (and re-defended on every render by `ShieldShapeRegistry.has_shape` — the renderer pushes an error and bails on unknown ids rather than silently substituting).

### 21.3 Rendering Pipeline

`HeraldryRenderer` (`engine/subsystems/heraldry/heraldry_renderer.gd`) is a `Node2D` that hosts a `SubViewport`. Consumers add it to the tree, call `update_descriptor(desc, size)`, and assign `get_texture()` to a `Sprite2D` or `TextureRect`. The ViewportTexture reference stays stable across descriptor changes — no need to reassign downstream sprites on refresh.

Shield silhouettes are code-defined polygons in normalized coordinates (`0..1`) inside `ShieldShapeRegistry`. No mask/outline PNG assets — drawing is pure-geometry.

Layer composition inside the viewport (back to front):

1. **Background fill**: `Polygon2D` with the shield silhouette, colored with `tincture_primary` (or `tincture_ordinary` when bordure is active, providing the outer rim).
2. **Inset fill (bordure only)**: `Polygon2D` with the inset silhouette, colored with `tincture_primary`. Revealing the outer ring gives the bordure effect.
3. **Secondary division polygons**: each clipped against the field silhouette via `Geometry2D.intersect_polygons`, then drawn as `Polygon2D` in `tincture_secondary`.
4. **Ordinary polygons (non-bordure)**: same clipping pattern as secondary, drawn in `tincture_ordinary`.
5. **Centered charge** (`Sprite2D`): modulate-tinted with `tincture_charge`, scaled to `CHARGE_FOOTPRINT_RATIO` of the shield's short dimension. Minor overhang past the silhouette is accepted for v1.
6. **Outline**: `Line2D` tracing the silhouette, closed, antialiased, near-black (`OUTLINE_COLOR`).

Bordure width comes from `OrdinaryRegistry.ORDINARIES.bordure.border_inset_ratio`. The inset silhouette is computed by `HeraldryRenderer._inset_polygon` — points scaled toward the silhouette's geometric centroid by `1 - 2 * ratio`. This gives a reasonable colored rim for heater-family shields; exotic silhouettes may need a different inset algorithm.

### 21.4 Normalized Shield Coordinates

All field-division and ordinary polygon definitions use normalized coordinates: `(0,0)` = top-left of the shield's bounding box, `(1,1)` = bottom-right. The renderer scales to pixel space via `HeraldryRenderer.scale_normalized_polygon(array, output_size)`. Decouples geometry from render resolution; the same const dictionaries drive both 64-px hex-map tokens and 256-px editor previews.

### 21.5 Persistence and Backfill

Migration 038 adds `party_heraldry` (+ `parties.heraldry_id` FK). Existing parties get NULL on the FK. `SessionLoadState._backfill_party_heraldry(campaign_id)` runs after `load_session()` and assigns a random preset shield to every party with a NULL `heraldry_id`. Idempotent — subsequent session loads skip parties already bound.

Five repository methods: `get_heraldry`, `get_heraldry_for_party`, `save_heraldry` (upsert + emits signal), `assign_heraldry_to_party`, `create_default_heraldry_for_party`.

### 21.6 EventBus Contract

`heraldry_changed(heraldry_id: String)` — emitted by `save_heraldry` on any upsert. Consumers (renderer cache, hex-map token, party-management UI) listen and refresh only the matching party's presentation.

### 21.7 Hex-Map Token Integration

`scenes/maps/hex_map_renderer.gd` holds `party_id → HeraldryRenderer` in `_heraldry_renderers` (the per-party cache). All renderers are parented under an invisible `HeraldryHolder` Node2D sibling of `EntityLayer`. The `PartyToken` (scene-defined) and dynamic split-party tokens are `Sprite2D` nodes whose `texture` points at their renderer's ViewportTexture.

Active vs inactive state uses scale + modulate only — no color-tinted Polygon2D and no gold ring overlay. Constants on the renderer:

```gdscript
const ACTIVE_SCALE := Vector2(1.15, 1.15)
const INACTIVE_SCALE := Vector2(0.9, 0.9)
const ACTIVE_MODULATE := Color(1.0, 1.0, 1.0, 1.0)
const INACTIVE_MODULATE := Color(0.72, 0.72, 0.78, 1.0)
```

Click-pulse tweens scale to `current × 1.15` briefly then back to `current`, so the pulse respects active/inactive baseline without fighting steady-state styling.

