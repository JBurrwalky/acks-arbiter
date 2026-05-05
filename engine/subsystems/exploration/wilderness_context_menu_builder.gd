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
## [param map_data]: HexMapData for validity / passability lookups.
## [param controller]: HexMapController (for is_hex_passable + party_hex). May
##   be null in unit tests, in which case the builder falls back to map_data.
## [param current_hex]: the active party's current hex. When the target equals
##   it, the menu omits Move Here and treats activities as on-hex (no travel).
##   Defaults to (-9999,-9999) so callers that don't supply it never collide
##   with a real hex.
## Returns Array[Dictionary] of menu options in display order.
static func build_menu(
	target_hex: Vector2i,
	active_party_id: String,
	map_data: HexMapData,
	controller: HexMapController = null,
	current_hex: Vector2i = Vector2i(-9999, -9999),
) -> Array[Dictionary]:
	var options: Array[Dictionary] = []

	# Target must exist on the map and be passable terrain. Move Here gating is
	# reachability — we let the execution layer (find_path) reject if no route
	# exists, so the menu doesn't disable a hex the player can clearly see.
	var target_valid: bool = false
	var target_passable: bool = false
	if controller != null:
		target_valid = controller.get_map() != null \
			and controller.get_map().is_valid_coord(target_hex)
		target_passable = target_valid and controller.is_hex_passable(target_hex)
	elif map_data != null:
		target_valid = map_data.is_valid_coord(target_hex)
		# Without a controller, fall back to a local passability check so unit
		# tests that pass map_data but not controller still gate ocean/lake.
		if target_valid:
			var t: HexTerrainData = map_data.get_hex(target_hex)
			target_passable = t == null \
				or (t.water != HexTerrainData.WATER_OCEAN \
					and t.water != HexTerrainData.WATER_LAKE)
	else:
		# Tests with both nulls: assume valid+passable so existing fixtures pass.
		target_valid = true
		target_passable = true

	var is_current_hex: bool = (target_hex == current_hex)

	var location_key := "hex:%d,%d" % [target_hex.x, target_hex.y]
	var cache: Dictionary = LocationCacheManager.get_cache_at_location(location_key)
	var has_cache: bool = not cache.is_empty()
	var has_party: bool = not active_party_id.is_empty()

	var base_data := {"hex_q": target_hex.x, "hex_r": target_hex.y}

	# Move Here: omitted entirely when targeting the party's current hex (less
	# clutter than a permanently-disabled "You are here" entry).
	if not is_current_hex:
		options.append({
			"id": "move_here",
			"label": "Move Here",
			"enabled": target_passable and has_party,
			"tooltip": "Travel the party to this hex." if target_passable \
				else "This terrain is impassable.",
			"category": "universal",
			"action_data": _action(base_data, "wilderness_move_here"),
		})

	# Activity options: on the current hex they fire in place. On a remote
	# passable hex the dispatcher pathfinds first and queues the activity to
	# fire on arrival. Either way, gating is "passable target + active party".
	var activity_enabled: bool = (is_current_hex or target_passable) and has_party

	options.append({
		"id": "explore",
		"label": "Explore",
		"enabled": activity_enabled,
		"tooltip": "",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_explore_hex"),
	})
	options.append({
		"id": "build_stronghold",
		"label": "Build Stronghold",
		"enabled": activity_enabled,
		"tooltip": "",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_build_stronghold"),
	})
	options.append({
		"id": "place_loot_cache",
		"label": "Place Loot Cache",
		"enabled": activity_enabled and not has_cache,
		"tooltip": "A cache already exists at this hex." if has_cache else "Hide a cache at this hex (1 hour).",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_place_cache"),
	})
	options.append({
		"id": "visit_loot_cache",
		"label": "Visit Loot Cache",
		"enabled": activity_enabled and has_cache,
		"tooltip": "" if has_cache else "No cache at this hex.",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_visit_cache"),
	})
	# Survey — Land Surveying assessment per le_wilderness_lair_rules.xml
	# §land_surveying. Estimates the total lair count in the hex (18+ base,
	# +4 cumulative per successful prior search). Quick action, no
	# wandering-encounter risk.
	options.append({
		"id": "survey",
		"label": "Survey",
		"enabled": activity_enabled,
		"tooltip": "Land Surveying assessment (18+ on 1d20, +4 per prior successful search). Estimates total lairs in this hex.",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_survey"),
	})
	# Search for Lairs — full-day deliberate search per
	# le_wilderness_lair_rules.xml §searching_for_lairs. 1 throw per hour for
	# 8 hours, target derived from daily wilderness movement (18+ at slow
	# speed); +4 with Tracking. One wandering-monster check per hour while
	# searching. Stops on first reveal or first encounter.
	options.append({
		"id": "search_lair",
		"label": "Search for Lairs",
		"enabled": activity_enabled,
		"tooltip": "Spend a day searching this hex for lairs. +4 with Tracking. One wandering check per hour.",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_search_lair"),
	})
	# Hunt — full-day deliberate activity per acore_adventures_and_encounters.xml
	# §rations_and_foraging.hunting. Daily auto-forage is independent and runs
	# on the wilderness_day_tick; players choose Hunt to commit a full day to
	# meat with the wandering-encounter risk in exchange for 2d6 person-feeds.
	options.append({
		"id": "hunt",
		"label": "Hunt",
		"enabled": activity_enabled,
		"tooltip": "Full-day hunt (1d20 vs 14, +4 Survival; 2d6 person-feeds on success). Triggers a wandering monster check.",
		"category": "universal",
		"action_data": _action(base_data, "wilderness_hunt"),
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
