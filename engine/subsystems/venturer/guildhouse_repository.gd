class_name GuildhouseRepository
extends RefCounted

## CRUD for the `guildhouses` table (Migration 144; Venturer→Guildhouse refactor).
##
## A guildhouse is the Venturer's mercantile base — its OWN structure, NOT a
## `strongholds` row (RAW `ax_venturer_class.xml`: the guildhouse "follows the
## rules for hideouts"). Created by FoundGuildhouseFlow. Apprentices are NOT
## stored here — they are `followers` rows (source_kind='venturer_apprentice').
##
## Static-function library; no autoload. All callers go through
## CampaignRepository.db. Money values are cp. The whitelist-enforced UPDATE +
## `_nullable_*` boundary coercion mirror HideoutRepository / SyndicateRepository.


const _GUILDHOUSE_UPDATE_FIELDS := [
	"market_class",
	"cp_value",
	"status",
	"location_map_id",
	"location_hex_q",
	"location_hex_r",
	"monopoly_seized",
	"monopoly_seized_day",
]


static func create_guildhouse(data: Dictionary) -> String:
	var id: String = str(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	var sql := """
		INSERT INTO guildhouses
			(id, campaign_id, owner_character_id, host_settlement_entrance_id,
			 market_class, cp_value, location_map_id, location_hex_q,
			 location_hex_r, monopoly_seized, monopoly_seized_day, status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	"""
	var bindings: Array = [
		id,
		str(data.get("campaign_id", "")),
		str(data.get("owner_character_id", "")),
		str(data.get("host_settlement_entrance_id", "")),
		int(data.get("market_class", 6)),
		int(data.get("cp_value", 0)),
		_nullable_str(data.get("location_map_id", null)),
		_nullable_int(data.get("location_hex_q", null)),
		_nullable_int(data.get("location_hex_r", null)),
		1 if bool(data.get("monopoly_seized", false)) else 0,
		_nullable_int(data.get("monopoly_seized_day", null)),
		str(data.get("status", "active")),
	]
	if not CampaignRepository.db.query_with_bindings(sql, bindings):
		push_error("GuildhouseRepository.create_guildhouse failed: %s" % data)
		return ""
	return id


static func get_guildhouse(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM guildhouses WHERE id = ?", [id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func get_guildhouse_for_owner(owner_character_id: String) -> Dictionary:
	if owner_character_id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM guildhouses WHERE owner_character_id = ? LIMIT 1", [owner_character_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func list_guildhouses_for_owner(owner_character_id: String) -> Array:
	if owner_character_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM guildhouses
		WHERE owner_character_id = ?
		ORDER BY created_at ASC
	""", [owner_character_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func list_guildhouses_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM guildhouses
		WHERE campaign_id = ?
		ORDER BY created_at ASC
	""", [campaign_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


## All guildhouses in a settlement — used to enforce "one venturer per
## settlement" when seizing monopoly power (RAW L12).
static func list_guildhouses_for_settlement(settlement_entrance_id: String) -> Array:
	if settlement_entrance_id.is_empty():
		return []
	if not CampaignRepository.db.query_with_bindings("""
		SELECT * FROM guildhouses
		WHERE host_settlement_entrance_id = ?
		ORDER BY created_at ASC
	""", [settlement_entrance_id]):
		return []
	return CampaignRepository.db.query_result.duplicate()


static func update_guildhouse(id: String, fields: Dictionary) -> bool:
	return _update_with_whitelist("guildhouses", id, fields, _GUILDHOUSE_UPDATE_FIELDS)


# ---------------------------------------------------------------------------
# Internal helpers (mirror HideoutRepository / SyndicateRepository)
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
			push_warning("GuildhouseRepository.update: ignored non-whitelisted column '%s' on %s" % [key, table])
			continue
		set_clauses.append("%s = ?" % key)
		bindings.append(fields[key])
	if set_clauses.is_empty():
		return false
	set_clauses.append("updated_at = datetime('now')")
	bindings.append(id)
	var sql := "UPDATE %s SET %s WHERE id = ?" % [table, ", ".join(set_clauses)]
	return CampaignRepository.db.query_with_bindings(sql, bindings)


## Coerce empty / null to SQL NULL on nullable columns (the String(null) Godot-4
## gotcha; mirrors HideoutRepository._nullable_str).
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
