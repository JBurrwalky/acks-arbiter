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
	var peasant_families: int = int(pool.get("peasant_families", 0))

	# RAW ax_domains_of_chaos.xml:398-399 — 1 warrior per family levies free;
	# "any additional levies are treated as militia". Per Jedidiah (2026-08-03)
	# the excess is capped at the militia allowance (2 per 10 families,
	# daw_armies_recruitment.xml:428) and carries the militia penalties: one
	# family's revenue per warrior, plus -1/-2 domain morale. The warriors
	# themselves stay tribal warriors — trained and equipped per tribal custom.
	#
	# The cap is a STANDING one, so excess already under arms is subtracted
	# (mirroring LevyMilitiaHandler's treatment of existing militia).
	var excess_cap: int = LevyPenaltyCalculator.levy_cap_for_families(peasant_families)
	var excess_active: int = _current_excess_levy_count(domain_id)
	var excess_room: int = maxi(0, excess_cap - excess_active)

	var requested: int = int(params.get("count", available))
	requested = maxi(0, requested)
	var free_count: int = mini(requested, available)
	var excess_count: int = mini(requested - free_count, excess_room)
	var count: int = free_count + excess_count
	if count <= 0:
		var reason: String = "excess_levy_cap_reached" if available <= 0 and excess_cap > 0 \
			else "pool_empty"
		return {
			"summary": "levy_tribal_warriors: nothing available (free=%d, excess room=%d of cap %d)" % [
				available, excess_room, excess_cap],
			"blocked_reason": reason,
		}

	var domain: Dictionary = _get_domain(domain_id)
	var character: Dictionary = CampaignRepository.get_character(character_id)
	var calendar_day: int = _calendar_day()
	var campaign_id: String = String(domain.get("campaign_id", ""))

	# 1. Decrement available_tribal_warriors — by the FREE portion only. Excess
	# warriors are peasants pulled off the land, not draws on the 1-per-family
	# warrior allotment, so they must not touch the pool (doing so would drive
	# it negative and break the §3 invariant).
	if free_count > 0:
		CampaignRepository.db.query_with_bindings("""
			UPDATE domains
			SET available_tribal_warriors = available_tribal_warriors - ?,
			    updated_at = datetime('now')
			WHERE id = ?
		""", [free_count, domain_id])

	# 2. Spawn the troop_units rows per the RAW Tribal Warrior Troop Type
	# table (per-race composition) per `ax_domains_of_chaos.xml:417-444`.
	# Each race produces a specific breakdown — e.g., orcs spawn 5 rows
	# (light_infantry, heavy_infantry, bowmen, crossbowmen, beast_riders);
	# kobolds spawn 1 row (light_infantry); skysos spawn 5 rows including
	# horse_archers + composite_bowmen.
	var race: String = TribalWarriorRegistry.inferred_tribal_race_for_domain(domain_id)
	# Free and excess warriors are composed SEPARATELY so every spawned row is
	# wholly one or the other — the is_excess_levy flag is per-row, and a row
	# holding a mix of free and penalised warriors could not be scored.
	var composition: Array = TribalWarriorRegistry.composition_for_race(race, free_count)
	var excess_composition: Array = TribalWarriorRegistry.composition_for_race(race, excess_count)
	# RAW base-morale modifier per `ax_domains_of_chaos.xml:451-453`: clanhold
	# domain morale at Steadfast/Stalwart gives +1 one-time; Demoralized or
	# worse gives -1 one-time.
	var domain_morale: int = int(domain.get("morale", 0))
	var morale_modifier: int = TribalWarriorRegistry.base_morale_modifier_for_domain_morale(domain_morale)
	var ids: Array = _spawn_levied_units_from_composition(
		character, domain_id, campaign_id, race, composition,
		morale_modifier, calendar_day, false)
	var excess_ids: Array = _spawn_levied_units_from_composition(
		character, domain_id, campaign_id, race, excess_composition,
		morale_modifier, calendar_day, true)
	ids.append_array(excess_ids)

	# 3. Departure log.
	var troop_type_summary: Array = []
	for row: Dictionary in composition:
		troop_type_summary.append("%d %s" % [row.get("count", 0), row.get("troop_type", "?")])
	for row: Dictionary in excess_composition:
		troop_type_summary.append("%d %s (excess)" % [
			row.get("count", 0), row.get("troop_type", "?")])
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
			"excess_composition": excess_composition,
			"free_count": free_count,
			"excess_count": excess_count,
			"morale_modifier": morale_modifier,
			"levied_by_character_id": character_id,
		})

	# 4. EventBus.
	if EventBus.has_signal("tribal_warriors_levied"):
		EventBus.emit_signal("tribal_warriors_levied",
			domain_id, character_id, ids, count)

	var summary: String = "%d tribal warriors levied (%d unit%s)" % [count, ids.size(),
		"" if ids.size() == 1 else "s"]
	if excess_count > 0:
		summary += "; %d beyond the free allotment — the domain loses %d famil%s of revenue and takes a morale penalty until they stand down" % [
			excess_count, excess_count, "y" if excess_count == 1 else "ies"]
	return {
		"summary": summary,
		"unit_ids": ids,
		"count": count,
		"free_count": free_count,
		"excess_count": excess_count,
		"excess_cap": excess_cap,
	}


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Phase 11D.5 per-race import — spawn one troop_units row per composition
## row. A row whose count exceeds its RAW unit size is chunked into several
## rows (e.g. a 240-warrior orc levy splits its 88 light_infantry into 1 unit
## plus 30 heavy_infantry, 40 bowmen, 40 crossbowmen and 12 beast_riders; only
## a troop_type over its own unit size gets split).
##
## [2026-08-01] The chunk size is now per-row, not the flat UNIT_SIZE_CAP —
## RAW L273 sizes cavalry and large-creature units at 60, so beast riders and
## every ogre troop type form 60-strong units, not 120.
static func _spawn_levied_units_from_composition(
	character: Dictionary, domain_id: String, campaign_id: String,
	race: String, composition: Array, morale_modifier: int, calendar_day: int,
	is_excess_levy: bool = false
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
		# RAW ax_domains_of_chaos.xml §tribal_warrior_morale: "Tribal warriors
		# use the base morale of their troop type", and levies from a
		# Steadfast/Stalwart domain gain a ONE-TIME +1 while Apathetic/
		# Demoralized suffer -1. Both belong in the stored value; this line
		# previously stored the domain modifier ALONE, dropping the troop
		# type's own morale — so an ogre levy (+2) and a kobold levy (-2)
		# both came out at the same number.
		var unit_morale: int = int(row.get("base_morale", 0)) + morale_modifier
		# RAW `daw_campaigns_troop_tables_summary.xml:273` sizes a unit at 120
		# for infantry but 60 for cavalry OR LARGE CREATURES, so goblin wolf
		# riders, orc boar riders and ALL ogre troops form 60-strong units.
		# `composition_for_race` carries the right size per row; fall back to
		# the flat cap only if a row somehow lacks it.
		var unit_size: int = int(row.get("unit_size", UNIT_SIZE_CAP))
		if unit_size <= 0:
			unit_size = UNIT_SIZE_CAP
		var remaining: int = count
		while remaining > 0:
			var unit_count: int = mini(remaining, unit_size)
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
				"morale": unit_morale,
				"is_veteran": false,
				"is_trained": true,
				"unit_xp": 0,
				"assignment_kind": "available",
				"hire_calendar_day": calendar_day,
				"equipment_kit": "tribal_custom",
				# Migration 213: excess rows carry the standing militia
				# penalties via LevyPenaltyCalculator. Same stats either way —
				# only the domain-level cost differs.
				"is_excess_levy": is_excess_levy,
			})
			if not unit_id.is_empty():
				ids.append(unit_id)
			remaining -= unit_count
	return ids


