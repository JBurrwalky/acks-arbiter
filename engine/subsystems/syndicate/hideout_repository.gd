class_name HideoutRepository
extends RefCounted

## CRUD for the `hideouts` table (Migration 143; Thief→Syndicate refactor).
##
## A hideout is the syndicate's secret base — its OWN structure, NOT a
## `strongholds` row (RAW `ax_thief_skill_update.xml`:50 "Hideouts are secret
## strongholds; do not secure domains"). Created by FoundSyndicateFlow.
##
## Static-function library; no autoload. All callers go through
## CampaignRepository.db. All money values are cp. The whitelist-enforced UPDATE
## pattern + `_nullable_str` boundary coercion mirror SyndicateRepository.


const _HIDEOUT_UPDATE_FIELDS := [
	"syndicate_id",
	"market_class",
	"cp_value",
	"status",
	"location_map_id",
	"location_hex_q",
	"location_hex_r",
]


static func create_hideout(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO hideouts
			(id, campaign_id, syndicate_id, owner_character_id,
			 host_settlement_entrance_id, market_class, cp_value,
			 location_map_id, location_hex_q, location_hex_r, status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("campaign_id", "")),
		_nullable_str(data.get("syndicate_id", null)),
		str(data.get("owner_character_id", "")),
		str(data.get("host_settlement_entrance_id", "")),
		int(data.get("market_class", 6)),
		int(data.get("cp_value", 0)),
		_nullable_str(data.get("location_map_id", null)),
		_nullable_int(data.get("location_hex_q", null)),
		_nullable_int(data.get("location_hex_r", null)),
		str(data.get("status", "active")),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("HideoutRepository.create_hideout failed: %s" % data)
		return ""
	return id


static func get_hideout(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM hideouts WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func get_hideout_for_syndicate(syndicate_id: String) -> Dictionary:
	if syndicate_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM hideouts WHERE syndicate_id = ? LIMIT 1", [syndicate_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_hideouts_for_owner(owner_character_id: String) -> Array:
	if owner_character_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM hideouts
		WHERE owner_character_id = ?
		ORDER BY created_at ASC
	""", [owner_character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update_hideout(id: String, fields: Dictionary) -> bool:
	return _update_with_whitelist("hideouts", id, fields, _HIDEOUT_UPDATE_FIELDS)


# ---------------------------------------------------------------------------
# Internal helpers (mirror SyndicateRepository)
# ---------------------------------------------------------------------------

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
			push_warning("HideoutRepository.update: ignored non-whitelisted column '%s' on %s" % [key, table])
			continue
		set_clauses.append("%s = ?" % key)
		bindings.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	bindings.append(id)
	var sql := "UPDATE %s SET %s WHERE id = ?" % [table, ", ".join(set_clauses)]
	return CampaignRepository.db.query_with_bindings(sql, bindings)


## Coerce empty / null to SQL NULL on nullable columns (the String(null)
## Godot-4 gotcha; mirrors SyndicateRepository._nullable_str).
static func _nullable_str(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s


## Nullable INTEGER coercion. Preserves a real 0 (only literal null → NULL).
static func _nullable_int(v: Variant) -> Variant:
	if v == null:
		return null
	return int(v)
