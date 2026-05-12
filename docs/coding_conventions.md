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

<!-- Updated 2026-05-02 — vellum text theme now covers Button-family + input controls -->

Runtime-built windows, overlays, and modal popups should use the shared `UiSurfaceStyles` helper instead of ad-hoc semi-transparent defaults.

- Use `UiSurfaceStyles.apply_textured_panel(panel)` for opaque parchment-backed `PanelContainer` surfaces that do not need a separate border frame.
- Use `UiSurfaceStyles.apply_framed_window_chrome(surface)` for modal windows and overlay panels that need both the `ui.bg.vellum_subtle` background and a visible frame border; `surface` may be either a `Control` panel or a `Window`-based popup/dialog.
- These helpers install the shared vellum text theme on the styled surface. The theme covers all commonly-used controls so text remains readable on the parchment background:
  - Passive surfaces: `Label`, `RichTextLabel`, `Window` titles, `ItemList`, `Tree` use `VELLUM_TEXT_COLOR` (dark near-black).
  - Interactive Button-family (`Button`, `OptionButton`, `MenuButton`, `CheckBox`, `CheckButton`, `LinkButton`): all interactive states (`font_color`, `font_pressed_color`, `font_hover_color`, `font_focus_color`) use `VELLUM_TEXT_COLOR`; the stylebox provides affordance feedback rather than text-color shifts.
  - Text input (`LineEdit`, `TextEdit`, `SpinBox`): font and caret use `VELLUM_TEXT_COLOR`; placeholder and read-only use a lighter shade.
  - Tabs (`TabBar`, `TabContainer`) and `PopupMenu`: selected/active text uses `VELLUM_TEXT_COLOR`; unselected/disabled use the lighter shade.
  - Disabled state across all controls uses `VELLUM_TEXT_COLOR.lightened(0.45)` — visibly distinct but still on the dark side of the parchment palette.
- Warning/highlight text on parchment uses `UiSurfaceStyles.VELLUM_WARNING_TEXT_COLOR` (dark red) instead of pale yellow/gray callouts.
- **Prior convention reversed (2026-05-02):** the older guidance said "do not globally darken Button text" on vellum surfaces. That assumed the Godot default Button font color (~white) was readable on parchment — it is not, and the project sets no project-level theme to override it. Button-family text is now darkened globally by the vellum text theme. Per-control `font_disabled_color` overrides are still permitted for screen-specific tweaks; do not reintroduce the prior carve-out.
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

`party_inventory_transfer_validator.gd` checks `context["carrier_positions"]` (Dictionary: carrier_id → Vector3i) via `VoxelGrid.is_adjacent(a, b)` (strict Chebyshev == 1). A carrier at the anchor's own cell is included only when it *is* the anchor — ACKS movement rules forbid two entities sharing one cell, and the validator locks the rule in even though live play can't produce the case. Combat mode also requires `context["combat_action_available"] == true`.

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
| `wilderness_handlers.gd` | state-scoped: `travel_leg`, `wilderness_encounter_check`, `getting_lost_check`, `forced_march_check`, `wilderness_activity`, `wilderness_activity_complete`. global: `wilderness_day_tick`. |
| `dungeon_handlers.gd` | `dungeon_movement_tick`, `dungeon_encounter_check`, `dungeon_light_tick`, `dungeon_action_complete` |
| `settlement_handlers.gd` | `settlement_move`, `settlement_activity`, `settlement_encounter` |
| `camp_handlers.gd` | `camp_watch`, `camp_rest_complete` |
| `domain_handlers.gd` | `domain_monthly_tick` |

Handler classes are `RefCounted`, take a `runner` (SessionRunner) in `_init()`, and expose `register(registry)` / `unregister(registry)` methods. State objects create and own their handler instance.

**Global vs state-scoped split (Phase 3, 2026-05-04):** When a handler class owns BOTH state-scoped events (only valid in one exploration state) AND global events (must fire across state transitions, like daily housekeeping), split the registration into `register_state_scoped` / `register_global` methods. `register` / `unregister` keep the all-in-one shape for tests and small handlers; `WildernessHandlers` is the canonical example — `wilderness_day_tick` is registered globally by `SessionRunner.load_session` (alongside `DomainHandlers`) so sustenance and weather rollover survive a transition to camp/dungeon/settlement, while `travel_leg`/`wilderness_encounter_check`/etc. remain state-scoped under `WildernessExploreState.enter`/`exit`.

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

## 22. Combat movement legality (2026-04-27)

Combat pathfinding and movement validation must distinguish two separate concepts:

1. **Path-step legality (waypoints).** A unit can pass *through* a cell occupied by an incapacitated combatant — dead, unconscious, paralyzed, sleeping, or petrified — but is blocked by any active occupant. Stepping over a body is fine; squeezing past a guard isn't.
2. **Endpoint legality (where movement stops).** End-of-move occupancy is one combatant per cell. Even a corpse blocks an *endpoint* — you can vault over a body but you cannot stop on it.

`MovementResolver._is_blocking_occupant(pos, mover_id)` is the path-step predicate; `_is_legal_endpoint(pos, mover_id)` is the endpoint predicate. Pathfinding must call both at the right phases — `path_bfs_3d` rejects waypoints via `_can_enter_3d` (which calls the step predicate) and rejects endpoint cells via the endpoint predicate before yielding the path.

Callers opt into occupancy checks by passing a non-empty `mover_id` to `path_bfs_3d` / `find_path` / `can_reach`. Empty `mover_id` keeps occupancy checks disabled — the dungeon explorer's group-walk pathfinding deliberately doesn't constrain on occupancy because party members can briefly co-occupy a cell during animated movement.

## 23. Class-power gating for action eligibility (2026-04-27)

Right-click action menus that gate on a thief skill (Pick Lock, Find Traps, Hide in Shadows, etc.) must check the **class power**, not just `cd.combat_progression == "thief"`. Bards have thief combat progression but only a subset of thief skills per ACKS RAW (Climb Walls, Hear Noise, Move Silently, Hide in Shadows, Read Languages — no Pick Lock, Find Traps, Pick Pockets, or Backstab). The wrong gating handed bards skills they shouldn't have.

Convention: maintain a constant list of class IDs that grant each gated power, named `CLASSES_WITH_<POWER_ID>`, in the consumer file (e.g. `dungeon_context_menu_builder.gd`, `dungeon_action_actor_picker.gd`). Verify each entry against that class's `data/classes/*.json` `class_powers` array — only classes that explicitly list the power belong on the list.

```gdscript
const CLASSES_WITH_OPEN_LOCKS := ["thief"]

# Eligibility = class with the power OR proficiency.
if cd.character_class in CLASSES_WITH_OPEN_LOCKS:
    return true
if cd.has_proficiency("lockpicking"):
    return true
```

When the same gating list lives in two files (e.g. menu builder + action picker), keep them in sync — comment each constant with a pointer to its sibling.

## 24. Fog of war is light-source-driven (2026-04-27)

Dungeon fog reveal is **light-source + LOS based**, not room-scoped. The pre-batch-3 mechanism (entering a room flips all its cells to Visible) was scaffolding put in place before light data was wired; it is **retired**. The `_reveal_room_voxel` helper survives for dev/debug use but no longer participates in the fog-update path.

Implementation:
- `FogRevealEngine.compute_visible_cells(map, members)` (pure static) takes the current voxel map and a `{entity_id: {pos, radius}}` payload, walks each member's Chebyshev box at their light + darkvision radius, and uses `VoxelLOS.has_los` to gate every cell.
- `DungeonMapController._update_fog_for_all_members_voxel` is the canonical entry point — both initial party-spawn reveal and post-move updates call it. The function demotes currently-Visible cells to Explored, then writes the new lit set.
- V1 simplification: members with radius 0 still expose their own cell so the player can see their portrait in pitch darkness. Full no-light mechanics (no movement without LOS) are deferred.

Room data structures (`get_room_at`, `get_room_cells`, `get_room_boundary_cells`) remain canonical for B6 leftover-cache placement and other room-scoped concerns. Only the fog-reveal hook moves to light + LOS.

## 25. Per-context scheduler speed tables (2026-04-27)

The scheduler's three speed bands (`SPEED_NORMAL`, `SPEED_FAST`, `SPEED_VERY_FAST`) are **caller-facing ordinals**, not multipliers. The actual rounds-per-real-second depends on the current exploration context, looked up via three const dictionaries on `SchedulerLoop`:

```gdscript
const DUNGEON_SPEEDS    := { SPEED_NORMAL: 1, SPEED_FAST: 6,  SPEED_VERY_FAST: 30 }
const WILDERNESS_SPEEDS := { SPEED_NORMAL: 1, SPEED_FAST: 2,  SPEED_VERY_FAST: 5 }
const SETTLEMENT_SPEEDS := { SPEED_NORMAL: 1, SPEED_FAST: 2,  SPEED_VERY_FAST: 5 }
```

Why context-coupled: the per-context `TIMESCALE_*` already amplifies the band (wilderness = 60×, settlement = 6×). Reusing one global multiplier across contexts means dungeon Fast and wilderness Fast are wildly different in felt pace. The tables let dungeon get a tighter band (1 round = 1 round) while wilderness keeps its hour-jumping behaviour at the same UI button.

Anything that needs the live multiplier should call `SchedulerLoop.get_effective_multiplier()` rather than reading `_speed` directly. The dungeon renderer's tween-speed computation is the canonical example — without going through the getter, tween playback would lag the clock at the larger dungeon bands. New consumers should follow the same pattern.

Adding a new exploration context: introduce a new `TIMESCALE_<context>` constant, a matching `<CONTEXT>_SPEEDS` dictionary, and an entry in `_speed_table_for_timescale()`. Don't try to share an existing context's table — that's how the wilderness/dungeon coupling bug came about in the first place.

## 26. Static-helper autoload access (2026-04-27)

Static utility methods on `RefCounted` classes (`TravelSpeedCalculator`, `HenchmanLifecycleManager`, etc.) sometimes need to reach an autoload that wasn't passed in by the caller. The convention is a defensive scene-tree walk that returns `null` when the tree isn't set up:

```gdscript
static func _get_campaign_repository():
	var main_loop := Engine.get_main_loop()
	if main_loop == null or not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	return root.get_node_or_null("CampaignRepository")
```

Why this shape:
- **No constructor injection.** Static methods can't carry instance state, and threading a repo through every public call balloons the API. The autoload is global by design — accessing it from a static helper is OK as long as the helper degrades when it's missing.
- **Null-safe at every layer.** Unit tests construct fixtures without a running scene tree; the helper returns `null` and the caller falls back to a sensible default (e.g. modifier-only movement in `TravelSpeedCalculator`). Tests that *do* want to exercise the autoload path can register a fake under the same node name.
- **Pattern is reused** in `HenchmanLifecycleManager._event_bus()` and `_get_party_wallet()`. New static helpers needing an autoload should copy this exact shape — do not invent variant lookups.

## 27. Player-decision modals from scheduler handlers (2026-05-05)

Scheduler-driven event handlers (anything called by `EventHandlerRegistry.resolve` from `scheduler_loop.tick`) **must not block on UI**. They run inline in the loop's tick step, return a result Dictionary synchronously, and the loop interprets the result. Any "the player needs to decide something" path therefore splits across three tiers:

1. **Handler tier** — emits a request signal on `EventBus` and returns `{auto_pause: true, pause_reason: …, presentation: {type: …, …}}`. Never `await` in the handler; never call into UI nodes from it.
2. **State tier** — listens for the request signal in `enter()`, disconnects in `exit()`. Owns the UI lifecycle: instantiate the modal, hand it the request payload, connect to its single resolve signal with `CONNECT_ONE_SHOT`, dispatch on the choice (state transition / scheduler resume / a back-into-handler call).
3. **Modal tier** — pure UI. One signal out (`decided(choice)`, `confirmed`, etc.). No EventBus emission, no DB calls, no scheduler manipulation. Static helpers for any pure data the modal exposes (button matrices, label formatters) so unit tests don't need a SceneTree.

The canonical example is the wilderness encounter decision flow:

- Handler: `WildernessHandlers._handle_travel_leg` emits `EventBus.encounter_decision_required(party_id, enc)` and returns `auto_pause: true` with a presentation payload.
- State: `WildernessExploreState._on_encounter_decision_required` opens `EncounterDecisionPrompt`, on `decided` dispatches to combat / encounter / evasion / continue.
- Modal: `EncounterDecisionPrompt` exposes `static buttons_for_disposition(d) -> Array` so the button matrix is testable with no scene tree.

Always emit the signal on EventBus (not on the handler instance). Handlers are RefCounted and don't survive state transitions; the state-tier listener subscribes once and stays alive across re-entries.

When the player picks a "do nothing" option (continue travel, dismiss notification), the state must call `_resume_scheduler()` because the handler returned `auto_pause: true`. Forgetting this leaves the world clock paused.

For background entities that triggered the same handler path but shouldn't surface a modal (e.g. multi-party play where a non-active party rolled an encounter), the state tier should auto-dispatch the safest default and resume the scheduler in the early-return — same as the active-party "continue" path.

## 28. Forage / sustenance counter offset model (2026-05-05)

The wilderness sustenance system models food and water as **abstract integer counters on `PartyData`** (`ration_units`, `water_units`), not as inventory items:

