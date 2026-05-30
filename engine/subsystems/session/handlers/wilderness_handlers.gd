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
##   "wilderness_day_tick"           — per-party midnight rollover (sustenance,
##                                     weather hook in P2, exhaustion in P3)

const ACTIVITY_EVENT := "wilderness_activity"
const ACTIVITY_COMPLETE_EVENT := "wilderness_activity_complete"
const DAY_TICK_EVENT := "wilderness_day_tick"
const NOON_TICK_EVENT := "wilderness_noon_tick"
const TRACKING_CHECK_EVENT := "tracking_check"
const PURSUIT_CATCHUP_EVENT := "pursuit_catchup_check"
## Deferred camp encounter resolution (gdd-realtime-scheduler.md §4.3.1). The
## 1-in-6 throw fires at camp_setup in CampHandlers; this event fires at the
## rolled hour-of-camp to spawn the creatures and compute per-member observer
## state. Registered globally so it survives camp → wilderness/combat
## transitions (though §4.3.1's cancel-on-camp-end rule normally cleans it up
## first).
const WILDERNESS_ENCOUNTER_EVENT := "wilderness_encounter"

## In-memory buffer keyed by party_id → most-recent foraging summary. Filled
## by the noon-tick handler and consumed by the midnight day-tick when
## writing the sustenance log row. Not persisted; on session reload the
## first noon tick repopulates it before midnight evaluates sustenance.
var _latest_forage_summary_by_party: Dictionary = {}


# ---------------------------------------------------------------------------
# Dependencies (injected on construction)
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner (untyped to avoid circular ref)


func _init(runner) -> void:
	_runner = runner


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

## Register all wilderness event handlers with the registry. Convenience that
## calls both `register_state_scoped` and `register_global`. Mostly used by
## tests; production splits the two lifetimes (see `register_global`).
func register(registry: EventHandlerRegistry) -> void:
	register_state_scoped(registry)
	register_global(registry)


## Unregister all wilderness event handlers. Mirrors `register`.
func unregister(registry: EventHandlerRegistry) -> void:
	unregister_state_scoped(registry)
	unregister_global(registry)


## Register the state-scoped subset — events that only make sense while the
## party is in WildernessExploreState (travel, encounters, activities). The
## state's enter/exit owns this lifetime.
func register_state_scoped(registry: EventHandlerRegistry) -> void:
	registry.register("travel_leg", _handle_travel_leg)
	registry.register("wilderness_encounter_check", _handle_encounter_check)
	registry.register("getting_lost_check", _handle_getting_lost_check)
	registry.register("forced_march_check", _handle_forced_march_check)
	registry.register(ACTIVITY_EVENT, _handle_wilderness_activity)
	registry.register(ACTIVITY_COMPLETE_EVENT, _handle_wilderness_activity_complete)


func unregister_state_scoped(registry: EventHandlerRegistry) -> void:
	registry.unregister("travel_leg")
	registry.unregister("wilderness_encounter_check")
	registry.unregister("getting_lost_check")
	registry.unregister("forced_march_check")
	registry.unregister(ACTIVITY_EVENT)
	registry.unregister(ACTIVITY_COMPLETE_EVENT)


## Register the global subset — events that must keep firing across state
## transitions (day-tick housekeeping for sustenance/weather rollover, and
## Phase 5 daily tracking + pursuit checks). Owned by SessionRunner.load_session,
## like DomainHandlers, so a party that camps or enters a dungeon mid-day
## still ticks at midnight.
func register_global(registry: EventHandlerRegistry) -> void:
	registry.register(DAY_TICK_EVENT, _handle_wilderness_day_tick)
	registry.register(NOON_TICK_EVENT, _handle_wilderness_noon_tick)
	registry.register(TRACKING_CHECK_EVENT, _handle_tracking_check)
	registry.register(PURSUIT_CATCHUP_EVENT, _handle_pursuit_catchup_check)
	registry.register(WILDERNESS_ENCOUNTER_EVENT, _handle_wilderness_encounter)


func unregister_global(registry: EventHandlerRegistry) -> void:
	registry.unregister(DAY_TICK_EVENT)
	registry.unregister(NOON_TICK_EVENT)
	registry.unregister(TRACKING_CHECK_EVENT)
	registry.unregister(PURSUIT_CATCHUP_EVENT)
	registry.unregister(WILDERNESS_ENCOUNTER_EVENT)


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

		# Phase 2: pull weather for each leg so DaW speed multipliers compose
		# with terrain. Legs scheduled now use the day they're entered on
		# (party_time + accumulated leg duration → julian_day).
		var weather: WeatherStateData = _weather_for_hex(terrain, coord, current_time)
		var rounds: int = TravelSpeedCalculator.hex_crossing_rounds(
			party, terrain_cat, on_road, weather)
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


## Schedule the next wilderness_day_tick for [param party_id], if one is not
## already pending. Idempotent against the scheduler queue: re-entering the
## wilderness state does not double-schedule.
##
## Fire time is the next midnight on the party's clock
## (party_time + (ROUNDS_PER_DAY - party_time % ROUNDS_PER_DAY)). When a party
## is sitting exactly at midnight this gives the *next* midnight (24h out)
## rather than 0 rounds away, which is the intended semantics — the day tick
## represents the rollover *into* the upcoming day.
##
## Returns the event_id when a tick was scheduled, or "" when one was already
## pending (no-op).
func schedule_day_tick(scheduler: EventScheduler, party_id: String) -> String:
	if scheduler == null or party_id.is_empty():
		return ""
	for event: ScheduledEvent in scheduler.get_events_for_owner(party_id):
		if event.event_type == DAY_TICK_EVENT:
			return ""
	var party_time: int = Timekeeping.get_party_time(party_id)
	var rounds_into_day: int = party_time % Timekeeping.ROUNDS_PER_DAY
	var rounds_to_midnight: int = Timekeeping.ROUNDS_PER_DAY - rounds_into_day
	var fire_time: int = party_time + rounds_to_midnight
	return scheduler.schedule_at(
		fire_time,
		DAY_TICK_EVENT,
		party_id,
		{},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	)