## Warriors already under arms beyond the free allotment. The excess cap is a
## STANDING one (mirroring `LevyMilitiaHandler._current_active_militia`), so
## repeat levies cannot stack past it — and a stand-down or battle death frees
## the slot back up, because the row stops being `status='active'`.
static func _current_excess_levy_count(domain_id: String) -> int:
	if domain_id.is_empty():
		return 0
	if not CampaignRepository.db.query_with_bindings("""
		SELECT COALESCE(SUM(count), 0) AS total
		FROM troop_units
		WHERE assigned_domain_id = ?
		  AND source_type = 'tribal_warrior'
		  AND status = 'active'
		  AND is_excess_levy = 1
	""", [domain_id]):
		return 0
	if CampaignRepository.db.query_result.is_empty():
		return 0
	return int(CampaignRepository.db.query_result[0].get("total", 0))


static func _parse_params(state: Dictionary) -> Dictionary:
	var raw: String = String(state.get("params_json", "{}"))
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


static func _resolve_domain_for_ruler(character_id: String) -> String:
	if character_id.is_empty():
		return ""
	if not CampaignRepository.db.query_with_bindings(
		"SELECT id FROM domains WHERE owner_character_id = ? ORDER BY created_at, id LIMIT 1",
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
	return Timekeeping.get_calendar_day()
