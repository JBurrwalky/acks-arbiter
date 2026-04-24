class_name WildernessHandlers
extends RefCounted

## Event handlers for wilderness (hex map) exploration.
##
## Registered by WildernessExploreState.enter() with the EventHandlerRegistry.
## Each handler receives a ScheduledEvent and returns a result Dictionary
## per the EventHandlerRegistry contract.
##
## Event types handled:
##   "travel_leg"                    — party crosses one hex boundary
##   "wilderness_encounter_check"    — random encounter roll for a hex
##   "getting_lost_check"            — daily navigation check
##   "forced_march_check"            — daily forced march endurance check
##   "wilderness_activity"           — a hex-level activity begins on arrival
##   "wilderness_activity_complete"  — a timed wilderness activity resolves

const ACTIVITY_EVENT := "wilderness_activity"
const ACTIVITY_COMPLETE_EVENT := "wilderness_activity_complete"


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
	registry.register(ACTIVITY_EVENT, _handle_wilderness_activity)
	registry.register(ACTIVITY_COMPLETE_EVENT, _handle_wilderness_activity_complete)


## Unregister all wilderness event handlers.
func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("travel_leg")
	registry.unregister("wilderness_encounter_check")
	registry.unregister("getting_lost_check")
	registry.unregister("forced_march_check")
	registry.unregister(ACTIVITY_EVENT)
	registry.unregister(ACTIVITY_COMPLETE_EVENT)


# ---------------------------------------------------------------------------
# Scheduling helpers (called by WildernessExploreState)
# ---------------------------------------------------------------------------