## Phase 5 polish (2026-05-05): schedule the next `wilderness_noon_tick` for
## [param party_id]. Idempotent — no-op when one is already pending.
## Foraging runs at noon (so food found earlier offsets the day's
## consumption evaluated at midnight).
func schedule_noon_tick(scheduler: EventScheduler, party_id: String) -> String:
	if scheduler == null or party_id.is_empty():
		return ""
	for event: ScheduledEvent in scheduler.get_events_for_owner(party_id):
		if event.event_type == NOON_TICK_EVENT:
			return ""
	var party_time: int = Timekeeping.get_party_time(party_id)
	var rounds_into_day: int = party_time % Timekeeping.ROUNDS_PER_DAY
	@warning_ignore("integer_division")
	var noon_round: int = Timekeeping.ROUNDS_PER_DAY / 2
	var rounds_to_noon: int
	if rounds_into_day < noon_round:
		rounds_to_noon = noon_round - rounds_into_day
	else:
		# Already past noon today — schedule tomorrow's noon.
		rounds_to_noon = (Timekeeping.ROUNDS_PER_DAY - rounds_into_day) + noon_round
	var fire_time: int = party_time + rounds_to_noon
	return scheduler.schedule_at(
		fire_time,
		NOON_TICK_EVENT,
		party_id,
		{},
		ScheduledEvent.PRIORITY_ENVIRONMENTAL,
	)


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

	# Phase 4: passive lair-spot check. Fires before the encounter check so
	# that even an interrupted travel leg leaves the player with the lair
	# discovery (a soft notification — does not halt travel by itself).
	var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null
	if terrain != null:
		_passive_lair_check(party_data, coord, terrain)
		# Phase 5 polish (2026-05-05): water refill on free-flowing or
		# standing water hexes. Settlement hexes are treated as having a
		# water source per design (see _refill_water_at_hex). Mirrors the
		# foraging auto-pass cap of party_size (one day's draw).
		_refill_water_at_hex(party_data, terrain)

	# Encounter check (per moving party). `do_encounter_check` doesn't depend
	# on which party for its core logic — only the hex_id annotation reads
	# the runner's primary party. The encounter still resolves correctly for
	# any moving party; the slight hex_id annotation drift for non-primary
	# encounters is a follow-up.
	if terrain != null:
		var encounter: Dictionary = _runner.do_encounter_check(terrain)
		if encounter.get("triggered", false):
			var enc: Dictionary = encounter["encounter_data"]
			# Phase 2: stamp encounter context with weather visibility so
			# CombatState shrinks the spawn distance when fog/rain/snow are
			# active. acore_adventures_and_encounters.xml §encounter_distance
			# + DaW §severe_weather_effects (reconnaissance penalties).
			var weather: WeatherStateData = _weather_for_hex(
				terrain, coord, Timekeeping.get_party_time(moving_pid))
			if weather != null:
				enc["visibility_multiplier"] = weather.encounter_visibility_multiplier()

			# Hybrid encounter-gate stamp (gdd-realtime-scheduler.md §4.3.3):
			# any wilderness encounter trigger marks today's day_index, which
			# gates subsequent same-day camp throws.
			_stamp_encounter_gate(party_data, Timekeeping.get_party_time(moving_pid))

			# Phase 5 polish (2026-05-05): every encounter halts travel and
			# surfaces an EncounterDecisionPrompt — the player picks how to
			# respond (fight, evade, engage, parley, continue). The reaction
			# router still tags the disposition for the modal's button matrix
			# and flavor text, but the routing decision has moved up to the
			# state-level UI listener (WildernessExploreState).
			_cancel_party_movement_and_activity(moving_pid)
			EventBus.order_cancelled.emit(moving_pid, "travel_leg")
			var enc_label: String = _format_encounter_label(enc)
			EventBus.encounter_decision_required.emit(moving_pid, enc)
			return {
				"auto_pause": true,
				"pause_reason": "Encounter — %s" % enc_label,
				"presentation": {
					"type": "encounter_decision",
					"encounter_data": enc,
				},
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
		# Phase 2: same visibility stamp as the travel-leg path.
		var weather: WeatherStateData = _weather_for_hex(
			terrain, coord, Timekeeping.get_party_time(event.owner_id))
		if weather != null:
			enc["visibility_multiplier"] = weather.encounter_visibility_multiplier()

		# Hybrid encounter-gate stamp (§4.3.3).
		_stamp_encounter_gate(party_data, Timekeeping.get_party_time(event.owner_id))

		# Phase 5 polish (2026-05-05): standalone encounter checks also route
		# through the EncounterDecisionPrompt — same flow as travel-leg
		# encounters. The state-level listener interprets the choice.
		var enc_label: String = _format_encounter_label(enc)
		EventBus.encounter_decision_required.emit(event.owner_id, enc)
		return {
			"auto_pause": true,
			"pause_reason": "Encounter — %s" % enc_label,
			"presentation": {
				"type": "encounter_decision",
				"encounter_data": enc,
			},
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
		"explore", "build_stronghold":
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
		"hunt":
			# Phase 3: full-day hunt activity per
			# acore_adventures_and_encounters.xml §rations_and_foraging.hunting.
			# 14+ on 1d20 (+4 Survival), success = 2d6 person-feeds, with one
			# wandering monster check during the day. Travel halts for the day.
			return _resolve_hunt_activity(party_id, hex_q, hex_r)
		"survey":
			# Phase 4: Land Surveying assessment per
			# le_wilderness_lair_rules.xml §land_surveying.
			return _resolve_survey_activity(party_id, hex_q, hex_r)
		"search_lair":
			# Phase 4: dedicated full-day lair search per
			# le_wilderness_lair_rules.xml §searching_for_lairs.
			return _resolve_lair_search_activity(party_id, hex_q, hex_r)
		_:
			push_warning("WildernessHandlers: unknown activity_type '%s'" % activity_type)
			return {
				"auto_pause": true,
				"pause_reason": "Arrived at destination",
			}


## Per-party midnight rollover (PRIORITY_ENVIRONMENTAL = 0, fires before
## scheduled-check tier and arrival tier on tied rounds). Phase 1 establishes
## the contract and idempotency guard; Phase 2 hooks weather rollover here,
## Phase 3 hooks SustenanceResolver.apply_daily and decrements ration/water
## counters. Self-reschedules +24hr via the next_events return contract so the
## tick survives a single missed dispatch (e.g., scheduler paused over a
## midnight boundary — the next dispatch resumes from the queued event).
##
## Idempotency: refuses to double-fire on the same fire_time round
## (last_day_tick_round persists across save/load). A re-entry into wilderness
## state that finds a pending tick in the queue is also a no-op via
## schedule_day_tick.
func _handle_wilderness_day_tick(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null:
		return {}

	# Idempotency: skip if this round's tick has already been stamped.
	if party_data.last_day_tick_round == event.fire_time:
		return {}

	var moving_pid: String = event.owner_id
	var old_exhaustion: int = party_data.exhaustion_days

	# Phase 1 stamp + Phase 2 weather rollover + Phase 3 sustenance:
	# acore_adventures_and_encounters.xml §rations_and_foraging — 2-day food
	# grace then 1 hp/day, 1 day water then 1d4 hp + 1d4/day. Wilderness-only:
	# Phase 3 v1 skips foraging and consumption when the party is in
	# settlement/dungeon/camp (current_location_type != "wilderness").
	party_data.last_day_tick_round = event.fire_time

	var moving_pid_str: String = event.owner_id
	@warning_ignore("integer_division")
	var day_index: int = event.fire_time / Timekeeping.ROUNDS_PER_DAY

	# Phase 5 polish (2026-05-05): foraging moved to NOON_TICK_EVENT — runs
	# earlier in the day so food found offsets that day's consumption. The
	# midnight tick consumes the summary stashed by the noon handler when
	# writing the sustenance log row.
	var forage_summary: Dictionary = _latest_forage_summary_by_party.get(moving_pid_str, {})
	_latest_forage_summary_by_party.erase(moving_pid_str)
	var sustenance_summary: Dictionary = {}
	if _is_wilderness_location(party_data):
		_load_member_proficiencies(party_data)
		sustenance_summary = SustenanceResolver.apply_daily(party_data, DiceSystem)
		_apply_sustenance_hp_loss(sustenance_summary)
		_emit_sustenance_signals(moving_pid_str, sustenance_summary)
		_log_sustenance_day(
			moving_pid_str, day_index, forage_summary, sustenance_summary)

	# Always persist after a tick — last_day_tick_round is the durable
	# idempotency guard against a session reload firing the same tick twice.
	# Phase 3 mutations (ration_units, water_units, *_days) ride along.
	CampaignRepository.save_party_state(party_data.to_state_dict())

	# Phase 2: roll today's weather for the party's current hex (cached) and
	# fire weather_changed + toast on material transitions.
	_roll_and_announce_weather(party_data, event.fire_time)

	var summary := {
		"tick_round": event.fire_time,
		"day_index": day_index,
		"exhaustion_days": party_data.exhaustion_days,
		"starvation_days": party_data.starvation_days,
		"dehydration_days": party_data.dehydration_days,
		"ration_units": party_data.ration_units,
		"water_units": party_data.water_units,
		"forage": forage_summary,
		"sustenance": sustenance_summary,
	}
	EventBus.wilderness_day_ticked.emit(moving_pid, summary)

	# Emit exhaustion delta only when a Phase 3 hook above mutates it. Phase 1
	# always reports 0→0; the conditional keeps the signal noise-free.
	if old_exhaustion != party_data.exhaustion_days:
		EventBus.exhaustion_changed.emit(
			moving_pid, old_exhaustion, party_data.exhaustion_days)

	# Self-reschedule for the next midnight. Day-tick does not auto-pause;
	# it is housekeeping — the player should not be interrupted at midnight
	# unless a Phase 3 threshold crossing demands it (sustenance_threshold_crossed).
	return {
		"next_events": [{
			"fire_time": event.fire_time + Timekeeping.ROUNDS_PER_DAY,
			"event_type": DAY_TICK_EVENT,
			"owner_id": moving_pid,
			"data": {},
			"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
		}]
	}


## Phase 5 polish (2026-05-05): per-party noon tick. Runs the daily foraging
## throws BEFORE the midnight sustenance evaluation so food found offsets
## the same day's consumption. Settlement hexes also get a daily water
## top-off here (resident parties don't run out while staying in town).
##
## Mutates `party.ration_units` and `party.water_units` via ForagingResolver.
## Stashes the forage_summary in `_latest_forage_summary_by_party` for the
## midnight tick to consume in the sustenance log.
func _handle_wilderness_noon_tick(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null:
		return {}

	var moving_pid: String = event.owner_id
	var forage_summary: Dictionary = {}

	if _is_wilderness_location(party_data):
		_load_member_proficiencies(party_data)
		var terrain := _terrain_for_party(party_data)
		var weather: WeatherStateData = null
		if terrain != null:
			weather = _weather_for_hex(
				terrain,
				Vector2i(party_data.current_hex_q, party_data.current_hex_r),
				event.fire_time)
		forage_summary = ForagingResolver.attempt_daily(
			party_data, terrain, weather, DiceSystem)
		_emit_forage_signals(moving_pid, forage_summary)
		# Settlement-resident parties get a daily water top-off — treat the
		# town as a free-flowing source, food still comes from the shop UI.
		if terrain != null:
			_refill_water_at_hex(party_data, terrain)
		# Decanter of Endless Water (gdd-treasure-item-backing.md §14):
		# any party member carrying a Decanter contributes its per-tick
		# output toward the water counter, capped at party_size. Runs AFTER
		# the river-hex check so a river hex AND a Decanter together still
		# clamp at the same daily cap. The service is a no-op when no
		# Decanters are carried (carries its own internal guards).
		DecanterRefillService.refill_party_water(
			party_data, CampaignRepository, EventBus)
		# Persist counter mutations so a session reload after noon but
		# before midnight doesn't lose the foraged units.
		CampaignRepository.save_party_state(party_data.to_state_dict())

	_latest_forage_summary_by_party[moving_pid] = forage_summary

	return {
		"next_events": [{
			"fire_time": event.fire_time + Timekeeping.ROUNDS_PER_DAY,
			"event_type": NOON_TICK_EVENT,
			"owner_id": moving_pid,
			"data": {},
			"priority": ScheduledEvent.PRIORITY_ENVIRONMENTAL,
		}]
	}


## Phase 5: daily tracking-session check. Per
## acore_proficiencies_rules_and_catalog.xml Tracking entry — a single
## throw with accumulated weather decay; on failure the session closes
## "lost_trail". On success, reschedule for the next day. v1 ground/light
## inputs default to "normal" / "good"; future polish can wire terrain
## inspection.
func _handle_tracking_check(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null or _runner == null:
		return {}
	var campaign_id: String = _runner.get_campaign_id()
	if campaign_id.is_empty():
		return {}

	var session: Dictionary = CampaignRepository.get_open_tracking_session(
		campaign_id, party_data.id)
	if session.is_empty():
		# Session closed externally (combat / abandoned). Stop cascading.
		return {}

	_load_member_proficiencies(party_data)
	var tracker: CharacterData = TrackingResolver.pick_tracker(party_data)
	if tracker == null:
		# Lost the only tracker (death / dismissal). Close as abandoned.
		var sid_lost: String = str(session.get("session_id", ""))
		CampaignRepository.close_tracking_session(sid_lost, "abandoned")
		EventBus.tracking_session_ended.emit(party_data.id, {
			"session_id": sid_lost,
			"reason": "abandoned",
		})
		return {}

	# Compute weather decay for the elapsed period (last_check_round → now)
	# under the current hex's weather. v1 uses the current hex's weather as
	# a stand-in for trail-length weather.
	var last_check: int = int(session.get("last_check_round", -1))
	var now_round: int = event.fire_time
	var hours_elapsed: float = 0.0
	if last_check >= 0:
		var rounds_delta: int = max(0, now_round - last_check)
		hours_elapsed = float(rounds_delta) / float(Timekeeping.ROUNDS_PER_HOUR)
	var terrain := _terrain_for_party(party_data)
	var weather: WeatherStateData = null
	if terrain != null:
		weather = _weather_for_hex(terrain,
			Vector2i(party_data.current_hex_q, party_data.current_hex_r),
			now_round)
	var period_decay: int = TrackingResolver.compute_weather_decay(hours_elapsed, weather)
	var prev_total: float = float(session.get("weather_decay_total", 0.0))
	var new_total: float = prev_total + float(period_decay)

	var target_size: int = int(session.get("target_size", 1))
	# Phase 6: Pathfinder specialist bonus on tracking throws.
	var specialist_bonus: int = SpecialistBonusResolver.bonus_for(
		campaign_id, party_data.id, SpecialistCatalog.KIND_TRACKING)
	var result: Dictionary = TrackingResolver.attempt(
		tracker, target_size, "normal", "good", int(new_total), DiceSystem,
		specialist_bonus)

	var sid: String = str(session.get("session_id", ""))
	CampaignRepository.update_tracking_session(sid, {
		"weather_decay_total": new_total,
		"last_check_round": now_round,
	})

	if not bool(result.get("succeeded", false)):
		CampaignRepository.close_tracking_session(sid, "lost_trail")
		EventBus.tracking_session_ended.emit(party_data.id, {
			"session_id": sid,
			"reason": "lost_trail",
			"throw": result,
		})
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "exploration",
			"title": "Trail Lost",
			"body": "%s lost the trail." % tracker.name,
			"duration": 4.0,
		})
		return {}

	# Success — reschedule for the next day.
	return {
		"next_events": [{
			"fire_time": now_round + Timekeeping.ROUNDS_PER_DAY,
			"event_type": TRACKING_CHECK_EVENT,
			"owner_id": party_data.id,
			"data": {},
			"priority": ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
		}],
	}


## Phase 5: daily catch-up roll for an open pursuit. Per
## acore_adventures_and_encounters.xml §if_evasion_fails — 50% (11+) catch-up
## when pursuer is faster; on miss the fleeing side may attempt evasion
## again; on hit, the pursuit closes and a hostile encounter fires.
func _handle_pursuit_catchup_check(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null or _runner == null:
		return {}
	var campaign_id: String = _runner.get_campaign_id()
	if campaign_id.is_empty():
		return {}

	var pursuit: Dictionary = CampaignRepository.get_open_pursuit_state(
		campaign_id, party_data.id)
	if pursuit.is_empty():
		return {}

	var advantage: int = int(pursuit.get("pursuer_speed_advantage", 0))
	var result: Dictionary = EvasionResolver.catch_up(advantage, DiceSystem)

	var pid: String = str(pursuit.get("pursuit_id", ""))
	var now_round: int = event.fire_time
	CampaignRepository.update_pursuit_state(pid, {
		"last_check_round": now_round,
		"days_in_pursuit": int(pursuit.get("days_in_pursuit", 0)) + 1,
	})

	if bool(result.get("caught", false)):
		CampaignRepository.close_pursuit_state(pid, "caught")
		EventBus.pursuit_caught_up.emit(party_data.id, pid, result)
		EventBus.notification_requested.emit({
			"type": "danger",
			"category": "exploration",
			"title": "Pursuers Caught Up",
			"body": "%s have caught up — combat begins." % str(pursuit.get("pursuer_label", "Pursuers")),
			"duration": 5.0,
		})
		# Force a hostile combat entry. Synthesise an encounter_data dict
		# from the pursuit row — `behavioral_disposition` is fixed to
		# hostile (the pursuers had every chance to give up; they didn't).
		var enc := {
			"encounter_id": CampaignRepository.generate_id(),
			"monster_group": str(pursuit.get("pursuer_label", "pursuers")),
			"number": int(pursuit.get("pursuer_size", 1)),
			"reaction_roll": 2,
			"behavioral_disposition": "hostile",
			"hex_id": "%d,%d" % [party_data.current_hex_q, party_data.current_hex_r],
			"forced_pursuit": true,
		}
		return {
			"enter_combat": true,
			"encounter_data": {
				"encounter_data": enc,
				"return_state": "wilderness",
			},
			"auto_pause": true,
			"pause_reason": "Pursuers caught up",
		}

	# Reschedule another catch-up check for tomorrow. Per RAW the cycle
	# repeats daily until the fleeing side escapes or is caught.
	return {
		"next_events": [{
			"fire_time": now_round + Timekeeping.ROUNDS_PER_DAY,
			"event_type": PURSUIT_CATCHUP_EVENT,
			"owner_id": party_data.id,
			"data": {},
			"priority": ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
		}],
	}


## Deferred camp encounter resolution (gdd-realtime-scheduler.md §4.3.1).
## Fires at the absolute round-time CampHandlers rolled for hour-within-camp.
## The 1-in-6 throw fired at camp_setup; this handler only spawns the
## creatures, computes per-member observer state at event.fire_time against
## the watch schedule persisted on PartyData, applies a Hear Noises 18+ on
## 1d20 to sleeping characters, and routes through the existing
## `encounter_decision_required` modal with surprise context attached.
##
## Cancellation: §4.3.1 says the encounter is bound to the camp; if the camp
## ends first (rest_complete or cancel_camp), CampHandlers.clear_camp_state
## removes any pending wilderness_encounter for this party. If this handler
## fires anyway with `party_data.is_camping == false` (unusual race — camp
## ended in the same scheduler tick), it gracefully no-ops.
func _handle_wilderness_encounter(event: ScheduledEvent) -> Dictionary:
	var party_data: PartyData = _party_data_for_event(event)
	if party_data == null:
		return {}
	if not party_data.is_camping:
		# Camp ended before this encounter could fire; pending event lingered.
		# Treat as a no-op rather than spawning an encounter against a party
		# that has already broken camp.
		return {}

	var party_id: String = event.owner_id
	var is_active: bool = (party_id == GameState.active_party_id)

	# Resolve the hex's terrain for the spawner.
	var controller: HexMapController = _runner.get_hex_map_controller() if _runner != null else null
	var map_data: HexMapData = controller.get_map() if controller != null else null
	var coord := Vector2i(party_data.current_hex_q, party_data.current_hex_r)
	var terrain: HexTerrainData = null
	if map_data != null:
		terrain = map_data.get_hex(coord)

	# Spawn creatures (no re-roll of the 1-in-6 — the camp throw at setup
	# already committed). The spawner uses the existing §4.1 column-selection
	# flow via SessionRunner.spawn_encounter_data.
	var enc: Dictionary = _runner.spawn_encounter_data(
		terrain, [], int(event.data.get("trigger_roll", 0)))
	if enc.is_empty():
		# No monster could be selected for this terrain — drop the encounter
		# rather than crashing. The gate flag has already been stamped at
		# camp_setup, so this won't re-fire today.
		return {}

	# Weather visibility stamp (same as travel-leg / standalone encounter paths).
	var weather: WeatherStateData = _weather_for_hex(terrain, coord, event.fire_time)
	if weather != null:
		enc["visibility_multiplier"] = weather.encounter_visibility_multiplier()

	# Compute per-member observer state at fire_time against the watch
	# schedule, then roll Hear Noises 18+ on 1d20 for each sleeper.
	var surprise_ctx: Dictionary = _compute_camp_surprise_context(
		party_data, event.fire_time)
	enc["observer_states"] = surprise_ctx.get("observer_states", {})
	enc["roused_sleepers"] = surprise_ctx.get("roused_sleepers", [])
	enc["unroused_sleepers"] = surprise_ctx.get("unroused_sleepers", [])
	enc["watch_index"] = surprise_ctx.get("watch_index", -1)
	enc["trigger_source"] = "camp"

	# Route through the existing player-decision modal (per §27 of
	# coding_conventions.md). The state-tier listener
	# (WildernessExploreState._on_encounter_decision_required) opens the
	# EncounterDecisionPrompt.
	var enc_label: String = _format_encounter_label(enc)
	EventBus.encounter_decision_required.emit(party_id, enc)
	return {
		"auto_pause": is_active,
		"pause_reason": "Encounter during camp — %s" % enc_label,
		"presentation": {
			"type": "encounter_decision",
			"encounter_data": enc,
		},
	}


## Computes per-party-member observer state at [param fire_time] against the
## camp's watch schedule. Returns a Dictionary:
##   {
##     "watch_index": int,            # 0..WATCH_COUNT-1 (or -1 if outside)
##     "observer_states": Dictionary, # {character_id: state_key}
##     "roused_sleepers":  Array,     # character_ids who passed Hear Noises
##     "unroused_sleepers": Array,    # character_ids who failed Hear Noises
##   }
## Observer state keys mirror acore_adventures_and_encounters.xml §surprise_and_sneaking:
##   "actively_watching" / "passively_watching" / "distracted_or_not_looking".
func _compute_camp_surprise_context(party_data: PartyData, fire_time: int) -> Dictionary:
	var result := {
		"watch_index": -1,
		"observer_states": {} as Dictionary,
		"roused_sleepers": [] as Array,
		"unroused_sleepers": [] as Array,
	}

	# Parse the watch schedule. If it's malformed or empty, fall back to
	# everyone passively_watching (safer than crashing).
	var assignments_var: Variant = JSON.parse_string(party_data.camp_watch_assignments_json)
	var assignments: Array = assignments_var if assignments_var is Array else []

	var rounds_per_watch: int = CampManager.WATCH_HOURS * Timekeeping.ROUNDS_PER_HOUR
	var camp_start: int = party_data.camp_start_round
	var camp_end: int = party_data.camp_end_round
	var watch_index: int = -1
	if camp_start >= 0 and fire_time >= camp_start and fire_time < camp_end and rounds_per_watch > 0:
		@warning_ignore("integer_division")
		watch_index = (fire_time - camp_start) / rounds_per_watch
		watch_index = clampi(watch_index, 0, CampManager.WATCH_COUNT - 1)
	result["watch_index"] = watch_index

	# Build the set of character_ids on the active watch and the set of all
	# characters anywhere in the watch rotation.
	var on_active_watch: Dictionary = {}
	var in_any_watch: Dictionary = {}
	if watch_index >= 0 and watch_index < assignments.size():
		for cid in assignments[watch_index]:
			on_active_watch[str(cid)] = true
	for watch: Variant in assignments:
		if watch is Array:
			for cid in watch:
				in_any_watch[str(cid)] = true

	var observer_states: Dictionary = {}
	var roused: Array = []
	var unroused: Array = []

	for cd: CharacterData in party_data.character_data:
		var cid: String = cd.id
		var state: String
		if watch_index < 0:
			# Encounter falls outside the camp window (defensive — shouldn't
			# happen given our scheduling). Everyone is awake but off-duty.
			state = "passively_watching"
		elif on_active_watch.has(cid):
			state = "actively_watching"
		elif in_any_watch.has(cid):
			# In the watch rotation but not on this watch → asleep.
			state = "distracted_or_not_looking"
			var hn_roll: RollResult = DiceSystem.roll_digital(20, 1, 0, "hear_noises")
			if hn_roll.modified_total >= 18:
				roused.append(cid)
			else:
				unroused.append(cid)
		else:
			# Party member not in any watch (unusual — joined after camp_setup,
			# or skipped from assignment). Treat as passively_watching.
			state = "passively_watching"
		observer_states[cid] = state

	result["observer_states"] = observer_states
	result["roused_sleepers"] = roused
	result["unroused_sleepers"] = unroused
	return result


## Stamps `party_data.last_encounter_trigger_day` to the day_index containing
## [param fire_time], persisting on change. Implements the hybrid encounter-
## gate of gdd-realtime-scheduler.md §4.3.3 — any positive wilderness
## encounter trigger (travel_leg / wilderness_encounter_check / hunt / lair
## search) bookkeeps against today so subsequent same-day camp throws are
## gated. Idempotent: re-stamping the same day is a no-op.
func _stamp_encounter_gate(party_data: PartyData, fire_time: int) -> void:
	if party_data == null:
		return
	@warning_ignore("integer_division")
	var day_idx: int = fire_time / Timekeeping.ROUNDS_PER_DAY
	if day_idx <= party_data.last_encounter_trigger_day:
		return
	party_data.last_encounter_trigger_day = day_idx
	CampaignRepository.save_party_state(party_data.to_state_dict())


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
		"hunt":             return "Hunt"
		"search_lair":      return "Search for Lairs"
		_:                   return activity_type.capitalize()


## Phase 3: resolve a Hunt activity at the party's current hex. Per RAW:
## "Must be the only activity for the day; no travel is possible." We model
## "the day" as the round during which the activity fires (the player has
## already cancelled travel by issuing the Hunt order via the context menu).
##
## The wandering monster check fires here as well — RAW: "One wandering
## monster check is made during the day of hunting using the appropriate
## terrain table." We delegate to `_runner.do_encounter_check(terrain)`
## which uses the appropriate terrain encounter table, identical to what
## travel_leg uses for its per-hex check.
##
## Auto-pauses on completion so the player sees the result and the wandering
## encounter (if one triggered) at once.
func _resolve_hunt_activity(party_id: String, hex_q: int, hex_r: int) -> Dictionary:
	var party_data: PartyData = _resolve_party_data_by_id(party_id)
	if party_data == null:
		return {"auto_pause": true, "pause_reason": "Hunt failed: party not found"}
	_load_member_proficiencies(party_data)
	# Resolve the hunt throw + 2d6 person-feeds on success.
	var result: Dictionary = HuntingResolver.attempt(party_data, DiceSystem)
	# Persist the updated ration_units (the resolver already mutated party_data).
	CampaignRepository.save_party_state(party_data.to_state_dict())

	# Emit hunt_resolved + toast.
	EventBus.hunt_resolved.emit(party_id, result)
	var toast_type: String = "success" if result.get("succeeded", false) else "warning"
	EventBus.notification_requested.emit({
		"type": toast_type,
		"category": "exploration",
		"title": "Hunt %s" % ("successful" if result.get("succeeded", false) else "failed"),
		"body": String(result.get("notes", "")),
		"duration": 5.0,
	})

	# Wandering monster check during the day of hunting. Phase 5 polish
	# (2026-05-05): the encounter, if any, surfaces an EncounterDecisionPrompt
	# at the state level via `encounter_decision_required`. The hunt-complete
	# presentation is replaced by the encounter-decision presentation when an
	# encounter triggers.
	var controller: HexMapController = _runner.get_hex_map_controller() if _runner != null else null
	var map_data: HexMapData = controller.get_map() if controller != null else null
	var terrain: HexTerrainData = map_data.get_hex(Vector2i(hex_q, hex_r)) if map_data != null else null
	if terrain != null:
		var encounter: Dictionary = _runner.do_encounter_check(terrain)
		if encounter.get("triggered", false):
			var enc: Dictionary = encounter["encounter_data"]
			var weather: WeatherStateData = _weather_for_hex(
				terrain, Vector2i(hex_q, hex_r), Timekeeping.get_party_time(party_id))
			if weather != null:
				enc["visibility_multiplier"] = weather.encounter_visibility_multiplier()
			# Hybrid encounter-gate stamp (§4.3.3).
			_stamp_encounter_gate(party_data, Timekeeping.get_party_time(party_id))
			var enc_label: String = _format_encounter_label(enc)
			EventBus.encounter_decision_required.emit(party_id, enc)
			return {
				"auto_pause": true,
				"pause_reason": "Hunt interrupted — %s" % enc_label,
				"presentation": {
					"type": "encounter_decision",
					"encounter_data": enc,
				},
			}

	return {
		"auto_pause": true,
		"pause_reason": "Hunt complete",
		"presentation": {"type": "hunt_complete", "result": result},
	}


## Phase 4: resolve a Survey activity at the party's current hex. Per
## le_wilderness_lair_rules.xml §land_surveying — a Land Surveying member
## may attempt one assessment on first arrival in the hex, and one
## additional assessment each time the hex is searched. Survey itself does
## NOT count as a search for the cumulative bonus (only successful lair
## searches do, per RAW: "Apply a cumulative +4 bonus for each successful
## search the party has conducted").
func _resolve_survey_activity(party_id: String, hex_q: int, hex_r: int) -> Dictionary:
	var party_data: PartyData = _resolve_party_data_by_id(party_id)
	if party_data == null:
		return {"auto_pause": true, "pause_reason": "Survey failed: party not found"}
	_load_member_proficiencies(party_data)

	var campaign_id: String = _runner.get_campaign_id() if _runner != null else ""
	var map_id: String = _map_id()
	if campaign_id.is_empty() or map_id.is_empty():
		return {"auto_pause": true, "pause_reason": "Survey failed: no map context"}

	var actual_lairs: int = CampaignRepository.count_lairs_in_hex(
		campaign_id, map_id, hex_q, hex_r)
	var progress: Dictionary = CampaignRepository.get_survey_progress(
		campaign_id, map_id, party_id, hex_q, hex_r)
	var prior_searches: int = int(progress.get("successful_searches", 0))

	# Phase 6: Land Surveyor specialist bonus.
	var specialist_bonus: int = SpecialistBonusResolver.bonus_for(
		campaign_id, party_id, SpecialistCatalog.KIND_SURVEYING)
	var result: Dictionary = SurveyingResolver.assess(
		party_data, prior_searches, actual_lairs, DiceSystem, specialist_bonus)

	# Persist the new estimate when the throw produced one (success OR
	# false-reading). Inconclusive failures leave the prior estimate intact.
	if int(result.get("estimate", -1)) >= 0:
		var row := {
			"campaign_id": campaign_id,
			"map_id": map_id,
			"party_id": party_id,
			"hex_q": hex_q,
			"hex_r": hex_r,
			"successful_searches": prior_searches,
			"last_search_round": int(progress.get("last_search_round", -1)),
			"last_estimate": int(result.get("estimate", -1)),
			"last_estimate_correct": bool(result.get("estimate_correct", true)),
		}
		CampaignRepository.upsert_survey_progress(row)

	EventBus.survey_completed.emit(party_id, result)

	var toast_type: String = "info"
	if not bool(result.get("eligible", false)):
		toast_type = "warning"
	elif not bool(result.get("succeeded", false)) and not bool(result.get("natural_one", false)):
		toast_type = "warning"
	EventBus.notification_requested.emit({
		"type": toast_type,
		"category": "exploration",
		"title": "Survey",
		"body": String(result.get("notes", "")),
		"duration": 5.0,
	})

	return {
		"auto_pause": true,
		"pause_reason": "Survey complete",
		"presentation": {"type": "survey_complete", "result": result},
	}


## Phase 4: resolve a full-day dedicated lair search at the party's current
## hex. Per le_wilderness_lair_rules.xml §searching_for_lairs.abstract_search_procedure:
##   "For each hour of searching, equal to six turns, make one secret
##    searching throw on behalf of the party using 1d20."
##   "Adventurers searching a hex are subject to one wandering encounter
##    throw per hour while searching."
##
## v1 collapses the 8 hours into a synchronous block: roll search → encounter
## per hour, exit early on first lair found OR first encounter triggered. The
## party clock does not auto-advance (mirroring Hunt's deliberate-day model);
## the next day-tick fires on schedule. If an encounter triggers we route
## through the combat path identically to a travel-leg encounter.
func _resolve_lair_search_activity(party_id: String, hex_q: int, hex_r: int) -> Dictionary:
	var party_data: PartyData = _resolve_party_data_by_id(party_id)
	if party_data == null:
		return {"auto_pause": true, "pause_reason": "Lair search failed: party not found"}
	_load_member_proficiencies(party_data)

	var campaign_id: String = _runner.get_campaign_id() if _runner != null else ""
	var map_id: String = _map_id()
	if campaign_id.is_empty() or map_id.is_empty():
		return {"auto_pause": true, "pause_reason": "Lair search failed: no map context"}

	var coord := Vector2i(hex_q, hex_r)
	var controller: HexMapController = _runner.get_hex_map_controller() if _runner != null else null
	var map_data: HexMapData = controller.get_map() if controller != null else null
	var terrain: HexTerrainData = map_data.get_hex(coord) if map_data != null else null

	const SEARCH_HOURS := 8
	var hours_spent: int = 0
	var lair_found_id: String = ""
	var search_results: Array = []
	var routed_encounter: Dictionary = {}

	for hour in range(SEARCH_HOURS):
		hours_spent = hour + 1
		var undiscovered: int = CampaignRepository.count_undiscovered_lairs(
			campaign_id, map_id, hex_q, hex_r)
		# RAW: "Determine the target value from the party's daily movement
		# rate through the hex." Dedicated search → daily_miles = 0
		# (party isn't traveling), which lands on the 18+ row of the table.
		# Phase 6: Pathfinder specialist bonus.
		var specialist_bonus: int = SpecialistBonusResolver.bonus_for(
			campaign_id, party_id, SpecialistCatalog.KIND_LAIR_SEARCH)
		var search_result: Dictionary = LairSearchResolver.search_hour(
			party_data, 0, undiscovered, DiceSystem, specialist_bonus)
		search_results.append(search_result)

		if bool(search_result.get("lair_found", false)):
			var revealed_at_round: int = Timekeeping.get_party_time(party_id)
			lair_found_id = CampaignRepository.reveal_one_lair(
				campaign_id, map_id, hex_q, hex_r, revealed_at_round, "search")
			break

		# Wandering encounter check this hour. Phase 5 polish (2026-05-05):
		# every encounter halts the search and surfaces the
		# EncounterDecisionPrompt — the player picks the response.
		if terrain != null:
			var encounter: Dictionary = _runner.do_encounter_check(terrain)
			if encounter.get("triggered", false):
				var enc: Dictionary = encounter["encounter_data"]
				var weather: WeatherStateData = _weather_for_hex(
					terrain, coord, Timekeeping.get_party_time(party_id))
				if weather != null:
					enc["visibility_multiplier"] = weather.encounter_visibility_multiplier()
				# Hybrid encounter-gate stamp (§4.3.3).
				_stamp_encounter_gate(party_data, Timekeeping.get_party_time(party_id))
				EventBus.encounter_decision_required.emit(party_id, enc)
				routed_encounter = {
					"auto_pause": true,
					"pause_reason": "Search interrupted — %s" % _format_encounter_label(enc),
					"presentation": {
						"type": "encounter_decision",
						"encounter_data": enc,
					},
				}
				break

	# Persist a successful-search bump to survey_progress when at least one
	# search throw succeeded (per RAW that's the trigger for the +4 cumulative
	# Land Surveying bonus). Reveal-or-not, success counts.
	var any_success: bool = false
	for sr: Dictionary in search_results:
		if bool(sr.get("succeeded", false)):
			any_success = true
			break
	if any_success:
		var prior: Dictionary = CampaignRepository.get_survey_progress(
			campaign_id, map_id, party_id, hex_q, hex_r)
		var row := {
			"campaign_id": campaign_id,
			"map_id": map_id,
			"party_id": party_id,
			"hex_q": hex_q,
			"hex_r": hex_r,
			"successful_searches": int(prior.get("successful_searches", 0)) + 1,
			"last_search_round": Timekeeping.get_party_time(party_id),
			"last_estimate": int(prior.get("last_estimate", -1)),
			"last_estimate_correct": bool(prior.get("last_estimate_correct", true)),
		}
		CampaignRepository.upsert_survey_progress(row)

	if not lair_found_id.is_empty():
		var reveal_result := {
			"lair_id": lair_found_id,
			"hex_q": hex_q,
			"hex_r": hex_r,
			"via": "search",
			"round": Timekeeping.get_party_time(party_id),
			"hours_spent": hours_spent,
		}
		EventBus.lair_discovered.emit(party_id, reveal_result)
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "exploration",
			"title": "Lair Discovered",
			"body": "Search succeeded after %d hour(s)." % hours_spent,
			"duration": 5.0,
		})

	if not routed_encounter.is_empty():
		# Re-stamp the pause_reason with the hour count for log clarity, but
		# keep the existing presentation (encounter_decision) so the state
		# opens the modal.
		var existing_reason: String = String(routed_encounter.get("pause_reason", ""))
		var encounter_override: Dictionary = routed_encounter.duplicate()
		encounter_override["pause_reason"] = "%s (hour %d)" % [existing_reason, hours_spent]
		return encounter_override

	if lair_found_id.is_empty():
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "exploration",
			"title": "Search Complete",
			"body": "No lair found after %d hour(s) of searching." % hours_spent,
			"duration": 4.0,
		})

	return {
		"auto_pause": true,
		"pause_reason": "Lair search complete",
		"presentation": {
			"type": "lair_search_complete",
			"hours_spent": hours_spent,
			"lair_found_id": lair_found_id,
			"hourly_results": search_results,
		},
	}


