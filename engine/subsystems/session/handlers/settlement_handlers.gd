class_name SettlementHandlers
extends RefCounted

## Event handlers for settlement (menu-driven PoI) exploration.
##
## Registered by SettlementExploreState.enter() with the EventHandlerRegistry.
## Settlement travel is scheduled as multi-block pathfinding with encounter
## checks and navigation throws, driven by the real-time scheduler.
##
## Event types handled:
##   "city_travel_arrival"  — party arrives at destination PoI
##   "navigation_check"     — commuting-speed navigation throw (every turn)
##   "city_encounter_check" — time-based urban encounter roll
##   "got_lost"             — party deviates after failed navigation throw
##   "settlement_activity"  — timed activity at a PoI (gather info, carouse, etc.)
##   "settlement_encounter" — legacy; kept for backward compat but unused in new flow
##   "commission_ready"     — commissioned item ready for pickup


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner

## Per-party active travel state. Keyed by party_id for future multi-party support.
var _active_travel: Dictionary = {}  # party_id → travel dict


func _init(runner) -> void:
	_runner = runner


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("city_travel_arrival", _handle_city_travel_arrival)
	registry.register("navigation_check", _handle_navigation_check)
	registry.register("city_encounter_check", _handle_city_encounter_check)
	registry.register("got_lost", _handle_got_lost)
	registry.register("settlement_activity", _handle_settlement_activity)
	registry.register("commission_ready", _handle_commission_ready)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("city_travel_arrival")
	registry.unregister("navigation_check")
	registry.unregister("city_encounter_check")
	registry.unregister("got_lost")
	registry.unregister("settlement_activity")
	registry.unregister("commission_ready")


# ---------------------------------------------------------------------------
# Scheduling helpers (called by SettlementExploreState)
# ---------------------------------------------------------------------------

