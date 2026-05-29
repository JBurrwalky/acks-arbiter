class_name LevyTribalWarriorsHandler
extends RefCounted

## levy_tribal_warriors handler — Phase 11D.5 per gdd-tribal-warriors.md §5.1.
## Activates dormant tribal warriors (counted in
## `domains.available_tribal_warriors`) into a fielded `troop_units` row.
##
## Validation per `TribalWarriorRegistry.can_levy`:
##   * Clanhold-style domain only.
##   * Caller must be the domain's ruler.
##   * `count` ≤ current `available_tribal_warriors`.
##
## Effects:
##   1. Decrements `domains.available_tribal_warriors` by count.
##   2. Inserts a `troop_units` row with `source_type='tribal_warrior'`,
##      `assignment_kind='available'`, per the v1 stub template from
##      TribalWarriorRegistry.default_template_for_domain.
##   3. Writes a `tribal_warriors_levied` departure log entry.
##   4. Emits `EventBus.tribal_warriors_levied`.
##
## v1 single-unit-per-levy: a polish pass adds the §5.1 'gang' / 'warband' /
## 'custom' templates that split the levy across multiple troop_units rows
## per the L&E lair_composition (champion / sub-chieftain / chieftain tiers).

const UNIT_SIZE_CAP := 120  # mirrors conscript_troops; chunk large levies into 120-warrior units


