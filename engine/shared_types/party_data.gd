class_name PartyData
extends RefCounted

## Canonical in-memory representation of a party and its travel state.
## Mirrors the parties + party_members + party_state tables.
## Used as the cross-subsystem contract for party operations.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Legacy formation grid dimensions (5 wide × 12 deep). Kept for back-compat
## with pre-γ.3 callers and tests; the Party tab's Formation sub-tab uses the
## grid-specific constants below per gdd-party-tab.md §7.
const GRID_COLS := 5
const GRID_ROWS := 12

## Wilderness formation grid: 6 wide × 12 deep (γ.3, gdd-party-tab.md §7.1).
## Wider than the legacy 5-col grid to accommodate vehicles, mercenaries,
## and large beasts of burden alongside PCs and henchmen. Existing
## formation_col values (0..4) remain valid in the widened layout.
const WILDERNESS_COLS := 6
const WILDERNESS_ROWS := 12

## Dungeon formation grid: 2 wide × 12 deep (γ.3, gdd-party-tab.md §7.1).
## Mirrors the ACKS "pairs side by side" rule per
## acore_adventures_and_encounters.xml §marching_order. Capped at 24 entities
## to keep dungeon UI legible; mass combat scales above this go through DaW.
const DUNGEON_COLS := 2
const DUNGEON_ROWS := 12

## Grid identifiers for the parameterized formation API.
const GRID_WILDERNESS := "wilderness"
const GRID_DUNGEON := "dungeon"

## Unassigned grid position sentinel.
const UNASSIGNED := -1

## Vehicle exploration speed in feet/turn (ACKS: all carts/wagons = 60').
const VEHICLE_SPEED := 60

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

# Dungeon position (parties table, migration 017). Populated from the DB on load
# so the savegame loader can restore the party into the right dungeon/level.
# The authoritative PER-MEMBER cells live in dungeon_entity_positions
# (migration 146); these party-level fields are the dungeon id, the active level,
# and the leader/camera-focus cell. See gdd-savegame-system.md §5.2.
var dungeon_id: String = ""
var dungeon_level: int = 1
var dungeon_col: int = 0
var dungeon_row: int = 0

# Settlement position (parties table, migration 019).
var settlement_id: String = ""       # settlement_entrances.id
var settlement_node_id: String = ""  # current POI id

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

# Wilderness sustenance counters (migration 047). Penalty mechanics from
# acore_adventures_and_encounters.xml are applied by the Phase 3
# SustenanceResolver; Phase 1 only tracks the state.
var exhaustion_days: int = 0
var starvation_days: int = 0
var dehydration_days: int = 0
var water_units: int = 0
var ration_units: int = 0
## Absolute game round when wilderness_day_tick last fired for this party.
## -1 sentinel = never ticked (next midnight schedules the first tick).
var last_day_tick_round: int = -1

# Camp state + per-day encounter gate (migration 131, gdd-realtime-scheduler.md §4.3).
#
# The party's current camp, if any. When `is_camping` is true, the four
# camp_* fields describe the camp's window and watch schedule, and
# `_handle_wilderness_encounter` (registered globally) can compute observer
# state at any fire_time. Cleared by CampHandlers on rest_complete /
# cancel_camp; cross-day camps preserve them until the player wakes.
var is_camping: bool = false
var camp_start_round: int = -1
var camp_end_round: int = -1
## JSON-encoded Array[Array[String]] — 3 watches × character_ids on duty.
## Empty "[]" when not camping. Parsed lazily by the wilderness_encounter
## handler since it's the only read site outside CampState.
var camp_watch_assignments_json: String = "[]"
## JSON-encoded Array[String] — character_ids sleeping in armor.
## Empty "[]" when not camping.
var camp_armed_sleepers_json: String = "[]"
## day_index (round / ROUNDS_PER_DAY) on which a wilderness encounter most
## recently triggered for this party. The hybrid camp-gate rule (§4.3.3)
## fires the camp throw only when current_day_index > last_encounter_trigger_day.
## -1 sentinel = never triggered.
var last_encounter_trigger_day: int = -1

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

