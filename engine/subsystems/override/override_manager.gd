class_name OverrideManager
extends Node

## OverrideManager — dev-mode game state manipulation.
##
## Instantiated as a child of Main.tscn. Accessed by OverridePanel via a typed
## reference set by Main at _ready(). Not an autoload.
##
## Dice overrides are stored in GameState.dice_overrides (Dictionary) so the
## future dice subsystem can read them without a direct dependency on this node.
##
## All overrides are logged to the override_log DB table via CampaignRepository.
##
## Roll type vocabulary (snake_case, matches action vocabulary):
##   encounter_check, player_surprise_check, monster_surprise_check,
##   initiative, attack_throw, damage_roll,
##   saving_throw_petrification, saving_throw_poison, saving_throw_blast,
##   saving_throw_wands, saving_throw_spells, morale_check, reaction_roll,
##   thief_skill_throw, proficiency_throw, domain_event_roll, hijink_roll,
##   mortal_wound_d20, mortal_wound_d6, tampering_with_mortality
##
## Player-facing rolls (prompted in PHYSICAL/HYBRID mode — called via DiceSystem.player_roll()):
##   player_surprise_check, initiative, attack_throw, damage_roll,
##   saving_throw_*, thief_skill_throw, proficiency_throw,
##   mortal_wound_d20, mortal_wound_d6, tampering_with_mortality
##
## GM/digital-only rolls (always called via DiceSystem.roll_digital()):
##   encounter_check, monster_surprise_check, morale_check, reaction_roll,
##   domain_event_roll, hijink_roll


# ---------------------------------------------------------------------------
# Character stat overrides
# ---------------------------------------------------------------------------

## Valid direct-settable fields on the characters table.
const CHARACTER_STAT_FIELDS := [
	"name", "level", "xp",
	"strength", "intelligence", "wisdom", "dexterity", "constitution", "charisma",
	"hp_max", "hp_current", "armor_class", "attack_throw",
	"loyalty_score", "wage_gp_per_month",
]

## Gold coin item key. All GP adjustments target an inventory_item with this key.
const GOLD_ITEM_KEY := "coin_gp"
const GOLD_ITEM_NAME := "Gold Pieces"

## Maximum snapshots kept per campaign (oldest pruned when exceeded).
const MAX_SNAPSHOTS := 10


# ---------------------------------------------------------------------------
# Dice queue
# ---------------------------------------------------------------------------

## Queue a forced result for the next roll of [param roll_type].
## Overwrites any existing queued override for that type.
func queue_dice_override(roll_type: String, forced_value: int) -> void:
	GameState.dice_overrides[roll_type] = forced_value
	_log_override("dice_queued", roll_type, roll_type, "", str(forced_value))
	EventBus.dice_override_queued.emit(roll_type, forced_value)


## Remove a pending dice override without consuming it.
func clear_dice_override(roll_type: String) -> void:
	if GameState.dice_overrides.has(roll_type):
		GameState.dice_overrides.erase(roll_type)
		_log_override("dice_cleared", roll_type, roll_type, "", "")


## Remove all pending dice overrides.
func clear_all_dice_overrides() -> void:
	for roll_type in GameState.dice_overrides.keys():
		_log_override("dice_cleared", roll_type, roll_type, "", "")
	GameState.dice_overrides.clear()


## Called by the dice subsystem to consume a queued override.
## Returns the forced value, or -1 if no override is queued for this roll type.
## Emits dice_override_consumed when an override is consumed.
func consume_dice_override(roll_type: String) -> int:
	if not GameState.dice_overrides.has(roll_type):
		return -1
	var value: int = GameState.dice_overrides[roll_type]
	GameState.dice_overrides.erase(roll_type)
	EventBus.dice_override_consumed.emit(roll_type, value)
	return value


# ---------------------------------------------------------------------------
# Character overrides
# ---------------------------------------------------------------------------

