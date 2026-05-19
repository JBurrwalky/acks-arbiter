class_name ArmyRepository
extends RefCounted

## CRUD service for the Phase 6A army-warfare tables (migrations 070-074):
##   armies                    (070)
##   army_officers             (071)
##   army_unit_assignments     (072)
##   army_supply_state         (073)
##   reconnaissance_cooldowns  (074)
##
## Per gdd-army-warfare.md §2 — IDs are TEXT (UUID-like) via
## CampaignRepository.generate_id(). The GDD's INTEGER PRIMARY KEY AUTOINCREMENT
## spec is overridden to match the codebase convention (every other table uses
## TEXT IDs).
##
## Mutating callers should pre-build a Dictionary of fields and pass it to
## create_*. update_* whitelists field names. Lookups are read-only and return
## duplicated Dictionaries so callers cannot accidentally mutate the cache.

const _ARMY_UPDATE_FIELDS := [
	"name", "political_owner_id", "command_character_id", "state",
	"map_id", "hex_q", "hex_r", "garrison_stronghold_id",
	"formed_calendar_day", "disbanded_calendar_day",
	"unit_scale", "strategic_stance",
	"forced_march_bonus_expires_leg_id", "consecutive_marching_days",
	"last_returned_to_garrison_day_index", "daily_penalty_state",
	"rng_seed_stream", "notes",
]

const _OFFICER_UPDATE_FIELDS := [
	"rank", "parent_officer_id",
	"leadership_ability", "strategic_ability", "morale_modifier",
	"derivation_source", "monthly_wage_cp",
	"appointed_calendar_day", "removed_calendar_day",
]

const _ASSIGNMENT_UPDATE_FIELDS := [
	"role", "parent_officer_id",
	"assigned_calendar_day", "released_calendar_day",
	"release_reason", "destination",
]

const _SUPPLY_UPDATE_FIELDS := [
	"supply_base_stronghold_id", "supply_line_status",
	"weekly_supply_cost_cp", "current_stockpile_cp",
	"supply_line_weighted_hexes", "last_supply_check_calendar_day",
	"consecutive_unsupplied_weeks",
	"requisition_cooldowns_json", "partial_supply_priority_json",
]


# ---------------------------------------------------------------------------
# armies (migration 070)
# ---------------------------------------------------------------------------

static func create_army(data: Dictionary) -> String:
	var id: String = String(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO armies
			(id, campaign_id, name, political_owner_id, command_character_id,
			 state, map_id, hex_q, hex_r, garrison_stronghold_id,
			 formed_calendar_day, disbanded_calendar_day,
			 unit_scale, strategic_stance,
			 forced_march_bonus_expires_leg_id, consecutive_marching_days,
			 last_returned_to_garrison_day_index, daily_penalty_state,
			 rng_seed_stream, notes)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		String(data.get("campaign_id", "")),
		String(data.get("name", "")),
		String(data.get("political_owner_id", "")),
		String(data.get("command_character_id", "")),
		String(data.get("state", "assembling")),
		_null_or_string(data.get("map_id", null)),
		data.get("hex_q", null),
		data.get("hex_r", null),
		_null_or_string(data.get("garrison_stronghold_id", null)),
		int(data.get("formed_calendar_day", 0)),
		int(data.get("disbanded_calendar_day", 0)),
		String(data.get("unit_scale", "platoon")),
		String(data.get("strategic_stance", "defensive")),
		String(data.get("forced_march_bonus_expires_leg_id", "")),
		int(data.get("consecutive_marching_days", 0)),
		int(data.get("last_returned_to_garrison_day_index", 0)),
		String(data.get("daily_penalty_state", "{}")),
		int(data.get("rng_seed_stream", 0)),
		String(data.get("notes", "")),
	]):
		push_error("ArmyRepository.create_army failed: name=%s" % data.get("name", "?"))
		return ""
	return id


