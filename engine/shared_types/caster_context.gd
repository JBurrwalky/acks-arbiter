class_name CasterContext
extends RefCounted

## Immutable snapshot of a caster at cast time. Built once when the player
## commits a cast; consumed by CastingResolver. Decouples resolution from the
## live CharacterData so a cast taken during a long resolution sequence sees
## consistent inputs.
##
## `map_context` is one of: "combat_grid" | "dungeon_grid" | "wilderness_hex" |
## "settlement_node". Only the position field for the active context is
## populated; the others are left at default. The resolver dispatches geometry
## queries against `map_context`.

var caster_id: String = ""
var caster_name: String = ""
var caster_level: int = 1
var caster_class: String = ""
var tradition: String = ""               # "arcane" | "divine"
var casting_stat_bonus: int = 0          # INT bonus arcane, WIS bonus divine
var alignment: String = "neutral"        # "lawful" | "neutral" | "chaotic"

# Position fields (only one is populated per map_context).
var current_position: Vector3i = Vector3i.ZERO  # combat_grid / dungeon_grid
var hex_position: Vector2i = Vector2i.ZERO       # wilderness_hex
var settlement_node_id: String = ""              # settlement_node
var map_context: String = "combat_grid"

var active_proficiencies: Array = []     # Array[String] of proficiency_keys
var is_in_combat: bool = false

# Disruption-relevant state at cast time. Read by validation step 4.
var is_prone: bool = false
var can_move_hands: bool = true
var can_speak: bool = true
var is_in_silence_area: bool = false


static func from_character_data(
        cd: CharacterData,
        map_context_str: String,
        tradition_str: String,
        casting_stat_bonus_value: int) -> CasterContext:
    ## Production factory. Tradition and casting_stat_bonus are computed
    ## upstream by the caller (typically the resolver) which has the registries
    ## needed to derive them. Position is left at default — the caller sets
    ## the appropriate position field based on map_context.
    var ctx := CasterContext.new()
    ctx.caster_id = cd.id
    ctx.caster_name = cd.name
    ctx.caster_level = cd.level
    ctx.caster_class = cd.character_class
    ctx.tradition = tradition_str
    ctx.casting_stat_bonus = casting_stat_bonus_value
    ctx.alignment = cd.alignment
    ctx.map_context = map_context_str
    var prof_keys: Array = []
    for p in cd.proficiencies:
        prof_keys.append(p.get("proficiency_key", ""))
    ctx.active_proficiencies = prof_keys
    return ctx