## Phase 4 helper: returns the active hex map id, or "" when no map is loaded.
func _map_id() -> String:
	if _runner == null:
		return ""
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return ""
	var map_data: HexMapData = controller.get_map()
	if map_data == null:
		return ""
	return map_data.id


## Phase 4 helper: passive lair-spot check on a travel_leg arrival. Project-
## designed elaboration of le_wilderness_lair_rules.xml §wandering_monsters
## "If the party accidentally wanders into a lair…". Skipped when no
## campaign / map context, when the hex has no undiscovered lairs, or when
## the moving party is unknown. Returns "" on no-spot, otherwise the
## revealed lair_id (signal + toast already fired).
func _passive_lair_check(party_data: PartyData, coord: Vector2i, terrain: HexTerrainData) -> String:
	if party_data == null or terrain == null or _runner == null:
		return ""
	var campaign_id: String = _runner.get_campaign_id()
	var map_id: String = _map_id()
	if campaign_id.is_empty() or map_id.is_empty():
		return ""

	var undiscovered: int = CampaignRepository.count_undiscovered_lairs(
		campaign_id, map_id, coord.x, coord.y)
	if undiscovered <= 0:
		return ""

	# Daily-movement target value from the party's actual on-hex speed.
	var terrain_cat: String = terrain.movement_cost_category()
	var on_road: bool = terrain.has_road() if terrain.has_method("has_road") else false
	var miles_per_day: float = TravelSpeedCalculator.get_miles_per_day(
		party_data, terrain_cat, on_road, null)
	var daily_miles: int = int(round(miles_per_day))

	# Phase 6: Pathfinder specialist bonus on passive throws too.
	var specialist_bonus: int = SpecialistBonusResolver.bonus_for(
		campaign_id, party_data.id, SpecialistCatalog.KIND_LAIR_SEARCH_PASSIVE)
	var result: Dictionary = LairSearchResolver.passive_check(
		party_data, daily_miles, undiscovered, DiceSystem, specialist_bonus)
	if not bool(result.get("succeeded", false)):
		return ""

	var at_round: int = Timekeeping.get_party_time(party_data.id)
	var lair_id: String = CampaignRepository.reveal_one_lair(
		campaign_id, map_id, coord.x, coord.y, at_round, "passive")
	if lair_id.is_empty():
		return ""

	EventBus.lair_discovered.emit(party_data.id, {
		"lair_id": lair_id,
		"hex_q": coord.x,
		"hex_r": coord.y,
		"via": "passive",
		"round": at_round,
	})
	EventBus.notification_requested.emit({
		"type": "info",
		"category": "exploration",
		"title": "Lair Spotted",
		"body": "Your party catches sight of a lair while passing through.",
		"duration": 4.0,
	})
	return lair_id


