class_name WildernessContextMenuBuilder
extends RefCounted

## Builds the list of context menu options for a right-click on a wilderness hex.
##
## Pure logic — no UI nodes, no signals, no side effects. Takes game state in,
## returns an Array of option Dictionaries out. Mirrors DungeonContextMenuBuilder.
##
## Each option: { id: String, label: String, enabled: bool, tooltip: String,
##                category: String, action_data: Dictionary }
## action_data always includes "action_type" key for dispatch.


## Build the full context menu for a right-click on [param target_hex].
## [param active_party_id]: the party whose orders this menu will issue. Empty
##   means no active party — most options will be disabled.
## [param map_data]: HexMapData for reachability checks.
## [param controller]: HexMapController (for can_move_to). May be null in tests.
## Returns Array[Dictionary] of menu options in display order.
static func build_menu(
	target_hex: Vector2i,
	active_party_id: String,
	map_data: HexMapData,
	controller: HexMapController = null,
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	var can_move: bool = true
	if controller != null:
		can_move = controller.can_move_to(target_hex)
	elif map_data != null:
		can_move = map_data.is_valid_coord(target_hex)

	var location_key := "hex:%d,%d" % [target_hex.x, target_hex.y]
	var cache: Dictionary = LocationCacheManager.get_cache_at_location(location_key)
	var has_cache: bool = not cache.is_empty()
	var has_party: bool = not active_party_id.is_empty()

	var base_data := {"hex_q": target_hex.x, "hex_r": target_hex.y}

	options.append({
		"id": "move_here",
		"label": "Move Here",
		"enabled": can_move and has_party,
		"tooltip": "Travel the party to this hex.",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_move_here"),
	})
	options.append({
		"id": "explore",
		"label": "Explore",
		"enabled": can_move and has_party,
		"tooltip": "",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_explore_hex"),
	})
	options.append({
		"id": "build_stronghold",
		"label": "Build Stronghold",
		"enabled": can_move and has_party,
		"tooltip": "",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_build_stronghold"),
	})
	options.append({
		"id": "place_loot_cache",
		"label": "Place Loot Cache",
		"enabled": can_move and has_party and not has_cache,
		"tooltip": "A cache already exists at this hex." if has_cache else "Hide a cache at this hex (1 hour).",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_place_cache"),
	})
	options.append({
		"id": "visit_loot_cache",
		"label": "Visit Loot Cache",
		"enabled": can_move and has_party and has_cache,
		"tooltip": "" if has_cache else "No cache at this hex.",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_visit_cache"),
	})
	options.append({
		"id": "survey",
		"label": "Survey",
		"enabled": can_move and has_party,
		"tooltip": "",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_survey"),
	})

	options.append({
		"id": "cancel",
		"label": "Cancel",
		"enabled": true,
		"tooltip": "",
		"category": "universal",
		"action_data": {"action_type": "cancel"},
	})

	return options


static func _action(base: Dictionary, action_type: String) -> Dictionary:
	var d := base.duplicate()
	d["action_type"] = action_type
	return d