## Array[Dictionary] — draft vehicles belonging to this party (from draft_vehicles table).
## Populated by the caller after loading; not serialized.
var vehicle_data: Array = []


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


# ---------------------------------------------------------------------------
# γ.3 — grid-parameterized formation API. The pre-γ.3 methods above continue
# to operate on the wilderness grid (formation_col / formation_row) for
# back-compat. Per gdd-party-tab.md §7.1 the dungeon grid is independent.
# ---------------------------------------------------------------------------

static func _col_key(grid: String) -> String:
	return "dungeon_formation_col" if grid == GRID_DUNGEON else "formation_col"


static func _row_key(grid: String) -> String:
	return "dungeon_formation_row" if grid == GRID_DUNGEON else "formation_row"


## Returns the grid position for [param character_id] on [param grid]
## (`"wilderness"` or `"dungeon"`), or Vector2i(UNASSIGNED, UNASSIGNED) if
## the character is in the party but unplaced on that grid.
func get_formation_pos_for(character_id: String, grid: String) -> Vector2i:
	var ck := _col_key(grid)
	var rk := _row_key(grid)
	for m: Dictionary in members:
		if m.get("character_id", "") == character_id:
			return Vector2i(m.get(ck, UNASSIGNED), m.get(rk, UNASSIGNED))
	return Vector2i(UNASSIGNED, UNASSIGNED)


## Returns the character_id at a given grid cell on [param grid], or "".
func get_character_at_for(col: int, row: int, grid: String) -> String:
	var ck := _col_key(grid)
	var rk := _row_key(grid)
	for m: Dictionary in members:
		if m.get(ck, UNASSIGNED) == col and m.get(rk, UNASSIGNED) == row:
			return m.get("character_id", "")
	return ""


## Returns all character_ids placed on [param grid].
func get_placed_members_for(grid: String) -> Array:
	var ck := _col_key(grid)
	var result: Array = []
	for m: Dictionary in members:
		if m.get(ck, UNASSIGNED) != UNASSIGNED:
			result.append(m["character_id"])
	return result


## Returns all character_ids NOT placed on [param grid].
func get_unplaced_members_for(grid: String) -> Array:
	var ck := _col_key(grid)
	var result: Array = []
	for m: Dictionary in members:
		if m.get(ck, UNASSIGNED) == UNASSIGNED:
			result.append(m["character_id"])
	return result


## Sets the grid position for [param character_id] on [param grid] in place.
func set_formation_pos_for(character_id: String, col: int, row: int, grid: String) -> void:
	var ck := _col_key(grid)
	var rk := _row_key(grid)
	for m: Dictionary in members:
		if m.get("character_id", "") == character_id:
			m[ck] = col
			m[rk] = row
			return


## Removes a character from [param grid] without removing them from the party.
func unplace_character_for(character_id: String, grid: String) -> void:
	set_formation_pos_for(character_id, UNASSIGNED, UNASSIGNED, grid)


## Returns the slowest effective movement rate among all party members,
## trained creatures, and vehicles (feet/turn).
## This is the base rate before terrain or forced-march modifiers.
## Vehicles always move at 60'/turn (30' loaded) per ACKS rules.
func get_slowest_movement() -> int:
	if character_data.is_empty() and creature_data.is_empty() and vehicle_data.is_empty():
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
	# Vehicles cap party speed at 60'/turn (ACKS: carts/wagons all move 60'/30').
	if not vehicle_data.is_empty():
		if VEHICLE_SPEED < slowest:
			slowest = VEHICLE_SPEED
	return slowest