- `ForagingResolver.attempt_daily` mutates the counters directly. No items are created.
- `SustenanceResolver.apply_daily` decrements them by `party_size` and rolls HP loss when the counters underflow into deficit days.
- River/lake/town hexes top off the water counter (mirroring foraging auto-pass) — the helper is `WildernessHandlers._refill_water_at_hex`. The cap is `party_size` (one day's draw).
- Foraging fires on `wilderness_noon_tick`; sustenance fires on `wilderness_day_tick` (midnight). The noon → midnight ordering means food found earlier in the day offsets that day's consumption. The noon handler stashes the forage summary in an in-memory buffer (`WildernessHandlers._latest_forage_summary_by_party`); the midnight handler consumes and erases it when writing the sustenance log row.
- The equipment catalog's `holds_water: true` flag (on `waterskin`, `barrel`, future jugs/jars) is for **inventory UI display and refill gating only** — it is not load-bearing for the counter mechanics. Generic containers (backpack, chest, pouch, sack) intentionally lack the flag.

When adding new sustenance hooks: mutate the counters, persist with `CampaignRepository.save_party_state(party_data.to_state_dict())`, and let the existing day-tick log row capture the change. **Do not introduce food items** as a parallel system — the counter is the source of truth, and the inventory layer (when it lands) is purely descriptive.


## 29. Domain Subsystem Conventions (2026-05-06)

Established during Domain Phase 0 (RAW-correct monthly tick). Conventions for the new `engine/subsystems/domains/` directory and the resolver chain that powers `domain_handlers._resolve_domain_month`:

- **Resolvers are static-only `RefCounted` classes.** Files are named `domain_*_calculator.gd` / `domain_*_resolver.gd` (calculator = pure summation, resolver = stateful enough to need branching). Every public function is `static`. No autoload registration. No internal mutable state. The resolver inputs ARE the contract — pass the domain dict, the relevant fixture data (hexes, ruler), and any cross-phase numbers (stronghold value, classification minimum) explicitly.
- **Income gate is the first-position check in revenue and growth.** Per `acore_axioms` §peasants_and_followers L108-109, when `stronghold_value_gp < classification_minimum_gp`, `DomainRevenueCalculator` returns `{total: 0, …, income_gate_active: true}` and `DomainGrowthResolver` zeros random change + morale-tier modifier (active-adventuring and investment bonuses still apply per the L121 reading). The expense calculator preserves the 2 gp/family universal garrison minimum even under the gate. Every downstream resolver checks `income_gate_active` from the revenue result rather than re-deriving sufficiency.
- **Banker's rounding via `XPAwardCalculator.bankers_round(value)`.** This is the project's canonical public banker's-rounding utility (per CLAUDE.md "Banker's rounding everywhere. No exceptions."). Phase 0 resolvers MUST call it directly — do NOT introduce private `_bankers_round` helpers (six already exist in other subsystems and are slated for future cleanup).
- **Stub helpers for cross-phase dependencies.** When a Phase 0 resolver needs data from a future phase (e.g., stronghold value from Phase 1's strongholds table), the handler exposes a `_stub_*` helper that returns the safe default (`_stub_stronghold_value` returns 0) and Phase 1+ replaces the helper body with the real query. Resolvers themselves take the values as parameters — they never know about the stub.
- **Ledger writes are append-only, one row per nonzero subcategory.** `domain_handlers._write_revenue_ledger` and `_write_expense_ledger` insert into `ledger_entries` (migration 058) with category ∈ {revenue, expense, tribute_in, tribute_out, investment, other} and a free-text subcategory. Never UPDATE or DELETE ledger rows; corrections write a compensating entry.
- **Dice are injected via `Callable` — use lambdas, not inner-class methods.** `DomainGrowthResolver.resolve_growth` takes an optional `dice_roller: Callable` with signature `(faces: int, count: int, exploding: bool) -> int`. Tests pass deterministic stubs as **GDScript lambdas**, NOT as `Callable(inner_class_instance, "method_name")` — inner-class callables don't reliably round-trip the resolver's `is_valid()` check. The resolver's fallback also wraps its static default via a lambda, not `Callable(static_method)`.
- **EventBus signals for cross-system change broadcast.** Phase 0 added eight signals in the Domain block of `engine/autoloads/event_bus.gd` (L487-528): `domain_followers_arrived`, `classification_advanced`, `classification_regressed`, `domain_treasury_changed`, `bandit_spawned`, `domain_event_resolved`, `stronghold_sufficiency_changed`, `land_value_improved`. Past-tense names; payloads are documented in the signal comments. Phase 1+ wires emitters where appropriate.
- **Persistence via `CampaignRepository.update_domain_monthly_state(domain_id, fields)`** rather than inline SQL in handlers. The whitelist (`_DOMAIN_MONTHLY_FIELDS`) prevents typoed field names from silently dropping. Adding a new monthly-mutated column = adding it to the constant list AND the migration.


## 30. Stronghold Subsystem Conventions (2026-05-06)

Established during Domain Phase 1 (commission lifecycle + sufficiency wiring). Conventions for `engine/subsystems/strongholds/`:

- **Resolvers are static-only `RefCounted` classes** (matches §29 domain pattern). The four Phase 1 resolvers — `StrongholdCostCalculator`, `CommissionPipeline`, `StrongholdRepository`, `ClaimingResolver` — expose only `static` methods. `CommissionPipeline` is the exception: it also instantiates per-session (matching `DomainHandlers`) for the daily-tick handler.
- **Daily tick, not monthly.** `acore_stronghold_construction_costs.pdf` rules construction at 1 day per 500 gp; a monthly tick would lose 27 days of resolution. Phase 1 introduces `stronghold_construction_daily_tick`, scheduled like `domain_monthly_tick` but with `owner_id="stronghold_global"` and a 1-day reschedule cadence (`Timekeeping.ROUNDS_PER_DAY = 8640`).
- **Speed tiers and engineer requirement come from the PDF, not the XML.** `acore_axioms_strongholds_and_domains.xml` covers establishing/sufficiency rules but not the cost/timeline math. The PDF is the authoritative source for: 500 gp/day base rate; speed tiers 100/150/200 → 500/666/1000 gp/day; engineer requirement of `ceil(gp_committed / 100,000)` at 250 gp/month each. Cleric/bladedancer get 50% cost reduction; their followers never check morale.
- **`StrongholdRepository.get_stronghold_value_for_domain(domain_id)`** is the single source of truth for sufficiency reads. It SUMs `gp_value` of completed strongholds (in-progress contribute zero per RAW). `domain_handlers._stub_stronghold_value` calls into it; Phase 0's stub is now wired. The repository's `_sufficiency_cache` (in-memory dict) lets `recompute_sufficiency_after_change` detect flips without storing a denormalized boolean column.
- **Class location restrictions are caller-validated, not schema-enforced.** `StrongholdCostCalculator.validate_class_location(power_id, territory, race, is_underground)` returns Array[String] of error codes. `CommissionPipeline.start_commission` calls it before any DB write; if errors are non-empty, no rows are inserted. The schema's `archetype` CHECK constraint covers archetype values but not the location matrix (which depends on territory + race + underground state).
- **Single-write-per-iteration in `advance_commissions`.** Each commission row is updated exactly once per daily tick (combining `gp_progressed`, `halfway_signal_fired`, `completed_calendar_day`, `status` into one update_commission call). An earlier iteration with separate writes per-branch had a bug where days between halfway and completion didn't advance gp_progressed; the unified pattern fixes that and is the canonical shape for any future tick handler that emits multiple milestone events per iteration.
- **`is_conforming_to_class` is display-only.** Per `[RESOLVED 2026-05-06]` in `docs/domain-roadmap-corrected.md`, the conforming/non-conforming flag has no mechanical effect (followers, garrison, morale, activities all gate on stronghold gp-value sufficiency only per `acore_axioms` §minimum_stronghold_value L88-94). The flag is stored on `strongholds.is_conforming_to_class` for UI badges only; `ClaimingResolver.is_archetype_conforming_to_class` computes it.
- **Tests filter signals by `stronghold_id`/`domain_id`** when verifying signal emission, since the campaign DB persists across test suites and prior tests' commissions may emit during a later test's tick advancement. The integration test's listeners use `if sid == stronghold_id` filters; without them, leftover commissions from earlier unit tests pollute the milestone array.
- **Test-only RNG reseed via `randomize()` in `_setup_campaign`.** The campaign.db persists across test runs in `user://`; `generate_id()` uses GDScript's default RNG which seeds the same way each run, so tests that create campaigns hit `UNIQUE constraint failed: campaigns.id` collisions on the second run. Calling `randomize()` at test setup dodges this. Production code does not need it.


## 31. Domain Tab UI Conventions (2026-05-07)

Established during Domain Phase 2 (player-facing Domain tab shell + Overview + Treasury + Establish-Domain). Conventions for `scenes/ui/notebook/domain/` and the Phase 2 cross-domain UI patterns:

- **Two whitelists per domain row.** `_DOMAIN_MONTHLY_FIELDS` (Phase 0) covers monthly-tick writes; `_DOMAIN_SETTINGS_FIELDS` (Phase 2) covers player-mutable knobs (name / alignment / religion / tax / liturgy / tithe / auto_pay_policies / establishment_method). UI surfaces ALWAYS go through `update_domain_settings`; monthly handlers ALWAYS go through `update_domain_monthly_state`. Splitting them prevents either side from accidentally smashing the other's columns.
- **Atomic treasury adjustments.** `CampaignRepository.adjust_domain_treasury(domain_id, delta_gp) -> int` performs the SET treasury_gp = treasury_gp + ? in a single SQL statement and returns the new balance via a follow-up SELECT. Use this rather than read-modify-write so concurrent writers (a monthly tick + a player deposit) don't lose updates. `DomainTreasury.deposit` / `.withdraw` always call through it.
- **Procedural sub-tab construction (no .tscn pairing).** Existing notebook tabs (character_tab_page, party_tab_page, …) build their UI in code, not via .tscn scenes. The Domain tab follows suit: each sub-tab is a `.gd` file extending VBoxContainer / PanelContainer / AcceptDialog, instantiated programmatically by the tab page's `_ensure_sub_tab_page`. This avoids the scene-id bookkeeping and keeps surface refactors localized to one file. Future Phase N+ sub-tabs (Activities / Realm / etc.) follow the same pattern.
- **Per-entity-per-sub-tab substate.** The Domain tab's NotebookState substate carries a `sub_tab_per_entity` dict so each entity remembers its last-active sub-tab independently. When the player switches entities, the new entity's persisted sub-tab is restored (defaulting to Overview if unset). This is in addition to the per-tab `entity_per_type` dict from `gdd-management-notebook.md` §6.1.4 — the two keys are independent.
- **Status header is reused across sub-tabs.** `domain/status_header.gd` is owned by `domain_tab_page.gd` (one instance per tab page), NOT instantiated per-sub-tab. Each sub-tab renders below the header without owning it. Sub-tab `display(domain_data)` methods receive the same domain row dict the header consumes; the page calls `_status_header.display(domain)` separately so the header refreshes on the same data refresh trigger as the active sub-tab.
- **Placeholder sub-tab pattern.** When a sub-tab is bundled into a future phase but the strip slot exists today, use `placeholder_sub_tab.gd` configured with `setup(title, planned_phase, description)`. Avoids per-phase placeholder boilerplate. The body explains what the sub-tab will do AND when (which phase) — keeps the player oriented across the build sequence.
- **Cross-tab activation: routing is asymmetric.** When the player clicks an entity in the Domain tab's strip, the tab emits `EventBus.notebook_active_entity_requested(entity_id)` so the Notebook root + Character tab also synchronize. When the Domain tab receives `notebook_active_entity_changed` from the outside, it resolves the entity-type (PC / humanoid henchman / ineligible) and updates its strip + content; ineligible entities (animals / vehicles / mercenary officers) leave the Domain tab's selection unchanged.
- **Establish-domain dialog branches dynamically on classification + own-race toggle.** Per `gdd-domain-tab.md` §16.1 + `acore_demihuman_classes.xml` race restrictions, the available acquisition methods change with both classification AND own-race state. The dialog's `_refresh_methods` re-populates the method dropdown on either change, marking each item available/disabled based on `EstablishDomainFlow.available_paths(character, classification, in_own_race_area)`. The chaotic-toggle is disabled for non-chaotic characters since the chaotic-only methods (clanhold_annex / recruit_chieftain) require chaotic alignment per `ax_domains_of_chaos`.
- **Active-adventuring detector is per-session-instantiated, not static.** Per `gdd-domain-tab.md` §6.2 the heuristic accumulates seven boolean triggers + a treasure-returned counter PER DOMAIN PER MONTH. State is held on a `RefCounted` instance owned by the session runner (not in DB), reset at month-rollover via `apply_monthly_state(domain_id, calendar_day)` which writes the resolved boolean to `domains.is_active_adventuring_this_month`, appends an `active_adventuring_log` audit row, and emits `active_adventuring_resolved`. The audit table records each month's snapshot for transparency in the Overview "Active this month" tooltip.
- **Treasury reason codes as constants.** `DomainTreasury.REASON_*` constants (REASON_OK / REASON_INSUFFICIENT_FUNDS / REASON_NOT_AT_STRONGHOLD / REASON_DOMAIN_NOT_FOUND / REASON_AMOUNT_INVALID / REASON_LAND_IMPROVEMENT_REJECTED / REASON_HEX_NOT_FOUND / REASON_STRONGHOLD_NOT_FOUND / REASON_CHARACTER_NOT_FOUND) are exposed to UI / tests for introspection. Tests assert on the constants rather than literal strings; UI tooltips can localize off the constants.



## 32. Activity Subsystem Conventions (2026-05-07)

Established during Domain Phase 3 (Activity Time-Cost Executor + Decrees & Remote Orders + Active Projects + strenuous accountant). Conventions for `engine/subsystems/activities/` and the per-location launcher contract:

- **Activities live in `data/activities/<category>.json`, not in code.** Each activity catalog file is a JSON dict with an `activities` array; each entry carries `id`, `category`, `frequency` (singular / restricted / ongoing), `activity_level`, `strenuous`, `duration_formula`, `default_ticks_required`, `session_time_cost_rounds` (or activity_level fallback), `location_kind`, `prerequisites`, `effect_summary`, `raw_citation`, optional `param_schema`. `ActivityCatalog._load_all` enumerates every `*.json` in `res://data/activities/` at construction. Adding a new activity is a JSON edit + handler module — no engine change.

- **Frequency semantics are codified in `ActivityTimeCostExecutor`.** Singular and Restricted resolve atomically inside a single ScheduledEvent (`activity_complete`). Ongoing fires `ongoing_session_complete` daily and reschedules itself at `event.fire_time + ROUNDS_PER_DAY`. Singular cancellation = total failure (no partial credit per `ax_campaign_play.xml` §frequency_types.singular L152-155). Ongoing cancellation = the day's session is forfeited (emits `activity_forfeited` with reason) but `ticks_accumulated` from prior days is preserved unless the caller passes `terminal=true` to mark the activity abandoned. The §15.1 tick-tolerance forfeit happens INSIDE the ongoing handler when `absence > ticks`.

- **Handlers are static `RefCounted` modules with `on_complete(state, runner) -> Dictionary` + optional `on_tick(state, runner) -> Dictionary`.** One file per RAW activity in `engine/subsystems/activities/handlers/<id>.gd`. Return dict keys: `summary` (human-readable), `presentation` (optional UI hint), `signals` / `ledger_entries` / `side_effects` are caller-private (the handler writes them directly via repository / EventBus calls). Handlers write deferred Phase 5/6/8 effects as ledger rows with `subcategory` ending `_pending` (e.g., `conscript_pending`, `mercenary_offers_pending`) so future phases can replay them.

- **Handler registration via a single glue file per category.** `engine/subsystems/activities/handlers/domain_handlers_registration.gd:register_all(registry)` registers all 16 domain-category handlers in one call. Phase 5/9 will add `troops_handlers_registration.gd`, `faith_handlers_registration.gd`, etc. SessionRunner's `load_session` calls each registration's `register_all` after instantiating the registry.

- **Strenuous accountant is per-session instance, but `get_attack_throw_penalty` is static.** The streak counter and per-day dedupe live on a SessionRunner-owned `StrenuousAccountant` instance. Combat / proficiency throw resolvers, however, can't hold a SessionRunner reference, so the read-side getter is a static method that goes through `CampaignRepository.get_character_activity_state` directly. This keeps the wire-in to one line per resolver site (`StrenuousAccountant.get_attack_throw_penalty(character_id)`) and avoids dependency injection in the combat hot path.

- **`activity_completed.outcome` dict's minimum keys are `activity_def_id`, `success`, `summary`.** Per-handler outcome dicts can extend with handler-specific keys (e.g., research outcome adds `research_progress`). UI listeners (Decrees & Remote Orders, Active Projects) only key off the minimum set; per-handler keys are consumed by handler-specific UI surfaces.

- **`ActivityLaunchContext` data shape (per-location launcher contract):**
  ```gdscript
  {
    "entity_id": String,        # character_id of the actor
    "activity_def_id": String,  # key into ActivityCatalog
    "location_kind": String,    # "anywhere" | "in_domain" | "at_stronghold" |
                                # "at_settlement" | "at_construction_site" |
                                # "at_dungeon" | "at_wilderness_hex"
    "location_ref": String,     # e.g., "settlement:<id>" | "stronghold:<id>" |
                                # "hex:<q>,<r>" | "domain:<id>"
    "params": Dictionary,       # activity-specific (e.g., issue_decree's
                                # {decree_kind, value} or oversee_investment's
                                # {gp_committed})
  }
  ```
  Launchers call `SessionRunner.get_activity_executor().launch(...)` with these args (positionally — there is no Context dict type). The canonical reference example is `scenes/ui/settlement/hiring_panel.gd:_dispatch_hire_via_activity_executor` which dispatches `hire_mercenaries` through the executor as a side-channel to the existing finalize_hire flow. New location surfaces (stronghold UI in Phase 4, wilderness/dungeon in later phases) follow the same pattern.

- **Active Projects sub-tab path is `scenes/ui/character_sheet/tabs/cs_tab_active_projects.gd`** matching the existing `cs_tab_*.gd` convention, NOT the roadmap text's `scenes/ui/notebook/character/sub_tabs/` (the codebase doesn't have that directory). New character-sheet sub-tabs always follow the `cs_tab_*.gd` naming; they are added to `character_tab_page.gd:SECTION_DEFS` and to `sheet_section_strip.gd:SECTIONS_BY_TYPE` (filtered per entity type).

- **Decrees & Remote Orders sub-tab uses procedural construction.** Like other Phase 2 Domain sub-tabs (Overview, Stronghold, Treasury) — extends `VBoxContainer`, builds cards programmatically in `_ready`, calls `display(domain_data)` to render content. Subscribes to four EventBus signals (`activity_launched`, `activity_tick_earned`, `activity_completed`, `activity_forfeited`) for live refresh, filtered by `_ruler_id`.

- **Migration numbering is plain integer prefixes only.** The migration runner (`campaign_repository.gd:159-167`) splits on `_` and rejects non-integer version prefixes — `065a_…` would be silently skipped. When the roadmap text uses `XXXa` suffix style for sub-migrations, renumber to plain integers. Cite the roadmap's intended number in the migration's comment header so future readers can trace lineage.

- **Phase 3 transient columns on `domains` (administer_domain_completed_this_month / pending_investment_gp) are reset by the monthly tick after consumption.** They are added to `_DOMAIN_MONTHLY_FIELDS` so monthly-tick writes can clear them. Activity handlers SET them via `update_domain_monthly_state` (issue_decree-style mutations of player-facing settings still go through `update_domain_settings`). Activity-set transient columns are a deliberate alternative to a side-effects queue table — simpler and avoids changing Phase 0 resolver input shapes.


## 33. Stronghold Sub-Tab + Construction Rate Bump Conventions (2026-05-07)

Established during Domain Phase 4 (Stronghold sub-tab full content + construction rate-bump wire-in). Conventions for `scenes/ui/notebook/domain/sub_tabs/stronghold_sub_tab.gd`, `engine/subsystems/strongholds/commission_pipeline.gd`'s rate-bump methods, and the activity-handler → commission-mutation pattern:

- **Rate-bump computations live in CommissionPipeline (static), not in handlers or CampaignRepository.** `CommissionPipeline.bump_daily_construction_rate(commission_id, bonus_pct) -> int` reads the prior rate, applies `bankers_round(prior × (1 + pct/100))`, writes through `update_commission`, and returns the new rate. Handlers call this method without holding pipeline state. The repository remains a pure CRUD surface; the rounding-aware math stays next to its sibling RAW computations in CommissionPipeline.

- **Compounding bumps over flat additive bumps.** When multiple supervisors stack (e.g. oversee_construction +5% AND supervise_construction +10%), each bump operates on the CURRENT rate, not the base. So `500 → ×1.10 → 550 → ×1.05 → 577 or 578` (banker's-rounded). Net 1.155× ≈ 15.5% rather than RAW's flat 10% — a small over-shoot that's consistent with the project's compounding-modifier convention used elsewhere (mod stacks, condition durations).

- **`+1 gp/day` fallback when banker's rounding collapses the bump.** If `bankers_round(prior × multiplier) == prior` (low base rate, e.g. 10 gp/day × 1.05 = 10.5 → 10), the method forces `new_rate = prior + 1` so successive supervisors always make some progress. Prevents the no-op-bump edge case on low-rate commissions.

- **Activity handler → commission lookup pattern.** Handlers that need the active commission for the ruler's domain use `CommissionPipeline.get_in_progress_commission_for_domain(domain_id)`. This joins `stronghold_commissions × strongholds` and returns the earliest-completing in_progress commission, or empty Dict. Handlers that get an empty result write a `*_no_active_commission` ledger row so the player can audit why their oversight had no effect — better than failing silently.

- **Stronghold sub-tab uses procedural construction with section cards.** Like Overview / Treasury / Decrees & Remote Orders, the sub-tab extends VBoxContainer and builds four titled cards (Sufficiency / Combined Value / Owned Strongholds / In Progress) plus an action row. Each card has a heading Label as child[0] and a body that is cleared-and-rebuilt via `_clear_card_body(card)` (preserves the heading) on every refresh.

- **Sufficiency banding has four states + an income-gate boolean.** Tier banding ladder per `acore_axioms` §insufficient_stronghold L452-456: **Sufficient** (value ≥ minimum, green, 0 morale), **≥½ minimum** (amber, −1), **≥¼ minimum** (orange, −2), **<¼ minimum** (red, −3). Income-gate banner is a SEPARATE binary: shown whenever `value < minimum`, regardless of which insufficient sub-tier the domain is in. The two indicators co-exist (e.g. ≥½ minimum shows amber tier label AND red income-gate banner).

- **Phase 1 wizard / modal cross-activation: `add_child` then connect signals.** The Stronghold sub-tab instantiates `CommissionWizard.new()` inside an `AcceptDialog` popup and `ClaimStrongholdModal.new()` as a CanvasLayer child. Both surfaces emit completion signals (`commission_placed`/`claimed`) and `cancelled`. The handler binds the popup/modal reference into the slot via `connect(_on_X_done.bind(popup))` so the slot can free the popup after handling. After completion, the sub-tab calls `_render_all()` to refresh.

- **Display-only flavor badges.** `is_conforming_to_class=false` displays a `[non-conforming archetype]` badge per the O-D10 resolution (display-only, no mechanical effect). `archetype_power_id` matching `cleric_divine_stronghold` / `bladedancer_divine_stronghold` displays a `[divine favor: 50% cost discount]` badge — the actual discount is applied during commissioning by `StrongholdCostCalculator.calculate_total_cost`. `is_claimed=true` displays `[claimed: <source>]` flavor.

- **Live signal subscriptions in `_subscribe_signals` / `_unsubscribe_signals`.** Sub-tabs that show derived state subscribe in `_ready` and unsubscribe in `_exit_tree`. Use `is_connected` guards to avoid double-subscribing on re-enter. Signal handlers either filter by domain_id (e.g. stronghold_sufficiency_changed carries domain_id) or unconditionally re-render (e.g. stronghold_completed which doesn't carry the domain — the renderer reads the current domain row's strongholds directly).

- **Default cross-activation parameters are sensible, not authoritative.** Buttons that open complex dialogs (CommissionWizard, ClaimStrongholdModal) pre-fill defaults so the player can press through quickly, but the dialogs themselves are the authoritative input surface. e.g. claim defaults to `archetype="fortress"` / `appraised_gp_value=25000` / `source="ruin"` — the player adjusts before confirming. Phase 5+ may add inline pickers before invoking the dialogs.


## 34. Army Warfare Subsystem Conventions (2026-05-08)

Conventions established while building Phase 6A part 1 (`engine/subsystems/armies/`, migrations 070-074, GDD `gdd-army-warfare.md` v1.0).

- **GDD-stated INTEGER PRIMARY KEY AUTOINCREMENT is overridden in favor of the codebase's TEXT-id convention.** Every existing table (campaigns, characters, domains, troop_units, ...) uses `TEXT PRIMARY KEY` populated from `CampaignRepository.generate_id()`. The army-warfare GDD specified INTEGER autoincrement for armies / officers / assignments / supply / battles, but adopting that would have introduced a second primary-key style with no offsetting benefit. All five Phase 6A migrations (070-074) use TEXT IDs and TEXT FKs to existing TEXT PKs. Future GDD revisions should mirror the codebase convention, not propose alternatives.

- **Migration numbering is sequential and never relies on roadmap text.** When the roadmap asserts a migration number (e.g. Phase 6A → 065-068) but those numbers are already taken by an in-flight earlier phase (Phase 5 took 065-069), the next phase mechanically renumbers to the next available block (Phase 6A → 070-074). The sequential constraint comes from `CampaignRepository._run_migrations()` which parses `parts[0].is_valid_int()` — non-integer suffixes (`065a`) are silently rejected. The roadmap and any GDD should be treated as advisory on numbering only; the migrations directory's contents are authoritative.

- **Per-army rng_seed_stream column stores the deterministic RNG seed for save-load reproducibility.** `armies.rng_seed_stream INTEGER` per `gdd-army-warfare.md` §4.9.1. Every probabilistic resolver running on this army (supply tick, vagary roll, collision tiebreaker, recon roll) draws from a per-army seeded stream so the exact event sequence reproduces on reload. The composer initializes it to `randi()` if the caller did not specify; downstream resolvers consume it but do not yet wire the seeded stream — that lands with Phase 6A part 2's scheduler integration.

- **Static-class entry points for army-warfare subsystems mirror the troop_units / domain pattern.** `ArmyRepository`, `ArmyValidator`, `SupplyCalculator`, `ArmyComposer`, `ArmyDisbander`, `RecruitmentVagariesResolver`, `EncounterScaler`, `ArmyCollisionDetector`, `ExtractionResistanceHeuristic` are all `class_name X extends RefCounted` with `static func` methods. No instances, no autoloads — keeps the wire-in to a single line at each call site (`ArmyComposer.compose(plan)`, `ArmyValidator.validate_hierarchy(army, officers, assignments)`). Same convention as Phase 5's `TroopUnitRepository`, `GarrisonExpenditureCalculator`, `FollowerArrivalResolver`.

- **Officer-ability stored snapshot, not computed-on-read.** `army_officers.leadership_ability / strategic_ability / morale_modifier` are stored values. The composer derives them from the underlying `characters` row at insert time. The field-battle resolver (Phase 6B) reads the snapshot — it does NOT recompute from the character's current state mid-battle. When the character mutates (level-up, retraining), the repository is responsible for re-deriving and updating every active `army_officers` row referencing the changed character. This matches `gdd-army-warfare.md` §3.3 "ACKS Constraint — recompute on character change."

- **Whitelisted UPDATE field arrays per repository.** `ArmyRepository._ARMY_UPDATE_FIELDS / _OFFICER_UPDATE_FIELDS / _ASSIGNMENT_UPDATE_FIELDS / _SUPPLY_UPDATE_FIELDS` enumerate every column that may be mutated via the `update_*` methods. Other fields (`id`, `campaign_id`, FKs to immutable referents) are rejected with `push_error`. Same defense-in-depth pattern as `TroopUnitRepository._UPDATE_FIELDS`.

- **Partial unique indexes for "at most one active X" semantics.** `army_unit_assignments` uses `CREATE UNIQUE INDEX ... WHERE released_calendar_day = 0` so a `troop_unit` may have at most one active assignment but unlimited historical (released) ones. SQLite supports this; insert collisions return false from `query_with_bindings` and the repository surfaces the failure cleanly. The same pattern applies to past-vs-active officers: rather than a separate index, the active-leader query filters `removed_calendar_day = 0` in WHERE clauses.

- **Resolver public API returns Dictionaries with `success` + `errors` + `warnings` triplets.** `ArmyComposer.compose(plan) -> {success, army_id, errors, warnings}` and `ArmyDisbander.disband(army_id, reason, day) -> {success, army_id, reason, units_released, mercenary_severance_gp, errors}`. Errors block; warnings are advisory (formation dialog displays them in an amber banner per the GDD). UI surfaces consume both lists for human-readable display. `ArmyValidator.validate_hierarchy(army, officers, assignments) -> {valid, errors, warnings}` follows the same shape.

- **Engine subsystems do not mutate world state outside their scope.** `RecruitmentVagariesResolver` is the canonical example: of the 19 vagary results, only `tribute` could conceivably be implemented in v1 with a treasury credit, but even that is left with `tribute_gp = 0` and a `needs_realm_resolution = true` flag in the payload. Real consequences (spawn brigand armies, generate NPC officers, apply price multipliers) belong to systems we have not built yet (Phase 7 Realm AI, Phase 8 Favors & Duties, Phase 6A part 2 mercenary market). The resolver emits a structured payload via `EventBus.recruitment_vagary_resolved(activity_id, result_key, payload)` and the consumer subsystems decide how to act on it. Same discipline applies to `ArmyCollisionDetector` (emits `armies_collided`; battle dispatcher in Phase 6B consumes) and `ExtractionResistanceHeuristic` (returns descriptor; resistance-battle scheduler in Phase 6A part 2 consumes).

- **Placeholder subsystems are explicitly named and documented as such.** `ExtractionResistanceHeuristic` is a v1 placeholder for the Phase 7 Realm AI subsystem. Its docstring states this directly; its 50% BR threshold heuristic per O-A-9 is a project-designed approximation of "will the local domain owner field forces?" The subsystem will be replaced wholesale when Realm AI lands. Same pattern for `ArmyCollisionDetector.classify_hostility()` (placeholder hostility = different `political_owner_id`; replaced by realm-graph allegiance lookup).

- **`var _` is a parse error — use `var _unused` and put it to work.** GDScript rejects `var _ = expression` because `_` is not a valid identifier on its own. To suppress an unused-variable warning when the value still needs to be evaluated for side effects, use `var _unused := expression` and follow with a meaningful operation (e.g. `check(_unused.size() == 3, "...")` in tests, `if _unused < 0: ...` in production code). Do not silence warnings via `_` — it does not work.

- **Game-day calendar timestamps are INTEGER columns, not strings.** Every `*_calendar_day` column on Phase 6A tables (`armies.formed_calendar_day` / `disbanded_calendar_day`, `army_officers.appointed_calendar_day` / `removed_calendar_day`, `army_unit_assignments.assigned_calendar_day` / `released_calendar_day`, `army_supply_state.last_supply_check_calendar_day`, `reconnaissance_cooldowns.last_roll_calendar_day`) stores an integer absolute game-day index. A non-zero value means "set"; zero means "unset / never." This matches Phase 5's `troop_units.hire_calendar_day / departure_calendar_day` and Phase 3's `activity_state.started_calendar_day`. UI layers convert to/from human-readable dates via the existing `Timekeeping` autoload.

- **Sub-unit encounter handling is a three-option player choice, NOT an automatic resolution.** `EncounterScaler.classify(encounter, army_id)` returns `options=[ignore, engage_with_party, destroy_with_army]` when the man-equivalent threshold (20) is not reached. The default recommendation is `ignore`. The engine never picks for the player; the UI surfaces the modal. Per O-A-10 resolution, `destroy_with_army` does not record army casualties — overwhelming odds is the design intent.

- **The 19-row Vagaries-of-Recruitment table is sacred and centrally defined.** `RecruitmentVagariesResolver.VAGARY_TABLE` is the single source of truth. Every entry is `[roll_low, roll_high, result_key, summary]`. Adding new entries means adding a row; modifying existing ones means changing the row. Do not duplicate the table elsewhere or hardcode roll bands in callers — always go through `lookup(roll)` or `resolve(...)`. RAW citation: `daw_vagaries.xml` §vagaries_of_recruitment L24-185.

- **Hex-path input is a list of Dictionaries with terrain + override flags.** `SupplyCalculator.compute_weighted_path_length(path, race)` takes `Array[Dictionary]` where each entry has at minimum `{"terrain": String}` and optionally `{"is_road", "is_settled", "is_navigable_waterway", "enemy_present"}`. The override flags take precedence over the base terrain key. Paths are produced by an upstream pathfinder (Phase 6A part 2 lands the army-aware variant); the supply calculator stays terrain-agnostic and only consumes the descriptor.


## 35. Field Battle Resolver Conventions (2026-05-08)

Conventions established while building Phase 6B part 1 (`engine/subsystems/armies/`, migrations 075-077, GDD `gdd-army-warfare.md` §6).

- **`int(null)` and `String(null)` raise "Invalid call 'X' constructor" in Godot 4 GDScript.** SQLite NULL columns surface as Godot null. `int(null)` and `String(null)` on a Variant containing null both fail at runtime with misleading error messages (e.g., "Invalid call 'String' constructor: <some_value>"). The fix is `_safe_int(variant, default)` and `_safe_string(variant, default)` helpers that null-check first. `FieldBattleResolver._safe_int(...)` and `RetreatResolver._safe_string(...)` are the canonical implementations; copy or reuse the pattern when reading nullable columns. Common cases: `armies.hex_q / hex_r / map_id` (NULL while assembling), `army_supply_state.supply_base_stronghold_id`, any optional FK or coordinate column. **Tests must always set nullable fields explicitly** when the test exercises a path that reads them, otherwise the NULL surfaces and fails. Repository update calls that whitelist nullable fields are authoritative — use `_safe_*(...)` for read-side coercion.

- **Battle log is append-only, sequence-numbered, JSON-payloaded.** `BattleRepository.append_log(battle_id, event_type, turn, phase, bpc, side, payload, calendar_day)` auto-allocates the next sequence_number per battle (UNIQUE constraint enforces). `payload_json` is `JSON.stringify(payload)`. Reading via `JSON.parse_string(row["payload_json"])`. The full event_type enumeration is the `gdd-army-warfare.md` §2.6 list. **Never log the same event_type to the same sequence twice** — append once at decision/transition points, not multiple times within a step.

- **Dice-roller Callable convention: `func(count: int, sides: int) -> int` returns the TOTAL of `count` dice with `sides` faces.** Not a per-die value — the full roll total. Resolvers test if the Callable is valid; if not, fall back to `randi_range(1, sides)` summed `count` times. **Test rollers** that need to control the dice should return the desired total directly: `func(_c, _s): return 7` makes every roll return 7. Per-call lambdas with `int(...)` casts of Variant captures (e.g., `int(dice_idx[0])`) can trigger the int-constructor bug; prefer simple lambdas without explicit casts, OR use class methods bound via `Callable(self, "_method_name")`.

- **The four-zone deployment is canonical: missile / skirmish / melee / reserve.** Every battle_unit_state row carries a `zone` column from this enum. Cascade order on hit overflow per RAW §battle_resolution.phase[*].procedure step 7 is phase-specific:
  - missile-phase overflow → skirmish → melee → reserve
  - skirmish-phase overflow → melee → reserve
  - melee-phase overflow → reserve → skirmish → missile
  Hardcoded in `FieldBattleResolver.CASCADE_ORDER`. Do NOT change this order — it is RAW.

- **Per-side BR totals apply Strategic-Ability division bonuses + status modifiers.** When totaling BR for a phase: each unit contributes `br_current` (snapshot decremented by absorbed hits), modified by status (×0.5 wavering, ×1.5 rallied, 0 if destroyed/routed/fleeing), plus the army-leader's Strategic-Ability division bonus per RAW §battle_ratings.strategic_ability L198-201 (+0.5 per unit at SA ≥3, +1.0 at SA ≥6). The overwhelmed-commander BR-halving per §battle_ratings.overwhelmed_commanders L202-205 is applied at deployment time when individual unit BR is snapshotted into `br_at_battle_start` — the runtime BR-totaling does not re-apply it.

- **Attack-throw modifiers are subtracted from the target, not added to the roll.** RAW expresses modifiers as ±N to the attack throw target (e.g., "skirmish 16+, lieutenant_leading +1, surprise +2"). v1 implementation stores `target = base_target - modifiers` (e.g., 16 - 3 = 13 effective target) and rolls 1d20 ≥ effective_target for hits. This matches RAW math while keeping the d20 roll unchanged.

- **Phase transitions reset BPC to terrain-derived starting count.** Per RAW §battle_resolution.phase[*].procedure step 1: "Set BPC to starting count based on terrain." On `transition='advance_phase'` or `'regress_phase'`, the resolver writes `current_bpc = starting_bpc` to the battle row before the next phase loop iteration. The `starting_bpc` column is set ONCE at battle setup and never modified afterward.

- **Heroic-foray engine surface is decoupled from the combat resolver.** `HeroicForayResolver` provides:
  - `is_qualifying_hero(...)` for eligibility
  - `compute_foe_pool(...)` for foe-BR-target → foe-unit-id selection
  - `encounter_distance_yards(...)` for the per-terrain × per-phase RAW table
  - `apply_foray_outcome(foes_defeated_br, opposing_unit_state_ids, day)` to remove opposing units' BR equal to defeated foe BR
  - `simulate_foray_silently(...)` is a v1 placeholder for NPC-vs-NPC silent battles
  The actual ACKS combat sub-scene resolution (full HP/AC/initiative/attacks for 6 rounds) lives in the standard combat resolver and is Phase 6B part 2's wire-up target. Until then, NPC heroes don't declare forays in silent battles (heuristic in `field_battle_resolver._silent_choice` keeps it that way) and PC forays go through `simulate_foray_silently` as a deterministic-stochastic placeholder.

- **Casualty resolver applies losses to underlying troop_units rows permanently.** `ArmyCasualtyResolver.resolve_battle_casualties(battle_id, day)` walks every `battle_unit_states` row, computes per-RAW casualty profile (50/50 destroyed; 25/25 routed/fleeing; BR-loss-fraction proportional for survivors), updates `troop_units.count`, flips `is_veteran=1` on ≥50%-loss survivors, and marks `status='departed'` on units reduced below 50% operational. **Do not call this multiple times per battle** — it modifies underlying `troop_units` rows.

- **Pursuit-throw targets are unit-type-keyed, not roll-keyed.** The 11+/14+/14+/18+ targets per RAW §pursuit_throw_targets L588-598 map to:
  - light_cavalry / flyer → 11+
  - other cavalry → 14+
  - light infantry → 14+
  - other infantry → 18+
  Hardcoded in `PursuitResolver.TARGET_*` constants. Substring matching on `troop_units.troop_type` decides which target applies. Substring keywords: `LIGHT_CAVALRY_KEYWORDS = ["light_cavalry", "light_cav", "flyer", "flying"]`, `OTHER_CAVALRY_KEYWORDS = ["cavalry", "horsemen", "lancer", "knight"]`, `LIGHT_INFANTRY_KEYWORDS = ["light_infantry", "light_inf", "skirmish", "slinger"]`. Update these when new troop types land.

- **Battle dispatcher hostility classification consults RealmGraph (Phase 7).** `BattleDispatcher.dispatch_collision` calls `ArmyCollisionDetector.classify_hostility`, which is now a thin wrapper around `RealmGraph.classify_hostility_for_armies` (Phase 7). Pre-Realm-graph fast path: identical political_owner_id → friendly. Otherwise resolve each army's apex via owner's owned-domain → liege chain root and compare. Same-apex / allied-apex (Phase 8 wiring) → friendly; everything else → hostile. `ExtractionResistanceHeuristic` (Phase 7 refactor) consults `RealmGraph` directly to federate vassal forces. The weekly Vagaries-of-War tick (Phase 7 `ArmySupplyTracker.run_supply_tick` step 5) consults `InEnemyTerritoryPredicate.is_eligible_for_war_vagary` which composes the same realm-graph apex resolution.

- **Save/load reconstruction via `get_battle_state(battle_id) -> {battle, unit_states, log}`.** A paused player-involved battle persists entirely through these three table sets (field_battles + battle_unit_states + battle_log) plus the EventScheduler's pause-state. The interactive UI rebuilds from `get_battle_state` on reopen. **Nothing battle-related lives in volatile scene state** — the resolver writes every transition to the database before pausing.


## 36. Realm AI Subsystem Conventions (2026-05-08)

Phase 7 introduced `engine/subsystems/realm_ai/` with 7 RAW-driven helpers (RealmGraph, InEnemyTerritoryPredicate, VagariesOfWarResolver, VassalRepository, RealmAggregator, TributeCalculator, RealmTitleResolver). Patterns established:

- **Static-helper RefCounted classes for stateless RAW math.** RealmGraph, TributeCalculator, RealmTitleResolver, VagariesOfWarResolver, InEnemyTerritoryPredicate, and VassalRepository all use `class_name X extends RefCounted` with only static methods. No instance state, no autoload. Callers invoke via `RealmGraph.apex_for_domain(id)` directly. RealmAggregator is the same pattern. Match this for any new RAW-table helper.

- **Apex-walk cycle guards.** Liege chains may be malformed (cycles, very deep). Use a hop-count cap (`_MAX_LIEGE_HOPS = 64` in RealmGraph) and `push_error` on exhaustion. For recursive sums (RealmAggregator), use a depth cap (`_MAX_DEPTH = 8`) PLUS a visited-character-id set passed down the stack to short-circuit revisits.

- **Banker's rounding everywhere economic.** TributeCalculator implements its own `_bankers_round(value: float) -> int` (round half to even) per CLAUDE.md core principle. Tolerance: `EPS = 1e-9` for the .5 detection. Use this pattern (NOT `round()`, NOT `int(value + 0.5)`) for any gp computation that touches the database.

- **RAW PATCH lock-ins via inline comments + named test cases.** When a RAW table has a documented project-interpretation correction (e.g., the [RESOLVED 2026-05-06] 17-63 = 50% efficiency band correcting source XML's "17-36"), the implementation file's data table carries an inline comment citing the source line and the project decision; the test suite has at least one explicitly named test method that asserts the corrected reading at boundary values. Pattern: `test_efficiency_factor_resolved_2026_05_06_17_63_band` — the date and band call out the specific RAW PATCH it locks in.

- **Liege-chain inverse pointers vs vassal_assignments.** `domains.liege_domain_id` (Phase 0 column) is the source of truth for the realm-graph apex walk and for tribute computation. `vassal_assignments` (Phase 7 table) records the *appointment* + loyalty/status state of each vassalage. The two carry independent constraints — liege_domain_id is the geographic / fiscal pointer; vassal_assignments is the relationship history. Update both when appointing or revoking a vassal.

- **Partial unique index for "at most one active X per pair".** `vassal_assignments` uses `CREATE UNIQUE INDEX ... WHERE status = 'active'` so departed/revolted/deceased rows stay for history while preventing double-active vassalage. Same pattern as `army_unit_assignments(troop_unit_id) WHERE released_calendar_day = 0`. Established convention for any entity that has lifecycle transitions but should have a single live row per relationship key.

- **Tribute flow direction.** A vassal pays its OWN realm's `compute_tribute_base_gp` (sum of vassal's personal + sub-vassal-realm families) to its liege. The liege's efficiency factor (`efficiency_factor(liege.direct_vassal_count)`) is applied to what the LIEGE RECEIVES, NOT to what the vassal pays. Per RAW §tribute "Each month, a ruler collects tribute from vassals and pays tribute to a superior lord if any" — vassal accounting per their own realm size, liege accounting per their direct-vassal count.

- **Allied realms are a Phase 8 concern.** `RealmGraph.is_allied(apex_a, apex_b)` is a stub returning false in v1 — the Office mechanic in `acore_axioms` §favors_and_duties (Phase 8) is what creates alliance edges. The structure is in place (function signature, RESULT_ALLIED constant, classify_hostility_by_apex consults it). When Phase 8 lands, populate a `realm_alliances` table and replace the stub with a SELECT.

- **Vagary-of-war handler scope: full vs signal-only.** Of the 28 results in `daw_vagaries.xml` §vagaries_of_war, v1 implements 7 with full mechanical effects (`all_quiet`, `good_omen`, `ill_omen`, `supply_problems`, `supply_boon`, `war_profiteers`, `commander_casualty`). The other 21 emit signal-only via `_signal_only(kind, summary)` returning `{applied: false, kind, summary, note: "v1 stub"}`. Callers / tests detect signal-only handlers via `payload.applied == false`. When you implement a stubbed handler, replace `_signal_only(...)` with a real handler returning `{applied: true, kind, ...}` and remove the stub note.

- **HenchmanLoyaltyResolver dice convention is a node-like with `roll(count, sides) -> int` method.** NOT a Callable. Tests use `class FakeDice extends RefCounted { var fixed_total: int; func roll(_count, _sides): return fixed_total }`. ExtractionResistanceHeuristic (Phase 7) follows this convention (its `dice` arg is `dice = null`, untyped, so `null` falls through to randi-based fallback in HenchmanLoyaltyResolver). Match this pattern for any helper that wraps a HenchmanLoyaltyResolver invocation.

- **Monthly-tick `tribute_in` / `tribute_out_owed` / `realm_title` are derived properties.** `domain_handlers._resolve_domain_month` computes them every monthly tick from the current realm aggregate; the persisted columns are write-only (set in `_save_domain` via the `_DOMAIN_MONTHLY_FIELDS` whitelist). Callers should NEVER write `tribute_out_owed` directly — let the monthly tick recompute. The same applies to `realm_title`.


## 37. Phase 8 — Favors & Duties Conventions (2026-05-08)

Phase 8 adds the monthly favors-and-duties cycle on top of Phase 7's vassal_assignments. New patterns:

- **Obligation rows are append-only history.** `vassal_obligations` rows are NEVER deleted. Status transitions to revoked / completed / defaulted preserve the row for audit/UI history. The `most_recent_active(assignment_id, kind)` helper finds the latest active row for a kind; that's all the resolver needs to cancel on a revoke roll.

- **Per-issue loyalty penalty stored on the obligation, not the assignment.** When a duty exceeds the safe-duty threshold, the cumulative -1 penalty is applied to the loyalty roll AT issue time and recorded in `vassal_obligations.loyalty_modifier_applied` for audit. Future loyalty rolls on the same vassal don't re-apply the penalty — it's a per-issue snapshot. This avoids drift if obligations change later.

- **D20 dispatcher pattern repeats.** FavorsDutiesResolver's TABLE constant + classify_roll() iteration mirrors VagariesOfWarResolver's `TABLE_PATH` / `classify_roll` exactly. Both use an array of `{min, max, ...}` entries and in-order linear search; both have a docstring section enumerating handler scope (full vs signal-only). Match this when adding any new RAW d20/d100 dispatcher.

- **Sub-roll for ambiguous RAW outcomes.** When a RAW result row contains compound text with explicit "if 1, ... if 2-6, ..." wording (e.g., the §favors_and_duties revoke row at L366), implement as a 1d6 sub-roll with the same FakeDice convention. Document the interpretation in the resolver's docstring AND in the build log decision section.

- **Mechanical-effect scope is the deferred subsystem's responsibility.** When an obligation type's full mechanical effect depends on a not-yet-built subsystem (e.g., Charter of Monopoly → Phase 10 commerce), implement the obligation creation + signal emission only; the persisted obligation row is the contract. The dependent phase reads the obligation table to actuate effects. Don't try to scaffold the dependent subsystem prematurely.

- **`liege_domain_id` write at appointment time.** When VassalAppointmentDialog creates a vassal_assignment, it ALSO updates the vassal-domain's `liege_domain_id` to point at the liege's primary domain. This keeps the RealmGraph apex walk consistent immediately. Pattern: any UI flow that mutates the realm graph must update both the vassal_assignments row AND the affected domain's liege_domain_id in the same transaction (no scheduler-tick reconciliation required).

- **Dice convention extends to d20/d6 sub-rolls.** Same node-like with `roll(count, sides)` method as HenchmanLoyaltyResolver. The FakeDice test pattern handles 1d20, 1d6, AND 2d6 (HenchmanLoyaltyResolver fallback) in a single class via `if count == 1 and sides == 20: ... elif count == 1 and sides == 6: ... elif count == 2 and sides == 6: ...`. Tests should set per-die fixed values explicitly (`fixed_d20`, `fixed_d6`) to avoid cross-roll contamination.

- **Custom signal naming on ConfirmationDialog subclasses.** Godot's `ConfirmationDialog` has built-in `confirmed` / `canceled` signals — redefining them causes a parse error (`Member "confirmed" redefined`). Convention: prefix custom signals with the action's noun, e.g. `vassal_appointed`, `appointment_cancelled`, NOT `confirmed`/`cancelled`. Same caution applies to `AcceptDialog` (which inherits `confirmed`).

- **Henchmen-tab right-click menu is the canonical vassalage entry point.** Items added in Phase 8: "Manage domain" (greyed if no domain), "Appoint as vassal" / "Revoke vassalage" (toggles based on existing assignment). All items toggle their visibility/disabled state via cheap repository checks (`VassalRepository.get_active_assignment_for_vassal`, `_henchman_owns_domain`). Don't accumulate menu state in the henchmen-tab's instance variables — recompute per-show.

- **Scutage as expense subcategory.** Scutage is NOT a separate ledger category; it's a subcategory under "expense" alongside garrison/liturgy/maintenance/tithe/repression. The pattern: `domain_handlers._compute_active_scutage_gp_for_domain` reads the active scutage obligations on the vassal-side assignment and the value is patched into the `expenses` dict before the ledger write. RAW L362: "Scutage ... counts as garrison expense for the vassal" — we treat it as its own subcategory rather than rolling into "garrison" so the ledger UI can surface it distinctly.

- **TradeRangeResolver hex distance via axial → cube formula.** `_axial_hex_distance(q1, r1, q2, r2)` uses the standard `(|dq| + |dr| + |ds|) / 2` where `ds = (-q1-r1) - (-q2-r2)`. Match this when computing inter-hex distance anywhere in the codebase — don't roll your own.


## 38. Domain Encounter / Bandit / Threat Subsystem Conventions (2026-05-08)

Phase 9A introduced `engine/subsystems/domains/` resolvers (domain_encounter_resolver, bandit_spawner, npc_challenger_emergence, market_class_modifier_resolver) + `domain_threat_repository`. Patterns established:

- **Throws-per-month compression for daily/weekly RAW frequencies.** RAW says civilized=monthly, borderlands=weekly, wilderness=daily encounter throws. A literal implementation fires up to 365 events/year/wilderness-domain via the EventScheduler — burns context. Pattern: roll N times in the monthly tick (1 / 4 / 30 throws). Same RAW probability distribution, same expected count over a year. `DomainEncounterResolver.THROWS_PER_MONTH` constant. Apply this pattern to any RAW mechanic with sub-monthly cadence whose effects only matter on month-grained boundaries.

- **Partial-unique-active indexes for "at most one X per domain at a time."** `domain_threats` uses `WHERE kind='bandit_swarm' AND status='active'` and `WHERE kind='npc_challenger' AND status='active'`. Same pattern as `vassal_assignments(liege, vassal) WHERE status='active'` and `army_unit_assignments(troop_unit_id) WHERE released_calendar_day=0`. Established convention: any entity with lifecycle transitions but a "currently-active" cardinality constraint goes through partial-unique-index.

- **Idempotent monthly sync vs. event-driven create.** `BanditSpawner.sync_for_domain(domain_data, calendar_day)` is idempotent — call it every monthly tick and it spawns / updates / disperses based on current morale. `DomainEncounterResolver.roll_monthly_encounters_for_domain` is event-driven — fires on each successful roll, may add multiple encounter rows in one tick. Pattern: state-tracking subsystems use idempotent sync; rare/random events use event-driven create. Never combine the two (don't make sync probabilistic).

- **Accumulator state stored on a related row's payload_json.** `NPCChallengerEmergence` stores its monthly-accumulating threshold on the bandit_swarm threat's `payload_json["challenger_threshold"]`. Avoids a dedicated `challenger_thresholds` table whose lifetime is intrinsically tied to the swarm anyway. Pattern: when an accumulator's lifetime matches an existing entity's lifetime, store it on the entity's `payload_json` instead of creating a new table.

- **Compound, not additive, percentage modifiers.** RAW war_profiteers says "+10% (cumulative on each repeat)". Project interpretation: cumulative = COMPOUNDED (1.10 × 1.10 = 121%, not 1.10 + 1.10 = 220%). `MarketClassModifierResolver.price_multiplier_for_category` and `DomainThreatRepository.sum_price_multiplier_pct` implement compounding. Apply compound semantics whenever RAW says "cumulative" without specifying additive — the alternative produces degenerate stacking outcomes (10 stacked = 1100%).

- **Lowest market_class number = largest settlement.** Class I = 1 = largest, class VI = 6 = smallest (per ACKS). `RecruitmentVagariesResolver._largest_urban_settlement_for_character` uses `ORDER BY market_class LIMIT 1` (ascending). When you see ORDER BY market_class anywhere, default to ascending = largest-first.

- **Side-effect dispatcher pattern for vagary resolvers.** `RecruitmentVagariesResolver._apply_side_effects(result_key, character_id, calendar_day, payload)` is invoked from `resolve()` AFTER `build_payload()`, BEFORE the EventBus signal. Stub results (no side effects yet) return `{}`. Implemented results return `{applied: bool, ...}` and the result is attached to payload as `side_effect`. Pattern: keep `build_payload()` PURE (no side effects, deterministic from inputs), put all DB writes / signal emits in the dispatcher. Same pattern as `VagariesOfWarResolver._dispatch()`.

- **Monthly-tick orchestration order: expire → encounter → bandit → challenger.** In `domain_handlers._resolve_domain_month`, market modifier expiry runs FIRST (so this month's effective class is current), then encounter rolls, then bandit sync, then challenger accumulation. Pattern: any monthly-tick orchestrator that touches multiple resolvers should expire-active-state BEFORE generating new state, and update derived state (bandit count from morale) AFTER the source state has settled (morale resolved + growth applied).

- **post_morale_data dictionary for resolvers that need post-resolution snapshot.** The encounter / bandit / challenger calls all need `domain_data` AS IT WILL BE AFTER this month's resolution — current morale (post-resolve), projected family count (post-growth). Pattern: build a duplicate dict mutating the relevant fields for the current call, don't mutate the canonical `domain_data` (which is still the pre-tick row).

- **Threat row over event-only signal for state-bearing threats.** Encounters that linger, bandit swarms, and NPC challengers all create a `domain_threats` row, NOT just a signal. The signal is for UI / log subscribers; the row is the source of truth. Pattern: when a "threat" has duration / status / response state, it gets a row; transient "this happened once" notifications stay signal-only.


## 39. Phase 9B — Siege Subsystem Conventions (2026-05-09)

Phase 9B introduces `engine/subsystems/sieges/` (10 modules) + 4 migrations (sieges, siege_actions, siege_artillery, siege_mines) implementing the full DaW siege resolver per `rules/daw_sieges.xml`. Patterns established:

- **All siege economic state in cp, not gp.** Project convention (PartyWallet, deduct_cost_cp, wealth_cp). `stored_supplies_cp`, `supplies_delta_cp`, `construction_rate_cp_per_day`, `MINE_BASE_COST_CP`, `PRISONER_VALUE_CP`, `CIRCUMVALLATION_CP_PER_100FT`. RAW gp values × 100. UI displays convert cp→gp at the formatter. No `_x100`-style integer hacks — daily-grain values that would otherwise be fractional gp (e.g., 8.57 gp/day consumption) are stored as plain integer cp (857). Drift across the siege is sub-cp at typical durations.

- **Per-action ledger row for every state mutation.** `siege_actions` captures every bombardment day, mining tick, repair, hijink, supply consumption, and assault turn with the modifier breakdown in `payload_json`. Source of truth for the UI's per-day siege history AND for the Inspect-math affordance (mirrors `battle_log` from Phase 6B). Convention: any sub-resolver that modifies sieges-row state MUST also append a siege_actions row capturing the inputs and computed deltas. Tests can read the ledger to verify resolver math without poking internals.

- **Static-class subsystem pattern with whitelisted UPDATE.** All 10 siege modules use `class_name X extends RefCounted` with static methods; persistence routes through `CampaignRepository.db`. `SiegeRepository.update()` and `update_mine()` use `_SIEGE_UPDATE_FIELDS` / `_MINE_UPDATE_FIELDS` arrays to reject non-whitelisted writes (push_error + skip). Same pattern as VassalRepository (Phase 7) and DomainThreatRepository (Phase 9A). When you add a siege column that the resolver writes via `update()`, you MUST add the column name to the whitelist or the write silently no-ops.

- **Single source of truth for unit_capacity / breach math.** `UnitCapacityCalculator` owns ceil(shp/1000) and floor(damage/1000). `siege_resolver.gd`, `siege_blockade_calculator.gd`, `siege_resolver_simplified.gd`, `siege_intervention_handler.gd` all call into it. The grid-mapped v1.1+ swap-in (per-structure unit_capacity summing) is a one-method replacement of `compute_unit_capacity`; everything else stays. Convention: per-domain or per-stronghold derived values that have a "v1 estimate vs. v1.1 mapped" axis should live in a dedicated calculator class with a stable interface.

- **EventScheduler tick orchestration: daily owns its own re-scheduling.** `SiegeResolver.tick_daily(siege_id, day, dice, scheduler)` ends by calling `scheduler.schedule_at(day+1, "siege_daily_tick", siege_id, ...)` if the siege didn't conclude. The handler in `SiegeHandlers._handle_daily_tick` does NOT pass `next_events` back through the registry — the resolver owns its own cadence. Same for `tick_weekly`. Convention: long-running activities that internally know their cadence should self-reschedule rather than relying on the registry/handler scaffold to chain events. This avoids a class of bugs where the handler reschedules unconditionally even when the underlying activity has ended.

- **Mode-flip cancels rival-mode events.** `SiegeInterventionHandler.escalate_to_full(siege_id, day, scheduler)` MUST `scheduler.cancel_all_for_owner(siege_id, "siege_simplified_concluded")` before scheduling daily/weekly ticks. The two resolution modes' scheduled events must NEVER coexist for the same siege — if they did, both would fire and you'd get a double conclusion. The symmetric (currently unused) de-escalation would cancel `siege_daily_tick` / `siege_weekly_tick`. Pattern: any state machine that has a mode flip with mode-scoped scheduled events must own a transition handler that purges the rival-mode events.

- **Casualty-cleanup field battle is NPC-vs-NPC simplified path ONLY.** RAW §casualties_in_simplified_sieges L831-836 says simplified sieges resolve a final battle for casualty purposes. This applies ONLY when `sieges.resolution_mode = 'simplified'` at conclusion time. Player-involved sieges (mode='full') always follow the Blockade → Reduction → Assault flow; the defender surrendering ends the siege without an assault, capture/destruction without surrender ends via `check_end_conditions`. `SiegeResolverSimplified.resolve_simplified_conclusion` defensively checks mode and bails if the dispatcher escalated to full before now.

- **Subversion breach is ephemeral, expires at next daily tick.** RAW §subversion L450 says subversion breaches "must be exploited immediately with an assault or are lost." Project interpretation (CONFIRMED 2026-05-09): same calendar-day assault consumes the breach; otherwise the next daily tick decrements `breach_count` and clears `pending_subversion_breach_until_day` from `payload_json`. `SiegeReductionResolver.reap_expired_subversion_breach(siege_id, day)` is called as the FIRST step of `SiegeResolver.tick_daily`. Pattern: ephemeral state with a same-day window goes on `payload_json` with a daily-tick reaper (reap-first ordering ensures the window is honored exactly).

- **Repair cap is cumulative across the siege, not per-day.** RAW §stronghold_repair L460 ("only half of all damage sustained during the siege can be repaired") is interpreted as `damage_repaired_total ≤ 0.5 × damage_dealt_total` over the siege's lifetime (CONFIRMED 2026-05-09). The cap is enforced in `SiegeReductionResolver.repair_overnight` by computing `cap_remaining = max(0, max_repair_total - damage_repaired)` before clamping `shp_to_repair`. Pattern: when RAW says "X can only Y a fraction of Z accumulated during the siege," store both running totals (`*_dealt_total`, `*_repaired_total`) on the entity row and compute the cap on read.

- **One-shot NPC owner for autogenerated armies (Option A).** `armies.political_owner_id` is `NOT NULL REFERENCES characters(id)`. When `BanditSpawner.materialize_swarm_as_army()` or `NPCChallengerEmergence.materialize_challenger_as_army()` creates an army on demand, it auto-creates a one-shot 'npc' 'named' character (Bandit Captain / the challenger) to satisfy the FK. The character persists after the army is destroyed for log/audit purposes (loot routing, XP attribution). Pattern: when an FK requires a character row but the entity is conceptually "no specific person" (bandits, generic NPCs), prefer creating a persistent named NPC over relaxing the FK — the audit trail benefits outweigh the row count.

- **persistence_tier='named' for one-shot owner NPCs, NOT 'reduced'.** The schema's CHECK constraint accepts `('full', 'named', 'transient')`. Phase 9A's `NPCChallengerEmergence._create_challenger_character` mistakenly uses `'reduced'` (not in the constraint, fails INSERT). Phase 9B helpers use `'named'`. Convention: when creating one-shot NPCs from any subsystem, validate against the actual CHECK constraint, not against assumed tier names. (Phase 9A bug queued for fix.)

- **Static caching of JSON tables loaded once.** `SiegeResolverSimplified._duration_table`, `_bonus_units_table`, and `SiegeReductionResolver._artillery_table` are `static var` Dictionaries lazy-loaded on first access via `_ensure_tables_loaded()` / `_ensure_table_loaded()`. Same pattern as Phase 9A's `BanditSpawner._scaling_data` and `DomainEncounterResolver._encounter_table`. Convention: data tables loaded from `res://data/...` JSON files at runtime should be `static var Dictionary` cached on the class, lazy-loaded via a private `_ensure_*_loaded()` helper that early-returns if non-empty.


## 40. Phase 9C — Disease + Call to Arms + Hex Icons + 9B Polish (2026-05-09)

Phase 9C bundles the disease vagary loop, Call to Arms troop muster, hex-map landmark icons, the five Phase 9B polish items, and the Phase 9A persistence_tier bug fix. Patterns established:

- **Per-troop disease state via boolean column, not `status` enum extension.** Migration 088 adds `is_diseased`, `disease_type`, `disease_recovery_calendar_day`, `disease_save_failed_by`, `disease_natural_roll` to troop_units. SQLite's CHECK constraint on `status` would force a table rebuild to add 'diseased' as a value; a boolean column is cheaper, doesn't break existing queries, and lets `status` retain its lifecycle semantics ('active' / 'departed'). Pattern: when a temporary state needs tracking on an existing row whose `status` column has a CHECK constraint, prefer adding new columns over extending the enum. Diseased units stay status='active' with is_diseased=1.

- **Secret saves: engine knows, normal UI gates.** Per RAW daw_vagaries §disease L304, disease saves are made secretly so commanders don't know which units will recover. v1 implementation: engine stores death_threshold, recovery day, failed_by, and natural_roll on the troop_units row; UI shows only the "Diseased" status label until duration expires (per O-9C-3 confirmation: no "recovery uncertain" append needed). Inspect-math debug affordance reveals all. Pattern: for any RAW mechanic that explicitly hides info from the player, store full state in the engine but expose only the public status via repository surface; deeper inspection lives in a debug-only path.

- **Natural-1 always kills, regardless of death_if_failed_by threshold.** Per RAW L301-302 + O-9C-2: `died = (failed_by >= death_threshold) OR (natural_roll == 1)`. Encode `bloody_flux` (natural-1-only death) as `death_if_failed_by = 999` so the threshold check fails harmlessly while the natural-1 OR clause catches it. Pattern: when RAW says "X always kills regardless of normal threshold," encode the normal threshold as an unreachable sentinel and let the OR clause carry the X-kills semantics.

- **Cure pipeline aggregates fractional capacity with carry-forward remainder.** Per RAW L307-310 + O-9C-4: 5 healer tiers (L9 caster=1.0, L7-8 caster=0.5, L6 caster or chirugeon=1/3, physicker=1/9, healer=0/no cure). Project mapping: Healing proficiency rank 2 = physicker, rank 3 = chirugeon (rank 1 healer has no mass-army cure capability per RAW omission). `DiseaseResolver.compute_cure_capacity_per_week(army_id)` sums all sources across attached PCs/henchmen/officers; `tick_weekly_cures` cures `floor(capacity + carry)` units and stamps the fractional remainder on `armies.daily_penalty_state["disease_cure_remainder"]` for next week. Pattern: when RAW specifies multiple healer tiers contributing fractional throughput, encode cure rates as floats and carry forward fractional remainder on the actor's state row.

- **Class name collision avoidance: prefer descriptive resolver names over generic `*Handler` patterns.** Phase 9C originally used `CallToArmsHandler` for the new resolver, which collided with the Phase 3 activity-executor stub at `engine/subsystems/activities/handlers/call_to_arms.gd` (also `class_name CallToArmsHandler`). Renamed to `CallToArmsMuster`. Pattern: when adding a new module that resolves a domain concept, prefer a verb-noun like `*Muster`, `*Resolver`, `*Calculator`, or `*Spawner` over the generic `*Handler` — `*Handler` is reserved for activity-executor handlers under `engine/subsystems/activities/handlers/`.

- **Snapshot vs spawn for cross-army troop transfer.** Per O-9C-5: Call to Arms transfers existing troop_units rows from the vassal's garrison to the lord's army (release current `army_unit_assignments` row; create new one to lord's army). The troop_units identity is preserved across the transfer, and the assignment-history pattern (`released_calendar_day` stamping) captures the move. Revocation reverses the transfer back to the vassal's garrison army. Pattern: when RAW says one entity's resources physically move to another's command, snapshot via `army_unit_assignments` updates (preserve identity) rather than spawning fresh rows.

- **Tranche distribution as static helper for testability.** `CallToArmsMuster.tranche_size(target_total, tranche)` returns the size of tranche N (1, 2, or 3) per RAW L675-677 (½ ceil + ¼ floor min 1 + remainder). Avoid duplicating the math inline in three different code paths; expose as a pure static helper. Tests verify the math against multiple target sizes (100, 7, 1, etc.) without setting up DB fixtures.

- **Magnitude_pct on obligation, not duty count duplication.** Per O-9C-7: full-garrison call-to-arms (`magnitude_pct=100`) counts as 2 duties via `compute_duty_count(magnitude_pct) -> 2`, but is still a SINGLE physical obligation row (one DB write, one event). Avoids partial-unique-active constraint loosening, sibling-FK juggling, and the aesthetic problem of two rows for one event. Pattern: when RAW says "demanding X counts as demanding Y duties," encode X as a magnitude property on the obligation, NOT as Y separate obligation rows.

- **Hex landmark icon overlay as Node2D child of the renderer.** `HexMapLandmarkIcons` is a Node2D added below the party token but above the terrain layer. Sprites are added/cleared via `refresh(map_id, hex_to_pixel, fog_check)` — caller passes a Callable for hex→pixel mapping (decouples from HexMapController internals) and a Callable for fog gating. Pattern: cross-rendering-pass overlay nodes that need camera transforms but live above some layers and below others should be plain Node2D children of the renderer with their own `refresh()` API; the renderer is responsible for ordering.

- **Side-by-side layout when both landmarks present on one hex.** Per the user's reference image: 24×24 icon boxes with a 5-px gap when both a settlement and a stronghold occupy the same hex. Constants `ICON_SIZE_PX = 24` + `SIDE_BY_SIDE_GAP_PX = 5` + computed `SIDE_BY_SIDE_HALF_OFFSET_PX = 14.5` keep the math local. Settlement on left, stronghold on right (canonical reading order). Pattern: paired-icon overlays should be parameterized by box size + gap as constants, not magic numbers; `_HALF_OFFSET = (ICON_SIZE + GAP) / 2` is the correct centering formula.

- **Mode-flip cancels rival-mode events (extends to all phase 9 subsystems).** Established in Phase 9B; reapplied here:
  - The simplified-conclusion siege event is cancelled by `escalate_to_full`.
  - The Call-to-Arms tranche events are cancelled by `resolve_revocation` (revoked_calendar_day stamp prevents tranche handlers from firing — the partial-unique-active index `WHERE revoked_calendar_day = 0` makes future arrivals no-ops).
  - The disease_recovery_check event is cancelled implicitly by `tick_weekly_cures` when it fast-forwards a unit's recovery (resolve_disease_recovery clears is_diseased; the scheduler's pending event finds a non-diseased unit and bails harmlessly).

- **Refuse-battle morale penalty is read on monthly tick, not pushed.** Per O-9C-4 + RAW L627-630: refusing battle with an NPC challenger imposes -4 on monthly morale rolls. Implementation: `encounters_threats_sub_tab._on_refuse_battle_with_challenger_pressed` stamps `morale_penalty=4` on the threat row; `domain_handlers._event_modifiers_sum` reads it via `DomainThreatRepository.get_active_challenger_for_domain(domain_id)` and subtracts. No separate "morale event" table needed — the threat row is the source of truth. Pattern: persistent morale modifiers tied to a threat / event row should be summed at the morale-roll site, not pushed into a separate modifier ledger.

- **Bandit-defeat outcome reflows population AND flags potential revert.** Per RAW L617-625: defeating bandits restores +1 morale, captured bandits return as families, AND if morale is still ≤ -1 after the +1, the families revert to banditry next month. `BanditSpawner.apply_defeat_outcome(threat_id, day, killed, captured)` does all three: bumps morale via `update_domain_monthly_state`, increments peasant_families by captured count, AND stamps `payload_json["potential_revert_next_tick"]=true` on the (defeated) threat row when applicable. The stale defeated row's payload survives past status='defeated' to inform next month's bandit spawner sync. Pattern: post-resolution flags that influence next-tick behavior live on the resolved row's payload_json, NOT on a separate "next-tick to-do" queue.

- **NPC defender auto-repair gated on `_defender_is_pc_owned(siege_id)`.** Phase 9B's siege resolver explicitly skipped auto-repair; Phase 9C adds the heuristic for NPC-defended sieges only. Budget = `min(damage_today × 10, stored_supplies_cp / 100)` per day (intuition: spend up to 10× shp/day in cp, capped at 1% of supply pool to prevent immediate exhaustion). PC-controlled defenders explicitly invoke `apply_method('reduction_repair', {cp_to_spend})`. Pattern: AI-driven side-effects on long-running player-visible state should be gated on PC-owned checks; never mutate state under PC control without explicit player input.

- **Defender-cover flag is OR-ed across triggers.** `payload_json["besieger_has_cover_for_artillery"] = true` set by EITHER complete circumvallation OR besieger-side movable_mantlet/movable_gallery addition. Once true, stays true until siege concludes. The artillery duel resolver reads this flag to apply RAW L236-237 (defender 5 misses with cover). Pattern: state flags representing "any-of-N triggers met" should be set independently by each trigger and never reset until the parent state ends.

- **Sally outcome glue stamps `pending_sally_battle_id` on payload, then maps via dedicated handler.** Per RAW L780-783, the siege ends regardless of who wins the sally battle. `_begin_sally` stamps the pending battle id; `handle_battle_concluded_for_sally(siege_id, battle_id, battle_outcome, day, scheduler)` is the dedicated mapper called by a battle_concluded listener. Pattern: cross-subsystem state transitions that depend on a pending event's outcome should leave a "pending" key on the source row's payload, then be cleared by a dedicated handler that consumes the event.

- **Scheduler tranche event pattern.** New event types added to siege_handlers.gd registration: `disease_recovery_check` (owner=troop_unit_id), `call_to_arms_tranche_arrival` (owner=call_to_arms_state_id, data["tranche"] ∈ {1,2,3}). Pattern: when a long-running activity has a small finite number of stages, schedule one event per stage at issue time (rather than re-scheduling at each stage's resolution). Cancellation is handled via `cancel_all_for_owner(state_id, event_type)`.


## 41. Phase 9C polish addendum — five carry-forward conventions (2026-05-09)

Phase 9C polish lands the 5 carry-forward items documented in §40. Patterns established beyond what §40 already captured:

- **Per-troop save column with tier-based backfill defaults.** Migration 090 adds `save_vs_death INTEGER NOT NULL DEFAULT 14` to troop_units, then backfills via separate UPDATEs by tier (untrained=16, average=14, veteran=12). SQLite's `ALTER TABLE ADD COLUMN` doesn't support `CASE` in DEFAULT; the migration runs the column-add + tier-conditional UPDATEs as separate statements. Pattern: when migrating to a tier-derived column default, do the ALTER first with a safe scalar default, then UPDATE WHERE tier = X for each tier.

- **Resolver fallback constants when DB column might be 0/missing.** `DiseaseResolver.FALLBACK_SAVE_VS_DEATH_TARGET = 14` guards against malformed troop_units rows with `save_vs_death = 0`. The resolver reads `int(unit.get("save_vs_death", 0))` and falls back to the constant if `<= 0`. Pattern: when a column has a meaningful zero (i.e. zero is invalid for the resolver's purposes), explicitly check for it and fall back to a documented constant rather than silently using zero.

- **Optional `scheduler` parameter threaded through static-method call chains.** `FavorsDutiesResolver.roll_monthly(...)` and `_apply_obligation(...)` both take `scheduler = null`. Production callers (e.g. `domain_handlers._resolve_domain_month`) extract from `_runner.get_scheduler()` and pass; tests pass null. The convention preserves the 100% testable pure-static pattern while letting production paths schedule downstream events. Pattern: when a static resolver needs to schedule events as a side effect of a public method, accept `scheduler = null` as the LAST optional parameter; never make scheduler-bearing the only path (would break tests).

- **Self-rescheduling tick handler returns `next_events` instead of calling `scheduler.schedule_at` directly.** `siege_handlers._handle_disease_cure_weekly_tick` returns a `next_events` array containing one entry that the registry then schedules. Contrast with `siege_handlers._handle_daily_tick` which delegates to `SiegeResolver.tick_daily` (which self-reschedules from inside the resolver via the scheduler param). Both patterns work; the registry-pattern is cleaner for handler-only logic, the in-resolver pattern is cleaner when the resolver needs to make a scheduler decision based on internal state. Pattern: prefer registry `next_events` for simple "fire again next week if condition" loops; prefer in-resolver `scheduler.schedule_at` when the resolver needs to make multiple complex scheduling decisions.

- **Idempotent event scheduling via `get_events_for_owner` check.** `DiseaseResolver._schedule_cure_tick_if_absent` checks `scheduler.get_events_for_owner(army_id)` for existing pending `disease_cure_weekly_tick` events before scheduling a new one. Prevents duplicate ticks when an army gets repeated infections. Pattern: when scheduling a "first-of-its-kind" event for an owner, check the queue for existing pending events of that type first; the EventScheduler's `get_events_for_owner(owner_id)` is the canonical query.

- **Decree-handler iterates active relationships and creates per-row obligations.** `CallToArmsHandler.on_complete` calls `VassalRepository.list_active_for_liege(character_id)` and creates one `vassal_obligations` + one `call_to_arms_state` per active vassal. The d20 random-roll path (`favors_duties_resolver.roll_monthly`) creates one obligation per assignment as a separate flow. Both paths converge on `CallToArmsMuster.issue_call(obligation_id, ...)`. Pattern: when a player decree affects multiple downstream entities (here: all vassals), iterate the relationship list and create per-target obligation rows; don't try to model "one decree, N effects" as a single row.

- **Live-refresh listener for hex-map landmark icons.** `hex_map_renderer.gd._ready` connects `EventBus.stronghold_completed` and `EventBus.stronghold_destroyed` to dedicated handler methods that call `_refresh_landmark_icons()`. The handlers ignore the stronghold_id argument since the refresh is full-map (cheap; queries only completed/claimed strongholds). Pattern: when a hex-map overlay needs to react to back-end state changes, prefer "full overlay refresh on signal" over surgical per-hex updates — the full refresh is bounded by the map's landmark count (typically <50 entities) and avoids stale-state bugs.

- **Legacy signal preserved alongside new behavior.** `CallToArmsHandler.on_complete` still emits `EventBus.vassal_muster_called(domain_id, delay_rounds)` for backward compatibility with any UI/test that listens for the muster-called notification, while ALSO calling the new CallToArmsMuster path that creates real obligations + scheduled tranches. Pattern: when a Phase 3 stub is upgraded to a real implementation, preserve any signals the stub emitted; downstream consumers may rely on them. Add new signals for the new behavior; don't repurpose old ones.


## 42. Phase 9A polish — Monster catalog as single source of truth (2026-05-09)

Phase 9A polish unifies `data/monsters/monster_catalog.json` (per-creature stat blocks) with `data/domain_events/wilderness_creature_table.json` (previously a duplicated thin slice). After the refactor, the catalog is the sole source of per-creature stats; the wilderness table is a slim category-membership index keyed by catalog ids. Patterns established:

- **One JSON file = one source of truth; companion files are thin indices keyed by ids.** Pre-Phase 9A polish, both files carried `individual_br`, `wandering_count`, `lair_count`, `platoon_br`, `lair_br`, `in_lair_pct` for the same 25 creatures — with no enforcement that they stayed in sync. Refactor: stats live exclusively in `monster_catalog.json` (under each entry's new `domain_encounter` block); the slim file stores only `categories` (d8 → column map) + `category_membership` (category → array of catalog ids). Pattern: when two JSON files describe the same entity, pick one as canonical and reduce the other to a pointer index. Add a consistency test that fails loud if the index references a missing canonical entry.

- **`domain_encounter` block is OPTIONAL on catalog entries.** Entries without it are catalog-only (elementals, ordinary cows / sheep / mules, swarms-with-no-BR-row, etc.) — present for `MonsterRegistry.get_monster(id)` lookups by other subsystems but ineligible for the random domain encounter throw. Entries WITH the block must populate all 9 fields: `individual_br`, `platoon_size`, `platoon_br`, `platoon_size_lair`, `platoon_br_lair`, `category`, `category_d8_columns`, `notes`, `raw_citation`. Pattern: optional metadata blocks on a heterogeneous catalog should be all-or-nothing — never partially populated, never with sentinel "0 means absent" semantics. Absence of the block = absence of eligibility.

- **`raw_citation` field on every domain_encounter block.** Every block carries an `ax_domain_level_encounters.xml §battle_rating_reference_tables.<category>.<creature_name> L<line>` citation. Future audits can grep `raw_citation` to confirm each datum traces back to a specific RAW row. Pattern: data-engineering sessions transcribing from RAW should embed a citation field on every transcribed entry; cite section + line number, not just the file. This makes "where did this number come from?" trivially answerable years later.

- **Snake_case ids derived from RAW labels with a SHARED-canonical exception.** Most ids are mechanical: `Bugbear` → `bugbear`, `Cat, Saber-Tooth` → `cat_saber_tooth`, `Wolf, Dire` → `wolf_dire`. Exception: when an id is already in widespread use across the codebase under a different name, preserve the existing id to avoid breaking refs. The pre-existing catalog had `dire_wolf` (not `wolf_dire`) because goblin's `encounter_hierarchy.allies[0].type = "dire_wolf"` and other refs depend on it. New variant ids should follow the `base_variant` pattern (`bear_grizzly`, `dragon_red_young`); ids already in use stay as-is. Pattern: when transcribing RAW into snake_case ids, grep the codebase for the legacy id first; if found, preserve it.

- **Category names are snake_case + qualifier suffix where ambiguous.** RAW BR sub-table names are `beastmen_and_humanoids` / `men` / `animals` / `vermin` / `fantastic_creatures` / `constructs` / `giants` / `summoned` / `undead`. Project canonicalization: drop the joining `and` (→ `beastmen_humanoids`) and explicit `_creatures` suffix on `fantastic` to disambiguate from a generic "fantastic" attribute. The 9 category names are stable across `categories.json`, `category_membership.json`, and per-entry `domain_encounter.category` — drift is caught by `test_membership_id_category_matches_bucket`.

- **d8 column routing with empty-list "not-reachable" semantics.** Constructs and summoned have `d8_columns: []` because they're not reached via the standard 1d8 wilderness encounter throw — they're conjured/built deliberately by spellcasters. The resolver still reads their `domain_encounter` blocks for siege/combat BR purposes, but the random throw never picks them. The consistency test gates `test_categories_cover_all_d8_columns` on `not membership.is_empty()` so empty-membership categories don't break d8 coverage. Pattern: when a catalog category exists in the schema but isn't reachable via the resolver's primary entry path, encode the gap as an empty array on the `d8_columns` field rather than omitting the category entirely — keeps the schema uniform and the consistency test clean.

- **Resolver consumes a static-cached MonsterRegistry instance.** `DomainEncounterResolver` is a `class_name X extends RefCounted` static-method class; it caches the registry via `static var _monster_registry: MonsterRegistry = null` and lazy-loads it on first use via `_ensure_registry_loaded()`. MonsterRegistry's `_init` reads `data/monsters/monster_catalog.json` once and caches in the instance. Pattern: when a static-class subsystem needs read-access to a non-autoload registry, prefer caching a single instance as a `static var` over passing the registry through every call. The instance is shared across all calls within the session; lifecycle matches the resolver's (until session restart).

- **Validation-on-first-use guard with explicit public method.** `DomainEncounterResolver.validate_consistency() -> Dictionary` returns `{ok, errors, warnings, total_ids}` and is called from `_ensure_validated_once()` on first encounter resolution. Returns warnings (non-fatal: id has wrong category) and errors (fatal: id missing or has no domain_encounter block). Tests can call the public method directly without poking internals; runtime calls it once, push_errors on mismatch, and proceeds. Pattern: cross-file consistency invariants for data files should be checked at first use, fail loud on errors, and be exposed as a callable public method for tests. Don't stuff the check into a private helper that tests can't call.

- **Cross-file consistency test pins the invariants.** `tests/test_monster_catalog_consistency.gd` (9 test methods, ~30 assertions) verifies: (1) catalog entries have all required fields; (2) every membership id resolves; (3) every membership id has a non-empty domain_encounter block; (4) entry's domain_encounter.category matches the membership bucket; (5) every d8 column 1..8 is covered by a non-empty category; (6) high-profile spot check (5 well-known creatures parse correctly); (7) DomainEncounterResolver.validate_consistency reports ok=true with ≥ 50 ids; (8) the resolver actually generates a non-empty encounter against the unified catalog. Pattern: when refactoring data files, write a consistency test that pins the invariants BEFORE making the refactor — the test catches regressions when future sessions add creatures to one file but not the other. Register in `tests/test_runner.tscn` + `tests/test_runner.gd` (next ext_resource id, append to suites array).

- **Backfill via Python helper script, not 28 individual Edit calls.** When a refactor needs to add the same field to N entries in a JSON file, write a one-shot Python script that loads, mutates, and writes the file with `json.dump(indent=2)` — preserves order and is much faster than N Edit calls (each requiring unique-anchor search). Helper goes in repo root with a `_` prefix (e.g., `_backfill_domain_encounter.py`); delete after the run completes successfully. Pattern: data-engineering refactors prefer Python helpers over many individual Edit calls; the helper is throwaway but leaves a clean diff via `json.dump`.

- **Data engineering vs functional engineering sessions split when scope > ~10h.** This session was framed as "expand monster_catalog 53 → ~184 entries + refactor + tests" — a 10h+ data engineering task. Pragmatic delivery: complete the FUNCTIONAL refactor (resolver, wilderness_creature_table.json, validation, consistency test) end-to-end, plus high-priority category coverage (96 new entries: 100% coverage of beastmen_humanoids / men / giants / undead / summoned / vermin / constructs, plus priority animals + fantastic). Document remaining ~80 BR rows as carry-forward in build_log. Pattern: when a session is framed with a "big number" target, prioritize FUNCTIONAL completeness over numerical completeness. A 60% catalog expansion with full structural refactor + tests is more shippable than a 100% catalog expansion with no validation. Carry-forward gets explicit, named entries in build_log so future sessions know exactly what to pick up.


## 42. Phase 9C polish round 2 — five carry-forward conventions (2026-05-09)

Phase 9C polish round 2 lands the carry-forward items from §41 (modal terrain, alignment metadata, per-troop save overlay, disease cure reconciliation, magnitude UI slider). New patterns:

- **Modal helpers tiebreak deterministically (alphabetical sort of keys).** `DomainEncounterResolver._domain_terrain_band` tallies terrain_key occurrences across hexes and picks the highest-count entry; on equal counts it sorts the keys alphabetically and picks the first. Pattern: any helper that runs at session boot OR on save-loaded data and produces a "most-common" pick must use deterministic tiebreaking; otherwise save/load races shuffle the result. Avoid reliance on dictionary iteration order (GDScript Dictionary preserves insertion order but Loader-rebuilt dicts may not match the original insertion order across runs).

- **Alignment-pair detection lives in the consumer subsystem, not on the catalog row.** `compute_alignment_pair_modifiers(domain_alignment, encounter_alignment)` is a public static in `DomainEncounterResolver`; the matrix logic lives ONCE there and is callable by other systems (army morale rolls, town reaction rolls). Pattern: alignment-pair math is a project-wide reaction concern; centralize the computation and let consumers call it. Don't duplicate the matrix in three different reaction-roll sites.

- **Project-designed save-overlay matrices document RAW provenance + project deviation explicitly.** `TroopUnitRepository._RACE_TIER_SAVE_VS_DEATH` is a 4×3 race×tier matrix not present in RAW (which uses class-by-HD save tables). The constant's docstring states: derivation source (ACKS Core race save tables for L1 fighters/units), what's project-designed (the tier shifts), and what isn't covered (anything outside the 4 races / 3 tiers returns -1 and the caller falls back to the schema DEFAULT). Pattern: whenever a v1 heuristic substitutes for a richer RAW system, document both the inspiration AND the simplification in the constant's docstring, AND provide a sentinel return for inputs outside the matrix.

- **Auto-derive at INSERT time when the caller doesn't supply.** `TroopUnitRepository.create_unit` computes `save_vs_death` from race+tier when not provided in `data`. Pattern: when adding a new column with a smarter-than-default-value derivation, do the auto-fill at the repository's INSERT site (NOT in a database trigger or migration backfill) — keeps the logic close to its consumers and testable in isolation.

- **State-recovery on load runs inline in session_runner, not via the scheduler.** `DiseaseResolver.reconcile_cure_ticks_on_session_load(scheduler, day)` is called once from `session_runner.gd` section 7d-2, immediately after `SiegeHandlers.register`. No event type, no recurring tick — just a one-shot recovery action that reads existing DB state and re-seeds in-memory scheduler events. Pattern: any subsystem whose state is split between persistent DB rows AND ephemeral in-memory scheduler events needs a `reconcile_*_on_session_load` static that runs at boot. Naming convention: `reconcile_X_on_session_load(scheduler, calendar_day)`.

- **Reconcile-on-load operations are idempotent via existing-pending check.** `_schedule_cure_tick_if_absent(army_id, day, scheduler)` calls `scheduler.get_events_for_owner(army_id)` and bails if any pending tick of the target type exists. Idempotent across multiple boots OR partial recovery scenarios. Pattern: every `_schedule_X_if_absent(...)` helper must consult `get_events_for_owner` first; never schedule without checking.

- **Per-card UI extras dictionary on activity cards.** `decrees_and_remote_orders_sub_tab._build_card` returns a card dict that includes an `extras: Dictionary` for activity-specific UI elements (currently only `magnitude_pct_slider` for `call_to_arms`). Other activities can extend the same pattern. `_params_for(activity_def_id)` reads from `extras` when building the launch params. Pattern: per-launch parameters that have constrained ranges (sliders, dropdowns) belong inline on the card via `extras`; complex multi-field params open a sub-dialog.

- **Slider value labels show derived consequences (not just the raw value).** The magnitude_pct slider's value label displays "50% (1 duty)" / "100% (2 duties)" — the duty count is derived via `CallToArmsMuster.compute_duty_count(magnitude_pct)`. Pattern: when a UI parameter has a non-obvious downstream effect (here: the duty-count gate at ≥100), surface the consequence in the live value label so the player understands what the choice means.

- **`_parse_params(state)` is the canonical helper name for activity handlers.** Both `conscript_troops.gd` and `call_to_arms.gd` define a private `_parse_params(state) -> Dictionary` that JSON-decodes `state.params_json`. Pattern: every activity handler that consumes per-launch params should define this exact helper for consistency. Avoid inlining `JSON.parse_string(state.get("params_json", "{}"))` at every read site.


## 43. Phase 9C polish round 3 — terrain-aware encounter selection (2026-05-09)

Phase 9C polish round 3 wires terrain-aware creature filtering into `DomainEncounterResolver._generate_encounter` and fixes a long-standing schema mismatch (resolver queried a non-existent `hex_cells.terrain_key` column). Patterns established:

- **Synthesize a derived key in code instead of adding a column.** `hex_cells` stores terrain across four columns: `biome` ∈ {clear, woods, jungle, swamp, desert}, `elevation` ∈ {flat, hills, mountains}, `civilization` ∈ {civilized, borderlands, wilderness}, `has_city` ∈ {0,1}. Multiple subsystems (resolver, army_marcher, battle_dispatcher) wanted a single "terrain_key" abstraction. Two options: (a) ALTER TABLE add a derived column with a trigger that maintains it; (b) synthesize at query time via a centralized helper. Project chose (b): `DomainEncounterResolver._synthesize_terrain_key(biome, elevation, civilization, has_city) -> String` with documented priority ordering (city > mountains > hills+clear > biome > clear). Pattern: when a logical property is derivable from existing columns and only a few subsystems read it, prefer a centralized synthesis helper over a schema migration. The helper docstring is the canonical truth; reuse it across subsystems.

- **Two-tier modal terrain helpers: raw vs band.** `_domain_modal_terrain_key(domain_id, hexes) -> String` returns the raw synthesized terrain_key (e.g. "woods", "mountains", "settled"). `_domain_terrain_band(domain_id, hexes) -> String` delegates to the raw helper then wraps in `classify_terrain_band` (returns the encounter-frequency-table band column name like "aerial_hills_woods"). Splitting them lets terrain-aware creature selection consume the raw key (via `terrain_affinity` matching) while the encounter-frequency column lookup keeps using the band. Pattern: when a derived value has multiple consumers with different vocabulary needs, split the helper into a raw-extractor + a wrapper that adds the consumer-specific transformation. Don't conflate the two.

- **Vocabulary normalization map decouples DB columns from runtime data files.** `data/domain_events/encounter_frequency_table.json:terrain_normalization` maps the resolver's synthesized terrain_key onto monster_catalog `terrain_affinity` vocabulary (e.g. "woods" → "woods", "mountains" → "mountains_hills", "settled" → "inhabited"). Public static helper `normalize_terrain_for_affinity(raw_terrain_key: String) -> String`. Unknown / empty keys fall back to "inhabited" (broadest category, prevents starvation of the eligible-creatures pool). Pattern: when two data sources describe the same concept with different vocabularies, define a normalization map in the data layer (NOT in code) so future schema migrations (split "woods" into "forest_light" / "forest_heavy") don't require a code change — just add map entries.

- **Filter-with-fallback for category-membership picks.** `_generate_encounter` filters `category_membership[picked_category]` by each candidate's `terrain_affinity` matching the normalized domain terrain. If the filtered list is empty (no creature in the picked category lives in this terrain), fall back to the unfiltered list with one `push_warning` per `(domain_id, category, terrain)` tuple via a static memo (`_terrain_fallback_warned`). Pattern: when a strict filter could starve a finite-pool selection, prefer a graceful fallback (pick from unfiltered) with one-time-per-key telemetry over hard-failing. The memoized warning surfaces sparse RAW coverage so future catalog additions can backfill the empty pairs.

- **Transparency-fields on result dicts report the resolver's INTENT, not the chosen output's properties.** The encounter dict's new `terrain_picked` field reports the normalized terrain that the resolver TRIED to match against — even when the fallback fires (so the picked creature might not actually live in that terrain). If we instead recorded the picked creature's first `terrain_affinity` entry, the field would be confusing on fallback paths. Pattern: when a derived field describes "what the resolver did," report the input/intent (the terrain it filtered on), not a derived property of the chosen output (the creature's terrain match). The field's contract is "what was the filter," not "where does this creature live."

- **Aspirational keys in normalization maps for forward-compat.** The `terrain_normalization` map includes keys like "forest_light", "forest_heavy", "mountains_or_hills", "clear_or_grass" that don't appear in the current schema. The synthesized terrain_key never produces them, but if a future schema migration introduces sub-biomes (split `woods` into `forest_light` / `forest_heavy`), the map already handles them. Pattern: when defining a vocabulary-normalization map, include reasonable future-vocabulary keys alongside the current schema — keeps schema migrations a one-side change rather than two-side coordinated change.

- **Static-cached warning memos avoid spam without leaking memory.** `DomainEncounterResolver._terrain_fallback_warned: Dictionary` accumulates `(domain_id|category|terrain)` keys to suppress duplicate `push_warning` calls. Lifetime is per-session (RefCounted clears at session restart). Pattern: when a class-level static method may emit telemetry per-call but only the first instance per identity-tuple is informative, memoize on a `static var Dictionary` keyed by the identity-tuple. Don't try to flush — the per-session lifetime is the right granularity.

- **Test silently passing because SQL silently fails is a class of bug.** The pre-session `test_carry_modal_terrain_picks_most_frequent` INSERTed into `hex_cells (map_id, q, r, terrain_key)` — `terrain_key` is not a real column. SQLite's `query_with_bindings` returned false (SQL error), the INSERT silently no-op'd, `_domain_modal_terrain_key` returned "" (no rows for those q/r), classify_terrain_band returned the safe default — and the test's only assertion was `check(true, "modal terrain helper smoke pass")`. Total silent failure for months. Pattern: when writing a test that requires DB seeding, ALWAYS make the test invoke the SUT with the seeded data and verify the expected property. Avoid "smoke tests" that don't exercise the path being tested. If the SUT is a private static, invoke it directly via the script reference rather than asserting trivial properties.

- **Optional dice + optional domain_id on internal helpers for testability.** `_generate_encounter(dice, modal_terrain_key: String = "", domain_id: String = "") -> Dictionary` — adding optional parameters preserves backward-compat with existing callers (the consistency test passes only `dice`) while letting new callers thread the modal terrain. Pattern: when adding new optional context to a private-internal helper, prefer trailing optional parameters with sensible defaults over overloads or context dicts.


## 44. Phase 9C polish round 4 — settled-lair flow (2026-05-09)

Phase 9C polish round 4 implements the settled-lair flow per RAW `ax_domain_level_encounters.xml` §dungeons L312-321 + §lingering_or_migrating L347-352. Lingering encounters are now promoted to `kind='settled_lair'` threats (instead of `kind='encounter'`); active settled lairs contribute a per-family-XP morale penalty to the monthly morale roll; dungeons in the domain double the linger chance. Patterns established:

- **Lifecycle-distinct threat kinds for permanent-vs-transient encounters.** RAW distinguishes "lingering" (decided to settle) from "migrating" (transient). The `domain_threats.kind` enum already had `settled_lair` and `encounter` separately; the resolver now selects between them based on `encounter.is_lingering`. Lingering threats persist (until defeated/cleared) and contribute to morale; migrating threats are transient. Pattern: when RAW specifies different DOWNSTREAM behavior for two states of the same trigger event, encode the difference at the persistence-kind level (not as a flag on a single kind), so downstream queries can filter cleanly. Co-evolves with partial-unique-active indexes when the lifecycle has cardinality constraints (bandit_swarm: max 1 active; settled_lair: many active OK).

- **Conditional behavior boost via optional resolver parameter.** `_generate_encounter(dice, modal_terrain_key="", domain_id="", has_dungeon=false)` — the trailing `has_dungeon` param doubles `percent_in_lair` (RAW L349). Caller (`roll_monthly_encounters_for_domain`) computes once via `_domain_has_dungeon(domain_id, map_id)` and threads through. Pattern: when a RAW boost depends on a domain-level state that's stable per call cycle (vs per-creature), compute it ONCE at the orchestrator and pass as a flag to the per-encounter helper. Don't re-query inside the per-encounter loop.

- **Modal modifier-roll penalty, not base-morale shift.** RAW L316: "The quotient is the penalty to the domain's base morale." Project interpretation: applied to the monthly morale-roll modifier sum (in `domain_handlers._event_modifiers_sum`), NOT to the base_morale column. End-to-end effect on rolled morale is the same, but cleaner state management — no need to track-and-untrack base morale shifts on threat lifecycle transitions; the penalty clears automatically when threats are defeated/cleared. Pattern: when RAW mentions a "penalty to base X" but the project models X with a base-vs-modifier split, prefer the modifier path. Base-X mutations are reserved for genuinely-permanent state changes (population growth, classification advancement).

- **Banker's rounding on per-family fractional values.** `_bankers_round(value: float) -> int` — round-half-to-even per CLAUDE.md project convention. GDScript's `roundi()` rounds half AWAY from zero, which is NOT banker's rounding. The local helper goes in DomainEncounterResolver because that's the only consumer; future callers can extract to a global helper. Pattern: when a calculation produces fractional outcomes that round to integers, use banker's rounding via a documented helper. Don't trust language-default rounding — explicitly verify or implement.

- **Repository helpers parallel the established kind-specific accessor pattern.** `DomainThreatRepository.list_active_settled_lairs_for_domain(domain_id)` mirrors the existing `get_active_bandit_swarm_for_domain` and `get_active_challenger_for_domain` (different return shapes — list vs single — because settled_lair has no partial-unique-active constraint). Pattern: when adding a kind-specific query helper, follow the existing naming + arity convention for that table. The naming differential (`list_active_*` for many vs `get_active_*` for at-most-one) tells the caller about the cardinality at a glance.

- **Test the contract, not the full stack, when dice sequencing gets complex.** Initial settled-lair test attempted to drive `roll_monthly_encounters_for_domain` end-to-end with a custom `SequenceDice` class that fed deterministic d100 sequences. This failed because (a) GDScript inner-class forward references in `class_name`-less files are fragile; (b) the monthly tick has too many moving parts (frequency-table target lookup, hex-count-vs-territory-type interactions, dice sequencing for BOTH encounter trigger AND lair check). Simplified test verifies each layer's contract independently: (1) `DomainThreatRepository.create_threat({kind: 'settled_lair'})` round-trips correctly; (2) `list_active_settled_lairs_for_domain` returns the row; (3) `_generate_encounter` produces is_lingering=true with d100=1; (4) `roll_monthly_encounters_for_domain`'s kind-assignment branch is a one-line `kind = "settled_lair" if is_lingering else "encounter"` verified by code inspection. Pattern: when end-to-end testing requires complex dice sequencing through multiple resolver layers, prefer per-layer contract tests over a custom dice class that's brittle in its own right. Each layer's behavior is more independently verifiable than the composed stack.

- **Compute domain-level invariants once at orchestrator, pass to per-iteration helpers.** `roll_monthly_encounters_for_domain` computes `modal_terrain_key` and `has_dungeon` once at the top (both stable per-domain over the throw cycle), passes both to each `_generate_encounter` call. Don't re-query inside the loop. Pattern: when an orchestrator runs N iterations of a per-iteration helper, identify domain-level invariants (don't change across iterations) and compute them once. The optional-trailing-parameters convention from §43 supports this cleanly.

- **Variable shadowing in nested if-blocks is a GDScript parse error.** Initial domain_handlers wiring re-declared `var peasants` inside an `if` block, while the outer function already had a `var peasants` declared earlier. GDScript's parser flags this as "could not parse global class" — a misleading error message that points to the outer file but is actually about the inner shadow. Fix: reuse the outer variable, OR rename the inner one if reuse is unclear. Pattern: when adding code to a long function, check if the variable names you're about to declare already exist in the enclosing scope. Prefer reuse over rename when the semantics are identical; rename when not. Avoid `var` re-declaration in nested blocks.

- **EventBus signal granularity: separate signals for permanent-vs-transient state changes.** `domain_encounter_occurred` fires for every encounter (kind in payload distinguishes); `settled_lair_established` fires ONLY for lingering encounters. UI/log subscribers can listen to either or both depending on their need (a "monsters have settled" prompt should listen to the second, not filter the first). Pattern: when a single resolver event has two semantically-distinct interpretations (transient vs permanent), emit BOTH a generic signal (with discriminator field) AND a kind-specific signal (no discriminator needed). Subscribers pick based on their use case; both are cheap to emit.


## 45. Phase 9C polish round 5 — HexTerrainQuery shared helper (2026-05-09)

Phase 9C polish round 5 extracts `_synthesize_terrain_key` from `DomainEncounterResolver` into a shared `HexTerrainQuery` helper at `engine/subsystems/exploration/hex_terrain_query.gd`. Three subsystems (DomainEncounterResolver, army_marcher, battle_dispatcher) now consume the same vocabulary. Patterns established:

- **Shared utility class lives next to its primary domain, not in a generic `shared/` directory.** `HexTerrainQuery` is consumed by 3 different subsystems (domains, armies, battles) but its primary subject matter is hex terrain. Lives in `engine/subsystems/exploration/` alongside other hex-aware utilities (hex_map_controller, foraging_resolver, weather_cache, light_source_tracker). Pattern: when a utility is consumed by multiple subsystems but has a clear primary domain, put it in the most-aligned subsystem rather than creating a generic `shared/` or `utilities/` directory. Keeps the module tree shallow and discoverable.

- **Pure function + DB-backed wrapper, exposed as separate static methods.** `synthesize_terrain_key(biome, elevation, civilization, has_city) -> String` is the pure function (no state, no DB). `query_terrain_key_for_hex(map_id, q, r, fallback) -> String` is the DB-backed wrapper. Splitting them lets `_domain_modal_terrain_key` (which queries multiple rows in a tight loop and synthesizes each) avoid the per-row fallback string allocation, while single-hex consumers (army_marcher, battle_dispatcher) get the convenient one-liner. Pattern: when a helper has both pure-computation and DB-backed forms, expose both. The pure form composes cleanly with bulk-loops; the DB form composes cleanly with single-hex lookups.

- **Configurable fallback parameter at the helper layer.** `query_terrain_key_for_hex(... fallback: String = "clear")` — different consumers want different defaults. army_marcher uses "clear" (matches TERRAIN_MULTIPLIERS lookup), battle_dispatcher uses "clear_or_grass" (legacy battle-resolver display string). Both are valid for their respective consumers; the helper accepts both rather than picking one canonical default. Pattern: when refactoring N call sites with different fallback strings to a shared helper, keep the fallback as a parameter rather than picking a canonical default. Backward-compat at every call site, no breaking changes to downstream lookups.

- **Optional-tighter-scoping parameter.** `query_terrain_key_for_hex` accepts an optional `map_id` — when empty, runs without the map_id filter (matches pre-refactor behavior — pre-refactor the SQL was broken anyway, but consumers expected loose matching). When non-empty, the query filters by map_id to avoid cross-map matches in multi-map campaigns. Pattern: when a query has an optional filter that tightens correctness without breaking existing callers, accept it as an optional parameter with empty/default = pre-refactor behavior. Lets callers opt into tighter scoping incrementally.

- **`Dictionary.get(key, default)` returns the stored null, NOT the default, when the key exists with null value.** This bit me in `battle_dispatcher._get_hex_terrain`: `army.get("map_id", "")` returned a Variant null when the SQL row had `map_id IS NULL` — then `String(null)` errored with "Invalid call. Nonexistent 'String' constructor." The fix: explicit null check `var map_id_v: Variant = army.get("map_id"); var map_id: String = "" if map_id_v == null else String(map_id_v)`. army_marcher already had `_safe_string(v, default) -> String` for this. Pattern: when extracting a string from a Dictionary backed by a SQL row with a nullable column, use `_safe_string`-style helpers or explicit null guards. NEVER trust `Dict.get(key, default)` to handle null-value-stored cases; the default is only returned when the KEY itself is missing.

- **Type-cast SCRIPT ERRORs vs assertion failures: SCRIPT ERROR is benign IF the function still returns valid data.** `String(null)` errors are runtime warnings — they log to stderr but don't halt execution. The function returns whatever default the runtime chose (often empty string). Tests that don't assert on the specific terrain string still pass. But the SCRIPT ERROR pollutes the test log and can mask real issues. Pattern: when refactoring code in a way that exposes new SCRIPT ERROR potential, fix the type-cast call sites defensively even if tests still pass — clean test logs are easier to debug.

- **Pre-existing same-pattern bugs are out of scope when fixing a specific carry-forward.** `in_enemy_territory_predicate.gd:44` has the same `String(army.get("map_id", ""))` null bug as the pre-refactor `battle_dispatcher`. The carry-forward target was specifically `army_marcher` + `battle_dispatcher`; the predicate fix is its own carry-forward. Pattern: when fixing a specific carry-forward item, resist the urge to fix every same-pattern bug in the codebase at once. Land the targeted fix, document the same-pattern bugs, defer them as separate carry-forward items. Smaller PRs are easier to review and bisect.

- **Refactor in passes: extract first, fix bugs second.** This session's refactor extracts the synthesis logic to a shared helper AND fixes the column-name bug AND adds the null-safe map_id extraction. Three changes in one PR. The build_log entry calls them out separately so a future bisect can identify which step caused regressions. Pattern: when a refactor combines multiple semantic changes (extraction + bug fix + new defensive code), document EACH semantic change separately in the build_log so future bisects don't have to re-derive the change list from the diff.

- **Stale .gdc compile cache can produce transient test failures.** Mid-session, the test runner reported 258/26 (1 regression) for the same code that, after another --import cycle, reported 259/25 (no regression). The `.godot/global_script_class_cache.cfg` and per-script .gdc files don't always invalidate cleanly when a class_name'd script is added to the project for the first time. Pattern: when test results disagree across consecutive runs of identical code, run `--import` again — the second import may rebuild stale .gdc files that the first import missed. If the disagreement persists across multiple imports, file a real bug.


## 46. Phase 9C polish round 6 — variant-flag pattern (2026-05-09)

Phase 9C polish round 6 introduces the catalog-flag-presence pattern for creature variants — using hydras' aquatic variant as the first concrete instance. The catalog flag's PRESENCE indicates "this creature has variant forms"; the flag's per-encounter VALUE is determined at encounter time and stored on the threat row's `payload_json`. Patterns established:

- **Catalog flag presence indicates variant-eligibility; flag value is per-instance.** Hydra catalog entries get `is_aquatic: false` and `is_regenerating: false`. The `false` defaults are the static-form representation. The encounter resolver overrides at instance time (e.g., aquatic: true when terrain is water; regenerating: TBD when variant rolling lands). The threat row's `payload_json["is_aquatic"]` is the per-instance authoritative value. Pattern: when a creature has variant forms determined at instance creation, use catalog flag PRESENCE to indicate the species is variant-eligible, and per-instance STORAGE for the determined variant. The catalog VALUE serves as documentation + a sensible static-form fallback for code that reads the catalog directly.

- **Branch on field presence, not hardcoded id lists.** `_generate_encounter` checks `if entry.has("is_aquatic"):` to decide whether to set the variant flag on the encounter dict. The alternative — `if creature_id.begins_with("hydra_"):` — would hardcode monster knowledge into the resolver. Pattern: when resolver code needs to branch on creature properties, branch on catalog FIELD presence rather than id-list matching. Future creatures with the same variant can opt in by adding the field; the resolver doesn't change.

- **Variant flags ride on `payload_json`, not new columns.** The `domain_threats.payload_json` field is freeform JSON; variant flags add a key (`{"is_aquatic": true}`). NO database migration required. Pattern: when a variant flag is per-instance and small (one or two booleans), prefer storing on an existing freeform JSON column over adding a new typed column. New columns require migrations + index decisions; payload_json scales linearly with feature count without schema churn. Larger structured state (like full regen-state tracking with multiple typed fields) might justify a real column, but boolean variant flags don't.

- **Optional fields on result dicts gated on caller-side `.has()` checks.** The encounter return dict's new `is_aquatic` field is OPTIONAL — present only when the catalog entry has the field. Callers that want to read it MUST gate on `encounter.has("is_aquatic")`, not `encounter.get("is_aquatic", false)` (the latter loses the eligibility signal). Pattern: when a result dict's field carries a "this concept applies" semantic, the field's PRESENCE is meaningful, not just its value. Document this in the docstring; consumers should use `.has()` to detect applicability.

- **Trailing optional parameters for backward-compat extension.** `synthesize_terrain_key(biome, elevation, civilization, has_city, water = "")` — the new `water` parameter is added as a trailing optional. Callers without water info (e.g., a synthesis call where only the land columns are known) keep working with empty water → land synthesis. Pattern: when extending a public function's signature with new context, add as trailing optional parameter with a default value that preserves prior behavior. NEVER reorder existing positional parameters; NEVER make existing optionals required.

- **Priority ordering documented in priority order, not source-code order.** The `synthesize_terrain_key` docstring lists priorities 1-7 in highest-wins order; the code body matches that order top-down (first match returns). Pattern: when a function has explicit priority logic (early-return on highest-priority match), structure the docstring as a numbered priority list AND structure the code body as a sequence of guards that match the list order. Future maintainers can add a new priority by inserting at the right spot in BOTH the docstring and code, without re-deriving the ordering.

- **BR-based atomic combat means HP-style mechanics don't translate to army scale.** Confirmed pattern: regen, partial damage, head loss, and other HP-state mechanics from individual-creature combat have no analogue in `field_battle_resolver`'s BR-allocation model. A unit's BR is consumed atomically (`if br <= hits_remaining: status='destroyed', br_current=0.0`). For army-scale planning, creatures with HP-state variants should use their MAX-state BR (worst-case difficulty). Pattern: when wiring a creature with state-dependent stats (regen, growth, transformation) into multiple combat scales, inventory which scales actually consume the state. Tactical = state matters; army = pessimistic-static-stats. Worst-case is the safe default for matchmaking.

- **Defer infrastructure that has no tested consumer.** Full tactical regen-state tracking (head_count, regrow_timer, cauterized_stumps) is meaningful infrastructure but the project has no tested tactical hydra fight to validate it against. Building it now would land untested code that will likely need adjustment when the first real fight surfaces edge cases. Pattern: when adding RAW-faithful infrastructure to support a NOT-YET-IMPLEMENTED feature, defer until at least one real consumer exists. Document the deferred work in build_log carry-forward; cite the spec section + the open questions; resume when a consumer is wired. This avoids "infrastructure looking for a consumer" — code that ages, drifts, and is hard to refactor when its real consumer finally arrives.

## 47. Phase 9C polish round 7 — Dragon data layer (hybrid Option C encoding) (2026-05-10)

Phase 9C polish round 7 introduces a heavier-weight encoding pattern for creatures whose instance variation goes beyond the boolean flags from §46 (hydras). Dragons have age × type × alignment × can_speak × hide_color × N abilities × (asleep | awake) × spell loadout — a combinatorial space where flag-based encoding doesn't scale. The hybrid Option C encoding (catalog + type lookup + ability lookup) is the project's pattern for such creatures. Patterns established:

- **Hybrid Option C encoding for high-cardinality variants.** When a creature's instance variation has multiple orthogonal axes (age band × type/color × N picked abilities × per-instance rolls), encode as: (1) catalog age-band entries with the AGE-DETERMINED stats (HD, AC, attacks, BR, spell-slot table, asleep/speech chances, ability count); (2) a separate type lookup file (`dragon_types.json`) keyed by type with TYPE-DETERMINED data (habitats, hide colors, breath weapon, alignment constraint, ability pool, terrain → type weighted picks); (3) a separate ability lookup file (`dragon_special_abilities.json`) keyed by ability id with ability text + selection constraints (alignment_required, spellcaster_required). The resolver composes per-instance variants from the three layers. Pattern: when variants have ≥3 orthogonal axes or per-instance picks from a curated pool, prefer three-file Option C over either flat catalog enumeration (catalog explosion) or single-flag overrides from §46 (insufficient state).

- **BR-row-with-abilities aliasing pattern.** External BR tables (e.g., daw troops table's "Dragon, Huge Venerable" row) sometimes encode shorthand for "base creature + applied special ability stack." Rather than instantiate the alias as a discrete catalog entry (catalog explosion + duplication of all the venerable stats), encode it as a `br_table_with_abilities` field on the BASE entry: `{"Dragon, Huge Venerable": {abilities_applied: ["massive_size"], individual_br: 18.762, ...}}`. The army-scale resolver looks up the alias on the catalog entry and applies the ability stack. Pattern: when a published BR/troops table contains rows that are shorthand for "base + ability composition," store them as `br_table_with_abilities` aliases on the base catalog entry, NOT as separate catalog entries. Avoids duplication; preserves the composition relationship; `MonsterRegistry.get_br_for_alias(base_id, alias_name)` is the canonical lookup.

- **In-data documentation of deferred resolver logic via embedded notes.** Files that ship data ahead of their resolver (catalog has dragon types, but no encounter resolver picks them yet) embed pseudocode and design notes as `_underscore_prefix` keys: `_selection_algorithm_note`, `_alignment_random_note`, `_offspring_note`, `_polymorph_self_speaker_priority_note`, `_spell_bias_note`. The leading underscore signals "this is a documentation key, not data; loaders should ignore." Pattern: when shipping data files whose resolver is deferred to a future session, embed the design spec INSIDE the data file as `_note_*` keys. The future implementer reads the data file as both the spec and the input. Avoids design drift between separate spec docs and the data; ensures the resolver author has the spec adjacent to the schema. Loaders MUST filter `_`-prefixed keys.

- **Dual terrain vocabulary management — synthesized terrain_key vs terrain_affinity.** The project has two terrain vocabularies: (a) the synthesized `terrain_key` (mountains/hills/desert/ocean/lake/woods/jungle/swamp/clear/settled — fine-grained) and (b) `monster_catalog.terrain_affinity` (mountains_hills/clear_grass_scrub/etc. — coarser combined buckets). Different consumers use different vocabularies. Catalog filtering uses `terrain_affinity` (matches RAW habitat groupings); secondary lookups (terrain → dragon type weighted pick) use synthesized `terrain_key` (needs hills-vs-mountains distinction). Pattern: when secondary lookups need finer terrain distinctions than the catalog's coarse buckets, use the synthesized `terrain_key` vocabulary as the lookup KEY. Document in the data file's `_note` which vocabulary each field uses; tests assert that the lookup keys are valid synthesized terrain_keys (not affinity strings).

- **Weighted-pick lookup tables with sentinel values for sub-rolls.** `terrain_to_dragon_type` maps each synthesized terrain to a list of `{type, weight}` pairs summing to 100. Some entries reference a sentinel (`__random_all_colors__`) instead of a concrete type id; when the picker hits the sentinel, it does a sub-roll against `random_all_colors_pool` (a separate weighted list excluding rare/special types). Pattern: when a weighted lookup has an "any of N" outcome that should NOT include all type ids equally (e.g., excluding wyrm and metallic from a "random color" sub-roll because they're PoI-only), use a sentinel string convention (`__double_underscore_prefix__`) and a named pool. The resolver checks: if pick.startswith("__"), recurse into the named pool; else use as-is. Avoids weight explosion at the top level; keeps "exclude PoI types from random" logic localized.

- **Per-type curated ability pools intersected with global constraints at runtime.** Each dragon type has a curated `special_abilities_pool` (pre-filtered to RAW-appropriate abilities for that color). The runtime picker computes `eligible = type_pool ∩ {abilities passing alignment_required filter} ∩ {abilities passing spellcaster_required filter}`. Then picks N uniformly without replacement, where N = catalog age band's `special_abilities_count`. Pattern: when an entity picks K-of-N from a constrained pool, encode the pool at the type/category level AND encode constraint flags at the item level. Compute the eligible set at pick time as the intersection. Keeps type-specific curation (e.g., "black dragons can have wing_claws") separate from global constraints (e.g., "polymorph_self requires can_speak"). Both layers are testable independently; the intersection is computed once per encounter.

- **Catalog age-band fields are AGE-determined; type-lookup fields are TYPE-determined.** The catalog's age-band entries hold all stats that vary by AGE only and are stable across colors: HD, AC, attacks, BR, treasure type, spell-slot table, chance_asleep_pct, chance_speech_pct, special_abilities_count. The type lookup holds all data that varies by TYPE only: habitats, hide colors, breath weapon dimensions/element, alignment_constraint, elemental_aura_damage_type, ability pool. Pattern: when a creature has two orthogonal classification axes (age × type), partition fields into the file whose axis they vary along. Don't duplicate type-data on every age band; don't duplicate age-data on every type. The resolver does ONE catalog lookup + ONE type lookup; per-instance state goes on payload_json (§46).

- **Lair eligibility belongs on the type-axis, not the catalog-axis.** Whether a dragon CAN be encountered as a settled lair (terrain has dungeons) is type-axis data: hills/clear/settled = false (these terrains' dragons stay nomadic per RAW); ocean/lake/swamp/etc. = true (lairs are environmental). Encoded as `lair_eligibility` per terrain in `dragon_types.json`. Pattern: when a "can this entity show up in context X" predicate depends on the entity's type/category rather than its individual stat block, store the predicate on the type-lookup file, NOT on each catalog entry. Single source of truth per type; new age bands inherit the eligibility automatically.

- **Test-driven data validation for high-cardinality data files.** `test_dragon_data_consistency.gd` is a 17-test, 453-assertion suite that validates the dragon data layer end-to-end: 10 age bands present, removed `dragon_huge_venerable` absent, Secondary fields populated per RAW (with a `RAW_SECONDARY` const driving the expected values), `br_table_with_abilities` aliasing intact, `terrain_affinity` covers all 8 dragon-eligible terrains, 9 dragon types with required fields, `terrain_to_dragon_type` uses synthesized vocabulary (not affinity), `lair_eligibility` matches locked spec, alignment constraints (wyrm=chaotic, metallic=lawful, others=null), 13 abilities with correct constraint flags, `elemental_aura_damage_type` matches locked spec. Pattern: when shipping a data file whose schema has multiple invariants and locked-in design decisions, write a consistency-test suite that encodes those invariants as `RAW_*` consts and asserts each one. Future edits that violate the spec will fail the tests; the test data IS the spec, machine-checked.

## 48. Phase 9C polish round 7 — Dragon variant resolver (per-encounter variant pickers) (2026-05-10)

Phase 9C polish round 7's second half wires up the runtime resolver that consumes the dragon data layer from §47. Picks dragon type from terrain, alignment, family composition, per-member can_speak / asleep / abilities / hide_color / spells, and threads the variant payload through the domain encounter signal + threat row's payload_json. Patterns established:

- **Field-presence detection as the variant-resolver branch trigger.** `DragonVariantResolver.is_dragon_entry(catalog_entry)` returns true iff the entry has `chance_speech_pct`. The encounter resolver branches on this — `if DragonVariantResolver.is_dragon_entry(entry): result["dragon_variant"] = DragonVariantResolver.resolve_group(...)`. Pattern: when wiring a variant resolver for a creature class, expose a predicate function that returns true based on FIELD PRESENCE (not id-prefix matching). The encounter resolver's branch reads as a domain-level English sentence ("if this is a dragon entry") rather than a creature-bookkeeping detail ("if id starts with dragon_"). New creature classes that adopt the same encoding (chance_speech_pct, chance_asleep_pct, special_abilities_count, spells_per_day_by_level) get variant resolution automatically.

- **Shared-vs-per-member resolution under one resolve_group call.** `resolve_group(catalog_entry, terrain_key, count, dice)` picks SHARED state first (type, alignment, family composition), then loops over members rolling INDEPENDENT per-dragon state. The shared/per-dragon partition is locked at the resolver level — type/alignment shared across the group (a clutch is all one color, all one alignment), can_speak / asleep / abilities / hide_color / spells per-member (each dragon is its own entity). Pattern: when a group of N entities shares some attributes but varies others, structure the resolver as: (a) pick shared attributes once at the group level; (b) loop members and roll independent attributes per-member; (c) return a payload with shared attributes at top level + a `members` array of per-member dicts. The schema documents the partition; consumers don't have to re-derive what's shared vs per-member.

- **Family-composition payload with mode discriminator.** `group_composition` carries a `mode` field with one of {"solo", "pair", "pair_with_offspring", "clutch"} plus the supporting fields (`pair_age`, `pair_count`, `offspring_age`, `offspring_count`). UI / LLM consumers branch on `mode` to render appropriately ("a solitary dragon" vs "a mated pair" vs "a pair with hatchlings" vs "a clutch of siblings"). Pattern: when a group can have several structural shapes (solo, pair, family, etc.), include a mode-discriminator field in the payload rather than forcing consumers to infer from counts. The discriminator is documentation and a branch key in one — adding a new shape only requires updating the enum + the picker, not every consumer's inference logic.

- **Sentinel string for sub-roll recursion in weighted picks.** `terrain_to_dragon_type[hills] = [["brown", 33], ["blue", 33], ["__random_all_colors__", 34]]`. The sentinel `__random_all_colors__` (double-underscore prefix convention) means "instead of picking this as a literal type, recurse into the `random_all_colors_pool` and uniform-pick from there." The resolver detects the sentinel after the weighted pick and calls the sub-roll. Pattern: when a weighted pick has an "any of N excluded subset" outcome, use a sentinel string (double-underscore prefix to avoid name collisions) and a named sub-pool elsewhere in the data file. Avoids weight explosion at the top level (would otherwise need [["brown", 33], ["blue", 33], ["red", 5], ["white", 5], ...] etc.) and keeps the sub-pool exclusion logic (e.g., "metallic + wyrm are PoI-only, exclude from random") localized.

- **Lair-eligibility override at the encounter generator centralizes the policy.** Hills/clear/settled dragons get `is_lingering=false` and `is_lair=false` forced on the encounter dict by `_generate_encounter` itself (after calling `DragonVariantResolver.is_lair_eligible(modal_terrain_key)`). This happens BEFORE the caller reads those fields. Pattern: when a "yes/no can this thing happen here" policy depends on a type/terrain lookup AND must override the result of another roll (here, the % In Lair check), encode the override at the point where the result dict is finalized — not at every downstream caller. Single source of truth for the policy; the caller's logic stays generic (read `is_lingering` from result and act on it).

- **Optional encounter-dict field naming convention.** New variant fields on the encounter dict are named for the concept they represent (`is_aquatic` from §46, `dragon_variant` from this round). The field PRESENCE is the eligibility signal; consumers gate on `.has("dragon_variant")` not `.get("dragon_variant", null) != null`. Pattern (extends §46): when adding a new variant field to a shared dict, name it after the concept (not "is_set_X"). Field PRESENCE means "this variant applies to this encounter"; the field VALUE is the variant payload. Multiple variants on the same dict each get their own optional field, each independently gated.

- **Payload-shape symmetry between threat row, encounter dict, and signal payload.** The same `dragon_variant` Dictionary appears on (a) `_generate_encounter`'s return value, (b) `threat_payload["dragon_variant"]` stored on `domain_threats.payload_json`, (c) `encounter_payload["dragon_variant"]` emitted on the `domain_encounter_occurred` signal. Pattern: when a variant payload needs to flow from generator → persistence → signal, plumb the SAME Dictionary through all three rather than re-shaping per layer. Consumers reading from any of the three see the same structure; no surprise field renames between layers.

- **Lazy-loaded module-level data caches with `_reset_for_testing` hook.** `DragonVariantResolver._types_data`, `_abilities_data`, `_monster_registry`, `_spell_registry` are static module-level caches populated on first use via `_ensure_data_loaded` and `_ensure_registry_loaded`. Tests call `_reset_for_testing()` in their `run_all_tests` setup to force a fresh load (and to allow swapping JSON files in future scenario tests). Pattern: for static-helper resolvers that load JSON data files lazily, expose a `_reset_for_testing()` (or `_reset_state()`) method that clears all cached state. Production code never calls it; tests use it to guarantee deterministic behavior across runs and to support swap-in test data. The leading underscore signals "internal / testing only."

- **Programmable test dice — queue first, fallback-by-shape second.** `ScriptedDice` class has `queue: Array` (next-roll-in-FIFO) and `fallback: Dictionary` (keyed by "%dd%d" string like "1d100" or "1d3" with default values per shape). The resolver consumes queue first; when queue is empty, the fallback returns the per-shape default. Pattern: when testing a resolver that makes many rolls (some critical, some incidental), use a hybrid dice abstraction — queue for the critical rolls under test, fallback for the noise. The test reads as "roll 1 for the type, 3 for the alignment, then don't care about the rest" instead of trying to enumerate every roll the resolver makes. The fallback's per-shape keying matches Godot's `roll(count, sides)` signature, so the dice abstraction maps cleanly to the resolver's `_roll_die(sides, dice)` helper.

- **`String(null)` crash defense for optional dict fields.** `String(composition.get("offspring_age", ""))` crashes when offspring_age is explicitly set to null in the dict (the `.get` default only kicks in when the key is MISSING, not when present-and-null). Fix: gate on null before the cast — `var v = dict.get(key, ""); var s = "" if v == null else String(v)`. Pattern: when a Dictionary field is documented as "optional, null-when-not-applicable" (e.g., `offspring_age: null` in solo/pair modes), every String() / int() / float() conversion at the read site MUST guard against null. The `.get(key, default)` idiom is NOT sufficient — defaults apply to absence, not nullity. Audit every `String(dict.get(...))` call when the field is nullable.

- **Defer offspring-age conversion until offspring_count > 0.** The resolver only computes `offspring_age` after `if offspring_count > 0:`. For solo/pair/clutch modes (offspring_count=0), the field is never read. Pattern: when a dict field is null in some modes and only meaningful in others, defer the field's READ (cast, lookup) until the mode-discriminator guarantees it's set. Keeps the no-offspring code path free of null-handling boilerplate and makes the read-site code statically obviously safe.


## 49. Phase 10A.1 — Class-bucket detection (2026-05-10)

- **`ClassBucketResolver` is the single source of truth for class-specific buckets.** All callers determining whether a character sees the Class-Specific Domain sub-tab — and which blocks render within it — MUST query `ClassBucketResolver.buckets_for(character_id)`, `has_bucket(character_id, "faith")`, `primary_bucket_for(character_id)`, `sub_tab_label_for(character_id)`, or `is_bardic_variant(character_id)`. Never write ad-hoc class-id checks like `if class_id in ["cleric", "bladedancer", "priestess"]:`. The resolver lives at `engine/subsystems/domains/class_bucket_resolver.gd` and reads from `data/classes/<class_id>.json` `class_powers` via a cached `ClassRegistry` singleton (`_class_registry_cache` pattern, mirrors `Combatant._get_class_registry()`). Five canonical bucket ids: `"faith"`, `"magical_research"`, `"trade"`, `"syndicate"`, `"garrison_training"` (per `gdd-domain-tab.md` §4.4 + §12.1).

- **Bucket detection rules are power-id-driven, not class-id-listed.** The resolver checks for specific `power_id` strings on the character's class definition:
  - `faith` ← `divine_casting` OR `spell_research_and_minor_item_creation` (the Bladedancer's restricted divine power)
  - `magical_research` ← `arcane_casting` OR `arcane_casting_in_armor` (elven variant + Darkblood Ruinguard)
  - `trade` ← `stronghold_guildhouse`
  - `syndicate` ← `stronghold_hideout` AND `combat_progression == "thief"` (the progression check excludes bards, who have thief progression but `stronghold_hall`, not `stronghold_hideout`)
  - `garrison_training` ← (`combat_progression == "fighter"` AND `level >= 5`) OR `class_id == "bard"` (the Bardic Patronage variant — RAW: `hireling_inspiration` L569-575 + `hall` L577-584 from `acore_campaign_classes.xml`)
  Pattern: detection rules cite the RAW source for each branch in the resolver's docstring; tests assert one row per class in the §12.1 matrix.

- **Divine-side magic research belongs in the Faith block, not Magical Research.** Cleric / Bladedancer / Priestess / Shaman / etc. have `spell_research` and `magic_item_creation` powers but they research divine spells and create divine items. Per `gdd-domain-tab.md` §12.1, only arcane casters get the Magical Research bucket; divine research surfaces inside the Faith block. The resolver enforces this by NOT having a fallback `(mage_progression + spell_research) → magical_research` rule — that branch would incorrectly capture Priestess (combat_progression="mage" + spell_research) and Witch (same shape). Pattern: when two distinct surfaces share underlying mechanics but separate by school/category, gate the bucket strictly by the school-specific power id, not by a generic "can research" capability.

- **Primary-bucket override for stacked-block ordering.** When a class has multiple buckets (Bladedancer = Faith + Garrison Training; Lightblessed = Magical Research + Faith), `PRIMARY_BUCKET_OVERRIDE[class_id]` decides which card opens expanded by default. Absent an override, the first bucket in the canonical `BUCKET_IDS` order wins. Pattern: when stacked-card UIs have a class-specific "lead" card, store the override as a per-class constant on the resolver, not as a UI parameter — keeps the visual hierarchy consistent across the tab.

- **Bard sees the Garrison Training bucket id with a VARIANT surface.** Per Q3 / [RESOLVED 2026-05-06] in `domain-roadmap-corrected.md` §10, Bards share `garrison_training` as their bucket id (so the sub-tab visibility logic is uniform), but they render the **Bardic Patronage** variant block: Chronicles of Battle aura (`hireling_inspiration`) + Solicit Followers (`hall`). They do NOT see `oversee_troop_training` / `train_troops` — those are restricted to fighter combat progression per `ax_campaign_play.xml` §oversee_troop_training requirement. The resolver exposes `is_bardic_variant(character_id)` so block UIs branch on it to swap content. The sub-tab label for a Bard is `"Bardic Patronage"`, not `"Garrison Training"`. Pattern: when two distinct classes share a bucket id but surface different content, model it as a variant flag on the resolver + content-swap in the block UI, not as a separate bucket id (avoids combinatorial bucket explosion).

- **Dynamic sub-tab label + per-entity visibility via TabBar.set_tab_hidden().** The Class-Specific tab in `domain_tab_page.gd` keeps a stable index in the TabBar but its visibility and title are recomputed each time the active entity changes (`_refresh_class_specific_tab()`). `set_tab_hidden(idx, true)` removes it from view when buckets are empty; `set_tab_title(idx, label)` swaps in the dynamic label (e.g., "Magical Research" for a pure mage, "Class Activities" for a multi-bucket Bladedancer, "Bardic Patronage" for a Bard). When the active sub-tab becomes hidden mid-session (e.g., entity switches to a class with no buckets), the page falls back to `"overview"`. Pattern: prefer TabBar's per-tab hidden flag over rebuilding the whole strip — keeps tab indices stable for substate persistence and avoids flicker.



## 50. Phase 10A.2 + 10A.3 — Faith / Bardic / Proficiency-gated activities (2026-05-11)

- **`pending_divine_effects` is one table with a status-lifecycle enum.** Rather than splitting one-shot and continuous effects into separate tables, a single `pending_divine_effects` table stores both via `status ∈ {pending, applied, expired, cancelled}`. One-shot effects (e.g. `consecrate_fields_land_value`) transition pending → applied on the monthly tick that fires them. Continuous effects (e.g. `consecrate_ruler_buff`) are inserted directly with status='applied' + an `expires_at_calendar_day` window; the monthly tick checks for any 'applied' row with expires_at > now and applies the bonus. A separate sweep transitions 'applied' → 'expired' when the window passes. Pattern: when delayed and continuous effects share most fields (domain_id, payload, dates), use one table + status enum rather than two tables with bifurcated shape.

- **Per-character relationships keyed on character_id, NOT domain_id, when the relationship MIGHT survive without a domain.** `congregants` is keyed `(character_id PK)` rather than `(domain_id PK)` because a divine caster can build a congregation in a settlement before they hold a domain; the domain-level ruler bonus (+0..8 DP per 10 families) is computed by joining `congregants → characters → domains WHERE owner_character_id = ?`. Pattern: if a relationship MIGHT outlive the foreign key (or pre-date it), key on the more fundamental entity and resolve the FK at query time.

- **`MagicResearchThrowUtil` is a shared static helper.** Magic-research throws use the same RAW procedure (`target_for_level` from the L0-L14 table + ability modifier + optional Magical Engineering rank, natural 1-3 always fails). The shared util is consumed by consecrate_fields, consecrate_ruler, and (future) Phase 10B.1 magic-research handlers. Pattern: when multiple handlers implement the same dice procedure with the same RAW citation, extract the procedure into a static helper class with a clear-named entry point (`MagicResearchThrowUtil.make_throw(...)`); pass the per-activity differences (ability modifier kind, roll_type label) as parameters.

- **Divine throws use WIS modifier, arcane throws use INT modifier.** Project-designed deviation from `acore-campaign-general-and-magic-research.xml` §general_magic_research_throw L56 which says "Intelligence bonus" without distinguishing caster type. The util exposes `int_mod_for_character` AND `wis_mod_for_character` accessors; consumers pick the appropriate one based on whether the activity is arcane or divine. Pattern: when RAW assumes one caster type but the rule applies more broadly, parameterize the deviation in the shared util rather than forking the rule per consumer.

- **`ClassBucketResolver.PRIMARY_BUCKET_OVERRIDE` is a per-class constant, not a UI parameter.** Stacked-block ordering for multi-bucket classes (Bladedancer = Faith + GT; Lightblessed = MR + Faith) decides which card opens expanded by default. Pattern: when stacked-card UIs have a class-specific "lead" card, store the override as a per-class constant on the resolver so the visual hierarchy stays consistent regardless of which UI path renders the blocks. v1.1+ can layer per-player preference on top of the override.

- **Activity eligibility checks live in the handler's `on_complete`, NOT only at UI launch time.** The UI greys out launchers when eligibility fails, BUT the handler ALSO performs the check defensively. This catches launches initiated by scripts, deferred-launch races (where eligibility changes between launch and completion), or future API paths that bypass the UI. Pattern: any business-rule eligibility (proficiency rank, level gate, alignment, class) should be enforced at BOTH the UI gate (for UX) AND the handler gate (for correctness).

- **`assignment_kind` enum for troop_units is `'garrison' | 'on_campaign' | 'available'`.** New units that aren't yet formally hired (Bardic Patronage Solicit Followers applicants, future Mercenary Market candidates) use `'available'` rather than introducing new enum values. The player's hire action transitions `'available'` → `'garrison'`. Pattern: when a domain-of-discourse already has an enum with the right shape, prefer reusing the closest value over schema migration. Reserve enum extension for cases where the new state has materially different downstream behavior.

- **`ledger_entries.category` is `'revenue' | 'expense' | 'tribute_in' | 'tribute_out' | 'investment' | 'other'`.** Audit-trail rows that don't move gp (training completion logs, recruitment audit, etc.) use `category='other'` with the descriptive subcategory. Pattern: `'other'` is the catch-all for informational rows; never invent new categories without a schema migration that adds them to the CHECK constraint.

- **`ChroniclesOfBattleAura` is pull-queried, not push-broadcast.** Morale-roll consumers explicitly call `ChroniclesOfBattleAura.compute_aura_bonus(...)` just before rolling. The aura helper does NOT broadcast a signal on every party-membership change. Pattern: passive auras whose effects manifest only at specific roll moments should be queried at the roll site, not eagerly broadcast. The signal pattern is reserved for state changes that need to refresh persistent UI or trigger downstream events.

- **Proficiency-gated activity helpers as static classes.** `TroopTrainingEligibility` exposes `get_manual_of_arms_rank(character_id)`, `eligible_troop_types(character_id)`, `can_train_troop_type(character_id, troop_type)`, etc. All consumers (Garrison sub-tab UI, train_troops handler, future automation) query these helpers rather than directly reading character_proficiencies rows. Pattern: when an activity's eligibility involves multiple proficiencies + their interactions (rank + companion proficiencies), extract a domain-specific eligibility class. Single source of truth for the "can this character do X?" question; tests assert against the helper rather than against raw proficiency rows.



## 51. Phase 10B.1a — Followers vs. henchmen vs. characters; magical-research schema patterns (2026-05-11)

- **`followers` is a NEW persistent class distinct from `characters` and `troop_units`.** Per Q25 [RESOLVED 2026-05-11]: followers are "almost-henchmen but not quite the same thing — they gain XP and treasure shares like henchmen when on adventure with the owner, but not when left at the stronghold. If henchman slots are available they may be promoted to henchman without a hiring reaction roll." Encompasses: mage/cleric/witch/warlock/elven_enchanter sanctum aspirants (0-level Normal Men pre-promotion), 1st-3rd-level same-class followers (most human classes), same-race race followers (elf/dwarf non-casters), Bard's solicit_followers 1st-3rd-level bard applicants (retro-migrated from `characters` in Phase 10B.1a per Q25a), future venturer apprentices (10B.2), and syndicate members (10B.3).

  - **source_kind enum** (extensible): `aspirant | class_follower | race_follower | bardic_recruit | venturer_apprentice | syndicate_member | generic`. Encodes ORIGIN, never changes after creation.
  - **status enum**: `aspirant_in_training | present | on_adventure | departed | promoted_to_henchman | failed_promotion`. Encodes lifecycle state.
  - **intended_class** (TEXT, nullable): aspirants only. Set at creation (mage / cleric / witch / warlock / elven_enchanter); used by the promotion-throw resolver to pick INT-mod (mage flavor) vs. WIS-mod (cleric flavor).
  - **promotion_eligible_day** (INTEGER, nullable): for aspirants only. Set at `joined_calendar_day + 120` (4 months × 30 days). The monthly-tick resolver in 10B.1d fires the d20 + ability_mod 14+ throw when this day is reached.
  - **0-level mercenaries stay in `troop_units`, not `followers`.** Hirelings paid wages without XP / treasure-share entitlement are mass-bookkept; followers are individually tracked persistent NPCs.

  Pattern: when the project's domain-of-discourse has a class of NPC that doesn't fit cleanly as "PC / henchman / NPC / hireling," introduce a distinct table rather than overloading existing types. Resist the temptation to make `characters.character_type` exhaustive — discriminator-overload makes lookups expensive and constraints brittle.

- **`promote_follower_to_henchman` is a cross-table operation that bypasses the standard hiring reaction roll.** Per Q25, the helper creates a `characters` row with `character_type='henchman'`, `persistence_tier='named'`, copies the follower's stats, then updates the source follower's `status='promoted_to_henchman'` with `promoted_to_henchman_id` linking forward. Henchman-slot eligibility is the caller's responsibility (the helper doesn't check Charisma-max — that's a UI-level gate). Pattern: cross-table promotion-style operations that change the entity's identity (follower → henchman) should be a single repository helper that does both the insert AND the source-row mutation atomically.

- **Aspirant promotion uses a single fixed 4-month timer (per Q20 [RESOLVED 2026-05-11]).** The standard sanctum's RAW 1d6-month variability (acore-campaign-hijinks.xml §sanctums L534-538) is collapsed to fixed 4 months (the expected value of 1d6, rounded to 4). Universal across Mage / Witch / Warlock / Elven Enchanter / Lightblessed Wonderworker. The Lightblessed-specific bits are: 50/50 mage/cleric split (per Q2), cleric branch uses WIS modifier, and INT/WIS gets boosted to 9 at aspirant creation if rolled lower. Pattern: when RAW prescribes a randomized timeline but the expected-value collapse simplifies UX without changing outcomes meaningfully, prefer the fixed-value approach. Document the simplification inline so future Q's can revisit.

- **`magic_research_projects` carries days_total / days_completed; monthly tick advances days_completed.** Per the Phase 10A.2 / 10B.1 pattern, in-progress research is a status-discriminated row (status='in_progress' → status='completed'|'failed'|'abandoned'). The monthly-tick stub in `domain_handlers.gd::_resolve_magic_research_month` advances `days_completed += 30` for in_progress rows; completion-throw + completion effects ship in 10B.1b/c. Pattern: long-running ACKS activities that span multiple months should encode their progress as a day-counter on the row, not as a schedule of separate "completion event" entries — keeps the monthly tick a pure UPDATE pass and avoids scheduler bloat.

- **Libraries and workshops reuse stronghold_id rather than spinning their own construction activity (per Q22).** Sub-structures of sanctums (libraries) and towers (workshops) reference an existing `strongholds(id)` FK. No new `construct_library` / `construct_workshop` Ongoing activity. Pattern: when RAW describes a sub-structure-of-a-stronghold construction relationship, model it as a foreign key into the parent stronghold's row and put the construction lifecycle on a `status` enum (building / operational / damaged / destroyed) rather than a separate construction-progress table. The actual gp-build-up happens via the existing stronghold-construction system; the sub-structure row gets stamped operational on completion.

- **Activity-handler registration shells ship empty in early waves and become populated as later waves attach handlers.** `MagicalResearchActivityHandlersRegistration.register_all` ships as a no-op in 10B.1a; each subsequent wave (10B.1b-f) adds its handler registrations. Pattern: ship the registration scaffolding (session_runner wiring + module location + class skeleton) early so the activity catalog can include the disabled-state UI surface without the handlers existing yet. Saves a session-runner edit per wave.

- **Shared eligibility helpers live on the most-complex handler in the wave, not in a separate utility module.** Phase 10B.1b's spell-research handlers (research_magic / rewrite_spell / replace_spell / scribe_spell) share four eligibility helpers (`_is_arcane_caster`, `_can_learn_spell_level`, `_get_arcane_spell_level`, `_add_spell_to_formulas_and_repertoire`). They live as public-static methods on `ResearchMagicHandler` (the most-complex handler that uses all four); the other three handlers call them via `ResearchMagicHandler._is_arcane_caster(...)` etc. Pattern: when 3-4 handlers in a single wave share a small (< 8) set of pure-function helpers, attach them to the handler that's already the "anchor" of the wave rather than spinning a separate `*_eligibility.gd` utility. The class_name is already imported; the helpers are co-located with the eligibility logic that's their primary consumer; tests can target the anchor handler's exported helpers. For larger or cross-wave helper sets, the separate-utility pattern from `TroopTrainingEligibility` (10A.3) or `MagicResearchThrowUtil` (10A.2) is still correct.

- **`location_kind` / `location_ref` on activity launch states are the canonical contract for physical-presence requirements.** The executor's `ActivityTimeCostExecutor._is_at_required_location` consults a `_location_resolver` Callable + the launch state's `location_kind` / `location_ref` fields. For Q21 [RESOLVED 2026-05-11] (Magical Research library residency), launchers set `location_kind="at_library"` + `location_ref="library:<library_id>"`. The handler does NOT enforce travel — that's the executor's responsibility once the resolver is wired. Handlers DO re-verify static state (the library still exists, is operational, is owned by the caster) at on_complete as a defensive cross-check. Pattern: physical-presence enforcement is a launch-state property, not a handler property. Handlers should never call into the location-tracking system directly — they only consult the state they're given.

- **JSON activity duration formulas are named keys resolved in `ActivityTimeCostExecutor._compute_ticks_required`.** Per the Phase 10B.1b pattern, when an activity's duration is a formula involving runtime params (e.g. `14 * target_spell_level` for research_magic), the JSON declares `"duration_formula": "research_magic_duration"` and the executor's `_compute_ticks_required` match statement adds the arm. Pattern: short names (snake_case verb form) for the formula key; the actual expression lives in the executor where the params are accessible. Avoid embedding GDScript-evaluatable expressions in JSON.

- **Catalog category names match RAW, not project-level abstractions.** Phase 10B.1b's catalog file is `magical_research_category.json` (matching the project's bucket / module / table prefix) but its `_meta.category` and per-activity `category` fields are `"magical"` to match `ax_campaign_play.xml` §magical. ActivityCatalog's `list_by_category("magical")` returns the 4 spell-research ids. Pattern: filename / class / table names use the project-level abstraction; catalog category strings use the literal RAW category name. The handoff document was incorrect on this point (said `<category name="magical_research">`); always cross-check the RAW XML before naming the category field.

- **Runtime-mutable catalogs are separate tables, not JSON; static catalogs are JSON, not tables.** Per Jedidiah's constraint 2026-05-11 for Phase 10B.1c ("create new items to the item catalog without populating the same item to shops"), player-crafted magic items live in a runtime DB table (`crafted_magic_items`); the static equipment catalog stays in `data/equipment/*.json` (read by `EquipmentCatalog` at startup). `ShopInventoryGenerator` reads only the JSON catalog, so DB-side crafted items never leak into shops. Pattern: any "items that exist only because the player generated them at runtime" go in a DB table with a clear creator/owner FK and a discriminating `item_key='crafted:<id>'` convention on inventory_items rows. Consumers that need the shop-visible / spawnable / availability-gated subset query the JSON catalog; consumers that need ALL items (e.g., inventory inspection) check both. This same pattern applies to future "player-discovered spells" or "player-trained troop variants" or any other runtime-extensible game-content catalog.

- **inventory_items.item_key uses a typed prefix to discriminate catalog source.** Crafted magic items use `item_key='crafted:<crafted_magic_items.id>'`. Future runtime-extensible item types should use similar prefixes (`scroll:<scroll_id>` for player-scribed scrolls, etc.) so consumers can dispatch resolution to the appropriate registry. Plain item_keys (no prefix) resolve via `EquipmentCatalog`. Pattern: when an inventory_items row's metadata depends on a runtime table, encode the table reference in the item_key as `<source>:<id>`; the inventory_items row carries denormalized fast-query fields (magical_bonus, weapon_damage, armor_ac_bonus, encumbrance_units) so casual consumers don't pay the extra lookup.

- **Effect-table-driven cost/time computations live in pure-function static helpers.** Phase 10B.1c's `MagicItemEnchanting` class exposes `base_gp_cost(effect_kind, spell_level, charges)` and `base_days(effect_kind, spell_level, multiplier)` as static methods consulting a `const EFFECT_TABLE`. Handlers call into these for the actual numbers; tests target the helper directly (covers the table without spinning up a full activity flow). Pattern: when RAW prescribes a table mapping (input → cost / time / target), make the table a `const Dictionary` on a pure-function helper class. Don't embed the table in the handler — it makes the handler harder to test and locks the table to one consumer. The `MagicResearchThrowUtil` (10A.2) follows the same pattern for the level→target table.

- **Handler dispatch via `match params.project_kind` keeps the unified activity row.** Per Q16, `research_magic` is a single activity row in the catalog but the handler dispatches to `_handle_spell_branch` / `_handle_magic_item_branch` / future construct/monster branches based on `params.project_kind`. Each branch is a private static method on the same handler class. Pattern: when RAW collapses multiple semantically-distinct operations into one activity, dispatch internally rather than splitting into separate handlers. Keeps the activity catalog clean and matches the RAW unification.

- **Event-driven resolvers register from session setup, not from autoloads.** Phase 10B.1d's `SanctumApprenticeResolver` lives as a regular RefCounted class with `subscribe()` / `unsubscribe()` methods. SessionRunner owns the lifecycle: instantiates on session load, calls subscribe, tears down on session unload. Pattern: long-lived signal subscribers that need to survive across exploration-state transitions but reset between campaigns should follow this idempotent-recreate pattern from FollowerArrivalResolver. Avoid putting them in autoloads — autoloads are for truly global services (GameState, EventBus, etc.).

- **Static promotion-style operations live on the resolver, not the repository.** `SanctumApprenticeResolver.resolve_promotion_throw(follower_row, calendar_day)` is a pure-function static that performs the d20+ability_mod throw AND mutates the follower row + emits events. Pattern: when a transformation is logically tied to a domain resolver (e.g., "this is the aspirant promotion mechanic"), put it on the resolver class even if the implementation is fully static and doesn't need instance state. Avoid hiding it as a private method on a handler that has nothing to do with it. Tests target the static method directly; the resolver instance is only needed for the signal-subscription side.

- **Named-character followers and troop-unit followers use different tables and different resolvers.** `FollowerArrivalResolver` populates `troop_units` (soldier-tier mass followers) from `data/followers/per_class_tables.json`. `SanctumApprenticeResolver` populates `followers` (named-character-tier apprentices + aspirants) from class metadata encoded directly in the resolver. Pattern: when two follower kinds have different schemas, different lifecycle states, and different consumer surfaces, keep them in separate tables with separate resolvers even if they fire off the same trigger event. Both subscribe to `EventBus.stronghold_completed` independently; the two resolvers don't know about each other.

- **Procedurally-built entities (constructs) get their own design + instance tables.** Phase 10B.1e's `construct_designs` (the formula/template) + `construct_instances` (actual bodies in the world) avoid the temptation to overload `crafted_magic_items` or `followers`. Pattern: when RAW prescribes a "design → create" workflow that lets the player choose stat parameters (HD, attacks, damage, abilities), the design row IS the formula AND a future template; the instance row is the body. Dedupe lookup (`find_matching_construct_design`) treats matching (creator, name, key stat tuple) as "same design" so repeat creates reuse the design row. Combat / garrison / encounter integration ships when those systems land; the tables ship first so the creation flow can be exercised end-to-end.

- **Combine "design + create" RAW splits into one v1 activity when the second step is essentially mandatory.** RAW §constructs has separate design (formula) and create (body) activities that both pay the same cost. In practice no one designs without immediately creating; the design-only path is for batch / repeat creates later. v1 collapses to one project — pay once, get formula + body. Future polish (`use_existing_design_id` param) restores the two-step path for repeat-create cost savings. Pattern: when RAW prescribes a two-step workflow but the first step is rarely useful alone, ship the combined path first and split later.

- **Each research-site type gets its own table when the RAW worth-thresholds differ.** Phase 10B.1a shipped `libraries` (spell research). 10B.1c reused that pattern for `workshops` (item creation). 10B.1f shipped `laboratories` (cross-breeding) per RAW L471's "special crossbreeding laboratory." All three share the same shape (id / campaign_id / owner_character_id / stronghold_id / structure_kind / gp_invested / max_X_supported / magic_research_throw_bonus / status / created_calendar_day). Pattern: when RAW prescribes a distinct named research site (library / workshop / laboratory) with its own worth-threshold semantics for different magical-research activities, give it its own table. Avoid the temptation to merge into a generic `research_sites` table — separate tables let each retain its specific column semantics (`max_spell_level_supported` vs `max_item_value_supported_gp` vs `max_crossbreed_cost_gp`) without nullable fields and per-row dispatch logic.

- **Project-designed soft caps go on the helper class, with a clear "no RAW counterpart" comment.** Phase 10B.1f's `MagicalResearchCrossbreed.validate_crossbreed_ability_count` enforces a `2 × per-progenitor` soft cap on total crossbreed abilities even though RAW only gives a per-progenitor cap (1 + INT_bonus). The crossbreed inherits from at most two parents, so 2× is the natural ceiling. Pattern: when RAW leaves a value unbounded but the reasonable maximum is derivable from RAW context, encode the derived cap in the helper as a "project-designed" check + document the reasoning inline. Avoids accepting absurd inputs (e.g., 50 abilities) without inventing a number out of thin air.

- **Cross-breeding eligibility is narrower than construct creation.** RAW §constructs L376 extends to Dwarven Craftpriests at L9, but RAW §crossbreeds L419 lists only "arcane spellcasters of 11th level or higher." The handlers in `research_magic.gd` enforce this asymmetry: `_handle_construct_branch` accepts arcane OR divine OR `dwarven_craftpriest`; `_handle_monster_branch` accepts arcane only. Pattern: don't reuse eligibility helpers across similar-looking RAW activities — copy the helper and customize per RAW. The cost in code duplication is small; the cost of an incorrect eligibility list is a player-visible rules error.

- **Gap-filler RAW imports stay scoped.** Phase 10B.1f borrows the monster_types taxonomy from `rules/le_monster_creation.xml` (Lairs & Encounters) but DOES NOT pull in the rest of the file's 19-step monster-from-scratch procedure. Pattern: when a RAW file provides one specific definition useful to a feature, encode just that definition as a constant in the helper + cite the source. Don't load the whole file into scope or build infrastructure for the unused parts. v1.1 can ship the full procedure when needed.

- **Multi-list class eligibility is data-driven via class_powers iteration.** Phase 10B.1g's `_researchable_spell_lists_for(character)` walks `class_powers` and collects the `spell_list` field from each casting-power entry. Lightblessed's dual-list works automatically because its JSON declares `arcane_casting` with `spell_list='arcane'` AND `divine_casting` with `spell_list='divine_cleric'`. Pattern: when a class can do something "with both X and Y" (dual-list, dual-casting, dual-progression), let the class JSON declare both via separate class_power entries + write the eligibility helper to discover them. Avoid `if class_id == "lightblessed_wonderworker"` hardcoding — it doesn't generalize when future classes inherit similar dual-flavor patterns.

- **Project-designed shortcuts use named constants with rationale comments.** Phase 10B.1g's `DUNGEON_UNDER_TOWER_TARGET_REDUCTION = 1` is a Q9 shortcut for the full RAW dungeon-stocking-with-monsters system. The constant carries a multi-line comment naming: (a) the RAW source it's shortcutting (`acore-campaign-hijinks.xml` L545-611), (b) the project-designed value (-1), (c) why it's conservative (low base targets would over-tilt with larger reductions). Pattern: when v1 ships a "this represents the full system as a single number" shortcut, name the constant, comment WHY the number was chosen, AND cite the full RAW system the shortcut replaces. Future me re-implementing the full system needs the breadcrumbs.

- **Pure-function extractions for encounter-loop calculations.** Phase 10B.1g's `apply_dungeon_target_reduction(base_target, has_dungeon)` lives as a public static next to the encounter loop that calls it. Tests target the function directly — they don't need to set up a full domain + roll the entire monthly-tick cycle to verify the math. Pattern: when an encounter-loop calculation depends on a single derived value (target adjustment, modifier sum), factor it into a pure function. Even if the function body is two lines, the named entry point + testability is worth the line of indirection. The Phase 9C `compute_settled_lair_morale_penalty` and `compute_wave_count` patterns are precedents.

- **Use `ClassBucketResolver` as the canonical eligibility gate in handlers, not per-handler power-id checks.** Phase 10B.1g.1 swapped `_handle_spell_branch` + `_handle_magic_item_branch` from `_is_arcane_caster(character)` to `ClassBucketResolver.buckets_for_character(character).has("magical_research")`. Reason: the bucket resolver is the single source of truth for Q11 (which classes get magical_research access). Reusing it in the handler means UI surface (which uses the resolver to decide whether to show the block) and handler behavior (which gates research attempts) agree by construction. A class is EITHER in the bucket OR not — both UI and handler see the same answer. Pattern: when a class-bucket resolver exists for a feature, prefer it over rebuilding the same eligibility logic inside handlers. Handlers should re-check defensively, but the check should be the SAME bucket check, not a re-derivation.

- **Per-class spell overlays use `restricted_to` arrays in the catalog, not separate indexed lists.** The spell catalog has 3 indexed lists (`arcane`, `divine_cleric`, `divine_bladedancer`) — NOT one list per class. Per-class differentiation among divine casters (Witch, Priestess, Shaman) is encoded as `restricted_to: ["witch"]` on individual spell entries in `spell_catalog.json`. The lookup helper `SpellRegistry.get_available_spells_for_class(class_id, level, class_registry)` walks BOTH the base indexed list AND the catalog's `restricted_to` overlays, returning the union. Pattern: when many classes share most of their list but differ in a handful of entries, use a base indexed list + per-spell restricted_to overlays rather than N near-duplicate indexed lists. Avoids data duplication; reduces drift; matches RAW which describes shared spells with class-specific additions, not isolated per-class lists.

- **OCR-dependent data ingestion blocks separate from code-side feature work.** Phase 10B.1g.1 hit a "PDF is image-only, no `pdftoppm`/`gs` available" wall. The code-side fixes (helper rewrite + gate widening) shipped without the PDF data because they make the system structurally correct. The data gap (per-class `restricted_to` coverage may be incomplete vs. the source PDF) was clearly logged + alternatives proposed (paste / typed JSON / pre-OCR / computer-use screenshot). Pattern: when an external data source isn't reachable, ship the structural code fix that makes the data USABLE once it arrives, document the data gap clearly, and DO NOT block the code feature on data ingestion. The two concerns can land separately.

- **Computer-use MCP is the fallback when OCR tooling is missing.** Phase 10B.1g.2 successfully ingested 5 pages of an image-only PDF via the computer-use MCP: user opened the PDF in VS Code (tier "click" — read-only + left-clickable), I called `request_access`, user approved the Windows dialog, I screenshotted each page + zoomed for fine detail, and transcribed the data into a structured JSON. Pattern: when CLI OCR tooling (pdftoppm/gs/tesseract) is unavailable in the environment but the user has the source file on their machine, the computer-use MCP closes the gap. Trade-off: ~2 minutes of user time to open the file + approve access, vs. paragraphs of "please paste this as text." Worth offering when an OCR-eligible source is involved.

- **PDF data ingestion produces THREE outputs in sequence: data file, structural fix, stub entries.** Phase 10B.1g.2 demonstrated the canonical flow: (1) write the captured data into a clean structured file (`per_class_spell_lists_FROM_PDF.json`) that mirrors the source's structure; (2) update structural references (`spell_list_indices.json`, class JSON pointers) to use the new data; (3) for entities named in the data but missing from secondary tables (`spell_catalog.json`), add stub entries with the required schema fields and a `_stub: true` flag. Pattern: capture the source data verbatim in its own file; let the codebase reference it; backfill missing dependencies with stubs that are explicitly marked. Stubs surface gaps without blocking integration. Tag stubs with `_added_in: "<wave id>"` so a future audit can clean them up by wave.

- **Per-class indexed lists scale better than shared-base + restricted_to overlays.** Phase 10B.1g.2 found that PDF-canonical class spell lists (Priestess's 75 spells vs Cleric's 50) overlap heavily but include enough class-specific additions that the previous "shared `divine_cleric` base + `restricted_to: [priestess]` overlay per spell" pattern was unworkable. The PDF treats each class as having its own dedicated list, so the codebase matches: each class gets a dedicated indexed list in `spell_list_indices.json`, and `restricted_to` is reserved for spells that genuinely cross multiple classes within a tradition (e.g., `angelic_choir` shared between Bladedancer + Priestess). Pattern: when class lists differ by more than ~30%, give each class its own indexed list. Restricted_to is for ~5-10% cross-class spells, not for the bulk.

## 52. Phase 10B.1h — Conditional-section modal pickers + activity-launcher gating (2026-05-11)

- **One picker dispatcher over N kinds beats N per-kind pickers when only fields differ.** Phase 10B.1h wired 7 magical-research launchers (research_spell / research_magic_item / research_construct / research_monster / rewrite_spell / replace_spell / scribe_spell) into a SINGLE `scenes/ui/notebook/domain/blocks/research_project_picker.gd`. The picker carries shared chrome (backdrop + centered PanelContainer + footer Cancel/Launch + live preview + validation row) and dispatches on `_kind` inside `_build_body()` to one of seven `_build_X_section()` field-builders. Each section populates a `_fields` dict that `_collect_params()` then match-dispatches over to assemble the activity params. Pattern: when modals share chrome but diverge in fields, conditional-section dispatch keeps the per-kind code small (50-100 lines per section) without duplicating the modal shell. Each section's fields key into the shared `_fields` dict; the collector and validator both pivot on `_kind`. The alternative (one file per kind) would have produced 7× boilerplate with no logic divergence.

- **Picker emits a generic `launch_requested(activity_def_id, params, location_kind, location_ref)` signal — the caller turns it into `executor.launch(...)`.** The picker doesn't own a reference to the ActivityTimeCostExecutor or the EventScheduler — instead, it emits a signal whose payload is shape-compatible with `ActivityTimeCostExecutor.launch`'s positional args. The caller (`magical_research_block._on_picker_launch_requested`) is responsible for resolving the executor + scheduler from the session_runner and translating the signal payload into the launch call. Pattern: keep modals stateless about session/executor — they're owned by the surrounding block / sub-tab. Modal emits a structured request; surrounding block dispatches. Trade-off vs. picker-owns-executor: the picker stays reusable from any surface (you can show it from a non-Domain context without changing its internals), and tests can verify the signal payload without standing up the full executor.

- **Picker queue_frees itself before emitting the terminal signal.** `_on_launch_pressed` does `visible = false; launch_requested.emit(...); queue_free()` (and `_on_cancel_pressed` mirrors it with `cancelled.emit()`). Reason: if the receiver opens a follow-up modal in its handler (e.g., a "you don't have enough gp" warning), the original picker should already be removed from the tree so the follow-up doesn't visually stack. Pattern: modals own their own teardown; emit the terminal signal AFTER hiding self but BEFORE queue_free() to keep the signal connected through the emission.

- **`_dd_id(dd: OptionButton) -> String` helper over inline `.get("id", "")` casts.** Pickers that store row dictionaries as OptionButton item_metadata need a String id for downstream params dicts. Wrapping `String(_dd_metadata(dd, null).get("id", ""))` in a one-line `_dd_id(dd)` helper makes call sites read as `var lib_id: String = _dd_id(_fields.get("library_id_dd"))`. Pattern: when the same multi-step extraction shows up at 5+ call sites in a picker, factor a tiny helper even if its body is one line.

- **Launcher buttons keyed by id in a Dictionary so `_refresh_activity_cards` can re-gate without rebuilding rows.** `magical_research_block._launcher_buttons: Dictionary` maps `launcher_id` → Button reference. `_build_activity_launchers` is called ONCE in `_ready()`; `_refresh_activity_cards` is called every time `_render_*` runs, walks the LAUNCHER_CARDS config, and re-disables / re-enables buttons based on current eligibility (caster bucket + library/workshop/laboratory presence). Pattern: when launcher rows are static but their enabled-state is dynamic, build the rows once and store button references for cheap re-disable. Avoids rebuilding the launcher UI on every signal-driven refresh, which would flicker and discard tooltip state. The state-rebuild cost is constant in row count and runs only on actual eligibility-affecting events (library_built, workshop_built, laboratory_built).

- **Per-launcher infra precondition checks happen in the block, not the picker.** The picker assumes its caller has already verified the caster's bucket gate; it surfaces fine-grained per-field validation (no library selected, no spell selected) via `_validate_params`. The block's `_refresh_activity_cards` does coarse precondition checks (does the caster own ANY library? ANY workshop? ANY laboratory?) and disables Launch buttons with a specific tooltip when the precondition fails. Pattern: distinguish coarse eligibility (block-level: do they have ANY of the required asset?) from fine validation (modal-level: have they SELECTED a specific asset?). Both layers gate; the picker isn't supposed to render at all if the block-level check fails.

- **Defensive `EventBus` signal subscription when the signal isn't emitted yet.** `magical_research_block` subscribes to `EventBus.laboratory_built` even though no current code path emits it. The handler is a no-op for now (`_render_laboratories` + `_refresh_activity_cards`), but wiring the connection now means when the stronghold-construction completion path eventually emits it, the block auto-refreshes without further changes. Pattern: when adding a sibling signal to an existing one (here, `library_built` / `workshop_built` already exist), subscribe defensively even if no emitter exists yet. Cost is one connect call; benefit is no follow-up wave to wire the subscriber later.

- **Live preview labels reduce the surface for back-and-forth validation.** The picker maintains two labels: `_preview_label` (cost + time + a summary of the selected params) and `_validation_label` (red-tinted rejection reason when params are invalid). Both are recomputed on every field change. `_launch_btn.disabled = not validation_message.is_empty()`. Pattern: instead of letting the user click Launch and surfacing a "this doesn't work" dialog, surface the rejection live in the picker so they can fix the issue without a round-trip. Two labels stacked under the form: one positive (cost preview), one negative (validation). Both empty when everything is fine and the button is enabled.