## Schedule a multi-hex travel path.
## [param path] is an Array[Vector2i] of hex coordinates (excluding current hex).
## An empty path is valid — it represents an in-place activity (target equals
## current hex). The result still has an `arrival_time` (= current game time)
## so callers that chain follow-up events on arrival work uniformly.
## [param scheduler] is the EventScheduler to insert into.
## [param party] is the PartyData (for speed calculation).
## [param map_data] is the HexMapData (for terrain lookup).
## Returns a Dictionary:
##   "event_ids":    Array[String] — one travel_leg id per leg (empty for in-place)
##   "arrival_time": int           — game-round clock after the final leg fires
##                                   (== current_time when path is empty)
##   "current_time": int           — game-round clock before any leg fires
func schedule_travel_path(
	path: Array,
	scheduler: EventScheduler,
	party: PartyData,
	map_data: HexMapData,
) -> Dictionary:
	if party == null:
		return {"event_ids": [] as Array[String], "arrival_time": 0, "current_time": 0}

	# Same-hex (in-place activity): no legs to schedule, but the activity will
	# fire "now" — return current_time as arrival_time so the caller's
	# schedule_at(arrival_time, ...) lands at the next scheduler tick.
	if path.is_empty():
		var now: int = Timekeeping.get_party_time(party.id)
		return {
			"event_ids": [] as Array[String],
			"arrival_time": now,
			"current_time": now,
		}

	var party_id: String = party.id
	var start_time: int = Timekeeping.get_party_time(party_id)
	var current_time: int = start_time
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

	return {
		"event_ids": event_ids,
		"arrival_time": current_time,
		"current_time": start_time,
	}


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Party crosses one hex boundary. Moves the EVENT'S party (not necessarily
## the runner's primary party) on the map, persists the new position, reveals
## fog around the destination, and runs an encounter check.
##
## Multi-party correctness: the controller's `move_party` / `can_move_to` /
## `_map_data.party_hex` all model the *primary* party's position only. For
## non-primary parties we update the DB directly, reveal fog non-destructively
## via `controller.reveal_around`, and emit `EventBus.party_hex_changed` so the
## renderer rebuilds that party's token.
func _handle_travel_leg(event: ScheduledEvent) -> Dictionary:
	var coord := Vector2i(int(event.data.get("hex_q", 0)), int(event.data.get("hex_r", 0)))
	var controller: HexMapController = _runner.get_hex_map_controller()
	var moving_pid: String = event.owner_id
	var primary_pid: String = _runner.get_party_id()
	var is_primary: bool = (not moving_pid.is_empty() and moving_pid == primary_pid)
	var is_active: bool = (moving_pid == GameState.active_party_id)

	# Validate target passability. We can NOT use `controller.can_move_to`
	# here — that checks adjacency from the controller's stored primary-party
	# hex, which is wrong for non-primary parties (and for primary parties is
	# redundant since the path was validated when scheduling).
	if not controller.is_hex_passable(coord):
		# Path is blocked (e.g., terrain changed). Cancel remaining legs and
		# any queued follow-up activity at the destination.
		_cancel_party_movement_and_activity(moving_pid)
		return {
			"auto_pause": is_active,
			"pause_reason": "Path blocked at %s" % str(coord),
		}

	# Resolve the moving party's data (primary uses the runner cache; non-
	# primary loads fresh from the DB so we don't mutate the wrong party).
	var party_data: PartyData = _party_data_for_event(event)

	# Move the party. Primary uses controller.move_party so fog of war updates
	# via _update_visibility (demote-and-reveal). Non-primary updates DB
	# directly and reveals fog non-destructively so the active party's
	# vicinity isn't accidentally demoted to EXPLORED.
	if is_primary:
		# move_party also calls _update_visibility(coord) and emits party_moved.
		controller.move_party(coord)
	else:
		controller.reveal_around(coord)
	if party_data != null:
		party_data.current_hex_q = coord.x
		party_data.current_hex_r = coord.y

	# Persist the moving party's position to the DB.
	var map_data: HexMapData = controller.get_map()
	if not moving_pid.is_empty():
		var map_id: String = map_data.id if map_data != null else ""
		CampaignRepository.update_party_position(moving_pid, map_id, coord.x, coord.y)

	# Notify the renderer so this party's token re-anchors. The controller's
	# `party_moved` only fires for the primary party; non-primary updates
	# need this signal.
	EventBus.party_hex_changed.emit(moving_pid, coord)

	# Save map state (fog updates).
	if map_data != null:
		CampaignRepository.save_hex_map(map_data, _runner.get_campaign_id())

	# Encounter check (per moving party). `do_encounter_check` doesn't depend
	# on which party for its core logic — only the hex_id annotation reads
	# the runner's primary party. The encounter still resolves correctly for
	# any moving party; the slight hex_id annotation drift for non-primary
	# encounters is a follow-up.
	var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null
	if terrain != null:
		var encounter: Dictionary = _runner.do_encounter_check(terrain)
		if encounter.get("triggered", false):
			# Cancel remaining travel legs AND any queued follow-up activity
			# for the AMBUSHED party only. Other parties' orders are
			# untouched.
			_cancel_party_movement_and_activity(moving_pid)
			EventBus.order_cancelled.emit(moving_pid, "travel_leg")

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

	# Notify hex entry and sync location key (consumed by inventory overlay
	# cache-lookup, among others). Only update if this travel leg belongs to
	# the currently active party — otherwise another party's motion would
	# invalidate the active party's location context.
	EventBus.hex_entered.emit("%d,%d" % [coord.x, coord.y])
	if is_active:
		GameState.current_location_key = "hex:%d,%d" % [coord.x, coord.y]

	# Check if this is the last leg — auto-pause on arrival at destination
	# only when the arriving party is the one the player is watching.
	var path_index: int = event.data.get("path_index", 0)
	var path_total: int = event.data.get("path_total", 1)
	if path_index == path_total - 1:
		return {
			"auto_pause": is_active,
			"pause_reason": "Arrived at destination",
			"presentation": {"type": "arrival", "hex": str(coord)},
		}

	return {}