## Set a single stat field on a character. [param field] must be in CHARACTER_STAT_FIELDS.
## Returns false if the field is not allowed or the DB write fails.
func override_character_stat(character_id: String, field: String, new_value) -> bool:
	if field not in CHARACTER_STAT_FIELDS:
		push_error("OverrideManager.override_character_stat: disallowed field '%s'" % field)
		return false
	var current := CampaignRepository.get_character(character_id)
	if current.is_empty():
		return false
	var old_value = current.get(field, "")
	current[field] = new_value
	if not CampaignRepository.save_character(current):
		return false
	_log_override("character_stat", character_id, field, str(old_value), str(new_value))
	EventBus.override_applied.emit("character_stat", character_id, field)
	return true


## Adjust a character's XP by [param delta] (positive to add, negative to subtract).
## Flags in the log if the result crosses a level threshold, but does not auto-level.
func override_character_xp(character_id: String, delta: int) -> bool:
	var current := CampaignRepository.get_character(character_id)
	if current.is_empty():
		return false
	var old_xp: int = current.get("xp", 0)
	var new_xp: int = maxi(0, old_xp + delta)
	current["xp"] = new_xp
	if not CampaignRepository.save_character(current):
		return false
	_log_override("character_xp", character_id, "xp", str(old_xp), str(new_xp))
	EventBus.override_applied.emit("character_xp", character_id, "xp")
	EventBus.xp_awarded.emit(character_id, delta)
	return true


## Apply or remove a named condition on a character.
## [param apply] true = add condition; false = remove all conditions matching the name.
func override_character_condition(character_id: String, condition_name: String, apply: bool) -> bool:
	if apply:
		var row_id := CampaignRepository.add_condition(character_id, condition_name)
		if row_id == -1:
			return false
		_log_override("character_condition", character_id, "condition", "", condition_name)
		EventBus.override_applied.emit("character_condition", character_id, condition_name)
		EventBus.condition_changed.emit(character_id, {"condition": condition_name, "applied": true})
	else:
		var conditions := CampaignRepository.get_conditions(character_id)
		var removed := false
		for row in conditions:
			if row.get("condition_name", "") == condition_name:
				CampaignRepository.remove_condition(row["id"] as int)
				removed = true
		if not removed:
			push_error("OverrideManager.override_character_condition: condition '%s' not found on character %s" % [
				condition_name, character_id
			])
			return false
		_log_override("character_condition", character_id, "condition", condition_name, "")
		EventBus.override_applied.emit("character_condition", character_id, condition_name)
		EventBus.condition_changed.emit(character_id, {"condition": condition_name, "applied": false})
	return true


## Toggle is_dead and is_active on a character.
func override_character_status(character_id: String, is_dead: bool) -> bool:
	var current := CampaignRepository.get_character(character_id)
	if current.is_empty():
		return false
	var old_dead: bool = (current.get("is_dead", 0) == 1)
	current["is_dead"] = 1 if is_dead else 0
	current["is_active"] = 0 if is_dead else 1
	if not CampaignRepository.save_character(current):
		return false
	_log_override("character_status", character_id, "is_dead", str(old_dead), str(is_dead))
	EventBus.override_applied.emit("character_status", character_id, "is_dead")
	if is_dead and not old_dead:
		EventBus.character_died.emit(character_id)
	return true


# ---------------------------------------------------------------------------
# Inventory overrides
# ---------------------------------------------------------------------------

## Add an item to a character's inventory.
func override_add_item(
	character_id: String,
	item_key: String,
	name: String,
	qty: int,
	enc_units: int,
	slot: String
) -> bool:
	var item_id := CampaignRepository.add_inventory_item({
		"character_id": character_id,
		"item_key":     item_key,
		"name":         name,
		"quantity":     qty,
		"encumbrance_units": enc_units,
		"slot":         slot,
	})
	if item_id.is_empty():
		return false
	_log_override("inventory_add", character_id, item_key, "", "%s x%d" % [name, qty])
	EventBus.override_applied.emit("inventory_add", character_id, item_key)
	EventBus.inventory_updated.emit(character_id)
	return true


