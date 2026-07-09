class_name DungeonFaction
extends RefCounted

## A dungeon faction — the primary strategic unit of dungeon-level play
## (`gdd-dungeon-factions.md` §7.1). Produced by DungeonFactionGenerator from
## dungeon-stocking output; consumed by the combat engine (alert propagation,
## reinforcements), the wandering-monster system, reaction rolls, and encounter
## narration.
##
## NOT the campaign-scoped FactionData (realm/organization/warband). This is a
## generation-time record scoped to a single dungeon + level, mutated at runtime
## as members are killed / alerted / replenished. Persisted dungeon-scoped (keyed
## on dungeon_id) by DungeonFactionRepository, NOT into the `factions` table.
##
## FF-5 EXTENSIBILITY: gdd-faction-framework.md §9 will append two fields to this
## record — `parent_faction_id` (link to an external `factions` row) and
## `allegiance_kind`. This record is built additively (from_row/to_row use
## Dictionary.get with defaults) so those columns can be added by a later
## migration + two field additions with no consumer breakage. Do NOT add them
## here — that is the FF-5 build.


# ---------------------------------------------------------------------------
# Vocabularies
# ---------------------------------------------------------------------------

## faction_type values (§7.1). Matches the dungeon warband subset of
## FactionData.TYPES so a future FF-5 promotion to an `organization` faction is
## vocabulary-compatible.
const TYPE_TRIBAL := "tribal"
const TYPE_MILITARY := "military"
const TYPE_CULT := "cult"
const TYPE_PACK := "pack"
const TYPE_COALITION := "coalition"
const TYPE_UNDEAD_HORDE := "undead_horde"

const VALID_TYPES: Array[String] = [
	TYPE_TRIBAL, TYPE_MILITARY, TYPE_CULT, TYPE_PACK, TYPE_COALITION, TYPE_UNDEAD_HORDE,
]

## Alignment uses the lowercase catalog convention ("lawful"/"neutral"/"chaotic"),
## matching data/monsters/monster_catalog.json and FactionData.ALIGNMENTS.
const ALIGNMENTS: Array[String] = ["lawful", "neutral", "chaotic"]

## Alert states (§8). Ordered weakest→strongest; index used by alert decay.
const ALERT_UNAWARE := "unaware"
const ALERT_CAUTIOUS := "cautious"
const ALERT_ALERTED := "alerted"
const ALERT_MOBILIZED := "mobilized"

const ALERT_LADDER: Array[String] = [
	ALERT_UNAWARE, ALERT_CAUTIOUS, ALERT_ALERTED, ALERT_MOBILIZED,
]


# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

var id: String = ""
var dungeon_id: String = ""
var dungeon_level: int = 1

var name: String = ""
var species: String = ""                  ## primary species id (e.g. "goblin")
var secondary_species: Array[String] = []  ## coalition members beyond `species`
var alignment: String = "neutral"
var faction_type: String = TYPE_TRIBAL

# ---------------------------------------------------------------------------
# Leadership
# ---------------------------------------------------------------------------

var leader_npc_id: String = ""            ## "" until the NPC personality record exists
var leader_room_id: int = -1
var leader_hd: float = 0.0

# ---------------------------------------------------------------------------
# Population (mutated at runtime by FactionWandering)
# ---------------------------------------------------------------------------

var starting_population: int = 0
var current_population: int = 0
var patrol_size: String = "1d4"           ## dice expression for wandering encounter size
var members_on_patrol: int = 0

# ---------------------------------------------------------------------------
# Territory (room ids are DungeonRoomData.id within the level)
# ---------------------------------------------------------------------------

var lair_room_ids: Array[int] = []
var core_room_ids: Array[int] = []
var patrol_room_ids: Array[int] = []
var frontier_room_ids: Array[int] = []

# ---------------------------------------------------------------------------
# Relationships (in-memory convenience list; the authoritative list lives on
# DungeonFactionGenerationResult.relationships and its own persistence table).
# ---------------------------------------------------------------------------

var relationships: Array = []             ## Array[DungeonFactionRelationship]

# ---------------------------------------------------------------------------
# Behavioral / runtime
# ---------------------------------------------------------------------------

var alert_state: String = ALERT_UNAWARE
var default_reaction_modifier: int = 0

## Twelve-axis mean-shift applied as the FACTION step of the NPC personality bias
## stack (§2.2 / gdd-npc-personality.md §4.1). { axis_name: float in [-2.0,+2.0] }.
var personality_weight_biases: Dictionary = {}

# ---------------------------------------------------------------------------
# Morale tracking
# ---------------------------------------------------------------------------

var morale_modifier: int = 0
var population_loss_percent: float = 0.0


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------

## Every room id this faction has any claim to (lair ⊆ core; the four lists are
## disjoint except lair ⊆ core by construction).
func all_room_ids() -> Array[int]:
	var out: Array[int] = []
	for r in core_room_ids:
		out.append(r)
	for r in patrol_room_ids:
		if not out.has(r):
			out.append(r)
	for r in frontier_room_ids:
		if not out.has(r):
			out.append(r)
	return out


