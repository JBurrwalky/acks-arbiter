class_name WildernessHandlers
extends RefCounted

## Event handlers for wilderness (hex map) exploration.
##
## Registered by WildernessExploreState.enter() with the EventHandlerRegistry.
## Each handler receives a ScheduledEvent and returns a result Dictionary
## per the EventHandlerRegistry contract.
##
## Event types handled:
##   "travel_leg"              — party crosses one hex boundary
##   "wilderness_encounter_check" — random encounter roll for a hex
##   "getting_lost_check"      — daily navigation check
##   "forced_march_check"      — daily forced march endurance check


# ---------------------------------------------------------------------------
# Dependencies (injected on construction)
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner (untyped to avoid circular ref)


func _init(runner) -> void:
	_runner = runner


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

## Register all wilderness event handlers with the registry.
func register(registry: EventHandlerRegistry) -> void:
	registry.register("travel_leg", _handle_travel_leg)
	registry.register("wilderness_encounter_check", _handle_encounter_check)
	registry.register("getting_lost_check", _handle_getting_lost_check)
	registry.register("forced_march_check", _handle_forced_march_check)


## Unregister all wilderness event handlers.
func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("travel_leg")
	registry.unregister("wilderness_encounter_check")
	registry.unregister("getting_lost_check")
	registry.unregister("forced_march_check")


# ---------------------------------------------------------------------------
# Scheduling helpers (called by WildernessExploreState)
# ---------------------------------------------------------------------------

## Schedule a multi-hex travel path. Returns the event IDs of all travel_leg events.
## [param path] is an Array[Vector2i] of hex coordinates (excluding current hex).
## [param scheduler] is the EventScheduler to insert into.
## [param party] is the PartyData (for speed calculation).
## [param map_data] is the HexMapData (for terrain lookup).
func schedule_travel_path(
	path: Array,
	scheduler: EventScheduler,
	party: PartyData,
	map_data: HexMapData,
) -> Array[String]:
	if path.is_empty() or party == null:
		return []

	var party_id: String = party.id
	var current_time: int = Timekeeping.get_party_time(party_id)
	var event_ids: Array[String] = []

	for i in range(path.size()):
		var coord: Vector2i = path[i]
		var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null
		var terrain_cat: String = terrain.movement_cost_category() if terrain != null else "clear"
		var on_road: bool = terrain.has_road() if terrain != null else false

		var rounds: int = TravelSpeedCalculator.hex_crossing_rounds(party, terrain_cat, on_road)
		current_time += rounds

		var data := {
			"hex_q": coord.x,
			"hex_r": coord.y,
			"terrain_category": terrain_cat,
			"path_index": i,
			"path_total": path.size(),
		}

		var event_id := scheduler.schedule_at(
			current_time,
			"travel_leg",
			party_id,
			data,
			ScheduledEvent.PRIORITY_ARRIVAL,
		)
		event_ids.append(event_id)

		EventBus.order_queued.emit(party_id, "travel_leg", current_time)

	return event_ids


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Party crosses one hex boundary. Move party on map, check encounter.
func _handle_travel_leg(event: ScheduledEvent) -> Dictionary:
	var coord := Vector2i(int(event.data.get("hex_q", 0)), int(event.data.get("hex_r", 0)))
	var controller: HexMapController = _runner.get_hex_map_controller()
	var party_data: PartyData = _runner.get_party_data()

	# Move the party
	if controller.can_move_to(coord):
		controller.move_party(coord)
	else:
		# Path is blocked (e.g., fog of war changed). Cancel remaining legs.
		_runner.get_scheduler().cancel_all_for_owner(event.owner_id, "travel_leg")
		return {"auto_pause": true, "pause_reason": "Path blocked at %s" % str(coord)}

	# Update party data position
	if party_data != null:
		party_data.current_hex_q = coord.x
		party_data.current_hex_r = coord.y

	# Save map state
	var map_data: HexMapData = controller.get_map()
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, _runner.get_campaign_id())

	# Encounter check
	var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null
	if terrain != null:
		var encounter: Dictionary = _runner.do_encounter_check(terrain)
		if encounter.get("triggered", false):
			# Cancel remaining travel legs — combat interrupts the journey
			_runner.get_scheduler().cancel_all_for_owner(event.owner_id, "travel_leg")
			EventBus.order_cancelled.emit(event.owner_id, "travel_leg")

			var enc: Dictionary = encounter["encounter_data"]
			return {
				"enter_combat": true,
				"encounter_data": {
					"encounter_data": enc,
					"return_state": "wilderness",
				},
				"auto_pause": true,
				"pause_reason": "Encounter: %d x %s" % [
					enc.get("number", 0), enc.get("monster_group", "unknown")],
			}

	# Notify hex entry
	EventBus.hex_entered.emit("%d,%d" % [coord.x, coord.y])

	# Check if this is the last leg — auto-pause on arrival at destination
	var path_index: int = event.data.get("path_index", 0)
	var path_total: int = event.data.get("path_total", 1)
	if path_index == path_total - 1:
		return {
			"auto_pause": true,
			"pause_reason": "Arrived at destination",
			"presentation": {"type": "arrival", "hex": str(coord)},
		}

	return {}