## Remove an item from inventory by its DB id.
func override_remove_item(item_id: String) -> bool:
	# Fetch first to log old value
	var items := CampaignRepository.get_inventory_items("")
	# We need a direct query — find the item by id across all characters
	CampaignRepository.db.query_with_bindings(
		"SELECT * FROM inventory_items WHERE id = ?", [item_id]
	)
	var row: Dictionary = {}
	if not CampaignRepository.db.query_result.is_empty():
		row = CampaignRepository.db.query_result[0]
	if not CampaignRepository.remove_inventory_item(item_id):
		return false
	var char_id: String = row.get("character_id", "")
	_log_override("inventory_remove", char_id, row.get("item_key", ""), row.get("name", ""), "")
	EventBus.override_applied.emit("inventory_remove", char_id, row.get("item_key", ""))
	EventBus.inventory_updated.emit(char_id)
	return true


## Add or subtract gold pieces for a character by manipulating the coin_gp inventory item.
## [param delta_gp] positive = add gold; negative = remove gold (capped at 0).
func override_adjust_gold(character_id: String, delta_gp: int) -> bool:
	if delta_gp == 0:
		return true
	# Find existing coin_gp item for this character
	var items := CampaignRepository.get_inventory_items(character_id)
	var coin_row: Dictionary = {}
	for item in items:
		if item.get("item_key", "") == GOLD_ITEM_KEY:
			coin_row = item
			break

	var old_qty: int = coin_row.get("quantity", 0) if not coin_row.is_empty() else 0
	var new_qty: int = maxi(0, old_qty + delta_gp)

	if coin_row.is_empty():
		if delta_gp <= 0:
			return true  # Nothing to remove
		# Create new coin_gp item
		var item_id := CampaignRepository.add_inventory_item({
			"character_id":       character_id,
			"item_key":           GOLD_ITEM_KEY,
			"name":               GOLD_ITEM_NAME,
			"quantity":          new_qty,
			"encumbrance_units": 1,
			"slot":              "pack",
		})
		if item_id.is_empty():
			return false
	else:
		if not CampaignRepository.db.query_with_bindings(
			"UPDATE inventory_items SET quantity = ? WHERE id = ?",
			[new_qty, coin_row["id"]]
		):
			push_error("OverrideManager.override_adjust_gold: update failed. character=%s" % character_id)
			return false

	_log_override("inventory_gold", character_id, GOLD_ITEM_KEY, str(old_qty), str(new_qty))
	EventBus.override_applied.emit("inventory_gold", character_id, GOLD_ITEM_KEY)
	EventBus.inventory_updated.emit(character_id)
	return true


# ---------------------------------------------------------------------------
# Hex world overrides
# ---------------------------------------------------------------------------

## Change a single terrain field on a hex cell.
## [param field] must be one of: elevation, biome, water, civilization, has_city, original_biome
## [param controller] pass the live HexMapController to also update in-memory data; null skips it.
func override_hex_terrain(map_id: String, coord: Vector2i, field: String, new_value, controller: HexMapController = null) -> bool:
	# Read old value for logging
	CampaignRepository.db.query_with_bindings(
		"SELECT %s FROM hex_cells WHERE map_id = ? AND q = ? AND r = ?" % field,
		[map_id, coord.x, coord.y]
	)
	var old_value = ""
	if not CampaignRepository.db.query_result.is_empty():
		old_value = CampaignRepository.db.query_result[0].get(field, "")

	if not CampaignRepository.update_hex_terrain_field(map_id, coord.x, coord.y, field, new_value):
		return false
	if controller != null:
		controller.update_hex_terrain(coord, field, new_value)
	var hex_id := "%d,%d" % [coord.x, coord.y]
	_log_override("hex_terrain", hex_id, field, str(old_value), str(new_value))
	EventBus.override_applied.emit("hex_terrain", hex_id, field)
	return true


