class_name SiegeRepository
extends RefCounted

## CRUD across the four Phase 9B siege tables: sieges (mig 084),
## siege_actions (mig 085), siege_artillery (mig 086), siege_mines (mig 087).
##
## Public API by table:
##
## sieges:
##   create_siege(payload: Dictionary) -> String
##   get_siege(siege_id: String) -> Dictionary
##   get_active_siege_for_stronghold(stronghold_id: String) -> Dictionary
##   list_active_sieges_for_campaign(campaign_id: String) -> Array
##   list_active_sieges_for_domain(domain_id: String) -> Array
##   update(siege_id: String, fields: Dictionary) -> bool   # whitelisted
##   conclude(siege_id: String, outcome: String, day: int) -> bool
##
## siege_actions:
##   append_action(siege_id, day, side, action_type, deltas: Dictionary,
##                 payload: Dictionary, related_battle_id: String = "") -> String
##   list_actions_for_siege(siege_id: String) -> Array
##   list_actions_since_day(siege_id: String, since_day: int) -> Array
##   list_actions_of_type(siege_id: String, action_type: String) -> Array
##
## siege_artillery:
##   add_artillery(siege_id, side, equipment_type, count: int) -> String
##   list_artillery(siege_id: String, side: String = "") -> Array
##   set_artillery_count(artillery_id: String, count: int) -> bool
##   mark_destroyed(artillery_id: String, destroyed_count: int) -> bool
##
## siege_mines:
##   create_mine(payload: Dictionary) -> String
##   get_mine(mine_id: String) -> Dictionary
##   list_active_mines(siege_id: String, side: String = "") -> Array
##   update_mine(mine_id: String, fields: Dictionary) -> bool   # whitelisted

const _SIEGE_UPDATE_FIELDS := [
	"current_phase", "current_shp", "damage_dealt_total", "damage_repaired_total",
	"breach_count", "is_blockaded", "blockade_method", "circumvallation_feet",
	"is_circumvallation_complete", "water_facing_pct", "stored_supplies_cp",
	"weeks_unsupplied", "starvation_penalty_stacks", "expected_end_calendar_day",
	"concluded_calendar_day", "outcome", "payload_json", "defending_army_id",
	"resolution_mode", "simplified_total_days", "simplified_site_modifier",
	"unit_capacity", "defender_posture",
]

const _MINE_UPDATE_FIELDS := [
	"workers_assigned", "cubic_feet_completed", "construction_rate_cp_per_day",
	"petard_damage", "is_detected", "detected_calendar_day", "is_completed",
	"is_destroyed_by_accident", "detonated_calendar_day", "countermine_target_id",
	"supervising_engineer_id",
]


# ---------------------------------------------------------------------------
# sieges CRUD
# ---------------------------------------------------------------------------

static func create_siege(payload: Dictionary) -> String:
	var id: String = String(payload.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO sieges
			(id, campaign_id, stronghold_id, domain_id,
			 besieging_army_id, defending_army_id,
			 map_id, hex_q, hex_r,
			 resolution_mode, current_phase,
			 starting_shp, current_shp, damage_dealt_total, damage_repaired_total,
			 breach_count, unit_capacity, material,
			 is_blockaded, blockade_method, circumvallation_feet,
			 is_circumvallation_complete, water_facing_pct,
			 stored_supplies_cp, weeks_unsupplied, starvation_penalty_stacks,
			 simplified_total_days, simplified_site_modifier,
			 started_calendar_day, expected_end_calendar_day, payload_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
		        ?, ?, ?, ?,
		        ?, ?, ?,
		        ?, ?, ?,
		        ?, ?,
		        ?, ?, ?,
		        ?, ?,
		        ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		String(payload.get("campaign_id", "")),
		String(payload.get("stronghold_id", "")),
		_null_or_string(payload.get("domain_id")),
		String(payload.get("besieging_army_id", "")),
		_null_or_string(payload.get("defending_army_id")),
		_null_or_string(payload.get("map_id")),
		_null_or_int(payload.get("hex_q")),
		_null_or_int(payload.get("hex_r")),
		String(payload.get("resolution_mode", "simplified")),
		String(payload.get("current_phase", "blockade")),
		int(payload.get("starting_shp", 0)),
		int(payload.get("current_shp", payload.get("starting_shp", 0))),
		int(payload.get("damage_dealt_total", 0)),
		int(payload.get("damage_repaired_total", 0)),
		int(payload.get("breach_count", 0)),
		int(payload.get("unit_capacity", 1)),
		String(payload.get("material", "stone")),
		1 if bool(payload.get("is_blockaded", false)) else 0,
		String(payload.get("blockade_method", "")),
		int(payload.get("circumvallation_feet", 0)),
		1 if bool(payload.get("is_circumvallation_complete", false)) else 0,
		int(payload.get("water_facing_pct", 0)),
		int(payload.get("stored_supplies_cp", 0)),
		int(payload.get("weeks_unsupplied", 0)),
		int(payload.get("starvation_penalty_stacks", 0)),
		int(payload.get("simplified_total_days", 0)),
		float(payload.get("simplified_site_modifier", 1.0)),
		int(payload.get("started_calendar_day", 0)),
		int(payload.get("expected_end_calendar_day", 0)),
		String(payload.get("payload_json", "{}")),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SiegeRepository.create_siege failed: stronghold=%s besieger=%s" % [
			payload.get("stronghold_id", ""), payload.get("besieging_army_id", "")])
		return ""
	return id