static func on_complete(state: Dictionary, _runner) -> Dictionary:
	var character_id: String = String(state.get("character_id", ""))
	var params: Dictionary = _parse_params(state)
	# Resolve target domain: explicit param takes precedence; else caller's primary owned domain.
	var domain_id: String = String(params.get("domain_id", ""))
	if domain_id.is_empty():
		domain_id = _resolve_domain_for_ruler(character_id)
	if domain_id.is_empty():
		return {"summary": "levy_tribal_warriors: no domain resolved"}

	var eligibility: Dictionary = TribalWarriorRegistry.can_levy(character_id, domain_id)
	if not bool(eligibility.get("ok", false)):
		return {
			"summary": "levy_tribal_warriors: blocked — %s" % str(eligibility.get("reason", "")),
			"blocked_reason": String(eligibility.get("reason", "")),
		}
	var pool: Dictionary = TribalWarriorRegistry.pool_for_domain(domain_id)
	var available: int = int(pool.get("available", 0))
	var requested: int = int(params.get("count", available))
	var count: int = mini(maxi(0, requested), available)
	if count <= 0:
		return {
			"summary": "levy_tribal_warriors: pool empty (available=%d)" % available,
			"blocked_reason": "pool_empty",
		}

	var domain: Dictionary = _get_domain(domain_id)
	var character: Dictionary = CampaignRepository.get_character(character_id)
	var calendar_day: int = _calendar_day()
	var campaign_id: String = String(domain.get("campaign_id", ""))

	# 1. Decrement available_tribal_warriors.
	CampaignRepository.db.query_with_bindings("""
		UPDATE domains
		SET available_tribal_warriors = available_tribal_warriors - ?,
		    updated_at = datetime('now')
		WHERE id = ?
	""", [count, domain_id])

	# 2. Spawn the troop_units rows per the RAW Tribal Warrior Troop Type
	# table (per-race composition) per `ax_domains_of_chaos.xml:417-444`.
	# Each race produces a specific breakdown — e.g., orcs spawn 5 rows
	# (light_infantry, heavy_infantry, bowmen, crossbowmen, beast_riders);
	# kobolds spawn 1 row (light_infantry); skysos spawn 5 rows including
	# horse_archers + composite_bowmen.
	var race: String = TribalWarriorRegistry.inferred_tribal_race_for_domain(domain_id)
	var composition: Array = TribalWarriorRegistry.composition_for_race(race, count)
	# RAW base-morale modifier per `ax_domains_of_chaos.xml:451-453`: clanhold
	# domain morale at Steadfast/Stalwart gives +1 one-time; Demoralized or
	# worse gives -1 one-time.
	var domain_morale: int = int(domain.get("morale", 0))
	var morale_modifier: int = TribalWarriorRegistry.base_morale_modifier_for_domain_morale(domain_morale)
	var ids: Array = _spawn_levied_units_from_composition(
		character, domain_id, campaign_id, race, composition,
		morale_modifier, calendar_day)

	# 3. Departure log.
	var troop_type_summary: Array = []
	for row: Dictionary in composition:
		troop_type_summary.append("%d %s" % [row.get("count", 0), row.get("troop_type", "?")])
	DepartureLogRecorder.record(
		campaign_id, domain_id, calendar_day,
		"tribal_warriors_levied",
		"Levied %d %s warrior%s (%d unit%s): %s" % [
			count, race,
			"" if count == 1 else "s",
			ids.size(), "" if ids.size() == 1 else "s",
			", ".join(troop_type_summary),
		],
		{
			"count": count,
			"unit_ids": ids,
			"race": race,
			"composition": composition,
			"morale_modifier": morale_modifier,
			"levied_by_character_id": character_id,
		})

	# 4. EventBus.
	if EventBus.has_signal("tribal_warriors_levied"):
		EventBus.emit_signal("tribal_warriors_levied",
			domain_id, character_id, ids, count)

	return {
		"summary": "%d tribal warriors levied (%d unit%s)" % [count, ids.size(),
			"" if ids.size() == 1 else "s"],
		"unit_ids": ids,
		"count": count,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Phase 11D.5 per-race import — spawn one troop_units row per
## composition row. Each composition row may further be chunked at
## UNIT_SIZE_CAP if its count exceeds the cap (e.g., a 240-warrior orc
## levy splits its 88 light_infantry into 1 unit + 30 heavy_infantry,
## 40 bowmen, 40 crossbowmen, 12 beast_riders — but if any single
## troop_type exceeds 120 warriors, that one is chunked).
static func _spawn_levied_units_from_composition(
	character: Dictionary, domain_id: String, campaign_id: String,
	race: String, composition: Array, morale_modifier: int, calendar_day: int
) -> Array:
	var ids: Array = []
	var owner_id: String = String(character.get("id", ""))
	for row_v in composition:
		var row: Dictionary = row_v
		var troop_type: String = str(row.get("troop_type", "light_infantry"))
		var count: int = int(row.get("count", 0))
		if count <= 0:
			continue
		var wage_per: int = int(row.get("wage_cp", 0))
		var supply_per: int = int(row.get("supply_cp", 0))
		var br_per: float = float(row.get("br_per_warrior", 0.0))
		var remaining: int = count
		while remaining > 0:
			var unit_count: int = mini(remaining, UNIT_SIZE_CAP)
			var monthly_wage: int = wage_per * unit_count
			var monthly_supply: int = supply_per * unit_count
			var unit_id: String = TroopUnitRepository.create_unit({
				"campaign_id": campaign_id,
				"owner_character_id": owner_id,
				"assigned_domain_id": domain_id,
				"source_type": "tribal_warrior",
				"troop_type": troop_type,
				"race": race,
				"tier": "average",
				"starting_count": unit_count,
				"count": unit_count,
				"battle_rating": br_per * float(unit_count),
				"monthly_wage_cp": monthly_wage,
				"monthly_supply_cp": monthly_supply,
				"monthly_specialist_cp": 0,
				"monthly_cost_cp": monthly_wage + monthly_supply,
				"morale": morale_modifier,
				"is_veteran": false,
				"is_trained": true,
				"unit_xp": 0,
				"assignment_kind": "available",
				"hire_calendar_day": calendar_day,
				"equipment_kit": "tribal_custom",
			})
			if not unit_id.is_empty():
				ids.append(unit_id)
			remaining -= unit_count
	return ids


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? LIMIT 1",
		[character_id]
	):
		return ""
	if CampaignRepository.db.query_result.is_empty():
		return ""
	return String(CampaignRepository.db.query_result[0].get("id", ""))


static func _get_domain(domain_id: String) -> Dictionary:
	if not CampaignRepository.db.query_with_bindings(
		"SELECT * FROM domains WHERE id = ? LIMIT 1", [domain_id]
	):
		return {}
	if CampaignRepository.db.query_result.is_empty():
		return {}
	return CampaignRepository.db.query_result[0].duplicate()


static func _calendar_day() -> int:
	var date: Dictionary = Timekeeping.get_date()
	var year: int = int(date.get("year", 1))
	var month: int = int(date.get("month", 1))
	var day: int = int(date.get("day", 1))
	return ((year - 1) * 12 + (month - 1)) * Timekeeping.DAYS_PER_MONTH + day
