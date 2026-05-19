class_name CallToArmsMuster
extends RefCounted

# NOTE: NOT named CallToArmsHandler — that class_name is taken by the Phase 3
# activity-executor stub at engine/subsystems/activities/handlers/call_to_arms.gd.
# This module (CallToArmsMuster) is the Phase 9C resolver that does the actual
# garrison aggregation + tranche scheduling + troop_units transfer; the existing
# activity-handler stub can be wired to call into us in a future polish session.

## Phase 9C — Call to Arms troop creation per RAW
## daw_armies_recruitment.xml §vassal_troops L656-702.
##
## When favors_duties_resolver lands a 'call_to_arms' duty, this handler:
##   1. Computes the vassal's realm garrison (vassal personal garrison +
##      sub-vassal garrisons recursively).
##   2. Determines target_total_units from realm garrison × magnitude_pct.
##   3. Determines period_unit (week/month/season) from vassal's title via
##      RealmTitleResolver.muster_period.
##   4. Creates the lord's army (or reuses one specified in payload).
##   5. Schedules three call_to_arms_tranche_arrival events:
##      - first  (½ ceil)        at issue + 1 period
##      - second (¼ floor min 1) at issue + 2 periods
##      - third  (remainder)     at issue + 3 periods
##   6. Persists call_to_arms_state row.
##
## On each tranche arrival: snapshots troop_units from vassal's garrison army
## to the lord's army (RAW L658: vassal's actual garrison mustered).
## On revocation: troops return to vassal's garrison.
##
## Public API:
##   issue_call(obligation_id, lord_id, vassal_id, calendar_day, magnitude_pct,
##              scheduler) -> call_to_arms_state_id
##   resolve_tranche_arrival(call_to_arms_state_id, tranche, calendar_day) -> Dictionary
##   resolve_revocation(call_to_arms_state_id, calendar_day) -> int
##   compute_realm_garrison_unit_count(vassal_id) -> int
##   muster_period_to_days(period_unit) -> int
##   tranche_size(target_total: int, tranche: int) -> int
##   compute_duty_count(magnitude_pct: int) -> int


# RAW L675-677 tranche distribution.
const TRANCHE_FIRST_FRACTION_NUMERATOR: int = 1
const TRANCHE_FIRST_FRACTION_DENOMINATOR: int = 2  # ½ rounded up
const TRANCHE_SECOND_FRACTION_NUMERATOR: int = 1
const TRANCHE_SECOND_FRACTION_DENOMINATOR: int = 4  # ¼ rounded down, min 1
const TRANCHE_SECOND_MIN: int = 1

