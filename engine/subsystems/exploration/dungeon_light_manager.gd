class_name DungeonLightManager
extends RefCounted

## Manages per-entity light sources in dungeons, tied to character inventory.
##
## Each character can carry one active light source (torch or lantern) equipped
## in a hand slot. The manager tracks active sources, ticks them down each
## dungeon turn, handles fuel consumption, auto-replacement, and provides
## per-entity light radii to the fog-of-war system.
##
## Requirements:
##   - Tinderbox must be in the character's inventory to light anything.
##   - Torches burn for 6 turns (360 rounds). On expiry, the torch item is
##     deleted and the next available torch is auto-lit if possible.
##   - Lanterns burn for 24 turns (1440 rounds) per oil flask. On fuel expiry,
##     the next oil flask is auto-consumed. If none available, the lantern
##     extinguishes.
##   - Doused sources retain their remaining uses (partial torches stay in
##     inventory as single items separate from unused stacks).


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TORCH_KEY := "torch"
const LANTERN_KEY := "lantern"
const TINDERBOX_KEY := "tinderbox"
const OIL_FLASK_KEY := "oil_flask_common"

const TORCH_USES := 6    # turns
const LANTERN_USES := 24 # turns (per oil flask)

const LIGHT_RADIUS_CELLS := 10  # 50 feet (30' bright + 20' dim) / 5 feet per cell

## Warning thresholds (turns remaining).
const WARN_LOW := 5
const WARN_CRITICAL := 2


# ---------------------------------------------------------------------------
# Active source tracking
# ---------------------------------------------------------------------------

## { character_id: { source_type: "torch"|"lantern", item_id: String,
##                   remaining_turns: int, carrier_id: String } }
var _active_sources: Dictionary = {}


# ---------------------------------------------------------------------------
# Lighting actions
# ---------------------------------------------------------------------------

## Attempt to light a torch for [param character_id].
## Checks for tinderbox, finds a torch in inventory (equipped or stacked),
## splits from stack if needed, equips in a hand slot, and activates.
## Returns a result dict: { success: bool, message: String, item_id: String }.
func light_torch(character_id: String) -> Dictionary:
	var inventory: Array = CampaignRepository.get_inventory_items(character_id)

	# Check tinderbox
	if not _has_item(inventory, TINDERBOX_KEY):
		return {"success": false, "message": "No tinderbox in inventory."}

	# Find an already-equipped, partially-used torch first
	var equipped_torch: Dictionary = _find_equipped_light(inventory, TORCH_KEY)
	if not equipped_torch.is_empty() and int(equipped_torch.get("uses_remaining", 0)) > 0:
		_activate(character_id, "torch", equipped_torch.get("id", ""),
			int(equipped_torch.get("uses_remaining", TORCH_USES)))
		return {"success": true, "message": "Torch re-lit.", "item_id": equipped_torch.get("id", "")}

	# Find an unequipped torch (stack or single)
	var torch_item: Dictionary = _find_unequipped_item(inventory, TORCH_KEY)
	if torch_item.is_empty():
		return {"success": false, "message": "No torches available."}

	var item_id: String = torch_item.get("id", "")
	var qty: int = int(torch_item.get("quantity", 1))
	var uses: int = int(torch_item.get("uses_remaining", -1))

	# If stacked (qty > 1) or unused (uses == -1), split and equip
	if qty > 1 or uses < 0:
		var slot := _find_free_hand_slot(inventory)
		if slot.is_empty():
			return {"success": false, "message": "No free hand slot."}
		var new_id: String = CampaignRepository.split_item_for_equip(item_id, slot, TORCH_USES)
		if new_id.is_empty():
			return {"success": false, "message": "Failed to split torch from stack."}
		_activate(character_id, "torch", new_id, TORCH_USES)
		return {"success": true, "message": "Torch lit.", "item_id": new_id}

	# Single unused torch — equip it
	if not _is_equipped_in_hand(torch_item):
		var slot := _find_free_hand_slot(inventory)
		if slot.is_empty():
			return {"success": false, "message": "No free hand slot."}
		CampaignRepository.update_inventory_item_equip_state(item_id, true, slot)

	var final_uses: int = uses if uses > 0 else TORCH_USES
	CampaignRepository.update_inventory_item_uses(item_id, final_uses)
	_activate(character_id, "torch", item_id, final_uses)
	return {"success": true, "message": "Torch lit.", "item_id": item_id}


