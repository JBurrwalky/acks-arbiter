extends RefCounted

## Builds the list of context menu options for a right-click on a dungeon cell.
##
## Pure logic — no UI nodes, no signals, no side effects. Takes game state in,
## returns an Array of option Dictionaries out.
##
## Each option: { id: String, label: String, enabled: bool, tooltip: String,
##                category: String, action_data: Dictionary }
##
## Categories: "universal", "environment", "entity", "self"
## action_data always includes "action_type" key for dispatch.

const DungeonSessionState := preload("res://engine/subsystems/exploration/dungeon_session_state.gd")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Build the full context menu for a right-click on [param target_cell].
## [param selected_ids]: currently selected entity IDs.
## [param map]: the current TacticalMapData level.
## [param party_data]: PartyData for class/proficiency/inventory checks.
## [param session_state]: DungeonSessionState for control groups, idle behaviors.
## [param light_manager]: DungeonLightManager (or null) for light source checks.
## Returns Array[Dictionary] of menu options in display order.
static func build_menu(
	selected_ids: Array,
	target_cell: Vector2i,
	map: TacticalMapData,
	party_data,  # PartyData or null
	session_state,  # DungeonSessionState or null
	light_manager = null,  # DungeonLightManager or null
) -> Array[Dictionary]:
	if selected_ids.is_empty():
		return []

	var options: Array[Dictionary] = []
	var cell: Dictionary = map.get_cell(target_cell) if map != null else {}
	var fog_state: int = map.get_fog(target_cell) if map != null else TacticalMapData.FogState.HIDDEN

	# Determine if the target cell is the selected entity's own cell (self-action).
	var is_self_click := _is_self_click(selected_ids, target_cell, map)

	# --- Universal options (always present) ---
	options.append_array(_build_universal_options(target_cell))

	# --- Environment options (cell features) ---
	if fog_state != TacticalMapData.FogState.HIDDEN and not cell.is_empty():
		options.append_array(_build_door_options(target_cell, cell, selected_ids, party_data, map, session_state))
		options.append_array(_build_stair_options(target_cell, cell, map, selected_ids, session_state))
		options.append_array(_build_trap_options(target_cell, cell, selected_ids, party_data))
		options.append_array(_build_interactable_options(target_cell, cell))

	# --- Entity options (target cell has entities) ---
	if fog_state == TacticalMapData.FogState.VISIBLE:
		if is_self_click:
			options.append_array(_build_self_options(selected_ids, party_data, light_manager))
		else:
			options.append_array(_build_entity_options(selected_ids, target_cell, map, party_data))
		# Loot pile on ground
		options.append_array(_build_loot_options(target_cell, cell))

	return options


# ---------------------------------------------------------------------------
# Universal options
# ---------------------------------------------------------------------------

static func _build_universal_options(target_cell: Vector2i) -> Array[Dictionary]:
	return [
		{
			"id": "move_here",
			"label": "Move Here",
			"enabled": true,
			"tooltip": "",
			"category": "universal",
			"action_data": {"action_type": "move_here", "cell": target_cell},
		},
		{
			"id": "search_here",
			"label": "Search Here",
			"enabled": true,
			"tooltip": "Search this area (1 turn)",
			"category": "universal",
			"action_data": {"action_type": "search_here", "cell": target_cell},
		},
		{
			"id": "listen_here",
			"label": "Listen Here",
			"enabled": true,
			"tooltip": "Listen for sounds (1 round)",
			"category": "universal",
			"action_data": {"action_type": "listen_here", "cell": target_cell},
		},
		{
			"id": "cancel",
			"label": "Cancel",
			"enabled": true,
			"tooltip": "",
			"category": "universal",
			"action_data": {"action_type": "cancel"},
		},
	]


# ---------------------------------------------------------------------------
# Door options
# ---------------------------------------------------------------------------