static func get_army(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM armies WHERE id = ?", [id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func update_army(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _ARMY_UPDATE_FIELDS.has(key):
			push_error("ArmyRepository.update_army: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE armies SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func list_armies_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM armies
		WHERE campaign_id = ? AND state != 'disbanded'
		ORDER BY formed_calendar_day, name
	""", [campaign_id])
	return CampaignRepository.db.query_result.duplicate()


static func list_armies_at_hex(map_id: String, hex_q: int, hex_r: int) -> Array:
	if map_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM armies
		WHERE map_id = ? AND hex_q = ? AND hex_r = ? AND state != 'disbanded'
		ORDER BY formed_calendar_day
	""", [map_id, hex_q, hex_r])
	return CampaignRepository.db.query_result.duplicate()


static func list_armies_for_owner(political_owner_id: String) -> Array:
	if political_owner_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM armies
		WHERE political_owner_id = ? AND state != 'disbanded'
		ORDER BY formed_calendar_day
	""", [political_owner_id])
	return CampaignRepository.db.query_result.duplicate()


static func list_armies_under_command(command_character_id: String) -> Array:
	if command_character_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM armies
		WHERE command_character_id = ? AND state != 'disbanded'
		ORDER BY formed_calendar_day
	""", [command_character_id])
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# army_officers (migration 071)
# ---------------------------------------------------------------------------

static func create_officer(data: Dictionary) -> String:
	var id: String = String(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO army_officers
			(id, army_id, character_id, rank, parent_officer_id,
			 leadership_ability, strategic_ability, morale_modifier,
			 derivation_source, monthly_wage_cp,
			 appointed_calendar_day, removed_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		String(data.get("army_id", "")),
		String(data.get("character_id", "")),
		String(data.get("rank", "lieutenant")),
		_null_or_string(data.get("parent_officer_id", null)),
		int(data.get("leadership_ability", 4)),
		int(data.get("strategic_ability", 0)),
		int(data.get("morale_modifier", 0)),
		String(data.get("derivation_source", "pc")),
		int(data.get("monthly_wage_cp", 0)),
		int(data.get("appointed_calendar_day", 0)),
		int(data.get("removed_calendar_day", 0)),
	]):
		push_error("ArmyRepository.create_officer failed: army=%s rank=%s" % [
			data.get("army_id", "?"), data.get("rank", "?"),
		])
		return ""
	return id