# Period unit → game days conversion (per RAW vassal_troops_by_realm_size table).
const PERIOD_DAYS_WEEK: int = 7
const PERIOD_DAYS_MONTH: int = 28      # matches Timekeeping.DAYS_PER_MONTH
const PERIOD_DAYS_SEASON: int = 91     # one ACKS season = 13 weeks


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Issue a call to arms. Creates the call_to_arms_state row and schedules the
## three tranche arrival events. Returns the call_to_arms_state_id.
##
## Parameters:
##   obligation_id   — the vassal_obligations row that issued the call
##   lord_id         — the lord (the army's command_character_id)
##   vassal_id       — the vassal (whose garrison provides troops)
##   calendar_day    — issue day
##   magnitude_pct   — % of vassal realm garrison being called (50, 100, etc.)
##   scheduler       — EventScheduler instance; null in test mode (no events scheduled)
static func issue_call(
	obligation_id: String,
	lord_id: String,
	vassal_id: String,
	calendar_day: int,
	magnitude_pct: int = 50,
	scheduler = null,
	lord_army_id_override: String = ""
) -> String:
	if obligation_id.is_empty() or lord_id.is_empty() or vassal_id.is_empty():
		return ""
	# 1. Compute vassal's realm garrison.
	var realm_garrison: int = compute_realm_garrison_unit_count(vassal_id)
	if realm_garrison <= 0:
		# Vassal has no garrison; no troops to call.
		return ""
	# 2. Compute target_total_units = ceil(realm_garrison × magnitude_pct / 100).
	var target_total: int = int(ceil(float(realm_garrison) * float(magnitude_pct) / 100.0))
	target_total = clampi(target_total, 0, realm_garrison)
	# 3. Determine period from vassal's title.
	var vassal_title: String = _get_vassal_title(vassal_id)
	var period_unit: String = RealmTitleResolver.muster_period(vassal_title).to_lower()
	if period_unit == "week" or period_unit == "month" or period_unit == "season":
		pass
	else:
		period_unit = "week"  # safe fallback for unknown titles
	var period_days: int = muster_period_to_days(period_unit)
	# 4. Locate or create lord's army.
	var lord_army_id: String = lord_army_id_override
	if lord_army_id.is_empty():
		lord_army_id = _create_lord_call_army(lord_id, vassal_id, calendar_day)
	if lord_army_id.is_empty():
		return ""
	# 5. Persist call_to_arms_state row.
	var state_id: String = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO call_to_arms_state
			(id, obligation_id, lord_army_id, vassal_character_id,
			 issued_calendar_day, period_unit, period_days, target_total_units,
			 payload_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		state_id, obligation_id, lord_army_id, vassal_id,
		calendar_day, period_unit, period_days, target_total,
		JSON.stringify({"magnitude_pct": magnitude_pct, "realm_garrison_at_issue": realm_garrison}),
	]):
		push_error("CallToArmsHandler.issue_call: failed to insert call_to_arms_state")
		return ""
	# 6. Schedule three tranche events.
	if scheduler != null:
		for tranche in [1, 2, 3]:
			scheduler.schedule_at(
				calendar_day + period_days * tranche,
				"call_to_arms_tranche_arrival",
				state_id,
				{"call_to_arms_state_id": state_id, "tranche": tranche},
				ScheduledEvent.PRIORITY_CONSEQUENCE
			)
	if EventBus.has_signal("call_to_arms_issued"):
		EventBus.emit_signal("call_to_arms_issued", obligation_id, lord_army_id, target_total)
	return state_id


## Resolve a tranche arrival. Snapshots troop_units from vassal's garrison
## army to the lord's army.
##
## Returns: {tranche, units_transferred, units_arrived_so_far, is_completed,
##           lord_army_id, transferred_unit_ids}
static func resolve_tranche_arrival(
	call_to_arms_state_id: String,
	tranche: int,
	calendar_day: int
) -> Dictionary:
	var result: Dictionary = {
		"tranche": tranche,
		"units_transferred": 0,
		"units_arrived_so_far": 0,
		"is_completed": false,
		"lord_army_id": "",
		"transferred_unit_ids": [],
	}
	if call_to_arms_state_id.is_empty() or tranche < 1 or tranche > 3:
		return result
	var state: Dictionary = _get_state(call_to_arms_state_id)
	if state.is_empty():
		return result
	if int(state.get("revoked_calendar_day", 0)) > 0 or int(state.get("is_completed", 0)) == 1:
		return result
	var target_total: int = int(state.get("target_total_units", 0))
	var vassal_id: String = String(state.get("vassal_character_id", ""))
	var lord_army_id: String = String(state.get("lord_army_id", ""))
	result.lord_army_id = lord_army_id
	# Compute target count for THIS tranche.
	var target_for_tranche: int = tranche_size(target_total, tranche)
	# Pull eligible units (vassal's active garrison troop_units, sorted by BR DESC).
	var eligible: Array = _list_vassal_garrison_units(vassal_id)
	# Skip already-transferred units (in case of multiple tranches).
	var already_transferred_ids: Array = _list_units_transferred_for_call(call_to_arms_state_id)
	var available: Array = []
	for u in eligible:
		var uid: String = String(u.get("id", ""))
		if not already_transferred_ids.has(uid):
			available.append(u)
	# Snapshot first N units.
	var transferred: Array = []
	for i in range(mini(target_for_tranche, available.size())):
		var u: Dictionary = available[i]
		var uid: String = String(u.get("id", ""))
		# Update army_unit_assignments to point at lord's army.
		# In v1 we release from the garrison army and create a new assignment to
		# the lord's army. The troop_units row identity is preserved.
		_transfer_troop_unit_to_army(uid, lord_army_id, calendar_day)
		transferred.append(uid)
	result.units_transferred = transferred.size()
	result.transferred_unit_ids = transferred
	# Update call_to_arms_state tally.
	var col: String = "units_arrived_first_tranche" if tranche == 1 \
		else ("units_arrived_second_tranche" if tranche == 2 else "units_arrived_third_tranche")
	CampaignRepository.db.query_with_bindings(
		"UPDATE call_to_arms_state SET %s = ?, updated_at = datetime('now') WHERE id = ?" % col,
		[transferred.size(), call_to_arms_state_id]
	)
	# If third tranche, mark complete.
	if tranche == 3:
		CampaignRepository.db.query_with_bindings(
			"UPDATE call_to_arms_state SET is_completed = 1, updated_at = datetime('now') WHERE id = ?",
			[call_to_arms_state_id]
		)
		result.is_completed = true
		if EventBus.has_signal("call_to_arms_fully_arrived"):
			EventBus.emit_signal("call_to_arms_fully_arrived", call_to_arms_state_id)
	# units_arrived_so_far across all tranches.
	var refreshed: Dictionary = _get_state(call_to_arms_state_id)
	result.units_arrived_so_far = int(refreshed.get("units_arrived_first_tranche", 0)) \
		+ int(refreshed.get("units_arrived_second_tranche", 0)) \
		+ int(refreshed.get("units_arrived_third_tranche", 0))
	if EventBus.has_signal("call_to_arms_tranche_arrived"):
		EventBus.emit_signal("call_to_arms_tranche_arrived",
			call_to_arms_state_id, tranche, transferred.size())
	return result


