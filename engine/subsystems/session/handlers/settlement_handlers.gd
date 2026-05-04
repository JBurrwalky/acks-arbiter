class_name SettlementHandlers
extends RefCounted

## Event handlers for settlement (menu-driven PoI) exploration.
##
## Registered by SettlementExploreState.enter() with the EventHandlerRegistry.
## Settlement travel is a single scheduled arrival event plus 1 (intra-district)
## or 2 (cross-district) encounter checks, per gdd-settlement-exploration-ui.md
## v2 §5.
##
## Event types handled:
##   "city_travel_arrival"  — party arrives at destination PoI
##   "city_encounter_check" — urban encounter roll (1d6 vs 6+, district-modifiable)
##   "settlement_activity"  — timed activity at a PoI (gather info, carouse, etc.)
##   "commission_ready"     — commissioned item ready for pickup


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Encounter check threshold on 1d6. Per acore-monster-stocking-rules.xml:175
## (City terrain row).
const ENCOUNTER_THRESHOLD_DEFAULT: int = 6
const ENCOUNTER_THRESHOLD_HIGH_CRIME: int = 5  # thieves' quarter, etc.
const ENCOUNTER_THRESHOLD_SAFE: int = 7        # noble quarter (effectively impossible on 1d6)


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner

## Per-party active travel state. Keyed by party_id.
## Holds {dest_poi_id, arrival_event_id} for cancellation support.
var _active_travel: Dictionary = {}


func _init(runner) -> void:
	_runner = runner


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("city_travel_arrival", _handle_city_travel_arrival)
	registry.register("city_encounter_check", _handle_city_encounter_check)
	registry.register("settlement_activity", _handle_settlement_activity)
	registry.register("commission_ready", _handle_commission_ready)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("city_travel_arrival")
	registry.unregister("city_encounter_check")
	registry.unregister("settlement_activity")
	registry.unregister("commission_ready")


# ---------------------------------------------------------------------------
# Scheduling helpers (called by SettlementExploreState)
# ---------------------------------------------------------------------------