## Schedules a full travel sequence from the party's current node to a
## destination PoI. Includes: arrival event, navigation checks (commuting only),
## and encounter checks at time-based intervals.
##
## Returns a travel info dict:
##   { arrival_event_id, nav_check_ids, encounter_check_ids,
##     total_rounds, block_count, path }
## Returns empty dict if no path exists.
func schedule_travel(
	map_data: SettlementMapData,
	origin_node: int,
	dest_poi: Dictionary,
	speed_mode: String,       ## "commuting" or "meandering"
	streets_only: bool,
	party_size: int,
	scheduler: EventScheduler,
	party_id: String,
	campaign_id: String,
	settlement_id: String,
	is_night: bool,
	looking_for_trouble: bool,
	origin_poi: Dictionary = {},  ## Origin POI (for route memory)
) -> Dictionary:
	# Get destination node.
	var dest_node_ids: Array = dest_poi.get("street_node_ids", [])
	if dest_node_ids.is_empty():
		return {}
	var dest_node: int = dest_node_ids[0]

	# Calculate route.
	var route := SettlementTravelCalculator.calculate_route(
		map_data, origin_node, dest_node, streets_only, party_size)
	if route.is_empty():
		return {}

	var block_count: int = route["block_count"]
	if block_count == 0:
		return {}  # Already at destination.

	var total_rounds: int
	if speed_mode == "commuting":
		total_rounds = route["commute_rounds"]
	else:
		total_rounds = route["meander_rounds"]

	var current_time: int = Timekeeping.get_party_time(party_id)

	# Schedule arrival.
	var arrival_id := scheduler.schedule_at(
		current_time + total_rounds,
		"city_travel_arrival",
		party_id,
		{
			"dest_poi": dest_poi,
			"dest_node": dest_node,
			"origin_poi": origin_poi,
			"settlement_id": settlement_id,
			"campaign_id": campaign_id,
			"block_count": block_count,
			"speed_mode": speed_mode,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)

	# Schedule navigation checks (commuting speed only, every turn).
	var nav_ids: Array[String] = []
	if speed_mode == "commuting":
		var turn_rounds: int = Timekeeping.ROUNDS_PER_TURN
		var nav_time: int = current_time + turn_rounds
		while nav_time < current_time + total_rounds:
			var nav_id := scheduler.schedule_at(
				nav_time,
				"navigation_check",
				party_id,
				{
					"origin_poi_id": origin_poi.get("id", ""),
					"dest_poi_id": dest_poi.get("id", ""),
					"settlement_id": settlement_id,
					"campaign_id": campaign_id,
					"speed_mode": speed_mode,
					"path": route["path"],
				},
				ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
			)
			nav_ids.append(nav_id)
			nav_time += turn_rounds

	# Schedule encounter checks.
	var encounter_ids := SettlementEncounterScheduler.schedule_encounter_checks(
		scheduler, party_id, current_time, total_rounds,
		route["has_alleys"], is_night, looking_for_trouble,
		settlement_id)

	# Record active travel state.
	var travel_state := {
		"dest_poi": dest_poi,
		"origin_poi": origin_poi,
		"path": route["path"],
		"block_count": block_count,
		"total_rounds": total_rounds,
		"speed_mode": speed_mode,
		"start_time": current_time,
		"arrival_event_id": arrival_id,
		"nav_check_ids": nav_ids,
		"encounter_check_ids": encounter_ids,
		"settlement_id": settlement_id,
		"campaign_id": campaign_id,
		"streets_only": streets_only,
		"is_night": is_night,
		"looking_for_trouble": looking_for_trouble,
		"party_size": party_size,
	}
	_active_travel[party_id] = travel_state

	EventBus.order_queued.emit(party_id, "city_travel_arrival", current_time + total_rounds)

	return {
		"arrival_event_id": arrival_id,
		"nav_check_ids": nav_ids,
		"encounter_check_ids": encounter_ids,
		"total_rounds": total_rounds,
		"block_count": block_count,
		"path": route["path"],
	}


## Cancels all pending travel events for a party. Returns the number cancelled.
func cancel_travel(scheduler: EventScheduler, party_id: String) -> int:
	var total := 0
	total += scheduler.cancel_all_for_owner(party_id, "city_travel_arrival")
	total += scheduler.cancel_all_for_owner(party_id, "navigation_check")
	total += scheduler.cancel_all_for_owner(party_id, "city_encounter_check")
	total += scheduler.cancel_all_for_owner(party_id, "got_lost")
	_active_travel.erase(party_id)
	if total > 0:
		EventBus.order_cancelled.emit(party_id, "city_travel_arrival")
	return total


## Returns the active travel state for a party, or empty dict if not traveling.
func get_active_travel(party_id: String) -> Dictionary:
	return _active_travel.get(party_id, {})


## Returns true if the party is currently traveling between PoIs.
func is_traveling(party_id: String) -> bool:
	return _active_travel.has(party_id)


## Schedule a timed activity at a PoI. Duration depends on activity type.
func schedule_activity(
	activity_type: String,
	poi_data: Dictionary,
	duration_turns: int,
	scheduler: EventScheduler,
	party_id: String,
) -> String:
	var current_time: int = Timekeeping.get_party_time(party_id)
	var duration_rounds: int = duration_turns * Timekeeping.ROUNDS_PER_TURN

	var event_id := scheduler.schedule_at(
		current_time + duration_rounds,
		"settlement_activity",
		party_id,
		{
			"activity_type": activity_type,
			"poi_data": poi_data,
			"duration_turns": duration_turns,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)
	EventBus.order_queued.emit(party_id, "settlement_activity", current_time + duration_rounds)
	return event_id


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Party arrives at destination PoI. Records the route and visited POI.
func _handle_city_travel_arrival(event: ScheduledEvent) -> Dictionary:
	var dest_poi: Dictionary = event.data.get("dest_poi", {})
	var dest_node: int = event.data.get("dest_node", -1)
	var origin_poi: Dictionary = event.data.get("origin_poi", {})
	var settlement_id: String = event.data.get("settlement_id", "")
	var campaign_id: String = event.data.get("campaign_id", "")

	# Move the party to the destination node on the controller.
	var controller: SettlementMapController = _find_settlement_controller()
	if controller != null and dest_node >= 0:
		controller.set_party_node(dest_node)

	# Record route memory (both directions).
	var origin_id: String = origin_poi.get("id", "")
	var dest_id: String = dest_poi.get("id", "")
	if not origin_id.is_empty() and not dest_id.is_empty():
		CampaignRepository.record_city_route(campaign_id, settlement_id, origin_id, dest_id)
		CampaignRepository.record_city_route(campaign_id, settlement_id, dest_id, origin_id)

	# Record visited POI.
	if not dest_id.is_empty():
		CampaignRepository.record_visited_poi(
			campaign_id, settlement_id, dest_id,
			event.fire_time, "visited")

	# Clear active travel state.
	_active_travel.erase(event.owner_id)

	var poi_name: String = dest_poi.get("name", "destination")
	return {
		"auto_pause": true,
		"pause_reason": "Arrived at %s" % poi_name,
		"presentation": {
			"type": "city_travel_arrival",
			"poi": dest_poi,
			"settlement_id": settlement_id,
		},
	}


## Navigation check during commuting-speed travel. Fires every turn.
func _handle_navigation_check(event: ScheduledEvent) -> Dictionary:
	var campaign_id: String = event.data.get("campaign_id", "")
	var settlement_id: String = event.data.get("settlement_id", "")
	var origin_poi_id: String = event.data.get("origin_poi_id", "")
	var dest_poi_id: String = event.data.get("dest_poi_id", "")

	# Gather party characters for proficiency checks.
	var party_characters: Array = _get_party_characters()

	var nav_result := SettlementNavigation.check_navigation(
		campaign_id, settlement_id, origin_poi_id, dest_poi_id, party_characters)

	if nav_result["succeeded"]:
		return {
			"presentation": {
				"type": "navigation_check",
				"result": nav_result,
				"succeeded": true,
			},
		}

	# Navigation failed — party gets lost.
	var deviation: int = SettlementNavigation.roll_deviation()
	return {
		"auto_pause": true,
		"pause_reason": "Navigation failed — took a wrong turn! Lost %d blocks." % deviation,
		"presentation": {
			"type": "navigation_check",
			"result": nav_result,
			"succeeded": false,
			"deviation_blocks": deviation,
		},
		"next_events": [{
			"event_type": "got_lost",
			"fire_time": event.fire_time,  # Resolve immediately.
			"owner_id": event.owner_id,
			"data": {
				"deviation_blocks": deviation,
				"settlement_id": settlement_id,
				"campaign_id": campaign_id,
			},
			"priority": ScheduledEvent.PRIORITY_CONSEQUENCE,
		}],
	}


## Party got lost — reroute with deviation penalty.
## The party's current travel is cancelled and rescheduled from a wrong position.
func _handle_got_lost(event: ScheduledEvent) -> Dictionary:
	var party_id: String = event.owner_id
	var deviation: int = event.data.get("deviation_blocks", 2)

	# The deviation adds extra blocks to the remaining travel time.
	# For now, we add the deviation as extra rounds at the current speed.
	var travel: Dictionary = _active_travel.get(party_id, {})
	if travel.is_empty():
		return {}

	var speed_mode: String = travel.get("speed_mode", "commuting")
	var party_size: int = travel.get("party_size", 1)
	var strag_mult: int = SettlementTravelCalculator._straggling_multiplier(party_size)

	var extra_rounds: int
	if speed_mode == "commuting":
		extra_rounds = deviation * SettlementTravelCalculator.COMMUTE_ROUNDS_PER_BLOCK * strag_mult
	else:
		extra_rounds = deviation * SettlementTravelCalculator.MEANDER_ROUNDS_PER_BLOCK

	# Cancel the old arrival event and reschedule with extended time.
	var scheduler: EventScheduler = _runner.get_scheduler()
	var old_arrival_id: String = travel.get("arrival_event_id", "")
	if not old_arrival_id.is_empty():
		scheduler.cancel(old_arrival_id)

	# Schedule new arrival with the extra time added.
	var old_dest_poi: Dictionary = travel.get("dest_poi", {})
	var dest_node_ids: Array = old_dest_poi.get("street_node_ids", [])
	var dest_node: int = dest_node_ids[0] if not dest_node_ids.is_empty() else -1
	var new_arrival_time: int = event.fire_time + extra_rounds + _remaining_rounds(travel, event.fire_time)

	var new_arrival_id := scheduler.schedule_at(
		new_arrival_time,
		"city_travel_arrival",
		party_id,
		travel.get("dest_poi", {}),
		ScheduledEvent.PRIORITY_ARRIVAL,
	)

	# Update travel state.
	travel["arrival_event_id"] = new_arrival_id
	travel["total_rounds"] = travel.get("total_rounds", 0) + extra_rounds

	return {
		"presentation": {
			"type": "got_lost",
			"extra_blocks": deviation,
			"extra_rounds": extra_rounds,
			"new_eta_rounds": new_arrival_time - event.fire_time,
		},
	}


## Urban encounter check. Fires at time-based intervals during travel.
## Encounters on 6+ on 1d6 (or 5+ with Looking for Trouble).
func _handle_city_encounter_check(event: ScheduledEvent) -> Dictionary:
	var threshold: int = event.data.get("threshold",
		SettlementEncounterScheduler.THRESHOLD_NORMAL)

	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "urban_encounter_check")
	if roll.modified_total >= threshold:
		return {
			"auto_pause": true,
			"pause_reason": "Urban encounter!",
			"presentation": {
				"type": "city_encounter_check",
				"roll": roll.modified_total,
				"threshold": threshold,
				"triggered": true,
				"is_night": event.data.get("is_night", false),
				"district_id": event.data.get("district_id", ""),
				"settlement_id": event.data.get("settlement_id", ""),
			},
		}
	return {}


## A timed activity at a PoI completes.
func _handle_settlement_activity(event: ScheduledEvent) -> Dictionary:
	var activity_type: String = event.data.get("activity_type", "")
	return {
		"auto_pause": true,
		"pause_reason": "Activity complete: %s" % activity_type,
		"presentation": {
			"type": "settlement_activity_complete",
			"activity_type": activity_type,
			"poi_data": event.data.get("poi_data", {}),
		},
	}


## A commissioned item is ready for pickup at a shop.
func _handle_commission_ready(event: ScheduledEvent) -> Dictionary:
	var item_name: String = event.data.get("item_name", "item")
	var character_id: String = event.data.get("character_id", "")
	EventBus.commission_ready.emit(
		event.data.get("commission_id", ""),
		character_id,
		event.data.get("item_key", ""))
	return {
		"auto_pause": true,
		"pause_reason": "Commission ready: %s" % item_name,
		"presentation": {
			"type": "commission_ready",
			"poi_id": event.data.get("poi_id", ""),
			"item_key": event.data.get("item_key", ""),
			"item_name": item_name,
			"character_id": character_id,
			"settlement_id": event.data.get("settlement_id", ""),
		},
	}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _find_settlement_controller() -> SettlementMapController:
	if _runner == null:
		return null
	for child in _runner.get_children():
		if child is SettlementMapController:
			return child
	return null


## Get party character data for proficiency checks.
func _get_party_characters() -> Array:
	if _runner == null:
		return []
	var party_data = _runner.get_party_data()
	if party_data == null:
		return []
	return party_data.character_data


## Calculate remaining rounds of travel from a given point in time.
func _remaining_rounds(travel: Dictionary, current_time: int) -> int:
	var start: int = travel.get("start_time", 0)
	var total: int = travel.get("total_rounds", 0)
	var end_time: int = start + total
	return maxi(end_time - current_time, 0)
