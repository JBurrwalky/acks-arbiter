class_name BattleRepository
extends RefCounted

## CRUD service for the Phase 6B battle tables (migrations 075-077):
##   field_battles            (075)
##   battle_unit_states       (076)
##   battle_log               (077)
##
## Pattern matches ArmyRepository: TEXT IDs via CampaignRepository.generate_id(),
## whitelisted UPDATE field arrays, duplicated Dictionary returns.
##
## battle_log inserts auto-allocate the next sequence_number per battle.

const _BATTLE_UPDATE_FIELDS := [
	"map_id", "hex_q", "hex_r",
	"terrain_type", "starting_bpc", "current_bpc", "current_phase",
	"battle_turn_number",
	"attacker_terrain_advantage", "defender_terrain_advantage",
	"attacker_surprised", "defender_surprised",
	"attacker_choice", "defender_choice",
	"outcome", "started_calendar_day", "ended_calendar_day",
	"is_player_involved", "weather_condition", "rng_seed",
]

const _UNIT_STATE_UPDATE_FIELDS := [
	"zone", "status",
	"br_at_battle_start", "br_current",
	"hits_absorbed_this_phase", "morale_state_modifier",
	"parent_officer_id",
]


# ---------------------------------------------------------------------------
# field_battles (075)
# ---------------------------------------------------------------------------

static func create_battle(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO field_battles
			(id, campaign_id, map_id, hex_q, hex_r,
			 attacker_army_id, defender_army_id,
			 terrain_type, starting_bpc, current_bpc, current_phase,
			 battle_turn_number,
			 attacker_terrain_advantage, defender_terrain_advantage,
			 attacker_surprised, defender_surprised,
			 attacker_choice, defender_choice,
			 outcome, started_calendar_day, ended_calendar_day,
			 is_player_involved, weather_condition, rng_seed)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("campaign_id", "")),
		_null_or_string(data.get("map_id", null)),
		int(data.get("hex_q", 0)),
		int(data.get("hex_r", 0)),
		str(data.get("attacker_army_id", "")),
		str(data.get("defender_army_id", "")),
		str(data.get("terrain_type", "clear_or_grass")),
		int(data.get("starting_bpc", 1)),
		int(data.get("current_bpc", 1)),
		str(data.get("current_phase", "missile")),
		int(data.get("battle_turn_number", 1)),
		str(data.get("attacker_terrain_advantage", "regular")),
		str(data.get("defender_terrain_advantage", "regular")),
		1 if bool(data.get("attacker_surprised", false)) else 0,
		1 if bool(data.get("defender_surprised", false)) else 0,
		str(data.get("attacker_choice", "")),
		str(data.get("defender_choice", "")),
		str(data.get("outcome", "")),
		int(data.get("started_calendar_day", 0)),
		int(data.get("ended_calendar_day", 0)),
		1 if bool(data.get("is_player_involved", false)) else 0,
		str(data.get("weather_condition", "calm")),
		int(data.get("rng_seed", 0)),
	]):
		push_error("BattleRepository.create_battle failed: attacker=%s defender=%s" % [
			data.get("attacker_army_id", "?"), data.get("defender_army_id", "?"),
		])
		return ""
	return id


static func get_battle(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM field_battles WHERE id = ?", [id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func update_battle(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _BATTLE_UPDATE_FIELDS.has(key):
			push_error("BattleRepository.update_battle: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE field_battles SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func list_active_battles_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM field_battles
		WHERE campaign_id = ? AND outcome = ''
		ORDER BY started_calendar_day
	""", [campaign_id])
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# battle_unit_states (076)
# ---------------------------------------------------------------------------

static func create_unit_state(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO battle_unit_states
			(id, battle_id, troop_unit_id, side, zone, status,
			 br_at_battle_start, br_current,
			 hits_absorbed_this_phase, morale_state_modifier,
			 parent_officer_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		str(data.get("battle_id", "")),
		str(data.get("troop_unit_id", "")),
		str(data.get("side", "attacker")),
		str(data.get("zone", "melee")),
		str(data.get("status", "engaged")),
		float(data.get("br_at_battle_start", 0.0)),
		float(data.get("br_current", data.get("br_at_battle_start", 0.0))),
		int(data.get("hits_absorbed_this_phase", 0)),
		int(data.get("morale_state_modifier", 0)),
		_null_or_string(data.get("parent_officer_id", null)),
	]):
		push_error("BattleRepository.create_unit_state failed: battle=%s unit=%s" % [
			data.get("battle_id", "?"), data.get("troop_unit_id", "?"),
		])
		return ""
	return id


static func update_unit_state(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _UNIT_STATE_UPDATE_FIELDS.has(key):
			push_error("BattleRepository.update_unit_state: rejected field '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE battle_unit_states SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func list_unit_states_for_battle(battle_id: String) -> Array:
	if battle_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM battle_unit_states
		WHERE battle_id = ?
		ORDER BY side, zone
	""", [battle_id])
	return CampaignRepository.db.query_result.duplicate()


static func list_unit_states_for_side(battle_id: String, side: String) -> Array:
	if battle_id.is_empty() or side.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM battle_unit_states
		WHERE battle_id = ? AND side = ?
		ORDER BY zone
	""", [battle_id, side])
	return CampaignRepository.db.query_result.duplicate()


static func list_unit_states_for_zone(battle_id: String, side: String, zone: String) -> Array:
	if battle_id.is_empty() or side.is_empty() or zone.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM battle_unit_states
		WHERE battle_id = ? AND side = ? AND zone = ?
	""", [battle_id, side, zone])
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# battle_log (077)
# ---------------------------------------------------------------------------

static func append_log(
	battle_id: String,
	event_type: String,
	turn_number: int,
	phase: String,
	bpc: int,
	side: String,
	payload: Dictionary,
	calendar_day: int = 0
) -> String:
	if battle_id.is_empty() or event_type.is_empty():
		return ""
	var id := CampaignRepository.generate_id()
	var seq := _next_sequence_number(battle_id)
	var payload_json := JSON.stringify(payload)
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO battle_log
			(id, battle_id, sequence_number, turn_number, phase, bpc_at_event,
			 event_type, side, payload_json, created_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [id, battle_id, seq, turn_number, phase, bpc, event_type, side, payload_json, calendar_day]):
		push_error("BattleRepository.append_log failed: battle=%s event=%s" % [battle_id, event_type])
		return ""
	if EventBus.has_signal("battle_log_appended"):
		EventBus.emit_signal("battle_log_appended", battle_id, id)
	return id


static func list_log_for_battle(battle_id: String) -> Array:
	if battle_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM battle_log
		WHERE battle_id = ?
		ORDER BY sequence_number
	""", [battle_id])
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

static func _next_sequence_number(battle_id: String) -> int:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT COALESCE(MAX(sequence_number), 0) AS s FROM battle_log WHERE battle_id = ?",
		[battle_id]):
		return 1
	if CampaignRepository.db.query_result.is_empty():
		return 1
	return int(CampaignRepository.db.query_result[0].get("s", 0)) + 1


static func _null_or_string(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s