## Schedules a travel sequence from the party's current PoI to a destination
## PoI. Same-district travel costs 1 turn (10 min) + 1 encounter check;
## cross-district travel costs 1 hour (6 turns) + 2 encounter checks (one per
## district transited).
##
## Returns a travel info dict:
##   { arrival_event_id, encounter_check_ids, total_rounds, is_same_district,
##     origin_district_id, dest_district_id }
## Returns empty dict if either PoI lookup fails.
func schedule_travel(
	settlement: SettlementMapData,
	current_poi_id: String,
	dest_poi_id: String,
	scheduler: EventScheduler,
	party_id: String,
	campaign_id: String,
	settlement_id: String,
	is_night: bool,
) -> Dictionary:
	if settlement == null:
		return {}

	var current_poi: Dictionary = settlement.get_poi(current_poi_id)
	var dest_poi: Dictionary = settlement.get_poi(dest_poi_id)
	if current_poi.is_empty() or dest_poi.is_empty():
		return {}
	if current_poi_id == dest_poi_id:
		return {}

	var origin_district_id: String = current_poi.get("district_id", "")
	var dest_district_id: String = dest_poi.get("district_id", "")
	var is_same_district: bool = origin_district_id == dest_district_id

	var current_time: int = Timekeeping.get_party_time(party_id)
	var rounds_per_turn: int = Timekeeping.ROUNDS_PER_TURN

	var total_rounds: int
	if is_same_district:
		total_rounds = rounds_per_turn  # 1 turn
	else:
		total_rounds = 6 * rounds_per_turn  # 1 hour

	# --- Schedule arrival ---
	var arrival_id := scheduler.schedule_at(
		current_time + total_rounds,
		"city_travel_arrival",
		party_id,
		{
			"dest_poi": dest_poi,
			"origin_poi": current_poi,
			"settlement_id": settlement_id,
			"campaign_id": campaign_id,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)

	# --- Schedule encounter checks ---
	var encounter_ids: Array[String] = []
	if is_same_district:
		var check_id := _schedule_encounter_check(
			scheduler, party_id, current_time + rounds_per_turn / 2,
			origin_district_id, settlement, settlement_id, is_night)
		encounter_ids.append(check_id)
	else:
		var origin_check_id := _schedule_encounter_check(
			scheduler, party_id, current_time + 2 * rounds_per_turn,
			origin_district_id, settlement, settlement_id, is_night)
		encounter_ids.append(origin_check_id)
		var dest_check_id := _schedule_encounter_check(
			scheduler, party_id, current_time + 4 * rounds_per_turn,
			dest_district_id, settlement, settlement_id, is_night)
		encounter_ids.append(dest_check_id)

	_active_travel[party_id] = {
		"dest_poi_id": dest_poi_id,
		"arrival_event_id": arrival_id,
		"encounter_check_ids": encounter_ids,
	}

	EventBus.order_queued.emit(party_id, "city_travel_arrival", current_time + total_rounds)

	return {
		"arrival_event_id": arrival_id,
		"encounter_check_ids": encounter_ids,
		"total_rounds": total_rounds,
		"is_same_district": is_same_district,
		"origin_district_id": origin_district_id,
		"dest_district_id": dest_district_id,
	}


## Cancels all pending travel events for a party. Returns the number cancelled.
func cancel_travel(scheduler: EventScheduler, party_id: String) -> int:
	var total := 0
	total += scheduler.cancel_all_for_owner(party_id, "city_travel_arrival")
	total += scheduler.cancel_all_for_owner(party_id, "city_encounter_check")
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


## Schedules a timed activity at a PoI. Duration depends on activity type;
## one-shot completion event (no tick-tolerance ongoing-activity model in V1 —
## see gdd-domain-tab.md §15.1.2 for the forthcoming Phase H+ migration).
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

## Party arrives at destination PoI. Records the visit and updates the
## SettlementContext (controller).
func _handle_city_travel_arrival(event: ScheduledEvent) -> Dictionary:
	var dest_poi: Dictionary = event.data.get("dest_poi", {})
	var settlement_id: String = event.data.get("settlement_id", "")
	var campaign_id: String = event.data.get("campaign_id", "")

	var dest_id: String = dest_poi.get("id", "")
	var controller: SettlementMapController = _find_settlement_controller()
	if controller != null and not dest_id.is_empty():
		controller.set_current_poi(dest_id)

	# Narrative-tracking visit log (does NOT gate menu visibility).
	if not dest_id.is_empty():
		CampaignRepository.record_visited_poi(
			campaign_id, settlement_id, dest_id,
			event.fire_time, "visited")

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


## Urban encounter check. Rolls 1d6 against the district-modifiable threshold
## (default 6+, high-crime 5+, safe 7+). On success, auto-pauses for the
## encounter UI to surface.
func _handle_city_encounter_check(event: ScheduledEvent) -> Dictionary:
	var threshold: int = int(event.data.get("threshold", ENCOUNTER_THRESHOLD_DEFAULT))

	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "urban_encounter_check")
	if roll.modified_total < threshold:
		return {}

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

func _schedule_encounter_check(
	scheduler: EventScheduler,
	party_id: String,
	fire_time: int,
	district_id: String,
	settlement: SettlementMapData,
	settlement_id: String,
	is_night: bool,
) -> String:
	var threshold: int = _threshold_for_district(settlement, district_id)
	return scheduler.schedule_at(
		fire_time,
		"city_encounter_check",
		party_id,
		{
			"district_id": district_id,
			"threshold": threshold,
			"is_night": is_night,
			"settlement_id": settlement_id,
		},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	)


func _threshold_for_district(settlement: SettlementMapData, district_id: String) -> int:
	if settlement == null:
		return ENCOUNTER_THRESHOLD_DEFAULT
	var dist: Dictionary = settlement.get_district(district_id)
	var modifier: String = dist.get("encounter_modifier", "default")
	match modifier:
		"high-crime", "high_crime":
			return ENCOUNTER_THRESHOLD_HIGH_CRIME
		"safe":
			return ENCOUNTER_THRESHOLD_SAFE
		_:
			return ENCOUNTER_THRESHOLD_DEFAULT


func _find_settlement_controller() -> SettlementMapController:
	if _runner == null:
		return null
	for child in _runner.get_children():
		if child is SettlementMapController:
			return child
	return null