## Phase 3 helper: resolve PartyData by id, primary path first then DB load.
func _resolve_party_data_by_id(party_id: String) -> PartyData:
	if _runner != null and _runner.get_party_id() == party_id:
		var primary: PartyData = _runner.get_party_data()
		if primary != null and primary.character_data.is_empty():
			# Reload character_data lazily.
			for row: Dictionary in CampaignRepository.list_party_characters(party_id):
				primary.character_data.append(CharacterData.from_dict(row))
		return primary
	var party_data: PartyData = CampaignRepository.load_party_data(party_id)
	if party_data == null:
		return null
	party_data.character_data = []
	for row: Dictionary in CampaignRepository.list_party_characters(party_id):
		party_data.character_data.append(CharacterData.from_dict(row))
	return party_data


## Phase 2 helper: resolve the WeatherStateData for [param terrain] at
## [param coord], on the day implied by [param at_round]. Returns null
## when no campaign / terrain is available so callers fall back to no-weather
## behavior. Reads through the WeatherCache (DB-backed) so identical hex × day
## queries return identical state.
func _weather_for_hex(
	terrain: HexTerrainData,
	coord: Vector2i,
	at_round: int,
) -> WeatherStateData:
	if terrain == null:
		return null
	var campaign_id: String = ""
	if _runner != null and _runner.has_method("get_campaign_id"):
		campaign_id = _runner.get_campaign_id()
	if campaign_id.is_empty():
		return null
	@warning_ignore("integer_division")
	var julian_day: int = (at_round / Timekeeping.ROUNDS_PER_DAY) % Timekeeping.DAYS_PER_YEAR + 1
	@warning_ignore("integer_division")
	var year: int = (at_round / Timekeeping.ROUNDS_PER_DAY) / Timekeeping.DAYS_PER_YEAR + 1
	return WeatherCache.get_or_generate(
		campaign_id, coord.x, coord.y, terrain, julian_day, year)


