class_name PartyData
extends RefCounted

## Canonical in-memory representation of a party and its travel state.
## Mirrors the parties + party_members + party_state tables.
## Used as the cross-subsystem contract for party operations.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Formation grid dimensions (5 wide × 12 deep).
## Row 0 is the front of the formation; col 0 is leftmost.
const GRID_COLS := 5
const GRID_ROWS := 12

## Unassigned grid position sentinel.
const UNASSIGNED := -1

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

var id: String = ""
var campaign_id: String = ""
var name: String = "The Party"

# ---------------------------------------------------------------------------
# Location
# ---------------------------------------------------------------------------

var current_map_id: String = ""
var current_hex_q: int = 0
var current_hex_r: int = 0
var current_location_type: String = "wilderness"  # "wilderness" | "dungeon" | "settlement" | "sea"

# ---------------------------------------------------------------------------
# Members & Formation
# ---------------------------------------------------------------------------

## Array of Dictionaries:
##   { character_id: String, formation_col: int, formation_row: int }
## Col/row = UNASSIGNED (-1) means the character is in the party but not
## placed on the formation grid yet.
var members: Array = []

# ---------------------------------------------------------------------------
# Travel State (persisted in party_state table)
# ---------------------------------------------------------------------------

var is_lost: bool = false
var is_force_marching: bool = false
var force_march_days_used: int = 0
var days_since_rest: int = 0
var rations_days_remaining: int = 0

# ---------------------------------------------------------------------------
# Runtime-only (not persisted — populated from loaded characters)
# ---------------------------------------------------------------------------

## Array[CharacterData] — full character objects for each member.
## Populated by the caller after loading; not serialized.
var character_data: Array = []

## Array[InventoryItem] — party-level shared inventory (party_id FK on inventory_items).
## Populated by the caller after loading; not serialized.
var shared_inventory: Array = []

## Array[TrainedCreatureData] — trained creatures belonging to this party.
## Populated by the caller after loading; not serialized.
var creature_data: Array = []


# ---------------------------------------------------------------------------
# Convenience queries
# ---------------------------------------------------------------------------

## Returns the CharacterData for a member by character_id, or null.
func get_member(character_id: String) -> CharacterData:
	for cd: CharacterData in character_data:
		if cd.id == character_id:
			return cd
	return null


## Returns true if the given character is a member of this party.
func has_member(character_id: String) -> bool:
	for m: Dictionary in members:
		if m.get("character_id", "") == character_id:
			return true
	return false


## Returns the grid position for a character as Vector2i(col, row),
## or Vector2i(UNASSIGNED, UNASSIGNED) if not placed.
func get_formation_pos(character_id: String) -> Vector2i:
	for m: Dictionary in members:
		if m.get("character_id", "") == character_id:
			return Vector2i(
				m.get("formation_col", UNASSIGNED),
				m.get("formation_row", UNASSIGNED),
			)
	return Vector2i(UNASSIGNED, UNASSIGNED)


## Returns the character_id at a given grid cell, or "" if empty.
func get_character_at(col: int, row: int) -> String:
	for m: Dictionary in members:
		if m.get("formation_col", UNASSIGNED) == col \
				and m.get("formation_row", UNASSIGNED) == row:
			return m.get("character_id", "")
	return ""


## Returns all character_ids that are placed on the grid (col/row != -1).
func get_placed_members() -> Array:
	var result: Array = []
	for m: Dictionary in members:
		if m.get("formation_col", UNASSIGNED) != UNASSIGNED:
			result.append(m["character_id"])
	return result


## Returns all character_ids that are NOT placed on the grid.
func get_unplaced_members() -> Array:
	var result: Array = []
	for m: Dictionary in members:
		if m.get("formation_col", UNASSIGNED) == UNASSIGNED:
			result.append(m["character_id"])
	return result


## Returns the marching order derived from the formation grid:
## sorted by row (front first), then by column (left to right).
## Unplaced members are appended at the end.
func get_marching_order() -> Array:
	var placed: Array = []
	var unplaced: Array = []
	for m: Dictionary in members:
		var col: int = m.get("formation_col", UNASSIGNED)
		var row: int = m.get("formation_row", UNASSIGNED)
		if col == UNASSIGNED:
			unplaced.append(m["character_id"])
		else:
			placed.append({"character_id": m["character_id"], "col": col, "row": row})
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["row"] != b["row"]:
			return a["row"] < b["row"]
		return a["col"] < b["col"]
	)
	var order: Array = []
	for p: Dictionary in placed:
		order.append(p["character_id"])
	order.append_array(unplaced)
	return order


## Sets a character's grid position. Updates the members array in place.
func set_formation_pos(character_id: String, col: int, row: int) -> void:
	for m: Dictionary in members:
		if m.get("character_id", "") == character_id:
			m["formation_col"] = col
			m["formation_row"] = row
			return


## Removes a character from the grid (sets to UNASSIGNED) without removing from party.
func unplace_character(character_id: String) -> void:
	set_formation_pos(character_id, UNASSIGNED, UNASSIGNED)


