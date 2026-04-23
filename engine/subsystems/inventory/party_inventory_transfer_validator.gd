class_name PartyInventoryTransferValidator
extends RefCounted

## Validates item transfers between carriers in the Party Inventory overlay.
##
## Dependencies:
##   - CampaignRepository (autoload): item/carrier lookups
##   - CreatureEquipmentService (class_name, static methods): creature validation
##   - DraftVehicleService (class_name, static methods): vehicle validation
##   - EquipmentCatalog (local instance): item metadata, container lookup
##   - Currency (preloaded const): coin detection
##
## Design note:
##   Pure validation — no side effects, no actual transfers. The overlay calls
##   validate_transfer() on every drag hover, and executes the transfer only
##   via CampaignRepository / LocationCacheManager methods when ok=true.

const Currency := preload("res://engine/subsystems/commerce/currency.gd")


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _catalog: RefCounted  # EquipmentCatalog instance


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _init(catalog: RefCounted = null) -> void:
	_catalog = catalog


# ---------------------------------------------------------------------------
# Public API — static helpers
# ---------------------------------------------------------------------------

## Returns carrier_ids reachable from the anchor (3D Chebyshev <= 1), including
## the anchor itself. Anchors or carriers missing from `carrier_positions` are
## excluded. Used by the overlay to dim non-adjacent columns and by the loot
## modal to filter the participant list.
static func collect_adjacent_carrier_ids(anchor_id: String,
		carrier_positions: Dictionary) -> Array:
	var result: Array = []
	if anchor_id.is_empty() or not carrier_positions.has(anchor_id):
		return result
	var anchor_pos: Vector3i = carrier_positions[anchor_id]
	for cid in carrier_positions.keys():
		var pos: Vector3i = carrier_positions[cid]
		if VoxelGrid.chebyshev_distance(anchor_pos, pos) <= 1:
			result.append(cid)
	return result


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Validates a proposed transfer. Returns {ok, reason, warnings, resolved_slot}.
##
## source: {carrier_type, carrier_id, item_id, quantity}
##   carrier_type: "character" | "creature" | "vehicle" | "cache"
## target: {carrier_type, carrier_id, slot: String = ""}
##   slot hint: "equipped", "loose", "container:<id>", "saddlebag", "cargo", "cache", ""
##   If blank, validator picks the most appropriate slot.
## context: {location_key, is_in_combat, active_character_id}
##
## item: Dictionary with the item data (item_key, item_category, is_equipped, slot,
##        encumbrance_units, quantity, etc.) — passed directly to avoid DB lookup.
##
## Returns: {
##   ok: bool,
##   reason: String,        # rejection reason (empty if ok)
##   warnings: Array,       # soft warnings for hover display
##   resolved_slot: String, # the slot the item would land in
## }
func validate_transfer(source: Dictionary, target: Dictionary,
		context: Dictionary, item: Dictionary) -> Dictionary:
	var result: Dictionary

	# 1. Same carrier check
	if source.get("carrier_type", "") == target.get("carrier_type", "") \
			and source.get("carrier_id", "") == target.get("carrier_id", ""):
		var src_slot := str(item.get("slot", ""))
		var tgt_slot := str(target.get("slot", ""))
		if tgt_slot.is_empty() or tgt_slot == src_slot:
			return _reject("Already there")

	# 2. Coin lock
	result = _check_coin_lock(item)
	if not result.ok:
		return result

	# 3. Equipped clothing lock
	result = _check_equipped_clothing(item)
	if not result.ok:
		return result

	# 4. Context friction (location matching)
	result = _check_context_friction(source, target, context)
	if not result.ok:
		return result

	# 5. Carrier-type restrictions + capacity + slot resolution
	var target_type: String = target.get("carrier_type", "")
	match target_type:
		"character":
			return _validate_to_character(source, target, context, item)
		"creature":
			return _validate_to_creature(source, target, context, item)
		"vehicle":
			return _validate_to_vehicle(source, target, context, item)
		"cache":
			return _accept("cache")
		_:
			return _reject("Unknown target carrier type: %s" % target_type)


# ---------------------------------------------------------------------------
# Validation checks
# ---------------------------------------------------------------------------

func _check_coin_lock(item: Dictionary) -> Dictionary:
	var key: String = str(item.get("item_key", ""))
	if Currency.is_coin(key):
		return _reject("Coins \u2014 use Transfer Gold modal")
	return _ok()


