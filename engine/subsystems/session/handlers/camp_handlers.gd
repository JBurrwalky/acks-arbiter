class_name CampHandlers
extends RefCounted

## Event handlers for wilderness camping (watch resolution).
##
## Registered by CampState after the player confirms watch assignments.
## Each watch is a scheduled event that fires 4 hours apart. If an encounter
## triggers on a watch, the scheduler auto-pauses and combat begins.
##
## Event types handled:
##   "camp_watch"         — resolve one 4-hour watch (encounter check)
##   "camp_rest_complete" — all watches done, compute recovery


# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

var _runner = null  # SessionRunner


func _init(runner) -> void:
	_runner = runner


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(registry: EventHandlerRegistry) -> void:
	registry.register("camp_watch", _handle_camp_watch)
	registry.register("camp_rest_complete", _handle_rest_complete)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister("camp_watch")
	registry.unregister("camp_rest_complete")


# ---------------------------------------------------------------------------
# Scheduling helper (called by CampState after watch assignment)
# ---------------------------------------------------------------------------

## Schedule 3 watch events and 1 rest_complete event.
## [param assignments] — Array of 3 Arrays, each with character_ids on watch.
## [param armed_sleepers] — Array of character_ids sleeping in armor.
## [param scheduler] — EventScheduler to insert into.
## [param party_id] — owning party.
func schedule_watches(
	assignments: Array,
	armed_sleepers: Array,
	scheduler: EventScheduler,
	party_id: String,
) -> void:
	var current_time: int = Timekeeping.get_party_time(party_id)

	for watch_index in range(CampManager.WATCH_COUNT):
		var watch_time: int = current_time + (watch_index * CampManager.WATCH_HOURS * Timekeeping.ROUNDS_PER_HOUR)
		var watch_data := {
			"watch_index": watch_index,
			"watchers": assignments[watch_index] if watch_index < assignments.size() else [],
			"all_assignments": assignments,
			"armed_sleepers": armed_sleepers,
		}
		scheduler.schedule_at(
			watch_time,
			"camp_watch",
			party_id,
			watch_data,
			ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
		)

	# Rest complete fires after all 3 watches (12 hours total)
	var rest_time: int = current_time + (CampManager.TOTAL_REST_HOURS * Timekeeping.ROUNDS_PER_HOUR)
	scheduler.schedule_at(
		rest_time,
		"camp_rest_complete",
		party_id,
		{
			"all_assignments": assignments,
			"armed_sleepers": armed_sleepers,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Resolve one 4-hour watch: advance time, roll encounter check.
func _handle_camp_watch(event: ScheduledEvent) -> Dictionary:
	var watch_index: int = event.data.get("watch_index", 0)

	# Encounter check (1-in-6 per watch, standard wilderness)
	var encounter: Variant = CampManager.check_watch_encounter(1.0 / 6.0)

	if encounter != null:
		# Cancel remaining watches and rest_complete — combat interrupts camp.
		_runner.get_scheduler().cancel_all_for_owner(event.owner_id, "camp_watch")
		_runner.get_scheduler().cancel_all_for_owner(event.owner_id, "camp_rest_complete")
		EventBus.order_cancelled.emit(event.owner_id, "camp_watch")

		# Determine who's sleeping on this watch for combat setup.
		var all_assignments: Array = event.data.get("all_assignments", [])
		var armed_sleepers: Array = event.data.get("armed_sleepers", [])
		var sleeping_ids := _get_sleeping_ids(watch_index, all_assignments)
		var armed_sleeping := _get_armed_sleeping_ids(sleeping_ids, armed_sleepers)

		return {
			"enter_combat": true,
			"encounter_data": {
				"encounter_data": encounter,
				"return_state": "camp",
				"watch_number": watch_index,
				"sleeping_characters": sleeping_ids,
				"armed_sleeping_characters": armed_sleeping,
			},
			"auto_pause": true,
			"pause_reason": "Encounter during watch %d!" % (watch_index + 1),
		}

	# No encounter — watch passed peacefully.
	return {
		"presentation": {
			"type": "camp_watch_clear",
			"watch_index": watch_index,
		},
	}


## All watches completed — compute rest recovery.
func _handle_rest_complete(event: ScheduledEvent) -> Dictionary:
	var armed_sleepers: Array = event.data.get("armed_sleepers", [])

	# Armed sleeper checks.
	var failed_rest_ids: Array = []
	for char_id in armed_sleepers:
		var char_data = CampaignRepository.load_character(char_id)
		if char_data == null or not char_data is Dictionary:
			continue
		var enc: int = char_data.get("encumbrance_stones", 5)
		var con_mod: int = char_data.get("con_modifier", 0)
		var result := CampManager.armed_sleeper_check(enc, con_mod)
		if not result["success"]:
			failed_rest_ids.append(char_id)

	# Compute recovery.
	var party_data: PartyData = _runner.get_party_data()
	var party_members: Array = []
	if party_data != null:
		for cd: CharacterData in party_data.character_data:
			party_members.append({"id": cd.id, "hp_current": cd.hp_current, "hp_max": cd.hp_max})

	var recovery := CampManager.compute_rest_recovery(party_members, failed_rest_ids)
	var rations := CampManager.compute_ration_consumption(party_members.size())

	# Apply recovery to characters.
	for char_id in recovery:
		var rec: Dictionary = recovery[char_id]
		var hp_gain: int = rec.get("hp_recovered", 0)
		if hp_gain > 0:
			var char_dict = CampaignRepository.load_character(char_id)
			if char_dict is Dictionary:
				var new_hp: int = mini(
					char_dict.get("hp_current", 0) + hp_gain,
					char_dict.get("hp_max", 0))
				CampaignRepository.update_character_fields(char_id, {"hp_current": new_hp})
		if rec.get("spells_recovered", false):
			CampaignRepository.reset_spell_slots(char_id)

	EventBus.rest_taken.emit(CampManager.TOTAL_REST_HOURS)

	# Phase 3 (2026-05-04): a full rest day clears exhaustion and resets the
	# days_since_rest counter (per `acore_adventures_and_encounters.xml`
	# §rest rules — 1 day rest per 6 of travel needed to avoid penalties).
	# Sustenance counters (starvation/dehydration) are cleared by the next
	# wilderness_day_tick when food/water are sufficient — they ride the
	# normal SustenanceResolver path and do not need a special-case here.
	if party_data != null and not failed_rest_ids.size() >= party_members.size():
		party_data.exhaustion_days = 0
		party_data.days_since_rest = 0
		party_data.is_force_marching = false
		party_data.force_march_days_used = 0
		CampaignRepository.save_party_state(party_data.to_state_dict())

	return {
		"auto_pause": true,
		"pause_reason": "Rest complete",
		"presentation": {
			"type": "camp_rest_complete",
			"rest_recovery": recovery,
			"rations_consumed": rations,
			"total_hours": CampManager.TOTAL_REST_HOURS,
			"failed_rest_ids": failed_rest_ids,
		},
	}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_sleeping_ids(watch_index: int, assignments: Array) -> Array:
	var awake_ids: Array = assignments[watch_index] if watch_index < assignments.size() else []
	var all_ids: Array = []
	for watch in assignments:
		for cid in watch:
			if cid not in all_ids:
				all_ids.append(cid)
	var sleeping: Array = []
	for cid in all_ids:
		if cid not in awake_ids:
			sleeping.append(cid)
	return sleeping


func _get_armed_sleeping_ids(sleeping_ids: Array, armed_sleepers: Array) -> Array:
	var result: Array = []
	for cid in sleeping_ids:
		if cid in armed_sleepers:
			result.append(cid)
	return result