## Reveal all hexes on the map (set fog to VISIBLE in both DB and controller).
## [param controller] is the live HexMapController; pass null to skip in-memory update.
func override_fog_reveal_all(map_id: String, controller: HexMapController) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE hex_cells SET fog_state = 'visible' WHERE map_id = ?",
		[map_id]
	)
	if controller != null and controller.get_map() != null:
		var map_data := controller.get_map()
		for coord in map_data.hexes.keys():
			map_data.set_fog_state(coord, HexMapData.FogState.VISIBLE)
		controller.visibility_updated.emit()
	_log_override("fog_reveal_all", map_id, "fog_state", "mixed", "visible")
	EventBus.override_applied.emit("fog_reveal_all", map_id, "fog_state")


## Hide all hexes on the map (set fog to HIDDEN in DB and controller).
func override_fog_hide_all(map_id: String, controller: HexMapController) -> void:
	CampaignRepository.db.query_with_bindings(
		"UPDATE hex_cells SET fog_state = 'hidden' WHERE map_id = ?",
		[map_id]
	)
	if controller != null and controller.get_map() != null:
		var map_data := controller.get_map()
		for coord in map_data.hexes.keys():
			map_data.set_fog_state(coord, HexMapData.FogState.HIDDEN)
		controller.visibility_updated.emit()
	_log_override("fog_hide_all", map_id, "fog_state", "mixed", "hidden")
	EventBus.override_applied.emit("fog_hide_all", map_id, "fog_state")


## Set fog state for a single hex.
## [param fog_state_str] must be "hidden", "explored", or "visible".
func override_fog_set_hex(
	map_id: String,
	coord: Vector2i,
	fog_state_str: String,
	controller: HexMapController
) -> void:
	const VALID_FOG_STATES := ["hidden", "explored", "visible"]
	if fog_state_str not in VALID_FOG_STATES:
		push_error("OverrideManager.override_fog_set_hex: invalid fog_state '%s'" % fog_state_str)
		return
	CampaignRepository.update_hex_fog(map_id, coord.x, coord.y, fog_state_str)
	if controller != null and controller.get_map() != null:
		var new_state: HexMapData.FogState
		match fog_state_str:
			"explored": new_state = HexMapData.FogState.EXPLORED
			"visible":  new_state = HexMapData.FogState.VISIBLE
			_:          new_state = HexMapData.FogState.HIDDEN
		controller.get_map().set_fog_state(coord, new_state)
		controller.visibility_updated.emit()
	var hex_id := "%d,%d" % [coord.x, coord.y]
	_log_override("hex_fog", hex_id, "fog_state", "", fog_state_str)
	EventBus.override_applied.emit("hex_fog", hex_id, "fog_state")


## Place a settlement stub on a hex (adds settlement_id to hex_cells.original_biome note).
## Full settlement generation is a separate future system.
func override_place_settlement(map_id: String, coord: Vector2i, settlement_name: String) -> bool:
	# Mark the hex as civilized and flag it as having a city
	var ok1 := CampaignRepository.update_hex_terrain_field(map_id, coord.x, coord.y, "civilization", "civilized")
	var ok2 := CampaignRepository.update_hex_terrain_field(map_id, coord.x, coord.y, "has_city", 1)
	if not (ok1 and ok2):
		return false
	var hex_id := "%d,%d" % [coord.x, coord.y]
	_log_override("settlement_placed", hex_id, "settlement", "", settlement_name)
	EventBus.override_applied.emit("settlement_placed", hex_id, settlement_name)
	return true


# ---------------------------------------------------------------------------
# Spawning overrides
# ---------------------------------------------------------------------------