## Resolve revocation: troops return to the vassal's garrison.
##
## Returns the count of units returned.
static func resolve_revocation(call_to_arms_state_id: String, calendar_day: int) -> int:
	if call_to_arms_state_id.is_empty():
		return 0
	var state: Dictionary = _get_state(call_to_arms_state_id)
	if state.is_empty():
		return 0
	if int(state.get("revoked_calendar_day", 0)) > 0:
		return 0
	var lord_army_id: String = String(state.get("lord_army_id", ""))
	var vassal_id: String = String(state.get("vassal_character_id", ""))
	# Find the vassal's primary garrison army.
	var garrison_army_id: String = _vassal_garrison_army_id(vassal_id)
	if garrison_army_id.is_empty():
		# No garrison army to return to — units stay assigned to the lord, log a warning.
		push_warning("CallToArmsHandler.resolve_revocation: vassal %s has no garrison army to receive returned troops" % vassal_id)
	# Pull all troop_units currently assigned to lord_army_id that came from
	# the call (filter via call_to_arms_state's transferred ids set).
	var transferred_ids: Array = _list_units_transferred_for_call(call_to_arms_state_id)
	var returned: int = 0
	for uid in transferred_ids:
		# Verify the unit is still assigned to the lord (might have been killed/disbanded).
		if not _unit_currently_assigned_to_army(uid, lord_army_id):
			continue
		if not garrison_army_id.is_empty():
			_transfer_troop_unit_to_army(uid, garrison_army_id, calendar_day)
		returned += 1
	CampaignRepository.db.query_with_bindings(
		"UPDATE call_to_arms_state SET revoked_calendar_day = ?, updated_at = datetime('now') WHERE id = ?",
		[calendar_day, call_to_arms_state_id]
	)
	if EventBus.has_signal("call_to_arms_revoked"):
		EventBus.emit_signal("call_to_arms_revoked", call_to_arms_state_id, returned)
	return returned