## Phase 3: returns true when the party is currently in a wilderness hex
## (not settlement/dungeon/camp). Foraging and sustenance only tick in
## wilderness — settlements abstract food/water, dungeon parties carry
## their own (Phase 3.5 polish), camp consumption is folded into the
## rest_complete handler in `camp_handlers.gd`.
func _is_wilderness_location(party_data: PartyData) -> bool:
	if party_data == null:
		return false
	return party_data.current_location_type == "wilderness"


## Phase 3: resolve the HexTerrainData under [param party_data]'s current hex.
## Returns null when the controller / map is not loaded (e.g., early bring-up
## or test fixtures without a runner-attached hex map).
func _terrain_for_party(party_data: PartyData) -> HexTerrainData:
	if party_data == null or _runner == null:
		return null
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return null
	var map_data: HexMapData = controller.get_map()
	if map_data == null:
		return null
	return map_data.get_hex(Vector2i(
		party_data.current_hex_q, party_data.current_hex_r))


## Phase 5 polish (2026-05-05): water refill on terrain that contains a free-
## flowing or standing water source, OR on settlement hexes (the user's design
## treats towns as always-stocked water sources; food in towns goes through
## the shop UI instead). Mirrors the ForagingResolver auto-pass behavior:
## tops off `party.water_units` to `party_size` (one day's draw) without
## over-filling. Idempotent — safe to call multiple times per leg.
func _refill_water_at_hex(party_data: PartyData, terrain: HexTerrainData) -> void:
	if party_data == null or terrain == null:
		return
	var has_water_source: bool = terrain.has_river()
	if not has_water_source and terrain.water == HexTerrainData.WATER_LAKE:
		has_water_source = true
	if not has_water_source and terrain.has_city:
		has_water_source = true
	if not has_water_source and not terrain.settlement_ids.is_empty():
		has_water_source = true
	if not has_water_source:
		return
	var party_size: int = party_data.character_data.size()
	if party_size <= 0:
		return
	var prior: int = party_data.water_units
	party_data.water_units = maxi(party_data.water_units, party_size)
	if party_data.water_units > prior:
		CampaignRepository.save_party_state(party_data.to_state_dict())
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "exploration",
			"title": "Waterskins Refilled",
			"body": "Topped off at the local water source.",
			"duration": 2.5,
		})


