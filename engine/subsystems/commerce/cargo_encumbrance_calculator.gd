class_name CargoEncumbranceCalculator
extends RefCounted

## Cargo encumbrance — unifies `inventory_items` and `cargo_holds` against
## the SAME per-carrier capacity limit per Q-MERC-17 [RESOLVED]: a single
## wagon cannot track two separate encumbrance limits.
##
## Per generation/gdd-settlement-economy.md §9.5. Stone is the canonical unit
## at the API boundary; the project's `inventory_items.encumbrance_units` is
## sub-stone (1000 units per stone in the existing `party_inventory_transfer_validator`
## convention), so the inventory sum is banker-rounded into stone at the
## boundary. cargo_holds.load_weight_stone is already in stone so no
## conversion is needed for cargo.
##
## RefCounted static-function library — no instance state.


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Conversion factor matching the existing party_inventory_transfer_validator
## convention at engine/subsystems/inventory/party_inventory_transfer_validator.gd:314.
## (load_max_stone * 1000 == load_max_encumbrance_units.)
const ENCUMBRANCE_UNITS_PER_STONE := 1000


# ---------------------------------------------------------------------------
# Draft vehicles
# ---------------------------------------------------------------------------

## Returns total stone used on a draft vehicle (inventory_items + cargo_holds).
static func draft_vehicle_used_stone(draft_vehicle_id: String) -> int:
	if draft_vehicle_id.is_empty():
		return 0
	var inv_stone: int = _sum_inventory_stone_for_vehicle(draft_vehicle_id)
	var cargo_stone: int = _sum_cargo_stone_for_draft_vehicle(draft_vehicle_id)
	return inv_stone + cargo_stone


## Returns a capacity-check dict for a draft vehicle:
##   {used_stone, load_normal_stone, load_max_stone,
##    is_over_normal, is_over_max, speed, free_stone}
## Returns {} if the vehicle is missing or has no valid hitched team.
static func draft_vehicle_capacity_check(draft_vehicle_id: String) -> Dictionary:
	var vehicle: Dictionary = _read_draft_vehicle(draft_vehicle_id)
	if vehicle.is_empty():
		return {}
	var item_key: String = str(vehicle.get("item_key", ""))
	var hitched_json: String = str(vehicle.get("hitched_creatures", "[]"))
	var team: Array = _resolve_hitched_team(hitched_json)
	var team_equiv: float = DraftVehicleService.calculate_team_equivalents(team)
	var capacity: Dictionary = DraftVehicleService.get_vehicle_capacity(item_key, team_equiv)
	if capacity.is_empty():
		return {}
	var used: int = draft_vehicle_used_stone(draft_vehicle_id)
	var load_normal: int = int(capacity.get("load_normal", 0))
	var load_max: int = int(capacity.get("load_max", 0))
	var is_over_normal: bool = used > load_normal
	var is_over_max: bool = used > load_max
	var speed: int = int(capacity.get("speed_loaded" if is_over_normal else "speed_normal", 0))
	return {
		"used_stone": used,
		"load_normal_stone": load_normal,
		"load_max_stone": load_max,
		"is_over_normal": is_over_normal,
		"is_over_max": is_over_max,
		"speed": speed,
		"free_stone": maxi(0, load_max - used),
	}


# ---------------------------------------------------------------------------
# Ships
# ---------------------------------------------------------------------------

## Returns total cargo stone on a ship. Ships in v1 do NOT carry
## inventory_items (personal gear stays on character inventories per §9.5),
## so the sum is cargo-only.
static func ship_used_stone(ship_id: String) -> int:
	if ship_id.is_empty():
		return 0
	return _sum_cargo_stone_for_ship(ship_id)


## Returns a capacity-check dict for a ship:
##   {used_stone, cargo_capacity_stone, is_over_capacity, free_stone}
static func ship_capacity_check(ship_id: String) -> Dictionary:
	var ship: Dictionary = _read_ship(ship_id)
	if ship.is_empty():
		return {}
	var used: int = ship_used_stone(ship_id)
	var capacity: int = int(ship.get("cargo_capacity_stone", 0))
	return {
		"used_stone": used,
		"cargo_capacity_stone": capacity,
		"is_over_capacity": used > capacity,
		"free_stone": maxi(0, capacity - used),
	}


# ---------------------------------------------------------------------------
# Internals — summation helpers
# ---------------------------------------------------------------------------

static func _sum_inventory_stone_for_vehicle(draft_vehicle_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(encumbrance_units * quantity), 0) AS total_eu
		FROM inventory_items
		WHERE vehicle_id = ?
	""", [draft_vehicle_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	var total_eu: int = int(CampaignRepository.db.query_result[0].get("total_eu", 0))
	# encumbrance_units → stone via /1000 with banker rounding (per CLAUDE.md).
	return _bankers_round(float(total_eu) / float(ENCUMBRANCE_UNITS_PER_STONE))


static func _sum_cargo_stone_for_draft_vehicle(draft_vehicle_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(loads_count * load_weight_stone), 0) AS total_stone
		FROM cargo_holds
		WHERE draft_vehicle_id = ?
	""", [draft_vehicle_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total_stone", 0))


static func _sum_cargo_stone_for_ship(ship_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(loads_count * load_weight_stone), 0) AS total_stone
		FROM cargo_holds
		WHERE ship_id = ?
	""", [ship_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total_stone", 0))


# ---------------------------------------------------------------------------
# Internals — fixture helpers
# ---------------------------------------------------------------------------

static func _read_draft_vehicle(draft_vehicle_id: String) -> Dictionary:
	if draft_vehicle_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id, item_key, hitched_creatures FROM draft_vehicles WHERE id = ?",
			[draft_vehicle_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


static func _read_ship(ship_id: String) -> Dictionary:
	if ship_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT id, cargo_capacity_stone FROM ships WHERE id = ?",
			[ship_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0]


## Parses the hitched_creatures JSON array. Each element is either an object
## with a `species_id` field, or a TrainedCreatureData; v1 stores JSON
## objects with at least species_id, so we extract that. The result is fed
## to DraftVehicleService.calculate_team_equivalents which expects an array
## of dicts or TrainedCreatureData.
static func _resolve_hitched_team(hitched_json: String) -> Array:
	if hitched_json.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(hitched_json)
	if not (parsed is Array):
		return []
	return parsed as Array


# ---------------------------------------------------------------------------
# Banker rounding (CLAUDE.md core principle)
# ---------------------------------------------------------------------------

static func _bankers_round(value: float) -> int:
	var floor_val: int = int(floor(value))
	var frac: float = value - float(floor_val)
	if absf(frac - 0.5) < 0.0000001:
		if floor_val % 2 == 0:
			return floor_val
		return floor_val + 1
	return int(roundf(value))