## Spawn an encounter at a hex with a chosen disposition.
## Creates an EncounterData dict and emits encounter_triggered.
## [param disposition] must be "hostile", "cautious", "neutral", or "friendly".
func override_spawn_encounter(
	map_id: String,
	coord: Vector2i,
	monster_group: String,
	count: int,
	disposition: String
) -> bool:
	const VALID_DISPOSITIONS := ["hostile", "cautious", "neutral", "friendly"]
	if disposition not in VALID_DISPOSITIONS:
		push_error("OverrideManager.override_spawn_encounter: invalid disposition '%s'" % disposition)
		return false

	var reaction_roll := 7  # Neutral baseline; override ignores the actual roll
	match disposition:
		"hostile":  reaction_roll = 2
		"cautious": reaction_roll = 5
		"neutral":  reaction_roll = 7
		"friendly": reaction_roll = 11

	var encounter_id := CampaignRepository.generate_id()
	var hex_id := "%d,%d" % [coord.x, coord.y]
	var encounter_data := {
		"encounter_id":            encounter_id,
		"monster_group":           monster_group,
		"number":                  count,
		"reaction_roll":           reaction_roll,
		"behavioral_disposition":  disposition,
		"hex_id":                  hex_id,
	}
	_log_override(
		"encounter_spawned", hex_id, monster_group,
		"", "%s x%d (%s)" % [monster_group, count, disposition]
	)
	EventBus.override_applied.emit("encounter_spawned", hex_id, monster_group)
	EventBus.encounter_triggered.emit(encounter_data)
	return true


## Place a dungeon entrance stub on a hex. Invokes the dungeon layout generator
## if one is registered; otherwise records a stub with empty dungeon_data.
## Returns the new dungeon entrance id, or "" on failure.
func override_place_dungeon(map_id: String, coord: Vector2i, dungeon_name: String) -> String:
	var entrance_id := CampaignRepository.create_dungeon_entrance({
		"campaign_id":  GameState.campaign_id,
		"map_id":       map_id,
		"hex_q":        coord.x,
		"hex_r":        coord.y,
		"name":         dungeon_name,
		"dungeon_data": "",  # [STUB] dungeon layout generation not yet implemented
	})
	if entrance_id.is_empty():
		return ""
	var hex_id := "%d,%d" % [coord.x, coord.y]
	_log_override("dungeon_placed", hex_id, "dungeon", "", dungeon_name)
	EventBus.override_applied.emit("dungeon_placed", hex_id, dungeon_name)
	return entrance_id


# ---------------------------------------------------------------------------
# Snapshot overrides
# ---------------------------------------------------------------------------

## Save a named snapshot of the current campaign state.
## Returns the new snapshot id, or "" on failure.
func save_session_snapshot(label: String) -> String:
	if GameState.campaign_id.is_empty():
		push_error("OverrideManager.save_session_snapshot: no active campaign")
		return ""
	var snap_id := CampaignRepository.save_snapshot(GameState.campaign_id, label)
	if snap_id.is_empty():
		return ""
	_log_override("snapshot_saved", GameState.campaign_id, "snapshot", "", label)
	EventBus.snapshot_saved.emit(snap_id, label)
	return snap_id


## Restore a named snapshot. Replaces all live campaign data with snapshot content.
## Returns false on failure.
func restore_session_snapshot(snapshot_id: String) -> bool:
	if not CampaignRepository.restore_snapshot(snapshot_id):
		return false
	_log_override("snapshot_restored", GameState.campaign_id, "snapshot", snapshot_id, "")
	EventBus.snapshot_restored.emit(snapshot_id)
	return true


## Returns a list of available snapshots for the current campaign.
## Each entry: { id, label, created_at }
func list_session_snapshots() -> Array:
	if GameState.campaign_id.is_empty():
		return []
	return CampaignRepository.list_snapshots(GameState.campaign_id)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _log_override(
	override_type: String,
	target_id: String,
	field: String,
	old_value: String,
	new_value: String
) -> void:
	if GameState.campaign_id.is_empty():
		return  # No active session — skip logging (e.g. during editor testing)
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO override_log
			(campaign_id, game_day, override_type, target_id, field_changed, old_value, new_value)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	""", [
		GameState.campaign_id,
		CampaignRepository.get_campaign(GameState.campaign_id).get("calendar_day", 0),
		override_type,
		target_id,
		field,
		old_value,
		new_value,
	])