## Format an encounter for surfacing in toasts and modal titles.
## Pluralizes the monster name with a simple "s" suffix when count > 1
## (good enough for v1 — proper pluralization tables can land later).
func _format_encounter_label(enc: Dictionary) -> String:
	var count: int = int(enc.get("number", 1))
	var monster: String = String(enc.get("monster_group", "unknown"))
	if monster.is_empty():
		monster = "unknown"
	var label: String = monster
	if count > 1 and not monster.ends_with("s"):
		label = monster + "s"
	return "%d× %s" % [count, label]


## Phase 3: lazily populate `proficiencies` on each party member so
## ForagingResolver / HuntingResolver can call `cd.has_proficiency("survival")`.
## Proficiencies are not loaded by SessionRunner.load_session (per existing
## convention — combat/dungeon handlers load on demand). One query per
## member per day-tick is cheap.
func _load_member_proficiencies(party_data: PartyData) -> void:
	if party_data == null:
		return
	for cd: CharacterData in party_data.character_data:
		if cd == null or cd.id.is_empty():
			continue
		# Skip if already loaded — runtime systems may have populated upstream.
		if not cd.proficiencies.is_empty():
			continue
		cd.proficiencies = CampaignRepository.get_character_proficiencies(cd.id)


## Phase 3: apply hp_loss_per_character from the SustenanceResolver result.
## Uses CampaignRepository.update_character_hp + emits the existing
## EventBus.damage_dealt signal so the rest of the engine (HUD, log, mortal
## wound watchers) reacts identically to combat damage. Source identifier
## is "starvation" or "dehydration" so log filters can distinguish.
func _apply_sustenance_hp_loss(sustenance: Dictionary) -> void:
	var hp_loss: Dictionary = sustenance.get("hp_loss_per_character", {})
	if hp_loss.is_empty():
		return
	# Determine the dominant cause for this character: if dehydration_days >= 1
	# AND starvation_days > grace, both apply. We split the damage source by
	# a simple rule: starvation contributes 1 hp, the rest is dehydration.
	var starvation_per_char: int = 0
	if int(sustenance.get("starvation_days_after", 0)) > SustenanceResolver.FOOD_GRACE_DAYS:
		starvation_per_char = SustenanceResolver.FOOD_DAILY_HP_LOSS
	for char_id in hp_loss:
		var total_loss: int = int(hp_loss[char_id])
		if total_loss <= 0:
			continue
		var char_dict = CampaignRepository.get_character(char_id)
		if not (char_dict is Dictionary):
			continue
		var current_hp: int = int(char_dict.get("hp_current", 0))
		var new_hp: int = current_hp - total_loss
		CampaignRepository.update_character_hp(char_id, new_hp)
		# Split damage source between starvation and dehydration so downstream
		# listeners get the right cause.
		if starvation_per_char > 0:
			EventBus.starvation_tick.emit(char_id, starvation_per_char)
			EventBus.damage_dealt.emit(
				char_id, starvation_per_char, "starvation", "")
		var dehydration_loss: int = total_loss - starvation_per_char
		if dehydration_loss > 0:
			EventBus.dehydration_tick.emit(char_id, dehydration_loss)
			EventBus.damage_dealt.emit(
				char_id, dehydration_loss, "dehydration", "")
		EventBus.hp_changed.emit(char_id, current_hp, new_hp)


