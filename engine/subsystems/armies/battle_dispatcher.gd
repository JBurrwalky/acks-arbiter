class_name BattleDispatcher
extends RefCounted

## Routes EventBus.armies_collided (and siege-assault triggers from Phase 9)
## to the appropriate field-battle resolution path per gdd-army-warfare.md §4.7
## and §6.11.
##
## Decision tree:
##   - Both armies are NPC-owned → resolve_silently (silent path); outcome
##     posts to the unified log per §7.6.
##   - At least one army is PC-owned (or PC-vassal under PC command) →
##     interactive path: start battle, EventScheduler pauses, the
##     field_battle_panel opens (Phase 6B part 2 wires this UI). The dispatcher
##     creates the field_battles row and emits battle_started + battle_pause_for_player.
##
## Phase 6A part 1's collision detector emits armies_collided. Phase 6B part 1
## (this module) consumes it. The Phase 6A part 2 work also needs to wire the
## scheduler-pause callback so the EventScheduler stops on player-involved
## collisions.
##
## Public API:
##   dispatch_collision(army_a_id, army_b_id, hex_q, hex_r, calendar_day,
##                      dice_roller=Callable()) -> Dictionary
##     Returns {battle_id, mode, outcome (silent only)}.
##   register_collision_listener() / unregister_collision_listener()
##     Helper to attach/detach the EventBus.armies_collided handler.

const MODE_SILENT := "silent"
const MODE_INTERACTIVE := "interactive"


# ---------------------------------------------------------------------------
# Collision listener (handoff-army-warfare-seams.md §3 deliverable 1)
# ---------------------------------------------------------------------------

## Attach the EventBus.armies_collided handler so march-time hostile collisions
## (emitted by ArmyCollisionDetector.detect_at_hex inside ArmyMarcher's travel-leg
## handler) route into dispatch_collision. Called at session activation
## (SessionRunner.load_session); idempotent. armies_collided carries no calendar_day,
## so the handler sources it from Timekeeping.
static func register_collision_listener() -> void:
	if not EventBus.armies_collided.is_connected(_on_armies_collided):
		EventBus.armies_collided.connect(_on_armies_collided)


static func unregister_collision_listener() -> void:
	if EventBus.armies_collided.is_connected(_on_armies_collided):
		EventBus.armies_collided.disconnect(_on_armies_collided)


static func _on_armies_collided(army_a_id: String, army_b_id: String, hex_q: int, hex_r: int) -> void:
	dispatch_collision(army_a_id, army_b_id, hex_q, hex_r, Timekeeping.get_calendar_day())