## Returns true if [param creature_id] is currently hitched to any draft vehicle.
## Vehicle rows store hitched creatures as a JSON-encoded array of creature IDs.
func is_creature_hitched(creature_id: String) -> bool:
	if creature_id.is_empty():
		return false
	for v in vehicle_data:
		var hitched_json := str(v.get("hitched_creatures", "[]"))
		var hitched = JSON.parse_string(hitched_json)
		if hitched is Array and creature_id in hitched:
			return true
	return false


## Returns true if [param creature] should be brought into the dungeon with the
## party. A creature must be alive, of a permitted species, and not currently
## hitched to a cart. Hitched mules/donkeys default to staying outside; an
## auto-unhitch flow is planned but not yet implemented.
func can_creature_enter_dungeon(creature: TrainedCreatureData) -> bool:
	if creature == null or not creature.is_alive:
		return false
	if not creature.can_enter_dungeon():
		return false
	if is_creature_hitched(creature.id):
		return false
	return true


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
	# Dungeon position (migration 017) + settlement position (migration 019).
	# Columns added by migration; absent on very old rows → helpers fall back.
	pd.dungeon_id = _str(party_row, "dungeon_id")
	pd.dungeon_level = _int(party_row, "dungeon_level", 1)
	pd.dungeon_col = _int(party_row, "dungeon_col")
	pd.dungeon_row = _int(party_row, "dungeon_row")
	pd.settlement_id = _str(party_row, "settlement_id")
	pd.settlement_node_id = _str(party_row, "settlement_node_id")

	pd.members = []
	for row: Dictionary in member_rows:
		pd.members.append({
			"character_id": _str(row, "character_id"),
			"formation_col": _int(row, "formation_col", UNASSIGNED),
			"formation_row": _int(row, "formation_row", UNASSIGNED),
			"dungeon_formation_col": _int(row, "dungeon_formation_col", UNASSIGNED),
			"dungeon_formation_row": _int(row, "dungeon_formation_row", UNASSIGNED),
		})

	# Party state — may not exist yet (new party)
	if not state_row.is_empty():
		pd.is_lost = bool(_int(state_row, "is_lost"))
		pd.is_force_marching = bool(_int(state_row, "is_force_marching"))
		pd.force_march_days_used = _int(state_row, "force_march_days_used")
		pd.days_since_rest = _int(state_row, "days_since_rest")
		pd.rations_days_remaining = _int(state_row, "rations_days_remaining")
		pd.exhaustion_days = _int(state_row, "exhaustion_days")
		pd.starvation_days = _int(state_row, "starvation_days")
		pd.dehydration_days = _int(state_row, "dehydration_days")
		pd.water_units = _int(state_row, "water_units")
		pd.ration_units = _int(state_row, "ration_units")
		pd.last_day_tick_round = _int(state_row, "last_day_tick_round", -1)
		# Migration 131: camp state + encounter gate (gdd-realtime-scheduler.md §4.3).
		pd.is_camping = bool(_int(state_row, "is_camping"))
		pd.camp_start_round = _int(state_row, "camp_start_round", -1)
		pd.camp_end_round = _int(state_row, "camp_end_round", -1)
		pd.camp_watch_assignments_json = _str(state_row, "camp_watch_assignments_json", "[]")
		pd.camp_armed_sleepers_json = _str(state_row, "camp_armed_sleepers_json", "[]")
		pd.last_encounter_trigger_day = _int(state_row, "last_encounter_trigger_day", -1)

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
		"exhaustion_days": exhaustion_days,
		"starvation_days": starvation_days,
		"dehydration_days": dehydration_days,
		"water_units": water_units,
		"ration_units": ration_units,
		"last_day_tick_round": last_day_tick_round,
		# Migration 131.
		"is_camping": int(is_camping),
		"camp_start_round": camp_start_round,
		"camp_end_round": camp_end_round,
		"camp_watch_assignments_json": camp_watch_assignments_json,
		"camp_armed_sleepers_json": camp_armed_sleepers_json,
		"last_encounter_trigger_day": last_encounter_trigger_day,
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