## Phase 3: route foraging EventBus signals + a NotificationManager toast.
## Splits food and water into separate `forage_resolved` emissions.
func _emit_forage_signals(party_id: String, forage: Dictionary) -> void:
	if forage.is_empty():
		return
	var food: Dictionary = forage.get("food", {})
	if not food.is_empty():
		EventBus.forage_resolved.emit(party_id, {
			"kind": "food",
			"rolls": int(food.get("rolls", 0)),
			"successes": int(food.get("successes", 0)),
			"units_added": int(food.get("units_added", 0)),
			"auto_pass": false,
			"weather_blocked": bool(food.get("weather_blocked", false)),
		})
	var water: Dictionary = forage.get("water", {})
	if not water.is_empty():
		EventBus.forage_resolved.emit(party_id, {
			"kind": "water",
			"rolls": int(water.get("rolls", 0)),
			"successes": int(water.get("successes", 0)),
			"units_added": int(water.get("units_added", 0)),
			"auto_pass": bool(water.get("auto_pass", false)),
			"weather_blocked": false,
		})
	# One info-tier toast per day summarising both. Toast routing follows
	# gdd-ui-architecture.md §6.3 — async outcomes flow through
	# NotificationManager, not a blocking modal.
	var notes: String = String(forage.get("notes", ""))
	if not notes.is_empty():
		EventBus.notification_requested.emit({
			"type": "info",
			"category": "exploration",
			"title": "Daily Foraging",
			"body": notes,
			"duration": 4.0,
		})


## Phase 3: route sustenance threshold + per-character damage signals.
func _emit_sustenance_signals(party_id: String, sustenance: Dictionary) -> void:
	if sustenance.is_empty():
		return
	var thresholds: Array = sustenance.get("thresholds_crossed", [])
	for label in thresholds:
		var label_str: String = String(label)
		var kind: String = "exhaustion"
		if label_str.begins_with("starvation") or label_str.begins_with("food"):
			kind = "starvation"
		elif label_str.begins_with("dehydration") or label_str.begins_with("water"):
			kind = "dehydration"
		EventBus.sustenance_threshold_crossed.emit(party_id, kind, label_str)
		var toast_data: Dictionary = _toast_for_threshold(label_str)
		if not toast_data.is_empty():
			EventBus.notification_requested.emit(toast_data)


