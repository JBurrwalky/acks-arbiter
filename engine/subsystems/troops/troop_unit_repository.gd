class_name TroopUnitRepository
extends RefCounted

## CRUD service for the `troop_units` table (migration 069). Phase 5 owner.
##
## Per `daw_armies_recruitment.xml` §army_sources six source types:
## mercenary / conscript / militia / follower / slave_soldier / vassal.
##
## monthly_cost_gp is denormalized = (wage + specialist + 4 × weekly_supply) × count
## per `daw_campaigns_troop_tables_summary.xml` §unit_characteristics_summary.
## Phase 5 callers compute it from the unit_template + count at hire and pass the
## result in directly; the repository does not derive it.
##
## starting_count is captured separately so the §morale_and_loyalty 25%-casualties
## Calamity threshold can be evaluated at any time as `count < (starting_count * 3 / 4)`.

const _UPDATE_FIELDS := [
	"assigned_domain_id", "assigned_stronghold_id",
	"source_type", "troop_type", "race", "tier",
	"starting_count", "count", "battle_rating",
	"monthly_wage_gp", "monthly_supply_gp", "monthly_specialist_gp",
	"monthly_cost_gp", "morale", "is_veteran", "is_trained",
	"unit_xp", "assignment_kind", "hire_calendar_day", "equipment_kit",
	"status", "departure_kind", "departure_calendar_day",
]


## Phase 9C polish 2026-05-09: per-race × per-tier save_vs_death overlay.
## Replaces the migration-090 tier-only fallback with a project-designed
## demihuman bonus structure. Demihumans are racially hardier vs Death.
## Anything not in this map falls back to the tier-only default.
##
## Numbers reference ACKS Core race save tables for L1 fighters/units:
##   human (1HD): 14 base; tier shifts ±2.
##   dwarven: 11 base (significant racial save vs Death bonus).
##   elven: 13 base (small bonus; primarily save-vs-spell oriented).
##   halfling: 11 base (RAW: very strong save vs Death).
##   mongrel / orc / goblinoid: 14 base (treated as human for save purposes).
const _RACE_TIER_SAVE_VS_DEATH := {
	"human":     {"untrained": 16, "average": 14, "veteran": 12},
	"dwarven":   {"untrained": 13, "average": 11, "veteran": 9},
	"elven":     {"untrained": 15, "average": 13, "veteran": 11},
	"halfling":  {"untrained": 13, "average": 11, "veteran": 9},
}


## Compute the save_vs_death target for a (race, tier) pair.
## Returns -1 if the pair isn't in the table; callers should fall back to 14.
static func compute_save_vs_death(race: String, tier: String) -> int:
	var r: String = race.to_lower()
	if not _RACE_TIER_SAVE_VS_DEATH.has(r):
		return -1
	var by_tier: Dictionary = _RACE_TIER_SAVE_VS_DEATH[r]
	var t: String = tier.to_lower()
	if not by_tier.has(t):
		return -1
	return int(by_tier[t])