## Swaps two characters' grid positions.
func swap_positions(char_a: String, char_b: String) -> void:
	var pos_a := get_formation_pos(char_a)
	var pos_b := get_formation_pos(char_b)
	set_formation_pos(char_a, pos_b.x, pos_b.y)
	set_formation_pos(char_b, pos_a.x, pos_a.y)


## Returns the slowest effective movement rate among all party members and
## trained creatures (feet/turn).
## This is the base rate before terrain or forced-march modifiers.
func get_slowest_movement() -> int:
	if character_data.is_empty() and creature_data.is_empty():
		return 120  # default
	var slowest: int = 999
	for cd: CharacterData in character_data:
		var spd: int = cd.get_effective_movement()
		if spd < slowest:
			slowest = spd
	for creature: TrainedCreatureData in creature_data:
		var spd: int = creature.get_effective_movement()
		if spd < slowest:
			slowest = spd
	return slowest


## Returns true if any party member has the given proficiency.
func any_member_has_proficiency(proficiency_key: String) -> bool:
	for cd: CharacterData in character_data:
		if cd.has_proficiency(proficiency_key):
			return true
	return false


## Returns the highest CON modifier among members with the given proficiency.
## Returns -999 if no member has the proficiency.
func best_con_modifier_with_proficiency(proficiency_key: String) -> int:
	var best: int = -999
	for cd: CharacterData in character_data:
		if cd.has_proficiency(proficiency_key):
			var mod: int = CharacterData.ability_modifier(cd.get_effective_ability_score("constitution"))
			if mod > best:
				best = mod
	return best


## Returns the party's current hex as a Vector2i.
func get_hex() -> Vector2i:
	return Vector2i(current_hex_q, current_hex_r)


## Returns true if the party needs to rest (6+ days of travel without rest,
## and no member has Endurance proficiency).
func needs_rest() -> bool:
	if any_member_has_proficiency("endurance"):
		return false
	return days_since_rest >= 6


## Returns the maximum forced march days allowed.
## Without Endurance: 1 day, then 24h rest.
## With Endurance: 1 + best CON bonus days.
func max_force_march_days() -> int:
	if not any_member_has_proficiency("endurance"):
		return 1
	var con_mod: int = best_con_modifier_with_proficiency("endurance")
	return maxi(1, 1 + con_mod)


## Returns true if the party can continue forced marching.
func can_force_march() -> bool:
	return force_march_days_used < max_force_march_days()


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

## Builds a PartyData from combined DB rows.
## [param party_row] from parties table.
## [param member_rows] from party_members table.
## [param state_row] from party_state table (may be empty Dictionary).
static func from_db(party_row: Dictionary, member_rows: Array, state_row: Dictionary) -> PartyData:
	var pd := PartyData.new()
	pd.id = _str(party_row, "id")
	pd.campaign_id = _str(party_row, "campaign_id")
	pd.name = _str(party_row, "name", "The Party")
	pd.current_map_id = _str(party_row, "current_map_id")
	pd.current_hex_q = _int(party_row, "current_hex_q")
	pd.current_hex_r = _int(party_row, "current_hex_r")
	pd.current_location_type = _str(party_row, "current_location_type", "wilderness")

	pd.members = []
	for row: Dictionary in member_rows:
		pd.members.append({
			"character_id": _str(row, "character_id"),
			"formation_col": _int(row, "formation_col", UNASSIGNED),
			"formation_row": _int(row, "formation_row", UNASSIGNED),
		})

	# Party state — may not exist yet (new party)
	if not state_row.is_empty():
		pd.is_lost = bool(_int(state_row, "is_lost"))
		pd.is_force_marching = bool(_int(state_row, "is_force_marching"))
		pd.force_march_days_used = _int(state_row, "force_march_days_used")
		pd.days_since_rest = _int(state_row, "days_since_rest")
		pd.rations_days_remaining = _int(state_row, "rations_days_remaining")

	return pd


## Returns a Dictionary suitable for DB persistence of the party_state row.
func to_state_dict() -> Dictionary:
	return {
		"party_id": id,
		"marching_order": "[]",  # legacy field — marching order now derived from grid
		"is_lost": int(is_lost),
		"is_force_marching": int(is_force_marching),
		"force_march_days_used": force_march_days_used,
		"days_since_rest": days_since_rest,
		"rations_days_remaining": rations_days_remaining,
		"current_mount_type": "",  # legacy field — mounts now per-character equipment
	}


# ---------------------------------------------------------------------------
# Null-coalescing helpers for SQLite rows (NULL values bypass Dictionary.get defaults)
# ---------------------------------------------------------------------------

static func _str(d: Dictionary, key: String, fallback: String = "") -> String:
	var v = d.get(key, fallback)
	return v if v != null else fallback


static func _int(d: Dictionary, key: String, fallback: int = 0) -> int:
	var v = d.get(key, fallback)
	return int(v) if v != null else fallback