## Random encounter check (can be scheduled independently from travel).
func _handle_encounter_check(event: ScheduledEvent) -> Dictionary:
	var map_data: HexMapData = _runner.get_hex_map_controller().get_map()
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null or map_data == null:
		return {}

	var coord := Vector2i(party_data.current_hex_q, party_data.current_hex_r)
	var terrain: HexTerrainData = map_data.get_hex(coord)
	if terrain == null:
		return {}

	var encounter: Dictionary = _runner.do_encounter_check(terrain)
	if encounter.get("triggered", false):
		var enc: Dictionary = encounter["encounter_data"]
		return {
			"enter_combat": true,
			"encounter_data": {
				"encounter_data": enc,
				"return_state": "wilderness",
			},
			"auto_pause": true,
			"pause_reason": "Encounter: %d x %s" % [
				enc.get("number", 0), enc.get("monster_group", "unknown")],
		}

	return {}


## Daily getting-lost check during multi-day travel.
func _handle_getting_lost_check(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return {}

	var terrain_cat: String = event.data.get("terrain_category", "clear")
	var on_road: bool = event.data.get("on_road", false)

	# Roll 1d20 for navigation
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "getting_lost")
	var result: Dictionary = TravelSpeedCalculator.check_getting_lost(
		party_data, terrain_cat, roll.modified_total, on_road)

	EventBus.getting_lost_checked.emit(result)

	if not result.get("succeeded", true):
		# Party got lost — cancel remaining travel_leg events.
		# The player must reissue orders.
		_runner.get_scheduler().cancel_all_for_owner(event.owner_id, "travel_leg")
		EventBus.order_cancelled.emit(event.owner_id, "travel_leg")
		party_data.is_lost = true

		return {
			"auto_pause": true,
			"pause_reason": "Party is lost!",
			"presentation": {"type": "getting_lost", "result": result},
		}

	return {}


## Daily forced march endurance check.
func _handle_forced_march_check(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _runner.get_party_data()
	if party_data == null:
		return {}

	var eligibility: Dictionary = TravelSpeedCalculator.check_force_march_eligibility(party_data)
	if not eligibility.get("can_continue", false):
		# Party cannot force march — cancel remaining travel legs beyond
		# the normal travel day.
		_runner.get_scheduler().cancel_all_for_owner(event.owner_id, "travel_leg")
		EventBus.order_cancelled.emit(event.owner_id, "travel_leg")
		return {
			"auto_pause": true,
			"pause_reason": "Party must rest — forced march limit reached",
			"presentation": {"type": "forced_march_exhausted", "result": eligibility},
		}

	# Roll forced march CON checks for each party member
	party_data.force_march_days_used += 1
	var failures: Array = []
	for cd: CharacterData in party_data.character_data:
		var throw_target: int = cd.get_effective_save("save_petrification")  # CON-based save
		var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "forced_march")
		var succeeded: bool = roll.modified_total >= throw_target
		var fm_result := {
			"character_id": cd.id,
			"roll": roll.modified_total,
			"succeeded": succeeded,
		}
		EventBus.forced_march_checked.emit(fm_result)
		if not succeeded:
			failures.append(fm_result)

	if not failures.is_empty():
		return {
			"auto_pause": true,
			"pause_reason": "%d party member(s) failed forced march check" % failures.size(),
			"presentation": {"type": "forced_march_failure", "failures": failures},
		}

	return {}