## True once every member is dead (§6.2 step 5 — faction is wiped out).
func is_wiped_out() -> bool:
	return current_population <= 0


## True while the faction still physically holds a lair room (needed for
## replenishment, §6.2 step 6). A caller drives lair loss by removing ids from
## lair_room_ids; this only reports the invariant.
func holds_lair() -> bool:
	return not lair_room_ids.is_empty()


## Recompute population_loss_percent from starting/current. Called after any
## population change so morale-threshold checks read a fresh value.
func refresh_loss_percent() -> void:
	if starting_population <= 0:
		population_loss_percent = 0.0
		return
	var lost: int = starting_population - current_population
	if lost < 0:
		lost = 0
	population_loss_percent = float(lost) / float(starting_population)


# ---------------------------------------------------------------------------
# Persistence (dungeon-scoped row; Array/Dictionary fields ride as JSON TEXT).
# ---------------------------------------------------------------------------

## DB-ready dictionary (arrays + biases encoded as JSON strings). The repository
## binds these directly.
func to_row() -> Dictionary:
	return {
		"id": id,
		"dungeon_id": dungeon_id,
		"dungeon_level": dungeon_level,
		"name": name,
		"species": species,
		"secondary_species": JSON.stringify(secondary_species),
		"alignment": alignment,
		"faction_type": faction_type,
		"leader_npc_id": leader_npc_id,
		"leader_room_id": leader_room_id,
		"leader_hd": leader_hd,
		"starting_population": starting_population,
		"current_population": current_population,
		"patrol_size": patrol_size,
		"members_on_patrol": members_on_patrol,
		"lair_room_ids": JSON.stringify(lair_room_ids),
		"core_room_ids": JSON.stringify(core_room_ids),
		"patrol_room_ids": JSON.stringify(patrol_room_ids),
		"frontier_room_ids": JSON.stringify(frontier_room_ids),
		"alert_state": alert_state,
		"default_reaction_modifier": default_reaction_modifier,
		"personality_weight_biases": JSON.stringify(personality_weight_biases),
		"morale_modifier": morale_modifier,
		"population_loss_percent": population_loss_percent,
	}


static func from_row(data: Dictionary) -> DungeonFaction:
	var f := DungeonFaction.new()
	f.id = _s(data, "id")
	f.dungeon_id = _s(data, "dungeon_id")
	f.dungeon_level = int(data.get("dungeon_level", 1)) if data.get("dungeon_level") != null else 1
	f.name = _s(data, "name")
	f.species = _s(data, "species")
	f.secondary_species = _decode_str_array(_s(data, "secondary_species"))
	f.alignment = _s(data, "alignment", "neutral")
	f.faction_type = _s(data, "faction_type", TYPE_TRIBAL)
	f.leader_npc_id = _s(data, "leader_npc_id")
	f.leader_room_id = int(data.get("leader_room_id", -1)) if data.get("leader_room_id") != null else -1
	f.leader_hd = float(data.get("leader_hd", 0.0)) if data.get("leader_hd") != null else 0.0
	f.starting_population = int(data.get("starting_population", 0)) if data.get("starting_population") != null else 0
	f.current_population = int(data.get("current_population", 0)) if data.get("current_population") != null else 0
	f.patrol_size = _s(data, "patrol_size", "1d4")
	f.members_on_patrol = int(data.get("members_on_patrol", 0)) if data.get("members_on_patrol") != null else 0
	f.lair_room_ids = _decode_int_array(_s(data, "lair_room_ids"))
	f.core_room_ids = _decode_int_array(_s(data, "core_room_ids"))
	f.patrol_room_ids = _decode_int_array(_s(data, "patrol_room_ids"))
	f.frontier_room_ids = _decode_int_array(_s(data, "frontier_room_ids"))
	f.alert_state = _s(data, "alert_state", ALERT_UNAWARE)
	f.default_reaction_modifier = int(data.get("default_reaction_modifier", 0)) if data.get("default_reaction_modifier") != null else 0
	f.personality_weight_biases = _decode_biases(_s(data, "personality_weight_biases"))
	f.morale_modifier = int(data.get("morale_modifier", 0)) if data.get("morale_modifier") != null else 0
	f.population_loss_percent = float(data.get("population_loss_percent", 0.0)) if data.get("population_loss_percent") != null else 0.0
	return f


## Coerce a nullable DB string column to a default ("" unless overridden).
static func _s(data: Dictionary, key: String, default_val: String = "") -> String:
	var v: Variant = data.get(key, default_val)
	return String(v) if v != null else default_val


## Parse a JSON int array, coercing JSON's float numbers back to int.
static func _decode_int_array(json_text: String) -> Array[int]:
	var out: Array[int] = []
	if json_text == "":
		return out
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Array:
		for v in parsed:
			out.append(int(v))
	return out


static func _decode_str_array(json_text: String) -> Array[String]:
	var out: Array[String] = []
	if json_text == "":
		return out
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Array:
		for v in parsed:
			out.append(String(v))
	return out


static func _decode_biases(json_text: String) -> Dictionary:
	if json_text == "":
		return {}
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Dictionary:
		return parsed
	return {}