static func _toast_for_threshold(label: String) -> Dictionary:
	match label:
		"food_grace_expired":
			return {
				"type": "warning", "category": "supply",
				"title": "Hungry",
				"body": "The party has gone two days without food. HP loss begins tomorrow if rations are still short.",
				"duration": 5.0,
			}
		"starvation_first_hp_loss":
			return {
				"type": "danger", "category": "supply",
				"title": "Starvation",
				"body": "The party is starving. -1 HP per character per day until food is found. Natural healing suspended.",
				"duration": 6.0,
			}
		"water_first_loss":
			return {
				"type": "danger", "category": "supply",
				"title": "Dehydration",
				"body": "The party is out of water. 1d4 HP per character per day until a source is found. Natural healing suspended.",
				"duration": 6.0,
			}
		"starvation_recovery", "dehydration_recovery":
			return {
				"type": "success", "category": "supply",
				"title": "Sustenance Restored",
				"body": "The party is fed and watered. Natural healing resumes.",
				"duration": 4.0,
			}
		_:
			return {}


## Phase 3: append a row to party_sustenance_log for the Notebook
## "last 7 days" view. Audit-only; not load-bearing.
func _log_sustenance_day(
	party_id: String,
	day_index: int,
	forage: Dictionary,
	sustenance: Dictionary,
) -> void:
	if CampaignRepository.db == null or party_id.is_empty():
		return
	var food: Dictionary = forage.get("food", {})
	var water: Dictionary = forage.get("water", {})
	# water auto-pass top-up isn't included in units_added; report the actual
	# party_size delta in that case so the audit log makes sense.
	var water_foraged: int = int(water.get("units_added", 0))
	if water.get("auto_pass", false):
		water_foraged = int(sustenance.get("party_size", 0))
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO party_sustenance_log
			(party_id, day_index, food_consumed, water_consumed,
			 food_foraged, water_foraged, hp_lost,
			 starvation_days_after, dehydration_days_after, exhaustion_days_after,
			 notes, logged_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
	""", [
		party_id, day_index,
		int(sustenance.get("food_consumed", 0)),
		int(sustenance.get("water_consumed", 0)),
		int(food.get("units_added", 0)),
		water_foraged,
		int(sustenance.get("total_hp_lost", 0)),
		int(sustenance.get("starvation_days_after", 0)),
		int(sustenance.get("dehydration_days_after", 0)),
		int(sustenance.get("exhaustion_days_after", 0)),
		String(forage.get("notes", "")),
	])


## Phase 2: roll today's weather for [param party_data]'s current hex, then
## emit `weather_changed` and route a toast through NotificationManager
## when the rolled weather differs materially from yesterday's record.
##
## "Material" = the short_label() string changes. Calm-to-calm rollovers,
## or two consecutive Cold-Snowy days, are silent. Severe transitions
## (Calm → Rainy, Rainy → Snowy, Mild → Hot, etc.) fire the signal and toast.
##
## Toast tier: warning when today is severe; info otherwise. The first tick
## of a campaign has no yesterday → silent unless today is severe (player
## should still hear about the storm they walked into).
func _roll_and_announce_weather(party_data: PartyData, at_round: int) -> void:
	if party_data == null or _runner == null:
		return
	var controller: HexMapController = _runner.get_hex_map_controller()
	if controller == null:
		return
	var map_data: HexMapData = controller.get_map()
	if map_data == null:
		return
	var coord := Vector2i(party_data.current_hex_q, party_data.current_hex_r)
	var terrain: HexTerrainData = map_data.get_hex(coord)
	if terrain == null:
		return

	var today: WeatherStateData = _weather_for_hex(terrain, coord, at_round)
	if today == null:
		return
	# Yesterday is one full day before this tick. Negative rounds wrap into
	# year 0 territory which the cache would key on; suppress the lookup when
	# at_round < ROUNDS_PER_DAY (campaign's first day-tick).
	var yesterday: WeatherStateData = null
	if at_round >= Timekeeping.ROUNDS_PER_DAY:
		yesterday = _weather_for_hex(
			terrain, coord, at_round - Timekeeping.ROUNDS_PER_DAY)

	var changed: bool = (yesterday == null and today.is_severe()) \
		or (yesterday != null and today.short_label() != yesterday.short_label())
	if not changed:
		return

	var summary := {
		"hex_q": coord.x,
		"hex_r": coord.y,
		"temperature_band": today.temperature_band,
		"temperature_label": WeatherStateData.TEMP_LABELS.get(
			today.temperature_band, "Mild"),
		"atmosphere": today.atmosphere,
		"atmosphere_label": WeatherStateData.ATMO_LABELS.get(today.atmosphere, "Calm"),
		"visibility_multiplier": today.visibility_multiplier,
		"produces_mud": today.produces_mud,
		"short_label": today.short_label(),
	}
	EventBus.weather_changed.emit(party_data.id, summary)

	# Toast routing — gated to severe weather so day-to-day calm rollovers
	# stay quiet. Per gdd-ui-architecture.md §6.3: async outcomes flow
	# through NotificationManager, never a blocking modal.
	if today.is_severe():
		var body: String = "%s in hex (%d, %d)." % [today.short_label(), coord.x, coord.y]
		if today.produces_mud:
			body += " Mud forming on the road."
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "exploration",
			"title": "Weather: %s" % today.short_label(),
			"body": body,
			"duration": 4.0,
		})


# ---------------------------------------------------------------------------
# Encounter-decision dispatch (Phase 5 polish, 2026-05-05)
# ---------------------------------------------------------------------------

## Resolve the player's "Attempt Evasion" choice from the EncounterDecisionPrompt.
##
## Calls EvasionResolver.attempt with the party size and pursuer count from
## the encounter dict. On success, emits an avoidance toast. On failure,
## opens a pursuit_states row, schedules the first daily catch-up check,
## and emits a "still being pursued" toast. Caller is responsible for
## resuming the scheduler.
##
## Returns the EvasionResolver result dict for caller diagnostics.
##
## NOTE: terrain modifiers to the evasion throw (RAW §judge_modifiers) are
## not yet wired — judge_modifier defaults to 0. TODO: pass densely-wooded
## bonus from the current hex terrain.
func attempt_evasion(party_id: String, encounter_data: Dictionary) -> Dictionary:
	var party_data: PartyData = _resolve_party_data_by_id(party_id)
	if party_data == null:
		return {}
	var evader_size: int = party_data.character_data.size()
	var pursuer_size: int = int(encounter_data.get("number", 1))
	var result: Dictionary = EvasionResolver.attempt(
		evader_size, pursuer_size, 0, DiceSystem)
	EventBus.evasion_attempted.emit(party_id, result)

	var enc_label: String = _format_encounter_label(encounter_data)
	if bool(result.get("succeeded", false)):
		EventBus.notification_requested.emit({
			"type": "success",
			"category": "exploration",
			"title": "Evasion Successful",
			"body": "Slipped away from %s. %s" % [
				enc_label, String(result.get("notes", ""))],
			"duration": 4.0,
		})
		EventBus.encounter_avoided.emit(party_id, encounter_data)
	else:
		# Open a pursuit_states row and schedule the first catch-up check.
		var campaign_id: String = _runner.get_campaign_id() if _runner != null else ""
		if not campaign_id.is_empty():
			var now_round: int = Timekeeping.get_party_time(party_id)
			var pursuit_id: String = CampaignRepository.open_pursuit_state({
				"campaign_id": campaign_id,
				"party_id": party_id,
				"pursuer_label": String(encounter_data.get("monster_group", "pursuers")),
				"pursuer_size": pursuer_size,
				# Speed advantage stays 0 in v1 — we do not yet expose monster
				# speeds in the encounter dict. With advantage 0 the catch-up
				# roll auto-fails (per EvasionResolver.catch_up which gates on
				# pursuer_speed_advantage > 0) and the player gets daily retry
				# attempts, which is RAW-conservative.
				"pursuer_speed_advantage": 0,
				"started_at_round": now_round,
				"last_check_round": now_round,
			})
			if not pursuit_id.is_empty() and _runner != null:
				var scheduler: EventScheduler = _runner.get_scheduler()
				if scheduler != null:
					scheduler.schedule_at(
						now_round + Timekeeping.ROUNDS_PER_DAY,
						PURSUIT_CATCHUP_EVENT,
						party_id,
						{},
						ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
					)
		EventBus.notification_requested.emit({
			"type": "warning",
			"category": "exploration",
			"title": "Pursued",
			"body": "%s remain in sight. %s" % [
				enc_label, String(result.get("notes", ""))],
			"duration": 5.0,
		})
	return result