static func get_officer(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM army_officers WHERE id = ?", [id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func update_officer(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _OFFICER_UPDATE_FIELDS.has(key):
			push_error("ArmyRepository.update_officer: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE army_officers SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func list_officers_for_army(army_id: String, include_removed: bool = false) -> Array:
	if army_id.is_empty():
		return []
	if include_removed:
		CampaignRepository.db.query_with_bindings("""
			SELECT * FROM army_officers
			WHERE army_id = ?
			ORDER BY appointed_calendar_day, rank
		""", [army_id])
	else:
		CampaignRepository.db.query_with_bindings("""
			SELECT * FROM army_officers
			WHERE army_id = ? AND removed_calendar_day = 0
			ORDER BY appointed_calendar_day, rank
		""", [army_id])
	return CampaignRepository.db.query_result.duplicate()


static func get_army_leader(army_id: String) -> Dictionary:
	if army_id.is_empty():
		return {}
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM army_officers
		WHERE army_id = ? AND rank = 'army_leader' AND removed_calendar_day = 0
		LIMIT 1
	""", [army_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


# ---------------------------------------------------------------------------
# army_unit_assignments (migration 072)
# ---------------------------------------------------------------------------

static func create_assignment(data: Dictionary) -> String:
	var id: String = String(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO army_unit_assignments
			(id, army_id, troop_unit_id, parent_officer_id, role,
			 assigned_calendar_day, released_calendar_day,
			 release_reason, destination)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		String(data.get("army_id", "")),
		String(data.get("troop_unit_id", "")),
		String(data.get("parent_officer_id", "")),
		String(data.get("role", "line")),
		int(data.get("assigned_calendar_day", 0)),
		int(data.get("released_calendar_day", 0)),
		String(data.get("release_reason", "")),
		String(data.get("destination", "")),
	]):
		push_error("ArmyRepository.create_assignment failed: army=%s unit=%s" % [
			data.get("army_id", "?"), data.get("troop_unit_id", "?"),
		])
		return ""
	return id


static func update_assignment(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _ASSIGNMENT_UPDATE_FIELDS.has(key):
			push_error("ArmyRepository.update_assignment: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE army_unit_assignments SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func list_active_assignments_for_army(army_id: String) -> Array:
	if army_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM army_unit_assignments
		WHERE army_id = ? AND released_calendar_day = 0
		ORDER BY assigned_calendar_day, role
	""", [army_id])
	return CampaignRepository.db.query_result.duplicate()


static func get_active_assignment_for_unit(troop_unit_id: String) -> Dictionary:
	if troop_unit_id.is_empty():
		return {}
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM army_unit_assignments
		WHERE troop_unit_id = ? AND released_calendar_day = 0
		LIMIT 1
	""", [troop_unit_id])
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


# ---------------------------------------------------------------------------
# army_supply_state (migration 073)
# ---------------------------------------------------------------------------

static func create_supply_state(data: Dictionary) -> bool:
	var army_id: String = String(data.get("army_id", ""))
	if army_id.is_empty():
		push_error("ArmyRepository.create_supply_state: army_id is required")
		return false
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO army_supply_state
			(army_id, supply_base_stronghold_id, supply_line_status,
			 weekly_supply_cost_cp, current_stockpile_cp,
			 supply_line_weighted_hexes, last_supply_check_calendar_day,
			 consecutive_unsupplied_weeks,
			 requisition_cooldowns_json, partial_supply_priority_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		army_id,
		_null_or_string(data.get("supply_base_stronghold_id", null)),
		String(data.get("supply_line_status", "out_of_supply_no_base")),
		int(data.get("weekly_supply_cost_cp", 0)),
		int(data.get("current_stockpile_cp", 0)),
		int(data.get("supply_line_weighted_hexes", 0)),
		int(data.get("last_supply_check_calendar_day", 0)),
		int(data.get("consecutive_unsupplied_weeks", 0)),
		String(data.get("requisition_cooldowns_json", "{}")),
		String(data.get("partial_supply_priority_json", "[]")),
	]):
		push_error("ArmyRepository.create_supply_state failed: army=%s" % army_id)
		return false
	return true


static func get_supply_state(army_id: String) -> Dictionary:
	if army_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM army_supply_state WHERE army_id = ?", [army_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func update_supply_state(army_id: String, fields: Dictionary) -> bool:
	if army_id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _SUPPLY_UPDATE_FIELDS.has(key):
			push_error("ArmyRepository.update_supply_state: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(army_id)
	var sql := "UPDATE army_supply_state SET %s WHERE army_id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


# ---------------------------------------------------------------------------
# reconnaissance_cooldowns (migration 074)
# ---------------------------------------------------------------------------

static func upsert_recon_cooldown(observer_army_id: String, observed_army_id: String, calendar_day: int, result: String) -> bool:
	if observer_army_id.is_empty() or observed_army_id.is_empty():
		return false
	# SQLite UPSERT (INSERT ... ON CONFLICT DO UPDATE).
	return CampaignRepository.db.query_with_bindings("""
		INSERT INTO reconnaissance_cooldowns
			(observer_army_id, observed_army_id, last_roll_calendar_day, last_result)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(observer_army_id, observed_army_id) DO UPDATE SET
			last_roll_calendar_day = excluded.last_roll_calendar_day,
			last_result = excluded.last_result
	""", [observer_army_id, observed_army_id, calendar_day, result])


static func get_recon_cooldown(observer_army_id: String, observed_army_id: String) -> Dictionary:
	if observer_army_id.is_empty() or observed_army_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM reconnaissance_cooldowns
		WHERE observer_army_id = ? AND observed_army_id = ?
	""", [observer_army_id, observed_army_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _null_or_string(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s