static func create_unit(data: Dictionary) -> String:
	var id: String = String(data.get("id", ""))
	if id.is_empty():
		id = CampaignRepository.generate_id()
	# Phase 9C polish 2026-05-09: compute save_vs_death from race + tier when
	# the caller didn't supply one. Falls back to schema DEFAULT 14 if the
	# race+tier pair is unknown.
	var race: String = String(data.get("race", "human"))
	var tier: String = String(data.get("tier", "average"))
	var explicit_save: int = int(data.get("save_vs_death", 0))
	var save_vs_death: int = explicit_save if explicit_save > 0 else compute_save_vs_death(race, tier)
	if save_vs_death <= 0:
		save_vs_death = 14
	if not CampaignRepository.db.query_with_bindings("""
		INSERT INTO troop_units
			(id, campaign_id, owner_character_id, assigned_domain_id,
			 assigned_stronghold_id, source_type, troop_type, race, tier,
			 starting_count, count, battle_rating,
			 monthly_wage_gp, monthly_supply_gp, monthly_specialist_gp,
			 monthly_cost_gp, morale, is_veteran, is_trained,
			 unit_xp, assignment_kind, hire_calendar_day, equipment_kit,
			 status, departure_kind, departure_calendar_day, save_vs_death)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	""", [
		id,
		String(data.get("campaign_id", "")),
		String(data.get("owner_character_id", "")),
		_null_or_string(data.get("assigned_domain_id", null)),
		_null_or_string(data.get("assigned_stronghold_id", null)),
		String(data.get("source_type", "mercenary")),
		String(data.get("troop_type", "")),
		race,
		tier,
		int(data.get("starting_count", 0)),
		int(data.get("count", data.get("starting_count", 0))),
		float(data.get("battle_rating", 0.0)),
		int(data.get("monthly_wage_gp", 0)),
		int(data.get("monthly_supply_gp", 0)),
		int(data.get("monthly_specialist_gp", 0)),
		int(data.get("monthly_cost_gp", 0)),
		int(data.get("morale", 0)),
		1 if bool(data.get("is_veteran", false)) else 0,
		1 if bool(data.get("is_trained", true)) else 0,
		int(data.get("unit_xp", 0)),
		String(data.get("assignment_kind", "available")),
		int(data.get("hire_calendar_day", 0)),
		String(data.get("equipment_kit", "")),
		String(data.get("status", "active")),
		String(data.get("departure_kind", "")),
		int(data.get("departure_calendar_day", 0)),
		save_vs_death,
	]):
		push_error("TroopUnitRepository.create_unit failed: source=%s type=%s" % [
			data.get("source_type", "?"), data.get("troop_type", "?"),
		])
		return ""
	return id


static func get_unit(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if not CampaignRepository.db.query_with_bindings(
			"SELECT * FROM troop_units WHERE id = ?", [id]):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func update_unit(id: String, fields: Dictionary) -> bool:
	if id.is_empty():
		return false
	var set_clauses: Array[String] = []
	var values: Array = []
	for key in fields:
		if not _UPDATE_FIELDS.has(key):
			push_error("TroopUnitRepository.update_unit: rejected '%s'" % key)
			continue
		set_clauses.append("%s = ?" % key)
		values.append(fields[key])
	if set_clauses.is_empty():
		return false
	values.append(id)
	var sql := "UPDATE troop_units SET %s WHERE id = ?" % ", ".join(set_clauses)
	return CampaignRepository.db.query_with_bindings(sql, values)


static func list_active_for_domain(domain_id: String) -> Array:
	if domain_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM troop_units
		WHERE assigned_domain_id = ? AND status = 'active'
		ORDER BY source_type, troop_type, hire_calendar_day
	""", [domain_id])
	return CampaignRepository.db.query_result.duplicate()


static func list_active_for_owner(character_id: String) -> Array:
	if character_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM troop_units
		WHERE owner_character_id = ? AND status = 'active'
		ORDER BY source_type, troop_type, hire_calendar_day
	""", [character_id])
	return CampaignRepository.db.query_result.duplicate()


static func list_active_for_campaign(campaign_id: String) -> Array:
	if campaign_id.is_empty():
		return []
	CampaignRepository.db.query_with_bindings("""
		SELECT * FROM troop_units
		WHERE campaign_id = ? AND status = 'active'
		ORDER BY assigned_domain_id, source_type, troop_type
	""", [campaign_id])
	return CampaignRepository.db.query_result.duplicate()


static func depart_unit(id: String, kind: String, calendar_day: int) -> bool:
	return update_unit(id, {
		"status": "departed",
		"departure_kind": kind,
		"departure_calendar_day": calendar_day,
	})


static func _null_or_string(v: Variant) -> Variant:
	if v == null:
		return null
	var s: String = String(v)
	if s.is_empty():
		return null
	return s