func _check_equipped_clothing(item: Dictionary) -> Dictionary:
	var cat: String = str(item.get("item_category", ""))
	var equipped: bool = _is_equipped(item)
	if cat == "clothing" and equipped:
		return _reject("Unequip clothing before transferring")
	return _ok()


func _check_context_friction(source: Dictionary, target: Dictionary,
		context: Dictionary) -> Dictionary:
	var location_key: String = str(context.get("location_key", "unknown"))

	# Settlement or wilderness: free transfer within same location
	if location_key.begins_with("settlement:") or location_key.begins_with("hex:"):
		return _ok()

	# Dungeon
	if location_key.begins_with("dungeon:"):
		if context.get("is_in_combat", false):
			return _check_combat_trade_action(source, target, context)
		return _check_dungeon_adjacency(source, target, context)

	# Unknown or "none" — check if source and target share location
	return _ok()


## Checks that source and target carriers are at 3D Chebyshev distance <= 1.
## Requires context["carrier_positions"]: Dictionary mapping carrier_id -> Vector3i.
## If positions are not supplied, rejects — the caller must populate this key.
func _check_dungeon_adjacency(source: Dictionary, target: Dictionary,
		context: Dictionary) -> Dictionary:
	var positions: Dictionary = context.get("carrier_positions", {})
	var src_id: String = source.get("carrier_id", "")
	var tgt_id: String = target.get("carrier_id", "")
	if not positions.has(src_id) or not positions.has(tgt_id):
		return _reject("Carrier position unknown")
	var src_pos: Vector3i = positions[src_id]
	var tgt_pos: Vector3i = positions[tgt_id]
	if VoxelGrid.chebyshev_distance(src_pos, tgt_pos) <= 1:
		return _ok()
	return _reject("Carriers are not adjacent")


## Checks that the active character has a combat action available, then adjacency.
## Requires context["combat_action_available"]: bool. Ignored when not in combat.
func _check_combat_trade_action(source: Dictionary, target: Dictionary,
		context: Dictionary) -> Dictionary:
	if not context.get("combat_action_available", false):
		return _reject("No action available to trade in combat")
	return _check_dungeon_adjacency(source, target, context)


# ---------------------------------------------------------------------------
# Per-target-type validation
# ---------------------------------------------------------------------------

func _validate_to_character(_source: Dictionary, target: Dictionary,
		_context: Dictionary, item: Dictionary) -> Dictionary:
	var slot_hint: String = str(target.get("slot", ""))
	var resolved_slot := "loose" if slot_hint.is_empty() else slot_hint

	# Capacity warning check
	var warnings: Array = []
	var char_id: String = str(target.get("carrier_id", ""))
	var items: Array = CampaignRepository.get_inventory_items(char_id)
	var current_units := _sum_encumbrance(items)
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	var new_total := current_units + item_units

	# ACKS character encumbrance bands (in 1/1000-stone units)
	# 0-5000 = unencumbered, 5001-7000 = light, 7001-10000 = heavy, 10001-20000 = severe
	var max_units := 20000  # base max; could adjust for STR mod
	if new_total > max_units:
		return _reject("Would exceed maximum carrying capacity")

	# Check band transition
	var old_band := _encumbrance_band(current_units)
	var new_band := _encumbrance_band(new_total)
	if new_band > old_band:
		var band_names := ["unencumbered", "lightly encumbered", "heavily encumbered", "severely encumbered"]
		if new_band < band_names.size():
			warnings.append("Would push to %s" % band_names[new_band])

	return _accept(resolved_slot, warnings)