## Compute the realm garrison unit count for a vassal.
## RAW L661: "Calls to arms are based on the garrison of the vassal's realm,
## not the vassal's personal domain."
##
## Aggregates the vassal's personal garrison + all sub-vassals' garrisons
## recursively. Counted as troop_units rows assigned to garrison armies for
## the vassal's domain or any sub-vassal's domain.
static func compute_realm_garrison_unit_count(vassal_id: String) -> int:
	if vassal_id.is_empty():
		return 0
	# Walk down: vassal_id + all transitive sub-vassals.
	var realm_character_ids: Array = [vassal_id]
	_gather_sub_vassals_recursive(vassal_id, realm_character_ids, 0)
	if realm_character_ids.is_empty():
		return 0
	# Count active troop_unit assignments to garrison armies owned by any
	# character in the realm.
	var placeholders: PackedStringArray = []
	for _i in range(realm_character_ids.size()):
		placeholders.append("?")
	var sql := """
		SELECT COUNT(*) AS n
		FROM army_unit_assignments aua
		JOIN armies a ON a.id = aua.army_id
		JOIN troop_units tu ON tu.id = aua.troop_unit_id
		WHERE a.political_owner_id IN (%s)
		      AND aua.released_calendar_day = 0
		      AND tu.status = 'active'
		      AND tu.assignment_kind = 'garrison'
	""" % ", ".join(placeholders)
	if not CampaignRepository.db.query_with_bindings(sql, realm_character_ids):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("n", 0))


## Convert period unit string → integer game days.
static func muster_period_to_days(period_unit: String) -> int:
	match period_unit.to_lower():
		"week": return PERIOD_DAYS_WEEK
		"month": return PERIOD_DAYS_MONTH
		"season": return PERIOD_DAYS_SEASON
		_: return PERIOD_DAYS_WEEK


## Compute the size of a specific tranche per RAW L675-677.
##   tranche 1: ceil(target / 2)
##   tranche 2: floor(target / 4), min 1 if target > 0
##   tranche 3: remainder
static func tranche_size(target_total: int, tranche: int) -> int:
	if target_total <= 0:
		return 0
	var first_size: int = int(ceil(float(target_total) / 2.0))
	var second_size: int = maxi(int(floor(float(target_total) / 4.0)), TRANCHE_SECOND_MIN)
	if tranche == 1:
		return first_size
	if tranche == 2:
		return second_size
	if tranche == 3:
		return maxi(0, target_total - first_size - second_size)
	return 0


## Compute duty count from magnitude_pct.
## RAW L660: full garrison = 2 duties.
## v1 simple linear interpretation: <100% = 1 duty, ≥100% = 2 duties.
## (Future polish could allow fractional duty counts via banker's rounding.)
static func compute_duty_count(magnitude_pct: int) -> int:
	return 2 if magnitude_pct >= 100 else 1


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _get_state(state_id: String) -> Dictionary:
	if state_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM call_to_arms_state WHERE id = ?", [state_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _get_vassal_title(vassal_id: String) -> String:
	## Look up the vassal's domain → personal_families + realm aggregation,
	## then call RealmTitleResolver.resolve_title.
	if vassal_id.is_empty():
		return "Baron"
	var aggregated: Dictionary = RealmAggregator.aggregate(vassal_id)
	var personal: int = int(aggregated.get("personal_families", 0))
	var realm: int = int(aggregated.get("all_realm_families", personal))
	# Count of domains ruled (vassal's own domain + sub-vassal domains).
	var domains_ruled: int = int(aggregated.get("direct_vassal_count", 0)) + 1
	return RealmTitleResolver.resolve_title(personal, domains_ruled, realm)


static func _create_lord_call_army(lord_id: String, vassal_id: String, calendar_day: int) -> String:
	## Create a fresh army to receive the called troops, owned and commanded
	## by the lord. v1 default: state='assembling' until first tranche arrives.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT campaign_id FROM characters WHERE id = ?", [lord_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	var campaign_id: String = String(CampaignRepository.db.query_result[0].get("campaign_id", ""))
	return ArmyRepository.create_army({
		"campaign_id": campaign_id,
		"name": "Call to Arms (vassal %s)" % vassal_id.substr(0, 8),
		"political_owner_id": lord_id,
		"command_character_id": lord_id,
		"state": "assembling",
		"formed_calendar_day": calendar_day,
	})


