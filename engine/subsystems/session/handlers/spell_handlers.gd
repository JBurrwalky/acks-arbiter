class_name SpellHandlers
extends RefCounted

## Global event handlers for the spell system's out-of-combat surfaces
## (Session 3). Registered once on session load via SessionRunner.
##
## Event types:
##   "spell_cast_complete"        — sentinel emitted by OutOfCombatCastFlow at
##                                  current_time + 1 round after a successful
##                                  cast. No-op handler — exists so future
##                                  layers (LLM narration, log overlays,
##                                  achievement triggers) can hook a single
##                                  reliable post-cast moment.
##   "spell_cast_encounter_check" — one-off encounter check fired alongside
##                                  spell_cast_complete. Wraps
##                                  SessionRunner.do_encounter_check with the
##                                  active state's terrain / wandering table.
##                                  Does NOT reschedule itself (unlike the
##                                  recurring dungeon_encounter_check).


var _runner = null


func _init(session_runner) -> void:
	_runner = session_runner


func register(registry: EventHandlerRegistry) -> void:
	registry.register("spell_cast_complete", _handle_spell_cast_complete)
	registry.register("spell_cast_encounter_check", _handle_spell_cast_encounter_check)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("spell_cast_complete")
	registry.unregister("spell_cast_encounter_check")


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

## No-op sentinel. Returns an empty dict so the scheduler loop continues.
func _handle_spell_cast_complete(_event: ScheduledEvent) -> Dictionary:
	return {}


## Fires a single encounter check against whatever exploration context is
## active when the event resolves. Mirrors the cadence of the recurring
## per-state encounter check but is single-shot — no `next_events` returned.
func _handle_spell_cast_encounter_check(event: ScheduledEvent) -> Dictionary:
	if _runner == null:
		return {}
	var state_key := String(event.data.get("state_key", _runner.get_current_state_key()))
	var encounter: Dictionary = {}
	match state_key:
		"dungeon":
			encounter = _runner.do_encounter_check(null, _dungeon_wandering_table())
		"wilderness":
			encounter = _runner.do_encounter_check(_wilderness_terrain())
		_:
			# Settlement / camp don't roll random encounters from a cast — the
			# spell still resolves and the sentinel still fires; the encounter
			# table simply does not apply here.
			return {}

	if not encounter.get("triggered", false):
		return {}

	return {
		"auto_pause": true,
		"pause_reason": "Casting drew attention",
		"presentation": {
			"type": "spell_cast_encounter",
			"encounter_data": encounter.get("encounter_data", {}),
		},
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _dungeon_wandering_table() -> Array:
	# Look up the active dungeon's wandering monster table the same way
	# DungeonHandlers does. Returns [] if no controller / no table.
	if _runner == null:
		return []
	var children: Array = _runner.get_children()
	for child in children:
		if child is DungeonMapController and child.has_map():
			var vmap = child.get_voxel_map()
			if vmap != null and "wandering_monster_table" in vmap:
				return vmap.wandering_monster_table
	return []


func _wilderness_terrain():
	# Returns the HexTerrainData at the party's current hex, or null if not
	# in a wilderness state. Same lookup as WildernessHandlers.
	if _runner == null:
		return null
	var party_data = _runner.get_party_data()
	if party_data == null:
		return null
	var hex_ctrl = _runner.get_hex_map_controller()
	if hex_ctrl == null:
		return null
	var map_data = hex_ctrl.get_map() if hex_ctrl.has_method("get_map") else null
	if map_data == null:
		return null
	var hex: Vector2i = party_data.get_hex()
	if map_data.has_method("get_terrain_at"):
		return map_data.get_terrain_at(hex.x, hex.y)
	return null
