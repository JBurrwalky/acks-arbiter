class_name ExtractionScheduler
extends RefCounted

## Encamped requisition_leg / loot_leg scheduled activities (gdd-army-warfare.md §4.3;
## daw_campaigning_armies.xml L345 encamped current-then-adjacent geography). A 7-day
## scheduled event mirroring army_marcher's travel_leg: begin_* sets armies.state to
## requisitioning / looting and schedules the leg; on completion the handler resolves the
## extraction (ExtractionResolver — current hex first, then adjacent), credits the army,
## flips state back to encamped, and emits a past-tense completion signal.
##
## ALL state the completion handler needs lives in event.data (JSON-persisted), so the leg
## survives save/load mid-leg — this service is recreated fresh on load_session and re-injects
## parked events on register (park-don't-consume, same as ArmyMarcher).
##
## Public API (mirrors ArmyMarcher):
##   register(registry) / unregister(registry)
##   begin_requisition(army_id, current_time, scheduler) -> Dictionary
##   begin_loot(army_id, current_time, scheduler) -> Dictionary
##   cancel(army_id, scheduler) -> int

const EVENT_REQUISITION_LEG := "requisition_leg"
const EVENT_LOOT_LEG := "loot_leg"
const LEG_DAYS := 7   # RAW models requisition/loot as a weekly (7-day) activity


func register(registry: EventHandlerRegistry) -> void:
	registry.register(EVENT_REQUISITION_LEG, _handle_requisition_leg)
	registry.register(EVENT_LOOT_LEG, _handle_loot_leg)


func unregister(registry: EventHandlerRegistry) -> void:
	registry.unregister(EVENT_REQUISITION_LEG)
	registry.unregister(EVENT_LOOT_LEG)


func begin_requisition(army_id: String, current_time: int, scheduler: EventScheduler) -> Dictionary:
	return _begin(army_id, ExtractionResolver.MODE_REQUISITION, EVENT_REQUISITION_LEG,
		"requisitioning", current_time, scheduler)


func begin_loot(army_id: String, current_time: int, scheduler: EventScheduler) -> Dictionary:
	return _begin(army_id, ExtractionResolver.MODE_LOOT, EVENT_LOOT_LEG,
		"looting", current_time, scheduler)


func cancel(army_id: String, scheduler: EventScheduler) -> int:
	if scheduler == null or army_id.is_empty():
		return 0
	var count := scheduler.cancel_all_for_owner(army_id, EVENT_REQUISITION_LEG)
	count += scheduler.cancel_all_for_owner(army_id, EVENT_LOOT_LEG)
	if count > 0:
		ArmyRepository.update_army(army_id, {"state": "encamped"})
	return count


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _begin(army_id: String, mode: String, event_type: String, state: String,
		current_time: int, scheduler: EventScheduler) -> Dictionary:
	if army_id.is_empty():
		return {"success": false, "error": "army_id_required"}
	if scheduler == null:
		return {"success": false, "error": "no_scheduler"}
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return {"success": false, "error": "army_not_found"}
	if String(army.get("state", "")) != "encamped":
		return {"success": false, "error": "army_must_be_encamped",
			"current_state": army.get("state", "")}
	# One extraction leg at a time per army (idempotent scheduling, §19.5).
	if scheduler.has_event_for_owner(army_id, event_type):
		return {"success": false, "error": "extraction_already_pending"}
	var leg_rounds := LEG_DAYS * Timekeeping.ROUNDS_PER_DAY
	var event_id := scheduler.schedule_after(current_time, leg_rounds, event_type, army_id, {
		"army_id": army_id, "mode": mode,
		"map_id": String(army.get("map_id", "")),
		"hex_q": _safe_int(army.get("hex_q")), "hex_r": _safe_int(army.get("hex_r")),
	}, ScheduledEvent.PRIORITY_ARRIVAL)
	ArmyRepository.update_army(army_id, {"state": state})
	if EventBus.has_signal("order_queued"):
		EventBus.emit_signal("order_queued", army_id, event_type, current_time + leg_rounds)
	return {"success": true, "leg_event_id": event_id, "mode": mode,
		"eta_round": current_time + leg_rounds, "leg_days": LEG_DAYS, "army_id": army_id}


func _handle_requisition_leg(event: ScheduledEvent) -> Dictionary:
	return _handle_leg(event, ExtractionResolver.MODE_REQUISITION)


func _handle_loot_leg(event: ScheduledEvent) -> Dictionary:
	return _handle_leg(event, ExtractionResolver.MODE_LOOT)


func _handle_leg(event: ScheduledEvent, mode: String) -> Dictionary:
	var army_id: String = event.owner_id
	var data: Dictionary = event.data
	var map_id := String(data.get("map_id", ""))
	var hex_q := _safe_int(data.get("hex_q"))
	var hex_r := _safe_int(data.get("hex_r"))
	var calendar_day := Timekeeping.get_calendar_day()

	var result := _resolve_encamped(army_id, map_id, hex_q, hex_r, mode, calendar_day)

	# Leg over — return the army to encamped.
	ArmyRepository.update_army(army_id, {"state": "encamped"})

	var domain_id := String(result.get("domain_id", ""))
	var gp_cp := int(result.get("gp_yield_cp", 0))
	var families_lost := int(result.get("families_lost", 0))
	if mode == ExtractionResolver.MODE_REQUISITION:
		if EventBus.has_signal("army_requisition_completed"):
			EventBus.emit_signal("army_requisition_completed", army_id, domain_id, gp_cp)
	else:
		if EventBus.has_signal("army_loot_completed"):
			EventBus.emit_signal("army_loot_completed", army_id, domain_id, gp_cp, families_lost)
	return {"event_type": event.event_type, "army_id": army_id, "extraction": result}


## Current hex first, then the 6 adjacent hexes (RAW L345). Requisition requires a friendly
## domain; loot takes any. Extracts from the FIRST eligible domain and returns its result.
func _resolve_encamped(army_id: String, map_id: String, hex_q: int, hex_r: int,
		mode: String, calendar_day: int) -> Dictionary:
	var candidates: Array = [Vector2i(hex_q, hex_r)]
	candidates.append_array(HexMapController.get_neighbors(Vector2i(hex_q, hex_r)))
	for coord in candidates:
		var domain_id := ExtractionResolver.domain_for_hex(map_id, coord.x, coord.y)
		if domain_id.is_empty():
			continue
		if mode == ExtractionResolver.MODE_REQUISITION \
				and not ExtractionResolver.is_friendly_domain(army_id, domain_id):
			continue
		var res := ExtractionResolver.resolve(army_id, domain_id, mode, calendar_day)
		if bool(res.get("success", false)):
			return res
	return {"success": false, "error": "no_extractable_domain"}


func _safe_int(v) -> int:
	return int(v) if v != null else 0
