class_name StandDownTribalWarriorsHandler
extends RefCounted

## stand_down_tribal_warriors handler — Phase 11D.5 per
## gdd-tribal-warriors.md §5.3. Returns levied warriors to dormant state.
##
## Effects:
##   1. The target tribal_warrior troop_unit's count is reduced by `count`.
##      If the full unit is stood down (count == unit.count), the row is
##      marked status='departed' with departure_kind='stood_down'.
##      Otherwise the row's count just decrements.
##   2. `domains.available_tribal_warriors` is incremented by `count`,
##      capped at `peasant_families - sum(remaining levied)` (the pool
##      invariant). The cap is normally satisfied by the decrement of the
##      unit's count happening in step 1 — we apply min() as defense-in-depth.
##   3. Departure log entry: `tribal_warriors_stood_down`.
##   4. EventBus signal: `tribal_warriors_stood_down`.
##
## Warriors returned to dormant state are NOT lost — they refill the
## available pool. Casualties (not voluntary stand-down) are the only
## permanent reduction.


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var params: Dictionary = _parse_params(state)
	var unit_id: String = String(params.get("troop_unit_id", ""))
	if unit_id.is_empty():
		return {"summary": "stand_down_tribal_warriors: troop_unit_id required",
				"blocked_reason": "missing_troop_unit_id"}
	var unit: Dictionary = TroopUnitRepository.get_unit(unit_id)
	if unit.is_empty():
		return {"summary": "stand_down_tribal_warriors: unit not found",
				"blocked_reason": "unit_not_found"}
	if String(unit.get("source_type", "")) != "tribal_warrior":
		return {"summary": "stand_down_tribal_warriors: unit is not tribal_warrior",
				"blocked_reason": "wrong_source_type"}
	if String(unit.get("status", "")) != "active":
		return {"summary": "stand_down_tribal_warriors: unit is not active",
				"blocked_reason": "unit_not_active"}
	# Ruler check — the unit's owner must match the caster, or the caster
	# must rule the domain the unit is assigned to.
	var owner_id: String = String(unit.get("owner_character_id", ""))
	var domain_id: String = String(unit.get("assigned_domain_id", ""))
	var domain: Dictionary = _get_domain(domain_id) if not domain_id.is_empty() else {}
	var domain_ruler: String = String(domain.get("owner_character_id", "")) if not domain.is_empty() else ""
	if owner_id != character_id and domain_ruler != character_id:
		return {"summary": "stand_down_tribal_warriors: not authorized",
				"blocked_reason": "not_authorized"}

	var current_count: int = int(unit.get("count", 0))
	var requested: int = int(params.get("count", current_count))
	var count: int = mini(maxi(0, requested), current_count)
	if count <= 0:
		return {"summary": "stand_down_tribal_warriors: count must be > 0",
				"blocked_reason": "zero_count"}

	var calendar_day: int = _calendar_day()
	var campaign_id: String = String(unit.get("campaign_id", ""))

	# 1. Mutate the unit row.
	if count >= current_count:
		# Full stand-down: mark departed.
		TroopUnitRepository.update_unit(unit_id, {
			"count": 0,
			"status": "departed",
			"departure_kind": "stood_down",
			"departure_calendar_day": calendar_day,
		})
	else:
		TroopUnitRepository.update_unit(unit_id, {"count": current_count - count})

	# 2. Increment available_tribal_warriors (capped at peasant_families - levied).
	if not domain_id.is_empty() and not domain.is_empty():
		var peasant_families: int = int(domain.get("peasant_families", 0))
		var pool_after: Dictionary = TribalWarriorRegistry.pool_for_domain(domain_id)
		var new_available_proposed: int = int(pool_after.get("available", 0)) + count
		var cap: int = peasant_families - int(pool_after.get("levied", 0))
		var new_available: int = maxi(0, mini(new_available_proposed, cap))
		CampaignRepository.db.query_with_bindings("""
			UPDATE domains
			SET available_tribal_warriors = ?, updated_at = datetime('now')
			WHERE id = ?
		""", [new_available, domain_id])

	# 3. Departure log.
	if not campaign_id.is_empty() and not domain_id.is_empty():
		DepartureLogRecorder.record(
			campaign_id, domain_id, calendar_day,
			"tribal_warriors_stood_down",
			"Stood down %d tribal warrior%s" % [count, "" if count == 1 else "s"],
			{
				"count": count,
				"troop_unit_id": unit_id,
				"stood_down_by_character_id": character_id,
				"unit_fully_disbanded": count >= current_count,
			})

	# 4. EventBus.
	if EventBus.has_signal("tribal_warriors_stood_down"):
		EventBus.emit_signal("tribal_warriors_stood_down",
			domain_id, character_id, unit_id, count)

	return {
		"summary": "%d tribal warriors stood down" % count,
		"count": count,
		"unit_disbanded": count >= current_count,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	return Timekeeping.get_calendar_day()