func _validate_to_creature(_source: Dictionary, target: Dictionary,
		_context: Dictionary, item: Dictionary) -> Dictionary:
	var creature_id: String = str(target.get("carrier_id", ""))
	var creature_data = target.get("data")  # TrainedCreatureData or null

	if creature_data == null:
		return _reject("Creature data not available")

	# Check rigging state via saddle type
	var saddle_type: String = creature_data.get_equipped_saddle_type()

	# Draft saddle is for vehicle hitching only, not cargo
	if saddle_type == "draft":
		return _reject("Draft saddle is for vehicle hitching; use a pack saddle for cargo")

	# Check if creature has any rigging at all
	var load_mult: float = creature_data.get_load_multiplier()
	if load_mult <= 0.0 and saddle_type.is_empty():
		return _reject("Creature needs a saddle or rope to carry cargo")

	# Determine slot
	var slot_hint: String = str(target.get("slot", ""))
	var resolved_slot := slot_hint

	if slot_hint.is_empty() or slot_hint == "cargo":
		# Default: validate as cargo
		var err: String = CreatureEquipmentService.validate_cargo_on_creature(
				creature_data, _item_to_dict(item))
		if not err.is_empty():
			return _reject(err)
		resolved_slot = "cargo"

	elif slot_hint == "saddlebag":
		if not CreatureEquipmentService.has_saddlebags_equipped(creature_data):
			return _reject("Creature has no saddlebags equipped")
		var sb_id: String = CreatureEquipmentService.get_saddlebag_item_id(creature_data)
		var err: String = CreatureEquipmentService.validate_into_saddlebags(
				creature_data, _item_to_dict(item), sb_id, _catalog)
		if not err.is_empty():
			return _reject(err)

	elif slot_hint == "equipped" or slot_hint == "tack":
		var err: String = CreatureEquipmentService.validate_equip_on_creature(
				creature_data, _item_to_dict(item), _catalog)
		if not err.is_empty():
			return _reject(err)
		resolved_slot = "equipped"

	# Capacity warning
	var warnings: Array = []
	var current_load: int = creature_data.get_current_load_units()
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))
	var normal_cap: int = creature_data.get_effective_capacity_normal() * 1000
	var max_cap: int = creature_data.get_effective_capacity_max() * 1000

	if current_load + item_units > max_cap:
		return _reject("Would exceed creature's maximum carrying capacity")
	if current_load + item_units > normal_cap:
		warnings.append("Would overload creature")

	return _accept(resolved_slot, warnings)


func _validate_to_vehicle(_source: Dictionary, target: Dictionary,
		_context: Dictionary, item: Dictionary) -> Dictionary:
	var vehicle_data = target.get("data")  # Dictionary or vehicle-like object

	if vehicle_data == null:
		return _reject("Vehicle data not available")

	var vehicle_key: String = str(vehicle_data.get("item_key", ""))
	var vehicle_id: String = str(target.get("carrier_id", ""))

	# Get hitched creatures to compute team equivalents
	var hitched_creatures: Array = vehicle_data.get("hitched_creatures_data", [])
	var team_equiv: float = DraftVehicleService.calculate_team_equivalents(hitched_creatures)

	# Get current load
	var vehicle_items: Array = CampaignRepository.get_items_in_vehicle(vehicle_id)
	var current_load: int = DraftVehicleService.calculate_vehicle_load_units(vehicle_items)
	var item_units: int = int(item.get("encumbrance_units", 0)) * int(item.get("quantity", 1))

	# Get capacity
	var capacity: Dictionary = DraftVehicleService.get_vehicle_capacity(vehicle_key, team_equiv)
	if capacity.is_empty():
		return _reject("Cannot determine vehicle capacity")

	var load_normal: int = int(capacity.get("load_normal", 0)) * 1000
	var load_max: int = int(capacity.get("load_max", 0)) * 1000

	if current_load + item_units > load_max:
		return _reject("Would exceed vehicle's maximum cargo capacity")

	var warnings: Array = []
	if current_load + item_units > load_normal:
		warnings.append("Would overload vehicle (reduced speed)")

	return _accept("cargo", warnings)


# ---------------------------------------------------------------------------
# Result helpers
# ---------------------------------------------------------------------------

func _ok() -> Dictionary:
	return {ok = true, reason = "", warnings = [], resolved_slot = ""}


func _accept(resolved_slot: String = "", warnings: Array = []) -> Dictionary:
	return {ok = true, reason = "", warnings = warnings, resolved_slot = resolved_slot}


func _reject(reason: String) -> Dictionary:
	return {ok = false, reason = reason, warnings = [], resolved_slot = ""}


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

func _is_equipped(item: Dictionary) -> bool:
	var val = item.get("is_equipped", false)
	if val is bool:
		return val
	return int(val) == 1


func _item_to_dict(item: Dictionary) -> Dictionary:
	# Ensure the item is in Dictionary form for service static methods
	return item


func _sum_encumbrance(items: Array) -> int:
	var total := 0
	for it in items:
		var enc: int = 0
		var qty: int = 1
		if it is InventoryItem:
			enc = it.encumbrance_units
			qty = it.quantity
		elif it is Dictionary:
			enc = int(it.get("encumbrance_units", 0))
			qty = int(it.get("quantity", 1))
		total += enc * qty
	return total


func _encumbrance_band(units: int) -> int:
	## Returns 0=unencumbered, 1=light, 2=heavy, 3=severe
	if units <= 5000:
		return 0
	elif units <= 7000:
		return 1
	elif units <= 10000:
		return 2
	else:
		return 3
