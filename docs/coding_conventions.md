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

### 3.3 Banker's Rounding — Everywhere (with explicit RAW exceptions)

<!-- Corrected 2026-07-07 (Faction FF-1 audit): the previous version of this
     section claimed Godot's roundi()/roundf() already do banker's rounding.
     They do NOT — Godot's built-ins round half AWAY FROM ZERO. -->

All rounding in the entire project uses round-half-to-even. **Godot's built-in `roundi()`/`roundf()` do NOT do this** — they round half away from zero (`roundi(2.5) == 3`, `roundi(-2.5) == -3`), which is a different, incompatible rounding mode. Use the shared helper below; never hand-roll banker's rounding at a call site and never assume `roundi()`/`round()` are sufficient.

```gdscript
# GOOD — the canonical shared helper (engine/shared_types/math_utils.gd)
var hp_bonus := MathUtils.bankers_round(con_modifier * 0.5)  # 2.5 -> 2, 3.5 -> 4

# BAD — Godot's built-in rounds half AWAY from zero, not to even
var hp_bonus := roundi(con_modifier * 0.5)  # WRONG: this is not banker's rounding

# BAD
var hp_bonus := int(con_modifier * 0.5)     # truncation, not rounding
var hp_bonus := ceili(con_modifier * 0.5)   # ceiling, not banker's
```

#### RAW-mandated exceptions (added 2026-05-27)

When a specific ACKS rule **explicitly specifies** a non-banker's rounding mode, the RAW rule wins over the project-wide convention. These exceptions are rare; each must be documented at the call site with the RAW citation and a brief justification ("per RAW we round down here — banker's rounding would open game difficulty gaps").

Known exceptions:

| Rule | Rounding mode | RAW citation | Rationale |
|---|---|---|---|
| Cross-tier number-appearing adjustment for wandering monsters (when the rolled monster's table differs from the dungeon level, the rolled number appearing is multiplied by `0.5 ^ tier_diff` for deeper-than-floor monsters or `2.0 ^ tier_diff` for shallower-than-floor monsters) | **Round down** | `rules/acore-monster-stocking-rules.xml:42-46`, `<rounding>Round down.</rounding>` inside the `dungeon_wandering_monsters` procedure | Banker's rounding here would let some unlucky tier-difference rolls produce one extra creature in encounters intended to be small, opening a noticeable difficulty gap at low monster counts. RAW round-down keeps the procedure deterministically conservative on monster count. |

Implementation pattern for exceptions:

```gdscript
# GOOD — RAW exception, cited inline
# RAW rule: rules/acore-monster-stocking-rules.xml:42-46 — round DOWN on cross-tier
# number-appearing adjustment (NOT banker's rounding — see docs/coding_conventions.md §3.3).
var adjusted_number := floori(base_number * pow(0.5, tier_diff))
```

#### Legacy private copies (known drift, not yet migrated)

`XpAwardCalculator.bankers_round` and `TreasurePlacementService._bankers_round` predate `MathUtils.bankers_round` and implement the same algorithm privately. New code must call `MathUtils.bankers_round` — do not add a third private copy. Migrating the two existing ones to delegate to `MathUtils.bankers_round` is a small, low-risk follow-up for whichever session next touches either file; not urgent enough to justify a standalone session.

When a new RAW exception is encountered during implementation, add a row to the table above and use the `floori()` / `ceili()` variant matching the RAW direction, with the citation comment as shown.

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
├── 004_timekeeping.sql              # campaign_clock, party_clocks (party_clocks dropped by 154)
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

<!-- 2026-05-28: added the writer/CHECK/RAW alignment invariant after the migration-133 crossbreed reaction-enum bug. -->

**A CHECK enum must cover every value its writers can produce, and both must match the canonical (RAW) vocabulary.** When a column's allowed set diverges from the range of values the code actually writes, INSERTs fail *intermittently* — only when a writer happens to produce the uncovered value — which is hard to reproduce and easy to misattribute (e.g. to an unrelated concurrent edit). When adding or changing an enum column, cross-check three things:

1. CHECK set ⊇ the output range of **every** code path that writes the column (helper functions, auto-rolls, launcher params), not just the path you're currently editing.
2. CHECK set matches the **project-wide** vocabulary for that concept. Example: reaction / disposition tiers are `hostile / unfriendly / neutral / indifferent / friendly` per the RAW Monster Reaction table (`rules/acore_adventures_and_encounters.xml:936-958`), used by `attitude.gd`, `encounter_data.gd`, `override_manager.gd`, the reputation schema, etc.
3. Where practical, add a deterministic test that inserts one row per allowed value (and/or asserts the writer's output set ⊆ the CHECK set). A round-trip-each-value test catches drift that an RNG-gated end-to-end test only hits probabilistically.

Cautionary example: migration 096 wrote `crossbreed_instances.initial_reaction IN (...,'friendly','helpful')` — misreading the RAW "12+ Friendly, helpful" row as two tiers and dropping the real 9-11 tier — while `MagicalResearchCrossbreed.roll_initial_reaction()` correctly emits `'indifferent'`. ~25% of crossbreed crafts failed the INSERT until migration 133 corrected the constraint.

<!-- 2026-06-10: added the legacy_alter_table guard after migration 151 reproduced the migration-117 FK-rewrite hazard. -->

**Changing a CHECK (or otherwise rebuilding a table) requires `PRAGMA legacy_alter_table = ON` if ANY other table foreign-keys into it.** SQLite cannot `ALTER` a CHECK constraint, so the standard fix is rename → recreate → `INSERT … SELECT *` → drop (migrations 011 / 013 / 117 / 151). But in modern SQLite (godot-sqlite's default, `legacy_alter_table = OFF`), `ALTER TABLE x RENAME TO x_old` **auto-rewrites FK references in OTHER tables** to point at `x_old`; when you then `DROP x_old`, those FKs dangle and every subsequent INSERT into the referencing table fails with `FOREIGN KEY constraint failed`. Wrap the rebuild in `PRAGMA foreign_keys = OFF; PRAGMA legacy_alter_table = ON;` … `PRAGMA legacy_alter_table = OFF; PRAGMA foreign_keys = ON;` so the references keep pointing at the original name (which resolves to the freshly-created table). Migrations 011/013 didn't need this only because no table referenced `inventory_items` yet; by 117/151, `location_caches.container_item_id REFERENCES inventory_items(id)` made the guard mandatory. After any such rebuild, confirm `PRAGMA foreign_key_check` returns zero rows.

Build-workflow corollary: the test DB (`user://campaign.db`) is carried forward across sessions, so a new migration only runs once. If you must force a clean rebuild (e.g. to re-test a migration), deleting the DB makes ALL migrations re-apply — and the **last** migration leaves `PRAGMA foreign_keys = ON` on that connection, which surfaces latent FK-violations in unrelated tests (savegame restore, character persistence) that the carried-forward DB masks (godot-sqlite opens with `foreign_keys` defaulted OFF). Those are a test-isolation artifact, not a regression; the true baseline is a run where no migration applies.

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

<!-- Added 2026-03-27 after Timekeeping autoload build; updated 2026-04-14 for scheduler-driven advancement; rewritten 2026-06-11 for the single-shared-timeline ruling; calendar-day serial convention added 2026-06-12 -->

**Single shared timeline (Jedidiah ruling 2026-06-11):** there is ONE world clock. `Timekeeping.get_total_rounds()` is the canonical "now" for fire_time computation, gating, ETA display, and persistence timestamps. `Timekeeping.advance_rounds(n)` (and the minute/turn/hour/day wrappers) is the only advancement API. The per-party clock API (`get_party_time`, `advance_party_*`, `register_party`, `sync_parties`, `get_leading_party`, `get_time_gap`) and the `party_clocks` table were REMOVED (migration 154) — do not reintroduce them. "This party is busy" is expressed via the order-lock (§19.5), never via clock divergence. See `docs/handoff_multi_party_time.md` for the audit and ruling.

**Passive clock:** `Timekeeping` never ticks on its own. The EventScheduler (via `SchedulerLoop`) advances it by calling `Timekeeping.advance_rounds()` as the clock reaches each event's timestamp. No background timer, no `_process()`.

**Advance methods emit boundary signals automatically:**

```gdscript
# GOOD — scheduler advances time to the next event timestamp
# (SchedulerLoop handles this automatically via advance_rounds)
var delta = next_event.fire_time - Timekeeping.get_total_rounds()
Timekeeping.advance_rounds(delta)
# Boundary signals (day_changed, month_changed, dawn, dusk) fire automatically

# BAD — manually tracking time to decide whether to emit signals
_elapsed_hours += 8
if _elapsed_hours % 24 == 0:
    emit_signal("day_changed")   # reinventing what Timekeeping already does
```

Direct `advance_hours()`-style calls outside the scheduler are reserved for lump-sum absorptions that are part of the design: `CombatFinalizer` (combat rounds rounded up to the turn boundary, ACKS RAW), town rest (`camp_state.gd`), hide-and-memorize (`location_cache_manager.gd`), and the GM override panel. Anything else should schedule events instead.

**Boundary signals fire once per crossing, even for large advances:**

```gdscript
# advance_days(40) from start:
#   → 40 × day_changed (for each day 2–41)
#   → 1 × month_changed (at day 29 = month 2)
#   → 0 × year_changed (no full year crossed)
#   → 2-3 × dawn / dusk per day depending on start position
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

**Calendar-day serial (`calendar_day` / `started_calendar_day` columns):** the canonical day-of-campaign integer is **1-based** and uses the project's 13-month calendar:

```gdscript
# GOOD — delegate to the canonical helpers; since 2026-06-12 the formula lives
# ONLY in Timekeeping (the 49 per-subsystem copies were deduplicated):
return Timekeeping.get_calendar_day()            # "today"
return Timekeeping.calendar_day_from_date(date)  # arbitrary {year, month, day} dict

# The formula itself, for reference (equals get_total_days() + 1 for today):
return ((year - 1) * Timekeeping.MONTHS_PER_YEAR + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day

# BAD — hardcoded 12-month year: Year 2 Month 1 collides with Year 1 Month 13
# (both = 336 + day), so cross-year elapsed-day math sees zero days at the
# year boundary and drifts one month per elapsed year. 48 copy-pasted helpers
# carried this bug until 2026-06-12.
return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day

# BAD — unshifted year/month (no -1): runs 392 days ahead of the canonical
# serial, so elapsed = today - started_calendar_day breaks when producer and
# consumer disagree (the pre-2026-06-12 encounters_threats_sub_tab bug).
return year * Timekeeping.DAYS_PER_YEAR + month * Timekeeping.DAYS_PER_MONTH + day
```

Never re-inline the formula or hardcode `12`/`13` in calendar math — delegate to `Timekeeping.get_calendar_day()` / `calendar_day_from_date()`. All persisted day-serial columns (`activity_states`, `stronghold_commissions`, sieges, ledgers, `domain_religion_conversion`, etc.) share this coordinate system; a new producer or consumer MUST go through the canonical helpers or elapsed-day arithmetic silently breaks.

**Day serials never enter the EventScheduler.** The scheduler's `fire_time` axis is ROUNDS (8,640 per day) — scheduling a day serial directly makes the event ~immediately past-due once the campaign is more than an hour old (the pre-2026-06-12 call-to-arms/siege/disease bug). Convert at the scheduling boundary with `Timekeeping.calendar_day_to_rounds(day_serial)` (midnight of that day); keep the day serial for DB stamps. `EventScheduler.schedule()` push_warns when a fire_time lands >2 days in the past as a tripwire for this class.

**Clock & event-queue persistence policy (2026-06-12):** the DB opens with `PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL` (CampaignRepository._ready) — never revert to the DELETE/FULL defaults; they fsync per implicit transaction and the per-frame write paths become a disk-hammer. The world clock does NOT persist per advance: `Timekeeping.advance_*` marks a dirty flag, and `SessionRunner.flush_clock_and_queue()` writes clock + scheduled_events together in ONE transaction at the choke points — every scheduler pause, every day boundary, and `save_session` (which also wraps active_effects in the same transaction). The in-memory clock is authoritative between flushes; crash exposure is bounded by the current running stretch. Two rules for code inside these transactions: only single-statement repository helpers (a callee with its own BEGIN/COMMIT commits the enclosing transaction prematurely), and signal-handler flushes must use the guarded-BEGIN pattern (`var own_txn := db.query("BEGIN TRANSACTION")` … `if own_txn: COMMIT`) since they can fire inside an enclosing transaction. Teardown ordering: pause the loop BEFORE clearing the scheduler, or the pause-flush persists an empty queue (see SessionRunner.end_session).

**Durations ruled in months stay in months.** A const initializer cannot reference an autoload, so a duration that a ruling expresses in months is declared as a month count and converted at the use site — never pre-multiplied into a hardcoded day count:

```gdscript
# GOOD — sanctum_apprentice_resolver.gd (Q20: "exactly 4 months")
const PROMOTION_DELAY_MONTHS: int = 4
...
"promotion_eligible_day": calendar_day + PROMOTION_DELAY_MONTHS * Timekeeping.DAYS_PER_MONTH,

# BAD — pre-multiplied with the wrong month length; sat wrong for a month
const PROMOTION_DELAY_DAYS: int = 120   # "4 months" × 30-day months on a 28-day calendar
```

### 6.9 Avoid SELECT-then-write on the same table inside a tight loop

<!-- Added 2026-05-27 after debugging the "database is locked" cascade during
     session load. See build_log.md 2026-05-27 — Lock-cascade fix. -->

godot-sqlite (4.7) does not always finalize a SELECT statement before the next
same-table write when both happen inside an inner loop. The dangling SELECT
cursor leaves the table in a locked state and the following UPDATE/INSERT/DELETE
fails with `SQL error: database is locked`. Worse, **once the cascade fires,
later unrelated writes on the same connection (timekeeping save, weather cache,
etc.) inherit the locked state for the rest of the session.** The error logs
appear far from the actual bug site, so always trace cascades back to the first
SELECT-then-same-table-write inside an inner loop.

**Anti-pattern** — SELECT and write on the same table within the inner loop body:

```gdscript
# BAD — SELECT-then-write same table inside the loop body
for merch_type in modifiers:
    if db.query_with_bindings("SELECT source_kind FROM x WHERE id=? AND k=?",
                              [id, merch_type]):
        if db.query_result.is_empty(): continue
        if db.query_result[0].source_kind == "manual": continue
    db.query_with_bindings("UPDATE x SET v=? WHERE id=? AND k=?",   # FAILS: locked
                           [value, id, merch_type])
```

**Preferred fix 1 — inline the predicate in a single guarded UPDATE:**

```gdscript
# GOOD — single statement; the skip-manual condition lives in the WHERE
for merch_type in modifiers:
    db.query_with_bindings("""
        UPDATE x SET v = ?
        WHERE id = ? AND k = ? AND source_kind != 'manual'
    """, [value, id, merch_type])
```

**Preferred fix 2 — UPSERT with a WHERE on the DO UPDATE branch** (for the
INSERT-or-update case; relies on SQLite 3.24+ UPSERT syntax):

```gdscript
# GOOD — INSERT-or-update without a separate SELECT
db.query_with_bindings("""
    INSERT INTO x (id, k, v, source_kind) VALUES (?, ?, ?, 'generated')
    ON CONFLICT(id, k) DO UPDATE SET v = excluded.v
    WHERE x.source_kind != 'manual'
""", [id, k, value])
```

**Acceptable pattern — hoist the SELECT outside the loop**, `.duplicate()` the
result, then iterate writes locally. This is the proven-working form used by
e.g. `merchant_pool_repository.refresh_merchants` and
`npc_ruler_generator.stock_rulers_and_tribute`:

```gdscript
# OK — SELECT once, duplicate, then loop the writes
db.query_with_bindings("SELECT id FROM x WHERE ...", [...])
var ids := db.query_result.duplicate()
for row in ids:
    db.query_with_bindings("UPDATE x SET v=? WHERE id=?", [value, row.id])
```

If you genuinely need per-row pre-write data (e.g. a value used in a check
before deciding to write), include that data in the outer SELECT's column list
rather than re-querying per iteration. Treat the outer SELECT as the place to
gather everything the loop body needs.

When grepping for the anti-pattern, look for `query_with_bindings("""` calls
issuing `SELECT` and `UPDATE/INSERT/DELETE/REPLACE` on the same table within a
single function body, especially inside `for`/`while` loops.

**Known sites — fixed 2026-05-27:** [region_demand_resolver._write_demand_modifiers](engine/subsystems/commerce/region_demand_resolver.gd), [demand_modifier_generator._write_cache](engine/subsystems/commerce/demand_modifier_generator.gd).

**Known sites — fixed 2026-05-27 (monthly-drift sweep):** [market_price_resolver.process_monthly_drift_for_campaign](engine/subsystems/commerce/market_price_resolver.gd) now hoists the dice fields into its outer SELECT and passes each row to `check_and_apply_drift(..., prefetched_row)`, so the loop body issues only the drift UPDATE. The one-shot callers (`compute_market_price` → `_ensure_dice_row` / `check_and_apply_drift`, fired once per market visit, not in a loop) keep the read-then-write form — that is the acceptable single-statement-sequence case, not the inner-loop cascade.

### 6.10 Notebook page text colors — light parchment surface

<!-- Added 2026-05-27 after the notebook content-text-invisible debugging. See
     build_log.md 2026-05-27 — Notebook text-color fix. -->

The Management Notebook page (`SBF_notebook_page`) is **light parchment**
`Color(0.9, 0.84, 0.74)`. Any text rendered on it must be **dark** or it is
invisible. Content migrated from the old `CharacterSheetOverlay` /
`PartyManagementOverlay` (which had dark backgrounds) carried light/cream text
colors that vanished on the light page — the bug class this section prevents.

**Notebook surface → text-color map:**

| Surface (stylebox) | bg | Text color |
|---|---|---|
| `SBF_notebook_page` (tab content) | light `0.9,0.84,0.74` | **dark** `VELLUM_TEXT_COLOR` (0.09,0.06,0.03) |
| `SBF_notebook_tab_active` (active tab chip) | light | dark |
| `SBF_notebook_container` (right-edge tab strip) | dark `0.16,0.1,0.05` | light |
| `SBF_notebook_tab_inactive` (inactive tab chip) | dark `0.3,0.2,0.1` | light |
| `SBF_framed_window` (sub-modals) | dark `0.19,0.13,0.08` | light |

**Use the shared palette** from `UiSurfaceStyles` (do NOT hardcode cream/gray text on the page):
- `VELLUM_TEXT_COLOR` `Color(0.09,0.06,0.03)` — primary body/heading text on the page.
- `VELLUM_SECONDARY_TEXT_COLOR` `Color(0.34,0.27,0.19)` — de-emphasized/secondary text (hints, timestamps, "dim" rows). Readable on parchment without washing out. Replaces the old light "DIM"/cream tones.
- `VELLUM_WARNING_TEXT_COLOR` `Color(0.46,0.12,0.08)` — warning/error text.
- Saturated semantic accents (HP red/green/orange, loyalty bands, gold pins) are fine on the page — keep them.

**Two traps that look like text-color bugs but are NOT** (don't "fix" these):
1. **`modulate` on a Label is a multiplier** (≤1 darkens). A `modulate = Color(0.85,0.85,0.85)` on dark theme text keeps it dark — it does not make text light. Only `font_color` overrides (or unthemed control types) cause light-on-light.
2. **`StyleBoxFlat.bg_color` named `_COLOR_NORMAL`/`_COLOR_DROP_OK`** etc. are panel/drop-zone backgrounds, not text. Light values there are correct.

**State-dependent chips** (entity tabs, sub-tab buttons whose background flips with active state) must flip text color with the state — dark on the light/inactive surface, light on the dark/active surface. See `notebook_tab_strip.gd` (`ACTIVE_LABEL_COLOR`/`INACTIVE_LABEL_COLOR`) and `entity_tab.gd` (`NAME_ACTIVE_COLOR`/`NAME_INACTIVE_COLOR`) for the pattern.

**`LinkButton` is NOT covered by the project theme** — it falls back to Godot's light default and is invisible on the page. Any `LinkButton` on the notebook page needs an explicit dark `font_color` override (see `party_tab_page.gd` member rows).

### 6.11 A plain Control does not stretch its children — anchor script-built roots to full-rect

<!-- Added 2026-05-27 after the "blank notebook tab" bug. See build_log.md
     2026-05-27 — Notebook tab content-collapse fix. -->

Containers (`VBoxContainer`, `HBoxContainer`, `PanelContainer`, …) lay out and
stretch their children per size flags. A **plain `Control` does not** — a child
added to it via `add_child()` keeps its default top-left anchors and **minimum
size**, regardless of `SIZE_EXPAND_FILL`. Size flags are honored by the *parent
container*, so they do nothing when the parent is a plain Control.

This bit the Notebook hard: each tab page (`notebook_tab_page`) is a plain
`Control` hosted in the `_page_holder` VBoxContainer. The page itself is
stretched by that container, but the page is not a container, so the root
layout node a tab builds (`root_vbox`, etc.) stayed at minimum size. Fixed-height
chrome (headers, sub-tab strips, dropdowns) still showed, but an
`SIZE_EXPAND_FILL` content area — especially a `ScrollContainer`, whose minimum
size is ~0 — **collapsed to zero height and rendered blank**. Tabs whose content
had intrinsic size (Inventory's carrier columns) showed but cramped at top-left.

**Rule:** when you `add_child()` a layout root to a plain `Control` and want it
to fill, anchor it explicitly:

```gdscript
# GOOD — root fills the plain-Control parent
add_child(root_vbox)
root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# BAD — relies on SIZE_EXPAND_FILL, which a plain Control ignores → collapses
root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
add_child(root_vbox)   # stays at minimum size
```

`set_anchors_and_offsets_preset(PRESET_FULL_RECT)` (anchors 0,0,1,1 + offsets 0)
makes the child track the parent's size dynamically. `set_anchors_preset()`
alone is NOT enough — with default `keep_offsets`, it leaves the child at its
old rect.

For the Notebook this is handled once in the base class:
`notebook_tab_page._stretch_content_children()` (called after `_build_content`)
full-rects every `Control` child, so individual tabs don't repeat it. The
regression test is `tests/test_party_tab.gd::test_content_root_is_stretched_full_rect`.

### 6.12 Per-hex campaign-progress state goes in keyed side-tables, never in hex_cells

<!-- Added 2026-06-10 during the lair lazy-placement rewrite (migration 152). -->

`CampaignRepository.save_hex_map()` persists fog-of-war by `INSERT OR REPLACE`-ing
**every** `hex_cells` row from the in-memory `HexTerrainData` objects — and it
runs on every travel leg. Any column added to `hex_cells` that is written by a
*handler* (not round-tripped through `HexTerrainData`) is silently reset to its
default on the next fog save.

**Rule:** `hex_cells` holds terrain + fog only — data that `HexTerrainData`
owns in memory. Campaign-progress state keyed to a hex (lair budgets, survey
reveals, future per-hex flags) goes in a dedicated side-table keyed
`(campaign_id, map_id, hex_q, hex_r)`, with repository CRUD and (when the
state has any orchestration) a small service facade.

```text
GOOD — hex_lair_state table (migration 152) + HexLairState service
       survey_progress table (migration 051, + party_id in the key)
BAD  — ALTER TABLE hex_cells ADD COLUMN lair_budget …  (clobbered by save_hex_map)
```

When a GDD's implementation map says "add columns to the hex table," translate
it to this pattern; `gdd-lair-discovery.md` §8 records the precedent. New
side-tables must also be classified in `CampaignRepository._SCOPE_DIRECT_CAMPAIGN`
(or excluded) or `test_savegame_snapshot` fails the scope-coverage audit.

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

### 7.4 Runtime Data Extracted from Sacred Rules XML (added 2026-05-27)

**Hard rule: `rules/*.xml` files are NEVER read at runtime.** The XML rule summaries under `rules/` are the project's "sacred" source of truth for ACKS rules, but they are not the runtime format. Runtime systems consume RAW tables only through **build-time extracted** data files under `data/<subsystem>/`.

This convention exists because runtime XML parsing is slow, brittle (one malformed cell breaks the parser at game start), and lacks the test discipline that the data layer demands. The encoded data files also serve as a stable interface: a Claude Code session editing a runtime subsystem can read the JSON without dragging the full XML grammar into its working context.

#### 7.4.1 What gets extracted

Any RAW table, list, or constant that a runtime system needs to consult. Examples:

- Condition catalog (`data/conditions/condition_catalog.json` from `ax_conditions_catalog.xml`).
- Dungeon stocking, wandering monster, and treasure tables (`data/dungeon_generator/*.json` from `acore-setting-construction-rules.xml`, `acore-monster-stocking-rules.xml`, and `acore_treasure_and_magic_items_rules.xml`; see [`gdd-dungeon-generator-v1.md`](../generation/gdd-dungeon-generator-v1.md) §12).
- Monster catalog (the per-monster stat blocks from `acore_monster_catalog_*.xml` and `le_monster_catalog_*.xml`).
- Domain encounter tables (`data/domain_events/encounter_frequency_table.json` from `ax_domain_level_encounters.xml`).

What does NOT get extracted: prose, examples, flavor text, sidebars. The XML summaries already strip these; the JSON extraction should be a structurally faithful representation of the XML tables and procedures only.

#### 7.4.2 Required structure of an extracted file

Every extracted JSON file MUST include a `_source` field at the top level (or per-table inside, if multiple tables share a file) citing the originating XML file and line range. This makes "where did this datum come from?" trivially answerable:

```json
{
  "_source": "rules/acore-monster-stocking-rules.xml:76-94 dungeon_wandering_monster_level",
  "_extracted_by": "tools/extract_dungeon_generator_data.py",
  "_extracted_at": "2026-05-27T12:00:00Z",
  "rows": [...]
}
```

The `_source` is mandatory. The `_extracted_by` and `_extracted_at` fields are recommended for traceability but optional.

#### 7.4.3 Extraction script discipline

Each subsystem's extraction lives in `tools/extract_<subsystem>_data.py` (or `.gd` if GDScript-only). The script MUST be:

- **Idempotent.** Re-running on the same XML produces byte-identical JSON output.
- **Single-purpose.** One script per subsystem dataset; do not pile multiple subsystems' extractions into one script.
- **Self-documenting.** A header comment lists the input XML files, output JSON files, and how to invoke the script.

The script is run manually before commits when the corresponding XML changes, and run automatically by the CI diff test (§7.4.4).

#### 7.4.4 Mandatory CI diff test

Every extracted dataset MUST be covered by a test under `tests/data_integrity/test_<subsystem>_data_freshness.<py|gd>` that:

1. Re-runs the extraction script into a temp directory.
2. Diffs each freshly-extracted JSON against the committed copy under `data/<subsystem>/`.
3. Fails if any difference exists.

This is the gate that catches the failure mode "someone edited the XML but forgot to re-run the extraction." It also catches "someone hand-edited the JSON," because that hand-edit will not match what the extraction script produces from the XML.

#### 7.4.5 When a runtime system needs to query a RAW rule

The runtime system loads the extracted JSON via the standard data loader (typically a Repository or a static loader class), caches it, and queries the cached data. It does NOT touch the XML directly under any circumstance. If you find yourself reaching for an XML file from a runtime path, stop and either (a) extract the data you need at build time, or (b) confirm the data is already extracted and use the existing JSON.

#### 7.4.6 RAW PATCH lock-ins inside extracted data

If a RAW table contains a documented error and the project has a corrected reading (e.g., the [RESOLVED 2026-05-06] 17-63 = 50% efficiency band correcting source XML's "17-36" — see §35 entry already in this file), the correction lives inside the extraction script as an inline patch with the citation. The extracted JSON carries the corrected values. The extraction script's patch comment must cite both the source XML line and the project-decision date. The CI diff test then locks the corrected values in: any drift requires touching the patch deliberately.

The convention precedent for this pattern is the Vagaries-of-Recruitment table (§35-equivalent entries in this file's later sections); the dungeon generator dataset is the second instance.

#### 7.4.7 Hybrid extracted + curated catalogs, materialization, and value sentinels

*(Added 2026-05-29, magic-item prices.)* Some datasets combine XML-extracted **structure** (names, categories) with **curated data from a non-XML authoritative source** — e.g. the magic-item catalog's sale prices come from the game creator's published price list, validated against the SACRED creation formula. Conventions for this hybrid case:

- **Curated data lives in the extraction script**, never hand-edited into the JSON (a hand-edit is silently overwritten on the next run and fails the §7.4.4 freshness test). Add a provenance field naming the non-XML source (e.g. `_price_source`) alongside `_source`.
- **Bidirectional validation.** When the script stamps a curated per-item map (e.g. prices) onto extracted items, it MUST assert a bijection — every extracted key has a curated entry and every curated key matches an extracted item — and error loudly otherwise. This catches the "mistyped an item_key / forgot a new item" data-entry failure that would otherwise ship a mis-valued item. (`extract_magic_item_catalog.py` is the precedent.)
- **Materialization.** A catalog item may carry a `sub_roll` (a d100 variant table) or a named `generator`; the loader resolves the concrete item at *selection* time, deterministic given a seeded RNG. A materialized item's `item_key` may therefore NOT be a top-level catalog key (e.g. `ring_of_protection_1`), and its value-carrying fields (`value_gp`, `magical_bonus`) come from the variant/generator, not the parent. Read the price off the materialized item, never via a parent-key lookup.
- **Value sentinels** (`value_gp` in a catalog; `value_cp` on an inventory row): `> 0` = the price; `0` = explicitly worthless / non-sellable (e.g. cursed items); `-1` = no fixed price (a sub_roll/generator parent, or non-merchandise). Sell paths gate magic items on `value_cp >= 0` and reject `unit_value_cp <= 0`.

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

### 9.6 Test database isolation (2026-06-16)

The "test database" in the §9.3 table is a **separate file**, not the player's live DB. Test runs must never open, wipe, or lock the playtest data. Two layers enforce this:

- **In-code redirect (`CampaignRepository`).** `_ready()` calls `_is_test_run()` and, when true, points `db.path` at `TEST_DB_PATH` (`user://campaign_test.db`) and `_active_saves_dir` at `TEST_SAVES_DIR` (`user://saves_test`) **before `open_db()`**. The path must be chosen pre-open — a post-open close/reopen swap triggers godot-sqlite FK-check breakage (the original reason the suite wiped the live file in place). `_is_test_run()` returns true if the command line contains `test_runner.tscn` **or** an explicit `--test` flag. `wipe_for_tests()` is guarded: it refuses to run unless `is_test_run` is set, so a stray call can never nuke live data. Any new save-file path **must** route through `_active_saves_dir`, never the `SAVES_DIR` constant directly, or it will escape the redirect.

- **APPDATA isolation (`tools/run_tests.ps1` / `.sh`).** Godot derives `user://` from `%APPDATA%` + the project name, which is **identical across every git worktree** — so by default concurrent worktrees share one `campaign.db` (lost playtest data, `database is locked` spam). The wrappers point `%APPDATA%` at a stable per-worktree temp dir before launching, giving each worktree a fully private `user://`. This is the **required** way to run the suite when another worktree is active. The dir is stable per worktree, so re-runs reuse the same isolated test DB (no fresh-DB FK-noise every run; measure pass/fail on run 2 of a freshly-created dir — run 1 applies all migrations with `foreign_keys` ON).

Net effect: the suite's `wipe_for_tests()` (called at both the start and end of `test_runner.gd.run()`) only ever clears the isolated test DB + `saves_test/`. The player can keep a long-running playtest campaign across any number of test runs.

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
| Hide-and-memorize cost | 1 hour of world-clock time (6 turns via `Timekeeping.advance_turns`). No proficiency check. | GDD §8.3 |
| Transfer validation | All inventory transfers route through `PartyInventoryTransferValidator` (RefCounted, `class_name`). Returns `{ok, reason, warnings, resolved_slot}`. Coin transfers are blocked ("use Transfer Gold modal"). Equipped clothing is immovable. Cross-location transfers rejected. Draft-saddle creatures reject cargo (explicit check — `CreatureEquipmentService` doesn't catch this). Dungeon adjacency and combat trade action are stubs for v1. | `gdd-party-inventory.md` §4 |
| Party split/merge | Splits create a new party at the same hex via `CampaignRepository.split_party()`; `SessionRunner` seeds the new party's day/noon ticks on the `party_split` signal. Merges require co-location (same hex, same map) via `CampaignRepository.merge_parties()`; on `party_merged`, `SessionRunner` cancels the dissolved party's queued events and re-points the session if the primary was merged away (single-timeline rework 2026-06-11 — `sync_parties()` no longer exists). `GameState.active_party_id` tracks which party the player controls; switch via `GameState.set_active_party()`. Wilderness-only for v1. | `coding_conventions.md` §15.5/§19.5, 2026-06-11 |
| Treasure XP | 1 XP per 1 GP of recovered coins, gems, jewelry, or special treasure. Awarded at the moment of distribution (modal Apply or Pick Up All). Equipment excluded until sell-for-XP system exists. Wired via `XPAwardCalculator.award_adventure_xp(monster_xp=0, treasure_xp=N, members)`. v1 simplification: XP awards on pickup, not "return to civilization." | `acore_adventures_and_encounters.xml`, 2026-04-18 |
| Dungeon loot placement | Defeated dungeon monsters' treasure lands in a `location_cache` at the leader's death cell (variant `"loose"`, `location_type = "dungeon_cell"`). Cache decay rules per GDD §8.2 apply. The cell flag `has_ground_items` enables the existing Loot/Pick Up All context menu options. The dungeon Loot action opens `LootDistributionModal.open_from_cache()`. | `gdd-party-inventory.md` §8, `gdd-dungeon-map-ui.md` §3.4, 2026-04-18 |
| Fractional caster level | The warlock casts "as a mage of two thirds class level" (PC p.47). Effective caster level = `round(2/3 × class level)` to NEAREST — 2/3 multiples never land on exactly .5, so banker's rounding is never engaged; nearest-rounding reproduces the printed slot table (= mage slots at that level). Implemented at the single choke point `CasterContext.effective_caster_level()` (`CASTER_LEVEL_RULES` const mirrors the `caster_level_rule` field on the class's casting power in `data/classes/<id>.json`); every spell resolution, dispel contest, and active-effect row inherits it. SLOTS still come from the class's own printed progression table, not from the mage table at runtime. | `rules/pc_classes_6.xml`, `caster_context.gd`, 2026-06-11 |

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

## 14. Dice Conventions

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

## 53. Tactical Grid Conventions (Voxel)

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

The game operates on a **real-time-with-pause** model. An `EventScheduler` priority queue holds future events keyed to absolute game-time timestamps (elapsed rounds). A `SchedulerLoop` ticks every frame during active gameplay, advances the world clock to the next event, resolves it via an `EventHandlerRegistry`, and repeats. The player controls clock speed (Pause/1x/2x/5x/Max).

**Core classes (all `RefCounted`, owned by SessionRunner — NOT autoloads):**

| Class | File | Role |
|---|---|---|
| `ScheduledEvent` | `engine/subsystems/session/scheduled_event.gd` | Data class for a single queued event |
| `EventScheduler` | `engine/subsystems/session/event_scheduler.gd` | Sorted priority queue |
| `EventHandlerRegistry` | `engine/subsystems/session/event_handler_registry.gd` | Maps event_type → handler Callable |
| `SchedulerLoop` | `engine/subsystems/session/scheduler_loop.gd` | Frame-tick driver, speed control, auto-pause |

**Speed & pause signal contract (2026-06-12):** `SchedulerLoop` is the ONLY emitter of `scheduler_paused` / `scheduler_resumed` / `scheduler_speed_changed` — UI must never emit these on EventBus directly (it desyncs every listener from the actual loop state; the pause-menu/save-panel spoof emits were removed). `set_speed()` delegates to `pause()` / `resume()` at the pause boundary, so toolbar pauses and unpauses always broadcast and always clear stale auto-pause state. Pass the pause reason as the `pause(reason)` parameter — never pre-set `auto_pause_reason` and then call `pause()`; the parameter is what the signal carries, so a stale reason can never be replayed. Frame deltas are clamped to `MAX_TICK_DELTA` (0.25s) inside `_tick_normal` so a window-drag hitch cannot fast-forward the world; already-due events (fire_time <= now) resolve immediately regardless of the fractional-round accumulator.

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
| `wilderness_handlers.gd` | ALL GLOBAL (Option 2, 2026-06-12): `travel_leg`, `wilderness_encounter_check`, `getting_lost_check`, `forced_march_check`, `wilderness_activity`, `wilderness_activity_complete`, `wilderness_day_tick`, `wilderness_noon_tick`, tracking/pursuit/encounter events. Registered for the whole session by `SessionRunner.load_session`; background parties' chains resolve in every context. |
| `dungeon_handlers.gd` | state-scoped: `dungeon_movement_tick`, `dungeon_encounter_check`, `dungeon_light_tick`, `dungeon_action_complete` |
| `settlement_handlers.gd` | state-scoped: `settlement_move`, `settlement_activity`, `settlement_encounter` |
| `camp_handlers.gd` | state-scoped: `camp_watch`, `camp_rest_complete` |
| `domain_handlers.gd` | global: `domain_monthly_tick` |

Handler classes are `RefCounted`, take a `runner` (SessionRunner) in `_init()`, and expose `register(registry)` / `unregister(registry)` methods. Dungeon/settlement/camp states create and own their handler instance; the wilderness instance is session-lifetime, owned by SessionRunner and borrowed by `WildernessExploreState` via `runner.get_wilderness_handlers()`.

**Registration scope rule (amended again 2026-06-12 — park-don't-consume):** an event coming due with no registered handler is no longer destroyed — `SchedulerLoop` parks it (`EventScheduler.park`) and `EventHandlerRegistry.register()` re-injects it when a handler for its type appears, so it resolves on the next tick in the registering context. Parked events stay pending obligations: they persist via `to_dicts()`, count in `size()`/owner queries (idempotency checks see them), and are reachable by `cancel_all_for_owner`. Scope guidance therefore becomes a LATENCY decision, not a data-safety one: register globally when the event must resolve PROMPTLY regardless of the player's context (`WildernessHandlers` — background parties act in real time; Option 2), and state-scoped when deferred delivery on context entry is correct UX (`commission_ready` fires mid-wilderness, parks, and is delivered as you next enter a settlement). Dungeon/settlement/camp handlers stay state-scoped (a background party cannot occupy those contexts in v1; split/merge is wilderness-only, §12). `test_all_wilderness_handlers_register_globally` pins the global set. Background-decision policy: see `_is_wilderness_ui_active` in `wilderness_handlers.gd` (halt-and-drop) and `docs/handoff_party_context_switching.md` (the Option 1 upgrade).

### 19.4 Priority Tiebreaker Rules

When multiple events share the same timestamp, resolve in this order (lower number = first):

| Priority | Constant | Category |
|---|---|---|
| 0 | `PRIORITY_ENVIRONMENTAL` | Weather, dawn/dusk, season, light ticks |
| 10 | `PRIORITY_SCHEDULED_CHECK` | Wandering monster rolls, encounter checks |
| 20 | `PRIORITY_ARRIVAL` | Travel arrival, search complete, construction done |
| 30 | `PRIORITY_CONSEQUENCE` | Combat start, trap trigger, domain event |

Within the same priority tier, alphabetical `owner_id` breaks ties; events still tied after that resolve in **scheduling order (FIFO)** via the monotonic `sequence` stamp that `EventScheduler.schedule()` writes onto every event (added 2026-06-12). Tie order survives save/load: `get_scheduled_events` orders by `(fire_time, rowid)` and the scheduler re-stamps sequences in load order. Never construct ordering-sensitive logic on raw insertion position — the sequence stamp is the contract.

### 19.5 Time Advancement Rules

<!-- Rewritten 2026-06-11 for the single-shared-timeline ruling (docs/handoff_multi_party_time.md) -->

- **One world clock:** `Timekeeping.get_total_rounds()` is "now"; `Timekeeping.advance_rounds(n)` advances. The per-party clock API no longer exists (§6.8). Event `owner_id` discipline is still mandatory — every scheduled event belongs to the party (or world owner like `"domain_global"`) it concerns, for cancellation and lock semantics.
- **fire_time is always ROUNDS:** day-granular systems (sieges, disease, call-to-arms) keep their day-serial bookkeeping but convert at the scheduling boundary via `Timekeeping.calendar_day_to_rounds(day_serial)` — see the §6.8 calendar-day block.
- **Clock persistence is debounced:** advances mark the clock dirty; `SessionRunner.flush_clock_and_queue()` persists clock + queue atomically on pause / day boundary / save (§6.8 persistence policy). Never reintroduce a per-advance save.
- **Idempotent scheduling:** "schedule X unless one is already pending" uses `EventScheduler.has_event_for_owner(owner_id, event_type)` (covers queued AND parked events) — never a hand-rolled `get_events_for_owner` scan.
- **Combat rounds up to the next turn:** After combat, `CombatFinalizer` advances the world clock by rounds fought, then rounds up to the next turn boundary (ACKS RAW, sacred: combat < 1 turn consumes a full turn). Background parties' events due inside the rounded window fire during the skip — ruled acceptable 2026-06-11 ("the world keeps moving").
- **No order-lock (ruled 2026-06-12, superseding the 2026-06-11 order-lock):** under the single timeline nothing needs locking — the lock concept belonged to the abandoned catch-up-time model. **A new order supersedes the old one.** Order surfaces cancel the party's pending travel AND in-progress activity events via `cancel_all_for_owner` before scheduling replacements (wilderness: `_on_context_action`; settlement: `_on_poi_clicked` cancels `city_travel_arrival`/`city_encounter_check`/`settlement_activity`). Time already spent is spent — the world clock moved; a cancelled activity yields nothing. Do not reintroduce a lock; if a future activity must be uninterruptible, gate it at its own order surface with an explicit confirm dialog instead.
- **Dungeon time is world time:** dungeon exploration advances the same clock as everything else; there is no async dungeon timeframe and no time-lock on exit.
- **Party lifecycle hooks:** on `party_split`, `SessionRunner` seeds the new party's day/noon ticks immediately; on `party_merged`, it cancels the dissolved party's queued events (`cancel_all_for_owner`) and re-points the session at the survivor if the primary was merged away.
- **Party-context switching (Option 1, 2026-06-12):** active = watched = selected. Every `GameState.set_active_party` is a full focus switch: `SessionRunner._apply_party_focus` re-points the watched-party trio (`_party_id`, `GameState.party_id`, `_party_data` via `_repoint_watched_party`) and transitions the UI to the party's persisted `current_location_type` context (loader-mirror builders `_build_dungeon_focus_context` / `_build_settlement_focus_context` — keep in sync with `SessionLoadState`). Switching is blocked (selection reverted + toast) in combat, camp, menus, and dungeon in-place combat (`is_in_combat()`). Toast actions focus a party via `EventBus.party_focus_requested` → `SessionRunner.go_to_party`.
- **Suspend ≠ exit (dungeon):** `DungeonExploreState.exit()` without `_departing` is a SUSPEND — it flushes positions/cells against the visit's captured `_owning_party_id` (NOT `runner.get_party_id()`, which is already re-pointed) and keeps picked locks, persisted positions, and queued dungeon events (the focus-coupled clock keeps them from coming due; park-don't-consume catches the combat lump-sum exception). Only the two real-departure sites (`_on_exit_requested`, `_on_all_party_resolved`) set `_departing`, which reverts locks, cancels dungeon events, and clears positions. `seed_dungeon_events` is queue-idempotent for resume.
- **Focus-coupled clock (Jedidiah's "Option C", 2026-06-12):** while ANY party has `current_location_type == 'dungeon'`, the world clock runs only while the dungeon layer has focus. `SessionRunner.get_clock_lock_reason()` ("" = unlocked) is the authority: consulted by `_on_clock_speed_requested` (toast + refuse), by every state-side `loop.resume()` call outside the dungeon, and by the wilderness camp-entry gate. `EventBus.clock_lock_changed` drives the disabled speed buttons. Pausing is always allowed. New `loop.resume()` call sites outside the dungeon layer MUST check the lock.
- **Switch-first encounters:** a background party's triggered encounter is fully formed (weather/gate/lair work included), then persisted to `party_state.pending_encounter` (`var_to_str`, never JSON — encounter dicts carry Godot types) with a sticky tap-to-act toast; `WildernessExploreState.enter` presents it through the normal `EncounterDecisionPrompt` (fire-and-clear, `call_deferred`).

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

## 25. Per-context scheduler speed profiles (2026-04-27; context-enum refactor 2026-06-12)

The scheduler's three speed bands (`SPEED_NORMAL`, `SPEED_FAST`, `SPEED_VERY_FAST`) are **caller-facing ordinals**, not multipliers. The actual rounds-per-real-second depends on the current exploration context, declared EXPLICITLY by states via `SchedulerLoop.set_context(TimeContext)` and looked up in the single profile table:

```gdscript
enum TimeContext { DUNGEON, SETTLEMENT, WILDERNESS }
const CONTEXT_PROFILES := {
	TimeContext.DUNGEON:    {"timescale": 1.0,  "bands": _BANDS_DUNGEON},   # ×1/×6/×30
	TimeContext.SETTLEMENT: {"timescale": 6.0,  "bands": _BANDS_STANDARD},  # ×1/×2/×5
	TimeContext.WILDERNESS: {"timescale": 60.0, "bands": _BANDS_STANDARD},  # ×1/×2/×5
}
```

Why context-coupled: the per-context timescale already amplifies the band (wilderness = 60×, settlement = 6×). Reusing one global multiplier across contexts means dungeon Fast and wilderness Fast are wildly different in felt pace. The profiles let dungeon get a tighter band (1 round = 1 round) while wilderness keeps its hour-jumping behaviour at the same UI button.

**The context is never inferred.** The pre-2026-06-12 implementation matched the float timescale against known constants and silently fell back to the wilderness table for anything unrecognized — any timescale tuning or new context would have changed speed bands with no error. `set_context()` sets timescale + bands together and asserts on unknown contexts. `set_timescale()` no longer exists.

Anything that needs the live multiplier should call `SchedulerLoop.get_effective_multiplier()` rather than reading `_speed` directly; consumers that must be pinned to a specific context (the dungeon renderer's tween-speed computation) read that context's row from `CONTEXT_PROFILES` — never a hand-copied table.

Adding a new exploration context: ONE `TimeContext` enum value + ONE `CONTEXT_PROFILES` row. States declare it in `enter()`; Option 1 party-context switching declares it on every watched-context change.

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

## 28. Provisions: inventory-as-truth consumption model (2026-05-05; revised 2026-06-08)

**Revised 2026-06-08 (gdd-rations-foodstuffs.md, Option B).** This section formerly read "the abstract counter is the source of truth; inventory is purely descriptive." That is **retired**: carried rations, water, and fodder are now real `inventory_items` consumed day by day. `PartyData.ration_units` / `water_units` are **per-tick DERIVED scratch values**, not persistent truth.

The SACRED `SustenanceResolver` math is kept UNCHANGED by wrapping it each `wilderness_day_tick`:

1. **derive** — `ProvisionsService.derive_food_into_counter` / `derive_water_into_counter` sum carried provisions out of inventory INTO the counters.
2. **resolve** — `SustenanceResolver.apply_daily(party, dice)` runs unchanged: decrements the counters by `party_size`, rolls the RAW starvation/dehydration HP curves.
3. **writeback** — `ProvisionsService.writeback_food` / `writeback_water` decrement the real inventory rows that were eaten/drunk.

Key rules:
- **Foraged food stays the counter's surplus.** `ForagingResolver` / `HuntingResolver` still deposit into `ration_units`; that foraged surplus is consumed FIRST each day, before any carried item (carried order: perishable → standard → iron via `ProvisionsLedger.food_priority`). Foraging is therefore unchanged.
- **`consumable_units_remaining` (migration 149)** is the per-row depletion state in person-days: `-1` = uninitialized = full (`quantity × catalog.consumable_person_days`); `>=0` = explicit remaining. Food/fodder rows are deleted at 0; water containers persist empty at 0. Distinct from `uses_remaining` (torch turns / scroll charges).
- **Water lives in containers.** `holds_water` items only — waterskin (liquid-only) and barrel (items XOR water; an item-bearing barrel is excluded). `holds_water` is now **load-bearing** (was UI-only). `water_units` is derived from container fill. **Hybrid back-compat:** a party with NO water containers keeps the legacy abstract `water_units` counter (derive/writeback are no-ops there), so container-less parties and the existing Decanter / refill tests are unaffected.
- **Fill-at-source** (`WildernessHandlers._refill_water_at_hex`, `DecanterRefillService`) fills all eligible containers to capacity for container parties, or tops the legacy counter to `party_size` for container-less parties.
- **Fodder + grazing (migration 150).** `AnimalSustenanceResolver` + `GrazingRules` feed trained creatures. Each animal needs `GrazingRules.daily_fodder_units` (by size) UNLESS it can graze/hunt the current terrain (per-diet × biome; RAW `le_monster_training_rules.xml:415`). Unfed non-grazers accrue `trained_creatures.fodder_starvation_days` and lose HP on the PC curve. Animals do NOT draw from the water counter (RAW gives no per-animal water rate).
- **Pure vs I/O split.** `ProvisionsLedger` (pure person-day math), `GrazingRules`, and `AnimalSustenanceResolver` are pure/static; `ProvisionsService` does all DB I/O. Display sites (Status Bar `_refresh_party_status`, inventory footer `_count_rations`) read real food/water-days through `ProvisionsService` — never the dead `rations_days_remaining` field.

When adding provisions hooks: change inventory (the truth) and let the derive/writeback wrap the resolver; never reintroduce a parallel "counter is truth" path.


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

- **All randomness in the encounter resolver routes through the `dice` abstraction — including uniform list/creature selection (2026-06-25).** `DomainEncounterResolver._generate_encounter(dice, …)` accepts a `dice` so a mocked/seeded dice FULLY determines the encounter. Every die roll uses `_roll_die(sides, dice)`, and the uniform creature pick uses `var idx := _roll_die(filtered.size(), dice) - 1` (same idiom as `DragonVariantResolver`). Never reach for raw `randi()` here — it escapes the abstraction and makes the encounter non-reproducible (this was the root cause of a flaky `is_lingering` test; see §14 + build_log 2026-06-25). Production passes `dice = null`, so `_roll_die` falls back to `randi_range(1, size)`: the `- 1` yields a uniform `0..size-1` index, distribution-identical to the old `randi() % size`. Tests that need to exercise a SPECIFIC creature or the WHOLE pool must drive the pick deterministically (a fake dice that returns the desired index roll, e.g. `tests/test_phase_9c.gd`'s `IndexWalkDice`), NOT loop-and-hope on randomized sampling.


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


## 54. Phase 9C polish round 2 — five carry-forward conventions (2026-05-09)

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


## 49. Phase 10A.1 — Class-bucket detection (2026-05-10; updated 2026-06-03: Q14 bucket set + `is_syndicate_class` + thief→syndicate domain block)

- **`ClassBucketResolver` is the single source of truth for class-specific buckets.** All callers determining whether a character sees the Class-Specific Domain sub-tab — and which blocks render within it — MUST query `ClassBucketResolver.buckets_for(character_id)`, `has_bucket(character_id, "syndicate")`, `primary_bucket_for(character_id)`, or `sub_tab_label_for(character_id)`. Never write ad-hoc class-id checks like `if class_id in ["cleric", "bladedancer", "priestess"]:`. The resolver lives at `engine/subsystems/domains/class_bucket_resolver.gd` and reads from `data/classes/<class_id>.json` `class_powers` via a cached `ClassRegistry` singleton (`_class_registry_cache` pattern, mirrors `Combatant._get_class_registry()`). Five canonical bucket ids: `"faith"`, `"magical_research"`, `"trade"`, `"syndicate"`, `"bardic_patronage"` (per `gdd-domain-tab.md` §4.4 + §12.1).

- **Engine validators that hold a class string (not a `character_id`) use `is_syndicate_class(class_id)`.** Both `is_syndicate_class` and the `"syndicate"` bucket route through the single `SYNDICATE_CLASS_IDS = ["thief", "assassin", "elven_nightblade"]` allowlist. This predicate is the gate that blocks the three syndicate classes from running domains or building domain-securing strongholds: a thief's hideout is NOT a domain-securing stronghold (`ax_thief_skill_update.xml`:50 "Hideouts are secret strongholds; do not secure domains"). Callers: `establish_domain_flow.gd` (rejects with `ERR_SYNDICATE_CLASS_NO_DOMAIN`), `commission_pipeline.gd` + `claiming_resolver.gd` (reject stronghold construction/claim). **Trap:** `dwarven_delver` shares thief combat-progression and thief skills but secures a real domain via a vault — it is NOT a syndicate class and KEEPS its domain. Drive any syndicate-vs-domain branch off this allowlist, never off combat_progression or a "thief skills" check. The Venturer has the parallel predicate `is_venturer_class` (the "trade" bucket's class-string form) used at the same three guard sites to block its domain-less mercantile-venture economy (see §77).

- **Bucket detection is power-id-driven EXCEPT syndicate, which is a class-id allowlist.** The resolver checks for specific `power_id` strings on the character's class definition, with one documented exception:
  - `faith` ← `divine_casting` OR `spell_research_and_minor_item_creation` (the Bladedancer's restricted divine power)
  - `magical_research` ← `arcane_casting` OR `arcane_casting_in_armor` (elven variant + Darkblood Ruinguard) OR `spell_research` (per Q11: divine casters with full research stack MR alongside Faith)
  - `trade` ← `stronghold_guildhouse`
  - `syndicate` ← `class_id in {"thief", "assassin", "elven_nightblade"}` (per Q14 [RESOLVED 2026-05-11]). This is a **documented exception** to the "no ad-hoc class-id lists" rule: RAW itself (`acore-campaign-hijinks.xml` §hijinks-eligibility) enumerates class ids, and power-id detection wrongly excluded the Assassin (fighter combat-progression, but hijink-eligible). The allowlist lives in `SYNDICATE_CLASS_IDS` and is also exposed as `is_syndicate_class(class_id)`.
  - `bardic_patronage` ← `class_id == "bard"` (its own bucket per Q14 — RAW: `hireling_inspiration` + `hall` from `acore_campaign_classes.xml`). The prior `garrison_training` bucket was REMOVED in Q14 (troop training is proficiency-gated in the Garrison sub-tab, not class-gated).
  Pattern: detection rules cite the RAW source for each branch in the resolver's docstring; tests assert one row per class in the §12.1 matrix.

- **Divine-side magic research belongs in the Faith block, not Magical Research.** Cleric / Bladedancer / Priestess / Shaman / etc. have `spell_research` and `magic_item_creation` powers but they research divine spells and create divine items. Per `gdd-domain-tab.md` §12.1, only arcane casters get the Magical Research bucket; divine research surfaces inside the Faith block. The resolver enforces this by NOT having a fallback `(mage_progression + spell_research) → magical_research` rule — that branch would incorrectly capture Priestess (combat_progression="mage" + spell_research) and Witch (same shape). Pattern: when two distinct surfaces share underlying mechanics but separate by school/category, gate the bucket strictly by the school-specific power id, not by a generic "can research" capability.

- **Primary-bucket override for stacked-block ordering.** When a class has multiple buckets (Bladedancer = Faith + Garrison Training; Lightblessed = Magical Research + Faith), `PRIMARY_BUCKET_OVERRIDE[class_id]` decides which card opens expanded by default. Absent an override, the first bucket in the canonical `BUCKET_IDS` order wins. Pattern: when stacked-card UIs have a class-specific "lead" card, store the override as a per-class constant on the resolver, not as a UI parameter — keeps the visual hierarchy consistent across the tab.

- **Bardic Patronage is its own bucket (Q14 [RESOLVED 2026-05-11]).** Bards get the `bardic_patronage` bucket (label "Bardic Patronage"), surfacing Chronicles of Battle aura (`hireling_inspiration`, L5+) + Solicit Followers (`hall`, L9+). They do NOT see `oversee_troop_training` / `train_troops` — those moved to the Garrison sub-tab (proficiency-gated on Manual of Arms). This supersedes the earlier Q3 model where Bards shared a `garrison_training` bucket id with a variant surface; that bucket no longer exists.

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
  - **promotion_eligible_day** (INTEGER, nullable): for aspirants only. Set at `joined_calendar_day + 112` — exactly 4 months per Q20, computed as `PROMOTION_DELAY_MONTHS * Timekeeping.DAYS_PER_MONTH` on the 13×28 calendar. (Corrected 2026-06-12: the original 120 was a 30-day-month slip; rows persisted before the fix keep their +120 stamp.) The monthly-tick resolver in 10B.1d fires the d20 + ability_mod 14+ throw when this day is reached.
  - **0-level mercenaries stay in `troop_units`, not `followers`.** Hirelings paid wages without XP / treasure-share entitlement are mass-bookkept; followers are individually tracked persistent NPCs.

  Pattern: when the project's domain-of-discourse has a class of NPC that doesn't fit cleanly as "PC / henchman / NPC / hireling," introduce a distinct table rather than overloading existing types. Resist the temptation to make `characters.character_type` exhaustive — discriminator-overload makes lookups expensive and constraints brittle.

- **`promote_follower_to_henchman` is a cross-table operation that bypasses the standard hiring reaction roll.** Per Q25, the helper creates a `characters` row with `character_type='henchman'`, `persistence_tier='named'`, copies the follower's stats, then updates the source follower's `status='promoted_to_henchman'` with `promoted_to_henchman_id` linking forward. Henchman-slot eligibility is the caller's responsibility (the helper doesn't check Charisma-max — that's a UI-level gate). Pattern: cross-table promotion-style operations that change the entity's identity (follower → henchman) should be a single repository helper that does both the insert AND the source-row mutation atomically.

- **Aspirant promotion uses a single fixed 4-month timer (per Q20 [RESOLVED 2026-05-11]).** The standard sanctum's RAW 1d6-month variability (acore-campaign-hijinks.xml §sanctums L534-538) is collapsed to fixed 4 months (the expected value of 1d6, rounded to 4). Universal across Mage / Witch / Warlock / Elven Enchanter / Lightblessed Wonderworker. The Lightblessed-specific bits are: 50/50 mage/cleric split (per Q2), cleric branch uses WIS modifier, and INT/WIS gets boosted to 9 at aspirant creation if rolled lower. Pattern: when RAW prescribes a randomized timeline but the expected-value collapse simplifies UX without changing outcomes meaningfully, prefer the fixed-value approach. Document the simplification inline so future Q's can revisit.

- **`magic_research_projects` rows are terminal historical records, not live progress trackers.** (Corrected 2026-06-12.) The 10B.1b/c handlers run research through the ActivityTimeCostExecutor tick system (`activity_states.ticks_accumulated` / `ticks_required`, 1 tick = 1 real day) and insert the `magic_research_projects` row only at completion, already stamped `status='completed'|'failed'` with `days_completed = days_total`. The 10B.1a monthly-tick stub that advanced `days_completed += 30` on in_progress rows was REMOVED 2026-06-12 as dead code (no producer of in_progress rows ever shipped) and unit-wrong (30-day month on the 13×28 calendar). The status enum keeps `in_progress`/`abandoned` for future waves; if a wave introduces genuinely month-paced projects, advance by `Timekeeping.DAYS_PER_MONTH`, never a hardcoded 30 (see §6.8 calendar conventions).

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

## 53. Phase 10B.2 — Trade Block conventions (2026-05-14)

Established across the six Phase 10B.2 build waves (Foundation → Buy/Sell + UI Scaffold → Persuade/Solicit/Locate → Shipping Contracts → Triggers + Monthly Tick → Integration + Close-out). Conventions for the commerce subsystem at `engine/subsystems/commerce/` + mercantile activity handlers + the visit-state lifecycle + the trade-route trigger autoload.

- **`BuySellCommon` shared-helper pattern for sibling activity handlers.** Phase 10B.2 §3 splits `buy_sell_merchandise` into two handlers (`buy_merchandise.gd` + `sell_merchandise.gd`) per §32's one-id-per-file convention. The 80% they share — party resolution, entry-toll first-fire, deterministic transaction RNG, carrier capacity, receipt builders — lives in `engine/subsystems/commerce/buy_sell_common.gd` (RefCounted static-function library). The handlers call into it; tests exercise BuySellCommon directly. Pattern: when 2+ handlers in the same activity family share substantial setup/teardown, extract the shared logic to a per-family `<Family>Common.gd` helper rather than duplicating across handlers or pulling it up into the registry. Naming: `<family>_common.gd` (e.g., `buy_sell_common.gd`). Function naming: verb-led (`resolve_party_for_character`, `charge_entry_toll_if_first_visit`, `build_buy_receipt`).

- **§0.1.1 LLM-promotion forward-compat hook pattern.** The merchant_pool table ships a nullable `promoted_npc_id TEXT REFERENCES characters(id)` column + a `refused_at_calendar_day INTEGER` column. v1 has zero callers populating either; every lifecycle path checks them with a `WHERE promoted_npc_id IS NULL` filter or `AND refused_at_calendar_day IS NULL` clause. Cost: 2 nullable columns + 3 SQL clauses. Benefit: a future LLM tool-caller can promote a merchant to a named, persistent NPC without rewriting any lifecycle code. Pattern: when a system needs to support a future "lift transactional entity to persistent entity" path that isn't being built yet, ship the nullable FK column + the preservation clauses on every lifecycle DELETE/UPDATE in the foundation wave. Tag every preservation site with `[NEEDS-LLM-PROMOTION-LATER]` so a future grep finds all promotion-aware code paths in one pass.

- **`VisitStateManager` per-visit lifecycle pattern.** Per `gdd-phase-10b-2-trade-block.md` §9. The `party_visit_state` table holds one row per (party, settlement) while the party is at the settlement. INSERTed on entry, DELETEd on departure. Mid-visit handlers (buy / sell / persuade / locate / accept_shipping_contract) read the row to (a) check whether entry toll has fired this visit, (b) look up the active character recorded at entry for monopolist-favor and domain-owner exemption. Pattern: when a system needs "did X happen yet this visit?" state, prefer a dedicated table over a flag on the entity. The composite PK (party_id, settlement_id) is the natural key; INSERT-OR-IGNORE makes re-entry idempotent; the lifecycle entry/exit hooks own the lifetime. Cleanup is one DELETE statement; cross-handler queries are trivial column reads.

- **Wave 4's `MercantileForfeitRouter` signal-subscriber pattern for missing engine hooks.** The `ActivityHandlerRegistry` exposes only `on_complete` + `on_tick` — no `on_started` or `on_forfeited`. Wave 3's solicit_merchants needed both: a launch-side `process_solicitation` invocation (filled by the UI router calling `SolicitMerchantsHandler.prepare_launch` BEFORE `executor.launch`) and a terminal-forfeit rollback (filled by `MercantileForfeitRouter` subscribing to `EventBus.activity_forfeited`, filtering on status='forfeited'/'abandoned', and dispatching to per-activity `handle_forfeit` static methods). Pattern: when an engine-provided hook surface lacks a lifecycle phase you need, prefer (a) UI-router-side setup for the "start" case or (b) a signal-subscriber router for the "end" case BEFORE extending the engine. Each new engine hook is permanent surface area; the router pattern keeps the engine stable while adapting per-subsystem.

- **`CommerceMonthlyResolver` static-dispatcher pattern for cross-subsystem monthly coordination.** Per §11.4. Multiple substrate-shipped monthly drivers (customs roll, ship operating costs, merchant pool refresh, market price drift) need to fire in canonical order from a single entry point. The pattern: a `<Subsystem>MonthlyResolver` RefCounted static-function library (NOT an autoload) exposes one entry: `process_for_campaign(campaign_id, current_calendar_day, current_year, rng) -> Dictionary`. The existing monthly tick coordinator (`DomainHandlers._handle_monthly_tick`) adds ONE line invoking it. Each driver call's result is collected into the return dict; one EventBus aggregate signal fires at the end. Single-coordinator preserves ordering; per-subsystem dispatcher modularity; minimal coupling. Compare to alternative "every driver as its own autoload subscribing to month_advanced signal" — that creates ordering coordination problems and N autoloads where one would do.

- **`TradeRouteTriggerHandlers` map-state-mutation autoload pattern.** Per §10. A system that subscribes to MANY map-state-changing signals (settlement_created/destroyed/market_class_changed, road/river overlay added/removed, hex_water_tag_changed) needs to be always-on across the session lifecycle — including BEFORE the campaign loads (setting-generation creates settlements). It earns autoload status per §5. Signal subscriptions are idempotent via `is_connected` guards. The autoload also exposes a STATIC entry point (`full_sweep_for_campaign(campaign_id)`) for the campaign-load path; the static method is callable via class_name without needing the autoload instance. Pattern: when an autoload needs both "signal subscriber" and "called-directly entry" surfaces, mix instance signal handlers with static class-method entries. Document which signals are SUBSCRIBED (autoload listens) vs EMITTED (where the state-mutation lives) vs deferred forward-compat contracts (subscriber wired, emitter not yet wired in production — flag with `[NEEDS-EMITTER-WIRING-<signal>]`).

- **Year-tick handling via data-driven dedup (Y-Option 3 per §12).** Annual events (customs roll, future birthday triggers, etc.) live inside the monthly tick. The dedupe is a DB column (`campaigns.last_customs_roll_year`): the resolver reads it, fires the annual driver if `current_year > last_year`, and the driver updates the column. Idempotent across save/load + retroactive monthly catch-up. Pattern: when an annual event needs to fire exactly once per year, store the last-fired year on the entity and use a `current > last` guard inside the monthly dispatcher. Avoid both "month==1 check at year boundary" (calendar-coupling fragility) AND separate `year_advanced` signal + autoload (over-engineering for one annual event). Self-healing — if a year-tick was somehow skipped (player saved mid-year, loaded after a year passed), the next monthly tick catches it.

- **Pre-charging fees + `mark_*_paid` to pin test outcomes when handlers use internally-seeded RNGs.** Wave 6's integration test reproduces Prereq.8's §12 Ashford/Thornwall regression THROUGH the new buy/sell handlers. The handlers compute toll via `BuySellCommon.transaction_rng(party_id, settlement_id)` which seeds via `hash()` — the test can't pass a probed-RNG to the handler. Solution: pre-charge the toll externally (call `MarketFeesCalculator.entry_toll_cp` with a probed-RNG, `PartyWallet.pay` the result, `VisitStateManager.mark_entry_toll_paid`). The handler's `charge_entry_toll_if_first_visit` checks `has_paid_entry_toll` and short-circuits to 0. Pattern: when a handler uses internally-seeded RNGs and the test needs a specific roll value, externalize the dice-driven step (use the substrate's pure function with a probed seed) and mark the handler's state as "already done" so the handler skips its internal roll. Same outcome; deterministic.

- **Handler-routed integration tests vs substrate-direct integration tests.** Prereq.8 shipped `test_commerce_integration.gd` which exercises the substrate directly (`MarketPriceResolver.compute_market_price`, `MarketFeesCalculator.entry_toll_cp`, `PartyWallet.pay`, `CargoHoldRepository.insert_purchase`). Wave 6 ships `test_trade_block_integration.gd` which routes the SAME workflow through `BuyMerchandiseHandler.on_complete` + `SellMerchandiseHandler.on_complete` + `VisitStateManager.on_party_entered_settlement/departed_settlement`. Both produce the same +8,940 / +5,820 / +9,992 regression anchors. Pattern: when a substrate is consumed by a higher-level handler API, ship TWO integration tests — one verifies the substrate composes correctly, the other verifies the handler API surfaces an equivalent end-to-end flow. The two tests pin different layers and would catch different classes of regression (substrate breakage vs handler-layer drift).

## 54. Phase 10B.3 — Syndicate block (Hijinks) (2026-05-18)

Established during Phase 10B.3 (Migration 118 + SyndicateRepository + HijinkThrowTarget + HijinkPlanningResolver + HijinkCommon + 6 per-hijink handlers + CrimeAndPunishmentResolver + NpcSyndicateMonthlyResolver + SyndicateBlock UI). Conventions for the syndicate subsystem at `engine/subsystems/syndicate/` + the per-hijink handler family under `engine/subsystems/activities/handlers/syndicate/`.

- **Defensive `_str_or_empty(v: Variant) -> String` coercion at SQLite-read boundaries.** `String(null)` errors in Godot 4 GDScript. SQLite NULL columns surface as `null` Variant values in the dict returned by godot-sqlite, and `Dictionary.get(key, default)` returns `null` (not the default) when the key IS present but its value is null. So `String(row.get("nullable_col", ""))` errors at runtime against rows where the column is NULL. The fix: a small static helper `_str_or_empty(v: Variant) -> String: return "" if v == null else str(v)` on every resolver/handler that reads nullable TEXT columns. Pattern: any repository / resolver / handler that reads nullable TEXT columns from a SQL row MUST coerce via this helper, not via `String(row.get(col, ""))`. The helper is one-liner-cheap; copy it locally per file rather than introducing a shared util module (avoids cross-file coupling for a 3-line helper). The error this prevents is hard to reproduce in unit tests that pre-populate all columns; it surfaces in end-to-end tests where nullable columns are intentionally left unset.

- **`Callable`-based pipeline sharing across N similar handlers.** Phase 10B.3 has 6 per-hijink handlers (assassinating / carousing / smuggling / spying / stealing / treasure_hunting) that share 95% of their resolution pipeline (eligibility check, throw target lookup, dice roll, catch-on-fail logic, lay-low scheduling, signal emission, caught-perpetrators row insertion). The shared pipeline lives in `HijinkCommon.resolve(hijink_id, params, yield_callable, rng, current_day, strict_catch)`. Each per-kind handler passes a `Callable(HandlerClass, "_compute_yield")` with signature `(perpetrator_level, rng, params, character_id) -> Dictionary{cp_yield, detail}`. The per-handler file is then ~30-50 lines: an `on_complete` shell + the per-kind yield math. Pattern: when N similar handlers share most of their pipeline with one small per-kind hook (a yield computation, a target picker, a side effect), pass that hook as a `Callable` to a shared resolver — NOT inheritance / NOT subclassing / NOT a switch statement in the shared resolver. The Callable approach keeps the per-handler file focused on its unique math; it makes the shared resolver pivot on data (the callable) not on control flow (an if-chain). Tests target the shared `HijinkCommon.resolve` once with a forced-success path; per-kind yield math can be unit-tested by calling the `_compute_yield` static directly.

- **`HijinkThrowTarget.classify_outcome(raw_d20, penalty, target, strict_catch) -> Dictionary` pure-function classifier.** ACKS proficiency throws have a uniform shape (roll d20, want >= target, with optional fail-by-N catch semantics). The classifier returns `{success, caught, margin_of_failure, effective_roll}`. Pattern: when a system has a uniform dice-result classification (success / fail / catastrophic-fail bands), extract it as a pure function that takes the raw roll + modifiers + thresholds and returns a result dict. Test the classifier exhaustively (every boundary band, every modifier sign, the strict / non-strict variants). Handlers consume the dict via key access.

- **`Timekeeping.get_total_days()` is the calendar-day API, not `current_calendar_day()`.** First-draft handlers in Phase 10B.3 called `Timekeeping.current_calendar_day()` (non-existent); fixed across all six handlers. The MarketPriceResolver pattern (`_read_current_calendar_day` private helper) calls `Timekeeping.get_total_days()` internally. When a handler / resolver needs the current calendar day, call `Timekeeping.get_total_days()` directly OR accept it as a parameter (`current_day: int` — the dependency-injection-friendly form).

- **Schema column is `character_class`, NOT `class_id`.** The `characters` table column for the character's class is `character_class`. `data/classes/*.json` files use `class_id` as the JSON-level identifier and registry key, but the DB column on `characters` is `character_class`. Phase 10B.3's first-draft `HijinkCommon._read_class_id` read the wrong column; fixed. Pattern: when reading the class of a character from SQL, use `character_class`; when reading the class registry, use the file's `class_id` field. They carry the same values but the column / field names differ.

- **Single consolidated test suite over per-handler test files.** Phase 10B.3's handoff suggested 12 separate test files (one per handler + per-resolver + integration). In practice the 6 per-hijink handlers share so much pipeline structure via `HijinkCommon.resolve` that a single `tests/test_phase_10b3.gd` (24 tests) covering: schema reachability + repository round-trips + classifier bands + planning brackets + smuggling happy + smuggling caught + C&P verdict + NPC monthly + end-to-end — exercises every code path that 12 separate files would. Pattern: when N similar handlers share a single pipeline, a single test suite covering one happy path + one failure path + the pipeline math is sufficient. Split per-handler ONLY if a specific handler develops kind-specific edge cases that need targeted coverage. Avoid the test-file proliferation that would make refactoring the shared pipeline harder.

- **`GameState.dice_overrides[<roll_type>] = N` for deterministic handler tests.** Phase 10B.3's smuggling test forces success and catch paths via `GameState.dice_overrides["hijink_throw"] = 20` (force success) / `= 1` (force natural-1 catch). The roll_type string must match the string passed to `DiceSystem.roll_digital(..., "hijink_throw")` at the production call site. Pattern: when a handler invokes a dice roll that a test needs to control, pass a unique `roll_type` string at the production call site and override it in tests via `GameState.dice_overrides`. The override is consumed exactly once per call (per `DiceSystem._consume_override`), so tests don't need to clear it between paths within a single test if they sequence the calls.

- **Permanent-flag effects (Branded / Maimed / Proscribed) wire to `CharacterLegalStatusRepository`; RAW physical effects logged-only in v1.** Phase 10 Q6 [RESOLVED 2026-05-10] established that brandings, maimings, and proscriptions affect the trial-modifier feedback loop (via `prior_crimes_modifier_cache`) and should be wired through. RAW's full retribution table includes physical effects like "loss of teeth, -2 reaction rolls," "hand amputated (cannot dual wield or use two-handed weapons)," "tortured (save vs Death or permanent wound)," etc. These are surfaced in `caught_perpetrators.punishment_kind` as descriptive labels but NOT applied to character HP / encumbrance / weapon-restrictions in v1. Each such site carries a `[NEEDS-PERMANENT-WOUND-COMBAT-PASS]` flag. Pattern: when a RAW table has effects in two layers (game-state-mutating + presentation-only), wire the state-mutating ones in v1 and tag the presentation-only ones with a single named flag so a future pass can grep and address them in one sweep.

- **Activity catalog files are JSON-driven; activity-level eligibility check is a single string-set lookup.** `data/activities/syndicate_category.json` declares 8 syndicate activities with `prerequisites: [...]` string arrays. The activity executor reads them and gates the launch surface. Each prerequisite name (`is_syndicate_boss`, `has_appropriate_thief_skill`, `not_laying_low_at_base`, `caught_in_prior_hijink_at_this_base`, etc.) is a discriminator the executor knows how to evaluate. Pattern: when introducing a new activity-launcher category, declare every per-activity precondition in the catalog file rather than wiring per-activity launch-time checks across the handler / UI / executor. The executor's precondition-evaluation dispatcher gets ONE new arm per new precondition kind; the handler stays focused on the on_complete pipeline.

## 56. Tier 3 UI display sweep — cp/gp boundary conventions (2026-05-19)

Established during the Tier 3 UI display sweep that closed the multi-session Currency-precision refactor (Migrations 110-117).

- **Local-variable suffix discipline: `_cp` for cp, `_gp` for gp, no bare names.** Every local that holds a monetary value MUST carry an explicit unit suffix. The Tier 3 sweep traced 3 latent bugs (`stronghold_value` cp-shown-as-gp; `monthly_wages_gp` actually summing cp; `owed_gp` actually carrying cp owed) all to bare-named locals whose semantics drifted from their initialization site to their display site. **Pattern:** when reading a column ending `_cp`, the local MUST be named `_cp`; when reading from a function returning gp (e.g., `compute_tribute_base_gp`), the local MUST be named `_gp`. Half-named locals (`stronghold_value`, `monthly_wage`) lose the unit when they cross a function boundary and produce silent display bugs. The cost is one suffix per variable; the benefit is grep-able and reader-checkable type discipline.

- **`Currency.format_cost(cp_value)` at the display site, NOT at the computation site.** Internal math stays in its native unit (gp for `TributeCalculator`-style calculators; cp for column-backed values). The boundary conversion (`× 100` to go gp→cp, `/ 100` is NEVER needed because we convert at the display site instead of pre-formatting) happens at the EXACT moment of `Label.text = ...` or `OptionButton.add_item(...)`. **Pattern:** if the value's path is `column.cp_value → variable_cp → Label.text`, only `Label.text = Currency.format_cost(variable_cp)` should reference `format_cost`. Do not pre-format earlier in the call chain — that loses the int / arithmetic-friendly value and complicates downstream consumers.

- **Latent stale-column reads after a rename are silent failures that grep can find.** Migration 116 renamed `strongholds.gp_value → cp_value`. Three production-code sites (two in `stronghold_sub_tab.gd`, one in `hex_map_landmark_icons.gd`'s SELECT) continued reading `gp_value` for the rest of the project's lifetime — godot-sqlite returns 0 / null for unknown column reads without raising, so the UI showed `"... · 0 gp"` and the landmark icons returned []. **Pattern:** every column rename migration MUST be paired with a project-wide grep for the OLD column name across `engine/`, `scenes/`, `tests/`, `data/`, `docs/`. The grep should fire BEFORE the migration lands so the rename is atomic with its consumers. Migration 116 didn't do that pass for `gp_value`; the Tier 3 sweep eventually caught the residue. Future column renames should include a `git grep <old_col_name>` snapshot in the migration's commit message as a sanity check.

- **Return-dict key shape is part of the public contract.** `HenchmanLifecycleManager.pay_back_wages` returns `{ok, paid_cp, message}`. Its caller `_do_pay_back_wages` was reading `result.get("paid_gp", 0)` — the key never existed; the call silently returned 0 every time. **Pattern:** when consuming a function's return dict, grep the function definition for the literal key (`paid_cp` vs `paid_gp`) before writing the consumer. Especially important across cp/gp boundary functions — the unit suffix in the return key is THE contract; mismatched suffix is an instant bug.

- **JSON column names are case-sensitive AND unit-suffixed contracts.** `data/commerce/common_merchandise.json` rows carry `base_price_cp`. `mercantile_panel.gd` was reading `entry.get("base_price_gp", 0)` — a key that doesn't exist in the JSON. Same pattern as the SQLite stale-column case: silent 0 return. **Pattern:** when consuming a JSON data file, mirror the SQLite-column pattern — verify the key against the JSON file directly, NOT against a memory of "what the field was called last quarter."

- **Removal of a legacy shim is a TWO-FILE diff: producer + tests.** Removing `FavorsDutiesResolver`'s `gp_value` legacy key meant updating `tests/test_favors_duties_resolver.gd` in tandem — the 2 test assertions reading `result["gp_value"]` had to migrate to `result["cp_value"]` (with × 100 scaling). **Pattern:** when removing a deprecated dict key from a public return contract, the producer + tests + any UI consumers all change in the SAME diff. Half-removed shims are worse than retained ones because consumers can break silently between sessions.

- **Test fixtures should use realistic post-fix values, NOT the buggy values that produced the wrong display.** `tests/test_henchmen_tab.gd` asserted `"100 gp"` against wage_cp_per_month rows of `{25, 25, 50}` — values that summed to 100 cp = 1 gp. The test was effectively testing the BUG (cp displayed as gp). The fix updated the fixture to `{2500, 2500, 5000}` = 10000 cp = 100 gp displayed as `"100gp"` via `Currency.format_cost`. **Pattern:** when a test asserts against a display string that was produced by a now-fixed bug, the fixture changes too — make the test inputs realistic for the corrected semantics, then assert against the corrected output. Tests that codify buggy display are landmines for future refactors.

## 55. Phase 10B.3 UI polish wave (2026-05-19)

Established during the Phase 10B.3 UI polish wave (8 thin activity handlers + SyndicateLauncher + SyndicateBlock row-button wiring).

- **`PartyWallet.pay_from_character` returns `{ok, message, total_paid_cp, per_character_deductions}` — NOT `{success, ...}`.** First-draft callers that did `pay.get("success", false)` always read false because the canonical key is `ok`. The activity executor's `launch()` separately uses `success` for its own return contract. **Pattern:** always confirm the function's actual return shape before consuming it; the two surfaces are distinct contracts in this codebase. `pay_from_character` / `deposit_to_party_*` / `deposit_to_party_by_shares` all use `ok`; `ActivityTimeCostExecutor.launch` uses `success`. When in doubt, grep the function definition for `return {`.

- **Pre-rolled randomized durations stuffed into params at launch time.** RAW prescribes "the perpetrator does not know the required time until completion" for several syndicate activities (plan_hijink L1228, perform_hijink L1247, lay_low L1197). The engine model resolves this by having the launcher pre-roll once and embed in params; `ActivityTimeCostExecutor._compute_ticks_required` reads the value back via a kebab-case formula key (`plan_hijink_duration` reads `params.planning_days_required`, etc.). The UI surface can hide the value if RAW fidelity matters; the engine doesn't have to dance around the "unknown until done" semantic — it just doesn't display it. **Pattern:** when RAW says a duration is randomized but the perpetrator doesn't know it, roll once at launch in the launcher (NOT in the executor and NOT in on_complete), embed in params, and let the executor's deterministic duration formula read it back. Keeps the executor pure (no RNG calls in `_compute_ticks_required`) and the launcher gets to side-effect the necessary state (e.g., `HijinkPlanningResolver.start_planning` flips planning_state immediately so other systems see in-flight planning).

- **Row-backed activities surface as per-row action buttons, NOT card-driven pickers.** Most syndicate activities target a specific existing entity (a specific hijink to plan/perform; a specific caught perpetrator to bribe / hire-attorney-for / interplead / await-trial). The natural UX is "click the button on the row." Only Order Hijink — which creates a new entity — uses a card-driven inline picker. **Pattern:** when an activity targets an existing row, surface the action as a per-row button on the entity's list-card; when an activity creates a new entity, surface a card-level picker. This avoids the "click Launch → open a 4-field picker modal where you re-select the same row you were already looking at" anti-pattern.

- **`SyndicateLauncher` prepare-and-launch pattern (per coding_conventions §53 Wave 4 generalization).** UI surfaces should NOT call `executor.launch(character_id, activity_def_id, location_kind, location_ref, params, scheduler, party_id)` directly. They call `<Subsystem>Launcher.launch_<kind>(character_id, ...kind-specific args...)` which:
  1. Validates inputs and returns a canonical error code (`invalid_params`, `ineligible`, `already_resolved`, `no_caught_perpetrator`, etc.) when validation fails — WITHOUT consulting the executor.
  2. Pre-rolls any RAW-randomized duration.
  3. Side-effects state that must exist before the activity ticks (e.g., `HijinkPlanningResolver.start_planning` flipping the hijink row's planning_state to 'planning' so other systems see in-flight state).
  4. Calls `executor.launch(...)` with the assembled params.
  This keeps UI code thin (one function call per button) and keeps validation testable without standing up the full executor + scheduler. Test pattern: pass null executor; validation should error out before the null-deref happens. **Pattern:** every multi-activity subsystem with non-trivial pre-launch state mutations earns a `<Subsystem>Launcher` static-function library. The UI never calls `executor.launch` directly; it always goes through the Launcher.

- **One handler file per activity_def_id, even for thin (< 50 line) handlers.** Each of the 8 syndicate handlers is its own file at `handlers/syndicate/<id>.gd` with its own `class_name`. InterpleadHandler is < 40 lines and could fit alongside BribeMagistrateHandler / HireAttorneyHandler in a single "syndicate_trial_actions.gd," but DON'T. The per-file convention matches §32 and keeps the registration glue uniform (one `registry.register("<id>", <Class>Handler.on_complete)` line per handler). Consolidating thin handlers makes refactoring harder and breaks the symmetry that lets the registration file be auto-readable.

- **Dispatch by `match` over `Dictionary→Callable` for per-kind in-process dispatch.** `PerformHijinkHandler.on_complete` dispatches to one of 6 kind-specific handlers via an inline `match hijink_kind:` block. GDScript can't reference a class_name's static method through a runtime string lookup without ClassDB scaffolding, so the data-driven dispatch table (`KIND_DISPATCH := {"smuggling": "SmugglingHijinkHandler", ...}`) is documentation-only. The 6-arm `match` is shorter than the alternative dispatch table + ClassDB.instantiate dance, and the explicit dispatch arms read cleanly when you're tracing what perform does for a given kind. **Pattern:** when you need to dispatch by string to one of N static methods on N known classes, write a `match` with N one-line arms; do NOT build a Dictionary→Callable lookup unless the set of targets is genuinely dynamic. Document the dispatch with a sibling const Dictionary so search-for-X-handler hits the file.

- **Inline OptionButton + Button pickers beat modal scenes for 1-2-field launchers.** Order Hijink's picker (member dropdown + kind dropdown + Order button) fits in 4 lines of card body. A separate modal scene with a header, footer, validation row, etc. (the Phase 10B.1h pattern for magical_research) would be 200+ lines of boilerplate for the same UX. **Pattern:** when a launcher's required inputs are 1-2 enums, inline pickers in the card body. The Phase 10B.1h conditional-section modal picker pattern earns its complexity at 5+ fields per kind across 3+ kinds. Below that threshold, inline.

## 57. Phase 11A — Append-only logs + monthly-tick transition recorders (2026-05-20)

Established during Phase 11A (Departure Log substrate). Conventions for `domain_departure_log` and any future append-only log tables in the project.

- **Append-only log tables have NO `update_*` or `delete_*` repository methods.** Once a row commits, it is immutable. The `DepartureLogRecorder` static-method library exposes only `record(...)`, `get_entry(id)`, `list_for_domain(domain_id, limit)`, `list_for_campaign(campaign_id, limit)`, and the three `export_as_*` helpers. Adding an UPDATE / DELETE path on `domain_departure_log` is a project-level bug — grep the repo for `UPDATE domain_departure_log` / `DELETE FROM domain_departure_log` and treat any hit as a regression. The migration's table definition intentionally has no `updated_at` column to make accidental updates harder.

- **`domain_id` FK is omitted intentionally on log tables that must survive hard-delete of the referenced row.** Migration 121's `domain_departure_log.domain_id` has no `REFERENCES domains(id)` clause because Phase 11B's `conquered` / `abandoned` lifecycle terminations may release the `domains` row, and the audit history must persist past that. `campaign_id` keeps its FK because campaign deletion is the full-tear-down operation that cascades everything. Repositories enforce non-empty `domain_id` at the write boundary (`DepartureLogRecorder.record` rejects an empty value) — the schema permits it for narrow legacy-data reasons; the recorder does not.

- **Monthly-tick transition recorders live on the log's recorder, not on the handler.** `DepartureLogRecorder.record_monthly_transitions(campaign_id, domain_data, result, calendar_day)` inspects the `result` dict returned by `_resolve_domain_month` and writes the appropriate `classification_*` / `morale_tier_dropped` entries. `DomainHandlers` calls it as a single line after `_emit_signals`. **Pattern:** when a subsystem's monthly tick computes a `result` dict and you want to chronicle transitions detected in it, put the inspection-and-write logic on the log's recorder, not on the handler. This keeps the recorder owning the entire "transition → log entry" semantic (event-type taxonomy, summary copy, payload shape) and makes the helper directly unit-testable without standing up a full handler instance.

- **Event-type taxonomy is the migration's `CHECK` constraint + the recorder's `VALID_EVENT_TYPES` const, kept in lockstep.** Adding a new event type requires updating BOTH. There's a test in `test_departure_log_recorder.gd::test_valid_event_types_matches_check_constraint` that tries to insert each `VALID_EVENT_TYPES` value and fails loudly if the migration's CHECK has fallen behind. **Pattern:** for any table with a CHECK-constrained string column, mirror the values in a `const` on the writer (recorder / repository) and add a smoke test that every const value is acceptable to the constraint. This catches the "added a new event type to the const but forgot the migration" failure mode at test time, not at runtime.

- **`departure_log_entry_recorded(domain_id, entry_id, event_type)` is the live-refresh signal.** UI surfaces that render the log connect to this and re-fetch when the affected domain matches; they do NOT re-fetch on every monthly tick. The signal fires AFTER the SQL commit, so listeners reading the table see the new row. This is the same listener-side refresh pattern §31 establishes for siege state changes.

## 58. Phase 11B — Lifecycle state machine + cross-subsystem signal bridges (2026-05-20)

Established during Phase 11B (Lifecycle handler). Conventions for `domains.lifecycle_state` and any future state-machine column that gates a subsystem's resolver.

- **`domains.lifecycle_state` is the canonical authority on whether a domain is mechanically alive.** Only `LifecycleHandler` writes it (via `CampaignRepository.update_domain_lifecycle_state(domain_id, new_state, calendar_day, grace_until_day)`). Resolvers and UI surfaces read it; nothing else writes it. The monthly tick (`DomainHandlers._handle_monthly_tick`) consults the column up-front and `continue`s past `abandoned` / `lost_to_foreign` rows so the row is preserved for the audit history but no longer runs revenue / expense / morale / growth. **Pattern:** for any subsystem with a terminal state, declare a `state` column with a CHECK enum + a single dedicated update helper on the repository; gate the resolver loop on the column rather than scattering state-checks through individual resolvers.

- **State transitions go through the handler, not the repository.** `CampaignRepository.update_domain_lifecycle_state` is a primitive — it writes columns + emits one signal. `LifecycleHandler.conquer_domain / abandon_domain / mark_stronghold_collapsed / restore_from_ruin` are the public entry points; they own the full transition (state mutation + cascading writes like hex release / vassal cascade / treasury liquidation + departure log + lifecycle-specific signals). UI surfaces and other subsystems call the handler methods, not the repository helper. **Pattern:** repositories own primitives; handlers own transitions. Don't expose a primitive that lets callers half-execute a transition.

- **Cross-subsystem signal bridges live in the consuming subsystem's handler.** Phase 9A's siege resolver emits `siege_concluded(siege_id, outcome)` and Phase 1's stronghold subsystem emits `stronghold_destroyed(stronghold_id, cause)` — both are "something happened in MY subsystem" signals, generic enough that other consumers could attach. The Phase 11B bridge — translating those generic signals into lifecycle calls — lives in `DomainHandlers.register()` (the domain-subsystem instance). The siege/stronghold modules do NOT call `LifecycleHandler.conquer_domain` directly. **Pattern:** when subsystem A emits a generic event and subsystem B needs a specific reaction, the listener + dispatch logic belongs in B's instance handler, not in A. This keeps A oblivious to its consumers and makes B's wiring discoverable by reading B.

- **Idempotent terminal-state guards.** `LifecycleHandler.mark_stronghold_collapsed` early-returns if the domain is ALREADY in `ruined_stronghold` state, so an attacker can't extend the grace window by repeatedly destroying strongholds. `restore_from_ruin` early-returns if the domain isn't in `ruined_stronghold` state. **Pattern:** state-machine transitions should validate the source state and no-op (return success) on duplicate calls, never error.

- **Treasury liquidation on abandon: always zero the row; credit the recipient only if named.** `LifecycleHandler.abandon_domain` always deducts the full `treasury_cp` from the domain. If `liquidate_to_character_id` is non-empty, the cp credits that character via `CampaignRepository.add_coins_cp` (which auto-distributes into denominations). If empty (forfeit cases: stronghold-collapse grace lapse, no-heir succession lapse), the cp evaporates — the domain row still goes to zero, the audit log records `liquidated_cp: 0`. **Pattern:** always zero the source on terminal transitions; credit the destination conditionally. This keeps reads-after-abandonment consistent regardless of whether a recipient existed.

- **Lifecycle test fixtures use raw SQL inserts for domain rows, NOT `CampaignRepository.create_domain`.** The `create_domain` whitelist + auto-fields are convenient for production code but make fixture setup verbose. `test_lifecycle_handler.gd::_create_domain` does an `INSERT OR REPLACE` with just the columns the lifecycle paths read. **Pattern:** test fixtures may bypass repository helpers when they need a precise row shape (especially lifecycle_state, ruined_stronghold_grace_until_day, treasury_cp) that the repository helpers compute or sanitize.

## 59. Phase 11C — Succession state machine + the reverts-to-overlord pattern (2026-05-20)

Established during Phase 11C (Ruler death + succession). Conventions for `RulerDeathHandler` and any future state machine that uses a designation-then-resolution split.

- **Designation and resolution are separate API calls, not one atomic action.** `RulerDeathHandler.designate_heir(...)` writes the heir-id columns; `resolve_succession(...)` consumes them later. The UI exposes a **Designate Heir** modal and a separate **Confirm Succession Now** button — designation is the player's plan, resolution is when it commits. The same separation lets the monthly-tick grace expiry auto-resolve a designated heir without UI input. **Pattern:** when a state machine needs both player input AND a time-based fallback, split the input step (designate / draft / propose) from the resolution step (confirm / commit / apply). The resolver can be called from either path.

- **`tick_succession_grace` is called from the monthly-tick loop ALONGSIDE `tick_lifecycle_state`, not chained.** Both are independent end-of-month grace checks on `domains.lifecycle_state` (ruined-stronghold grace + succession grace respectively). Either may fire per row. Each is responsible for its own state predicates and is a no-op when the row's state isn't applicable. **Pattern:** when multiple state machines share a state-column enum, add per-state-machine tick helpers and call them sequentially from the host loop. Don't try to multiplex through a single ticker — each machine's preconditions and side effects diverge.

- **Vassal-reverts-to-overlord is the v1 default; Dynasties is the long-term replacement.** When a vassal henchman dies with no designated heir AND grace lapses, `RulerDeathHandler.resolve_succession` transfers ownership to the overlord PC under direct rule rather than firing abandonment. This is documented as a v1 default in `gdd-domain-tab.md` §9.4 and `memory/project_dynasties_succession.md`. The succession state machine + `designated_heir_*` columns are deliberately shaped to accept a future Dynasties bloodline-heir resolver: future work populates `designated_heir_character_id` from a new bloodline-relationships table; the resolver itself is unchanged. **Pattern:** when shipping a v1 default that will be replaced, design the surrounding schema + API to be reusable by the eventual replacement. Don't bake the placeholder into the persistence layer; bake it into the resolver only.

- **Non-henchman loyalty modifier (−2 per `acore_axioms` §non_henchman_vassals) is captured in the departure-log payload, not on the heir's row.** The `succession_resolved` entry's `full_details_json` carries `"non_henchman_loyalty_modifier": -2` when the heir's kind is `non_henchman`. The applied loyalty modifier eventually lives on `vassal_assignments.base_loyalty_modifier` (already a column from Phase 7); the resolver records the value in the log and leaves it for the realm code to consume when the heir later swears fealty as a vassal. **Pattern:** when a state transition encodes a future-applicable RAW modifier, record the value in the log entry's structured payload + the appropriate live table. Don't lose the citation — future readers + future code both need it.

- **Multi-domain ruler-death produces N `succession_started` signals + 1 `ruler_died` signal.** A PC ruling three domains who dies generates three independent grace clocks, each with its own designation flow. The consolidated `ruler_died(deceased_character_id, affected_domain_ids: Array)` lets UI surfaces (status header, notification toast) react once; the per-domain `succession_started` lets per-domain sub-tabs refresh independently. **Pattern:** for batch state transitions affecting N rows, emit both the per-row signals AND a single batch signal. Consumers that want per-row reactivity hook the per-row signal; consumers that want a single notification hook the batch signal.

- **State-machine columns CHECK constraints are the source of truth; mirror in handler constants.** `domains.designated_heir_kind` has a CHECK in `('', 'pc', 'henchman', 'non_henchman')`. `RulerDeathHandler` exposes `KIND_PC / KIND_HENCHMAN / KIND_NON_HENCHMAN` + `VALID_HEIR_KINDS`. Same pattern as `DepartureLogRecorder.VALID_EVENT_TYPES` mirror per §57. **Pattern:** any CHECK-constrained string column needs a corresponding handler const list + a smoke test that every const value is acceptable to the CHECK. This is the third repetition of this convention; future state-machine columns should follow it without re-deriving.

## 60. Phase 11D-prereq.0a — Realm substrate: pair-symmetric relations + cached pointers + apex-walk fallback (2026-05-20)

Established during the Realm Substrate foundation (`engine/subsystems/realm_ai/realm_repository.gd`). Conventions for two-axis lookup helpers + symmetric-pair relation tables.

- **Canonical pair ordering for symmetric-relation tables.** `realm_relations` stores diplomatic disposition between two realms. The repository swaps inputs so `realm_a_id < realm_b_id` lexicographically before writing, and queries the same way. A UNIQUE index on `(realm_a_id, realm_b_id)` enforces one row per pair. Callers don't think about order — `get_relation(A, B)` and `get_relation(B, A)` hit the same row. **Pattern:** when modeling a symmetric pair-relation as a table row, normalize the pair ordering in the repository before every read AND write; never store both `(A, B)` and `(B, A)`. Tests verify the canonical-ordering invariant explicitly (`test_relation_canonical_pair_ordering`).

- **Cached pointer + walk-fallback pattern for chain-derived lookups.** `domains.realm_id` caches the realm the domain belongs to. `RealmRepository.get_realm_for_domain(domain_id)` reads the cache first (O(1)); falls back to walking the `liege_domain_id` chain via `RealmGraph.apex_for_domain` when the cache is null. This makes hot-path lookups fast for migrated/current data without sacrificing correctness for new/legacy rows. **Pattern:** when a derived value is cheap to cache but the source of truth lives elsewhere (here: the liege chain), add a nullable cache column + a fallback compute step. Don't make the cache mandatory; null is "compute now." Tests cover both the cache-hit path AND the fallback path (`test_get_realm_for_domain_uses_cached_realm_id` + `test_get_realm_for_domain_walks_apex_when_cache_null`).

- **Coexistence of multiple lookup-strata classes.** `RealmGraph` walks apex domains (army/military layer). `RealmRepository` resolves realm entities (political/diplomatic layer). Both consult `domains.liege_domain_id`; they're parallel APIs for different consumers. **Pattern:** when a single data structure (the liege chain) serves multiple layered subsystems, expose separate static-method classes per layer rather than one mega-API. RealmGraph stays focused on army-collision concerns; RealmRepository stays focused on realm-entity concerns. Cross-layer needs (e.g., RealmGraph's `is_allied` eventually reading `realm_relations`) are explicit bridge updates, not implicit dependencies.

- **`realm_kind = 'tracked' | 'foreign'` distinguishes in-simulation from flavor-backdrop.** Tracked realms have a head character + corresponding apex domain. Foreign realms exist for off-map flavor (an "Empire across the sea" that may invade) and have nullable head + no domain. The `realm_kind` enum lets diplomatic + conquest code distinguish the two without checking for NULL columns. **Pattern:** when a model needs to support both fully-modeled and partial entities, use an explicit kind enum on the row rather than relying on which columns are NULL. The enum makes the intent legible in code reads.

- **`get_relation(realm, realm)` returns `allied` for self-comparisons.** A realm is allied with itself by definition; callers asking "are these two domains in friendly territory?" don't need a separate `is_same_realm` branch. **Pattern:** for symmetric relations, define the self case as the highest-positive disposition. Saves call sites from needing a special-case check.

- **Resolver-style methods that may need follow-up instantiation return empty placeholders that downstream code fills.** `RealmRepository.resolve_conquest_outcome(...)` returns `new_owner_id=""` for the off-map-attacker occupy path because v1 has no in-simulation owner to assign — Phase 11D-prereq.0b's siege bridge will call `instantiate_realm_for_off_map_force` and patch `new_owner_id` before forwarding the outcome to `LifecycleHandler.conquer_domain`. **Pattern:** when a resolver can't fully resolve until a downstream caller acts, return a partial result with explicit-empty fields documenting "downstream fills this" — don't return null or error. Lets the caller compose without changing the resolver's signature when downstream gets smarter.

## 61. Phase 11D-prereq.0b — Three-outcome conquest taxonomy + polymorphic new_owner_id (2026-05-20)

Established during the realm-reification + retroactive 11B fix. Conventions for shipping a state-machine revision that supersedes an earlier 1:1 mapping between caller-side enum and dispatch logic.

- **Caller-side enums collapse from "who" to "what happened" when "who" doesn't matter at the dispatch layer.** 11B's original `conqueror_kind` had three values (`same_campaign_npc` / `foreign_realm` / `player`) but two of them (`foreign_realm` / `player`) dispatched identically. After the 2026-05-20 design review the taxonomy collapsed to a defender-POV three-outcome list (`occupied` / `looted_local_succession` / `salted_to_ruin`); attacker identity moved into the `new_owner_id` parameter (polymorphic — works for tracked NPCs, PCs, or newly-instantiated foreign realm heads). **Pattern:** before adding a third value to an enum, check whether the existing values dispatch identically — if so, the enum is wrong-shaped and should describe the OUTCOME rather than the CAUSE. The cause goes in a separate field that downstream consumers can interpret.

- **Polymorphic id fields preserve future-feature affordances without dedicated code paths.** `LifecycleHandler.conquer_domain(...)`'s `new_owner_id` parameter accepts any `character_id` — PC, henchman, NPC, or freshly-spawned head NPC for a newly-instantiated foreign realm. Multiplayer (v.future) PvP conquest doesn't need a separate `OUTCOME_PLAYER_CONQUEST` — it just sets `new_owner_id` to the hostile PC's character_id. **Pattern:** when a future feature might extend the call site, use a polymorphic id parameter rather than baking the feature's existence into an enum. Saves both the enum churn and the dead-code window before the feature ships.

- **State-machine constant renames need a migration + audit pass — don't leave constants alongside their new replacements.** When 0b renamed `STATE_LOST_TO_FOREIGN` → `STATE_SALTED_TO_RUIN`, the old constant declaration had to be DELETED (not kept alongside as a deprecation alias). Migration 125 renamed the column value via full table rebuild. Audit pass: grep'd every `*.gd` for the old constant name; three live references in non-test code (`ruler_death_handler.gd`, `domain_handlers.gd`, `overview_sub_tab.gd`) failed parse until updated. **Pattern:** constant renames always carry an audit step. The constant disappears AND every reference site updates in the same commit. Don't keep a deprecated alias — Godot's parser fails hard on missing constants, which catches drift at parse time (good); leaving a deprecated alias hides the issue (bad).

- **Outcome dispatch dispatches by string match in `LifecycleHandler.conquer_domain` — not by polymorphic class.** GDScript supports `match` on string values, and the three outcomes have distinct enough side effects that the alternative (one class per outcome) would be overkill. **Pattern:** dispatch by string match when the dispatch table has 2-4 entries with clear side-effect divergence + relatively simple per-arm logic. Class polymorphism earns its complexity at 5+ entries OR when the logic per arm becomes a 50+ line implementation. The current arms are 3-5 lines each.

- **Pre-write validation in the handler, even when the resolver already validated.** `LifecycleHandler.conquer_domain` re-validates the `outcome` string against `VALID_CONQUEST_OUTCOMES` and rejects empty `new_owner_id` for outcomes that require it (occupied / looted_local_succession). The resolver (`RealmRepository.resolve_conquest_outcome`) already validates the intent + returns a structured result, but the handler doesn't trust upstream — direct test calls bypass the resolver. **Pattern:** handlers re-validate inputs they receive even when an upstream caller "should have" validated. Tests + direct programmatic calls don't always come through the canonical pipeline. The cost (a few lines of redundant validation) is much less than the cost of a malformed write succeeding.

- **Test files moved at API revision time; old test file gets the "moved to" comment.** When the 3-outcome taxonomy shipped, the three obsolete conquest tests in `test_lifecycle_handler.gd` were deleted and replaced with the new `test_lifecycle_conquest_outcomes.gd`. The `test_lifecycle_handler.gd` `run_all_tests()` retains an inline comment ("Phase 11D-prereq.0b: conquest tests moved to test_lifecycle_conquest_outcomes.gd") so future readers know where to find the relocated coverage. **Pattern:** when an API revision moves tests between files, leave a one-line breadcrumb in the source file's run_all_tests body. Future debugging sessions can grep for the test name and the breadcrumb tells them which file to look in now.

## 62. Phase 11D.1 — Orthogonal-axes column refactor + deprecated-flag drop (2026-05-21)

Established during the `domain_style` + `alignment` schema migration. Conventions for splitting a single overloaded boolean into two orthogonal columns + retiring the original flag without a back-compat alias.

- **When a single boolean conflates two orthogonal axes, replace it with two explicit columns, not a "fixed" boolean.** `domains.is_chaotic_domain` was a single INTEGER 0/1 flag that callers interpreted variously as "this domain is clanhold-style" OR "this domain has chaotic alignment" depending on the mechanic. After per-callsite audit, the field's truth-set split into two distinct axes: `domain_style ∈ {civilized, clanhold}` (the RAW "exceptions from clanholds" mechanics — garrison +2gp, halved investment, urban 7gp cap, etc.) AND `alignment ∈ {lawful, neutral, chaotic}` (religion-driven morale math). Migration 127 added `domain_style`, dropped `is_chaotic_domain`, and audited every read site to classify it correctly. **Pattern:** when one column's readers disagree about what the column MEANS, audit the readers and split the column rather than redefining it. The audit step is non-optional — it's the only way to surface the conflation.

- **Drop the deprecated flag entirely; don't keep a derived-read-only shim.** Q-DSA-3 resolved 2026-05-20 in favor of dropping `is_chaotic_domain` outright via full `domains` table rebuild rather than keeping a derived `is_chaotic_domain AS (alignment='chaotic' OR domain_style='clanhold')` view-style alias. Rationale: no production data + no back-compat means any value of "smooth migration" is theoretical, and a derived alias would let stale call sites keep reading the wrong field. SQL-execution failures at column-not-found surface every missed callsite at test time. **Pattern:** when a column is being replaced by a better-shaped successor AND there is no live data depending on it, drop the column in the same migration that adds the replacement. Don't leave the deprecated column as a "fall back" — fall-backs are how renames silently rot.

- **Audit every callsite by classifying it, not by mechanical substitution.** When migrating `is_chaotic_domain` reads, each one was inspected and classified as either (a) a style-driven mechanic mapping to `domain_style=='clanhold'` (garrison expenditure offset, settlement growth clanhold-cap bypass, establishment flow's clanhold-method force-lock) or (b) an alignment-driven mechanic mapping to `alignment=='chaotic'` (the "Chaotic" status-header badge, the overview-sub-tab classification line). Mechanical "find-and-replace" would have shipped the wrong semantics for half the sites. **Pattern:** when migrating reads of an overloaded column, do not use replace-all. Classify per-callsite by reading the surrounding mechanic; the classifications go into the build_log as a rename map alongside the migration's SQL.

- **Carry the rename through the calculator result-dictionary keys, not just the input columns.** `GarrisonExpenditureCalculator.compute()` returned a dict with `chaotic_offset_per_family_cp` — the result key was named after the input column, so when the column dropped the key was stale too. Phase 11D.1 renamed the result key to `clanhold_offset_per_family_cp` and updated every consumer (`garrison_sub_tab.gd` × 3 sites + `test_garrison_expenditure_calculator.gd` × 1 site) in the same change. **Pattern:** when renaming a column, grep for the column name in calculator outputs + intermediate variable names + UI badge strings; the rename must propagate through every layer that named itself after the old column.

- **CHECK-constrained string enums beat 0/1 integer flags for "which of these is true" columns.** `is_chaotic_domain INTEGER CHECK IN (0, 1)` carries two bits of information (true/false) but reads at every site need to wrap in `bool(int(...))`. `domain_style TEXT CHECK IN ('civilized', 'clanhold')` reads as `String(...) == "clanhold"` — slightly more characters but no coercion ambiguity, and the enum value documents itself at every read. **Pattern:** new "which kind is this" columns use a TEXT CHECK enum, not an INTEGER 0/1 flag, even when there are only two values. Future-proofs the column against gaining a third value (e.g., adding 'urban_clanhold' would not require migrating the column type).

- **UI badges that conflated two axes split into two badges, not one merged label.** `status_header.gd` previously appended `" · Chaotic"` to the territory line whenever `is_chaotic_domain=1`. Post-11D.1, the same code path appends `" · Chaotic"` ONLY when `alignment='chaotic'`, AND `" · Clanhold"` ONLY when `domain_style='clanhold'`. A domain that's clanhold-style + lawful alignment gets the Clanhold badge but not the Chaotic one — and vice versa. **Pattern:** when splitting a conflated column, audit the UI surfaces that displayed the conflated state too. The split usually reveals that the UI also wanted to show two pieces of information, and the merge was a v0 simplification.

## 63. Phase 11D.2 — Clanhold-style resolver branches (2026-05-22)

Established during the clanhold-mechanics fan-out across `DomainRevenueCalculator`, `DomainGrowthResolver`, `DomainExpenseCalculator`, `SettlementGrowthResolver`, `ClassificationAdvancement`, `ConscriptTroopsHandler`, `LevyMilitiaHandler`, `FavorsDutiesResolver`, and `MonopolyRegistry`. Conventions for fanning out a "this domain runs on different rules" branch across many sibling resolvers.

- **Each resolver reads `domain_style` from the domain dict it already takes.** The orthogonal-axes columns (`domain_style`, `alignment`) live on the `domains` row that every resolver in the monthly-tick pipeline already receives. There's no need for a global "is_clanhold" service or per-resolver dependency injection — every resolver computes `is_clanhold := String(domain.get("domain_style", "civilized")) == "clanhold"` inline. **Pattern:** when adding a new style/alignment branch to N resolvers, each resolver reads its own copy of the column. Don't centralize the read in a helper that callers must remember to consult; the column is already on the domain dict, and re-reading it is cheap + makes each resolver self-contained.

- **Style-driven parameters become named constants per resolver, not a shared table.** `DomainGrowthResolver` declares `INVESTMENT_GP_PER_ROLL_CIVILIZED = 1000` and `INVESTMENT_GP_PER_ROLL_CLANHOLD = 2000`. `SettlementGrowthResolver` declares its own `SETTLEMENT_INVESTMENT_GP_PER_ROLL_CIVILIZED` + `..._CLANHOLD` constants. `DomainExpenseCalculator` declares `CLANHOLD_GARRISON_OFFSET_CP_PER_FAMILY`. Each constant lives where it's used and is cited with the RAW line (`# RAW L83: ...`). **Pattern:** prefer per-resolver named constants over a centralized "ClanholdConfig" table. The constants are short enough to be self-documenting, the RAW citations live next to them, and there's no cross-resolver coupling to maintain.

- **Distance-gate constants pair with their effective-gate selectors.** `ClassificationAdvancement` declares both `ADVANCE_DISTANCE_BORDERLANDS_MILES = 72` (civilized) and `CLANHOLD_ADVANCE_DISTANCE_BORDERLANDS_MILES = 50` (clanhold). The `_can_advance_to_borderlands(..., effective_distance_gate)` helper takes the chosen gate as a parameter, defaulting to the civilized value. The dispatcher picks the gate based on `is_clanhold` and passes it. **Pattern:** when a style branch tightens a numeric gate, declare both gates as named constants, then add an `effective_*` parameter to internal helpers so the helpers don't have to re-read `domain_style`. Keeps the branching at the dispatcher level + makes the helpers reusable for either branch.

- **Same-realm gate is a separate bool parameter, not a derived check.** `ClassificationAdvancement.check_classification_change(..., friendly_settlement_same_realm)` takes the realm-match check as a precomputed bool, not as a `(friendly_settlement_realm_id, defender_realm_id)` pair to derive internally. The caller (`DomainHandlers._friendly_settlement_in_same_realm`) consults `RealmRepository` to compute it. Defaults to `true` so callers that haven't yet wired realm-aware lookups get the legacy behavior. **Pattern:** when a resolver needs realm-relation context but lives below the realm-substrate layer in the dependency graph, accept the realm-aware bool as a parameter rather than reaching up into the realm substrate. The caller is the right place to consult `RealmRepository` because the caller already knows the realm context.

- **Activity handlers reject blocked operations with `blocked_reason` strings, not exceptions.** `ConscriptTroopsHandler.on_complete` returns `{summary: "...", blocked_reason: "clanhold_style_no_conscription"}` when the operation is forbidden by clanhold-style + chieftain vassalage limits. The summary describes the RAW citation + the player's alternative path (e.g., "Use Levy Tribal Warriors instead (Phase 11D.5)"). **Pattern:** activity handlers signal "blocked by rule" via a structured result dict, not by raising — the caller (activity-time-cost-executor + UI) can surface the block to the player and choose what to do. `blocked_reason` is a stable snake_case string suitable for UI conditionals; the human-readable text goes in `summary`.

- **Favors/duties resolver: blocked-by-chieftain check happens AFTER `classify_roll` but BEFORE `_apply_obligation` dispatch.** `FavorsDutiesResolver.roll_monthly` calls `classify_roll` first to get the obligation kind, then checks `_liege_rules_clanhold(liege_id)` against the four blocked kinds (call_to_council / loan / charter_of_monopoly / grant_of_land). On block, the outcome dict gets `applied: false` + `blocked_by_chieftain_vassalage_limits: true` + a descriptive summary, and the resolver returns early without creating an obligation. The d20 roll is preserved in the outcome for ledger/audit. **Pattern:** "rolled but inapplicable" is a distinct concept from "didn't roll" — preserve the roll so the audit log shows what the universe rolled, then attach the block-reason flag so downstream consumers know not to apply effects. Don't re-roll until allowed.

- **Settlement / monopoly subsystems check the SETTLEMENT'S PARENT DOMAIN, not the granting character's domain.** `MonopolyRegistry.grant_monopoly` looks up the settlement's `parent_domain_id` from `settlement_entrances`, then checks that domain's `domain_style`. The granting character may be a different person who happens to control the settlement; the rule operates on the settlement's locality, not the grantor. **Pattern:** rules that operate "within a settlement" key on the settlement's containing domain, not the actor's home domain. The two can differ in vassal/overlord chains, and RAW's intent is usually about the place, not the person.

## 64. Phase 11D.3 — Multi-axis morale-modifier composition + conversion state machine (2026-05-22)

Established during the alignment-vs-religion morale penalty fan-out + the religion-conversion state machine. Conventions for layering multiple base-morale modifiers onto a single resolver + for state machines whose "in-flight" state imposes ongoing side effects.

- **Base-morale modifiers compose at one site, with clear RAW citations per arm.** `DomainMoraleResolver.resolve_base_morale` is the single funnel for every modifier that affects the deterministic base morale floor: personal_authority lookup, insufficient_stronghold penalty, classification penalty, additional_troops bonus, alignment-vs-religion penalty, beastman-rules-kin stack, active-conversion penalty, consecrate_ruler buff. Each arm has a one-line `# RAW §section LNNN-MMM:` comment immediately above it documenting the rule it implements. **Pattern:** when many small modifiers contribute to one composite value, keep them all in one function and annotate each arm with its source-of-truth citation. Resist the urge to break each into its own helper — the composition is the API.

- **State-machine columns whose "in-flight" status imposes side effects: read the active row in the resolver that consumes the side effect.** `DomainMoraleResolver._has_active_religion_conversion(domain_id)` performs a one-row lookup against `domain_religion_conversion WHERE status='active'` and adds −1 to base morale if a row exists. The morale resolver doesn't need to know WHAT the conversion is or HOW it's progressing — just whether it's active. **Pattern:** when a state machine's "active" status imposes a side effect on a sibling resolver, the sibling does a simple existence lookup; it doesn't need the full state-machine API. The state-machine API stays focused on its own concerns (start / tick / abort / complete).

- **Per-character-per-domain entity keys: the helpers take an optional trailing `domain_id`, defaulting to the character's primary domain.** Migration 128 rebuilt `congregants` from per-character to per-character-per-domain. All four helpers (`get_congregants`, `upsert_congregants`, `add_congregant_pending_cp`, `adjust_congregant_count`) gained an optional trailing `domain_id` param. When unspecified, the helper calls `primary_domain_id_for_character(character_id)` to resolve a default. **Pattern:** when extending a per-X entity key to per-X-per-Y, make Y a trailing optional parameter that defaults to the canonical Y for X. Existing callers continue to work; new callers can specify Y explicitly when they need to. The fallback resolution lives in the repository, not in every caller.

- **Implicit-religion design: defer the per-character religion column to a future schema pass; identify the proselytizer via the conversion arc's `driving_character_id`.** ACKS divine casters don't carry an explicit `religion` field in their database row — religion is implicit in class/alignment/(future) deity-of-record. Rather than ship a `characters.religion` column for 11D.3, the conversion resolver identifies "which caster's congregants count toward this arc" via the arc's `driving_character_id`. Multi-caster contributions per gdd-religion-conversion.md §5.7 are explicitly deferred. **Pattern:** when the data model needs a field that has no good current home + the immediate work has a natural single-entity proxy, use the proxy and defer the field. The deferred field gets a build_log note + a comment in the consuming resolver, not a half-built schema column.

- **Integer-only multiplier composition: per-100 magnitudes + post-multiplication divide.** `ReligionConversionResolver` declares `_MORALE_MULTIPLIERS_PCT`, `DRIVER_BONUS_PCT_*`, and `ALTAR_BONUS_*_PCT` as integer percentages. The composite gain is computed as `base × morale_pct × driver_pct × altar_pct` followed by a single `/ 1_000_000` divide. **Pattern:** when composing multiple multiplicative bonuses, keep them as integer percentages (×100) and divide once at the end. Avoids floating-point intermediate values + makes the order independent. The 1,000,000 divisor is the product of three 100s — natural-looking.

- **Conversion arc lifecycle: start writes both arc row AND declared `religion`; complete writes both `effective_religion` AND `alignment`; abort reverts only declared `religion`.** Per gdd-religion-conversion.md §6.1 + §5.6 + §7.2:
  - `start_conversion` inserts the arc row and sets `domains.religion = to_religion`. The "declared" religion flips immediately; the "practiced" religion (`effective_religion`) and alignment stay at the original values until completion.
  - `complete_conversion` updates `effective_religion` + `alignment` atomically (the arc row's status flips at the same time).
  - `abort_conversion` reverts `domains.religion` back to the original `from_religion` (the declaration un-makes) but doesn't touch `effective_religion` or `alignment` (those never changed during the arc).
  **Pattern:** when a state machine flips a "declared" property eagerly but the "effective" property lazily (at completion), the resolver should distinguish the two and only abort the eager flip. The lazy flip never happened, so there's nothing to undo.

- **Conversion resolver returns a structured tick result with `applied / completed / failed_morale / congregant_gain / status_change`.** `tick_conversion(...)` returns a dict whose presence/absence of keys + boolean flags lets the caller distinguish "no active arc" (`applied=false`), "active but stalled" (`congregant_gain=0`, `completed=false`), "progressed" (`congregant_gain>0`), and "completed/failed" (`status_change` populated). **Pattern:** tick-style monthly resolvers return a status dict whose flags are mutually-exclusive enough that the caller can branch with a simple `if result.completed` / `elif result.failed_morale` / `else` ladder. The dict is the audit trail too — passes through to the departure log without translation.

## 65. Phase 11D.4 — Eligibility matrix dispatch + defense-in-depth (2026-05-22)

Established during the establishment-flow eligibility matrix + LifecycleHandler conquest gate. Conventions for systems that gate state transitions on multi-factor (alignment × style × method × target) eligibility matrices.

- **Eligibility checks live in the validator AND the dispatcher — not just the validator.** `EstablishDomainFlow.validate_establishment` enforces the §7 matrix at the caller's request, returning `Array[String]` of `ERR_*` codes for the UI to render. But `LifecycleHandler.conquer_domain` ALSO checks the matrix via `_conquest_eligible(domain, new_owner_id)` before dispatching `OUTCOME_OCCUPIED`. Tests + direct programmatic calls + future siege-bridge variants don't always go through the validator; the dispatcher's re-check prevents a malformed call from installing a forbidden ruler. **Pattern:** when a multi-factor rule gates a state transition, write the check once as a static helper and call it from BOTH the validator AND the dispatcher. The cost (a few SQL reads per dispatch) is dwarfed by the cost of a malformed transition that silently succeeds.

- **Two-flavor target-population detection: caller-supplied flag OR target-id lookup.** `_target_is_beastman_populated(params)` accepts EITHER `target_is_beastman: bool` (for METHOD_CLEAR vs a wilderness lair where there's no existing domain row) OR `target_domain_id: String` (for METHOD_CONQUEST against an existing domain — the flow reads the target's `establishment_method` to detect beastman population). Defaults to false when neither is provided (permissive). **Pattern:** when a rule needs context about a target that may or may not exist as a database row, accept either an explicit bool OR a lookup id and resolve internally. The caller picks the path they know — wilderness encounters know "this lair is beastman" without an id; siege bridges have an id but might not know the population kind without looking it up. The helper handles both.

- **Error codes are caller-friendly strings, not domain-knowledge constants.** `ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL = "beastman_blocked_for_lawful_neutral"`. The string is snake_case + descriptive enough that UI conditionals (`if errors.has(ERR_BEASTMAN_BLOCKED_FOR_LAWFUL_NEUTRAL): _show_modal("Lawful or neutral...")`) read clearly. No need for an int enum — the string IS the identity. **Pattern:** when error codes are consumed across modules, snake_case-string identifiers beat integer enums. The strings serialize into the departure log + audit traces directly without lookup tables.

- **Warning helpers return Array[String] of human-readable strings, NOT structured error dicts.** `VassalAppointmentWarnings.warnings_for_appointment(henchman_id, target_domain_id)` returns an array of complete UI strings ("−2 base morale: chaotic ruler in lawful domain..."). The UI just renders them as bullets — no further processing required. **Pattern:** when a helper exists to produce warnings for a single confirmation modal, return the strings ready-to-render. Don't return a structured Dict that the UI must then localize / format. The localization story (eventually) lives in one upstream pass on the helper itself.

- **Defensive-fail-conservative on unknown character/domain inputs.** `_conquest_eligible(domain, new_owner_id)` returns false (block the conquest) when the new owner's character row doesn't exist. The conservative default prevents a malformed call from sneaking through the gate. **Pattern:** when an eligibility check encounters missing reference data, default to "block the transition." The opposite (default-allow) is a footgun that lets test fixtures + bad call sites silently succeed.

- **Explicit-vs-default param contradiction surfaces as an error, not silent override.** `establish_domain` force-locks `domain_style='clanhold'` for the chaotic methods (CLANHOLD_ANNEX / RECRUIT_CHIEFTAIN). When the caller OMITS `domain_style`, the force-lock happens silently — but when the caller explicitly passes `domain_style='civilized'` with one of these methods, the validator returns `ERR_INVALID_STYLE_FOR_METHOD`. **Pattern:** distinguish "caller didn't specify" (default applies) from "caller specified a contradiction" (error). The first is permissive; the second is a sign of caller-side confusion that should surface. `params.has("domain_style")` vs `params.get("domain_style", "civilized")` is the discriminator.

## 66. Phase 11D.5 — Derived-quantity column for stateful pool tracking (2026-05-22)

Established during the tribal-warrior subsystem implementation. Conventions for tracking a quantity that's *conceptually derivable* but where the derivation has history-dependent behavior (casualties leave gaps that population growth doesn't auto-fill).

- **Pure-derivation collapses when history matters; store the state explicitly.** The tribal-warrior pool LOOKS derivable: `pool = peasant_families - levied`. But casualties leave a permanent gap — a warrior who dies cannot be replaced from their own family; only NEW families can fill the gap. With pure derivation, after 100 casualties + population growth of 50 the pool would re-fill to (peasant_families - levied) ignoring the gap. The history is lost. The solution: store `domains.available_tribal_warriors` as an explicit column maintained by levy / stand-down / casualty / population-growth paths. The slack `peasant_families - available - levied` reads the dead-not-yet-replaced count for free. **Pattern:** if a quantity LOOKS derivable but the derivation has memory (past events shape current state), promote it to a stored column. The "is it derivable?" check is "could I rebuild this from scratch given only the current state of the other columns?" — if no, store it.

- **Repository derivation helper returns a structured pool dictionary, not a single number.** `TribalWarriorRegistry.pool_for_domain(domain_id)` returns `{peasant_families, available, levied, slack, pool_invariant_ok, is_clanhold}`. Callers (UI, handlers, tests) read whichever field they need; nobody has to re-derive. **Pattern:** when a single concept needs multiple related numbers (count + slack + invariant check + branch flag), return a Dictionary with all of them. Avoids the temptation to add per-field helpers that each re-query the database.

- **Style-gated read with universal helper signature.** `pool_for_domain` returns zero-valued pool for civilized domains (the dormant pool is a clanhold-only concept). UI callers don't need to branch on style before calling — they just render zeros, which the Tribal Warriors UI section already hides for non-clanhold domains. **Pattern:** when a helper conceptually applies to a subset of entities, return a sentinel-valued response for the non-matching subset instead of erroring. The `is_clanhold` flag in the result dict lets callers branch on display logic if needed.

- **Migration backfill pre-populates the derived state.** Migration 129 `UPDATE domains SET available_tribal_warriors = peasant_families WHERE domain_style = 'clanhold'` seeds the pool at its canonical initial state for every pre-existing clanhold row. New clanholds created post-migration default to 0 (since their `peasant_families` defaults to 0 at establishment time and grows from there). **Pattern:** when adding a stored column whose value derives from other columns at "natural" initial state, backfill via UPDATE in the same migration. New rows get the DEFAULT 0, which matches their initial state too. The maintenance code paths handle the divergence over time.

- **Cross-resolver `BEASTMAN_RACES` constant mirrored, not shared.** Both `DomainMoraleResolver.BEASTMAN_RACES` and `TribalWarriorRegistry.BEASTMAN_RACES` declare the same 8-race list (hobgoblin / orc / gnoll / goblin / bugbear / kobold / ogre / troll). A docstring on each says "mirrors the other." When the list changes (e.g., adding 'giant'), both must be updated. **Pattern:** small enum-style constants used in 2-3 resolvers can be mirrored rather than centralized — the cost of a shared `ACKSConstants` module exceeds the cost of mirroring N≤3 lists. For larger or more-frequently-used enums, centralize. (Reassess if a 4th consumer arrives.)

- **Defense-in-depth at the handler boundary AND the registry boundary.** `LevyTribalWarriorsHandler.on_complete` calls `TribalWarriorRegistry.can_levy(character_id, domain_id)` for ownership + style gating. The registry returns `{ok, reason}` and the handler converts into a `blocked_reason` result-dict field. The handler ALSO caps the count at `pool.available` even though `can_levy` already passed — defense against race conditions or test-driven direct calls that bypass `can_levy`. **Pattern:** activity handlers consume registry validators AND maintain their own min/max clamps. The registry says "you may"; the handler says "and here's what's physically possible."

## 67. Phase 11E — Scenario-harness integration test pattern (2026-05-22)

Established during the Phase 11E scenario harness. Conventions for multi-month integration tests that compose resolver calls without depending on the SessionRunner state machine.

- **Scenarios are white-box: they call resolvers directly in the same order as the production monthly tick.** `ScenarioRunnerBase.tick_monthly(N)` iterates over seeded domains and invokes `DomainRevenueCalculator → GarrisonExpenditureCalculator → DomainExpenseCalculator → DomainMoraleResolver → DomainGrowthResolver → ClassificationAdvancement` in the same sequence as `DomainHandlers._handle_monthly_tick`. **Pattern:** integration tests for a multi-resolver pipeline don't need to wire signals or session-state plumbing if the production code is already a static-resolver composition. A white-box ticker that mirrors the production order gives 95% of the integration coverage with 5% of the setup cost; the SessionRunner-driven path is exercised separately by Phase E2E tests when those land.

- **Determinism via injected roller.** `ScenarioRunnerBase._deterministic_roller()` returns `count × 5` for every call. Scenarios that need specific dice outcomes pass a custom lambda. **Pattern:** when a resolver takes a `dice_roller: Callable`, scenario tests inject deterministic rollers so the asserted outcomes don't depend on RNG. Use `count × N` (where N is the bias choice — 5 = mid-range; 8 = high-bias; 2 = low-bias) for "I just want predictable positive results" cases.

- **Per-scenario campaign IDs to avoid cross-test pollution.** Each scenario file uses `seed_campaign("scenario_<short_name>_camp")` with a distinct id, and cleanup runs before AND between sub-tests within the scenario. **Pattern:** integration tests that mutate global tables (campaigns, characters, domains) must namespace their test rows + clean up religiously. Cross-suite pollution is the dominant failure mode for shared-DB integration tests; per-scenario id prefixes are the simplest mitigation.

- **Scenario base provides world-seeding helpers, not setup conventions.** `seed_campaign / seed_character / seed_domain / seed_stronghold / seed_hexes` are factory-style helpers with sensible defaults + override-dict params. Scenarios call them with explicit overrides for the dimensions they care about. **Pattern:** integration test scaffolding exposes factories, not fixtures. Each scenario states what it CHANGES from defaults; readers see the variation clearly.

- **Assertions can use either base helpers or direct resolver outputs.** `assert_domain_state(domain_id, expected_dict)` queries the row + compares fields. Resolver-return-dict assertions inline the keys the scenario cares about. **Pattern:** integration assertions should be readable. The base helper is for "did the row settle to this state?" The inline-resolver-return assertions are for "did this monthly tick produce this composition?" Both are first-class.

- **Result dicts from resolvers are inspected by KEY, not by index or shape.** Per the existing handlers' convention, resolvers return Dictionaries with named keys (`{resolved, new_owner_id, reverted_to_overlord, abandoned}` etc.). Scenario assertions read those keys explicitly: `check(bool(resolution.get("reverted_to_overlord", false)), ...)`. **Pattern:** when writing assertions against a resolver result-dict, read the GDD or resolver docstring to confirm the actual key names. Don't guess (`outcome="transferred"`) — read (`reverted_to_overlord=true`). This was a real bug in the Phase 11E succession scenario first pass.

## 68. Phase 11F — Class-tailored UI guidance + procedural empty-state pages (2026-05-22)

Established during the Phase 11F empty-state page closeout. Conventions for UI surfaces that vary content significantly based on the active entity's class.

- **Class-keyed guidance lives in a static class with a single `guidance_for(character_id)` entry point.** `ClassEmptyStateGuidance.guidance_for(character_id)` returns a fully-built `Dictionary` with all the strings + paths the UI needs. The UI page (`empty_state_page.gd`) does ZERO class-branching itself — it just renders whatever the guidance dict tells it to. **Pattern:** when a UI surface varies significantly by class / category / state, push all the variation into a static-class data builder and keep the UI as a dumb renderer of the result. The data builder is testable in isolation; the UI tests can use stub guidance dicts.

- **Class buckets, not per-class methods.** `_fighter_guidance(pre_9, class_id, character)` covers the entire fighter-progression bucket (fighter, paladin, anti-paladin, vaultguard, spellsword, bladedancer, barbarian, ruinguard, dwarven_fury, darkblood_ruinguard) and varies the `class_note` field per the specific class within the bucket. **Pattern:** when the variation has structure (10 classes share 95% of the guidance), use bucket-level helpers with class-specific elaborations rather than 10 separate methods. The buckets become the public structure of the guidance.

- **Procedural UI page construction per project convention §31.** `empty_state_page.gd` extends `VBoxContainer` and builds its UI in `_ready` from a sequence of `Label.new()` + `VBoxContainer.new()` + `add_child()` calls. No `.tscn` file. Layout constants (`_CARD_PADDING`, `_CARD_SEPARATION`) at the top of the script. **Pattern:** when a leaf UI component has no designer-editable state, build it procedurally. The script is the spec. `render_for(character_id)` is the public-facing rebuild trigger; everything else is internal.

- **Per-class restrictions surface as available + disabled_reason fields on each path.** The Explorer's "land grant" and "purchase" paths return `{available: false, disabled_reason: "Explorer stronghold restricted to..."}`. The UI greys them out and shows the reason. **Pattern:** when a class-keyed structure has both "applicable" and "blocked" entries, model them all as records with an `available` flag rather than filtering the blocked ones out. The UI surfaces them dimmed-with-explanation — players see what they CAN'T do (and why) instead of wondering if a path silently doesn't exist for them.

- **Pre-9 banner threads through as a single `pre_9: bool` field + a `subline: String` for the banner text.** `_pre_9_subline(pre_9)` returns the canonical banner text when `pre_9=true`, empty otherwise. The UI checks `subline.is_empty()` to decide visibility. **Pattern:** boolean state that controls a UI element's visibility AND another field's content should ship both as named fields in the result dict, not as a computed-once-in-the-UI conditional. Keeps the data builder's intent visible at the call site of the renderer.

## 69. Test stability — stale assertions vs genuine pollution (2026-05-22)

Established during the post-Phase-11 cleanup pass. Conventions for distinguishing test failures by category and choosing the right fix.

- **Hardcoded exact-count assertions go stale and look like flakes.** Tests asserting `count == 176` against a JSON-loaded catalog fail the day a new entry is added. The failures look pollution-flake-shaped (some runs pass, some fail) because test ordering changes the cache-hit state of preceding tests, but the root cause is the assertion is wrong. **Pattern:** for data-driven counts that grow naturally as content is added, assert `>= minimum` rather than `== exact`. Document the current count in a comment so a future reader knows what the actual size was when the test was written. Example:

  ```gdscript
  # Current count (2026-05-22): 224. Assert ≥ a sensible minimum.
  check(_reg.get_monster_count() >= 50,
      "catalog should have at least 50 monsters (current: %d)" % _reg.get_monster_count())
  ```

- **Adjacent string literals don't concatenate in GDScript.** Python and JavaScript do implicit string concat across adjacent literals; GDScript does NOT. A multi-line string expression like:

  ```gdscript
  var text := (
      "[b]%s[/b]\n\n"
      "Cannot be undone.\n"
      "%d gp lost.\n"
  ) % [name, amount]
  ```

  parses as "expected closing ')' after grouping expression" — the parser hits the second `"` and doesn't know what to do. **Pattern:** explicit `+` between adjacent strings:

  ```gdscript
  var text := (
      "[b]%s[/b]\n\n"
      + "Cannot be undone.\n"
      + "%d gp lost.\n"
  ) % [name, amount]
  ```

  This pattern caused a multi-session parse cascade on `status_header.gd` and `overview_sub_tab.gd` preload paths (errors looked like "Cannot infer the type of StatusHeaderScript constant" — the cascading symptom hid the actual line-number error in the preloaded script). When you see a "Cannot infer the type of ... constant" preload error, run `--check-only --script <path>` on the preloaded script to get the real line number.

- **Format-drift assertions (e.g., location_key gaining a Z coord) also look like flakes.** When a key/format string changes shape (e.g., `"dungeon:test_dungeon:cell:2,3"` → `"dungeon:test_dungeon:cell:2,3,0"`), tests asserting the OLD shape fail consistently. **Pattern:** asserts against format strings should ideally use a structured parser/check rather than full-string equality. When that's overkill, document the format-version assumption in a comment so future drift is detectable:

  ```gdscript
  # location_key format gained a z coord (defaults 0) post-Phase 9 voxel work.
  check(cache.get("location_key", "") == "dungeon:test_dungeon:cell:2,3,0", ...)
  ```

- **Genuine signal/state pollution requires test-infrastructure work, not assertion fixes.** Failures that REALLY do pass-in-isolation but fail-in-sequence are caused by:
  - Signal connections from prior tests persisting (use `EventBus.disconnect_all(...)` in teardown).
  - Global state (GameState fields, NotebookState, autoload caches) not reset between tests.
  - Static-class state accumulators (rare in this project since most static classes are stateless).

  **Pattern:** when an assertion fails INCONSISTENTLY across runs, that's a real pollution flake. Investigate by isolating the suite (`--script test_X.gd`) — if it passes alone, it's pollution. The fix lives in the affected test's `_setup`/`_cleanup` or in a session-wide teardown registered in `test_runner.gd`. This is genuine test-infrastructure work — not a 5-minute assertion edit.

- **Cross-suite RNG-seed coupling via generated IDs is a third flake class (added 2026-05-28).** `CampaignRepository.generate_id()` draws from a module-level `_id_rng` that is `randomize()`d once at class-load, so the ID stream is non-deterministic per process. Some suites seed their own RNG from generated IDs — e.g. `ShippingContractOfferRoller` seeds offers off `party_id`/`settlement_id` — making them BOTH non-deterministic per run AND sensitive to how many IDs earlier suites consumed. **Symptom:** adding a DB-mutating test to an early suite flips an *unrelated* later suite's pass/fail, because the added `add_inventory_item`/`add_*_item` calls shift the global ID stream. **Pattern:** put DB-mutating tests in late-running suites (registered near the end of `test_runner.gd`'s run array) so they can't perturb earlier RNG-seeded suites; and when a downstream suite asserts "a suitable random result always appears," make it guarantee/retry rather than trust a single roll. **Diagnosis:** a `git stash` baseline run — if the failing suite is unrelated to your change and flips when your change is stashed, it's this coupling, not your code. (Found during treasure-item-backing Phase 1: a gem-sell DB test added to `ShopServiceTests` flipped `test_shipping_contract_workflow`; relocating it to the last-running `test_treasure_instantiator.gd` returned the failure count to baseline.)

- **The Phase-11-cleanup pass converted 6+ "flake" failures to passes** by recognizing them as stale-assertion drift rather than pollution: equipment catalog count, specialization registry counts (3 tests), monster registry counts (3 tests), torch/lantern radius (2 sites), location_key z-coord. Final battery improved from 24-25 failed to 20-21 failed — a 16-20% reduction. The remaining ~15 failures (signal/state-pollution variants) are genuine and need test-infrastructure work in a future session.

## 70. Phase 11D.5 polish — composing the tribal-warrior pool maintenance hooks (2026-05-22)

Established during the post-11F polish pass. Conventions for wiring multiple state-tracking hooks (levy / stand-down / casualty / population-growth / spoils / retention-tick) into the monthly-tick + battle-resolution pipelines without coupling them.

- **Pool maintenance is a fan-out, not a service.** `available_tribal_warriors` is mutated by SIX different code paths: levy handler (decrement), stand-down handler (increment), army-casualty resolver (refill survivors), monthly-tick population-growth (increment up to cap), monthly-tick retention (no direct effect — only the timer column), spoils-distribution (no direct effect — only the timer column). Each hook lives in its own module. No central "TribalWarriorPoolManager" service. **Pattern:** when a single column is mutated by N different lifecycle events, let each event's handler own its update. Document the invariant (`available + levied <= peasant_families`) in the registry's pool-derivation helper and have each handler enforce it locally via `clampi(proposed, 0, cap)`.

- **Casualty hooks fire AFTER the unit-status update, not before.** `ArmyCasualtyResolver._resolve_side` updates the troop_unit row first (count + status='departed') and THEN calls `_refill_tribal_warrior_pool_with_survivors(unit, new_count)`. The helper queries the database for current levied count — by the time it runs, the destroyed unit's status='departed' is committed, so the `WHERE status='active'` filter correctly excludes it. **Pattern:** when a hook depends on side-effects already being committed, sequence the row update + the hook in that order. Don't try to compute the post-state before writing; let the database be the source of truth.

- **Sized obligation `is_tribal_warrior_muster` flag threads through to `_apply_obligation`.** The favors-duties resolver's `_size_obligation` returns `{magnitude, gp_value}` for standard obligation types and `{magnitude, gp_value, is_tribal_warrior_muster: true}` for the clanhold-vassal call_to_arms branch. `_apply_obligation` reads the flag and routes the muster materialization through a different path (signal-only for v1; the full auto-levy flow is a future polish). **Pattern:** when a resolver's branches need different downstream handling, add a flag to the sizing-dict + branch in the consumer. Don't fork the sizing function; fork the consumer's dispatch.

- **`apply_spoils_to_tribal_warriors` returns the reset unit_ids, not a void.** The caller can use the result to write departure-log entries, emit signals, or simply discard. By returning the data, the function stays testable + composable. **Pattern:** when a side-effecting helper has a meaningful "what did it do" answer, return it. The caller decides whether to consume. Don't make it `-> void` even if the immediate callers don't need the return.

- **3-month-without-spoils retention is a COUNT-UP with RESET-ON-CREDIT, not a date comparison.** Two alternatives considered:
  1. Per-unit `last_qualifying_spoils_day` column; monthly tick checks "was this within the last 30 days?".
  2. Per-unit `months_without_qualifying_spoils` counter; battle-time `apply_spoils_to_tribal_warriors` resets to 0; monthly tick increments.
  Approach 2 is simpler + has no clock-comparison edge cases (what's a "month" when the calendar drifts? what if the same unit gets 2 qualifying credits in one month?). The downside: counter increments after a mid-month credit, leaving a unit at 1 after a qualifying month — but the SEMANTIC interpretation is "1 month has passed since the last credit", which is correct. **Pattern:** count-up + reset-on-credit beats date-comparison for "N consecutive events without X" semantics. The counter's meaning is "events since last reset", not "events with X = no".

- **Population-growth refill is gated by `domain_style == 'clanhold'`.** Civilized domains' peasant_families also grows, but the pool refill skips them (the pool is conceptually 0 for civilized — see convention §66). The gate prevents the monthly tick from writing `available_tribal_warriors` for non-clanhold domains (where the column should stay at 0 forever). **Pattern:** style-specific maintenance hooks check the style flag explicitly; the registry's "civilized returns zeros" pattern handles the read side, but writes must be explicitly gated.

- **Signal-only stubs unblock the dispatch chain without requiring the full handler.** `tribal_warriors_morale_check_triggered` and `tribal_warriors_called_to_arms` are emitted but no v1 handler consumes them. They're hooks for future polish (the morale-roll mechanic; the auto-levy materialization). The pipeline is fully wired through; downstream behavior is just deferred. **Pattern:** when the upstream is ready but the downstream handler isn't, emit the signal anyway. Tests verify the signal fires; the handler can land later without restructuring the pipeline.

## 71. Per-source-type exemption from RAW universal rules (2026-05-22)

Established during the Q-TW-8 resolution (Option B) for tribal-warrior units. Convention for when a source-type-specific exception to a RAW universal rule is the cleaner design than a separate downstream-cleanup path.

- **Some RAW rules apply universally to all troop types, but the in-fiction semantics are source-type-specific.** Example: the 50%-operational-dissolution rule (units below half-strength count as destroyed) makes sense for MERCENARIES (the survivors disband, go find new contracts) but NOT for TRIBAL WARRIORS (the survivors are still owed to the chieftain; the army owner just marches them home). Applying the rule uniformly created a phantom "orphaned warriors" state that required a refill-hook fix downstream.

- **Source-type exemption beats downstream cleanup.** The earlier Phase 11D.5 v1 fix was: let the 50%-rule fire, then add a `_refill_tribal_warrior_pool_with_survivors` helper to clean up the data inconsistency. Cleaner alternative (shipped as Option B): just EXEMPT tribal-warrior units from the rule in the first place. The downstream cleanup helper becomes unnecessary; the data layer never enters the inconsistent state.

  ```gdscript
  var is_tribal_warrior: bool = String(unit.get("source_type", "")) == "tribal_warrior"
  var operational_dissolution_threshold: bool = new_count < starting_count / 2
  var unit_destroyed: bool = (status == "destroyed") or (new_count <= 0) \
      or (operational_dissolution_threshold and not is_tribal_warrior)
  ```

  **Pattern:** when a RAW rule applies universally but the in-fiction reading produces a source-type-specific carve-out, encode the carve-out at the RULE-CHECK site, not as a downstream cleanup. The data layer stays clean; future readers don't need to trace through a refill helper to understand the model.

- **Removing dead code at the same commit that obsoletes it.** Convention §61's parse-failure-on-rename pattern applies to function deletions too. When Option B obsoleted `_refill_tribal_warrior_pool_with_survivors`, the helper was DELETED (not commented out, not kept as a no-op). A short historical-note comment replaced it documenting why it's gone:

  ```gdscript
  ## Phase 11D.5 polish historical note (Option B / Q-TW-8 resolution 2026-05-22):
  ## The _refill_tribal_warrior_pool_with_survivors helper was REMOVED here.
  ## Under Option B, tribal-warrior units are exempt from the 50%-operational-
  ## dissolution trigger above... [explanation]
  ```

  **Pattern:** when a helper becomes unnecessary, delete it + leave a one-paragraph historical note at its former location. The note documents the design decision for future readers without leaving cobwebbed code around. Don't comment-out the body — the git history has it if anyone needs it.

- **Q-TW-8 closure: "not-applicable" is a valid Q-item resolution.** The Q-TW-8 question (50-hex reachability check for survivor return-to-villages) had been carried in the GDD as an open design choice with v1.1's recommendation. The Option B resolution: the question itself is misframed — there's no scenario the system would apply to. Marked ✅ RESOLVED as not-applicable in §12, with the reasoning recorded.

  **Pattern:** open-question items aren't required to resolve to an implementation. "Not-applicable / question misframed" is a valid outcome. Document the reasoning so future readers can audit the closure (and reopen if the model proves wrong in play).

## 72. Per-race composition table — RAW Tribal Warrior Troop Type import (2026-05-22)

Established during the per-race stat-block import for tribal warriors. Conventions for transcribing wide RAW reference tables into structured constants + scaling them at runtime.

- **RAW reference tables encode as nested-dictionary constants, not arrays.** `_COMPOSITION_PER_120` is keyed `{race: {troop_type: count_per_120}}` — a dict-of-dicts. The alternative (flat array of rows with race/troop_type/count columns) is less Godot-idiomatic + harder to reason about. **Pattern:** when transcribing a wide RAW table where rows = troop_types and columns = races/cultures, transpose to dict-of-dicts keyed by the categorical dimension callers most need to look up by. Here that's race; the levy handler queries "what's the composition for race X?", which is one dict lookup.

- **`per_N` normalization in the constant; scaling logic in the helper.** The table is "per 120 warriors" because that's RAW's natural unit (one company). The constant captures the raw per-120 numbers; `composition_for_race(race, count)` scales each entry by `count/120` with banker's-style integer rounding + residual assignment to the largest-count troop type. **Pattern:** when a reference table is normalized to a fixed unit but callers pass arbitrary counts, scale at the helper not at the constant. The constant stays human-readable matching the source; the helper handles the math.

- **Residual assignment to the largest-count category preserves the source's intent at non-modular sizes.** A 100-warrior orc levy can't perfectly match the per-120 ratios (44+30+20+20+6 = 120; scaled to 100, exact values are non-integer). Floored scaling gives 36+25+16+16+5 = 98; the 2-warrior residual goes to light_infantry (the largest category) → 38+25+16+16+5 = 100. **Pattern:** integer-scaling of a percentage breakdown is lossy; resolve the loss by assigning the residual to the largest category. This preserves the qualitative shape (still mostly light_infantry with some heavy + bowmen + crossbowmen + a few beast_riders) at any total count.

- **Inference helpers with documented priority order beat magic defaults.** `inferred_tribal_race_for_domain(domain_id)` resolves race in three layers: (1) explicit `domain.tribal_race` column (future schema); (2) establishment_method inference (`clanhold_annex`/`recruit_chieftain` → `orc`; else → `jutland`); (3) hard fallback to `jutland`. **Pattern:** when a column doesn't yet exist but downstream code needs a sensible value, write the inference helper with explicit priority order in docstring. Future schema migration adds the column; the priority-1 path activates without further changes.

- **Per-troop-type stat tables stay separate from the race composition.** `_COMPOSITION_PER_120` and `_TROOP_TYPE_STATS` are two distinct dictionaries — one is "which troop types for this race", the other is "what does each troop type cost / weigh in battle". They join at the composition helper. **Pattern:** keep cross-cutting tables separate when they have different growth dimensions. If new troop types are added later, only `_TROOP_TYPE_STATS` grows; if a new race is added, only `_COMPOSITION_PER_120` grows. Joining at the helper composes them.

- **Existing-test refactoring strategy when behavior changes from single-row to multi-row.** Levy now produces N troop_units rows instead of 1. Tests that did `var unit_id = ids[0]` had to update: either loop across all ids (full stand-down test) or pick the largest unit (partial stand-down test). **Pattern:** when a function's output cardinality changes (1 → N), test assertions move from "first/only element" patterns to "iterate-and-sum" or "pick-by-property" patterns. The assertion meaning stays the same; the access pattern updates.


## 73. Canonical-edge storage for between-hex entities (2026-05-22)

Established during migration 130 (rivers as first-class edge entities). Pattern for storing data that lives on the shared edge between two adjacent hexes — i.e., is owned by neither hex individually but by the boundary itself.

- **Pick the lex-lower endpoint as the canonical owner.** `hex_river_edges` stores one row per river edge with `(map_id, hex_q, hex_r, edge)` PK where `(hex_q, hex_r)` is the smaller of the two adjacent hexes under lexicographic ordering on `(q, r)`. `edge` (0..5) names which edge of the owner the entity follows; the non-owner is implied. No mirror row is ever written. **Pattern:** when an entity sits on the boundary between two records, picking ONE as canonical owner via a deterministic rule (lex ordering, smallest-id, etc.) eliminates double-write drift, halves storage, and makes "is X between A and B" a single-row lookup.

- **Canonicalize at the write boundary, not in SQL.** SQLite's PRIMARY KEY guarantees uniqueness of `(map_id, hex_q, hex_r, edge)` but doesn't enforce that `(hex_q, hex_r)` is the lex-lower endpoint — a row inserted with the non-owner side would still be unique. The canonicality rule is enforced by `CampaignRepository.save_hex_river_edge`, which flips any non-canonical input to its mirror before insert. **Pattern:** when a structural invariant can't be expressed as a SQL CHECK, enforce it at the single repository write site (the only path callers should reach the table through). Downstream queries can then assume the invariant. This mirrors the migration-119 `validate_hex_map_parent_linkage` pattern (§ for the cross-scale invariant).

- **The shared-type helper does the geometric work.** `HexRiverEdgeData` carries:
  - `canonicalize_edge(q1, r1, q2, r2) -> Dictionary` — given two coords, returns the canonical owner + edge index. `{"adjacent": false}` for non-adjacent pairs.
  - `is_canonical() -> bool` / `flip_to_canonical()` — instance-side check/repair.
  - `EDGE_NEIGHBOR_OFFSETS` — Vector2i offset per edge (0..5) for flat-top axial coords.
  - `opposite_edge(e)` — `(e + 3) % 6`, used when flipping owner.

  Repository code uses these helpers; subsystems should call them rather than reimplementing the geometry. **Pattern:** shared types encapsulate the geometry/algebra of canonical ownership; repositories handle persistence; subsystems do neither. If a subsystem finds itself computing axial-offset deltas or flipping edge indices, it's doing the shared type's job.

## 74. Retry hygiene + satisfiable acceptance invariants (2026-05-28; placement/fixpoint bullets added 2026-06-10)

Established while fixing the DG-V1 dungeon-generator stocking retry loop (`dungeon_generator_v1.gd`, `stocker.gd`, `acceptance_tests.gd`, `encounter_roller.gd`).

- **Place against the validator's model, not a more permissive one.** The DG-V1 key placer originally computed each door's "outside region" with all OTHER locked doors treated as passable, then a separate solvability validator checked the strict initial-state model — so placement could create circular key dependencies (key A behind door B, key B behind door A) that validation correctly rejected, and the only recovery was burning the retry budget re-rolling placements (~15-20% of multi-floor attempts). The rewrite places keys during ONE fixpoint BFS that uses the validator's exact passability rules: each key lands in a room already proven reachable, so the output is valid by construction and the validator passes on the first attempt. **Pattern:** when a generator has a generate-step and a validate-step, the generate-step must use the SAME reachability/legality model the validator checks (or a strictly stricter one). A looser model turns validation failures into a retry tax at best and an unsatisfiable loop at worst. Bonus: construct-then-validate under one shared model usually collapses N per-item graph sweeps into one fixpoint (here: 1745 ms → 45 ms, ~90% of generation CPU).

- **Every fixpoint/worklist loop carries an explicit pass cap that fails fast.** `validate_solvability`'s fixed-point BFS is provably monotone, but a future edit could break monotonicity and convert a test run into a silent CPU pin (the DG-V1 "hang" investigation cost a full session). The loop now computes `max_passes = total doors + stairs + 2` (every legitimate pass is caused by a delayed unlock event) and on excess logs `push_error` and bails with the partial result. **Pattern:** any `while`-until-stable loop gets a domain-derived iteration bound with `push_error` + graceful bail — a regression then fails a test in milliseconds instead of hanging a runner. Wall-clock budgets checked OUTSIDE the loop do not work (proven during the hang investigation: the stuck loop never yields back to the checkpoint).

- **A retry that re-runs a mutating step must restore the FULL pre-step state, not a subset.** The stocking retry loop snapshots door state before stocking and restores it before each retry. The original snapshot captured only the fields the author happened to remember (`is_secret`, `wired_lever_position`) and missed `type` / `door_material` — so a door forced to LOCKED on a failed attempt bled into the next attempt and corrupted acceptance ("found 2 qualifying doors"). **Pattern:** when you snapshot/restore mutable state for a retry, enumerate EVERY field the inner step can write — grep the step for assignments to the object — and restore all of them; restoring a subset is a latent state-bleed bug. Derived/cell state stamped from those fields (here, `lever_portcullis_*` terrain features) must also be cleared or recomputed on retry.

- **An acceptance/validation gate must assert an invariant the producers can actually guarantee.** DG-V1 §14.1.6 originally hard-required "exactly one secret+locked door per trap room," but the layout generator independently places secret+locked doors (§8.1), so a room can already hold two before the stocker runs — "exactly one" is unsatisfiable and would fail valid, playable dungeons. The gate was set to the satisfiable playability invariant (">= 1") with the stricter ideal downgraded to a soft warning. **Pattern:** before making a count/shape check a HARD gate, ask "can every upstream producer be constrained to satisfy this?" If an independent producer can violate it without harming playability, the hard gate belongs at the playability floor (>= 1, reachable, non-null) and the ideal becomes a soft warning. Verify satisfiability with a multi-seed stress sweep, not just the few fixed test seeds.

- **Changing an RNG-consuming sequence is deterministic but breaking — expect it to surface latent crashes.** Reordering the stocker into two passes shifted which monsters seeds roll, immediately hitting a latent `int(null)` crash in `encounter_roller.gd` (`percent_in_lair` is `null` for some catalog monsters). **Pattern:** any refactor that alters the order/count of `rng` draws changes every downstream roll, so the fixed-seed suite now exercises entirely different generated content. Re-run a multi-seed sweep after such a change, and treat newly-surfaced crashes as pre-existing latent bugs to fix — a function documented to "always return X, never null" must honor that for every data row — not as regressions to paper over.

- **Two-sided lookup helper is mandatory for "is this hex touched?" queries.** Because rows are stored once on the lex-lower side, asking "what rivers touch hex H?" requires querying for rows where H is the owner UNION rows where H is the neighbor of an owner. `CampaignRepository.get_river_edges_for_hex` does this; `hex_has_river` is its fast existence-check variant. **Pattern:** any consumer asking "does X touch this record" must use the two-sided helper, not a direct WHERE clause that only matches the owner side. Putting both branches into the helper means subsystem code reads as "does river touch hex" without leaking the canonicality detail.

- **Flow direction inverts when the row flips.** `flow_clockwise` is interpreted relative to the OWNER's center (per GDD §3.6.3 — the clockwise vertex of edge `e` is the corner shared with edge `(e+1) % 6`). When `flip_to_canonical()` moves ownership to the other endpoint, the same physical flow now appears "counterclockwise" from the new center, so the field is negated automatically. **Pattern:** when a directional field is interpreted in the owner's local frame, the canonicalization step must also flip the field to preserve physical semantics. Document this in the shared type's docstring; callers should never have to reason about it.

- **Lossy migrations are explicit, not silent.** Migration 130 converts old `hex_overlays(overlay_type='river')` rows by extracting the edge list and rebuilding `hex_river_edges` rows, defaulting `flow_clockwise=1` (an arbitrary choice — the old model didn't have flow_vertex direction). The migration header documents the lossy semantics. Hand-authored test JSON is re-converted manually. **Pattern:** when a schema change loses information that wasn't recorded in the old model, set defaults that produce coherent (if not bit-exact) downstream behavior, document the loss prominently, and accept that any pre-existing content needs hand-correction. Don't try to be clever — the missing information truly isn't there.

- **Adjacent-hex consumers read a cached flag, not the table.** `HexTerrainData.has_river_cached: bool` is set by the loader (`CampaignRepository.load_hex_map` and `HexMapData.from_dict`) after fetching river edges; per-hex consumers (foraging, wilderness water refill) call `terrain.has_river()` which just reads the flag. Reaching into the DB on every per-hex check is wasted IO and couples the consumer to repository state. **Pattern:** when a shared-type consumer needs "does this row reference X" but X lives in a separate table, the loader populates a transient flag on the in-memory object. Document the flag as "set by the loader; do not write directly." This keeps consumers DB-agnostic and works for both repository-loaded and JSON-loaded test fixtures.

---

## 75. Character Armor Class is equipment-derived, never hardcoded (2026-05-29)

Established while fixing the bug where a PC/henchman's `armor_class` was never computed from equipment (it defaulted to 0 and was only ever set by the GM override panel, polymorph, or test fixtures). See `CharacterAcCalculator` (`engine/subsystems/characters/character_ac_calculator.gd`).

- **One canonical computation owns the BASE AC; the effective getter owns the layered effects.** `CharacterAcCalculator.compute(character, inventory_rows) -> int` is the single source of equipment-derived AC, and `recompute(...)` writes it to `CharacterData.armor_class`. Per §12 ("Effective getters are mandatory"), the stored `armor_class` is the BASE (equipment + Dexterity); `CharacterData.get_effective_ac()` layers ModifierContainer stacks (spells, conditions, directional Shield, a Ring of Protection, etc.) on top. **Never fold a spell/condition/worn-magic-item AC effect into the stored field — that's the modifier system's job.** This mirrors the creature path (`TrainedCreatureData.get_armor_class` + `Combatant.from_trained_creature`, which adds equipped barding AC as an `"armor_class"` modifier).

- **ACKS composition (RAW, ascending AC, base 0):** body armor `armor_ac_bonus` (Hide 1 … Plate 6, `acore_equipment.xml:143-148`) + shield `armor_ac_bonus` (+1, `:149`) + Dexterity modifier (`CharacterData.ability_modifier` of the EFFECTIVE DEX; `acore_basics_and_characters.xml:242`, creation step 8 `:150`) + equipped armor/shield `magical_bonus` (the +N). Body armor = `item_category == "armor"` in slot `"armor"` (the dedicated paper-doll armor slot, gdd-character-tab.md §3.4 / migration 151 — `"body"` is now creature barding only, and armor coexists with the separate `"torso_clothing"` slot); shield = `item_category == "shield"` in slot `"hands_off"`. Magic-armor WEIGHT reduction is `EncumbranceCalculator`'s job, not this one.

- **Recompute fires only on the real equip/attribute/combat paths — never on synthetic fixtures.** `CampaignRepository.recompute_character_armor_class(character_id)` loads inventory + DEX, computes via the calculator, and persists `characters.armor_class` (it does NOT emit `inventory_updated`, to avoid loops). It is called from the equip-state write chokepoints (`update_inventory_item_equip_state`, `merge_item_on_unequip`, `split_item_for_equip`), `sanitize_character_equipment` (party-load repair for legacy saves), the henchman equipment-kit applier, and after a Dexterity GM override. Creation (`CharacterGenerator.generate_pc/generate_npc`) sets the baseline (DEX mod, empty inventory). Combat `Combatant.wire_equipment` recomputes the in-memory `_character` as a safety net for stale/transient data. **Because the recompute does NOT fire when code sets `armor_class` directly, the existing combat/modifier tests that hardcode AC and test modifier layering stay valid** — only equip/attribute/combat-wiring paths re-derive it. Do not hook the broad `inventory_updated` signal for AC: it fires on coin pickups and would clobber polymorph (which writes the flat field) and GM AC overrides.

- **Dual-shape input.** Like `EncumbranceCalculator` and `TrainedCreatureData`, the calculator accepts both `InventoryItem` objects and raw DB-row / `to_dict()` Dictionaries; it reads `is_equipped` as `int(...) == 1` for dicts. Pass `[]` for "no inventory yet" (creation) → AC = DEX modifier.


## 76. Thief→Syndicate: syndicate classes run syndicates, not domains (2026-06-03)

The three syndicate classes (thief / assassin / elven nightblade, per `ClassBucketResolver.SYNDICATE_CLASS_IDS`) do NOT run domains. Per RAW `ax_thief_skill_update.xml`:50 — "Hideouts are secret strongholds; do not secure domains or attract families." Their late-game vehicle is a **syndicate** operated from a **hideout** planted inside someone else's settlement. For the initial release they may not create domains or domain-securing strongholds at all.

- **A hideout is its OWN entity, NOT a `strongholds` row.** The hideout lives in the `hideouts` table (Migration 143) with `syndicates.hideout_id` as the source-of-truth FK. It never appears in stronghold/domain UI and never counts toward any domain's sufficiency. The old `syndicates.hideout_stronghold_id` FK to `strongholds` is left in place but VESTIGIAL (migrations are non-destructive) — read `hideout_id` first, fall back to `hideout_stronghold_id` only for legacy rows. Rationale: modeling the hideout as a stronghold re-introduced the exact domain-securing coupling the refactor removes; a distinct lightweight entity keeps the two games from bleeding together.

- **Block the domain/stronghold paths with `ClassBucketResolver.is_syndicate_class(class_id)`, never an ad-hoc class check.** Guards live at `EstablishDomainFlow.validate_establishment`/`available_paths` (returns `ERR_SYNDICATE_CLASS_NO_DOMAIN` / `[]`), `CommissionPipeline.start_commission`, and `ClaimingResolver.claim_existing` (reject code `"syndicate_class_cannot_build_stronghold"`). **Trap:** `dwarven_delver` shares thief combat-progression and thief skills but secures a real domain via a vault — it is NOT a syndicate class. Drive the branch off the allowlist, never off combat_progression or "has thief skills" (see also §49).

- **A class-specific late-game vehicle gets its own *Flow + Dialog, mirroring EstablishDomain*.** `FoundSyndicateFlow` (engine, static; `validate_founding` side-effect-free, `found_syndicate` does the writes) parallels `EstablishDomainFlow`; `FoundSyndicateDialog` parallels `EstablishDomainDialog`. The flow charges the hideout's market-class minimum via `PartyWallet.pay_from_character` (check `.ok` — NOT `.success`) as the atomic funds check (no separate balance read), then spawns 2d6 level-1 followers of the boss's class. Host-settlement proximity uses 6-mile-hex adjacency (`HexMapController.hex_distance(...) <= 1`), not real-distance math.

- **Income is net; charge upkeep ONLY for what the net table excludes.** `NpcSyndicateMonthlyResolver`'s L1-8 fast-path income table "already factors in wages, attorneys, bribes, fines, and healing" (RAW `acore-campaign-hijinks.xml`:523). So member WAGE upkeep (`HENCHMAN_MONTHLY_WAGE_GP_BY_LEVEL`) applies ONLY to L9+ members (who earn via individually-rolled hijinks, not the net table). Charging L1-8 wages on top would double-count. General rule: when a RAW table is documented as *net*, never re-apply the costs it already folds in.

- **The monthly tick must process domain-less entities too.** Syndicate bosses own no domain, so the domain-only monthly resolution never reaches them. `domain_handlers._handle_monthly_tick` runs `NpcSyndicateMonthlyResolver.process_campaign_month` AFTER the commerce pass and BEFORE the `domains.is_empty()` early-return, and includes the `syndicate_results` summary in BOTH return dicts. Pattern: a per-entity activity that is NOT gated on domain ownership belongs before the domain early-return, not inside the per-domain loop.

- **Domain tab is dual-mode, keyed on `is_syndicate_class`.** For syndicate-class entities `domain_tab_page` hides the domain sub-tab strip entirely and renders a syndicate surface (a "Found a syndicate…" empty-state, or the `SyndicateBlock` once founded). The `SyndicateBlock` is recreated fresh per render and freed on the next render (NOT pooled like the domain sub-tab pages) because it subscribes to EventBus signals in `_ready` and unsubscribes in `_exit_tree` — pooling-and-re-adding would not re-fire `_ready`, leaving its live-refresh subscriptions dead.


## 77. Venturer→Guildhouse: the Venturer runs a guildhouse + monopoly, not a domain (2026-06-03)

Mirrors §76 for the Venturer (`ClassBucketResolver.VENTURER_CLASS_IDS = ["venturer"]`, the sole "trade"-bucket class). Per RAW `ax_venturer_class.xml`: a Venturer's guildhouse "follows the rules for hideouts" (L9: 2d6 apprentices, ruffian wages, market-class cost, secures no domain); the L12 `monopoly_power` is the income (1gp/urban-family/month from the guildhouse's settlement, without ruling the domain). For the initial release the Venturer may not create domains or domain-securing strongholds (the project disallows non-conforming strongholds; the guildhouse secures nothing).

- **Block with `is_venturer_class(class_id)`** at the same three guard sites as the syndicate block (`establish_domain_flow` → `ERR_VENTURER_CLASS_NO_DOMAIN`; `commission_pipeline` + `claiming_resolver` → `"venturer_class_cannot_build_stronghold"`). The guards OR the two predicates; the founding logic stays class-specific.

- **The guildhouse is its OWN entity** (`guildhouses` table, Migration 144), NOT a `strongholds` row. It REUSES `HideoutCostTable` for cost/size (RAW: it follows hideout rules). `FoundGuildhouseFlow` + `GuildhouseRepository` mirror `FoundSyndicateFlow` + `HideoutRepository`.

- **Apprentices live in the unified `followers` table** (`source_kind='venturer_apprentice'`), NOT a bespoke table and NOT `syndicate_members`. This is the pre-designed home (the enum value pre-existed; §51). They are individual rows (level/status), recruitable as henchmen (`promote_follower_to_henchman` → a `characters` NPC row), and become full NPCs with the future NPC system. Spawn via `CampaignRepository.create_follower` (omit `stronghold_id` → NULL; the apprentice→guildhouse link is implicit via `owner_character_id`). Apprentice hijinks / leveling / auto-promotion are deferred to that NPC system — the data model already supports them. General rule: when a new kind of "almost-henchman" follower appears, add a `source_kind` to `followers`, never a parallel per-class table.

- **Income = L12 monopoly; apprentice wages are charged DIRECTLY (NOT a §76 double-count).** Unlike the syndicate's net L1-8 income table, the guildhouse has no net table, so `VentureMonthlyResolver` pays apprentice ruffian wages outright alongside the monopoly revenue (1gp × `settlement_entrances.urban_families` when `guildhouses.monopoly_seized`). The L12 settlement monopoly is a flag on the guildhouse, DISTINCT from the per-merchandise `monopoly_holdings` / `MonopolyRegistry` (the buy/sell trade advantage) — do not conflate. "One venturer per settlement" is enforced at seize.

- **Monthly tick + dual-mode UI**: `domain_handlers._handle_monthly_tick` runs `VentureMonthlyResolver.process_campaign_month` next to the syndicate one (before the `domains.is_empty()` early-return; `venture_results` in both return dicts). `domain_tab_page` adds a venturer branch keyed on `has_bucket(id, "trade")` that hides the domain sub-tabs and renders the guildhouse surface (`FoundGuildhouseDialog` + `GuildhouseBlock`, recreated-and-freed per render). The deferred full Trade Block (mercantile activity launchers) attaches to `GuildhouseBlock`.

## 78. Class templates: build-time import of the Player's Companion catalog (2026-06-03; Mystic in-scope + poison pricing 2026-06-11)

The 31 per-class template tables in `rules/pc_class_templates.md` are imported to the runtime resource `data/templates/class_templates.json` by `tools/import_class_templates.py` — a §7.4 build-time extractor (rules/* is never read at runtime; the three out-of-scope classes Dwarven Machinist / Gnomish Trickster / Thrassian Gladiator are skipped — the Mystic moved IN-scope 2026-06-11 when `data/classes/mystic.json` landed, bringing the catalog to 28 classes / 224 templates; its exotic weapons resolve via the "type-of" PHRASE_RULES per the source's footnote equivalences: war ring→dart, elephant trunk blade→pole_arm, coiling blade→whip, double-bladed dagger→short_sword, tiger's claws→dagger, tulwar→short_sword, khanda→sword). The importer also prices poison doses from `data/equipment/poisons.json` (cost_cp_per_dose × dose count → entry `metadata.value_gp` + `poison_key`/`doses`, summed by `TemplateWealthSweep.recompute_gp`) — un-priced poison was the common wealth-sweep deficit driver for mystic_13_14 / assassin_13_14 / dwarven_delver_15_16; pricing it put all three within ~8% of band target, keeping `EXPECTED_FLAGGED` empty. `ClassTemplateRepository` (`engine/subsystems/characters/`, a non-autoload `class_name` service mirroring `EquipmentCatalog` / `MagicItemCatalog`) loads it into typed `ClassTemplate` / `TemplateProficiency` / `TemplateEquipmentEntry` resources (`engine/shared_types/`). `generation/gdd-class-templates.md` §6.2 is the schema of record. Patterns established:

- **Reference data goes in `data/templates/`.** New top-level data dir for character-build reference catalogs. The importer's output carries the §7.4.2 `_source` (`rules/pc_class_templates.md`) + `_extracted_by`, but no `_extracted_at` (omitted for byte-identical idempotency: `json.dump(sort_keys=True, indent=2)`, no timestamps). Covered by the mandatory §7.4.4 freshness gate `tests/data_integrity/test_class_templates_data_freshness.gd`, which shells out to the importer's `--check` (same pattern as the dungeon-generator gate).

- **Curated override files are INPUTS, not outputs.** `data/templates/equipment_overrides.json` (phrase→item_key) and `label_overrides.json` (template_id→IP-neutral label) are hand-edited, Jedidiah-reviewed INPUT files the importer READS; it never writes them. This reconciles the GDD's override-table workflow with §7.4.7 ("curated data must not be hand-edited into the overwritten output"): the diffed output is `class_templates.json`; the override files sit upstream of it. The systematic mechanical mappings (flavor stripping, type-of footnote equivalences, clothing/armor tiering, quantity/bundle math) live in the script (curated-in-script, §7.4.7); the external files are reserved for the genuine long tail. First import needed ZERO equipment overrides — the built-in ordered `PHRASE_RULES` resolved all 216 templates.

- **Equipment `base_item_id` is a RUNTIME catalog key, never an XML id.** The GDD §6.5 says "resolve against `pc_equipment_catalog.xml`," but the runtime `EquipmentCatalog` loads `data/equipment/*.json`; the importer builds its lookup from those JSON files so every `base_item_id` resolves at runtime (and in the sanity test). `""` + `resolution_status:"non_catalog"` marks intentional non-catalog items (familiars, totem animals, jewelry-by-value, poisons) — these are NOT catalog misses and are reported separately from `unresolved`. Holy / unholy symbols → `holy_symbol` with `metadata.deity = null` (populated at character creation, gdd §5.2).

- **proficiency_kind is POSITIONAL, not detected from italics.** The markdown extraction lost the source's italic markers, so the importer tags by position: list_order 1 = `class` (the template's signature slot — per gdd §8.2 "the first is the class proficiency"; may carry a catalog-`general` proficiency in the class slot); for arcane (mage / warlock / elven_enchanter / elven_spellsword / lightblessed_wonderworker), witch, and the natural-prof classes (barbarian / bard / elven_courtier / dwarven_craftpriest / shaman) the LAST (3rd) is `arcane_bonus` / `tradition` / `natural`; all others are `general`. These special classes always list exactly 3 proficiencies (verified across all 216); the INT-cull rule (gdd §8.2) and the sanity test both depend on the position-3 invariant. The importer additionally resolves a snake_case `proficiency_key` beyond the gdd §6.2 schema — an engineering extension for downstream proficiency application.

- **Two project class-id rebrands apply at import.** Zaharan Ruinguard → `darkblood_ruinguard`, Nobiran Wonderworker → `lightblessed_wonderworker`, and the "Black Lore of Zahar" proficiency → `black_lore_of_chaos` (the 2026-04-24 Zahar→Chaos rebrand). The importer maps source display names → runtime class_ids and asserts each `data/classes/<id>.json` exists, so a future class rename surfaces as a loud import error.

- **The runtime consumer is `ClassedNpcBuilder` (§10 step 5, added 2026-06-04).** `engine/subsystems/characters/classed_npc_builder.gd` (`class_name`, non-autoload, deps injectable) is the unified entry point for building any classed NPC from a template. `select_template` rolls 3d6 and takes the band-CONTAINING template (`ClassTemplateRepository.get_template_for_class_at_roll`) — NPC selection is Path B only, no choice (gdd §7.2), distinct from the at-or-below PC query. `build_classed_npc` builds the base `CharacterData` via `CharacterGenerator.generate_npc`, then sources proficiencies from the template (instead of `auto_select_proficiencies`) and grants the template's catalog equipment + coin, returning an in-memory bundle; `persist` writes it, mirroring `NpcRulerGenerator` (create_character → stamp_powers → save_character_proficiencies → add_inventory_item per item → add_coins_cp → recompute AC). proficiency_kind "class" → `slot_type:"class"`, all others (general/natural/tradition/arcane_bonus) → "general"; catalog equipment → inventory rows (stowed "pack"); familiars / totems / jewelry-by-value are surfaced in `non_catalog_items` and routed by `persist()` to their own subsystems (see the non-catalog routing bullet below), never as raw equipment rows. a level>1 build applies only the L1 floor and sets `advancement_pending`. Pattern: template-driven entity builders return an in-memory bundle + a separate `persist`, keeping bulk-generation tests DB-free (the 100-henchman coherence test).

- **INT adjustment + PC creation flow (§10 steps 6-7, added 2026-06-04).** `TemplateIntAdjuster` (`engine/subsystems/characters/`, pure static) implements §8: mundane templates gain extra GENERAL proficiencies = `max(0, CharacterData.ability_modifier(INT))`; arcane templates (the 5 in `TemplateIntAdjuster.ARCANE_CLASSES` — mage / warlock / elven_enchanter / elven_spellsword / lightblessed_wonderworker, matching the importer + §8.2, NOT witch / priestess) cull the position-3 `arcane_bonus` proficiency + drop the italicized bonus spell at INT <= 12, or add 1 / 2 general slots + 1 / 2 rolled-spell *counts* at 16-17 / 18. **RAW LOCK-IN:** gdd §8.1's `floor((INT-11)/2)` formula is WRONG (yields 2 at INT 15 and 3 at INT 17); the explicit table in §8.1 — which equals the ACKS INT ability modifier floored at 0 — is authoritative, and `compute_adjustment` uses `CharacterData.ability_modifier`, never the formula. (The GDD §8.1 formula text was corrected to the table on 2026-06-04; `test_template_int_adjuster.gd` pins INT 15→1 / 17→2 against regression.) `PcTemplateCreationFlow` (`engine/subsystems/characters/`) is the §4 choice-point stub: roll 3d6 → STARTING_GP (×10) / TEMPLATE_CAP; Path A keeps the gold; Path B applies a template at-or-below the cap + INT adjustments + the §4.2.1 proficiency editor (class prof locked-but-swappable, natural / tradition locked, arcane cull with a player override, INT-bonus general slots). Path B uses the template's listed wealth as the funds, NOT STARTING_GP — the 3d6 roll is consumed by one path, never both (§4.1). Both the NPC builder and the PC flow share `ClassedNpcBuilder.proficiency_records` / `.equipment_records` (static) + `TemplateProficiency.to_record()`, so PC and NPC template application stay identical (§4.2.1 "the same editor logic is invoked headlessly by the NPC builder"). The actual extra-spell ROLLS are deferred to the spell-repertoire picker (§10 step 11); the pipeline surfaces `extra_spells_to_roll` only and concretely drops the `bonus_spell` at arcane INT <= 12.

- **Review-pass closures (2026-06-04).** The accumulated "flag for Jedidiah" items from steps 1-8 were resolved against RAW: **(a)** `sensing_good` was ADDED to `data/proficiencies/proficiency_catalog.json` — it is a real Zaharan Ruinguard class proficiency (`rules/pc_classes_5.xml:317`), the Chaotic mirror of Sensing Evil (`rules/acore_proficiencies_rules_and_catalog.xml:947`), that the extraction had missed; the importer's `PROF_KNOWN_GAPS` is now empty and the darkblood_ruinguard Avenger template resolves its class proficiency (`test_class_templates.test_sensing_good_resolved` pins it). **(b)** The three "catalog gaps" were RAW-verified ABSENT (`acore_equipment.xml` + `pc_equipment_catalog.xml`) and reclassified, NOT added: ornamental crystal ball → a 20gp `valuable` (a crystal ball is a magic item in ACKS; the template prop is decorative), disguise kit + medicine bag → `flavor_tool` (the Disguise / Healing proficiencies need no kit). The importer's "catalog gaps to flag" list is now empty. **(c)** The 15 wealth-sweep deviations are RAW-FAITHFUL, not fixable — ACKS Core has a single 25gp holy symbol (`acore_equipment.xml:115`), no cheaper "wooden" tier, so low-band clerical templates genuinely run rich; they stay flagged-for-info in `wealth_sweep.md`. **(d)** The gdd §8.1 formula text was corrected (see the INT bullet above). General rule: a "catalog gap" is only real if the item/rule EXISTS in a SACRED `rules/*.xml` and the extraction missed it — verify against the XML before adding to a runtime catalog; if RAW has no such entry, it is flavor / valuable, not a gap to fill.

- **Wealth-target sanity sweep (§10 step 8, added 2026-06-04).** `tools/import_class_templates.py` emits a SECOND checked-in artifact — `data/templates/wealth_sweep.md`, a deterministic, human-reviewable markdown report (for Jedidiah) of each template's resolved gp vs its `3d6 x 10` band target (midpoint x 10), with the > 40% deviations flagged + their top gp drivers. The importer's `--check` now gates BOTH artifacts (class_templates.json + wealth_sweep.md) for byte-identical freshness, and the existing data-integrity test covers it. `TemplateWealthSweep` (`engine/subsystems/characters/`, pure static) is the runtime equivalent: `band_target_gp`, `deviation_fraction` / `is_flagged` (computed from the STORED `resolved_gp_value` with a pure-float `> 0.40` threshold — NO rounding — so the importer, the markdown, and the runtime agree on the flagged set with no Python-banker's-vs-GDScript-away-from-zero boundary disagreement), `recompute_gp` (from the live `EquipmentCatalog`), and `sweep(repo)`. **The key invariant the sweep ADDS beyond the importer's stderr:** `test_template_wealth_sweep` asserts `recompute_gp` equals the importer's stored `resolved_gp_value` for all 216 templates — catching drift between the importer's build-time cost map and the runtime catalog. The flagged SET is pinned in the test so a NEW deviation from a future override / catalog change surfaces loudly. **Calibration outcome (2026-06-04):** the first sweep flagged 15 templates, but ~14 were just iron-ration pricing noise — the catalog had stored 6gp/week (the TOP of the RAW `1gp-6gp` availability range, `acore_equipment.xml:125`) and most templates carry 1-6 weeks of rations. After re-pricing iron rations to 1gp (and standard to 3sp), the abundant-market end of the RAW ranges, the flagged set collapsed to ONE: `dwarven_fury_15_16` at -60% (UNDER target). That lone outlier then turned out to be a **published RAW typo** — the Bloodboiler's "10gp" residual coin is a dropped zero for "100gp" (corroborated by the cash-rich dwarven-fury pattern: the adjacent 13-14 / 17-18 bands carry 41gp / 85gp residuals, so a 10gp 15-16 residual is anomalous). Patched via `RAW_TEMPLATE_PATCHES` in the importer per §7.4.6 — the SACRED source is never edited. **Net result: ZERO templates now deviate > 40%.** The sweep earned its keep — it validated the whole 216-template catalog and surfaced BOTH a systematic pricing miscalibration AND a source typo. Lesson: when a sweep flags broadly, first check whether a single catalog price at the wrong end of a RAW range is the common driver; then the genuine residual outlier is often a real data error worth correcting (here, a RAW errata patched per §7.4.6). Pattern: a "report for human review" derived artifact is markdown (readable) not JSON, carries a provenance line instead of a `_source` field, and is freshness-gated by extending the generator's `--check` to diff it too.

- **Template selection LOCKS class_metadata sub-selections (§10 step 9, added 2026-06-04).** `TemplateClassMetadata` (`engine/subsystems/characters/`, pure static) derives the class-specific selections a template fixes at selection (gdd §4.4, §9.1): witch → `{"witch_tradition": <tradition.to_lower()>}`, barbarian → `{"regional_origin": <region>}`, shaman → `{"shaman_totem": <species>, "shaman_totem_placeholder": "1"}`. These land in the `characters.class_metadata` JSON column (Migration 040) — the SAME column the pre-template barbarian/witch mechanics already use; `regional_origin` is mechanically live (`ClassEquipRestrictionValidator` reads it for the `determined_by_regional_origin` weapon-permission sentinel). **The barbarian region was IP-stripped from the template label at import (§6.6), but its NATURAL proficiency is the region's signature**, so the region is recovered by reverse-mapping the natural prof against `barbarian.json regional_origins[*].bonus_proficiency` (data-driven — climbing→jutland, precise_shooting→skysostan, running→ivory_kingdoms — no hard-coded IP map). The witch tradition rides the template's top-level `tradition` field; the shaman totem species lives in the totem equipment entry's `metadata.companion_kind=="totem"`. Two new string-valued `CharacterData.get/set_class_metadata_value` helpers (the existing `*_flag` pair is boolean-only). `ClassedNpcBuilder.build_classed_npc` stamps the result onto the CharacterData (surfaced as `class_metadata_locked` in the bundle, round-trips through to_dict); `PcTemplateCreationFlow.choose_path_b` surfaces it for the creation wizard. Classes that lock nothing (incl. natural-prof classes like bard/dwarven_craftpriest that have no *region*) derive `{}`.

- **Higher-level NPC magic-item progression (§10 step 10, added 2026-06-04).** `TemplateMagicItemProgression` (`engine/subsystems/characters/`, static) is the v1 §7.5 deterministic ladder layered on the L1 template floor — PROJECT-DESIGNED, not RAW. **Keys off the class's `combat_progression` field** (the first-class `data/classes/*.json` field: fighter/cleric/thief/mage), NOT spellcasting status — so an Elven Spellsword (arcane caster, `combat_progression:"fighter"`) takes the weapon/armor ladder and NEVER the mage scroll/wand ladder (gdd §7.5 hybrid rule; verified by test). The PURE math (`weapon_armor_plus` = fighter/thief +1 per 3 levels past 1, cleric +1 per 4, cap +3 via `floori`; `scroll_wand_counts` = cleric divine scroll @L5/L7, mage arcane scroll @L3/L7/L14 + wand @L5/L9; `has_any_grant`) is a function of level+progression only and fully testable without catalogs. `compute()` additionally picks WHICH template piece gets the +N (highest-`cost_cp` `item_category=="weapon"`; `"armor"` body piece, else `"shield"` as a v1 fallback) and materializes placeholder scrolls/wands from `MagicItemCatalog` (categories `"scroll"` / `"rod_staff_wand"`; the real arcane/divine split + proper wand selection deferred to the magic-item GDD, §7.5/§11). The builder computes it when level>1 (`magic_item_progression` in the bundle), and `persist()` stamps `is_magical=1` + `magical_bonus=N` onto exactly ONE matching weapon and ONE armor inventory row (the existing Migration 005 columns) and adds the scroll/wand rows. Deterministic RNG via `make_rng(class_id, level, roll)` (`rng.seed = hash(...)`, the project convention). L1 builds get an all-zero result (the common henchman case pays no catalog cost).

- **Arcane spell repertoire picker (§10 step 11, added 2026-06-04).** `TemplateSpellRepertoire` (`engine/subsystems/characters/`, deps injectable like RepertoireEngine) bridges the CURATED template spells with the GENERIC `RepertoireEngine` growth. `name_to_key` resolves the importer's lowercase prose spell names (`"magic missile"`→`magic_missile`; `"darkness"` resolves at runtime as Light's synthetic reverse form — all 22 distinct arcane-template spell names resolve, guarded by a coverage test). `build_repertoire` returns `character_spells` rows ready for `save_character_spells`: template starting_spells + the INT-kept bonus_spell, then at L1 the §8.2 INT extras (1 at INT 16-17, 2 at 18) rolled on the arcane L1 list (dedup-no-reroll per ACKS — fewer spells, not a reroll), or at level>1 grown to the class's level-N capacity (`get_arcane_repertoire_capacity`, which folds in the INT modifier so the L1 extras are NOT double-counted). **The §8 design is internally consistent with RepertoireEngine capacity**: at L1 template(1) + bonus(INT≥13) + extras = capacity[0] exactly across INT 12/14/16/18. The builder lazily constructs it on first arcane build (avoids the 254-spell SpellRegistry load for mundane/L1-henchman builds), attaches `repertoire_spells` to the bundle, and `persist()` routes them to `save_character_spells`; `PcTemplateCreationFlow.build_repertoire` is the PC-side parity hook (§4.2.1). Deterministic single-roll tests use `GameState.dice_overrides[label]` (single-value-per-roll-type, consumed on first roll); multi-roll cases assert ranges/membership.

- **Non-catalog item routing (§5.2 / §9.1, added 2026-06-04).** `ClassedNpcBuilder.persist()` routes the bundle's `non_catalog_items` (it previously surfaced-but-dropped them) via `_route_non_catalog_items`, dispatching each entry's `metadata` by kind to its owning subsystem. The data has SIX kinds, not the four with dedicated subsystems: **familiar** (`companion_kind:"familiar"`, 13 across mage/warlock/witch/elven_courtier/elven_spellsword/darkblood_ruinguard) → `CampaignRepository.create_familiar`, GRANTED at creation bypassing the bind ritual (gdd §5.2); the form supplies the body, HD/HP/INT/save derive from the master via `FamiliarData.compute_progression_for_master_level` + banker's-halved HP, mirroring `CharacterCreationScreen`'s finalize block; the flavor species → mechanical `form_key` through the curated `FAMILIAR_SPECIES_TO_FORM` const (birds→`hawk`, serpents+lizard→`snake_small`, dog→`cat`) with the true species kept as `cosmetic_species`. **totem** (`companion_kind:"totem"`, 8 shaman bands) → `create_trained_creature` as an ordinary companion animal (v1, gdd §9.1); `species_id` resolves to a real `MonsterRegistry` id via `TOTEM_SPECIES_TO_SPECIES_ID` (owl/raven→`hawk_ordinary`, eagle→`hawk_giant`, rat→`varmint_giant_rat` — STAT stand-ins) so the placeholder has catalog stats + a deterministic seeded HP roll, and the TRUE species + placeholder flag ride in `purchase_item_key = "totem_placeholder:<species>"` (the future totem subsystem finds them `LIKE 'totem_placeholder:%'` and reads the real species even though `species_id` is a stand-in); `handler_id` = the new character. **valuable** (`noncatalog_kind:"valuable"`, 24) → a `value_cp = value_gp*100` inventory row (item_key `"valuables"`, category `"treasure"`), sellable by ShopService (value-driven, Migration 134). **poison** (`noncatalog_kind:"separate_catalog", tag:"poison"`, 2) → a generic `poison_dose` placeholder + `push_warning` TODO, since `data/equipment/poisons.json` has no inventory bridge yet and the template tags "poison" with no specific key. **flavor_tool / flavor_consumable** (disguise_kit / medicine_bag / carving_knife / body_oil, 7) → INTENTIONALLY SKIPPED, no row: per this section's 2026-06-04 review-pass they were deliberately classified as flavor because the governing proficiency (Disguise / Healing / etc.) provides the capability — producing nothing IS the design, not a drop-bug. A genuinely unknown kind hits the `else` `push_warning` (never silent). **Conventions established:** (1) template-grant routing lives in `persist()` and is DEFENSIVE — every cross-subsystem repo call (`create_familiar` / `create_trained_creature`) is `has_method()`-guarded so the DB-free fake repo (the 100-henchman coherence test) and partial fakes don't crash; the test's `_FakeRepo` was extended with `familiars_created` / `creatures_created`. (2) a trained_creature needs a party FK but a standalone classed NPC has none, so `party_id` is threaded `opts → bundle["party_id"] → persist`; absent, the totem is NOT created and a `push_warning` says so (warn-not-drop — the totem genuinely cannot persist party-less; callers wanting it pass `opts.party_id`). (3) heavy registries (`MonsterRegistry`) are lazily built on first use (`_ensure_monster_registry`, mirroring `_ensure_spell_repertoire`) so the common non-totem path pays nothing. The four real kinds are covered by `test_classed_npc_builder.gd` (familiar form-mapping + master-binding, totem placeholder marker + no-party skip, valuable value_cp, poison placeholder, flavor inertness).

- **PC creation template UI (§10 step 12, added + reworked 2026-06-06).** The §4 choice point is a new step in `CharacterCreationScreen` (renumbered 13→14): `ClassTemplatePanel` (`scenes/ui/character_creation/`, `class_name` + `extends VBoxContainer`, standard `setup(state, …)` + `is_complete()`, built programmatically per §13.2). The panel does ONLY the fork — a wealth roll (`DiceSystem.player_roll(6,3,0,"starting_gold",…)`, the SAME roll type EQUIPMENT uses) → Path A (keep gold) / Path B (template cards). **Decisions Jedidiah locked:** (a) "pick after template" — `CLASS_CUSTOMIZATION` (barbarian region / witch tradition) MOVED to after the template step; Path B locks origin/tradition (skip it), Path A keeps it for those 2 classes. (b) **Reuse the full pickers, not a bespoke editor** — an initial compact in-template §4.2.1 editor (OptionButton swaps + cull + preview) was BUILT then REPLACED: it couldn't match the real pickers (no multi-rank stacking, no specialization sub-pick, no §8.2 spell roll). Instead Path B SEEDS creation_state and flows through the SAME Proficiencies + Spells steps a normal character uses. Patterns established:
  - **Seed-and-reuse beats reimplement.** On a Path B card, `_apply_template` seeds: `proficiencies` (editable class/general, INT-cull applied) + `bonus_proficiencies` (locked natural/tradition) via `PcTemplateCreationFlow.template_base_proficiencies` (cull + record-split, NO INT-bonus auto-fill — the player fills those); equipment/coin; `template_class_metadata` PLUS the `barbarian_origin`/`witch_tradition` keys intermediate steps read directly (divine-Spells tradition bonus, equip validator); and the BASE arcane repertoire + `template_extra_spells` via `template_base_repertoire` (= `build_repertoire` with 0 auto-rolled extras). Then the wizard STOPS skipping PROFICIENCIES (and SPELLS). `ProficiencySelectionPanel` needs ZERO changes — its slot math (1 class + 1 general + INT-mod generals) ALIGNS with a template's grant (the arcane_bonus IS the first INT-bonus general; the §8 cull = mod 0 at INT ≤ 12), so the seeded set fits and the player edits with full multi-rank / specialization / swap / fill. Lesson: when a bespoke "compact" UI starts re-implementing a rich existing panel, seed the rich panel instead.
  - **Template-mode in the reused Spells panel.** A template defines the repertoire + §8.2 extras (1 at INT 16-17, 2 at 18 — NOT the normal pick-1 + INT-mod), so `SpellSelectionPanel._setup_arcane` branches on `template_path=="B"`: shows the granted base read-only + a roll for the §8.2 extras (reusing `_on_roll_bonus_pressed`), and `is_complete()` is GATED until those are rolled+confirmed. The no-input case (arcane Path B, extras == 0, repertoire already seeded) is the ONE spot `_should_skip_spells` still skips on Path B.
  - **Step-ownership invalidation.** The CLASS_TEMPLATE step OWNS `wealth_roll` + the Path A/B choice + (Path B) `proficiencies`/`bonus_proficiencies`/`spells`/`inventory`/loose-coin/`template_extra_spells`; steps AT or BEFORE it wipe them all (`_clear_template_outputs`), steps AFTER it NEVER wipe template-owned fields — they reset only their own output and un-spend gold (`gold_remaining_cp → starting_gold_cp`). FAMILIAR / divine SPELLS guard their clears with `template_path != "B"`. EQUIPMENT owns the gold roll ONLY for no-template classes (`template_path == ""`); when a template ran it only un-spends.
  - **Path A reconciliation = one roll (§4.1).** Path A writes `starting_gold_cp = gold_remaining_cp = roll×10×100`; `EquipmentShopPanel._restore_from_state` hides its roll button when `starting_gold_cp > 0`, so the shop opens pre-funded — the die is never rolled twice.
  - **Reused-instance hygiene (§13.3).** The screen keeps ONE panel instance for every PC, so `setup()`/`_restore_from_state` is a FULL rehydration: recompute the roll button's `disabled` (a transient dice-prompt guard that otherwise left a LATER character's button greyed-out — a real bug caught in playtest) and clear cached templates. The §4 origin/tradition a template locks is shown as a parenthetical after the title (`_origin_suffix` via `TemplateClassMetadata.derive` — "Berserker (Jutland)", "Crone (Sylvan)"), since the IP-stripped label omits it.
  - **`finalize_proficiencies` swaps + `swap_options` are now UI-UNUSED** (the reused picker does the editing) but kept as a tested headless capability; `template_base_proficiencies` is the UI seeder. **Still deferred:** PC-side valuable/totem/poison non-catalog routing (logged via `push_warning`; `ClassedNpcBuilder._route_non_catalog_items` is the reference). Headless tests cover the flow seeders + swaps (`test_pc_template_creation_flow.gd`); the panel UI + step-flow are verified by launching the wizard (programmatic panels aren't unit-tested, per §13).

## 79. Savegame persistence: the DB is the save, context+position must round-trip (2026-06-07)

The game has no separate save file — **the SQLite DB is the live save** (write-through during play; `SessionRunner.save_session()` flushes in-memory-only state on pause-menu Save / quit). `generation/gdd-savegame-system.md` is the design of record. Phase S-1 made the model faithful for **location/context**, which it previously dropped on load (a party saved in a dungeon/settlement reloaded in wilderness). Patterns established:

- **Each context flushes its own dirty state via `SessionState.flush_to_db(runner)`.** This additive base virtual (default no-op) replaced the old wilderness-only `if` in `save_session()`. Overrides: `WildernessExploreState` → hex map (fog/survey); `DungeonExploreState` → voxel cells + per-entity positions + party-level dungeon position; `SettlementExploreState` → current POI. `save_session()` calls `_current_state.flush_to_db(self)`. When you add a new exploration state with mutable in-memory state, override `flush_to_db` rather than special-casing the runner.

- **`current_location_type` is written centrally in `SessionRunner.transition_to_state()`, for primary-location states ONLY.** wilderness/dungeon/settlement → `CampaignRepository.update_party_location_type(_party_id, state_key)`. Sub-context states (combat / camp / encounter / downtime) are NOT in that list, so they leave the saved context untouched — combat-in-a-dungeon still restores to the dungeon. This rides the existing §16.2 rule that SessionRunner is the sole driver of context.

- **The loader branches on `current_location_type`; never hardcode a boot context.** `SessionLoadState` loads the top-level hex map (so exiting a restored dungeon/settlement returns to the right hex) then `match`es the saved type → re-enters dungeon (rebuild entrance via `get_dungeon_entrance_for_dungeon_id` + pass `restore_positions`) / settlement (`get_settlement_entrance` + saved POI) / wilderness. **Always provide a fallback:** an unresolvable dungeon/settlement (stale save) falls back to wilderness with a `push_warning`, never a crash.

- **Dungeon restore is PER-MEMBER and exact — never re-scatter on load.** Each entity's live `Vector3i(col,row,level)` is persisted in the dedicated `dungeon_entity_positions` table (migration 146), keyed `(party_id, entity_id)`, written on flush, DELETEd on dungeon exit. `DungeonMapController.restore_entity_positions()` places each entity individually + sets the active level to the leader's level + mirrors `teleport_party_to`'s refresh signals (`entity_moved` / `level_changed` / `_update_visibility_on_move` / `party_moved`). `_scatter_party_at_entry` is the FRESH-ENTRY path only. (Jedidiah 2026-06-07: anchor-scatter on reload could yank members across the map — unexpected.)

- **Write-only persistence is a bug — explored state must be read back on load.** `_save_dungeon_cell_states()` had been saving voxel fog/door state that `load_dungeon()` never read, so re-entry showed a pristine dungeon. `DungeonMapController._merge_persisted_cell_state()` now overlays persisted `voxel_map_cells` (fog/door fields only; structural fields stay from the layout) after building from the layout; it no-ops on first entry (sparse + empty). General rule: if you add a `save_*` for runtime state, add the matching read in the load path in the same change, or it is dead code that silently loses data.

- **No saving mid-combat.** `SessionState.is_in_combat()` (additive virtual, default false) is overridden by `DungeonExploreState` (returns its in-place `_in_combat`) so the guard covers dungeon combat, which keeps the "dungeon" state key rather than transitioning to "combat". `SessionRunner.is_in_combat()` = `state_key == "combat" or _current_state.is_in_combat()`; both `save_session()` and the pause-menu Save check it (the menu shows a "Cannot Save During Combat" toast rather than a silent no-op).

- **Location columns already existed; most of S-1 was wiring, not schema.** `parties.current_location_type` (base), `dungeon_*` (migration 017), `settlement_id/settlement_node_id` (migration 019) were present-but-unused — only the per-member `dungeon_entity_positions` table was new (migration 146). When a feature looks "missing," check whether the columns are already there and merely unread before writing a migration.

- **Named save slots: WHOLE-DB capture + PER-CAMPAIGN restore (S-2, 2026-06-07).** `save_snapshot` = `VACUUM INTO 'user://saves/<id>.db'` (a complete copy of the entire DB — cannot miss a table). `restore_snapshot` = `ATTACH` the slot + `_restore_campaign_from_slot`: per-table `DELETE FROM main.<t> WHERE <campaign-scope>` then `INSERT … SELECT … FROM slot.<t> WHERE <campaign-scope>`, so **only the slot's campaign is touched — other campaigns are left intact** (Jedidiah requires per-campaign isolation). The scope per table comes from `_campaign_scope_entries()` — a registry that IS exhaustively maintained and **kept honest by `test_scope_map_covers_all_tables`** (asserts `scope map ∪ SNAPSHOT_EXCLUDED_TABLES == all tables`, so a new table fails the suite until classified). The dungeon-content tables (`dungeon_floors/rooms/doors`, `monster_groups`, `treasure_hoards`, `key_items`, `voxel_map_cells`) key off a `dungeon_id` buried in `dungeon_entrances.dungeon_data` JSON — there is no SQL path to a campaign, so they are scoped by a **computed dungeon-id list** (`_dungeon_ids_for_campaign`), not a WHERE clause. Column-intersection (`_shared_columns`) handles schema drift; `game_snapshots` is excluded so the slot list survives. `game_snapshots` is slot METADATA (migration 147: `slot_kind`/`schema_version`/`location_label`); `snapshot_data` holds a manifest, not rows.

- **Per-campaign DELETE must run deepest-child-first.** A child table's scope subquery reads its parent's rows (`character_id IN (SELECT id FROM main.characters WHERE campaign_id=?)`), so if the parent is deleted first the child-delete matches nothing and orphans rows. `_campaign_scope_entries()` is ordered depth-3 → depth-2 → depth-1 (direct `campaign_id` parents last, `campaigns` very last). INSERT reads from the read-only `slot`, so its order is irrelevant. When adding a table, place it before its scope-parent.

- **Restore copies via ATTACH — never close/reopen the DB connection.** godot-sqlite mishandles `close_db`/`open_db` (FK-check breakage — see `wipe_for_tests`'s comment), so the slot is applied by ATTACH + table copy on the LIVE connection inside one transaction. SQLite 3.27+ `VACUUM INTO`, `ATTACH`, and schema-qualified `PRAGMA main.table_info` / `slot.sqlite_master` are all available (bundled 3.51.0) — verify with a one-shot `--script` SceneTree probe before relying on an exotic SQLite feature.

- **A column's declared TYPE can drift from its real usage when a subsystem is rebuilt — realign it, don't just coerce the reader (2026-06-07).** `parties.settlement_node_id` was `INTEGER DEFAULT -1` (migration 019, the old settlement "street-graph node" model), but the settlement system was later rebuilt to string POI ids (`SettlementMapController.get_current_poi_id() -> String`), `PartyData.settlement_node_id` is a `String`, and the writers (`update_party_settlement_position(node_id: String)` / `clear_party_settlement_position`) store a POI id / `''`. Phase S-1 added the FIRST reader of the column (`PartyData.from_db` via `_str`), which EXPOSED the drift: a fresh party has the INTEGER `-1` default, and `_str` returned int `-1` from a `-> String` function → loader crash on every new party. The fix is BOTH layers, and you generally want both: **(1)** `PartyData._str` now returns the value only when it `is String`, else the fallback — a `-> String` DB-row helper must NEVER `return` a raw Variant (this is the crash fix and a defensive net for any future type drift); **(2)** migration 148 rebuilt the column to `TEXT NOT NULL DEFAULT ''` (ADD temp → copy with `typeof(...) = 'text'` guard → DROP → RENAME; SQLite 3.51, cf. the DROP/RENAME COLUMN migrations 097 / 108-111) so fresh rows get `''` and RAW reads are strings. Applied migrations are immutable history, so migration 019's now-stale comment is left as-is; 148 + the `schema.sql` parties comment carry the current truth. Lesson: when the first reader of a long-dormant column crashes on a type, check whether the column's declared type still matches how the rest of the code uses it and realign the SCHEMA, not just the reader. The regression test (`test_savegame_location.test_fresh_party_settlement_node_id_default`) asserts the bare-DEFAULT read (the case the existing settlement tests missed — they always WROTE a position first) AND `typeof(raw) == TYPE_STRING`, so the realignment can't silently regress behind `_str`'s coercion.

- **Loading a slot re-enters via the existing `session_load` path; don't patch a live session.** `SessionRunner.load_slot(id)` = `end_session()` (tears down + harmless pre-restore save) → `restore_snapshot(id)` → `transition_to_state("session_load", {campaign_id})`. Re-entry reuses S-1's context-aware loader, so a loaded slot lands in its saved context (dungeon cell / settlement POI / hex). `save_to_slot(label)` flushes the live state first so the slot is current.

- **New save FILES need cleanup hooks that plain row-DELETE doesn't give you.** `delete_snapshot` and `prune_oldest_snapshots` remove the `user://saves/*.db` file AND the row; `wipe_for_tests` clears the saves dir (row-wipe alone orphans files, accumulating across test runs). Whenever a table's rows reference external files, the delete/wipe/prune paths must remove the files too.


## 80. Setting-generation canonical data + determinism harness (2026-06-12) [PROVISIONAL]

The pre-game setting-generation pipeline (docs/setting-generation-build-handoff.md; gdd-setting-generation.md) introduced these conventions:

- **`setting_*` tables (migration 156) are the CANONICAL world, separate from the play tables.** They are written only by `engine/subsystems/generation/world/*` during campaign creation and frozen by the Layer-8 post-approval lock (`setting_parameters.is_locked`). Every `SettingRepository` writer checks the lock and fails loudly after it. The play layer (hex_maps/hex_cells/domains/realms) is materialized FROM the canonical data at the party-creation handoff and may then evolve; the canonical setting never changes. Do not point runtime systems at `setting_*` for mutable state.

- **Deterministic TEXT ids inside the canonical dataset.** Generation-assigned ids (`pol_0001`, `evt_000123_004`, `stl_0042`, `reg_...`, `ruin_...`) — NEVER `CampaignRepository.generate_id()` (random) and never `AUTOINCREMENT` (global across campaigns, so two same-seed runs interleaved in one DB would diverge). The §9.1 determinism hash test compares two same-seed generation runs row-for-row; random ids break it.

- **All pipeline randomness through `WorldGenRng`** (`engine/subsystems/generation/world/world_gen_rng.gd`): `derive_seed(campaign_seed, subsystem, tick, entity_id)` / `stream(...)` — a project-pinned FNV-1a 64 over a canonical byte encoding (length-prefixed strings; little-endian int64). NOT GDScript `hash()` (engine-internal, version-dependent). Never iterate a Dictionary to make seeded draws — sort keys first; never share one sequential RNG across subsystems (draw-order coupling). A golden-value test (`test_setting_stage0.gd`) pins the derivation; changing it invalidates every share-seed and must be deliberate.

- **Canonical hex iteration order is `(r ASC, q ASC)`** (row-major raster). Shared by the dataset hasher, `SettingRepository.list_hexes`, and the replay-frame RLE. Replay `owner_by_hex` RLE format: runs of `polity_id:count` joined by `;`, `''` polity_id = unowned, over the canonical hex order.

- **Determinism hash harness** (`SettingDatasetHasher`): SHA-256 per setting table (sub-hashes localize a divergence to the layer that wrote the table) + a combined world hash. Excludes `campaign_id` (differs between the two compare runs), `created_at`, and the lock fields (the lock stamps the hash, so the hash cannot include it). Floats hash as raw IEEE-754 bits (`PackedByteArray.encode_double`), not formatted text — formatting hides sub-epsilon platform drift, which is exactly what the harness exists to catch. Any session touching `engine/subsystems/generation/world/` must keep the hash test green.

- **Banker's rounding:** the pipeline reuses `XPAwardCalculator.bankers_round()` (the existing single utility; cross-subsystem use precedent: stronghold_cost_calculator). Do not add another per-file `_bankers_round` copy inside generation code.

- **`setting_hexes` is re-saved (upsert) as its substrate evolves across layers.** Terrain (elevation/biome/water/land_value) is fixed at Layer 2; the substrate columns (culture_weights/alignment_weights/population_band/territory_class/owner_polity_id) are seeded at Layer 3 and rewritten through Layer 4. `SettingRepository.save_hexes` is `INSERT OR REPLACE` on `(campaign_id, q, r)`; the orchestrator re-persists the whole in-memory `ctx["hex_grid"]` each time a layer mutates the substrate. The in-memory grid is the single source of truth within a `generate()` call; the DB mirrors it at layer boundaries so each stage is independently inspectable.

- **`setting_polities` holds the EVOLVING polity set, not just the final one.** Layer 3 (`CultureSeeder`) writes the tick-0 SEED polities (`founded_tick = 0`, `fell_tick = NULL`); Layer 4 runs them forward and re-persists the present-day result. A Stage-3 test that asserts seed-state invariants on `setting_polities` is only valid while Layer 4 is a stub — when the sim lands, those assertions move to a seed-only checkpoint (noted in `test_setting_stage3.gd`). Polity ids are deterministic `pol_NNNN` in placement order (humans/demihumans first, then beastmen in canonical hex order).

- **Culture records (`data/cultures/*.json`) are READ-ONLY pipeline inputs.** `CultureCatalogLoader` caches them; per-campaign jitter (catalog §7) lands on an *instance* dict (`ctx["culture_instances"]`), never written back to disk. The catalog uses capitalized alignments (`Lawful/Neutral/Chaotic`); the sim/DB use lowercased (`lawful/neutral/chaotic`) — lowercase at the `CultureSeeder` boundary.

- **Beastman geographic distribution is build-time extracted** (`tools/extract_setting_generation_data.py` → `data/setting_generation/beastman_distribution.json`, §7.4 pattern with a `--check` freshness gate). It carries a documented RAW PATCH (§7.4.6): the `river` column's d100 had a gap at 13 (bugbear `1-12`, gnoll `14-25` in `ax_domains_of_chaos.xml:278-279`); the extractor corrects gnoll to `13-25` so the table is contiguous, citing the source line. Never hand-edit the JSON (the freshness test fails it) and never edit the XML (sacred).

- **Stage 4 config is one data-driven resource (`SimConstants`, §7.8) + the RAW tier table (`DomainTierTable`, §12.1A).** All history-sim constants live as fields on a single `SimConstants` instance threaded through the sim — no scattered literals — so the balance pass (history-sim §17) retunes one file. `DomainTierTable` is pure-static reference data (RAW `titles_of_nobility` verified 2026-06-12); `tier_for_families()` keys in-sim tier on OVERALL realm families.

- **The history sim (`HistorySimulator`) is a per-tick phase loop over an in-memory state; it persists nothing itself.** `run(ctx, constants)` mutates `ctx["hex_grid"]` (population/class/owner/substrate) in place and writes the §7.2 outputs into `ctx` (`sim_polities`, `sim_settlements`, `sim_events`, `sim_replay_frames`, `sim_replay_palette`, `sim_ruin_seeds`, `sim_fallen_polities`); the orchestrator's `_run_history_sim` then `clear_sim_output` + re-persists. Phase order per history-sim §3: expansion/war/migration BEFORE stability/collapse (so a tick's overextension feeds that tick's collapse roll); substrate diffusion AFTER political change. Each sub-stage 4a–4g fills its phase method; unbuilt phases are explicit no-op stubs so the loop runs end-to-end from 4a.

- **Substrate is parsed into memory for the tick loop, serialized to canonical JSON only at finalize.** Per-tick `JSON.parse`/`stringify` over every hex would dominate a 160-tick run, so `_parse_substrate()` loads `culture_weights`/`alignment_weights` into `_culture_w`/`_alignment_w` (Vector2i → {key: float}) once; the loop mutates those; `_serialize_substrate()` writes them back as sorted-key full-precision JSON (`JSON.stringify(w, "", true, true)`) so two same-seed runs are byte-identical. Inhabited hexes (pop > 0) are normalized to sum 1.0 with the minority floor (§11.1); empty land keeps its diffused trace un-normalized.

- **Static per-edge data is precomputed once, never per tick.** Diffusion edge damping is a function of static terrain + the static river graph, so `_precompute_edge_damp()` caches it per directed land-land edge (`Vector3i(q,r,e)`); the diffusion loop reads the cache. Diffusion processes each undirected edge once (`_canonical_less`) and skips empty-empty pairs. The graph-Laplacian step is symmetric (+T to one endpoint, −T to the other) so it conserves mass and stays deterministic. This pattern — cache anything terrain-derived before the loop — applies to every later sim phase.

- **The sim's present-day output REPLACES the Layer-3 seed polities.** `setting_polities`/`setting_settlements`/`setting_events`/`setting_ruin_seeds`/`setting_fallen_polities`/`setting_replay_frames`/`setting_replay_palette` are cleared (`SettingRepository.clear_sim_output`) before the sim re-persists; `setting_hexes` is NOT cleared (the sim mutates substrate in place and re-saves via the upsert). A seed-state test therefore asserts on the IN-MEMORY seed ctx (run Layers 1-3 only), never the post-`generate()` DB — see `test_setting_stage3.gd` / `test_setting_stage1.gd` (its perf test times Layers 1-2 in isolation, not the whole pipeline).

- **Beastman polities are identified in the sim as those whose `culture_id` has no `culture_instances` entry** (only selected human/demihuman cultures get a jittered instance). Their clanholds stay wilderness (no classification advancement) and found no urban settlements (catalog §5.3); the cap stays 2,000 families/24-mile hex.

History-sim Stage 4 (4b–4d landed 2026-06-13) added these (all [PROVISIONAL] until the §17 balance pass):

- **Prev-tick ledger coupling: war reads last tick's economy outputs.** The phase order is expansion → war → migration → economy → stability → … (history-sim §3), so when `_phase_war` runs, this tick's ledger has not been computed yet. War strength reads `pol["garrison_spent"]` and pillage loot reads `pol["last_income"]`, both stamped by the PREVIOUS tick's `_phase_economy`. This is deliberate (a war's territorial swing must spike garrison need the same tick, so economy comes after war) — tick-0 wars are no-ops because no ledger has run. When a later phase needs a value the ledger produces, store it on the polity in `_phase_economy` and read the prev-tick copy; do not reorder the economy phase to make it "fresh."

- **§4.4 `effective_svg` is a single evaluator used two ways.** `_apply_svg_modifiers(base, mods, …)` implements catalog §4.4: `'set'` modifiers first (first match wins, then break), then ALL matching `'adjust'` modifiers accumulate, clamp [0,1]. Conditions (`_svg_condition`): `target_same_alignment`, `target_opposite_alignment` (Lawful↔Chaotic only — NOT merely "different"; secession's `alignment_mismatch` is the "differ" test, a separate thing), `target_is_demihuman` (target instance tier), `target_in/outside_my_seed_biome` (attacker `seed_biomes` vs the target hex via `CultureSeeder._hex_matches_term`). `_effective_svg(P,Q)` drives the crushing-victory disposition (evaluated at Q's capital hex; svg ≤0.35 / 0.35–0.65 → vassalize, ≥0.65 → annex). `_effective_svg_for_hex(owner,key)` drives per-hex substrate assimilation (target = the hex's dominant NON-owner culture; a pure homeland uses base svg and is skipped when already ≥0.999 owner weight — the lerp is a no-op there). Modifier-less instances (e.g. in-memory test instances) return base svg, so the upgrade is invisible to pre-§4.4 tests.

- **4d creates NO new polities — new polities arrive only with 4e shatter / 4f migration.** War-vassalization sets `liege_id` on the existing defender; annexation flips its hexes to the victor and marks it `alive=false` (the key stays in `_polities`); decisive transfers move existing vassal-polities; secession clears `liege_id`. Because no `_polities` key is added mid-tick, the war set (a snapshot list) and the `_sorted_polity_ids()` loops are safe to iterate. `_annex` iterates a `.duplicate()` of the defender's hexes while `_flip_hex` mutates the live lists. Any phase that DOES spawn polities (4e/4f) must build into a separate list and merge after the iteration, never into the dict being walked. The §7.4 internal vassal-domain records (CORE_MAX partition → `vassal_count`) are deferred to 4e, where shatter consumes them.

- **`_emit_event` writes fully-formed §11 rows; the event log is append-only within a run.** Every event carries all `SettingRepository.EVENT_COLUMNS` (deterministic `evt_NNNNNN` id from a monotonic counter; `year_before_start = (n_ticks − tick) × tick_years`; `hexes` canonically sorted before `JSON.stringify`; `significance` 0.0 until 4g scores it; `region_hint` "" until naming). `type` must be in the migration-156 CHECK set (`war`/`conquest`/`vassalage`/`secession`/`pillage`/`collapse_*`/…). A resolved war emits a `war` event even on defender-holds (the war happened); 4g significance scoring ranks/trims the verbose log.

- **Sim WorldGenRng stream names (the per-tick draws).** Registry so a future phase doesn't collide: `contest` (4b border contest); `war_escalate` / `war_margin` / `war_transfer` / `war_pillage` / `secede` (4d); `ruler` / `collapse` / `severity` / `shatter` (4e); `beastman_repop` / `beastman_race` / `migrate` (4f). Each is keyed `(campaign_seed, name, tick, "P>Q"|"q,r"|entity)`; independent per entity so iteration order never affects a value.

History-sim Stage 4e/4f (collapse + renewal, landed 2026-06-13):

- **Collapse (4e) and renewal (4f) are one mechanic in two phases — test them together.** §7.6 collapse DRAINS polities (a healthy realm lives ~30 ticks, §7.5; ~39% of low-tier collapses depopulate to wilderness); the ONLY things that create polities from empty wilderness are §8 migration bands and §7.6 beastman repopulation (4f) plus §7.6 shatter successors. So `_phase_collapse` without `_phase_migration` drains the present-day map to ~0 polities — a degenerate world. The full-pipeline integration tests assume the rise→fall→**renewal** equilibrium (the §17 target: ~50% wilderness, several surviving realms), so they only pass with BOTH phases live. A deep/short-history UNIT test that runs the sim on a single hand-built polity must pass a no-collapse `SimConstants` (`c.collapse_base = 0.0`) to isolate the growth/expansion/substrate mechanic it targets — collapse would otherwise destroy the lone realm. (See `test_setting_stage4a/4b` `_stable_constants`.)

- **New polities are created at exactly four points; never mutate `_polities` while iterating it.** Shatter successors (4e `_spawn_successor`), beastman clanholds (4f `_spawn_beastman_clanhold`), and migrant realms (4f `_found_migrant_polity`) all draw a fresh `pol_NNNN` id from the monotonic `_next_polity_seq` (initialized in `_init_polities` past the seed range). 4e collects successors in a local list and merges them AFTER the collapse loop; 4f's spawns happen inside `_phase_migration`, which iterates `_depopulated_at` keys / `_bands` / sorted ids but NOT `_polities` itself, so adding is safe. `_finalize_new_polity(pol, tick)` is the shared runtime-field augmentation (resets the collapse/economy/expansion slate, `founded_tick = now` so ascendancy applies, `is_beastman` per §5.3 = no jittered instance). Any future phase that spawns polities must follow collect-then-merge, never insert into the dict it is walking.

- **Internal vassal-domain decomposition is on-demand, not per-tick state.** `_internal_vassal_domains(pol)` (core = capital + nearest up to `CORE_MAX`; the rest BFS-partitioned into `VASSAL_SIZE`-contiguous chunks) runs only at a collapse (for `_vassal_count` → the shatter gate/K cap) and at finalize (the `internal_vassals` output column). Deterministic (canonical seed + fixed `_OFF` BFS), so two same-seed runs match; cheap because it never runs in the hot tick loop.

- **Collapse restores wilderness by reverting hexes to unowned; the substrate trace stays.** `_revert_to_wilderness(h, keep_fraction, mark_depopulated)` clears `owner_polity_id`, sets `territory_class` wilderness, scales population by the keep fraction (rump 0.5 / depopulate 0.1), and leaves `_culture_w[h]` as the diffused provenance trace. Depopulated hexes are stamped in `_depopulated_at` (Vector2i→tick) for 4f beastman repopulation after `BEASTMAN_DELAY`. A migrating band that finds no home conserves its people via `_dissolve_band` (families + culture/alignment blend into the stop hex by population weight) — never silently drop a band's families.

History-sim Stage 4g (present-day handoff + significance, landed 2026-06-13):

- **Present-day handoff runs once at finalize, not per tick.** `_assign_present_day_handoff()` (called from `_finalize` after `_serialize_substrate`) stamps each alive realm's `ruler_level` (`DomainTierTable.ruler_level_for_tier`), `ruler_class` (catalog §4.3: a martial-leaning base distribution lerped with the normalized `sphere_weights` tilt at `RULER_CLASS_BLEND`, then a seeded `WorldGenRng.stream(..., "ruler_class", n_ticks, pid)` draw — sphere weights move the odds, they don't set the class), and `morale_seed` JSON. `_score_event_significance()` then scores every event (`_EVENT_SIGNIFICANCE[type]` + `significance_severity_weight × severity`). `_phase_log` stays a per-tick no-op: events are emitted inline by their phase, significance is a finalize pass. New phases that produce handoff data belong at finalize, not in the tick loop.

- **The stronghold-value numbers live in `DomainTierTable`, sourced from the CORRECTED rules XML.** `rulers_stronghold_value_gp` in `revenue_by_realm_type` (acore-setting-construction-rules.xml) had a transcription error (Principality/Duchy/County), corrected 2026-06-13; `DomainTierTable.TIERS[].stronghold_value_gp` and GDD §12.1 now follow the XML (Empire 720K / Kingdom 480K / Principality 360K / Duchy 115K / County 70K / March 45K / Barony 22.5K). When the rules XML and a GDD figure disagree, the XML wins (source precedence) and the GDD is rewritten to match — never the reverse. The §7.5.1 per-family ledger (Land 3-9 + Services 4 + Taxes 2; overhead 3; garrison 2/3/4) was verified unchanged.

- **Profiling is built into the sim behind a flag.** `HistorySimulator._profile` (default off) + `_mark`/`_phase_us`/`profile_summary()` accumulate per-phase microseconds; the 4a perf test enables it and prints a per-phase breakdown. Use it before optimizing — the post-4f perf pass found substrate/war/expansion dominated, not the phases first guessed. The perf-test budget is a 25s regression guard, not the target (the sim runs ~9s).

History-sim §9.3 calibration (tuned baseline, 2026-06-13):

- **The §7.8 constants are CALIBRATION-tuned — do NOT pin their VALUES in tests.** The §9.3 pass tuned ~14 balance knobs (`collapse_base`, `tier_risk_mult`+`tier_risk_cohesion_floor`, the `severity_band_*`, `base_secede`, `war_band_crushing`/`capital_reach`/`svg_annex_min`/`war_base`, `expansion_G`/`expansion_N0`, `classification_advance_fraction`, `wilderness_beastman_density`) toward the §17 targets, and will be re-tuned again. Tests must check these as INVARIANTS (e.g. `tier_risk_mult >= 1.0`, `severity_band_rump < severity_band_shatter < 1.0`), never pinned equalities, or every balance change becomes a test break (it bit `test_setting_stage4_foundation`). A test that needs a specific value (e.g. the collapse-risk clamp) should set `sim._c.<field>` locally rather than rely on the default. RAW-derived constants (garrison 2/3/4, the 2gp floor, caps, the stronghold/tier table) ARE pinned — those encode rules, not balance. The tuned values carry `[CALIBRATION yyyy-mm-dd]` comments in `sim_constants.gd` / `setting_parameters.gd`.

- **The calibration harness measures wilderness as `territory_class == "wilderness"`** (the ACKS classification — a beastman clanhold keeps it even while owning the hex), and splits realms into civilized vs beastman (`CultureCatalogLoader.ids_by_tier`) and top-level vs vassal. The §17 "5–10 realms" reads best as `empires_with_vassals` (top-level civ realms ruling ≥1 vassal), not the raw independent count. `test_setting_calibration.gd` runs a cheap medium-×3 SMOKE in the regular suite; `ACKS_CALIBRATION=1` runs the full Large×20 sweep (~3 min) the targets are pegged to.

- **Two beastman model rules emerged from calibration** (Jedidiah's rulings, both in `history_simulator.gd`): (1) a Lawful/Neutral war-victor DESTROYS a beaten beastman clanhold (`_resolve_crushing` annexes it → its land civilizes), only a Chaotic victor vassalizes it; (2) beastmen do NOT expand (`_phase_expansion` skips `is_beastman`) — they are scattered low-density clanholds (ax_domains_of_chaos), the chaotic interior civilizations push back, not empire-builders. These two, plus softening empire size-collapse (`tier_risk_mult` 1.35→1.15) so empires persist and absorb neighbors, were what produced the multi-ethnic-empire-over-mono-culture-vassal end state at ~50% wilderness.

- **A suite's "all tests passed (N checks)" print is HARDCODED and unreliable** (noted earlier for the runner; reconfirmed here): the calibration constant changes silently broke two suites whose `print` still said "passed" — the runner counts pass/fail via `has_failures()`. When verifying after a change, grep the run log for `ASSERTION FAILED` (and compare the count to a known-good run), never trust the per-suite "passed" line.

## 81. Name banks: static per-culture assets built from the conlang kits (2026-06-13) [PROVISIONAL]

Setting-generation Stage 5 (handoff §6; gdd-naming-conventions.md §13) turns the authored conlang kits into committed static name banks that runtime naming (Stage 6) reads as pure lookup. The build tool is `tools/build_name_banks.py` (Python, the §7.4 data-prep precedent — extractors are Python, GDScript loads + tests the JSON); output is `data/name_banks/<culture_id>.json` (one per culture, filename = bare culture_id like `data/cultures/`, NOT the conlang `culture_<id>.json`) + `_manifest.json` (the index). Loader: `NameBankLoader` (`engine/subsystems/generation/world/name_bank_loader.gd`, RefCounted, static cache, mirrors `CultureCatalogLoader`; skips `_manifest.json`).

- **The conlang kit schema (gdd-naming-conventions §2.6) is a SKETCH — the real corpus varies; detect by shape/prefix, never by exact key.** Audited variance over the 65 kits (the audit is worth re-running before any kit-consuming work): `inherits` is a string OR a 1- OR 2-element list (cross-family blends inherit two bases) — normalize to a list. The seed-stock clan key has ~25 spellings (`clan_gens`/`clan_houses`/`clan_rod`/`clan_ovog`/`houses_filiation`/`tribes_hordes`/…) — harvest by the `clan_`/`houses_` prefix + `tribes_hordes`, not a fixed key. Flagship settlements are `flagship_settlements` OR `flagship_lairs` — harvest by the `flagship_` prefix. The corpus splits cleanly into **55 standard kits** (human + 6 demihuman: full `lexicon` with adjectives/resources/…, `title_ladder` tiers `{ruler, domain}`, `religion` with `sample_deity_renames`, `banks_patterns` ships/taverns/military_units/dungeons_ruins) and **10 beastman kits** (reduced: `lexicon` = `concepts`+`feature_words` only, tiers `{ruler, scope}` with no domain, `religion` = `venerated`/`demonized` totemic, patterns = `war_bands`/`lairs_dungeons`, no ship/tavern). Branch on `race == "beastman"`.

- **The build is deterministic by CONSTRUCTION, not by a seeded RNG — no `WorldGenRng`, no `random`.** A name bank is a committed asset, rebuilt from kits offline, never per-campaign; its only determinism requirement is byte-identical re-runs (the freshness gate). So assembly uses sorted enumeration + a co-prime diagonal sweep (`weave(stems, heads)`: `S[k%len(S)], H[k%len(H)]` — both axes vary from the first pair, no clustering on one stem), and serializes `json.dumps(sort_keys=True, ensure_ascii=True) + "\n"`. `ensure_ascii=True` (the extractor default) escapes the kits' macrons/diacritics to `\uXXXX` → pure-ASCII output, dodging every UTF-8/cp1252 mojibake gotcha. Per-campaign name SELECTION (Stage 6) is the part that uses `WorldGenRng`; the bank itself carries no RNG.

- **Lean on authored content; assemble only what the kits genuinely lack.** The kits already hold finished title ladders, deity renames, and seed name stocks — pass those through verbatim (`titles`/`religion`/`patterns`/`morphology` blocks + seed `personal_m`/`_f`/clan/epithet/flagship carried into the categories). The build's real generative value-add is the two things kits do NOT enumerate: **settlement compounds** and **transparent feature names** (modifier-root + feature/settlement-word via the generic euphonic `compound()` — the per-culture `compounding_rule` is authored as PROSE, not machine-executable, so a generic elision/dedup rule is used and the LLM curation pass polishes register). Plus light top-ups: re-gendered personal counterparts (strip a known male ending, append a female one), kinship-marker patronymics, and `the [Adjective]` epithets. Harvest the concrete authored EXAMPLES embedded in `banks_patterns` (`'Wave-Wolf', 'Storm-Raven'` / `desc: Victrix, Aquila`) for ship/tavern/military/dungeon rather than inventing filler — and reject any example carrying an unfilled `[slot]` BEFORE stripping brackets (else `the Howe of [name]` → dangling `the Howe of`, and the template `The [Adjective] [Noun]` → bare `The`).

- **Gendered suffix endings are NOT universal — do not gate on them.** Many cultures gender names semantically (East Asian: "auspicious martial meanings"), by prefix (Mayan `Aj-`/`Ix-`), or by filiation (Nguni `ka-`) rather than by suffix; `gendered_endings` legitimately yields empty parsed arrays for them. The §14 people-name convention (order + ≥1 surname source) lives in the kit and is what's required. The validation gate is: CORE categories (personal_male/female, clan_house, epithet, settlement, feature) ≥ 10 each (≥ the spot-check's "10 per category"), no case-insensitive dupes, a family base inherited, a title ladder with ruler titles, and NO `exonym` field anywhere (endonym-only, §12).

- **Freshness gate = the tool's own `--check`, shelled out from GDScript (§7.4.4 pattern).** `test_setting_name_banks.gd` runs `python tools/build_name_banks.py --check` (the diff + validation live in Python, never re-implemented in GDScript) plus on-disk/loader sanity. `--check` flags missing/changed/ORPHANED banks (a deleted kit must drop its bank) and any validation regression. After editing a kit OR the build tool, re-run `python tools/build_name_banks.py` and commit the regenerated `data/name_banks/`.

- **Banks carry a `lexicon` passthrough (added Stage 6).** Each bank includes the realized per-culture `lexicon` (`feature_words`/`settlement_words`/`adjectives`/`resources`/`directional`; beastman = `concepts`+`feature_words`) so runtime naming (§82) is bank-self-contained — subtype→recipe feature names, transparent templates, and on-the-fly compounds — without re-loading the conlang kits at play time (the §13 "pure lookup" goal).

## 82. Layer-5 runtime naming + idempotent setting writers (2026-06-13) [PROVISIONAL]

Stage 6 (handoff §6; gdd-region-painting.md §3.3/§5/§6; gdd-naming-conventions.md §4/§6.3/§7) fills every empty name column the earlier layers leave. Split: `NameAssembler` (pure, deterministic composition over a bank + rng + used-set — no DB/ctx, fully unit-testable) and `NameGenerator` (the Layer-5 orchestration over ctx). `_run_naming` calls `NameGenerator.new().run(ctx)` then re-persists the tables it mutated.

- **The history sim does NOT name realms — Layer 5 does.** `sim_polities[].name` is empty after Stage 4 (the sim sets ruler_class/level/morale, not names). Naming-conventions §6.3 "realms emerge from the sim and are named by convention" means the realm ENTITY emerges in the sim; the NAME is assigned here (domain title over a root: capital / people-`toponym` / `House <dynasty>`). Don't look for realm names in the Stage-4 output — generate them.

- **Idempotent upsert writers so a later layer fills columns it owns.** `save_polities`/`save_settlements`/`save_events`/`save_ruin_seeds`/`save_fallen_polities`/`save_regions` now pass `replace=true` to `_bulk_insert` (INSERT OR REPLACE on the `(campaign_id, id)` PK), matching `save_hexes`. Layer 4 still `clear_sim_output`s first (REPLACE-into-empty == INSERT, so its behavior is unchanged); Layer 5 re-saves the in-place-mutated rows to fill name columns without a clear/duplicate dance. **`setting_regions` is NOT a sim-output table** (`clear_sim_output` never touches it — Phase 1 wrote it at Layer 3), so Layer 5's `save_regions` is its only update path; a plain re-INSERT there would PK-collide, which is why the upsert change was required.

- **Significance re-score needs no stored prominence.** §3.3 `significance = clamp(0.45·size + 0.35·prominence + 0.20·context)`. Phase 1 stored `0.45·size + 0.35·prominence` (max 0.80 — the clamp is a no-op, and `prominence` is discarded, not persisted). So Layer 5 reproduces the formula exactly as `clamp(stored_sig + 0.20·context, 0, 1)` — never re-derive prominence. `context = 0.5·(≥2 owner/adjacent cultures over the region's hexes+ring) + 0.5·(a qualifying historical event, sig ≥ 0.60, intersects the region)` — two binary factors.

- **Name-origin priority + the caps (process by significance DESC so majors claim budgets first).** Per region: historical override (a qualifying event intersects AND the map-wide budget `max(1, hexes/100)`, 1 per region) → for terrain clusters only, hydronym-derivation (an overlapping NAMED hydronym whose sig exceeds the cluster's by ≥ 0.10, capped at ≤ 25% of clusters) → descriptive/cultural (default, a subtype-matched `feature` name from the dominant culture's bank). Name non-cluster regions FIRST so hydronyms exist as donors before clusters borrow them. Multilingual `name_alternates` only when sig ≥ 0.65 AND ≥ 2 adjacent cultures (each adjacent culture draws the feature from its OWN bank — the locked "each culture names the feature" model, not literal translation). Fallen-polity reaches are `historical_cultural` regions named "the Old <Toponym> Reach" — the ONLY live-culture toponyms, exempt from the override cap, themselves capped `max(3, hexes/100)` on the largest heartlands (≥ 4 hexes).

- **Fallen polities carry no culture_id — recover it.** `setting_fallen_polities` is `[polity_id, toponym_root, hexes, era_tick]` (no culture). Build a `polity_id → culture_id` map from the ruin seeds' `provenance_culture_id` (and depopulation/conquest events' `culture_ids[0]`) to resolve the fallen culture's `toponym` (via `CultureCatalogLoader.toponym`).

- **Stage 6 WorldGenRng streams (extend the §80 registry).** `settlement_name` (keyed `stl_id`), `polity_name` + `dynasty_name` (keyed `pol_id`), `region_name` (keyed `region_id`, and `"region_id|culture_id"` for each alternate), `ruin_name` (keyed `ruin_id`). Per-entity keying so iteration order never affects a name; a shared `{culture_id: {name_lower: true}}` `used` dict dedups within a campaign and qualifies (Upper/Lower/Great/Little, §5.6) on pool exhaustion. Name columns ARE in the determinism hash (§80), so every draw MUST be seeded — a green hash test + the Stage-6 two-run determinism test prove it.

- **Roads are NOT named at Layer 5 — the network doesn't exist yet.** Region-painting §6 road naming needs the road network, built in Layer 6 (Stage 7, setting-gen §9.2). No `road`-layer regions exist at Layer 5, so `NameGenerator` skips them; a Stage-7 follow-up pass reuses `NameAssembler` once roads are built (handoff: "run before final road naming or iterate once").

- **Terrain-cluster families key on biome, with an enclosed-low BASIN; plateau is DEFERRED (region_painter §4.2).** `_cluster_family`: mountains → `range` (trumps cover); then by biome — woods/jungle → `forest`, desert → `desert`, swamp → `swamp`, clear → `plains`. A flat-band `plains` COMPONENT is promoted to **basin** when `_is_enclosed_basin` holds (≥ 0.6 of its deduped land-ring is hills/mountains — a low enclosed clear-cluster; an unringed/coastal one stays plains; component-level so a basin's interior doesn't fragment; deterministic — the ring is a set). **Do NOT equate `hills`+clear with plateau** (a 2026-06-13 mistake Jedidiah corrected): the elevation tag (`mountains`/`hills`/`flat`, from `elevation_raw` magnitude) is a height/roughness proxy — `hills` = rugged moderate terrain, NOT flat high ground. A real plateau is flat-at-high-elevation, which needs a LOCAL-FLATNESS measure (low `elevation_raw` variance across the ring) gated on high `elevation_raw`. `elevation_raw` is already persisted per hex, so that is a future flatness-pass (with threshold tuning + plateau-vs-range resolution), not a persistence change. The naming side is pre-wired — `name_assembler.gd` `_SUBTYPE_FEATURE_KEY` already maps basin→vale (and plateau→plain, dormant until detection lands), so adding the family later needs no Stage-6 change.

## 83. Settlement stocking: rank-size model grounded in RAW density (2026-06-14) [PROVISIONAL]

Layer 6 §9.1 (`infrastructure_generator.gd` `_reconcile_settlements` → `_stock_realm`) derives the 24-mile campaign map's settlements from RAW demographic primitives, NOT the quick-stocking placement table (that table is a GM shortcut assuming one frontier density; the generator scales density with each realm's actual population). See gdd-setting-generation.md §9.1.

- **RAW primitives (all confirmed).** 5 people/family (`acore_axioms_strongholds_and_domains.xml:106`); 24-mile peasant caps 2,000 / 4,000 / 12,480 by territory class (`:156-160`, = 16× the 6-mile 125/250/780; densities 20/40/125 ppl·mi⁻²); ~10% urban + largest settlement = 20% of urban (`acore-setting-construction-rules.xml:161-176`); market class by urban families I≥20,000 / II≥5,000 / III≥1,750 / IV≥600 / V≥250 / VI<250 (`acore-campaign-hijinks.xml:632-638`, = the `_MARKET_*` consts). The "~15 settlement points per region" budget (`acore-setting-construction-rules:412`) is for the finer 6-mile REGIONAL map, not the 24-mile campaign map — don't anchor 24-mile density to it.

- **Variable urban fraction.** `f_u = 0.05 + 0.15·dev`, `dev` = mean territory-class weight over the realm's hexes (civilized 1.0 / borderlands 0.5 / wilderness 0.0). Agrarian frontier realms 5%, fully-civilized 20% — the `acore:186-189` adjustment, derived from development because the culture catalog has no urbanism axis (Jedidiah ruling 2026-06-14: vary 5–20% by advancement).

- **Rank-size (Zipf, exponent 1) per realm.** Settlement of rank r has `urban_families = bankers_round(A / r)`, `A = 0.20 · (f_u · realm peasant)`. Count above a threshold T = `floor(A / T)`. The 24-mile map persists ONLY Class III+ (`T = _MARKET_III = 1,750`), EXCEPT a realm whose largest (= its capital) is Class IV shows that one seat (`count < 1 → count = 1`; Jedidiah ruling: "Class IV allowed iff it is the realm's largest settlement and capital"). `A < _MARKET_IV (600)` → no mapped settlement (folds into the hex's rural aggregate; materializes on a future 6-mile zoom at T=250). Observed on the small test map: ~11 settlements (8 Class III + 3 Class II) over 180 hexes — the seat exception is a safety net that need not fire when realms are large.

- **The sim's per-hex emergence is a PLACEMENT SIGNAL, not the settlement set.** `history_simulator._emerge_urban` scatters a record per hex; Layer 6 keeps only the max-per-hex `urban_families` to RANK candidate hexes (capital = rank 1; secondaries = top-signal non-capital hexes ≥ 2 apart, `_CITY_SPACING`). Sizes come from the rank-size curve, not the scatter. This retired the prior one-settlement-per-hex scatter (which, compounded by stale cross-ownership records over 160 ticks, produced ~548 phantom hamlets per region) and the §9.1 "top up with Class V–VI hamlets" rule.

- **Aggregate hexes from `hex_grid.owner_polity_id`, NOT `pol["hexes"]`.** The exported polity rows (`history_simulator._polity_rows`) carry `capital_q/r` + `culture_id` but NOT a hex list, and include ONLY alive polities. So Layer 6 builds the owner→hexes partition from the hex grid (the authoritative source roads/forts also use) and does NOT test a (nonexistent) `alive` flag. Reading `pol["hexes"]` or `pol["alive"]` off an exported row yields empty/false → **zero settlements** (the bug that surfaced 2026-06-14: only the `size()>0` checks failed, ~3 failures, masking that the whole set was empty).

- **Settlements are REPLACED at Layer 6, not upserted — atomically.** §9.1 rebuilds the set (different rows/count, not an in-place column fill), so `_run_infrastructure` calls `SettingRepository.replace_settlements`, which is `_bulk_insert(..., replace=true, clear_first=true)`: the DELETE and the inserts run in ONE transaction. A naive "DELETE (autocommit) then `_bulk_insert`" is a data-loss bug — `_bulk_insert` opens its own transaction and early-returns on empty rows, so an empty rebuild or a failed insert leaves the table permanently wiped. The §82 idempotent `save_settlements` upsert (still used by Stages 4/6) would instead leave the stale Stage-4 scatter rows orphaned — that produced ~1,400 spurious failures before the switch. `clear_first` performs the campaign-scoped DELETE inside the transaction, BEFORE the empty-rows skip, so a zero-settlement world clears safely and atomically.

- **City hexes are validated against the realm's CURRENT ownership; the capital can be stale.** A realm can stay alive after losing its capital hex to a conqueror, and the sim never relocates `capital_q/r` (history_simulator anticipates exactly this with its `lost_capital` check). So `_rank_hexes` ranks only the realm's OWNED hexes (the `hex_grid.owner_polity_id` partition) and uses the capital as rank-1 ONLY when the realm still owns it — otherwise its best owned hex becomes the de-facto seat. An unvalidated capital would place a city on a hex another realm owns → cross-realm hex collision → `_settlement_row` reusing the same `sim_by_hex[hex].id` for both → `INSERT OR REPLACE` silently dropping one (a 2026-06-14 review finding). Likewise `_settlement_row` reuses the sim row's id/name ONLY when `sim.polity_id == pol.id` — a hex urbanized by a former owner carries that polity's culture name, so a conquered city would otherwise wear a mismatched-culture name; `emergence_tick` (real urban age) is reused either way.

- **Every persisted setting_* table must be in BOTH `SettingRepository._DATA_TABLES` AND `SettingDatasetHasher._table_specs()`.** The savegame-scoping registry (`CampaignRepository._SCOPE_DIRECT_CAMPAIGN`) and the §80 determinism hash are independent gates; `setting_roads`/`setting_fortifications` (migrations 157/158) were added to the former but omitted from the hasher, so the Layer-8 world_hash silently excluded all road/fort output (a 2026-06-14 review finding). When you add a `setting_*` table, register it in all three.


## 84. World map renders into a SubViewport anchored above the status bar (2026-06-24)

The wilderness hex map (`scenes/maps/hex_map.tscn`, a `Node2D` + `Camera2D`) renders into a `SubViewport`, NOT straight into the root window viewport. In `scenes/Main.tscn` the tree is:

    WorldViewport (SubViewportContainer; scenes/maps/world_viewport_frame.gd; full-rect; stretch=true)
    └── WorldSubViewport (SubViewport)
        └── HexMap (Node2D — the wilderness renderer + its HexHUD CanvasLayer)

- **Why.** `SessionStatusBar` is a `CanvasLayer` (layer 80) drawn over the root viewport; rendering the map full-screen meant the map drew, took clicks, and centered its camera in the strip hidden behind the bar (buried context menus, off-center "focus on party"). The SubViewport's render area is sized to `window − bar`, so none of that happens.
- **`stretch = true` resizes the viewport; it does NOT scale the image.** The `SubViewportContainer` sets `SubViewport.size = container.size`, so the `Camera2D` shows more/less world at the same zoom. Never rely on image scaling for fit.
- **The frame tracks the bar via a signal, not a hard ref.** `SessionStatusBar` emits `EventBus.bar_height_changed(height_px: float)` on every drag / height-state change / show-hide / window resize; `height_px` is the bar's occluding height (0 when hidden) and is also readable directly via `SessionStatusBar.get_effective_bar_height()`. `world_viewport_frame.gd` sets `offset_bottom = -height_px` (anchored full-rect, so a negative bottom offset lifts the bottom edge to the bar's top).
- **Anything reading the visible rect now gets the above-bar area for free.** Inside the SubViewport, `get_viewport().get_visible_rect().size` and the mouse position are SubViewport-local, so camera centering/limits (`hex_map_renderer.gd`) and the context-menu on-screen clamp (`dungeon_context_menu.gd` `_show_options`) need no bar-aware math.
- **New world surfaces mount into a bar-tracking frame, not the root.** Two frames exist:
  - *Wilderness* — the static `WorldViewport` (authored in Main.tscn) wrapping the 2D HexMap.
  - *Dungeon* — built in code by `dungeon_explore_state.enter()`: a `world_viewport_frame.gd` `SubViewportContainer` (`stretch=true`) → `SubViewport` (`own_world_3d=true`, `handle_input_locally=true`) → the dungeon `Node3D` (`_scene`), pushed through `NavigationStack.push_node` so push/pop/fade lifecycle is preserved. `own_world_3d` because the dungeon carries its own Camera3D / DirectionalLight3D / WorldEnvironment (same as the combat map, `scenes/ui/combat/combat_screen.gd`). `_scene` stays the renderer reference and all `DungeonHUD/...` children render inside the SubViewport, so they clip above the bar.
  - Renderers' input survives in either frame: clicks go through the container's GUI forwarding; keyboard pan polls the `Input` singleton in `_process`.
- **A bar-tracking frame must be HIDDEN when its surface isn't the active context** — otherwise its SubViewportContainer draws an opaque (cleared) rectangle over whatever renders behind it. The dungeon frame is hidden automatically (the nav stack hides obscured/popped nodes). The static wilderness `WorldViewport` is NOT nav-managed, so `wilderness_explore_state` enter/exit toggles `runner.get_world_viewport().visible` — without this, the wilderness frame covers the 3D dungeon (the regression that surfaced when the dungeon got its own frame). `transparent_bg` is NOT a fix: the container still eats input even when transparent.
- **`session_runner.gd` resolves the renderer with `get_parent().find_child("HexMap", true, false)`** and the frame with `find_child("WorldViewport", true, false)` (recursive) so the lookups survive the reparenting; don't revert to fixed `get_node(...)` paths.

## 85. Base/hybrid culture model — only BASE cultures seed (2026-06-29) [PROVISIONAL]

The culture-emergence model (gdd-culture-emergence-and-territory.md §3; docs/handoff_culture_emergence_build.md Phase 1) splits human cultures into **11 BASE cultures** (the only ones ever seeded) and **first-order HYBRID cultures** (emerge at runtime where two bases meet — Phase 4, never seeded). The old per-member human kits (alani, cuchulan, hammuran, …) are now redundant with the bases.

- **Seeding gate is a DATA marker, not a hardcoded id list.** Each base mechanical kit (`data/cultures/<base>.json`) carries `mechanical.identity.culture_class = "base"`; the accessor `CultureCatalogLoader.culture_class(record)` defaults to `"member"`. `CultureSeeder._select_cultures` restricts the **human** candidate pool to `culture_class == "base"` (via `_candidate_pool(..., bases_only=true)`); demihuman/beastman selection is unchanged. **`culture_class` has THREE values: `base` | `hybrid` | `member`.** Hybrids (§3.6, Phase 4) are STATIC `data/cultures/<id>.json` kits carrying `culture_class = "hybrid"` + `identity.culture_synthesis_parents = [base_a, base_b]`; because `bases_only` excludes anything `!= "base"`, hybrids never seed — they live in the catalog only to be looked up by parent-pair when a merge emerges them (NO runtime synthesis). The 40 legacy single-culture member kits were physically RETIRED 2026-06-29 (data/cultures + data/conlang + data/name_banks all deleted) once confirmed they were never seeded (human seeding = bases only) and never referenced by hybrids (`synthesis_sources` use `BASE_01..11` + the `elvish`/`dwarven`/`beastman` families, never member ids) — a pure no-behavior-change cleanup, exactly as predicted. Don't reintroduce member-id allowlists or re-add member kits. (Two hardcoded `else "agrippan"` fallbacks in `name_generator.gd` / `infrastructure_generator.gd` were repointed to the base `albawyn`.)
- **Base mechanical kits are DERIVED from the member each base "reuses"** (named in the base's conlang concept note): copy the member's mechanical scalars, then override identity (`culture_id`/`demonym`/`toponym`/`csv_id`/`culture_class`, drop `synthesis_sources`), set `civ_or_clan` per GDD §3.2 (FIXED: the 3 clan bases = thiodons/albawyn/wendaki; the other 8 = civ), force `alignment.allowed` = all three (§3.7), rewrite `terrain.seed_biomes`, and point `flavor.name_bank_key` at the base. Scalars are PROVISIONAL (engineering authority) — tune later.
- **The 11 base names were overhauled 2026-06-29 (Jedidiah, naming pass):** Quirium→**Vallica**, Thiodmark→**Thiodons**, Hellaspol→**Ellinike**, Shinarur→**Shamhar**, Tollanaz→**Tollteca**, Manitland→**Wendaki**, Huaxia→**Qinzhao**, Hinowa→**Yamatsu** (Albawyn / Aryastan / Kemetra unchanged). `BASE_0N` slots are stable; only the names moved. A base-name change ripples to: the base kit + conlang kit + bank (rename all three), `BASE_CSV` in `tools/generate_hybrid_kits.py` + `tools/name_hybrids.py` (incl. the hardcoded `brythald` pair), every hybrid's `culture_synthesis_parents` (re-run `--generate` for the 46; patch the 9 authored by hand), and any test/doc references. A culture's NAME ≠ a place-suffix: demonym names the PEOPLE (Thiodons), toponym names the LAND (Thiodmark) — `-mark`/`-gard`/`-heim` belong only on toponyms.
- **All 55 hybrids were renamed to rules-based people-names 2026-06-30** (Jedidiah's naming pass; method + full old→new table in `gdd-hybrid-conlang-fusion.md` §5: Conquest = conquered civ re-voiced in the conqueror clan's register+people-ending; Peer = coined shared-trait word from both parents' lexemes; Confederated = coined "people/nation" word; NO real deity names or verbatim ethnonyms; demonym names the PEOPLE not the place). `brythald` kept. **To rename a hybrid, the id must change in TWO coordinated places: the conlang FILENAME stem (`generate_hybrid_kits.py`'s `pair_map` reads the id from the filename) AND the conlang's internal `kit_id` field (`build_name_banks.py` keys banks off `kit_id` and expects filename==kit_id).** Mechanics that worked: (1) flip conlang `kit_id`+rename file; (2) the 46 GENERATED kits — delete the old mech file, update the generator's `RECOVERED` set to the NEW ids, re-run `--generate` (demonym=`id.capitalize()`, all prose templated from the id, so they rebuild correctly); (3) the 9 RECOVERED authored kits — rename+hand-patch identity/`name_bank_key`/prose only (preserve authored mechanicals); (4) demonyms with punctuation (Ch'ulet) need a post-generate override since the generator can only produce `id.capitalize()`; (5) delete ALL `data/name_banks/*.json` + rebuild (the builder does not prune orphans; `--check`/`SettingGenerationDataFreshness` flags leftovers). Toponyms (the LAND, from conlang `homeland`) are preserved across a people-rename — do NOT blanket-replace the old name in conlang prose or you corrupt `homeland`. `culture_synthesis_parents` reference BASE ids (stable), so hybrid renames never touch parent-refs.
- **Seed-biome matching is SUBTYPE-resolved** (`CultureSeeder._hex_matches_term`, GDD §4.1): `forest`→`woods`+subtype `""` (plain), `taiga`→`forest_taiga`, `dense forest`→`forest_dense`, `grassland`→`clear`+(`""`|`clear_grassland`), `savanna`→`clear_savanna` — NOT the old loose `woods`→any / `clear`→any collapse. This is what lets the §4 caps and the stricter base seed_biomes (humans seed only developable clear/plain-forest/taiga — never dense-forest/jungle/desert/tundra/swamp/glacial-or-volcanic mountains) have well-defined source states. `clear_steppe`/`clear_scrub` are **Phase-2 deforestation products, not painted at seed time** — their match arms exist but hit nothing on a fresh map.
- **Name-bank corpus is 82** (11 bases + 55 first-order hybrids = all 11C2 base pairs + 6 demihuman + 10 beastman; the generic `beastmen` culture is bankless by design — the fallback excludes it). Was 122 before 40 legacy single-culture member kits were retired (2026-06-29). **Note:** 9 of the 55 hybrids (HYB_16/19/21/22/35/43/49/50/55 — shidhean, senecar, sumset, sargonid, ptolan, serican, thracan, ryujin, tikan) were authored in the OLD style (mechanical kit + conlang + `HYB_NN` csv_id with `synthesis_sources` `BASE_a/BASE_b`); the retirement's member-heuristic (mechanical kit + human + no `base` marker) wrongly swept them, and they were RECOVERED from git — conlang kit + bank, then their legacy mechanical kits too (re-adjusted to `culture_class="hybrid"` + all-three alignment + `culture_synthesis_parents`; they become 9 of the 55 static hybrid kits per §3.6). **When retiring "members", first exclude any kit whose `csv_id` starts `HYB_` — those are hybrids regardless of whether they carry a legacy mechanical kit.** `tools/build_name_banks.py` auto-discovers every `data/conlang/culture_*.json` (1:1 → bank), so retiring a culture = delete its conlang kit + its `data/name_banks/<id>.json` (the build does NOT prune orphans) + its `data/cultures/<id>.json`, then re-run the build (rewrites surviving banks + manifest `count`). `test_setting_name_banks.gd` `EXPECTED_BANK_COUNT` is a coarse tripwire; the `--check` freshness gate (§81) — which flags orphaned banks as drift — is the real authority. After adding/retiring any conlang kit, re-run the build and commit `data/name_banks/`. When a test needs a representative bank, use a surviving culture: a base for single-family/classical (e.g. `vallica` — the renamed Quirium — carries Imperator/Marcus/classical), a HYBRID for a 2-family cross-blend (e.g. `arjungs`).

## 86. Territory gating + deforestation + expansion constraints (2026-06-29) [PROVISIONAL]

The §4 biome/race territory cap, the §5 deforestation transitions, and the §5.1–5.3 peaceful-expansion constraints (gdd-culture-emergence-and-territory.md; handoff Phases 2–3). The cap makes forest/mountain/jungle hexes cap below Civilized; deforestation is the escape valve that clears forest so it can civilize; the expansion constraints (terrain preference, natural borders, overseas colonization) shape WHERE realms grow.

- **`TerritoryCap.effective_cap(biome, subtype, elevation, race, river_or_coastal)`** (`engine/.../world/territory_cap.gd`, pure) returns the MAX classification a hex can reach, read through the dominant culture's RACE (§4.2 human / §4.3 dwarf / §4.4 elf). Callers `min()` it against the population-gated class — it only CAPS, never raises. Use `TerritoryCap.allows(cap, target)` to gate advancement. Applies to civ + demihuman cultures; **clanholds are clamped to wilderness separately** (`_demote_to_clanhold`) and never reach the advancement path. The §4.2 desert cradle exception keys on river/coastal incidence (`HistorySimulator._river_incident`, built for ANY river width).
- **The cap is read on the hex's CURRENT biome.** Deforestation changes the biome, which changes the cap on the next read — so the cap and the §5.2 transition are not in conflict (a forest's Borderlands cap is a transition TRIGGER, not a permanent ceiling).
- **Graduated deforestation is a TIMED cost, persisted per-hex.** `setting_hexes.clearing_progress` (migration 178; a column, NOT a side table — 1:1 per hex, mirrors `original_biome`, auto-hashed via `HEX_COLUMNS`). Every in-memory grid hex carries it from `geo_field_to_grid` (the `_bulk_insert` "fail loudly on missing key" rule means hand-built `setting_hexes` fixtures must include it). `Deforestation.next_step(biome, subtype, koppen)` (pure) owns the §5.2 step (dense→plain forest→clear; taiga/jungle→clear) and the §5.3 climate→subtype map (keyed on persisted `koppen`); the caller owns the per-tick accrual + thresholds (`SimConstants.clear_ticks_step=20`/`clear_ticks_jungle=30`/`clear_rate_base`).
- **`HistorySimulator._phase_deforestation` (sim-time, 24-mile) is one integration point; a runtime EventScheduler phase (6-mile gameplay) is the other (deferred).** A hex clears only while it is FULL for its class but biome-capped below the next class (`not TerritoryCap.allows(cap, next)`), human-dominant, in a non-clanhold polity. Sim-time uses a UNIFORM `+1/tick` — the §5.4 `+2`-near-market-class-III accelerator is a runtime feature (market class is a Layer-6 output, assigned AFTER the sim). Deterministic: no RNG, fixed threshold.
- **Reforestation reuses the SAME `clearing_progress` counter, in reverse** (`HistorySimulator._phase_reforestation`, after deforestation; `Deforestation.reforest_target`). Per hex per tick only one direction acts (deforestation = human pop>0; reforestation = pop==0 natural OR elf-dominant held), so the shared counter is unambiguous except on plain forest (clear-down vs elven-regrow-dense), disambiguated by actor. **Only a was-forest clear hex regrows** (`original_biome` set) — virgin grassland never afforests, even for elves. Natural ceiling = the climate's non-dense climax (taiga for cold, else plain forest), needs a target-biome NEIGHBOR; elves restore the dense/jungle climax with NO neighbor. Sim-time elf rate is uniform `+2` (the `+3`-near-elven-settlement is a runtime feature). At-climax / non-regrowing hexes instead DRAIN any in-progress clearing (the "reverse in-progress" case).
- **Expansion terrain preference (§5.1/§4.6) biases ORDER, not amount.** `TerritoryCap.is_hard_excluded` (§4.6 race exclusions) + `TerritoryCap.terrain_rank` (biome-dominates-elevation soft order) feed `HistorySimulator._expansion_preference`, which multiplies each frontier hex's `mult` in `_compute_frontier` by `cap_weight × terrain_rank`. PEACEFUL expansion only — `_resolve_contest` strength and `_phase_war` are untouched. **Keep the cap-weight gradient GENTLE** (`expansion_pref_wilderness ≈ 0.55`, not a harsh 0.2): forest/mountain is wilderness/borderlands-capped but is the *path* to civilization via deforestation, so a harsh penalty makes realms refuse it and the map collapses to mostly-unowned. The boxed-in budget-reduction valve must fire ONLY for genuinely §4.6-excluded-bound frontier (threshold just above `expansion_pref_excluded`) — a broader trigger death-spirals (throttled realms shrink → less size-scaled budget). The preference improved the calibration (wilderness 73% → 58%, toward the §17 target). **Beware `var x := <expr containing Dictionary.get()>`** — it's a Variant-inference parse error that silently fails the whole script compile; type it explicitly.
- **Natural-border river resistance (§5.2) is CONTEST-ONLY, by hard-won calibration.** `HistorySimulator._build_river_barriers` builds `_river_edge_any` ("q,r,e" → true for EVERY river edge, both widths, both directions — distinct from the navigable-only `_river_barrier` diffusion set). `_compute_frontier` damps a frontier hex's `mult` by `SimConstants.natural_border_resistance_river` (≈0.5) **only when the hex is enemy-owned AND reached only across a river** (`_river_free_approach(pid, n)` is false) — NOT when it is empty land to settle. **This scope is critical:** damping empty-land settlement across rivers strands trans-river wilderness unclaimed on the finite-tick history sim and regressed the §17 coverage target ~4pts (Large×12: wilderness 58.6→62.4, unowned 24.4→27.3); restricting the damp to inter-realm border contests keeps coverage at the 3a baseline (wilderness 59.2, unowned 24.8) while mature borders still settle onto rivers via stabilization. Coast needs no multiplier (land can't cross ocean); mountain spines rely on the §4.6 elevation preferencing (handoff §5.2 omits explicit mountain gating). War (`_phase_war`) is exempt.
- **Consolidate-before-expand gate (§5.2):** `_is_border_bounded(pol, frontier)` (the realm has NO river-free developable open SETTLE target left and either abuts a river-crossed frontier or sits on a coastline — a realm merely enclosed by enemy land is a WAR situation, not this) + `_is_saturated(pol)` (≥`saturation_hex_fraction`=0.75 of the polity's POPULATED hexes at ≥`saturation_pop_fraction`=0.50 of their CURRENT-biome cap `cap_for(_hex_territory_cap)` — the present biome's ceiling, NOT the post-deforestation one) gate a budget reduction in `_expand_polity` (`consolidate_rate`=0.5, kept >0 so a river is never a HARD border). The gate fires RARELY precisely because the resistance is contest-only (empty land stays freely claimable → realms are seldom border-bounded), so it is coverage-neutral in practice. **Coverage policy (Jedidiah 2026-06-29): do NOT weaken this gate to chase the wilderness target** — if maps come out too wild, raise ascendant-polity pop growth instead. Determinism: all three helpers iterate fixed-order Arrays / `range(6)`; `_river_edge_any` is `.has()`-only, never iterated.
- **Overseas expansion (§5.3) reuses `sea_lane_range` as the SINGLE governing distance** — the crux that makes the war-split rule fall out for free. `_precompute_sea_lanes` builds `_sea_lane_neighbors` (static: each coastal land hex → the coastal hexes within `sea_lane_range`=10 sharing an ocean, via the SAME `_hex_distance ≤ range` + `_shared_ocean` test `_connected_components` uses). `_compute_frontier` then adds, for each POPULATED owned coastal hex, its EMPTY sea-lane-neighbour coastal hexes as overseas settle entries (`overseas=true`, land-frontier processed first so land-adjacent targets win the `seen` dedup), weighted by a soft distance-decayed `_sea_cross_factor(d)` (`sea_cross_base·sea_cross_decay^(d-1)`). Colonization of EMPTY land only — no amphibious contest (that is war). **Because overseas reach == the contiguity sea-lane range, a colony is bridged to its parent while linked (≤10, shared ocean → same `_connected_components` component → never severed) and AUTO-SECEDES the instant war stretches its nearest link past the range** (it drops out of the capital's component → `_phase_contiguity` sheds it: secede if sea-isolated ≥`contiguity_min_secede_hexes`, absorb if land-surrounded by the conqueror, revert-to-wilderness if a lone hex). **No stored sea-link marker** (the handoff's suggested marker is redundant — connectivity is recomputed live from geometry every tick). New colonies are wilderness-CLASS frontier, so heavy-coastline seeds show higher wilderness % — expected, not a carpet (Large×12: +5pt wilderness, concentrated on archipelago seeds; civ/realm counts flat). Beastmen never reach `_compute_frontier` (skipped in `_phase_expansion`), so only realm-builders colonize.

## 87. Hybrid emergence — border merge (Phase 4c, 2026-06-30) [PROVISIONAL]

First-order hybrids emerge at runtime into the culture SUBSTRATE where two base cultures meet (gdd-culture-emergence-and-territory.md §3.3/§3.6; gdd-hybrid-conlang-fusion.md §6.4). 4c is the peaceful-BORDER merge; conquest merge + polity persistence is §4d.

- **The parent-pair → hybrid lookup lives in the CATALOG, built at load time.** `CultureCatalogLoader.hybrid_for_parents(a, b) -> String` scans `culture_class=="hybrid"` records' `culture_synthesis_parents` into a cached, order-independent map (`_pair_key` sorts the pair). No separate definition-table file (§3.6). Returns `""` for an unknown pair, `a==b`, or a non-base input. `clear_cache()` resets it alongside the record cache. `culture_class` now has THREE values (`base | hybrid | member`); `culture_synthesis_parents(record)` is the accessor.
- **Hybrid culture INSTANCES are built eagerly at seed, for all 55 — seed-EXCLUDED as polities but present for lookup.** `CultureSeeder` loops the catalog after the seeded instances and `_jitter_instance`s every hybrid record into `ctx["culture_instances"]` (deterministic — per-culture RNG stream keyed by cid, so it never perturbs the seeded cultures' jitter; inert until a merge grows the weight). This is why Stage3's `test_culture_instances_jittered_within_bounds` now also bounds-checks the hybrids. The instance carries `culture_class` + `language_family` (added for §4c: base-identification + the shared-family merge bonus).
- **`HistorySimulator._phase_hybridization(tick)` grows the hybrid into a SEAM via the existing `_lerp_toward`** — runs after `_phase_substrate` (diffusion has mixed the border) in BOTH tick paths. A seam = a land hex whose top-two DISTINCT human-base weights (`_top_two_bases`, deterministic weight-desc/id-asc) are each ≥ `hybrid_seam_threshold`. On a locked MERGE it does `_culture_w[key] = _lerp_toward(w, hyb, hybrid_merge_rate)` (sum-preserving: scales others by 1−rate, adds rate to the hybrid even when absent). **SUBSTRATE ONLY** — no polity `culture_id` flip, and assimilation/diffusion/expansion are UNTOUCHED (the hybrid reaches a small seam equilibrium against assimilation's counter-pull; domination/persistence is §4d). This isolation is deliberate for calibration safety — the phase only ever ADDS a human-race minor culture at borders, so classification/territory dynamics are unmoved (verified baseline-neutral: 478/16 = prior 477/16 + the new suite).
- **Merge is decided ONCE per base-pair and LOCKED** (`_merge_decisions["a|b"] -> "merge"/"displace"`, canonical `a<b`). The draw is tick-INDEPENDENT (`WorldGenRng.stream(seed, "hybridize_decide", 0, pkey)`), so the outcome is a stable property of (seed, pair) revealed on first contact — not dependent on which hex/tick first hits threshold. **SCOPE (Jedidiah 2026-06-30): 4c merges SAME-CLASS pairs only** — civ×civ (Peer) and clan×clan (Confederated); a clan×civ (Conquest) seam is SKIPPED (`_civ_or_clan_of(ca) != _civ_or_clan_of(cb)`) because a peaceful border lacks the conqueror-over-subject the Conquest kit encodes and §6.4's clan-over-civ gate needs a clear winner — those emerge from conquest in §4d.
- **Merge probability is minimal + PROVISIONAL:** `hybrid_merge_base_p` × `hybrid_merge_family_bonus` when the two bases share a `language_family` (comma-split intersection via `_shares_language_family`/`_family_set`). The §3.3 parity + alignment drivers are DEFERRED to the §4e calibration pass. All four knobs (`hybrid_seam_threshold`/`hybrid_merge_base_p`/`hybrid_merge_family_bonus`/`hybrid_merge_rate`) are `SimConstants` `[PROVISIONAL]`, tunable via `tools/calib_sweep.tscn`.

**§4d — conquest merge + finalize relabel (2026-06-30):**
- **The CONQUEST trigger RETARGETS assimilation, not a new phase.** `_assimilate_held_hexes` — on a held hex carrying a foreign BASE substrate — computes a `culture_target`: default the owner, but if `_conquest_merge_target(owner, subject)` returns a hybrid, the hex assimilates toward HYB(A,B) instead (conquered/contested zones become the hybrid). §6.4 gate: a clan×civ pair merges ONLY when the OWNER (conqueror) is the clan (`oc != sc and oc != "clan"` → displace); same-class is symmetric. Reuses the §4c per-pair lock (`_merge_decisions`), so a pair resolves to the SAME hybrid/decision whether it first meets at a border (§4c) or a conquest (§4d). Alignment still assimilates toward the realm's own alignment.
- **REABSORPTION FIX — the actual Peer-realm mechanism (2026-07-01, the "small pockets reabsorbed" bug).** The conquest retarget grows a hybrid on a held hex only while the dominant NON-owner is still a foreign BASE. Once the hybrid ITSELF becomes the dominant non-owner, `_conquest_merge_target(base, hybrid)` returns `""` (a hybrid is not a base) → `culture_target` reverts to the owner BASE and assimilation ERODES the emergent hybrid back down, so a fusion never reaches whole-realm scale (the observed failure). Fix: when `_dominant_other_culture(_culture_w[key], owner)` is a hybrid whose `culture_synthesis_parents` include the owner's base, keep driving the hex toward THAT hybrid (`culture_target = subj`) instead of reverting. This is what lets Peer/civ hybrids consolidate to realms. **CIV-GATED (`_civ_or_clan_of(subj) == "civ"`):** a CLAN hybrid (Confederated clan×clan, or a clan-classified Conquest hybrid) must NOT consolidate — clan cultures are clanholds (`is_clanhold`), which clamp hexes to wilderness density and seat NO urban settlements (§5.3); a clan hybrid taking over a realm ERASES its settlements (observed on small/short seeds → 0-settlement worlds → materialization break). Clan hybrids stay SUBSTRATE (their §4c/§4d role); only civ fusions grow to whole-realm scale. Helpers: `_is_hybrid(cid)`, `_hybrid_has_parent(hyb, base)` (reads `culture_synthesis_parents` carried on the instance by `_jitter_instance` — no per-tick catalog lookup).
- **Realms are RELABELED to the hybrid at FINALIZE, never mid-sim (Jedidiah).** The sim runs on base ids; only substrate goes hybrid. `_finalize_hybrid_identities()` (first line of `_finalize`, before serialize/handoff) relabels any realm whose mass-weighted populated-substrate dominant (`_dominant_populated_culture`) is a HYBRID at ≥ `hybrid_adopt_min_share` (0.35 — a plurality, not a majority; the base core is entrenched so a hybrid rarely reaches an outright majority): `culture_id` → the hybrid, `culture_synthesis_parents = [base_a, base_b]`; base realms carry `[]`. Emits a `cultural_shift`/`hybrid_emerged` event. Runs at finalize → never perturbs the tuned mid-sim dynamics (calibration-safe).
- **Persistence gotcha — adding a `POLITY_COLUMNS` entry means updating EVERY polity-row builder that reaches `save_polities`.** `setting_polities.culture_synthesis_parents` (migration 179; JSON `[a,b]` or `[]`; the determinism hash carries it automatically since setting_dataset_hasher keys on `SettingRepository.POLITY_COLUMNS`). `_bulk_insert` FAILS LOUDLY on a row missing any column key (rolls back the whole insert → `save_polities` false → `generate()` false). There are TWO builders: `HistorySimulator._polity_rows()` (the sim/present-day output, saved at `setting_generator.gd:167/198`) AND the seeder's `_make_polity`/`_make_beastman_polity` (the tick-0 SEED snapshot saved at `setting_generator.gd:152`). Updating only `_polity_rows` (missing the seed builders) caused a full world-gen cascade — 100% wilderness, 0 polities, unnamed regions, ~20 red suites that looked unrelated to culture; **the tell is `_bulk_insert: row missing column '<col>'` in the log.** Seed polities are always base cultures → `"[]"`.

**§4e — realm emergence + calibration (2026-06-30, REVISED 2026-07-01):**
- **Hybrid REALMS emerge via the §4d reabsorption-fixed retarget → finalize relabel. GO-NATIVE ADOPTION IS INERT for hybrids — do not rely on it.** The 2026-06-30 belief ("realms emerge via go-native adopting the hybrid") was WRONG, and the seeder's `HYBRID_VIGOR` dev bump + a `hybrid_go_native_bonus` built on it did NOTHING (both removed 2026-07-01). Reason: `_developed()` is consumed ONLY in `_phase_go_native`, and `_subject_culture_share` returns a realm's dominant NON-owner culture by populated mass — always a BASE, because a hybrid is a thin seam, never the plurality subject. PROOF: cranking `hybrid_go_native_bonus` to 5.0 (certain-flip for any hybrid subject) left every seed BYTE-IDENTICAL. The working mechanism is entirely: §4d retarget grows a civ hybrid to a realm's populated-mass plurality → `_finalize_hybrid_identities` Case 2 relabels it. (`_finalize` keeps Case 1 — a realm whose `culture_id` is already a hybrid records its parents — but with go-native inert that case is now vanishingly rare.)
- **Hybrids manifest at two levels:** (1) SUBSTRATE / regions — border+conquest zones become dominantly a hybrid; Layer-5 region naming reads the dominant substrate, so the 55 hybrid name banks appear on regions even without a realm relabel. (2) whole REALMS — now "occasional-to-common" for CIV hybrids (~6.4/large map at `base_p`=0.2; clan hybrids never relabel a realm — §4d civ-gate).
- **Calibration via `tools/calib_sweep.tscn`** (hybrid_realms / distinct_hybrids / hybrid_dom_hexes / realms_hyb_plurality / max_hyb_share + per-culture owned-land shares). **`hybrid_merge_base_p` 0.5 → 0.2 (2026-07-01):** the reabsorption fix made hybrids viable at realm scale, so far fewer border-merges are needed; at 0.5 the fixed retarget OVERSHOT to ~15 realms and §17 broke (wild 43%). At 0.2: Large×8 mean ~6.4 hybrid realms, §17 in band (wild 52.1 / civ 73.9), distinct ~2.1; civ hybrid ids (xianjin, shangteca, kinshungs, wallans) appear as REALM cultures. All `hybrid_*` knobs PROVISIONAL — raise `base_p` for more prevalence. The §3.3 parity/alignment merge drivers stay DEFERRED. Integration guard: `test_setting_hybridization.gd::test_hybrid_emerges_on_generated_map` (full large seed-1000 gen → substrate + ≥1 recorded hybrid realm).


## 88. Watchable history replay — per-frame culture + territory + seed labels (2026-07-01) [PROVISIONAL]

The Screen C replay animated ONLY political ownership; the Culture/Territory layers fell back to the present-day map, so a viewer could not watch cultures spread or the civ/borderlands/wilderness frontier advance — which is exactly what you need to troubleshoot how the runtime maps turn out. Migration 180 stores those two extra layers per replay frame and a per-polity culture-seed label. Supersedes the §80 statement that "replay frames store ownership only."

- **Every replay `*_by_hex` shares ONE RLE encoding + helper.** `HistorySimulator._rle_field(value_of: Callable)` generalizes the old `_rle_owners`: runs of `value:count` joined by `;`, `''` = the field's "none" value, over the canonical `(r ASC, q ASC)` hex order. `_rle_owners` is now a one-liner over it; `_capture_replay_frame` captures `owner_by_hex` (owner_polity_id), `culture_by_hex` (`_dominant_key(_culture_w[key])`), and `territory_by_hex` (`territory_class`) each cadence tick. Values carry no `:` (ids + classes are colon-free), so the decoder splits on the LAST colon — do not introduce a `:` into any per-hex value.
- **Culture/territory layers are FRAME-AUTHORITATIVE — decode with `decode_value_map`, not `decode_owner_map`.** `ReplayFrameDecoder.decode_value_map(rle, ordered_hexes)` keeps EVERY hex including `''` entries (owner map SKIPS `''`, because missing→fall-back-to-hex-owner). A culture/territory hex mapped to `''` means "none this epoch" and must NOT fall back to the present-day substrate. `political_map_view` gates on `not _culture_override.is_empty()` / `not _territory_override.is_empty()` (set by `show_cultures`/`show_territories`, cleared by `bind`) to switch a layer between frame data (replay) and present-day (Screen D); no separate boolean flag.
- **Replay `set_replay_mode(true)` now covers Political, Culture AND Territory** (all three are frame-aware) — only Biome/Elevation (unchanging terrain) show the present-day tooltip. The frame-aware `_replay_tooltip` reports THIS epoch's realm/culture/frontier, never the stored end-state.
- **Culture colours are pre-seeded from the UNION across ALL frames, not just present-day.** A culture that spreads then dies out would otherwise draw grey on rewind (its id absent from the present-day-only `_ensure_culture_colors`). The replay screen computes the union (`_all_frame_cultures`, via `decode_runs`) and calls `seed_culture_colors(ids)`, which populates `_culture_colors` deterministically over sorted ids and is a no-op if already filled (so Screen D's present-day derivation is unaffected).
- **The culture-seed label ("Vallican_01") rides on the replay PALETTE, which already enumerates every frame owner.** `setting_replay_palette.seed_label` (migration 180) — `HistorySimulator._build_palette` assigns `"<CultureName>_NN"` with a per-culture ordinal in sorted-polity-id order (dead polities stay in `_polities`, so the palette covers fallen/unnamed realms that `setting_polities` — alive-only — omits). This is why the label goes here and NOT on `setting_fallen_polities` (selective) or `setting_polities` (survivors only). The replay tooltip leads with the seed label so a realm's seed culture is legible while scrubbing even before it earns a proper name; the eventual name, if any, follows in parens.

## 89. Ruler-AI persistence + the "three sites" rule for RUNTIME tables (2026-07-01) [PROVISIONAL]

Phase 0 of the ruler AI (gdd-ruler-ai.md §4/§10) added `ruler_dispositions` (migration 181) — the first NEW runtime (non-`setting_*`) table since the §83 "register in all three sites" convention was written. Resolution of the "as applicable" clause in gdd-ruler-ai.md §10:

- **A runtime table registers in TWO places, not three:** `CampaignRepository._SCOPE_DIRECT_CAMPAIGN` (it must carry a `campaign_id TEXT NOT NULL REFERENCES campaigns(id)` column; `test_savegame_snapshot`'s coverage audit fails until the table is classified or excluded) and the `db/schema.sql` tail (per §6.3 — current practice DOES maintain schema.sql; migrations 180/181 both appended their tables). `SettingRepository._DATA_TABLES` and `SettingDatasetHasher._table_specs()` are `setting_*`-only registries — a runtime table must NOT go in the hasher (it isn't part of the frozen setting dataset, and post-lock writes would not perturb the §80 world hash anyway; registering it would break hash stability for no benefit).
- **Derived-cache tables state their regeneration function in the migration header.** `ruler_dispositions` is a regenerable cache of `StrategicDispositionBuilder.build()` over `characters.personality` + `characters.alignment` — the header says so, which is what makes a future drop-and-rebuild migration non-destructive in practice (gdd-ruler-ai.md §10).
- **The §8.3 derivation layer is realm_ai, the struct is a shared type.** `StrategicDisposition`/`RulerProfile` live in `engine/shared_types/` (consumed across subsystems); `StrategicDispositionBuilder` + `RulerDispositionRepository` live in `engine/subsystems/realm_ai/` per gdd-ruler-ai.md §3.1 (which supersedes gdd-npc-personality.md §11.1's older `generation/npcs/strategic_disposition.gd` placement). The builder is pure (no RNG, no rounding, no DB in `build()`); persistence and relational seeding are separate statics so the golden test runs in memory.
- **Ruler-creation wiring pattern:** every path that mints an NPC ruler calls `StrategicDispositionBuilder.build_and_persist_for_character(id)` AFTER the character row + personality are persisted (NpcRulerGenerator.generate_for_domain, SettingMaterializer._build_ruler). Failures are non-fatal push_warnings — the idempotent `backfill_campaign()` (wired into `stock_rulers_and_tribute`) rebuilds any missing rows, and the Phase-3 LOD promotion adds the lazy ensure. A character with no personality JSON (beastman chieftain path) degrades to the neutral-baseline disposition (all axes 5, motivations ""), never to a missing row.

## 90. Ruler-AI action catalog + planner-internal activity intents (2026-07-01) [PROVISIONAL]

Phase 1 of the ruler AI (gdd-ruler-ai.md §5/§11) established the planner's action-vocabulary patterns:

- **Planner-internal activity category.** `data/activities/ruler_ai_category.json` (category `ruler_ai`) holds planner-level intents that must validate against the activity vocabulary (design brief §17) but never surface as player launchers — safe because UI blocks hard-code their activity-id const lists and never call `list_by_category` dynamically. When an action a planner emits exists in NO activity JSON (Phase 1 caught `withstand_siege`), REGISTER it — an unregisterable candidate breaks the §9.2 LLM-suggestion validator by construction.
- **Composite-intent handlers wrap existing handlers with a CLEAN delegate state.** `RaiseGarrisonHandler` calls the wrapped handlers with `{"character_id": ...}` only — never the original `state` — because every handler re-parses `state.params_json` and a composite's own params would leak into the wrapped handler's `count`/`domain_id`. Wrapped handlers re-check their own RAW gates (clanhold blocks etc.), so a composite cannot bypass one.
- **Ids with catalog entries but deliberately NO handler:** `hold` (gdd-ruler-ai.md §5.2 "(none)" — the planner resolves it without dispatch) and `withstand_siege` (rides the Phase-3 siege path). A scorer/dispatcher must special-case these; `ActivityHandlerRegistry.invoke_on_complete` push_warns on them otherwise.
- **RAW-precondition gates live where the FORCE is checked, not where the unit type exists.** The repress_population gate is "domain has ≥1 active NON-militia unit" (militia cannot BE the repressing force, `acore_axioms_strongholds_and_domains.xml:510-516`) — NOT "no militia exist". Generalization: when RAW constrains which resource may perform an action, gate on the existence of an eligible resource, never on the presence of an ineligible one.
- **Garrison funding trigger is shared, single-definition:** `RulerActionCatalog.garrison_needs_raising(garrison)` = under the universal 2gp/family minimum (+2 clanhold) OR wilderness under the 4gp/family base-morale threshold (`:233` — a morale threshold, NOT an enforced expense floor; borderlands 3gp is customary only). Both the catalog gate and the composite's stop condition use it — never re-derive the condition inline.
- **Abstract stronghold mutations follow DomainStocker's conventions** (cp_value = gp×100, `shp` stored in gp units equal to the stronghold's gp value) and spend in whole gp only; pair any whole-gp spend floor with a whole-gp availability gate (`minimum - value >= 100`) so the planner is never offered an un-completable sub-gp intent.

## 91. Ruler-AI planner: deterministic routing, launcher debits, backdrop stabilization (2026-07-01) [PROVISIONAL]

Phase 2 of the ruler AI (gdd-ruler-ai.md §6/§3.2/§8.4) — patterns hardened by two adversarial verify rounds (15 defects fixed pre-merge):

- **"Resolve the ruler's domain" is ONE deterministic query, everywhere:** `SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1`. Every activity handler's `_resolve_domain_for_ruler`, `RulerAI._personal_domain_for_ruler`, `retreat_resolver`, `primary_domain_id_for_character`, and `RealmGraph.apex_for_character` now share it. NEVER write an owner→domain lookup without the `ORDER BY created_at, id` — an unordered LIMIT 1 makes a planner score domain B and a handler act on domain A for any multi-domain owner. A planner plans exactly ONE turn per ruler on that personal domain (RAW `acore_axioms_strongholds_and_domains.xml:265-272`); "top-2..3 for large realms" means multiple ACTIONS, not multiple domains.
- **The LAUNCHER owns activity-cost debits.** Handlers whose header says "treasury was already debited at launch" (oversee_investment) mean it: any launch surface must `DomainTreasury.withdraw` BEFORE dispatching `on_complete`, and block on failure. Use category `"expense"` for the withdrawal so the handler's own informational `"investment"` row keeps its meaning. RulerAI's monthly batch bypasses the executor entirely (it calls handlers' `on_complete` directly), so it pays its own withdraw inline in `RulerAI._execute`. The PLAYER path goes through the single shared `ActivityTimeCostExecutor.launch()` (`engine/subsystems/activities/activity_time_cost_executor.gd`) — **fixed 2026-07-02**: `launch()` now debits there too, gated on `activity_def_id == "oversee_investment"` and resolved via the same `primary_domain_id_for_character` query (never the caller-supplied `params.domain_id`), returning `error: "insufficient_funds"` and skipping `activity_state` creation on a failed withdrawal. Any FUTURE launcher-cost activity added to the catalog needs the same treatment at whichever site actually calls `on_complete` for it — `executor.launch()` for anything scheduler-driven, or its own inline withdraw if it bypasses the executor like RulerAI does.
- **§8.4 backdrop auto-stabilize grants morale-roll effects ONLY, via opts flags** on `_resolve_domain_month(domain, day, opts)` — never by faking transient dict flags: `_save_domain` READS `administer_domain_completed_this_month` for the +5% XP bonus before resetting it, so a faked flag pays phantom XP. The neglect floor (`min(prior, 0)`) binds only when the roll's event-modifier sum is ≥ 0 — a remaining negative modifier is substantive damage (challenger, lair, taxes) and applies in full (known ±1 bound from the assumed-administer +1, documented in `ruler_backdrop_stabilizer.gd`).
- **"_this_month" domain columns are consumed-and-reset by `_save_domain`, all of them.** `is_repressed_this_month` + `repression_cp_per_family_this_month` joined `administer_domain_completed_this_month`/`pending_investment_cp` in the reset block (repression is a monthly stance; sustained repression = repress again). A transient column with no reset site is a latent permanent-state bug — grep for one before adding the next.
- **Player-side classification for the monthly report gate:** `auto_pause` fires only when a player-side domain exists; player-side = PCs plus PC-employed henchmen (a henchman heir keeps the player's domain paused and un-planned). The planner's active set excludes `character_type IN ('pc','henchman')` outright.
- **Scorer determinism:** tie-breaks come from `RulerActionScorer.monthly_rng(ruler_id, calendar_day)` (the CommerceMonthlyResolver hash-seed idiom) applied over a canonical pre-sort whose key (`action_id|decree_kind|value`) must stay a TOTAL order across simultaneous candidates.

## 92. Ruler-AI crisis + LOD: army-keyed threat routing, null-disposition anchors (2026-07-02) [PROVISIONAL]

Phase 3 of the ruler AI (gdd-ruler-ai.md §7/§8) — patterns hardened by the adversarial verify round:

- **Defensive actions require a FOE IN THE FIELD, never just a threat row.** `RulerCrisisResponder.detect_threats` sets `threat_present` only for a hostile army (an active `domain_threats` row with `linked_army_id`) or a non-concluded siege. An emerged challenger WITHOUT a linked army — the normal NPC post-emergence state; armies materialize via the Phase-9B path — is §7.2 STABILITY pressure (with accumulating and morale-collapse states), never a defensive trigger: offering `defensive_resistance` with no dispatchable attacker burns the ruler's monthly action slot on a blocked no-op forever. Generalization: before gating an action on a threat, confirm the DISPATCH data (the attacker id) exists, not just the state flag. A siege's `besieging_army_id` doubles as the resistance target when no threat row supplied one.
- **Crisis biases ride ctx["crisis_biases"]** ({action_id or "issue_decree|<kind>": multiplier} from `RulerCrisisResponder.posture_biases`) multiplied inside the scorer — mathematically §6.1's "apply crisis bias" step while keeping the tie-break machinery; `hold`'s flat floor accepts crisis biases (§7.1 cautious hoarding) but stays exempt from §6.2 modifiers. Stability-bias tax keys are the LOWER-tax lever and direction-gate in the scorer exactly like the §6.2 morale column — boosting a raise-tax decree would accelerate the morale spiral the bias exists to bleed.
- **The §7.3 regression anchor is NULL-disposition degradation:** `resistance_threshold(null) == 0.50` exactly (any BUILT disposition has a nonzero military weight, so null is the only exact anchor) — the generalized `ExtractionResistanceHeuristic.evaluate` with default opts is behaviorally identical to the old placeholder. When generalizing a placeholder heuristic, make "no new inputs" reproduce it BY CONSTRUCTION and keep its original tests running.
- **LOD:** the `regional_6mi` map IS the §8.1 play window (the rolling frontier grows the map), so window+buffer = map membership while located domains only exist there. The full-tier gate is checked in BOTH the geometry query and the conflict-hook path (campaign-scoped) — the §8.1 materialization-safety invariant ("the buffer never promotes a named/abstract ruler") has a dedicated test. Campaigns with no region map (fixtures) fall back to the full-tier set. `RulerLodManager.sync`'s promote/demote cache is session-local; persistence + the §8.2 demotion grace land with Phase 4's `ruler_ai_state`.

## 93. Ruler-AI LLM contract seams + runtime-state persistence (2026-07-02) [PROVISIONAL]

- **Seam A (retroactive narration) pattern:** the narrator SHORT-CIRCUITS on `LLMManager.is_configured()` — the stub warns per call and only returns a generic fallback, so an unconfigured provider is never called. Any null/failed/`is_fallback` envelope substitutes a DETERMINISTIC template: a per-id phrase bank in `data/templates/` (the npc-personality §9.3 fragment-bank convention — `ruler_action_templates.json`), the structured outcome's `summary` verbatim (engine truth), and shared banks via PUBLIC accessors (`PersonalityMock.motivation_phrase`) rather than duplicate loaders. Unconfigured narration must be a pure function of persisted rows (the "no variance" acceptance bar). Narration caches persist keyed `"day|action[|variant]"` — include a variant key wherever the planner's own distinctness key is finer than the action id (decrees: `action_id|decree_kind`).
- **Seam B (structured LLM suggestions) pattern:** validation is STRICT — any invalid part rejects the WHOLE suggestion with a logged reason (design brief §9.1); validate against an explicit vocabulary const (`RulerActionCatalog.ACTION_IDS`), and REJECT any key that would ride an UNGATED scorer fallback (the bare `issue_decree` key bypasses the per-kind raise-tax direction gate — require the `issue_decree|<kind>` form). Accepted suggestions become ONE-TURN in-memory pending modifiers popped by the planner turn (`consume_pending`) — a posture override + multiplicative biases on the existing `crisis_biases` channel; they never execute and never mutate persisted dispositions. Under the mock, `reassess()` is a no-op that makes NO provider call.
- **`INSERT OR REPLACE` upserts must carry `created_at` through** (`COALESCE(?, datetime('now'))` bound to the existing row's value): REPLACE deletes + reinserts, silently resetting DEFAULT-stamped columns and falsifying any creation-order contract.
- **Stateful static caches that mirror DB state need BOTH halves of save/load reconciliation:** hydrate the cold cache FROM the persisted rows (so a loaded session doesn't replay transition signals), and CLEAR the cache in `SessionRunner.load_session` beside the disease/siege on-load reconciliations (so an in-process `load_slot` snapshot restore can't diff against pre-restore memory).
- **§8.2 demotion grace is for GEOMETRY exits only:** the grace gate re-checks BOTH eligibility halves — the character (`_is_full_tier_npc`) and a plannable domain (`_has_plannable_domain` = the geometry query's lifecycle filter minus location, because location is exactly what grace forgives). Death, tier loss, or a terminal domain demotes immediately; a grace holdover stays in the returned active set (it keeps planning) with `demotion_pending_day` stamped in `ruler_ai_state`, cleared silently on re-entry.

## 94. On-map army token layer — 3D overlay, pure-logic model, signal-driven (2026-07-04) [PROVISIONAL]

- **The LIVE regional (6-mile) renderer is `scenes/maps/hex_map_renderer_3d.gd` (Node3D), NOT the 2D `hex_map_renderer.gd`.** `project.godot` `rendering/wilderness_hex_mode="heightmap_3d"` makes `SessionRunner._maybe_swap_wilderness_3d()` rename+`queue_free()` the 2D `HexMap` at boot and swap in the 3D scene (renamed `HexMap`). The 2D renderer + `HexMapLandmarkIcons` are dead code under the live flag. **New on-map overlays go on the 3D renderer**, not as Node2D layers mirroring §40. Markers are `Node3D`/`MeshInstance3D`/`Label3D` grouped under a named `Node3D` root child of the renderer (`_army_root`, alongside `_token_root`/`_landmark_root`), placed at `WildernessHexMath.axial_to_world(coord)` (XZ) + `_hex_height(coord)` (Y) + a lift. There is NO `hex_to_pixel` Callable — call the static math directly. Picking is a terrain raycast → hex coord, so a click on a marker is resolved by a `coord → id` index the layer maintains (`_army_hex_index`), NOT per-object collision; the layer emits a new signal (`army_token_clicked`) from the renderer's `_pick`, and the party wins same-hex ties.
- **Split the layer into a headless-testable pure-logic model + a thin renderer.** The renderer (`scenes/`, never loaded by the headless suite) only renders + wires signals; ALL queryable/derivable state (which armies, composition, owner, state colour, supply gauge) lives in a `RefCounted` static model under `engine/` (`ArmyMapPresence`) that the suite exercises. Same rule for the right-click menu: eligibility/order-set is a pure-logic builder (`ArmyMarchingContextMenu`, RefCounted+`class_name`, unit-tested) producing the `dungeon_context_menu.gd` option shape (`{label, enabled, tooltip, category, action_data:{action_type, …}}`); the map layer only renders it (shared `dungeon_context_menu.gd` widget, auto-pauses via `SchedulerLoop`) and the owning state's `_on_context_action` dispatches — mirrors §19.6.
- **Signal-driven refresh, full rebuild.** There is NO `army_state_changed` signal — every `ArmyRepository.update_army({"state":…})` is signal-less. The layer connects the army-lifecycle EventBus signals (`army_formed`/`army_disbanded`/`battle_concluded`/`armies_collided`/`army_supply_cut` → rebuild; `army_arrived_at_hex` → rebuild + clear a stale path overlay; `order_queued` **filtered to `event_type=="army_travel_leg"`** → rebuild, the ONLY hook for the encamped→marching recolor) and does a wholesale `_rebuild_armies()` each time (a handful of armies per map — cheap + bug-free vs per-token diffing). Connect in `_ready`; the persistent renderer auto-disconnects on free.
- **Army position is a single in-flight leg, read from the in-memory scheduler.** There is no stored multi-hex army route (no path column, no legs table); `march_army` pre-schedules exactly ONE `army_travel_leg`. The selected-army path overlay reads that one segment via `scheduler.get_events_for_owner(army_id)` filtered to `ArmyMarcher.EVENT_ARMY_TRAVEL_LEG` (`ev.data.from/to_hex_q/r`) — the layer needs the live `EventScheduler` (from `runner.get_scheduler()`), not a DB query.
- **`int(army.get("hex_q", 0))` crashes on an unpositioned army** — `hex_q`/`hex_r` are NULL (not absent) for `assembling` armies, and `.get(key, default)` returns the null VALUE, so `int(null)` throws "Nonexistent 'int' constructor". Coerce with a null guard (`int(v) if v != null else 0`). Same trap as the `current_hex_q` reads in `wilderness_explore_state`.
- **Gate un-landed downstream orders behind a documented flag, disabled-with-tooltip, never omitted.** Phase-B extraction orders (requisition/loot) render DISABLED with a Phase-B tooltip (`PHASE_B_EXTRACTION_AVAILABLE=false`) AND `execute_action` returns `phase_b_pending` (defence-in-depth) so placeholder economics can never fire; one flag flip enables them when the resolver lands. GDD §7.3's "disabled-state tooltips" means present-but-greyed with a reason, not silently dropped.
- **"Player-orderable" is stricter than siege "player-involved".** For issuing direct orders, ownership = PC **or a henchman whose lord is a PC** — NOT the siege-dispatcher `_is_pc_or_pc_associate` breadth that also counts named NPC vassals (a vassal ruler's own army is influenced via call-to-arms/duties, not direct march orders; it's inspect-only on the map). `henchman_relationships(henchman_character_id, lord_character_id)` is the join.

## 95. Battle/siege routing backbone — collision listener, modal-pause keying, LOD conflict hook (2026-07-04) [PROVISIONAL]

- **A doc-comment-promised-but-unimplemented method is a real gap, not an existing API.** `BattleDispatcher.register_collision_listener()` was named in the class docstring (and the handoff's interface index) but had NO implementation — same class of error as the phantom `begin_march`. Grep the actual `func` before "just calling" a method a doc/handoff names. Likewise a subsystem handler that is *built and tested* but registered NOWHERE (`ArmyMarcher.register` was called by no production code) is a latent blocker: its scheduled events (`army_travel_leg`) park unhandled forever, so marches never resolve and collisions never fire. Register such handlers at session activation (`SessionRunner.load_session`, mirroring the SiegeHandlers `unregister→new→register` block) with a matching `end_session` unregister.
- **EventBus-signal listeners are wired by `.connect()` at session activation, NOT via the EventHandlerRegistry.** The registry (`registry.register(EVENT, handler)`) is for *scheduled* events; an EventBus signal like `armies_collided` is a `.connect()`. A pure-static `RefCounted` (BattleDispatcher) can own the connection via a **static** handler + idempotent `is_connected` guards (`register_collision_listener`/`unregister_collision_listener`) — the static-method Callable identity is stable across `connect`/`disconnect`. `armies_collided` carries no `calendar_day`; the listener sources it from `Timekeeping.get_calendar_day()`.
- **A scheduler pause that brackets a modal sub-game MUST be keyed to that sub-game's id.** `SessionRunner._on_battle_concluded_for_scheduler` resumes ONLY when the concluded `battle_id` equals the `_paused_for_battle_id` captured when the pause was taken. A sibling **silent** NPC-vs-NPC battle can conclude *synchronously* (the collision detector emits multiple `armies_collided` in one loop; the silent path resolves inline and emits `battle_concluded`) while a player battle is paused — an un-keyed resume would advance the clock out from under the open player panel and never re-pause. Capture `{was_paused_before, owner_id}` on the FIRST pause (the pause signal re-fires per phase), restore on the matching conclusion only, and reset both on `end_session`. (Owner: the loop owner (SessionRunner), so the scenes/ panel stays scheduler-free.)
- **godot-sqlite: `.get(column, default)` does NOT apply the default for a SQL-NULL column.** A NULL `TEXT` column comes back as a Godot `null` with the key PRESENT, so `row.get("col", "")` returns `null`, and `String(null)` / `int(null)` crash ("Nonexistent 'String'/'int' constructor"). Guard every nullable column read: `var v: Variant = row.get("col"); var s := "" if v == null else String(v)` (the pattern already in `siege_resolver`, `campaign_repository`). The `.get(...)` default only fires when the key is ABSENT, which SELECT results never are.
- **The Regional-LOD conflict hook keeps the full-tier gate as the sole safety boundary.** `ConflictParticipants.active_ruler_ids(campaign_id)` (stateless, re-derived from live `field_battles`/`sieges` rows each call — no persistence) returns RAW opposing-NPC `political_owner_id`s of player-involved conflicts; it must NOT itself gate tier or promote. `RulerLodManager.active_set`/`sync` re-run `_is_full_tier_npc` on every `extra_ruler_id`, so a `named`-tier opponent (bandit captain / challenger — both `persistence_tier='named'`) is silently dropped and NEVER promoted (§8.1 materialization safety). Feed it in two places: the monthly tick (`domain_handlers` sync `extra_ruler_ids`) AND an immediate `sync` on `battle_started`/`siege_started` (SessionRunner-owned — NOT inside the static dispatchers, which must stay decoupled from `realm_ai`). Player-involved predicate per table: `field_battles.is_player_involved = 1`; `sieges.resolution_mode = 'full'` (sieges have no `is_player_involved` column). Non-concluded per table: `field_battles.outcome = ''`; `sieges.current_phase != 'concluded'`.
- **World-log for engine-resolved conflicts: subscribe the log to the conclusion signal and re-query for context.** `GameLog` consumes `EventBus.battle_concluded(battle_id, outcome)` and re-queries `BattleRepository.get_battle` for belligerents/player-involvement (the signal carries no context), then appends a `combat` line (`npc_battle_resolved` silent / `pc_battle_concluded` player, §7.6). Keeps the log wiring in the log owner — no resolver edit, no `armies→GameLog` coupling.

## 96. RAW extraction resolver, per-domain ledger, and resolve/preview parity (2026-07-04) [PROVISIONAL]

- **Cross-army RAW limits live in a DOMAIN-keyed ledger, not a per-army column.** A per-army store (`army_supply_state.requisition_cooldowns_json`) cannot enforce "requisition a domain once per 6 months" or "60 gp/family combined ceiling per domain" — those are properties of the domain across ALL armies. `domain_extraction_ledger` (migration 183, keyed `(campaign_id, domain_id)`) owns the cooldown stamp + running per-family cumulative. New campaign-scoped tables with their own `campaign_id` go in `CampaignRepository._SCOPE_DIRECT_CAMPAIGN` (not `_SCOPE_VIA_*`); migrations auto-discover (drop `NNN_*.sql`, no registration), and mirror the CREATE into `db/schema.sql` (a human-reference mirror — the DB boots by replaying migrations, so a schema.sql miss won't break the game, but a bad migration prefix will).
- **The domain family count is `domains.peasant_families` — the per-hex `domain_hexes.families` column is 0 at runtime** (M2b-1 per-6-mile-hex population deferred). Yields/family-loss read/write `peasant_families` via `CampaignRepository.get_domain` / `update_domain_monthly_state` (whitelisted), clamping `maxi(0, …)` like the monthly path. Don't sum `domain_hexes.families`.
- **Banker's rounding at the gp→cp boundary is `XPAwardCalculator.bankers_round(gp_per_family × families × 100.0)`.** The §12 table's "roundi() everywhere" is WRONG (Godot `roundi()` is round-half-away-from-zero); the whole money layer routes through `XPAwardCalculator.bankers_round` (round-half-to-even). All persisted money is cp = gp×100.
- **A resolver that charges a source must confirm the sink up front.** `ExtractionResolver.resolve` guards `ArmyRepository.get_supply_state(army_id).is_empty()` and `_fail`s BEFORE any domain side effect — never decrement families / stamp the ledger cooldown+ceiling for a yield the army can't be credited (supply-less armies exist: bandit/challenger `create_army` bypasses `ArmyComposer`, which is the only path that inserts a supply row). Return `success:false` when the yield is dropped — never report a phantom yield.
- **`preview()` and `resolve()` MUST gate on identical predicates.** A read-only eligibility preview (for menu enable/tooltip) that is even slightly more permissive than the executing resolver enables an order the resolver then silently no-ops (and on a scheduled path, wastes the leg). Concretely: the requisition 6-month cooldown (`last_requisition_calendar_day`) and the 60 gp/family ceiling period (`period_anchor_calendar_day`) are INDEPENDENT clocks — the ceiling period expiring must NOT clear an active cooldown in either the resolver or the preview.
- **Scheduled-activity legs (encamped `requisition_leg`/`loot_leg`) put ALL completion state in `event.data`** — the leg survives save/load because the `EventScheduler` serializes `event.data` (JSON), and the handler service is recreated fresh on `load_session` (so no instance state can be relied on). Register the service at `load_session` (else events park unhandled — the Phase-A `ArmyMarcher` lesson) with a matching `end_session` unregister. Reuse `HexMapController.get_neighbors` (flat-top axial 6-neighbours) for "current-then-adjacent" geography — NOT `WildernessHexMath` (that's world-XZ render math).
- **RAW movement-halving for extraction is a real ×0.5 on daily miles**, threaded through `compute_army_daily_miles(…, extraction_mode)` (it was documented-but-unapplied). A comment claiming a caller applies an effect elsewhere is not the effect — verify the multiplier actually lands in the leg-duration computation.

## 97. Extraction-resistance seam — decision→battle→gate, sync-vs-async, re-entrancy, levy demob (2026-07-04) [PROVISIONAL]

- **A synchronous hook cannot await an interactive battle.** `ExtractionResolver.resolve` (called from `EventScheduler` handlers) runs `_resistance_hook_phase_c` → `ExtractionResistanceRouter.should_proceed` and expects a `bool` back. `BattleDispatcher.dispatch_collision` bifurcates: SILENT (NPC-vs-NPC) resolves in-call so the outcome gates the yield immediately; INTERACTIVE (player-involved) returns `outcome:""` and the battle plays out later via the Phase-A panel. The seam CANNOT block on an interactive outcome — it blocks the yield for that attempt (returns false) and the player re-issues after winning. Do NOT build a deferred-credit path unless the async lifecycle (a `battle_concluded` listener + a pending-yield store) is actually wired.
- **Gate on the battle ROW, not on who you passed as attacker.** `dispatch_collision` picks the tactical attacker/defender itself (by marching-state, else BR proxy), so the extractor is NOT necessarily the tactical attacker. Read `BattleRepository.get_battle(battle_id).attacker_army_id` and compare to the extractor before mapping the outcome. Authoritative `field_battles.outcome` → winner: attacker won iff ∈ {`attacker_victory`, `defender_annihilation`, `defender_voluntary_withdrawal`}; defender won iff ∈ {`defender_victory`, `attacker_annihilation`, `attacker_voluntary_withdrawal`}; else draw. (`attacker_annihilation` = the ATTACKER was annihilated. The resolver's own `attacker_won`/`defender_won` booleans at `field_battle_resolver.gd:698` are over-broad — do NOT copy them; use the explicit set.)
- **Materialising an army mid-leg + a later collision re-scan = duplicate battle.** When one code path creates a second army at a hex and dispatches it (the resistance levy), and another path (`ArmyMarcher`'s post-arrival `ArmyCollisionDetector.detect_at_hex`) re-scans that same hex, they collide. `detect_at_hex` does NOT skip `battling` armies, and `start_battle` does not guard against an army already in a battle — so `dispatch_collision` now no-ops (`already_battling`) if either army's state is `battling`. Silent battles are self-safe (the loser retreats/disbands before the re-scan); this guard specifically covers the ongoing (interactive) case.
- **A mustered army is temporary — demobilise it, don't orphan it.** A resistance levy pulls garrison `troop_units` into a new army (`assignment_kind` flipped `garrison`→`on_campaign`; `assigned_domain_id` UNCHANGED). After a SILENT battle, `_demobilize_defender` flips surviving units back to `garrison` and marks the army `disbanded` — otherwise the domain is permanently stripped of its garrison on a WIN and the levy lingers as a collision hazard. Casualties are already applied by the resolver (destroyed units are `status != 'active'`, skipped); an annihilated levy is already `disbanded` (no-op). The battle resolver only disbands on annihilation — victory/retreat cleanup is the caller's job.
- **A one-off muster torn down by a persistent TAG + a battle_concluded listener, not by in-hook state (2026-07-06).** A PLAYER-involved resistance battle resolves asynchronously, so `should_proceed` can't await the outcome to call `_demobilize_defender` in-hook — the interactive levy previously LEAKED (garrison stranded `on_campaign` on a WIN/retreat; a phantom army on the map). Fix: tag the levy at creation (`armies.provenance='resistance_levy'`, migration 186; `ArmyRepository.PROVENANCE_*`, code-validated no-CHECK per §184's ALTER style) and register a `SessionRunner`-owned `EventBus.battle_concluded` listener (`ExtractionResistanceRouter.register_battle_conclusion_listener`, sibling to `BattleRetreatSiegeRouter.register_listener`) that runs `_demobilize_defender` on either participant tagged a spent levy. A persistent tag (not a static pending-map keyed by `battle_id`) is deliberate — it survives save/load mid-battle (the same discipline as the `_episodes` session-reset above). The silent path STILL demobilises inline (idempotent — the listener no-ops on an already-`disbanded` levy; keeps subsystem tests that don't boot SessionRunner correct); in-game a silent levy just gets torn down by whichever fires first.
- **Don't demob a levy that acquired a NEW reason to exist — a forming/active siege.** A levy that LOST and retreated INTO a co-located stronghold (`RetreatResolver` stamps `garrison_stronghold_id`) becomes that stronghold's `defending_army_id` when the victor besieges — demobilising it would strip the besieged garrison. The teardown guard (`_levy_reason_still_active`) skips any levy with a non-empty `garrison_stronghold_id`; that single proxy covers BOTH siege timings — the NPC victor dispatches synchronously in the aftermath (before `battle_concluded`), a player victor's siege is deferred to the pause-handoff modal (AFTER `battle_concluded`) — because the flag is set in either case (belt-and-suspenders: also skip if named in an active `sieges` row). Teardown of a holed-up levy then belongs to the siege lifecycle (a still-open follow-up), not the field-battle aftermath.
- **A symmetric-looking gap can have asymmetric semantics — check before generalising.** A `CallToArmsMuster` lord army (`provenance='call_to_arms'`) looks like the same "temporary muster" leak, but it is a STANDING body: it may fight many battles and its teardown is revocation-driven (`resolve_revocation`, fired from `FavorsDutiesResolver`). Auto-disbanding it on `battle_concluded` would be a BUG. So it is tagged (identifiable) but the demob listener's provenance gate deliberately EXCLUDES it. When a prompt frames two things as the same fix, verify the lifecycle before wiring shared teardown.
- **Static per-decision caches must not outlive their scope.** `ExtractionResistanceRouter._episodes` (decide-resistance-once per `(domain,army,mode,day)`, so a pro-rated multi-hex march doesn't re-roll per hex) is `static var` and its key is NOT campaign-scoped — `SessionRunner.load_session` calls `reset_episode_cache()` so a decision cached under one campaign can never bleed into another. `_prune_stale_episodes` drops prior-day keys to keep it bounded within a session. Any static mutable cache in a `class_name` service needs a session-load reset + a test-isolation reset hook.
- **Reuse the built decision layer; do not re-derive the threshold.** The §7.3 resistance decision is `ExtractionResistanceHeuristic.evaluate(domain, army, day, dice=null, {disposition, defending_own_stronghold})` — it federates vassals, rolls loyalty, emits `vassal_revolted`, and returns `will_resist` off a disposition-modulated threshold (`RulerCrisisResponder.resistance_threshold`; null disposition → exact 0.50 anchor). The seam calls it once and consumes `will_resist` + `vassals_responding`; it never recomputes BR or the threshold. Fetch disposition via `RulerDispositionRepository.get_disposition` (returns null-able — store in a `Variant`, pass through; never `String()`/typed-null it).
- **When a spec cites a RAW rule that the RAW doesn't support, flag it — don't invent the mechanic.** The Phase-C handoff (§5 step 5) placed a "henchman-morale roll when a lord loots a vassal" in this phase, citing GDD §4.3.3; `acks-raw-lookup` shows the Henchman Morale roll is a Call-to-Arms mechanic (`ax_campaign_play.xml:518-528`, "demanding two duties"), NOT a requisition/loot one, and GDD §4.3.3 has no such note. Per doc-authority (RAW is SACRED) the case was FLAGGED `[NEEDS-JEDIDIAH-REVIEW]`, not implemented as an invented rule. Same discipline for a player-facing surface that doesn't cleanly exist (the step-4 resist-choice modal): guard + notify + flag, rather than fabricate a `domain_threats.kind` the CHECK enum + sub-tab don't support.

## 98. Ruler-AI dispatch routing — trigger, don't re-implement; thread the scheduler; hold ALL (2026-07-04) [PROVISIONAL]

- **The planner TRIGGERS a subsystem's entry point; it does not re-implement the subsystem's table.** `RulerAI._execute`'s `call_to_arms` routes each vassal through `FavorsDutiesResolver.trigger_call_to_arms` (a NEW public method that delegates to the existing `_apply_obligation`), so the obligation-creation + `_compute_safe_duty_threshold` + `_run_loyalty_check` + `vassal_revolted` machinery is reused verbatim — the random monthly duty roll and the planner's deliberate crisis muster now share ONE code path. To expose a private flow to a new caller, add optional trailing params to the private method (here `lord_army_id_override=""`, `magnitude_pct_override=50`) and a thin public wrapper — existing callers stay byte-identical; do NOT copy the flow into the caller.
- **The static monthly planner has no scheduler — thread one in for anything that schedules events.** `RulerAI.process_campaign_month/_take_turn/_execute` gained a trailing `scheduler=null` sourced at the call site from `_runner.get_scheduler()` (the same accessor `FavorsDutiesResolver.roll_monthly` already uses in `domain_handlers`). `CallToArmsMuster.issue_call` and `ArmyMarcher.cancel_march` no-op gracefully on `scheduler=null`, so tests still persist the state rows (`call_to_arms_state`) — only the scheduled EVENTS (tranche arrivals, march cancellation) need a live scheduler. Add the param as trailing-optional so every existing caller/test keeps working.
- **A crisis action that operates on "the threat" must handle MORE than one.** `withstand_siege` sets the defender posture on EVERY active siege on the domain (a domain may hold several besieged strongholds), not `sieges[0]` — `SiegeRepository.list_active_sieges_for_domain` orders by `started_calendar_day ASC`, so `[0]` is the OLDEST, silently defending the wrong stronghold. Iterate; don't index.
- **Two "garrison" representations exist — know which a consumer counts.** `troop_units.assignment_kind='garrison' + assigned_domain_id` (a loose domain garrison, no army — what `ExtractionResistanceHeuristic` / Phase-C muster read) is DISTINCT from units in a **garrison army** (`army_unit_assignments` → `armies` owned by the character, units still `assignment_kind='garrison'` — what `CallToArmsMuster.compute_realm_garrison_unit_count` counts via a JOIN). Seeding the wrong one makes `issue_call` return `""` (zero garrison → no muster). A test fixture for call_to_arms MUST build a garrison army (create_army + create_officer + create_assignment + flip `assignment_kind`), per `test_phase_9c`'s pattern.
- **Never reinforce a `battling` army.** A call-to-arms merge target must be `encamped`/`assembling` only — the field-battle resolver assumes a fixed roster, so mid-combat reinforcement corrupts battle state (`CallToArmsMuster`'s own garrison lookup already excludes `battling` — match it).
- **A defender-posture column read only in the branch it gates keeps the resolver "unchanged."** `sieges.defender_posture` (migration 184, default `'undecided'`) is read ONLY in `siege_resolver.apply_method('sally')` — a `'hold_fast'` defender is refused the sortie; the default value preserves every existing siege test. Adding a minimal state column + reading it in the ONE place the resolver already branches on defender behavior is how you give a "minimal posture" real teeth without touching the blockade/reduction/assault progression. (The "hold, no sortie" commitment is PROJECT-DESIGNED — `daw_sieges.xml` doesn't forbid sorties — sanctioned as the handoff's minimal-behavior decision.)
- **Removing an action from `_NO_DISPATCH` requires a matching `match` branch.** `_NO_DISPATCH` short-circuits BEFORE the dispatch `match`; drop an action from it (here `withstand_siege`) and you MUST add its `match` arm or it hits the `no dispatch mapping` fallthrough. Both new arms return real `{dispatched:true, ...}` dicts so Seam-A narration + the `ruler_action_taken` log carry engine truth.

## 99. NPC threat escalation — a driver reuses the player's UI path; detect-vs-dispatch split for the scheduler (2026-07-04) [PROVISIONAL]

- **An autonomous NPC driver IS the player's threats-sub-tab, minus the human.** `ThreatEscalationDriver` (§4.10.2) reuses the EXACT pipeline the Encounters & Threats sub-tab presses by hand: `NPCChallengerEmergence.materialize_challenger_as_army` → `ExtractionResistanceHeuristic.evaluate` (the §7.3 decision, same as `defensive_resistance`) → `SiegeDispatcher.dispatch_new_siege` / `BattleDispatcher.dispatch_collision`. When you close a "no-one presses the button for NPCs" gap, drive the SAME reused functions from the monthly tick — don't fork a parallel implementation. Replicate the scene-private lookups (`_stronghold_for_domain`, `_garrison_army_for_stronghold`) as static helpers (the scenes/ versions aren't loaded headless).
- **Scope guards fall out of the input set, not per-item checks.** The driver runs ONLY for NPC/active-LOD/non-backdrop domains because it iterates `active_ruler_ids` (the RulerLodManager active set — PCs and backdrop rulers are simply absent) and processes ONLY `npc_challenger` threats (bandit swarms never escalate, §4.10.4). Guard by choosing the right set to iterate, not by re-deriving player/backdrop/kind on each item.
- **Idempotence lives in the artifact, not the driver.** The driver is stateless between ticks; per-threat bookkeeping (`offered_day` / `refused_day` / `dispatched_day`) goes in the threat row's `payload_json` — a `dispatched_day` short-circuits any re-dispatch. No migration, no scheduler events of its own; the dispatched siege/battle owns its ticks.
- **A dead placeholder that always returns `{}` silently disables the feature that depends on it.** `RetreatResolver._find_friendly_stronghold_at` had returned `{}` "until Phase 9 stabilizes the strongholds table" — but the hex columns (`location_map_id/hex_q/hex_r`, `idx_strongholds_hex`) had existed for ages, so `retreated_into_stronghold` (and thus the whole retreat→siege RAW rule) had NEVER fired. When wiring a feature onto an existing predicate, VERIFY the predicate actually returns truthy for the real case; a stale "v1 placeholder" comment is not proof.
- **Detect where the data is; dispatch where the scheduler is.** The battle aftermath (`FieldBattleResolver._resolve_post_battle_state`) has the retreat result but NO scheduler; a dispatched siege needs one for its ticks. So the aftermath EMITs `battle_loser_retreated_into_stronghold` (victor = the OTHER army in the `field_battles` row; annihilation early-returns skip it — an annihilated army is disbanded, never retreats), and a SessionRunner-owned `BattleRetreatSiegeRouter` (registered with a `get_scheduler` Callable, like `BattleDispatcher.register_collision_listener`) DECIDES + dispatches with the live scheduler. Split detection from dispatch when the detection site lacks a dependency the dispatch needs.
- **"Hostile intent" for a post-combat victor is hostile-UNLESS-proven-friendly.** A victor that just beat the domain's field army and holds the ground IS the aggressor. Don't gate on `RealmGraph.classify_hostility == HOSTILE` (that returns false for a LANDLESS victor with an empty apex — a challenger / free company — so they'd never besiege). Return true unless the victor's realm is provably the same/allied as the domain's. Reuse a decision layer's boolean flag ONLY where its semantics align: the extraction-resistance `defending_own_stronghold` term models sortie-reluctance (+0.10 = harder to resist), which is MISaligned with a challenger accept-via-siege-defence, so pass `false` there (the disposition terms drive the choice) rather than the literal-looking `true`.
- **A decision modal that fires INSIDE a battle's aftermath must HAND OFF the battle pause, not open its own competing one (2026-07-06).** The player-victor siege-decision modal (`scenes/ui/battle/siege_decision_panel.gd`, opened from `EventBus.siege_decision_required`) is auto-paused by SessionRunner — but the signal fires from `FieldBattleResolver._run_aftermath` BEFORE the caller emits `battle_concluded`, and a player-victor battle is always interactive (already paused). So the emit order is `siege_decision_required` → `battle_concluded`. If `_on_battle_concluded_for_scheduler` resumed unconditionally it would run the clock out from under the just-opened modal. The fix: `_on_siege_decision_required` INHERITS the battle's pre-pause state (`_scheduler_paused_before_battle` while `_battle_pause_active`, else the live `is_paused()`), takes over the pause, and `battle_concluded` early-returns its resume when `_siege_decision_active`. The pause is then continuous from battle-start → decision → resolve. When a modal can open during another paused sub-game's teardown, key the resume so only the OWNER releases it (same lesson as the silent-battle pause-key in §95).
- **Keep player-choice dispatch beside the NPC heuristic in one headless-testable class.** `BattleRetreatSiegeRouter.resolve_player_decision(choice, victor, stronghold, defeated, day=-1, scheduler=null)` is the sibling of the NPC `on_retreat_into_stronghold` heuristic — both live in the static router so all retreat→siege routing (RAW `daw_axioms_pitching_battle.xml:563-575`) is in one place the suite exercises without a SceneTree. The modal (`scenes/`, never loaded headless) stays UI-only: it emits ONE `decided(choice)` signal and SessionRunner calls the router (with the live scheduler) — the §27 modal-tier split. `besiege` → `SiegeDispatcher.dispatch_new_siege` (player-involvement routing stays centralised → full siege); `encamp` and `march_on` share the encamped end-state in v1 (the victor is already `encamped` post-battle; a real March-on destination can't be picked from the modal), differing only in intent + guidance. A null `scheduler`/`day < 0` default from the registered `_scheduler_provider`/`Timekeeping` so the modal never has to hold either.

## 100. Threat armies field REAL troops; militia deaths are a permanent, limited domain resource (2026-07-04) [PROVISIONAL]

- **A threat army must field real `troop_units`, not just a count in its name.** `BanditSpawner.materialize_swarm_as_army` and `NPCChallengerEmergence.materialize_challenger_as_army` used to create a unit-less army shell — the swarm's size lived only in the army NAME, so the army had BR 0. A BR-0 aggressor makes the §7.3 resistance decision trivially "accept" (`attacker_br=0` → threshold 0) and leaves the resulting siege/battle a strengthless phantom. `ThreatForceComposer.field_bandit_force(army_id, campaign_id, owner_id, troop_count, calendar_day)` is the shared closer: it creates the army-leader officer (so `army_unit_assignments.parent_officer_id` is non-null) + chunked `troop_units` (≤120 each, `source_type='mercenary'`, `troop_type='Brigands'`, self-funding — no wages, they live by pillage) and assigns them. **When you materialize any force from an abstract count, verify the count becomes real rows the battle math will read — a name is not a unit.**
- **The challenger LEADS the domain's bandits; RAW gives no retinue formula.** RAW (daw §L627-630) says a challenger "emerges from the bandits" but specifies no level-based retinue. Per Jedidiah (2026-07-04), the challenger fields the domain's existing morale-scaled band via `ThreatForceComposer.bandit_force_for_domain(domain_id)` — prefer the active `bandit_swarm.bandit_count`, else the morale-tier scale (≤-4 → 1/family, -3 → 1/2, -2 → 1/5, else 1/10, floored at 1). Don't invent a strength model where RAW is silent; reuse the RAW-anchored one already computed for the swarm.
- **Combat losses already persist and survive disband — verify before you "fix" it.** `ArmyCasualtyResolver.resolve_battle_casualties` (wired once per battle at `FieldBattleResolver._run_aftermath`) decrements the real `troop_units.count` and marks destroyed units `status='departed'`; `ArmyDisbander.disband` only touches `assignment_kind`/`status`, never `count`. So a bloodied unit keeps its reduced count through disband with no extra work. The reverse-flow "make losses persist" ask was already satisfied for regular troops — only the militia-specific population/morale reconciliation was genuinely missing.
- **Militia deaths are a PERMANENT population + morale loss (RAW daw_armies_recruitment L429-432), applied once per battle at the single resolution point.** `_resolve_side` accumulates `militia_deaths_by_domain` (crippled/dead of `source_type='militia'` units, keyed by `assigned_domain_id`); `resolve_battle_casualties` merges both sides (a domain's militia can attack OR defend; a unit is on exactly one side so no double-count) and calls `_apply_militia_population_loss` per domain. That helper: `peasant_families -= killed` (L429 "1 family per levied peasant" made permanent by L432), floored at 0; domain morale `-1` below 2/10 killed-density or `-2` at/above (`killed*10/families >= 2`), clamped to `[-4,4]`. Apply at the ONE resolution site so it can't double-charge; the shrunken `peasant_families` shrinks the levy cap, which is what makes militia limited.
- **The levy cap is a STANDING cap, enforced against militia already under arms.** `LevyMilitiaHandler` caps at `(peasant_families/10)*2` MINUS `_current_active_militia(domain_id)` (`SUM(count)` of `source_type='militia' status='active'`), returning `blocked_reason='militia_cap_reached'` at the ceiling. Dead militia are `status='departed'` (not counted → the slot frees) but the family they cost is gone (cap shrank) — so a domain that loses its militia cannot regenerate them indefinitely; the resource is bounded by the population it permanently spent. This mirrors the `available_tribal_warriors` clanhold precedent.
- **Modeling gap flagged for Jedidiah (Layer-1 faithfulness):** the TEMPORARY levy penalties (L429 revenue reduction + L430 morale hit that L431 says "remain until sent home") are NOT modeled at levy time — a pre-existing gap. The permanent-on-death loss is therefore applied directly on death, scaled by death density, rather than by converting a tracked temporary penalty. Defensible given the current system, but the full RAW model would first apply the temporary penalty at levy and make the killed fraction permanent on death. Revisit if temporary domain-levy penalties are ever implemented.


## 101. Player-as-defender extraction — persistent threat + resist/concede; the sync hook decides on RE-ISSUE, not this pass (2026-07-06) [PROVISIONAL]

- **A player-facing choice cannot ride the synchronous resolve hook — surface a persistent threat, decide later.** `ExtractionResistanceRouter.should_proceed` is a `bool` hook called from `ExtractionResolver.resolve`; it CANNOT block on a player's Resist/Concede click. So a player-owned target raises a persistent `hostile_extraction` `domain_threats` row (migration 185) and returns `false` (blocks THIS attempt); the player answers later via `resolve_player_choice(threat_id, "resist"|"concede", day)` from the threats sub-tab, and the decision governs the NEXT extraction pass — never the one that raised it. This is the same "player re-issues after the fact" shape as the interactive-battle limitation (§97); do not try to make the click retroactively credit the blocked attempt.
- **Concede must clear the per-day episode cache before re-running the resolve.** `_episodes` memoizes the gate result per `(domain, army, mode, day)`. On Concede the router sets the threat payload `decision="concede"`, then calls `_clear_episodes_for(domain, army)` BEFORE `ExtractionResolver.resolve(...)` — otherwise the same-day cached `false` short-circuits and the yield is never credited. After the resolve credits, mark the threat `departed` and disband the raider. (Resist is self-contained: materialise the levy + `dispatch_collision`, mark the threat `departed`; the battle governs.)
- **Idempotency is per (domain, raider army), enforced in code AND by a partial-unique index.** Migration 185 adds `idx_domain_threats_unique_active_hostile_extraction ON (domain_id, linked_army_id) WHERE kind='hostile_extraction' AND status='active'` (mirroring the bandit_swarm/challenger unique-active constraints), and `_handle_player_domain` re-finds the active row rather than stacking a second one or re-firing the alert. Multiple *distinct* raiders on one domain are allowed (two aggressors); the same raider re-issuing is not.
- **`ArmyDisbander.disband(reason)` validates `reason` against `VALID_REASONS` — an unlisted reason silently no-ops (returns `success:false`, army NOT disbanded).** Adding a new disband trigger means adding the constant to `VALID_REASONS`, not just passing a new string (added `REASON_RAID_CONCLUDED` for the conceded-raid war-band dispersal; **FIXED 2026-07-06**: also added `REASON_MUSTER_FAILED` — the pre-existing `"muster_failed"` string-literal calls in `extraction_resistance_router._materialize_defender` AND `npc_raid_driver._field_raider` never actually disbanded the half-built army on the muster-failure path; both call sites now pass `ArmyDisbander.REASON_MUSTER_FAILED`). Watch for this whenever you call `disband` with a bespoke reason string — grep `VALID_REASONS` first.
- **`army_unit_assignments.release_reason` is a fixed CHECK enum (`'', 'voluntary', 'casualty', 'desertion', 'disband', 'transfer'`) — an unlisted value fails the CHECK (non-fatal SQL error logged, row left unreleased).** `ExtractionResistanceRouter._demobilize_defender` used to write `release_reason = 'defense_over'`, which isn't a member — **FIXED 2026-07-06**: changed to `'disband'` (already valid, and correct: the levy IS being disbanded, mirroring the `update_army({"state": "disbanded"})` call right after). No migration needed since a valid value already covered the case. When writing to a CHECK-constrained column, verify the literal is an actual member — a silent CHECK failure looks like nothing happened, not like an error the caller sees.
- **Changing a CHECK enum = rebuild the table; the trailing `PRAGMA foreign_keys = ON` is a KNOWN first-run test artifact.** SQLite can't `ALTER` a CHECK, so migration 185 follows the 011/013/133 rename→create→copy→drop→recreate-indexes pattern (create indexes AFTER the `DROP` so the renamed-away index NAMES are free). All those migrations end with `PRAGMA foreign_keys = ON`, which persists on the connection **only for the run that first applies the migration** — and `wipe_for_tests` does parent-before-child deletes that need FKs OFF. So the run that first applies any such migration shows a cascade of `FOREIGN KEY constraint failed` in the wipe (dozens of spurious suite failures); the SECOND run (migration already applied, not re-executed → FKs stay at the default OFF) is clean. This is exactly why the bar is net-zero on the **second consecutive** run — do not chase the first-run FK cascade.
- **`NpcRaidDriver` is a threat-escalation-style driver (over disposition + geography), NOT a ruler-planner action.** It lives beside `ThreatEscalationDriver` in the monthly tick and gates on `crisis_response=="aggressive"` + hex-adjacency to a player domain, so the ruler-AI "defense-only v1" invariant (`gdd-army-warfare.md` §4.10.1) is untouched — no offensive action was added to `RulerActionCatalog`. It fields the raider already AT the frontier hex and issues a **same-hex** loot leg (a real from-hex leg would self-loot the aggressor's own domain, since marching-LOOT does not skip friendly domains like requisition does). Cadence per (target, aggressor) via `RAID_COOLDOWN_DAYS`, read from the latest `hostile_extraction` row's `payload_json.raider_owner_id` (no dedicated table).

## 102. Live LLM Integration L-0/L-1 — the generate() coroutine contract, and the Object.call() indirection for deferred-await tests (2026-07-07) [PROVISIONAL]

- **`LLMManager.generate(context, opts) -> ResponseEnvelope` must execute literally zero `await` statements on the unconfigured/forced-mock path.** This is the load-bearing §5.1 contract of the whole LLM layer: `var env := await LLMManager.generate(ctx)` inside a synchronous test loop only works because the mock path never actually suspends. Any future edit to `generate()`/`_execute_with_retry()` that adds an unconditional `await` before the mock/unconfigured short-circuit silently breaks every consumer that relies on same-frame completion — there's a dedicated test (`test_llm_generate_wall.gd`) guarding this; keep it green.
- **GDScript's static analyzer requires `await` at ANY direct call site to a function whose body contains `await` anywhere — even a bare fire-and-forget statement is fine, but assigning the return value (`var x := coroutine_call()`, typed OR untyped) is not, regardless of whether that branch would actually suspend at runtime.** When a test's whole point is to fire a coroutine and await it *later* (concurrency/coalescing/cancel-mid-flight tests), or to prove a coroutine completes synchronously without forcing the *caller* to become a coroutine itself (the zero-await proof above — `await` here would make `run_all_tests()` async, breaking `test_runner.gd`'s synchronous `_run_suite()` dispatch contract), route the call through `Object.call("method_name", ...)` instead of a direct call. `Object.call()` has a generic Variant return signature, so the analyzer doesn't flag it; the runtime behavior (the deferred awaitable) is unchanged. See `test_llm_generate_async.gd`/`test_llm_generate_wall.gd` for the pattern.
- **The §6.3 stale-context guard must be checked both before AND after any `await` that could let the active campaign change.** A retry-loop guard placed only at the top of a `while true:` loop (before the HTTP await) never re-fires for a request that succeeds on its first attempt — it only protects requests that retry. Re-check immediately after every `await` that crosses a real suspension point, not just at the loop's entry.
- **A `while true:` loop where every branch ends in `return` or `continue` still needs a trailing return statement after the loop.** GDScript's "not all code paths return a value" analyzer does not special-case `while true` as provably non-terminating; add a defensive (genuinely unreachable) `return` after the loop rather than fighting the analyzer.
- Service shape: `engine/subsystems/llm/` is pure `RefCounted`/static services (LLMProvider/MockLlmProvider/OllamaProvider/LlmRequestQueue/PromptAssembler/LlmResponseValidator/LlmTaskRegistry/LlmSettings/LlmUsageTracker) — no new autoload; `LLMManager` (existing autoload) owns orchestration + the HTTP transport pool only. Settings persist via `LlmSettings` ⇄ `user://settings.cfg` (ConfigFile), never SQLite — API keys and provider config are a local-user concern, not campaign state.
- New async test-suite pattern: a suite whose checks require real `await` (not same-frame) cannot run through `test_runner.gd`'s synchronous `_run_suite()` loop (conventions §9.2's existing limitation). Such a suite exposes `run_async_tests() -> void` (a coroutine) alongside a no-op `run_all_tests()`, and is awaited directly from a dedicated "Async suites" block in `test_runner.gd`'s own (now-async) `run()`, after the normal sync dispatch loop. Failures still read through the same `has_failures()`/`fail_count()` surface.

## 103. Faction Framework FF-1 — compute-on-read stance, JSONL audit trails, and the authority split (2026-07-07) [PROVISIONAL]

- **Compute-on-read default stance, lazy instantiation.** `FactionStanceService.get_stance(a, b, day)` never creates a row for an un-instantiated pair — it computes the structural default via `DefaultStanceEvaluator.evaluate(...)` on every read and returns `{instantiated: false, ...}`. A row is only ever created by an explicit `instantiate_stance`/`shift_stance` call or a ledger deed that moves `grievance_score` away from zero. Reusable pattern for any "attitude of A toward B" system where most pairs never actually interact: don't pre-materialize the full N×N matrix.
- **Time-based decay at read time, not on a schedule.** An instantiated stance row whose `last_evaluated_day` is ≥ 336 days (12 game-months) old moves one band toward the current structural default the next time it's *read*, and persists the move + refreshed `last_evaluated_day` — so repeated reads within the same stale window don't rescan or double-decay. Every stance read/write takes an explicit game `day` parameter; never wall-clock.
- **`true_stance` isolation.** Ordinary stance reads (`get_stance`) NEVER return `true_stance` — it is exposed only via an explicitly named dev/audit accessor (`get_stance_full_for_audit`). If you're adding a stance consumer (dialogue, UI, LLM prompt context), use `get_stance`, never the audit accessor.
- **Authority split, enforced at the write layer.** Realm↔realm political state lives ONLY in `realm_relations` (+ `treaties`); a realm-mirror↔realm-mirror pair is REJECTED by `FactionStanceService.instantiate_stance`/`shift_stance` (logged error, no row written). Do not relax this to "just write it anyway" — the whole point is one source of truth per relationship kind.
- **JSONL audit-trail pattern.** `PoliticalAudit` writes one JSON record per evaluation/mutation to a `user://` path, gated by a `ProjectSettings` flag (`factions/debug_political_audit`, in `project.godot`'s `[acks]`-style custom section) — zero file I/O when the flag is off, wall-clock-free and RNG-free records so replaying the same seed produces a byte-identical trace. Use this shape for any future dev-audit trail; it's cheaper than a DB table and doesn't touch the savegame.
- **Shared banker's-rounding helper: `MathUtils.bankers_round(value: float) -> int`** (`engine/shared_types/math_utils.gd`) — the canonical implementation project-wide as of this session; see the corrected §3.3 above. New code must call it, not `roundi()`.
- **PoI controlling-faction linkage already existed, unused.** `settlement_pois.owner_faction_id` and dungeon `pois.faction_id` predate FF-1 — reuse them as "controlling faction," do not add a new column when a system needs to link a PoI to a faction.

## 104. NPC Dialogue Phase 1 — no new autoload, deterministic-summarizer, mock-only reply planner (2026-07-07) [PROVISIONAL]

- **Service shape: `engine/subsystems/dialogue/` is entirely `RefCounted` — no new autoload.** `DialogueSession`/`DialogueContextBuilder`/`DialogueMoveCatalog`/`DialogueTemplateProvider` are constructed by their callers; `DialogueAdjudicator`/`NpcReplyPlanner`/`NpcMemoryStore` are static-only utility classes. Entry-point session/session-runner states own party/runner context and construct the session; `DialogueScreen` (CanvasLayer UI) never touches repositories directly beyond read-only display lookups. Follows the `EncounterScreen`/`CombatController` precedent.
- **Deterministic-summarizer pattern — reusable for any "narrate retroactively" subsystem.** Because every consequential dialogue move is engine-adjudicated, the move log is memory ground truth: `NpcMemoryStore.summarize_move_log` converts it into `facts` tags + a template `summary` with **no LLM call**. This is the always-written mock-path baseline. An LLM (Phase 4) may later rewrite `summary`'s prose but must never touch the engine-derived `facts`. The general shape — engine writes the structured record first, LLM re-skins it later, never the reverse — is the project's standing pattern for any LLM-adjacent subsystem (mirrors Seam A's narration cache and Layer-7's `is_fallback` split).
- **Mock-only reply-planner contract.** `NpcReplyPlanner.plan_reply` is a pure deterministic outcome→plan mapping that never calls `LLMManager.generate()` in Phase 1 — the plan's `template_outcome` key must match `data/dialogue/templates/tier0.json`'s keys exactly, and `DialogueTemplateProvider` renders from the plan. This keeps the whole system CI-runnable offline; the Phase-4 live performer is a drop-in that consumes the identical plan shape.
- **Recall memories at session open, not just the relationship row.** `NpcMemoryStore.recall(campaign_id, npc_id)` (§8.3 top-K, K=6) must be called whenever a `DialogueSession` opens — `DialogueContextBuilder`'s two real entry points (`from_encounter`/`from_settlement_poi`) populate `context["memories"]` themselves; `DialogueSession._open()` additionally recalls as a **fallback only** (skipped if the caller already populated `memories`) for contexts assembled some other way. If you add a third context-building path, either populate `memories` yourself or rely on the session's fallback — don't leave it empty and assume someone else did it.
- **Attitude vocabulary is 5+2, not a flat 7-state enum.** `Attitude` (`engine/shared_types/attitude.gd`) models the core diplomatic ladder as 5 states, with `fearful`/`cowed` as intimidation-only variants layered on top — `npc_relationships.attitude`'s 7-value SQL CHECK matches this shape. Don't assume `Attitude.shift_tier` needs a 7-way linear ladder; check the actual enum before extending attitude-adjacent code.
- New tables: `npc_relationships` (Layer 1, mechanical spine — one row per NPC×party), `npc_memories` (Layer 2, episodic, importance-ranked recall index), `npc_issues` (Layer 3/Track 2 — landed with the rest of the approved data model in one migration even though not consumed until Phase 3, per the project's "land the whole model in one pass" precedent — see §103's Faction FF-1.0 and generation/gdd-quest-rumor-system.md's Q-1 for the same choice).

## 105. Quest & Rumor Q-1 — the dual campaign-deletion-mechanism footgun, and bool-to-SQLite serialization (2026-07-07) [PROVISIONAL]

- **`CampaignRepository` has TWO independent per-campaign deletion mechanisms — update BOTH when adding a campaign-scoped table.** `delete_campaign()`'s hand-rolled `DELETE FROM ... WHERE campaign_id = ?` sequence (actually executed when a player deletes a campaign) and `_campaign_scope_entries()`/`_SCOPE_DIRECT_CAMPAIGN`/`_SCOPE_VIA_*` (used by the savegame snapshot/restore system, and completeness-checked by `test_savegame_snapshot.gd`'s `test_scope_map_covers_all_tables`) are **not the same list twice** — they're separate code paths that happen to need the same table names. A table added to only one of them will silently leak orphaned rows on the OTHER path with no test catching it (only the scope-map path is completeness-tested). When you add a new campaign-scoped table: add it to both, in the same session, and don't assume "I updated the purge cascade" covers `delete_campaign()` too.
- **GDScript `bool` fields must serialize as SQLite `1`/`0` int, not raw bool, before reaching `query_with_bindings`.** godot-sqlite does not implicitly coerce `bool` → `INTEGER` the way it does for other Variant types. Every shared-type `to_dict()` with a bool field needs an explicit `1 if value else 0` (or equivalent) conversion — grep any `*_data.gd`'s `to_dict()` for the pattern before assuming a new bool field will just work.
- Service shape (matches Faction FF-1's §103 and Dialogue's §104): `engine/subsystems/quests/` is `QuestRegistry`/`RumorRegistry` (stateful repositories, constructed with `.new(repository, campaign_id)`) + `RewardValuator` (pure/static) — no new autoload. Future Q-2/Q-3 phases add a signal-driven watcher (`QuestCompletionWatcher`) and a monthly-batch pass (`RumorRegistry.decay_pass`, Q-3), matching the `NpcSyndicateMonthlyResolver`/ruler-AI monthly-tick precedent.
- Land the full approved data model in one migration even when later phases will leave some of it unconsumed for a while (this session's `quests`/`quest_rewards`/`domain_grants`/`rumors`/`rumor_settlement_pool` in migration 192 — `domain_grants`'s single-owner+vassalage consumer is Q-4, `decay_pass`'s consumer is Q-3) — avoids renumbering migrations later and lets sibling in-flight sessions build against a stable schema.

## 106. `String(null)` is an invalid GDScript constructor — coerce nullable DB columns null-safely (2026-07-07)

<!-- Added 2026-07-07 (Wave 1): the same crash bit three separate files across two
     build tracks — promoted to a first-class convention. -->

- **`String(x)` where `x` is a Variant `null` throws "Invalid call. Nonexistent 'String' constructor" at runtime** (not a parse error — it passes `--check-only` and only crashes when the null actually flows through). SQL-NULL columns from a raw repository row (`get_faction`/`get_character`/etc. return the raw dict, and `.get(key, default)` returns the stored `null`, NOT the default, when the key exists with a null value) are the classic source. This crashed `rebel_coalition.gd::launch()` (nullable faction alignment/religion/culture) and `hire_through_dialogue.gd::hireable_as()` (nullable `employer_id`), taking down the entire hot path each sat on.
- **Use a null-safe coercion, never bare `String(row.get(k))`.** The project idiom is a small static helper: `static func _s(v: Variant, default_value: String = "") -> String: return default_value if v == null else str(v)`. For CHECK-constrained columns (e.g. `alignment IN ('lawful','neutral','chaotic')`), pass a valid default (`_s(faction.get("alignment"), "neutral")`), not `""`.
- **`str(x)` is null-tolerant** (`str(null)` → `"<null>"`) where `String(null)` is not — but `"<null>"` is rarely the value you want, so prefer the `_s(v, default)` helper that returns a real default.
- Shared-type `from_dict()` methods already coerce these (that's why round-tripping through a shared type is safe); the danger is reading a RAW repository row dict directly. Prefer the shared type; if you must read the raw row, coerce every nullable string column.
- `--check-only` will NOT catch this (the null is a runtime value). It also false-positives on autoload identifiers (`Identifier not found: EventBus/CampaignRepository/LLMManager/GameState`) — ignore those; only the full runner (which loads autoloads) is authoritative for autoload-referencing code.

## 107. Live LLM L-3 — consumer-wiring patterns (Seam A live, A6 ordered queue, NarrativeUpgrader, Seam B triggers) (2026-07-07) [PROVISIONAL]

- **The awaitable-sibling pattern preserves the no-variance bar by construction.** A live coroutine variant (`RulerActionNarrator.narrate_action_live`) whose only `await` sits inside `if is_configured():` returns same-frame with ZERO awaits under mock — so `var env := await narrate_action_live(...)` in a synchronous test loop is byte-identical to the sync `narrate_action()`. Keep the sync original for template-only/test callers; add the coroutine sibling, don't replace.
- **A6 ordered-pending-queue for any log category that awaits an LLM envelope:** reserve a slot synchronously in emission order BEFORE the await, fill it on resolution, flush head-first stopping at the first unfilled slot. A failed/timed-out head must STILL fill (the narrator always returns a template on failure) so it flushes and unblocks those behind it. `game_log.gd::_ruler_pending_slots` is the reference.
- **Firing a coroutine fire-and-forget from a synchronous engine step** (not a test): `Object.call("method", ...)` (autoload) or `Callable(Class, "method").call(...)` (static) sidesteps the static-analyzer "must be called with await" demand — the same trick §102 documents for tests, now also used in production (`RulerSeamBTrigger.dispatch`, the Seam-A queue).
- **The A3 lock-exempt / hash-excluded pair for a presentation cache on a locked setting:** `setting_narrative` is the ONE lock-exempt `SettingRepository` writer (`save_narrative`, via `_bulk_insert(bypass_lock=true)`) AND is excluded from `SettingDatasetHasher` (presentation, not mechanics — mirrors the `*_placeholder` exclusion for `setting_quests`/`setting_rumors`). Any future presentation-only cache on a locked setting follows this pair; the determinism-hash tests are same-seed-equal, so excluding a table doesn't break them.
- **Seam-B trigger contract:** significance sites (`siege_started` → stronghold.domain_id → owner; `domain_conquered` → the ruler who lost it; `domain_morale_changed` with `new_morale <= -2` Turbulent) dispatch `RulerStrategyReassessor.reassess` via a single `RulerSeamBTrigger` (hosted at `GameLog._ready`, mirroring Seam A), with a per-ruler 1-game-month cooldown (bucket = `floor(get_calendar_day() / DAYS_PER_MONTH)`, no wall-clock). Handlers are INERT under mock (gate on `is_configured()`), so they add zero DB queries during normal play and fire the moment a provider lands. Validation is NEVER relaxed on the live path (bare `issue_decree` bias key stays rejected, §93).

## 108. Faction FF-3 — realm-politics monthly step, the SeededDice seam, and the rebellion state machine (2026-07-07) [PROVISIONAL]

- **Realm politics runs INSIDE the sovereign's `RulerAI.process_campaign_month` turn, gated on `is_sovereign`** (personal domain is a realm apex — `liege_domain_id` NULL) — NOT a separate monthly-tick pass. Treaty renewal/expiry, petition/appeal adjudication, and own-vassal plot advancement run there, before planner-action scoring, stored under `report['realm_politics']`. Vassals never get a separate step; they act only through loyalty/compliance, keeping monthly cost linear in ruler count.
- **The `SeededDice` determinism seam** (`engine/shared_types/seeded_dice.gd`): production paths needing a seeded `dice` resolver (`roll(count, sides)`) build `SeededDice.for_monthly(actor_id, calendar_day, tag)` — the same per-(actor, month) hash-seed idiom as `RulerActionScorer.monthly_rng`, but wrapped in the FakeDice-compatible `roll()` contract so production and tests share ONE interface. Never pass `null` to a `dice` seam in production (it falls back to un-seeded `randi` and breaks replay).
- **Diplomacy actions are active-LOD-sovereign-only and weight-gated** (`diplomatic_weight`/`expansion_weight`) — the war-ceiling raise (§5.6) lifts the ruler-AI defend-only ceiling for those rulers ONLY; backdrop/regional-LOD rulers keep it. Register a new ruler action in `ruler_action_catalog.gd` (`ACTION_IDS`) AND give it a distinct `RulerActionNarrator` Seam-A phrase in `data/templates/ruler_action_templates.json` — the `test_narration_covers_all_action_ids` distinct-template check fails if you add an action id without a phrase (it collides on `_default`). This is a required paired edit.
- **`declare_war` reuses the army-warfare seam, not a new offensive pipeline:** it registers an `npc_challenger` `domain_threat` on the target sovereign; `ThreatEscalationDriver` fields the force + dispatches on the target's next active-LOD turn.
- **Rebellion is a state machine on `faction_plots`** (SEED → SOUND OUT → READY → LAUNCH → RESOLVE) with a §7.4 secrecy countdown; LAUNCH flips committed domains to a NEW rebel realm-mirror (`create_realm` + `ensure_realm_mirror` + re-point `domains.realm_id`/null `liege_domain_id`). Full liege-chain re-parenting stays with the realms-titles path; RESOLVE records intent + ledger, it does not fabricate domain surgery. **FF-3/FF-4 boundary:** FF-3 builds the rebellion secret-loyalty-rolls + plot secrecy ONLY; the third-party `AllegianceEvaluator`/feign-betrayal is FF-4 (needs FF-2 orgs).
- **When a project subsystem reuses a RAW resolver that returns STATE-TRANSITION keys, persist AND consume them — don't just read the outcome band (2026-07-08).** `HenchmanLoyaltyResolver.resolve_loyalty_check(morale, is_grudging, is_fanatic, dice, extra)` takes carryover flags as INPUT (Grudging −1 next roll, Fanatic +2 all future rolls, RAW §2.2 `acore_equipment.xml:806-808`) and returns `set_fanatic`/`clear_grudging` as OUTPUT state transitions. Vassal loyalty (`VassalLoyaltyResolver.roll_for_trigger`) originally passed `false,false` and read only `outcome` — silently dropping the RAW carryover. The fix stores `vassal_assignments.loyalty_is_fanatic` (persistent) + `loyalty_grudging_pending` (one-shot), reads them into the resolver, and rolls them forward exactly like the henchman consumer (`HenchmanLifecycleManager.trigger_loyalty_check`): `if clear_grudging → false; if set_fanatic → true; if outcome==GRUDGING → grudging=true`. **The §5.3 compliance-behavior tag (how a vassal responds to requests) and the RAW dice carryover (how the next loyalty ROLL is modified) are BOTH needed — the tag is not a substitute for the roll modifier** (Jedidiah's ruling: the +2 prevents insane one-roll Fanatic→Hostile swings). If you reuse a RAW resolver anywhere, wire its returned transition keys through to storage; reading only the band loses the roll-to-roll memory.

## 109. Dialogue Phase 2 — StatusProfile evidence assembler, two-resolver discipline, wrap-don't-reimplement hiring (2026-07-07) [PROVISIONAL]

- **StatusProfile is an EVIDENCE ASSEMBLER, never an aggregate dice score (§7.1).** `StatusProfileBuilder` gathers reputation + memories + titles + worn-equipment into a struct whose `to_resolver_context()` emits ONLY RAW modifier-line keys (`personally_harmed`/`harmed_friends_*`/`has_legal_authority`/`brandishing_*`/`favors_*`). The project-designed `status_tier`/`dress_quality` are DELIBERATELY excluded from that method so they can never reach the sacred tone tables — `status_tier` feeds only the §6.5 per-issue differential. When adding evidence, map it to an EXISTING `InteractionResolver` context key; do not invent a new dice line.
- **Harm evidence is highest-tier-wins → exactly ONE RAW threat line, not additive:** `personally_harmed` (−5) OR `harmed_friends_witnessed` (−5) OR `harmed_friends_belief` (−2). A personally-witnessed NPC grudge memory escalates above the reputation hearsay floor.
- **Two-resolver discipline:** Track-1 tone rolls go through `InteractionResolver` (owns the reputation cascade). Track-2 per-issue rolls go through `PerIssueResolver` (reuses `InteractionResolver._apply_sacred_modifiers` for the tone stack + `already_attitude` line but does NOT re-apply reputation; its modifiers are request-framing + relationship + terms + status-differential). The status-differential modifier is Track-2 ONLY.
- **Wrap-don't-reimplement for hiring:** `HireThroughDialogue` is a thin wrapper over `henchman_lifecycle_manager` (`attempt_hire`/`finalize_hire`) that adds only the interview's ±1 situational modifier, disposition classification, and the §11.4 slander delta via the existing `ReputationSystem`. Reuse `henchman_hired`; add no hiring machinery.
- **Session-scoped pending state for offer moves:** `_pending_bribe_quality` is consumed by the next influence attempt; `_pending_terms_modifier` by the next dependent hire/if_paid-knowledge move (persisted to `npc_issues.terms`). Knowledge lives in `characters.personality.knowledge` (JSON), NOT a new table — `ask_question` tolerates empty knowledge (hidden from the menu; resolves `no_knowledge`, never a crash or a lie — lie fabrication is Phase 3).
- **RAW modifier lines can be TONE-SCOPED — check which reaction block a rule lives in before wiring it (2026-07-08).** `ax_reactions_and_influencing.xml` has separate modifier blocks per tone: diplomatic (:77-113), intimidation (:165-205), seduction (:243-324). The "+1 per noble rank or equivalent" status line lives ONLY inside `<seductive_interactions>` (:253-254), so it is wired into `InteractionResolver._apply_seduction` alone — NOT the diplomatic/intimidation stacks. A `StatusProfile` evidence key (`noble_ranks`) may ride in the shared resolver context but be consumed by only one tone's `_apply_*`; that's the intended scoping, not a bug. Before adding a RAW modifier, `acks-raw-lookup` the exact block it appears under and scope it there.
- **Bribery is gated on the Bribery proficiency (RAW `ax_reactions:96`).** `offer_bribe` sets `ctx["has_bribery"]` from `DialogueSession._speaker_has_bribery()` (catalog key `"bribery"`, rank ≥ 1), NOT unconditionally — the gold is still escrowed without the proficiency, but the +1..+3 reaction bonus only applies with it (the resolver's `prof_bribery` block is gated on `has_bribery`, applying +0 when false). Bribe QUALITY is per-target: `DialogueAdjudicator.bribe_quality_for_amount(amount_cp, target_level)` keyed to `HenchmanTables.monthly_wage(level)` (both cp; ≥ 1 day's/week's/month's pay → +1/+2/+3). Dress bands are catalog-anchored (`acore_equipment.xml:220-244` clothing prices: serf 2gp … noble 100gp … duchess's gown 1000gp), not a round-number guess.

## 110. Quest Q-2/Q-3/Q-4 — abstract-handle LOD seeding, session-scoped watchers, repo-seam cross-writes (2026-07-07) [PROVISIONAL]

- **Setting-gen seeding writes ONLY ctx dicts** (`ctx["setting_quests"]`/`["setting_rumors"]`, persisted by `setting_generator._run_infrastructure`) — it NEVER touches the runtime `characters`/`quests` tables (setting-gen produces a setting dataset, not a campaign DB). Questgivers are ABSTRACT `qg_<settlement_id>` handles at seed time, promoted to full NPCs on approach (the PoI seed→runtime LOD precedent). Keeps the whole seeding pass pure w.r.t. the runtime DB.
- **INSERT parent-before-child is the REVERSE of the DELETE order:** a quest-sourced rumor's `source_quest_id` FKs `setting_quests(id)`, so seed `setting_quests` before `setting_rumors`, even though `SettingRepository._DATA_TABLES` deletes children-first.
- **Session-scoped signal watchers** (`QuestCompletionWatcher`) are instantiated per `load_session` with `register_listeners()`/`unregister_listeners()` — exactly like `PoiEmergenceHandler`/`BaselineNpcStocker`, NOT autoloads, re-created on campaign switch.
- **Cross-subsystem DB writes from a repository-injected service go through a `CampaignRepository` seam method,** not a direct call to the other subsystem's repository — e.g. `QuestRegistry` writes vassalage via `CampaignRepository.create_vassal_assignment` (delegating to `VassalRepository`), so unit-test fakes opt out cleanly via `has_method()`.
- **Personality-gated decisions take the axes as parameters** (`disburse_reward_unaccepted(attitude, honesty, self_interest)`) resolved by the caller, since no persistent `honesty` column exists yet — keep the service storage-agnostic and forward-compatible.
- **Monthly-tick batch steps that must run WITHOUT domains** (rumor `decay_pass` — rumors exist without domains) go AHEAD of the `domains.is_empty()` early-return, in the §10.1 order, `NpcSyndicateMonthlyResolver` batch style (no `auto_pause`/LLM).

## 111. Faction FF-2 Organizations — org-month batch, deterministic seeding, the shared tithe decree, and the party-isn't-a-faction ledger rule (2026-07-08) [PROVISIONAL]

- **`FactionAI.process_campaign_month(campaign_id, calendar_day, active_settlements)` mirrors `RulerAI`'s shape** and slots into `domain_handlers._handle_monthly_tick` immediately AFTER the syndicate/venture resolvers and BEFORE `RulerAI` — the proven monthly-batch order. Within the pass, **resolve the ledger first, then select the action** (income before choice — the ruler-planner post-resolution precedent). Active-LOD gated; backdrop orgs take no turns.
- **Deterministic org ids give seeding idempotency with no dedup pass:** `org_synd_<sid>`, `org_temple_<settlement>_<religion>`, `org_church_<realm>_<religion>`, `org_<type>_<settlement>`. `OrgSeeder.backfill_campaign` is safe to re-run at every materialization (it mirrors the FF-1.1 realm-mirror hook in `setting_materializer`); the deterministic ids make a rebuild byte-identical. Seed keyed to `hash(campaign_id)`.
- **The ¼-wages ledger rule** (`FactionLedgerResolver`): non-syndicate org monthly net = ¼ × Σ(members' Henchman-Monthly-Fee wages), banker's rounding, accumulating in `treasury_gp`; temples add the tithe share. **`syndicate` and `merchant_guild` (Venturer-class syndicate) are PASSTHROUGH — never re-resolve their treasury** (the `NpcSyndicateMonthlyResolver`/`VentureMonthlyResolver` already own it; a second income path double-counts). Negative treasury fires the RAW consequences (congregant departure, unpaid-loyalty, `survive` goal).
- **Tithe apportionment is ONE shared engine path for player and NPC rulers:** `issue_decree(decree_kind="tithe_apportionment", params.shares={faction_id:pct})` — an additive `decree_kind` riding the EXISTING `issue_decree` handler (never fork the handler; same pattern the Seam-A `decree_kind` uses). `TitheApportionment.apply` validates sum-100 + temple-present; the player Tithe panel and NPC lobbying both route here so reactions fire identically regardless of who decreed.
- **The party is NOT a faction:** a faction quest turn-in writes `reputation_entries` (scope=`faction`, the §8.3 party↔faction ledger) + debits the org treasury — NOT a `faction_events` row (that table is strictly inter-faction, two faction ids). Reuse the reputation seam for any party→faction standing change.
- **`FactionActionNarrator` is a verbatim `RulerActionNarrator` clone** with an in-memory static cache (factions carry no `narration_cache` column — that lives on `ruler_ai_state`); the player-relevance gate (met / same-settlement / instantiated stance) suppresses non-relevant factions — the ruler-seam anti-spam rule.
- **The FF-2/FF-4 line:** actions that reduce to FF-4 machinery (`undermine_rival` = covert op §6.7; `declare_stance` = allegiance evaluator §7) are registered in the action vocabulary as **inert stubs** — `goal_relevance` 0 so the scorer never selects them, handler returns `{deferred_to:"FF-4"}`. FF-4 lights them up without a vocabulary change.
- **A faction-goal quest predicate = a persisted `progress.goal_satisfied` flag** the faction layer sets and `QuestCompletionWatcher.poll_faction_goals` reads monthly (idempotent, migration-free) — the "faction goal state" is that flag, not a live cross-subsystem query. **The production trigger** (Q-6, 2026-07-08): `FactionAI._maybe_satisfy_posted_jobs` fires after a *successful* goal-advancing org action and calls `QuestRegistry.satisfy_faction_goal_quests(faction_id, advanced_goals)`, which satisfies only the faction's **accepted** open jobs (an untaken posted job must NOT auto-complete). A poll-flag with no production caller is a dead loop — always wire the trigger, and cover it with a test that exercises the *production path*, not one that calls the satisfier directly (the latter masks the missing caller). v1 ties completion to the faction visibly advancing its aim; a concrete party-deed model is deferred design.
- **The org affordability gate** (`FactionAI._score_candidates`): the spend base is the post-income `treasury` (the ledger's `treasury_after`, already banked) — do NOT also add `total_income_gp` (that double-counts the month's earnings). Cost-0 fallbacks (hold, raise_funds, survival moves) are ALWAYS affordable (`if cost > 0 and cost > treasury`) so a broke org can still act its way out; `hold` stays the anti-thrash floor even at negative treasury.
- **`_apply_negative_treasury` must NOT persist `goal_primary`** — the survive posture is condition-derived each month from the treasury (`forced_survive`); overwriting the authored goal has no restoration path and permanently erases the org's identity after one deficit month. Persist only the roster shrink; report the transient posture in the return.
- **Declared action costs must actually be debited by the handler**, not merely gate affordability (`_do_court_patron` debits its 100 gp) — otherwise the "cost" is fiction and the action is free every turn.

## 112. Dialogue Phase 3 — the request_action template, Seam-B adjudication, the deterministic lie engine, and the minimal charm-defection combat hook (2026-07-08) [PROVISIONAL]

- **`request_action` is a data-defined matrix** (`data/dialogue/requestable_actions.json`, keyed by class/role/proficiency predicate → owning-subsystem handoff). The rule-10.2 gate (`RequestableActionsMatrix.is_known`) rejects any LLM-suggested action not in the registry. **Resolution template for every row:** attitude gate → `PerIssueResolver` per-issue roll → `offer_terms` where payment applies → deterministic handoff to the owning subsystem → `EventScheduler` carries deferred completion. **Dialogue initiates; the owning subsystem executes and owns the outcome** — dialogue never resolves the spell/hijink/research itself. `mobile`/`combat_capable` predicate flags default false (opt-in) so `request_action` doesn't surface on every plain NPC.
- **Seam-B `persuade_ruler` computes strength deterministically** (`RulerAudience.persuade`): `persuasion_strength = issue-band base (0.8/0.6/0.4; refuse→0) + min(concessions×0.1, 0.3) + crisis(±0.2)`, clamped. It routes through `RulerStrategyReassessor.apply_validated` — **do NOT relax that validation** (unknown `target_action_id` is strict-rejected, exactly like a bad bias key). `urge` supports only v1-catalog (defensive/economic) actions; urging offensive war is ruler-AI v2 — refuse gracefully, the packet shape is reserved.
- **The lie decision AND the lie content are engine-side, never the LLM's** (`DeceptionEngine`): the decision is deterministic (the §9.4 trigger set); the false content is a `misleading`/`false` accuracy variant (rumor machinery reused) or a template; a `deception_by_npc` memory keeps the NPC consistent forever after. **Detection is deduction, not a die:** every reply carries a demeanor beat (present on ALL replies, so its presence is never a tell); a seeded composure roll makes a lie leak or hold, and an honest-noise roll emits false-positive beats. No player-side detection roll in v1.
- **`NpcIntentPolicy.select` attaches ≤1 NPC-initiated move per ~3 exchanges**, seeded/deterministic; the mock provider performs every NPC move from templates (the P3/P4 line: P3 produces the engine DECISION on the mock path — which reply is a lie, the beat, the NPC move, the parley/audience resolution — and live-LLM performance is P4).
- **Charm defection reuses the mutable `Combatant.side` field** — the minimal-additive combat capability: `CombatRoster.apply_charm_defection` records `pre_charm_side` and moves the PC to the charmer's side; `end_charm_defection` restores it. Because every existing turn/targeting read (`get_alive_on_side`, `get_enemy_combatants`, …) already reads `.side`, no other combat code changes — the whole feature is two `Combatant` fields + four roster methods. When you must add cross-subsystem state mid-feature, prefer overriding an existing honored field over threading a new flag through every reader.
- **Variant-inference gotcha (recurring):** `var x := NpcIntentPolicy.select(...)` fails under warnings-as-errors because `select` returns a Dictionary-or-`null` (untyped Variant). Use plain `var x = ...` for nullable returns — you can't type them `: Dictionary` (Dictionary is non-nullable in GDScript 4). Helpers that return a concrete non-null type (`compose_beat -> Dictionary`, `.new()`) keep `:=` fine.

## 112. Dungeon Faction Generation — deterministic, dungeon-scoped, input-graph-driven (Wave 3 Track D, 2026-07-09) [PROVISIONAL]

Subsystem at `engine/subsystems/generation/dungeon_factions/` (gdd-dungeon-factions.md). Turns dungeon-stocking output into factions/territory/relationships. Consumes dungeon-generation output; produces `DungeonFaction` records for FF-5, the combat engine, the wandering-monster system, and reaction rolls.

- **Entry point:** `DungeonFactionGenerator.generate(input: DungeonFactionInput, seed: int) -> DungeonFactionGenerationResult`. PURE generation — no DB / EventBus / LLM. Deterministic + replayable: same input + seed → byte-identical output. RNG only in name templates (`FactionNames`) and relationship rolls (`RelationshipGenerator`), each on an isolated sub-stream (`seed + 0x1111` / `seed + 0x2222`) so adding a faction never shifts the relationship roll and vice-versa.
- **The generator works off an ABSTRACT room graph (`DungeonFactionInput`), not `DungeonLayout` directly.** This decouples the deterministic core from the DG-V1 grid so the golden test builds a hand-authored input. `DungeonFactionInputBuilder.from_layout(layout, dungeon_id)` is the real DG-V1 adapter (rooms + corridor-component adjacency + catalog traits via `MonsterFactionTraits`); it is the integration seam that needs in-engine verification (never exercised by the golden test).
- **`MonsterGroupData` lacks intelligence / monster_types / per-creature HD / organization.** The faction identifier needs all of them (§3), so the input placement (`DungeonFactionMonsterPlacement`) carries them explicitly; the adapter fills them from `data/monsters/monster_catalog.json` (intelligence values: non/animal/low/average/high — ACKS "semi" is collapsed there; the code still handles semi = pack-if-organized).
- **Territory = nearest-lair flood-fill through WIDE-OPEN passages only.** `TerritoryAssigner._traversable` = `kind == KIND_OPEN and width_ft >= 10`; every door/narrow/strong/stair edge is a defensible chokepoint the faction claims UP TO but not across (§4.3.2). Member (core) rooms are always controlled regardless of the doors between them. Rooms occupied by a non-faction monster (an uncontrolled hazard) are NOT claimable → unclaimed.
- **Awareness (§5.2) is the synthesis of §4.3 + §5.2, NOT the literal §5.2:** two factions are UNAWARE when a strong-boundary door (locked/barred/stuck/secret) separates their territories OR > 8 unclaimed rooms lie between them (`FactionGraph.is_aware`, a 0/1-BFS counting only unclaimed rooms). A locked door yields unawareness even at 1 room apart — matches the §12 worked example (goblins ↔ cult), which the literal §5.2 (secret-door-only) would miss.
- **`gdd-dungeon-factions.md` §12's printed territory map contradicts its own faction summaries on rooms 6 and 12 (map says unclaimed; summaries claim them).** The flood-fill is Voronoi-consistent with the SUMMARIES (room 6 = goblin frontier, room 12 = unclaimed across a single-corridor chokepoint) and matches 14/15 rooms of the printed map. The golden test asserts the flood-fill result and documents the deviation.
- **A lone powerful intelligent monster is a SOLITARY THREAT, not a 1-room faction (§3.3).** Every eligible intelligent species first becomes a candidate; the identifier then RECLASSIFIES any candidate that is one creature / one room / one species / one placement — 4+ HD or special-abilities → `DungeonSolitaryThreat`, weaker → dropped (independent encounter, no record). A group (number > 1) or a controller (has a controlled secondary species, e.g. necromancer + skeletons) stays a faction even in one room. Uncontrolled unintelligent undead form no faction (§2.1); controller linkage is explicit (`controlled_by_species`) — the DG-V1 adapter does not infer it (DG-V1 stocking emits no control relation yet).
- **Persistence is dungeon-CONTENT (migration 201), NOT `_SCOPE_DIRECT_CAMPAIGN`.** `dungeon_factions` / `dungeon_faction_relationships` / `dungeon_solitary_threats` key on `dungeon_id` (no FK / no campaign_id — the dungeon id lives in `dungeon_entrances.dungeon_data` JSON) and purge dungeon-scoped in `CampaignRepository._campaign_scope_entries()` (the same `dungeon_scoped` block as `monster_groups`). Room references ride as JSON int arrays on each record; the territory map is REBUILT from those on load (not its own table). `DungeonFactionRepository` is a static-method RefCounted reaching through `CampaignRepository.db` (the DG-V1 repository pattern). Runtime-mutable state (population, alert, morale) round-trips through savegame (§79).
- **`DungeonFaction` (the §7.1 record) is built additively-extensible for FF-5:** `from_row`/`to_row` use `Dictionary.get` with defaults so a later migration + two field additions (`parent_faction_id`, `allegiance_kind`, gdd-faction-framework.md §9) need no rewrite. Do NOT add those two fields in Track D. Alignment uses the lowercase catalog convention (lawful/neutral/chaotic), matching `monster_catalog.json` and `FactionData`.
- **Wave-3 signals live in one `# --- Wave 3 Dungeon Factions ---` block in `event_bus.gd`:** `dungeon_factions_generated(dungeon_id, faction_count)` (emitted by the repository on save), `dungeon_faction_alert_changed(...)` (AlertPropagation, on an actual escalate/decay transition), `dungeon_faction_wiped_out(...)` (FactionWandering, on the population→0 transition). The pure generator emits nothing.
