class_name SyndicateRepository
extends RefCounted

## CRUD for the five Phase 10B.3 syndicate tables: syndicates,
## syndicate_members, hijink_assignments, caught_perpetrators, lay_low_state.
##
## Per docs/phase-10-plan.md §"Phase 10B.3 — Syndicate block". Static-function
## library; no autoload. All callers go through CampaignRepository.db. All
## money values are cp.
##
## Whitelist-enforced UPDATE pattern follows VassalObligationsRepository — the
## per-table _*_UPDATE_FIELDS arrays constrain which columns can be modified
## via update(*, fields).


# ---------------------------------------------------------------------------
# Whitelisted update fields
# ---------------------------------------------------------------------------

const _SYNDICATE_UPDATE_FIELDS := [
	"hideout_stronghold_id",
	"base_settlement_entrance_id",
	"syndicate_size_max",
	"current_size",
	"status",
	"hideout_id",  # Migration 143: source-of-truth FK to the hideouts table.
]

const _MEMBER_UPDATE_FIELDS := [
	"level",
	"follower_kind",
	"status",
	"hijink_eligible",
]

const _HIJINK_UPDATE_FIELDS := [
	"planning_state",
	"planning_days_required",
	"planning_days_completed",
	"status",
	"started_day",
	"completed_day",
	"target_id",
	"throw_result",
	"cp_yield",
	"caught",
]

const _CAUGHT_UPDATE_FIELDS := [
	"time_languishing_days",
	"attorney_rank",
	"bribe_amount_cp",
	"interpleader_id",
	"verdict",
	"fine_cp",
	"punishment_kind",
	"punishment_resolved",
	"prior_crimes_modifier",
	"resolved_day",
]


# ===========================================================================
# Syndicates
# ===========================================================================

static func create_syndicate(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO syndicates
			(id, campaign_id, boss_character_id, hideout_stronghold_id,
			 base_settlement_entrance_id, syndicate_size_max, current_size, status,
			 hideout_id)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("boss_character_id", "")),
		_nullable_str(data.get("hideout_stronghold_id", null)),
		_nullable_str(data.get("base_settlement_entrance_id", null)),
		int(data.get("syndicate_size_max", 0)),
		int(data.get("current_size", 0)),
		str(data.get("status", "active")),
		# Migration 143 (Thief→Syndicate): source-of-truth FK to the hideout.
		# Existing callers omit it → binds NULL (the hideout-stronghold_id stays
		# the vestigial column).
		_nullable_str(data.get("hideout_id", null)),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SyndicateRepository.create_syndicate failed: %s" % data)
		return ""
	return id