## Random encounter check (can be scheduled independently from travel).
## Uses the EVENT'S party (event.owner_id), not the runner's primary, so a
## standalone encounter check fires against the right party in multi-party
## sessions.
func _handle_encounter_check(event: ScheduledEvent) -> Dictionary:
	var map_data: HexMapData = _runner.get_hex_map_controller().get_map()
	var party_data: PartyData = _party_data_for_event(event)
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
## Uses the EVENT'S party so non-primary parties traveling in the background
## also roll their own getting-lost checks.
func _handle_getting_lost_check(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null:
		return {}
	var moving_pid: String = event.owner_id
	var is_primary: bool = (not moving_pid.is_empty() and moving_pid == _runner.get_party_id())

	var terrain_cat: String = event.data.get("terrain_category", "clear")
	var on_road: bool = event.data.get("on_road", false)

	# Roll 1d20 for navigation
	var roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "getting_lost")
	var result: Dictionary = TravelSpeedCalculator.check_getting_lost(
		party_data, terrain_cat, roll.modified_total, on_road)

	EventBus.getting_lost_checked.emit(result)

	if not result.get("succeeded", true):
		# Party got lost — cancel remaining travel_leg events AND any queued
		# follow-up activity (lost parties shouldn't auto-start a task at the
		# wrong hex). The player must reissue orders.
		_cancel_party_movement_and_activity(moving_pid)
		EventBus.order_cancelled.emit(moving_pid, "travel_leg")
		party_data.is_lost = true
		# Non-primary PartyData is loaded fresh per event — must be saved
		# back to the DB or the `is_lost` mutation is lost on next reload.
		if not is_primary:
			CampaignRepository.save_party_state(party_data.to_state_dict())

		return {
			"auto_pause": (moving_pid == GameState.active_party_id),
			"pause_reason": "Party is lost!",
			"presentation": {"type": "getting_lost", "result": result},
		}

	return {}