## Attempt to light a lantern for [param character_id].
## Checks for tinderbox, equipped lantern, and oil flask. Consumes one oil flask.
func light_lantern(character_id: String) -> Dictionary:
	var inventory: Array = CampaignRepository.get_inventory_items(character_id)

	# Check tinderbox
	if not _has_item(inventory, TINDERBOX_KEY):
		return {"success": false, "message": "No tinderbox in inventory."}

	# Find equipped lantern
	var lantern: Dictionary = _find_equipped_light(inventory, LANTERN_KEY)
	if lantern.is_empty():
		# Try to find an unequipped lantern and equip it
		var unequipped: Dictionary = _find_unequipped_item(inventory, LANTERN_KEY)
		if unequipped.is_empty():
			return {"success": false, "message": "No lantern available."}
		var slot := _find_free_hand_slot(inventory)
		if slot.is_empty():
			return {"success": false, "message": "No free hand slot."}
		CampaignRepository.update_inventory_item_equip_state(
			unequipped.get("id", ""), true, slot)
		lantern = unequipped

	var lantern_id: String = lantern.get("id", "")
	var current_uses: int = int(lantern.get("uses_remaining", 0))

	# If lantern still has fuel, just re-activate
	if current_uses > 0:
		_activate(character_id, "lantern", lantern_id, current_uses)
		return {"success": true, "message": "Lantern re-lit.", "item_id": lantern_id}

	# Need oil — consume one flask
	if not _consume_oil(inventory, character_id):
		return {"success": false, "message": "No oil flask available."}

	CampaignRepository.update_inventory_item_uses(lantern_id, LANTERN_USES)
	_activate(character_id, "lantern", lantern_id, LANTERN_USES)
	return {"success": true, "message": "Lantern lit (oil consumed).", "item_id": lantern_id}


## Douse (extinguish) the light source for [param character_id].
## The item stays in inventory with its remaining uses intact.
func douse(character_id: String) -> void:
	_active_sources.erase(character_id)


# ---------------------------------------------------------------------------
# Tick (called each dungeon turn by the dungeon_light_tick handler)
# ---------------------------------------------------------------------------

## Tick all active light sources by 1 turn.
## Returns an Array of event dictionaries describing what happened:
##   { type: "warning"|"expired"|"refueled"|"auto_lit", character_id, source_type, ... }
func tick_all() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var to_remove: Array[String] = []

	for character_id in _active_sources.keys():
		var source: Dictionary = _active_sources[character_id]
		var remaining: int = source.get("remaining_turns", 0)
		var source_type: String = source.get("source_type", "")
		var item_id: String = source.get("item_id", "")

		remaining -= 1

		# Persist to inventory
		if remaining > 0:
			CampaignRepository.update_inventory_item_uses(item_id, remaining)
		source["remaining_turns"] = remaining

		# Warning thresholds
		if remaining == WARN_LOW:
			events.append(_warning_event(character_id, source_type, remaining))
		elif remaining == WARN_CRITICAL:
			events.append(_warning_event(character_id, source_type, remaining))

		# Expiry
		if remaining <= 0:
			if source_type == "torch":
				events.append_array(_handle_torch_expiry(character_id, item_id))
				to_remove.append(character_id)
			elif source_type == "lantern":
				var refueled := _handle_lantern_expiry(character_id, item_id)
				events.append_array(refueled)
				if not _active_sources.has(character_id) or _active_sources[character_id].get("remaining_turns", 0) <= 0:
					to_remove.append(character_id)

	for cid in to_remove:
		_active_sources.erase(cid)

	return events


# ---------------------------------------------------------------------------
# Query API (used by DungeonMapController for fog)
# ---------------------------------------------------------------------------

## Returns the light radius in cells for [param character_id].
## 6 for torch/lantern, 0 for no active light.
func get_light_radius(character_id: String) -> int:
	if _active_sources.has(character_id):
		return LIGHT_RADIUS_CELLS
	return 0


## Returns all character IDs with active light sources.
func get_all_lit_entities() -> Array[String]:
	var result: Array[String] = []
	for cid in _active_sources.keys():
		result.append(cid)
	return result


## Returns true if any character has an active light source.
func has_any_light() -> bool:
	return not _active_sources.is_empty()


## Returns remaining turns for [param character_id]'s active source, or 0.
func get_remaining_turns(character_id: String) -> int:
	if _active_sources.has(character_id):
		return _active_sources[character_id].get("remaining_turns", 0)
	return 0


## Returns the source type for [param character_id], or "".
func get_source_type(character_id: String) -> String:
	if _active_sources.has(character_id):
		return _active_sources[character_id].get("source_type", "")
	return ""


