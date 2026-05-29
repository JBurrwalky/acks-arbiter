class_name CampHandlers
extends RefCounted

## Event handlers for wilderness camping.
##
## Revised 2026-05-27 (gdd-realtime-scheduler.md §4.3): camp_watch is a state
## /UX boundary, NOT an encounter check. The camp's single encounter throw is
## performed in `schedule_watches` at camp_setup, gated by the hybrid rule
## (§4.3.3). On a positive throw, a `wilderness_encounter` event is scheduled
## at a uniform 1d(camp_hours) hour within the camp window; that event's
## handler (in WildernessHandlers, registered globally) spawns the creatures
## and computes per-member observer state at fire_time against the watch
## schedule persisted on PartyData.
##
## Event types handled:
##   "camp_watch"         — state/UX boundary marker (no encounter roll)
##   "camp_rest_complete" — all watches done, compute recovery + clear camp state


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

## Stamps the camp state on PartyData, schedules the 3 watch markers + the
## rest_complete event, and performs the gated camp encounter throw per
## gdd-realtime-scheduler.md §4.3.1.
##
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
	var camp_end_time: int = current_time + (CampManager.TOTAL_REST_HOURS * Timekeeping.ROUNDS_PER_HOUR)

	# Stamp the camp window + watch schedule on PartyData so the globally-
	# registered wilderness_encounter handler can compute observer state at
	# fire_time regardless of which session state the party is in.
	var party_data: PartyData = _resolve_party_data(party_id)
	if party_data != null:
		party_data.is_camping = true
		party_data.camp_start_round = current_time
		party_data.camp_end_round = camp_end_time
		party_data.camp_watch_assignments_json = JSON.stringify(assignments)
		party_data.camp_armed_sleepers_json = JSON.stringify(armed_sleepers)
		CampaignRepository.save_party_state(party_data.to_state_dict())

	# Schedule the 3 watch markers — state/UX events, not encounter throws.
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

	# Rest complete fires after all 3 watches (12 hours total).
	scheduler.schedule_at(
		camp_end_time,
		"camp_rest_complete",
		party_id,
		{
			"all_assignments": assignments,
			"armed_sleepers": armed_sleepers,
		},
		ScheduledEvent.PRIORITY_ARRIVAL,
	)

	# Camp encounter throw (gdd-realtime-scheduler.md §4.3.1).
	_perform_camp_encounter_throw(party_id, party_data, current_time, camp_end_time, scheduler)


## Performs the gated camp encounter throw at camp_setup. Per §4.3.3, the
## throw fires only when current_day_index > last_encounter_trigger_day (the
## party has not already had an encounter triggered today). On a positive 1-in
## -6 throw, stamps the gate flag and schedules `wilderness_encounter` at a
## uniform random hour within the camp window.
func _perform_camp_encounter_throw(
	party_id: String,
	party_data: PartyData,
	camp_start: int,
	camp_end: int,
	scheduler: EventScheduler,
) -> void:
	if party_data == null:
		return

	# Civilized hex: no random encounters (mirrors do_encounter_check).
	var controller: HexMapController = _runner.get_hex_map_controller() if _runner != null else null
	var map_data: HexMapData = controller.get_map() if controller != null else null
	var terrain: HexTerrainData = null
	if map_data != null:
		terrain = map_data.get_hex(Vector2i(party_data.current_hex_q, party_data.current_hex_r))
	if terrain != null and terrain.civilization == HexTerrainData.TERRITORY_CIVILIZED:
		return

	@warning_ignore("integer_division")
	var current_day_index: int = camp_start / Timekeeping.ROUNDS_PER_DAY

	# Hybrid-rule gate: skip the throw if an encounter has already triggered
	# for this party today.
	if current_day_index <= party_data.last_encounter_trigger_day:
		return

	var threshold: int = 1  # 1-in-6 (matches do_encounter_check)
	var roll: RollResult = DiceSystem.roll_digital(6, 1, 0, "camp_encounter_check")
	if roll.modified_total > threshold:
		return

	# Stamp the gate flag so any further travel_leg or camp throw today is
	# gated. The encounter has been *committed*, even though its resolution
	# fires later.
	party_data.last_encounter_trigger_day = current_day_index
	CampaignRepository.save_party_state(party_data.to_state_dict())

	# Roll uniform hour-of-camp. Camp is TOTAL_REST_HOURS hours; pick 0..n-1
	# (so the encounter fires somewhere strictly within the camp window).
	var camp_hours: int = CampManager.TOTAL_REST_HOURS
	var hour_offset: int = DiceSystem.roll_digital(
		camp_hours, 1, 0, "camp_encounter_hour").modified_total - 1
	hour_offset = clampi(hour_offset, 0, camp_hours - 1)
	var fire_time: int = camp_start + (hour_offset * Timekeeping.ROUNDS_PER_HOUR)
	# Clamp inside [camp_start, camp_end) just in case of rounding edge cases.
	fire_time = clampi(fire_time, camp_start, camp_end - 1)

	scheduler.schedule_at(
		fire_time,
		WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT,
		party_id,
		{
			"camp_start_round": camp_start,
			"camp_end_round": camp_end,
			"trigger_source": "camp",
			"trigger_roll": roll.modified_total,
		},
		ScheduledEvent.PRIORITY_SCHEDULED_CHECK,
	)


# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

## Watch boundary marker. State/UX only — no encounter throw. Future hooks:
## mage memorization window completion, cleric prayer window, Rest activity
## tick at the watch handoff.
func _handle_camp_watch(event: ScheduledEvent) -> Dictionary:
	var watch_index: int = event.data.get("watch_index", 0)
	return {
		"presentation": {
			"type": "camp_watch_boundary",
			"watch_index": watch_index,
		},
	}


## All watches completed — compute rest recovery and clear camp state.
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
	var party_data: PartyData = _resolve_party_data(event.owner_id)
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

	# A full rest day clears exhaustion and resets days_since_rest per
	# acore_adventures_and_encounters.xml §rest rules.
	if party_data != null and not failed_rest_ids.size() >= party_members.size():
		party_data.exhaustion_days = 0
		party_data.days_since_rest = 0
		party_data.is_force_marching = false
		party_data.force_march_days_used = 0

	# Clear camp state on PartyData and cancel any pending wilderness_encounter
	# event whose fire_time was past camp_end (per §4.3.1: leaving the camp
	# dissolves the scheduled encounter).
	clear_camp_state(event.owner_id, party_data)

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
# Public helpers
# ---------------------------------------------------------------------------

## Clears the camp_* fields on PartyData and cancels any pending
## wilderness_encounter event for this party. Called by `_handle_rest_complete`
## (normal end) and by `CampState.handle_action("cancel_camp")` (player abort).
## Safe to call when no camp is active (idempotent).
func clear_camp_state(party_id: String, party_data: PartyData = null) -> void:
	if party_data == null:
		party_data = _resolve_party_data(party_id)

	var scheduler: EventScheduler = _runner.get_scheduler() if _runner != null else null
	if scheduler != null and not party_id.is_empty():
		scheduler.cancel_all_for_owner(party_id, WildernessHandlers.WILDERNESS_ENCOUNTER_EVENT)

	if party_data != null:
		party_data.is_camping = false
		party_data.camp_start_round = -1
		party_data.camp_end_round = -1
		party_data.camp_watch_assignments_json = "[]"
		party_data.camp_armed_sleepers_json = "[]"
		CampaignRepository.save_party_state(party_data.to_state_dict())


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Resolves the camping party's PartyData. Uses the runner's cached object for
## the primary party (so in-memory mutations like camp_* fields persist within
## the session); falls back to a fresh DB load for non-primary parties.
func _resolve_party_data(party_id: String) -> PartyData:
	if _runner == null or party_id.is_empty():
		return null
	if party_id == _runner.get_party_id():
		return _runner.get_party_data()
	return CampaignRepository.load_party_data(party_id)