static func get_siege(siege_id: String) -> Dictionary:
	if siege_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM sieges WHERE id = ?", [siege_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func get_active_siege_for_stronghold(stronghold_id: String) -> Dictionary:
	if stronghold_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM sieges
		WHERE stronghold_id = ? AND current_phase != 'concluded'
		ORDER BY started_calendar_day DESC
		LIMIT 1
	""", [stronghold_id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_active_sieges_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM sieges
		WHERE campaign_id = ? AND current_phase != 'concluded'
		ORDER BY started_calendar_day
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_active_sieges_for_domain(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM sieges
		WHERE domain_id = ? AND current_phase != 'concluded'
		ORDER BY started_calendar_day
	""", [domain_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update(siege_id: String, fields: Dictionary) -> bool:
	if siege_id.is_empty() or fields.is_empty():
		return false
	var set_clauses: Array = []
	var values: Array = []
	for key in fields.keys():
		var k: String = String(key)
		if not _SIEGE_UPDATE_FIELDS.has(k):
			push_error("SiegeRepository.update: rejected non-whitelisted '%s'" % k)
			continue
		set_clauses.append("%s = ?" % k)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	values.append(siege_id)
	var sql := "UPDATE sieges SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func conclude(siege_id: String, outcome: String, day: int) -> bool:
	return update(siege_id, {
		"current_phase": "concluded",
		"outcome": outcome,
		"concluded_calendar_day": day,
	})


# ---------------------------------------------------------------------------
# siege_actions ledger
# ---------------------------------------------------------------------------

static func append_action(
	siege_id: String,
	calendar_day: int,
	actor_side: String,
	action_type: String,
	deltas: Dictionary = {},
	payload: Dictionary = {},
	related_battle_id: String = ""
) -> String:
	if siege_id.is_empty() or actor_side.is_empty() or action_type.is_empty():
		return ""
	var id: String = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO siege_actions
			(id, siege_id, calendar_day, actor_side, action_type,
			 shp_damage_dealt, shp_repaired, breaches_added,
			 supplies_delta_cp, related_battle_id, payload_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		siege_id,
		calendar_day,
		actor_side,
		action_type,
		int(deltas.get("shp_damage_dealt", 0)),
		int(deltas.get("shp_repaired", 0)),
		int(deltas.get("breaches_added", 0)),
		int(deltas.get("supplies_delta_cp", 0)),
		_null_or_string(related_battle_id),
		JSON.stringify(payload),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SiegeRepository.append_action failed: siege=%s type=%s" % [siege_id, action_type])
		return ""
	return id


static func list_actions_for_siege(siege_id: String) -> Array:
	if siege_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM siege_actions
		WHERE siege_id = ?
		ORDER BY calendar_day, created_at
	""", [siege_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_actions_since_day(siege_id: String, since_day: int) -> Array:
	if siege_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM siege_actions
		WHERE siege_id = ? AND calendar_day >= ?
		ORDER BY calendar_day, created_at
	""", [siege_id, since_day]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_actions_of_type(siege_id: String, action_type: String) -> Array:
	if siege_id.is_empty() or action_type.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM siege_actions
		WHERE siege_id = ? AND action_type = ?
		ORDER BY calendar_day, created_at
	""", [siege_id, action_type]):
		return []
	return CampaignRepository.db.query_result.duplicate()


# ---------------------------------------------------------------------------
# siege_artillery
# ---------------------------------------------------------------------------

static func add_artillery(siege_id: String, side: String, equipment_type: String, count: int = 1) -> String:
	if siege_id.is_empty() or side.is_empty() or equipment_type.is_empty():
		return ""
	var id: String = CampaignRepository.generate_id()
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO siege_artillery (id, siege_id, side, equipment_type, count)
		VALUES (?, ?, ?, ?, ?)
	""", [id, siege_id, side, equipment_type, maxi(1, count)]):
		push_error("SiegeRepository.add_artillery failed: siege=%s type=%s" % [siege_id, equipment_type])
		return ""
	# Phase 9C E3: besieger-side mantlets / galleries provide cover for besieger
	# artillery per RAW L236-237 (defender 5 misses if cover present).
	if side == "besieger" and (equipment_type == "movable_mantlet" or equipment_type == "movable_gallery"):
		_set_payload_flag(siege_id, "besieger_has_cover_for_artillery", true)
	return id


static func _set_payload_flag(siege_id: String, key: String, value: bool) -> void:
	## Read-modify-write a single boolean key on sieges.payload_json.
	var siege: Dictionary = get_siege(siege_id)
	if siege.is_empty():
		return
	var raw: String = String(siege.get("payload_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	var d: Dictionary = parsed if (parsed is Dictionary) else {}
	d[key] = value
	update(siege_id, {"payload_json": JSON.stringify(d)})


static func list_artillery(siege_id: String, side: String = "") -> Array:
	if siege_id.is_empty():
		return []
	if side.is_empty():
		if not CampaignRepository.db.query_with_bindings("""
			SELECT * FROM siege_artillery
			WHERE siege_id = ? AND is_destroyed = 0
			ORDER BY side, equipment_type
		""", [siege_id]):
			return []
	else:
		if not CampaignRepository.db.query_with_bindings("""
			SELECT * FROM siege_artillery
			WHERE siege_id = ? AND side = ? AND is_destroyed = 0
			ORDER BY equipment_type
		""", [siege_id, side]):
			return []
	return CampaignRepository.db.query_result.duplicate()


static func set_artillery_count(artillery_id: String, count: int) -> bool:
	if artillery_id.is_empty():
		return false
	if count <= 0:
		# Mark destroyed instead.
		return CampaignRepository.db.query_with_bindings(
			"UPDATE siege_artillery SET is_destroyed = 1, count = 0 WHERE id = ?",
			[artillery_id]
		)
	return CampaignRepository.db.query_with_bindings(
		"UPDATE siege_artillery SET count = ? WHERE id = ?",
		[count, artillery_id]
	)


static func mark_destroyed(artillery_id: String, destroyed_count: int) -> bool:
	if artillery_id.is_empty() or destroyed_count <= 0:
		return false
	if not CampaignRepository.db.query_with_bindings(
		"SELECT count FROM siege_artillery WHERE id = ?", [artillery_id]
	):
		return false
	if CampaignRepository.db.query_result.is_empty():
		return false
	var current_count: int = int(CampaignRepository.db.query_result[0].get("count", 0))
	var new_count: int = maxi(0, current_count - destroyed_count)
	return set_artillery_count(artillery_id, new_count)


# ---------------------------------------------------------------------------
# siege_mines
# ---------------------------------------------------------------------------

static func create_mine(payload: Dictionary) -> String:
	var id: String = String(payload.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO siege_mines
			(id, siege_id, side, supervising_engineer_id,
			 workers_assigned, cubic_feet_total, cubic_feet_completed,
			 construction_rate_cp_per_day, petard_damage,
			 countermine_target_id, started_calendar_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		String(payload.get("siege_id", "")),
		String(payload.get("side", "besieger")),
		_null_or_string(payload.get("supervising_engineer_id")),
		clampi(int(payload.get("workers_assigned", 0)), 0, 100),
		int(payload.get("cubic_feet_total", 20000)),
		int(payload.get("cubic_feet_completed", 0)),
		int(payload.get("construction_rate_cp_per_day", 0)),
		int(payload.get("petard_damage", 0)),
		_null_or_string(payload.get("countermine_target_id")),
		int(payload.get("started_calendar_day", 0)),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SiegeRepository.create_mine failed: siege=%s side=%s" % [
			payload.get("siege_id", ""), payload.get("side", "")])
		return ""
	return id


static func get_mine(mine_id: String) -> Dictionary:
	if mine_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM siege_mines WHERE id = ?", [mine_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_active_mines(siege_id: String, side: String = "") -> Array:
	if siege_id.is_empty():
		return []
	if side.is_empty():
		if not CampaignRepository.db.query_with_bindings("""
			SELECT * FROM siege_mines
			WHERE siege_id = ? AND is_completed = 0 AND is_destroyed_by_accident = 0
			ORDER BY side, started_calendar_day
		""", [siege_id]):
			return []
	else:
		if not CampaignRepository.db.query_with_bindings("""
			SELECT * FROM siege_mines
			WHERE siege_id = ? AND side = ?
			      AND is_completed = 0 AND is_destroyed_by_accident = 0
			ORDER BY started_calendar_day
		""", [siege_id, side]):
			return []
	return CampaignRepository.db.query_result.duplicate()


static func update_mine(mine_id: String, fields: Dictionary) -> bool:
	if mine_id.is_empty() or fields.is_empty():
		return false
	var set_clauses: Array = []
	var values: Array = []
	for key in fields.keys():
		var k: String = String(key)
		if not _MINE_UPDATE_FIELDS.has(k):
			push_error("SiegeRepository.update_mine: rejected non-whitelisted '%s'" % k)
			continue
		set_clauses.append("%s = ?" % k)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(mine_id)
	var sql := "UPDATE siege_mines SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

static func _null_or_string(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s


static func _null_or_int(v: Variant) -> Variant:
	if v == null:
		return null
	return int(v)