static func _list_vassal_garrison_units(vassal_id: String) -> Array:
	## Pull ALL active garrison troop_units across the vassal's realm
	## (personal + sub-vassals), sorted by battle_rating DESC so the strongest
	## troops are mustered first.
	var realm_ids: Array = [vassal_id]
	_gather_sub_vassals_recursive(vassal_id, realm_ids, 0)
	if realm_ids.is_empty():
		return []
	var placeholders: PackedStringArray = []
	for _i in range(realm_ids.size()):
		placeholders.append("?")
	var sql := """
		SELECT tu.id, tu.battle_rating, aua.id AS assignment_id, aua.army_id
		FROM army_unit_assignments aua
		JOIN armies a ON a.id = aua.army_id
		JOIN troop_units tu ON tu.id = aua.troop_unit_id
		WHERE a.political_owner_id IN (%s)
		      AND aua.released_calendar_day = 0
		      AND tu.status = 'active'
		      AND tu.assignment_kind = 'garrison'
		ORDER BY tu.battle_rating DESC
	""" % ", ".join(placeholders)
	if not CampaignRepository.db.query_with_bindings(sql, realm_ids):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func _list_units_transferred_for_call(state_id: String) -> Array:
	## Read transferred_unit_ids from the call_to_arms_state payload_json.
	var state: Dictionary = _get_state(state_id)
	if state.is_empty():
		return []
	var raw: String = String(state.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return []
	var d: Dictionary = parsed
	var ids: Variant = d.get("transferred_unit_ids", [])
	return ids if (ids is Array) else []


static func _transfer_troop_unit_to_army(troop_unit_id: String, target_army_id: String, calendar_day: int) -> void:
	## Release current assignment + create new assignment to target army.
	## In v1 we use a simple release+reassign pattern (preserves the troop_units
	## row identity; assignment history is captured by the released_calendar_day).
	if troop_unit_id.is_empty() or target_army_id.is_empty():
		return
	# Release the current active assignment.
	CampaignRepository.db.query_with_bindings("""
		UPDATE army_unit_assignments
		SET released_calendar_day = ?, release_reason = 'transfer',
		    destination = ?
		WHERE troop_unit_id = ? AND released_calendar_day = 0
	""", [calendar_day, target_army_id, troop_unit_id])
	# Create new assignment to target army (parent_officer_id is the army's first officer
	# or NULL — v1 simplification: use the army's command_character_id reference).
	# army_unit_assignments.parent_officer_id is NOT NULL in the schema; for v1 we
	# pick the first officer of the target army or fall back to the command_character_id
	# treated as a virtual officer (a future migration could relax this constraint).
	var parent_officer_id: String = _first_officer_id_for_army(target_army_id)
	if parent_officer_id.is_empty():
		# No officers yet — the schema requires a non-empty parent_officer_id, so we
		# create an officer record on the target army for the command character.
		parent_officer_id = _ensure_command_officer(target_army_id, calendar_day)
	if parent_officer_id.is_empty():
		push_warning("CallToArmsHandler._transfer_troop_unit_to_army: no parent_officer_id available for army %s" % target_army_id)
		return
	var new_id: String = CampaignRepository.generate_id()
	CampaignRepository.db.query_with_bindings("""
		INSERT INTO army_unit_assignments
			(id, army_id, troop_unit_id, parent_officer_id, role,
			 assigned_calendar_day, released_calendar_day, release_reason, destination)
		VALUES (?, ?, ?, ?, 'line', ?, 0, '', '')
	""", [new_id, target_army_id, troop_unit_id, parent_officer_id, calendar_day])
	# Update assignment_kind on troop_units to 'on_campaign' (no longer garrisoned).
	CampaignRepository.db.query_with_bindings(
		"UPDATE troop_units SET assignment_kind = 'on_campaign' WHERE id = ?",
		[troop_unit_id]
	)
	# Append the unit id to the call_to_arms_state's transferred list (for revocation tracking).
	# This requires the caller to know the state id; we look it up by army.
	_append_transferred_unit(target_army_id, troop_unit_id)


static func _first_officer_id_for_army(army_id: String) -> String:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM army_officers WHERE army_id = ? LIMIT 1", [army_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _ensure_command_officer(army_id: String, calendar_day: int) -> String:
	## Create a placeholder army_officers row for the army's command character
	## so troop_unit assignments have a parent_officer_id. v1 simplification.
	var army: Dictionary = ArmyRepository.get_army(army_id)
	if army.is_empty():
		return ""
	var command_id: String = String(army.get("command_character_id", ""))
	if command_id.is_empty():
		return ""
	var officer_id: String = CampaignRepository.generate_id()
	# Schema columns per migration 071: rank (not role), leadership_ability,
	# derivation_source, monthly_wage_cp.
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO army_officers
			(id, army_id, character_id, rank, leadership_ability, strategic_ability,
			 morale_modifier, derivation_source, monthly_wage_cp,
			 appointed_calendar_day)
		VALUES (?, ?, ?, 'army_leader', 4, 0, 0, 'pc', 0, ?)
	""", [officer_id, army_id, command_id, calendar_day]):
		return ""
	return officer_id


static func _append_transferred_unit(target_army_id: String, troop_unit_id: String) -> void:
	## Locate the call_to_arms_state whose lord_army_id matches and append the unit.
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id, payload_json FROM call_to_arms_state WHERE lord_army_id = ? AND revoked_calendar_day = 0 LIMIT 1",
		[target_army_id]
	):
		return
	if CampaignRepository.db.query_result.is_empty():
		return
	var row: Dictionary = CampaignRepository.db.query_result[0]
	var state_id: String = String(row.get("id", ""))
	var raw: String = String(row.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	var d: Dictionary = parsed if (parsed is Dictionary) else {}
	var ids: Array = d.get("transferred_unit_ids", []) if d.has("transferred_unit_ids") else []
	if not ids.has(troop_unit_id):
		ids.append(troop_unit_id)
		d["transferred_unit_ids"] = ids
		CampaignRepository.db.query_with_bindings(
			"UPDATE call_to_arms_state SET payload_json = ? WHERE id = ?",
			[JSON.stringify(d), state_id]
		)


static func _unit_currently_assigned_to_army(troop_unit_id: String, army_id: String) -> bool:
	if not CampaignRepository.db.query_with_bindings("""
		SELECT 1 FROM army_unit_assignments
		WHERE troop_unit_id = ? AND army_id = ? AND released_calendar_day = 0
		LIMIT 1
	""", [troop_unit_id, army_id]):
		return false
	return not CampaignRepository.db.query_result.is_empty()


static func _vassal_garrison_army_id(vassal_id: String) -> String:
	## Return the FIRST garrison-tied army owned by the vassal.
	if not CampaignRepository.db.query_with_bindings("""
		SELECT id FROM armies
		WHERE political_owner_id = ? AND state IN ('encamped', 'assembling')
		      AND garrison_stronghold_id IS NOT NULL
		ORDER BY formed_calendar_day ASC LIMIT 1
	""", [vassal_id]):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _gather_sub_vassals_recursive(parent_id: String, accumulator: Array, depth: int) -> void:
	## Walk vassal_assignments downward from parent_id. Cycle/depth guarded.
	if depth >= 8:
		return
	if not CampaignRepository.db.query_with_bindings("""
		SELECT vassal_character_id FROM vassal_assignments
		WHERE liege_character_id = ? AND status = 'active'
	""", [parent_id]):
		return
	var ids: Array = CampaignRepository.db.query_result.duplicate()
	for row in ids:
		var sub: String = String(row.get("vassal_character_id", ""))
		if sub.is_empty() or accumulator.has(sub):
			continue
		accumulator.append(sub)
		_gather_sub_vassals_recursive(sub, accumulator, depth + 1)