static func dispatch_collision(
	army_a_id: String,
	army_b_id: String,
	hex_q: int,
	hex_r: int,
	calendar_day: int,
	dice_roller: Callable = Callable()
) -> Dictionary:
	var army_a: Dictionary = ArmyRepository.get_army(army_a_id)
	var army_b: Dictionary = ArmyRepository.get_army(army_b_id)
	if army_a.is_empty() or army_b.is_empty():
		return {"battle_id": "", "mode": "", "outcome": "", "error": "missing_army"}

	# Re-entrancy guard: an army already in an active battle must not be pulled into a second
	# one. This matters for the Phase-C resistance seam — ExtractionResistanceRouter materialises
	# a defender at the extraction hex and dispatches it, then ArmyMarcher's own post-arrival
	# collision scan re-scans that hex; without this guard an ONGOING (interactive) resistance
	# battle would spawn a duplicate. (Silent battles resolve before the re-scan and the loser
	# retreats/disbands, so the pair is already gone — this specifically covers the async case.)
	if String(army_a.get("state", "")) == "battling" or String(army_b.get("state", "")) == "battling":
		return {"battle_id": "", "mode": "", "outcome": "", "error": "already_battling"}

	# Determine attacker / defender per the strategic-stance + arrival rules
	# (gdd-army-warfare.md §4.7). v1 simplification: the army NOT currently
	# in 'encamped' is the attacker (it's the one that moved into the hex).
	# If both are encamped or both are marching, fall back to the GDD §6.1
	# defender_determination procedure: smaller army is the defender (using
	# total BR as proxy for size).
	var attacker_id: String
	var defender_id: String
	var a_state: String = String(army_a.get("state", ""))
	var b_state: String = String(army_b.get("state", ""))
	if a_state == "marching" and b_state != "marching":
		attacker_id = army_a_id
		defender_id = army_b_id
	elif b_state == "marching" and a_state != "marching":
		attacker_id = army_b_id
		defender_id = army_a_id
	else:
		# Use BR as size proxy.
		var br_a: float = _compute_army_br(army_a_id)
		var br_b: float = _compute_army_br(army_b_id)
		if br_a >= br_b:
			attacker_id = army_a_id
			defender_id = army_b_id
		else:
			attacker_id = army_b_id
			defender_id = army_a_id

	# Determine if the player is involved.
	var is_player_involved: bool = _is_player_involved(army_a) or _is_player_involved(army_b)

	# Determine terrain at the collision hex. v1: read from hex_cells if
	# available; default to clear_or_grass.
	var terrain: String = _get_hex_terrain(army_a, hex_q, hex_r)

	# Determine current weather. v1: read from weather_states for the campaign
	# if available; default to calm.
	var weather: String = "calm"

	# Start the battle.
	var battle_id: String = FieldBattleResolver.start_battle(
		attacker_id, defender_id,
		terrain, weather, calendar_day,
		is_player_involved, dice_roller
	)

	if battle_id.is_empty():
		return {"battle_id": "", "mode": "", "outcome": "", "error": "start_battle_failed"}

	if is_player_involved:
		# Interactive path — the field_battle_panel UI will drive continue_battle.
		# Phase 6B part 2 wires the scheduler-pause + UI open. v1 just emits the
		# pause signal; the actual scheduler integration is part of Phase 6A part 2.
		if EventBus.has_signal("battle_pause_for_player"):
			EventBus.emit_signal("battle_pause_for_player", battle_id, "deployment")
		return {"battle_id": battle_id, "mode": MODE_INTERACTIVE, "outcome": ""}

	# Silent path.
	var outcome: String = FieldBattleResolver.resolve_silently(battle_id, dice_roller)
	return {"battle_id": battle_id, "mode": MODE_SILENT, "outcome": outcome}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _is_player_involved(army: Dictionary) -> bool:
	## A battle is player-involved if any of:
	##   - The army's political_owner_id is a PC.
	##   - The army's command_character_id is a PC.
	##   - (Future) A PC vassal Called-to-Arms with command_authority='lord'.
	##     Per gdd-army-warfare.md §8.5; that requires Phase 7 Realm AI's
	##     allegiance graph and is out of scope for v1.
	if army.is_empty():
		return false
	if _is_pc_character(String(army.get("political_owner_id", ""))):
		return true
	if _is_pc_character(String(army.get("command_character_id", ""))):
		return true
	return false


static func _is_pc_character(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT character_type FROM characters WHERE id = ?", [character_id]):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	return String(CampaignRepository.db.query_result[0].get("character_type", "")) == "pc"


static func _compute_army_br(army_id: String) -> float:
	var assignments: Array = ArmyRepository.list_active_assignments_for_army(army_id)
	var total: float = 0.0
	for assn in assignments:
		var unit_id: String = String(assn.get("troop_unit_id", ""))
		if not CampaignRepository.db.query_with_bindings(
			"SELECT battle_rating FROM troop_units WHERE id = ?", [unit_id]):
			continue
		if CampaignRepository.db.query_result.is_empty():
			continue
		total += float(CampaignRepository.db.query_result[0].get("battle_rating", 0.0))
	return total


static func _get_hex_terrain(army: Dictionary, hex_q: int, hex_r: int) -> String:
	## Phase 9C polish round 5 2026-05-09: refactored to use HexTerrainQuery.
	## Pre-refactor this queried `hex_cells.terrain_key` — a column that does
	## not exist in the schema; the SQL silently failed and every NPC-vs-NPC
	## collision battle defaulted to "clear_or_grass" terrain regardless of
	## actual hex biome. Post-refactor, extracts map_id from the army (was
	## the underscore-prefixed unused arg pre-refactor) and queries the real
	## biome/elevation/civilization/has_city columns. Default fallback
	## "clear_or_grass" preserved for callers/UI that may have read the
	## legacy string value. Note `armies.map_id` is nullable per migration
	## 070 ("NULL while assembling, populated on activate") — handle null
	## defensively to avoid `String(null)` SCRIPT ERRORs.
	var map_id_v: Variant = army.get("map_id")
	var map_id: String = "" if map_id_v == null else String(map_id_v)
	return HexTerrainQuery.query_terrain_key_for_hex(map_id, hex_q, hex_r, "clear_or_grass")