## Daily forced march endurance check. Operates on the EVENT'S party.
func _handle_forced_march_check(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null:
		return {}
	var moving_pid: String = event.owner_id
	var is_primary: bool = (not moving_pid.is_empty() and moving_pid == _runner.get_party_id())

	var eligibility: Dictionary = TravelSpeedCalculator.check_force_march_eligibility(party_data)
	if not eligibility.get("can_continue", false):
		# Party cannot force march — cancel remaining travel legs beyond the
		# normal travel day and any queued follow-up activity.
		_cancel_party_movement_and_activity(moving_pid)
		EventBus.order_cancelled.emit(moving_pid, "travel_leg")
		return {
			"auto_pause": (moving_pid == GameState.active_party_id),
			"pause_reason": "Party must rest — forced march limit reached",
			"presentation": {"type": "forced_march_exhausted", "result": eligibility},
		}

	# Roll forced march CON checks for each party member
	party_data.force_march_days_used += 1
	# Persist non-primary mutations.
	if not is_primary:
		CampaignRepository.save_party_state(party_data.to_state_dict())
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


## Party arrived at the destination and the queued activity begins.
## For instant activities (visit cache, placeholder toasts) this resolves in
## one fire. For timed activities (place cache) it schedules a follow-up
## completion event.
func _handle_wilderness_activity(event: ScheduledEvent) -> Dictionary:
	var activity_type: String = str(event.data.get("activity_type", ""))
	var hex_q: int = int(event.data.get("hex_q", 0))
	var hex_r: int = int(event.data.get("hex_r", 0))
	var party_id: String = event.owner_id

	match activity_type:
		"place_loot_cache":
			EventBus.notification_requested.emit({
				"type": "info",
				"category": "exploration",
				"title": "Placing Cache",
				"body": "Your party is hiding a cache here (1 hour).",
				"duration": 3.0,
			})
			var completion_data := event.data.duplicate()
			var fire_time: int = Timekeeping.get_party_time(party_id) + Timekeeping.ROUNDS_PER_HOUR
			EventBus.order_queued.emit(party_id, ACTIVITY_COMPLETE_EVENT, fire_time)
			return {
				"next_events": [{
					"event_type": ACTIVITY_COMPLETE_EVENT,
					"fire_time": fire_time,
					"owner_id": party_id,
					"data": completion_data,
					"priority": ScheduledEvent.PRIORITY_ARRIVAL,
				}]
			}
		"visit_loot_cache":
			var location_key := "hex:%d,%d" % [hex_q, hex_r]
			var cache: Dictionary = LocationCacheManager.get_cache_at_location(location_key)
			if cache.is_empty():
				EventBus.notification_requested.emit({
					"type": "info",
					"category": "exploration",
					"title": "No Cache Here",
					"body": "There is no cache at this hex.",
					"duration": 3.0,
				})
			else:
				var cache_id: String = str(cache.get("id", ""))
				EventBus.wilderness_cache_visit_requested.emit(cache_id, Vector2i(hex_q, hex_r))
			return {
				"auto_pause": true,
				"pause_reason": "Arrived at cache",
			}
		"explore", "build_stronghold", "survey":
			var label := _activity_label(activity_type)
			EventBus.notification_requested.emit({
				"type": "info",
				"category": "exploration",
				"title": "Feature coming soon",
				"body": "%s is not yet implemented." % label,
				"duration": 4.0,
			})
			return {
				"auto_pause": true,
				"pause_reason": "Arrived at destination",
			}
		_:
			push_warning("WildernessHandlers: unknown activity_type '%s'" % activity_type)
			return {
				"auto_pause": true,
				"pause_reason": "Arrived at destination",
			}


## Timed wilderness activity resolves. Today this only handles place_loot_cache;
## other activity types drop here only if more timed activities are added later.
func _handle_wilderness_activity_complete(event: ScheduledEvent) -> Dictionary:
	var activity_type: String = str(event.data.get("activity_type", ""))
	var hex_q: int = int(event.data.get("hex_q", 0))
	var hex_r: int = int(event.data.get("hex_r", 0))

	match activity_type:
		"place_loot_cache":
			var cache_id: String = LocationCacheManager.create_wilderness_hidden_cache(
				Vector2i(hex_q, hex_r))
			if cache_id.is_empty():
				EventBus.notification_requested.emit({
					"type": "warning",
					"category": "exploration",
					"title": "Cache Failed",
					"body": "Could not place a cache at this hex.",
					"duration": 4.0,
				})
				return {"auto_pause": true, "pause_reason": "Cache placement failed"}
			EventBus.notification_requested.emit({
				"type": "success",
				"category": "exploration",
				"title": "Cache Hidden",
				"body": "Open Party Inventory to fill this cache.",
				"duration": 4.0,
			})
			return {"auto_pause": true, "pause_reason": "Cache placed"}
		_:
			push_warning("WildernessHandlers: no completion for activity_type '%s'" % activity_type)
			return {"auto_pause": true, "pause_reason": "Activity complete"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Resolves the moving party's PartyData. For events owned by the runner's
## primary party we reuse the runner's cached object (so in-memory mutations
## like `is_lost` persist within the session); for non-primary parties we
## load fresh from the repository AND populate `character_data` (which
## `load_party_data` leaves empty), so handlers that iterate members
## (forced march CON checks, etc.) work uniformly across parties.
##
## Mutations on freshly-loaded non-primary PartyData must be re-saved
## explicitly by the caller — this helper does NOT save.
func _party_data_for_event(event: ScheduledEvent) -> PartyData:
	if _runner == null:
		return null
	var pid: String = event.owner_id
	if pid.is_empty():
		return null
	if pid == _runner.get_party_id():
		return _runner.get_party_data()
	var party_data: PartyData = CampaignRepository.load_party_data(pid)
	if party_data == null:
		return null
	party_data.character_data = []
	for char_row: Dictionary in CampaignRepository.list_party_characters(pid):
		party_data.character_data.append(CharacterData.from_dict(char_row))
	return party_data


## Cancels a party's pending travel legs AND any queued follow-up activity.
## Used by encounter triggers and blocked-path branches so that an interrupted
## journey does not silently resume the queued task after combat or detour.
func _cancel_party_movement_and_activity(party_id: String) -> void:
	if _runner == null:
		return
	var scheduler: EventScheduler = _runner.get_scheduler()
	if scheduler == null:
		return
	scheduler.cancel_all_for_owner(party_id, "travel_leg")
	scheduler.cancel_all_for_owner(party_id, ACTIVITY_EVENT)
	scheduler.cancel_all_for_owner(party_id, ACTIVITY_COMPLETE_EVENT)


func _activity_label(activity_type: String) -> String:
	match activity_type:
		"explore":          return "Explore"
		"build_stronghold": return "Build Stronghold"
		"survey":           return "Survey"
		"place_loot_cache": return "Place Loot Cache"
		"visit_loot_cache": return "Visit Loot Cache"
		_:                   return activity_type.capitalize()