# ---------------------------------------------------------------------------
# Expiry handling
# ---------------------------------------------------------------------------

func _handle_torch_expiry(character_id: String, item_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# Delete the consumed torch from inventory
	CampaignRepository.remove_inventory_item(item_id)
	events.append({
		"type": "expired",
		"character_id": character_id,
		"source_type": "torch",
		"message": "Torch burned out.",
	})

	# Try to auto-light the next torch
	var result: Dictionary = light_torch(character_id)
	if result.get("success", false):
		events.append({
			"type": "auto_lit",
			"character_id": character_id,
			"source_type": "torch",
			"message": "New torch lit automatically.",
			"item_id": result.get("item_id", ""),
		})
	else:
		events.append({
			"type": "darkness",
			"character_id": character_id,
			"source_type": "torch",
			"message": result.get("message", "No more torches."),
		})

	return events


func _handle_lantern_expiry(character_id: String, item_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []

	# Try to auto-refuel from oil
	var inventory: Array = CampaignRepository.get_inventory_items(character_id)
	if _consume_oil(inventory, character_id):
		CampaignRepository.update_inventory_item_uses(item_id, LANTERN_USES)
		_active_sources[character_id] = {
			"source_type": "lantern",
			"item_id": item_id,
			"remaining_turns": LANTERN_USES,
		}
		events.append({
			"type": "refueled",
			"character_id": character_id,
			"source_type": "lantern",
			"message": "Lantern refueled (oil flask consumed).",
		})
	else:
		# No oil — extinguish
		CampaignRepository.update_inventory_item_uses(item_id, 0)
		events.append({
			"type": "expired",
			"character_id": character_id,
			"source_type": "lantern",
			"message": "Lantern out of fuel — no oil flasks remaining.",
		})
		events.append({
			"type": "darkness",
			"character_id": character_id,
			"source_type": "lantern",
			"message": "No fuel available.",
		})

	return events


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _activate(character_id: String, source_type: String, item_id: String, remaining: int) -> void:
	_active_sources[character_id] = {
		"source_type": source_type,
		"item_id": item_id,
		"remaining_turns": remaining,
	}


func _has_item(inventory: Array, item_key: String) -> bool:
	for item in inventory:
		if item.get("item_key", "") == item_key and int(item.get("quantity", 0)) > 0:
			return true
	return false


func _find_equipped_light(inventory: Array, item_key: String) -> Dictionary:
	for item in inventory:
		if item.get("item_key", "") == item_key and int(item.get("is_equipped", 0)) == 1:
			var slot: String = item.get("slot", "")
			if slot == "hands_main" or slot == "hands_off":
				return item
	return {}


func _find_unequipped_item(inventory: Array, item_key: String) -> Dictionary:
	for item in inventory:
		if item.get("item_key", "") == item_key and int(item.get("is_equipped", 0)) == 0:
			if int(item.get("quantity", 0)) > 0:
				return item
	return {}


func _is_equipped_in_hand(item: Dictionary) -> bool:
	if int(item.get("is_equipped", 0)) == 0:
		return false
	var slot: String = item.get("slot", "")
	return slot == "hands_main" or slot == "hands_off"


func _find_free_hand_slot(inventory: Array) -> String:
	var main_occupied := false
	var off_occupied := false
	for item in inventory:
		if int(item.get("is_equipped", 0)) == 1:
			match item.get("slot", ""):
				"hands_main":
					main_occupied = true
				"hands_off":
					off_occupied = true
	if not off_occupied:
		return "hands_off"
	if not main_occupied:
		return "hands_main"
	return ""


func _consume_oil(inventory: Array, character_id: String) -> bool:
	for item in inventory:
		if item.get("item_key", "") == OIL_FLASK_KEY and int(item.get("quantity", 0)) > 0:
			var oil_id: String = item.get("id", "")
			var qty: int = int(item.get("quantity", 1))
			CampaignRepository.update_inventory_item_quantity(oil_id, qty - 1)
			EventBus.inventory_updated.emit(character_id)
			return true
	return false


func _warning_event(character_id: String, source_type: String, remaining: int) -> Dictionary:
	var name_str: String = "Torch" if source_type == "torch" else "Lantern"
	var body: String
	if remaining == WARN_LOW:
		body = "About %d minutes of light remaining." % (remaining * 10)
	else:
		body = "Only %d minutes of light remaining!" % (remaining * 10)
	return {
		"type": "warning",
		"character_id": character_id,
		"source_type": source_type,
		"remaining_turns": remaining,
		"message": "%s: %s" % [name_str, body],
	}