static func get_syndicate(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM syndicates WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_syndicates_for_boss(boss_character_id: String) -> Array:
	if boss_character_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM syndicates
		WHERE boss_character_id = ?
		ORDER BY created_at ASC
	""", [boss_character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_syndicates_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM syndicates
		WHERE campaign_id = ?
		ORDER BY created_at ASC
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update_syndicate(id: String, fields: Dictionary) -> bool:
	return _update_with_whitelist("syndicates", id, fields, _SYNDICATE_UPDATE_FIELDS)


# ===========================================================================
# Syndicate members
# ===========================================================================

static func create_member(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO syndicate_members
			(id, syndicate_id, character_id_if_named, level, follower_kind,
			 status, hijink_eligible)
		VALUES (?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("syndicate_id", "")),
		_nullable_str(data.get("character_id_if_named", null)),
		int(data.get("level", 1)),
		str(data.get("follower_kind", "thief")),
		str(data.get("status", "active")),
		1 if bool(data.get("hijink_eligible", true)) else 0,
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SyndicateRepository.create_member failed: %s" % data)
		return ""
	return id


static func get_member(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM syndicate_members WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_members(syndicate_id: String, only_active: bool = false) -> Array:
	if syndicate_id.is_empty():
		return []
	var sql := "SELECT * FROM syndicate_members WHERE syndicate_id = ?"
	if only_active:
		sql += " AND status = 'active'"
	sql += " ORDER BY level DESC, created_at ASC"
	if not CampaignRepository.db.query_with_bindings(sql, [syndicate_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func count_members_by_status(syndicate_id: String) -> Dictionary:
	if syndicate_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings("""
		SELECT status, COUNT(*) AS n FROM syndicate_members
		WHERE syndicate_id = ?
		GROUP BY status
	""", [syndicate_id]):
		return {}
	var out: Dictionary = {}
	for row: Dictionary in CampaignRepository.db.query_result:
		out[str(row.get("status", ""))] = int(row.get("n", 0))
	return out


static func update_member(id: String, fields: Dictionary) -> bool:
	return _update_with_whitelist("syndicate_members", id, fields, _MEMBER_UPDATE_FIELDS)


# ===========================================================================
# Hijink assignments
# ===========================================================================

static func create_hijink(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO hijink_assignments
			(id, syndicate_id, syndicate_member_id, boss_character_id, hideout_id,
			 hijink_kind, planning_state, planning_days_required,
			 planning_days_completed, status, started_day, completed_day,
			 target_id, throw_result, cp_yield, caught)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("syndicate_id", "")),
		_nullable_str(data.get("syndicate_member_id", null)),
		str(data.get("boss_character_id", "")),
		_nullable_str(data.get("hideout_id", null)),
		str(data.get("hijink_kind", "")),
		str(data.get("planning_state", "unplanned")),
		int(data.get("planning_days_required", 0)),
		int(data.get("planning_days_completed", 0)),
		str(data.get("status", "queued")),
		int(data.get("started_day", 0)),
		data.get("completed_day", null),
		str(data.get("target_id", "")),
		data.get("throw_result", null),
		int(data.get("cp_yield", 0)),
		1 if bool(data.get("caught", false)) else 0,
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SyndicateRepository.create_hijink failed: %s" % data)
		return ""
	return id


static func get_hijink(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM hijink_assignments WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_hijinks_for_syndicate(syndicate_id: String, status_filter: String = "") -> Array:
	if syndicate_id.is_empty():
		return []
	var sql := "SELECT * FROM hijink_assignments WHERE syndicate_id = ?"
	var bindings: Array = [syndicate_id]
	if not status_filter.is_empty():
		sql += " AND status = ?"
		bindings.append(status_filter)
	sql += " ORDER BY started_day DESC, created_at DESC"
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_planning_hijinks() -> Array:
	if not CampaignRepository.db.query("""
		SELECT * FROM hijink_assignments
		WHERE planning_state = 'planning' AND status = 'planning'
	"""):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update_hijink(id: String, fields: Dictionary) -> bool:
	return _update_with_whitelist("hijink_assignments", id, fields, _HIJINK_UPDATE_FIELDS)


# ===========================================================================
# Caught perpetrators
# ===========================================================================

static func create_caught(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO caught_perpetrators
			(id, character_id, hijink_assignment_id, crime_type,
			 time_languishing_days, attorney_rank, bribe_amount_cp,
			 interpleader_id, verdict, fine_cp, punishment_kind,
			 punishment_resolved, prior_crimes_modifier, arrested_day,
			 resolved_day)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("character_id", "")),
		_nullable_str(data.get("hijink_assignment_id", null)),
		str(data.get("crime_type", "")),
		int(data.get("time_languishing_days", 0)),
		int(data.get("attorney_rank", 0)),
		int(data.get("bribe_amount_cp", 0)),
		_nullable_str(data.get("interpleader_id", null)),
		data.get("verdict", null),
		int(data.get("fine_cp", 0)),
		data.get("punishment_kind", null),
		1 if bool(data.get("punishment_resolved", false)) else 0,
		int(data.get("prior_crimes_modifier", 0)),
		int(data.get("arrested_day", 0)),
		data.get("resolved_day", null),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("SyndicateRepository.create_caught failed: %s" % data)
		return ""
	return id


static func get_caught(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM caught_perpetrators WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_caught_for_character(character_id: String, unresolved_only: bool = false) -> Array:
	if character_id.is_empty():
		return []
	var sql := "SELECT * FROM caught_perpetrators WHERE character_id = ?"
	if unresolved_only:
		sql += " AND punishment_resolved = 0"
	sql += " ORDER BY arrested_day DESC, created_at DESC"
	if not CampaignRepository.db.query_with_bindings(sql, [character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_caught_awaiting_trial() -> Array:
	if not CampaignRepository.db.query("""
		SELECT * FROM caught_perpetrators
		WHERE verdict IS NULL AND punishment_resolved = 0
		ORDER BY arrested_day ASC
	"""):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update_caught(id: String, fields: Dictionary) -> bool:
	return _update_with_whitelist("caught_perpetrators", id, fields, _CAUGHT_UPDATE_FIELDS)


# ===========================================================================
# Lay-low state
# ===========================================================================

## Inserts or replaces the lay-low row for a character. RAW §lay_low L1196 —
## the timer is per-base, but each character may only be laying low at one
## base at a time (you start over if you switch bases mid-window). PK is
## character_id so REPLACE is the correct semantics.
static func upsert_lay_low(character_id: String, base_id: String, started_day: int, ends_day: int) -> bool:
	if character_id.is_empty() or base_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings("""
		INSERT OR REPLACE INTO lay_low_state
			(character_id, base_id, started_day, ends_day)
		VALUES (?, ?, ?, ?)
	""", [character_id, base_id, started_day, ends_day]):
		push_error("SyndicateRepository.upsert_lay_low failed for %s" % character_id)
		return false
	return true


static func get_lay_low(character_id: String) -> Dictionary:
	if character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM lay_low_state WHERE character_id = ?", [character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


## Returns true if the character is currently laying low at the named base.
## A character may operate in OTHER bases while laying low at this one
## (RAW L1196). [param current_day] is the calendar day to compare against
## ends_day.
static func is_laying_low_at_base(character_id: String, base_id: String, current_day: int) -> bool:
	var row := get_lay_low(character_id)
	if row.is_empty():
		return false
	if str(row.get("base_id", "")) != base_id:
		return false
	return current_day < int(row.get("ends_day", 0))


static func clear_lay_low(character_id: String) -> bool:
	if character_id.is_empty():
		return false
	if not CampaignRepository.db.query_with_bindings(
		"DELETE FROM lay_low_state WHERE character_id = ?", [character_id]
	):
		return false
	return true


# ===========================================================================
# Internals
# ===========================================================================

static func _update_with_whitelist(
		table: String,
		id: String,
		fields: Dictionary,
		whitelist: Array,
) -> bool:
	if id.is_empty() or fields.is_empty():
		return false
	var set_clauses: Array[String] = []
	var bindings: Array = []
	for key: String in fields.keys():
		if not (key in whitelist):
			push_warning("SyndicateRepository.update: ignored non-whitelisted column '%s' on %s" % [key, table])
			continue
		set_clauses.append("%s = ?" % key)
		bindings.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	bindings.append(id)
	var sql := "UPDATE %s SET %s WHERE id = ?" % [table, ", ".join(set_clauses)]
	return CampaignRepository.db.query_with_bindings(sql, bindings)


## Returns null when [param v] is null or "" so SQLite stores SQL NULL on
## nullable FK columns rather than the empty string (which would fail FK
## enforcement). For non-nullable TEXT columns, callers should NOT route
## through this helper.
static func _nullable_str(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s