static func _build_door_options(
	target_cell: Vector2i,
	cell: Dictionary,
	selected_ids: Array,
	party_data,
	map: TacticalMapData,
	session_state = null,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not map.is_door(target_cell):
		return options

	var door_state: String = cell.get("door_state", "")
	var door_type: String = cell.get("door_type", "")
	var door_material: String = cell.get("door_material", "wood_standard")
	var door_detected: bool = cell.get("door_detected", true)
	var tf: String = cell.get("terrain_feature", "")

	# Destroyed doors — no interactions.
	if door_state == "destroyed":
		return options

	# Secret doors that haven't been detected — no door options shown.
	if tf == "door_secret" and not door_detected:
		return options

	# Arches are always open — no interaction.
	if door_type == "arch":
		return options

	# Check spike/wedge state from session.
	var is_spiked := session_state != null and session_state.has_method("is_spiked") \
		and session_state.is_spiked(target_cell)
	var is_wedged := session_state != null and session_state.has_method("is_wedged") \
		and session_state.is_wedged(target_cell)
	var has_spikes := _any_selected_has_iron_spikes(selected_ids)

	# --- Spiked door: offer removal, block open ---
	if is_spiked:
		options.append(_option("remove_spike", "Remove Spike", true,
			"Remove the iron spike (returns spike to inventory)", "environment",
			{"action_type": "remove_spike", "cell": target_cell}))
		# Listen is still available through a spiked door.
		if tf != "portcullis":
			options.append(_option("listen_at_door", "Listen at Door", true,
				"Listen through the door (1 round)", "environment",
				{"action_type": "listen_at_door", "cell": target_cell}))
		return options

	# --- Wedged door: offer removal, block close ---
	if is_wedged:
		options.append(_option("remove_wedge", "Remove Wedge", true,
			"Remove the iron spike (returns spike to inventory)", "environment",
			{"action_type": "remove_wedge", "cell": target_cell}))
		return options

	# --- Portcullis ---
	if tf == "portcullis":
		if door_state != "open":
			options.append(_option("force_portcullis", "Force Portcullis", true,
				"Strength throw to raise (18+ with STR modifier). Drops when you act.",
				"environment",
				{"action_type": "force_portcullis", "cell": target_cell}))
			# Spike shut a closed portcullis.
			options.append(_option("spike_shut", "Spike Shut", has_spikes,
				"Use an iron spike to block the portcullis" if has_spikes else "Requires iron spikes",
				"environment",
				{"action_type": "spike_shut", "cell": target_cell}))
		else:
			# Check if held open (not wedged — wedged is handled above).
			var is_held := session_state != null and session_state.has_method("is_held_open") \
				and session_state.is_held_open(target_cell)
			if not is_held:
				options.append(_option("drop_portcullis", "Drop Portcullis", true,
					"Lower the portcullis", "environment",
					{"action_type": "drop_portcullis", "cell": target_cell}))
			# Wedge open a raised portcullis.
			options.append(_option("wedge_open", "Wedge Open", has_spikes,
				"Use an iron spike to hold the portcullis open" if has_spikes else "Requires iron spikes",
				"environment",
				{"action_type": "wedge_open", "cell": target_cell}))
		return options

	# --- Open door — can close it ---
	if door_state == "open":
		options.append(_option("close_door", "Close Door", true, "", "environment",
			{"action_type": "close_door", "cell": target_cell}))
		# Wedge open (with iron spike).
		options.append(_option("wedge_open", "Wedge Open", has_spikes,
			"Use an iron spike to hold the door open" if has_spikes else "Requires iron spikes",
			"environment",
			{"action_type": "wedge_open", "cell": target_cell}))
		return options

	# --- Closed door (various sub-states) ---
	if door_state == "closed" or door_state.is_empty():
		options.append(_option("open_door", "Open Door", true, "", "environment",
			{"action_type": "open_door", "cell": target_cell}))

	if door_state == "stuck":
		options.append(_option("force_door", "Force Door", true,
			"Strength throw to unstick (1 round)", "environment",
			{"action_type": "force_door", "cell": target_cell}))

	if door_state == "locked":
		# Unlock with key.
		options.append(_option("unlock_door", "Unlock", false,
			"Requires the matching key", "environment",
			{"action_type": "unlock_door", "cell": target_cell}))
		# Pick lock (thief or Lockpicking proficiency).
		var can_pick := _any_selected_can_pick_lock(selected_ids, party_data)
		var pick_tooltip := "Thief class or Lockpicking proficiency required"
		if can_pick:
			# Check if all capable characters have already failed at this lock.
			var all_failed := _all_pickers_failed(selected_ids, party_data, session_state)
			if all_failed:
				can_pick = false
				pick_tooltip = "Already failed — must gain a level to retry"
			else:
				pick_tooltip = "Pick lock throw (1 turn)"
		options.append(_option("pick_lock", "Pick Lock", can_pick,
			pick_tooltip, "environment",
			{"action_type": "pick_lock", "cell": target_cell}))

	# Bash door — requires wooden door AND an axe in the basher's inventory.
	if door_state in ["closed", "stuck", "locked", ""]:
		if not _is_wooden_door(door_material):
			options.append(_option("bash_door", "Bash Door", false,
				"This door is too strong to batter down.", "environment",
				{"action_type": "bash_door", "cell": target_cell}))
		elif not _any_selected_has_axe(selected_ids):
			options.append(_option("bash_door", "Bash Door", false,
				"Requires an axe.", "environment",
				{"action_type": "bash_door", "cell": target_cell}))
		else:
			var bash_turns := _bash_door_turns(door_material)
			options.append(_option("bash_door", "Bash Door", true,
				"Destroy the door (%d turn%s). Requires an axe." % [bash_turns, "s" if bash_turns > 1 else ""],
				"environment",
				{"action_type": "bash_door", "cell": target_cell, "turns": bash_turns}))

	# Spike shut — any closed door (requires iron spikes).
	if door_state in ["closed", "stuck", "locked", ""]:
		options.append(_option("spike_shut", "Spike Shut", has_spikes,
			"Use an iron spike to block the door" if has_spikes else "Requires iron spikes",
			"environment",
			{"action_type": "spike_shut", "cell": target_cell}))

	# Listen at door — special variant of listen.
	options.append(_option("listen_at_door", "Listen at Door", true,
		"Listen through the door (1 round)", "environment",
		{"action_type": "listen_at_door", "cell": target_cell}))

	return options


# ---------------------------------------------------------------------------
# Stair options
# ---------------------------------------------------------------------------

static func _build_stair_options(
	target_cell: Vector2i,
	cell: Dictionary,
	map: TacticalMapData,
	selected_ids: Array = [],
	session_state = null,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var tf: String = cell.get("terrain_feature", "")

	var is_transition := map.is_transition_cell(target_cell)

	if tf == "stairs_up":
		if is_transition:
			if _has_exit_candidates(selected_ids, map, session_state):
				options.append(_option("exit_dungeon", "Exit Dungeon", true,
					"Queue selected characters to exit the dungeon", "environment",
					{"action_type": "exit_dungeon", "cell": target_cell}))
		else:
			options.append(_option("ascend", "Ascend", true,
				"Climb to the level above", "environment",
				{"action_type": "ascend", "cell": target_cell}))

	elif tf == "stairs_down":
		options.append(_option("descend", "Descend", true,
			"Descend to the level below", "environment",
			{"action_type": "descend", "cell": target_cell}))

	elif is_transition and tf != "stairs_up" and tf != "stairs_down":
		# Non-stair transition cell (e.g., cave entrance).
		if _has_exit_candidates(selected_ids, map, session_state):
			options.append(_option("exit_dungeon", "Exit Dungeon", true,
				"Queue selected characters to exit the dungeon", "environment",
				{"action_type": "exit_dungeon", "cell": target_cell}))

	return options


## Returns true if any selected entity hasn't already exited or been queued.
static func _has_exit_candidates(
	selected_ids: Array,
	map: TacticalMapData,
	session_state,
) -> bool:
	for eid in selected_ids:
		var sid: String = str(eid)
		if map.get_entity_pos(sid) == Vector2i(-1, -1):
			continue  # Not on the map.
		if session_state != null:
			if session_state.has_method("is_exited") and session_state.is_exited(sid):
				continue
			if session_state.has_method("is_queued_for_exit") and session_state.is_queued_for_exit(sid):
				continue
		return true
	return false


# ---------------------------------------------------------------------------
# Trap options
# ---------------------------------------------------------------------------

static func _build_trap_options(
	target_cell: Vector2i,
	cell: Dictionary,
	selected_ids: Array,
	party_data,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var trap_detected: bool = cell.get("trap_detected", false)
	var trap_disarmed: bool = cell.get("trap_disarmed", false)

	if not trap_detected or trap_disarmed:
		return options

	var can_disarm := _any_selected_can_disarm_trap(selected_ids, party_data)
	options.append(_option("disarm_trap", "Disarm Trap", can_disarm,
		"Thief class or Find/Remove Traps proficiency required" if not can_disarm else "Remove trap throw (1 turn)",
		"environment",
		{"action_type": "disarm_trap", "cell": target_cell}))

	options.append(_option("trigger_trap", "Trigger Trap (Deliberate)", true,
		"Use a 10-foot pole or thrown object to trigger safely", "environment",
		{"action_type": "trigger_trap", "cell": target_cell}))

	return options


# ---------------------------------------------------------------------------
# Interactable object options (levers, fountains, chests, etc.)
# ---------------------------------------------------------------------------

static func _build_interactable_options(
	target_cell: Vector2i,
	cell: Dictionary,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var tf: String = cell.get("terrain_feature", "")

	if tf == "lever":
		options.append(_option("use_lever", "Use Lever", true,
			"Pull or push the lever", "environment",
			{"action_type": "use_lever", "cell": target_cell}))
	elif tf in ["fountain", "altar", "statue"]:
		options.append(_option("examine", "Examine", true,
			"Examine this object", "environment",
			{"action_type": "examine", "cell": target_cell}))

	return options


# ---------------------------------------------------------------------------
# Loot options (items on ground)
# ---------------------------------------------------------------------------

static func _build_loot_options(
	target_cell: Vector2i,
	cell: Dictionary,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var has_items: bool = cell.get("has_ground_items", false)
	if not has_items:
		return options

	options.append(_option("loot", "Loot", true,
		"Pick up items from the ground", "entity",
		{"action_type": "loot", "cell": target_cell}))
	options.append(_option("pick_up_all", "Pick Up All", true,
		"Grab everything (up to encumbrance limit)", "entity",
		{"action_type": "pick_up_all", "cell": target_cell}))

	return options


# ---------------------------------------------------------------------------
# Entity options (target cell contains another entity)
# ---------------------------------------------------------------------------

static func _build_entity_options(
	selected_ids: Array,
	target_cell: Vector2i,
	map: TacticalMapData,
	party_data,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if map == null:
		return options

	var target_entities: Array[String] = map.get_entities_at(target_cell)
	if target_entities.is_empty():
		return options

	# Determine relationship to first target entity.
	var target_id: String = target_entities[0]
	var is_party_member := _is_party_member(target_id, party_data)

	if is_party_member:
		# Target is a friendly party member.
		options.append(_option("trade", "Trade", true,
			"Open dual inventory to exchange items", "entity",
			{"action_type": "trade", "cell": target_cell, "target_id": target_id}))
		options.append(_option("heal", "Heal", false,
			"Healing spells or Healing proficiency required", "entity",
			{"action_type": "heal", "cell": target_cell, "target_id": target_id}))
		options.append(_option("add_to_group", "Add to Group", true,
			"Add to the selected entity's control group", "entity",
			{"action_type": "add_to_group", "cell": target_cell, "target_id": target_id}))
		# Cast Spell (deferred).
		options.append(_option("cast_spell", "Cast Spell", false,
			"Spell system not yet implemented", "entity",
			{"action_type": "cast_spell", "cell": target_cell, "target_id": target_id}))
	else:
		# Target is NPC or monster — show both talk and attack.
		options.append(_option("talk", "Talk", true,
			"Initiate dialogue", "entity",
			{"action_type": "talk", "cell": target_cell, "target_id": target_id}))
		options.append(_option("attack", "Attack", true,
			"Engage in combat", "entity",
			{"action_type": "attack", "cell": target_cell, "target_id": target_id}))
		options.append(_option("cast_spell", "Cast Spell", false,
			"Spell system not yet implemented", "entity",
			{"action_type": "cast_spell", "cell": target_cell, "target_id": target_id}))

	return options


# ---------------------------------------------------------------------------
# Self-action options (right-click own cell)
# ---------------------------------------------------------------------------

static func _build_self_options(
	selected_ids: Array,
	party_data,
	light_manager,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if selected_ids.is_empty():
		return options

	var first_id: String = selected_ids[0]

	# Hide (thief or Hide in Shadows proficiency).
	var can_hide := _any_selected_can_hide(selected_ids, party_data)
	options.append(_option("hide", "Hide", can_hide,
		"Thief class or relevant proficiency required" if not can_hide else "Attempt Hide in Shadows",
		"self",
		{"action_type": "hide"}))

	# Stealth Move — not applicable for self-click (that's Hide); stealth move
	# is for distant cells. Omitted here per GDD §3.5.2.

	# Light Torch.
	options.append(_option("light_torch", "Light Torch", true,
		"Light a torch (requires torch + tinderbox)", "self",
		{"action_type": "light_torch", "character_id": first_id}))

	# Light Lantern.
	options.append(_option("light_lantern", "Light Lantern", true,
		"Light a lantern (requires lantern + tinderbox + oil)", "self",
		{"action_type": "light_lantern", "character_id": first_id}))

	# Extinguish Light.
	var has_light := false
	if light_manager != null and light_manager.has_method("get_light_radius"):
		has_light = light_manager.get_light_radius(first_id) > 0
	options.append(_option("extinguish_light", "Extinguish Light", has_light,
		"No active light source" if not has_light else "Put out your light source",
		"self",
		{"action_type": "extinguish_light", "character_id": first_id}))

	# Heal (self).
	options.append(_option("heal_self", "Heal", false,
		"Healing spells or Healing proficiency required", "self",
		{"action_type": "heal", "character_id": first_id}))

	# Cast Spell (deferred).
	options.append(_option("cast_spell_self", "Cast Spell", false,
		"Spell system not yet implemented", "self",
		{"action_type": "cast_spell", "character_id": first_id}))

	# Use Item.
	options.append(_option("use_item", "Use Item", true,
		"Use a consumable item (potion, scroll)", "self",
		{"action_type": "use_item", "character_id": first_id}))

	# Set Default Idle Behavior.
	options.append(_option("set_idle_behavior", "Set Default Idle Behavior", true,
		"Configure what this entity does when idle", "self",
		{"action_type": "set_idle_behavior", "character_id": first_id}))

	# Drop Item.
	options.append(_option("drop_item", "Drop Item", true,
		"Drop an item from inventory onto the ground", "self",
		{"action_type": "drop_item", "character_id": first_id}))

	return options


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Check if the target cell is the same cell as any selected entity.
static func _is_self_click(selected_ids: Array, target_cell: Vector2i, map: TacticalMapData) -> bool:
	if map == null:
		return false
	for eid in selected_ids:
		if map.get_entity_pos(eid) == target_cell:
			return true
	return false


## Check if an entity is a party member (present in PartyData).
static func _is_party_member(entity_id: String, party_data) -> bool:
	if party_data == null:
		return false
	if not party_data.has_method("get_member"):
		return false
	return party_data.get_member(entity_id) != null


## Check if any selected entity can pick locks (thief class or Lockpicking proficiency).
static func _any_selected_can_pick_lock(selected_ids: Array, party_data) -> bool:
	return _any_selected_has_ability(selected_ids, party_data, "thief", "lockpicking")


## Check if ALL lock-capable selected entities have already failed a pick lock attempt.
## Returns false if session_state is null (permissive — don't block if we can't check).
static func _all_pickers_failed(selected_ids: Array, party_data, session_state) -> bool:
	if session_state == null or party_data == null:
		return false
	if not session_state.has_method("has_failed_pick_lock"):
		return false
	var any_can_try := false
	for eid in selected_ids:
		var cd = party_data.get_member(str(eid))
		if cd == null:
			continue
		# Only check entities that CAN pick locks.
		if cd.combat_progression != "thief" and not cd.has_proficiency("lockpicking"):
			continue
		if not session_state.has_failed_pick_lock(str(eid), cd.level):
			return false  # At least one capable picker hasn't failed.
		any_can_try = true
	return any_can_try  # True only if there were capable pickers and ALL failed.


## Check if any selected entity can disarm traps (thief class or Find/Remove Traps prof).
static func _any_selected_can_disarm_trap(selected_ids: Array, party_data) -> bool:
	return _any_selected_has_ability(selected_ids, party_data, "thief", "find_traps")


## Check if any selected entity can hide (thief class or relevant proficiency).
static func _any_selected_can_hide(selected_ids: Array, party_data) -> bool:
	return _any_selected_has_ability(selected_ids, party_data, "thief", "skulking")


## Generic check: any selected entity has the given combat_progression OR proficiency.
static func _any_selected_has_ability(
	selected_ids: Array,
	party_data,
	progression: String,
	proficiency_key: String,
) -> bool:
	if party_data == null or not party_data.has_method("get_member"):
		return false
	for eid in selected_ids:
		var cd = party_data.get_member(str(eid))
		if cd == null:
			continue
		if cd.combat_progression == progression:
			return true
		if cd.has_proficiency(proficiency_key):
			return true
	return false


## Check if any selected entity has iron spikes in their inventory.
static func _any_selected_has_iron_spikes(selected_ids: Array) -> bool:
	for eid in selected_ids:
		var items: Array = CampaignRepository.get_inventory_items(str(eid))
		for item in items:
			if item.get("item_key", "") == "iron_spikes_12" and item.get("quantity", 0) > 0:
				return true
	return false


## Check if any selected entity has an axe in their inventory.
static func _any_selected_has_axe(selected_ids: Array) -> bool:
	const AXE_ITEM_KEYS := ["hand_axe", "battle_axe", "great_axe"]
	for eid in selected_ids:
		var items: Array = CampaignRepository.get_inventory_items(str(eid))
		for item in items:
			if item.get("item_key", "") in AXE_ITEM_KEYS:
				return true
	return false


## Is this a wooden door material?
static func _is_wooden_door(door_material: String) -> bool:
	return door_material in ["wood_simple", "wood_standard", "wood_reinforced"]


## How many turns to bash a wooden door?
static func _bash_door_turns(door_material: String) -> int:
	match door_material:
		"wood_simple":
			return 1
		"wood_standard", "wood_reinforced":
			return 3
		_:
			return 0  # Non-wooden doors cannot be bashed.


## Convenience constructor for an option dictionary.
static func _option(
	id: String,
	label: String,
	enabled: bool,
	tooltip: String,
	category: String,
	action_data: Dictionary,
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"enabled": enabled,
		"tooltip": tooltip,
		"category": category,
		"action_data": action_data,
	}
